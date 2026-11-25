import Foundation

/// When a numbering rule's counter starts again from 1.
public enum CounterReset: String, CaseIterable, Sendable {
  case never, yearly, monthly
}

/// A numbering rule as the company record stores it
/// (`company.numbering[kind]`: `{pattern, next, padding, reset, period}`).
/// It reads from and writes into the stored JSON, so fields this version
/// doesn't know stay as they were.
public struct NumberingRule: Hashable, Sendable {
  public var raw: JSONValue

  public init(_ raw: JSONValue) {
    self.raw = raw
  }

  public init(pattern: String, next: Int = 1, padding: Int = 4, reset: CounterReset = .never, period: String = "") {
    raw = [
      "pattern": .string(pattern),
      "next": .number(Double(next)),
      "padding": .number(Double(padding)),
      "reset": .string(reset.rawValue),
      "period": .string(period),
    ]
  }

  /// e.g. "INV-{year}-{counter}"; empty when it isn't text.
  public var pattern: String { raw["pattern"]?.string ?? "" }
  /// The next counter, as JavaScript reads it (`Number(next)`).
  public var next: Double { WebJS.toNumber(raw["next"]) }
  /// The counter's minimum digits, as JavaScript reads it.
  public var padding: Double { WebJS.toNumber(raw["padding"]) }
  /// "never", "yearly", "monthly", or a value of a newer version (which
  /// counts as no reset period, as on the web).
  public var reset: String { raw["reset"]?.string ?? "" }
  /// The period ("2026" or "2026-10") the counter was last used in.
  public var period: JSONValue? { raw["period"] }
}

/// A number given out, and the rule to store back on the company.
public struct NumberAllocation: Hashable, Sendable {
  public var number: String
  public var rule: NumberingRule
}

/// A counter taken on the server for one new number (`reserve_number`).
public struct ReservedCounter: Hashable, Sendable {
  public var counter: Int
  /// The period key the counter belongs to.
  public var period: String

  public init(counter: Int, period: String) {
    self.counter = counter
    self.period = period
  }
}

/// Document, letter and item numbers (src/lib/numbering.ts).
public enum Numbering {
  public static let placeholders: [(token: String, description: String)] = [
    ("{counter}", "Sequential counter, zero padded (required)"),
    ("{year}", "Year of the document date, e.g. 2026"),
    ("{yy}", "Two-digit year, e.g. 26"),
    ("{month}", "Two-digit month, e.g. 09"),
    ("{day}", "Two-digit day, e.g. 05"),
    ("{client}", "The client's number"),
  ]

  /// The numbered kinds, in the web's order (`defaultNumbering`).
  public static let kinds: [String] = [
    "invoice", "quote", "credit", "payment", "payment_made", "client", "journal", "bill", "vendor_credit",
    "expense", "employee", "proforma", "sales_order", "purchase_order", "delivery_note", "product", "letter",
  ]

  /// The rules a new company starts with (`defaultNumbering` in src/db/defaults.ts).
  public static func defaultRules() -> [String: NumberingRule] {
    let rule = { (pattern: String, padding: Int) in NumberingRule(pattern: pattern, padding: padding) }
    return [
      "invoice": rule("INV-{year}-{counter}", 4),
      "quote": rule("QUO-{year}-{counter}", 4),
      "credit": rule("CN-{year}-{counter}", 4),
      "payment": rule("PAY-{counter}", 4),
      "payment_made": rule("PM-{counter}", 4),
      "client": rule("C-{counter}", 4),
      "journal": rule("JE-{year}-{counter}", 4),
      "bill": rule("BILL-{year}-{counter}", 4),
      "vendor_credit": rule("VC-{year}-{counter}", 4),
      "expense": rule("EXP-{year}-{counter}", 4),
      "employee": rule("EMP-{counter}", 3),
      "proforma": rule("PF-{year}-{counter}", 4),
      "sales_order": rule("SO-{year}-{counter}", 4),
      "purchase_order": rule("PO-{year}-{counter}", 4),
      "delivery_note": rule("DN-{year}-{counter}", 4),
      // Item codes: used only when Company.items.autoSku is on.
      "product": rule("SKU-{counter}", 5),
      // Employee letters, numbered when issued: HR-2026-0001, from 1 again each year.
      "letter": NumberingRule(pattern: "HR-{year}-{counter}", reset: .yearly),
    ]
  }

  /// The period a counter belongs to: the year, the month, or none.
  public static func periodKey(_ reset: String, _ date: String) -> String {
    if reset == "yearly" { return WebJS.prefix(date, 4) }
    if reset == "monthly" { return WebJS.prefix(date, 7) }
    return ""
  }

  /// The counter to use for a document dated `date`, honouring yearly and monthly resets.
  public static func currentCounter(_ rule: NumberingRule, _ date: String) -> Int {
    let key = periodKey(rule.reset, date)
    if rule.reset != "never", WebJS.truthy(rule.period), rule.period != .string(key) { return 1 }
    // Math.max(1, Math.trunc(next) || 1)
    let next = rule.next.rounded(.towardZero)
    if next.isNaN || next < 1 { return 1 }
    return next >= 9_007_199_254_740_991 ? 9_007_199_254_740_991 : Int(next)
  }

  /// The number `rule` writes for `counter` on `date`. A pattern without
  /// `{counter}` gets it at the end; placeholders it doesn't know stay as
  /// they are.
  public static func formatNumber(_ rule: NumberingRule, _ counter: Int, _ date: String, _ clientNumber: String = "")
    -> String
  {
    formatNumber(pattern: rule.pattern, padding: rule.padding, counter: counter, date: date, clientNumber: clientNumber)
  }

  public static func formatNumber(
    pattern rulePattern: String, padding: Double, counter: Int, date: String, clientNumber: String = ""
  ) -> String {
    let padded = WebJS.padStart(String(counter), width(padding, least: 0))
    let pattern = withCounter(rulePattern)
    let parts = date.components(separatedBy: "-")
    let year = parts.count > 0 ? parts[0] : ""
    let month = parts.count > 1 ? parts[1] : ""
    let day = parts.count > 2 ? parts[2] : ""
    let values: [String: String] = [
      "counter": padded,
      "year": year,
      "yy": WebJS.suffix(year, 2),
      "month": month,
      "day": day,
      "client": clientNumber,
      // The web looks the placeholder up in a plain object, which also
      // answers for the names it inherits.
      "constructor": "function Object() { [native code] }",
      "__proto__": "[object Object]",
    ]
    var out = ""
    for piece in tokens(pattern) {
      switch piece {
      case .text(let text): out += text
      case .token(let name, let source): out += values[name.lowercased()] ?? source
      }
    }
    return out
  }

  /// Whether `text` is a number `rule` writes, for any counter and date
  /// (letters in any case): a code given by the app rather than typed in
  /// another way.
  public static func writtenBy(_ rule: NumberingRule, _ text: String) -> Bool {
    writtenBy(pattern: rule.pattern, padding: rule.padding, text)
  }

  public static func writtenBy(pattern rulePattern: String, padding: Double, _ text: String) -> Bool {
    let digits = width(padding, least: 1)
    var matcher: [Matcher.Piece] = []
    for piece in tokens(withCounter(rulePattern)) {
      switch piece {
      case .text(let text): matcher.append(.literal(Array(text.utf16)))
      case .token(let name, let source):
        switch name.lowercased() {
        case "counter": matcher.append(.digits(min: digits, max: nil))
        case "year": matcher.append(.digits(min: 4, max: 4))
        case "yy", "month", "day": matcher.append(.digits(min: 2, max: 2))
        case "client": matcher.append(.anything)
        default: matcher.append(.literal(Array(source.utf16)))
        }
      }
    }
    return Matcher(pieces: matcher).matches(Array(WebJS.trim(text).utf16))
  }

  /// Picks the next free number for a document dated `date`. Numbers already
  /// in use (typed in by hand, say) are skipped. Returns the number and the
  /// rule to store back on the company.
  public static func allocateNumber(
    _ rule: NumberingRule, _ date: String, clientNumber: String = "", isTaken: (String) -> Bool
  ) -> NumberAllocation {
    var counter = currentCounter(rule, date)
    var number = formatNumber(rule, counter, date, clientNumber)
    var tries = 0
    while isTaken(number) && tries < 100_000 {
      counter += 1
      number = formatNumber(rule, counter, date, clientNumber)
      tries += 1
    }
    var fields = WebJS.spread(rule.raw)
    fields["next"] = .number(Double(counter + 1))
    fields["period"] = .string(periodKey(rule.reset, date))
    return NumberAllocation(number: number, rule: NumberingRule(.object(fields)))
  }

  /// `allocateNumber` skipping the numbers in use whatever their case, as the
  /// web does: `taken` holds them in lower case (the web also trims them for
  /// documents, but not for journals).
  public static func allocateNumber(
    _ rule: NumberingRule, _ date: String, clientNumber: String = "", taken: Set<String>
  ) -> NumberAllocation {
    allocateNumber(rule, date, clientNumber: clientNumber) { taken.contains($0.lowercased()) }
  }

  /// `allocateNumber`, starting from a counter taken on the server when there
  /// is one for the document's period (never below this device's own counter).
  public static func allocateFrom(
    _ rule: NumberingRule, _ date: String, clientNumber: String, reserved: ReservedCounter?,
    isTaken: (String) -> Bool
  ) -> NumberAllocation {
    guard let reserved, reserved.period == periodKey(rule.reset, date) else {
      return allocateNumber(rule, date, clientNumber: clientNumber, isTaken: isTaken)
    }
    let next = max(reserved.counter, currentCounter(rule, date))
    var fields = WebJS.spread(rule.raw)
    fields["next"] = .number(Double(next))
    fields["period"] = .string(reserved.period)
    return allocateNumber(NumberingRule(.object(fields)), date, clientNumber: clientNumber, isTaken: isTaken)
  }

  /// The number a rule would give next, without changing it.
  public static func previewNumber(_ rule: NumberingRule, _ date: String, clientNumber: String = "C-0001") -> String {
    formatNumber(rule, currentCounter(rule, date), date, clientNumber)
  }

  // MARK: Patterns

  /// The pattern, trimmed, with `{counter}` at the end when it has none.
  private static func withCounter(_ rulePattern: String) -> String {
    var pattern = WebJS.trim(rulePattern)
    if pattern.isEmpty { pattern = "{counter}" }
    if !hasASCIICounter(pattern) { pattern += "{counter}" }
    return pattern
  }

  /// `/\{counter\}/i` (JavaScript's ignore-case matches ASCII letters only here).
  private static func hasASCIICounter(_ pattern: String) -> Bool {
    let wanted = Array("{counter}".utf8)
    let units = Array(pattern.utf16)
    guard units.count >= wanted.count else { return false }
    for start in 0...(units.count - wanted.count) {
      var all = true
      for (offset, byte) in wanted.enumerated() {
        let unit = units[start + offset]
        let lower = (unit >= 0x41 && unit <= 0x5A) ? unit + 0x20 : unit
        if lower != UInt16(byte) {
          all = false
          break
        }
      }
      if all { return true }
    }
    return false
  }

  /// `Math.max(least, Math.min(12, padding))`, as a length.
  private static func width(_ padding: Double, least: Int) -> Int {
    if padding.isNaN { return least }
    return Int(min(12, max(Double(least), padding)).rounded(.towardZero))
  }

  private enum Piece {
    case text(String)
    /// A `{word}` placeholder: its name, and the text as written.
    case token(String, String)
  }

  /// The pattern split at its `{word}` placeholders (`/\{(\w+)\}/g`).
  private static func tokens(_ pattern: String) -> [Piece] {
    let scalars = Array(pattern.unicodeScalars)
    var pieces: [Piece] = []
    var text = String.UnicodeScalarView()
    var i = 0
    while i < scalars.count {
      if scalars[i] == "{" {
        var j = i + 1
        while j < scalars.count, WebJS.isWordCharacter(scalars[j]) { j += 1 }
        if j > i + 1, j < scalars.count, scalars[j] == "}" {
          if !text.isEmpty {
            pieces.append(.text(String(text)))
            text = String.UnicodeScalarView()
          }
          var name = String.UnicodeScalarView()
          name.append(contentsOf: scalars[(i + 1)..<j])
          var source = String.UnicodeScalarView()
          source.append(contentsOf: scalars[i...j])
          pieces.append(.token(String(name), String(source)))
          i = j + 1
          continue
        }
      }
      text.append(scalars[i])
      i += 1
    }
    if !text.isEmpty { pieces.append(.text(String(text))) }
    return pieces
  }

  /// The regular expression `writtenBy` builds (`^…$`, ignoring case), matched
  /// over UTF-16 code units as JavaScript matches it.
  private struct Matcher {
    enum Piece {
      case literal([UInt16])
      /// `\d{min,max}`; no max for `\d{min,}`.
      case digits(min: Int, max: Int?)
      /// `.*`: anything but a line break.
      case anything
    }

    let pieces: [Piece]

    func matches(_ text: [UInt16]) -> Bool {
      match(0, 0, text)
    }

    private func match(_ piece: Int, _ at: Int, _ text: [UInt16]) -> Bool {
      guard piece < pieces.count else { return at == text.count }
      switch pieces[piece] {
      case .literal(let units):
        guard at + units.count <= text.count else { return false }
        for (offset, unit) in units.enumerated()
        where Self.canonical(unit) != Self.canonical(text[at + offset]) {
          return false
        }
        return match(piece + 1, at + units.count, text)
      case .digits(let least, let most):
        var end = at
        while end < text.count, text[end] >= 0x30, text[end] <= 0x39, most.map({ end - at < $0 }) ?? true {
          end += 1
        }
        guard end - at >= least else { return false }
        for stop in stride(from: end, through: at + least, by: -1) where match(piece + 1, stop, text) {
          return true
        }
        return false
      case .anything:
        var end = at
        while end < text.count, ![0x0A, 0x0D, 0x2028, 0x2029].contains(text[end]) { end += 1 }
        for stop in stride(from: end, through: at, by: -1) where match(piece + 1, stop, text) {
          return true
        }
        return false
      }
    }

    /// Canonicalize of JavaScript's ignore-case matching without the `u`
    /// flag: the upper case of a code unit when it is one code unit, and
    /// never from outside ASCII into it.
    private static func canonical(_ unit: UInt16) -> UInt16 {
      guard let scalar = Unicode.Scalar(UInt32(unit)) else { return unit }
      let upper = Array(String(scalar).uppercased().utf16)
      guard upper.count == 1 else { return unit }
      if unit >= 128 && upper[0] < 128 { return unit }
      return upper[0]
    }
  }
}
