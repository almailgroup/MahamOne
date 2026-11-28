import Foundation

// The accounts and journal entries payroll posts (src/db/payroll.ts
// `ensureAccounts`, `moneyAccount`, `postEntry`, `postPayment`,
// `reverseEntry`, `assertOpen`), on the port of src/db/accounting.ts
// `createAccount`, `createJournal`, `newJournalLine` and `saveJournal` with
// `{ system: true }` (the only way payroll saves an entry), and the
// provisions' balances of `loadLedger`.

/// One of the accounts payroll posts to (`PayrollAccountKey`).
enum PwAccountKey: String, CaseIterable, Sendable {
  case salaries, allowances, pifssExpense, eosExpense, leaveExpense, salariesPayable, pifssPayable
  case leaveProvision, eosProvision, advances, otherDeductions
}

/// One side of an entry the payroll posts: positive minor units are a debit, negative a credit (`Posting`).
struct PwPosting: Equatable, Sendable {
  var key: PwAccountKey
  var amount: Int64
  var description: String
}

enum PwLedger {
  struct Spec: Sendable {
    let code: String
    let name: String
    let nameAr: String
    let type: String
  }

  /// `PAYROLL_ACCOUNTS`.
  static let specs: [PwAccountKey: Spec] = [
    .salaries: Spec(code: "6010", name: "Salaries and wages", nameAr: "الرواتب والأجور", type: "expense"),
    .allowances: Spec(code: "6020", name: "Allowances", nameAr: "البدلات", type: "expense"),
    .pifssExpense: Spec(
      code: "6030", name: "PIFSS – employer share", nameAr: "حصة صاحب العمل في التأمينات الاجتماعية", type: "expense"),
    .eosExpense: Spec(code: "6040", name: "End-of-service indemnity", nameAr: "مكافأة نهاية الخدمة", type: "expense"),
    .leaveExpense: Spec(code: "6050", name: "Leave salary", nameAr: "رواتب الإجازات", type: "expense"),
    .salariesPayable: Spec(code: "2300", name: "Salaries payable", nameAr: "رواتب مستحقة", type: "liability_current"),
    .pifssPayable: Spec(
      code: "2310", name: "PIFSS payable", nameAr: "التأمينات الاجتماعية المستحقة", type: "liability_current"),
    .leaveProvision: Spec(
      code: "2320", name: "Leave salary provision", nameAr: "مخصص الإجازات", type: "liability_current"),
    .eosProvision: Spec(
      code: "2700", name: "End-of-service indemnity provision", nameAr: "مخصص مكافأة نهاية الخدمة",
      type: "liability_non_current"),
    .advances: Spec(code: "1320", name: "Staff advances", nameAr: "سلف الموظفين", type: "asset_current"),
    .otherDeductions: Spec(code: "4500", name: "Other income", nameAr: "إيرادات أخرى", type: "income_other"),
  ]

  // MARK: Settings of the company

  /// `accountingSettings(company)`: what is saved, or the defaults of the company's country.
  static func accounting(_ company: JSONValue) -> JSONValue {
    if let saved = WebJS.present(company["accounting"]) { return saved }
    let country = company["address"]?.pwStr("country") ?? ""
    return [
      "template": .string(chartTemplate(country)), "fiscalYearEnd": ["month": 12, "day": 31], "lockDate": .null,
    ]
  }

  /// `chartTemplateFor(country)`.
  static func chartTemplate(_ country: String) -> String {
    if country == "GB" { return "uk" }
    if country == "AE" { return "ae" }
    if country == "KW" || country.isEmpty { return "kw" }
    return "generic"
  }

  /// `assertOpen`: refuses dates in the locked period, in payroll's words.
  static func assertOpen(_ company: JSONValue, _ text: PwText, _ dates: String?...) throws {
    guard let lock = accounting(company).pwText("lockDate"), !lock.isEmpty else { return }
    let locked = dates.contains { date in
      guard let date, !date.isEmpty else { return false }
      return !WebJS.less(lock, date)
    }
    guard locked else { return }
    throw pwFail(
      "The books are locked up to {date}. Change the lock date in Settings → Accounting to post on an earlier date.",
      ["date": text.date(lock, company)])
  }

  /// `assertUnlocked` of accounting.ts (the journal's own check).
  static func assertUnlocked(_ company: JSONValue, _ text: PwText, _ dates: String?...) throws {
    guard let lock = accounting(company).pwText("lockDate"), !lock.isEmpty else { return }
    let locked = dates.contains { date in
      guard let date, !date.isEmpty else { return false }
      return !WebJS.less(lock, date)
    }
    guard locked else { return }
    throw pwFail(
      "The books are locked up to {date}. Change the lock date in Settings → Accounting to edit earlier transactions.",
      ["date": text.date(lock, company)])
  }

  // MARK: Accounts

  /// `roleMap(accounts)`: the account for each role, active ones first.
  static func roleMap(_ accounts: [JSONValue]) -> [String: String] {
    let ordered = PwSort.stable(accounts) { a, b in
      (a.pwTruthy("archived") ? 1 : 0) - (b.pwTruthy("archived") ? 1 : 0)
    }
    var roles: [String: String] = [:]
    for account in ordered {
      guard let role = account.pwText("role"), !role.isEmpty, roles[role] == nil else { continue }
      roles[role] = account.pwId
    }
    return roles
  }

  /// `findSystemAccount`.
  static func findSystemAccount(_ accounts: [JSONValue], _ spec: Spec, _ template: String) -> JSONValue? {
    func named(_ a: JSONValue) -> Bool {
      WebJS.trim(a.pwStr("name")).lowercased() == spec.name.lowercased()
        || (a.pwText("nameAr").map(WebJS.trim) == spec.nameAr)
    }
    let usable = accounts.filter { !$0.pwTruthy("archived") && $0.pwStr("type") == spec.type }
    return usable.first { $0.pwStr("code") == spec.code && (template == "kw" || named($0)) }
      ?? usable.first(where: named)
  }

  /// `payrollAccount`: the one chosen in the settings, else the one found by code.
  static func payrollAccount(_ accounts: [JSONValue], _ settings: JSONValue, _ key: PwAccountKey, _ template: String)
    -> JSONValue?
  {
    let chosen = settings["accounts"]?[key.rawValue]?.string ?? ""
    let account = chosen.isEmpty ? nil : accounts.first { $0.pwId == chosen && !$0.pwTruthy("archived") }
    return account ?? (specs[key].flatMap { findSystemAccount(accounts, $0, template) })
  }

  /// `freeAccountCode`.
  static func freeCode(_ accounts: [JSONValue], _ wanted: String) -> String {
    let taken = Set(accounts.map { $0.pwStr("code") })
    if !taken.contains(wanted) { return wanted }
    let width = wanted.utf16.count
    var n = (Int(wanted) ?? 0) + 1
    while true {
      let code = WebJS.padStart(String(n), width)
      if !taken.contains(code) { return code }
      n += 1
    }
  }

  /// `ensureAccounts`: the account of each key, made when the company lacks it.
  static func ensure(
    _ ctx: WriteContext, _ company: JSONValue, _ settings: JSONValue, _ keys: [PwAccountKey],
    overrides: [PwAccountKey: String?] = [:]
  ) -> [PwAccountKey: String] {
    var accounts = ctx.pwAll("accounts")
    let template = accounting(company).pwStr("template")
    var out: [PwAccountKey: String] = [:]
    for key in keys {
      let wanted = (overrides[key] ?? nil) ?? ""
      let chosen = wanted.isEmpty ? nil : accounts.first { $0.pwId == wanted && !$0.pwTruthy("archived") }
      if let account = chosen ?? payrollAccount(accounts, settings, key, template) {
        out[key] = account.pwId
        continue
      }
      guard let spec = specs[key] else { continue }
      let account = createAccount(
        ctx, code: freeCode(accounts, spec.code), name: spec.name, nameAr: spec.nameAr, type: spec.type)
      ctx.put("accounts", account)
      accounts.append(account)
      PwLog.add(
        ctx, "account", account.pwId, "created", "Account {code} {name} created",
        vars: ["code": .text(account.pwStr("code")), "name": .text(account.pwStr("name"))],
        arabic: ["name": account.pwText("nameAr")])
      out[key] = account.pwId
    }
    return out
  }

  /// `createAccount(companyId, { code, name, nameAr, type })`.
  static func createAccount(_ ctx: WriteContext, code: String, name: String, nameAr: String, type: String)
    -> JSONValue
  {
    [
      "id": .string(ctx.newId()), "companyId": .string(ctx.companyId), "code": .string(code),
      "name": .string(name), "type": .string(type), "description": "", "role": .null, "bank": .null,
      "archived": false, "createdAt": .string(ctx.stamp), "updatedAt": .string(ctx.stamp),
      "nameAr": .string(nameAr),
    ]
  }

  /// `moneyAccount`: the bank or cash account money is paid from.
  static func moneyAccount(_ ctx: WriteContext, _ ids: String?...) throws -> JSONValue {
    let accounts = ctx.pwAll("accounts")
    let wanted = ids.compactMap { $0 }.first { !$0.isEmpty }
    let chosen = wanted.flatMap { id in accounts.first { $0.pwId == id } }
    let bank = roleMap(accounts)["bank"]
    let candidate = chosen ?? accounts.first(where: { $0.pwId == bank && bank != nil })
    guard let account = candidate, account.pwStr("type") == "asset_cash", !account.pwTruthy("archived") else {
      throw pwFail("Choose the bank account the money is paid from.")
    }
    return account
  }

  // MARK: Journals

  /// `newJournalLine(overrides)`.
  static func line(
    _ ctx: WriteContext, accountId: String, debit: Double = 0, credit: Double = 0, description: String,
    contactId: JSONValue = .null
  ) -> JSONValue {
    [
      "id": .string(ctx.newId()), "accountId": .string(accountId), "description": .string(description),
      "debit": .number(debit), "credit": .number(credit), "contactId": contactId,
    ]
  }

  /// `createJournal(companyId, overrides)`: the journal's id, then the two
  /// default lines the overrides replace (their ids are used up all the same).
  static func journal(_ ctx: WriteContext, _ overrides: [String: JSONValue]) -> JSONValue {
    var fields: [String: JSONValue] = [
      "id": .string(ctx.newId()), "companyId": .string(ctx.companyId), "number": "", "date": .string(ctx.today),
      "reference": "", "notes": "", "status": "posted",
    ]
    _ = line(ctx, accountId: "", description: "")
    _ = line(ctx, accountId: "", description: "")
    fields["createdAt"] = .string(ctx.stamp)
    fields["updatedAt"] = .string(ctx.stamp)
    for (key, value) in overrides { fields[key] = value }
    return .object(fields)
  }

  /// `saveJournal(input, { system: true })`.
  @discardableResult
  static func save(_ ctx: WriteContext, _ input: JSONValue, _ text: PwText) throws -> JSONValue {
    guard let company = ctx.get("companies", input.pwStr("companyId")) else { throw pwFail("Company not found") }
    let existing = ctx.get("journals", input.pwId)
    try assertUnlocked(company, text, input.pwText("date"), existing?.pwText("date"))
    if let existing, WebJS.truthy(existing["vatReturnId"]) {
      throw pwFail("This entry closes a VAT return. Undo the return to change it.")
    }
    let lines = input.pwList("lines").filter { l in
      !l.pwStr("accountId").isEmpty && (l.pwNum("debit") != 0 || l.pwNum("credit") != 0)
    }
    if lines.contains(where: { $0.pwNum("debit") < 0 || $0.pwNum("credit") < 0 }) {
      throw pwFail("Amounts must be positive. Use the other column to reverse.")
    }
    if lines.contains(where: { $0.pwNum("debit") != 0 && $0.pwNum("credit") != 0 }) {
      throw pwFail("A line can have a debit or a credit, not both.")
    }
    if lines.count < 2 { throw pwFail("A journal needs at least two lines with amounts.") }
    let p = PwM.places(company.pwStr("currency"))
    let debit = PwM.total(lines.map { $0.pwNum("debit") })
    let credit = PwM.total(lines.map { $0.pwNum("credit") })
    if PwM.round(debit - credit, p) != 0 { throw pwFail("Debits and credits must be equal.") }
    for l in lines {
      let account = ctx.get("accounts", l.pwStr("accountId"))
      if account == nil || account?.pwStr("companyId") != company.pwId {
        throw pwFail("Choose an account on every line.")
      }
    }
    var journal = input.pwMerging([
      "lines": .array(lines), "number": .string(WebJS.trim(input.pwStr("number"))),
    ])
    if journal.pwStr("number").isEmpty {
      let stored = WebJS.present(company["numbering"]?["journal"])
      let rule = NumberingRule(stored ?? Numbering.defaultRules()["journal"]!.raw)
      let taken = Set(
        ctx.all("journals").filter { $0.pwStr("companyId") == company.pwId && $0.pwId != journal.pwId }
          .map { $0.pwStr("number").lowercased() })
      let allocated = Numbering.allocateNumber(rule, journal.pwStr("date")) { taken.contains($0.lowercased()) }
      journal.set("number", .string(allocated.number))
      var numbering = WebJS.spread(company["numbering"])
      numbering["journal"] = allocated.rule.raw
      ctx.put("companies", company.pwWith("numbering", .object(numbering)))
    }
    journal.set("updatedAt", .string(ctx.stamp))
    if existing == nil { journal.set("createdAt", .string(ctx.stamp)) }
    ctx.put("journals", journal)
    PwLog.add(
      ctx, "journal", journal.pwId, existing == nil ? "created" : "updated",
      existing == nil ? "Journal {number} created" : "Journal {number} updated",
      vars: ["number": .text(journal.pwStr("number"))])
    return journal
  }

  /// `balanced(list)`.
  static func balanced(_ list: [PwPosting]) -> Bool {
    list.reduce(Int64(0)) { $0 + $1.amount } == 0
  }

  /// `postEntry`: one payroll entry of postings, or nil when there are none.
  static func postEntry(
    _ ctx: WriteContext, _ company: JSONValue, _ accounts: [PwAccountKey: String], _ list: [PwPosting],
    date: String, sourceId: String, reference: String, text: PwText
  ) throws -> JSONValue? {
    if list.isEmpty { return nil }
    if !balanced(list) { throw pwFail("Debits and credits must be equal.") }
    let p = PwM.places(company.pwStr("currency"))
    let lines = list.map { x in
      line(
        ctx, accountId: accounts[x.key] ?? "", debit: x.amount > 0 ? PwM.fromMinor(x.amount, p) : 0,
        credit: x.amount < 0 ? PwM.fromMinor(-x.amount, p) : 0, description: text.t(x.description))
    }
    let entry = journal(
      ctx,
      [
        "date": .string(date), "sourceId": .string(sourceId), "reference": .string(reference),
        "kind": "payroll", "status": "posted", "lines": .array(lines),
      ])
    return try save(ctx, entry, text)
  }

  /// `postPayment`: money paid from the bank against a liability.
  static func postPayment(
    _ ctx: WriteContext, debit: String, bank: String, amount: Double, date: String, sourceId: String,
    reference: String, text: PwText
  ) throws -> JSONValue {
    let lines: [JSONValue] = [
      line(ctx, accountId: debit, debit: amount, description: reference),
      line(ctx, accountId: bank, credit: amount, description: reference),
    ]
    let entry = journal(
      ctx,
      [
        "date": .string(date), "kind": "payroll", "sourceId": .string(sourceId), "reference": .string(reference),
        "status": "posted", "lines": .array(lines),
      ])
    return try save(ctx, entry, text)
  }

  /// `reverseEntry`: an opposite entry on the same date; nil when there is none to reverse.
  static func reverseEntry(_ ctx: WriteContext, _ journalId: String?, text: PwText) throws -> String? {
    guard let journalId, !journalId.isEmpty, let original = ctx.get("journals", journalId) else { return nil }
    let lines = original.pwList("lines").map { l in
      line(
        ctx, accountId: l.pwStr("accountId"), debit: l.pwNum("credit"), credit: l.pwNum("debit"),
        description: l.pwStr("description"), contactId: l["contactId"] ?? .null)
    }
    let entry = journal(
      ctx,
      [
        "date": original["date"] ?? .null, "kind": "payroll",
        "sourceId": WebJS.present(original["sourceId"]) ?? .null, "reversalOf": .string(original.pwId),
        "reference": .string(text.t("Reversal of {number}", ["number": original.pwStr("number")])),
        "status": "posted", "lines": .array(lines),
      ])
    return try save(ctx, entry, text).pwId
  }

  // MARK: Balances

  /// `ledgerBalances` for the provision accounts: what the company's posted
  /// entries hold on them at the end of a day (debit positive, minor units).
  /// The ledger's other sources (documents, payments, expenses, stock) never
  /// post to them in the web's chart; when one of the company's records names
  /// one of these accounts all the same, the iPhone can't work the balance
  /// out exactly, and refuses rather than post a different amount.
  static func balances(_ ctx: WriteContext, _ company: JSONValue, _ ids: [String], on date: String) throws
    -> [String: Int64]
  {
    let wanted = Set(ids)
    let p = PwM.places(company.pwStr("currency"))
    let accounts = ctx.pwAll("accounts")
    let roles = Set(roleMap(accounts).values)
    let elsewhere = ["documents", "payments", "expenses", "products", "landedCosts", "stockEntries", "stockIssues"]
    let named =
      !wanted.isDisjoint(with: roles)
      || elsewhere.contains { table in ctx.pwAll(table).contains { mentions($0, wanted) } }
    if named {
      throw pwFail(
        "The provision accounts are used by other entries of the books, so this pay run can’t be approved on this iPhone yet."
      )
    }
    var out: [String: Int64] = [:]
    for id in ids { out[id] = 0 }
    for journal in ctx.pwAll("journals") where journal.pwStr("status") == "posted" {
      let lines = journal.pwList("lines").map { l in
        (account: l.pwStr("accountId"), amount: PwM.minor(l.pwNum("debit"), p) - PwM.minor(l.pwNum("credit"), p))
      }.filter { $0.amount != 0 }
      // An entry that doesn't balance is a problem of the ledger, left out of it.
      guard lines.reduce(Int64(0), { $0 + $1.amount }) == 0 else { continue }
      guard !WebJS.less(date, journal.pwStr("date")) else { continue }
      for l in lines where wanted.contains(l.account) {
        out[l.account, default: 0] += l.amount
      }
    }
    return out
  }

  /// Whether a record names one of the accounts anywhere.
  private static func mentions(_ value: JSONValue, _ ids: Set<String>) -> Bool {
    switch value {
    case .string(let text): return ids.contains(text)
    case .array(let items): return items.contains { mentions($0, ids) }
    case .object(let fields): return fields.values.contains { mentions($0, ids) }
    default: return false
    }
  }
}
