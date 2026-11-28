import MahamKit
import SwiftUI

// `/banking` and `/banking/:accountId` (src/apps/books/pages/banking/index.tsx
// with src/lib/banking/match.ts): every bank, cash and card account with what
// the books hold, and an account's statement lines with their matching state
// and reconciliation. Transfers, typed statement lines, matching and the
// lines' menus save natively (AwBankingWrites) once they can on this iPhone.

/// One entry of the books on a money account (`BookEntry`).
struct AcBookEntry: Sendable {
  let source: AcSource
  let id: String
  let date: String
  var amount: Int
  let number: String
  let contactId: String?
  let line: AcLine

  var key: String { "\(source.rawValue):\(id)" }
}

/// `reconciliation`: how far the books agree with the bank.
struct AcReconciliation: Sendable {
  let statementBalance: Int?
  let statementDate: String?
  let bookBalance: Int
  let difference: Int?
  let unmatched: Int
  let total: Int
}

enum AcBanking {
  /// `matchKey`.
  static func key(_ match: JSONValue) -> String { "\(match.str("source")):\(match.str("id"))" }

  /// `bookEntries`: one entry per payment, expense or journal that moves money on the account.
  static func entries(_ lines: [AcLine], _ accountId: String) -> [AcBookEntry] {
    var order: [String] = []
    var entries: [String: AcBookEntry] = [:]
    for line in lines where line.accountId == accountId {
      guard line.source == .payment || line.source == .expense || line.source == .journal else { continue }
      let key = "\(line.source.rawValue):\(line.sourceId)"
      if var entry = entries[key] {
        entry.amount += line.amount
        entries[key] = entry
      } else {
        order.append(key)
        entries[key] = AcBookEntry(
          source: line.source, id: line.sourceId, date: line.date, amount: line.amount, number: line.number,
          contactId: line.contactId, line: line)
      }
    }
    return order.compactMap { entries[$0] }.filter { $0.amount != 0 }
  }

  /// `reconciliation`.
  static func reconciliation(_ transactions: [JSONValue], _ lines: [AcLine], _ accountId: String, _ p: Int)
    -> AcReconciliation
  {
    let ordered = transactions.sorted { a, b in
      a.str("date") != b.str("date") ? a.str("date") < b.str("date") : a.num("position") < b.num("position")
    }
    let last = ordered.last { $0.number("balance") != nil }
    let statementDate = ordered.last?.str("date")
    let asOf = last?.str("date") ?? statementDate
    var book = 0
    for line in lines where line.accountId == accountId && (asOf == nil || line.date <= asOf!) { book += line.amount }
    let statement = last.map { AcLedger.minor($0.num("balance"), p) }
    return AcReconciliation(
      statementBalance: statement, statementDate: last?.str("date"), bookBalance: book,
      difference: statement.map { $0 - book },
      unmatched: transactions.filter { $0.obj("match") == nil && !$0.flag("ignored") }.count,
      total: transactions.count)
  }

  /// Money accounts in use, by code.
  static func moneyAccounts(_ books: AcBooks) -> [AcAccount] {
    AcSort.sortedByCode(books.accounts.filter { AcAccountTypes.isMoneyAccount($0.type) && !$0.archived })
  }

  /// Newest first, keeping the statement's order on a day.
  static func newestFirst(_ a: JSONValue, _ b: JSONValue) -> Bool {
    a.str("date") != b.str("date") ? a.str("date") > b.str("date") : a.num("position") > b.num("position")
  }
}

/// `/banking`: an account card for each bank, cash and card account.
struct AcBankingPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(SuiteState.self) private var suite: SuiteState?
  @State private var transferring = false

  var body: some View {
    let one = model.one
    let books = one.acBooks
    let accounts = AcBanking.moneyAccounts(books)
    let transactions = one.records(.bankTransactions)
    let canTransfer = AwWrite.journals && AwAccess(model, suite).edits && !accounts.isEmpty
    WebPage(spacing: 16, refresh: { [model] in await model.one.sync() }) {
      PageHeader(
        t("Banking"), description: t("Import statements, match them to your books and keep every account reconciled.")
      ) {
        if canTransfer {
          WebButton(t("Transfer money"), icon: .arrowLeftRight, variant: .outline) { transferring = true }
        }
      }
      .padding(.bottom, -16)
      AcPayrollNote()
      if accounts.isEmpty {
        Card {
          if !one.hasData {
            DataLoadingRow()
          } else {
            WebEmptyState(
              icon: .banknote, title: t("No bank accounts yet"),
              description: t("Add your bank, cash and card accounts in the chart of accounts.")
            ) {
              WebButton(t("Open chart of accounts")) { router.push(.accounts) }
            }
          }
        }
      } else {
        ForEach(accounts) { account in
          AcBankAccountCard(account: account, books: books, transactions: transactions.filter { $0.str("accountId") == account.id })
        }
      }
    }
    .awTransferDialog($transferring, accounts: AwPick.money(one), from: nil)
  }
}

/// An account's card: its name, what the books hold and the statement's state.
struct AcBankAccountCard: View {
  let account: AcAccount
  let books: AcBooks
  let transactions: [JSONValue]
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let format = model.one.format
    let card = account.type == "liability_credit_card"
    let keys = Set(AcBanking.entries(books.lines, account.id).map(\.key))
    let unmatched = transactions.filter { tx in
      guard !tx.flag("ignored") else { return false }
      guard let match = tx.obj("match") else { return true }
      return !keys.contains(AcBanking.key(match))
    }.count
    let balance = books.lines.reduce(0) { $1.accountId == account.id ? $0 + $1.amount : $0 }
    let last = transactions.sorted(by: AcBanking.newestFirst).first
    Button {
      Haptics.play(.tap)
      router.push(.bankAccount(id: account.id))
    } label: {
      Card {
        VStack(alignment: .leading, spacing: 0) {
          HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
              Text(localName(account.raw)).font(.web(16, .semibold)).foregroundStyle(palette.slate(900)).lineLimit(1)
              Text(subtitle).font(.web(12)).foregroundStyle(palette.slate(500))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            IconView(card ? .creditCard : .banknote, size: 20).foregroundStyle(palette.slate(400))
          }
          Text(format.acMoney(card ? -balance : balance))
            .font(.web(24, .semibold, tabular: true))
            .foregroundStyle(palette.slate(900))
            .environment(\.layoutDirection, .leftToRight)
            .padding(.top, 16)
          Text(card ? t("Owed on the card") : t("In your books")).font(.web(12)).foregroundStyle(palette.slate(500))
          Rectangle().fill(palette.slate(100)).frame(height: 1).padding(.top, 16)
          HStack(spacing: 8) {
            Text(
              last.map { t("Statement to {date}", ["date": format.date($0.text("date"))]) }
                ?? t("No statement imported")
            )
            .font(.web(14))
            .foregroundStyle(palette.slate(500))
            .frame(maxWidth: .infinity, alignment: .leading)
            if !transactions.isEmpty {
              if unmatched > 0 {
                Badge(tp(unmatched, "{count} to match", "{count} to match"), tone: .amber)
              } else {
                Badge(t("All matched"), tone: .green)
              }
            }
          }
          .padding(.top, 12)
        }
        .padding(20)
      }
    }
    .buttonStyle(PressedScale())
  }

  private var subtitle: String {
    account.bankInstitution.isEmpty ? account.code : "\(account.code) · \(account.bankInstitution)"
  }
}

/// `/banking/:accountId`: the reconciliation figures and the statement lines.
struct AcBankAccountPage: View {
  let id: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(SuiteState.self) private var suite: SuiteState?
  @Environment(\.palette) private var palette
  @State private var tab = "match"
  @State private var transferring = false
  @State private var adding: JSONValue?
  @State private var matching: JSONValue?

  init(id: String) {
    self.id = id
  }

  var body: some View {
    let one = model.one
    let books = one.acBooks
    let account = books.account(id)
    let access = AwAccess(model, suite)
    RecordDetailPage(
      record: account?.raw, title: account.map { localName($0.raw) } ?? "", subtitle: account.map(subtitle),
      breadcrumb: t("Banking")
    ) {
      if let account, reconciled(account, books) { Badge(t("Reconciled"), tone: .green) }
    } actions: {
      if let account {
        if AwWrite.journals, access.edits {
          WebButton(t("Transfer"), icon: .arrowLeftRight, variant: .outline, size: .sm) { transferring = true }
        }
        if AwWrite.statementLines, access.accounting {
          WebButton(t("Add statement lines"), icon: .listPlus, size: .sm) { adding = account.raw }
        }
      }
    } content: {
      if let account {
        AcPayrollNote()
        content(account, books)
      }
    }
    .awTransferDialog($transferring, accounts: transferAccounts(account), from: id)
    .awStatementLinesDialog($adding)
    .awMatchDialog($matching)
  }

  /// The money accounts a transfer can be between (this one at least).
  private func transferAccounts(_ account: AcAccount?) -> [JSONValue] {
    let money = AwPick.money(model.one)
    if money.contains(where: { $0.rid == id }) { return money }
    return account.map { [$0.raw] } ?? []
  }

  /// A line's menu and match panel, for those who may change statement lines.
  private func lineActions(_ tx: JSONValue) -> AwLineActions? {
    guard AwWrite.matching, AwAccess(model, suite).accounting else { return nil }
    let model = self.model
    var onMatch: (() -> Void)? = nil
    if tab == "match" { onMatch = { matching = tx } }
    return AwLineActions(tab: tab, onMatch: onMatch, run: { action in AwLineAction.run(action, line: tx, model: model) })
  }

  private func subtitle(_ account: AcAccount) -> String {
    account.bankInstitution.isEmpty ? account.code : "\(account.code) · \(account.bankInstitution)"
  }

  private func transactions(_ account: AcAccount) -> [JSONValue] {
    model.one.records(.bankTransactions).filter { $0.str("accountId") == account.id }
  }

  private func reconciled(_ account: AcAccount, _ books: AcBooks) -> Bool {
    let rec = AcBanking.reconciliation(transactions(account), books.lines, account.id, books.precision)
    return rec.total > 0 && rec.unmatched == 0 && rec.difference == 0
  }

  @ViewBuilder
  private func content(_ account: AcAccount, _ books: AcBooks) -> some View {
    let format = model.one.format
    let card = account.type == "liability_credit_card"
    let all = transactions(account)
    let entries = AcBanking.entries(books.lines, account.id)
    let byKey = Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    let sorted = all.sorted(by: AcBanking.newestFirst)
    let lists = split(sorted, byKey)
    let rec = AcBanking.reconciliation(all, books.lines, account.id, books.precision)
    let dateSuffix = rec.statementDate.map { " · " + format.date($0) } ?? ""
    AcStat(
      t("Statement balance") + dateSuffix,
      value: rec.statementBalance.map { format.acMoney(card ? -$0 : $0) } ?? "—")
    AcStat(t("In your books") + dateSuffix, value: format.acMoney(card ? -rec.bookBalance : rec.bookBalance))
    AcStat(
      t("Difference"), value: rec.difference.map { format.acMoney(abs($0)) } ?? "—", hint: differenceHint(rec),
      tone: (rec.difference ?? 0) != 0 ? Token.amber(700) : nil)
    ListCard {
      Segmented(
        selection: $tab,
        options: [
          SegmentOption("match", t("To match"), count: lists.match.count),
          SegmentOption("matched", t("Matched"), count: lists.matched.count),
          SegmentOption("ignored", t("Ignored"), count: lists.ignored.count),
        ])
    } rows: {
      if all.isEmpty {
        WebEmptyState(
          icon: .fileUp, title: t("No statement yet"),
          description: t("Import an Excel, CSV or OFX statement from your online banking to match it to your books."))
      } else {
        let shown = tab == "matched" ? lists.matched : tab == "ignored" ? lists.ignored : lists.match
        if shown.isEmpty {
          VStack(spacing: 8) {
            IconView(.circleCheck, size: 32).foregroundStyle(palette[.emerald(500)])
            Text(tab == "match" ? t("Everything is matched.") : t("Nothing here."))
              .font(.web(14))
              .foregroundStyle(palette.slate(600))
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 48)
        } else {
          ForEach(shown.map(Rec.init)) { record in
            AcStatementLineRow(
              transaction: record.raw, entry: matched(record.raw, byKey), format: format,
              actions: lineActions(record.raw))
          }
        }
      }
    }
  }

  private func matched(_ tx: JSONValue, _ byKey: [String: AcBookEntry]) -> AcBookEntry? {
    tx.obj("match").flatMap { byKey[AcBanking.key($0)] }
  }

  private func split(_ sorted: [JSONValue], _ byKey: [String: AcBookEntry])
    -> (match: [JSONValue], matched: [JSONValue], ignored: [JSONValue])
  {
    var match: [JSONValue] = []
    var done: [JSONValue] = []
    var ignored: [JSONValue] = []
    for tx in sorted {
      if tx.flag("ignored") {
        ignored.append(tx)
      } else if matched(tx, byKey) != nil {
        done.append(tx)
      } else {
        match.append(tx)
      }
    }
    return (match, done, ignored)
  }

  private func differenceHint(_ rec: AcReconciliation) -> String {
    guard let difference = rec.difference else { return t("Shown once a statement with balances is imported.") }
    if rec.unmatched > 0 {
      return tp(rec.unmatched, "{count} statement line to match", "{count} statement lines to match")
    }
    return difference != 0 ? t("Check for missing or duplicated transactions.") : t("Your books agree with the bank.")
  }
}

/// A statement line: its description and date, what it is matched to, and the amount.
struct AcStatementLineRow: View {
  let transaction: JSONValue
  let entry: AcBookEntry?
  let format: CompanyFormat
  /// The line's menu and match panel, for those who may change statement lines.
  var actions: AwLineActions? = nil
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    if let actions {
      HStack(spacing: 0) {
        Button {
          Haptics.play(.tap)
          (actions.onMatch ?? action)?()
        } label: {
          content.contentShape(Rectangle())
        }
        .buttonStyle(PressedFill(radius: 0, color: .slate(100)))
        AwLineMenu(transaction: transaction, actions: actions)
          .padding(.trailing, 8)
      }
      .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
    } else {
      AcTapRow(action: action) { content }
    }
  }

  private var content: some View {
    let amount = transaction.num("amount")
    return HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(transaction.text("description") ?? "—")
            .font(.web(14, .medium))
            .foregroundStyle(palette.slate(800))
            .lineLimit(2)
          Text(dateText).font(.web(12)).foregroundStyle(palette.slate(500))
          detailLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Text(format.money(amount))
          .font(.web(14, .semibold, tabular: true))
          .foregroundStyle(amount > 0 ? palette[.emerald(700)] : palette.slate(900))
          .environment(\.layoutDirection, .leftToRight)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(minHeight: 56)
  }

  private var action: (() -> Void)? {
    guard let entry else { return nil }
    let route = AcLinks.source(entry.source, entry.id, one: model.one)
    return { router.push(route) }
  }

  private var dateText: String {
    var text = format.date(transaction.text("date"))
    if let value = transaction.text("valueDate"), value != transaction.str("date") {
      text += " · " + t("Value date {date}", ["date": format.date(value)])
    }
    return text
  }

  @ViewBuilder
  private var detailLine: some View {
    if let entry {
      HStack(spacing: 4) {
        IconView(.link2, size: 12)
        Text(matchText(entry)).lineLimit(1)
      }
      .font(.web(12))
      .foregroundStyle(palette.primary(700))
    } else if transaction.obj("match") != nil {
      Text(t("What it was matched to has been deleted.")).font(.web(12)).foregroundStyle(palette[.amber(700)])
    } else if let reference = transaction.text("reference") {
      Text(reference).font(.web(12)).foregroundStyle(palette.slate(500)).lineLimit(1)
    }
  }

  private func matchText(_ entry: AcBookEntry) -> String {
    let name = model.one.contactName(entry.contactId)
    let base = "\(t(entry.source.label)) \(entry.number)"
    return name.isEmpty ? base : "\(base) · \(name)"
  }
}
