import MahamKit
import SwiftUI

// The nine document types the web keeps in `documents` (`type`), sharing
// one list and one page (`src/apps/books/pages/documents/list.tsx`,
// `view.tsx`): invoices, quotes, credit notes, proformas, sales orders and
// delivery notes; bills, vendor credits and purchase orders.

/// A document type, as the web names it, with its words and its pages.
enum DocType: String, CaseIterable, Sendable {
  case invoice, quote, credit, proforma
  case salesOrder = "sales_order"
  case deliveryNote = "delivery_note"
  case bill
  case vendorCredit = "vendor_credit"
  case purchaseOrder = "purchase_order"

  init(_ kind: SalesDocumentKind) {
    switch kind {
    case .invoice: self = .invoice
    case .quote: self = .quote
    case .credit: self = .credit
    case .proforma: self = .proforma
    case .salesOrder: self = .salesOrder
    case .deliveryNote: self = .deliveryNote
    }
  }

  init(_ kind: PurchaseDocumentKind) {
    switch kind {
    case .bill: self = .bill
    case .vendorCredit: self = .vendorCredit
    case .purchaseOrder: self = .purchaseOrder
    }
  }

  var isPurchase: Bool { self == .bill || self == .vendorCredit || self == .purchaseOrder }
  /// Delivery notes have no prices.
  var priced: Bool { self != .deliveryNote }

  var plural: String {
    switch self {
    case .invoice: "Invoices"
    case .quote: "Quotes"
    case .credit: "Credit notes"
    case .proforma: "Proforma invoices"
    case .salesOrder: "Sales orders"
    case .deliveryNote: "Delivery notes"
    case .bill: "Bills"
    case .vendorCredit: "Vendor credits"
    case .purchaseOrder: "Purchase orders"
    }
  }

  var singular: String {
    switch self {
    case .invoice: "Invoice"
    case .quote: "Quote"
    case .credit: "Credit note"
    case .proforma: "Proforma invoice"
    case .salesOrder: "Sales order"
    case .deliveryNote: "Delivery note"
    case .bill: "Bill"
    case .vendorCredit: "Vendor credit"
    case .purchaseOrder: "Purchase order"
    }
  }

  var newLabel: String {
    switch self {
    case .invoice: "New invoice"
    case .quote: "New quote"
    case .credit: "New credit note"
    case .proforma: "New proforma invoice"
    case .salesOrder: "New sales order"
    case .deliveryNote: "New delivery note"
    case .bill: "New bill"
    case .vendorCredit: "New vendor credit"
    case .purchaseOrder: "New purchase order"
    }
  }

  /// The list's empty state.
  var emptyTitle: String {
    switch self {
    case .invoice: "No invoices yet"
    case .quote: "No quotes yet"
    case .credit: "No credit notes yet"
    case .proforma: "No proforma invoices yet"
    case .salesOrder: "No sales orders yet"
    case .deliveryNote: "No delivery notes yet"
    case .bill: "No bills yet"
    case .vendorCredit: "No vendor credits yet"
    case .purchaseOrder: "No purchase orders yet"
    }
  }

  var icon: Icon {
    switch self {
    case .invoice: .fileText
    case .quote: .scrollText
    case .credit: .fileMinus
    case .bill: .receipt
    case .vendorCredit: .receiptText
    case .proforma: .fileClock
    case .salesOrder: .clipboardList
    case .purchaseOrder: .shoppingCart
    case .deliveryNote: .packageCheck
    }
  }

  /// The second date: due, valid until or delivery.
  var secondDateLabel: String {
    switch self {
    case .quote, .proforma: "Valid until"
    case .salesOrder, .purchaseOrder, .deliveryNote: "Delivery date"
    default: "Due date"
    }
  }

  func secondDate(_ doc: JSONValue) -> String? {
    switch self {
    case .salesOrder, .purchaseOrder, .deliveryNote: doc.text("deliveryDate")
    default: doc.text("dueDate")
    }
  }

  /// The status chips (`FILTERS`).
  var chips: [ListChip] {
    let all = ListChip("all", t("All"))
    let draft = ListChip("draft", t("Draft"))
    switch self {
    case .invoice, .bill:
      return [all, draft, ListChip("unpaid", t("Unpaid")), ListChip("overdue", t("Overdue")),
        ListChip("paid", t("Paid")), ListChip("void", t("Void"))]
    case .quote:
      return [all, draft, ListChip("sent", t("Sent")), ListChip("accepted", t("Accepted")),
        ListChip("expired", t("Expired")), ListChip("invoiced", t("Invoiced")),
        ListChip("converted", t("Converted")), ListChip("declined", t("Declined"))]
    case .credit:
      return [all, draft, ListChip("sent", t("Open")), ListChip("applied", t("Applied")), ListChip("void", t("Void"))]
    case .vendorCredit:
      return [all, draft, ListChip("open", t("Open")), ListChip("applied", t("Applied")), ListChip("void", t("Void"))]
    case .proforma:
      return [all, draft, ListChip("sent", t("Sent")), ListChip("accepted", t("Accepted")),
        ListChip("expired", t("Expired")), ListChip("converted", t("Converted"))]
    case .salesOrder:
      return [all, draft, ListChip("confirmed", t("Confirmed")),
        ListChip("partially_invoiced", t("Partially invoiced")), ListChip("invoiced", t("Invoiced")),
        ListChip("cancelled", t("Cancelled"))]
    case .purchaseOrder:
      return [all, draft, ListChip("issued", t("Issued")), ListChip("partially_billed", t("Partially billed")),
        ListChip("billed", t("Billed")), ListChip("cancelled", t("Cancelled"))]
    case .deliveryNote:
      return [all, draft, ListChip("delivered", t("Delivered")), ListChip("cancelled", t("Cancelled"))]
    }
  }

  /// The route of a document of this type.
  func route(_ id: String) -> Route {
    switch self {
    case .invoice: .salesDocument(.invoice, id: id)
    case .quote: .salesDocument(.quote, id: id)
    case .credit: .salesDocument(.credit, id: id)
    case .proforma: .salesDocument(.proforma, id: id)
    case .salesOrder: .salesDocument(.salesOrder, id: id)
    case .deliveryNote: .salesDocument(.deliveryNote, id: id)
    case .bill: .purchaseDocument(.bill, id: id)
    case .vendorCredit: .purchaseDocument(.vendorCredit, id: id)
    case .purchaseOrder: .purchaseDocument(.purchaseOrder, id: id)
    }
  }

  /// The route of the new-document page.
  var newRoute: Route {
    switch self {
    case .invoice: .newSalesDocument(.invoice)
    case .quote: .newSalesDocument(.quote)
    case .credit: .newSalesDocument(.credit)
    case .proforma: .newSalesDocument(.proforma)
    case .salesOrder: .newSalesDocument(.salesOrder)
    case .deliveryNote: .newSalesDocument(.deliveryNote)
    case .bill: .newPurchaseDocument(.bill)
    case .vendorCredit: .newPurchaseDocument(.vendorCredit)
    case .purchaseOrder: .newPurchaseDocument(.purchaseOrder)
    }
  }
}

/// A document's rules for showing it.
enum DocRules {
  /// Today, as the web compares dates ("2026-11-26").
  static var today: String { ISODates.today() }

  /// `displayStatus`: "overdue", "expired" and "open" as the web shows them.
  static func displayStatus(_ doc: JSONValue, today: String = DocRules.today) -> String {
    let type = doc.str("type")
    let status = doc.str("status")
    let due = doc.text("dueDate")
    let balance = doc.obj("totals")?.num("balance") ?? 0
    if (type == "invoice" || type == "bill"), status == "sent" || status == "partial", let due, due < today,
      balance > 0
    {
      return "overdue"
    }
    if (type == "quote" || type == "proforma"), status == "sent", let due, due < today { return "expired" }
    if (type == "bill" || type == "vendor_credit"), status == "sent" { return "open" }
    return status
  }

  /// A status chip holds a status (`matches`).
  static func matches(_ chip: String, _ status: String) -> Bool {
    switch chip {
    case "all": true
    case "unpaid": ["sent", "open", "partial", "overdue"].contains(status)
    case "sent": status == "sent" || status == "partial"
    case "open": status == "open" || status == "partial"
    default: status == chip
    }
  }

  /// Newest first: by issue date, then number.
  static func newestFirst(_ a: JSONValue, _ b: JSONValue) -> Bool {
    let (da, db) = (a.str("issueDate"), b.str("issueDate"))
    if da != db { return da > db }
    return a.str("number").localizedStandardCompare(b.str("number")) == .orderedDescending
  }

  /// A line's amount before tax: quantity × price, less its discount.
  static func lineAmount(_ line: JSONValue) -> Double {
    let gross = line.num("quantity") * line.num("unitPrice")
    let discount = line.num("discount")
    let off = line.str("discountType") == "amount" ? discount : gross * discount / 100
    return gross - off
  }
}

// MARK: The list

/// `/invoices`, `/quotes`, … and `/bills`, …: every document of a type.
struct DocumentListPage: View {
  let type: DocType
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let one = model.one
    let format = one.format
    let docs = documents
    let today = DocRules.today
    RecordListPage(
      title: t(type.plural), records: docs.map(Rec.init), chips: chips(docs, today: today),
      chipFilter: { record, chip in DocRules.matches(chip, DocRules.displayStatus(record.raw, today: today)) },
      searchPlaceholder: type.isPurchase ? t("Search number, vendor, reference…") : t("Search number, client, PO…"),
      searchText: { record in
        let doc = record.raw
        let contact = one.record(.clients, doc.str("clientId"))
        return [
          doc.str("number"), contact?.str("name") ?? "", contact?.str("nameAr") ?? "", doc.str("poNumber"),
          doc.str("vendorReference"), doc.str("receiverName"),
        ].joined(separator: " ")
      },
      newLabel: DcWrite.documents && DcWrite.edits(model) ? t(type.newLabel) : nil, onNew: { router.push(type.newRoute) },
      emptyIcon: type.icon, emptyTitle: t(type.emptyTitle)
    ) { record in
      DocumentRow(doc: record.raw, type: type, format: format)
    } footer: { visible in
      DocumentListFooter(docs: visible.map(\.raw), type: type, format: format, today: today)
    }
  }

  /// This type's documents, newest first.
  private var documents: [JSONValue] {
    model.one.records(.documents)
      .filter { $0.str("type") == type.rawValue && !$0.flag("archived") }
      .sorted(by: DocRules.newestFirst)
  }

  /// The chips with their counts.
  private func chips(_ docs: [JSONValue], today: String) -> [ListChip] {
    let statuses = docs.map { DocRules.displayStatus($0, today: today) }
    return type.chips.map { chip in
      var counted = chip
      if chip.id != "all" { counted.count = statuses.filter { DocRules.matches(chip.id, $0) }.count }
      return counted
    }
  }
}

/// A document in a list: the contact; "number · date"; the total and the badges.
struct DocumentRow: View {
  let doc: JSONValue
  let type: DocType
  let format: CompanyFormat
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let name = model.one.contactName(doc.text("clientId"))
    let number = doc.text("number") ?? t("Draft")
    let status = DocRules.displayStatus(doc)
    ListRow(
      title: name.isEmpty ? "—" : name,
      subtitle: "\(number) · \(format.date(doc.text("issueDate")))",
      amount: type.priced ? format.money(doc.obj("totals")?.num("total") ?? 0, doc.text("currency")) : nil
    ) {
      statusBadge(status)
      if type == .salesOrder, let delivery = doc.text("deliveryStatus"), delivery != "not_delivered" {
        Badge(status: StatusMeta.delivery(delivery))
      }
    } action: {
      router.push(type.route(doc.rid))
    }
  }
}

/// Under the list: how many, and the totals per currency (with what is
/// still owed on invoices).
private struct DocumentListFooter: View {
  let docs: [JSONValue]
  let type: DocType
  let format: CompanyFormat
  let today: String
  @Environment(\.palette) private var palette

  var body: some View {
    Text(tp(docs.count, "{count} document", "{count} documents", ["count": format.count(docs.count)]))
    if type.priced {
      ForEach(totals) { sum in
        // Each label stays with its amount; the pairs wrap as a whole.
        FlowLayout(spacing: 12, lineSpacing: 4) {
          DocumentFooterAmount(label: t("Total"), amount: format.money(sum.total, sum.currency))
          if type == .invoice || type == .bill {
            DocumentFooterAmount(label: t("Outstanding"), amount: format.money(sum.balance, sum.currency))
          }
        }
      }
    }
  }

  private var totals: [CurrencyTotal] {
    var sums: [String: (Double, Double)] = [:]
    var order: [String] = []
    for doc in docs {
      let status = DocRules.displayStatus(doc, today: today)
      if status == "void" || status == "cancelled" { continue }
      let currency = doc.text("currency") ?? format.currency
      if sums[currency] == nil { order.append(currency) }
      var entry = sums[currency] ?? (0, 0)
      entry.0 += doc.obj("totals")?.num("total") ?? 0
      if (type == .invoice || type == .bill), status != "draft" { entry.1 += doc.obj("totals")?.num("balance") ?? 0 }
      sums[currency] = entry
    }
    return order.map { CurrencyTotal(currency: $0, total: sums[$0]!.0, balance: sums[$0]!.1) }
  }
}

/// "Total KWD 4,826.250" under a list, the amount in bold.
private struct DocumentFooterAmount: View {
  let label: String
  let amount: String
  @Environment(\.palette) private var palette

  var body: some View {
    HStack(spacing: 4) {
      Text(label)
      Text(amount)
        .font(.web(14, .semibold, tabular: true))
        .foregroundStyle(palette.slate(900))
        .environment(\.layoutDirection, .leftToRight)
    }
    .fixedSize()
  }
}

/// A list's total in one currency, and what is still owed.
struct CurrencyTotal: Identifiable {
  let currency: String
  var total: Double
  var balance: Double
  var id: String { currency }
}

// MARK: A document

/// `/invoices/:id`, `/bills/:id`, …: the title, its status and contact, the
/// summary, the lines, the notes, the payments, what it came from and
/// turned into.
struct DocumentPage: View {
  let type: DocType
  let id: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  /// What the page's actions are doing, and their dialogs (DcActions.swift).
  @State private var actionState = DcActionState()

  init(type: DocType, id: String) {
    self.type = type
    self.id = id
  }

  var body: some View {
    let one = model.one
    let format = one.format
    let doc = one.record(.documents, id)
    let currency = doc?.text("currency") ?? format.currency
    let status = doc.map { DocRules.displayStatus($0) } ?? ""
    let contactId = doc?.text("clientId")
    let contact = one.contactName(contactId)
    let number = doc?.text("number") ?? t("Draft")
    RecordDetailPage(
      record: doc, title: "\(t(type.singular)) \(number)", subtitle: contact.isEmpty ? nil : contact,
      breadcrumb: t(type.plural)
    ) {
      statusBadge(status)
      if type == .salesOrder, let delivery = doc?.text("deliveryStatus") {
        Badge(status: StatusMeta.delivery(delivery))
      }
    } actions: {
      if let doc {
        DcDocumentActions(type: type, doc: doc, state: actionState)
      }
      if let contactId, !contactId.isEmpty {
        WebButton(
          type.isPurchase ? t("Open vendor") : t("Open client"), icon: .userRound, variant: .outline, size: .sm
        ) {
          router.push(.contact(type.isPurchase ? .vendor : .customer, id: contactId))
        }
      }
    } content: {
      if let doc {
        InfoCard(t("Summary"), rows: summary(doc, status: status, format: format, currency: currency))
        DocumentLinesCard(doc: doc, type: type, format: format, currency: currency)
        TextCard(title: t("Introduction"), text: doc.text("intro"))
        TextCard(title: t("Notes"), text: doc.text("notes"))
        TextCard(title: t("Terms"), text: doc.text("terms"))
        TextCard(title: t("Private notes"), text: doc.text("privateNotes"))
        DocumentPaymentsCard(doc: doc, format: format)
        DocumentLinksCard(doc: doc, format: format)
      }
    }
    .modifier(DcActionDialogs(state: actionState))
  }
}

extension DocumentPage {
  /// The summary card's rows: dates, references, the totals and what happened to it.
  func summary(_ doc: JSONValue, status: String, format: CompanyFormat, currency: String) -> [InfoRow] {
    let totals = doc.obj("totals")
    let money = { (value: Double) in format.money(value, currency) }
    let optional = { (value: Double) in value == 0 ? "" : money(value) }
    var rows = [
      InfoRow(t("Issue date"), format.date(doc.text("issueDate"))),
      InfoRow(t(type.secondDateLabel), format.date(type.secondDate(doc))),
      InfoRow(
        type.isPurchase ? t("Vendor reference") : t("PO number"),
        doc.str(type.isPurchase ? "vendorReference" : "poNumber")),
      InfoRow(t("Delivery place"), doc.str("deliveryPlace")),
      InfoRow(t("Received by"), doc.str("receiverName")),
      InfoRow(t("Currency"), currency == format.currency ? "" : currency),
    ]
    if type.priced {
      let balance = totals?.num("balance") ?? 0
      let owes: [DocType] = [.invoice, .bill, .credit, .vendorCredit]
      rows.append(InfoRow(t("Subtotal"), money(totals?.num("subtotal") ?? 0), tabular: true))
      rows.append(InfoRow(t("Discount"), optional(-(totals?.num("discount") ?? 0)), tabular: true))
      rows.append(InfoRow(t("Tax"), optional(totals?.num("taxTotal") ?? 0), tabular: true))
      rows.append(InfoRow(t("Total"), money(totals?.num("total") ?? 0), strong: true, tabular: true))
      rows.append(InfoRow(t("Deposit"), optional(doc.num("deposit")), tabular: true))
      rows.append(InfoRow(t("Paid"), optional(totals?.num("paid") ?? 0), tabular: true))
      rows.append(
        InfoRow(
          t("Balance"), owes.contains(type) ? money(balance) : "", strong: true, tabular: true,
          tone: balance > 0 && status == "overdue" ? .red(600) : nil))
    }
    rows.append(InfoRow(t("Sent"), format.dateTime(doc.text("sentAt"))))
    rows.append(InfoRow(t("Voided"), format.dateTime(doc.text("voidedAt"))))
    rows.append(InfoRow(t("Reason"), doc.str("voidReason")))
    return rows
  }
}

/// The document's lines: each item's name and description, "quantity unit ×
/// price" and its amount; section headings in between.
struct DocumentLinesCard: View {
  let doc: JSONValue
  let type: DocType
  let format: CompanyFormat
  let currency: String
  @Environment(\.palette) private var palette

  var body: some View {
    let lines = doc.list("items")
    if !lines.isEmpty {
      Card {
        CardHeader(t("Items"))
        VStack(spacing: 0) {
          ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            if line.str("kind") == "heading" {
              Text(localName(line))
                .font(.web(13, .semibold))
                .foregroundStyle(palette.slate(600))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 6)
            } else {
              HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                  Text(localName(line))
                    .font(.web(14, .medium))
                    .foregroundStyle(palette.slate(900))
                  if let description = line.text("description") {
                    Text(description)
                      .font(.web(12))
                      .foregroundStyle(palette.slate(500))
                      .lineLimit(3)
                  }
                  Text(quantityText(line))
                    .font(.web(12, tabular: true))
                    .foregroundStyle(palette.slate(500))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if type.priced {
                  Text(format.money(DocRules.lineAmount(line), currency))
                    .font(.web(14, .semibold, tabular: true))
                    .foregroundStyle(palette.slate(900))
                    .environment(\.layoutDirection, .leftToRight)
                }
              }
              .padding(.horizontal, 20)
              .padding(.vertical, 12)
              .overlay(alignment: .top) {
                if index > 0 { Rectangle().fill(palette.slate(100)).frame(height: 1) }
              }
            }
          }
        }
        .padding(.bottom, 4)
      }
    }
  }

  private func quantityText(_ line: JSONValue) -> String {
    let quantity = format.quantity(line.num("quantity"))
    let unit = line.str("unit")
    let counted = unit.isEmpty ? quantity : "\(quantity) \(unit)"
    guard type.priced else { return counted }
    var text = "\(counted) × \(format.money(line.num("unitPrice"), currency))"
    if line.num("discount") > 0 {
      let off = line.str("discountType") == "amount"
        ? format.money(line.num("discount"), currency) : format.percent(line.num("discount"))
      text += " · " + t("Discount") + " " + off
    }
    return text
  }
}

/// The payments that settle this document (`allocations`), each opening its page.
struct DocumentPaymentsCard: View {
  let doc: JSONValue
  let format: CompanyFormat
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let id = doc.rid
    let payments = model.one.records(.payments).filter { payment in
      payment.list("allocations").contains { $0.str("documentId") == id }
        || payment.list("documentIds").contains { $0.string == id }
    }
    .sorted { $0.str("date") > $1.str("date") }
    RelatedCard(t("Payments"), records: payments.map(Rec.init)) { record in
      let payment = record.raw
      let applied = payment.list("allocations").first { $0.str("documentId") == id }?.num("amount")
      ListRow(
        title: payment.text("number") ?? t("Payment"),
        subtitle: format.date(payment.text("date")),
        amount: format.money(applied ?? payment.num("amount"), payment.text("currency"))
      ) {
        if payment.flag("voided") { statusBadge("void") }
      } action: {
        let direction: PaymentDirection = payment.str("direction") == "out" ? .made : .received
        router.push(.payment(direction, id: payment.rid))
      }
    }
  }
}

/// What the document came from, turned into, replaces or was replaced by.
struct DocumentLinksCard: View {
  let doc: JSONValue
  let format: CompanyFormat
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    RelatedCard(t("Related documents"), records: linked.map(Rec.init)) { record in
      let other = record.raw
      let type = DocType(rawValue: other.str("type")) ?? .invoice
      ListRow(
        title: "\(t(type.singular)) \(other.text("number") ?? t("Draft"))",
        subtitle: format.date(other.text("issueDate")),
        amount: type.priced ? format.money(other.obj("totals")?.num("total") ?? 0, other.text("currency")) : nil
      ) {
        statusBadge(DocRules.displayStatus(other))
      } action: {
        router.push(type.route(other.rid))
      }
    }
  }

  private var linked: [JSONValue] {
    let one = model.one
    let id = doc.rid
    var found: [JSONValue] = []
    for key in ["sourceId", "convertedToId", "replacesId", "replacedById"] {
      if let other = doc.text(key), let record = one.record(.documents, other) { found.append(record) }
    }
    // Documents made from this one (invoices from an order, notes from an invoice).
    let ids = Set(found.map(\.rid))
    found += one.records(.documents).filter { $0.str("sourceId") == id && !ids.contains($0.rid) }
    return found
  }
}
