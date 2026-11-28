import Foundation

// How the document ports read and change raw records the way the web's
// code does: `doc.number` on a record that may lack it, `{ ...doc, k: v }`
// (a `nil` value is JavaScript's `undefined`, which JSON leaves out), and
// money through decimal.js-light's rules (`dec`, `round`).

/// Changes laid over a record in order, as `{ ...record, a: 1, b: undefined }`:
/// a `nil` value takes the field away (JSON drops `undefined`).
public typealias DcPatch = [(String, JSONValue?)]

enum DcJS {
  /// `dec(value)`: a number through its shortest text, a text as decimal.js
  /// reads it, anything else 0.
  static func dec(_ value: JSONValue?) -> Decimal {
    switch value {
    case .number(let n)?: return Money.dec(n)
    case .string(let s)?: return Money.dec(s)
    default: return 0
    }
  }

  /// `round(value, places)`: half away from zero, as a JavaScript number.
  static func round(_ value: Decimal, _ places: Int) -> Double {
    Money.toNumber(Money.round(value, places))
  }

  static func round(_ value: Double, _ places: Int) -> Double {
    Money.toNumber(Money.round(value, places))
  }

  /// `decimal.toNumber()`.
  static func number(_ value: Decimal) -> Double { Money.toNumber(value) }

  /// `currencyPrecision(doc.currency || 'KWD')`.
  static func precision(of record: JSONValue) -> Int {
    let currency = record["currency"]?.string ?? ""
    return Money.precision(currency.isEmpty ? "KWD" : currency)
  }

  /// `{ ...record, ...patch }`.
  static func merge(_ record: JSONValue, _ patch: DcPatch) -> JSONValue {
    var fields = WebJS.spread(record)
    apply(&fields, patch)
    return .object(fields)
  }

  static func apply(_ fields: inout [String: JSONValue], _ patch: DcPatch) {
    for (key, value) in patch {
      if let value { fields[key] = value } else { fields.removeValue(forKey: key) }
    }
  }

  /// `{ ...record, ...overrides }` for overrides given as a stored object
  /// (fields set to null stay null).
  static func merge(_ record: JSONValue, object overrides: JSONValue?) -> JSONValue {
    var fields = WebJS.spread(record)
    for (key, value) in WebJS.spread(overrides) { fields[key] = value }
    return .object(fields)
  }

  /// `text.trim()` of a field that should be text ("" when it isn't).
  static func trimmed(_ value: JSONValue?) -> String {
    WebJS.trim(value?.string ?? "")
  }

  /// `a || b` for a text field: the field when it is a non-empty text, else `fallback`.
  static func orText(_ value: JSONValue?, _ fallback: JSONValue?) -> JSONValue? {
    WebJS.truthy(value) ? value : fallback
  }

  /// `value ?? fallback`: the value unless it is missing or null.
  static func orElse(_ value: JSONValue?, _ fallback: JSONValue?) -> JSONValue? {
    WebJS.present(value) ?? fallback
  }

  /// `new Set(ids)` in the order they were first seen.
  static func unique(_ ids: [String]) -> [String] {
    var seen = Set<String>()
    return ids.filter { seen.insert($0).inserted }
  }

  /// The stable sort of `[...list].sort((a, b) => Number(a.archived) - Number(b.archived))`.
  static func activeFirst(_ list: [JSONValue]) -> [JSONValue] {
    list.filter { !WebJS.truthy($0["archived"]) } + list.filter { WebJS.truthy($0["archived"]) }
  }
}

extension JSONValue {
  /// A text field ("" when missing or not text).
  func dcText(_ key: String) -> String { self[key]?.string ?? "" }
  /// A list field (none when missing).
  func dcList(_ key: String) -> [JSONValue] { self[key]?.array ?? [] }
  /// `Boolean(record[key])`.
  func dcTruthy(_ key: String) -> Bool { WebJS.truthy(self[key]) }
  /// The record's id.
  var dcId: String { self["id"]?.string ?? "" }
  /// A text field when it is a non-empty text (`record[key] ? … : …`).
  func dcNonEmpty(_ key: String) -> String? {
    guard let value = self[key]?.string, !value.isEmpty else { return nil }
    return value
  }
}
