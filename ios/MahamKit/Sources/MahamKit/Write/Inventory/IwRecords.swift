import Foundation

// Reading and changing raw records the way the web's stock code does
// (src/db/inventory.ts and friends): fields as JavaScript sees them,
// `{ ...record, field }` copies, and the company's records of a table in
// Dexie's order (by id). The names carry `iw` so they never meet another
// area's helpers in MahamKit.

extension JSONValue {
  /// `record.field` as text, or "" when it isn't text.
  func iwText(_ key: String) -> String { self[key]?.string ?? "" }

  /// `record.field` when it is text, else nil.
  func iwString(_ key: String) -> String? { self[key]?.string }

  /// `record.field` when it is a number, else nil.
  func iwNumber(_ key: String) -> Double? { self[key]?.double }

  /// `Boolean(record.field)`.
  func iwTruthy(_ key: String) -> Bool { WebJS.truthy(self[key]) }

  /// `record.field === true`.
  func iwIsTrue(_ key: String) -> Bool { self[key]?.bool == true }

  /// `record.field ?? []` when it is a list.
  func iwList(_ key: String) -> [JSONValue] { self[key]?.array ?? [] }

  /// The record's id ("" when it has none).
  var iwId: String { iwText("id") }

  /// `{ ...record, [key]: value }` (nil leaves the field out).
  func iwWith(_ key: String, _ value: JSONValue?) -> JSONValue {
    var copy = WebJS.spread(self)
    copy[key] = value
    return .object(copy)
  }

  /// `{ ...record, ...fields }`.
  func iwWith(_ fields: [String: JSONValue]) -> JSONValue {
    var copy = WebJS.spread(self)
    for (key, value) in fields { copy[key] = value }
    return .object(copy)
  }
}

enum IwRecords {
  /// `db.<table>.where('companyId').equals(companyId).toArray()`: by id.
  static func company(_ ctx: WriteContext, _ table: String, _ companyId: String) -> [JSONValue] {
    ctx.all(table) { $0["companyId"]?.string == companyId }
  }

  /// `db.<table>.where(field).equals(value).toArray()`: by id.
  static func matching(_ ctx: WriteContext, _ table: String, _ field: String, _ value: String) -> [JSONValue] {
    ctx.all(table) { $0[field]?.string == value }
  }

  /// `a.localeCompare(b)` for text people typed (names): the root order
  /// of the language, case after the letter.
  static func localeCompare(_ a: String, _ b: String) -> Int {
    switch a.compare(b, options: [], range: nil, locale: Locale(identifier: "en_US")) {
    case .orderedAscending: return -1
    case .orderedDescending: return 1
    case .orderedSame: return 0
    }
  }

  /// `a < b` for JavaScript values that should be text: by UTF-16 code
  /// units; anything that isn't text compares as neither.
  static func textOrder(_ a: JSONValue?, _ b: JSONValue?) -> Int {
    guard let x = a?.string, let y = b?.string else { return 0 }
    if WebJS.less(x, y) { return -1 }
    if WebJS.less(y, x) { return 1 }
    return 0
  }

  /// `a <= b` for dates as the web compares them (both text).
  static func onOrBefore(_ date: JSONValue?, _ limit: String) -> Bool {
    guard let text = date?.string else { return false }
    return !WebJS.less(limit, text)
  }

  /// `[...list].sort((a, b) => Number(a.archived) - Number(b.archived))`:
  /// the ones in use first, each group in its order.
  static func archivedLast(_ list: [JSONValue]) -> [JSONValue] {
    list.filter { !$0.iwIsTrue("archived") } + list.filter { $0.iwIsTrue("archived") }
  }

  /// `[...new Set(values)]`, in first-seen order.
  static func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for value in values where seen.insert(value).inserted { out.append(value) }
    return out
  }

  /// `String(n)` for a stored number, as messages and keys write it.
  static func numberText(_ value: Double) -> String { WebJS.numberString(value) }
}
