import Foundation
import MahamKit

// Reports as data (`src/apps/books/features/reports/model.ts`): rows of
// captions, accounts and totals with an amount per column, shown the way the
// web lays out a financial statement.

enum AcRowKind: Sendable {
  case heading, section, caption, detail, subtotal, total, grand
}

/// A record behind a row: its code and names.
struct AcRecordName: Sendable {
  var code: String?
  var name: String
  var nameAr: String?
}

struct AcReportRow: Sendable, Identifiable {
  let key: String
  let kind: AcRowKind
  /// English text, translated when shown; unused when `record` is set alone.
  var label: String?
  var vars: [String: String] = [:]
  var record: AcRecordName?
  /// Account behind the row, for links to the general ledger.
  var accountId: String?
  /// Minor units per column; nil leaves the cell empty.
  var values: [Int?]

  var id: String { key }
}

enum AcReportColumn: Sendable {
  case date(String)
  case period(AcRange, year: Bool)
  case label(String)
}

enum AcReportSubtitle: Sendable {
  case asOf(String)
  case period(AcRange, year: Bool)
}

struct AcReportModel: Sendable {
  let file: String
  let title: String
  let subtitle: AcReportSubtitle
  let columns: [AcReportColumn]
  let rows: [AcReportRow]
  /// Statements: brackets for negatives and a dash for nothing; ledgers: blank cells.
  let isLedger: Bool

  /// Figure of the row with `key` in the first column (`valueOf`).
  func value(_ key: String) -> Int {
    rows.first { $0.key == key }?.values.first.flatMap { $0 } ?? 0
  }
}

/// The statement reports (`StatementId`).
enum AcStatementId: String, CaseIterable, Sendable {
  case balanceSheet = "balance-sheet"
  case profitAndLoss = "profit-and-loss"
  case changesInEquity = "changes-in-equity"
  case cashFlow = "cash-flow"
  case trialBalance = "trial-balance"
  case assetSchedule = "asset-schedule"

  /// Balance sheet and trial balance are as at a date.
  var asOf: Bool { self == .balanceSheet || self == .trialBalance }
  var comparable: Bool { [.balanceSheet, .profitAndLoss, .changesInEquity, .cashFlow].contains(self) }
  var detailed: Bool { self == .balanceSheet || self == .profitAndLoss }
}

enum AcReportModels {
  private static func record(_ account: AcAccount) -> AcRecordName {
    AcRecordName(code: account.code, name: account.name, nameAr: account.nameAr)
  }

  private static func nonZero(_ values: [Int?]) -> Bool {
    values.contains { ($0 ?? 0) != 0 }
  }

  private static func pair(_ current: Int, _ previous: Int?, _ compare: Bool) -> [Int?] {
    compare ? [current, previous ?? 0] : [current]
  }

  /// `captionRows`: caption rows for both columns, with accounts under them when `detail`.
  static func captionRows(
    _ current: [AcCaption], _ previous: [AcCaption]?, detail: Bool, keep: [String] = []
  ) -> [AcReportRow] {
    var rows: [AcReportRow] = []
    for caption in current {
      let before = previous?.first { $0.key == caption.key }
      let values: [Int?] = previous != nil ? [caption.total, before?.total ?? 0] : [caption.total]
      var accountOrder: [String] = []
      var accounts: [String: AcAccount] = [:]
      for row in caption.rows + (before?.rows ?? []) where accounts[row.account.id] == nil {
        accountOrder.append(row.account.id)
        accounts[row.account.id] = row.account
      }
      var extraOrder: [String] = []
      var extras: [String: String] = [:]
      for extra in caption.extras + (before?.extras ?? []) where extras[extra.key] == nil {
        extraOrder.append(extra.key)
        extras[extra.key] = extra.label
      }
      if !nonZero(values), accounts.isEmpty, extras.isEmpty, !keep.contains(caption.key) { continue }
      rows.append(AcReportRow(key: caption.key, kind: .caption, label: caption.label, values: values))
      if !detail { continue }
      for account in AcSort.sortedByCode(accountOrder.compactMap { accounts[$0] }) {
        func amount(_ c: AcCaption?) -> Int { c?.rows.first { $0.account.id == account.id }?.amount ?? 0 }
        rows.append(
          AcReportRow(
            key: "\(caption.key):\(account.id)", kind: .detail, record: record(account), accountId: account.id,
            values: previous != nil ? [amount(caption), amount(before)] : [amount(caption)]))
      }
      for key in extraOrder {
        func amount(_ c: AcCaption?) -> Int { c?.extras.first { $0.key == key }?.amount ?? 0 }
        rows.append(
          AcReportRow(
            key: "\(caption.key):\(key)", kind: .detail, label: extras[key],
            values: previous != nil ? [amount(caption), amount(before)] : [amount(caption)]))
      }
    }
    return rows
  }

  // MARK: Statement of financial position

  static func financialPosition(
    _ current: AcFinancialPosition, _ previous: AcFinancialPosition?, detail: Bool
  ) -> AcReportModel {
    let compare = previous != nil
    func v(_ pick: (AcFinancialPosition) -> Int) -> [Int?] {
      pair(pick(current), previous.map(pick), compare)
    }
    func section(
      _ key: String, _ label: String, _ captions: (AcFinancialPosition) -> [AcCaption],
      _ total: (AcFinancialPosition) -> Int, _ totalLabel: String, always: Bool = false
    ) -> [AcReportRow] {
      let body = captionRows(captions(current), previous.map(captions), detail: detail)
      if body.isEmpty, !always { return [] }
      return [AcReportRow(key: key, kind: .section, label: label, values: [])] + body + [
        AcReportRow(key: "\(key)-total", kind: .subtotal, label: totalLabel, values: v(total))
      ]
    }
    var rows: [AcReportRow] = [AcReportRow(key: "assets", kind: .heading, label: "Assets", values: [])]
    rows += section(
      "non-current-assets", "Non-current assets", { $0.nonCurrentAssets }, { $0.totalNonCurrentAssets },
      "Total non-current assets")
    rows += section(
      "current-assets", "Current assets", { $0.currentAssets }, { $0.totalCurrentAssets }, "Total current assets",
      always: true)
    rows.append(AcReportRow(key: "total-assets", kind: .grand, label: "Total assets", values: v { $0.totalAssets }))
    rows.append(
      AcReportRow(key: "equity-and-liabilities", kind: .heading, label: "Equity and liabilities", values: []))
    rows += section("equity", "Equity", { $0.equity }, { $0.totalEquity }, "Total equity", always: true)
    rows += section(
      "non-current-liabilities", "Non-current liabilities", { $0.nonCurrentLiabilities },
      { $0.totalNonCurrentLiabilities }, "Total non-current liabilities")
    rows += section(
      "current-liabilities", "Current liabilities", { $0.currentLiabilities }, { $0.totalCurrentLiabilities },
      "Total current liabilities", always: true)
    rows.append(
      AcReportRow(key: "total-liabilities", kind: .total, label: "Total liabilities", values: v { $0.totalLiabilities }))
    rows.append(
      AcReportRow(
        key: "total-equity-and-liabilities", kind: .grand, label: "Total equity and liabilities",
        values: v { $0.totalEquity + $0.totalLiabilities }))
    var columns: [AcReportColumn] = [.date(current.asOf)]
    if let previous { columns.append(.date(previous.asOf)) }
    return AcReportModel(
      file: "statement-of-financial-position", title: "Statement of financial position",
      subtitle: .asOf(current.asOf), columns: columns, rows: rows, isLedger: false)
  }

  // MARK: Statement of profit or loss

  static func profitOrLoss(
    _ current: AcProfitOrLoss, _ previous: AcProfitOrLoss?, detail: Bool, yearEnd: AcFiscalEnd
  ) -> AcReportModel {
    let compare = previous != nil
    let year = AcFiscal.isFinancialYear(current.range, yearEnd)
    func v(_ pick: (AcProfitOrLoss) -> Int) -> [Int?] { pair(pick(current), previous.map(pick), compare) }
    func captions(_ keys: [String], always: [String] = []) -> [AcReportRow] {
      captionRows(
        keys.compactMap { current.caption($0) }, previous.map { p in keys.compactMap { p.caption($0) } },
        detail: detail, keep: always)
    }
    // Each levy has its own line, as in Kuwaiti financial statements.
    var levyOrder: [String] = []
    var levyAccounts: [String: AcAccount] = [:]
    for row in current.levies.rows + (previous?.levies.rows ?? []) where levyAccounts[row.account.id] == nil {
      levyOrder.append(row.account.id)
      levyAccounts[row.account.id] = row.account
    }
    let levyRows = AcSort.sortedByCode(levyOrder.compactMap { levyAccounts[$0] }).map { account in
      AcReportRow(
        key: "levy:\(account.id)", kind: .caption, record: AcRecordName(name: account.name, nameAr: account.nameAr),
        accountId: account.id,
        values: pair(
          current.levies.rows.first { $0.account.id == account.id }?.amount ?? 0,
          previous?.levies.rows.first { $0.account.id == account.id }?.amount ?? 0, compare))
    }
    let loss = current.profit < 0
    let profitLabel =
      year ? (loss ? "Loss for the year" : "Profit for the year") : (loss ? "Loss for the period" : "Profit for the period")
    var rows = captions(["revenue", "cost-of-sales"], always: ["revenue"])
    rows.append(AcReportRow(key: "gross-profit", kind: .subtotal, label: "Gross profit", values: v { $0.grossProfit }))
    rows += captions(
      ["other-income", "administrative", "depreciation", "other-expenses", "finance-costs"], always: ["administrative"])
    rows.append(
      AcReportRow(
        key: "profit-before-levies", kind: .subtotal, label: "Profit before KFAS, Zakat, NLST and income tax",
        values: v { $0.profitBeforeLevies }))
    rows += levyRows
    rows.append(AcReportRow(key: "profit", kind: .grand, label: profitLabel, values: v { $0.profit }))
    var columns: [AcReportColumn] = [.period(current.range, year: year)]
    if let previous { columns.append(.period(previous.range, year: year)) }
    return AcReportModel(
      file: "statement-of-profit-or-loss", title: "Statement of profit or loss",
      subtitle: .period(current.range, year: year), columns: columns, rows: rows, isLedger: false)
  }

  // MARK: Statement of changes in equity

  static func changesInEquity(
    _ current: AcChangesInEquity, _ previous: AcChangesInEquity?, yearEnd: AcFiscalEnd
  ) -> AcReportModel {
    let shown = Set(current.components + (previous?.components ?? []))
    let components = AcEquity.allCases.filter { shown.contains($0) }
    func values(_ vals: AcEquityValues) -> [Int?] {
      components.map { vals[$0] ?? 0 } + [AcStatements.equityTotal(vals)]
    }
    func block(_ soce: AcChangesInEquity, _ prefix: String, opening: Bool) -> [AcReportRow] {
      var rows: [AcReportRow] = []
      if opening {
        rows.append(
          AcReportRow(
            key: "\(prefix)-opening", kind: .subtotal, label: "Balance at {date}",
            vars: ["date": AcDate.addDays(soce.range.from, -1)], values: values(soce.opening)))
      }
      for movement in soce.movements {
        rows.append(
          AcReportRow(
            key: "\(prefix)-\(movement.key)", kind: .caption, label: movement.label, values: values(movement.values)))
      }
      rows.append(
        AcReportRow(
          key: "\(prefix)-closing", kind: .total, label: "Balance at {date}", vars: ["date": soce.range.to],
          values: values(soce.closing)))
      return rows
    }
    var rows: [AcReportRow] = []
    if let previous { rows += block(previous, "previous", opening: true) }
    rows += block(current, "current", opening: previous == nil)
    return AcReportModel(
      file: "statement-of-changes-in-equity", title: "Statement of changes in equity",
      subtitle: .period(current.range, year: AcFiscal.isFinancialYear(current.range, yearEnd)),
      columns: components.map { AcReportColumn.label($0.label) } + [AcReportColumn.label("Total")], rows: rows, isLedger: false)
  }

  // MARK: Statement of cash flows

  static func cashFlow(_ current: AcCashFlow, _ previous: AcCashFlow?, yearEnd: AcFiscalEnd) -> AcReportModel {
    let compare = previous != nil
    let year = AcFiscal.isFinancialYear(current.range, yearEnd)
    func v(_ pick: (AcCashFlow) -> Int) -> [Int?] { pair(pick(current), previous.map(pick), compare) }
    func lines(_ pick: (AcCashFlow) -> [AcCashFlowLine], _ kind: AcRowKind = .caption) -> [AcReportRow] {
      pick(current).map { line in
        AcReportRow(
          key: line.key, kind: kind, label: line.label,
          values: pair(line.amount, previous.flatMap { p in pick(p).first { $0.key == line.key }?.amount }, compare))
      }.filter { nonZero($0.values) }
    }
    let adjustments = lines({ $0.adjustments }, .detail)
    let working = lines({ $0.workingCapital }, .detail)
    var rows: [AcReportRow] = [
      AcReportRow(key: "operating", kind: .section, label: "Operating activities", values: []),
      AcReportRow(
        key: "profit", kind: .caption, label: year ? "Profit for the year" : "Profit for the period",
        values: v { $0.profit }),
    ]
    if !adjustments.isEmpty {
      rows.append(AcReportRow(key: "adjustments", kind: .caption, label: "Adjustments for:", values: []))
      rows += adjustments
    }
    if !working.isEmpty {
      rows.append(AcReportRow(key: "working-capital", kind: .caption, label: "Changes in working capital:", values: []))
      rows += working
    }
    rows.append(
      AcReportRow(
        key: "operating-total", kind: .subtotal, label: "Net cash from operating activities", values: v { $0.operating }))
    rows.append(AcReportRow(key: "investing", kind: .section, label: "Investing activities", values: []))
    rows += lines { $0.investing }
    rows.append(
      AcReportRow(
        key: "investing-total", kind: .subtotal, label: "Net cash from investing activities",
        values: v { $0.investingTotal }))
    rows.append(AcReportRow(key: "financing", kind: .section, label: "Financing activities", values: []))
    rows += lines { $0.financing }
    rows.append(
      AcReportRow(
        key: "financing-total", kind: .subtotal, label: "Net cash from financing activities",
        values: v { $0.financingTotal }))
    rows.append(
      AcReportRow(
        key: "net-change", kind: .total, label: "Net increase (decrease) in cash and bank balances",
        values: v { $0.netChange }))
    rows.append(
      AcReportRow(
        key: "opening-cash", kind: .caption, label: "Cash and bank balances at the start of the period",
        values: v { $0.opening }))
    rows.append(
      AcReportRow(
        key: "closing-cash", kind: .grand, label: "Cash and bank balances at the end of the period",
        values: v { $0.closing }))
    var columns: [AcReportColumn] = [.period(current.range, year: year)]
    if let previous { columns.append(.period(previous.range, year: year)) }
    return AcReportModel(
      file: "statement-of-cash-flows", title: "Statement of cash flows", subtitle: .period(current.range, year: year),
      columns: columns, rows: rows, isLedger: false)
  }

  // MARK: Trial balance

  static func trialBalance(_ books: AcBooks, asOf: String) -> AcReportModel {
    let tb = AcStatements.trialBalance(books.lines, books.accounts, asOf, books.fiscalYearEnd)
    var rows: [AcReportRow] = tb.rows.map { row in
      if let account = row.account {
        return AcReportRow(
          key: account.id, kind: .caption, record: record(account), accountId: account.id,
          values: [row.debit == 0 ? nil : row.debit, row.credit == 0 ? nil : row.credit])
      }
      return AcReportRow(
        key: "earlier", kind: .caption, label: "Profit of earlier years",
        values: [row.debit == 0 ? nil : row.debit, row.credit == 0 ? nil : row.credit])
    }
    rows.append(AcReportRow(key: "total", kind: .grand, label: "Total", values: [tb.totalDebit, tb.totalCredit]))
    return AcReportModel(
      file: "trial-balance", title: "Trial balance", subtitle: .asOf(asOf), columns: [.label("Debit"), .label("Credit")],
      rows: rows, isLedger: true)
  }

  // MARK: Fixed asset schedule

  static func assetSchedule(
    _ assets: [JSONValue], _ runs: [JSONValue], _ books: AcBooks, range: AcRange
  ) -> AcReportModel {
    let schedule = AcAssetSchedule.build(assets, runs, books, range)
    var rows: [AcReportRow] = []
    for group in schedule.groups {
      rows.append(
        AcReportRow(
          key: group.accountId, kind: .section,
          record: group.account.map { record($0) } ?? AcRecordName(name: "—"), values: []))
      for row in group.rows {
        rows.append(
          AcReportRow(
            key: row.asset.rid, kind: .detail,
            record: AcRecordName(code: row.asset.str("number"), name: row.asset.str("name"), nameAr: row.asset.text("nameAr")),
            values: row.figures.columns.map { Optional($0) }))
      }
      rows.append(
        AcReportRow(
          key: "\(group.accountId)-total", kind: .subtotal, label: "Total {name}",
          vars: ["name": group.account?.name ?? ""],
          record: group.account.map { AcRecordName(name: $0.name, nameAr: $0.nameAr) },
          values: group.totals.columns.map { Optional($0) }))
    }
    rows.append(
      AcReportRow(key: "total", kind: .grand, label: "Total", values: schedule.totals.columns.map { Optional($0) }))
    return AcReportModel(
      file: "fixed-asset-schedule", title: "Fixed asset schedule",
      subtitle: .period(range, year: AcFiscal.isFinancialYear(range, books.fiscalYearEnd)),
      columns: AcScheduleFigures.labels.map { AcReportColumn.label($0) }, rows: rows, isLedger: false)
  }

  // MARK: Building a statement

  /// `buildStatement`.
  static func build(
    _ id: AcStatementId, books: AcBooks, assets: [JSONValue], runs: [JSONValue], range: AcRange, asOf: String,
    compare: Bool, detail: Bool
  ) -> AcReportModel {
    let special = AcSpecial(books.accounts, template: books.settings.template)
    let yearEnd = books.fiscalYearEnd
    let previousRange = AcFiscal.previousYear(range)
    let lines = books.lines
    let accounts = books.accounts
    switch id {
    case .balanceSheet:
      let current = AcStatements.financialPosition(lines, accounts, asOf, yearEnd, special)
      let previous =
        compare
        ? AcStatements.financialPosition(lines, accounts, AcFiscal.comparativeDate(asOf, yearEnd), yearEnd, special)
        : nil
      return financialPosition(current, previous, detail: detail)
    case .profitAndLoss:
      let current = AcStatements.profitOrLoss(lines, accounts, range, special)
      let previous = compare ? AcStatements.profitOrLoss(lines, accounts, previousRange, special) : nil
      return profitOrLoss(current, previous, detail: detail, yearEnd: yearEnd)
    case .changesInEquity:
      let current = AcStatements.changesInEquity(lines, accounts, range, special, books.yearEndJournals)
      let previous =
        compare ? AcStatements.changesInEquity(lines, accounts, previousRange, special, books.yearEndJournals) : nil
      return changesInEquity(current, previous, yearEnd: yearEnd)
    case .cashFlow:
      let kinds = books.journalKinds
      let current = AcStatements.cashFlow(lines, accounts, range, special, kinds)
      let previous = compare ? AcStatements.cashFlow(lines, accounts, previousRange, special, kinds) : nil
      return cashFlow(current, previous, yearEnd: yearEnd)
    case .trialBalance:
      return trialBalance(books, asOf: asOf)
    case .assetSchedule:
      return assetSchedule(assets, runs, books, range: range)
    }
  }
}
