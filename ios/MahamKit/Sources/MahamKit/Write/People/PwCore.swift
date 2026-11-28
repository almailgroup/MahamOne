import Foundation

// What the People and payroll write ports share: reading records as the
// web's code reads them, amounts as src/lib/money.ts works them out, days as
// date-fns counts them, the words a port stores (in the person's language,
// as the web's `t` stores them), the cloud link, and the activity log with
// numbers kept as numbers (`messageVars`).

// MARK: - Reading records

extension JSONValue {
  /// `record.key` as text; "" when it is missing or not text.
  func pwStr(_ key: String) -> String { self[key]?.string ?? "" }

  /// `record.key` when it is text.
  func pwText(_ key: String) -> String? { self[key]?.string }

  /// `record.key` as a number; 0 when it is missing or not a number.
  func pwNum(_ key: String) -> Double { self[key]?.double ?? 0 }

  /// `record.key` when it is a number.
  func pwNumber(_ key: String) -> Double? { self[key]?.double }

  /// `record.key` as a list; none when it is missing or not a list.
  func pwList(_ key: String) -> [JSONValue] { self[key]?.array ?? [] }

  /// `record.key === true`.
  func pwFlag(_ key: String) -> Bool { self[key]?.bool == true }

  /// `Boolean(record.key)`.
  func pwTruthy(_ key: String) -> Bool { WebJS.truthy(self[key]) }

  /// The record's id.
  var pwId: String { pwStr("id") }

  /// The record's fields.
  var pwFields: [String: JSONValue] { object ?? [:] }

  /// The record with `key` set (or, with nil, left out).
  func pwWith(_ key: String, _ value: JSONValue?) -> JSONValue {
    var copy = self
    copy.set(key, value)
    return copy
  }

  /// The record with each field of `fields` set (`{ ...record, ...fields }`).
  func pwMerging(_ fields: [String: JSONValue]) -> JSONValue {
    var all = pwFields
    for (key, value) in fields { all[key] = value }
    return .object(all)
  }
}

extension JSONValue {
  /// A number as JSON.
  static func pwNum(_ value: Double) -> JSONValue { .number(value) }

  /// Text, or null.
  static func pwOptional(_ value: String?) -> JSONValue { value.map(JSONValue.string) ?? .null }
}

// MARK: - Amounts

/// The web's `src/lib/money.ts` as the payroll uses it: decimals from a
/// number's shortest text, rounded half away from zero, and numbers back as
/// JavaScript holds them.
enum PwM {
  static func dec(_ value: Double) -> Decimal { Money.dec(value) }

  /// `decimal.toNumber()`.
  static func num(_ value: Decimal) -> Double { Money.toNumber(value) }

  /// `round(value, places)`: a number.
  static func round(_ value: Decimal, _ places: Int) -> Double { Money.toNumber(Money.round(value, places)) }

  static func round(_ value: Double, _ places: Int) -> Double { Money.toNumber(Money.round(value, places)) }

  static func minor(_ value: Double, _ places: Int) -> Int64 { Money.toMinor(value, places) }

  static func minor(_ value: Decimal, _ places: Int) -> Int64 { Money.toMinor(value, places) }

  static func fromMinor(_ minor: Int64, _ places: Int) -> Double { Money.toNumber(Money.fromMinor(minor, places)) }

  /// The sum of amounts, as decimals.
  static func total(_ values: [Double]) -> Decimal {
    values.reduce(Decimal(0)) { $0 + Money.dec($1) }
  }

  /// `Math.round`.
  static func jsRound(_ value: Double) -> Double {
    guard value.isFinite else { return value }
    let result = (value + 0.5).rounded(.down)
    return result == 0 ? 0 : result
  }

  /// `Math.round(n * 100) / 100`.
  static func two(_ value: Double) -> Double { jsRound(value * 100) / 100 }

  /// `Math.trunc`.
  static func trunc(_ value: Double) -> Double { value.rounded(.towardZero) }

  /// `Math.min(max, Math.max(min, Math.round(n)))`, or `fallback` for a number that isn't finite.
  static func whole(_ value: Double?, _ low: Double, _ high: Double, _ fallback: Double) -> Double {
    guard let value, value.isFinite else { return fallback }
    return min(high, max(low, jsRound(value)))
  }

  /// A JavaScript number from text the way `Number(text)` reads stored values.
  static func number(_ value: JSONValue?) -> Double { WebJS.toNumber(value) }

  /// The currency's decimals.
  static func places(_ currency: String) -> Int { Money.precision(currency) }
}

// MARK: - Days

/// Calendar days written yyyy-MM-dd, with date-fns' arithmetic.
enum PwDates {
  static func day(_ value: String) -> CivilDay? { ISODates.parse(value) }

  static func isDate(_ value: String?) -> Bool {
    guard let value else { return false }
    return ISODates.isISODate(value)
  }

  /// `addDaysISO`.
  static func addDays(_ value: String, _ days: Int) -> String { ISODates.addDays(value, days) }

  /// `daysBetween`: 0 where the web gets NaN (never for real days).
  static func daysBetween(_ from: String, _ to: String) -> Int { ISODates.daysBetween(from, to) ?? 0 }

  /// date-fns `addMonths`.
  static func addMonths(_ value: String, _ months: Int) -> String {
    guard let day = day(value) else { return ISODates.invalid }
    return day.adding(months: months).text
  }

  /// `new Date(year, month - 1, day)` written back.
  static func make(_ year: Int, _ month: Int, _ day: Int) -> CivilDay {
    CivilDay(javaScriptYear: year, month: month, day: day)
  }

  /// date-fns `differenceInMonths(later, earlier)`.
  static func differenceInMonths(_ later: String, _ earlier: String) -> Int {
    guard let l = day(later), let e = day(earlier) else { return 0 }
    let sign = l.dayNumber > e.dayNumber ? 1 : (l.dayNumber < e.dayNumber ? -1 : 0)
    let difference = abs((l.year - e.year) * 12 + (l.month - e.month))
    if difference < 1 { return 0 }
    var working = l
    if working.month == 2 && working.day > 27 {
      working = make(working.year, working.month, 30)
    }
    let moved = make(working.year, working.month - sign * difference, working.day)
    let compared = moved.dayNumber > e.dayNumber ? 1 : (moved.dayNumber < e.dayNumber ? -1 : 0)
    var notFull = compared == -sign
    let lastDay = l.day == CivilDay.daysIn(year: l.year, month: l.month)
    if lastDay && difference == 1 && l.dayNumber > e.dayNumber { notFull = false }
    let result = sign * (difference - (notFull ? 1 : 0))
    return result
  }

  /// Whole months from `from` to the end of `on` (`completedMonths`).
  static func completedMonths(_ from: String, _ on: String) -> Int {
    if WebJS.less(on, from) { return 0 }
    return max(0, differenceInMonths(addDays(on, 1), from))
  }

  /// 0 for Sunday, as `Date.getDay()`.
  static func weekday(_ value: String) -> Int { day(value)?.weekday ?? 0 }

  /// date-fns `addYears`.
  static func addYears(_ value: String, _ years: Int) -> String { addMonths(value, years * 12) }

  /// Today on this device.
  static func today(_ ctx: WriteContext) -> String { ctx.today }
}

// MARK: - Order

enum PwSort {
  /// `a.localeCompare(b)` (with `{ numeric: true }`): the platform's collation, near enough to ICU's root.
  static func localeCompare(_ a: String, _ b: String, numeric: Bool = false) -> Int {
    let result = a.compare(b, options: numeric ? [.numeric] : [], range: nil, locale: Locale(identifier: "en"))
    switch result {
    case .orderedAscending: return -1
    case .orderedDescending: return 1
    case .orderedSame: return a == b ? 0 : (WebJS.less(a, b) ? -1 : 1)
    }
  }

  /// `a.localeCompare(b)` without case, as `{ sensitivity: 'base' }`.
  static func baseCompare(_ a: String, _ b: String) -> Int {
    let result = a.compare(
      b, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: Locale(identifier: "en"))
    switch result {
    case .orderedAscending: return -1
    case .orderedDescending: return 1
    case .orderedSame: return 0
    }
  }

  /// A stable sort, as JavaScript's `Array.prototype.sort` is.
  static func stable<T>(_ items: [T], by compare: (T, T) -> Int) -> [T] {
    items.enumerated().sorted { left, right in
      let order = compare(left.element, right.element)
      return order != 0 ? order < 0 : left.offset < right.offset
    }.map { $0.element }
  }

  /// `a < b` for JavaScript strings, as -1, 0 or 1 (`localeCompare` of ISO dates and ids).
  static func code(_ a: String, _ b: String) -> Int { a == b ? 0 : (WebJS.less(a, b) ? -1 : 1) }
}

// MARK: - Words

/// The words a port stores or shows, as the web's `t` gives them: in the
/// person's language (English in the parity tests).
public struct PwText: Sendable {
  public var language: InterfaceLanguage
  private let translate: @Sendable (String, [String: String]) -> String

  public init(language: InterfaceLanguage, translate: @escaping @Sendable (String, [String: String]) -> String) {
    self.language = language
    self.translate = translate
  }

  /// English, untranslated.
  public static let english = PwText(language: .en) { I18n.interpolate($0, $1) }

  /// `t(text, vars)`.
  public func t(_ text: String, _ vars: [String: String] = [:]) -> String { translate(text, vars) }

  /// `interfaceLocale(company.locale)`.
  func locale(_ company: JSONValue?) -> FormatLocale {
    .interface(language, companyLocale: company?.pwText("locale"))
  }

  /// `formatDate(value, company.dateFormat, interfaceLocale(company.locale))`.
  func date(_ value: String?, _ company: JSONValue?) -> String {
    let format = Format.DateFormat(company?.pwText("dateFormat") ?? "dd/MM/yyyy")
    return Format.date(value, format: format, locale: locale(company))
  }

  /// `localName(record)`.
  func localName(_ record: JSONValue?) -> String {
    guard let record else { return "" }
    let arabic = WebJS.trim(record.pwStr("nameAr"))
    return language == .ar && !arabic.isEmpty ? arabic : record.pwStr("name")
  }

  /// `formatPeriod(period, locale)`: "September 2026", "سبتمبر 2026".
  func period(_ period: String, _ company: JSONValue?) -> String {
    guard PwPay.isPeriod(period), let year = Int(period.prefix(4)), let month = Int(period.suffix(2)) else {
      return period
    }
    let english = [
      "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
      "November", "December",
    ]
    let arabic = [
      "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر",
    ]
    let names = locale(company).isArabic ? arabic : english
    return names[month - 1] + " " + String(year)
  }
}

// MARK: - The cloud link

/// The person's link to a company kept in the cloud (`db.syncState`, the
/// web's `CloudLink`): who they are there, what the owner allowed them and
/// what the server has. Nil for a company kept on this device only.
public struct PwLink: Sendable, Equatable {
  public var userId: String
  public var role: MemberRole
  public var removed: Bool
  public var approver: Bool
  /// The owner's limits on this person, app by app.
  public var permissions: [String: String]?
  /// What the server has beyond the first migrations.
  public var features: [String]

  public init(
    userId: String, role: MemberRole, removed: Bool = false, approver: Bool = false,
    permissions: [String: String]? = nil, features: [String] = []
  ) {
    self.userId = userId
    self.role = role
    self.removed = removed
    self.approver = approver
    self.permissions = permissions
    self.features = features
  }

  /// The link the sync engine keeps for the company.
  public init(state: SyncState) {
    self.init(
      userId: state.userId, role: state.role, removed: state.status == .removed, approver: state.approver ?? false,
      permissions: state.permissions, features: state.features ?? [])
  }

  /// A `syncState` row as the web stores it.
  init?(row: JSONValue?) {
    guard let row, let role = MemberRole(rawValue: row.pwStr("role")) else { return nil }
    var permissions: [String: String]?
    if let apps = row["permissions"]?["apps"]?.object {
      permissions = apps.compactMapValues { $0.string }
    }
    self.init(
      userId: row.pwStr("userId"), role: role, removed: row.pwStr("status") == "removed",
      approver: row.pwFlag("approver"), permissions: permissions,
      features: row.pwList("features").compactMap(\.string))
  }

  var rolesPermissions: Roles.Permissions {
    Roles.readPermissions(.object(["apps": .object((permissions ?? [:]).mapValues { .string($0) })]))
  }

  /// `linkHasFeature(link, feature)`: always for a company on this device.
  static func has(_ link: PwLink?, _ feature: String) -> Bool {
    guard let link else { return true }
    return link.features.contains(feature)
  }

  /// `canWriteRecord(role, table, {}) && !limitBlocksWrite(role, permissions, table, record)`.
  func mayWrite(_ table: String, _ record: JSONValue = .object([:])) -> Bool {
    let isPrivate: Roles.PrivacyCheck = { Privacy.isPrivateRecord($0, $1) }
    return Roles.canWriteRecord(role, table, record, isPrivate: isPrivate)
      && !Roles.limitBlocksWrite(role, rolesPermissions, table, record, lookup: nil)
  }
}

// MARK: - The activity log

/// `logActivity` with its variables as the web keeps them: numbers stay numbers.
enum PwLog {
  enum Var {
    case text(String)
    case number(Double)

    var json: JSONValue {
      switch self {
      case .text(let value): .string(value)
      case .number(let value): .number(value)
      }
    }

    /// `String(value)`.
    var shown: String {
      switch self {
      case .text(let value): value
      case .number(let value): WebJS.numberString(value)
      }
    }
  }

  static func add(
    _ ctx: WriteContext, _ entity: String, _ entityId: String, _ action: String, _ text: String,
    vars: [String: Var] = [:], arabic: [String: String?] = [:], refs: ActivityRefs = ActivityRefs()
  ) {
    var fields: [String: JSONValue] = [
      "id": .string(ctx.newId()), "companyId": .string(ctx.companyId), "at": .string(ctx.stamp),
      "entity": .string(entity), "entityId": .string(entityId),
      "clientId": refs.clientId.map(JSONValue.string) ?? .null,
      "documentId": refs.documentId.map(JSONValue.string) ?? .null,
      "action": .string(action),
      "message": .string(I18n.interpolate(text, vars.mapValues(\.shown))),
      "messageKey": .string(text),
      "messageVars": .object(vars.mapValues(\.json)),
    ]
    if let userId = ctx.userId, !userId.isEmpty {
      fields["by"] = .string(userId)
      let name = String(WebJS.trim(ctx.userName ?? "").prefix(200))
      if !name.isEmpty { fields["byName"] = .string(name) }
    }
    if let employee = refs.employeeId, !employee.isEmpty { fields["employeeId"] = .string(employee) }
    if refs.confidential { fields["confidential"] = .bool(true) }
    var names: [String: JSONValue] = [:]
    for (key, value) in arabic {
      let trimmed = WebJS.trim(value ?? "")
      if !trimmed.isEmpty { names[key] = .string(trimmed) }
    }
    if !names.isEmpty { fields["messageVarsAr"] = .object(names) }
    ctx.put("activities", .object(fields))
  }
}

// MARK: - Reading a company

extension WriteContext {
  /// The company's records of a table (`where('companyId').equals(id)`), in id order.
  func pwAll(_ table: String) -> [JSONValue] {
    all(table).filter { $0.pwStr("companyId") == companyId }
  }

  /// Records of a table that belong to an employee (`where('employeeId').equals(id)`), in id order.
  func pwOf(_ table: String, employee: String) -> [JSONValue] {
    all(table).filter { $0.pwStr("employeeId") == employee }
  }

  /// The company record.
  var pwCompany: JSONValue? { self.get("companies", companyId) }
}

/// The web's error with its English message.
func pwFail(_ message: String, _ vars: [String: String] = [:]) -> WriteFailure {
  WriteFailure(message, vars)
}
