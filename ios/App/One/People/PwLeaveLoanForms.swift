import MahamKit
import SwiftUI

// Leave and staff loans saved natively: recording leave (its days counted
// from the dates around weekends and the company's holidays) or a change
// to a balance, cancelling leave, leave brought forward for everyone who
// needs it, and loans or salary advances paid from the bank.
//
// A dialog's fields are kept by the button that opens it, not by the
// dialog's body: the dialog lays its body out twice (whole, or scrolling)
// and shows the one that fits.

/// What the leave dialog is filling in.
struct PwLeaveValues {
  var who = ""
  /// A type of the law ("annual", "sick", …) or "reason:<id>".
  var type = "annual"
  /// "leave", "adjustment" or "opening".
  var kind = "leave"
  var start = ISODates.today()
  var end = ISODates.today()
  var days = 0.0
  var notes = ""
  var saving = false
}

/// "Record leave" (for one employee or any current one), or "Set the leave
/// balance" of one employee: an opening balance on a date, or days added or removed.
struct PwRecordLeaveButton: View {
  var employeeId: String?
  var balance = false
  @Environment(AppModel.self) private var model
  @State private var open = false
  @State private var values = PwLeaveValues()

  var body: some View {
    if PwKinds.can(PwKinds.leave) {
      button
        .webDialog(
          isPresented: $open, title: balance ? t("Set the leave balance") : t("Record leave"),
          description: balance
            ? t(
              "Use an opening balance for staff who joined before you started here; it replaces what came before its date."
            )
            : t("Working days skip Fridays, Saturdays and public holidays.")
        ) {
          PwLeaveForm(employeeId: employeeId, balance: balance, values: $values) { open = false }
        }
    }
  }

  @ViewBuilder
  private var button: some View {
    if balance {
      WebButton(t("Set the leave balance"), icon: .slidersHorizontal, variant: .outline, size: .sm) { start() }
    } else {
      WebButton(t("Record leave"), icon: .calendarPlus, size: .sm, haptic: .press) { start() }
    }
  }

  /// The first current employee unless one is given; leave, or an opening balance.
  private func start() {
    let first = model.one.peEmployees.first(where: \.isCurrent)?.id ?? ""
    values = PwLeaveValues(who: employeeId ?? first, kind: balance ? "opening" : "leave")
    open = true
  }
}

private struct PwLeaveForm: View {
  let employeeId: String?
  let balance: Bool
  @Binding var values: PwLeaveValues
  let onDone: () -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if employeeId == nil {
        Field(t("Employee")) { Select(selection: $values.who, options: employees) }
      }
      if balance {
        Field(t("Change")) {
          Select(
            selection: $values.kind,
            options: [
              SelectOption("opening", t("Opening balance on a date")),
              SelectOption("adjustment", t("Add or remove days")),
            ])
        }
      } else {
        Field(t("Type of leave")) { Select(selection: $values.type, options: types) }
      }
      dates
      Field(t("Notes"), optional: true) { TextInput(text: $values.notes) }
      HStack {
        WebButton(t("Cancel"), variant: .outline, action: onDone)
        WebButton(t("Save"), loading: values.saving) { Task { await save() } }
      }
    }
  }

  @ViewBuilder
  private var dates: some View {
    if balance {
      Field(t("Date")) { DateField(value: $values.start, required: true) }
      Field(t("Days"), hint: values.kind == "adjustment" ? t("Use a minus sign to remove days.") : nil) {
        PwNumberField(value: $values.days, allowNegative: values.kind == "adjustment")
      }
    } else {
      Field(t("First day")) { DateField(value: $values.start, required: true) }
      Field(t("Last day")) { DateField(value: $values.end, required: true) }
    }
  }

  /// `isCurrent(e) || e.id === employeeId`, in the company's order.
  private var employees: [SelectOption<String>] {
    model.one.peEmployees.filter { $0.isCurrent || $0.id == employeeId }.map { SelectOption($0.id, $0.displayName) }
  }

  private var types: [SelectOption<String>] {
    let list = ["annual", "sick", "maternity", "hajj", "bereavement", "unpaid"].map {
      SelectOption($0, PeLeave.typeLabel($0))
    }
    return list + reasons.map { SelectOption("reason:" + $0.id, $0.displayName) }
  }

  /// The company's reasons offered for this employee, once switched on (`reasonsFor`).
  private var reasons: [PeLeaveReason] {
    let one = model.one
    let settings = one.pePayrollSettings
    guard settings.leaveReasonsOn else { return [] }
    let category = one.peEmployee(values.who)?.category
    return settings.leaveReasons.filter { reason in
      !reason.archived && (reason.categories.isEmpty || category.map { reason.categories.contains($0) } ?? true)
    }
  }

  private func save() async {
    let one = model.one
    let v = values
    guard let companyId = one.companyId, !v.who.isEmpty else {
      model.toast = Toast(kind: .error, message: t("This employee could not be found."))
      return
    }
    // The reason chosen, as the company offers it to this employee.
    let reasonId = v.kind == "leave" && v.type.hasPrefix("reason:") ? String(v.type.dropFirst("reason:".count)) : nil
    let chosen = reasonId.flatMap { id in reasons.first { $0.id == id } }
    if let chosen, chosen.noteRequired, v.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      model.toast = Toast(kind: .error, message: t("Enter a note: {reason} needs one.", ["reason": chosen.displayName]))
      return
    }
    values.saving = true
    defer { values.saving = false }
    var record = PwPayroll.newLeaveRecord(companyId: companyId, employeeId: v.who, start: v.start)
    record.set("type", .string(v.kind == "leave" ? (chosen?.base ?? v.type) : "annual"))
    record.set("kind", .string(v.kind))
    record.set("end", .string(v.kind == "leave" ? v.end : v.start))
    record.set("days", .number(v.kind == "leave" ? 0 : v.days))
    record.set("notes", .string(v.notes))
    if let chosen { record.set("reasonId", .string(chosen.id)) }
    let input = record
    let text = PwText.app
    let name = one.peEmployee(v.who)?.displayName ?? ""
    let success =
      v.kind == "leave"
      ? t("Leave recorded for {name}", ["name": name]) : t("Leave balance of {name} updated", ["name": name])
    guard await PwSave.run(model, success: success, { ctx in try PwPayroll.saveLeave(ctx, input, text: text) }) != nil
    else { return }
    onDone()
  }
}

/// "Cancel leave" on a leave record, with the web's confirmation.
struct PwCancelLeaveButton: View {
  let recordId: String
  @Environment(AppModel.self) private var model
  @State private var confirming = false

  var body: some View {
    if PwKinds.can(PwKinds.leave) {
      WebButton(t("Cancel"), variant: .ghost, size: .xs) { confirming = true }
        .pwConfirm(
          $confirming, title: t("Cancel this leave?"),
          description: t("It no longer counts against the balance or in pay runs prepared from now on."),
          confirmLabel: t("Cancel leave"), danger: true, cancelLabel: t("Keep")
        ) { Task { await cancel() } }
    }
  }

  private func cancel() async {
    let id = recordId
    let text = PwText.app
    await PwSave.run(model, success: t("Leave cancelled")) { ctx in try PwPayroll.cancelLeave(ctx, id: id, text: text) }
  }
}

/// "Set opening leave balances": the same days for every current employee
/// without an opening balance yet, confirmed (the spreadsheet way is on the web).
struct PwOpeningsButton: View {
  @Environment(AppModel.self) private var model
  @State private var open = false
  @State private var date = String(ISODates.today().prefix(8)) + "01"
  @State private var days = 0.0
  @State private var saving = false

  var body: some View {
    if PwKinds.can(PwKinds.openings) {
      WebButton(t("Set opening leave balances"), icon: .listChecks, variant: .outline, size: .sm) {
        date = String(ISODates.today().prefix(8)) + "01"
        days = 0
        open = true
      }
      .disabled(!model.one.peEmployees.contains(where: \.isCurrent))
      .webDialog(isPresented: $open, title: t("Set opening leave balances")) {
        Field(t("As of"), hint: t("The date the balances are from, such as the first day of this month.")) {
          DateField(value: $date, required: true)
        }
        Text(tp(days, "Everyone without a balance starts at {count} day", "Everyone without a balance starts at {count} days"))
          .font(.web(14, .medium))
        Text(t("Current employees with no opening balance yet all get the same number of days."))
          .font(.web(14))
        Field(t("Days brought forward")) { PwNumberField(value: $days) }
        Text(
          needing > 0
            ? tp(
              needing, "This applies to {count} current employee without an opening balance.",
              "This applies to {count} current employees without an opening balance.")
            : t("Every current employee has an opening leave balance already.")
        )
        .font(.web(14))
      } footer: {
        WebButton(t("Cancel"), variant: .outline) { open = false }
        WebButton(tp(needing, "Set for {count} employee", "Set for {count} employees"), loading: saving) {
          Task { await save() }
        }
        .disabled(needing == 0)
      }
    }
  }

  /// `employeesNeedingLeaveOpening`: current employees with no opening balance yet.
  private var needing: Int {
    let one = model.one
    return PeLeave.needingOpening(one.peEmployees.filter(\.isCurrent), one.peLeaveRecords).count
  }

  private func save() async {
    saving = true
    defer { saving = false }
    let day = date
    let count = days
    guard
      let set = await PwSave.run(model, { ctx in try PwEmployees.setLeaveOpeningForEveryone(ctx, date: day, days: count) })
    else { return }
    model.confirm(
      tp(set, "Opening leave balance set for {count} employee", "Opening leave balances set for {count} employees"))
    open = false
  }
}

/// "Edit" on an employee's leave brought forward, saved confirmed
/// (`LeaveOpeningDialog`), and "Confirm" for one imported with 0 days.
struct PwLeaveOpeningButtons: View {
  let employeeId: String
  @Environment(AppModel.self) private var model
  @State private var open = false
  @State private var date = ISODates.today()
  @State private var days = 0.0
  @State private var saving = false

  var body: some View {
    if PwKinds.can(PwKinds.openings) {
      FlowLayout(spacing: 8) {
        WebButton(t("Edit"), variant: .outline, size: .sm) {
          load()
          open = true
        }
        if let opening, !opening.confirmed {
          WebButton(t("Confirm"), size: .sm, loading: saving && !open) {
            Task { await save(date: opening.date, days: opening.days) }
          }
        }
      }
      .webDialog(
        isPresented: $open, title: t("Leave brought forward"),
        description: t(
          "The annual leave {name} had left on this date, from your records before. Leave counts from this date: nothing before it is added.",
          ["name": name])
      ) {
        Field(t("Date")) { DateField(value: $date, required: true) }
        Field(t("Days brought forward")) { PwNumberField(value: $days) }
      } footer: {
        WebButton(t("Cancel"), variant: .outline) { open = false }
        WebButton(t("Save and confirm"), loading: saving) { Task { await save(date: date, days: days) } }
      }
    }
  }

  private var opening: PeLeaveOpening? { model.one.peEmployee(employeeId)?.leaveOpening }

  private var name: String { model.one.peEmployee(employeeId)?.displayName ?? "" }

  private func load() {
    date = opening?.date ?? ISODates.today()
    days = opening?.days ?? 0
  }

  private func save(date day: String, days count: Double) async {
    saving = true
    defer { saving = false }
    let id = employeeId
    guard
      await PwSave.run(
        model, success: t("Leave brought forward for {name} confirmed", ["name": name]),
        { ctx in try PwEmployees.setLeaveOpening(ctx, employeeId: id, date: day, days: count) }) != nil
    else { return }
    open = false
  }
}

// MARK: - Loans

/// What the loan dialog is filling in.
struct PwLoanValues {
  var who = ""
  var date = ISODates.today()
  var amount = 0.0
  var instalment = 0.0
  var firstPeriod = String(ISODates.today().prefix(7))
  var account = ""
  var notes = ""
  var saving = false

  /// A new loan, for the first current employee unless one is given, paid
  /// from the payroll's bank account; or the loan as saved.
  @MainActor
  static func of(_ one: OneData, employeeId: String?, loanId: String?) -> PwLoanValues {
    let first = one.peEmployees.first(where: \.isCurrent)?.id ?? ""
    var values = PwLoanValues(who: employeeId ?? first, account: PwAccounts.defaultCash(one))
    guard let loanId, let loan = one.record(.staffLoans, loanId) else { return values }
    values.who = loan.str("employeeId")
    values.date = loan.str("date")
    values.amount = loan.num("amount")
    values.instalment = loan.num("instalment")
    values.firstPeriod = loan.str("firstPeriod")
    values.notes = loan.str("notes")
    return values
  }
}

/// "New loan": a loan or salary advance paid from the bank, recovered in instalments.
struct PwNewLoanButton: View {
  var employeeId: String?
  @Environment(AppModel.self) private var model
  @State private var open = false
  @State private var values = PwLoanValues()

  var body: some View {
    if PwKinds.can(PwKinds.loan) {
      WebButton(t("New loan"), icon: .plus, size: .sm, haptic: .press) {
        values = PwLoanValues.of(model.one, employeeId: employeeId, loanId: nil)
        open = true
      }
      .webDialog(
        isPresented: $open, title: t("New loan or advance"),
        description: t(
          "Interest-free and recovered from pay in monthly instalments, at most 10% of the wage (art. 59).")
      ) {
        PwLoanForm(employeeId: employeeId, loanId: nil, values: $values) { open = false }
      }
    }
  }
}

private struct PwLoanForm: View {
  let employeeId: String?
  let loanId: String?
  @Binding var values: PwLoanValues
  let onDone: () -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if loanId == nil {
        if employeeId == nil {
          Field(t("Employee")) { Select(selection: $values.who, options: employees) }
        }
        Field(t("Paid on")) { DateField(value: $values.date) }
        Field(t("Amount")) { PwNumberField(value: $values.amount) }
        Field(t("Paid from")) { Select(selection: $values.account, options: PwAccounts.cash(model.one)) }
      }
      Field(t("Monthly instalment")) { PwNumberField(value: $values.instalment) }
      Field(t("First instalment in")) { PwMonthSelect(period: $values.firstPeriod) }
      Field(t("Notes"), optional: true) { TextInput(text: $values.notes) }
      HStack {
        WebButton(t("Cancel"), variant: .outline, action: onDone)
        WebButton(loanId == nil ? t("Pay the loan") : t("Save"), loading: values.saving) { Task { await save() } }
      }
    }
  }

  /// `isCurrent(e) || e.id === employeeId`, in the company's order.
  private var employees: [SelectOption<String>] {
    model.one.peEmployees.filter { $0.isCurrent || $0.id == employeeId }.map { SelectOption($0.id, $0.displayName) }
  }

  private func save() async {
    let one = model.one
    let v = values
    guard let companyId = one.companyId, !v.who.isEmpty else {
      model.toast = Toast(kind: .error, message: t("This employee could not be found."))
      return
    }
    values.saving = true
    defer { values.saving = false }
    var loan =
      loanId.flatMap { one.record(.staffLoans, $0) }
      ?? PwPayroll.newLoan(companyId: companyId, employeeId: v.who, today: ISODates.today())
    if loanId == nil {
      loan.set("date", .string(v.date))
      loan.set("amount", .number(v.amount))
      loan.set("paidFromAccountId", v.account.isEmpty ? .null : .string(v.account))
    }
    loan.set("instalment", .number(v.instalment))
    loan.set("firstPeriod", .string(v.firstPeriod))
    loan.set("notes", .string(v.notes))
    let input = loan
    let text = PwText.app
    let name = one.peEmployee(v.who)?.displayName ?? ""
    let success = loanId == nil ? t("Loan to {name} recorded", ["name": name]) : nil
    guard await PwSave.run(model, success: success, { ctx in try PwPayroll.saveLoan(ctx, input, text: text) }) != nil
    else { return }
    onDone()
  }
}

/// "Cancel loan": a loan nothing was recovered on, its payment reversed.
struct PwCancelLoanButton: View {
  let loanId: String
  @Environment(AppModel.self) private var model
  @State private var confirming = false

  var body: some View {
    if PwKinds.can(PwKinds.loan) {
      WebButton(t("Cancel loan"), variant: .ghost, size: .xs) { confirming = true }
        .pwConfirm(
          $confirming, title: t("Cancel this loan?"),
          description: t("Its payment is reversed in the books. Only loans with nothing recovered can be cancelled."),
          confirmLabel: t("Cancel loan"), danger: true, cancelLabel: t("Keep")
        ) { Task { await cancel() } }
    }
  }

  private func cancel() async {
    let id = loanId
    let text = PwText.app
    await PwSave.run(model, success: t("Loan cancelled")) { ctx in try PwPayroll.cancelLoan(ctx, id: id, text: text) }
  }
}
