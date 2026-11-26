import MahamKit
import SwiftUI

// Payments received and payments made (`src/apps/books/pages/payments/list.tsx`,
// `detail.tsx`): one `payments` table, `direction: "out"` for money paid to
// vendors, anything else received from clients.

/// The wording of the payment pages for each direction (`PAYMENT_COPY`).
struct CtPaymentCopy {
  let direction: PaymentDirection

  var out: Bool { direction == .made }
  var title: String { out ? t("Payments made") : t("Payments received") }
  var description: String {
    out ? t("Money paid to vendors and vendor credits applied.") : t("Money received and credit notes applied.")
  }
  var party: String { out ? t("Vendor") : t("Client") }
  var credit: String { out ? t("Vendor credit") : t("Credit note") }
  var account: String { out ? t("Paid from") : t("Deposit to") }
  var total: String { out ? t("Total paid") : t("Total received") }
  var empty: String {
    out
      ? t("Record what you pay vendors to keep bill balances up to date.")
      : t("Record payments as they arrive to keep invoice balances up to date.")
  }
  var notApplied: String { out ? t("Not applied to any bill.") : t("Not applied to any invoice.") }
  var deletedDoc: String { out ? t("Deleted bill") : t("Deleted invoice") }
  var unapplied: String { out ? t("Unapplied (advance to the vendor)") : t("Unapplied (client credit)") }
  var openParty: String { out ? t("Open vendor") : t("Open client") }
  var contactKind: ContactKind { out ? .vendor : .customer }

  /// "KD 400.000 from Blue Harbour Cafe", or from an unknown client.
  func from(amount: String, name: String?) -> String {
    guard let name, !name.isEmpty else {
      return out
        ? t("{amount} to an unknown vendor", ["amount": amount])
        : t("{amount} from an unknown client", ["amount": amount])
    }
    return out
      ? t("{amount} to {name}", ["amount": amount, "name": name])
      : t("{amount} from {name}", ["amount": amount, "name": name])
  }
}

// MARK: The list

/// `/payments`, `/payments-made`: a method filter, search, one row per
/// payment (newest first) and the totals.
struct CtPaymentListPage: View {
  let direction: PaymentDirection
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let copy = CtPaymentCopy(direction: direction)
    let one = model.one
    let format = one.format
    let payments = self.payments
    let numbers = documentNumbers
    CtListPage(
      title: copy.title, description: copy.description, records: payments.map(Rec.init),
      filter: .select(methodOptions(payments)), initial: "",
      matches: { record, method in method.isEmpty || record.raw.str("method") == method },
      searchPlaceholder: t("Search payments…"),
      searchText: { CtPaymentListPage.searchText($0.raw, one: one, numbers: numbers) },
      newLabel: t("Record payment"), onNew: { router.push(.newPayment(direction)) },
      emptyIcon: .creditCard, emptyTitle: t("No payments yet"), emptyDescription: copy.empty,
      noMatch: t("No payments match.")
    ) { record in
      CtPaymentRow(payment: record.raw, format: format, direction: direction, numbers: numbers)
    } footer: { visible in
      CtPaymentFooter(payments: visible.map(\.raw), format: format, label: copy.total)
    }
  }

  /// This direction's payments, newest first: by date, then number.
  private var payments: [JSONValue] {
    let out = direction == .made
    return model.one.records(.payments)
      .filter { CtPayments.isOut($0) == out }
      .sorted { a, b in
        let (da, db) = (a.str("date"), b.str("date"))
        if da != db { return da > db }
        return ctNumeric(a.str("number"), b.str("number")) == .orderedDescending
      }
  }

  /// Document numbers by id, for the "applied to" line and the search.
  private var documentNumbers: [String: String] {
    var numbers: [String: String] = [:]
    for doc in model.one.records(.documents) { numbers[doc.rid] = doc.str("number") }
    return numbers
  }

  /// "All methods", the methods offered now, then older ones still in use.
  private func methodOptions(_ payments: [JSONValue]) -> [SelectOption<String>] {
    let offered = CtPayments.offered(direction)
    var methods = offered
    for payment in payments {
      let method = payment.str("method")
      if !method.isEmpty, !methods.contains(method) { methods.append(method) }
    }
    return [SelectOption("", t("All methods"))] + methods.map { SelectOption($0, CtPayments.methodLabel($0)) }
  }

  /// Number, contact, reference, cheque number and the documents it paid.
  static func searchText(_ payment: JSONValue, one: OneData, numbers: [String: String]) -> String {
    let contact = one.record(.clients, payment.str("clientId"))
    let invoices = payment.list("documentIds").compactMap { $0.string.flatMap { numbers[$0] } }
    return [
      payment.str("number"), contact?.str("name") ?? "", contact?.str("nameAr") ?? "", payment.str("reference"),
      payment.obj("cheque")?.str("number") ?? "", invoices.joined(separator: " "),
    ].joined(separator: " ")
  }
}

/// A payment in the list: the contact; "number · date"; the method, cheque
/// or reference and what it paid; the amount, its cheque's status (or what
/// is not applied yet).
struct CtPaymentRow: View {
  let payment: JSONValue
  let format: CompanyFormat
  let direction: PaymentDirection
  let numbers: [String: String]
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let name = model.one.contactName(payment.text("clientId"))
    let currency = payment.text("currency")
    let unapplied = payment.flag("voided") ? 0 : CtPayments.unapplied(payment)
    let status = CtPayments.status(payment)
    CtListRow(
      title: name.isEmpty ? "—" : name,
      subtitle: "\(payment.str("number")) · \(format.date(payment.text("date")))",
      detail: detail,
      amount: format.money(payment.num("amount"), currency), amountMuted: payment.flag("voided")
    ) {
      if let status {
        Badge(status: status)
      } else if unapplied > 0 {
        Badge(t("{amount} unapplied", ["amount": format.money(unapplied, currency)]), tone: .amber)
      }
    } action: {
      router.push(.payment(direction, id: payment.rid))
    }
  }

  private var detail: String {
    var parts = [CtPayments.methodLabel(payment.str("method"))]
    if let number = payment.obj("cheque")?.text("number") {
      parts.append(t("Cheque {number}", ["number": number]))
    } else if let reference = payment.text("reference") {
      parts.append(reference)
    }
    let invoices = payment.list("documentIds").compactMap { $0.string.flatMap { numbers[$0] } }
    if !invoices.isEmpty { parts.append(invoices.joined(separator: ", ")) }
    return parts.joined(separator: " · ")
  }
}

/// Under the list: how many, and the total per currency (credit notes and
/// void payments left out).
struct CtPaymentFooter: View {
  let payments: [JSONValue]
  let format: CompanyFormat
  let label: String
  @Environment(\.palette) private var palette

  var body: some View {
    Text(tp(payments.count, "{count} payment", "{count} payments"))
    ForEach(totals) { sum in
      HStack(spacing: 4) {
        Text(label)
        Text(format.money(sum.total, sum.currency))
          .foregroundStyle(palette.slate(900))
          .fontWeight(.semibold)
          .environment(\.layoutDirection, .leftToRight)
      }
    }
  }

  private var totals: [CurrencyTotal] {
    var sums: [String: Decimal] = [:]
    var order: [String] = []
    for payment in payments where payment.str("method") != "credit_note" && !payment.flag("voided") {
      let currency = payment.text("currency") ?? format.currency
      if sums[currency] == nil { order.append(currency) }
      sums[currency, default: 0] += Money.dec(payment.num("amount"))
    }
    return order.map { currency in
      let rounded = Money.round(sums[currency] ?? 0, Money.precision(currency))
      return CurrencyTotal(currency: currency, total: Money.toNumber(rounded), balance: 0)
    }
  }
}

// MARK: A payment

/// `/payments/:id`, `/payments-made/:id`: the amount and who paid (or was
/// paid), a void payment's reason, the details, the cheque, what it was
/// applied to and its files.
struct CtPaymentPage: View {
  let direction: PaymentDirection
  let id: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let one = model.one
    let payment = one.record(.payments, id)
    // Links that only know "a payment" land on the right page.
    let shown = payment.map { CtPayments.direction($0) } ?? direction
    let copy = CtPaymentCopy(direction: shown)
    let status = payment.flatMap { CtPayments.status($0) }
    let clientId = payment?.text("clientId")
    let hasContact = clientId.flatMap { one.record(.clients, $0) } != nil
    RecordDetailPage(
      record: payment, title: t("Payment {number}", ["number": payment?.str("number") ?? ""]),
      subtitle: payment.map { subtitle($0, copy: copy) }, breadcrumb: copy.title
    ) {
      if let status { Badge(status: status) }
    } actions: {
      if let clientId, hasContact {
        WebButton(copy.openParty, icon: .userRound, variant: .outline, size: .sm) {
          router.push(.contact(copy.contactKind, id: clientId))
        }
      }
      if let payment, !payment.flag("voided") {
        WebButton(t("Edit"), icon: .pencil, variant: .outline, size: .sm) {
          router.push(.editPayment(shown, id: payment.rid))
        }
      }
    } content: {
      if let payment {
        CtPaymentBody(payment: payment, direction: shown)
      }
    }
  }

  private func subtitle(_ payment: JSONValue, copy: CtPaymentCopy) -> String {
    let format = model.one.format
    let amount = format.money(payment.num("amount"), payment.text("currency"))
    return copy.from(amount: amount, name: model.one.contactName(payment.text("clientId")))
  }
}

/// The cards of a payment's page.
struct CtPaymentBody: View {
  let payment: JSONValue
  let direction: PaymentDirection
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let copy = CtPaymentCopy(direction: direction)
    let format = model.one.format
    let status = CtPayments.status(payment)
    if payment.flag("voided") {
      CtNote(
        .danger,
        title: t("This payment is void: {reason}", ["reason": payment.text("voidReason") ?? t("Voided")]),
        lines: voidLines)
    }
    CtInfoCard(t("Details"), rows: detailRows(copy: copy, format: format))
    if payment.obj("cheque") != nil {
      CtInfoCard(t("Cheque"), rows: chequeRows(format: format)) {
        if let status { Badge(status: status) }
      }
    }
    CtRowsCard(t("Applied to")) {
      if payment.list("allocations").isEmpty {
        CtEmptyText(copy.notApplied)
      } else {
        ForEach(Array(payment.list("allocations").enumerated()), id: \.offset) { _, allocation in
          allocationRow(allocation, copy: copy, format: format)
        }
      }
    }
    CtRowsCard(t("Attachments"), description: t("A scan of the cheque or the transfer receipt.")) {
      if files.isEmpty {
        CtEmptyText(t("No files attached."))
      } else {
        ForEach(files.map(Rec.init)) { record in
          let size = ctFileSize(record.raw.num("size"))
          ListRow(
            title: record.raw.text("name") ?? t("File"), subtitle: size.isEmpty ? nil : size,
            leading: { IconView(.paperclip, size: 16).foregroundStyle(palette.slate(400)) }, status: { EmptyView() })
        }
      }
    }
  }

  private var money: (Double) -> String {
    let format = model.one.format
    let currency = payment.text("currency")
    return { format.money($0, currency) }
  }

  private var files: [JSONValue] {
    let id = payment.rid
    return model.one.records(.attachments).filter { $0.str("ownerId") == id }
  }

  private var voidLines: [String] {
    var lines = [t("It no longer counts in the books or against the documents it paid.")]
    if let other = payment.obj("cheque")?.text("replacedById"), let replacement = model.one.record(.payments, other) {
      lines.append(t("Replaced by payment {payment}.", ["payment": replacement.str("number")]))
    }
    return lines
  }

  /// The account the money went into (or came from), as the ledger picks it:
  /// the one stored, else cash or bank by the method.
  private var account: JSONValue? {
    let accounts = model.one.records(.accounts)
    let method = payment.str("method")
    let role = method == "cash" || method == "cod" ? "cash" : "bank"
    if let id = payment.text("accountId"), let stored = accounts.first(where: { $0.rid == id }) { return stored }
    return accounts.first { $0.str("role") == role } ?? accounts.first { $0.str("role") == "bank" }
  }

  private func detailRows(copy: CtPaymentCopy, format: CompanyFormat) -> [CtRow] {
    let one = model.one
    let money = self.money
    var rows: [CtRow] = []
    rows.append(CtRow(t("Amount"), money(payment.num("amount")), strong: true, tabular: true))
    rows.append(CtRow(t("Date"), format.date(payment.text("date"))))
    rows.append(CtRow(t("Method"), CtPayments.methodLabel(payment.str("method"))))
    if let provider = payment.text("provider") {
      rows.append(CtRow(t("Provider"), CtPayments.providerLabel(provider)))
    }
    let fee = payment.num("fee")
    if fee != 0 {
      let feeAccount = payment.text("feeAccountId").flatMap { one.record(.accounts, $0) }
      rows.append(CtRow(t("Fee"), "\(money(fee)) (\(ctAccountLabel(feeAccount)))", tabular: true))
    }
    if payment.str("method") != "credit_note" {
      let label = payment.obj("cheque") != nil ? t("Held in") : copy.account
      rows.append(CtRow(label, ctAccountLabel(account)))
    }
    rows.append(CtRow(t("Reference"), payment.str("reference")))
    if let creditId = payment.text("creditId"), let credit = one.record(.documents, creditId) {
      let route = DocType(rawValue: credit.str("type")).map { $0.route(credit.rid) }
      rows.append(CtRow(copy.credit, credit.str("number"), route: route))
    }
    let unapplied = payment.flag("voided") ? 0 : CtPayments.unapplied(payment)
    if unapplied > 0 {
      rows.append(CtRow(copy.unapplied, money(unapplied), tabular: true, tone: .amber(700)))
    }
    rows.append(CtRow(t("Notes"), payment.str("notes"), multiline: true))
    return rows
  }

  private func chequeRows(format: CompanyFormat) -> [CtRow] {
    guard let cheque = payment.obj("cheque") else { return [] }
    let one = model.one
    var rows: [CtRow] = []
    rows.append(CtRow(t("Cheque number"), cheque.str("number")))
    rows.append(CtRow(t("Bank"), CtCheques.bankName(cheque.str("bank"))))
    rows.append(CtRow(t("Cheque date"), format.date(cheque.text("date"))))
    rows.append(CtRow(direction == .made ? t("Pay to") : t("Drawer"), cheque.str("drawer")))
    rows.append(CtRow(t("Civil ID"), cheque.str("drawerCivilId")))
    if let printed = cheque.text("printedAt") {
      let crossed = cheque.flag("crossed") ? " · \(t("A/C payee only"))" : ""
      rows.append(CtRow(t("Printed on"), format.dateTime(printed) + crossed))
    }
    let spoiled = cheque.list("spoiledLeaves").map { $0.str("number") }.filter { !$0.isEmpty }
    rows.append(CtRow(t("Spoiled leaves"), spoiled.joined(separator: ", ")))
    rows.append(CtRow(t("Deposited on"), format.date(cheque.text("depositedOn"))))
    if let cleared = cheque.text("clearedOn") {
      let bank = cheque.text("bankAccountId").flatMap { one.record(.accounts, $0) }
      rows.append(CtRow(t("Cleared on"), "\(format.date(cleared)) · \(ctAccountLabel(bank))"))
    }
    if let returned = cheque.text("returnedOn") {
      rows.append(CtRow(t("Returned on"), "\(format.date(returned)) · \(cheque.str("returnReason"))"))
    }
    if let journal = cheque.text("clearingJournalId") {
      rows.append(CtRow(t("Clearing entry"), t("View entry"), route: .journal(id: journal)))
    }
    if let other = linked(cheque.text("replacesId")) { rows.append(linkRow(t("Replaces"), other)) }
    if let other = linked(cheque.text("replacedById")) { rows.append(linkRow(t("Replaced by"), other)) }
    return rows
  }

  private func linked(_ id: String?) -> JSONValue? {
    id.flatMap { model.one.record(.payments, $0) }
  }

  /// "Cheque 100482 · PAY-0051", opening that payment.
  private func linkRow(_ label: String, _ other: JSONValue) -> CtRow {
    let cheque = t("Cheque {number}", ["number": other.obj("cheque")?.str("number") ?? ""])
    return CtRow(
      label, "\(cheque) · \(other.str("number"))", route: .payment(CtPayments.direction(other), id: other.rid))
  }

  private func allocationRow(_ allocation: JSONValue, copy: CtPaymentCopy, format: CompanyFormat) -> some View {
    let doc = model.one.record(.documents, allocation.str("documentId"))
    let route = doc.flatMap { found in DocType(rawValue: found.str("type")).map { $0.route(found.rid) } }
    return ListRow(
      title: doc?.text("number") ?? copy.deletedDoc,
      subtitle: doc.map { format.date($0.text("issueDate")) },
      amount: money(allocation.num("amount")),
      action: opening(route))
  }

  private func opening(_ route: Route?) -> (() -> Void)? {
    guard let route else { return nil }
    return { router.push(route) }
  }
}
