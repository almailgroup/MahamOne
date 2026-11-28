import MahamKit
import SwiftUI

// `/assets` and `/assets/:id` (src/apps/books/pages/assets/index.tsx,
// detail.tsx): the register with its figures, the depreciation runs, and an
// asset with its depreciation schedule. Assets are made, disposed of and
// voided, and depreciation run and undone, natively (AwAssetForm,
// AwAssetActions) once they can be saved on this iPhone.

/// `/assets`: the fixed asset register and the monthly depreciation runs.
struct AcAssetsPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(SuiteState.self) private var suite: SuiteState?
  @State private var tab = "register"
  @State private var filter = "active"
  @State private var query = ""
  @State private var running = false
  @State private var confirm: AwConfirm?

  var body: some View {
    let one = model.one
    let format = one.format
    let p = Money.precision(format.currency)
    let assets = one.records(.assets)
    let runs = one.records(.depreciationRuns)
    let live = assets.filter { $0.str("status") != "void" }
    let active = live.filter { $0.str("status") == "active" }
    let cost = active.reduce(0) { $0 + AcLedger.minor($1.num("cost"), p) }
    let depreciated = active.reduce(0) { $0 + AcAssets.posted($1, runs, p) }
    let lastRun = AcAssets.activeRuns(runs).max { $0.str("period") < $1.str("period") }
    let accounting = AwAccess(model, suite).accounting
    let canNew = AwWrite.assets && accounting
    let canRun = AwWrite.depreciation && accounting
    WebPage(spacing: 16, refresh: { [model] in await model.one.sync() }) {
      PageHeader(
        t("Fixed assets"),
        description: t(
          "Equipment, vehicles, furniture and other things the business keeps for more than a year, and their depreciation."
        )
      ) {
        if canRun {
          WebButton(t("Run depreciation"), icon: .calendarClock, variant: .outline) { running = true }
            .disabled(active.isEmpty)
        }
        if canNew {
          WebButton(t("New asset"), icon: .plus, haptic: .press) { router.push(.newAsset) }
        }
      }
      .padding(.bottom, -16)
      AcStat(t("Cost of assets in use"), value: format.acMoney(cost))
      AcStat(
        t("Accumulated depreciation"), value: format.acMoney(depreciated),
        hint: lastRun.map { t("Depreciation posted up to {date}", ["date": format.date($0.text("date"))]) }
          ?? t("No depreciation posted yet"))
      AcStat(t("Book value"), value: format.acMoney(cost - depreciated))
      if canNew, unlinkedBillLines > 0 {
        AcNotice(
          tp(
            unlinkedBillLines, "{count} bill line was booked to a fixed asset account but is not in the register.",
            "{count} bill lines were booked to fixed asset accounts but are not in the register."),
          tone: .blue, link: t("Add from a bill"),
          onLink: {
            AwAssetDraft.source = "bill"
            router.push(.newAsset)
          })
      }
      ListCard {
        Segmented(
          selection: $tab,
          options: [
            SegmentOption("register", t("Register"), count: live.count),
            SegmentOption("runs", t("Depreciation runs"), count: AcAssets.activeRuns(runs).count),
          ])
        if tab == "register", !live.isEmpty {
          Segmented(
            selection: $filter,
            options: [
              SegmentOption("active", t("In use")), SegmentOption("disposed", t("Disposed of")),
              SegmentOption("all", t("All")),
            ], small: true)
          TextInput(text: $query, placeholder: t("Search assets…"), leadingIcon: .search)
        }
      } rows: {
        if tab == "runs" {
          AcRunsList(runs: runs, onUndo: undoAction(canRun))
        } else if assets.isEmpty, !one.hasData {
          DataLoadingRow()
        } else if live.isEmpty {
          WebEmptyState(
            icon: .landmark, title: t("No fixed assets yet"),
            description: t(
              "Add what the business owns, such as computers, furniture or vehicles. Maham Books works out the depreciation every month."
            )
          ) {
            if canNew {
              WebButton(t("New asset"), icon: .plus) { router.push(.newAsset) }
            }
          }
        } else {
          let shown = shownAssets(live)
          if shown.isEmpty {
            AcCardText(t("No assets match your search."), centered: true)
          } else {
            ForEach(shown.map(Rec.init)) { record in
              AcAssetRow(asset: record.raw, runs: runs, format: format)
            }
          }
        }
      }
    }
    .awRunDialog($running)
    .awConfirm($confirm)
  }

  /// Bill lines booked to fixed asset accounts that no asset was made from.
  private var unlinkedBillLines: Int {
    let one = model.one
    guard let company = one.company else { return 0 }
    let bills = one.records(.documents).filter { $0.str("type") == "bill" }
    return AwAssets.billAssetLines(
      company: company, bills: bills, accounts: one.records(.accounts), assets: one.records(.assets)
    ).filter { $0.assetId == nil }.count
  }

  /// Undoing the latest run, for those who may.
  private func undoAction(_ allowed: Bool) -> ((JSONValue) -> Void)? {
    guard allowed else { return nil }
    return { run in confirm = AwAssetActions.undoRun(run, model: model) }
  }

  private func shownAssets(_ live: [JSONValue]) -> [JSONValue] {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    let kept = live.filter { asset in
      guard filter == "all" || asset.str("status") == filter else { return false }
      if q.isEmpty { return true }
      let text = [
        asset.str("number"), asset.str("name"), asset.str("nameAr"), asset.str("serialNumber"), asset.str("location"),
        asset.str("custodian"),
      ].joined(separator: " ").lowercased()
      return text.contains(q)
    }
    return kept.sorted { AcText.compareNumeric($0.str("number"), $1.str("number")) == .orderedDescending }
  }
}

/// An asset in the register: its name and number, book value and status.
struct AcAssetRow: View {
  let asset: JSONValue
  let runs: [JSONValue]
  let format: CompanyFormat
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let p = Money.precision(format.currency)
    let active = asset.str("status") == "active"
    ListRow(
      title: localName(asset), subtitle: asset.str("number"),
      amount: active ? format.acMoney(AcAssets.bookValue(asset, runs, p)) : "—"
    ) {
      Badge(status: AcAssets.status(asset.str("status")))
    } action: {
      router.push(.asset(id: asset.rid))
    }
  }
}

/// The depreciation runs, newest first; undone ones struck through.
struct AcRunsList: View {
  let runs: [JSONValue]
  /// Undoes the latest run that was not undone, for those who may.
  var onUndo: ((JSONValue) -> Void)? = nil
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let sorted = runs.sorted { a, b in
      a.str("period") != b.str("period")
        ? a.str("period") > b.str("period") : a.str("createdAt") > b.str("createdAt")
    }
    if sorted.isEmpty {
      WebEmptyState(
        icon: .calendarClock, title: t("No depreciation runs yet"),
        description: t(
          "Run depreciation at the end of each month. Each run posts one journal for every asset in use."))
    } else {
      ForEach(sorted.map(Rec.init)) { record in
        runRow(record.raw)
      }
    }
  }

  /// The latest run that was not undone: the only one that can be undone.
  private var latest: JSONValue? {
    AcAssets.activeRuns(runs).max { $0.str("period") < $1.str("period") }
  }

  @ViewBuilder
  private func runRow(_ run: JSONValue) -> some View {
    if let onUndo, run.rid == latest?.rid {
      HStack(spacing: 0) {
        Button {
          Haptics.play(.tap)
          router.push(.journal(id: run.str("journalId")))
        } label: {
          runContent(run).contentShape(Rectangle())
        }
        .buttonStyle(PressedFill(radius: 0, color: .slate(100)))
        WebButton(t("Undo"), icon: .undo2, variant: .ghost, size: .sm) { onUndo(run) }
          .padding(.trailing, 8)
      }
      .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
    } else {
      AcTapRow(action: { router.push(.journal(id: run.str("journalId"))) }) { runContent(run) }
    }
  }

  @ViewBuilder
  private func runContent(_ run: JSONValue) -> some View {
    let format = model.one.format
    let undone = run.text("reversedAt") != nil
    let journal = model.one.record(.journals, run.str("journalId"))
    let reversal = run.text("reversalJournalId").flatMap { model.one.record(.journals, $0) }
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(AcDate.monthLabel(run.str("period"), arabic: LanguageStore.shared.isArabic))
              .font(.web(16, .medium))
              .strikethrough(undone)
              .foregroundStyle(undone ? palette.slate(500) : palette.slate(900))
            if undone { Badge(t("Undone")) }
          }
          Text(journalNumbers(journal, reversal))
            .font(.web(12))
            .foregroundStyle(palette.primary(700))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Text(format.money(run.num("total")))
          .font(.web(14, .semibold, tabular: true))
          .foregroundStyle(undone ? palette.slate(500) : palette.slate(900))
          .environment(\.layoutDirection, .leftToRight)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(minHeight: 56)
  }

  private func journalNumbers(_ journal: JSONValue?, _ reversal: JSONValue?) -> String {
    var parts: [String] = []
    if let journal { parts.append(journal.str("number")) }
    if let reversal { parts.append(reversal.str("number")) }
    return parts.joined(separator: " · ")
  }
}

/// `/assets/:id`: an asset's details, value, depreciation schedule and entries.
struct AcAssetPage: View {
  let id: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(SuiteState.self) private var suite: SuiteState?
  @State private var fullSchedule = false
  @State private var disposing: JSONValue?
  @State private var confirm: AwConfirm?

  init(id: String) {
    self.id = id
  }

  var body: some View {
    let one = model.one
    let asset = one.record(.assets, id)
    let accounting = AwAccess(model, suite).accounting
    RecordDetailPage(
      record: asset, title: asset.map { localName($0) } ?? "", subtitle: asset?.str("number"),
      breadcrumb: t("Fixed assets")
    ) {
      if let asset { Badge(status: AcAssets.status(asset.str("status"))) }
    } actions: {
      if let asset, asset.str("status") != "void", accounting {
        actions(asset)
      }
    } content: {
      if let asset {
        AcAssetDetails(asset: asset)
        if asset.str("status") == "active" {
          AcScheduleCard(asset: asset, full: $fullSchedule)
        }
        AcAssetEntries(asset: asset)
        AcAssetValue(asset: asset)
      }
    }
    .awDisposeDialog($disposing)
    .awConfirm($confirm)
  }

  /// Dispose of, Undo disposal, Edit and Void asset, as each can be saved on this iPhone.
  @ViewBuilder
  private func actions(_ asset: JSONValue) -> some View {
    let status = asset.str("status")
    let depreciated = AcAssets.lastDepreciationDate(asset, model.one.records(.depreciationRuns)) != nil
    if status == "active", AwWrite.disposals {
      WebButton(t("Dispose of"), icon: .trash2, variant: .outline, size: .sm) { disposing = asset }
    }
    if status == "disposed", AwWrite.assets {
      WebButton(t("Undo disposal"), icon: .undo2, variant: .outline, size: .sm) {
        confirm = AwAssetActions.undoDisposal(asset, model: model)
      }
    }
    if AwWrite.assets {
      WebButton(t("Edit"), icon: .pencil, variant: .outline, size: .sm) { router.push(.editAsset(id: id)) }
    }
    if status == "active", !depreciated, AwWrite.assets {
      DropdownMenu(name: t("More actions")) {
        IconView(.moreHorizontal, size: 16)
      } items: {
        DropdownItem(t("Void asset"), icon: .ban, danger: true) {
          confirm = AwAssetActions.voidAsset(asset, model: model, router: router)
        }
      }
    }
  }
}

/// The asset's details card, its notes and its disposal.
struct AcAssetDetails: View {
  let asset: JSONValue
  @Environment(AppModel.self) private var model

  var body: some View {
    let one = model.one
    let format = one.format
    let books = one.acBooks
    InfoCard(t("Details"), rows: rows(books, format))
    TextCard(title: t("Notes"), text: notes)
    if let disposal = asset.obj("disposal") {
      let gain = disposal.num("gain")
      InfoCard(
        t("Disposal"),
        rows: [
          InfoRow(t("Date"), format.date(disposal.text("date"))),
          InfoRow(t("Sale price"), format.money(disposal.num("proceeds")), tabular: true),
          InfoRow(
            gain >= 0 ? t("Gain on disposal") : t("Loss on disposal"), format.money(abs(gain)), strong: true,
            tabular: true),
          InfoRow(t("Depreciation to the date"), format.money(disposal.num("depreciation")), tabular: true),
        ])
    }
  }

  private var notes: String? {
    let text = [asset.str("description"), asset.str("notes")].filter { !$0.isEmpty }.joined(separator: "\n")
    return text.isEmpty ? nil : text
  }

  private func label(_ books: AcBooks, _ id: String?) -> String {
    guard let account = books.account(id) else { return "—" }
    return "\(account.code) \(localName(account.raw))"
  }

  private func rows(_ books: AcBooks, _ format: CompanyFormat) -> [InfoRow] {
    let terms = AcDepreciationTerms(asset)
    let method =
      asset.str("method") == "declining_balance"
      ? t(
        "{method}, {rate} a year",
        ["method": t(AcAssets.methodLabel(asset.str("method"))), "rate": format.percent(AcDepreciation.decliningRate(terms))])
      : t(AcAssets.methodLabel(asset.str("method")))
    var rows = [
      InfoRow(t("Asset account"), label(books, asset.text("assetAccountId"))),
      InfoRow(t("Purchase date"), format.date(asset.text("purchaseDate"))),
      InfoRow(t("Bought"), bought(books)),
      InfoRow(t("Depreciation method"), method),
      InfoRow(t("Useful life"), AcAssets.lifeText(Int(asset.num("usefulLifeMonths")))),
      InfoRow(t("Depreciation starts"), format.date(asset.text("depreciationStart"))),
      InfoRow(t("Accumulated depreciation account"), label(books, asset.text("accumulatedAccountId"))),
      InfoRow(t("Depreciation expense account"), label(books, asset.text("expenseAccountId"))),
      InfoRow(t("Serial number"), asset.str("serialNumber")),
      InfoRow(t("Location"), asset.str("location")),
      InfoRow(t("Custodian"), asset.str("custodian")),
    ]
    if let arabic = asset.text("nameAr"), arabic != localName(asset) {
      rows.append(InfoRow(t("Name in Arabic"), arabic))
    }
    return rows
  }

  private func bought(_ books: AcBooks) -> String {
    let source = asset.str("source")
    if source == "bill", asset.text("billId") != nil {
      let bill = asset.text("billId").flatMap { model.one.record(.documents, $0) }
      return bill.map { "\(t("Bill")) \($0.str("number"))" } ?? t("From a bill")
    }
    if source == "purchase" {
      return t("Paid from {account}", ["account": label(books, asset.text("paidFromAccountId"))])
    }
    return t(AcAssets.sourceLabel(source))
  }
}

/// The asset's value: cost, salvage value, depreciation and book value.
struct AcAssetValue: View {
  let asset: JSONValue
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let p = Money.precision(format.currency)
    let runs = one.records(.depreciationRuns)
    let posted = AcAssets.posted(asset, runs, p)
    let cost = AcLedger.minor(asset.num("cost"), p)
    let active = asset.str("status") == "active"
    let last = AcAssets.lastDepreciationDate(asset, runs)
    Card {
      CardHeader(t("Value"))
      VStack(spacing: 0) {
        AcLineRow(label: t("Cost"), value: format.acMoney(cost), divider: false)
        AcLineRow(label: t("Salvage value"), value: format.money(asset.num("salvageValue")))
        AcLineRow(label: t("Accumulated depreciation"), value: active ? format.acMoney(posted) : "—")
        AcLineRow(label: t("Book value"), value: active ? format.acMoney(cost - posted) : "—", strong: true)
      }
      Text(
        last.map { t("Depreciation posted up to {date}", ["date": format.date($0)]) } ?? t("No depreciation posted yet")
      )
      .font(.web(12))
      .foregroundStyle(palette.slate(500))
      .padding(.horizontal, 20)
      .padding(.top, 4)
      .padding(.bottom, 16)
    }
  }
}

/// `Depreciation schedule`: month by month until the end of the useful life.
struct AcScheduleCard: View {
  let asset: JSONValue
  @Binding var full: Bool
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let p = Money.precision(format.currency)
    let schedule = AcDepreciation.schedule(AcDepreciationTerms(asset), p)
    let posted = postedPeriods(one.records(.depreciationRuns))
    let shown = full ? schedule : Array(schedule.prefix(12))
    Card {
      CardHeader(t("Depreciation schedule"), description: t("Month by month until the end of its useful life."))
      if schedule.isEmpty {
        AcCardText(t("Fully depreciated."))
      } else {
        HStack(spacing: 12) {
          Text(t("Month")).frame(maxWidth: .infinity, alignment: .leading)
          Text(t("Depreciation")).frame(width: 96, alignment: .trailing)
          Text(t("Book value")).frame(width: 104, alignment: .trailing)
        }
        .font(.web(12, .medium))
        .foregroundStyle(palette.slate(500))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(palette.slate(50).opacity(0.6))
        ForEach(shown, id: \.period) { row in
          scheduleRow(row, format: format, posted: posted.contains(row.period))
        }
        if schedule.count > 12 {
          WebButton(full ? t("Show less") : t("Show the whole schedule"), variant: .ghost, size: .sm) {
            full.toggle()
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
        }
      }
    }
  }

  private func postedPeriods(_ runs: [JSONValue]) -> Set<String> {
    var out = Set<String>()
    for run in AcAssets.activeRuns(runs) where run.list("lines").contains(where: { $0.str("assetId") == asset.rid }) {
      out.insert(run.str("period"))
    }
    return out
  }

  private func scheduleRow(_ row: AcScheduleRow, format: CompanyFormat, posted: Bool) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(AcDate.monthLabel(row.period, arabic: LanguageStore.shared.isArabic))
          .font(.web(14))
          .foregroundStyle(palette.slate(700))
        if posted { Badge(t("Posted"), tone: .green) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Text(format.acMoney(row.charge))
        .frame(width: 96, alignment: .trailing)
        .foregroundStyle(palette.slate(700))
      Text(format.acMoney(row.bookValue))
        .frame(width: 104, alignment: .trailing)
        .foregroundStyle(palette.slate(900))
    }
    .font(.web(13, tabular: true))
    .lineLimit(1)
    .minimumScaleFactor(0.7)
    .padding(.horizontal, 20)
    .padding(.vertical, 10)
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }
}

/// `Entries`: the journals that record the asset.
struct AcAssetEntries: View {
  let asset: JSONValue
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let format = model.one.format
    let entries = self.entries
    Card {
      CardHeader(t("Entries"), description: t("Journals that record this asset."))
      if entries.isEmpty {
        AcCardText(t("Nothing posted yet."))
      } else {
        VStack(spacing: 0) {
          ForEach(entries.indices, id: \.self) { index in
            entryRow(entries[index].journal, amount: entries[index].amount, format: format)
          }
        }
      }
    }
  }

  private var entries: [(journal: JSONValue, amount: Double)] {
    let one = model.one
    let id = asset.rid
    var out: [(journal: JSONValue, amount: Double)] = []
    for journal in one.records(.journals) where journal.str("sourceId") == id {
      out.append((journal, journal.list("lines").reduce(0) { $0 + $1.num("debit") }))
    }
    for run in one.records(.depreciationRuns) {
      guard let line = run.list("lines").first(where: { $0.str("assetId") == id && $0.num("amount") != 0 }),
        let journal = one.record(.journals, run.str("journalId"))
      else { continue }
      out.append((journal, line.num("amount")))
    }
    return out.enumerated().sorted { a, b in
      let x = a.element.journal.str("date")
      let y = b.element.journal.str("date")
      return x == y ? a.offset < b.offset : x > y
    }.map { $0.element }
  }

  private func entryRow(_ journal: JSONValue, amount: Double, format: CompanyFormat) -> some View {
    AcTapRow(action: { router.push(.journal(id: journal.rid)) }) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(journal.str("number")).font(.web(14, .medium)).foregroundStyle(palette.primary(700))
            Text(format.date(journal.text("date"))).font(.web(14)).foregroundStyle(palette.slate(500))
          }
          FlowLayout(spacing: 6, lineSpacing: 6) {
            AcJournalBadges(journal: journal, showStatus: false)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Text(format.money(amount))
          .font(.web(14, tabular: true))
          .foregroundStyle(palette.slate(900))
          .environment(\.layoutDirection, .leftToRight)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 10)
    }
  }
}
