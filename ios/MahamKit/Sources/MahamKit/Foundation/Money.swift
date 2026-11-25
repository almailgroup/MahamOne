import Foundation

// The port of the web's `src/lib/money.ts`. Amounts are `Decimal`s built
// from text, never from a Double's binary value: a Double goes through its
// shortest string first, as `dec()` goes through `String(n)`, so 0.1 stays
// 0.1. Rounding is half away from zero and never gives -0.

/// A number the money and format helpers take: `Decimal`, `Double` or an
/// integer.
public protocol MoneyValue: Sendable {
  /// The value as the web's `dec(value)` makes it.
  var moneyDecimal: Decimal { get }
  /// The value as a JavaScript number holds it.
  var moneyNumber: Double { get }
}

extension Decimal: MoneyValue {
  public var moneyDecimal: Decimal { self }
  public var moneyNumber: Double { Money.toNumber(self) }
}

extension Double: MoneyValue {
  public var moneyDecimal: Decimal { Money.dec(self) }
  public var moneyNumber: Double { self }
}

extension Int: MoneyValue {
  public var moneyDecimal: Decimal { Decimal(self) }
  public var moneyNumber: Double { Double(self) }
}

extension Int64: MoneyValue {
  public var moneyDecimal: Decimal { Decimal(self) }
  public var moneyNumber: Double { Double(self) }
}

public enum Money {
  // MARK: Decimals

  /// `dec(n)`: the number's shortest string as a Decimal (0 when it is not
  /// finite).
  public static func dec(_ value: Double) -> Decimal {
    guard value.isFinite else { return 0 }
    return DigitString(shortest: value).decimal ?? .nan
  }

  public static func dec(_ value: Int) -> Decimal { Decimal(value) }

  /// `dec(text)`: the trimmed text as decimal.js-light reads it
  /// (`-?(\d+(\.\d*)?|\.\d+)(e[+-]?\d+)?`), 0 when it is empty or not a
  /// number.
  public static func dec(_ value: String?) -> Decimal {
    guard let value else { return 0 }
    let trimmed = JSText.trim(value)
    if trimmed.isEmpty { return 0 }
    guard let digits = DigitString(text: trimmed) else { return 0 }
    return digits.decimal ?? .nan
  }

  /// Rounds half away from zero, which is what invoices conventionally use;
  /// never -0.
  public static func round(_ value: some MoneyValue, _ places: Int) -> Decimal {
    var source = value.moneyDecimal
    var result = Decimal()
    NSDecimalRound(&result, &source, places, .plain)
    return result.isZero ? 0 : result
  }

  public static func sum(_ values: [some MoneyValue]) -> Decimal {
    values.reduce(Decimal(0)) { $0 + $1.moneyDecimal }
  }

  /// `decimal.toNumber()`: the nearest Double.
  public static func toNumber(_ value: Decimal) -> Double {
    if value.isNaN { return .nan }
    return Double(value.description) ?? 0
  }

  /// `String(n)`: how JavaScript writes a number ("0.1", "1e-7", "1e+21").
  public static func jsString(_ value: Double) -> String {
    if value.isNaN { return "NaN" }
    if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
    return DigitString(shortest: value).javaScriptText
  }

  // MARK: Currencies

  /// Number of minor-unit digits for an ISO 4217 currency (USD 2, JPY 0,
  /// KWD 3): the digits Node's `Intl.NumberFormat` uses (ICU 78, CLDR 48).
  /// Any other code, known or not, has 2.
  public static func precision(_ currency: String) -> Int {
    precisions[currency.uppercased()] ?? 2
  }

  private static let precisions: [String: Int] = {
    var table: [String: Int] = [:]
    let zero = [
      "ADP", "AFN", "ALL", "BIF", "BYR", "CLP", "COP", "DJF", "ESP", "GNF", "HUF", "IDR", "IQD",
      "IRR", "ISK", "ITL", "JPY", "KMF", "KPW", "KRW", "LAK", "LBP", "LUF", "MGA", "MGF", "MMK",
      "MRO", "PKR", "PYG", "RWF", "SLL", "SOS", "STD", "SYP", "TMM", "TRL", "UGX", "UYI", "VND",
      "VUV", "XAF", "XOF", "XPF", "YER", "ZMK", "ZWD",
    ]
    for code in zero { table[code] = 0 }
    for code in ["BHD", "JOD", "KWD", "LYD", "OMR", "TND"] { table[code] = 3 }
    for code in ["CLF", "UYW"] { table[code] = 4 }
    return table
  }()

  // MARK: Input

  /// Turns Arabic-Indic (٠-٩) and Persian (۰-۹) digits into 0-9 and the
  /// Arabic decimal and thousands separators into "." and ",", so amounts
  /// typed on an Arabic keyboard are understood.
  public static func normalizeDigits(_ input: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in input.unicodeScalars {
      switch scalar.value {
      case 0x0660...0x0669:
        scalars.append(Unicode.Scalar(UInt8(ascii: "0") + UInt8(scalar.value - 0x0660)))
      case 0x06F0...0x06F9:
        scalars.append(Unicode.Scalar(UInt8(ascii: "0") + UInt8(scalar.value - 0x06F0)))
      case 0x066B:
        scalars.append(".")
      case 0x066C, 0x060C:
        scalars.append(",")
      default:
        scalars.append(scalar)
      }
    }
    return String(scalars)
  }

  /// Parses user input such as "1,234.50" or "12.5%" into a number (0 when
  /// invalid).
  public static func parseAmount(_ input: String?) -> Double {
    guard let input, !input.isEmpty else { return 0 }
    // Spaces, commas and % go; then everything but digits, ".", "+" and "-".
    let kept = normalizeDigits(input).unicodeScalars.filter { scalar in
      if JSText.isWhitespace(scalar) { return false }
      switch scalar {
      case "0"..."9", ".", "+", "-": return true
      default: return false
      }
    }
    let n = javaScriptNumber(String(String.UnicodeScalarView(kept)))
    return n.isFinite ? n : 0
  }

  public static func parseAmount(_ input: Double) -> Double {
    input.isFinite ? input : 0
  }

  /// `Number(text)` for text of digits, ".", "+" and "-": NaN unless it is
  /// one optional sign and a decimal number; "" is 0.
  private static func javaScriptNumber(_ text: String) -> Double {
    var body = Substring(text)
    if body.isEmpty { return 0 }
    var negative = false
    if let sign = body.first, sign == "+" || sign == "-" {
      negative = sign == "-"
      body = body.dropFirst()
    }
    let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let integer = parts.first ?? ""
    let fraction = parts.count > 1 ? parts[1] : ""
    let isDigits: (Substring) -> Bool = { $0.allSatisfy { $0 >= "0" && $0 <= "9" } }
    guard isDigits(integer), isDigits(fraction), !(integer.isEmpty && fraction.isEmpty) else {
      return .nan
    }
    let normalized =
      (negative ? "-" : "") + (integer.isEmpty ? "0" : integer) + "." + (fraction.isEmpty ? "0" : fraction)
    return Double(normalized) ?? .nan
  }

  // MARK: Minor units

  /// Converts an amount to integer minor units (pence, fils, cents),
  /// rounding half away from zero. Ledger sums use these so they are exact.
  public static func toMinor(_ value: some MoneyValue, _ places: Int) -> Int64 {
    var scaled = value.moneyDecimal * power(places)
    var result = Decimal()
    NSDecimalRound(&result, &scaled, 0, .plain)
    if result.isNaN { return 0 }
    if let whole = DigitString(decimal: result).int64 { return whole }
    return result < 0 ? .min : .max
  }

  /// Converts integer minor units back to an amount with `places` decimals.
  public static func fromMinor(_ minor: Int64, _ places: Int) -> Decimal {
    let result = Decimal(minor) / power(places)
    return result.isZero ? 0 : result
  }

  /// True when two amounts are equal to the currency's smallest unit (fils,
  /// cents).
  public static func sameAmount(_ a: some MoneyValue, _ b: some MoneyValue, currency: String) -> Bool {
    let places = precision(currency)
    return toMinor(a, places) == toMinor(b, places)
  }

  /// 10 to the power `places` (which may be negative).
  private static func power(_ places: Int) -> Decimal {
    Decimal(sign: .plus, exponent: max(-127, min(127, places)), significand: 1)
  }
}

// MARK: The first native screens' helpers

extension Money {
  /// The currency's decimals; the same as `precision(_:)`.
  public static func fractionDigits(_ currency: String) -> Int {
    precision(currency)
  }

  /// An amount in the device's own number style, as the first native
  /// screens show it. Screens that match the web use `Format.money`.
  public static func format(_ amount: Double, currency: String, locale: Locale = .current) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    formatter.locale = locale
    let digits = fractionDigits(currency)
    formatter.minimumFractionDigits = digits
    formatter.maximumFractionDigits = digits
    return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(amount)"
  }
}
