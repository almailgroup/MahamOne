import Foundation

// What the web's JavaScript does with text and numbers, where Swift's own
// functions differ: which characters `\s` and `trim()` treat as white space,
// and how `String(n)` writes a number.

enum JSText {
  /// `\s` in a JavaScript regular expression, and what `trim()` removes:
  /// white space and line terminators.
  static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029,
      0x202F, 0x205F, 0x3000, 0xFEFF:
      true
    default:
      false
    }
  }

  /// What `.` in a JavaScript regular expression does not match.
  static func isLineTerminator(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x0A, 0x0D, 0x2028, 0x2029: true
    default: false
    }
  }

  /// `text.trim()`.
  static func trim(_ text: String) -> String {
    let scalars = text.unicodeScalars
    guard let first = scalars.firstIndex(where: { !isWhitespace($0) }),
      let last = scalars.lastIndex(where: { !isWhitespace($0) })
    else { return "" }
    return String(scalars[first...last])
  }

  /// `text.replace(/\s/g, '')`.
  static func removingWhitespace(_ text: String) -> String {
    var scalars = String.UnicodeScalarView()
    scalars.append(contentsOf: text.unicodeScalars.filter { !isWhitespace($0) })
    return String(scalars)
  }

  /// `text.slice(start)` counted in UTF-16 code units, as JavaScript counts.
  static func slice(_ text: String, from start: Int) -> String {
    let units = Array(text.utf16)
    let begin = start < 0 ? max(units.count + start, 0) : min(start, units.count)
    return String(decoding: units[begin...], as: UTF16.self)
  }

  /// `text.length`.
  static func length(_ text: String) -> Int { text.utf16.count }
}

/// A decimal number as digits: `digits × 10^exponent`, with no leading or
/// trailing zeros in `digits` (zero has none at all).
struct DigitString: Equatable, Sendable {
  var negative: Bool
  var digits: [UInt8]
  var exponent: Int

  static let zero = DigitString(negative: false, digits: [], exponent: 0)

  init(negative: Bool, digits: [UInt8], exponent: Int) {
    var digits = digits
    var exponent = exponent
    let leading = digits.firstIndex { $0 != 0 } ?? digits.count
    digits.removeFirst(leading)
    while let last = digits.last, last == 0 {
      digits.removeLast()
      exponent += 1
    }
    self.negative = digits.isEmpty ? false : negative
    self.digits = digits
    self.exponent = digits.isEmpty ? 0 : exponent
  }

  /// Reads `-?(\d+(\.\d*)?|\.\d+)(e[+-]?\d+)?`, the text decimal.js-light
  /// accepts and the way Swift writes a `Double` or a `Decimal`. Nil for
  /// anything else, including an exponent too large to hold.
  init?(text: String) {
    var bytes = Array(text.utf8)[...]
    var negative = false
    if bytes.first == UInt8(ascii: "-") {
      negative = true
      bytes = bytes.dropFirst()
    }
    var digits: [UInt8] = []
    var pointShift = 0
    var sawPoint = false
    var integerDigits = 0
    var fractionDigits = 0
    while let byte = bytes.first {
      if byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") {
        digits.append(byte - UInt8(ascii: "0"))
        if sawPoint {
          fractionDigits += 1
          pointShift -= 1
        } else {
          integerDigits += 1
        }
      } else if byte == UInt8(ascii: "."), !sawPoint {
        sawPoint = true
      } else {
        break
      }
      bytes = bytes.dropFirst()
    }
    // "5." and ".5" are numbers, "." is not.
    guard integerDigits > 0 || fractionDigits > 0 else { return nil }
    var exponent = 0
    if let byte = bytes.first, byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E") {
      bytes = bytes.dropFirst()
      var exponentNegative = false
      if let sign = bytes.first, sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") {
        exponentNegative = sign == UInt8(ascii: "-")
        bytes = bytes.dropFirst()
      }
      guard !bytes.isEmpty,
        bytes.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") })
      else { return nil }
      // Past a billion the exponent is out of decimal.js-light's range too.
      let significant = bytes.drop { $0 == UInt8(ascii: "0") }
      guard significant.count <= 9 else { return nil }
      for byte in significant { exponent = exponent * 10 + Int(byte - UInt8(ascii: "0")) }
      if exponentNegative { exponent = -exponent }
      bytes = bytes[bytes.endIndex...]
    }
    guard bytes.isEmpty else { return nil }
    self.init(negative: negative, digits: digits, exponent: exponent + pointShift)
  }

  /// The digits of a finite `Double`'s shortest round-trip form, which is
  /// what JavaScript's `String(n)` writes.
  init(shortest value: Double) {
    if value == 0 || !value.isFinite {
      self = .zero
      return
    }
    // Swift writes the shortest digits that read back as the same Double
    // ("0.1", "1e-07", "1.2345e+20"), choosing the closest when there are
    // several, as ECMAScript's Number::toString does.
    self = DigitString(text: value.magnitude.description) ?? .zero
    negative = value < 0
  }

  /// A `Decimal`'s digits.
  init(decimal: Decimal) {
    if decimal.isNaN || decimal.isZero {
      self = .zero
      return
    }
    self = DigitString(text: decimal.description) ?? .zero
  }

  var isZero: Bool { digits.isEmpty }

  /// Where the decimal point falls: the value is `0.digits × 10^pointPosition`.
  var pointPosition: Int { digits.count + exponent }

  /// The digits kept to at most `count`, rounding half up.
  func rounded(toSignificantDigits count: Int) -> DigitString {
    guard digits.count > count, count > 0 else { return self }
    var kept = Array(digits[0..<count])
    var exponent = self.exponent + (digits.count - count)
    if digits[count] >= 5 {
      var index = count - 1
      while index >= 0 {
        if kept[index] == 9 {
          kept[index] = 0
          index -= 1
        } else {
          kept[index] += 1
          break
        }
      }
      if index < 0 {
        kept.insert(1, at: 0)
        kept.removeLast()
        exponent += 1
      }
    }
    return DigitString(negative: negative, digits: kept, exponent: exponent)
  }

  /// The number as a `Decimal`: nil when it is too large for one. Decimal
  /// keeps 38 digits, so longer numbers are rounded (half up) to 38.
  var decimal: Decimal? {
    if isZero { return 0 }
    var value = rounded(toSignificantDigits: 38)
    // Decimal's exponent runs from -128 to 127.
    if value.exponent < -128 {
      let drop = -128 - value.exponent
      if drop > value.digits.count { return 0 }
      value = value.rounded(toSignificantDigits: value.digits.count - drop)
      if value.exponent < -128 { return 0 }
    }
    while value.exponent > 127, value.digits.count < 38 {
      value.digits.append(0)
      value.exponent -= 1
    }
    if value.exponent > 127 { return nil }
    var significand = Decimal(0)
    var chunk: UInt64 = 0
    var chunkScale: UInt64 = 1
    for digit in value.digits {
      chunk = chunk * 10 + UInt64(digit)
      chunkScale *= 10
      if chunkScale == 1_000_000_000_000_000_000 {
        significand = significand * Decimal(chunkScale) + Decimal(chunk)
        chunk = 0
        chunkScale = 1
      }
    }
    if chunkScale > 1 { significand = significand * Decimal(chunkScale) + Decimal(chunk) }
    return Decimal(sign: value.negative ? .minus : .plus, exponent: value.exponent, significand: significand)
  }

  /// The number as an integer, or nil when it has a fraction or does not fit.
  var int64: Int64? {
    if isZero { return 0 }
    guard exponent >= 0 else { return nil }
    var result: Int64 = 0
    for digit in digits + [UInt8](repeating: 0, count: exponent) {
      let (times, overflow) = result.multipliedReportingOverflow(by: 10)
      guard !overflow else { return nil }
      let (plus, overflow2) = times.addingReportingOverflow(Int64(digit))
      guard !overflow2 else { return nil }
      result = plus
    }
    return negative ? -result : result
  }

  /// The digits before the decimal point ("0" when there are none) and
  /// after it (without trailing zeros).
  var plainParts: (integer: String, fraction: String) {
    if isZero { return ("0", "") }
    let text = digits.map { Character(Unicode.Scalar($0 + UInt8(ascii: "0"))) }
    let point = pointPosition
    if exponent >= 0 {
      return (String(text) + String(repeating: "0", count: exponent), "")
    }
    if point <= 0 {
      return ("0", String(repeating: "0", count: -point) + String(text))
    }
    return (String(text[0..<point]), String(text[point...]))
  }

  /// ECMAScript's Number::toString for these digits.
  var javaScriptText: String {
    if isZero { return "0" }
    let text = String(digits.map { Character(Unicode.Scalar($0 + UInt8(ascii: "0"))) })
    let k = digits.count
    let n = pointPosition
    let sign = negative ? "-" : ""
    if k <= n, n <= 21 {
      return sign + text + String(repeating: "0", count: n - k)
    }
    if 0 < n, n <= 21 {
      let split = text.index(text.startIndex, offsetBy: n)
      return sign + text[..<split] + "." + text[split...]
    }
    if -6 < n, n <= 0 {
      return sign + "0." + String(repeating: "0", count: -n) + text
    }
    let e = n - 1
    let exponentText = (e < 0 ? "-" : "+") + String(e.magnitude)
    if k == 1 { return sign + text + "e" + exponentText }
    return sign + text.prefix(1) + "." + text.dropFirst() + "e" + exponentText
  }
}
