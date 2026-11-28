import MahamKit
import SwiftUI

// What changes the banking pages (src/apps/books/pages/banking/index.tsx,
// features/banking/transfer-dialog.tsx, src/lib/banking/match.ts): moving
// money between the company's own accounts, statement lines typed in from a
// statement, matching a line to an entry of the books or recording it as a
// transfer or against another account, and unmatching, ignoring, restoring
// or deleting a line.

// MARK: Suggestions

/// `suggestMatches`: entries of the books with the same amount, close in
/// date, best first (a number or the contact's name in the bank's words counts).
@MainActor
enum AwMatch {
  /// Words in most business names that say nothing about who paid (`COMMON_WORDS`).
  static let common: Set<String> = [
    "company", "trading", "general", "contracting", "w.l.l", "wll", "the", "and", "شركه", "مؤسسه", "للتجاره",
    "التجاره", "العامه", "والمقاولات", "المقاولات",
  ]

  /// `normalizeArabic`: no diacritics or tatweel; alef, yeh and teh marbuta written one way.
  static func normalizeArabic(_ text: String) -> String {
    var out = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 0x064B...0x0652, 0x0640: continue
      case 0x0623, 0x0625, 0x0622: out.append("\u{0627}")
      case 0x0649: out.append("\u{064A}")
      case 0x0629: out.append("\u{0647}")
      default: out.append(scalar)
      }
    }
    return String(out)
  }

  private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
    if scalar == "." || scalar == "-" { return true }
    switch scalar.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber,
      .letterNumber, .otherNumber:
      return true
    default:
      return false
    }
  }

  /// `words(text)`: the words of more than two letters, common ones left out.
  static func words(_ text: String) -> Set<String> {
    var out = Set<String>()
    var current = String.UnicodeScalarView()
    func flush() {
      let word = String(current)
      if word.utf16.count > 2 && !common.contains(word) { out.insert(word) }
      current = String.UnicodeScalarView()
    }
    for scalar in normalizeArabic(text.lowercased()).unicodeScalars {
      if isWordScalar(scalar) {
        current.append(scalar)
      } else {
        flush()
      }
    }
    flush()
    return out
  }

  static func suggest(
    _ line: JSONValue, amount: Int, entries: [AcBookEntry], taken: Set<String>, names: [String: String],
    maxDays: Int = 30
  ) -> [AcBookEntry] {
    let text = "\(line.str("description")) \(line.str("reference"))".lowercased()
    let textWords = words(text)
    var scored: [(entry: AcBookEntry, score: Int, order: Int)] = []
    for (order, entry) in entries.enumerated() where entry.amount == amount && !taken.contains(entry.key) {
      let days = abs(ISODates.daysBetween(entry.date, line.str("date")) ?? Int.max / 8)
      if days > maxDays { continue }
      var score = 100 - days * 4
      if !entry.number.isEmpty, text.contains(entry.number.lowercased()) { score += 50 }
      if let id = entry.contactId, let name = names[id], !words(name).isDisjoint(with: textWords) { score += 25 }
      scored.append((entry, score, order))
    }
    return scored.sorted { a, b in a.score != b.score ? a.score > b.score : a.order < b.order }.map { $0.entry }
  }
}

// MARK: Transfers

extension View {
  /// "Transfer money" while `isPresented`: between `accounts`, from `from` first.
  func awTransferDialog(_ isPresented: Binding<Bool>, accounts: [JSONValue], from: String?) -> some View {
    modifier(AwTransferDialog(isPresented: isPresented, accounts: accounts, initialFrom: from))
  }

  /// "Add statement lines" while `account` is set.
  func awStatementLinesDialog(_ account: Binding<JSONValue?>) -> some View {
    modifier(AwStatementLinesDialog(account: account))
  }

  /// Matching or recording a statement line while `line` is set.
  func awMatchDialog(_ line: Binding<JSONValue?>) -> some View {
    modifier(AwMatchDialog(line: line))
  }
}

private struct AwTransferDialog: ViewModifier {
  @Binding var isPresented: Bool
  let accounts: [JSONValue]
  let initialFrom: String?
  @Environment(AppModel.self) private var model
  @State private var from = ""
  @State private var to = ""
  @State private var date = AcDate.today
  @State private var amount = 0.0
  @State private var reference = ""
  @State private var saving = false
  @State private var error: String?

  func body(content: Content) -> some View {
    let currency = model.one.format.currency
    content
      .webDialog(
        isPresented: $isPresented, title: t("Transfer money"),
        description: t("Between your own accounts: topping up petty cash, paying off the card, moving savings.")
      ) {
        Field(t("From")) { Select(selection: $from, options: options) }
        Field(t("To")) { Select(selection: $to, options: options) }
        Field(t("Date")) { DateField(value: $date, required: true) }
        Field(t("Amount ({currency})", ["currency": currency])) { AwAmountField(value: $amount) }
        Field(t("Reference"), optional: true) { TextInput(text: $reference) }
        AwFormError(text: error)
      } footer: {
        WebButton(t("Cancel"), variant: .outline) { isPresented = false }
        WebButton(t("Record transfer"), loading: saving) { save() }
      }
      .onChange(of: isPresented, initial: true) { _, open in
        guard open else { return }
        let first = initialFrom ?? accounts.first?.rid ?? ""
        from = first
        to = accounts.first { $0.rid != first }?.rid ?? ""
        date = AcDate.today
        amount = 0
        reference = ""
        saving = false
        error = nil
      }
  }

  private var options: [SelectOption<String>] {
    accounts.map { SelectOption($0.rid, AwPick.label($0)) }
  }

  private func save() {
    guard let companyId = model.one.companyId else { return }
    let input = (from: from, to: to, date: date, amount: amount, reference: reference)
    saving = true
    error = nil
    Task {
      let saved = await AwSave.run(model, failed: { error = $0 }) { ctx, tr in
        try AwBanking.saveTransfer(
          ctx, companyId: companyId, from: input.from, to: input.to, date: input.date, amount: input.amount,
          reference: input.reference, tr: tr)
      }
      saving = false
      guard saved != nil else { return }
      model.confirm(t("Transfer recorded"))
      isPresented = false
    }
  }
}

// MARK: Statement lines typed in

/// A statement line as typed: money in or out, and the balance when the statement shows it.
private struct AwTypedLine: Identifiable {
  let id = UUID()
  var date = AcDate.today
  var description = ""
  var reference = ""
  var moneyIn = 0.0
  var moneyOut = 0.0
  var balance = ""

  var amount: Double { Money.toNumber(Money.dec(moneyIn) - Money.dec(moneyOut)) }
  var filled: Bool { ISODates.isISODate(date) && amount != 0 }

  var statementLine: AwStatementLine {
    let typed = balance.trimmingCharacters(in: .whitespaces)
    return AwStatementLine(
      date: date, description: description, reference: reference, amount: amount,
      balance: typed.isEmpty ? nil : Money.parseAmount(typed))
  }
}

private struct AwStatementLinesDialog: ViewModifier {
  @Binding var account: JSONValue?
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette
  @State private var lines: [AwTypedLine] = [AwTypedLine()]
  @State private var saving = false
  @State private var error: String?

  func body(content: Content) -> some View {
    let ready = lines.filter(\.filled)
    content
      .webDialog(
        isPresented: shown, title: t("Add statement lines"),
        description: t("Type the lines from a statement as the bank shows them. Lines already there are skipped.")
      ) {
        ForEach($lines) { $line in
          lineFields($line)
        }
        WebButton(t("Add line"), icon: .plus, variant: .outline, size: .sm) { lines.append(AwTypedLine()) }
        AwFormError(text: error)
      } footer: {
        WebButton(t("Cancel"), variant: .outline) { account = nil }
        WebButton(
          ready.isEmpty ? t("Import") : tp(ready.count, "Import {count} line", "Import {count} lines"), loading: saving
        ) { save() }
        .disabled(ready.isEmpty)
      }
      .onChange(of: account?.rid, initial: true) { _, _ in
        guard account != nil else { return }
        lines = [AwTypedLine()]
        saving = false
        error = nil
      }
  }

  private var shown: Binding<Bool> {
    Binding(get: { account != nil }, set: { if !$0 { account = nil } })
  }

  private func lineFields(_ line: Binding<AwTypedLine>) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Field(t("Date")) { DateField(value: line.date, required: true) }
      Field(t("Description")) { TextInput(text: line.description) }
      Field(t("Reference"), optional: true) { TextInput(text: line.reference) }
      HStack(spacing: 8) {
        Field(t("Money in")) { AwAmountField(value: line.moneyIn) }
        Field(t("Money out")) { AwAmountField(value: line.moneyOut) }
      }
      Field(t("Balance"), optional: true) {
        TextInput(text: line.balance, keyboard: .numbersAndPunctuation)
          .environment(\.layoutDirection, .leftToRight)
      }
    }
    .padding(.bottom, 8)
    .overlay(alignment: .bottom) { Rectangle().fill(palette.slate(200)).frame(height: 1) }
  }

  private func save() {
    guard let target = account, let companyId = model.one.companyId else { return }
    let accountId = target.rid
    let typed = lines.filter(\.filled).map(\.statementLine)
    saving = true
    error = nil
    Task {
      let result = await AwSave.run(model, failed: { error = $0 }) { ctx, _ in
        try AwBanking.importStatement(ctx, companyId: companyId, accountId: accountId, lines: typed, fileName: "")
      }
      saving = false
      guard let result else { return }
      model.confirm(
        result.duplicates > 0
          ? tp(
            result.added, "{count} line imported, {duplicates} already there",
            "{count} lines imported, {duplicates} already there", ["duplicates": "\(result.duplicates)"])
          : tp(result.added, "{count} line imported", "{count} lines imported"))
      account = nil
    }
  }
}

// MARK: Matching a line

private struct AwMatchDialog: ViewModifier {
  @Binding var line: JSONValue?
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette
  @State private var recipe = "transfer"
  @State private var otherMoney = ""
  @State private var otherAccount: String?
  @State private var busy = false
  @State private var error: String?

  func body(content: Content) -> some View {
    content
      .webDialog(isPresented: shown, title: title, description: subtitle) {
        if let line {
          panel(line)
        }
      }
      .onChange(of: line?.rid, initial: true) { _, _ in
        guard let line else { return }
        let text = "\(line.str("description")) \(line.str("reference"))"
        let money = moneyAccounts(line)
        let card = text.range(of: "card|بطاقة", options: [.regularExpression, .caseInsensitive]) != nil
        let cardAccount = money.first(where: { $0.str("type") == "liability_credit_card" })
        otherMoney = (card ? cardAccount?.rid : nil) ?? money.first?.rid ?? ""
        let transfer = text.range(
          of: "transfer|repayment|top.?up|tfr|تحويل|سداد", options: [.regularExpression, .caseInsensitive]) != nil
        recipe = !money.isEmpty && transfer ? "transfer" : "account"
        otherAccount = nil
        busy = false
        error = nil
      }
  }

  private var shown: Binding<Bool> {
    Binding(get: { line != nil }, set: { if !$0 { line = nil } })
  }

  private var title: String {
    line.map { $0.text("description") ?? "—" } ?? ""
  }

  private var subtitle: String? {
    guard let line else { return nil }
    let format = model.one.format
    return "\(format.date(line.text("date"))) · \(format.money(line.num("amount")))"
  }

  /// The other bank, cash and card accounts.
  private func moneyAccounts(_ line: JSONValue) -> [JSONValue] {
    AwPick.money(model.one).filter { $0.rid != line.str("accountId") }
  }

  @ViewBuilder
  private func panel(_ line: JSONValue) -> some View {
    let candidates = suggestions(line)
    if !candidates.isEmpty {
      Text(t("Found in your books").uppercased())
        .font(.web(12, .medium))
        .foregroundStyle(palette.slate(500))
      ForEach(candidates.prefix(4), id: \.key) { entry in
        candidateRow(entry, line: line)
      }
    }
    Text((candidates.isEmpty ? t("Record it as") : t("Or record it as")).uppercased())
      .font(.web(12, .medium))
      .foregroundStyle(palette.slate(500))
    if AwWrite.recording {
      Segmented(
        selection: $recipe, options: [SegmentOption("transfer", t("Transfer")), SegmentOption("account", t("Other"))])
      recipeFields(line)
      WebButton(t("Record and match"), loading: busy) { record(line) }
        .disabled(recipe == "transfer" ? otherMoney.isEmpty : (otherAccount ?? "").isEmpty)
    }
    AwFormError(text: error)
  }

  @ViewBuilder
  private func recipeFields(_ line: JSONValue) -> some View {
    let into = line.num("amount") > 0
    if recipe == "transfer" {
      let money = moneyAccounts(line)
      if money.isEmpty {
        AwHint(t("No other bank or cash account."))
      } else {
        Field(into ? t("From") : t("To")) {
          Select(selection: $otherMoney, options: money.map { SelectOption($0.rid, AwPick.label($0)) })
        }
      }
    } else {
      Field(t("Account")) {
        Combobox(
          selection: $otherAccount, options: otherOptions(line), placeholder: t("Choose an account…"),
          searchPlaceholder: t("Search accounts…"))
      }
    }
  }

  private func otherOptions(_ line: JSONValue) -> [ComboOption] {
    let accounts = model.one.records(.accounts).filter { !$0.flag("archived") && $0.rid != line.str("accountId") }
    return AwPick.options(AwPick.byCode(accounts))
  }

  private func suggestions(_ line: JSONValue) -> [AcBookEntry] {
    let one = model.one
    let books = one.acBooks
    let accountId = line.str("accountId")
    let entries = AcBanking.entries(books.lines, accountId)
    let keys = Set(entries.map(\.key))
    var taken = Set<String>()
    for tx in one.records(.bankTransactions) where tx.str("accountId") == accountId {
      if let match = tx.obj("match"), keys.contains(AcBanking.key(match)) { taken.insert(AcBanking.key(match)) }
    }
    var names: [String: String] = [:]
    for client in one.records(.clients) {
      names[client.rid] = "\(client.str("name")) \(client.str("nameAr"))".trimmingCharacters(in: .whitespaces)
    }
    let amount = AcLedger.minor(line.num("amount"), books.precision)
    return AwMatch.suggest(line, amount: amount, entries: entries, taken: taken, names: names)
  }

  private func candidateRow(_ entry: AcBookEntry, line: JSONValue) -> some View {
    let format = model.one.format
    let contact = model.one.contactName(entry.contactId)
    var detail = format.date(entry.date)
    if !contact.isEmpty { detail += " · \(contact)" }
    if !entry.line.text.isEmpty { detail += " · \(entry.line.text)" }
    let shape = RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous)
    return HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("\(t(entry.source.label)) \(entry.number)").font(.web(14, .medium)).foregroundStyle(palette.slate(800))
        Text(detail).font(.web(12)).foregroundStyle(palette.slate(500)).lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Text(format.acMoney(entry.amount))
        .font(.web(14, .semibold, tabular: true))
        .environment(\.layoutDirection, .leftToRight)
      if AwWrite.matching {
        WebButton(t("Match"), size: .sm) { match(entry, line: line) }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(palette.surface, in: shape)
    .border(palette.slate(200), in: shape)
  }

  private func match(_ entry: AcBookEntry, line: JSONValue) {
    let id = line.rid
    let source = entry.source.rawValue
    let recordId = entry.id
    error = nil
    Task {
      let done = await AwSave.perform(model, failed: { error = $0 }) { ctx, _ in
        try AwBanking.matchLine(ctx, id: id, source: source, recordId: recordId)
      }
      if done {
        model.confirm(t("Line matched"))
        self.line = nil
      }
    }
  }

  private func record(_ line: JSONValue) {
    let id = line.rid
    let action: AwCreateAction =
      recipe == "transfer" ? .transfer(otherAccountId: otherMoney) : .account(accountId: otherAccount ?? "")
    let done = recipe == "transfer" ? t("Transfer recorded and matched") : t("Recorded and matched")
    busy = true
    error = nil
    Task {
      let saved = await AwSave.run(model, failed: { error = $0 }) { ctx, tr in
        try AwBanking.createFromLine(ctx, id: id, action: action, tr: tr)
      }
      busy = false
      guard saved != nil else { return }
      model.confirm(done)
      self.line = nil
    }
  }
}

// MARK: A line's menu

/// What a statement line's menu offers on each tab, and what tapping the line does.
struct AwLineActions {
  /// "match", "matched" or "ignored".
  let tab: String
  /// Opens the match panel (lines to match).
  let onMatch: (() -> Void)?
  /// Runs a menu action: "unmatch", "restore", "ignore" or "delete".
  let run: (String) -> Void
}

/// The `…` menu of a statement line: Unmatch, Restore or Ignore, Delete line.
struct AwLineMenu: View {
  let transaction: JSONValue
  let actions: AwLineActions
  @Environment(\.palette) private var palette

  init(transaction: JSONValue, actions: AwLineActions) {
    self.transaction = transaction
    self.actions = actions
  }

  var body: some View {
    let run = actions.run
    DropdownMenu(name: t("Actions for {name}", ["name": transaction.str("description")])) {
      IconView(.moreHorizontal, size: 16).foregroundStyle(palette.slate(600))
    } items: {
      if actions.tab == "matched" {
        DropdownItem(t("Unmatch"), icon: .undo2) { run("unmatch") }
      }
      if actions.tab == "ignored" {
        DropdownItem(t("Restore"), icon: .undo2) { run("restore") }
      } else {
        DropdownItem(t("Ignore"), icon: .eyeOff) { run("ignore") }
      }
      DropdownItem(t("Delete line"), icon: .trash2, danger: true) { run("delete") }
    }
  }
}

@MainActor
enum AwLineAction {
  /// Runs a statement line's menu action, with the web's toast.
  static func run(_ action: String, line: JSONValue, model: AppModel) {
    let id = line.rid
    Task {
      switch action {
      case "unmatch":
        await AwSave.perform(model, done: t("Match removed")) { ctx, _ in try AwBanking.unmatchLine(ctx, id: id) }
      case "restore":
        await AwSave.perform(model, done: t("Line restored")) { ctx, _ in
          try AwBanking.ignoreLine(ctx, id: id, ignored: false)
        }
      case "ignore":
        await AwSave.perform(model, done: t("Line ignored")) { ctx, _ in
          try AwBanking.ignoreLine(ctx, id: id, ignored: true)
        }
      default:
        await AwSave.perform(model, done: t("Statement line deleted")) { ctx, _ in AwBanking.deleteLine(ctx, id: id) }
      }
    }
  }
}
