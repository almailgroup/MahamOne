import MahamKit
import SwiftUI
import UIKit

// What a document's page can do to it (`view.tsx` for the sales types,
// `bill-view.tsx` for purchases): the main next step, then the More menu
// (mark as sent or accepted, convert, deliver, duplicate, void, restore,
// issue again, cancel, delete), with the web's confirmations and words.
// Sending by email, payments and PDFs belong to their own areas.

/// A reason asked for before a void or a request for approval (`ReasonDialog`).
struct DcReasonAsk {
  let title: String
  let description: String
  var label: String = t("Reason")
  var required = true
  let confirmLabel: String
  var danger = false
  let run: (String) async throws -> Void
}

/// Part of an order to invoice, bill or deliver (`PartDialog`).
struct DcPartAsk {
  let doc: JSONValue
  let target: String
  let progress: [DcLineProgress]
}

/// The state of a document page's actions and dialogs.
@MainActor
@Observable
final class DcActionState {
  var busy: String?
  var confirm: DcConfirm?
  var reason: DcReasonAsk?
  var reasonText = ""
  var reasonError: String?
  var reasonBusy = false
  var part: DcPartAsk?
  var quantities: [String: Double] = [:]
  var partBusy = false
  var delivering: JSONValue?
  var deliverDate = ""
  var receiverName = ""
  var civilId = ""
  var deliverErrors: [String: String] = [:]
  var deliverBusy = false
}

/// The actions, worked out from the document as it stands.
@MainActor
struct DcActionRunner {
  let model: AppModel
  let router: ShellRouter
  let state: DcActionState
  let type: DocType
  let doc: JSONValue

  var one: OneData { model.one }
  var link: DcLink? { one.writeLink }
  var company: JSONValue? { one.company }

  /// A read of the company for working out what an action may do.
  func reading<T>(_ body: (WriteContext) -> T) -> T? {
    guard let companyId = one.companyId else { return nil }
    var tables: [String: [String: JSONValue]] = [:]
    for kind in [RecordKind.documents, .companies, .clients] {
      var byId: [String: JSONValue] = [:]
      for record in one.records(kind) { byId[record.rid] = record }
      tables[kind.rawValue] = byId
    }
    let snapshot = tables
    let read = WriteContext(
      companyId: companyId, userId: nil, role: .owner, records: { snapshot[$0] ?? [:] })
    return body(read)
  }

  /// The payments of the document (credit notes: their applications).
  var payments: [JSONValue] {
    guard DcRules.postsToLedger(type.rawValue) else { return [] }
    let id = doc.rid
    let credit = type == .credit || type == .vendorCredit
    return one.records(.payments).filter { payment in
      credit ? payment.str("creditId") == id : payment.list("documentIds").contains(.string(id))
    }
  }

  var creditsNote: String {
    guard payments.contains(where: { $0.str("method") == "credit_note" }) else { return "" }
    switch type {
    case .credit: return t("It is taken off the invoices it was applied to, so they are owed again.")
    case .vendorCredit: return t("It is taken off the bills it was applied to, so they are owed again.")
    case .bill: return t("Vendor credits applied to it are taken off, so they can be used again.")
    default: return t("Credit notes applied to it are taken off, so they can be used again.")
    }
  }

  var moneyPaid: Bool {
    payments.contains { $0.str("method") != "credit_note" && !$0.flag("voided") }
  }

  static func joined(_ parts: [String]) -> String {
    parts.filter { !$0.isEmpty }.joined(separator: " ")
  }

  // MARK: Running

  func run(_ key: String, _ action: @escaping () async throws -> Void) {
    guard state.busy == nil else { return }
    state.busy = key
    Task { @MainActor in
      defer { state.busy = nil }
      do {
        try await action()
      } catch {
        DcWrite.fail(model, error)
      }
    }
  }

  /// The new document's toast, then its page (or its editor).
  func opened(_ created: JSONValue, edit: Bool) {
    model.confirm(type.isPurchase ? createdPurchaseText(created) : DcWrite.createdText(created))
    let kind = DocType(rawValue: created.str("type")) ?? type
    router.push(edit ? DcWrite.editRoute(kind, id: created.rid) : kind.route(created.rid))
  }

  private func createdPurchaseText(_ created: JSONValue) -> String {
    let kind = DocType(rawValue: created.str("type")) ?? type
    return t("{document} {number} created", ["document": t(kind.singular), "number": created.str("number")])
  }

  /// `setDocumentStatus(id, status)`, with a number from the cloud when it is issued now.
  func setStatus(
    _ status: String, patch: DcPatch = [], freePaid: Bool = false, message: ActivityMessage? = nil
  ) async throws {
    let id = doc.rid
    let request = try await one.write { ctx in DcDocuments.issueCounterRequest(ctx, id: id, status: status) }
    let reserved = await one.reserveNumber(request)
    let link = self.link
    try await one.write { ctx in
      try DcDocuments.setDocumentStatus(
        ctx, id: id, status: status, message: message, patch: patch, freePaid: freePaid, reserved: reserved,
        link: link)
    }
  }

  func markSent() async throws {
    guard let status = DcRules.issuedStatus(type.rawValue), doc.str("status") == "draft" else { return }
    let id = doc.rid
    let request = try await one.write { ctx in DcDocuments.issueCounterRequest(ctx, id: id, status: status) }
    let reserved = await one.reserveNumber(request)
    let link = self.link
    try await one.write { ctx in try DcDocuments.markSent(ctx, id: id, reserved: reserved, link: link) }
  }

  /// A copy saved as a new draft, numbered from the cloud's counter when the web would take one.
  func duplicate(as target: DocType?, overrides: DcPatch) async throws -> JSONValue {
    let id = doc.rid
    let kind = (target ?? type).rawValue
    guard let companyId = one.companyId else { throw WriteFailure("Company not found") }
    let request = try await one.write { ctx in
      DcDocuments.newDraftCounterRequest(ctx, companyId: companyId, type: kind)
    }
    let reserved = await one.reserveNumber(request)
    let link = self.link
    return try await one.write { ctx in
      try DcDocuments.duplicateDocument(
        ctx, id: id, asType: target?.rawValue, overrides: overrides, reserved: reserved, link: link)
    }
  }

  func convert(_ to: DocType) {
    run("convert-\(to.rawValue)") {
      let id = doc.rid
      guard let companyId = one.companyId else { return }
      let request = try await one.write { ctx in
        DcDocuments.newDraftCounterRequest(ctx, companyId: companyId, type: to.rawValue)
      }
      let reserved = await one.reserveNumber(request)
      let link = self.link
      let created = try await one.write { ctx in
        try DcDocuments.convertDocument(ctx, sourceId: id, to: to.rawValue, reserved: reserved, link: link)
      }
      opened(created, edit: false)
    }
  }

  func reissue() async throws -> JSONValue {
    let id = doc.rid
    guard let companyId = one.companyId else { throw WriteFailure("Company not found") }
    let kind = type.rawValue
    let request = try await one.write { ctx in
      DcDocuments.newDraftCounterRequest(ctx, companyId: companyId, type: kind)
    }
    let reserved = await one.reserveNumber(request)
    let link = self.link
    return try await one.write { ctx in try DcDocuments.reissueDocument(ctx, id: id, reserved: reserved, link: link) }
  }

  // MARK: Confirmations

  func remove() {
    let first: String
    if type == .invoice && moneyPaid {
      first = t("Payments recorded against it will be kept as unapplied client credit.")
    } else if type == .bill && moneyPaid {
      first = t("Payments made against it will be kept as an unapplied advance to the vendor.")
    } else {
      first = t("This cannot be undone.")
    }
    let number = doc.str("number")
    state.confirm = DcConfirm(
      title: t("Delete {document} {number}?", ["document": DcWrite.noun(type), "number": number]),
      description: DcActionRunner.joined([first, creditsNote]), confirmLabel: t("Delete"), danger: true
    ) {
      run("delete") {
        let id = doc.rid
        let link = self.link
        try await one.write { ctx in try DcDocuments.deleteDocument(ctx, id: id, link: link) }
        model.confirm(t("{document} deleted", ["document": t(type.singular)]))
        router.back()
      }
    }
  }

  /// Under the rules, or to issue it again, money paid against it becomes the customer's credit.
  func freed(_ again: Bool) -> String {
    let rules = DcApprovals.rulesInEffect(company, link)
    let covered = rules?["documentTypes"]?.array?.contains(.string(type.rawValue)) ?? false
    return (again || covered) && moneyPaid
      ? t("Payments recorded against it will be kept as unapplied client credit.") : ""
  }

  func voidNote(_ again: Bool = false) -> String {
    if type.isPurchase {
      return DcActionRunner.joined([
        t("A void document stays in your records for reference but leaves the books."), creditsNote,
      ])
    }
    return DcActionRunner.joined([
      t("A void document stays in your records for reference but no longer counts as owed."), creditsNote,
      freed(again),
    ])
  }

  /// Voided as it always was: asked, without a reason.
  func voidPlain() {
    state.confirm = DcConfirm(
      title: t("Void {number}?", ["number": doc.str("number")]), description: voidNote(),
      confirmLabel: t("Void document"), danger: true
    ) {
      run("void") { try await setStatus("void") }
    }
  }

  /// Voided with why; void and reissue then opens the copy issued in its place.
  func voidWithReason(again: Bool) {
    let number = doc.str("number")
    let rules = DcApprovals.rulesInEffect(company, link)
    let description =
      again
      ? "\(voidNote(true)) \(t("A new draft is made in its place, to correct and issue with a new number. It prints which invoice it replaces."))"
      : voidNote()
    ask(
      DcReasonAsk(
        title: again
          ? t("Void {number} and issue it again?", ["number": number]) : t("Void {number}?", ["number": number]),
        description: description, label: t("Why it is voided"), required: rules != nil,
        confirmLabel: again ? t("Void and reissue") : t("Void document"), danger: true
      ) { reason in
        let patch: DcPatch = reason.isEmpty ? [] : [("voidReason", .string(reason))]
        try await setStatus("void", patch: patch, freePaid: again)
        if again {
          let created = try await reissue()
          opened(created, edit: true)
        }
      })
  }

  /// Asks an approver to void or restore it.
  func request(_ kind: String) {
    let number = doc.str("number")
    let waiting = one.records(.approvals).contains {
      $0.str("subjectId") == doc.rid && $0.str("status") == "pending"
    }
    let description: String
    if waiting {
      description = t("A request on {number} is already waiting for approval.", ["number": number])
    } else if kind == "invoice_void" {
      description = "\(voidNote()) \(t("An approver decides. It is voided when they approve."))"
    } else {
      description = t("An approver decides. It counts as owed again when they approve.")
    }
    ask(
      DcReasonAsk(
        title: kind == "invoice_void"
          ? t("Ask to void {number}?", ["number": number]) : t("Ask to restore {number}?", ["number": number]),
        description: description, confirmLabel: t("Send for approval")
      ) { reason in
        let subject = doc
        let link = self.link
        try await one.write { ctx in
          try DcApprovals.requestApproval(
            ctx, kind: kind, subject: subject, reason: reason, byName: ctx.userName, link: link)
        }
        model.confirm(t("Sent for approval"))
      })
  }

  func ask(_ reason: DcReasonAsk) {
    state.reasonText = ""
    state.reasonError = nil
    state.reason = reason
  }

  func cancelDocument() {
    let number = doc.str("number")
    let label = type == .deliveryNote ? t("Cancel delivery note") : t("Cancel order")
    let description =
      type == .purchaseOrder
      ? t("A cancelled document stays in your records for reference. Bills already made from it are not changed.")
      : t(
        "A cancelled document stays in your records for reference. Invoices and delivery notes already made from it are not changed."
      )
    state.confirm = DcConfirm(
      title: t("Cancel {number}?", ["number": number]), description: description, confirmLabel: label,
      cancelLabel: t("Keep"), danger: true
    ) {
      run("cancelled") { try await setStatus("cancelled") }
    }
  }

  // MARK: Orders

  var progress: [DcLineProgress] {
    reading { ctx in DcOrders.progressOf(ctx, doc) } ?? []
  }

  func openPart(_ target: String) {
    let progress = self.progress
    var quantities: [String: Double] = [:]
    for line in progress { quantities[line.line.rid] = DcOrders.remainingOf(line, target) }
    state.quantities = quantities
    state.part = DcPartAsk(doc: doc, target: target, progress: progress)
  }

  func openDeliver() {
    state.deliverDate = doc.text("deliveryDate") ?? ISODates.today()
    state.receiverName = doc.str("receiverName")
    state.civilId = doc.str("receiverCivilId")
    state.deliverErrors = [:]
    state.delivering = doc
  }
}

/// The page's buttons: Edit, the main next step and the More menu.
struct DcDocumentActions: View {
  let type: DocType
  let doc: JSONValue
  let state: DcActionState
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let runner = DcActionRunner(model: model, router: router, state: state, type: type, doc: doc)
    if DcWrite.documents && DcWrite.edits(model) {
      WebButton(t("Edit"), icon: .pencil, variant: .outline, size: .sm) {
        router.push(DcWrite.editRoute(type, id: doc.rid))
      }
      if type.isPurchase {
        purchasePrimary(runner)
      } else {
        salesPrimary(runner)
      }
      DropdownMenu(name: t("More actions")) {
        IconView(.moreHorizontal, size: 16).foregroundStyle(palette.slate(600))
      } items: {
        if type.isPurchase {
          purchaseMenu(runner)
        } else {
          salesMenu(runner)
        }
      }
    }
  }

  // MARK: Sales (view.tsx)

  private func left(_ progress: [DcLineProgress], _ key: String) -> Bool {
    progress.contains { (key == "toInvoice" ? $0.toInvoice : $0.toDeliver) > 0 }
  }

  private var status: String { doc.str("status") }

  private func canInvoice(_ progress: [DcLineProgress]) -> Bool {
    type == .salesOrder && (status == "confirmed" || status == "partially_invoiced") && left(progress, "toInvoice")
  }

  private func canDeliver(_ progress: [DcLineProgress]) -> Bool {
    let open =
      (type == .salesOrder && status != "draft" && status != "cancelled") || (type == .invoice && status != "void")
    return open && left(progress, "toDeliver")
  }

  /// The main next step, among those this page has.
  private func primary(_ progress: [DcLineProgress]) -> String? {
    if (type == .quote || type == .proforma) && (status == "accepted" || status == "sent") { return "to-invoice" }
    if type == .salesOrder && status == "draft" { return "confirm" }
    if canInvoice(progress) { return "invoice" }
    if type == .salesOrder && canDeliver(progress) { return "deliver" }
    if type == .deliveryNote && status == "draft" { return "delivered" }
    if type == .proforma && status == "draft" { return "sent" }
    return nil
  }

  private func needsProgress() -> Bool { type == .salesOrder || type == .invoice || type == .purchaseOrder }

  @ViewBuilder
  private func salesPrimary(_ runner: DcActionRunner) -> some View {
    let progress = needsProgress() ? runner.progress : []
    switch primary(progress) ?? "" {
    case "to-invoice":
      WebButton(t("Convert to invoice"), icon: .fileText, size: .sm, loading: state.busy == "convert-invoice") {
        runner.convert(.invoice)
      }
    case "confirm":
      WebButton(t("Confirm order"), icon: .circleCheck, size: .sm, loading: state.busy == "confirm") {
        runner.run("confirm") { try await runner.markSent() }
      }
    case "invoice":
      WebButton(t("Create invoice"), icon: .fileText, size: .sm) { runner.openPart("invoice") }
    case "deliver":
      WebButton(t("Create delivery note"), icon: .packageCheck, size: .sm) { runner.openPart("delivery_note") }
    case "delivered":
      WebButton(t("Mark as delivered"), icon: .packageCheck, size: .sm) { runner.openDeliver() }
    case "sent":
      WebButton(t("Mark as sent"), icon: .circleCheck, size: .sm, loading: state.busy == "sent") {
        runner.run("sent") { try await runner.markSent() }
      }
    default:
      EmptyView()
    }
  }

  @ViewBuilder
  private func salesMenu(_ runner: DcActionRunner) -> some View {
    let progress = needsProgress() ? runner.progress : []
    let emailed = type == .invoice || type == .quote || type == .credit
    let settled = status == "invoiced" || status == "converted"
    let booked = DcRules.postsToLedger(type.rawValue)
    let company = model.one.company
    let link = model.one.writeLink
    let waits = DcApprovals.waitsForApproval(company, link, doc)
    let correcting = DcApprovals.correctsByNewNumber(company)
    let rules = DcApprovals.rulesInEffect(company, link)
    let reissued = type == .invoice || type == .credit
    let replacement = doc.text("replacedById").flatMap { model.one.record(.documents, $0) }
    if emailed && status == "draft" {
      DropdownItem(t("Mark as sent"), icon: .circleCheck) { runner.run("sent") { try await runner.markSent() } }
    }
    if (type == .quote || type == .proforma) && !settled && status != "accepted" {
      DropdownItem(t("Mark as accepted"), icon: .thumbsUp) { runner.run("accepted") { try await runner.setStatus("accepted") } }
    }
    if type == .quote && !settled && status != "declined" {
      DropdownItem(t("Mark as declined"), icon: .thumbsDown) { runner.run("declined") { try await runner.setStatus("declined") } }
      DropdownItem(t("Convert to proforma invoice"), icon: .fileClock) { runner.convert(.proforma) }
      DropdownItem(t("Convert to sales order"), icon: .clipboardList) { runner.convert(.salesOrder) }
    }
    if type == .proforma && status == "draft" {
      DropdownItem(t("Convert to invoice"), icon: .fileText) { runner.convert(.invoice) }
    }
    if canDeliver(progress) && primary(progress) != "deliver" {
      DropdownItem(t("Create delivery note"), icon: .packageCheck) { runner.openPart("delivery_note") }
    }
    if type == .invoice && status != "draft" && status != "void" {
      DropdownItem(t("Create credit note"), icon: .fileMinus) {
        runner.run("credit") {
          let created = try await runner.duplicate(as: .credit, overrides: [("sourceId", .string(doc.rid))])
          runner.opened(created, edit: true)
        }
      }
    }
    if type == .deliveryNote && status == "delivered" {
      DropdownItem(t("Mark as not delivered"), icon: .undo2) { runner.run("draft") { try await runner.setStatus("draft") } }
    }
    DropdownItem(t("Duplicate"), icon: .copy) {
      runner.run("duplicate") {
        let created = try await runner.duplicate(as: nil, overrides: [])
        runner.opened(created, edit: true)
      }
    }
    if status == "void" && booked {
      if waits {
        DropdownItem(t("Request restore"), icon: .undo2) { runner.request("invoice_unvoid") }
      } else {
        DropdownItem(t("Restore (un-void)"), icon: .undo2) { runner.run("sent") { try await runner.setStatus("sent") } }
      }
      if correcting && reissued && replacement == nil {
        DropdownItem(t("Issue again in its place"), icon: .copy) {
          runner.run("reissue") {
            let created = try await runner.reissue()
            runner.opened(created, edit: true)
          }
        }
      }
    } else if booked && status != "draft" {
      if waits {
        DropdownItem(t("Request void"), icon: .ban) { runner.request("invoice_void") }
      } else if !correcting && rules == nil {
        DropdownItem(t("Void document"), icon: .ban) { runner.voidPlain() }
      } else {
        DropdownItem(t("Void document"), icon: .ban) { runner.voidWithReason(again: false) }
        if correcting && reissued {
          DropdownItem(t("Void and reissue"), icon: .rotateCcw) { runner.voidWithReason(again: true) }
        }
      }
    }
    if status == "cancelled" {
      DropdownItem(t("Reopen"), icon: .rotateCcw) {
        runner.run("reopen") { try await runner.setStatus(type == .salesOrder ? "confirmed" : "draft") }
      }
    } else if type == .salesOrder || type == .deliveryNote {
      DropdownItem(type == .salesOrder ? t("Cancel order") : t("Cancel delivery note"), icon: .ban) {
        runner.cancelDocument()
      }
    }
    // Under the rules, issued documents are voided, never deleted (D12).
    if !DcApprovals.voidsInsteadOfDeleting(company, link, doc) {
      DropdownSeparator()
      DropdownItem(t("Delete"), icon: .trash2, danger: true) { runner.remove() }
    }
  }

  // MARK: Purchases (bill-view.tsx)

  @ViewBuilder
  private func purchasePrimary(_ runner: DcActionRunner) -> some View {
    let order = type == .purchaseOrder
    let progress = order ? runner.progress : []
    let canBill =
      order && (status == "issued" || status == "partially_billed") && progress.contains { $0.toInvoice > 0 }
    if status == "draft" {
      WebButton(order ? t("Mark as issued") : t("Mark as open"), icon: .circleCheck, size: .sm, loading: state.busy == "open") {
        runner.run("open") { try await runner.markSent() }
      }
    } else if canBill {
      WebButton(t("Convert to bill"), icon: .receipt, size: .sm) { runner.openPart("bill") }
    }
  }

  @ViewBuilder
  private func purchaseMenu(_ runner: DcActionRunner) -> some View {
    let order = type == .purchaseOrder
    if type == .bill && status != "draft" && status != "void" {
      DropdownItem(t("Create vendor credit"), icon: .fileMinus) {
        runner.run("credit") {
          let created = try await runner.duplicate(
            as: .vendorCredit, overrides: [("sourceId", .string(doc.rid)), ("vendorReference", .string(""))])
          runner.opened(created, edit: true)
        }
      }
    }
    DropdownItem(t("Duplicate"), icon: .copy) {
      runner.run("duplicate") {
        let created = try await runner.duplicate(as: nil, overrides: [("vendorReference", .string(""))])
        runner.opened(created, edit: true)
      }
    }
    if order {
      if status == "cancelled" {
        DropdownItem(t("Reopen"), icon: .rotateCcw) { runner.run("issued") { try await runner.setStatus("issued") } }
      } else if status != "draft" {
        DropdownItem(t("Cancel order"), icon: .ban) { runner.cancelDocument() }
      }
    } else if status == "void" {
      DropdownItem(t("Restore (un-void)"), icon: .undo2) { runner.run("sent") { try await runner.setStatus("sent") } }
    } else if status != "draft" {
      DropdownItem(t("Void document"), icon: .ban) { runner.voidPlain() }
    }
    DropdownSeparator()
    DropdownItem(t("Delete"), icon: .trash2, danger: true) { runner.remove() }
  }
}

/// The dialogs of a document page: confirmations, the reason, delivery and parts.
struct DcActionDialogs: ViewModifier {
  let state: DcActionState
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  func body(content: Content) -> some View {
    content
      .dcConfirm(confirmBinding)
      .webDialog(
        isPresented: reasonShown, title: state.reason?.title ?? "", description: state.reason?.description
      ) {
        Field(state.reason?.label ?? t("Reason"), error: state.reasonError) {
          DcTextArea(text: reasonText, lines: 3)
        }
      } footer: {
        WebButton(t("Cancel"), variant: .outline) { state.reason = nil }
        WebButton(
          state.reason?.confirmLabel ?? t("OK"), variant: state.reason?.danger == true ? .danger : .primary,
          loading: state.reasonBusy
        ) {
          confirmReason()
        }
      }
      .webDialog(
        isPresented: deliverShown, title: t("Mark as delivered"),
        description: t("Who signed for the goods, as written on the signed copy.")
      ) {
        VStack(alignment: .leading, spacing: 16) {
          Field(t("Delivery date")) { DateField(value: deliverDate, required: true) }
          Field(t("Received by"), error: state.deliverErrors["name"]) { TextInput(text: receiverName) }
          Field(t("Civil ID number"), error: state.deliverErrors["civilId"], optional: true) {
            DcTextField(text: civilId, keyboard: .numberPad, leftToRight: true)
          }
        }
      } footer: {
        WebButton(t("Cancel"), variant: .outline) { state.delivering = nil }
        WebButton(t("Mark as delivered"), icon: .packageCheck, loading: state.deliverBusy) { deliver() }
      }
      .webDialog(
        isPresented: partShown, title: partTitle,
        description: t("Everything that is left is filled in. Change a quantity to take part of a line.")
      ) {
        DcPartLines(state: state)
      } footer: {
        WebButton(t("Cancel"), variant: .outline) { state.part = nil }
        WebButton(partTitle, loading: state.partBusy) { createPart() }
          .disabled(partInvalid)
      }
  }

  private var confirmBinding: Binding<DcConfirm?> {
    Binding(get: { state.confirm }, set: { state.confirm = $0 })
  }

  private var reasonText: Binding<String> {
    Binding(get: { state.reasonText }, set: { state.reasonText = $0 })
  }

  private var deliverDate: Binding<String> {
    Binding(get: { state.deliverDate }, set: { state.deliverDate = $0 })
  }

  private var receiverName: Binding<String> {
    Binding(get: { state.receiverName }, set: { state.receiverName = $0 })
  }

  private var civilId: Binding<String> {
    Binding(get: { state.civilId }, set: { state.civilId = $0 })
  }

  private var reasonShown: Binding<Bool> {
    Binding(get: { state.reason != nil }, set: { if !$0 { state.reason = nil } })
  }

  private var deliverShown: Binding<Bool> {
    Binding(get: { state.delivering != nil }, set: { if !$0 { state.delivering = nil } })
  }

  private var partShown: Binding<Bool> {
    Binding(get: { state.part != nil }, set: { if !$0 { state.part = nil } })
  }

  private var partTitle: String {
    switch state.part?.target {
    case "invoice": t("Create invoice")
    case "bill": t("Convert to bill")
    default: t("Create delivery note")
    }
  }

  private var partInvalid: Bool {
    guard let part = state.part else { return true }
    let tooMuch = part.progress.contains { (state.quantities[$0.line.rid] ?? 0) > DcOrders.remainingOf($0, part.target) }
    let nothing = part.progress.allSatisfy { !((state.quantities[$0.line.rid] ?? 0) > 0) }
    return tooMuch || nothing
  }

  private func confirmReason() {
    guard let ask = state.reason, !state.reasonBusy else { return }
    let reason = state.reasonText.trimmingCharacters(in: .whitespacesAndNewlines)
    if ask.required && reason.isEmpty {
      state.reasonError = t("Say why, for the approver.")
      return
    }
    state.reasonBusy = true
    Task { @MainActor in
      defer { state.reasonBusy = false }
      do {
        try await ask.run(reason)
        state.reason = nil
      } catch {
        DcWrite.fail(model, error)
      }
    }
  }

  private func deliver() {
    guard let doc = state.delivering, !state.deliverBusy else { return }
    var found: [String: String] = [:]
    let name = state.receiverName.trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty { found["name"] = t("Enter the name of the person who received the goods.") }
    let civilId = state.civilId.trimmingCharacters(in: .whitespaces)
    if !civilId.isEmpty && !Kuwait.isValidCivilId(civilId) {
      found["civilId"] = t("Check the Civil ID number: it has 12 digits.")
    }
    state.deliverErrors = found
    if !found.isEmpty { return }
    state.deliverBusy = true
    let id = doc.rid
    let date = state.deliverDate
    let receiver = state.receiverName
    let civil = state.civilId
    let link = model.one.writeLink
    Task { @MainActor in
      defer { state.deliverBusy = false }
      do {
        try await model.one.write { ctx in
          try DcOrders.markDelivered(
            ctx, id: id, date: date, receiverName: receiver, receiverCivilId: civil, link: link)
        }
        model.confirm(t("{number} marked as delivered", ["number": doc.str("number")]))
        state.delivering = nil
      } catch {
        DcWrite.fail(model, error)
      }
    }
  }

  private func createPart() {
    guard let part = state.part, !state.partBusy, let companyId = model.one.companyId else { return }
    state.partBusy = true
    let id = part.doc.rid
    let target = part.target
    let quantities = state.quantities
    let one = model.one
    let link = one.writeLink
    let type = DocType(rawValue: part.doc.str("type")) ?? .salesOrder
    Task { @MainActor in
      defer { state.partBusy = false }
      do {
        let request = try await one.write { ctx in
          DcDocuments.newDraftCounterRequest(ctx, companyId: companyId, type: target)
        }
        let reserved = await one.reserveNumber(request)
        let created = try await one.write { ctx in
          try DcOrders.createFromOrder(
            ctx, sourceId: id, target: target, quantities: quantities, reserved: reserved, link: link)
        }
        state.part = nil
        let runner = DcActionRunner(model: model, router: router, state: state, type: type, doc: part.doc)
        runner.opened(created, edit: false)
      } catch {
        DcWrite.fail(model, error)
      }
    }
  }
}

/// The lines of a part: what was ordered, what is left, and how much to take.
struct DcPartLines: View {
  let state: DcActionState
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let format = model.one.format
    let part = state.part
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        WebButton(t("All remaining"), variant: .outline, size: .sm) { fill(remaining: true) }
        WebButton(t("Clear"), variant: .ghost, size: .sm) { fill(remaining: false) }
      }
      let lines = part?.progress ?? []
      ForEach(lines.indices, id: \.self) { index in
        DcPartLine(state: state, line: lines[index], target: part?.target ?? "invoice", index: index, format: format)
      }
    }
  }

  private func fill(remaining: Bool) {
    guard let part = state.part else { return }
    var quantities: [String: Double] = [:]
    for line in part.progress { quantities[line.line.rid] = remaining ? DcOrders.remainingOf(line, part.target) : 0 }
    state.quantities = quantities
  }
}

/// One line of a part.
struct DcPartLine: View {
  let state: DcActionState
  let line: DcLineProgress
  let target: String
  let index: Int
  let format: CompanyFormat
  @Environment(\.palette) private var palette

  var body: some View {
    let left = DcOrders.remainingOf(line, target)
    let unit = line.line.str("unit")
    VStack(alignment: .leading, spacing: 6) {
      Text(localName(line.line)).font(.web(14, .medium)).foregroundStyle(palette.slate(900))
      Text(t("Ordered {quantity}", ["quantity": withUnit(line.ordered, unit)]))
        .font(.web(12))
        .foregroundStyle(palette.slate(500))
      if left > 0 {
        HStack(spacing: 8) {
          DcAmountField(value: quantity).frame(width: 120)
          Text(t("{quantity} left", ["quantity": withUnit(left, unit)]))
            .font(.web(12))
            .foregroundStyle(palette.slate(500))
        }
      } else {
        Text(t("Nothing left")).font(.web(12, .medium)).foregroundStyle(palette[.emerald(700)])
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func withUnit(_ value: Double, _ unit: String) -> String {
    unit.isEmpty ? format.quantity(value) : "\(format.quantity(value)) \(unit)"
  }

  private var quantity: Binding<Double> {
    let id = line.line.rid
    return Binding<Double>(get: { state.quantities[id] ?? 0 }, set: { state.quantities[id] = $0 })
  }
}
