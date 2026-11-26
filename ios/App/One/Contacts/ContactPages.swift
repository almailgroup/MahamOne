import MahamKit
import SwiftUI

// Clients and vendors (`src/apps/books/pages/clients/list.tsx`,
// `detail.tsx`): one `clients` table, where `isCustomer` (missing means yes)
// puts a contact under Clients and `isVendor` under Vendors.

/// The wording and rules of each kind of contact (`CONTACT_COPY`).
struct CtContactCopy {
  let kind: ContactKind

  var vendor: Bool { kind == .vendor }
  var title: String { vendor ? t("Vendors") : t("Clients") }
  var description: String { vendor ? t("The suppliers you buy from.") : t("The people and companies you bill.") }
  var newLabel: String { vendor ? t("New vendor") : t("New client") }
  var emptyTitle: String { vendor ? t("No vendors yet") : t("No clients yet") }
  var empty: String {
    vendor
      ? t("Add the suppliers you buy from to record their bills and what you pay them.")
      : t("Add the people and companies you work with to invoice them in seconds.")
  }
  var search: String { vendor ? t("Search vendors…") : t("Search clients…") }
  var noMatch: String { vendor ? t("No vendors match.") : t("No clients match.") }
  var owedLabel: String { vendor ? t("You owe") : t("Outstanding") }
  var alsoOther: String { vendor ? t("Also a client") : t("Also a vendor") }
  var icon: Icon { vendor ? .truck : .users }
  /// The document that counts towards the balance: invoices or bills.
  var docType: String { vendor ? "bill" : "invoice" }
  /// The documents listed on the contact, in this order (`DOC_TYPES`).
  var docTypes: [DocType] {
    vendor ? [.bill, .vendorCredit, .purchaseOrder] : [.invoice, .quote, .credit, .proforma, .salesOrder, .deliveryNote]
  }
  var side: CtSide { vendor ? .vendor : .customer }
  var paymentDirection: PaymentDirection { vendor ? .made : .received }
}

/// Who a contact is (`isCustomer`, `isVendor` in `src/db/purchases.ts`).
enum CtContacts {
  static func isCustomer(_ contact: JSONValue) -> Bool { contact["isCustomer"]?.bool != false }
  static func isVendor(_ contact: JSONValue) -> Bool { contact["isVendor"]?.bool == true }

  static func isKind(_ contact: JSONValue, _ kind: ContactKind) -> Bool {
    kind == .vendor ? isVendor(contact) : isCustomer(contact)
  }

  /// The page a contact shows on: a vendor opened from a client link (or
  /// the reverse) shows on its own page, as the web redirects it.
  static func shownKind(_ contact: JSONValue, asked: ContactKind) -> ContactKind {
    if asked == .vendor { return !isVendor(contact) && isCustomer(contact) ? .customer : .vendor }
    return isCustomer(contact) ? .customer : .vendor
  }

  /// The share held back from each invoice or bill (`contactRetention`), 0 for none.
  static func retention(_ contact: JSONValue) -> Double {
    let percent = contact.num("retentionPercent")
    return percent.isFinite && percent > 0 ? min(percent, 100) : 0
  }

  /// "Tax retention" or "Contract retention".
  static func retentionKindLabel(_ kind: String?) -> String {
    kind == "contract" ? t("Contract retention") : t("Tax retention")
  }

  /// The other name: English under an Arabic one, and the other way round.
  @MainActor
  static func otherName(_ contact: JSONValue) -> String? {
    let shown = localName(contact)
    let other = shown == contact.str("name") ? contact.text("nameAr") : contact.text("name")
    return other
  }

  /// Retention still held on a document (`heldRetention`).
  static func heldRetention(_ doc: JSONValue) -> Double {
    let currency = doc.text("currency") ?? "KWD"
    var released = Decimal(0)
    for release in doc.list("retentionReleases") where release.text("reversedOn") == nil {
      released += Money.dec(release.num("amount"))
    }
    let held = Money.dec(doc.obj("totals")?.num("retention") ?? 0) - Money.round(released, Money.precision(currency))
    return Money.toNumber(Money.round(held, Money.precision(currency)))
  }

  /// Issued and not void, for the documents that post (`isPosted`).
  static func isPosted(_ doc: JSONValue) -> Bool {
    let type = doc.str("type")
    guard ["invoice", "credit", "bill", "vendor_credit"].contains(type) else { return false }
    return CtStatements.counted(doc)
  }
}

// MARK: The list

/// A record with the name it sorts by.
struct CtNamed {
  let name: String
  let record: JSONValue
}

/// What a contact's row shows: invoiced (or billed), still owed, overdue.
struct CtContactStats {
  var invoiced: Double = 0
  var balance: Double = 0
  var overdue = false
  var count = 0
}

/// `/clients`, `/vendors`: Active / Archived, search; each contact with
/// what it still owes (or is owed).
struct CtContactListPage: View {
  let kind: ContactKind
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let copy = CtContactCopy(kind: kind)
    let format = model.one.format
    let contacts = self.contacts
    let stats = self.stats(format: format)
    let archived = contacts.filter { $0.flag("archived") }.count
    CtListPage(
      title: copy.title, description: copy.description, records: contacts.map(Rec.init),
      filter: .chips([
        ListChip("active", t("Active"), count: contacts.count - archived),
        ListChip("archived", t("Archived"), count: archived),
      ]),
      initial: "active",
      matches: { record, chip in record.raw.flag("archived") == (chip == "archived") },
      searchPlaceholder: copy.search, searchText: { CtContactListPage.searchText($0.raw) },
      newLabel: copy.newLabel, onNew: { router.push(.newContact(kind)) },
      emptyIcon: copy.icon, emptyTitle: copy.emptyTitle, emptyDescription: copy.empty, noMatch: copy.noMatch
    ) { record in
      CtContactRow(contact: record.raw, kind: kind, stats: stats[record.id] ?? CtContactStats(), format: format)
    }
  }

  /// This kind's contacts, by name.
  private var contacts: [JSONValue] {
    model.one.records(.clients)
      .filter { CtContacts.isKind($0, kind) }
      .map { CtNamed(name: localName($0), record: $0) }
      .sorted { ctCollate($0.name, $1.name) == .orderedAscending }
      .map { $0.record }
  }

  /// Each contact's invoices (or bills): issued and not void, in its own currency.
  private func stats(format: CompanyFormat) -> [String: CtContactStats] {
    let copy = CtContactCopy(kind: kind)
    let one = model.one
    let today = DocRules.today
    var result: [String: CtContactStats] = [:]
    for doc in one.records(.documents) where doc.str("type") == copy.docType {
      let status = doc.str("status")
      if status == "draft" || status == "void" { continue }
      let id = doc.str("clientId")
      var entry = result[id] ?? CtContactStats()
      entry.count += 1
      let currency = one.record(.clients, id)?.text("currency") ?? format.currency
      if doc.str("currency") == currency {
        let totals = doc.obj("totals")
        entry.invoiced += totals?.num("total") ?? 0
        if status == "sent" || status == "partial" { entry.balance += totals?.num("balance") ?? 0 }
      }
      if DocRules.displayStatus(doc, today: today) == "overdue" { entry.overdue = true }
      result[id] = entry
    }
    return result
  }

  /// What the search box looks in: names, number, email, phone, city, contact people.
  static func searchText(_ contact: JSONValue) -> String {
    var parts = [
      contact.str("name"), contact.str("nameAr"), contact.str("number"), contact.str("email"), contact.str("phone"),
      contact.obj("address")?.str("city") ?? "",
    ]
    for person in contact.list("contacts") {
      parts.append("\(person.str("name")) \(person.str("email")) \(person.str("phone"))")
    }
    return parts.joined(separator: " ")
  }
}

/// A contact in the list: its name and number, its badges, and what it owes.
struct CtContactRow: View {
  let contact: JSONValue
  let kind: ContactKind
  let stats: CtContactStats
  let format: CompanyFormat
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let copy = CtContactCopy(kind: kind)
    let currency = contact.text("currency") ?? format.currency
    CtListRow(
      title: localName(contact), subtitle: contact.text("number"),
      amount: format.money(stats.balance, currency), amountCaption: copy.owedLabel, amountMuted: stats.balance <= 0
    ) {
      if contact.flag("creditHold") { Badge(t("On credit hold"), tone: .red) }
      if stats.overdue { Badge(t("Overdue"), tone: .red) }
    } action: {
      router.push(.contact(kind, id: contact.rid))
    }
  }
}

// MARK: A contact

/// Everything a contact's page shows, read once per redraw.
@MainActor
struct CtContactData {
  let contact: JSONValue
  let kind: ContactKind
  let copy: CtContactCopy
  let format: CompanyFormat
  let company: JSONValue?
  let companyCurrency: String
  let today: String
  /// All of the contact's documents, any type.
  let docs: [JSONValue]
  /// The documents listed for this kind of contact.
  let ownDocs: [JSONValue]
  /// All of its payments, both ways, void ones too.
  let allPayments: [JSONValue]
  /// Payments of this side, credit notes left out, newest first.
  let payments: [JSONValue]
  /// Expenses paid to it (vendors), newest first.
  let expenses: [JSONValue]
  let position: CtPosition
  let returnedCheques: Int
  let retention: Double
  let showRetentions: Bool

  init(contact: JSONValue, kind: ContactKind, one: OneData) {
    let id = contact.rid
    let copy = CtContactCopy(kind: kind)
    self.contact = contact
    self.kind = kind
    self.copy = copy
    format = one.format
    company = one.company
    companyCurrency = one.format.currency
    today = DocRules.today
    docs = one.records(.documents).filter { $0.str("clientId") == id }
    let types = Set(copy.docTypes.map(\.rawValue))
    ownDocs = docs.filter { types.contains($0.str("type")) }
    allPayments = one.records(.payments).filter { $0.str("clientId") == id }
    let out = kind == .vendor
    payments = allPayments
      .filter { CtPayments.isOut($0) == out && $0.str("method") != "credit_note" }
      .sorted(by: CtContactData.newestPayment)
    expenses = one.records(.expenses).filter { $0.str("vendorId") == id }.sorted { $0.str("date") > $1.str("date") }
    position = CtStatements.position(
      side: copy.side, contact: contact, documents: docs, payments: allPayments, companyCurrency: one.format.currency,
      today: DocRules.today)
    returnedCheques = allPayments.filter { !CtPayments.isOut($0) && $0.obj("cheque")?.str("status") == "returned" }
      .count
    retention = CtContacts.retention(contact)
    let held = docs.contains { types.contains($0.str("type")) && ($0.obj("totals")?.num("retention") ?? 0) > 0 }
    showRetentions = retention > 0 || !contact.list("clearanceCertificates").isEmpty || held
  }

  /// Money in the company currency, from minor units.
  func companyMoney(_ minor: Int64) -> String {
    format.money(ctMajor(minor, position.precision), companyCurrency)
  }

  /// The route of one of the contact's documents.
  func route(of doc: JSONValue) -> Route? {
    DocType(rawValue: doc.str("type")).map { $0.route(doc.rid) }
  }

  nonisolated static func newestPayment(_ a: JSONValue, _ b: JSONValue) -> Bool {
    let (da, db) = (a.str("date"), b.str("date"))
    if da != db { return da > db }
    return a.str("createdAt") > b.str("createdAt")
  }
}

/// `/clients/:id`, `/vendors/:id`: the name and its badges, the summary
/// figures, then Overview / Documents / Payments / Statement / Retentions.
struct CtContactPage: View {
  let kind: ContactKind
  let id: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let one = model.one
    let contact = one.record(.clients, id)
    let shown = contact.map { CtContacts.shownKind($0, asked: kind) } ?? kind
    let copy = CtContactCopy(kind: shown)
    RecordDetailPage(
      record: contact, title: contact.map { localName($0) } ?? "", subtitle: contact.flatMap { subtitle($0) },
      breadcrumb: copy.title
    ) {
      if let contact {
        CtContactBadges(contact: contact, kind: shown, format: one.format)
      }
    } actions: {
      if shown == .vendor {
        WebButton(t("New bill"), icon: .plus, size: .sm) { router.push(.newPurchaseDocument(.bill)) }
      } else {
        WebButton(t("New quote"), variant: .outline, size: .sm) { router.push(.newSalesDocument(.quote)) }
        WebButton(t("New invoice"), icon: .plus, size: .sm) { router.push(.newSalesDocument(.invoice)) }
      }
      WebButton(t("Edit"), icon: .pencil, variant: .outline, size: .sm) {
        router.push(.editContact(shown, id: id))
      }
    } content: {
      if let contact {
        CtContactBody(data: CtContactData(contact: contact, kind: shown, one: one))
      }
    }
  }

  /// The other name and the number.
  private func subtitle(_ contact: JSONValue) -> String? {
    let parts = [CtContacts.otherName(contact), contact.text("number")].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}

/// The badges by a contact's name: archived, credit hold, returned cheques,
/// retention, tax exempt, its currency, and "Also a vendor" (or client).
struct CtContactBadges: View {
  let contact: JSONValue
  let kind: ContactKind
  let format: CompanyFormat
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let copy = CtContactCopy(kind: kind)
    let vendor = kind == .vendor
    let percent = CtContacts.retention(contact)
    let returned = returnedCount
    let other = otherKind
    if contact.flag("archived") { Badge(t("Archived"), tone: .slate) }
    if contact.flag("creditHold"), !vendor { Badge(t("On credit hold"), tone: .red) }
    if returned > 0, !vendor {
      Badge(tp(returned, "{count} returned cheque", "{count} returned cheques"), tone: .red)
    }
    if percent > 0 { Badge(t("{percent} retention", ["percent": format.percent(percent)]), tone: .violet) }
    if contact.flag("taxExempt") { Badge(t("Tax exempt"), tone: .amber) }
    if let currency = contact.text("currency") { Badge(currency, tone: .blue) }
    if let other {
      Button {
        Haptics.play(.tap)
        router.push(.contact(other, id: contact.rid))
      } label: {
        Badge(copy.alsoOther, tone: .violet)
      }
      .buttonStyle(.plain)
    }
  }

  private var returnedCount: Int {
    let id = contact.rid
    return model.one.records(.payments).filter { payment in
      payment.str("clientId") == id && !CtPayments.isOut(payment)
        && payment.obj("cheque")?.str("status") == "returned"
    }.count
  }

  private var otherKind: ContactKind? {
    if kind == .vendor { return CtContacts.isCustomer(contact) ? .customer : nil }
    return CtContacts.isVendor(contact) ? .vendor : nil
  }
}

/// The summary figures and the sections of a contact's page.
struct CtContactBody: View {
  let data: CtContactData
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var tab = "overview"
  @State private var docType = ""
  @State private var list = "payments"
  @State private var expenseId = ""
  @State private var showingExpense = false

  init(data: CtContactData) {
    self.data = data
  }

  var body: some View {
    let expense = model.one.record(.expenses, expenseId)
    let dialogRows = expense.map { CtExpenseInfo.rows($0, one: model.one) } ?? []
    VStack(alignment: .leading, spacing: 16) {
      CtContactSummary(data: data)
      if (data.contact.text("currency") ?? data.companyCurrency) != data.companyCurrency {
        Text(t("Amounts in {currency}, at each document’s exchange rate.", ["currency": data.companyCurrency]))
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
      }
      Segmented(selection: $tab, options: tabs)
      section
    }
    .webDialog(
      isPresented: $showingExpense,
      title: t("Expense {number}", ["number": expense?.str("number") ?? ""]),
      description: t("Something paid straight away, without a bill to pay later.")
    ) {
      CtDetailRows(rows: dialogRows)
    }
  }

  private var tabs: [SegmentOption<String>] {
    var options = [
      SegmentOption("overview", t("Overview")),
      SegmentOption("documents", t("Documents"), count: data.ownDocs.count),
      SegmentOption("payments", t("Payments"), count: data.payments.count),
      SegmentOption("statement", t("Statement")),
    ]
    if data.showRetentions { options.append(SegmentOption("retentions", t("Retentions"))) }
    return options
  }

  @ViewBuilder private var section: some View {
    switch tab {
    case "documents": documentsTab
    case "payments": paymentsTab
    case "statement": CtStatementPanel(data: data)
    case "retentions" where data.showRetentions: CtRetentionPanel(data: data)
    default: overviewTab
    }
  }

  // MARK: Overview

  @ViewBuilder private var overviewTab: some View {
    let open = openDocs
    let recent = Array(recentDocs.prefix(5))
    CtRowsCard(
      data.kind == .vendor ? t("Open bills") : t("Open invoices"),
      description: open.isEmpty
        ? nil : tp(open.count, "{count} document still to pay", "{count} documents still to pay")
    ) {
      if open.isEmpty {
        CtEmptyText(t("Nothing is due."))
      } else {
        ForEach(open.map(Rec.init)) { record in
          openRow(record.raw)
        }
      }
    }
    CtRowsCard(t("Recent documents")) {
      if data.ownDocs.count > recent.count {
        WebButton(t("View all"), variant: .ghost, size: .sm) { tab = "documents" }
      }
    } rows: {
      if recent.isEmpty {
        WebEmptyState(
          title: t("No documents yet"),
          description: data.kind == .vendor
            ? t("Bills from this vendor show here.") : t("Quotes, invoices and credit notes for this client show here."))
      } else {
        ForEach(recent.map(Rec.init)) { record in
          CtContactDocRow(doc: record.raw, data: data)
        }
      }
    }
    CtContactDetailsCard(data: data)
  }

  /// Invoices (or bills) still to pay, soonest due first.
  private var openDocs: [JSONValue] {
    data.docs
      .filter { $0.str("type") == data.copy.docType && CtContacts.isPosted($0) && balance($0) > 0 }
      .sorted { ($0.text("dueDate") ?? $0.str("issueDate")) < ($1.text("dueDate") ?? $1.str("issueDate")) }
  }

  /// The contact's documents, newest first.
  private var recentDocs: [JSONValue] {
    data.ownDocs.sorted { a, b in
      let (da, db) = (a.str("issueDate"), b.str("issueDate"))
      if da != db { return da > db }
      return a.str("createdAt") > b.str("createdAt")
    }
  }

  private func balance(_ doc: JSONValue) -> Double { doc.obj("totals")?.num("balance") ?? 0 }

  private func openRow(_ doc: JSONValue) -> some View {
    let late = doc.text("dueDate").flatMap { ISODates.daysBetween($0, data.today) } ?? 0
    let due = doc.text("dueDate").map { t("Due {date}", ["date": data.format.date($0)]) }
    let route = data.route(of: doc)
    return ListRow(
      title: doc.str("number"), subtitle: due ?? data.format.date(doc.text("issueDate")),
      amount: data.format.money(balance(doc), doc.text("currency"))
    ) {
      if late > 0 { Badge(tp(late, "{count} day late", "{count} days late"), tone: .red) }
    } action: {
      if let route { router.push(route) }
    }
  }

  // MARK: Documents

  @ViewBuilder private var documentsTab: some View {
    let types = data.copy.docTypes
    let shown = types.first { $0.rawValue == docType } ?? types[0]
    let listed = data.docs.filter { $0.str("type") == shown.rawValue }.sorted { $0.str("issueDate") > $1.str("issueDate") }
    ListCard {
      Segmented(selection: docTypeSelection(shown), options: typeOptions(types), small: true)
    } rows: {
      if listed.isEmpty {
        VStack(spacing: 4) {
          Text(t("Nothing here yet."))
            .font(.web(14))
            .foregroundStyle(palette.slate(500))
          WebButton(t("Create one"), variant: .ghost, size: .sm) { router.push(shown.newRoute) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
      } else {
        ForEach(listed.map(Rec.init)) { record in
          CtContactDocRow(doc: record.raw, data: data)
        }
      }
    }
  }

  private func docTypeSelection(_ shown: DocType) -> Binding<String> {
    Binding(get: { shown.rawValue }, set: { docType = $0 })
  }

  private func typeOptions(_ types: [DocType]) -> [SegmentOption<String>] {
    types.map { type in
      SegmentOption(type.rawValue, t(type.plural), count: data.docs.filter { $0.str("type") == type.rawValue }.count)
    }
  }

  // MARK: Payments

  @ViewBuilder private var paymentsTab: some View {
    if data.kind == .vendor {
      ListCard {
        Segmented(
          selection: $list,
          options: [
            SegmentOption("payments", t("Payments"), count: data.payments.count),
            SegmentOption("expenses", t("Expenses"), count: data.expenses.count),
          ], small: true)
      } rows: {
        if list == "expenses" {
          expenseRows
        } else {
          paymentRows
        }
      }
    } else {
      ListCard {
        paymentRows
      }
    }
  }

  @ViewBuilder private var paymentRows: some View {
    if data.payments.isEmpty {
      WebEmptyState(title: t("No payments yet.")) {
        WebButton(t("Record payment"), icon: .plus, variant: .outline, size: .sm) {
          router.push(.newPayment(data.copy.paymentDirection))
        }
      }
    } else {
      ForEach(data.payments.map(Rec.init)) { record in
        CtContactPaymentRow(payment: record.raw, format: data.format, direction: data.copy.paymentDirection)
      }
    }
  }

  @ViewBuilder private var expenseRows: some View {
    if data.expenses.isEmpty {
      CtEmptyText(t("No expenses yet."), centered: true)
    } else {
      ForEach(data.expenses.map(Rec.init)) { record in
        let expense = record.raw
        ListRow(
          title: "\(expense.str("number")) · \(data.format.date(expense.text("date")))",
          subtitle: expense.text("description") ?? "—",
          amount: data.format.money(expense.num("amount"), expense.text("currency")),
          action: {
            expenseId = expense.rid
            showingExpense = true
          })
      }
    }
  }
}

/// Balance, overdue, credit used (or cheques not yet presented), the last
/// payment and cheques in hand (or retention held), two to a row.
struct CtContactSummary: View {
  let data: CtContactData
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let position = data.position
    let vendor = data.kind == .vendor
    let money: (Int64) -> String = { data.companyMoney($0) }
    CtFigureGrid {
      CtFigure(
        label: vendor ? t("You owe") : t("Balance due"), value: money(position.balance),
        hint: position.retentionHeld != 0
          ? t("Plus {amount} retention held", ["amount": money(position.retentionHeld)]) : nil)
      CtFigure(
        label: t("Overdue"), value: money(position.overdue), tone: position.overdue > 0 ? .danger : .plain)
      if vendor {
        CtFigure(
          label: t("Cheques not yet presented"), value: money(position.uncleared),
          hint: tp(position.unclearedCount, "{count} cheque", "{count} cheques"))
      } else {
        CtFigure(
          label: t("Credit used"), value: money(position.exposure), hint: creditHint(position, money: money),
          tone: creditDanger(position) ? .danger : .plain, share: creditShare(position))
      }
      CtFigure(
        label: vendor ? t("Last payment made") : t("Last payment"),
        value: position.lastPayment.map { money($0.amount) } ?? "—",
        hint: position.lastPayment.map { "\(data.format.date($0.date)) · \($0.number)" } ?? t("No payments yet."),
        action: lastPaymentAction(position))
      if vendor {
        CtFigure(label: t("Retention you hold"), value: money(position.retentionHeld))
      } else {
        CtFigure(
          label: t("Cheques in hand"), value: money(position.uncleared),
          hint: tp(position.unclearedCount, "{count} cheque not cleared yet", "{count} cheques not cleared yet"))
      }
    }
  }

  private var onHold: Bool { data.contact.flag("creditHold") }

  private func creditDanger(_ position: CtPosition) -> Bool {
    onHold || (position.available ?? 0) < 0
  }

  private func creditHint(_ position: CtPosition, money: (Int64) -> String) -> String {
    if onHold { return t("On credit hold") }
    guard let limit = position.limit else { return t("No credit limit") }
    let available = position.available ?? 0
    if available < 0 {
      return t("{amount} over the limit of {limit}", ["amount": money(-available), "limit": money(limit)])
    }
    return t("{amount} left of {limit}", ["amount": money(available), "limit": money(limit)])
  }

  private func creditShare(_ position: CtPosition) -> Double? {
    guard let limit = position.limit else { return nil }
    if limit > 0 { return Double(position.exposure) / Double(limit) }
    return position.exposure > 0 ? 2 : 0
  }

  private func lastPaymentAction(_ position: CtPosition) -> (() -> Void)? {
    guard let last = position.lastPayment else { return nil }
    let direction = data.copy.paymentDirection
    return { router.push(.payment(direction, id: last.id)) }
  }
}

/// One of a contact's documents: its number (and the vendor's reference),
/// "type · date · due", what is still owed (or its total), the retention
/// held and the status.
struct CtContactDocRow: View {
  let doc: JSONValue
  let data: CtContactData
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let type = DocType(rawValue: doc.str("type")) ?? .invoice
    let totals = doc.obj("totals")
    let total = totals?.num("total") ?? 0
    let balance = totals?.num("balance") ?? 0
    let open = CtContacts.isPosted(doc) && balance > 0
    let currency = doc.text("currency")
    let held = (totals?.num("retention") ?? 0) != 0 ? CtContacts.heldRetention(doc) : 0
    CtListRow(
      title: title, subtitle: subtitle(type, open: open),
      amount: type.priced ? data.format.money(open ? balance : total, currency) : nil,
      amountCaption: open && balance != total ? t("of {amount}", ["amount": data.format.money(total, currency)]) : nil,
      trailingBadges: true
    ) {
      if held > 0 { Badge(t("{amount} held", ["amount": data.format.money(held, currency)]), tone: .violet) }
      statusBadge(DocRules.displayStatus(doc, today: data.today))
    } action: {
      router.push(type.route(doc.rid))
    }
  }

  private var title: String {
    let number = doc.text("number") ?? t("Draft")
    guard let reference = doc.text("vendorReference") else { return number }
    return "\(number) · \(reference)"
  }

  private func subtitle(_ type: DocType, open: Bool) -> String {
    var parts = [t(type.singular), data.format.date(doc.text("issueDate"))]
    if open, let due = doc.text("dueDate") { parts.append(t("Due {date}", ["date": data.format.date(due)])) }
    return parts.filter { !$0.isEmpty }.joined(separator: " · ")
  }
}

/// One of a contact's payments: "number · date", the method and cheque or
/// reference, the cheque's status until it clears, and the amount.
struct CtContactPaymentRow: View {
  let payment: JSONValue
  let format: CompanyFormat
  let direction: PaymentDirection
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let cheque = payment.str("method") == "cheque" ? payment.obj("cheque") : nil
    let voided = payment.flag("voided")
    ListRow(
      title: "\(payment.str("number")) · \(format.date(payment.text("date")))",
      subtitle: method(cheque),
      amount: format.money(payment.num("amount"), payment.text("currency"))
    ) {
      if let cheque, cheque.str("status") != "cleared" || voided {
        Badge(status: StatusMeta.cheque(cheque.str("status")))
      }
    } action: {
      router.push(.payment(direction, id: payment.rid))
    }
  }

  private func method(_ cheque: JSONValue?) -> String {
    let label = CtPayments.methodLabel(payment.str("method"))
    if let cheque { return "\(label) \(cheque.str("number"))" }
    if let reference = payment.text("reference") { return "\(label) · \(reference)" }
    return label
  }
}

/// The contact's details: its people, addresses, tax and civil ID, terms,
/// credit limit, retention and notes.
struct CtContactDetailsCard: View {
  let data: CtContactData
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let contact = data.contact
    let people = contact.list("contacts")
    Card {
      CardHeader(t("Details")) {
        WebButton(t("Edit"), icon: .pencil, variant: .ghost, size: .sm) {
          router.push(.editContact(data.kind, id: contact.rid))
        }
      }
      VStack(alignment: .leading, spacing: 20) {
        if !people.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(people.enumerated()), id: \.offset) { _, person in
              CtContactPerson(person: person, showPrimary: people.count > 1)
            }
          }
        }
        ForEach(blocks) { block in
          VStack(alignment: .leading, spacing: 4) {
            Text(block.label)
              .font(.web(12, .medium))
              .textCase(.uppercase)
              .foregroundStyle(palette.slate(500))
            ForEach(Array(block.lines.enumerated()), id: \.offset) { _, line in
              Text(line)
                .font(.web(14))
                .foregroundStyle(palette.slate(700))
                .textSelection(.enabled)
            }
          }
        }
        if let notes = contact.text("notes") {
          Text(notes)
            .font(.web(12))
            .foregroundStyle(palette[.amber(900)])
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(palette[.amber(50)], in: RoundedRectangle(cornerRadius: WebRadius.sm, style: .continuous))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(20)
    }
  }

  /// The labelled blocks, those with something to show.
  private var blocks: [CtDetailBlock] {
    let contact = data.contact
    let locale = Localization.language == .ar ? "ar" : "en"
    var blocks: [CtDetailBlock] = []
    let address = Geo.formatAddressLines(contact["address"], locale: locale)
    if !address.isEmpty {
      blocks.append(CtDetailBlock(data.kind == .vendor ? t("Address") : t("Billing address"), address))
    }
    if let shipping = contact["shippingAddress"], !Geo.isAddressEmpty(shipping) {
      blocks.append(CtDetailBlock(t("Shipping address"), Geo.formatAddressLines(shipping, locale: locale)))
    }
    if let taxId = contact.text("taxId") { blocks.append(CtDetailBlock(taxIdLabel, [taxId])) }
    if let civilId = contact.text("civilId") { blocks.append(CtDetailBlock(t("Civil ID"), [civilId])) }
    let terms = contact.number("paymentTermsDays") ?? data.company?.obj("defaults")?.number("paymentTermsDays")
    if let terms {
      blocks.append(CtDetailBlock(t("Payment terms"), [tp(Int(terms), "{count} day", "{count} days")]))
    }
    if data.kind == .customer {
      let limit = contact.number("creditLimit").map { data.format.money($0) } ?? t("No credit limit")
      blocks.append(CtDetailBlock(t("Credit limit"), [limit]))
    }
    if data.retention > 0 {
      let kind = CtContacts.retentionKindLabel(contact.text("retentionKind"))
      let text = t("{kind} of {percent}", ["kind": kind, "percent": data.format.percent(data.retention)])
      blocks.append(CtDetailBlock(t("Retention"), [text]))
    }
    return blocks
  }

  /// What a contact's tax number is called (`taxIdLabel`).
  private var taxIdLabel: String {
    guard let label = data.company?.text("taxIdLabel")?.trimmingCharacters(in: .whitespaces), !label.isEmpty else {
      return t("Tax ID")
    }
    return ["Tax card no.", "VAT No.", "Tax ID", "Tax No."].contains(label) ? t(label) : label
  }
}

/// A labelled block of the details card.
struct CtDetailBlock: Identifiable {
  let label: String
  let lines: [String]
  var id: String { label }

  init(_ label: String, _ lines: [String]) {
    self.label = label
    self.lines = lines
  }
}

/// A contact person: name (and "Primary contact"), email and phone, each opening Mail or Phone.
struct CtContactPerson: View {
  let person: JSONValue
  let showPrimary: Bool
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 8) {
        Text(person.text("name") ?? t("Contact person"))
          .font(.web(14, .medium))
          .foregroundStyle(palette.slate(800))
        if showPrimary, person.flag("primary") {
          Text(t("Primary contact"))
            .font(.web(12))
            .foregroundStyle(palette.slate(500))
        }
      }
      if let email = person.text("email"), let url = URL(string: "mailto:\(email)") {
        Link(destination: url) {
          HStack(spacing: 6) {
            IconView(.mail, size: 14)
            Text(verbatim: email).environment(\.layoutDirection, .leftToRight)
          }
          .font(.web(14))
          .foregroundStyle(palette.primary(700))
        }
      }
      if let phone = person.text("phone"), let url = URL(string: "tel:\(phone.filter { !$0.isWhitespace })") {
        Link(destination: url) {
          HStack(spacing: 6) {
            IconView(.phone, size: 14)
            Text(verbatim: phone).environment(\.layoutDirection, .leftToRight)
          }
          .font(.web(14))
          .foregroundStyle(palette.slate(600))
        }
      }
    }
  }
}
