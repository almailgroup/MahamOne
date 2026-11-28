import MahamKit
import SwiftUI

// The final settlement saved natively: the form filled in as the law and
// the records give it (`settlementDefaults`), posted on the leaving date
// with the employee marked as left, then paid from the bank, or reversed.

/// On the settlement page: the form for an employee without a live
/// settlement, the payment and the reversal for one with.
struct PwSettlementActions: View {
  let employeeId: String
  @Environment(AppModel.self) private var model

  var body: some View {
    if let settlement = live {
      PwSettlementRecordActions(settlement: settlement)
    } else if PwKinds.can(PwKinds.settlement), model.one.record(.employees, employeeId) != nil {
      PwSettlementFormCard(employeeId: employeeId)
    }
  }

  private var live: JSONValue? {
    model.one.records(.finalSettlements).first {
      $0.str("employeeId") == employeeId && $0.str("status") != "reversed"
    }
  }
}

private struct PwSettlementFormCard: View {
  let employeeId: String
  @Environment(AppModel.self) private var model
  @State private var leavingDate = ISODates.today()
  @State private var reason = ""
  @State private var form: PwSettlements.Form?
  @State private var setup: PwSettlements.Setup?
  @State private var override = false
  @State private var indemnity = 0.0
  @State private var confirming = false
  @State private var busy = false

  var body: some View {
    Card {
      CardHeader(t("Final settlement"), description: t("Labour Law 6/2010, articles 51 and 53. An estimate, not legal advice."))
      CardBody {
        VStack(alignment: .leading, spacing: 16) {
          Field(t("Leaving date")) { DateField(value: $leavingDate) }
          Field(t("Reason")) {
            Select(
              selection: $reason,
              options: [SelectOption("", t("Choose a reason"))]
                + PePeople.leavingReasons.map { SelectOption($0, PePeople.leavingReasonLabel($0)) })
          }
          if form != nil { fields }
        }
      }
    }
    .onChange(of: leavingDate) { _, _ in Task { await prepare() } }
    .onChange(of: reason) { _, _ in Task { await prepare() } }
    .pwConfirm(
      $confirming, title: t("Post the final settlement?"),
      description: t(
        "{name} is marked as left on {date} and the settlement is posted to the books. You can reverse it while it is unpaid.",
        ["name": name, "date": model.one.format.date(leavingDate)]),
      confirmLabel: t("Post settlement")
    ) { Task { await post() } }
  }

  @ViewBuilder
  private var fields: some View {
    Field(t("Notice pay (months)")) { PwNumberField(value: number(\.noticeMonths)) }
    Field(t("Unused leave (days)")) { PwNumberField(value: number(\.leaveDays)) }
    Field(t("Last salary (days)")) { PwNumberField(value: number(\.lastSalaryDays)) }
    Field(t("Covered by PIFSS contributions"), optional: true) { PwNumberField(value: number(\.pifssOffset)) }
    Switch(t("Enter the indemnity myself"), isOn: $override)
    if override {
      Field(t("Indemnity")) { PwNumberField(value: $indemnity) }
    }
    ForEach(loanIndices, id: \.self) { index in
      Field(t("Loan recovery")) { PwNumberField(value: loanAmount(index)) }
    }
    Field(t("Other deductions"), optional: true) { PwNumberField(value: number(\.otherDeductions)) }
    Field(t("Reason for the deduction"), optional: true) { TextInput(text: text(\.deductionNote)) }
    Field(t("Notes"), optional: true) { TextInput(text: text(\.notes)) }
    PwSettlementTotals(form: current, setup: setup)
    WebButton(t("Post settlement"), loading: busy) { confirming = true }
  }

  private var name: String { model.one.peEmployee(employeeId)?.displayName ?? "" }

  private var loanIndices: [Int] { Array((form?.loans ?? []).indices) }

  /// The form with the indemnity entered by hand, when it is.
  private var current: PwSettlements.Form? {
    guard var form else { return nil }
    form.indemnityOverride = override ? indemnity : nil
    return form
  }

  private func number(_ path: WritableKeyPath<PwSettlements.Form, Double>) -> Binding<Double> {
    Binding<Double>(get: { form?[keyPath: path] ?? 0 }, set: { form?[keyPath: path] = $0 })
  }

  private func text(_ path: WritableKeyPath<PwSettlements.Form, String>) -> Binding<String> {
    Binding<String>(get: { form?[keyPath: path] ?? "" }, set: { form?[keyPath: path] = $0 })
  }

  private func loanAmount(_ index: Int) -> Binding<Double> {
    Binding<Double>(
      get: { form?.loans.indices.contains(index) == true ? (form?.loans[index].num("amount") ?? 0) : 0 },
      set: { value in
        guard var loans = form?.loans, loans.indices.contains(index) else { return }
        loans[index].set("amount", .number(value))
        form?.loans = loans
      })
  }

  private func prepare() async {
    guard !reason.isEmpty, ISODates.isISODate(leavingDate) else {
      form = nil
      return
    }
    let id = employeeId
    let day = leavingDate
    let why = reason
    let draft = await PwSave.read(model) { ctx in
      try PwSettlements.draft(ctx, employeeId: id, leavingDate: day, reason: why)
    }
    form = draft?.form
    setup = draft?.setup
  }

  private func post() async {
    guard let input = current else { return }
    busy = true
    defer { busy = false }
    let text = PwText.app
    await PwSave.run(model, success: t("Final settlement posted")) { ctx in try PwSettlements.post(ctx, input, text: text) }
  }
}

private struct PwSettlementTotals: View {
  let form: PwSettlements.Form?
  let setup: PwSettlements.Setup?
  @Environment(AppModel.self) private var model
  @State private var amounts: (indemnity: Double, noticePay: Double, leavePay: Double, lastSalary: Double, deductions: Double, net: Double)?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let amounts {
        row(t("Indemnity"), amounts.indemnity)
        row(t("Notice, leave and last salary"), amounts.noticePay + amounts.leavePay + amounts.lastSalary)
        row(t("Deductions"), amounts.deductions)
        row(t("Net amount due"), amounts.net)
      }
    }
    .task(id: form) { await work() }
  }

  private func row(_ label: String, _ value: Double) -> some View {
    HStack {
      Text(label).font(.web(14))
      Spacer()
      Text(model.one.format.money(value)).font(.web(14, .semibold))
    }
  }

  private func work() async {
    guard let form, let setup else {
      amounts = nil
      return
    }
    amounts = await PwSave.read(model) { ctx in PwSettlements.amounts(ctx, form, setup) } ?? nil
  }
}

/// A posted settlement: paid from the bank, its payment undone, or reversed.
private struct PwSettlementRecordActions: View {
  let settlement: JSONValue
  @Environment(AppModel.self) private var model
  @State private var paying = false
  @State private var undoing = false
  @State private var date = ISODates.today()
  @State private var account = ""
  @State private var busy = false

  var body: some View {
    if PwKinds.can(PwKinds.settlement) {
      HStack(spacing: 8) {
        if settlement.str("status") == "posted" {
          WebButton(t("Record payment"), icon: .banknote, size: .sm) { paying = true }
          WebButton(t("Reverse"), icon: .rotateCcw, variant: .outline, size: .sm) { undoing = true }
        } else if settlement.str("status") == "paid" {
          WebButton(t("Undo payment"), icon: .undo2, variant: .outline, size: .sm) { undoing = true }
        }
      }
      .webDialog(isPresented: $paying, title: t("Pay the final settlement"), description: name) {
        VStack(alignment: .leading, spacing: 16) {
          Field(t("Amount")) { Text(model.one.format.money(settlement.num("net"))).font(.web(16, .semibold)) }
          Field(t("Payment date")) { DateField(value: $date) }
          Field(t("Paid from")) { Select(selection: $account, options: PwAccounts.cash(model.one)) }
        }
      } footer: {
        WebButton(t("Cancel"), variant: .outline) { paying = false }
        WebButton(t("Record payment"), loading: busy) { Task { await pay() } }
      }
      .pwConfirm(
        $undoing, title: paid ? t("Undo the payment?") : t("Reverse the settlement?"),
        description: paid
          ? t("The payment entry is reversed and the settlement goes back to unpaid.")
          : t(
            "Its entry is reversed on the leaving date. The employee stays marked as left; you can prepare a new settlement."
          ),
        confirmLabel: paid ? t("Undo payment") : t("Reverse"), danger: true
      ) { Task { await reverse() } }
      .onAppear { account = PwAccounts.defaultCash(model.one) }
    }
  }

  private var paid: Bool { settlement.str("status") == "paid" }

  private var name: String { model.one.peEmployee(settlement.str("employeeId"))?.displayName ?? "" }

  private func pay() async {
    busy = true
    defer { busy = false }
    let id = settlement.rid
    let day = date
    let bank = account.isEmpty ? nil : account
    let text = PwText.app
    guard
      await PwSave.run(
        model, success: t("Final settlement paid"),
        { ctx in try PwSettlements.pay(ctx, id: id, date: day, bankAccountId: bank, text: text) }) != nil
    else { return }
    paying = false
  }

  private func reverse() async {
    let id = settlement.rid
    let text = PwText.app
    let success = paid ? t("Payment undone") : t("Settlement reversed")
    await PwSave.run(model, success: success) { ctx in try PwSettlements.reverse(ctx, id: id, text: text) }
  }
}
