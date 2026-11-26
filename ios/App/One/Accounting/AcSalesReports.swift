import Foundation
import MahamKit

// The reports outside the ledger: aging, tax, sales by contact and payments
// (`src/lib/reports.ts`), statements of account and credit exposure
// (`src/lib/statements.ts`), retentions (`src/lib/retention.ts`) and stock
// levels (`src/lib/inventory/costing.ts`). Amounts in the company currency
// follow the web's own arithmetic: JavaScript numbers rounded to the
// currency, or minor units where the web works in them.

/// `round(a + b, p)` as the web writes it: the numbers added, then rounded to the currency.
func acRound(_ value: Double, _ p: Int) -> Double {
  Money.toNumber(Money.round(value, p))
}

// MARK: Aging, tax, sales and payments

struct AcAgingRow: Sendable {
  let clientId: String
  let clientName: String
  let buckets: [Double]
  let total: Double
}

struct AcAging: Sendable {
  let rows: [AcAgingRow]
  let totals: [Double]
  let total: Double
}

struct AcTaxRow: Sendable {
  let key: String
  let name: String
  let rate: Double
  var base: Double
  var tax: Double
}

struct AcTaxReport: Sendable {
  let rows: [AcTaxRow]
  let net: Double
  let tax: Double
  let gross: Double
  let documents: Int
}

struct AcContactSalesRow: Sendable {
  let clientId: String
  let clientName: String
  var invoices: Int
  var invoiced: Double
  var paid: Double
  var outstanding: Double
}

struct AcContactSales: Sendable {
  let rows: [AcContactSalesRow]
  let invoices: Int
  let invoiced: Double
  let paid: Double
  let outstanding: Double
}

struct AcPaymentsReport: Sendable {
  let list: [JSONValue]
  let byMethod: [(method: String, amount: Double)]
  let total: Double
}

enum AcReports {
  /// `AGING_BUCKETS`.
  static let agingBuckets = ["Current", "1–30 days", "31–60 days", "61–90 days", "90+ days"]

  /// The date range presets of the sales reports (`RANGE_PRESETS`).
  static let rangePresets: [(value: String, label: String)] = [
    ("this-month", "This month"), ("last-month", "Last month"), ("this-quarter", "This quarter"),
    ("last-quarter", "Last quarter"), ("this-year", "This year"), ("last-year", "Last year"), ("all", "All time"),
  ]

  static func counts(_ doc: JSONValue) -> Bool {
    let status = doc.str("status")
    return status != "draft" && status != "void"
  }

  /// Days past due to aging bucket.
  static func bucket(_ dueDate: String?, _ asOf: String) -> Int {
    let late = dueDate.map { AcDate.daysBetween($0, asOf) } ?? 0
    return late <= 0 ? 0 : late <= 30 ? 1 : late <= 60 ? 2 : late <= 90 ? 3 : 4
  }

  private static func names(_ clients: [JSONValue]) -> [String: String] {
    var out: [String: String] = [:]
    for client in clients { out[client.rid] = client.str("name") }
    return out
  }

  /// Stable sort, largest first.
  private static func largestFirst<T>(_ items: [T], _ value: (T) -> Double) -> [T] {
    items.enumerated().sorted { a, b in
      let x = value(a.element)
      let y = value(b.element)
      return x == y ? a.offset < b.offset : x > y
    }.map { $0.element }
  }

  /// `agingReport`: unpaid invoices (receivables) or bills (payables) by how late they are.
  static func aging(_ docs: [JSONValue], _ clients: [JSONValue], currency: String, asOf: String, type: String)
    -> AcAging
  {
    let p = Money.precision(currency)
    let names = AcReports.names(clients)
    var order: [String] = []
    var byClient: [String: [Double]] = [:]
    for doc in docs where doc.str("type") == type && doc.str("currency") == currency {
      let status = doc.str("status")
      guard status == "sent" || status == "partial" else { continue }
      let balance = doc.obj("totals")?.num("balance") ?? 0
      guard balance > 0 else { continue }
      let index = bucket(doc.text("dueDate"), asOf)
      let client = doc.str("clientId")
      if byClient[client] == nil { order.append(client) }
      var row = byClient[client] ?? [0, 0, 0, 0, 0]
      row[index] = acRound(row[index] + balance, p)
      byClient[client] = row
    }
    let rows = largestFirst(
      order.map { id -> AcAgingRow in
        let buckets = byClient[id] ?? [0, 0, 0, 0, 0]
        return AcAgingRow(
          clientId: id, clientName: names[id] ?? "—", buckets: buckets, total: acRound(buckets.reduce(0, +), p))
      }
    ) { $0.total }
    let totals = (0..<5).map { i in acRound(rows.reduce(0) { $0 + $1.buckets[i] }, p) }
    return AcAging(rows: rows, totals: totals, total: acRound(totals.reduce(0, +), p))
  }

  /// `taxReport`: tax on invoices issued in the range, less credit notes.
  static func tax(_ docs: [JSONValue], _ clients: [JSONValue], currency: String, range: AcRange) -> AcTaxReport {
    let p = Money.precision(currency)
    let exempt = Set(clients.filter { $0.flag("taxExempt") }.map(\.rid))
    var order: [String] = []
    var map: [String: AcTaxRow] = [:]
    var net = 0.0
    var tax = 0.0
    var gross = 0.0
    var documents = 0
    for doc in docs {
      let type = doc.str("type")
      guard type == "invoice" || type == "credit", doc.str("currency") == currency, counts(doc) else { continue }
      let issued = doc.str("issueDate")
      guard issued >= range.from, issued <= range.to else { continue }
      let sign = type == "credit" ? -1.0 : 1.0
      let taxExempt = doc.obj("posting").map { $0.flag("taxExempt") } ?? exempt.contains(doc.str("clientId"))
      let result = AcCalc.compute(doc, taxExempt: taxExempt)
      documents += 1
      net += sign * Money.toNumber(result.netTotal)
      tax += sign * Money.toNumber(result.taxTotal)
      gross += sign * Money.toNumber(result.total)
      for summary in result.taxes where summary.kind != "reverse_charge" {
        if map[summary.key] == nil { order.append(summary.key) }
        var row = map[summary.key] ?? AcTaxRow(key: summary.key, name: summary.name, rate: summary.rate, base: 0, tax: 0)
        row.base = acRound(row.base + sign * Money.toNumber(summary.base), p)
        row.tax = acRound(row.tax + sign * Money.toNumber(summary.amount), p)
        map[summary.key] = row
      }
    }
    let rows = order.compactMap { map[$0] }.enumerated().sorted { a, b in
      if a.element.rate != b.element.rate { return a.element.rate > b.element.rate }
      let names = AcText.compare(a.element.name, b.element.name)
      return names == .orderedSame ? a.offset < b.offset : names == .orderedAscending
    }.map { $0.element }
    return AcTaxReport(
      rows: rows, net: acRound(net, p), tax: acRound(tax, p), gross: acRound(gross, p), documents: documents)
  }

  /// `salesByClient`: invoices per client, or bills per vendor.
  static func byContact(
    _ docs: [JSONValue], _ clients: [JSONValue], currency: String, range: AcRange, type: String
  ) -> AcContactSales {
    let p = Money.precision(currency)
    let names = AcReports.names(clients)
    var order: [String] = []
    var map: [String: AcContactSalesRow] = [:]
    for doc in docs where doc.str("type") == type && doc.str("currency") == currency && counts(doc) {
      let issued = doc.str("issueDate")
      guard issued >= range.from, issued <= range.to else { continue }
      let client = doc.str("clientId")
      if map[client] == nil { order.append(client) }
      var row =
        map[client]
        ?? AcContactSalesRow(
          clientId: client, clientName: names[client] ?? "—", invoices: 0, invoiced: 0, paid: 0, outstanding: 0)
      let totals = doc.obj("totals")
      row.invoices += 1
      row.invoiced = acRound(row.invoiced + (totals?.num("total") ?? 0), p)
      row.paid = acRound(row.paid + (totals?.num("paid") ?? 0), p)
      row.outstanding = acRound(row.outstanding + max(0, totals?.num("balance") ?? 0), p)
      map[client] = row
    }
    let rows = largestFirst(order.compactMap { map[$0] }) { $0.invoiced }
    return AcContactSales(
      rows: rows, invoices: rows.reduce(0) { $0 + $1.invoices }, invoiced: acRound(rows.reduce(0) { $0 + $1.invoiced }, p),
      paid: acRound(rows.reduce(0) { $0 + $1.paid }, p), outstanding: acRound(rows.reduce(0) { $0 + $1.outstanding }, p))
  }

  /// `paymentsReport`: payments received (`in`) or made (`out`) in a period, by method.
  static func payments(_ payments: [JSONValue], currency: String, range: AcRange, out: Bool) -> AcPaymentsReport {
    let p = Money.precision(currency)
    let list = payments.filter { x in
      (x.str("direction") == "out") == out && !x.flag("voided") && x.str("currency") == currency
        && x.str("method") != "credit_note" && x.str("date") >= range.from && x.str("date") <= range.to
    }.enumerated().sorted { a, b in
      let x = a.element.str("date")
      let y = b.element.str("date")
      return x == y ? a.offset < b.offset : x > y
    }.map { $0.element }
    var order: [String] = []
    var byMethod: [String: Double] = [:]
    for x in list {
      let method = x.str("method")
      if byMethod[method] == nil { order.append(method) }
      byMethod[method] = acRound((byMethod[method] ?? 0) + x.num("amount"), p)
    }
    let methods = largestFirst(order.map { (method: $0, amount: byMethod[$0] ?? 0) }) { $0.amount }
    return AcPaymentsReport(list: list, byMethod: methods, total: acRound(list.reduce(0) { $0 + $1.num("amount") }, p))
  }

  /// `paymentMethodLabel`: an English key.
  static func methodLabel(_ method: String) -> String {
    switch method {
    case "bank_transfer": "Bank transfer"
    case "knet": "KNET"
    case "cash": "Cash"
    case "wamd": "WAMD"
    case "cheque": "Cheque"
    case "link": "Payment link"
    case "card": "Credit card"
    case "bnpl": "Buy now, pay later"
    case "cod": "Cash on delivery"
    case "credit_note": "Credit note"
    case "other": "Other"
    case "paypal": "PayPal"
    case "stripe": "Stripe"
    case "mobile_money": "Mobile money"
    default: method
    }
  }
}

// MARK: Statements of account

/// What a statement of account shows of a contact (`Statement`), minor units.
struct AcStatement: Sendable {
  let currency: String
  let precision: Int
  let opening: Int
  let closing: Int
  let debits: Int
  let credits: Int
  /// Open documents by days past due: current, 1–30, 31–60, 61–90, 90+.
  let buckets: [Int]
  let retentionHeld: Int
  let chequesTotal: Int
  let chequesCount: Int

  var overdue: Int { buckets.dropFirst().reduce(0, +) }
}

/// Where a customer stands today (`Exposure`), minor units.
struct AcExposure: Sendable {
  let balance: Int
  let overdue: Int
  let uncleared: Int
  let exposure: Int
  let limit: Int?
  let available: Int?
  let precision: Int
}

enum AcAccountStatements {
  static let start = "0000-01-01"

  /// `voidDate`: when a voided payment left the books.
  static func voidDate(_ payment: JSONValue) -> String {
    payment.text("voidedOn") ?? payment.obj("cheque")?.text("returnedOn") ?? payment.str("date")
  }

  static func voidedBy(_ payment: JSONValue, _ date: String) -> Bool {
    payment.flag("voided") && voidDate(payment) <= date
  }

  static func releasedOn(_ doc: JSONValue, _ asOf: String) -> Decimal {
    var sum = Decimal(0)
    for release in doc.list("retentionReleases") where release.str("date") <= asOf {
      if let undone = release.text("reversedOn"), undone <= asOf { continue }
      sum += Money.dec(release.num("amount"))
    }
    return sum
  }

  /// `STATEMENT_PERIODS`.
  static let periods: [(value: String, label: String)] = [
    ("this-month", "This month"), ("last-month", "Last month"), ("this-quarter", "This quarter"),
    ("this-year", "This year"), ("custom", "Custom"),
  ]

  /// `buildStatement`: the figures of one contact's statement for a period.
  static func build(
    customer: Bool, documents: [JSONValue], payments: [JSONValue], from: String, to: String, currency: String,
    companyCurrency: String? = nil, convert: Bool = false
  ) -> AcStatement {
    let p = Money.precision(currency)
    let charge = customer ? "invoice" : "bill"
    let creditType = customer ? "credit" : "vendor_credit"
    let direction = customer ? "in" : "out"
    let converting = convert && companyCurrency == currency
    func included(_ record: JSONValue) -> Bool { converting || record.str("currency") == currency }
    func minor(_ amount: Decimal, _ record: JSONValue) -> Int {
      let rate: Double
      if record.str("currency") == currency {
        rate = 1
      } else if let value = record.number("exchangeRate"), value > 0 {
        rate = value
      } else {
        rate = 1
      }
      return AcLedger.minor(amount * Money.dec(rate), p)
    }
    let docs = documents.filter {
      ($0.str("type") == charge || $0.str("type") == creditType) && AcReports.counts($0) && included($0)
    }
    let counting = payments.filter {
      ($0.str("direction") == "out" ? "out" : "in") == direction && $0.str("method") != "credit_note" && included($0)
    }
    var events: [(order: String, date: String, amount: Int)] = []
    for doc in docs {
      let isCharge = doc.str("type") == charge
      let totals = doc.obj("totals")
      let issued = doc.str("issueDate")
      let number = doc.str("number")
      events.append(
        ("\(issued)|0|\(isCharge ? 0 : 1)|\(number)|0", issued,
          (isCharge ? 1 : -1) * minor(Money.dec(totals?.num("total") ?? 0), doc)))
      let retention = totals?.num("retention") ?? 0
      if !isCharge || retention == 0 { continue }
      events.append(("\(issued)|0|0|\(number)|1", issued, -minor(Money.dec(retention), doc)))
      for release in doc.list("retentionReleases") {
        let value = minor(Money.dec(release.num("amount")), doc)
        let date = release.str("date")
        events.append(("\(date)|3|\(number)|\(release.rid)|0", date, value))
        if let undone = release.text("reversedOn") {
          events.append(("\(undone)|3|\(number)|\(release.rid)|1", undone, -value))
        }
      }
    }
    for pay in counting {
      let value = minor(Money.dec(pay.num("amount")), pay)
      events.append(("\(pay.str("date"))|1|\(pay.str("number"))|0", pay.str("date"), -value))
      if pay.flag("voided") {
        let date = voidDate(pay)
        events.append(("\(date)|2|\(pay.str("number"))|0", date, value))
      }
    }
    let ordered = events.enumerated().sorted { a, b in
      let order = AcText.compare(a.element.order, b.element.order)
      return order == .orderedSame ? a.offset < b.offset : order == .orderedAscending
    }.map { $0.element }
    var opening = 0
    for event in ordered where event.date < from { opening += event.amount }
    var balance = opening
    var debits = 0
    var credits = 0
    for event in ordered where event.date >= from && event.date <= to {
      balance += event.amount
      debits += customer ? max(event.amount, 0) : max(-event.amount, 0)
      credits += customer ? max(-event.amount, 0) : max(event.amount, 0)
    }

    // Aging on the statement date: what each document still owes.
    var applied: [String: Decimal] = [:]
    func apply(_ pay: JSONValue) {
      if pay.str("date") > to || voidedBy(pay, to) { return }
      for allocation in pay.list("allocations") {
        applied[allocation.str("documentId"), default: 0] += Money.dec(allocation.num("amount"))
      }
    }
    counting.forEach(apply)
    payments.filter { $0.str("method") == "credit_note" }.forEach(apply)
    var buckets = [0, 0, 0, 0, 0]
    var held = 0
    for doc in docs where doc.str("type") == charge && doc.str("issueDate") <= to {
      let totals = doc.obj("totals")
      let released = releasedOn(doc, to)
      let owed =
        Money.dec(totals?.num("total") ?? 0) - Money.dec(totals?.num("retention") ?? 0) + released
        - (applied[doc.rid] ?? 0)
      let open = minor(owed, doc)
      if open > 0 { buckets[AcReports.bucket(doc.text("dueDate"), to)] += open }
      let retention = totals?.num("retention") ?? 0
      if retention != 0 { held += minor(Money.dec(retention) - released, doc) }
    }

    // Cheques received (or issued) by the date that had not cleared by then.
    var chequesTotal = 0
    var chequesCount = 0
    for pay in counting {
      guard pay.str("method") == "cheque", let cheque = pay.obj("cheque") else { continue }
      if pay.str("date") > to || voidedBy(pay, to) { continue }
      if cheque.str("status") == "cleared", cheque.text("clearedOn").map({ $0 <= to }) ?? true { continue }
      chequesTotal += minor(Money.dec(pay.num("amount")), pay)
      chequesCount += 1
    }
    return AcStatement(
      currency: currency, precision: p, opening: opening, closing: balance, debits: debits, credits: credits,
      buckets: buckets, retentionHeld: held, chequesTotal: chequesTotal, chequesCount: chequesCount)
  }

  /// `contactPosition` of a customer: what they owe now and cheques not cleared.
  static func exposure(
    client: JSONValue, documents: [JSONValue], payments: [JSONValue], companyCurrency: String, today: String
  ) -> AcExposure {
    let p = Money.precision(companyCurrency)
    let statement = build(
      customer: true, documents: documents, payments: payments, from: start, to: today, currency: companyCurrency,
      companyCurrency: companyCurrency, convert: true)
    let exposure = max(0, statement.closing + statement.chequesTotal)
    let limit = client.number("creditLimit").flatMap { $0.isFinite ? AcLedger.minor($0, p) : nil }
    return AcExposure(
      balance: statement.closing, overdue: statement.overdue, uncleared: statement.chequesTotal, exposure: exposure,
      limit: limit, available: limit.map { $0 - exposure }, precision: p)
  }
}

// MARK: Retentions

enum AcRetentions {
  /// `heldRetention`: the retention less what was released, in the document currency.
  static func held(_ doc: JSONValue) -> Double {
    let p = Money.precision(doc.text("currency") ?? "KWD")
    let retention = Money.dec(doc.obj("totals")?.num("retention") ?? 0)
    return Money.toNumber(Money.round(retention - AcCalc.releasedRetention(doc), p))
  }

  /// `retentionKindLabel`.
  static func kindLabel(_ kind: String?) -> String {
    (kind ?? "tax") == "contract" ? "Contract retention" : "Tax retention"
  }

  /// `retentionStatus`.
  static func status(_ kind: String?, _ contact: JSONValue?, _ today: String) -> String {
    if (kind ?? "tax") == "contract" { return "awaiting_handover" }
    let certificates = contact?.list("clearanceCertificates") ?? []
    let valid = certificates.contains { certificate in
      guard let issued = certificate.text("issueDate"), issued <= today else { return false }
      return certificate.text("expiryDate").map { $0 >= today } ?? true
    }
    if valid { return "certificate" }
    return certificates.isEmpty ? "awaiting_certificate" : "expired"
  }

  /// `RETENTION_STATUS_META`.
  static func statusMeta(_ status: String) -> StatusMeta {
    switch status {
    case "certificate": StatusMeta(label: "Certificate on file", tone: .green)
    case "expired": StatusMeta(label: "Certificate expired", tone: .red)
    case "awaiting_certificate": StatusMeta(label: "Waiting for certificate", tone: .amber)
    case "awaiting_handover": StatusMeta(label: "Waiting for handover", tone: .blue)
    default: .unknown
    }
  }
}

// MARK: Stock

/// An item's stock (`StockLevel`).
struct AcStockLevel: Sendable {
  let quantity: Double
  /// Major units, to the currency's decimals.
  let value: Double
  /// Minor units.
  let valueMinor: Int
  let unitCost: Double
  let byWarehouse: [String: Double]
}

enum AcStock {
  /// `stockLevels`: every item's quantity and value, optionally as at the end of a day.
  static func levels(_ movements: [JSONValue], _ p: Int, asAt: String? = nil) -> [String: AcStockLevel] {
    var quantities: [String: Decimal] = [:]
    var values: [String: Int] = [:]
    var warehouses: [String: [String: Decimal]] = [:]
    for movement in movements {
      if let asAt, movement.str("date") > asAt { continue }
      let product = movement.str("productId")
      let quantity = Money.dec(movement.num("quantity"))
      quantities[product, default: 0] += quantity
      values[product, default: 0] += AcLedger.minor(movement.num("value"), p)
      warehouses[product, default: [:]][movement.str("warehouseId"), default: 0] += quantity
    }
    var result: [String: AcStockLevel] = [:]
    for (product, quantity) in quantities {
      let minor = values[product] ?? 0
      let value = Money.toNumber(Money.fromMinor(Int64(minor), p))
      var unitCost = 0.0
      if quantity > 0 {
        unitCost = Money.toNumber(Money.round(Money.fromMinor(Int64(minor), p) / quantity, 6))
      }
      var byWarehouse: [String: Double] = [:]
      for (warehouse, q) in warehouses[product] ?? [:] { byWarehouse[warehouse] = Money.toNumber(Money.round(q, 6)) }
      result[product] = AcStockLevel(
        quantity: Money.toNumber(Money.round(quantity, 6)), value: value, valueMinor: minor, unitCost: unitCost,
        byWarehouse: byWarehouse)
    }
    return result
  }

  /// `SOURCE_RANK`: the order of movements on the same day.
  static func rank(_ source: String) -> Int {
    switch source {
    case "opening": 0
    case "bill": 1
    case "landed_cost": 2
    case "credit": 3
    case "transfer": 4
    case "invoice": 5
    case "vendor_credit": 6
    case "issue": 7
    default: 8
    }
  }

  /// `compareMovements`.
  static func inOrder(_ a: JSONValue, _ b: JSONValue) -> Bool {
    if a.str("date") != b.str("date") { return a.str("date") < b.str("date") }
    let ra = rank(a.str("sourceType"))
    let rb = rank(b.str("sourceType"))
    if ra != rb { return ra < rb }
    if a.str("sequence") != b.str("sequence") { return a.str("sequence") < b.str("sequence") }
    return a.rid < b.rid
  }

  /// `MOVEMENT_LABELS`: an English key.
  static func movementLabel(_ source: String) -> String {
    switch source {
    case "opening": "Opening stock"
    case "bill": "Bill"
    case "landed_cost": "Landed cost"
    case "credit": "Credit note"
    case "transfer": "Stock transfer"
    case "invoice": "Invoice"
    case "vendor_credit": "Vendor credit"
    case "issue": "Items issued"
    case "adjustment": "Stock adjustment"
    default: source
    }
  }
}
