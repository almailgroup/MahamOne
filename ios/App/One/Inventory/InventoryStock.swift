import Foundation
import MahamKit

// The read side of the web's stock: `stockLevels` and `compareMovements`
// (src/lib/inventory/costing.ts), `isLowStock` and `onHand`
// (src/apps/books/features/inventory/use-inventory.ts), the labels
// (labels.ts) and the items issued (src/features/inventory/issues.ts,
// src/db/stock-issues.ts). Quantities, values and average costs are worked
// out from the movements as the web stored them (it costs them at the
// weighted average when it writes them); nothing here writes.

/// What an item is (`ProductKind`). Items saved before inventory existed
/// have none and are services (`productKind`).
enum InvKind: String, CaseIterable, Sendable {
  case service
  case nonStock = "non_stock"
  case stock

  /// `productKind(product)`.
  init(_ product: JSONValue?) {
    self = InvKind(rawValue: product?["kind"]?.string ?? "") ?? .service
  }

  /// `KIND_LABELS[kind].label`, translated.
  var label: String {
    switch self {
    case .service: t("Service")
    case .nonStock: t("Non-stock item")
    case .stock: t("Stock item")
    }
  }

  /// `KIND_LABELS[kind].plural`, translated.
  var plural: String {
    switch self {
    case .service: t("Services")
    case .nonStock: t("Non-stock items")
    case .stock: t("Stock items")
    }
  }

  /// `KIND_TONE`.
  var tone: StatusTone {
    switch self {
    case .service: .gray
    case .nonStock: .blue
    case .stock: .violet
    }
  }
}

/// One stock item's quantity and value, in total and per warehouse (`StockLevel`).
struct InvStockLevel: Sendable {
  /// On hand, to 6 decimals.
  var quantity: Double
  /// In the company currency.
  var value: Double
  /// The value in minor units (fils), exact.
  var valueMinor: Int64
  /// The weighted average cost of one unit; 0 when nothing is in stock.
  var unitCost: Double
  /// On hand per warehouse id, to 6 decimals.
  var byWarehouse: [String: Double]
}

enum InvStock {
  // MARK: Order

  /// `SOURCE_RANK`: on the same day stock comes in before it goes out;
  /// counts come last. Nil for a source this version doesn't know.
  static func rank(_ sourceType: String) -> Int? {
    switch sourceType {
    case "opening": 0
    case "bill": 1
    case "landed_cost": 2
    case "credit": 3
    case "transfer": 4
    case "invoice": 5
    case "vendor_credit": 6
    case "issue": 7
    case "adjustment": 8
    default: nil
    }
  }

  /// `compareMovements`: by date, then source, then the order recorded, then
  /// id. A source this version doesn't know ranks with any other, as the
  /// web's `NaN` does.
  static func compare(_ a: JSONValue, _ b: JSONValue) -> Int {
    let date = plain(a.str("date"), b.str("date"))
    if date != 0 { return date }
    if let ra = rank(a.str("sourceType")), let rb = rank(b.str("sourceType")), ra != rb {
      return ra < rb ? -1 : 1
    }
    let sequence = plain(a.str("sequence"), b.str("sequence"))
    if sequence != 0 { return sequence }
    return plain(a.rid, b.rid)
  }

  /// Sorts movements as `compareMovements` does.
  static func precedes(_ a: JSONValue, _ b: JSONValue) -> Bool {
    compare(a, b) < 0
  }

  /// JavaScript's `<` on strings: UTF-16 code units, no locale rules.
  static func plain(_ x: String, _ y: String) -> Int {
    if x.utf16.lexicographicallyPrecedes(y.utf16) { return -1 }
    if y.utf16.lexicographicallyPrecedes(x.utf16) { return 1 }
    return 0
  }

  // MARK: Levels

  /// What `stockLevels` adds up for one item.
  private struct Running {
    var quantity: Decimal = 0
    var value: Int64 = 0
    var byWarehouse: [String: Decimal] = [:]
  }

  /// `stockLevels(movements, precision, asAt)`: every item's quantity and
  /// value from its movements, optionally as at the end of a day. Values
  /// add up in minor units; quantities as decimals; the average cost is the
  /// value over the quantity, to 6 decimals, and 0 when none is in stock.
  static func levels(_ movements: [JSONValue], precision: Int, asAt: String? = nil) -> [String: InvStockLevel] {
    var totals: [String: Running] = [:]
    for movement in movements {
      if let asAt, !asAt.isEmpty, plain(movement.str("date"), asAt) > 0 { continue }
      let product = movement.str("productId")
      let quantity = Money.dec(movement.num("quantity"))
      var running = totals[product] ?? Running()
      running.quantity += quantity
      running.value += Money.toMinor(movement.num("value"), precision)
      running.byWarehouse[movement.str("warehouseId"), default: 0] += quantity
      totals[product] = running
    }
    var result: [String: InvStockLevel] = [:]
    for (product, running) in totals {
      result[product] = level(running, precision: precision)
    }
    return result
  }

  private static func level(_ running: Running, precision: Int) -> InvStockLevel {
    var byWarehouse: [String: Double] = [:]
    for (warehouse, quantity) in running.byWarehouse {
      byWarehouse[warehouse] = round6(quantity)
    }
    var unitCost: Double = 0
    if running.quantity > 0 {
      unitCost = unitCostOf(Decimal(running.value) / running.quantity, precision: precision)
    }
    return InvStockLevel(
      quantity: round6(running.quantity), value: Money.toNumber(Money.fromMinor(running.value, precision)),
      valueMinor: running.value, unitCost: unitCost, byWarehouse: byWarehouse)
  }

  /// `round6`: half away from zero at 6 decimals.
  private static func round6(_ value: Decimal) -> Double {
    Money.toNumber(Money.round(value, 6))
  }

  /// `unitCostOf(minorPerUnit, scale)`: minor units per unit as an amount
  /// of the currency, to 6 decimals (never -0).
  private static func unitCostOf(_ minorPerUnit: Decimal, precision: Int) -> Double {
    let scale = Decimal(sign: .plus, exponent: precision, significand: 1)
    let cost = Money.toNumber(Money.round(minorPerUnit / scale, 6))
    return cost == 0 ? 0 : cost
  }

  /// `isLowStock`: at or below the item's reorder level, when it has one.
  static func isLow(_ product: JSONValue, _ level: InvStockLevel?) -> Bool {
    guard let reorder = product["reorderLevel"]?.double else { return false }
    return (level?.quantity ?? 0) <= reorder
  }

  /// `onHand`: the quantity in one warehouse, or in all of them.
  static func onHand(_ level: InvStockLevel?, warehouse: String?) -> Double {
    guard let level else { return 0 }
    guard let warehouse, !warehouse.isEmpty else { return level.quantity }
    return level.byWarehouse[warehouse] ?? 0
  }

  /// `round(dec(quantity).times(dec(unitCost)), p)`: a quantity's value at
  /// the average cost.
  static func valueAt(_ quantity: Double, unitCost: Double, precision: Int) -> Double {
    Money.toNumber(Money.round(Money.dec(quantity) * Money.dec(unitCost), precision))
  }

  /// The sum of `toMinor(value)` over some movements, in minor units.
  static func minorSum(_ movements: [JSONValue], key: String = "value", precision: Int) -> Int64 {
    var sum: Int64 = 0
    for movement in movements {
      sum += Money.toMinor(movement.num(key), precision)
    }
    return sum
  }

  /// `fromMinor(minor, p)` as a number.
  static func amount(_ minor: Int64, precision: Int) -> Double {
    Money.toNumber(Money.fromMinor(minor, precision))
  }
}

// MARK: Labels

/// The words of `labels.ts`, translated, and where a movement came from.
enum InvLabels {
  /// `ENTRY_LABELS`: opening stock, adjustment or transfer.
  static func entryKind(_ kind: String) -> String {
    switch kind {
    case "opening": t("Opening stock")
    case "adjustment": t("Stock adjustment")
    case "transfer": t("Stock transfer")
    default: kind
    }
  }

  /// `REASON_LABELS`; nil for an entry without a reason.
  static func reason(_ reason: String?) -> String? {
    switch reason ?? "" {
    case "": nil
    case "damaged": t("Damaged")
    case "expired": t("Expired")
    case "count": t("Count difference")
    case "other": t("Other")
    default: reason
    }
  }

  /// `MOVEMENT_LABELS`: what moved the stock.
  static func movement(_ sourceType: String) -> String {
    switch sourceType {
    case "bill": t("Bill")
    case "vendor_credit": t("Vendor credit")
    case "invoice": t("Invoice")
    case "credit": t("Credit note")
    case "adjustment": t("Stock adjustment")
    case "opening": t("Opening stock")
    case "transfer": t("Stock transfer")
    case "landed_cost": t("Landed cost")
    case "issue": t("Items issued")
    default: sourceType
    }
  }

  /// `movementLink`: the page of what a movement came from.
  static func movementRoute(_ movement: JSONValue) -> Route {
    let id = movement.str("sourceId")
    switch movement.str("sourceType") {
    case "landed_cost": return .landedCost(id: id)
    case "issue": return .stockIssue(id: id)
    case "bill": return .purchaseDocument(.bill, id: id)
    case "vendor_credit": return .purchaseDocument(.vendorCredit, id: id)
    case "invoice": return .salesDocument(.invoice, id: id)
    case "credit": return .salesDocument(.credit, id: id)
    default: return .stockEntry(id: id)
    }
  }

  /// A stock entry's or landed cost's badge: Posted (or Allocated) and Void.
  static func postedBadge(_ status: String, allocated: Bool = false) -> StatusMeta {
    if status == "void" { return StatusMeta(label: "Void", tone: .gray) }
    return allocated ? StatusMeta(label: "Allocated", tone: .green) : StatusMeta(label: "Posted", tone: .green)
  }
}

// MARK: Items issued

/// Where an issue stands (`IssueState`): waiting for an approver, kept, or not kept.
enum InvIssueState: String, Sendable {
  case waiting, approved, posted, void, rejected, cancelled
  /// A request status this version doesn't know.
  case unknown

  /// `ISSUE_STATES`: the label (an English key) and tone.
  var meta: StatusMeta {
    switch self {
    case .waiting: StatusMeta(label: "Waiting for approval", tone: .amber)
    case .approved: StatusMeta(label: "Confirmed", tone: .blue)
    case .posted: StatusMeta(label: "Issued", tone: .green)
    case .void: StatusMeta(label: "Void", tone: .gray)
    case .rejected: StatusMeta(label: "Rejected", tone: .red)
    case .cancelled: StatusMeta(label: "Taken back", tone: .gray)
    case .unknown: .unknown
    }
  }

  /// Kept as a stock issue (not only asked for).
  var isKept: Bool { self == .posted || self == .void }
}

/// An issue as the lists show it (`IssueRow`): one kept, or one asked for.
struct InvIssueRow: Identifiable, Sendable {
  /// The issue's id (a request's is the issue it would make).
  let id: String
  let issue: JSONValue
  let request: JSONValue?
  let state: InvIssueState
}

enum InvIssues {
  /// `isStockIssueRequest`.
  static func isRequest(_ request: JSONValue?) -> Bool {
    request?.str("kind") == "stock_issue" && request?.str("subjectTbl") == "stockIssues"
  }

  /// `requestedIssue`: the issue a request carries, as it was sent, or nil.
  static func requestedIssue(_ request: JSONValue) -> JSONValue? {
    guard isRequest(request), var after = request.obj("after") else { return nil }
    guard after["warehouseId"]?.string != nil, SyncJSON.truthy(after["recipient"]), after["lines"]?.array != nil
    else { return nil }
    after.set("id", .string(request.str("subjectId")))
    after.set("companyId", .string(request.str("companyId")))
    return after
  }

  /// `useIssueRows`: the items issued and the requests to issue them,
  /// newest first; a request that was carried out shows as the issue it
  /// made. With `employee`, only theirs.
  static func rows(issues: [JSONValue], requests: [JSONValue], employee: String? = nil) -> [InvIssueRow] {
    let mine = issues.filter { employee == nil || $0.obj("recipient")?.str("employeeId") == employee }
    let kept = Set(mine.map(\.rid))
    var bySubject: [String: JSONValue] = [:]
    for request in requests where request.str("kind") == "stock_issue" {
      bySubject[request.str("subjectId")] = request
    }
    var rows: [InvIssueRow] = []
    for issue in mine {
      rows.append(
        InvIssueRow(
          id: issue.rid, issue: issue, request: bySubject[issue.rid],
          state: issue.str("status") == "void" ? .void : .posted))
    }
    for request in requests where isRequest(request) && !kept.contains(request.str("subjectId")) {
      guard let issue = requestedIssue(request) else { continue }
      if let employee, issue.obj("recipient")?.str("employeeId") != employee { continue }
      rows.append(InvIssueRow(id: issue.rid, issue: issue, request: request, state: state(of: request)))
    }
    return rows.sorted(by: newestFirst)
  }

  /// A request's state: pending is waiting; approved and applied are confirmed.
  static func state(of request: JSONValue) -> InvIssueState {
    switch request.str("status") {
    case "pending": .waiting
    case "approved", "applied": .approved
    case "rejected": .rejected
    case "cancelled": .cancelled
    default: .unknown
    }
  }

  /// By date, then when it was made, newest first.
  private static func newestFirst(_ a: InvIssueRow, _ b: InvIssueRow) -> Bool {
    let date = InvStock.plain(b.issue.str("date"), a.issue.str("date"))
    if date != 0 { return date < 0 }
    return InvStock.plain(b.issue.str("createdAt"), a.issue.str("createdAt")) < 0
  }

  /// The issues page's filter (`matches`).
  static func matches(_ row: InvIssueRow, _ show: String) -> Bool {
    switch show {
    case "waiting": row.state == .waiting || row.state == .approved
    case "issued": row.state == .posted
    case "other": row.state == .void || row.state == .rejected || row.state == .cancelled
    default: true
    }
  }

  /// `issueSummary`: "2 Shirt, 1 Trousers" (in Arabic, the Arabic names and "، ").
  static func summary(_ issue: JSONValue, arabic: Bool) -> String {
    let parts = issue.list("lines").map { line in
      "\(Money.jsString(line.num("quantity"))) \(lineName(line, arabic: arabic))"
    }
    return parts.joined(separator: arabic ? "، " : ", ")
  }

  /// `(ar && line.nameAr) || line.name`.
  static func lineName(_ line: JSONValue, arabic: Bool) -> String {
    if arabic, let nameAr = line.text("nameAr") { return nameAr }
    return line.str("name")
  }

  /// `recipientLabel`: the name in the interface language, with the job title.
  static func recipientLabel(_ recipient: JSONValue?, arabic: Bool) -> String {
    let name = (arabic ? recipient?.text("nameAr") : nil) ?? recipient?.str("name") ?? ""
    let title = (arabic ? recipient?.text("jobTitleAr") : nil) ?? recipient?.str("jobTitle") ?? ""
    return title.isEmpty ? name : "\(name) (\(title))"
  }

  /// `STATUS_META` of an approval request.
  static func requestMeta(_ status: String) -> StatusMeta {
    switch status {
    case "pending": StatusMeta(label: "Waiting for approval", tone: .amber)
    case "approved": StatusMeta(label: "Approved", tone: .blue)
    case "rejected": StatusMeta(label: "Rejected", tone: .red)
    case "cancelled": StatusMeta(label: "Cancelled", tone: .gray)
    case "applied": StatusMeta(label: "Approved and done", tone: .green)
    default: StatusMeta(label: "Approval request", tone: .gray)
    }
  }
}
