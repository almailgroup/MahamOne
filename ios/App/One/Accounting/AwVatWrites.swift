import MahamKit
import SwiftUI

// Filing a VAT return, recording its payment or refund, and undoing a
// filing (src/apps/books/pages/accounting/vat.tsx `FileDialog`,
// `PaymentDialog` and `undo`).

@MainActor
enum AwVatFiling {
  /// The return as the books give it now, as filing keeps and posts it: the
  /// boxes and net of `vatReturn`, and the VAT on the tax accounts in the
  /// period (`vatAccountTotals`).
  static func figures(_ live: AcVatReturn, books: AcBooks, period: AcRange) -> AwVatFigures {
    let lines = AcVat.lines(books.lines, period)
    let outputTax = books.roles["output_tax"]
    let inputTax = books.roles["input_tax"]
    var output = 0
    var input = 0
    for line in lines {
      if line.accountId == outputTax { output -= line.amount }
      if line.accountId == inputTax { input += line.amount }
    }
    let boxes = live.boxes.map { AwVatBox(id: $0.id, label: $0.label, amount: $0.amount, vat: $0.vat) }
    return AwVatFigures(boxes: boxes, net: live.net, output: output, input: input)
  }

  /// "Undo this filing?": the return is ready to file again, its entries removed.
  static func undo(_ record: JSONValue, model: AppModel) -> AwConfirm {
    let id = record.rid
    return AwConfirm(
      title: t("Undo this filing?"),
      description: t(
        "The return goes back to “ready to file” and its closing entry (and any payment recorded) is removed."),
      confirmLabel: t("Undo filing"), danger: true
    ) {
      Task {
        await AwSave.perform(model, done: t("Filing undone")) { ctx, tr in try AwVat.undo(ctx, id: id, tr: tr) }
      }
    }
  }
}

extension View {
  /// "Mark as filed" while `isPresented`, for the return of `period` as the books give it.
  func awVatFileDialog(_ isPresented: Binding<Bool>, period: AcRange, figures: AwVatFigures) -> some View {
    modifier(AwVatFileDialog(isPresented: isPresented, period: period, figures: figures))
  }

  /// "Record VAT payment" (or refund) while `record` is set.
  func awVatPaymentDialog(_ record: Binding<JSONValue?>) -> some View {
    modifier(AwVatPaymentDialog(record: record))
  }
}

private struct AwVatFileDialog: ViewModifier {
  @Binding var isPresented: Bool
  let period: AcRange
  let figures: AwVatFigures
  @Environment(AppModel.self) private var model
  @State private var filedOn = AcDate.today
  @State private var reference = ""
  @State private var lock = true
  @State private var saving = false
  @State private var error: String?

  func body(content: Content) -> some View {
    let format = model.one.format
    content
      .webDialog(
        isPresented: $isPresented, title: t("Mark as filed"),
        description: t(
          "Record that you submitted this return. The VAT for the period moves to your VAT liability account.")
      ) {
        Field(t("Filed on")) { DateField(value: $filedOn, required: true) }
        Field(t("Reference"), optional: true) { TextInput(text: $reference, placeholder: t("Submission receipt")) }
        Switch(
          t("Lock the period"),
          description: t(
            "Nothing dated on or before {date} can be changed afterwards.", ["date": format.date(period.to)]),
          isOn: $lock)
        AwFormError(text: error)
      } footer: {
        WebButton(t("Cancel"), variant: .outline) { isPresented = false }
        WebButton(t("Mark as filed"), loading: saving) { save() }
      }
      .onChange(of: isPresented) { _, open in
        guard open else { return }
        filedOn = AcDate.today
        reference = ""
        lock = true
        saving = false
        error = nil
      }
  }

  private func save() {
    guard let companyId = model.one.companyId else { return }
    let input = (filedOn: filedOn, reference: reference, lock: lock)
    let period = self.period
    let figures = self.figures
    saving = true
    error = nil
    Task {
      let saved = await AwSave.run(model, failed: { error = $0 }) { ctx, tr in
        try AwVat.file(
          ctx, companyId: companyId, start: period.from, end: period.to, figures: figures, filedOn: input.filedOn,
          reference: input.reference, lock: input.lock, tr: tr)
      }
      saving = false
      guard saved != nil else { return }
      model.confirm(t("Return marked as filed"))
      isPresented = false
    }
  }
}

private struct AwVatPaymentDialog: ViewModifier {
  @Binding var record: JSONValue?
  @Environment(AppModel.self) private var model
  @State private var date = AcDate.today
  @State private var accountId = ""
  @State private var saving = false
  @State private var error: String?

  func body(content: Content) -> some View {
    let pay = (record?.num("net") ?? 0) > 0
    content
      .webDialog(
        isPresented: shown, title: pay ? t("Record VAT payment") : t("Record VAT refund"), description: description(pay)
      ) {
        Field(t("Date")) { DateField(value: $date, required: true) }
        Field(pay ? t("Paid from") : t("Received into")) {
          Select(selection: $accountId, options: options(pay))
        }
        AwFormError(text: error)
      } footer: {
        WebButton(t("Cancel"), variant: .outline) { record = nil }
        WebButton(pay ? t("Record payment") : t("Record refund"), loading: saving) { save(pay) }
      }
      .onChange(of: record?.rid, initial: true) { _, _ in
        guard record != nil else { return }
        date = AcDate.today
        accountId = ""
        saving = false
        error = nil
      }
  }

  private var shown: Binding<Bool> {
    Binding(get: { record != nil }, set: { if !$0 { record = nil } })
  }

  private func description(_ pay: Bool) -> String {
    let format = model.one.format
    let amount = format.acMoney(abs(Int(record?.num("net") ?? 0)))
    return pay
      ? t("{amount} paid to the tax office.", ["amount": amount])
      : t("{amount} received from the tax office.", ["amount": amount])
  }

  /// The bank account (the default), then the bank and cash accounts; cards too for a payment (`MoneyAccountSelect`).
  private func options(_ pay: Bool) -> [SelectOption<String>] {
    let accounts = model.one.records(.accounts)
    let money = AwPick.byCode(
      accounts.filter { a in
        let type = a.str("type")
        return (!a.flag("archived") || a.rid == accountId)
          && (type == "asset_cash" || (pay && type == "liability_credit_card"))
      })
    let auto = accounts.first { $0.str("role") == "bank" }
    let first = auto.map { t("{name} (default)", ["name": localName($0)]) } ?? t("Default account")
    return [SelectOption("", first)] + money.map { SelectOption($0.rid, AwPick.label($0)) }
  }

  private func save(_ pay: Bool) {
    guard let target = record else { return }
    let fallback = model.one.records(.accounts).first { $0.str("role") == "bank" }?.rid
    let chosen: String? = accountId.isEmpty ? fallback : accountId
    guard let bank = chosen else {
      error = t("Choose the bank account.")
      return
    }
    let id = target.rid
    let day = date
    saving = true
    error = nil
    Task {
      let saved = await AwSave.run(model, failed: { error = $0 }) { ctx, tr in
        try AwVat.recordPayment(ctx, id: id, date: day, accountId: bank, tr: tr)
      }
      saving = false
      guard saved != nil else { return }
      model.confirm(pay ? t("VAT payment recorded") : t("VAT refund recorded"))
      record = nil
    }
  }
}
