import MahamKit
import SwiftUI

// The document editor (`src/apps/books/pages/documents/editor.tsx` for the
// six sales types, `purchases/bill-editor.tsx` for bills, vendor credits and
// purchase orders) on a phone: the header fields, the lines, the totals and
// the notes, with Cancel and Save in the bar at the bottom. Saving goes
// through the port of the web's `saveDocument` (MahamKit/Write/Documents),
// with a number from the cloud's counter when the web would take one.

extension DocType {
  /// `DOCUMENT_LABELS[type].numberLabel`.
  var numberLabel: String {
    switch self {
    case .invoice: "Invoice number"
    case .quote: "Quote number"
    case .credit: "Credit note number"
    case .proforma: "Proforma number"
    case .salesOrder: "Order number"
    case .deliveryNote: "Delivery note number"
    case .bill: "Bill number"
    case .vendorCredit: "Vendor credit number"
    case .purchaseOrder: "PO number"
    }
  }

  /// Who the document is for, as the contact field calls it.
  var contactLabel: String {
    switch self {
    case .quote: "Prepared for"
    case .salesOrder, .deliveryNote: "Customer"
    case .bill, .vendorCredit, .purchaseOrder: "Vendor"
    default: "Bill to"
    }
  }

  /// Quotes and proformas are valid until a date; invoices and bills are due on one.
  var validity: Bool { self == .quote || self == .proforma }
  var dated: Bool { self == .invoice || self == .bill || validity }
}

/// A contact to create from the editor's "New client" / "New vendor".
struct DcNewContact: Identifiable {
  let id = UUID()
  let name: String
  let kind: ContactKind
}

struct DcEditorPage: View {
  let type: DocType
  let id: String?
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @State private var doc: JSONValue?
  @State private var original: JSONValue?
  @State private var defaultTaxes: [JSONValue] = []
  @State private var missing = false
  @State private var errors: [String: String] = [:]
  @State private var saving: String?
  @State private var numberHint = ""
  @State private var confirm: DcConfirm?
  @State private var newContact: DcNewContact?
  @State private var asking: DcApprovalRequired?
  @State private var reason = ""
  @State private var reasonError: String?
  @State private var sending = false

  init(type: DocType, id: String?) {
    self.type = type
    self.id = id
  }

  var body: some View {
    content
      .task(id: model.one.revision) { await load() }
      .task(id: hintKey) { await suggest() }
      .dcConfirm($confirm)
      .sheet(item: $newContact) { request in
        DcContactSheet(kind: request.kind, name: request.name) { saved in
          selectContact(saved.rid, picked: saved)
        }
        .environment(model)
        .environment(router)
        .webTheme()
      }
      .webDialog(
        isPresented: askingShown,
        title: t("Send the change of {number} for approval?", ["number": doc?.str("number") ?? ""]),
        description: t(
          "{number} has been issued, so an approver decides on this change. It stays as it is until they approve.",
          ["number": doc?.str("number") ?? ""])
      ) {
        Field(t("Reason"), error: reasonError) {
          DcTextArea(text: $reason, lines: 3)
        }
      } footer: {
        WebButton(t("Cancel"), variant: .outline) { asking = nil }
        WebButton(t("Send for approval"), icon: .send, loading: sending) {
          Task { await sendForApproval() }
        }
      }
  }

  @ViewBuilder
  private var content: some View {
    if let doc {
      DcEditorForm(
        type: type, isNew: id == nil, doc: docBinding(doc), errors: $errors, numberHint: numberHint,
        defaultTaxes: defaultTaxes, saving: saving, sendsForApproval: sendsForApproval(doc),
        onContact: { selectContact($0, picked: model.one.record(.clients, $0)) },
        onNewContact: { name in newContact = DcNewContact(name: name, kind: type.isPurchase ? .vendor : .customer) },
        onCancel: { cancel() }, onSave: { intent in Task { await save(intent) } })
    } else if missing {
      WebPage {
        Card {
          WebEmptyState(
            icon: .fileSearch, title: t("This document could not be found."),
            description: t("Back to {list}", ["list": t(type.plural).lowercased()]))
        }
      }
    } else {
      WebPage { Card { DataLoadingRow() } }
    }
  }

  private func docBinding(_ fallback: JSONValue) -> Binding<JSONValue> {
    Binding(get: { doc ?? fallback }, set: { doc = $0 })
  }

  private var askingShown: Binding<Bool> {
    Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })
  }

  private var dirty: Bool { doc != nil && doc != original }

  /// When the number shown as a hint is worked out again.
  private var hintKey: String {
    "\(doc?.str("issueDate") ?? "")|\(doc?.str("clientId") ?? "")|\(doc?.str("number").isEmpty ?? true)"
  }

  // MARK: Loading

  private func load() async {
    guard doc == nil, !missing else { return }
    let one = model.one
    if let id {
      guard let found = one.record(.documents, id), found.str("type") == type.rawValue else {
        missing = one.hasData && one.phase == .ready
        return
      }
      doc = found
      original = found
    } else {
      guard let company = one.company else { return }
      let kind = type
      do {
        let draft = try await one.write { ctx in DcEditorPage.newDraft(ctx, company: company, type: kind) }
        doc = draft
        original = draft
      } catch {
        DcWrite.fail(model, error)
      }
    }
    if let company = one.company {
      defaultTaxes = (try? await one.write { ctx in DcDocuments.defaultTaxes(ctx, company) }) ?? []
    }
  }

  /// `draftDocument`, with the bill editor's expense account on each line.
  nonisolated static func newDraft(_ ctx: WriteContext, company: JSONValue, type: DocType) -> JSONValue {
    let draft = DcDocuments.draftDocument(ctx, company: company, type: type.rawValue, client: nil)
    guard type.isPurchase else { return draft }
    let companyId = company.rid
    let expense = ctx.all("accounts") { $0.str("companyId") == companyId && $0.str("role") == "expense" }.first
    guard let expense else { return draft }
    let items = draft.list("items").map { DcDocuments.applying($0, [("accountId", .string(expense.rid))]) }
    return DcDocuments.applying(draft, [("items", .array(items))])
  }

  /// The number a new document would get (`suggestNumber`), shown until it has one.
  private func suggest() async {
    guard let doc, doc.str("number").isEmpty, let company = model.one.company else { return }
    let contact = model.one.record(.clients, doc.str("clientId"))
    let date = doc.str("issueDate")
    let kind = type.rawValue
    numberHint =
      (try? await model.one.write { ctx in
        DcDocuments.suggestNumber(
          ctx, company: company, type: kind, issueDate: date, clientNumber: contact?.str("number") ?? "")
      }) ?? ""
  }

  // MARK: The contact

  /// `selectClient`: the contact's currency, terms and retention for a new document.
  private func selectContact(_ contactId: String, picked: JSONValue?) {
    guard var next = doc else { return }
    errors["client"] = nil
    let company = model.one.company
    if contactId != next.str("clientId") { next.set("posting", nil) }
    next.set("clientId", .string(contactId))
    if let picked {
      let paid = next.obj("totals")?.num("paid") ?? 0
      if id == nil || paid == 0 {
        let currency = picked.text("currency") ?? company?.str("currency") ?? "KWD"
        next.set("currency", .string(currency))
      }
      if id == nil, type == .invoice || type == .bill {
        let days = picked.number("paymentTermsDays") ?? company?.obj("defaults")?.number("paymentTermsDays") ?? 0
        next.set("dueDate", .string(ISODates.addDays(next.str("issueDate"), Int(days.rounded(.towardZero)))))
        next = DcDocuments.applying(
          next, DcRules.retentionDefaults(picked, type: type.rawValue, issueDate: next.str("issueDate")))
      }
    }
    doc = next
  }

  // MARK: Approvals

  /// Saving an issued document the company's rules keep for approvers sends the change for approval.
  private func sendsForApproval(_ doc: JSONValue) -> Bool {
    id != nil && DcApprovals.waitsForApproval(model.one.company, model.one.writeLink, doc)
  }

  private func sendForApproval() async {
    guard let request = asking, let kind = request.kind else { return }
    let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    if why.isEmpty {
      reasonError = t("Say why, for the approver.")
      return
    }
    sending = true
    defer { sending = false }
    let link = model.one.writeLink
    do {
      try await model.one.write { ctx in
        try DcApprovals.requestApproval(
          ctx, kind: kind, subject: request.subject, proposal: request.proposal, reason: why, byName: ctx.userName,
          link: link)
      }
      model.confirm(t("Sent for approval"))
      asking = nil
      original = doc
      router.back()
    } catch {
      DcWrite.fail(model, error)
    }
  }

  // MARK: Saving

  private func cancel() {
    if dirty {
      confirm = DcConfirm(
        title: t("Discard unsaved changes?"), description: t("You have changes that have not been saved yet."),
        confirmLabel: t("Discard changes"), cancelLabel: t("Keep editing"), danger: true
      ) { router.back() }
    } else {
      router.back()
    }
  }

  /// `save(intent)`: checks the fields, the client's credit, then saves; "sent" marks it as sent too.
  private func save(_ intent: String) async {
    guard let doc, saving == nil else { return }
    let one = model.one
    var found: [String: String] = [:]
    if doc.str("clientId").isEmpty {
      found["client"] = type.isPurchase ? t("Choose the vendor.") : t("Choose who this is for.")
    }
    if !DcEditorPage.hasContent(doc, purchase: type.isPurchase) {
      found["items"] = type.isPurchase ? t("Add at least one line.") : t("Add at least one item.")
    }
    let number = doc.str("number")
    if !number.trimmingCharacters(in: .whitespaces).isEmpty, let company = one.company {
      let kind = type.rawValue
      let docId = doc.rid
      let taken =
        (try? await one.write { ctx in
          DcDocuments.isNumberTaken(ctx, companyId: company.rid, type: kind, number: number, except: docId)
        }) ?? false
      if taken { found["number"] = t("This number is already used.") }
    }
    errors = found
    if !found.isEmpty {
      model.toast = Toast(kind: .error, message: t("Please fix the highlighted fields."))
      return
    }
    // Customers on credit hold, or going over their limit, need a confirmation.
    if let question = DcCredit.question(doc, one: one) {
      confirm = DcConfirm(
        title: question.title, description: question.description, confirmLabel: question.confirmLabel,
        danger: question.danger
      ) { Task { await perform(intent, doc) } }
      return
    }
    await perform(intent, doc)
  }

  /// The lines saved: empty ones dropped, as the web drops them.
  nonisolated static func hasContent(_ doc: JSONValue, purchase: Bool) -> Bool {
    doc.list("items").contains { line in
      guard line.str("kind") == "item" else { return false }
      let named = !line.str("name").trimmingCharacters(in: .whitespaces).isEmpty
      let described = !line.str("description").trimmingCharacters(in: .whitespaces).isEmpty
      return named || (!purchase && described) || line.num("unitPrice") != 0
    }
  }

  /// What is saved: the lines and charges kept, and for the purchase editor the status it takes.
  nonisolated static func cleaned(_ doc: JSONValue, type: DocType, intent: String) -> JSONValue {
    let trimmed = { (value: String) in !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let items = doc.list("items").filter { line in
      if type.isPurchase { return trimmed(line.str("name")) || line.num("unitPrice") != 0 }
      if line.str("kind") == "heading" { return trimmed(line.str("name")) || trimmed(line.str("description")) }
      return trimmed(line.str("name")) || trimmed(line.str("description")) || line.num("unitPrice") != 0
    }
    let charges = doc.list("charges").filter { trimmed($0.str("label")) || $0.num("amount") != 0 }
    var patch: DcPatch = [("items", .array(items)), ("charges", .array(charges))]
    if type.isPurchase {
      // Saving takes a draft out of the office: an open bill, an issued order.
      let status = doc.str("status")
      let next: String =
        intent == "draft" ? "draft" : status == "draft" ? (DcRules.issuedStatus(type.rawValue) ?? status) : status
      patch.append(("status", .string(next)))
    }
    return DcDocuments.applying(doc, patch)
  }

  private func perform(_ intent: String, _ doc: JSONValue) async {
    saving = intent
    defer { saving = nil }
    let one = model.one
    let link = one.writeLink
    let input = DcEditorPage.cleaned(doc, type: type, intent: intent)
    do {
      let request = try await one.write { ctx in DcDocuments.counterRequest(ctx, input) }
      let reserved = await one.reserveNumber(request)
      let saved = try await one.write { ctx in
        try DcDocuments.saveDocument(ctx, input, reserved: reserved, link: link)
      }
      if intent == "sent" && !type.isPurchase && saved.str("status") == "draft",
        let status = DcRules.issuedStatus(type.rawValue)
      {
        let savedId = saved.rid
        let issue = try await one.write { ctx in DcDocuments.issueCounterRequest(ctx, id: savedId, status: status) }
        let counter = await one.reserveNumber(issue)
        try await one.write { ctx in try DcDocuments.markSent(ctx, id: savedId, reserved: counter, link: link) }
      }
      let issued = one.record(.documents, saved.rid) ?? saved
      model.confirm(DcWrite.savedText(type, number: issued.str("number")))
      original = self.doc
      finish(issued)
    } catch let approval as DcApprovalRequired {
      // Kept for approvers: asked why, then sent for approval.
      if approval.kind != nil {
        reason = ""
        reasonError = nil
        asking = approval
      } else {
        DcWrite.fail(model, approval)
      }
    } catch {
      if let failure = error as? WriteFailure, failure.message == "The number {number} is already used by another document." {
        errors["number"] = t("This number is already used.")
      }
      DcWrite.fail(model, error)
    }
  }

  /// Back to the document's own page.
  private func finish(_ saved: JSONValue) {
    let page = DcWrite.viewRoute(saved)
    router.back()
    if router.current != page { router.push(page) }
  }
}

/// The confirmation a credit hold or a credit limit asks for (`useCreditCheck`).
struct DcCreditQuestion {
  let title: String
  let description: String
  let confirmLabel: String
  let danger: Bool
}

@MainActor
enum DcCredit {
  /// `creditCheck` before an invoice or sales order is saved.
  static func question(_ doc: JSONValue, one: OneData) -> DcCreditQuestion? {
    let type = doc.str("type")
    guard type == "invoice" || type == "sales_order", let client = one.record(.clients, doc.str("clientId")) else {
      return nil
    }
    let limited = client.number("creditLimit") != nil
    if !client.flag("creditHold") && !limited { return nil }
    let company = one.company
    let currency = company?.str("currency") ?? "KWD"
    let clientId = client.rid
    let documents = one.records(.documents).filter { $0.str("clientId") == clientId }
    let payments = one.records(.payments).filter { $0.str("clientId") == clientId }
    let saved = one.record(.documents, doc.rid)
    let position = CtStatements.position(
      side: .customer, contact: client, documents: documents, payments: payments, companyCurrency: currency,
      today: ISODates.today())
    let exempt = DcCalc.documentTaxExempt(doc, contact: client)
    let increase = exposureIncrease(doc, saved: saved, currency: currency, taxExempt: exempt)
    if increase <= 0 && saved != nil { return nil }
    let projected = position.exposure + max(increase, 0)
    let format = one.format
    let money = { (minor: Int64) in format.money(Money.toNumber(Money.fromMinor(minor, position.precision))) }
    let noun = t((DocType(rawValue: type) ?? .invoice).singular).lowercased()
    if client.flag("creditHold") {
      return DcCreditQuestion(
        title: t("{name} is on credit hold", ["name": client.str("name")]),
        description: t(
          "Save this {document} anyway? What they owe, with cheques not yet cleared, would be {amount}.",
          ["document": noun, "amount": money(projected)]),
        confirmLabel: t("Override and save"), danger: true)
    }
    guard let limit = position.limit, increase > 0, projected > limit else { return nil }
    return DcCreditQuestion(
      title: t("This takes {name} over their credit limit", ["name": client.str("name")]),
      description: t(
        "Credit used would be {projected}: {over} over the limit of {limit}.",
        ["projected": money(projected), "over": money(projected - limit), "limit": money(limit)]),
      confirmLabel: t("Save anyway"), danger: false)
  }

  /// `exposureIncrease`: what saving adds to what the customer owes, in company minor units.
  static func exposureIncrease(_ doc: JSONValue, saved: JSONValue?, currency: String, taxExempt: Bool) -> Int64 {
    let p = Money.precision(currency)
    func value(_ d: JSONValue) -> Int64 {
      let result = DcCalc.computeDocument(d, paid: d.obj("totals")?.num("paid") ?? 0, taxExempt: taxExempt)
      let due = d.str("type") == "sales_order" ? result.total : result.balance
      let rate = d.str("currency") == currency ? 1 : (d.number("exchangeRate").flatMap { $0 == 0 ? nil : $0 } ?? 1)
      return Money.toMinor(Money.dec(due) * Money.dec(rate), p)
    }
    var before: Int64 = 0
    if let saved, saved.str("type") == "invoice", CtStatements.counted(saved) { before = value(saved) }
    return value(doc) - before
  }
}
