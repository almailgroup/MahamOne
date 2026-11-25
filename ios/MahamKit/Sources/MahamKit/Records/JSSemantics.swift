import Foundation

/// How JavaScript reads text and values, where the web's rules depend on it:
/// `trim()` and `\s`, `String(n)`, `JSON.stringify`, truthiness, spreading a
/// value into an object, and string order (UTF-16 code units). The ports in
/// MahamKit go through these so that they give the web's answers for the
/// same records, odd ones included.
enum WebJS {
  // MARK: Text

  /// `\s` of a JavaScript regular expression: what `trim()` removes.
  static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
      return true
    default:
      return false
    }
  }

  /// `\d` of a JavaScript regular expression: ASCII digits only.
  static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
    scalar.value >= 0x30 && scalar.value <= 0x39
  }

  /// `\w`: ASCII letters, digits and the underscore.
  static func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F: return true
    default: return false
    }
  }

  /// `text.trim()`.
  static func trim(_ text: String) -> String {
    let scalars = text.unicodeScalars
    guard let first = scalars.firstIndex(where: { !isSpace($0) }),
      let last = scalars.lastIndex(where: { !isSpace($0) })
    else { return "" }
    return String(scalars[first...last])
  }

  /// `text.replace(/[\s…]/g, '')`: the text without the scalars `drop` matches.
  static func removing(_ text: String, where drop: (Unicode.Scalar) -> Bool) -> String {
    var out = String.UnicodeScalarView()
    for scalar in text.unicodeScalars where !drop(scalar) { out.append(scalar) }
    return String(out)
  }

  /// `text.padStart(length, pad)`: lengths in UTF-16 code units, as in JavaScript.
  static func padStart(_ text: String, _ length: Int, _ pad: Character = "0") -> String {
    let missing = length - text.utf16.count
    return missing > 0 ? String(repeating: pad, count: missing) + text : text
  }

  /// `text.slice(0, count)` (UTF-16 code units).
  static func prefix(_ text: String, _ count: Int) -> String {
    let units = Array(text.utf16)
    return String(decoding: units.prefix(max(0, count)), as: UTF16.self)
  }

  /// `text.slice(-count)` (UTF-16 code units).
  static func suffix(_ text: String, _ count: Int) -> String {
    let units = Array(text.utf16)
    return String(decoding: units.suffix(max(0, count)), as: UTF16.self)
  }

  /// `a < b` for JavaScript strings: by UTF-16 code units.
  static func less(_ a: String, _ b: String) -> Bool {
    a.utf16.lexicographicallyPrecedes(b.utf16)
  }

  // MARK: Numbers

  /// `String(n)` for a JavaScript number (Number::toString): "1", "0.1",
  /// "1e+21", "1e-7".
  static func numberString(_ value: Double) -> String {
    if value.isNaN { return "NaN" }
    if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
    if value == 0 { return "0" }
    if value < 0 { return "-" + numberString(-value) }
    // Swift's description has the shortest digits that read back as the
    // same number, as JavaScript's does; only the layout differs.
    let text = value.description
    var mantissa = Substring(text)
    var exponent = 0
    if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
      mantissa = text[..<e]
      exponent = Int(text[text.index(after: e)...]) ?? 0
    }
    let pieces = mantissa.split(separator: ".", omittingEmptySubsequences: false)
    let whole = pieces.first.map(String.init) ?? ""
    let fraction = pieces.count > 1 ? String(pieces[1]) : ""
    var digits = Array(whole + fraction)
    var point = whole.count + exponent
    while digits.first == "0" {
      digits.removeFirst()
      point -= 1
    }
    while digits.last == "0" { digits.removeLast() }
    let k = digits.count
    let n = point
    let all = String(digits)
    if k <= n && n <= 21 { return all + String(repeating: "0", count: n - k) }
    if 0 < n && n <= 21 { return String(digits[0..<n]) + "." + String(digits[n...]) }
    if -6 < n && n <= 0 { return "0." + String(repeating: "0", count: -n) + all }
    let e = n - 1
    let rest = k > 1 ? "." + String(digits[1...]) : ""
    return String(digits[0]) + rest + "e" + (e < 0 ? "-" : "+") + String(abs(e))
  }

  /// `Number(value)`, near enough for stored records: numbers as they are,
  /// numeric text read, booleans 1 and 0, null 0, anything else NaN.
  static func toNumber(_ value: JSONValue?) -> Double {
    guard let value else { return .nan }
    switch value {
    case .number(let number): return number
    case .bool(let flag): return flag ? 1 : 0
    case .null: return 0
    case .string(let text):
      let trimmed = trim(text)
      if trimmed.isEmpty { return 0 }
      if trimmed == "Infinity" || trimmed == "+Infinity" { return .infinity }
      if trimmed == "-Infinity" { return -.infinity }
      guard isDecimalLiteral(trimmed) else { return .nan }
      return Double(trimmed) ?? .nan
    case .array, .object:
      return .nan
    }
  }

  /// `[+-]?(digits[.digits?]|.digits)([eE][+-]?digits)?`
  private static func isDecimalLiteral(_ text: String) -> Bool {
    var scalars = Array(text.unicodeScalars)[...]
    if let sign = scalars.first, sign == "+" || sign == "-" { scalars = scalars.dropFirst() }
    var whole = 0
    while let s = scalars.first, isDigit(s) {
      whole += 1
      scalars = scalars.dropFirst()
    }
    var fraction = 0
    if scalars.first == "." {
      scalars = scalars.dropFirst()
      while let s = scalars.first, isDigit(s) {
        fraction += 1
        scalars = scalars.dropFirst()
      }
    }
    if whole == 0 && fraction == 0 { return false }
    if let e = scalars.first, e == "e" || e == "E" {
      scalars = scalars.dropFirst()
      if let sign = scalars.first, sign == "+" || sign == "-" { scalars = scalars.dropFirst() }
      var digits = 0
      while let s = scalars.first, isDigit(s) {
        digits += 1
        scalars = scalars.dropFirst()
      }
      if digits == 0 { return false }
    }
    return scalars.isEmpty
  }

  // MARK: Values

  /// `Boolean(value)`; a missing value (`undefined`) is false.
  static func truthy(_ value: JSONValue?) -> Bool {
    guard let value else { return false }
    switch value {
    case .null: return false
    case .bool(let flag): return flag
    case .number(let number): return number != 0 && !number.isNaN
    case .string(let text): return !text.isEmpty
    case .array, .object: return true
    }
  }

  /// A present value: neither missing (`undefined`) nor `null`.
  static func present(_ value: JSONValue?) -> JSONValue? {
    if let value, !value.isNull { return value }
    return nil
  }

  /// `String(value)`; a missing value is "undefined".
  static func string(_ value: JSONValue?) -> String {
    guard let value else { return "undefined" }
    switch value {
    case .null: return "null"
    case .bool(let flag): return flag ? "true" : "false"
    case .number(let number): return numberString(number)
    case .string(let text): return text
    case .array(let items):
      return items.map { $0.isNull ? "" : string($0) }.joined(separator: ",")
    case .object: return "[object Object]"
    }
  }

  /// `JSON.stringify(value)`. JavaScript writes an object's keys in the order
  /// they were made; a stored record has no order, so they come sorted here.
  static func json(_ value: JSONValue) -> String {
    switch value {
    case .null: return "null"
    case .bool(let flag): return flag ? "true" : "false"
    case .number(let number): return number.isFinite ? numberString(number) : "null"
    case .string(let text): return quote(text)
    case .array(let items): return "[" + items.map(json).joined(separator: ",") + "]"
    case .object(let fields):
      let keys = fields.keys.sorted(by: less)
      return "{" + keys.map { key in quote(key) + ":" + json(fields[key] ?? .null) }.joined(separator: ",") + "}"
    }
  }

  /// A JSON string literal, escaped as `JSON.stringify` escapes it.
  static func quote(_ text: String) -> String {
    var out = "\""
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 0x22: out += "\\\""
      case 0x5C: out += "\\\\"
      case 0x08: out += "\\b"
      case 0x09: out += "\\t"
      case 0x0A: out += "\\n"
      case 0x0C: out += "\\f"
      case 0x0D: out += "\\r"
      case 0x00..<0x20:
        let hex = String(scalar.value, radix: 16)
        out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
      default: out.unicodeScalars.append(scalar)
      }
    }
    return out + "\""
  }

  /// The fields of a record (`asRow`): an object's fields, none for another
  /// value, and nil for `null` or a missing record.
  static func object(_ value: JSONValue?) -> [String: JSONValue]? {
    guard let value else { return nil }
    switch value {
    case .null: return nil
    case .object(let fields): return fields
    default: return [:]
    }
  }

  /// `{ ...value }`: an object's fields, the characters of a text or the items
  /// of a list under their index, and nothing for anything else.
  static func spread(_ value: JSONValue?) -> [String: JSONValue] {
    guard let value else { return [:] }
    switch value {
    case .object(let fields): return fields
    case .array(let items):
      var out: [String: JSONValue] = [:]
      for (i, item) in items.enumerated() { out[String(i)] = item }
      return out
    case .string(let text):
      var out: [String: JSONValue] = [:]
      for (i, unit) in text.utf16.enumerated() { out[String(i)] = .string(String(decoding: [unit], as: UTF16.self)) }
      return out
    default:
      return [:]
    }
  }

  /// `value[key]`: a field of an object, an item of a list or a character of a
  /// text by its index (and their `length`); nothing otherwise.
  static func property(_ value: JSONValue?, _ key: String) -> JSONValue? {
    guard let value else { return nil }
    switch value {
    case .object(let fields): return fields[key]
    case .array(let items):
      if key == "length" { return .number(Double(items.count)) }
      guard let index = arrayIndex(key), index < items.count else { return nil }
      return items[index]
    case .string(let text):
      let units = Array(text.utf16)
      if key == "length" { return .number(Double(units.count)) }
      guard let index = arrayIndex(key), index < units.count else { return nil }
      return .string(String(decoding: [units[index]], as: UTF16.self))
    default:
      return nil
    }
  }

  /// A key that names an array index ("0", "12"; not "01" or "-1").
  private static func arrayIndex(_ key: String) -> Int? {
    guard let index = Int(key), index >= 0, String(index) == key else { return nil }
    return index
  }

  /// JSON without its nulls, at every level, as jsonb_strip_nulls (and the
  /// web's stripNulls): null items of a list stay.
  static func stripNulls(_ value: JSONValue) -> JSONValue {
    switch value {
    case .array(let items): return .array(items.map(stripNulls))
    case .object(let fields):
      var out: [String: JSONValue] = [:]
      for (key, field) in fields where !field.isNull { out[key] = stripNulls(field) }
      return .object(out)
    default:
      return value
    }
  }

  /// `sameData` of src/cloud/roles.ts: deep equality of JSON data where a
  /// missing value and null are the same at the top, but a field set to null
  /// is not a missing field.
  static func sameData(_ a: JSONValue?, _ b: JSONValue?) -> Bool {
    (a ?? .null) == (b ?? .null)
  }
}
