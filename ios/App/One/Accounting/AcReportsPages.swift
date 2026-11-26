import MahamKit
import SwiftUI

// `/reports` and `/reports/:report` (src/apps/books/pages/reports/index.tsx,
// financial.tsx and the report document of features/reports): the reports
// by group, and each report with the web's period choices, read only.

/// The reports the web lists, by group (`GROUPS`).
enum AcReportList {
  static let groups: [(title: String, items: [(id: String, label: String)])] = [
    (
      "Financial statements",
      [
        ("balance-sheet", "Balance sheet"), ("profit-and-loss", "Profit and loss"),
        ("changes-in-equity", "Changes in equity"), ("cash-flow", "Cash flow"),
      ]
    ),
    (
      "Accounting",
      [
        ("trial-balance", "Trial balance"), ("general-ledger", "General ledger"),
        ("asset-schedule", "Fixed asset schedule"), ("auditor-pack", "Auditor pack"),
      ]
    ),
    (
      "Sales",
      [
        ("aging", "Receivables aging"), ("tax", "Tax summary"), ("sales", "Sales by client"),
        ("payments", "Payments received"),
      ]
    ),
    (
      "Credit control",
      [("statements", "Statements of account"), ("exposure", "Customer exposure"), ("retentions", "Retentions")]
    ),
    ("Purchases", [("payables", "Payables aging"), ("purchases", "Purchases by vendor"), ("payments-made", "Payments made")]),
    (
      "Inventory",
      [
        ("stock-on-hand", "Stock on hand"), ("stock-valuation", "Stock valuation"),
        ("stock-movements", "Stock movements"), ("low-stock", "Low stock"), ("issued-items", "Issued items"),
      ]
    ),
  ]

  static var ids: [String] { groups.flatMap { $0.items.map { $0.id } } }

  static func label(_ id: String) -> String {
    for group in groups {
      if let item = group.items.first(where: { $0.id == id }) { return item.label }
    }
    return id
  }

  /// A report's address: its id and the query after it ("general-ledger?account=…").
  static func parse(_ name: String) -> (id: String, params: [String: String]) {
    let pieces = name.split(separator: "?", maxSplits: 1).map(String.init)
    var params: [String: String] = [:]
    if pieces.count > 1 {
      for pair in pieces[1].split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2 { params[parts[0]] = parts[1].removingPercentEncoding ?? parts[1] }
      }
    }
    return (pieces.first ?? name, params)
  }
}

/// `/reports`: every report, by group.
struct AcReportsPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    WebPage(spacing: 16, refresh: { [model] in await model.one.sync() }) {
      AcReportsHeader()
      ForEach(AcReportList.groups.indices, id: \.self) { index in
        groupCard(index)
      }
    }
  }

  private func groupCard(_ index: Int) -> some View {
    let group = AcReportList.groups[index]
    return ListCard {
      Text(t(group.title).uppercased())
        .font(.web(12, .semibold))
        .tracking(0.3)
        .foregroundStyle(palette.slate(500))
    } rows: {
      ForEach(group.items.indices, id: \.self) { item in
        ListRow(title: t(group.items[item].label)) {
          IconView(.chevronRight, size: 16).foregroundStyle(palette.slate(400))
        } action: {
          router.push(.report(group.items[item].id))
        }
      }
    }
  }
}

/// The reports' header: title, description and the year-end close.
struct AcReportsHeader: View {
  @Environment(ShellRouter.self) private var router

  var body: some View {
    PageHeader(t("Reports"), description: t("Financial statements, sales, purchases and stock, from your own books.")) {
      WebButton(t("Year-end close"), icon: .calendarCheck, variant: .outline) { router.push(.yearEnd) }
    }
    .padding(.bottom, -16)
  }
}

/// `/reports/:report`: the report chosen from a select, as on a phone.
struct AcReportPage: View {
  @State private var current: String
  private let params: [String: String]
  @Environment(AppModel.self) private var model

  init(name: String) {
    let parsed = AcReportList.parse(name)
    _current = State(initialValue: AcReportList.ids.contains(parsed.id) ? parsed.id : "profit-and-loss")
    params = parsed.params
  }

  var body: some View {
    WebPage(spacing: 16, refresh: { [model] in await model.one.sync() }) {
      AcReportsHeader()
      Select(selection: $current, options: options)
      AcReportContent(id: current, params: params).id(current)
    }
  }

  private var options: [SelectOption<String>] {
    var out: [SelectOption<String>] = []
    for group in AcReportList.groups {
      for item in group.items { out.append(SelectOption(item.id, t(item.label))) }
    }
    return out
  }
}

/// The report itself.
struct AcReportContent: View {
  let id: String
  let params: [String: String]

  var body: some View {
    if let statement = AcStatementId(rawValue: id) {
      AcPayrollNote()
      AcStatementReport(id: statement)
    } else if id == "general-ledger" {
      AcPayrollNote()
      AcGeneralLedgerReport(params: params)
    } else if id == "auditor-pack" {
      AcPayrollNote()
      AcAuditorPack()
    } else if ["aging", "tax", "sales", "payments", "payables", "purchases", "payments-made"].contains(id) {
      AcSalesReport(report: id)
    } else if ["statements", "exposure", "retentions"].contains(id) {
      AcReceivablesReport(report: id)
    } else {
      AcInventoryReport(report: id, params: params)
    }
  }
}

// MARK: Statements

/// The IFRS statements, the trial balance and the fixed asset schedule
/// (`StatementReport`): the period, the comparative and the accounts.
struct AcStatementReport: View {
  let id: AcStatementId
  @Environment(AppModel.self) private var model
  @State private var preset = "this-year"
  @State private var custom = AcDate.presetRange("this-quarter", AcDate.today)
  @State private var asOfPreset = "today"
  @State private var asOfCustom = AcDate.today
  @State private var compare = true
  @State private var detail = false

  var body: some View {
    let one = model.one
    let books = one.acBooks
    let range = AcFiscal.periodRange(preset, books.fiscalYearEnd, custom: custom, today: AcDate.today)
    let asOf = AcFiscal.asOfDate(asOfPreset, books.fiscalYearEnd, custom: asOfCustom, today: AcDate.today)
    let report = AcReportModels.build(
      id, books: books, assets: one.records(.assets), runs: one.records(.depreciationRuns), range: range, asOf: asOf,
      compare: compare && id.comparable, detail: detail || !id.detailed)
    Card {
      AcToolbar {
        if id.asOf {
          AcAsOfPicker(preset: $asOfPreset, custom: $asOfCustom)
        } else {
          AcRangePicker(preset: $preset, custom: $custom, options: AcPeriods.statement)
        }
        if id.comparable { Switch(t("Compare with last year"), isOn: $compare) }
        if id.detailed { Switch(t("Show accounts"), isOn: $detail) }
        statusBadge(report)
      }
      AcProblemsNotice(problems: books.problems)
      AcReportDocumentView(report: report, linkRange: linkRange(range, asOf, books))
      if id == .assetSchedule, report.rows.count <= 1 {
        AcAssetScheduleEmpty()
      }
      Color.clear.frame(height: 16)
    }
  }

  private func linkRange(_ range: AcRange, _ asOf: String, _ books: AcBooks) -> AcRange {
    guard id.asOf else { return range }
    return AcRange(
      from: id == .trialBalance ? AcFiscal.start(asOf, books.fiscalYearEnd) : "0000-01-01", to: asOf)
  }

  @ViewBuilder
  private func statusBadge(_ report: AcReportModel) -> some View {
    let format = model.one.format
    switch id {
    case .balanceSheet:
      let difference = report.value("total-assets") - report.value("total-equity-and-liabilities")
      if difference == 0 {
        Badge(t("Balanced"), tone: .green)
      } else {
        Badge(t("Out of balance by {amount}", ["amount": format.acFigure(difference, ledger: true)]), tone: .red)
      }
    case .cashFlow:
      let difference =
        report.value("operating-total") + report.value("investing-total") + report.value("financing-total")
        - report.value("net-change")
      if difference == 0 {
        Badge(t("Agrees with cash and bank"), tone: .green)
      } else {
        Badge(t("Does not agree with cash and bank"), tone: .red)
      }
    case .trialBalance:
      let totals = report.rows.last?.values ?? []
      if totals.count == 2, totals[0] == totals[1] { Badge(t("Balanced"), tone: .green) }
    default:
      EmptyView()
    }
  }
}

/// "No fixed assets in this period." with the link to the register.
struct AcAssetScheduleEmpty: View {
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(spacing: 6) {
      Text(t("No fixed assets in this period.")).font(.web(14)).foregroundStyle(palette.slate(500))
      Button {
        Haptics.play(.tap)
        router.push(.assets)
      } label: {
        Text(t("Open the fixed asset register")).font(.web(14, .medium)).foregroundStyle(palette.primary(700))
      }
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 20)
    .padding(.vertical, 24)
  }
}

/// "Some transactions need attention", with the first eight problems.
struct AcProblemsNotice: View {
  let problems: [AcProblem]
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    if !problems.isEmpty {
      let shape = RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          IconView(.triangleAlert, size: 16)
          Text(t("Some transactions need attention")).font(.web(14, .medium))
        }
        ForEach(problems.prefix(8).indices, id: \.self) { index in
          problemRow(problems[index])
        }
      }
      .foregroundStyle(palette[.amber(900)])
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(palette[.amber(50)], in: shape)
      .border(palette[.amber(200)], in: shape)
      .padding(.horizontal, 20)
      .padding(.top, 16)
    }
  }

  private func problemRow(_ problem: AcProblem) -> some View {
    Button {
      Haptics.play(.tap)
      router.push(AcLinks.source(problem.source, problem.sourceId, one: model.one))
    } label: {
      Text(verbatim: problem.number + ": " + problem.text)
        .font(.web(14))
        .multilineTextAlignment(.leading)
    }
    .buttonStyle(.plain)
  }
}

// MARK: The report document

/// A report laid out as a financial statement (`ReportDocument`): the
/// company, title and period, then the rows; account rows open the ledger.
struct AcReportDocumentView: View {
  let report: AcReportModel
  let linkRange: AcRange?
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  private var wide: Bool { report.columns.count > 3 }
  private var valueWidth: CGFloat { wide ? 100 : report.columns.count == 1 ? 120 : 104 }

  var body: some View {
    let format = model.one.format
    VStack(alignment: .leading, spacing: 0) {
      header(format)
      if wide {
        ScrollView(.horizontal, showsIndicators: true) {
          table(format).frame(width: 200 + CGFloat(report.columns.count) * (valueWidth + 8) + 32)
        }
      } else {
        table(format)
      }
    }
  }

  private func header(_ format: CompanyFormat) -> some View {
    let company = model.one.company
    return VStack(spacing: 2) {
      if let company {
        Text(localName(company)).font(.web(14)).foregroundStyle(palette.slate(500))
      }
      Text(t(report.title)).font(.web(20, .semibold)).foregroundStyle(palette.slate(900))
      Text(AcReportText.subtitle(report.subtitle, format: format)).font(.web(14)).foregroundStyle(palette.slate(600))
      Text(t("Amounts in {currency}", ["currency": AcReportText.currencyName(format.currency)]))
        .font(.web(12))
        .foregroundStyle(palette.slate(500))
        .padding(.top, 4)
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 20)
    .padding(.top, 24)
    .padding(.bottom, 16)
  }

  private func table(_ format: CompanyFormat) -> some View {
    VStack(spacing: 0) {
      HStack(alignment: .bottom, spacing: 8) {
        Spacer(minLength: 0)
        ForEach(report.columns.indices, id: \.self) { index in
          Text(AcReportText.heading(report.columns[index], format: format))
            .multilineTextAlignment(.trailing)
            .frame(width: valueWidth, alignment: .trailing)
        }
      }
      .font(.web(12, .medium))
      .foregroundStyle(palette.slate(500))
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .overlay(alignment: .top) { Rectangle().fill(palette.slate(200)).frame(height: 1) }
      .overlay(alignment: .bottom) { Rectangle().fill(palette.slate(200)).frame(height: 1) }
      ForEach(report.rows) { row in
        AcReportRowView(row: row, report: report, format: format, valueWidth: valueWidth, action: action(row))
      }
    }
  }

  private func action(_ row: AcReportRow) -> (() -> Void)? {
    guard let accountId = row.accountId else { return nil }
    let range = linkRange
    return { router.push(AcLinks.ledger(accountId, range)) }
  }
}

/// One row of a report, styled by its kind.
struct AcReportRowView: View {
  let row: AcReportRow
  let report: AcReportModel
  let format: CompanyFormat
  let valueWidth: CGFloat
  let action: (() -> Void)?
  @Environment(\.palette) private var palette

  var body: some View {
    Group {
      if let action {
        Button {
          Haptics.play(.tap)
          action()
        } label: {
          content.contentShape(Rectangle())
        }
        .buttonStyle(PressedFill(radius: 0, color: .slate(100)))
      } else {
        content
      }
    }
  }

  private var content: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      label
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, row.kind == .detail ? 16 : 0)
      ForEach(report.columns.indices, id: \.self) { index in
        Text(format.acFigure(index < row.values.count ? row.values[index] : nil, ledger: report.isLedger))
          .font(.web(row.kind == .detail ? 13 : 14, weight, tabular: true))
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .frame(width: valueWidth, alignment: .trailing)
          .environment(\.layoutDirection, .leftToRight)
      }
    }
    .foregroundStyle(textColor)
    .padding(.horizontal, 16)
    .padding(.top, topPadding)
    .padding(.bottom, bottomPadding)
    .background(row.kind == .grand ? palette.slate(50) : Color.clear)
    .overlay(alignment: .top) {
      if let border { Rectangle().fill(palette.slate(border)).frame(height: row.kind == .grand ? 2 : 1) }
    }
    .overlay(alignment: .bottom) {
      if row.kind == .grand { Rectangle().fill(palette.slate(300)).frame(height: 2) }
    }
  }

  @ViewBuilder
  private var label: some View {
    if row.kind == .heading {
      Text(AcReportText.label(row, format: format).uppercased())
        .font(.web(12, .semibold))
        .tracking(0.3)
    } else {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        if let code = row.record?.code, !code.isEmpty {
          Text(code).font(.web(row.kind == .detail ? 13 : 14, tabular: true)).foregroundStyle(palette.slate(500))
        }
        Text(AcReportText.label(row, format: format))
          .font(.web(row.kind == .detail ? 13 : 14, weight))
          .multilineTextAlignment(.leading)
      }
    }
  }

  private var weight: FontWeight {
    switch row.kind {
    case .section, .total, .grand: .semibold
    case .subtotal: .medium
    default: .regular
    }
  }

  private var textColor: Color {
    switch row.kind {
    case .heading: palette.slate(500)
    case .detail: palette.slate(600)
    case .caption: palette.slate(800)
    default: palette.slate(900)
    }
  }

  private var border: Int? {
    switch row.kind {
    case .subtotal: 200
    case .total, .grand: 300
    default: nil
    }
  }

  private var topPadding: CGFloat {
    switch row.kind {
    case .heading: 24
    case .section: 16
    case .detail: 4
    case .caption: 6
    case .grand: 10
    default: 8
    }
  }

  private var bottomPadding: CGFloat {
    switch row.kind {
    case .heading, .section, .detail: 4
    case .caption: 6
    case .grand: 10
    default: 8
    }
  }
}

/// A report's words in the interface language (`rowLabel`, `columnHeading`, `subtitleText`).
@MainActor
enum AcReportText {
  static func label(_ row: AcReportRow, format: CompanyFormat) -> String {
    if let record = row.record, row.label == nil { return name(record) }
    guard let label = row.label else { return "" }
    var vars = row.vars
    for (key, value) in vars where ISODates.isISODate(value) { vars[key] = format.date(value) }
    if let record = row.record, vars["name"] != nil { vars["name"] = name(record) }
    return t(label, vars)
  }

  static func name(_ record: AcRecordName) -> String {
    if LanguageStore.shared.isArabic, let arabic = record.nameAr, !arabic.trimmingCharacters(in: .whitespaces).isEmpty {
      return arabic
    }
    return record.name
  }

  static func heading(_ column: AcReportColumn, format: CompanyFormat) -> String {
    switch column {
    case .date(let date): format.date(date)
    case .period(let range, let year):
      year ? AcFiscal.label(range.from, range.to) : "\(format.date(range.from)) – \(format.date(range.to))"
    case .label(let label): t(label)
    }
  }

  static func subtitle(_ subtitle: AcReportSubtitle, format: CompanyFormat) -> String {
    switch subtitle {
    case .asOf(let date): t("As at {date}", ["date": format.date(date)])
    case .period(let range, let year):
      year
        ? t("For the year ended {date}", ["date": format.date(range.to)])
        : t("For the period from {from} to {to}", ["from": format.date(range.from), "to": format.date(range.to)])
    }
  }

  /// "Kuwaiti Dinar" in the interface language (`Intl.DisplayNames`).
  static func currencyName(_ code: String) -> String {
    let locale = Locale(identifier: LanguageStore.shared.isArabic ? "ar" : "en")
    return locale.localizedString(forCurrencyCode: code) ?? code
  }
}

// MARK: General ledger

/// `GeneralLedgerReport`: every account's movements over a period, or one account's.
struct AcGeneralLedgerReport: View {
  @State private var accountId: String?
  @State private var preset: String
  @State private var custom: AcRange
  @State private var limit = 200
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  init(params: [String: String]) {
    _accountId = State(initialValue: params["account"])
    if let from = params["from"], let to = params["to"] {
      _preset = State(initialValue: "custom")
      _custom = State(initialValue: AcRange(from: from, to: to))
    } else {
      _preset = State(initialValue: "this-year")
      _custom = State(initialValue: AcDate.presetRange("this-quarter", AcDate.today))
    }
  }

  var body: some View {
    let one = model.one
    let books = one.acBooks
    let format = one.format
    let range = AcFiscal.periodRange(preset, books.fiscalYearEnd, custom: custom, today: AcDate.today)
    let shown = range.from == "0000-01-01" ? AcRange(from: firstLineDate(books), to: range.to) : range
    let activity = AcStatements.generalLedger(
      books.lines, books.accounts, shown, books.fiscalYearEnd, accountId: accountId?.isEmpty == false ? accountId : nil)
    Card {
      AcToolbar {
        Combobox(
          selection: $accountId, options: accountOptions(books), placeholder: t("All accounts"),
          searchPlaceholder: t("Search accounts…"))
        AcRangePicker(preset: $preset, custom: $custom, options: AcPeriods.statement)
      }
      AcProblemsNotice(problems: books.problems)
      VStack(spacing: 2) {
        Text(t("General ledger")).font(.web(20, .semibold)).foregroundStyle(palette.slate(900))
        Text(t("For the period from {from} to {to}", ["from": format.date(shown.from), "to": format.date(shown.to)]))
          .font(.web(14))
          .foregroundStyle(palette.slate(500))
      }
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 20)
      .padding(.top, 24)
      .padding(.bottom, 12)
      if activity.isEmpty {
        AcCardText(t("No transactions in this period."), centered: true)
      } else {
        let blocks = visible(activity)
        let left = remaining(activity, blocks)
        ForEach(blocks.indices, id: \.self) { index in
          accountBlock(blocks[index], format: format)
        }
        if left > 0 {
          ListShowMore(remaining: left) { limit += 200 }
        }
      }
      Color.clear.frame(height: 8)
    }
  }

  private func accountOptions(_ books: AcBooks) -> [ComboOption] {
    var options = [ComboOption(value: "", label: t("All accounts"))]
    for account in AcSort.sortedByCode(books.accounts) {
      options.append(
        ComboOption(
          value: account.id, label: "\(account.code) \(localName(account.raw))",
          keywords: "\(account.name) \(account.nameAr ?? "")"))
    }
    return options
  }

  /// "From the beginning": the start of the month of the first line.
  private func firstLineDate(_ books: AcBooks) -> String {
    guard let first = books.lines.first?.date else { return AcDate.today }
    return String(first.prefix(8)) + "01"
  }

  /// The accounts shown, cut to `limit` lines in all.
  private func visible(_ activity: [AcAccountActivity]) -> [(activity: AcAccountActivity, count: Int)] {
    var left = limit
    var out: [(activity: AcAccountActivity, count: Int)] = []
    for item in activity {
      if left <= 0 { break }
      let count = min(left, item.lines.count)
      out.append((item, count))
      left -= max(count, 1)
    }
    return out
  }

  private func remaining(
    _ activity: [AcAccountActivity], _ blocks: [(activity: AcAccountActivity, count: Int)]
  ) -> Int {
    // An account with only an opening balance counts as one line.
    let total = activity.reduce(0) { $0 + max($1.lines.count, 1) }
    let shown = blocks.reduce(0) { $0 + max($1.count, 1) }
    return max(0, total - shown)
  }

  @ViewBuilder
  private func accountBlock(_ item: (activity: AcAccountActivity, count: Int), format: CompanyFormat) -> some View {
    let activity = item.activity
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(activity.account.code).font(.web(14, tabular: true)).foregroundStyle(palette.slate(500))
      Text(localName(activity.account.raw)).font(.web(14, .semibold)).foregroundStyle(palette.slate(900))
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(format.acMoney(activity.opening))
        .font(.web(14, tabular: true))
        .foregroundStyle(palette.slate(500))
        .environment(\.layoutDirection, .leftToRight)
    }
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 6)
    .background(palette.slate(50).opacity(0.4))
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(200)).frame(height: 1) }
    ForEach(0..<item.count, id: \.self) { index in
      lineRow(activity.lines[index].line, balance: activity.lines[index].balance, format: format)
    }
    if item.count == activity.lines.count {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(t("Closing balance")).font(.web(14, .medium))
          .frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .trailing, spacing: 2) {
          Text(format.acMoney(activity.closing)).font(.web(14, .semibold, tabular: true))
          Text("\(t("Debit")) \(format.acMoney(activity.debit)) · \(t("Credit")) \(format.acMoney(activity.credit))")
            .font(.web(12, tabular: true))
            .foregroundStyle(palette.slate(500))
        }
        .environment(\.layoutDirection, .leftToRight)
      }
      .foregroundStyle(palette.slate(900))
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
    }
  }

  private func lineRow(_ line: AcLine, balance: Int, format: CompanyFormat) -> some View {
    AcTapRow(action: { router.push(AcLinks.source(line.source, line.sourceId, one: model.one)) }) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(line.number).font(.web(14, .medium)).foregroundStyle(palette.primary(700))
            Text(format.date(line.date)).font(.web(12)).foregroundStyle(palette.slate(500))
          }
          Text(line.text).font(.web(13)).foregroundStyle(palette.slate(700)).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .trailing, spacing: 2) {
          Text(format.acMoney(abs(line.amount)))
            .font(.web(14, tabular: true))
            .foregroundStyle(palette.slate(900))
          Text("\(line.amount > 0 ? t("Debit") : t("Credit")) · \(format.acMoney(balance))")
            .font(.web(12, tabular: true))
            .foregroundStyle(palette.slate(500))
        }
        .environment(\.layoutDirection, .leftToRight)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
    }
  }
}
