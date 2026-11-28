import MahamKit
import SwiftUI

// Pay runs saved natively: preparing a month, updating a draft from the
// records, what is entered for one employee, the pay date, sending it for
// the Super Admin's approval, approving (posting), paying, undoing the
// payment and reopening, with the web's confirmations and words.

/// "New pay run" on the payroll page: the month, then the run prepared.
struct PwNewPayRunButton: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @State private var open = false
  @State private var period = String(ISODates.today().prefix(7))
  @State private var saving = false

  var body: some View {
    if PwKinds.can(PwKinds.payRun) && !model.one.records(.employees).isEmpty {
      WebButton(t("New pay run"), icon: .plus, haptic: .press) { open = true }
        .webDialog(isPresented: $open, title: t("New pay run")) {
          Field(t("Month")) { PwMonthSelect(period: $period) }
        } footer: {
          WebButton(t("Cancel"), variant: .outline) { open = false }
          WebButton(t("Prepare pay run"), loading: saving) { Task { await prepare() } }
        }
    }
  }

  private func prepare() async {
    saving = true
    defer { saving = false }
    let month = period
    guard let run = await PwSave.run(model, { ctx in try PwPayRuns.create(ctx, period: month) }) else { return }
    open = false
    model.confirm(t("Payroll for {month} prepared", ["month": PePayroll.formatPeriod(month, model.one.format)]))
    router.push(.payRun(id: run.rid))
  }
}

/// What can be done with a pay run, by where it stands.
struct PwPayRunActions: View {
  let runId: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @State private var dialog: Dialog?
  @State private var confirming: Confirming?
  @State private var busy = false

  enum Dialog: Identifiable {
    case line, payDate, pay, ask
    var id: Self { self }
  }

  enum Confirming: Identifiable {
    case approve, reopen, undo, delete
    var id: Self { self }
  }

  var body: some View {
    if let run = model.one.record(.payRuns, runId) {
      FlowLayout(spacing: 8) {
        buttons(run)
      }
      .modifier(PwPayRunDialogs(run: run, dialog: $dialog))
      .modifier(PwPayRunConfirms(run: run, confirming: $confirming, busy: $busy))
    }
  }

  @ViewBuilder
  private func buttons(_ run: JSONValue) -> some View {
    switch run.str("status") {
    case "draft": draftButtons(run)
    case "approved": approvedButtons
    case "paid": paidButtons
    default: EmptyView()
    }
  }

  @ViewBuilder
  private func draftButtons(_ run: JSONValue) -> some View {
    if PwKinds.can(PwKinds.payRun) {
      WebButton(t("Update from records"), icon: .refreshCw, variant: .outline, size: .sm, loading: busy) {
        Task { await refresh() }
      }
      WebButton(t("Overtime"), icon: .pencil, variant: .outline, size: .sm) { dialog = .line }
      WebButton(t("Pay date"), icon: .calendarDays, variant: .outline, size: .sm) { dialog = .payDate }
    }
    if needsApproval(run) {
      if PwKinds.can(PwKinds.approvals) {
        WebButton(t("Ask for approval"), icon: .send, size: .sm) { dialog = .ask }
      }
    } else if PwKinds.can(PwKinds.posting) {
      WebButton(t("Approve"), icon: .check, size: .sm) { confirming = .approve }
    }
    if PwKinds.can(PwKinds.payRun) && run.list("reversalJournalIds").isEmpty {
      WebButton(t("Delete draft"), icon: .trash2, variant: .ghost, size: .sm) { confirming = .delete }
    }
  }

  @ViewBuilder
  private var approvedButtons: some View {
    if PwKinds.can(PwKinds.posting) {
      WebButton(t("Record payment"), icon: .banknote, size: .sm) { dialog = .pay }
      WebButton(t("Reopen"), icon: .rotateCcw, variant: .outline, size: .sm) { confirming = .reopen }
    }
  }

  @ViewBuilder
  private var paidButtons: some View {
    if PwKinds.can(PwKinds.posting) {
      WebButton(t("Undo payment"), icon: .undo2, variant: .outline, size: .sm) { confirming = .undo }
    }
  }

  /// With salary approval on, someone other than the owner sends the run first.
  private func needsApproval(_ run: JSONValue) -> Bool {
    let one = model.one
    let requests = one.records(.approvals).filter { $0.str("subjectId") == runId }
    return !PwApprovals.postable(one.company, one.pwLink, run, requests)
  }

  private func refresh() async {
    busy = true
    defer { busy = false }
    let id = runId
    await PwSave.run(model, success: t("Pay run updated from the records")) { ctx in try PwPayRuns.refresh(ctx, id: id) }
  }
}

// MARK: - Dialogs

/// What the pay run's dialogs are filling in. Kept by the modifier, not by
/// the dialogs' bodies, which are laid out twice (whole, or scrolling).
struct PwPayRunValues {
  var lineId = ""
  var normal = 0.0
  var restDay = 0.0
  var holiday = 0.0
  var absent = 0.0
  var adjustments: [PwDraft] = []
  var loans: [PwDraft] = []
  var payDate = ""
  var notes = ""
  var paidOn = ""
  var account = ""
  var note = ""
  var saving = false

  /// What is entered for one employee of the run, as saved.
  mutating func load(line id: String, of run: JSONValue) {
    lineId = id
    guard let line = run.list("lines").first(where: { $0.rid == id }) else { return }
    let overtime = line.obj("overtime")
    normal = overtime?.num("normal") ?? 0
    restDay = overtime?.num("restDay") ?? 0
    holiday = overtime?.num("holiday") ?? 0
    absent = line.num("absentDays")
    adjustments = line.list("adjustments").map { PwDraft($0) }
    loans = line.list("loans").map { PwDraft($0) }
  }
}

private struct PwPayRunDialogs: ViewModifier {
  let run: JSONValue
  @Binding var dialog: PwPayRunActions.Dialog?
  @Environment(AppModel.self) private var model
  @State private var values = PwPayRunValues()

  func body(content: Content) -> some View {
    content
      .webDialog(isPresented: shown(.line), title: t("Overtime")) {
        PwPayLineEditor(run: run, values: $values) { dialog = nil }
      }
      .webDialog(isPresented: shown(.payDate), title: t("Pay date")) {
        PwPayDateEditor(run: run, values: $values) { dialog = nil }
      }
      .webDialog(
        isPresented: shown(.pay), title: t("Pay the salaries for {month}", ["month": month]),
        description: t("Records the transfer from the bank: Dr salaries payable, Cr bank.")
      ) {
        PwPayRunPayment(run: run, values: $values) { dialog = nil }
      }
      .webDialog(
        isPresented: shown(.ask), title: t("Ask the Super Admin to approve the payroll for {month}?", ["month": month]),
        description: t(
          "The owner and the members allowed to approve get its totals by department and position by email, and see each employee’s pay here. Any change to the pay run after this asks for a new approval."
        )
      ) {
        PwAskApproval(run: run, values: $values) { dialog = nil }
      }
      .onChange(of: dialog) { _, opened in
        guard opened != nil else { return }
        start()
      }
  }

  private var month: String { PePayroll.formatPeriod(run.str("period"), model.one.format) }

  private func shown(_ which: PwPayRunActions.Dialog) -> Binding<Bool> {
    Binding<Bool>(get: { dialog == which }, set: { if !$0 { dialog = nil } })
  }

  /// A dialog opening: its fields as the run has them.
  private func start() {
    var fresh = PwPayRunValues()
    fresh.payDate = run.str("payDate")
    fresh.notes = run.str("notes")
    fresh.paidOn = run.str("payDate")
    fresh.account = PwAccounts.defaultCash(model.one)
    values = fresh
  }
}

private struct PwPayRunConfirms: ViewModifier {
  let run: JSONValue
  @Binding var confirming: PwPayRunActions.Confirming?
  @Binding var busy: Bool
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  private var month: String { PePayroll.formatPeriod(run.str("period"), model.one.format) }

  private var posted: String {
    t(
      "Salaries, PIFSS and deductions are posted to the books on {date}. You can reopen the pay run until it is paid.",
      ["date": model.one.format.date(run.str("date"))])
  }

  func body(content: Content) -> some View {
    content
      .pwConfirm(
        shown(.approve), title: t("Approve the payroll for {month}?", ["month": month]), description: posted,
        confirmLabel: t("Approve")
      ) { Task { await approve(month) } }
      .pwConfirm(
        shown(.reopen), title: t("Reopen the payroll for {month}?", ["month": month]),
        description: t("Its entries are reversed so you can change it and approve it again."),
        confirmLabel: t("Reopen")
      ) { Task { await act(t("Pay run reopened")) { ctx, id, text in try PwPayRuns.reopen(ctx, id: id, text: text) } } }
      .pwConfirm(
        shown(.undo), title: t("Undo the payment?"),
        description: t("The payment entry is reversed and the pay run goes back to approved."),
        confirmLabel: t("Undo payment"), danger: true
      ) { Task { await act(t("Payment undone")) { ctx, id, text in try PwPayRuns.undoPayment(ctx, id: id, text: text) } } }
      .pwConfirm(
        shown(.delete), title: t("Delete this draft?"),
        description: t("Nothing was posted for it. You can prepare the month again later."), confirmLabel: t("Delete"),
        danger: true
      ) { Task { await remove() } }
  }

  private func shown(_ which: PwPayRunActions.Confirming) -> Binding<Bool> {
    Binding<Bool>(get: { confirming == which }, set: { if !$0 { confirming = nil } })
  }

  private func act(_ success: String, _ port: @escaping (WriteContext, String, PwText) throws -> JSONValue) async {
    busy = true
    defer { busy = false }
    let id = run.rid
    let text = PwText.app
    await PwSave.run(model, success: success) { ctx in try port(ctx, id, text) }
  }

  private func approve(_ month: String) async {
    busy = true
    defer { busy = false }
    let id = run.rid
    let link = model.one.pwLink
    let text = PwText.app
    guard
      let approved = await PwSave.run(
        model, success: t("Payroll for {month} approved", ["month": month]),
        { ctx in try PwPayRuns.approve(ctx, id: id, link: link, text: text) })
    else { return }
    // The request it was posted with, marked done on its own: the posting stands whatever becomes of it.
    if let request = approved.requestId, PwKinds.can(PwKinds.approvals) {
      _ = try? await model.one.write { ctx in PwApprovals.markApplied(ctx, requestId: request, link: link) }
    }
  }

  private func remove() async {
    let id = run.rid
    guard await PwSave.run(model, success: t("Draft deleted"), { ctx in try PwPayRuns.delete(ctx, id: id) }) != nil
    else { return }
    router.back()
  }
}

/// What is entered for one employee of a draft: overtime, absence, additions and deductions, loan recoveries.
private struct PwPayLineEditor: View {
  let run: JSONValue
  @Binding var values: PwPayRunValues
  let onDone: () -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Field(t("Employee")) {
        Select(selection: line, options: lines)
      }
      if !values.lineId.isEmpty {
        PwLineFields(values: $values)
        HStack {
          WebButton(t("Cancel"), variant: .outline, action: onDone)
          WebButton(t("Save"), loading: values.saving) { Task { await save() } }
        }
      }
    }
  }

  private var lines: [SelectOption<String>] {
    [SelectOption("", t("Select an employee to add overtime, absence, additions or deductions."))]
      + run.list("lines").map { SelectOption($0.rid, localName($0.str("name"), $0.text("nameAr"))) }
  }

  /// The employee chosen, with what is entered for them as saved.
  private var line: Binding<String> {
    Binding<String>(
      get: { values.lineId },
      set: { id in values.load(line: id, of: run) })
  }

  private func save() async {
    values.saving = true
    defer { values.saving = false }
    let v = values
    let runId = run.rid
    let id = v.lineId
    let changes = PwPayRuns.LineChanges(
      overtime: (v.normal, v.restDay, v.holiday), absentDays: v.absent, adjustments: v.adjustments.map(\.json),
      loans: v.loans.map(\.json))
    let name = run.list("lines").first { $0.rid == id }.map { localName($0.str("name"), $0.text("nameAr")) } ?? ""
    guard
      await PwSave.run(
        model, success: t("Pay of {name} updated", ["name": name]),
        { ctx in try PwPayRuns.updateLine(ctx, runId: runId, lineId: id, changes) }) != nil
    else { return }
    onDone()
  }
}

private struct PwLineFields: View {
  @Binding var values: PwPayRunValues

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(t("Overtime hours")).font(.web(14, .medium))
      Field(t("Working days (+25%)")) { PwNumberField(value: $values.normal) }
      Field(t("Rest days (+50%)")) { PwNumberField(value: $values.restDay) }
      Field(t("Public holidays (double)")) { PwNumberField(value: $values.holiday) }
      Field(t("Unpaid absence (days)")) { PwNumberField(value: $values.absent) }
      adjustments
      if !values.loans.isEmpty {
        Text(t("Loan instalments")).font(.web(14, .medium))
        ForEach(values.loans.indices, id: \.self) { index in
          Field(t("Loan recovery")) { PwNumberField(value: $values.loans.row(index).number("amount")) }
        }
      }
    }
  }

  @ViewBuilder
  private var adjustments: some View {
    Text(t("Additions and deductions")).font(.web(14, .medium))
    Text(t("Bonuses, commissions, fines or other one-off amounts.")).font(.web(12))
    ForEach(values.adjustments.indices, id: \.self) { index in
      PwAdjustmentRow(adjustment: $values.adjustments.row(index)) {
        if values.adjustments.indices.contains(index) { values.adjustments.remove(at: index) }
      }
    }
    WebButton(t("Add an addition or deduction"), icon: .plus, variant: .outline, size: .sm) {
      values.adjustments.append(PwDraft(["id": "", "type": "addition", "amount": 0, "note": ""]))
    }
  }
}

private struct PwAdjustmentRow: View {
  @Binding var adjustment: PwDraft
  let onRemove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Field(t("Type")) {
        Select(
          selection: $adjustment.text("type"),
          options: [SelectOption("addition", t("Addition")), SelectOption("deduction", t("Deduction"))])
      }
      Field(t("Amount")) { PwNumberField(value: $adjustment.number("amount")) }
      Field(t("Note"), optional: true) { TextInput(text: $adjustment.text("note")) }
      WebButton(t("Remove"), icon: .trash2, variant: .ghost, size: .sm, action: onRemove)
    }
    .padding(12)
    .modifier(InputChrome(focused: false))
  }
}

/// The pay date (until paid) and the notes of a run.
private struct PwPayDateEditor: View {
  let run: JSONValue
  @Binding var values: PwPayRunValues
  let onDone: () -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Field(t("Pay date"), hint: t("Wages are due within 7 days of the end of the month (art. 56).")) {
        DateField(value: $values.payDate)
      }
      Field(t("Notes"), optional: true) { TextInput(text: $values.notes) }
      HStack {
        WebButton(t("Cancel"), variant: .outline, action: onDone)
        WebButton(t("Save"), loading: values.saving) { Task { await save() } }
      }
    }
  }

  private func save() async {
    values.saving = true
    defer { values.saving = false }
    let id = run.rid
    let date = values.payDate
    let text = values.notes
    guard
      await PwSave.run(model, { ctx in try PwPayRuns.updateRun(ctx, id: id, payDate: date, notes: text) }) != nil
    else { return }
    onDone()
  }
}

/// Recording the salaries as paid.
private struct PwPayRunPayment: View {
  let run: JSONValue
  @Binding var values: PwPayRunValues
  let onDone: () -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    let one = model.one
    let totals = PePayroll.totals(PePayRun(run).lines, one.pePrecision)
    VStack(alignment: .leading, spacing: 16) {
      Field(t("Amount")) { Text(one.format.money(totals.net)).font(.web(16, .semibold)) }
      Field(t("Payment date")) { DateField(value: $values.paidOn) }
      Field(t("Paid from")) { Select(selection: $values.account, options: PwAccounts.cash(one)) }
      HStack {
        WebButton(t("Cancel"), variant: .outline, action: onDone)
        WebButton(t("Record payment"), loading: values.saving) { Task { await pay() } }
      }
    }
  }

  private func pay() async {
    values.saving = true
    defer { values.saving = false }
    let id = run.rid
    let day = values.paidOn
    let bank = values.account.isEmpty ? nil : values.account
    let text = PwText.app
    let month = PePayroll.formatPeriod(run.str("period"), model.one.format)
    guard
      await PwSave.run(
        model, success: t("Salaries for {month} paid", ["month": month]),
        { ctx in try PwPayRuns.pay(ctx, id: id, date: day, bankAccountId: bank, text: text) }) != nil
    else { return }
    onDone()
  }
}

/// Sending a draft for the Super Admin's approval, with a note.
private struct PwAskApproval: View {
  let run: JSONValue
  @Binding var values: PwPayRunValues
  let onDone: () -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Field(t("Note for the Super Admin"), optional: true) { TextInput(text: $values.note) }
      HStack {
        WebButton(t("Cancel"), variant: .outline, action: onDone)
        WebButton(t("Ask for approval"), loading: values.saving) { Task { await ask() } }
      }
    }
  }

  private func ask() async {
    values.saving = true
    defer { values.saving = false }
    let id = run.rid
    let typed = values.note
    let link = model.one.pwLink
    let name = model.session?.user.fullName ?? model.session?.user.email ?? ""
    let text = PwText.app
    guard
      await PwSave.run(
        model, success: t("Sent for the Super Admin’s approval"),
        { ctx in try PwApprovals.request(ctx, runId: id, note: typed, byName: name, link: link, text: text) }) != nil
    else { return }
    onDone()
  }
}
