import MahamKit
import SwiftUI

// The fixed asset form (src/apps/books/pages/assets/form.tsx, with the
// account pickers of shared.tsx): `/assets/new` and `/assets/:id/edit`. The
// asset's details, how it was bought (paid now, from a bill line, owned
// before, already in the books), its depreciation and a live preview.

@MainActor
enum AwAssetAccounts {
  private static func isAssetAccount(_ account: JSONValue) -> Bool {
    let type = account.str("type")
    return type == "asset_fixed" || type == "asset_non_current"
  }

  /// `isAccumulated`: an accumulated depreciation or amortisation account.
  static func isAccumulated(_ account: JSONValue) -> Bool {
    let name = account.str("name")
    let matches = name.range(of: "accumulated|depreciation|amorti[sz]ation", options: [.regularExpression, .caseInsensitive])
    return matches != nil || account.str("nameAr").contains("مجمع")
  }

  /// `categoryAccounts`: fixed and non-current asset accounts that hold cost.
  static func categories(_ accounts: [JSONValue], keep: String?) -> [JSONValue] {
    AwPick.byCode(
      accounts.filter { a in
        (isAssetAccount(a) && !isAccumulated(a) && !a.flag("archived")) || a.rid == keep
      })
  }

  /// `accumulatedAccounts`: asset accounts, the usual ones first.
  static func accumulated(_ accounts: [JSONValue], keep: String?) -> [JSONValue] {
    let kept = AwPick.byCode(accounts.filter { a in (isAssetAccount(a) && !a.flag("archived")) || a.rid == keep })
    return kept.filter(isAccumulated) + kept.filter { !isAccumulated($0) }
  }

  /// `expenseAccounts`: accounts depreciation can be charged to, depreciation first.
  static func expenses(_ accounts: [JSONValue], keep: String?) -> [JSONValue] {
    let kept = AwPick.byCode(
      accounts.filter { a in
        (AcAccountTypes.group(a.str("type")) == .expense && !a.flag("archived")) || a.rid == keep
      })
    return kept.filter { $0.str("type") == "expense_depreciation" }
      + kept.filter { $0.str("type") != "expense_depreciation" }
  }

  /// Bank, cash and card accounts the asset can be paid from.
  static func money(_ accounts: [JSONValue], keep: String?) -> [JSONValue] {
    AwPick.byCode(
      accounts.filter { a in
        AcAccountTypes.isMoneyAccount(a.str("type")) && (!a.flag("archived") || a.rid == keep)
      })
  }

  /// `suggestAccumulated`: the nearest accumulated depreciation account coded
  /// after the category (1520 → 1530 in the Kuwait chart).
  static func suggestAccumulated(_ accounts: [JSONValue], categoryId: String) -> JSONValue? {
    guard let category = accounts.first(where: { $0.rid == categoryId }) else { return nil }
    let candidates = accounts.filter { isAssetAccount($0) && isAccumulated($0) && !$0.flag("archived") }
    if let code = Double(category.str("code")) {
      let after = candidates.compactMap { a -> (JSONValue, Double)? in
        guard let value = Double(a.str("code")), value > code else { return nil }
        return (a, value)
      }.sorted { $0.1 < $1.1 }
      if let near = after.first(where: { $0.1 - code <= 20 }) { return near.0 }
    }
    return candidates.first { $0.str("type") == category.str("type") } ?? candidates.first
  }

  /// `suggestExpense`: the depreciation account of the chart.
  static func suggestExpense(_ books: AcBooks) -> String? {
    if let found = AcSpec.depreciation.find(books.accounts, template: books.settings.template) { return found.id }
    return books.accounts.first { $0.type == "expense_depreciation" && !$0.archived }?.id
  }
}

/// `SOURCE_LABELS`: how an asset was bought.
enum AwAssetSource {
  static let all = ["purchase", "bill", "opening", "existing"]

  static func hint(_ source: String) -> String {
    switch source {
    case "bill": "The bill already recorded the cost; the asset is linked to its line."
    case "opening": "Bought before you used Maham Books: records its cost and the depreciation so far."
    case "existing": "The cost is already in the accounts, for example from a journal. Nothing is posted."
    default: "Records the purchase, paid from a bank, cash or card account."
    }
  }
}

/// `/assets/new` and `/assets/:id/edit`.
struct AwAssetFormPage: View {
  let id: String?
  @Environment(AppModel.self) private var model
  @State private var fresh: JSONValue?

  init(id: String?) {
    self.id = id
  }

  var body: some View {
    let existing = id.flatMap { model.one.record(.assets, $0) }
    content(existing)
      .onAppear {
        if id == nil, fresh == nil {
          fresh = newAsset(source: AwAssetDraft.source ?? "purchase")
          AwAssetDraft.source = nil
        }
      }
  }

  @ViewBuilder
  private func content(_ existing: JSONValue?) -> some View {
    if let initial = existing ?? fresh {
      AwAssetForm(initial: initial, isNew: existing == nil)
        .id(initial.rid + initial.str("updatedAt"))
    } else {
      RecordDetailPage(record: nil, title: t("New asset")) { EmptyView() }
    }
  }

  /// A new asset (paid for now, or from a bill), with the usual expense account and the bank.
  private func newAsset(source: String) -> JSONValue? {
    guard let companyId = model.one.companyId else { return nil }
    let books = model.one.acBooks
    let bank = books.roles["bank"]
    return AwAssets.blank(
      companyId: companyId,
      overrides: [
        "expenseAccountId": .string(AwAssetAccounts.suggestExpense(books) ?? ""),
        "paidFromAccountId": bank.map(JSONValue.string) ?? .null, "source": .string(source),
      ], today: AcDate.today)
  }
}

/// The form itself.
struct AwAssetForm: View {
  let initial: JSONValue
  let isNew: Bool
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var asset: JSONValue
  @State private var saving = false
  @State private var confirm: AwConfirm?

  init(initial: JSONValue, isNew: Bool) {
    self.initial = initial
    self.isNew = isNew
    _asset = State(initialValue: initial)
  }

  var body: some View {
    let one = model.one
    let runs = one.records(.depreciationRuns)
    let locked =
      !isNew && (initial.str("status") == "disposed" || AwAssets.lastDepreciationDate(initial, runs) != nil)
    WebPage(spacing: 16) {
      PageHeader(
        isNew ? t("New asset") : t("Edit {name}", ["name": localName(initial)]), breadcrumb: t("Fixed assets"),
        onBreadcrumb: { leave() }
      )
      .padding(.bottom, -16)
      detailsCard
      purchaseCard(locked)
      depreciationCard(locked)
      notesCard
      AwAssetPreview(asset: asset)
    }
    .stickyActions {
      WebButton(t("Cancel"), variant: .outline) { leave() }
      WebButton(t("Save asset"), loading: saving) { save() }
    }
    .awConfirm($confirm)
  }

  // MARK: Cards

  private var detailsCard: some View {
    Card {
      CardHeader(t("Asset"))
      CardBody {
        Field(t("Name")) { TextInput(text: text("name")) }
        Field(t("Name in Arabic"), optional: true) {
          TextInput(text: text("nameAr")).environment(\.layoutDirection, .rightToLeft)
        }
        Field(t("Asset number"), hint: t("Leave empty to number it automatically.")) {
          TextInput(text: text("number"), placeholder: "FA-0001")
        }
        Field(t("Serial number"), optional: true) { TextInput(text: text("serialNumber")) }
        Field(t("Location"), optional: true) {
          TextInput(text: text("location"), placeholder: t("e.g. Head office, Shuwaikh warehouse"))
        }
        Field(t("Custodian"), hint: t("Who looks after it."), optional: true) { TextInput(text: text("custodian")) }
        Field(t("Description"), optional: true) { AwTextArea(text: text("description")) }
      }
    }
  }

  private func purchaseCard(_ locked: Bool) -> some View {
    let source = asset.str("source")
    let accounts = model.one.records(.accounts)
    return Card {
      CardHeader(t("Purchase"), description: t(AwAssetSource.hint(source)))
      CardBody {
        if locked {
          AcNotice(
            t(
              "Depreciation has been posted for this asset, so its cost and depreciation can’t change. Undo the depreciation runs first."
            ), icon: .lock, tone: .slate)
        }
        if isNew {
          Segmented(selection: text("source"), options: sourceOptions)
        }
        if source == "bill" {
          Field(t("Bill line")) {
            Combobox(
              selection: billLineBinding, options: lineOptions, placeholder: t("Choose a bill line…"),
              searchPlaceholder: t("Search bills…"), emptyText: t("No bill lines booked to fixed asset accounts."))
          }
          .disabled(locked)
        }
        Field(t("Asset account"), hint: t("The category, e.g. vehicles.")) {
          Select(
            selection: categoryBinding,
            options: AwPick.select(AwAssetAccounts.categories(accounts, keep: asset.text("assetAccountId"))))
        }
        .disabled(locked)
        if source == "purchase" {
          Field(t("Paid from")) {
            Select(
              selection: text("paidFromAccountId"),
              options: AwPick.select(AwAssetAccounts.money(accounts, keep: asset.text("paidFromAccountId"))))
          }
          .disabled(locked)
        }
        Field(t("Purchase date")) {
          DateField(value: purchaseDateBinding, required: true)
        }
        .disabled(locked)
        Field(t("Cost")) {
          AwAmountField(value: number("cost"))
        }
        .disabled(locked)
      }
    }
  }

  private func depreciationCard(_ locked: Bool) -> some View {
    let accounts = model.one.records(.accounts)
    let source = asset.str("source")
    let months = asset.num("usefulLifeMonths")
    let defaultRate = AcDepreciation.defaultDecliningRate(months)
    let format = model.one.format
    return Card {
      CardHeader(t("Depreciation"))
      CardBody {
        Field(t("Depreciation starts"), hint: t("When the asset was put to use.")) {
          DateField(value: text("depreciationStart"), required: true)
        }
        Field(t("Useful life (months)"), hint: AcAssets.lifeText(Int(months))) {
          AwAmountField(value: lifeBinding, blankZero: false)
        }
        Field(t("Depreciation method")) {
          Select(selection: text("method"), options: methodOptions)
        }
        if asset.str("method") == "declining_balance" {
          Field(
            t("Yearly rate (%)"), hint: t("Empty uses twice the straight-line rate ({rate}).", ["rate": format.percent(defaultRate)]),
            optional: true
          ) {
            AwAmountField(value: rateBinding)
          }
        }
        Field(t("Salvage value"), hint: t("What it will be worth at the end."), optional: true) {
          AwAmountField(value: number("salvageValue"))
        }
        if source != "purchase" {
          Field(t("Depreciation already charged"), hint: t("Before the asset was entered here."), optional: true) {
            AwAmountField(value: number("openingDepreciation"))
          }
          if asset.num("openingDepreciation") > 0 {
            Field(t("Charged up to")) {
              DateField(value: openingDateBinding)
            }
          }
        }
        Field(t("Accumulated depreciation account")) {
          Select(
            selection: text("accumulatedAccountId"),
            options: AwPick.select(AwAssetAccounts.accumulated(accounts, keep: asset.text("accumulatedAccountId"))))
        }
        Field(t("Depreciation expense account")) {
          Select(
            selection: text("expenseAccountId"),
            options: AwPick.select(AwAssetAccounts.expenses(accounts, keep: asset.text("expenseAccountId"))))
        }
      }
      .disabled(locked)
    }
  }

  private var notesCard: some View {
    Card {
      CardHeader(t("Notes"))
      CardBody {
        Field(t("Notes"), optional: true) { AwTextArea(text: text("notes")) }
      }
    }
  }

  private var sourceOptions: [SegmentOption<String>] {
    [
      SegmentOption("purchase", t("Paid for now")), SegmentOption("bill", t("From a bill")),
      SegmentOption("opening", t("Owned before")), SegmentOption("existing", t("Already in the books")),
    ]
  }

  private var methodOptions: [SelectOption<String>] {
    [SelectOption("straight_line", t("Straight line")), SelectOption("declining_balance", t("Declining balance"))]
  }

  // MARK: Bill lines

  private var billLines: [AwBillAssetLine] {
    let one = model.one
    guard let company = one.company else { return [] }
    let bills = one.records(.documents).filter { $0.str("type") == "bill" }
    return AwAssets.billAssetLines(
      company: company, bills: bills, accounts: one.records(.accounts), assets: one.records(.assets))
  }

  private var lineOptions: [ComboOption] {
    let format = model.one.format
    let chosen = asset.str("billLineId")
    return billLines.filter { $0.assetId == nil || $0.line.str("id") == chosen }.map { found in
      let name = localName(found.line)
      return ComboOption(
        value: found.line.str("id"), label: "\(found.bill.str("number")) · \(name.isEmpty ? t("Line") : name)",
        detail: format.money(found.cost),
        keywords: "\(found.bill.str("vendorReference")) \(found.line.str("description"))")
    }
  }

  private var billLineBinding: Binding<String?> {
    Binding(
      get: { asset.text("billLineId") },
      set: { lineId in
        guard let lineId, let found = billLines.first(where: { $0.line.str("id") == lineId }) else { return }
        chooseLine(found)
      })
  }

  /// `chooseLine`: the asset takes the line's name, cost, date and account.
  private func chooseLine(_ found: AwBillAssetLine) {
    let accounts = model.one.records(.accounts)
    let date = found.bill.str("issueDate")
    var patch: [String: JSONValue] = [
      "billId": .string(found.bill.rid), "billLineId": .string(found.line.str("id")),
      "cost": .number(found.cost), "purchaseDate": .string(date), "depreciationStart": .string(date),
      "assetAccountId": .string(found.accountId),
      "vendorId": found.bill.text("clientId").map(JSONValue.string) ?? .null,
    ]
    if asset.str("name").isEmpty { patch["name"] = .string(found.line.str("name")) }
    if asset.str("nameAr").isEmpty, let arabic = found.line.text("nameAr") { patch["nameAr"] = .string(arabic) }
    if asset.str("description").isEmpty { patch["description"] = .string(found.line.str("description")) }
    if let accumulated = AwAssetAccounts.suggestAccumulated(accounts, categoryId: found.accountId) {
      patch["accumulatedAccountId"] = .string(accumulated.rid)
    }
    update(patch)
  }

  // MARK: Bindings

  private func update(_ patch: [String: JSONValue]) {
    var fields = asset.object ?? [:]
    for (key, value) in patch { fields[key] = value }
    asset = .object(fields)
  }

  private func text(_ key: String) -> Binding<String> {
    Binding(get: { asset.str(key) }, set: { update([key: .string($0)]) })
  }

  private func number(_ key: String) -> Binding<Double> {
    Binding(get: { asset.num(key) }, set: { update([key: .number(max(0, $0))]) })
  }

  /// The category, and the accumulated depreciation account that goes with it.
  private var categoryBinding: Binding<String> {
    Binding(
      get: { asset.str("assetAccountId") },
      set: { categoryId in
        var patch: [String: JSONValue] = ["assetAccountId": .string(categoryId)]
        let accounts = model.one.records(.accounts)
        if let accumulated = AwAssetAccounts.suggestAccumulated(accounts, categoryId: categoryId) {
          patch["accumulatedAccountId"] = .string(accumulated.rid)
        }
        update(patch)
      })
  }

  /// The purchase date; depreciation starts with it unless it was set apart.
  private var purchaseDateBinding: Binding<String> {
    Binding(
      get: { asset.str("purchaseDate") },
      set: { date in
        let start = asset.str("depreciationStart") == asset.str("purchaseDate") ? date : asset.str("depreciationStart")
        update(["purchaseDate": .string(date), "depreciationStart": .string(start)])
      })
  }

  /// Whole months.
  private var lifeBinding: Binding<Double> {
    Binding(
      get: { asset.num("usefulLifeMonths") },
      set: { update(["usefulLifeMonths": .number(max(0, $0).rounded())]) })
  }

  /// The yearly rate; empty (0) uses the default.
  private var rateBinding: Binding<Double> {
    Binding(
      get: { asset["decliningRate"]?.double ?? 0 },
      set: { rate in update(["decliningRate": rate > 0 ? .number(rate) : .null]) })
  }

  private var openingDateBinding: Binding<String> {
    Binding(
      get: { asset.str("openingDepreciationDate") },
      set: { date in update(["openingDepreciationDate": date.isEmpty ? .null : .string(date)]) })
  }

  // MARK: Saving

  private func leave() {
    if asset != initial {
      confirm = AwUnsaved.confirm { router.back() }
    } else {
      router.back()
    }
  }

  private func save() {
    let input = asset
    let created = isNew
    saving = true
    Task {
      let saved = await AwSave.run(model) { ctx, tr in try AwAssets.save(ctx, input, tr: tr) }
      saving = false
      guard let saved else { return }
      model.confirm(t("Asset {number} saved", ["number": saved.str("number")]))
      router.back()
      if created { router.push(.asset(id: saved.rid)) }
    }
  }
}

/// `Depreciation preview`: each month's charge, the first and last months, the total.
struct AwAssetPreview: View {
  let asset: JSONValue
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  init(asset: JSONValue) {
    self.asset = asset
  }

  var body: some View {
    let format = model.one.format
    let p = Money.precision(format.currency)
    let rows = schedule(p)
    Card {
      CardHeader(t("Depreciation preview"))
      if let first = rows.first, let last = rows.last {
        let monthly = rows.count > 1 ? rows[1].charge : first.charge
        let arabic = LanguageStore.shared.isArabic
        VStack(spacing: 0) {
          AcLineRow(label: t("Each month"), value: format.acMoney(monthly), strong: true, divider: false)
          AcLineRow(
            label: t("First month"),
            value: "\(AcDate.monthLabel(first.period, arabic: arabic)) · \(format.acMoney(first.charge))")
          AcLineRow(label: t("Fully depreciated"), value: AcDate.monthLabel(last.period, arabic: arabic))
          AcLineRow(label: t("Total to depreciate"), value: format.money(total), strong: true)
        }
        .padding(.bottom, 8)
      } else {
        AcCardText(t("Enter the cost, the useful life and when depreciation starts."))
      }
    }
  }

  private var total: Double {
    Money.toNumber(
      Money.dec(asset.num("cost")) - Money.dec(asset.num("salvageValue")) - Money.dec(asset.num("openingDepreciation")))
  }

  private func schedule(_ p: Int) -> [AcScheduleRow] {
    guard asset.num("cost") > asset.num("salvageValue"), asset.num("usefulLifeMonths") > 0,
      !asset.str("depreciationStart").isEmpty
    else { return [] }
    return AcDepreciation.schedule(AcDepreciationTerms(asset), p)
  }
}
