import Foundation

// What the stock writes need from the company's accounting
// (src/db/chart-setup.ts, src/db/accounting.ts, src/lib/accounting/charts.ts,
// src/db/posting.ts): the lock date, the accounts stock posts to (created
// when the chart doesn't have them) and the posting snapshots of documents
// in a locked period.

/// The company's accounting settings as the stock writes read them
/// (`accountingSettings(company)`).
struct IwAccountingSettings {
  /// The chart template ("kw", "generic", "uk", "ae"), as stored.
  let template: String?
  /// The lock date when there is one (`lockDate`, a non-empty day).
  let lockDate: String?

  init(_ company: JSONValue) {
    if let accounting = WebJS.present(company["accounting"]) {
      template = accounting["template"]?.string
      let lock = accounting["lockDate"]?.string ?? ""
      lockDate = lock.isEmpty ? nil : lock
    } else {
      template = Self.templateFor(company["address"]?["country"]?.string ?? "")
      lockDate = nil
    }
  }

  /// `chartTemplateFor(country)`.
  static func templateFor(_ country: String) -> String {
    if country == "GB" { return "uk" }
    if country == "AE" { return "ae" }
    if country == "KW" || country.isEmpty { return "kw" }
    return "generic"
  }

  /// Whether a day falls on or before the lock date.
  func locks(_ date: JSONValue?) -> Bool {
    guard let lockDate else { return false }
    return IwRecords.onOrBefore(date, lockDate)
  }
}

enum IwAccounts {
  // MARK: The lock date

  /// `LockedPeriodError`: the web's words, the lock date in the company's format.
  static func lockedPeriod(_ lockDate: String, _ company: JSONValue) -> WriteFailure {
    let format = Format.DateFormat(company["dateFormat"]?.string ?? "dd/MM/yyyy")
    let locale = company["locale"]?.string ?? ""
    let date = Format.date(lockDate, format: format, locale: FormatLocale(locale.isEmpty ? "en-KW" : locale))
    return WriteFailure(
      "The books are locked up to {date}. Change the lock date in Settings → Accounting to edit earlier transactions.",
      ["date": date])
  }

  /// `assertUnlocked(company, ...dates)`.
  static func assertUnlocked(_ company: JSONValue, _ dates: JSONValue?...) throws {
    let settings = IwAccountingSettings(company)
    guard let lock = settings.lockDate else { return }
    for date in dates {
      guard let text = date?.string, !text.isEmpty else { continue }
      if !WebJS.less(lock, text) { throw lockedPeriod(lock, company) }
    }
  }

  // MARK: Accounts

  /// An account the app looks up by code or name (`AccountSpec`).
  struct Spec {
    let code: String
    let name: String
    let nameAr: String
    let type: String
    /// The English name in another chart (the spec's `match` expression).
    let matches: (String) -> Bool
  }

  /// `/a|b/i.test(name)` for plain alternatives.
  private static func contains(_ name: String, _ words: [String]) -> Bool {
    let lower = name.lowercased()
    return words.contains { lower.contains($0) }
  }

  /// The specs of `ACCOUNT_SPECS` the stock writes use.
  static func spec(_ key: String) -> Spec? {
    switch key {
    case "inventory":
      return Spec(code: "1200", name: "Inventory", nameAr: "المخزون", type: "asset_current") {
        contains($0, ["inventor", "stock"])
      }
    case "costOfSales":
      return Spec(code: "5000", name: "Cost of sales", nameAr: "تكلفة المبيعات", type: "expense_direct_cost") {
        contains($0, ["cost of sales", "cost of goods"])
      }
    case "inventoryAdjustments":
      return Spec(code: "5300", name: "Inventory adjustments", nameAr: "تسويات المخزون", type: "expense_direct_cost") {
        contains($0, ["inventory adjustment", "inventory write", "stock adjustment", "stock write"])
      }
    case "issuedItems":
      return Spec(code: "6240", name: "Items issued to employees", nameAr: "مواد مصروفة للموظفين", type: "expense") {
        contains($0, ["uniform", "issued to employees", "issued to staff"])
      }
    default:
      return nil
    }
  }

  /// `findSpecAccount(accounts, key, template)`: Kuwait charts by code,
  /// others by name; accounts with a role never match.
  static func findSpecAccount(_ accounts: [JSONValue], _ key: String, template: String?) -> JSONValue? {
    guard let spec = spec(key) else { return nil }
    let candidates = IwRecords.archivedLast(
      accounts.filter { $0["type"]?.string == spec.type && !$0.iwTruthy("role") })
    if template == "kw", let byCode = candidates.first(where: { $0["code"]?.string == spec.code }) {
      return byCode
    }
    if let byName = candidates.first(where: { WebJS.trim($0.iwText("name")).lowercased() == spec.name.lowercased() }) {
      return byName
    }
    if let byArabic = candidates.first(where: { $0["nameAr"]?.string.map(WebJS.trim) == spec.nameAr }) {
      return byArabic
    }
    return candidates.first { spec.matches($0.iwText("name")) }
  }

  /// `freeCode(accounts, wanted)`: the spec's code when free, else the next one after it.
  static func freeCode(_ accounts: [JSONValue], _ wanted: String) -> String {
    let taken = Set(accounts.compactMap { $0["code"]?.string })
    if !taken.contains(wanted) { return wanted }
    guard let base = Int(wanted) else {
      var i = 2
      while taken.contains("\(wanted)-\(i)") { i += 1 }
      return "\(wanted)-\(i)"
    }
    let width = wanted.utf16.count
    var next = base + 1
    while taken.contains(WebJS.padStart(String(next), width)) { next += 1 }
    return WebJS.padStart(String(next), width)
  }

  /// `roleMap(accounts)`: the account of each automatic posting, active ones first.
  static func roleMap(_ accounts: [JSONValue]) -> [String: String] {
    var roles: [String: String] = [:]
    for account in IwRecords.archivedLast(accounts) {
      guard let role = account["role"]?.string, !role.isEmpty, roles[role] == nil else { continue }
      roles[role] = account.iwText("id")
    }
    return roles
  }

  /// `ensureSpecAccount(company, key)`: the account, created when missing.
  @discardableResult
  static func ensureSpecAccount(_ ctx: WriteContext, _ company: JSONValue, _ key: String) -> JSONValue? {
    guard let spec = spec(key) else { return nil }
    let companyId = company.iwId
    let accounts = IwRecords.company(ctx, "accounts", companyId)
    let template = IwAccountingSettings(company).template
    if let found = findSpecAccount(accounts, key, template: template) { return found }
    let stamp = JSONValue.string(ctx.stamp)
    let code = freeCode(accounts, spec.code)
    let account: JSONValue = .object([
      "id": .string(ctx.newId()),
      "companyId": .string(companyId),
      "code": .string(code),
      "name": .string(spec.name),
      "type": .string(spec.type),
      "description": "",
      "role": .null,
      "bank": .null,
      "archived": false,
      "createdAt": stamp,
      "updatedAt": stamp,
      "nameAr": .string(spec.nameAr),
    ])
    ctx.put("accounts", account)
    ctx.logActivity(
      entity: "account", entityId: account.iwId, action: "created",
      message: ActivityMessage(
        "Account {code} {name} created", vars: ["code": code, "name": spec.name], arabic: ["name": spec.nameAr]))
    return account
  }

  /// The accounts stock posts to (`stockAccounts`): cost of sales is the
  /// account with that role when there is one.
  struct StockAccounts {
    var inventory: JSONValue?
    var costOfSales: JSONValue?
    var adjustments: JSONValue?
    var issuedItems: JSONValue?
  }

  static func stockAccounts(_ accounts: [JSONValue], template: String?) -> StockAccounts {
    let live = IwRecords.archivedLast(accounts)
    return StockAccounts(
      inventory: findSpecAccount(accounts, "inventory", template: template),
      costOfSales: live.first { $0["role"]?.string == "cost_of_sales" }
        ?? findSpecAccount(accounts, "costOfSales", template: template),
      adjustments: findSpecAccount(accounts, "inventoryAdjustments", template: template),
      issuedItems: findSpecAccount(accounts, "issuedItems", template: template))
  }

  /// `ensureStockAccounts(company)`: inventory (1200), cost of sales (5000)
  /// and inventory adjustments (5300), created when the chart doesn't have them.
  static func ensureStockAccounts(_ ctx: WriteContext, _ company: JSONValue) {
    let accounts = IwRecords.company(ctx, "accounts", company.iwId)
    let found = stockAccounts(accounts, template: IwAccountingSettings(company).template)
    if found.inventory == nil { ensureSpecAccount(ctx, company, "inventory") }
    if found.costOfSales == nil && roleMap(accounts)["cost_of_sales"] == nil {
      ensureSpecAccount(ctx, company, "costOfSales")
    }
    if found.adjustments == nil { ensureSpecAccount(ctx, company, "inventoryAdjustments") }
  }

  /// `ensureIssueAccounts(company)`: the stock accounts and the expense of
  /// items issued to employees (6240).
  static func ensureIssueAccounts(_ ctx: WriteContext, _ company: JSONValue) {
    ensureStockAccounts(ctx, company)
    let accounts = IwRecords.company(ctx, "accounts", company.iwId)
    if stockAccounts(accounts, template: IwAccountingSettings(company).template).issuedItems == nil {
      ensureSpecAccount(ctx, company, "issuedItems")
    }
  }

  // MARK: Posting snapshots

  /// `postingSnapshot(doc, taxExempt, productAccounts)`.
  static func postingSnapshot(_ doc: JSONValue, taxExempt: Bool, productAccounts: [String: JSONValue]) -> JSONValue {
    var accounts: [String: JSONValue] = [:]
    let type = doc["type"]?.string
    if type == "invoice" || type == "credit" {
      for item in doc.iwList("items") {
        let productId = item["productId"]
        let account: JSONValue? = WebJS.truthy(productId) ? productAccounts[WebJS.string(productId)] : nil
        if item["kind"]?.string != "heading", WebJS.truthy(account), let account {
          accounts[WebJS.string(item["id"])] = account
        }
      }
    }
    return .object(["taxExempt": .bool(taxExempt), "accounts": .object(accounts)])
  }

  /// `freezeLockedPostings(company, affected)`: issued documents on or
  /// before the lock date that still follow the settings get a snapshot of
  /// what they post with now.
  static func freezeLockedPostings(_ ctx: WriteContext, _ company: JSONValue, affected: (JSONValue) -> Bool) {
    let settings = IwAccountingSettings(company)
    guard let lock = settings.lockDate else { return }
    let companyId = company.iwId
    let docs = IwRecords.company(ctx, "documents", companyId).filter { doc in
      !WebJS.truthy(doc["posting"]) && IwSources.isPosted(doc) && IwRecords.onOrBefore(doc["issueDate"], lock)
        && affected(doc)
    }
    if docs.isEmpty { return }
    let exempt = Set(
      IwRecords.company(ctx, "clients", companyId).filter { $0.iwTruthy("taxExempt") }.map(\.iwId))
    var accounts: [String: JSONValue] = [:]
    for product in IwRecords.company(ctx, "products", companyId) {
      accounts[product.iwId] = product["incomeAccountId"] ?? .null
    }
    for doc in docs {
      let clientExempt = exempt.contains(WebJS.string(doc["clientId"]))
      ctx.put("documents", doc.iwWith("posting", postingSnapshot(doc, taxExempt: clientExempt, productAccounts: accounts)))
    }
  }
}
