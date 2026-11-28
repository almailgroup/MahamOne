import Foundation

/// The port of the web's stock writes (src/db/inventory.ts): warehouses,
/// items, stock entries (opening stock, adjustments, transfers), landed
/// costs, the stock movements of documents and items issued, and their
/// costing at the weighted average. Each function does what the web's does
/// inside its Dexie transaction, in the same order (the same ids are handed
/// out), and refuses with the web's English words (`WriteFailure`).
///
/// `syncDocumentStock` and `recost` are what the document ports call when a
/// document is saved, voided or deleted.
public enum InventoryWrites {
  // MARK: The company

  /// The company record, or the web's "Company not found".
  static func theCompany(_ ctx: WriteContext) throws -> JSONValue {
    guard let company = ctx.get("companies", ctx.companyId) else { throw WriteFailure("Company not found") }
    return company
  }

  /// `currencyPrecision(company.currency)`.
  static func precision(_ company: JSONValue) -> Int {
    Money.precision(company.iwText("currency"))
  }

  // MARK: Warehouses

  /// `createWarehouse(companyId, overrides)`: a new id is taken even when
  /// `overrides` names one.
  public static func createWarehouse(_ ctx: WriteContext, _ overrides: [String: JSONValue] = [:]) -> JSONValue {
    let stamp = JSONValue.string(ctx.stamp)
    var fields: [String: JSONValue] = [
      "id": .string(ctx.newId()),
      "companyId": .string(ctx.companyId),
      "name": "",
      "nameAr": "",
      "address": "",
      "isDefault": false,
      "archived": false,
      "createdAt": stamp,
      "updatedAt": stamp,
    ]
    for (key, value) in overrides { fields[key] = value }
    return .object(fields)
  }

  /// `ensureDefaultWarehouse(companyId)`: the warehouse documents use when a
  /// line names none; "Main store" is made when the company has none.
  @discardableResult
  public static func ensureDefaultWarehouse(_ ctx: WriteContext) -> JSONValue {
    let all = IwRecords.company(ctx, "warehouses", ctx.companyId)
    let found =
      all.first { $0.iwTruthy("isDefault") && !$0.iwTruthy("archived") } ?? all.first { !$0.iwTruthy("archived") }
    if let found {
      if !found.iwTruthy("isDefault") {
        let updated = found.iwWith(["isDefault": true, "updatedAt": .string(ctx.stamp)])
        ctx.put("warehouses", updated)
        return updated
      }
      return found
    }
    var overrides: [String: JSONValue] = [
      "name": "Main store", "nameAr": "المستودع الرئيسي", "isDefault": true,
    ]
    // The very first one has the same id on every device.
    if all.isEmpty { overrides["id"] = .string("\(ctx.companyId)-main-store") }
    let warehouse = createWarehouse(ctx, overrides)
    ctx.put("warehouses", warehouse)
    return warehouse
  }

  /// `saveWarehouse(input)`.
  @discardableResult
  public static func saveWarehouse(_ ctx: WriteContext, _ input: JSONValue) throws -> JSONValue {
    let name = WebJS.trim(input.iwText("name"))
    if name.isEmpty { throw WriteFailure("Enter a name for the warehouse.") }
    let id = input.iwId
    let all = IwRecords.company(ctx, "warehouses", input.iwText("companyId"))
    let existing = all.first { $0.iwId == id }
    if all.contains(where: { $0.iwId != id && WebJS.trim($0.iwText("name")).lowercased() == name.lowercased() }) {
      throw WriteFailure("Another warehouse already has this name.")
    }
    if input.iwTruthy("archived") && input.iwTruthy("isDefault") {
      throw WriteFailure("Choose another default warehouse before archiving this one.")
    }
    let parentId = input.iwTruthy("parentId") ? input["parentId"] : nil
    if let parentId {
      let parent = all.first { $0["id"] == parentId }
      if parent == nil || parent?.iwTruthy("archived") == true || parent?.iwId == id {
        throw WriteFailure("Choose the main warehouse this one belongs to.")
      }
      if parent?.iwTruthy("parentId") == true {
        throw WriteFailure("A sub-warehouse can’t have sub-warehouses of its own.")
      }
      if all.contains(where: { $0["parentId"]?.string == id && !$0.iwTruthy("archived") }) {
        throw WriteFailure("This warehouse has sub-warehouses, so it can’t become a sub-warehouse.")
      }
      if input.iwTruthy("isDefault") { throw WriteFailure("A sub-warehouse can’t be the default warehouse.") }
    }
    if input.iwTruthy("archived") && all.contains(where: { $0["parentId"]?.string == id && !$0.iwTruthy("archived") }) {
      throw WriteFailure("Archive its sub-warehouses before archiving this warehouse.")
    }
    let stamp = JSONValue.string(ctx.stamp)
    let isDefault =
      parentId == nil && (input.iwTruthy("isDefault") || !all.contains { $0.iwId != id && $0.iwTruthy("isDefault") })
    var fields = WebJS.spread(input)
    fields["name"] = .string(name)
    fields["nameAr"] = .string(input["nameAr"]?.string.map(WebJS.trim) ?? "")
    fields["address"] = .string(WebJS.trim(input.iwText("address")))
    fields["isDefault"] = .bool(isDefault)
    fields["parentId"] = parentId ?? .null
    fields["keeper"] = cleanKeeper(input["keeper"])
    fields["updatedAt"] = stamp
    let warehouse = JSONValue.object(fields)
    if isDefault {
      for other in all where other.iwId != id && other.iwTruthy("isDefault") {
        ctx.put("warehouses", other.iwWith(["isDefault": false, "updatedAt": stamp]))
      }
    }
    ctx.put("warehouses", warehouse)
    ctx.logActivity(
      entity: "stock", entityId: id, action: existing != nil ? "updated" : "created",
      message: ActivityMessage(existing != nil ? "Warehouse {name} updated" : "Warehouse {name} created", vars: ["name": name]))
    return warehouse
  }

  /// `cleanKeeper(keeper)`: trimmed, or null when it names nobody.
  static func cleanKeeper(_ keeper: JSONValue?) -> JSONValue {
    guard let keeper, WebJS.truthy(keeper) else { return .null }
    let name = WebJS.trim(keeper.iwText("name"))
    let userId = keeper["userId"]?.string.map(WebJS.trim) ?? ""
    if name.isEmpty && userId.isEmpty { return .null }
    let employee = keeper["employeeId"]
    return .object([
      "employeeId": WebJS.truthy(employee) ? (employee ?? .null) : .null,
      "name": .string(name),
      "nameAr": .string(keeper["nameAr"]?.string.map(WebJS.trim) ?? ""),
      "jobTitle": .string(WebJS.trim(keeper.iwText("jobTitle"))),
      "jobTitleAr": .string(keeper["jobTitleAr"]?.string.map(WebJS.trim) ?? ""),
      "userId": userId.isEmpty ? .null : .string(userId),
    ])
  }

  // MARK: Movements

  /// `loadSetup(company)`: the stock items, the warehouses and the default
  /// one (made when missing), the clients that are tax exempt.
  static func loadSetup(_ ctx: WriteContext, _ company: JSONValue) -> IwSources.Setup {
    let companyId = company.iwId
    let products = IwRecords.company(ctx, "products", companyId)
    let warehouses = IwRecords.company(ctx, "warehouses", companyId)
    let clients = IwRecords.company(ctx, "clients", companyId)
    let fallback = warehouses.first { $0.iwTruthy("isDefault") && !$0.iwTruthy("archived") }
    let defaultWarehouse = fallback ?? ensureDefaultWarehouse(ctx)
    var ids = Set(warehouses.map(\.iwId))
    ids.insert(defaultWarehouse.iwId)
    return IwSources.Setup(
      companyCurrency: company.iwText("currency"), precision: precision(company),
      products: Set(products.filter(IwSources.isStockItem).map(\.iwId)), defaultWarehouseId: defaultWarehouse.iwId,
      warehouses: ids, exemptClients: Set(clients.filter { $0.iwTruthy("taxExempt") }.map(\.iwId)))
  }

  /// The movements of one source (`where('sourceId').equals(id)`), by id.
  static func movements(of sourceId: String, _ ctx: WriteContext) -> [JSONValue] {
    IwRecords.matching(ctx, "stockMovements", "sourceId", sourceId)
  }

  private static func sameKeys(_ a: [String], _ b: [String]) -> Bool {
    a.count == b.count && a.sorted(by: WebJS.less) == b.sorted(by: WebJS.less)
  }

  /// `replaceMovements(company, existing, planned)`: a source's movements
  /// replaced by the planned ones. Movements in a locked period stay; a
  /// change to them is refused. The items whose movements changed.
  static func replaceMovements(_ ctx: WriteContext, _ company: JSONValue, _ existing: [JSONValue], _ planned: [JSONValue])
    throws -> [String]
  {
    let settings = IwAccountingSettings(company)
    let locked = { (m: JSONValue) in settings.locks(m["date"]) }
    if !sameKeys(existing.filter(locked).map(IwSources.plannedKey), planned.filter(locked).map(IwSources.plannedKey)) {
      throw IwAccounts.lockedPeriod(settings.lockDate ?? "", company)
    }
    let before = existing.filter { !locked($0) }
    let after = planned.filter { !locked($0) }
    if sameKeys(before.map(IwSources.plannedKey), after.map(IwSources.plannedKey)) { return [] }
    let stamp = JSONValue.string(ctx.stamp)
    let ids = movementIds(company.iwId, after)
    for movement in before { ctx.delete("stockMovements", movement.iwId) }
    for (index, movement) in after.enumerated() {
      ctx.put(
        "stockMovements",
        movement.iwWith([
          "id": .string(ids[index]), "companyId": .string(company.iwId), "unitCost": 0, "value": 0,
          "createdAt": stamp, "updatedAt": stamp,
        ]))
    }
    return IwRecords.unique((before + after).map { $0.iwText("productId") })
  }

  /// `movementIds(companyId, planned)`: ids that follow from what the
  /// movements are, so two devices that plan the same source agree.
  static func movementIds(_ companyId: String, _ planned: [JSONValue]) -> [String] {
    var seen: [String: Int] = [:]
    return planned.map { movement in
      let key = "\(companyId)|\(WebJS.string(movement["sourceId"]))|\(IwSources.plannedKey(movement))"
      let n = seen[key] ?? 0
      seen[key] = n + 1
      return "sm-" + stableId("\(key)|\(n)")
    }
  }

  /// `recost(company, productIds)`: the items' movements valued again at
  /// the weighted average, in date order, outside locked periods.
  public static func recost(_ ctx: WriteContext, productIds: [String]) throws {
    guard let company = ctx.get("companies", ctx.companyId) else { return }
    recost(ctx, company, productIds)
  }

  static func recost(_ ctx: WriteContext, _ company: JSONValue, _ productIds: [String]) {
    let ids = IwRecords.unique(productIds)
    if ids.isEmpty { return }
    let p = precision(company)
    let lockDate = IwAccountingSettings(company).lockDate
    let stamp = JSONValue.string(ctx.stamp)
    let wanted = Set(ids)
    var grouped: [String: [JSONValue]] = [:]
    for movement in IwRecords.company(ctx, "stockMovements", company.iwId) {
      let product = movement.iwText("productId")
      if wanted.contains(product) { grouped[product, default: []].append(movement) }
    }
    var changed: [JSONValue] = []
    for id in ids {
      let product = ctx.get("products", id)
      changed += IwCosting.costMovements(
        grouped[id] ?? [], precision: p, lockDate: lockDate, fallbackUnitCost: product?["costPrice"])
    }
    for movement in changed { ctx.put("stockMovements", movement.iwWith("updatedAt", stamp)) }
  }

  /// `activeLandedCosts(documentId)`: the landed costs with charges on the
  /// document or allocated to its goods (void ones too).
  static func activeLandedCosts(_ ctx: WriteContext, _ documentId: String) -> [JSONValue] {
    let asCost = IwRecords.matching(ctx, "landedCosts", "billId", documentId)
    let asTarget = IwRecords.matching(ctx, "landedCosts", "targetBillId", documentId)
    var seen = Set<String>()
    var out: [JSONValue] = []
    for cost in asCost + asTarget where seen.insert(cost.iwId).inserted { out.append(cost) }
    return out
  }

  static func planLandedCost(_ ctx: WriteContext, _ cost: JSONValue, _ setup: IwSources.Setup) -> [JSONValue] {
    let costBill = ctx.get("documents", cost.iwText("billId"))
    let targetBill = ctx.get("documents", cost.iwText("targetBillId"))
    guard let links = IwSources.landedCostLinks(cost, costBill, targetBill, setup.products), let costBill,
      let targetBill
    else { return [] }
    let shares = IwSources.allocateLandedCost(cost, costBill, targetBill, links, setup).shares
    return IwSources.landedCostMovements(cost, costBill, shares, precision: setup.precision)
  }

  static func syncLandedCost(_ ctx: WriteContext, _ company: JSONValue, _ cost: JSONValue, _ setup: IwSources.Setup)
    throws -> [String]
  {
    try replaceMovements(ctx, company, movements(of: cost.iwId, ctx), planLandedCost(ctx, cost, setup))
  }

  /// `previousWarehouses(movements)`: where each line moved stock before.
  static func previousWarehouses(_ movements: [JSONValue]) -> [String: String] {
    var map: [String: String] = [:]
    for movement in movements {
      guard WebJS.truthy(movement["lineId"]) else { continue }
      map[WebJS.string(movement["lineId"])] = movement.iwText("warehouseId")
    }
    return map
  }

  /// `syncDocumentStock(companyId, documentId)`: the document's stock
  /// movements (and those of landed costs linked to it) made to match the
  /// document as saved, voided or deleted, then the items costed again.
  /// Documents without stock items cost nothing.
  public static func syncDocumentStock(_ ctx: WriteContext, documentId: String) throws {
    let doc = ctx.get("documents", documentId)
    let existing = movements(of: documentId, ctx)
    let linked = activeLandedCosts(ctx, documentId)
    let productIds = IwRecords.unique(
      (doc?.iwList("items") ?? []).compactMap { item in
        WebJS.truthy(item["productId"]) ? WebJS.string(item["productId"]) : nil
      })
    let products = productIds.map { ctx.get("products", $0) }
    let type = doc?["type"]?.string ?? ""
    let hasStock = doc != nil && IwSources.stockDocumentTypes.contains(type) && products.contains(where: IwSources.isStockItem)
    if !hasStock && existing.isEmpty && linked.isEmpty { return }
    guard let company = ctx.get("companies", ctx.companyId) else { return }
    if hasStock, let doc, IwSources.movesStock(doc) { IwAccounts.ensureStockAccounts(ctx, company) }
    let setup = loadSetup(ctx, company)
    let planned = doc.map { IwSources.documentMovements($0, setup, previous: previousWarehouses(existing)) } ?? []
    var touched = try replaceMovements(ctx, company, existing, planned)
    for cost in linked { touched += try syncLandedCost(ctx, company, cost, setup) }
    recost(ctx, company, touched)
  }

  /// `rebuildStock(companyId)`: every movement of the company planned and
  /// costed again (after restoring an old backup); locked periods stay.
  public static func rebuildStock(_ ctx: WriteContext) throws {
    guard let company = ctx.get("companies", ctx.companyId) else { return }
    let companyId = company.iwId
    let settings = IwAccountingSettings(company)
    let setup = loadSetup(ctx, company)
    let documents = IwRecords.company(ctx, "documents", companyId)
    let entries = IwRecords.company(ctx, "stockEntries", companyId)
    let costs = IwRecords.company(ctx, "landedCosts", companyId)
    let issues = IwRecords.company(ctx, "stockIssues", companyId)
    let all = IwRecords.company(ctx, "stockMovements", companyId)
    var bySource: [String: [JSONValue]] = [:]
    var sourceOrder: [String] = []
    for movement in all {
      let source = movement.iwText("sourceId")
      if bySource[source] == nil { sourceOrder.append(source) }
      bySource[source, default: []].append(movement)
    }
    var touched: [String] = []
    func sync(_ sourceId: String, _ planned: [JSONValue]) throws {
      do {
        touched += try replaceMovements(ctx, company, bySource[sourceId] ?? [], planned)
      } catch let failure as WriteFailure where failure.message.hasPrefix("The books are locked up to") {
        // Movements of a locked period keep the values they were posted with.
      }
      bySource[sourceId] = nil
    }
    for doc in documents where IwSources.stockDocumentTypes.contains(doc.iwText("type")) {
      let before = bySource[doc.iwId] ?? []
      try sync(doc.iwId, IwSources.documentMovements(doc, setup, previous: previousWarehouses(before)))
    }
    for entry in entries { try sync(entry.iwId, IwSources.entryMovements(entry, setup)) }
    for cost in costs { try sync(cost.iwId, planLandedCost(ctx, cost, setup)) }
    for issue in issues { try sync(issue.iwId, IwSources.issueMovements(issue, setup)) }
    // Movements whose source is gone.
    for source in sourceOrder {
      guard let left = bySource[source] else { continue }
      let open = left.filter { !settings.locks($0["date"]) }
      for movement in open { ctx.delete("stockMovements", movement.iwId) }
      touched += open.map { $0.iwText("productId") }
    }
    recost(ctx, company, touched + all.map { $0.iwText("productId") })
  }

  // MARK: Items

  /// `OpeningStockInput`: stock a new stock item starts with.
  public struct OpeningStock: Sendable, Equatable {
    public var warehouseId: String
    public var quantity: Double
    public var unitCost: Double
    public var date: String

    public init(warehouseId: String, quantity: Double, unitCost: Double, date: String) {
      self.warehouseId = warehouseId
      self.quantity = quantity
      self.unitCost = unitCost
      self.date = date
    }
  }

  /// `hasStockHistory(product)`: movements or stock entries.
  public static func hasStockHistory(_ ctx: WriteContext, _ product: JSONValue) -> Bool {
    let companyId = product.iwText("companyId")
    let id = product.iwId
    let moved = ctx.all("stockMovements") { $0["companyId"]?.string == companyId && $0["productId"]?.string == id }
    if !moved.isEmpty { return true }
    return IwRecords.company(ctx, "stockEntries", companyId).contains { entry in
      entry.iwList("lines").contains { $0["productId"]?.string == id }
    }
  }

  /// `skuKey(sku)`: SKUs compare without case or spaces at the ends.
  public static func skuKey(_ sku: JSONValue?) -> String {
    WebJS.trim(sku?.string ?? "").lowercased()
  }

  /// `takenSkus(companyId, exceptId)`.
  static func takenSkus(_ products: [JSONValue], except id: String?) -> Set<String> {
    Set(products.filter { $0.iwId != id }.map { skuKey($0["sku"]) }.filter { !$0.isEmpty })
  }

  /// `itemCodeRule(company)`: the rule item codes are built with.
  public static func itemCodeRule(_ company: JSONValue) -> NumberingRule {
    if let stored = WebJS.present(company["numbering"]?["product"]) { return NumberingRule(stored) }
    return Numbering.defaultRules()["product"] ?? NumberingRule(pattern: "SKU-{counter}", padding: 5)
  }

  /// `suggestItemCode(company)`: the code a new item saved now without an SKU would get.
  public static func suggestItemCode(_ company: JSONValue, products: [JSONValue], today: String) -> String {
    let taken = takenSkus(products.filter { $0["companyId"] == company["id"] }, except: nil)
    return Numbering.allocateNumber(itemCodeRule(company), today) { taken.contains(skuKey(.string($0))) }.number
  }

  /// `productKind(product)`.
  public static func productKind(_ product: JSONValue?) -> String {
    guard let kind = WebJS.present(product?["kind"]) else { return "service" }
    return kind.string ?? WebJS.string(kind)
  }

  /// `saveItem(input, { opening })`: an item saved; a service or non-stock
  /// item that becomes a stock item starts moving stock on its issued
  /// documents; a new stock item can get its opening stock at once; a new
  /// item without an SKU gets the next code when the company gives codes.
  @discardableResult
  public static func saveItem(
    _ ctx: WriteContext, _ input: JSONValue, opening: OpeningStock? = nil, reserved: ReservedCounter? = nil
  ) throws -> JSONValue {
    let name = WebJS.trim(input.iwText("name"))
    if name.isEmpty { throw WriteFailure("Enter a name for the item.") }
    guard var company = ctx.get("companies", input.iwText("companyId")) else { throw WriteFailure("Company not found") }
    let id = input.iwId
    let existing = ctx.get("products", id)
    let kind = productKind(input)
    let wasStock = productKind(existing) == "stock"
    var moved = 0
    if let existing {
      let companyId = existing.iwText("companyId")
      moved = ctx.all("stockMovements") { $0["companyId"]?.string == companyId && $0["productId"]?.string == id }.count
    }
    if existing != nil && wasStock && kind != "stock" && moved > 0 {
      throw WriteFailure(
        "This item has stock history, so it stays a stock item. Archive it if you no longer sell it.")
    }
    if (WebJS.present(input["costPrice"])?.double ?? 0) < 0 { throw WriteFailure("The cost can’t be negative.") }
    if (WebJS.present(input["reorderLevel"])?.double ?? 0) < 0 {
      throw WriteFailure("The reorder level can’t be negative.")
    }
    var sku = WebJS.trim(input.iwText("sku"))
    let companyProducts = IwRecords.company(ctx, "products", company.iwId)
    let taken = takenSkus(companyProducts, except: id)
    let givesCodes = WebJS.truthy(company["items"]?["autoSku"])
    if givesCodes, !sku.isEmpty, taken.contains(skuKey(.string(sku))),
      !(existing != nil && skuKey(existing?["sku"]) == skuKey(.string(sku)))
    {
      let other = companyProducts.filter { $0.iwId != id && skuKey($0["sku"]) == skuKey(.string(sku)) }
      if let first = other.first, other.allSatisfy({ $0.iwTruthy("archived") }) {
        throw WriteFailure(
          "The archived item {name} already has the SKU {sku}.", ["name": first.iwText("name"), "sku": sku])
      }
      throw WriteFailure("Another item already has the SKU {sku}.", ["sku": sku])
    }
    if sku.isEmpty, existing == nil, givesCodes {
      let allocated = Numbering.allocateFrom(
        itemCodeRule(company), ctx.today, clientNumber: "", reserved: reserved
      ) { taken.contains(skuKey(.string($0))) }
      sku = allocated.number
      let numbering = (company["numbering"] ?? .object([:])).iwWith("product", allocated.rule.raw)
      company = company.iwWith("numbering", numbering)
      ctx.put("companies", company)
    }
    let stamp = ctx.stamp
    var fields = WebJS.spread(input)
    fields["name"] = .string(name)
    fields["sku"] = .string(sku)
    fields["kind"] = .string(kind)
    fields["costPrice"] = .number(IwMoney.round(IwDecimal(WebJS.present(input["costPrice"]) ?? .number(0)), 6))
    fields["barcode"] = .string(input["barcode"]?.string.map(WebJS.trim) ?? "")
    fields["hsCode"] = .string(input["hsCode"]?.string.map(WebJS.trim) ?? "")
    fields["reorderLevel"] = kind == "stock" ? (WebJS.present(input["reorderLevel"]) ?? .null) : .null
    fields["updatedAt"] = .string(stamp)
    // A unit typed by hand has no id.
    if !WebJS.truthy(fields["unitId"]) { fields["unitId"] = nil }
    // Pictures change only through their own page: a form opened before
    // one was added doesn't take it away.
    let imageIds = existing != nil ? existing?["imageIds"] : input["imageIds"]
    if let list = imageIds?.array, !list.isEmpty {
      fields["imageIds"] = .array(list)
    } else {
      fields["imageIds"] = nil
    }
    if existing == nil { fields["createdAt"] = .string(stamp) }
    let product = JSONValue.object(fields)
    if let existing, (WebJS.present(existing["incomeAccountId"]) ?? .null) != (WebJS.present(product["incomeAccountId"]) ?? .null) {
      // Sales of a closed period keep the income account they were posted to.
      IwAccounts.freezeLockedPostings(ctx, company) { doc in
        let type = doc["type"]?.string
        return (type == "invoice" || type == "credit") && doc.iwList("items").contains { $0["productId"]?.string == id }
      }
    }
    ctx.put("products", product)

    if kind == "stock" {
      IwAccounts.ensureStockAccounts(ctx, company)
      ensureDefaultWarehouse(ctx)
    }
    if let existing, wasStock, kind == "stock", existing["costPrice"] != product["costPrice"] {
      // The cost price values sales made before any stock had a cost.
      recost(ctx, company, [id])
    }
    if existing != nil && wasStock != (kind == "stock") {
      // Issued documents with the item start (or stop) moving stock.
      let documents = IwRecords.company(ctx, "documents", company.iwId).filter { doc in
        IwSources.movesStock(doc) && doc.iwList("items").contains { $0["productId"]?.string == id }
      }
      let settings = IwAccountingSettings(company)
      if settings.lockDate != nil, documents.contains(where: { settings.locks($0["issueDate"]) }) {
        throw WriteFailure(
          "This item is on documents in a locked period, so whether it is tracked in stock can’t change.")
      }
      let setup = loadSetup(ctx, company)
      var touched: [String] = []
      for doc in documents {
        let before = movements(of: doc.iwId, ctx)
        let planned = IwSources.documentMovements(doc, setup, previous: previousWarehouses(before))
        touched += try replaceMovements(ctx, company, before, planned)
        for cost in activeLandedCosts(ctx, doc.iwId) { touched += try syncLandedCost(ctx, company, cost, setup) }
      }
      recost(ctx, company, touched)
    }
    if kind == "stock", let opening, opening.quantity > 0 {
      let warehouseId = opening.warehouseId.isEmpty ? ensureDefaultWarehouse(ctx).iwId : opening.warehouseId
      try addStockEntry(
        ctx, company,
        StockEntryInput(
          kind: "opening", date: opening.date, warehouseId: warehouseId, reference: "", notes: "",
          lines: [.init(productId: id, quantity: opening.quantity, unitCost: opening.unitCost)]))
    }
    ctx.logActivity(
      entity: "product", entityId: id, action: existing != nil ? "updated" : "created",
      message: ActivityMessage(existing != nil ? "Item {name} updated" : "Item {name} created", vars: ["name": name]))
    return product
  }

  /// A counter the cloud hands out (`reserve_number`), asked for before saving.
  public struct CounterRequest: Sendable, Equatable {
    public var kind: String
    public var date: String
    /// This device's own next counter less one: the one taken is never lower.
    public var min: Int
  }

  /// `reserveItemCounter(input, opening)`, without the asking: for a new
  /// item without an SKU in a company that gives codes, what to ask the
  /// cloud for, so two devices never give the same code; nil to number on
  /// this iPhone. A save that is going to be refused asks for none.
  public static func itemCounterRequest(_ ctx: WriteContext, _ input: JSONValue, opening: OpeningStock? = nil)
    -> CounterRequest?
  {
    if !WebJS.trim(input.iwText("sku")).isEmpty { return nil }
    if WebJS.trim(input.iwText("name")).isEmpty || (WebJS.present(input["costPrice"])?.double ?? 0) < 0
      || (WebJS.present(input["reorderLevel"])?.double ?? 0) < 0
    {
      return nil
    }
    if ctx.get("products", input.iwId) != nil { return nil }
    guard let company = ctx.get("companies", input.iwText("companyId")), WebJS.truthy(company["items"]?["autoSku"])
    else { return nil }
    if productKind(input) == "stock", let opening, opening.quantity > 0 {
      if (try? IwAccounts.assertUnlocked(company, .string(opening.date))) == nil { return nil }
    }
    let taken = takenSkus(IwRecords.company(ctx, "products", company.iwId), except: input.iwId)
    let local = Numbering.allocateNumber(itemCodeRule(company), ctx.today) { taken.contains(skuKey(.string($0))) }
    let next = local.rule.next
    return CounterRequest(kind: "product", date: ctx.today, min: next.isFinite ? Int(next) - 1 : 0)
  }

  /// `nextItemCodes(company, taken, count, reserved)`: the next codes and the rule after them.
  static func nextItemCodes(_ company: JSONValue, taken: inout Set<String>, count: Int, today: String)
    -> (codes: [String], rule: NumberingRule)
  {
    var rule = itemCodeRule(company)
    var codes: [String] = []
    for _ in 0..<max(0, count) {
      let current = taken
      let allocated = Numbering.allocateNumber(rule, today) { current.contains(skuKey(.string($0))) }
      rule = allocated.rule
      taken.insert(skuKey(.string(allocated.number)))
      codes.append(allocated.number)
    }
    return (codes, rule)
  }

  /// `uncodedItems(products)`: items without an SKU that aren't archived, oldest first.
  static func uncodedItems(_ products: [JSONValue]) -> [JSONValue] {
    let missing = products.filter { !$0.iwTruthy("archived") && WebJS.trim($0.iwText("sku")).isEmpty }
    return missing.enumerated().sorted { a, b in
      let created = IwRecords.localeCompare(
        a.element["createdAt"]?.string ?? "", b.element["createdAt"]?.string ?? "")
      if created != 0 { return created < 0 }
      let name = IwRecords.localeCompare(a.element.iwText("name"), b.element.iwText("name"))
      if name != 0 { return name < 0 }
      return a.offset < b.offset
    }.map(\.element)
  }

  /// `assignItemCodes(companyId)`: the next codes given to the items
  /// without one, oldest first. How many got one.
  @discardableResult
  public static func assignItemCodes(_ ctx: WriteContext) throws -> Int {
    let company = try theCompany(ctx)
    let products = IwRecords.company(ctx, "products", ctx.companyId)
    let missing = uncodedItems(products)
    if missing.isEmpty { return 0 }
    var taken = Set(products.map { skuKey($0["sku"]) }.filter { !$0.isEmpty })
    let next = nextItemCodes(company, taken: &taken, count: missing.count, today: ctx.today)
    let stamp = JSONValue.string(ctx.stamp)
    for (index, product) in missing.enumerated() {
      ctx.put("products", product.iwWith(["sku": .string(next.codes[index]), "updatedAt": stamp]))
    }
    let numbering = (company["numbering"] ?? .object([:])).iwWith("product", next.rule.raw)
    ctx.put("companies", company.iwWith("numbering", numbering))
    // The count is a number in the message's values, as on the web.
    let count = Double(missing.count)
    var activity: [String: JSONValue] = [
      "id": .string(ctx.newId()), "companyId": .string(ctx.companyId), "at": stamp,
      "entity": "company", "entityId": .string(ctx.companyId), "clientId": .null, "documentId": .null,
      "action": "item_codes",
      "message": .string(I18n.interpolate("Item codes given to {count} items", ["count": WebJS.numberString(count)])),
      "messageKey": "Item codes given to {count} items",
      "messageVars": .object(["count": .number(count)]),
    ]
    if let userId = ctx.userId, !userId.isEmpty {
      activity["by"] = .string(userId)
      let name = String(WebJS.trim(ctx.userName ?? "").prefix(200))
      if !name.isEmpty { activity["byName"] = .string(name) }
    }
    ctx.put("activities", .object(activity))
    return missing.count
  }

  /// `deleteItem(id)`: an item without stock history, with its pictures;
  /// documents keep their copy of it.
  public static func deleteItem(_ ctx: WriteContext, id: String) throws {
    guard let product = ctx.get("products", id) else { return }
    if hasStockHistory(ctx, product) { throw WriteFailure("This item has stock history. Archive it instead.") }
    for attachment in IwRecords.matching(ctx, "attachments", "ownerId", id) { ctx.delete("attachments", attachment.iwId) }
    ctx.delete("products", id)
    ctx.logActivity(
      entity: "product", entityId: id, action: "deleted",
      message: ActivityMessage(
        "Item {name} deleted", vars: ["name": product.iwText("name")], arabic: ["name": product["nameAr"]?.string]))
  }

  // MARK: Stock entries

  /// `StockEntryInput`: opening stock, an adjustment or a transfer.
  public struct StockEntryInput: Sendable, Equatable {
    public struct Line: Sendable, Equatable {
      public var productId: String
      public var quantity: Double
      public var unitCost: Double?

      public init(productId: String, quantity: Double, unitCost: Double? = nil) {
        self.productId = productId
        self.quantity = quantity
        self.unitCost = unitCost
      }
    }

    /// "opening", "adjustment" or "transfer".
    public var kind: String
    public var date: String
    public var warehouseId: String
    public var toWarehouseId: String?
    /// "damaged", "expired", "count" or "other".
    public var reason: String?
    public var reference: String
    public var notes: String
    public var lines: [Line]

    public init(
      kind: String, date: String, warehouseId: String, toWarehouseId: String? = nil, reason: String? = nil,
      reference: String, notes: String, lines: [Line]
    ) {
      self.kind = kind
      self.date = date
      self.warehouseId = warehouseId
      self.toWarehouseId = toWarehouseId
      self.reason = reason
      self.reference = reference
      self.notes = notes
      self.lines = lines
    }
  }

  /// `nextNumber(prefix, taken)`: "ADJ-0007".
  public static func nextNumber(_ prefix: String, _ taken: [String]) -> String {
    var last = 0
    let head = prefix + "-"
    for number in taken where number.hasPrefix(head) {
      let digits = number.dropFirst(head.count)
      guard !digits.isEmpty, digits.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }) else { continue }
      let value = Int(digits.prefix(18)) ?? Int.max
      last = max(last, value)
    }
    return "\(prefix)-\(WebJS.padStart(String(last + 1), 4))"
  }

  /// `addStockEntry(company, input)`: a stock entry recorded, its movements planned and costed.
  @discardableResult
  static func addStockEntry(_ ctx: WriteContext, _ company: JSONValue, _ input: StockEntryInput) throws -> JSONValue {
    try IwAccounts.assertUnlocked(company, .string(input.date))
    let lines = input.lines.filter { !$0.productId.isEmpty && $0.quantity != 0 }
    if lines.isEmpty { throw WriteFailure("Add at least one item with a quantity.") }
    let companyId = company.iwId
    for line in lines {
      let product = ctx.get("products", line.productId)
      if product == nil || product?["companyId"]?.string != companyId || !IwSources.isStockItem(product) {
        throw WriteFailure("Only stock items can be added.")
      }
    }
    if input.kind != "adjustment" && lines.contains(where: { $0.quantity < 0 }) {
      throw WriteFailure("Quantities must be positive.")
    }
    if input.kind == "opening" && lines.contains(where: { !(($0.unitCost ?? 0) >= 0) }) {
      throw WriteFailure("The cost can’t be negative.")
    }
    let warehouses = IwRecords.company(ctx, "warehouses", companyId)
    let live = { (id: String?) in warehouses.contains { $0["id"]?.string == id && !$0.iwTruthy("archived") } }
    if !live(input.warehouseId) { throw WriteFailure("Choose a warehouse.") }
    if input.kind == "transfer" {
      if !live(input.toWarehouseId) { throw WriteFailure("Choose where the stock goes.") }
      if input.toWarehouseId == input.warehouseId { throw WriteFailure("Choose two different warehouses.") }
    }
    IwAccounts.ensureStockAccounts(ctx, company)
    let taken = IwRecords.company(ctx, "stockEntries", companyId).map { $0.iwText("number") }
    let stamp = JSONValue.string(ctx.stamp)
    let prefix = input.kind == "opening" ? "OPN" : input.kind == "transfer" ? "TRF" : "ADJ"
    let entryId = ctx.newId()
    let number = nextNumber(prefix, taken)
    var entryLines: [JSONValue] = []
    for line in lines {
      entryLines.append(
        .object([
          "id": .string(ctx.shortId()),
          "productId": .string(line.productId),
          "quantity": .number(line.quantity),
          "unitCost": input.kind == "opening" ? .number(IwMoney.round(line.unitCost ?? 0, 6)) : .null,
        ]))
    }
    let entry: JSONValue = .object([
      "id": .string(entryId),
      "companyId": .string(companyId),
      "kind": .string(input.kind),
      "number": .string(number),
      "date": .string(input.date),
      "warehouseId": .string(input.warehouseId),
      "toWarehouseId": input.kind == "transfer" ? (input.toWarehouseId.map(JSONValue.string) ?? .null) : .null,
      "reason": input.kind == "adjustment" ? .string(input.reason ?? "other") : .null,
      "reference": .string(WebJS.trim(input.reference)),
      "notes": .string(WebJS.trim(input.notes)),
      "lines": .array(entryLines),
      "status": "posted",
      "voidedAt": .null,
      "createdAt": stamp,
      "updatedAt": stamp,
    ])
    ctx.put("stockEntries", entry)
    let setup = loadSetup(ctx, company)
    recost(ctx, company, try replaceMovements(ctx, company, [], IwSources.entryMovements(entry, setup)))
    let text =
      input.kind == "opening"
      ? "Opening stock {number} recorded"
      : input.kind == "transfer" ? "Stock transfer {number} recorded" : "Stock adjustment {number} recorded"
    ctx.logActivity(
      entity: "stock", entityId: entryId, action: "posted", message: ActivityMessage(text, vars: ["number": number]))
    return entry
  }

  /// `recordStockEntry(companyId, input)`: opening stock, an adjustment or a transfer.
  @discardableResult
  public static func recordStockEntry(_ ctx: WriteContext, _ input: StockEntryInput) throws -> JSONValue {
    try addStockEntry(ctx, try theCompany(ctx), input)
  }

  /// `voidStockEntry(id)`: the entry stays on record and its movements leave the books.
  public static func voidStockEntry(_ ctx: WriteContext, id: String) throws {
    guard let entry = ctx.get("stockEntries", id), entry["status"]?.string != "void" else { return }
    guard let company = ctx.get("companies", entry.iwText("companyId")) else { return }
    try IwAccounts.assertUnlocked(company, entry["date"])
    let stamp = JSONValue.string(ctx.stamp)
    ctx.put("stockEntries", entry.iwWith(["status": "void", "voidedAt": stamp, "updatedAt": stamp]))
    let existing = movements(of: id, ctx)
    recost(ctx, company, try replaceMovements(ctx, company, existing, []))
    ctx.logActivity(
      entity: "stock", entityId: id, action: "void",
      message: ActivityMessage("Stock entry {number} voided", vars: ["number": entry.iwText("number")]))
  }

  /// `syncIssueStock(company, issue)`: the movements of items issued made to
  /// match the issue as stored (posted or void), then costed.
  static func syncIssueStock(_ ctx: WriteContext, _ company: JSONValue, _ issue: JSONValue) throws {
    let setup = loadSetup(ctx, company)
    let existing = movements(of: issue.iwId, ctx)
    recost(ctx, company, try replaceMovements(ctx, company, existing, IwSources.issueMovements(issue, setup)))
  }

  // MARK: Landed costs

  /// `LandedCostInput`: charges on a bill allocated to the stock received on it or an earlier one.
  public struct LandedCostInput: Sendable, Equatable {
    public var billId: String
    public var sourceLineIds: [String]
    public var targetBillId: String
    public var targetLineIds: [String]
    /// "value" or "quantity".
    public var method: String
    public var notes: String

    public init(
      billId: String, sourceLineIds: [String], targetBillId: String, targetLineIds: [String], method: String,
      notes: String
    ) {
      self.billId = billId
      self.sourceLineIds = sourceLineIds
      self.targetBillId = targetBillId
      self.targetLineIds = targetLineIds
      self.method = method
      self.notes = notes
    }
  }

  /// `saveLandedCost(companyId, input)`: the charges post to inventory and
  /// raise the cost of the items from the date of the bill with the charges.
  @discardableResult
  public static func saveLandedCost(_ ctx: WriteContext, _ input: LandedCostInput) throws -> JSONValue {
    let company = try theCompany(ctx)
    let companyId = ctx.companyId
    let costBill = ctx.get("documents", input.billId)
    let targetBill = ctx.get("documents", input.targetBillId)
    func issuedBill(_ doc: JSONValue?) -> Bool {
      guard let doc else { return false }
      return doc["companyId"]?.string == companyId && doc["type"]?.string == "bill" && IwSources.movesStock(doc)
    }
    guard issuedBill(costBill), issuedBill(targetBill), let costBill, let targetBill else {
      throw WriteFailure("Both bills must be issued (not drafts or void).")
    }
    if IwRecords.textOrder(targetBill["issueDate"], costBill["issueDate"]) > 0 {
      throw WriteFailure("The bill with the charges must be dated on or after the bill with the goods.")
    }
    try IwAccounts.assertUnlocked(company, costBill["issueDate"])
    let setup = loadSetup(ctx, company)
    let stockIds = Set(IwSources.stockLines(costBill, setup.products).map { WebJS.string($0["id"]) })
    let sourceLineIds = IwRecords.unique(input.sourceLineIds).filter { !stockIds.contains($0) }
    if sourceLineIds.isEmpty { throw WriteFailure("Choose the charges to add to the cost of the goods.") }
    let others = IwRecords.matching(ctx, "landedCosts", "billId", costBill.iwId).filter {
      $0["status"]?.string == "active"
    }
    let chosen = Set(sourceLineIds)
    let overlaps = others.contains { other in
      other.iwList("sourceLineIds").contains { line in chosen.contains(line.string ?? "\u{0}") }
    }
    if overlaps {
      throw WriteFailure("A charge on this bill is already allocated to stock.")
    }
    let taken = IwRecords.company(ctx, "landedCosts", companyId).map { $0.iwText("number") }
    let stamp = JSONValue.string(ctx.stamp)
    let id = ctx.newId()
    let number = nextNumber("LC", taken)
    let cost: JSONValue = .object([
      "id": .string(id),
      "companyId": .string(companyId),
      "number": .string(number),
      "billId": .string(costBill.iwId),
      "sourceLineIds": .array(sourceLineIds.map(JSONValue.string)),
      "targetBillId": .string(targetBill.iwId),
      "targetLineIds": .array(IwRecords.unique(input.targetLineIds).map(JSONValue.string)),
      "method": .string(input.method),
      "notes": .string(WebJS.trim(input.notes)),
      "status": "active",
      "voidedAt": .null,
      "createdAt": stamp,
      "updatedAt": stamp,
    ])
    if IwSources.landedCostLinks(cost, costBill, targetBill, setup.products) == nil {
      throw WriteFailure("The bill with the goods has no stock items to receive the charges.")
    }
    IwAccounts.ensureStockAccounts(ctx, company)
    ctx.put("landedCosts", cost)
    recost(ctx, company, try syncLandedCost(ctx, company, cost, setup))
    ctx.logActivity(
      entity: "stock", entityId: id, action: "created",
      message: ActivityMessage(
        "Landed cost {number} allocated to {bill}", vars: ["number": number, "bill": targetBill.iwText("number")]))
    return cost
  }

  /// `voidLandedCost(id)`: the charges go back to their expense accounts.
  public static func voidLandedCost(_ ctx: WriteContext, id: String) throws {
    guard let cost = ctx.get("landedCosts", id), cost["status"]?.string != "void" else { return }
    guard let company = ctx.get("companies", cost.iwText("companyId")) else { return }
    let costBill = ctx.get("documents", cost.iwText("billId"))
    try IwAccounts.assertUnlocked(company, costBill?["issueDate"])
    let stamp = JSONValue.string(ctx.stamp)
    ctx.put("landedCosts", cost.iwWith(["status": "void", "voidedAt": stamp, "updatedAt": stamp]))
    let existing = movements(of: id, ctx)
    recost(ctx, company, try replaceMovements(ctx, company, existing, []))
    ctx.logActivity(
      entity: "stock", entityId: id, action: "void",
      message: ActivityMessage("Landed cost {number} voided", vars: ["number": cost.iwText("number")]))
  }
}
