import Foundation

/// The port of the web's chart of accounts writes (src/db/accounting.ts:
/// `createAccount`, `cleanBankDetails`, `saveAccount`, `ensureSpecAccount`,
/// `accountInUse`, `deleteAccount`).
public enum AwAccounts {
  /// `createAccount(companyId, overrides)` for a form: a new id, stamped now.
  public static func blank(
    companyId: String, overrides: [String: JSONValue] = [:], now: Date = Date(), id: String = newId()
  ) -> JSONValue {
    let stamp = Defaults.nowStamp(now)
    let base: [String: JSONValue] = [
      "id": .string(id), "companyId": .string(companyId), "code": .string(""), "name": .string(""),
      "type": .string("expense"), "description": .string(""), "role": .null, "bank": .null, "archived": .bool(false),
      "createdAt": .string(stamp), "updatedAt": .string(stamp),
    ]
    return .object(base.merging(overrides) { _, new in new })
  }

  /// `createAccount` inside an action: the next id of the action, stamped at its moment.
  static func create(_ ctx: WriteContext, companyId: String, _ overrides: [String: JSONValue]) -> JSONValue {
    blank(companyId: companyId, overrides: overrides, now: ctx.now, id: ctx.newId())
  }

  /// `cleanBankDetails(bank)`: the IBAN grouped in fours, the BIC in capitals; nil when all empty.
  public static func cleanBankDetails(_ bank: JSONValue?) -> JSONValue {
    guard let bank, WebJS.truthy(bank) else { return .null }
    let iban = Kuwait.compactIban(bank.awStr("iban"))
    let cleaned: [String: String] = [
      "institution": WebJS.trim(bank.awStr("institution")),
      "accountNumber": WebJS.trim(bank.awStr("accountNumber")),
      "iban": iban.isEmpty ? "" : Kuwait.formatIban(iban),
      "bic": WebJS.trim(bank.awStr("bic")).uppercased(),
    ]
    guard cleaned.values.contains(where: { !$0.isEmpty }) else { return .null }
    return .object(cleaned.mapValues(JSONValue.string))
  }

  /// `saveAccount(input)`: adds or updates an account of the chart.
  @discardableResult
  public static func save(_ ctx: WriteContext, _ input: JSONValue) throws -> JSONValue {
    var fields = input.awFields
    let nameAr = input["nameAr"]?.string.map(WebJS.trim)
    fields.removeValue(forKey: "nameAr")
    let code = WebJS.trim(input.awStr("code"))
    let name = WebJS.trim(input.awStr("name"))
    fields["code"] = .string(code)
    fields["name"] = .string(name)
    if let nameAr, !nameAr.isEmpty { fields["nameAr"] = .string(nameAr) }
    let bank = cleanBankDetails(input["bank"])
    fields["bank"] = bank
    if name.isEmpty { throw WriteFailure("Enter a name for the account.") }
    if code.isEmpty { throw WriteFailure("Enter a code for the account.") }
    if let iban = bank["iban"]?.string, !iban.isEmpty, !Kuwait.isValidIban(iban) {
      throw WriteFailure("The IBAN is not valid. Check it against a bank statement.")
    }
    let id = input.awId
    let companyId = input.awStr("companyId")
    let sameCode = ctx.all("accounts").filter {
      $0.awStr("companyId") == companyId && $0.awStr("code") == code && $0.awId != id
    }
    if !sameCode.isEmpty {
      throw WriteFailure("Code {code} is already used by another account.", ["code": code])
    }
    let existing = ctx.get("accounts", id)
    if let existing, existing.awTruthy("role"), existing["type"] != input["type"] {
      throw WriteFailure("The type of an account used for automatic postings cannot change.")
    }
    if let existing, existing.awTruthy("role"), input.awTruthy("archived") {
      throw WriteFailure("Accounts used for automatic postings cannot be archived.")
    }
    fields["updatedAt"] = .string(ctx.stamp)
    let account = JSONValue.object(fields)
    ctx.put("accounts", account)
    let vars = ["code": code, "name": name]
    ctx.logActivity(
      entity: "account", entityId: id, action: existing != nil ? "updated" : "created",
      message: ActivityMessage(
        existing != nil ? "Account {code} {name} updated" : "Account {code} {name} created", vars: vars,
        arabic: ["name": account["nameAr"]?.string]))
    return account
  }

  /// `ensureSpecAccount(company, key)`: the company's account for a spec,
  /// created (and logged) when the chart doesn't have it.
  @discardableResult
  public static func ensureSpec(_ ctx: WriteContext, _ company: JSONValue, _ spec: AwSpec) -> JSONValue {
    let accounts = AwBooks.records(ctx, "accounts", company.awId)
    if let found = spec.find(accounts, template: AwBooks.template(company)) { return found }
    let account = create(
      ctx, companyId: company.awId,
      [
        "code": .string(AwSpec.freeCode(accounts, spec.code)), "name": .string(spec.name),
        "nameAr": .string(spec.nameAr), "type": .string(spec.type),
      ])
    ctx.put("accounts", account)
    ctx.logActivity(
      entity: "account", entityId: account.awId, action: "created",
      message: ActivityMessage(
        "Account {code} {name} created", vars: ["code": account.awStr("code"), "name": account.awStr("name")],
        arabic: ["name": account["nameAr"]?.string]))
    return account
  }

  /// `accountInUse(account)`: whether any transaction or setting refers to it.
  public static func inUse(_ ctx: WriteContext, _ account: JSONValue) -> Bool {
    if account.awTruthy("role") { return true }
    let id = account.awId
    let companyId = account.awStr("companyId")
    func any(_ table: String, _ test: (JSONValue) -> Bool) -> Bool {
      AwBooks.records(ctx, table, companyId).contains(where: test)
    }
    if any("journals", { $0.awList("lines").contains { $0.awStr("accountId") == id } }) { return true }
    if any("payments", { $0.awStr("accountId") == id }) { return true }
    if any("products", { $0.awStr("incomeAccountId") == id }) { return true }
    let usedByDocument: (JSONValue) -> Bool = { doc in
      if doc.awList("items").contains(where: { $0.awStr("accountId") == id }) { return true }
      let posted = WebJS.spread(doc["posting"]?["accounts"])
      return posted.values.contains(.string(id))
    }
    if any("documents", usedByDocument) { return true }
    if any("expenses", { $0.awStr("accountId") == id || $0.awStr("paidFromAccountId") == id }) { return true }
    let usedByAsset: (JSONValue) -> Bool = { asset in
      ["assetAccountId", "accumulatedAccountId", "expenseAccountId", "paidFromAccountId"].contains {
        asset.awStr($0) == id
      }
    }
    return any("assets", usedByAsset)
  }

  /// `deleteAccount(id)`: only an account nothing refers to.
  public static func delete(_ ctx: WriteContext, id: String) throws {
    guard let account = ctx.get("accounts", id) else { return }
    if inUse(ctx, account) {
      throw WriteFailure("This account is used by transactions or settings. Archive it instead.")
    }
    ctx.delete("accounts", id)
    ctx.logActivity(
      entity: "account", entityId: id, action: "deleted",
      message: ActivityMessage(
        "Account {code} {name} deleted", vars: ["code": account.awStr("code"), "name": account.awStr("name")],
        arabic: ["name": account["nameAr"]?.string]))
  }
}
