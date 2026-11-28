import Foundation

/// decimal.js-light as the web configures it (src/lib/money.ts: precision
/// 40, `ROUND_HALF_UP`), for the stock writes: costing, the split of landed
/// costs and the parts of a document's lines must give the web's figures to
/// the fils, ties included.
///
/// decimal.js-light *truncates* the result of `plus`, `minus`, `times` and
/// `dividedBy` to 40 significant digits; only `toDecimalPlaces` rounds (half
/// away from zero). Foundation's `Decimal` keeps 38 digits and rounds, which
/// can tip a value that should be exactly half a fils (1.5 × 1001 / 3) to
/// the other side, so the ports compute with this type instead.
struct IwDecimal: Sendable, Equatable, CustomStringConvertible {
  /// Most significant first, no leading or trailing zeros; empty for zero.
  private(set) var digits: [UInt8]
  /// The value is `digits × 10^exponent`.
  private(set) var exponent: Int
  private(set) var negative: Bool

  /// decimal.js-light's `precision`.
  static let precision = 40

  static let zero = IwDecimal(negative: false, digits: [], exponent: 0)
  static let one = IwDecimal(1)

  init(negative: Bool, digits: [UInt8], exponent: Int) {
    var digits = digits
    var exponent = exponent
    let leading = digits.firstIndex { $0 != 0 } ?? digits.count
    if leading > 0 { digits.removeFirst(leading) }
    while let last = digits.last, last == 0 {
      digits.removeLast()
      exponent += 1
    }
    self.digits = digits
    self.exponent = digits.isEmpty ? 0 : exponent
    self.negative = digits.isEmpty ? false : negative
  }

  init(_ value: Int) {
    var magnitude = value.magnitude
    var out: [UInt8] = []
    while magnitude > 0 {
      out.append(UInt8(magnitude % 10))
      magnitude /= 10
    }
    self.init(negative: value < 0, digits: out.reversed(), exponent: 0)
  }

  /// `dec(n)`: the number's shortest string (`String(n)`); 0 when not finite.
  init(_ value: Double) {
    guard value.isFinite, value != 0 else {
      self = .zero
      return
    }
    let parsed = DigitString(shortest: value)
    self.init(negative: parsed.negative, digits: parsed.digits, exponent: parsed.exponent)
  }

  /// `dec(value)` for a stored value: numbers as `dec(n)`, text as
  /// decimal.js-light reads it (0 when it can't), anything else 0.
  init(_ value: JSONValue?) {
    switch value {
    case .number(let number)?:
      self.init(number)
    case .string(let text)?:
      let trimmed = WebJS.trim(text)
      if trimmed.isEmpty {
        self = .zero
      } else if let parsed = DigitString(text: trimmed) {
        self.init(negative: parsed.negative, digits: parsed.digits, exponent: parsed.exponent)
      } else {
        self = .zero
      }
    default:
      self = .zero
    }
  }

  /// `new Decimal(10).pow(places)` for a whole number of places.
  static func power(_ places: Int) -> IwDecimal {
    IwDecimal(negative: false, digits: [1], exponent: places)
  }

  // MARK: Reading

  var isZero: Bool { digits.isEmpty }
  var isNegative: Bool { negative }

  /// Where the decimal point falls: the value is `0.digits × 10^point`.
  private var point: Int { digits.count + exponent }

  /// `toNumber()`: the nearest double.
  func toNumber() -> Double {
    if digits.isEmpty { return 0 }
    var text = negative ? "-" : ""
    text.reserveCapacity(digits.count + 8)
    for digit in digits { text.unicodeScalars.append(Unicode.Scalar(digit + 48)) }
    text += "e" + String(exponent)
    let number = Double(text) ?? 0
    return number == 0 ? 0 : number
  }

  /// The value as a whole number (for figures already rounded to units).
  func toInt() -> Int {
    let number = toNumber()
    guard number.isFinite, Swift.abs(number) < 9.0e18 else { return 0 }
    return Int(number)
  }

  /// Plain digits ("-12.5", "0.001", "300"), the same text for the same value.
  var description: String {
    if digits.isEmpty { return "0" }
    let text = String(decoding: digits.map { $0 + 48 }, as: UTF8.self)
    let sign = negative ? "-" : ""
    if exponent >= 0 { return sign + text + String(repeating: "0", count: exponent) }
    let p = point
    if p <= 0 { return sign + "0." + String(repeating: "0", count: -p) + text }
    let split = text.index(text.startIndex, offsetBy: p)
    return sign + text[..<split] + "." + text[split...]
  }

  // MARK: Comparing

  /// -1, 0 or 1 for the magnitudes.
  private static func compareMagnitude(_ a: IwDecimal, _ b: IwDecimal) -> Int {
    if a.digits.isEmpty || b.digits.isEmpty {
      if a.digits.isEmpty && b.digits.isEmpty { return 0 }
      return a.digits.isEmpty ? -1 : 1
    }
    if a.point != b.point { return a.point < b.point ? -1 : 1 }
    let count = max(a.digits.count, b.digits.count)
    for index in 0..<count {
      let x = index < a.digits.count ? a.digits[index] : 0
      let y = index < b.digits.count ? b.digits[index] : 0
      if x != y { return x < y ? -1 : 1 }
    }
    return 0
  }

  static func compare(_ a: IwDecimal, _ b: IwDecimal) -> Int {
    if a.negative != b.negative {
      if a.isZero && b.isZero { return 0 }
      return a.negative ? -1 : 1
    }
    let magnitude = compareMagnitude(a, b)
    return a.negative ? -magnitude : magnitude
  }

  func gt(_ other: IwDecimal) -> Bool { Self.compare(self, other) > 0 }
  func lt(_ other: IwDecimal) -> Bool { Self.compare(self, other) < 0 }
  func eq(_ other: IwDecimal) -> Bool { Self.compare(self, other) == 0 }

  func negated() -> IwDecimal {
    IwDecimal(negative: !negative, digits: digits, exponent: exponent)
  }

  func abs() -> IwDecimal {
    IwDecimal(negative: false, digits: digits, exponent: exponent)
  }

  // MARK: Arithmetic (truncated to 40 significant digits)

  /// The value cut (toward zero) to decimal.js-light's precision.
  private func truncated() -> IwDecimal {
    guard digits.count > Self.precision else { return self }
    let drop = digits.count - Self.precision
    return IwDecimal(negative: negative, digits: Array(digits.prefix(Self.precision)), exponent: exponent + drop)
  }

  /// Both digit strings at the same (lower) exponent.
  private static func aligned(_ a: IwDecimal, _ b: IwDecimal) -> (a: [UInt8], b: [UInt8], exponent: Int) {
    let e = min(a.exponent, b.exponent)
    let x = a.digits + [UInt8](repeating: 0, count: a.exponent - e)
    let y = b.digits + [UInt8](repeating: 0, count: b.exponent - e)
    return (x, y, e)
  }

  private static func addDigits(_ x: [UInt8], _ y: [UInt8]) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: max(x.count, y.count) + 1)
    var carry: UInt8 = 0
    var i = x.count - 1
    var j = y.count - 1
    var k = out.count - 1
    while k >= 0 {
      let sum = (i >= 0 ? x[i] : 0) + (j >= 0 ? y[j] : 0) + carry
      out[k] = sum % 10
      carry = sum / 10
      i -= 1
      j -= 1
      k -= 1
    }
    return out
  }

  /// x − y for magnitudes with x ≥ y.
  private static func subtractDigits(_ x: [UInt8], _ y: [UInt8]) -> [UInt8] {
    var out = x
    var borrow: Int = 0
    var i = x.count - 1
    var j = y.count - 1
    while i >= 0 {
      var value = Int(x[i]) - borrow - (j >= 0 ? Int(y[j]) : 0)
      if value < 0 {
        value += 10
        borrow = 1
      } else {
        borrow = 0
      }
      out[i] = UInt8(value)
      i -= 1
      j -= 1
    }
    return out
  }

  func plus(_ other: IwDecimal) -> IwDecimal {
    if other.isZero { return truncated() }
    if isZero { return other.truncated() }
    let (x, y, e) = Self.aligned(self, other)
    if negative == other.negative {
      return IwDecimal(negative: negative, digits: Self.addDigits(x, y), exponent: e).truncated()
    }
    let order = Self.compareMagnitude(self, other)
    if order == 0 { return .zero }
    if order > 0 {
      return IwDecimal(negative: negative, digits: Self.subtractDigits(x, y), exponent: e).truncated()
    }
    return IwDecimal(negative: other.negative, digits: Self.subtractDigits(y, x), exponent: e).truncated()
  }

  func minus(_ other: IwDecimal) -> IwDecimal { plus(other.negated()) }

  func times(_ other: IwDecimal) -> IwDecimal {
    if isZero || other.isZero { return .zero }
    var accumulator = [Int](repeating: 0, count: digits.count + other.digits.count)
    for i in stride(from: digits.count - 1, through: 0, by: -1) {
      let a = Int(digits[i])
      if a == 0 { continue }
      for j in stride(from: other.digits.count - 1, through: 0, by: -1) {
        accumulator[i + j + 1] += a * Int(other.digits[j])
      }
    }
    var carry = 0
    for k in stride(from: accumulator.count - 1, through: 0, by: -1) {
      let value = accumulator[k] + carry
      accumulator[k] = value % 10
      carry = value / 10
    }
    let product = accumulator.map { UInt8($0) }
    return IwDecimal(negative: negative != other.negative, digits: product, exponent: exponent + other.exponent)
      .truncated()
  }

  /// `dividedBy`: the quotient cut to 40 significant digits. Division by
  /// zero gives 0 (the web throws; the ports never divide by zero).
  func dividedBy(_ other: IwDecimal) -> IwDecimal {
    if isZero || other.isZero { return .zero }
    // Enough places that the whole quotient has more than 40 digits.
    let shift = max(0, Self.precision + other.digits.count - digits.count + 1)
    let dividend = digits + [UInt8](repeating: 0, count: shift)
    let quotient = Self.divideDigits(dividend, by: other.digits)
    return IwDecimal(
      negative: negative != other.negative, digits: quotient, exponent: exponent - other.exponent - shift
    ).truncated()
  }

  /// The whole part of x ÷ y for digit strings (y without leading zeros).
  private static func divideDigits(_ x: [UInt8], by y: [UInt8]) -> [UInt8] {
    // A divisor of up to 18 digits fits a UInt64 with room for one more digit.
    if y.count <= 18 {
      var divisor: UInt64 = 0
      for digit in y { divisor = divisor * 10 + UInt64(digit) }
      var remainder: UInt64 = 0
      var out = [UInt8]()
      out.reserveCapacity(x.count)
      for digit in x {
        remainder = remainder * 10 + UInt64(digit)
        out.append(UInt8(remainder / divisor))
        remainder %= divisor
      }
      return out
    }
    var remainder: [UInt8] = []
    var out = [UInt8]()
    out.reserveCapacity(x.count)
    for digit in x {
      remainder.append(digit)
      if let first = remainder.firstIndex(where: { $0 != 0 }) {
        if first > 0 { remainder.removeFirst(first) }
      } else {
        remainder = []
      }
      var count: UInt8 = 0
      while !lessMagnitude(remainder, y) {
        remainder = subtractDigits(remainder, y)
        if let first = remainder.firstIndex(where: { $0 != 0 }) {
          if first > 0 { remainder.removeFirst(first) }
        } else {
          remainder = []
        }
        count += 1
      }
      out.append(count)
    }
    return out
  }

  /// x < y for whole numbers as digit strings without leading zeros.
  private static func lessMagnitude(_ x: [UInt8], _ y: [UInt8]) -> Bool {
    if x.count != y.count { return x.count < y.count }
    for (a, b) in zip(x, y) where a != b { return a < b }
    return false
  }

  // MARK: Rounding

  /// `toDecimalPlaces(places, ROUND_HALF_UP)`: half away from zero.
  func toDecimalPlaces(_ places: Int) -> IwDecimal {
    if digits.isEmpty || exponent >= -places { return self }
    let keep = digits.count - (-places - exponent)
    if keep < 0 { return .zero }
    var kept = Array(digits.prefix(keep))
    let roundUp = digits[keep] >= 5
    if roundUp {
      var index = kept.count - 1
      var carried = true
      while index >= 0 {
        if kept[index] == 9 {
          kept[index] = 0
          index -= 1
        } else {
          kept[index] += 1
          carried = false
          break
        }
      }
      if carried { kept.insert(1, at: 0) }
    }
    return IwDecimal(negative: negative, digits: kept, exponent: -places)
  }
}

/// The web's money helpers on `IwDecimal` (src/lib/money.ts).
enum IwMoney {
  /// `round(value, places)`: half away from zero, as a number (never -0).
  static func round(_ value: IwDecimal, _ places: Int) -> Double {
    value.toDecimalPlaces(places).toNumber()
  }

  static func round(_ value: Double, _ places: Int) -> Double {
    round(IwDecimal(value), places)
  }

  /// `toMinor(value, places)`: whole minor units, half away from zero.
  static func toMinor(_ value: IwDecimal, _ places: Int) -> Int {
    value.times(IwDecimal.power(places)).toDecimalPlaces(0).toInt()
  }

  static func toMinor(_ value: Double, _ places: Int) -> Int {
    toMinor(IwDecimal(value), places)
  }

  /// `fromMinor(minor, places)`: back to an amount, as a number (never -0).
  static func fromMinor(_ minor: Int, _ places: Int) -> Double {
    IwDecimal(minor).dividedBy(IwDecimal.power(places)).toNumber()
  }

  /// `Math.round(x)`: the nearest whole number, halves toward +∞.
  static func jsRound(_ value: Double) -> Double {
    guard value.isFinite else { return value }
    let floor = value.rounded(.down)
    let result = value - floor >= 0.5 ? floor + 1 : floor
    return result == 0 ? 0 : result
  }
}
