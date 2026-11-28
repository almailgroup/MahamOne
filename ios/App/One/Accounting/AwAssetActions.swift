import MahamKit
import SwiftUI

// What changes fixed assets besides their form (src/apps/books/pages/assets/
// detail.tsx and index.tsx): disposing of an asset (sold, scrapped or written
// off) and undoing it, voiding one entered by mistake, running the month's
// depreciation and undoing the latest run.

/// How the asset form opens: "Add from a bill" starts it on a bill line.
@MainActor
enum AwAssetDraft {
  /// The way the next new asset was bought ("bill"), taken by the form when it opens.
  static var source: String?
}

@MainActor
enum AwAssetActions {
  /// "Void {name}?": the purchase entry is reversed and the asset leaves the register.
  static func voidAsset(_ asset: JSONValue, model: AppModel, router: ShellRouter) -> AwConfirm {
    let id = asset.rid
    let number = asset.str("number")
    return AwConfirm(
      title: t("Void {name}?", ["name": localName(asset)]),
      description: t(
        "Use this for an asset entered by mistake. Its purchase entry is reversed and it leaves the register; the history stays in the books."
      ), confirmLabel: t("Void asset"), danger: true
    ) {
      Task {
        let done = await AwSave.perform(model, done: t("Asset {number} voided", ["number": number])) { ctx, tr in
          try AwAssets.voidAsset(ctx, id: id, tr: tr)
        }
        if done { router.back() }
      }
    }
  }

  /// "Undo the disposal?": a reversing journal, and the asset is in use again.
  static func undoDisposal(_ asset: JSONValue, model: AppModel) -> AwConfirm {
    let id = asset.rid
    return AwConfirm(
      title: t("Undo the disposal?"), description: t("A reversing journal is posted and the asset is back in use."),
      confirmLabel: t("Undo disposal")
    ) {
      Task {
        await AwSave.perform(model, done: t("Disposal undone")) { ctx, tr in try AwAssets.undoDisposal(ctx, id: id, tr: tr) }
      }
    }
  }

  /// "Undo depreciation for {month}?": a reversing journal; the month can be run again.
  static func undoRun(_ run: JSONValue, model: AppModel) -> AwConfirm {
    let id = run.rid
    let month = AcDate.monthLabel(run.str("period"), arabic: LanguageStore.shared.isArabic)
    return AwConfirm(
      title: t("Undo depreciation for {month}?", ["month": month]),
      description: t(
        "A reversing journal is posted, so the history stays in the books. You can run the month again afterwards."),
      confirmLabel: t("Undo run"), danger: true
    ) {
      Task {
        await AwSave.perform(model, done: t("Depreciation for {month} undone", ["month": month])) { ctx, tr in
          try AwAssets.reverseRun(ctx, id: id, tr: tr)
        }
      }
    }
  }
}

// MARK: Disposing of an asset

extension View {
  /// The disposal dialog while `asset` is set.
  func awDisposeDialog(_ asset: Binding<JSONValue?>) -> some View {
    modifier(AwDisposeDialog(asset: asset))
  }

  /// The depreciation run dialog.
  func awRunDialog(_ isPresented: Binding<Bool>) -> some View {
    modifier(AwRunDialog(isPresented: isPresented))
  }
}

private struct AwDisposeDialog: ViewModifier {
  @Binding var asset: JSONValue?
  @Environment(AppModel.self) private var model
  @State private var date = AcDate.today
  @State private var proceeds = 0.0
  @State private var depositAccountId = ""
  @State private var notes = ""
  @State private var busy = false
  @State private var error: String?

  func body(content: Content) -> some View {
    let name = asset.map { localName($0) } ?? ""
    content
      .webDialog(
        isPresented: shown, title: t("Dispose of {name}", ["name": name]),
        description: t(
          "Sold, scrapped or written off. Depreciation is charged up to the date, and the gain or loss is posted.")
      ) {
        form
      } footer: {
        WebButton(t("Cancel"), variant: .outline) { asset = nil }
        WebButton(t("Dispose of asset"), variant: .danger, loading: busy) { submit() }
          .disabled(!valid)
      }
      .onChange(of: asset?.rid, initial: true) { _, _ in
        guard asset != nil else { return }
        date = AcDate.today
        proceeds = 0
        depositAccountId = ""
        notes = ""
        busy = false
        error = nil
      }
  }

  private var shown: Binding<Bool> {
    Binding(get: { asset != nil }, set: { if !$0 { asset = nil } })
  }

  private var valid: Bool {
    guard let asset else { return false }
    return ISODates.isISODate(date) && date >= asset.str("purchaseDate")
  }

  /// Bank, cash and other current assets the money can go into.
  private var deposits: [JSONValue] {
    AwPick.byCode(
      model.one.records(.accounts).filter { a in
        let type = a.str("type")
        return !a.flag("archived") && (type == "asset_cash" || type == "asset_receivable" || type == "asset_current")
      })
  }

  @ViewBuilder
  private var form: some View {
    Field(t("Date")) { DateField(value: $date, required: true) }
    Field(t("Sale price"), hint: t("Leave at zero if it was scrapped.")) { AwAmountField(value: $proceeds) }
    if proceeds > 0 {
      Field(t("Money received in")) {
        Select(selection: $depositAccountId, options: AwPick.select(deposits))
      }
    }
    Field(t("Notes"), optional: true) { AwTextArea(text: $notes) }
    if let asset, valid {
      figures(asset)
    }
    AwFormError(text: error)
  }

  private func figures(_ asset: JSONValue) -> some View {
    let format = model.one.format
    let p = Money.precision(format.currency)
    let preview = AwAssets.disposalPreview(
      asset, model.one.records(.depreciationRuns), date: date, proceeds: proceeds, p)
    return VStack(spacing: 0) {
      AcLineRow(label: t("Depreciation to the date"), value: format.acMoney(preview.depreciation), divider: false)
      AcLineRow(label: t("Cost"), value: format.acMoney(preview.cost), divider: false)
      AcLineRow(label: t("Accumulated depreciation"), value: format.acMoney(preview.accumulated), divider: false)
      AcLineRow(label: t("Book value"), value: format.acMoney(preview.bookValue), divider: false)
      AcLineRow(label: t("Sale price"), value: format.acMoney(preview.proceeds), divider: false)
      AcLineRow(
        label: preview.gain >= 0 ? t("Gain on disposal") : t("Loss on disposal"),
        value: format.acMoney(abs(preview.gain)), strong: true)
    }
    .padding(.horizontal, -20)
  }

  private func submit() {
    guard let target = asset else { return }
    let id = target.rid
    let name = localName(target)
    let chosen = depositAccountId.isEmpty ? nil : depositAccountId
    let input = (date: date, proceeds: proceeds, notes: notes)
    busy = true
    error = nil
    Task {
      let done = await AwSave.perform(model, failed: { error = $0 }) { ctx, tr in
        try AwAssets.dispose(
          ctx, id: id, date: input.date, proceeds: input.proceeds, depositAccountId: chosen, notes: input.notes, tr: tr)
      }
      busy = false
      if done {
        model.confirm(t("{name} disposed of", ["name": name]))
        asset = nil
      }
    }
  }
}

// MARK: Running depreciation

private struct AwRunDialog: ViewModifier {
  @Binding var isPresented: Bool
  @Environment(AppModel.self) private var model
  @State private var period: String?
  @State private var busy = false
  @State private var error: String?

  func body(content: Content) -> some View {
    content
      .webDialog(
        isPresented: $isPresented, title: t("Run depreciation"),
        description: t("Charges every asset in use up to the end of the month, in one journal.")
      ) {
        form
      } footer: {
        WebButton(t("Cancel"), variant: .outline) { isPresented = false }
        WebButton(t("Post depreciation"), loading: busy) { run() }
          .disabled(!canRun)
      }
      .onChange(of: isPresented) { _, open in
        if open {
          period = nil
          error = nil
          busy = false
        }
      }
  }

  private var runs: [JSONValue] { model.one.records(.depreciationRuns) }
  private var month: String { period ?? AwAssets.suggestedPeriod(runs, today: AcDate.today) }
  private var current: String { AcDate.period(AcDate.today) }
  private var future: Bool { month > current }
  private var done: Bool { AwAssets.activeRuns(runs).contains { $0.str("period") == month } }

  private var due: [(asset: JSONValue, amount: Int)] {
    if future || done { return [] }
    let p = Money.precision(model.one.format.currency)
    return AwAssets.depreciationDue(model.one.records(.assets), runs, AwDepreciation.periodEnd(month), p)
  }

  private var canRun: Bool { !future && !done && !due.isEmpty }

  private func label(_ period: String) -> String {
    AcDate.monthLabel(period, arabic: LanguageStore.shared.isArabic)
  }

  /// This month and the three years before it, newest first.
  private var months: [SelectOption<String>] {
    var periods: [String] = []
    for back in 0..<36 { periods.append(AcDate.shiftPeriod(current, -back)) }
    if !periods.contains(month) { periods.append(month) }
    return periods.map { SelectOption($0, label($0)) }
  }

  private var monthBinding: Binding<String> {
    Binding(get: { month }, set: { period = $0 })
  }

  @ViewBuilder
  private var form: some View {
    Field(t("Month"), hint: t("Months that were skipped are caught up.")) {
      Select(selection: monthBinding, options: months)
    }
    if future {
      AwHint(t("Depreciation can only be run for months that have started."), tone: .amber(700))
    } else if done {
      AwHint(t("Depreciation for {month} is already posted.", ["month": label(month)]))
    } else if due.isEmpty {
      AwHint(t("Nothing to charge for {month}.", ["month": label(month)]))
    } else {
      dueList
    }
    AwFormError(text: error)
  }

  private var dueList: some View {
    let format = model.one.format
    let p = Money.precision(format.currency)
    let items = due
    let total = items.reduce(0) { $0 + $1.amount }
    return VStack(spacing: 0) {
      ForEach(items.map { Rec($0.asset) }) { record in
        AcLineRow(
          label: "\(record.raw.str("number")) \(localName(record.raw))",
          value: format.acMoney(items.first { $0.asset.rid == record.id }?.amount ?? 0))
      }
      AcLineRow(
        label: t("Total for {month}", ["month": label(month)]), value: format.money(Money.toNumber(Money.fromMinor(Int64(total), p))),
        strong: true)
    }
    .padding(.horizontal, -20)
  }

  private func run() {
    let chosen = month
    let shownMonth = label(chosen)
    guard let companyId = model.one.companyId else { return }
    busy = true
    error = nil
    Task {
      let result = await AwSave.run(model, failed: { error = $0 }) { ctx, tr in
        try AwAssets.runDepreciation(ctx, companyId: companyId, period: chosen, tr: tr).created
      }
      busy = false
      guard let created = result else { return }
      if created {
        model.confirm(t("Depreciation for {month} posted", ["month": shownMonth]))
        isPresented = false
      } else {
        error = t("Nothing to charge for {month}.", ["month": shownMonth])
      }
    }
  }
}
