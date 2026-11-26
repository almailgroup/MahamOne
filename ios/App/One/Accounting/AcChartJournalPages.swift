import MahamKit
import SwiftUI

// `/accounts` (src/apps/books/pages/accounting/chart.tsx), `/journals` and
// `/journals/:id` (journals.tsx, journal-editor.tsx), read only.

// MARK: Chart of accounts

/// `/accounts`: every account by group, with its balance as of today.
struct AcChartPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @State private var query = ""
  @State private var showArchived = false

  var body: some View {
    let books = model.one.acBooks
    let balances = books.balances(upTo: AcDate.today)
    let visible = visibleAccounts(books)
    let format = model.one.format
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(
        t("Chart of accounts"),
        description: t("Every invoice, payment and journal is recorded in these accounts. Balances are as of today."))
      AcPayrollNote()
      ListCard {
        TextInput(text: $query, placeholder: t("Search accounts…"), leadingIcon: .search)
        Switch(t("Show archived"), isOn: $showArchived)
      } rows: {
        if books.accounts.isEmpty, !model.one.hasData {
          DataLoadingRow()
        } else if visible.isEmpty {
          AcCardText(t("No accounts match your search."), centered: true)
        } else {
          ForEach(AcGroup.allCases, id: \.self) { group in
            let rows = visible.filter { $0.group == group }
            if !rows.isEmpty {
              AcGroupHeading(title: t(group.label))
              ForEach(rows) { account in
                AcAccountRow(account: account, balance: balances[account.id] ?? 0, format: format) {
                  router.push(
                    AcLinks.ledger(account.id, AcRange(from: "0000-01-01", to: AcDate.today)))
                }
              }
            }
          }
        }
      }
    }
  }

  private func visibleAccounts(_ books: AcBooks) -> [AcAccount] {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    let shown = books.accounts.filter { account in
      guard showArchived || !account.archived else { return false }
      if q.isEmpty { return true }
      let type = AcAccountTypes.label(account.type)
      let text = "\(account.code) \(account.name) \(account.nameAr ?? "") \(type) \(t(type))".lowercased()
      return text.contains(q)
    }
    return AcSort.sortedByCode(shown)
  }
}

/// An account in the chart: code, name (with its other-language name), badges and balance.
struct AcAccountRow: View {
  let account: AcAccount
  let balance: Int
  let format: CompanyFormat
  let action: () -> Void
  @Environment(\.palette) private var palette

  var body: some View {
    AcTapRow(action: action) {
      HStack(alignment: .top, spacing: 12) {
        Text(account.code)
          .font(.web(14, tabular: true))
          .foregroundStyle(palette.slate(500))
          .frame(width: 48, alignment: .leading)
        VStack(alignment: .leading, spacing: 3) {
          Text(localName(account.raw))
            .font(.web(14, .medium))
            .foregroundStyle(account.archived ? palette.slate(500) : palette.slate(900))
            .multilineTextAlignment(.leading)
          if !otherName.isEmpty {
            Text(otherName).font(.web(12)).foregroundStyle(palette.slate(500))
          }
          if account.role != nil || account.archived {
            HStack(spacing: 6) {
              if account.role != nil { Badge(t("System")) }
              if account.archived { Badge(t("Archived")) }
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Text(balanceText)
          .font(.web(14, tabular: true))
          .foregroundStyle(balance == 0 ? palette.slate(300) : palette.slate(700))
          .lineLimit(1)
          .environment(\.layoutDirection, .leftToRight)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .frame(minHeight: 48)
    }
  }

  private var balanceText: String {
    if balance == 0 { return "—" }
    return format.acMoney(AcAccountTypes.isDebitNormal(account.type) ? balance : -balance)
  }

  /// The account's name in the other language, shown under the main one.
  private var otherName: String {
    let shown = localName(account.raw)
    let other =
      LanguageStore.shared.isArabic
      ? account.name : (account.nameAr?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    return !other.isEmpty && other != shown ? other : ""
  }
}

// MARK: Journals

/// A journal's kind (`JOURNAL_KINDS`): label, tone and where it is managed.
struct AcJournalKind: Sendable {
  let label: String
  let tone: StatusTone
  let owner: String?

  static func of(_ journal: JSONValue) -> AcJournalKind? {
    switch journal.str("kind") {
    case "transfer": AcJournalKind(label: "Transfer", tone: .violet, owner: nil)
    case "cheque_clearing": AcJournalKind(label: "Cheque clearing", tone: .blue, owner: "Payments")
    case "cheque_return": AcJournalKind(label: "Returned cheque", tone: .red, owner: "Payments")
    case "payroll": AcJournalKind(label: "Payroll", tone: .blue, owner: "Payroll")
    case "depreciation": AcJournalKind(label: "Depreciation", tone: .amber, owner: "Fixed assets")
    case "asset_purchase": AcJournalKind(label: "Asset purchase", tone: .amber, owner: "Fixed assets")
    case "asset_opening": AcJournalKind(label: "Asset opening balance", tone: .amber, owner: "Fixed assets")
    case "asset_disposal": AcJournalKind(label: "Asset disposal", tone: .amber, owner: "Fixed assets")
    case "year_end": AcJournalKind(label: "Year-end close", tone: .green, owner: "Year-end close")
    case "retention_release": AcJournalKind(label: "Retention release", tone: .violet, owner: "Retentions")
    default: nil
    }
  }

  /// `journalOwnerLink`: the page where an owned journal is managed.
  @MainActor
  static func ownerRoute(_ journal: JSONValue, one: OneData) -> Route? {
    switch journal.str("kind") {
    case "depreciation": return .assets
    case "asset_purchase", "asset_opening", "asset_disposal":
      if let source = journal.text("sourceId") { return .asset(id: source) }
      return .assets
    case "year_end": return .yearEnd
    case "cheque_clearing", "cheque_return":
      guard let payment = journal.text("paymentId") ?? journal.text("sourceId") else { return .payments(.received) }
      let out = one.record(.payments, payment)?.str("direction") == "out"
      return .payment(out ? .made : .received, id: payment)
    case "payroll": return .payroll
    case "retention_release": return .report("retentions")
    default: return nil
    }
  }
}

enum AcJournals {
  /// Entries Maham Books made itself.
  static func isSystem(_ journal: JSONValue) -> Bool {
    journal.text("kind") != nil || journal.text("vatReturnId") != nil
  }

  /// `journalTotals`.
  static func totals(_ journal: JSONValue, _ p: Int) -> (debit: Double, credit: Double, difference: Double) {
    var debit = Decimal(0)
    var credit = Decimal(0)
    for line in journal.list("lines") {
      debit += Money.dec(line.num("debit"))
      credit += Money.dec(line.num("credit"))
    }
    return (
      Money.toNumber(Money.round(debit, p)), Money.toNumber(Money.round(credit, p)),
      Money.toNumber(Money.round(debit - credit, p))
    )
  }

  /// Newest first, then by number.
  static func newestFirst(_ a: JSONValue, _ b: JSONValue) -> Bool {
    if a.str("date") != b.str("date") { return a.str("date") > b.str("date") }
    return AcText.compare(a.str("number"), b.str("number")) == .orderedDescending
  }
}

/// `/journals`: manual journals and the entries Maham Books made.
struct AcJournalsPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let one = model.one
    let format = one.format
    let journals = one.records(.journals).sorted(by: AcJournals.newestFirst)
    RecordListPage(
      title: t("Manual journals"),
      description: t(
        "Entries that don’t come from an invoice or payment: owner investments, opening balances, corrections. Entries made by Maham Books are marked."
      ),
      records: journals.map(Rec.init), chips: chips(journals),
      chipFilter: { record, chip in (chip == "system") == AcJournals.isSystem(record.raw) },
      newLabel: t("New journal"), onNew: { router.push(.newJournal) }, emptyIcon: .notebookPen,
      emptyTitle: t("No manual journals yet"),
      emptyDescription: t("Invoices and payments are recorded automatically. Use a journal for anything else.")
    ) { record in
      AcJournalRow(journal: record.raw, format: format)
    }
  }

  private func chips(_ journals: [JSONValue]) -> [ListChip] {
    let system = journals.filter(AcJournals.isSystem).count
    if system == 0 { return [] }
    return [
      ListChip("all", t("All"), count: journals.count),
      ListChip("manual", t("Manual"), count: journals.count - system),
      ListChip("system", t("Made by Maham Books"), count: system),
    ]
  }
}

/// A journal in the list: its reference, "number · date", the amount and its badges.
struct AcJournalRow: View {
  let journal: JSONValue
  let format: CompanyFormat
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let reference = journal.str("reference")
    let total = AcJournals.totals(journal, Money.precision(format.currency)).debit
    ListRow(
      title: reference.isEmpty ? journal.str("number") : reference,
      subtitle: "\(journal.str("number")) · \(format.date(journal.text("date")))",
      amount: format.money(total)
    ) {
      AcJournalBadges(journal: journal)
    } action: {
      router.push(.journal(id: journal.rid))
    }
  }
}

/// Posted or draft, VAT return, the kind and reversal.
struct AcJournalBadges: View {
  let journal: JSONValue
  var showStatus = true

  var body: some View {
    if showStatus {
      Badge(journal.str("status") == "posted" ? t("Posted") : t("Draft"), tone: journal.str("status") == "posted" ? .green : .gray)
    }
    if journal.text("vatReturnId") != nil { Badge(t("VAT return"), tone: .blue) }
    if let kind = AcJournalKind.of(journal) { Badge(t(kind.label), tone: kind.tone) }
    if journal.text("reversalOf") != nil { Badge(t("Reversal")) }
  }
}

/// `/journals/:id`: the journal's date, reference and notes, and its lines.
struct AcJournalPage: View {
  let id: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let one = model.one
    let journal = one.record(.journals, id)
    let kind = journal.flatMap(AcJournalKind.of)
    RecordDetailPage(
      record: journal, title: t("Journal {number}", ["number": journal?.str("number") ?? ""]),
      breadcrumb: t("Manual journals")
    ) {
      if let journal { AcJournalBadges(journal: journal) }
    } content: {
      if let journal {
        if journal.text("vatReturnId") != nil {
          AcNotice(
            t(
              "This entry moves the period’s VAT to the VAT liability account. It was made when the return was filed and can only be removed by undoing the filing."
            ), tone: .blue, link: t("Open VAT returns"), onLink: { router.push(.vat) })
        }
        if let kind, let owner = kind.owner {
          AcNotice(
            t("Maham Books made this entry in {place}, so it can only be changed there.", ["place": t(owner)]),
            icon: .lock, tone: .slate, link: t("Open {place}", ["place": t(owner)]),
            onLink: ownerAction(journal))
          if let reversed = reversedJournal(journal) {
            AcNotice(
              t("It reverses journal {number}.", ["number": reversed.str("number")]), icon: .undo2, tone: .slate,
              link: t("View"), onLink: { router.push(.journal(id: reversed.rid)) })
          }
        }
        InfoCard(
          rows: [
            InfoRow(t("Date"), one.format.date(journal.text("date"))),
            InfoRow(t("Reference"), journal.str("reference")),
          ])
        TextCard(title: t("Notes"), text: journal.text("notes"))
        AcJournalLinesCard(journal: journal)
      }
    }
  }

  private func ownerAction(_ journal: JSONValue) -> (() -> Void)? {
    guard let route = AcJournalKind.ownerRoute(journal, one: model.one) else { return nil }
    return { router.push(route) }
  }

  private func reversedJournal(_ journal: JSONValue) -> JSONValue? {
    guard let id = journal.text("reversalOf") else { return nil }
    return model.one.record(.journals, id)
  }
}

/// The lines of a journal: account, description, debit or credit; the totals and any difference.
struct AcJournalLinesCard: View {
  let journal: JSONValue
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let format = model.one.format
    let totals = AcJournals.totals(journal, Money.precision(format.currency))
    let lines = journal.list("lines")
    Card {
      CardHeader(
        t("Lines"),
        description: t("Amounts in {currency}. Each line has a debit or a credit.", ["currency": format.currency]))
      VStack(spacing: 0) {
        ForEach(lines.indices, id: \.self) { index in
          lineRow(lines[index], format: format, first: index == 0)
        }
      }
      AcLineRow(label: t("Total") + " · " + t("Debit"), value: format.money(totals.debit), strong: true)
      AcLineRow(label: t("Total") + " · " + t("Credit"), value: format.money(totals.credit), strong: true)
      if totals.difference != 0 {
        AcLineRow(label: t("Difference"), value: differenceText(totals.difference, format), strong: true, tone: .red(600))
      }
    }
  }

  private func differenceText(_ difference: Double, _ format: CompanyFormat) -> String {
    let amount = format.money(abs(difference))
    return difference > 0 ? t("{amount} more debit", ["amount": amount]) : t("{amount} more credit", ["amount": amount])
  }

  @ViewBuilder
  private func lineRow(_ line: JSONValue, format: CompanyFormat, first: Bool) -> some View {
    let account = model.one.acBooks.account(line.text("accountId"))
    let debit = line.num("debit")
    let credit = line.num("credit")
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(account.map { "\($0.code) \(localName($0.raw))" } ?? "—")
          .font(.web(14, .medium))
          .foregroundStyle(palette.slate(900))
        if let description = line.text("description") {
          Text(description).font(.web(12)).foregroundStyle(palette.slate(500))
        }
        if let contact = line.text("contactId"), !model.one.contactName(contact).isEmpty {
          Text(model.one.contactName(contact)).font(.web(12)).foregroundStyle(palette.slate(500))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .trailing, spacing: 2) {
        Text(debit != 0 ? format.money(debit) : format.money(credit))
          .font(.web(14, .semibold, tabular: true))
          .foregroundStyle(palette.slate(900))
          .environment(\.layoutDirection, .leftToRight)
        Text(debit != 0 ? t("Debit") : t("Credit")).font(.web(12)).foregroundStyle(palette.slate(500))
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .overlay(alignment: .top) {
      if !first { Rectangle().fill(palette.slate(100)).frame(height: 1) }
    }
  }
}
