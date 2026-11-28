import Foundation

// What the accounting writes share (src/db/accounting.ts, src/db/chart-setup.ts,
// src/lib/accounting/charts.ts and account-types.ts): reading raw records the
// way JavaScript reads them, the accounting settings and the lock date, the
// account for each automatic posting, the accounts looked up by code, and
// the activity log with numbers among its values.

// MARK: Reading records

extension JSONValue {
  /// A text field ("" when missing or not text).
  func awStr(_ key: String) -> String { self[key]?.string ?? "" }

  /// A text field JavaScript reads as true (not missing, null or empty).
  func awText(_ key: String) -> String? {
    guard let value = self[key]?.string, !value.isEmpty else { return nil }
    return value
  }

  /// A number field (0 when missing or not a number).
  func awNum(_ key: String) -> Double { self[key]?.double ?? 0 }

  /// A field JavaScript reads as true.
  func awTruthy(_ key: String) -> Bool { WebJS.truthy(self[key]) }

  /// A list field (empty when missing).
  func awList(_ key: String) -> [JSONValue] { self[key]?.array ?? [] }

  /// The record's fields (`{ ...record }`).
  var awFields: [String: JSONValue] { WebJS.spread(self) }

  /// The record's id.
  var awId: String { awStr("id") }
}

/// `{ ...base, ...overrides }` where a nil override is `undefined`: the
/// field is left out, as `JSON` drops it.
func awSpread(_ base: [String: JSONValue], _ overrides: [String: JSONValue?]) -> [String: JSONValue] {
  var fields = base
  for (key, value) in overrides {
    if let value {
      fields[key] = value
    } else {
      fields.removeValue(forKey: key)
    }
  }
  return fields
}

/// A JavaScript number as stored.
func awNumber(_ value: Decimal) -> JSONValue { .number(Money.toNumber(value)) }

/// `round(value, places)` as a number.
func awRound(_ value: some MoneyValue, _ places: Int) -> Double { Money.toNumber(Money.round(value, places)) }

/// `toMinor(value, places)`.
func awMinor(_ value: some MoneyValue, _ places: Int) -> Int { Int(Money.toMinor(value, places)) }

/// `fromMinor(minor, places)` as a number.
func awMajor(_ minor: Int, _ places: Int) -> Double { Money.toNumber(Money.fromMinor(Int64(minor), places)) }

/// `value !== 0` for a field that should hold a number (a missing one is not 0).
func awNotZero(_ value: JSONValue?) -> Bool {
  if case .number(let number)? = value { return number != 0 }
  return true
}

/// `value < 0` for a field that should hold a number.
func awNegative(_ value: JSONValue?) -> Bool {
  if case .number(let number)? = value { return number < 0 }
  return false
}

// MARK: Settings and the lock date

/// The company's accounting settings and the lock date (src/db/chart-setup.ts,
/// `assertUnlocked`).
public enum AwBooks {
  /// `chartTemplateFor(country)`: Kuwait is the default.
  public static func chartTemplateFor(_ country: String) -> String {
    switch country {
    case "GB": "uk"
    case "AE": "ae"
    case "KW", "": "kw"
    default: "generic"
    }
  }

  /// `accountingSettings(company)`: the company's, or the defaults for
  /// companies created before accounting.
  public static func settings(_ company: JSONValue) -> JSONValue {
    if let saved = WebJS.present(company["accounting"]) { return saved }
    let country = company["address"]?["country"]?.string ?? ""
    return .object([
      "template": .string(chartTemplateFor(country)),
      "fiscalYearEnd": .object(["month": .number(12), "day": .number(31)]),
      "lockDate": .null,
    ])
  }

  /// The lock date, when the books are locked.
  public static func lockDate(_ company: JSONValue) -> String? {
    settings(company).awText("lockDate")
  }

  /// The chart template the company started from.
  public static func template(_ company: JSONValue) -> String {
    settings(company)["template"]?.string ?? ""
  }

  /// `LockedPeriodError`: the lock date in the company's date format, in the interface language.
  public static func lockedError(_ lock: String, _ company: JSONValue, _ tr: I18n.Translator) -> WriteFailure {
    let format = Format.DateFormat(company["dateFormat"]?.string ?? "dd/MM/yyyy")
    let locale = FormatLocale.interface(tr.language, companyLocale: company["locale"]?.string)
    let date = Format.date(lock, format: format, locale: locale)
    return WriteFailure(
      "The books are locked up to {date}. Change the lock date in Settings → Accounting to edit earlier transactions.",
      ["date": date])
  }

  /// `assertUnlocked(company, ...dates)`: throws when a date falls on or before the lock date.
  public static func assertUnlocked(_ company: JSONValue, _ dates: [String?], _ tr: I18n.Translator) throws {
    guard let lock = lockDate(company) else { return }
    let locked = dates.contains { date in
      guard let date, !date.isEmpty else { return false }
      return !WebJS.less(lock, date)
    }
    if locked { throw lockedError(lock, company, tr) }
  }

  /// The company's records of a table, in id order (`where('companyId').equals(id)`).
  static func records(_ ctx: WriteContext, _ table: String, _ companyId: String) -> [JSONValue] {
    ctx.all(table) { $0.awStr("companyId") == companyId }
  }

  /// `roleMap(accounts)`: the account for each automatic posting (active accounts first).
  public static func roleMap(_ accounts: [JSONValue]) -> [String: String] {
    var roles: [String: String] = [:]
    let ordered = accounts.filter { !$0.awTruthy("archived") } + accounts.filter { $0.awTruthy("archived") }
    for account in ordered {
      if let role = account.awText("role"), roles[role] == nil { roles[role] = account.awId }
    }
    return roles
  }

  /// `formatMoney(amount, currency, locale)` as the web writes amounts into the activity log.
  static func activityMoney(_ amount: Double, _ currency: String, _ companyLocale: String?) -> String {
    let locale = FormatLocale((companyLocale?.isEmpty == false ? companyLocale : nil) ?? "en-KW")
    return Format.money(amount, currency: currency, locale: locale, display: .code)
  }

  /// `monthLabel(period, locale)`: "March 2026" in the interface language.
  public static func monthLabel(_ period: String, _ tr: I18n.Translator) -> String {
    let parts = period.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count >= 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return period }
    let day = CivilDay(javaScriptYear: year, month: month, day: 1)
    let names = tr.language == .ar ? DateNames.dateFnsArabic : DateNames.dateFnsEnglish
    return names.monthsWide[day.month - 1] + " " + String(day.year)
  }

  /// `financialYearLabel(start, end)`: "2026", or "2025–2026" for a year across two.
  public static func financialYearLabel(_ start: String, _ end: String) -> String {
    let a = WebJS.prefix(start, 4)
    let b = WebJS.prefix(end, 4)
    return a == b ? b : "\(a)–\(b)"
  }
}

// MARK: Account types

/// `src/lib/accounting/account-types.ts`.
public enum AwAccountTypes {
  /// Every type, in the chart's order, with its group.
  public static let order: [(type: String, group: String)] = [
    ("asset_cash", "asset"), ("asset_receivable", "asset"), ("asset_current", "asset"),
    ("asset_prepayments", "asset"), ("asset_fixed", "asset"), ("asset_non_current", "asset"),
    ("liability_payable", "liability"), ("liability_credit_card", "liability"), ("liability_current", "liability"),
    ("liability_non_current", "liability"), ("equity", "equity"), ("income", "income"),
    ("income_other", "income"), ("expense_direct_cost", "expense"), ("expense", "expense"),
    ("expense_depreciation", "expense"), ("expense_other", "expense"),
  ]

  /// `accountGroup(type)`; a type this version doesn't know has none.
  public static func group(_ type: String) -> String? {
    order.first { $0.type == type }?.group
  }

  /// `isMoneyAccount(type)`: bank, cash and card accounts.
  public static func isMoneyAccount(_ type: String) -> Bool {
    type == "asset_cash" || type == "liability_credit_card"
  }

  /// A fixed or non-current asset account (what an asset is kept in).
  public static func isFixedAsset(_ type: String) -> Bool {
    type == "asset_fixed" || type == "asset_non_current"
  }
}

// MARK: Accounts looked up by code

/// `ACCOUNT_SPECS`: accounts some postings need that have no role.
public struct AwSpec: Sendable {
  public let code: String
  public let name: String
  public let nameAr: String
  public let type: String
  /// Recognises the account by its English name in other charts (case-insensitive).
  public let match: String

  public static let statutoryReserve = AwSpec(
    code: "3200", name: "Statutory reserve", nameAr: "الاحتياطي الإجباري", type: "equity",
    match: "statutory|legal reserve")
  public static let voluntaryReserve = AwSpec(
    code: "3210", name: "Voluntary reserve", nameAr: "الاحتياطي الاختياري", type: "equity",
    match: "voluntary|general reserve")
  public static let disposal = AwSpec(
    code: "4520", name: "Gain or loss on disposal of assets", nameAr: "أرباح وخسائر استبعاد الأصول",
    type: "income_other", match: "disposal|sale of (fixed )?assets")
  public static let kfas = AwSpec(
    code: "7200", name: "KFAS contribution", nameAr: "حصة مؤسسة الكويت للتقدم العلمي", type: "expense_other",
    match: "kfas")
  public static let kfasPayable = AwSpec(
    code: "2500", name: "KFAS payable", nameAr: "حصة مؤسسة الكويت للتقدم العلمي المستحقة",
    type: "liability_current", match: "kfas")
  public static let zakat = AwSpec(code: "7210", name: "Zakat", nameAr: "الزكاة", type: "expense_other", match: "zakat")
  public static let zakatPayable = AwSpec(
    code: "2510", name: "Zakat payable", nameAr: "الزكاة المستحقة", type: "liability_current", match: "zakat")
  public static let nlst = AwSpec(
    code: "7220", name: "National Labour Support Tax", nameAr: "ضريبة دعم العمالة الوطنية", type: "expense_other",
    match: "nlst|labou?r support")
  public static let nlstPayable = AwSpec(
    code: "2520", name: "NLST payable", nameAr: "ضريبة دعم العمالة الوطنية المستحقة", type: "liability_current",
    match: "nlst|labou?r support")
  public static let incomeTax = AwSpec(
    code: "7230", name: "Income tax", nameAr: "ضريبة الدخل", type: "expense_other", match: "income tax")
  public static let incomeTaxPayable = AwSpec(
    code: "2530", name: "Income tax payable", nameAr: "ضريبة الدخل المستحقة", type: "liability_current",
    match: "income tax")

  /// `s.match.test(name)`.
  func matches(_ text: String) -> Bool {
    text.range(of: match, options: [.regularExpression, .caseInsensitive]) != nil
  }

  /// `findSpecAccount(accounts, key, template)`: Kuwait charts match by code
  /// (accounts may have been renamed), others by name; accounts with a role never match.
  public func find(_ accounts: [JSONValue], template: String) -> JSONValue? {
    let typed = accounts.filter { $0.awStr("type") == type && !$0.awTruthy("role") }
    let candidates = typed.filter { !$0.awTruthy("archived") } + typed.filter { $0.awTruthy("archived") }
    if template == "kw", let byCode = candidates.first(where: { $0.awStr("code") == code }) { return byCode }
    let lower = name.lowercased()
    if let found = candidates.first(where: { WebJS.trim($0.awStr("name")).lowercased() == lower }) { return found }
    if let found = candidates.first(where: { $0["nameAr"]?.string.map(WebJS.trim) == nameAr }) { return found }
    return candidates.first { matches($0.awStr("name")) }
  }

  /// `freeCode(accounts, wanted)`: the spec's own code when free, else the next free one after it.
  static func freeCode(_ accounts: [JSONValue], _ wanted: String) -> String {
    let taken = Set(accounts.map { $0.awStr("code") })
    if !taken.contains(wanted) { return wanted }
    let numeric = !wanted.isEmpty && wanted.unicodeScalars.allSatisfy(WebJS.isDigit)
    guard numeric, let base = Int(wanted) else {
      var i = 2
      while taken.contains("\(wanted)-\(i)") { i += 1 }
      return "\(wanted)-\(i)"
    }
    let width = wanted.utf16.count
    var next = base + 1
    while taken.contains(WebJS.padStart(String(next), width)) { next += 1 }
    return WebJS.padStart(String(next), width)
  }
}

// MARK: The activity log, with numbers

enum AwActivity {
  /// `logActivity` for a message whose values are not all text (a count):
  /// they are stored as JavaScript stored them, numbers as numbers.
  static func log(
    _ ctx: WriteContext, entity: String, entityId: String, action: String, text: String, vars: [String: JSONValue],
    arabic: [String: String?] = [:]
  ) {
    var fields: [String: JSONValue] = [
      "id": .string(ctx.newId()), "companyId": .string(ctx.companyId), "at": .string(ctx.stamp),
    ]
    if let userId = ctx.userId, !userId.isEmpty {
      fields["by"] = .string(userId)
      let name = String((ctx.userName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
      if !name.isEmpty { fields["byName"] = .string(name) }
    }
    fields["entity"] = .string(entity)
    fields["entityId"] = .string(entityId)
    fields["clientId"] = .null
    fields["documentId"] = .null
    fields["action"] = .string(action)
    fields["message"] = .string(I18n.interpolate(text, vars.mapValues { WebJS.string($0) }))
    fields["messageKey"] = .string(text)
    fields["messageVars"] = .object(vars)
    var names: [String: JSONValue] = [:]
    for (key, value) in arabic {
      let trimmed = WebJS.trim(value ?? "")
      if !trimmed.isEmpty { names[key] = .string(trimmed) }
    }
    if !names.isEmpty { fields["messageVarsAr"] = .object(names) }
    ctx.put("activities", .object(fields))
  }
}

// MARK: Text order

enum AwText {
  /// `a.localeCompare(b, undefined, { numeric: true }) < 0` for codes and
  /// numbers such as "FA-0002" and "FA-0010": runs of digits by their value,
  /// the rest ignoring case.
  static func numericLess(_ a: String, _ b: String) -> Bool {
    let x = runs(a)
    let y = runs(b)
    for (left, right) in zip(x, y) {
      switch (left, right) {
      case (.digits(let m), .digits(let n)):
        let p = trimZeros(m)
        let q = trimZeros(n)
        if p.count != q.count { return p.count < q.count }
        if p != q { return p < q }
      case (.digits, .text): return true
      case (.text, .digits): return false
      case (.text(let s), .text(let t)):
        let ls = s.lowercased()
        let lt = t.lowercased()
        if ls != lt { return WebJS.less(ls, lt) }
      }
    }
    // Equal to the collation: the caller keeps their order.
    return x.count < y.count
  }

  private enum Run {
    case digits(String)
    case text(String)
  }

  private static func runs(_ text: String) -> [Run] {
    var out: [Run] = []
    var current = ""
    var inDigits = false
    for scalar in text.unicodeScalars {
      let digit = WebJS.isDigit(scalar)
      if !current.isEmpty && digit != inDigits {
        out.append(inDigits ? .digits(current) : .text(current))
        current = ""
      }
      inDigits = digit
      current.unicodeScalars.append(scalar)
    }
    if !current.isEmpty { out.append(inDigits ? .digits(current) : .text(current)) }
    return out
  }

  private static func trimZeros(_ digits: String) -> String {
    let trimmed = String(digits.drop { $0 == "0" })
    return trimmed.isEmpty ? "0" : trimmed
  }
}
