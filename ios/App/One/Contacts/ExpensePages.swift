import MahamKit
import SwiftUI

// Expenses (`src/apps/books/pages/purchases/expenses.tsx`): money spent
// without a bill. The web opens each one in a dialog
// (`src/features/purchases/expense-dialog.tsx`); here the dialog shows its
// details to read.

/// An expense's details, as the web's expense dialog shows them.
@MainActor
enum CtExpenseInfo {
  /// The lines of the dialog: amount, category, date, tax, currency, paid
  /// from, rate, vendor or paid to, reference, description, notes, receipt.
  static func rows(_ expense: JSONValue, one: OneData) -> [CtRow] {
    let format = one.format
    let currency = expense.text("currency") ?? format.currency
    let amount = expense.num("amount")
    var rows: [CtRow] = []
    rows.append(CtRow(t("Amount paid"), format.money(amount, currency), strong: true, tabular: true))
    let tax = includedTax(amount, taxes: expense.list("taxes"), currency: currency)
    if tax > 0 {
      rows.append(CtRow(t("Tax included"), t("Includes {amount} tax", ["amount": format.money(tax, currency)])))
    } else if let name = expense.list("taxes").first?.text("name") {
      rows.append(CtRow(t("Tax included"), name))
    }
    rows.append(CtRow(t("Category"), category(expense, one: one)))
    rows.append(CtRow(t("Date"), format.date(expense.text("date"))))
    rows.append(CtRow(t("Currency"), currency == format.currency ? "" : currency))
    rows.append(CtRow(t("Paid from"), paidFrom(expense, one: one)))
    if currency != format.currency, let rate = expense.number("exchangeRate"), rate > 0 {
      rows.append(CtRow(t("Exchange rate"), format.quantity(rate), tabular: true))
    }
    if let vendorId = expense.text("vendorId"), one.record(.clients, vendorId) != nil {
      rows.append(CtRow(t("Vendor"), one.contactName(vendorId)))
    } else {
      rows.append(CtRow(t("Paid to"), expense.str("payee")))
    }
    rows.append(CtRow(t("Reference"), expense.str("reference")))
    rows.append(CtRow(t("Description"), expense.str("description"), multiline: true))
    rows.append(CtRow(t("Notes"), expense.str("notes"), multiline: true))
    let files = one.records(.attachments).filter { $0.str("ownerId") == expense.rid }.map { $0.str("name") }
    rows.append(CtRow(t("Receipt"), files.filter { !$0.isEmpty }.joined(separator: ", ")))
    return rows
  }

  /// The category's name (an expense or asset account), or "—".
  static func category(_ expense: JSONValue, one: OneData) -> String {
    guard let account = one.record(.accounts, expense.str("accountId")) else { return "—" }
    let name = localName(account)
    return name.isEmpty ? "—" : name
  }

  /// The account the money came from; the bank when none is chosen.
  static func paidFrom(_ expense: JSONValue, one: OneData) -> String {
    let account: JSONValue?
    if let id = expense.text("paidFromAccountId") {
      account = one.record(.accounts, id)
    } else {
      account = one.records(.accounts).first { $0.str("role") == "bank" }
    }
    guard let account else { return "—" }
    let name = localName(account)
    return name.isEmpty ? "—" : name
  }

  /// Tax included in the amount (`includedTax`): reverse charge left out.
  nonisolated static func includedTax(_ amount: Double, taxes: [JSONValue], currency: String) -> Double {
    let rates = taxes.filter { $0.str("kind") != "reverse_charge" }.map { $0.num("rate") }
    let sum = rates.reduce(0, +)
    guard sum != 0 else { return 0 }
    let gross = Money.dec(amount)
    let net = gross / (Money.dec(sum) / 100 + 1)
    return Money.toNumber(Money.round(gross - net, Money.precision(currency)))
  }
}

/// `/expenses`: a category filter, search, one row per expense (newest
/// first) and the total; a row opens its details.
struct CtExpensesPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @State private var openId = ""
  @State private var showing = false

  init() {}

  var body: some View {
    let one = model.one
    let format = one.format
    let expenses = self.expenses
    let open = one.record(.expenses, openId)
    let rows = open.map { CtExpenseInfo.rows($0, one: one) } ?? []
    CtListPage(
      title: t("Expenses"), description: t("Receipts and costs paid straight away, without a bill."),
      records: expenses.map(Rec.init), filter: .select(categories(expenses)), initial: "",
      matches: { record, category in category.isEmpty || record.raw.str("accountId") == category },
      searchPlaceholder: t("Search expenses…"), searchText: { CtExpensesPage.searchText($0.raw, one: one) },
      newLabel: t("Record expense"), onNew: { router.push(.newExpense) },
      emptyIcon: .wallet, emptyTitle: t("No expenses yet"),
      emptyDescription: t("Snap a receipt and record what you spent; it goes straight into your books."),
      noMatch: t("No expenses match.")
    ) { record in
      CtExpenseRow(expense: record.raw, format: format) {
        openId = record.id
        showing = true
      }
    } footer: { visible in
      CtExpenseFooter(expenses: visible.map(\.raw), format: format)
    }
    .webDialog(
      isPresented: $showing, title: t("Expense {number}", ["number": open?.str("number") ?? ""]),
      description: t("Something paid straight away, without a bill to pay later.")
    ) {
      CtDetailRows(rows: rows)
    }
  }

  /// Newest first: by date, then number.
  private var expenses: [JSONValue] {
    model.one.records(.expenses).sorted { a, b in
      let (da, db) = (a.str("date"), b.str("date"))
      if da != db { return da > db }
      return ctNumeric(a.str("number"), b.str("number")) == .orderedDescending
    }
  }

  /// "All categories", then the categories in use, by code.
  private func categories(_ expenses: [JSONValue]) -> [SelectOption<String>] {
    let used = Set(expenses.map { $0.str("accountId") })
    let accounts = model.one.records(.accounts)
      .filter { used.contains($0.rid) }
      .sorted { ctNumeric($0.str("code"), $1.str("code")) == .orderedAscending }
    return [SelectOption("", t("All categories"))]
      + accounts.map { SelectOption($0.rid, "\($0.str("code")) \(localName($0))") }
  }

  /// Number, description, reference, who was paid and the category, in English and Arabic.
  static func searchText(_ expense: JSONValue, one: OneData) -> String {
    let vendor = expense.text("vendorId").flatMap { one.record(.clients, $0) }
    let category = one.record(.accounts, expense.str("accountId"))
    return [
      expense.str("number"), expense.str("description"), expense.str("reference"),
      vendor == nil ? expense.str("payee") : "", vendor?.str("name") ?? "", vendor?.str("nameAr") ?? "",
      category?.str("name") ?? "", category?.str("nameAr") ?? "",
    ].joined(separator: " ")
  }
}

/// An expense in the list: its description (or number), "date · number",
/// the category, and the amount.
struct CtExpenseRow: View {
  let expense: JSONValue
  let format: CompanyFormat
  let open: () -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    let one = model.one
    let vendor = expense.text("vendorId").map { one.contactName($0) } ?? ""
    let paidTo = vendor.isEmpty ? expense.str("payee") : vendor
    CtListRow(
      title: expense.text("description") ?? expense.str("number"),
      subtitle: "\(format.date(expense.text("date"))) · \(expense.str("number"))",
      detail: [CtExpenseInfo.category(expense, one: one), paidTo].filter { !$0.isEmpty }.joined(separator: " · "),
      amount: format.money(expense.num("amount"), expense.text("currency")),
      action: open)
  }
}

/// Under the list: how many, and the total per currency.
struct CtExpenseFooter: View {
  let expenses: [JSONValue]
  let format: CompanyFormat
  @Environment(\.palette) private var palette

  var body: some View {
    Text(tp(expenses.count, "{count} expense", "{count} expenses"))
    ForEach(totals) { sum in
      HStack(spacing: 4) {
        Text(t("Total"))
        Text(format.money(sum.total, sum.currency))
          .foregroundStyle(palette.slate(900))
          .fontWeight(.semibold)
          .environment(\.layoutDirection, .leftToRight)
      }
    }
  }

  private var totals: [CurrencyTotal] {
    var sums: [String: Double] = [:]
    var order: [String] = []
    for expense in expenses {
      let currency = expense.text("currency") ?? format.currency
      if sums[currency] == nil { order.append(currency) }
      sums[currency, default: 0] += expense.num("amount")
    }
    return order.map { CurrencyTotal(currency: $0, total: sums[$0] ?? 0, balance: 0) }
  }
}
