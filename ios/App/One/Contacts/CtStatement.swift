import Foundation
import MahamKit

// The port of the web's statements of account (`src/lib/statements.ts`):
// every invoice, credit note, payment, returned cheque and retention of one
// customer (or vendor) in a period, with the balance before it, a running
// balance and the balance after it, aged by due date; and where a contact
// stands today (`contactPosition`). Amounts are integer minor units of the
// statement's currency, so running balances are exact.

/// Whose statement: a customer's (what they owe) or a vendor's (what is owed to them).
enum CtSide: Sendable {
  case customer, vendor

  /// The documents that charge: invoices or bills.
  var charge: String { self == .customer ? "invoice" : "bill" }
  /// The documents that credit: credit notes or vendor credits.
  var creditType: String { self == .customer ? "credit" : "vendor_credit" }
  /// Payments that count: received from customers, made to vendors.
  var direction: String { self == .customer ? "in" : "out" }
}

/// One line of a statement.
struct CtEntry: Identifiable, Sendable {
  let id: String
  var order: String
  var date: String
  /// invoice, bill, opening, credit, vendor_credit, retention, release,
  /// release_undone, payment, payment_void
  var kind: String
  var number: String
  var reference = ""
  var dueDate: String?
  /// The change to what is owed (positive: owed more).
  var amount: Int64
  var debit: Int64 = 0
  var credit: Int64 = 0
  /// The balance after this line.
  var balance: Int64 = 0
  var documentId: String?
  var paymentId: String?
  var percent: Double?
  var chequeNumber: String?
  var chequeBank: String?
  var voided = false
  /// returned, cancelled or voided (payment reversals).
  var voidKind: String?

  init(_ id: String, order: String, date: String, kind: String, number: String, amount: Int64) {
    self.id = id
    self.order = order
    self.date = date
    self.kind = kind
    self.number = number
    self.amount = amount
  }
}

/// A cheque received (or issued) that had not cleared by the statement date.
struct CtChequeHeld: Identifiable, Sendable {
  let id: String
  let number: String
  let chequeNumber: String
  let bank: String
  let date: String
  let amount: Int64
  /// held or deposited.
  let status: String
}

/// A statement of account.
struct CtStatement: Sendable {
  var currency: String
  var precision: Int
  var from: String
  var to: String
  var opening: Int64 = 0
  var closing: Int64 = 0
  var entries: [CtEntry] = []
  var debits: Int64 = 0
  var credits: Int64 = 0
  /// Open documents by days past due: current, 1–30, 31–60, 61–90, 90+.
  var buckets: [Int64] = [0, 0, 0, 0, 0]
  /// Payments and credit notes not applied to a document yet.
  var unapplied: Int64 = 0
  var retentionHeld: Int64 = 0
  var cheques: [CtChequeHeld] = []
  var chequesTotal: Int64 = 0
  /// Documents in other currencies that this statement leaves out.
  var otherCurrencies: [String] = []

  init(currency: String, precision: Int, from: String, to: String) {
    self.currency = currency
    self.precision = precision
    self.from = from
    self.to = to
  }
}

/// The last payment of a contact, in company-currency minor units.
struct CtLastPayment: Sendable {
  let id: String
  let date: String
  let number: String
  let amount: Int64
}

/// Where a contact stands today, in the company currency (minor units).
struct CtPosition: Sendable {
  var balance: Int64 = 0
  var overdue: Int64 = 0
  var uncleared: Int64 = 0
  var unclearedCount = 0
  var exposure: Int64 = 0
  var retentionHeld: Int64 = 0
  var limit: Int64?
  var available: Int64?
  var lastPayment: CtLastPayment?
  var precision = 3
}

/// A statement period, `yyyy-MM-dd` to `yyyy-MM-dd`.
struct CtRange: Sendable, Equatable {
  let from: String
  let to: String
}

enum CtStatements {
  static let start = "0000-01-01"

  // MARK: Rules

  /// Documents that are part of the books (issued and not void).
  static func counted(_ doc: JSONValue) -> Bool {
    let status = doc.str("status")
    return status != "draft" && status != "void"
  }

  /// An opening-balance document made by the import.
  static func isOpening(_ doc: JSONValue) -> Bool {
    let items = doc.list("items")
    guard items.count == 1 else { return false }
    return items[0].str("name") == "Opening balance" && items[0].str("nameAr") == "رصيد افتتاحي"
  }

  /// When a voided payment left the books (return or cancellation date).
  static func voidDate(_ payment: JSONValue) -> String {
    if let date = payment.text("voidedOn") { return date }
    if let date = payment.obj("cheque")?.text("returnedOn") { return date }
    return payment.str("date")
  }

  /// A payment as it stood on a date: void only once the void happened.
  static func voidedBy(_ payment: JSONValue, _ date: String) -> Bool {
    payment.flag("voided") && voidDate(payment) <= date
  }

  /// Retention released by a date (and not undone by then).
  static func releasedOn(_ doc: JSONValue, _ asOf: String) -> Decimal {
    var released = Decimal(0)
    for release in doc.list("retentionReleases") {
      guard release.str("date") <= asOf else { continue }
      if let reversed = release.text("reversedOn"), reversed <= asOf { continue }
      released += Money.dec(release.num("amount"))
    }
    return released
  }

  static func paymentDirection(_ payment: JSONValue) -> String {
    payment.str("direction") == "out" ? "out" : "in"
  }

  /// Days past due to aging bucket: current, 1–30, 31–60, 61–90, 90+.
  static func agingBucket(_ dueDate: String?, _ asOf: String) -> Int {
    let late = dueDate.flatMap { ISODates.daysBetween($0, asOf) } ?? 0
    if late <= 0 { return 0 }
    if late <= 30 { return 1 }
    if late <= 60 { return 2 }
    if late <= 90 { return 3 }
    return 4
  }

  /// Company-currency value of one unit of the record's currency (1 when the same).
  static func rate(_ record: JSONValue, _ currency: String) -> Decimal {
    if record.str("currency") == currency { return 1 }
    let rate = record.num("exchangeRate")
    return rate > 0 ? Money.dec(rate) : 1
  }

  // MARK: The statement

  /// Builds the statement of one contact for a period (`buildStatement`).
  static func build(
    side: CtSide, documents: [JSONValue], payments: [JSONValue], from: String, to: String, currency: String,
    companyCurrency: String? = nil, convert: Bool = false
  ) -> CtStatement {
    let precision = Money.precision(currency)
    let converting = convert && companyCurrency == currency
    let included: (JSONValue) -> Bool = { converting || $0.str("currency") == currency }
    let minor: (Decimal, JSONValue) -> Int64 = { amount, record in
      Money.toMinor(amount * rate(record, currency), precision)
    }
    var statement = CtStatement(currency: currency, precision: precision, from: from, to: to)

    let docs = documents.filter { doc in
      let type = doc.str("type")
      return (type == side.charge || type == side.creditType) && counted(doc)
    }
    statement.otherCurrencies = Array(Set(docs.filter { !included($0) }.map { $0.str("currency") })).sorted()
    let shown = docs.filter(included)
    let counting = payments.filter { pay in
      paymentDirection(pay) == side.direction && pay.str("method") != "credit_note" && included(pay)
    }

    var events: [CtEntry] = []
    for doc in shown {
      events += documentEvents(doc, side: side, minor: minor)
    }
    for pay in counting {
      events += paymentEvents(pay, minor: minor)
    }
    events.sort { ctCollate($0.order, $1.order) == .orderedAscending }

    var opening: Int64 = 0
    for event in events where event.date < from { opening += event.amount }
    var balance = opening
    for var event in events where event.date >= from && event.date <= to {
      balance += event.amount
      let up = max(event.amount, 0)
      let down = max(-event.amount, 0)
      event.debit = side == .customer ? up : down
      event.credit = side == .customer ? down : up
      event.balance = balance
      statement.debits += event.debit
      statement.credits += event.credit
      statement.entries.append(event)
    }
    statement.opening = opening
    statement.closing = balance

    statement.buckets = aging(shown, counting: counting, all: payments, side: side, asOf: to, minor: minor)
    statement.unapplied = statement.buckets.reduce(0, +) - balance
    statement.retentionHeld = retentionHeld(shown, side: side, asOf: to, minor: minor)
    statement.cheques = chequesHeld(counting, asOf: to, minor: minor)
    statement.chequesTotal = statement.cheques.reduce(0) { $0 + $1.amount }
    return statement
  }

  /// A document's lines: itself, its retention, and the retention's releases.
  private static func documentEvents(
    _ doc: JSONValue, side: CtSide, minor: (Decimal, JSONValue) -> Int64
  ) -> [CtEntry] {
    let charge = doc.str("type") == side.charge
    let id = doc.rid
    let number = doc.str("number")
    let issued = doc.str("issueDate")
    let totals = doc.obj("totals")
    let value = minor(Money.dec(totals?.num("total") ?? 0), doc)
    let kind = charge ? (isOpening(doc) ? "opening" : side.charge) : side.creditType
    var entry = CtEntry(
      "doc-\(id)", order: "\(issued)|0|\(charge ? 0 : 1)|\(number)|0", date: issued, kind: kind, number: number,
      amount: charge ? value : -value)
    let reference = side == .vendor ? doc.str("vendorReference") : doc.str("poNumber")
    entry.reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
    entry.dueDate = charge ? doc.text("dueDate") : nil
    entry.documentId = id
    var events = [entry]
    let retention = totals?.num("retention") ?? 0
    guard charge, retention != 0 else { return events }

    var held = CtEntry(
      "ret-\(id)", order: "\(issued)|0|0|\(number)|1", date: issued, kind: "retention", number: number,
      amount: -minor(Money.dec(retention), doc))
    held.documentId = id
    held.percent = doc.number("retentionPercent")
    events.append(held)
    // Released parts become due again; undoing a release holds them back again.
    for release in doc.list("retentionReleases") {
      let released = minor(Money.dec(release.num("amount")), doc)
      let date = release.str("date")
      var line = CtEntry(
        "rel-\(release.rid)", order: "\(date)|3|\(number)|\(release.rid)|0", date: date, kind: "release",
        number: number, amount: released)
      line.reference = release.str("reference")
      line.documentId = id
      events.append(line)
      if let reversed = release.text("reversedOn") {
        var undone = CtEntry(
          "relx-\(release.rid)", order: "\(reversed)|3|\(number)|\(release.rid)|1", date: reversed,
          kind: "release_undone", number: number, amount: -released)
        undone.reference = release.str("reference")
        undone.documentId = id
        events.append(undone)
      }
    }
    return events
  }

  /// A payment's line, and its reversal when it was voided later.
  private static func paymentEvents(_ pay: JSONValue, minor: (Decimal, JSONValue) -> Int64) -> [CtEntry] {
    let value = minor(Money.dec(pay.num("amount")), pay)
    let cheque = pay.str("method") == "cheque" ? pay.obj("cheque") : nil
    let number = pay.str("number")
    let date = pay.str("date")
    let reference = cheque?.str("number") ?? pay.str("reference").trimmingCharacters(in: .whitespacesAndNewlines)
    var entry = CtEntry(
      "pay-\(pay.rid)", order: "\(date)|1|\(number)|0", date: date, kind: "payment", number: number,
      amount: -value)
    entry.reference = reference
    entry.paymentId = pay.rid
    entry.chequeNumber = cheque?.str("number")
    entry.chequeBank = cheque?.str("bank")
    entry.voided = pay.flag("voided")
    var events = [entry]
    guard pay.flag("voided") else { return events }
    let voided = voidDate(pay)
    var reversal = CtEntry(
      "void-\(pay.rid)", order: "\(voided)|2|\(number)|0", date: voided, kind: "payment_void", number: number,
      amount: value)
    reversal.reference = reference
    reversal.paymentId = pay.rid
    reversal.chequeNumber = cheque?.str("number")
    reversal.chequeBank = cheque?.str("bank")
    switch cheque?.str("status") {
    case "returned": reversal.voidKind = "returned"
    case "cancelled": reversal.voidKind = "cancelled"
    default: reversal.voidKind = "voided"
    }
    events.append(reversal)
    return events
  }

  /// What was still owed on each charge at `asOf`, by days past due.
  private static func aging(
    _ docs: [JSONValue], counting: [JSONValue], all: [JSONValue], side: CtSide, asOf: String,
    minor: (Decimal, JSONValue) -> Int64
  ) -> [Int64] {
    var applied: [String: Decimal] = [:]
    let apply: (JSONValue) -> Void = { pay in
      if pay.str("date") > asOf || voidedBy(pay, asOf) { return }
      for allocation in pay.list("allocations") {
        let id = allocation.str("documentId")
        applied[id] = (applied[id] ?? 0) + Money.dec(allocation.num("amount"))
      }
    }
    counting.forEach(apply)
    // Credit notes applied to invoices (they move no money).
    all.filter { $0.str("method") == "credit_note" }.forEach(apply)

    var buckets: [Int64] = [0, 0, 0, 0, 0]
    for doc in docs where doc.str("type") == side.charge && doc.str("issueDate") <= asOf {
      let totals = doc.obj("totals")
      let total = Money.dec(totals?.num("total") ?? 0)
      let retention = Money.dec(totals?.num("retention") ?? 0)
      let paid: Decimal = applied[doc.rid] ?? 0
      let owed: Decimal = total - retention + releasedOn(doc, asOf) - paid
      let value = minor(owed, doc)
      if value > 0 { buckets[agingBucket(doc.text("dueDate"), asOf)] += value }
    }
    return buckets
  }

  /// Retention held back on the statement date: not due yet, so not in the balance.
  private static func retentionHeld(
    _ docs: [JSONValue], side: CtSide, asOf: String, minor: (Decimal, JSONValue) -> Int64
  ) -> Int64 {
    var held: Int64 = 0
    for doc in docs where doc.str("type") == side.charge && doc.str("issueDate") <= asOf {
      let retention = doc.obj("totals")?.num("retention") ?? 0
      guard retention != 0 else { continue }
      held += minor(Money.dec(retention) - releasedOn(doc, asOf), doc)
    }
    return held
  }

  /// Cheques received (or issued) by the date that had not cleared by then.
  private static func chequesHeld(
    _ payments: [JSONValue], asOf: String, minor: (Decimal, JSONValue) -> Int64
  ) -> [CtChequeHeld] {
    var cheques: [CtChequeHeld] = []
    for pay in payments {
      guard pay.str("method") == "cheque", let cheque = pay.obj("cheque") else { continue }
      if pay.str("date") > asOf || voidedBy(pay, asOf) { continue }
      let status = cheque.str("status")
      if status == "cleared", (cheque.text("clearedOn").map { $0 <= asOf } ?? true) { continue }
      let depositedOn = cheque.text("depositedOn")
      let atBank = status == "deposited" || !CtCheques.isOpen(status)
      let deposited = atBank && (depositedOn.map { $0 <= asOf } ?? false)
      cheques.append(
        CtChequeHeld(
          id: pay.rid, number: pay.str("number"), chequeNumber: cheque.str("number"), bank: cheque.str("bank"),
          date: cheque.str("date"), amount: minor(Money.dec(pay.num("amount")), pay), status: deposited ? "deposited" : "held"))
    }
    cheques.sort { a, b in
      a.date != b.date ? a.date < b.date : ctCollate(a.chequeNumber, b.chequeNumber) == .orderedAscending
    }
    return cheques
  }

  // MARK: Where a contact stands

  /// What a contact owes (or is owed) today, overdue, cheques not cleared
  /// yet, retention held and, for customers, credit used (`contactPosition`).
  static func position(
    side: CtSide, contact: JSONValue, documents: [JSONValue], payments: [JSONValue], companyCurrency: String,
    today: String
  ) -> CtPosition {
    let precision = Money.precision(companyCurrency)
    let statement = build(
      side: side, documents: documents, payments: payments, from: start, to: today, currency: companyCurrency,
      companyCurrency: companyCurrency, convert: true)
    var position = CtPosition()
    position.precision = precision
    position.balance = statement.closing
    position.overdue = statement.buckets.dropFirst().reduce(0, +)
    position.uncleared = statement.chequesTotal
    position.unclearedCount = statement.cheques.count
    position.exposure = max(0, statement.closing + statement.chequesTotal)
    position.retentionHeld = statement.retentionHeld
    if side == .customer, let limit = contact.number("creditLimit"), limit.isFinite {
      let minorLimit = Money.toMinor(limit, precision)
      position.limit = minorLimit
      position.available = minorLimit - position.exposure
    }
    let paid = payments.filter { pay in
      paymentDirection(pay) == side.direction && pay.str("method") != "credit_note" && !pay.flag("voided")
    }
    .sorted { a, b in
      a.str("date") != b.str("date") ? a.str("date") > b.str("date") : a.str("createdAt") > b.str("createdAt")
    }
    if let last = paid.first {
      let rate = last.str("currency") == companyCurrency ? 0 : last.num("exchangeRate")
      let factor = rate > 0 ? Money.dec(rate) : Decimal(1)
      position.lastPayment = CtLastPayment(
        id: last.rid, date: last.str("date"), number: last.str("number"),
        amount: Money.toMinor(Money.dec(last.num("amount")) * factor, precision))
    }
    return position
  }

  // MARK: Periods

  /// The dates of a statement period (`presetRange`): this-month,
  /// last-month, this-quarter or this-year.
  static func range(_ period: String, today: String) -> CtRange {
    let parts = today.split(separator: "-").compactMap { Int($0) }
    let year = parts.first ?? 2026
    let month = parts.count > 1 ? parts[1] : 1
    switch period {
    case "last-month":
      return CtRange(from: firstOf(year, month - 1), to: ISODates.addDays(firstOf(year, month), -1))
    case "this-quarter":
      let first = (month - 1) / 3 * 3 + 1
      return CtRange(from: firstOf(year, first), to: ISODates.addDays(firstOf(year, first + 3), -1))
    case "this-year":
      return CtRange(from: "\(pad(year, 4))-01-01", to: "\(pad(year, 4))-12-31")
    default:
      return CtRange(from: firstOf(year, month), to: ISODates.addDays(firstOf(year, month + 1), -1))
    }
  }

  /// The first of a month, with months before January or after December
  /// moving the year.
  private static func firstOf(_ year: Int, _ month: Int) -> String {
    var y = year
    var m = month
    while m < 1 {
      m += 12
      y -= 1
    }
    while m > 12 {
      m -= 12
      y += 1
    }
    return "\(pad(y, 4))-\(pad(m, 2))-01"
  }

  private static func pad(_ value: Int, _ width: Int) -> String {
    let text = String(value)
    return String(repeating: "0", count: max(0, width - text.count)) + text
  }
}
