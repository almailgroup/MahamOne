import Foundation
import MahamKit

// The statements from the ledger (`src/lib/accounting/statements.ts`,
// `cash-flow.ts`): balances, the IFRS statement of profit or loss and of
// financial position, changes in equity, the trial balance, the general
// ledger and the statement of cash flows. Amounts are minor units.

/// An account and its amount, signed so the section's normal side is positive.
struct AcAmountRow: Sendable {
  let account: AcAccount
  let amount: Int
}

/// An amount not tied to one account (profit not yet moved to retained earnings).
struct AcExtra: Sendable {
  let key: String
  let label: String
  let amount: Int
}

/// A line of a statement: the accounts behind it and the amount shown (`Caption`).
struct AcCaption: Sendable {
  let key: String
  /// English text, translated where it is shown.
  let label: String
  let rows: [AcAmountRow]
  let extras: [AcExtra]
  let total: Int
}

/// Accounts the IFRS statements present on their own lines (`SpecialAccounts`).
struct AcSpecial: Sendable {
  var levies: [String: String] = [:]
  var financeCosts: Set<String> = []
  var statutoryReserve: String?
  var voluntaryReserve: String?
  var endOfService: Set<String> = []

  /// `specialAccounts`.
  init(_ accounts: [AcAccount], template: String) {
    for (spec, kind) in [
      (AcSpec.kfas, "kfas"), (AcSpec.zakat, "zakat"), (AcSpec.nlst, "nlst"), (AcSpec.incomeTax, "income_tax"),
    ] {
      if let account = spec.find(accounts, template: template) { levies[account.id] = kind }
    }
    if let finance = AcSpec.financeCosts.find(accounts, template: template) { financeCosts.insert(finance.id) }
    for account in accounts
    where account.type == "expense_other" && account.role == nil && levies[account.id] == nil
      && AcSpec.financeCosts.matches(account.name)
    {
      financeCosts.insert(account.id)
    }
    let eos = AcSpec.endOfService
    for account in accounts where account.type == eos.type && (eos.matches(account.name) || account.nameAr == eos.nameAr) {
      endOfService.insert(account.id)
    }
    if let found = eos.find(accounts, template: template) { endOfService.insert(found.id) }
    statutoryReserve = AcSpec.statutoryReserve.find(accounts, template: template)?.id
    voluntaryReserve = AcSpec.voluntaryReserve.find(accounts, template: template)?.id
  }
}

/// The equity column an equity account belongs to (`EquityComponent`).
enum AcEquity: String, CaseIterable, Sendable {
  case capital, statutory, voluntary, partners, other, retained

  /// `EQUITY_LABELS`.
  var label: String {
    switch self {
    case .capital: "Share capital"
    case .statutory: "Statutory reserve"
    case .voluntary: "Voluntary reserve"
    case .partners: "Partners’ current accounts"
    case .other: "Other equity"
    case .retained: "Retained earnings"
    }
  }

  static func of(_ account: AcAccount, _ special: AcSpecial) -> AcEquity {
    if account.role == "capital" { return .capital }
    if account.role == "retained_earnings" { return .retained }
    if account.role == "drawings" { return .partners }
    if account.id == special.statutoryReserve { return .statutory }
    if account.id == special.voluntaryReserve { return .voluntary }
    return .other
  }
}

struct AcProfitOrLoss: Sendable {
  let range: AcRange
  let revenue: AcCaption
  let costOfSales: AcCaption
  let grossProfit: Int
  let otherIncome: AcCaption
  let administrative: AcCaption
  let depreciation: AcCaption
  let otherExpenses: AcCaption
  let financeCosts: AcCaption
  let profitBeforeLevies: Int
  let levies: AcCaption
  let profit: Int

  func caption(_ key: String) -> AcCaption? {
    [revenue, costOfSales, otherIncome, administrative, depreciation, otherExpenses, financeCosts, levies].first {
      $0.key == key
    }
  }
}

struct AcFinancialPosition: Sendable {
  let asOf: String
  let nonCurrentAssets: [AcCaption]
  let totalNonCurrentAssets: Int
  let currentAssets: [AcCaption]
  let totalCurrentAssets: Int
  let totalAssets: Int
  let equity: [AcCaption]
  let totalEquity: Int
  let nonCurrentLiabilities: [AcCaption]
  let totalNonCurrentLiabilities: Int
  let currentLiabilities: [AcCaption]
  let totalCurrentLiabilities: Int
  let totalLiabilities: Int
  let difference: Int
}

/// One component's figures (`EquityValues`).
typealias AcEquityValues = [AcEquity: Int]

struct AcEquityMovement: Sendable {
  let key: String
  let label: String
  let values: AcEquityValues
}

struct AcChangesInEquity: Sendable {
  let range: AcRange
  let components: [AcEquity]
  let opening: AcEquityValues
  let movements: [AcEquityMovement]
  let closing: AcEquityValues
}

struct AcTrialRow: Sendable {
  let account: AcAccount?
  let debit: Int
  let credit: Int
}

/// One account's movements in a range, with running balances (`LedgerAccountActivity`).
struct AcAccountActivity: Sendable {
  let account: AcAccount
  let opening: Int
  let lines: [(line: AcLine, balance: Int)]
  let debit: Int
  let credit: Int
  let closing: Int
}

struct AcCashFlowLine: Sendable {
  let key: String
  let label: String
  let amount: Int
}

struct AcCashFlow: Sendable {
  let range: AcRange
  let profit: Int
  let adjustments: [AcCashFlowLine]
  let workingCapital: [AcCashFlowLine]
  let operating: Int
  let investing: [AcCashFlowLine]
  let investingTotal: Int
  let financing: [AcCashFlowLine]
  let financingTotal: Int
  let netChange: Int
  let opening: Int
  let closing: Int
  let difference: Int
}

enum AcStatements {
  /// Sum of line amounts per account, for lines matching `include`.
  static func balances(_ lines: [AcLine], _ include: (AcLine) -> Bool) -> [String: Int] {
    var out: [String: Int] = [:]
    for line in lines where include(line) { out[line.accountId, default: 0] += line.amount }
    return out
  }

  static func caption(
    _ key: String, _ label: String, _ accounts: [AcAccount], _ include: (AcAccount) -> Bool, _ amounts: [String: Int],
    _ sign: Int, extras: [AcExtra] = []
  ) -> AcCaption {
    let rows = AcSort.sortedByCode(accounts.filter(include)).compactMap { account -> AcAmountRow? in
      let amount = sign * (amounts[account.id] ?? 0)
      return amount == 0 ? nil : AcAmountRow(account: account, amount: amount)
    }
    let total = rows.reduce(0) { $0 + $1.amount } + extras.reduce(0) { $0 + $1.amount }
    return AcCaption(key: key, label: label, rows: rows, extras: extras.filter { $0.amount != 0 }, total: total)
  }

  static func sum(_ captions: [AcCaption]) -> Int { captions.reduce(0) { $0 + $1.total } }

  /// Net profit of the lines in a date range (`profitBetween`).
  static func profitBetween(_ lines: [AcLine], _ types: [String: String], _ from: String?, _ to: String) -> Int {
    var sum = 0
    for line in lines {
      guard let type = types[line.accountId], AcAccountTypes.isProfitAndLoss(type) else { continue }
      if (from == nil || line.date >= from!) && line.date <= to { sum += line.amount }
    }
    return -sum
  }

  static func types(_ accounts: [AcAccount]) -> [String: String] {
    var out: [String: String] = [:]
    for account in accounts { out[account.id] = account.type }
    return out
  }

  /// `profitOrLoss`: income positive, costs negative, so every subtotal is a plain sum.
  static func profitOrLoss(_ lines: [AcLine], _ accounts: [AcAccount], _ range: AcRange, _ special: AcSpecial)
    -> AcProfitOrLoss
  {
    let amounts = balances(lines) { $0.date >= range.from && $0.date <= range.to }
    func of(_ type: String) -> (AcAccount) -> Bool { { $0.type == type } }
    let revenue = caption("revenue", "Revenue", accounts, of("income"), amounts, -1)
    let costOfSales = caption("cost-of-sales", "Cost of sales", accounts, of("expense_direct_cost"), amounts, -1)
    let otherIncome = caption("other-income", "Other income", accounts, of("income_other"), amounts, -1)
    let administrative = caption(
      "administrative", "General and administrative expenses", accounts, of("expense"), amounts, -1)
    let depreciation = caption(
      "depreciation", "Depreciation and amortisation", accounts, of("expense_depreciation"), amounts, -1)
    let otherExpenses = caption(
      "other-expenses", "Other expenses", accounts,
      { $0.type == "expense_other" && special.levies[$0.id] == nil && !special.financeCosts.contains($0.id) },
      amounts, -1)
    let financeCosts = caption(
      "finance-costs", "Finance costs", accounts,
      { $0.type == "expense_other" && special.financeCosts.contains($0.id) }, amounts, -1)
    let levies = caption(
      "levies", "KFAS, Zakat, NLST and income tax", accounts,
      { AcAccountTypes.isProfitAndLoss($0.type) && special.levies[$0.id] != nil }, amounts, -1)
    let grossProfit = revenue.total + costOfSales.total
    let profitBeforeLevies =
      grossProfit + sum([otherIncome, administrative, depreciation, otherExpenses, financeCosts])
    return AcProfitOrLoss(
      range: range, revenue: revenue, costOfSales: costOfSales, grossProfit: grossProfit, otherIncome: otherIncome,
      administrative: administrative, depreciation: depreciation, otherExpenses: otherExpenses,
      financeCosts: financeCosts, profitBeforeLevies: profitBeforeLevies, levies: levies,
      profit: profitBeforeLevies + levies.total)
  }

  /// `financialPosition` (IAS 1).
  static func financialPosition(
    _ lines: [AcLine], _ accounts: [AcAccount], _ asOf: String, _ yearEnd: AcFiscalEnd, _ special: AcSpecial
  ) -> AcFinancialPosition {
    let amounts = balances(lines) { $0.date <= asOf }
    let types = AcStatements.types(accounts)
    let fyStart = AcFiscal.start(asOf, yearEnd)
    func of(_ type: String) -> (AcAccount) -> Bool { { $0.type == type } }
    let nonCurrentAssets = [
      caption("ppe", "Property and equipment", accounts, of("asset_fixed"), amounts, 1),
      caption(
        "other-non-current-assets", "Intangible and other non-current assets", accounts, of("asset_non_current"),
        amounts, 1),
    ]
    let currentAssets = [
      caption(
        "other-current-assets", "Inventories and other current assets", accounts, of("asset_current"), amounts, 1),
      caption("prepayments", "Prepayments", accounts, of("asset_prepayments"), amounts, 1),
      caption("receivables", "Trade receivables", accounts, of("asset_receivable"), amounts, 1),
      caption("cash", "Cash and bank balances", accounts, of("asset_cash"), amounts, 1),
    ]
    func component(_ key: AcEquity) -> (AcAccount) -> Bool {
      { $0.type == "equity" && AcEquity.of($0, special) == key }
    }
    let currentYear = profitBetween(lines, types, fyStart, asOf)
    let earlier = profitBetween(lines, types, nil, AcDate.addDays(fyStart, -1))
    let equity = [
      caption("capital", AcEquity.capital.label, accounts, component(.capital), amounts, -1),
      caption("statutory", AcEquity.statutory.label, accounts, component(.statutory), amounts, -1),
      caption("voluntary", AcEquity.voluntary.label, accounts, component(.voluntary), amounts, -1),
      caption("partners", AcEquity.partners.label, accounts, component(.partners), amounts, -1),
      caption("other", AcEquity.other.label, accounts, component(.other), amounts, -1),
      caption(
        "retained", AcEquity.retained.label, accounts, component(.retained), amounts, -1,
        extras: [
          AcExtra(key: "earlier", label: "Profit of earlier years", amount: earlier),
          AcExtra(key: "current", label: "Profit for the current year", amount: currentYear),
        ]),
    ]
    let nonCurrentLiabilities = [
      caption(
        "end-of-service", "Provision for end-of-service indemnity", accounts,
        { $0.type == "liability_non_current" && special.endOfService.contains($0.id) }, amounts, -1),
      caption(
        "loans", "Loans and other non-current liabilities", accounts,
        { $0.type == "liability_non_current" && !special.endOfService.contains($0.id) }, amounts, -1),
    ]
    let currentLiabilities = [
      caption("payables", "Trade payables", accounts, of("liability_payable"), amounts, -1),
      caption(
        "other-current-liabilities", "Accruals and other current liabilities", accounts,
        { $0.type == "liability_current" || $0.type == "liability_credit_card" }, amounts, -1),
    ]
    let totalNonCurrentAssets = sum(nonCurrentAssets)
    let totalCurrentAssets = sum(currentAssets)
    let totalEquity = sum(equity)
    let totalNonCurrentLiabilities = sum(nonCurrentLiabilities)
    let totalCurrentLiabilities = sum(currentLiabilities)
    let totalAssets = totalNonCurrentAssets + totalCurrentAssets
    let totalLiabilities = totalNonCurrentLiabilities + totalCurrentLiabilities
    return AcFinancialPosition(
      asOf: asOf, nonCurrentAssets: nonCurrentAssets, totalNonCurrentAssets: totalNonCurrentAssets,
      currentAssets: currentAssets, totalCurrentAssets: totalCurrentAssets, totalAssets: totalAssets, equity: equity,
      totalEquity: totalEquity, nonCurrentLiabilities: nonCurrentLiabilities,
      totalNonCurrentLiabilities: totalNonCurrentLiabilities, currentLiabilities: currentLiabilities,
      totalCurrentLiabilities: totalCurrentLiabilities, totalLiabilities: totalLiabilities,
      difference: totalAssets - totalEquity - totalLiabilities)
  }

  static func zeroEquity() -> AcEquityValues {
    var values: AcEquityValues = [:]
    for key in AcEquity.allCases { values[key] = 0 }
    return values
  }

  /// `changesInEquity`.
  static func changesInEquity(
    _ lines: [AcLine], _ accounts: [AcAccount], _ range: AcRange, _ special: AcSpecial, _ yearEndJournals: Set<String>
  ) -> AcChangesInEquity {
    var byId: [String: AcAccount] = [:]
    for account in accounts { byId[account.id] = account }
    func balanceAt(_ inclusive: (String) -> Bool) -> AcEquityValues {
      var values = zeroEquity()
      for line in lines where inclusive(line.date) {
        guard let account = byId[line.accountId] else { continue }
        if account.type == "equity" {
          values[AcEquity.of(account, special), default: 0] -= line.amount
        } else if AcAccountTypes.isProfitAndLoss(account.type) {
          values[.retained, default: 0] -= line.amount
        }
      }
      return values
    }
    let opening = balanceAt { $0 < range.from }
    let closing = balanceAt { $0 <= range.to }
    var profit = zeroEquity()
    var capital = zeroEquity()
    var partners = zeroEquity()
    var statutory = zeroEquity()
    var voluntary = zeroEquity()
    for line in lines where line.date >= range.from && line.date <= range.to {
      guard let account = byId[line.accountId] else { continue }
      if AcAccountTypes.isProfitAndLoss(account.type) {
        profit[.retained, default: 0] -= line.amount
        continue
      }
      if account.type != "equity" { continue }
      let component = AcEquity.of(account, special)
      let yearEnd = line.source == .journal && yearEndJournals.contains(line.sourceId)
      if yearEnd, component == .statutory {
        statutory[.statutory, default: 0] -= line.amount
        statutory[.retained, default: 0] += line.amount
      } else if yearEnd, component == .voluntary {
        voluntary[.voluntary, default: 0] -= line.amount
        voluntary[.retained, default: 0] += line.amount
      } else if component == .capital {
        capital[.capital, default: 0] -= line.amount
      } else if component == .partners {
        partners[.partners, default: 0] -= line.amount
      }
    }
    var other = zeroEquity()
    for key in AcEquity.allCases {
      let moved = (profit[key] ?? 0) + (capital[key] ?? 0) + (partners[key] ?? 0) + (statutory[key] ?? 0)
        + (voluntary[key] ?? 0)
      other[key] = (closing[key] ?? 0) - (opening[key] ?? 0) - moved
    }
    let all = [
      AcEquityMovement(key: "profit", label: "Profit for the period", values: profit),
      AcEquityMovement(key: "statutory", label: "Transfer to statutory reserve", values: statutory),
      AcEquityMovement(key: "voluntary", label: "Transfer to voluntary reserve", values: voluntary),
      AcEquityMovement(key: "capital", label: "Capital introduced or withdrawn", values: capital),
      AcEquityMovement(key: "partners", label: "Partners’ drawings and contributions", values: partners),
      AcEquityMovement(key: "other", label: "Other movements", values: other),
    ]
    let movements = all.filter { movement in
      movement.key == "profit" || AcEquity.allCases.contains { (movement.values[$0] ?? 0) != 0 }
    }
    let components = AcEquity.allCases.filter { key in
      key == .capital || key == .retained || (opening[key] ?? 0) != 0 || (closing[key] ?? 0) != 0
        || movements.contains { ($0.values[key] ?? 0) != 0 }
    }
    return AcChangesInEquity(
      range: range, components: components, opening: opening, movements: movements, closing: closing)
  }

  static func equityTotal(_ values: AcEquityValues) -> Int {
    AcEquity.allCases.reduce(0) { $0 + (values[$1] ?? 0) }
  }

  /// `trialBalance`: balance-sheet accounts from the beginning, income and
  /// expenses from the start of the financial year, earlier years' profit apart.
  static func trialBalance(_ lines: [AcLine], _ accounts: [AcAccount], _ asOf: String, _ yearEnd: AcFiscalEnd)
    -> (rows: [AcTrialRow], totalDebit: Int, totalCredit: Int)
  {
    let fyStart = AcFiscal.start(asOf, yearEnd)
    let types = AcStatements.types(accounts)
    let amounts = balances(lines) { line in
      if line.date > asOf { return false }
      if let type = types[line.accountId], AcAccountTypes.isProfitAndLoss(type) { return line.date >= fyStart }
      return true
    }
    var rows: [AcTrialRow] = AcSort.sortedByCode(accounts).compactMap { account -> AcTrialRow? in
      let amount = amounts[account.id] ?? 0
      if amount == 0 { return nil }
      return AcTrialRow(account: account, debit: max(amount, 0), credit: max(-amount, 0))
    }
    let earlier = profitBetween(lines, types, nil, AcDate.addDays(fyStart, -1))
    if earlier != 0 { rows.append(AcTrialRow(account: nil, debit: max(-earlier, 0), credit: max(earlier, 0))) }
    return (rows, rows.reduce(0) { $0 + $1.debit }, rows.reduce(0) { $0 + $1.credit })
  }

  /// `generalLedger`: every account's movements in a range, with opening and running balances.
  static func generalLedger(
    _ lines: [AcLine], _ accounts: [AcAccount], _ range: AcRange, _ yearEnd: AcFiscalEnd, accountId: String? = nil
  ) -> [AcAccountActivity] {
    let fyStart = AcFiscal.start(range.from, yearEnd)
    var byAccount: [String: [AcLine]] = [:]
    for line in lines { byAccount[line.accountId, default: []].append(line) }
    var out: [AcAccountActivity] = []
    for account in AcSort.sortedByCode(accounts) where accountId == nil || account.id == accountId {
      let pl = AcAccountTypes.isProfitAndLoss(account.type)
      let own = byAccount[account.id] ?? []
      var opening = 0
      for line in own where line.date < range.from && (!pl || line.date >= fyStart) { opening += line.amount }
      var running = opening
      var debit = 0
      var credit = 0
      var shown: [(line: AcLine, balance: Int)] = []
      for line in own where line.date >= range.from && line.date <= range.to {
        running += line.amount
        if line.amount > 0 { debit += line.amount } else { credit -= line.amount }
        shown.append((line, running))
      }
      if opening != 0 || !shown.isEmpty {
        out.append(
          AcAccountActivity(
            account: account, opening: opening, lines: shown, debit: debit, credit: credit, closing: running))
      }
    }
    return out
  }

  // MARK: Cash flow

  private static func bucket(_ account: AcAccount, _ special: AcSpecial) -> String? {
    switch account.type {
    case "asset_cash": return "cash"
    case "asset_receivable": return "receivables"
    case "asset_current": return "other-current-assets"
    case "asset_prepayments": return "prepayments"
    case "asset_fixed", "asset_non_current": return "fixed"
    case "liability_payable": return "payables"
    case "liability_current", "liability_credit_card": return "other-current-liabilities"
    case "liability_non_current": return special.endOfService.contains(account.id) ? "end-of-service" : "loans"
    case "equity":
      if account.role == "capital" { return "capital" }
      if account.role == "drawings" { return "partners" }
      if account.role == "opening_balance" { return "opening" }
      return "other-equity"
    default: return nil
    }
  }

  private static func cashFlowLabel(_ bucket: String) -> String {
    switch bucket {
    case "receivables": "(Increase) decrease in trade receivables"
    case "other-current-assets": "(Increase) decrease in inventories and other current assets"
    case "prepayments": "(Increase) decrease in prepayments"
    case "payables": "Increase (decrease) in trade payables"
    case "other-current-liabilities": "Increase (decrease) in accruals and other liabilities"
    case "end-of-service": "Provision for end-of-service indemnity, net of payments"
    case "loans": "Loans and other non-current liabilities"
    case "capital": "Capital introduced or withdrawn"
    case "partners": "Partners’ drawings and contributions"
    case "opening": "Opening balances entered"
    default: "Dividends and other equity movements"
    }
  }

  private struct EntryFlags {
    var opening = false
    var cash = false
    var profit = false
  }

  /// `cashFlow`: the indirect method (IAS 7); `kinds` gives each journal's kind.
  static func cashFlow(
    _ lines: [AcLine], _ accounts: [AcAccount], _ range: AcRange, _ special: AcSpecial, _ kinds: [String: String]
  ) -> AcCashFlow {
    var byId: [String: AcAccount] = [:]
    for account in accounts { byId[account.id] = account }
    func kindOf(_ line: AcLine) -> String? { line.source == .journal ? kinds[line.sourceId] : nil }
    let inRange = lines.filter { $0.date >= range.from && $0.date <= range.to }

    // Opening balances that move no cash are left out entirely.
    var entries: [String: EntryFlags] = [:]
    for line in inRange {
      let account = byId[line.accountId]
      var entry = entries[line.sourceId] ?? EntryFlags()
      if kindOf(line) == "asset_opening" || account?.role == "opening_balance" { entry.opening = true }
      if account?.type == "asset_cash" { entry.cash = true }
      if let account, AcAccountTypes.isProfitAndLoss(account.type) { entry.profit = true }
      entries[line.sourceId] = entry
    }
    var nonCash = Set<String>()
    for (id, entry) in entries where entry.opening && !entry.cash && !entry.profit { nonCash.insert(id) }

    var moves: [String: Int] = [:]
    var profit = 0
    var depreciation = 0
    var disposals = 0
    var purchases = 0
    for line in inRange where !nonCash.contains(line.sourceId) {
      guard let account = byId[line.accountId] else { continue }
      if AcAccountTypes.isProfitAndLoss(account.type) {
        profit -= line.amount
        if account.type == "expense_depreciation" {
          depreciation += line.amount
        } else if kindOf(line) == "asset_disposal" {
          disposals += line.amount
        }
        continue
      }
      guard let bucket = AcStatements.bucket(account, special), bucket != "cash" else { continue }
      // A balance going up on the debit side uses cash.
      moves[bucket, default: 0] -= line.amount
      if bucket == "fixed" {
        let kind = kindOf(line)
        if kind != "depreciation" && kind != "asset_disposal" { purchases -= line.amount }
      }
    }
    func move(_ bucket: String) -> Int { moves[bucket] ?? 0 }
    func flowLine(_ key: String) -> AcCashFlowLine {
      AcCashFlowLine(key: key, label: cashFlowLabel(key), amount: move(key))
    }

    let adjustments = [
      AcCashFlowLine(key: "depreciation", label: "Depreciation and amortisation", amount: depreciation),
      AcCashFlowLine(
        key: "disposals", label: "(Gain) loss on disposal of property and equipment", amount: disposals),
      flowLine("end-of-service"),
    ]
    let workingCapital = ["receivables", "other-current-assets", "prepayments", "payables", "other-current-liabilities"]
      .map(flowLine)
    let operating =
      profit + adjustments.reduce(0) { $0 + $1.amount } + workingCapital.reduce(0) { $0 + $1.amount }
    let investingTotal = move("fixed") - depreciation - disposals
    let investing = [
      AcCashFlowLine(key: "purchases", label: "Purchase of property and equipment", amount: purchases),
      AcCashFlowLine(
        key: "proceeds", label: "Proceeds from disposal of property and equipment", amount: investingTotal - purchases),
    ]
    let financing = ["capital", "partners", "loans", "opening", "other-equity"].map(flowLine)
    let financingTotal = financing.reduce(0) { $0 + $1.amount }
    var opening = 0
    var closing = 0
    for item in lines where byId[item.accountId]?.type == "asset_cash" {
      if item.date < range.from { opening += item.amount }
      if item.date <= range.to { closing += item.amount }
    }
    return AcCashFlow(
      range: range, profit: profit, adjustments: adjustments, workingCapital: workingCapital, operating: operating,
      investing: investing, investingTotal: investingTotal, financing: financing, financingTotal: financingTotal,
      netChange: closing - opening, opening: opening, closing: closing,
      difference: operating + investingTotal + financingTotal - (closing - opening))
  }
}
