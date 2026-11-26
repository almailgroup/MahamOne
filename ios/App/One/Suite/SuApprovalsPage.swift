import MahamKit
import SwiftUI

// Approval requests (`src/pages/approvals.tsx`, `src/features/approvals`):
// changes waiting for an approver, the person's own requests and the
// decided ones. Read only here: they are decided on the web.

enum SuApprovals {
  /// What each kind of request asks for (English keys).
  static func kindLabel(_ kind: String) -> String {
    switch kind {
    case "invoice_edit": "Change to an issued document"
    case "invoice_void": "Void"
    case "invoice_unvoid": "Restore from void"
    case "cheque_create": "New cheque"
    case "cheque_edit": "Change to a cheque"
    case "cheque_delete": "Cheque deleted"
    case "cheque_replace": "Cheque replaced"
    case "security_cheque_cash": "Security cheque cashed"
    case "payroll": "Pay run"
    case "letter": "Employee letter"
    case "stock_issue": "Items issued"
    default: "Approval request"
    }
  }

  /// A request's state: its words and tone.
  static func status(_ status: String) -> StatusMeta {
    switch status {
    case "pending": StatusMeta(label: "Waiting for approval", tone: .amber)
    case "approved": StatusMeta(label: "Approved", tone: .blue)
    case "rejected": StatusMeta(label: "Rejected", tone: .red)
    case "cancelled": StatusMeta(label: "Cancelled", tone: .gray)
    case "applied": StatusMeta(label: "Approved and done", tone: .green)
    default: StatusMeta(label: "Approval request", tone: .gray)
    }
  }

  /// What each field of a document is called (`FIELD_LABELS`).
  static let fieldLabels: [String: String] = [
    "type": "Document type", "number": "Number", "clientId": "Customer", "issueDate": "Issue date",
    "dueDate": "Due date", "poNumber": "PO number", "vendorReference": "Vendor reference", "currency": "Currency",
    "exchangeRate": "Exchange rate", "items": "Lines", "discount": "Discount", "discountType": "Discount type",
    "taxes": "Taxes", "charges": "Charges", "pricesIncludeTax": "Prices include tax", "deposit": "Deposit requested",
    "depositDueDate": "Deposit due", "notes": "Notes", "terms": "Terms", "footer": "Footer", "intro": "Introduction",
    "templateId": "Template", "accentColor": "Colour of this document", "deliveryDate": "Delivery date",
    "deliveryPlace": "Delivery place", "retentionPercent": "Retention", "retentionKind": "Retention kind",
    "replacesNumber": "Replaces",
  ]

  /// The fields an edit request changes, in the order a document shows them.
  static func changes(_ request: JSONValue) -> [SuFieldChange] {
    guard request.str("kind") == "invoice_edit" else { return [] }
    let before = request["before"]
    let after = request["after"]
    return Roles.invoiceContentFields.compactMap { (field: String) -> SuFieldChange? in
      let old = before?[field]
      let asked = after?[field]
      if Roles.sameData(old, asked) { return nil }
      return SuFieldChange(field: field, label: fieldLabels[field] ?? field, before: old, after: asked)
    }
  }

  /// The requests the person may see, as the tab shows them.
  static func shown(_ all: [JSONValue], tab: String, userId: String) -> [JSONValue] {
    switch tab {
    case "waiting":
      return all.filter { $0.str("status") == "pending" }.sorted { $0.str("requestedAt") < $1.str("requestedAt") }
    case "mine":
      return all.filter { $0.str("requestedBy") == userId }.sorted(by: newest)
    default:
      return Array(all.filter { $0.str("status") != "pending" }.sorted(by: newest).prefix(100))
    }
  }

  static func newest(_ a: JSONValue, _ b: JSONValue) -> Bool {
    (a.text("decidedAt") ?? a.str("requestedAt")) > (b.text("decidedAt") ?? b.str("requestedAt"))
  }
}

/// A field a request changes: what it says now and what is asked for.
struct SuFieldChange: Identifiable {
  let field: String
  let label: String
  let before: JSONValue?
  let after: JSONValue?
  var id: String { field }
}

/// `/approvals`: Waiting, Asked by me and Decided.
struct SuApprovalsPage: View {
  @Environment(AppModel.self) private var model
  @State private var tab = "waiting"

  var body: some View {
    let role = SuRole(model)
    // Requests about People data stay out of sight of those who don't see People.
    let all = model.one.records(.approvals).filter {
      role.seesPeople || !Privacy.isPrivateRecord("approvals", $0)
    }
    let shown = SuApprovals.shown(all, tab: tab, userId: role.userId)
    let waiting = all.filter { $0.str("status") == "pending" }.count
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(
        t("Approval requests"),
        description: t(
          "Changes to issued documents that wait for the owner or a member the owner allowed to approve."))
      if suLoading(model, empty: all.isEmpty) {
        SuLoadingCard()
      } else {
        ListCard {
          Segmented(
            selection: $tab,
            options: [
              SegmentOption("waiting", t("Waiting"), count: waiting),
              SegmentOption("mine", t("Asked by me")),
              SegmentOption("decided", t("Decided")),
            ])
        } rows: {
          if shown.isEmpty {
            WebEmptyState(
              icon: .clipboardCheck,
              title: tab == "waiting" ? t("Nothing is waiting for approval.") : t("No requests yet."),
              description: role.approver
                ? t("Changes that need your approval show here.")
                : t("Changes you send for approval show here until they are decided."))
          } else {
            ForEach(shown.map(Rec.init)) { record in
              SuRow {
                SuRequestCard(request: record.raw)
              }
            }
          }
        }
        if !role.readOnly {
          HStack {
            Spacer(minLength: 0)
            SuWebButton(t("Open on the web"), path: "/approvals")
          }
          .padding(.top, 16)
        }
      }
    }
  }
}

/// One request: what is asked and about what, its state, who asked and
/// when, why, the fields it changes, and the decision.
private struct SuRequestCard: View {
  let request: JSONValue
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let meta = SuApprovals.status(request.str("status"))
    let format = model.one.format
    let changes = SuApprovals.changes(request)
    VStack(alignment: .leading, spacing: 12) {
      FlowLayout(spacing: 8, lineSpacing: 6) {
        Text(t(SuApprovals.kindLabel(request.str("kind"))))
          .font(.web(16, .medium))
          .foregroundStyle(palette.slate(900))
        subject
        Badge(status: meta)
        if request.flag("expired") { Badge(t("Expired"), tone: .gray) }
      }
      Text(t("Asked by {name} · {date}", ["name": askedBy, "date": format.dateTime(request.text("requestedAt"))]))
        .font(.web(12))
        .foregroundStyle(palette.slate(500))
      if let reason = request.text("reason") {
        Text(reason)
          .font(.web(14))
          .foregroundStyle(palette.slate(700))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(palette.slate(50), in: RoundedRectangle(cornerRadius: WebRadius.sm, style: .continuous))
      }
      if !changes.isEmpty {
        SuChangesTable(changes: changes)
      }
      if pending, let doc, changedSinceAsked(doc) {
        Text(t("The document has changed since this was asked. Approving changes only what was asked for."))
          .font(.web(12))
          .foregroundStyle(palette[.amber(700)])
      }
      if let decided = request.text("decidedAt"), !pending {
        Text(decision(meta, decided: decided, format: format))
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
      }
      if request.str("status") == "approved" {
        Text(
          t(
            "Approved, but not carried out yet on this device. Carry it out again, or reject it if it can’t be carried out."
          )
        )
        .font(.web(12))
        .foregroundStyle(palette[.amber(700)])
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }

  private var pending: Bool { request.str("status") == "pending" }

  /// The document it is about, when it is on this iPhone.
  private var doc: JSONValue? {
    guard request.str("subjectTbl") == "documents" else { return nil }
    return model.one.record(.documents, request.str("subjectId"))
  }

  /// "Invoice INV-0042", opening the document when it is here.
  @ViewBuilder
  private var subject: some View {
    let number = request.str("subjectNumber")
    if let doc, let type = DocType(rawValue: doc.str("type")) {
      SuLink("\(t(type.singular)) \(number)") { router.push(type.route(doc.rid)) }
    } else if !number.isEmpty {
      Text(verbatim: "\(subjectLabel) \(number)").font(.web(14)).foregroundStyle(palette.slate(600))
    }
  }

  private var subjectLabel: String {
    let type = request["after"]?["type"]?.string ?? ""
    switch request.str("subjectTbl") {
    case "documents": return DocType(rawValue: type).map { t($0.singular) } ?? t("Document")
    case "payments", "securityCheques": return t("Cheque")
    case "payRuns": return t("Pay run")
    case "employeeLetters": return t("Letter")
    default: return ""
    }
  }

  /// The team's names aren't on this iPhone: the name kept with the request, or "A team member".
  private var askedBy: String {
    if request.str("requestedBy") == SuRole(model).userId, let email = model.session?.user.email { return email }
    return request.text("requestedByName") ?? t("A team member")
  }

  private func decision(_ meta: StatusMeta, decided: String, format: CompanyFormat) -> String {
    let line = t(
      "{status} by {name} · {date}",
      ["status": t(meta.label), "name": t("A team member"), "date": format.dateTime(decided)])
    return suJoin([line, request.text("decisionNote")])
  }

  /// The document changed in what the request is about since it was asked.
  private func changedSinceAsked(_ doc: JSONValue) -> Bool {
    guard request.str("kind") == "invoice_edit", let before = request["before"] else { return false }
    return Roles.invoiceContentFields.contains { field in
      before[field] != nil && !Roles.sameData(before[field], doc[field])
    }
  }
}

/// "Field / Now / Asked for".
private struct SuChangesTable: View {
  let changes: [SuFieldChange]
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
      GridRow {
        Text(t("Field"))
        Text(t("Now"))
        Text(t("Asked for"))
      }
      .font(.web(12, .medium))
      .foregroundStyle(palette.slate(500))
      ForEach(changes) { change in
        Rectangle().fill(palette.slate(100)).frame(height: 1).gridCellUnsizedAxes(.horizontal)
        GridRow {
          Text(t(change.label)).font(.web(14)).foregroundStyle(palette.slate(600))
          Text(written(change.before, field: change.field)).font(.web(14)).foregroundStyle(palette.slate(500))
          Text(written(change.after, field: change.field))
            .font(.web(14, .medium))
            .foregroundStyle(palette.slate(900))
        }
      }
    }
  }

  /// A value as the request card writes it.
  private func written(_ raw: JSONValue?, field: String) -> String {
    guard let raw, !raw.isNull, raw.string != "" else { return "—" }
    let format = model.one.format
    if field == "clientId", let id = raw.string {
      let name = model.one.contactName(id)
      return name.isEmpty ? t("Another customer") : name
    }
    if field == "items", let lines = raw.array { return tp(lines.count, "{count} line", "{count} lines") }
    if let flag = raw.bool { return flag ? t("Yes") : t("No") }
    if let text = raw.string { return ISODates.isISODate(text) ? format.date(text) : text }
    if let number = raw.double { return Money.jsString(number) }
    return t("Changed")
  }
}
