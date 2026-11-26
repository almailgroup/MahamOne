import Foundation
import MahamKit

// The company's books as the web loads them (`loadLedger` in
// `src/db/accounting.ts`): the chart of accounts, the accounting settings and
// the ledger built from every record on this iPhone, worked out once for each
// change of the mirror.

// MARK: Accounts

/// An account of the chart (`Account`).
struct AcAccount: Identifiable, Sendable {
  let raw: JSONValue
  let id: String
  let code: String
  let name: String
  let nameAr: String?
  /// An `AccountType` ("asset_cash", "expense", …).
  let type: String
  let role: String?
  let archived: Bool

  init(_ raw: JSONValue) {
    self.raw = raw
    id = raw.rid
    code = raw.str("code")
    name = raw.str("name")
    nameAr = raw["nameAr"]?.string
    type = raw.str("type")
    role = raw.text("role")
    archived = raw.flag("archived")
  }

  var group: AcGroup { AcAccountTypes.group(type) }
  var bankInstitution: String { raw.obj("bank")?.str("institution") ?? "" }
}

/// The five groups of the chart (`AccountGroup`).
enum AcGroup: String, CaseIterable, Sendable {
  case asset, liability, equity, income, expense

  /// `ACCOUNT_GROUP_LABELS`.
  var label: String {
    switch self {
    case .asset: "Assets"
    case .liability: "Liabilities"
    case .equity: "Equity"
    case .income: "Income"
    case .expense: "Expenses"
    }
  }
}

/// `src/lib/accounting/account-types.ts`.
enum AcAccountTypes {
  /// `ACCOUNT_TYPE_ORDER`, with each type's label and group.
  static let order: [(type: String, label: String, group: AcGroup)] = [
    ("asset_cash", "Bank & cash", .asset),
    ("asset_receivable", "Accounts receivable", .asset),
    ("asset_current", "Other current asset", .asset),
    ("asset_prepayments", "Prepayment", .asset),
    ("asset_fixed", "Fixed asset", .asset),
    ("asset_non_current", "Non-current asset", .asset),
    ("liability_payable", "Accounts payable", .liability),
    ("liability_credit_card", "Credit card", .liability),
    ("liability_current", "Current liability", .liability),
    ("liability_non_current", "Non-current liability", .liability),
    ("equity", "Equity", .equity),
    ("income", "Income", .income),
    ("income_other", "Other income", .income),
    ("expense_direct_cost", "Cost of sales", .expense),
    ("expense", "Expense", .expense),
    ("expense_depreciation", "Depreciation", .expense),
    ("expense_other", "Other expense", .expense),
  ]

  static func label(_ type: String) -> String {
    order.first { $0.type == type }?.label ?? type
  }

  /// The type's group; a type this version doesn't know counts by its prefix.
  static func group(_ type: String) -> AcGroup {
    if let known = order.first(where: { $0.type == type }) { return known.group }
    if type.hasPrefix("asset") { return .asset }
    if type.hasPrefix("liability") { return .liability }
    if type.hasPrefix("income") { return .income }
    if type.hasPrefix("expense") { return .expense }
    return .equity
  }

  /// Income and expense accounts restart every financial year.
  static func isProfitAndLoss(_ type: String) -> Bool {
    let g = group(type)
    return g == .income || g == .expense
  }

  /// Accounts money is paid into or out of.
  static func isMoneyAccount(_ type: String) -> Bool {
    type == "asset_cash" || type == "liability_credit_card"
  }

  /// Natural balance side, used to show balances as positive figures.
  static func isDebitNormal(_ type: String) -> Bool {
    let g = group(type)
    return g == .asset || g == .expense
  }
}

// MARK: Accounts looked up by code

/// `ACCOUNT_SPECS`: accounts some postings and statements need that have no role.
struct AcSpec: Sendable {
  let code: String
  let name: String
  let nameAr: String
  let type: String
  /// Recognises the account by its English name in other charts (an ICU pattern, case-insensitive).
  let match: String

  static let statutoryReserve = AcSpec(
    code: "3200", name: "Statutory reserve", nameAr: "الاحتياطي الإجباري", type: "equity",
    match: "statutory|legal reserve")
  static let voluntaryReserve = AcSpec(
    code: "3210", name: "Voluntary reserve", nameAr: "الاحتياطي الاختياري", type: "equity",
    match: "voluntary|general reserve")
  static let depreciation = AcSpec(
    code: "6900", name: "Depreciation", nameAr: "الإهلاك", type: "expense_depreciation",
    match: "depreciation|amorti[sz]ation")
  static let financeCosts = AcSpec(
    code: "7100", name: "Finance costs", nameAr: "تكاليف التمويل", type: "expense_other",
    match: "finance cost|interest (expense|paid)|loan interest")
  static let kfas = AcSpec(
    code: "7200", name: "KFAS contribution", nameAr: "حصة مؤسسة الكويت للتقدم العلمي", type: "expense_other",
    match: "kfas")
  static let zakat = AcSpec(code: "7210", name: "Zakat", nameAr: "الزكاة", type: "expense_other", match: "zakat")
  static let nlst = AcSpec(
    code: "7220", name: "National Labour Support Tax", nameAr: "ضريبة دعم العمالة الوطنية", type: "expense_other",
    match: "nlst|labou?r support")
  static let incomeTax = AcSpec(
    code: "7230", name: "Income tax", nameAr: "ضريبة الدخل", type: "expense_other", match: "income tax")
  static let retentionsReceivable = AcSpec(
    code: "1110", name: "Retentions receivable", nameAr: "محتجزات مدينة", type: "asset_current",
    match: "retentions? (receivable|held by customers)")
  static let retentionsPayable = AcSpec(
    code: "2010", name: "Retentions payable", nameAr: "محتجزات دائنة", type: "liability_current",
    match: "retentions? (payable|held from vendors)")
  static let endOfService = AcSpec(
    code: "2700", name: "End-of-service indemnity provision", nameAr: "مخصص مكافأة نهاية الخدمة",
    type: "liability_non_current", match: "end.of.service|indemnity|gratuity")
  static let inventory = AcSpec(
    code: "1200", name: "Inventory", nameAr: "المخزون", type: "asset_current", match: "inventor|stock")
  static let costOfSales = AcSpec(
    code: "5000", name: "Cost of sales", nameAr: "تكلفة المبيعات", type: "expense_direct_cost",
    match: "cost of (sales|goods)")
  static let inventoryAdjustments = AcSpec(
    code: "5300", name: "Inventory adjustments", nameAr: "تسويات المخزون", type: "expense_direct_cost",
    match: "(inventory|stock) (adjustment|write)")
  static let issuedItems = AcSpec(
    code: "6240", name: "Items issued to employees", nameAr: "مواد مصروفة للموظفين", type: "expense",
    match: "uniform|issued to (employees|staff)")

  /// Whether an English name matches the spec's pattern.
  func matches(_ text: String) -> Bool {
    text.range(of: match, options: [.regularExpression, .caseInsensitive]) != nil
  }

  /// `findSpecAccount`: Kuwait charts match by code, others by name; accounts
  /// with a role never match.
  func find(_ accounts: [AcAccount], template: String) -> AcAccount? {
    let candidates = AcSort.liveFirst(accounts.filter { $0.type == type && $0.role == nil })
    if template == "kw", let byCode = candidates.first(where: { $0.code == code }) { return byCode }
    let lower = name.lowercased()
    if let found = candidates.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lower }) {
      return found
    }
    if let found = candidates.first(where: { $0.nameAr?.trimmingCharacters(in: .whitespacesAndNewlines) == nameAr }) {
      return found
    }
    return candidates.first { matches($0.name) }
  }
}

/// Orders the web uses.
enum AcSort {
  /// Active accounts before archived ones, keeping the order otherwise.
  static func liveFirst(_ accounts: [AcAccount]) -> [AcAccount] {
    accounts.filter { !$0.archived } + accounts.filter(\.archived)
  }

  /// By code, as numbers where they are numbers.
  static func byCode(_ a: AcAccount, _ b: AcAccount) -> Bool {
    AcText.compareNumeric(a.code, b.code) == .orderedAscending
  }

  /// Stable sort by code.
  static func sortedByCode(_ accounts: [AcAccount]) -> [AcAccount] {
    accounts.enumerated().sorted { x, y in
      let order = AcText.compareNumeric(x.element.code, y.element.code)
      return order == .orderedSame ? x.offset < y.offset : order == .orderedAscending
    }.map { $0.element }
  }
}

// MARK: Settings

/// The financial year's last day (`fiscalYearEnd`).
struct AcFiscalEnd: Hashable, Sendable {
  let month: Int
  let day: Int
}

/// A period of days, both included.
struct AcRange: Hashable, Sendable {
  let from: String
  let to: String
}

/// `accountingSettings(company)`, with the defaults for companies created before accounting.
struct AcSettings: Sendable {
  let template: String
  let fiscalYearEnd: AcFiscalEnd
  let lockDate: String?
  /// `accounting.vat`, when VAT returns were set up.
  let vat: JSONValue?
  /// `accounting.levies`.
  let levies: JSONValue?
  let country: String

  init(company: JSONValue?) {
    country = company?.obj("address")?.str("country") ?? ""
    if let accounting = company?.obj("accounting") {
      template = accounting.text("template") ?? AcSettings.template(for: country)
      let end = accounting.obj("fiscalYearEnd")
      fiscalYearEnd = AcFiscalEnd(month: Int(end?.number("month") ?? 12), day: Int(end?.number("day") ?? 31))
      lockDate = accounting.text("lockDate")
      vat = accounting.obj("vat")
      levies = accounting.obj("levies")
    } else {
      template = AcSettings.template(for: country)
      fiscalYearEnd = AcFiscalEnd(month: 12, day: 31)
      lockDate = nil
      vat = nil
      levies = nil
    }
  }

  /// `chartTemplateFor`: Kuwait is the default.
  static func template(for country: String) -> String {
    switch country {
    case "GB": "uk"
    case "AE": "ae"
    case "KW", "": "kw"
    default: "generic"
    }
  }
}

// MARK: The books

/// The chart of accounts and the ledger of the company on screen
/// (`CompanyLedger` with its settings).
struct AcBooks: Sendable {
  let accounts: [AcAccount]
  let accountsById: [String: AcAccount]
  let lines: [AcLine]
  let problems: [AcProblem]
  /// Manual and system journals, to tell what kind of entry a line comes from.
  let journals: [JSONValue]
  let settings: AcSettings
  let currency: String
  let precision: Int
  let roles: [String: String]

  static let empty = AcBooks(
    accounts: [], accountsById: [:], lines: [], problems: [], journals: [], settings: AcSettings(company: nil),
    currency: "KWD", precision: 3, roles: [:])

  var fiscalYearEnd: AcFiscalEnd { settings.fiscalYearEnd }

  /// `roleMap`: the account for each automatic posting (active accounts first).
  static func roleMap(_ accounts: [AcAccount]) -> [String: String] {
    var roles: [String: String] = [:]
    for account in AcSort.liveFirst(accounts) {
      if let role = account.role, roles[role] == nil { roles[role] = account.id }
    }
    return roles
  }

  /// Builds the books from the records (`loadLedger`).
  static func build(
    company: JSONValue?, accounts raw: [JSONValue], documents: [JSONValue], payments: [JSONValue],
    journals: [JSONValue], expenses: [JSONValue], products: [JSONValue], clients: [JSONValue],
    movements: [JSONValue], entries: [JSONValue], landedCosts: [JSONValue], issues: [JSONValue]
  ) -> AcBooks {
    let accounts = raw.map(AcAccount.init)
    let settings = AcSettings(company: company)
    let currency = company?.text("currency") ?? "KWD"
    let precision = Money.precision(currency)
    var byId: [String: JSONValue] = [:]
    for doc in documents { byId[doc.rid] = doc }
    var productAccounts: [String: String] = [:]
    var stockItems = Set<String>()
    for product in products {
      if let account = product.text("incomeAccountId") { productAccounts[product.rid] = account }
      if product.str("kind") == "stock" { stockItems.insert(product.rid) }
    }
    let exempt = Set(clients.filter { $0.flag("taxExempt") }.map(\.rid))
    let roles = roleMap(accounts)
    let template = settings.template
    let costOfSales =
      AcSort.liveFirst(accounts).first { $0.role == "cost_of_sales" } ?? AcSpec.costOfSales.find(accounts, template: template)
    var landed = Set<String>()
    for cost in landedCosts {
      for id in landedCostSources(cost, byId[cost.str("billId")], byId[cost.str("targetBillId")], stockItems) {
        landed.insert(cost.str("billId") + ":" + id)
      }
    }
    let stock = AcStockContext(
      products: stockItems, inventoryAccountId: AcSpec.inventory.find(accounts, template: template)?.id,
      costOfSalesAccountId: costOfSales?.id,
      adjustmentAccountId: AcSpec.inventoryAdjustments.find(accounts, template: template)?.id,
      issuedItemsAccountId: AcSpec.issuedItems.find(accounts, template: template)?.id, landedCostLines: landed)
    let ctx = AcLedgerContext(
      companyCurrency: currency, precision: precision, roles: roles, accountIds: Set(accounts.map(\.id)),
      productAccounts: productAccounts, exemptClients: exempt, documents: byId, stock: stock,
      retentionReceivable: AcSpec.retentionsReceivable.find(accounts, template: template)?.id,
      retentionPayable: AcSpec.retentionsPayable.find(accounts, template: template)?.id, clearing: nil)
    let built = AcLedger.build(
      AcLedger.Sources(
        documents: documents, payments: payments, journals: journals, expenses: expenses, movements: movements,
        entries: entries, issues: issues), ctx)
    var accountsById: [String: AcAccount] = [:]
    for account in accounts { accountsById[account.id] = account }
    return AcBooks(
      accounts: accounts, accountsById: accountsById, lines: built.lines, problems: built.problems,
      journals: journals, settings: settings, currency: currency, precision: precision, roles: roles)
  }

  /// `landedCostLinks(...).sourceIds`: the bill lines and charges a landed cost allocates.
  static func landedCostSources(
    _ cost: JSONValue, _ costBill: JSONValue?, _ targetBill: JSONValue?, _ products: Set<String>
  ) -> [String] {
    guard cost.str("status") == "active", let costBill, let targetBill else { return [] }
    guard costBill.str("type") == "bill", targetBill.str("type") == "bill" else { return [] }
    guard AcLedger.isPosted(costBill), AcLedger.isPosted(targetBill) else { return [] }
    func stockLines(_ doc: JSONValue) -> [JSONValue] {
      doc.list("items").filter { $0.str("kind") == "item" && products.contains($0.text("productId") ?? "") }
    }
    let stockIds = Set(stockLines(costBill).map { $0.str("id") })
    let available = Set(
      (costBill.list("items").filter { $0.str("kind") == "item" } + costBill.list("charges")).map { $0.str("id") })
    let sourceIds = cost.list("sourceLineIds").compactMap(\.string).filter {
      available.contains($0) && !stockIds.contains($0)
    }
    let wanted = cost.list("targetLineIds").compactMap(\.string)
    let targets = stockLines(targetBill).filter {
      $0.num("quantity") > 0 && (wanted.isEmpty || wanted.contains($0.str("id")))
    }
    if sourceIds.isEmpty || targets.isEmpty { return [] }
    return sourceIds
  }

  // MARK: Reading

  func account(_ id: String?) -> AcAccount? {
    guard let id else { return nil }
    return accountsById[id]
  }

  /// Sum of each account's lines up to and including `date` (all lines without one).
  func balances(upTo date: String? = nil) -> [String: Int] {
    var out: [String: Int] = [:]
    for line in lines where date == nil || line.date <= date! {
      out[line.accountId, default: 0] += line.amount
    }
    return out
  }

  /// The kind of each journal (`statementContext.kinds`).
  var journalKinds: [String: String] {
    var out: [String: String] = [:]
    for journal in journals { out[journal.rid] = journal.text("kind") ?? "" }
    return out
  }

  /// Journals of the year-end close.
  var yearEndJournals: Set<String> {
    Set(journals.filter { $0.str("kind") == "year_end" }.map(\.rid))
  }
}

/// The books of the company on screen, built once for each change of the mirror.
@MainActor
enum AcBooksCache {
  private static var key: String?
  private static var cached: AcBooks?

  static func books(_ one: OneData) -> AcBooks {
    let key = "\(one.companyId ?? "")|\(one.revision)"
    if key == self.key, let cached { return cached }
    let books = AcBooks.build(
      company: one.company, accounts: one.records(.accounts), documents: one.records(.documents),
      payments: one.records(.payments), journals: one.records(.journals), expenses: one.records(.expenses),
      products: one.records(.products), clients: one.records(.clients), movements: one.records(.stockMovements),
      entries: one.records(.stockEntries), landedCosts: one.records(.landedCosts), issues: one.records(.stockIssues))
    self.key = key
    cached = books
    return books
  }
}

extension OneData {
  /// The company's chart of accounts and ledger (`useLedger`).
  var acBooks: AcBooks { AcBooksCache.books(self) }
}
