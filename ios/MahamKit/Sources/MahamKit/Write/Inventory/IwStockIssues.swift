import Foundation

/// Items issued to employees, ported from the web's `src/db/stock-issues.ts`:
/// uniforms handed from a (sub-)warehouse to a guard. An approver records
/// them at once; whoever looks after a sub-warehouse sends them for
/// approval (an approval request of kind `stock_issue` carrying the issue
/// as it would be kept), and only once it is confirmed does the stock leave
/// the warehouse and its cost go to the books.
public enum IwStockIssues {
  /// The person's place in a company kept in the cloud (`CloudLink`): nil
  /// for a company kept on this device only.
  public struct Link: Sendable, Equatable {
    public var role: MemberRole
    public var userId: String
    /// The owner allowed them to approve requests.
    public var approver: Bool
    /// What the company's server has (`server_features`).
    public var features: [String]?

    public init(role: MemberRole, userId: String, approver: Bool = false, features: [String]? = nil) {
      self.role = role
      self.userId = userId
      self.approver = approver
      self.features = features
    }

    /// `linkHasFeature(link, feature)`.
    public func has(_ feature: String) -> Bool { features?.contains(feature) ?? false }
  }

  /// `IssueInput`: what issuing items asks for.
  public struct Input: Sendable, Equatable {
    public struct Line: Sendable, Equatable {
      public var productId: String
      public var quantity: Double

      public init(productId: String, quantity: Double) {
        self.productId = productId
        self.quantity = quantity
      }
    }

    public var date: String
    public var warehouseId: String
    /// `IssueRecipient`: employeeId, number, name, nameAr, jobTitle, jobTitleAr.
    public var recipient: JSONValue
    public var lines: [Line]
    public var notes: String

    public init(date: String, warehouseId: String, recipient: JSONValue, lines: [Line], notes: String) {
      self.date = date
      self.warehouseId = warehouseId
      self.recipient = recipient
      self.lines = lines
      self.notes = notes
    }
  }

  /// `Issuer`: who issues the items, as the issue names them.
  public struct Issuer: Sendable, Equatable {
    /// Their account; nil in a company kept on this device.
    public var userId: String?
    public var name: String

    public init(userId: String?, name: String) {
      self.userId = userId
      self.name = name
    }
  }

  // MARK: Who may issue

  /// `managesWarehouses(link)`: the owner, an admin or an accountant (everyone on this device).
  public static func managesWarehouses(_ link: Link?) -> Bool {
    guard let link else { return true }
    return Roles.managesWarehouses(link.role)
  }

  /// `issuesOffered(link)`: in the cloud once its server has issuing.
  public static func issuesOffered(_ link: Link?) -> Bool {
    guard let link else { return true }
    return link.has("stock_issues")
  }

  /// Whether the person records items issued at once (`!link || isApprover`).
  public static func isApprover(_ link: Link?) -> Bool {
    guard let link else { return true }
    return Roles.isApprover(link.role, link.approver)
  }

  /// `issuesFrom(warehouse, link)`: those who manage warehouses from any in
  /// use, anyone else from the sub-warehouse they look after.
  public static func issuesFrom(_ warehouse: JSONValue?, _ link: Link?) -> Bool {
    guard let warehouse, !warehouse.iwTruthy("archived") else { return false }
    guard let link else { return true }
    return link.role != .viewer
      && (Roles.managesWarehouses(link.role)
        || (warehouse.iwTruthy("parentId") && Roles.issuesFromWarehouse(link.role, userId: link.userId, warehouse)))
  }

  // MARK: What waits

  /// `isStockIssueRequest(request)`.
  public static func isStockIssueRequest(_ request: JSONValue?) -> Bool {
    request?["kind"]?.string == "stock_issue" && request?["subjectTbl"]?.string == "stockIssues"
  }

  /// `requestedIssue(request)`: the issue a request carries, or nil.
  public static func requestedIssue(_ request: JSONValue) -> JSONValue? {
    guard isStockIssueRequest(request), let after = WebJS.present(request["after"]), WebJS.truthy(after) else {
      return nil
    }
    guard after["warehouseId"]?.string != nil, WebJS.truthy(after["recipient"]), after["lines"]?.array != nil else {
      return nil
    }
    return after.iwWith(["id": request["subjectId"] ?? .null, "companyId": request["companyId"] ?? .null])
  }

  /// `stockKey(warehouseId, productId)`.
  public static func stockKey(_ warehouseId: String, _ productId: String) -> String { "\(warehouseId)|\(productId)" }

  /// `waitingQuantities(requests, except)`: asked for and not issued yet, by warehouse and item.
  public static func waitingQuantities(_ requests: [JSONValue], except: String? = nil) -> [String: Double] {
    var waiting: [String: Double] = [:]
    for request in requests {
      let status = request["status"]?.string
      guard status == "pending" || status == "approved", request["id"]?.string != except || except == nil else {
        continue
      }
      guard let issue = requestedIssue(request) else { continue }
      let warehouse = issue.iwText("warehouseId")
      for line in issue.iwList("lines") {
        let key = stockKey(warehouse, WebJS.string(line["productId"]))
        waiting[key] = IwDecimal(waiting[key] ?? 0).plus(IwDecimal(line["quantity"])).toNumber()
      }
    }
    return waiting
  }

  /// `waitingIssueRequests(companyId)`: waiting for an approver, or
  /// confirmed and not recorded yet.
  public static func waitingIssueRequests(_ ctx: WriteContext) -> [JSONValue] {
    let requests = IwRecords.company(ctx, "approvals", ctx.companyId).filter { request in
      let status = request["status"]?.string
      return (status == "pending" || status == "approved") && isStockIssueRequest(request)
    }
    return requests.filter { request in
      request["status"]?.string != "approved" || ctx.get("stockIssues", request.iwText("subjectId")) == nil
    }
  }

  /// `warehouseStock(companyId, warehouseId)`: each item's stock in a warehouse now.
  public static func warehouseStock(_ ctx: WriteContext, warehouseId: String) -> [String: Double] {
    var stock: [String: Double] = [:]
    for movement in IwRecords.matching(ctx, "stockMovements", "warehouseId", warehouseId)
    where movement["companyId"]?.string == ctx.companyId {
      let product = movement.iwText("productId")
      stock[product] = IwDecimal(stock[product] ?? 0).plus(IwDecimal(movement["quantity"])).toNumber()
    }
    return stock
  }

  // MARK: Issuing

  /// `buildIssue(company, input, issuer, waiting)`: the issue as it would be kept, checked.
  static func buildIssue(_ ctx: WriteContext, _ company: JSONValue, _ input: Input, _ issuer: Issuer, waiting: [String: Double])
    throws -> JSONValue
  {
    try IwAccounts.assertUnlocked(company, .string(input.date))
    let companyId = company.iwId
    guard let warehouse = ctx.get("warehouses", input.warehouseId), warehouse["companyId"]?.string == companyId,
      !warehouse.iwTruthy("archived")
    else { throw WriteFailure("Choose the warehouse the items come from.") }
    let recipient = input.recipient
    if !recipient.iwTruthy("employeeId") || WebJS.trim(recipient.iwText("name")).isEmpty {
      throw WriteFailure("Choose the employee who receives the items.")
    }
    // The same item twice is one line.
    var order: [String] = []
    var quantities: [String: Double] = [:]
    for line in input.lines {
      if line.productId.isEmpty || !(line.quantity != 0) { continue }
      if !(line.quantity > 0) { throw WriteFailure("Quantities must be positive.") }
      if quantities[line.productId] == nil { order.append(line.productId) }
      quantities[line.productId] = IwDecimal(quantities[line.productId] ?? 0).plus(IwDecimal(line.quantity)).toNumber()
    }
    if order.isEmpty { throw WriteFailure("Add at least one item with a quantity.") }
    var products: [JSONValue] = []
    for id in order {
      guard let product = ctx.get("products", id), product["companyId"]?.string == companyId,
        IwSources.isStockItem(product), !product.iwTruthy("archived")
      else { throw WriteFailure("Only stock items can be issued.") }
      products.append(product)
    }
    let stock = warehouseStock(ctx, warehouseId: warehouse.iwId)
    for (index, id) in order.enumerated() {
      let left = IwDecimal(stock[id] ?? 0).minus(IwDecimal(waiting[stockKey(warehouse.iwId, id)] ?? 0)).toNumber()
      if IwDecimal(quantities[id] ?? 0).gt(IwDecimal(left)) {
        throw WriteFailure(
          "Only {quantity} of {item} left in {warehouse} to issue.",
          [
            "quantity": WebJS.numberString(max(0, left)), "item": products[index].iwText("name"),
            "warehouse": warehouse.iwText("name"),
          ])
      }
    }
    let stamp = JSONValue.string(ctx.stamp)
    let issueId = ctx.newId()
    var lines: [JSONValue] = []
    for (index, id) in order.enumerated() {
      let product = products[index]
      var line: [String: JSONValue] = [
        "id": .string(ctx.shortId()),
        "productId": .string(id),
        "nameAr": WebJS.present(product["nameAr"]) ?? "",
        "quantity": .number(quantities[id] ?? 0),
      ]
      line["name"] = product["name"]
      line["unit"] = product["unit"]
      lines.append(.object(line))
    }
    let name = WebJS.trim(issuer.name)
    return .object([
      "id": .string(issueId),
      "companyId": .string(companyId),
      "number": "",
      "date": .string(input.date),
      "warehouseId": .string(warehouse.iwId),
      "recipient": .object([
        "employeeId": recipient["employeeId"] ?? .null,
        "number": .string(WebJS.trim(recipient.iwText("number"))),
        "name": .string(WebJS.trim(recipient.iwText("name"))),
        "nameAr": .string(recipient["nameAr"]?.string.map(WebJS.trim) ?? ""),
        "jobTitle": .string(WebJS.trim(recipient.iwText("jobTitle"))),
        "jobTitleAr": .string(recipient["jobTitleAr"]?.string.map(WebJS.trim) ?? ""),
      ]),
      "issuedBy": issuer.userId.map(JSONValue.string) ?? .null,
      "issuedByName": .string(WebJS.prefix(name, 200)),
      "requestId": .null,
      "approvedBy": .null,
      "approvedByName": "",
      "approvedAt": .null,
      "lines": .array(lines),
      "notes": .string(WebJS.trim(input.notes)),
      "status": "posted",
      "voidedAt": .null,
      "createdAt": stamp,
      "updatedAt": stamp,
    ])
  }

  /// `issueSummary(issue, arabic)`: "1 Trouser, 2 T-shirts".
  public static func issueSummary(_ issue: JSONValue, arabic: Bool = false) -> String {
    issue.iwList("lines").map { line in
      let arabicName = arabic ? (line["nameAr"]?.string ?? "") : ""
      let name = arabicName.isEmpty ? line.iwText("name") : arabicName
      return "\(WebJS.string(line["quantity"])) \(name)"
    }.joined(separator: arabic ? "، " : ", ")
  }

  /// `keepIssue(company, issue)`: numbered now, its stock leaves the
  /// warehouse and its cost is booked.
  @discardableResult
  static func keepIssue(_ ctx: WriteContext, _ company: JSONValue, _ issue: JSONValue) throws -> JSONValue {
    try IwAccounts.assertUnlocked(company, issue["date"])
    IwAccounts.ensureIssueAccounts(ctx, company)
    let taken = IwRecords.company(ctx, "stockIssues", company.iwId).map { $0.iwText("number") }
    let kept = issue.iwWith([
      "number": .string(InventoryWrites.nextNumber("ISS", taken)), "status": "posted", "updatedAt": .string(ctx.stamp),
    ])
    ctx.put("stockIssues", kept)
    try InventoryWrites.syncIssueStock(ctx, company, kept)
    let recipient = kept["recipient"]
    let name = recipient?["name"]?.string ?? ""
    let nameAr = recipient?["nameAr"]?.string ?? ""
    ctx.logActivity(
      entity: "stock", entityId: kept.iwId, action: "posted",
      message: ActivityMessage(
        "Items issued to {name}: {items}", vars: ["name": name, "items": issueSummary(kept)],
        arabic: ["name": nameAr.isEmpty ? name : nameAr, "items": issueSummary(kept, arabic: true)]))
    return kept
  }

  /// `issueStock(companyId, input, issuer)`: an approver (everyone in a
  /// company kept on this device) records the items at once; anyone else
  /// who may issue from the warehouse sends them for approval.
  @discardableResult
  public static func issueStock(_ ctx: WriteContext, _ input: Input, issuer: Issuer, link: Link?) throws
    -> (issue: JSONValue?, request: JSONValue?)
  {
    if !issuesOffered(link) {
      throw WriteFailure("Issuing items needs the latest database update. Ask the owner to run it.")
    }
    let approver = isApprover(link)
    let company = try InventoryWrites.theCompany(ctx)
    let warehouse = ctx.get("warehouses", input.warehouseId)
    if !issuesFrom(warehouse, link) {
      throw WriteFailure("You can only issue items from the sub-warehouse you look after.")
    }
    let waiting = waitingQuantities(waitingIssueRequests(ctx))
    let issue = try buildIssue(ctx, company, input, issuer, waiting: waiting)
    if approver {
      let kept = try keepIssue(
        ctx, company,
        issue.iwWith([
          "approvedBy": issuer.userId.map(JSONValue.string) ?? .null,
          "approvedByName": issue["issuedByName"] ?? "",
          "approvedAt": issue["createdAt"] ?? .null,
        ]))
      return (kept, nil)
    }
    let created = issue["createdAt"] ?? .null
    var fields: [String: JSONValue] = [
      "id": .string(ctx.newId()),
      "companyId": .string(ctx.companyId),
      "kind": "stock_issue",
      "subjectTbl": "stockIssues",
      "subjectId": issue["id"] ?? .null,
      // Numbered once confirmed.
      "subjectNumber": "",
      "before": .null,
      "after": issue,
      "reason": issue["notes"] ?? "",
      "status": "pending",
      // The cloud stamps both with its own.
      "requestedBy": .string(link?.userId ?? ""),
      "requestedAt": created,
      "decidedBy": .null,
      "decidedAt": .null,
      "decisionNote": "",
      "createdAt": created,
      "updatedAt": created,
    ]
    let issuedByName = issue.iwText("issuedByName")
    if !issuedByName.isEmpty { fields["requestedByName"] = .string(issuedByName) }
    let request = JSONValue.object(fields)
    ctx.put("approvals", request)
    let recipient = issue["recipient"]
    let name = recipient?["name"]?.string ?? ""
    let nameAr = recipient?["nameAr"]?.string ?? ""
    ctx.logActivity(
      entity: "stock", entityId: issue.iwId, action: "approval:asked",
      message: ActivityMessage(
        "Items to issue to {name} sent for approval: {items}", vars: ["name": name, "items": issueSummary(issue)],
        arabic: ["name": nameAr.isEmpty ? name : nameAr, "items": issueSummary(issue, arabic: true)]))
    return (nil, request)
  }

  // MARK: Requests confirmed

  /// `checkedRequest(request)`: the issue a request asks for, checked before
  /// it is kept; nil when it is kept already, by this request.
  static func checkedRequest(_ ctx: WriteContext, _ request: JSONValue) throws -> JSONValue? {
    guard let proposal = requestedIssue(request) else {
      throw WriteFailure("This version of the app can’t carry out this request.")
    }
    if let kept = ctx.get("stockIssues", request.iwText("subjectId")) {
      if kept["requestId"] == request["id"] { return nil }
      throw WriteFailure("These items are already on record under another request. Reject this one.")
    }
    let companyId = request["companyId"]?.string
    guard let warehouse = ctx.get("warehouses", proposal.iwText("warehouseId")),
      warehouse["companyId"]?.string == companyId
    else { throw WriteFailure("Choose the warehouse the items come from.") }
    let recipient = proposal["recipient"]
    if !WebJS.truthy(recipient?["employeeId"]) || WebJS.trim(WebJS.string(WebJS.present(recipient?["name"]) ?? "")).isEmpty {
      throw WriteFailure("Choose the employee who receives the items.")
    }
    let proposed = proposal.iwList("lines")
    if proposed.isEmpty { throw WriteFailure("Add at least one item with a quantity.") }
    var lines: [JSONValue] = []
    for (index, line) in proposed.enumerated() {
      let product = ctx.get("products", WebJS.string(line["productId"]))
      guard let product, product["companyId"]?.string == companyId, IwSources.isStockItem(product) else {
        throw WriteFailure("Only stock items can be issued.")
      }
      guard let quantity = line["quantity"]?.double, quantity.isFinite, quantity > 0 else {
        throw WriteFailure("Quantities must be positive.")
      }
      let lineId = line["id"]?.string ?? ""
      var checked: [String: JSONValue] = [
        "id": .string(lineId.isEmpty ? "line-\(index + 1)" : lineId),
        "nameAr": WebJS.present(product["nameAr"]) ?? "",
        "quantity": .number(quantity),
      ]
      checked["productId"] = product["id"]
      checked["name"] = product["name"]
      checked["unit"] = product["unit"]
      lines.append(.object(checked))
    }
    return proposal.iwWith("lines", .array(lines))
  }

  /// `issueRequestProblem(request)`: why an approver can't confirm it, or nil.
  public static func issueRequestProblem(_ ctx: WriteContext, _ request: JSONValue) -> WriteFailure? {
    do {
      _ = try checkedRequest(ctx, request)
      return nil
    } catch let failure as WriteFailure {
      return failure
    } catch {
      return nil
    }
  }

  /// `issueShortfall(request)`: what the warehouse no longer holds of what
  /// a request asks for, or nil (the approver may still confirm it).
  public static func issueShortfall(_ ctx: WriteContext, _ request: JSONValue) -> WriteFailure? {
    guard let issue = requestedIssue(request) else { return nil }
    let warehouseId = issue.iwText("warehouseId")
    let stock = warehouseStock(ctx, warehouseId: warehouseId)
    let warehouse = ctx.get("warehouses", warehouseId)
    let waiting = waitingQuantities(waitingIssueRequests(ctx), except: request["id"]?.string)
    for line in issue.iwList("lines") {
      let product = WebJS.string(line["productId"])
      let left = IwDecimal(stock[product] ?? 0).minus(IwDecimal(waiting[stockKey(warehouseId, product)] ?? 0))
        .toNumber()
      if IwDecimal(line["quantity"]).gt(IwDecimal(left)) {
        return WriteFailure(
          "{warehouse} has only {quantity} of {item} left.",
          [
            "warehouse": warehouse?.iwText("name") ?? "", "quantity": WebJS.numberString(max(0, left)),
            "item": line.iwText("name"),
          ])
      }
    }
    return nil
  }

  /// `applyStockIssueRequest(request)`: a confirmed request carried out on
  /// the approver's device, under the request's id for the issue. The
  /// issue's id.
  @discardableResult
  public static func applyStockIssueRequest(_ ctx: WriteContext, _ request: JSONValue) throws -> String {
    guard let issue = try checkedRequest(ctx, request) else { return request.iwText("subjectId") }
    guard let company = ctx.get("companies", request.iwText("companyId")) else {
      throw WriteFailure("Company not found")
    }
    let approverId = ctx.userId.flatMap { $0.isEmpty ? nil : $0 }
    let approverName = approverId == nil ? "" : WebJS.prefix(WebJS.trim(ctx.userName ?? ""), 200)
    let requestedBy = request["requestedBy"]
    let requestedByName = request["requestedByName"]
    try keepIssue(
      ctx, company,
      issue.iwWith([
        "issuedBy": WebJS.truthy(requestedBy) ? (requestedBy ?? .null) : (issue["issuedBy"] ?? .null),
        "issuedByName": WebJS.truthy(requestedByName) ? (requestedByName ?? .null) : (issue["issuedByName"] ?? .null),
        "requestId": request["id"] ?? .null,
        "approvedBy": WebJS.present(request["decidedBy"]) ?? approverId.map(JSONValue.string) ?? .null,
        "approvedByName": .string(approverName),
        "approvedAt": WebJS.present(request["decidedAt"]) ?? .string(ctx.stamp),
      ]))
    return request.iwText("subjectId")
  }

  /// `voidStockIssue(id)`: approvers only; the issue stays on record and its
  /// stock comes back to the warehouse.
  public static func voidStockIssue(_ ctx: WriteContext, id: String, link: Link?) throws {
    guard let issue = ctx.get("stockIssues", id), issue["status"]?.string != "void" else { return }
    if link != nil && !isApprover(link) { throw WriteFailure("Only an approver voids items issued.") }
    guard let company = ctx.get("companies", issue.iwText("companyId")) else { return }
    try IwAccounts.assertUnlocked(company, issue["date"])
    let stamp = JSONValue.string(ctx.stamp)
    let voided = issue.iwWith(["status": "void", "voidedAt": stamp, "updatedAt": stamp])
    ctx.put("stockIssues", voided)
    try InventoryWrites.syncIssueStock(ctx, company, voided)
    ctx.logActivity(
      entity: "stock", entityId: id, action: "void",
      message: ActivityMessage("Items issued {number} voided", vars: ["number": issue.iwText("number")]))
  }
}
