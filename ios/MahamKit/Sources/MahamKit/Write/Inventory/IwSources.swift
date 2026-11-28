import Foundation

/// Where stock movements come from, ported from the web's
/// `src/lib/inventory/sources.ts`: issued bills, vendor credits, invoices
/// and credit notes, stock entries, landed costs and items issued to
/// employees. Movements are planned here without their cost (as records
/// without `id`, `companyId`, `unitCost`, `value`, `createdAt`,
/// `updatedAt`); `IwCosting` values them.
enum IwSources {
  /// `StockSetup`: what planning reads about the company.
  struct Setup {
    var companyCurrency: String
    var precision: Int
    /// Ids of the stock items.
    var products: Set<String>
    var defaultWarehouseId: String
    /// Warehouses that exist; lines pointing elsewhere use the default one.
    var warehouses: Set<String>
    /// Clients marked tax exempt.
    var exemptClients: Set<String>
  }

  /// `STOCK_DOCUMENT_TYPES`: quotes, orders and delivery notes never move stock.
  static let stockDocumentTypes: Set<String> = ["bill", "vendor_credit", "invoice", "credit"]

  /// `isStockItem(product)`.
  static func isStockItem(_ product: JSONValue?) -> Bool {
    product?["kind"]?.string == "stock"
  }

  /// `isPosted(doc)`: invoices, credit notes, bills and vendor credits, issued and not void.
  static func isPosted(_ doc: JSONValue?) -> Bool {
    guard let type = doc?["type"]?.string, stockDocumentTypes.contains(type) else { return false }
    let status = doc?["status"]?.string
    return status != "draft" && status != "void"
  }

  /// `movesStock(doc)`.
  static func movesStock(_ doc: JSONValue?) -> Bool {
    isPosted(doc)
  }

  /// `stockLines(doc, products)`: lines that carry a stock item.
  static func stockLines(_ doc: JSONValue, _ products: Set<String>) -> [JSONValue] {
    doc.iwList("items").filter { item in
      guard item["kind"]?.string == "item", let product = item["productId"]?.string, !product.isEmpty else {
        return false
      }
      return products.contains(product)
    }
  }

  private static func warehouseOf(_ id: JSONValue?, _ setup: Setup) -> String {
    if let id = id?.string, !id.isEmpty, setup.warehouses.contains(id) { return id }
    return setup.defaultWarehouseId
  }

  /// `order(stamp, index, part)`: "createdAt|0003|0".
  static func order(_ stamp: JSONValue?, _ index: Int, _ part: Int = 0) -> String {
    "\(WebJS.string(stamp))|\(WebJS.padStart(String(index), 4))|\(part)"
  }

  /// A stored or planned movement's identity (`plannedKey`).
  static func plannedKey(_ m: JSONValue) -> String {
    let fields = [
      "productId", "warehouseId", "date", "quantity", "sourceValue", "sourceType", "lineId", "documentId", "number",
      "returnOf", "basisQuantity", "sequence",
    ]
    return WebJS.json(.array(fields.map { m[$0] ?? .null }))
  }

  /// `documentMovements(doc, setup, previous)`: bills bring stock in at the
  /// line's value in the company currency, vendor credits take it out at
  /// the value credited; invoices take it out and credit notes bring it
  /// back, both costed later.
  static func documentMovements(_ doc: JSONValue, _ setup: Setup, previous: [String: String] = [:]) -> [JSONValue] {
    guard movesStock(doc) else { return [] }
    // The stock lines with a quantity, each with its place among the items.
    var lines: [(index: Int, item: JSONValue)] = []
    for (index, item) in doc.iwList("items").enumerated() {
      guard item["kind"]?.string == "item", let product = item["productId"]?.string, !product.isEmpty,
        setup.products.contains(product), item["quantity"]?.double != 0
      else { continue }
      lines.append((index: index, item: item))
    }
    if lines.isEmpty { return [] }
    let type = doc.iwText("type")
    let purchase = type == "bill" || type == "vendor_credit"
    let parts: [String: Int]? =
      purchase
      ? IwCalc.documentLineParts(
        doc, companyCurrency: setup.companyCurrency, precision: setup.precision, exemptClients: setup.exemptClients)
      : nil
    let direction: Double = type == "bill" || type == "credit" ? 1 : -1
    var planned: [JSONValue] = []
    for line in lines {
      let item = line.item
      guard let quantity = item["quantity"]?.double, quantity.isFinite else { continue }
      let lineId = item["id"]
      var wanted = WebJS.present(item["warehouseId"])
      if wanted == nil, let id = lineId?.string, let before = previous[id] { wanted = .string(before) }
      var fields: [String: JSONValue] = [
        "productId": item["productId"] ?? .null,
        "warehouseId": .string(warehouseOf(wanted, setup)),
        "quantity": .number(direction * quantity),
        "sourceType": .string(type),
        "basisQuantity": .null,
        "sequence": .string(order(doc["createdAt"], line.index)),
        "notes": "",
      ]
      fields["date"] = doc["issueDate"]
      fields["sourceId"] = doc["id"]
      fields["lineId"] = lineId
      fields["documentId"] = doc["id"]
      fields["number"] = doc["number"]
      if let parts {
        let part = parts[WebJS.string(lineId)] ?? 0
        fields["sourceValue"] = .number(IwMoney.fromMinor(Int(direction) * part, setup.precision))
      } else {
        fields["sourceValue"] = .null
      }
      if type == "credit" {
        fields["returnOf"] = doc["sourceId"]
      } else {
        fields["returnOf"] = .null
      }
      planned.append(.object(fields))
    }
    return planned
  }

  /// `entryMovements(entry, setup)`: opening stock, an adjustment or a transfer.
  static func entryMovements(_ entry: JSONValue, _ setup: Setup) -> [JSONValue] {
    guard entry["status"]?.string == "posted" else { return [] }
    let kind = entry.iwText("kind")
    let from = warehouseOf(entry["warehouseId"], setup)
    var planned: [JSONValue] = []
    for (index, line) in entry.iwList("lines").enumerated() {
      guard let product = line["productId"]?.string, setup.products.contains(product) else { continue }
      guard let quantity = line["quantity"]?.double, quantity != 0, quantity.isFinite else { continue }
      var common: [String: JSONValue] = [
        "sourceType": .string(kind),
        "documentId": .null,
        "returnOf": .null,
        "basisQuantity": .null,
        "notes": "",
        "productId": .string(product),
      ]
      common["date"] = entry["date"]
      common["sourceId"] = entry["id"]
      common["number"] = entry["number"]
      common["lineId"] = line["id"]
      if kind == "transfer" {
        var out = common
        out["warehouseId"] = .string(from)
        out["quantity"] = .number(-quantity)
        out["sourceValue"] = .null
        out["sequence"] = .string(order(entry["createdAt"], index, 0))
        var into = common
        into["warehouseId"] = .string(warehouseOf(entry["toWarehouseId"], setup))
        into["quantity"] = .number(quantity)
        into["sourceValue"] = .null
        into["sequence"] = .string(order(entry["createdAt"], index, 1))
        planned.append(.object(out))
        planned.append(.object(into))
      } else {
        var only = common
        only["warehouseId"] = .string(from)
        only["quantity"] = .number(quantity)
        if kind == "opening" {
          let value = IwDecimal(line["quantity"]).times(IwDecimal(WebJS.present(line["unitCost"]) ?? .number(0)))
          only["sourceValue"] = .number(IwMoney.round(value, setup.precision))
        } else {
          only["sourceValue"] = .null
        }
        only["sequence"] = .string(order(entry["createdAt"], index))
        planned.append(.object(only))
      }
    }
    return planned
  }

  /// `issueMovements(issue, setup)`: items issued leave the warehouse at the
  /// weighted average cost; void issues move nothing.
  static func issueMovements(_ issue: JSONValue, _ setup: Setup) -> [JSONValue] {
    guard issue["status"]?.string == "posted" else { return [] }
    let from = warehouseOf(issue["warehouseId"], setup)
    var planned: [JSONValue] = []
    for (index, line) in issue.iwList("lines").enumerated() {
      guard let product = line["productId"]?.string, setup.products.contains(product) else { continue }
      guard let quantity = line["quantity"]?.double, quantity != 0, quantity.isFinite else { continue }
      var fields: [String: JSONValue] = [
        "productId": .string(product),
        "warehouseId": .string(from),
        "quantity": .number(-quantity),
        "sourceType": "issue",
        "documentId": .null,
        "sourceValue": .null,
        "returnOf": .null,
        "basisQuantity": .null,
        "sequence": .string(order(issue["createdAt"], index)),
        "notes": "",
      ]
      fields["date"] = issue["date"]
      fields["sourceId"] = issue["id"]
      fields["lineId"] = line["id"]
      fields["number"] = issue["number"]
      planned.append(.object(fields))
    }
    return planned
  }

  // MARK: Landed costs

  /// `LandedCostLinks`: the charges that post to inventory and the stock lines that receive a share.
  struct LandedCostLinks {
    var sourceIds: [String]
    var targets: [JSONValue]
  }

  /// `landedCostLinks(cost, costBill, targetBill, products)`: nil when the landed cost has no effect.
  static func landedCostLinks(_ cost: JSONValue, _ costBill: JSONValue?, _ targetBill: JSONValue?, _ products: Set<String>)
    -> LandedCostLinks?
  {
    guard cost["status"]?.string == "active", let costBill, let targetBill else { return nil }
    guard costBill["type"]?.string == "bill", targetBill["type"]?.string == "bill" else { return nil }
    guard isPosted(costBill), isPosted(targetBill) else { return nil }
    let stockIds = Set(stockLines(costBill, products).map { WebJS.string($0["id"]) })
    var available = Set<String>()
    for item in costBill.iwList("items") where item["kind"]?.string == "item" { available.insert(WebJS.string(item["id"])) }
    for charge in costBill.iwList("charges") { available.insert(WebJS.string(charge["id"])) }
    let sourceIds = cost.iwList("sourceLineIds").compactMap(\.string).filter {
      available.contains($0) && !stockIds.contains($0)
    }
    let wanted = cost.iwList("targetLineIds").compactMap(\.string)
    let targets = stockLines(targetBill, products).filter { line in
      (line["quantity"]?.double ?? 0) > 0 && (wanted.isEmpty || wanted.contains(WebJS.string(line["id"])))
    }
    if sourceIds.isEmpty || targets.isEmpty { return nil }
    return LandedCostLinks(sourceIds: sourceIds, targets: targets)
  }

  /// One stock line's share of a landed cost (`LandedCostShare`), in minor units.
  struct LandedCostShare {
    var lineId: JSONValue?
    var productId: JSONValue?
    var warehouseId: String
    var quantity: JSONValue?
    var lineValue: Int
    var share: Int
  }

  /// `allocateLandedCost(cost, costBill, targetBill, links, setup)`: the
  /// charges split over the stock lines by value or by quantity; the shares
  /// add up to the charges exactly.
  static func allocateLandedCost(
    _ cost: JSONValue, _ costBill: JSONValue, _ targetBill: JSONValue, _ links: LandedCostLinks, _ setup: Setup
  ) -> (total: Int, shares: [LandedCostShare]) {
    let costParts = IwCalc.documentLineParts(
      costBill, companyCurrency: setup.companyCurrency, precision: setup.precision, exemptClients: setup.exemptClients)
    let sameBill = targetBill["id"] == costBill["id"]
    let targetParts =
      sameBill
      ? costParts
      : IwCalc.documentLineParts(
        targetBill, companyCurrency: setup.companyCurrency, precision: setup.precision,
        exemptClients: setup.exemptClients)
    var total = 0
    for id in links.sourceIds { total += costParts[id] ?? 0 }
    let byQuantity = cost["method"]?.string == "quantity"
    let weights = links.targets.map { line in
      byQuantity ? IwDecimal(line["quantity"]) : IwDecimal(targetParts[WebJS.string(line["id"])] ?? 0)
    }
    let shares = IwCalc.allocate(total, weights)
    var out: [LandedCostShare] = []
    for (index, line) in links.targets.enumerated() {
      out.append(
        LandedCostShare(
          lineId: line["id"], productId: line["productId"], warehouseId: warehouseOf(line["warehouseId"], setup),
          quantity: line["quantity"], lineValue: targetParts[WebJS.string(line["id"])] ?? 0, share: shares[index]))
    }
    return (total, out)
  }

  /// `landedCostMovements(cost, costBill, shares, precision)`: value-only
  /// movements, dated like the bill with the charges.
  static func landedCostMovements(_ cost: JSONValue, _ costBill: JSONValue, _ shares: [LandedCostShare], precision: Int)
    -> [JSONValue]
  {
    var planned: [JSONValue] = []
    for (index, share) in shares.enumerated() {
      var fields: [String: JSONValue] = [
        "warehouseId": .string(share.warehouseId),
        "quantity": 0,
        "sourceType": "landed_cost",
        "sourceValue": .number(IwMoney.fromMinor(share.share, precision)),
        "returnOf": .null,
        "sequence": .string(order(cost["createdAt"], index)),
        "notes": "",
      ]
      fields["productId"] = share.productId
      fields["date"] = costBill["issueDate"]
      fields["sourceId"] = cost["id"]
      fields["lineId"] = share.lineId
      fields["documentId"] = costBill["id"]
      fields["number"] = cost["number"]
      fields["basisQuantity"] = share.quantity
      planned.append(.object(fields))
    }
    return planned
  }
}
