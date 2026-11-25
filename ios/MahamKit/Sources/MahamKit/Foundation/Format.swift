import Foundation

// The port of the web's `src/lib/format.ts`. Numbers are written by hand
// (grouping, decimals, the currency's place, the minus sign) to match what
// the web's `Intl.NumberFormat` writes; see `FormatLocale` for the locales.
// Amounts round half away from zero at the currency's decimals, from the
// amount's decimal digits, as Intl does.

public enum Format {
  /// How currencies are shown: `code` is the international style ("KWD
  /// 1.500"), `local` the way amounts are written in Kuwait ("KD 1.500",
  /// "1.500 د.ك").
  public enum CurrencyDisplay: String, Codable, Sendable {
    case code, local
  }

  /// A company's date format (`DateFormat` in the web's `db/types.ts`):
  /// `locale` or a date-fns pattern such as `dd/MM/yyyy`.
  public struct DateFormat: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let locale: DateFormat = "locale"
    public static let dayMonthYear: DateFormat = "dd/MM/yyyy"
    public static let monthDayYear: DateFormat = "MM/dd/yyyy"
    public static let iso: DateFormat = "yyyy-MM-dd"
    public static let dotted: DateFormat = "dd.MM.yyyy"
    public static let dashed: DateFormat = "dd-MM-yyyy"
    public static let dayMonthNameYear: DateFormat = "d MMM yyyy"
    public static let monthNameDayYear: DateFormat = "MMM d, yyyy"
  }

  /// `DATE_FORMATS`: the choices in Settings, with their labels.
  public static let dateFormats: [(value: DateFormat, label: String)] = [
    (.locale, "Based on locale"),
    (.dayMonthYear, "31/12/2026"),
    (.monthDayYear, "12/31/2026"),
    (.iso, "2026-12-31"),
    (.dotted, "31.12.2026"),
    (.dashed, "31-12-2026"),
    (.dayMonthNameYear, "31 Dec 2026"),
    (.monthNameDayYear, "Dec 31, 2026"),
  ]

  // MARK: Money

  /// `formatMoney`: "KD 1,234.500" / "1,234.500 د.ك" (`.local`), "KWD
  /// 1,234.500" / "1,234.500 KWD" (`.code`). Foreign currencies keep their
  /// symbol in English ("$10.00") and their code in Arabic ("10.00 USD").
  public static func money(
    _ amount: some MoneyValue, currency: String, locale: FormatLocale, display: CurrencyDisplay = .code
  ) -> String {
    let code = safeCurrency(currency)
    let digits = Money.precision(code)
    let text = currencyText(
      amount.moneyDecimal, code: code, showCode: arabicCode(locale, code, display), minimum: digits,
      maximum: digits, locale: locale)
    return localize(text, code: code, display: display)
  }

  /// `formatUnitPrice`: like `money` but keeps the extra decimals of
  /// precise unit prices (0.537), up to 6.
  public static func unitPrice(
    _ amount: some MoneyValue, currency: String, locale: FormatLocale, display: CurrencyDisplay = .code
  ) -> String {
    let code = safeCurrency(currency)
    let digits = Money.precision(code)
    let text = currencyText(
      amount.moneyDecimal, code: code, showCode: arabicCode(locale, code, display), minimum: digits,
      maximum: max(digits, decimalsOf(amount.moneyNumber)), locale: locale)
    return localize(text, code: code, display: display)
  }

  /// `formatAmount`: the figure with the currency's decimals and no symbol,
  /// "1,234.50".
  public static func amount(_ amount: some MoneyValue, currency: String, locale: FormatLocale) -> String {
    let digits = Money.precision(safeCurrency(currency))
    return number(amount, minimumFractionDigits: digits, maximumFractionDigits: digits, locale: locale)
  }

  /// `formatQuantity`: up to 6 decimals, "1,500", "2.25".
  public static func quantity(_ quantity: some MoneyValue, locale: FormatLocale) -> String {
    number(quantity, minimumFractionDigits: 0, maximumFractionDigits: 6, locale: locale)
  }

  /// `formatPercent`: "5%" in English, "5‎%‎" in Arabic; `rate` is a
  /// percentage (5 for 5%), up to 4 decimals.
  public static func percent(_ rate: some MoneyValue, locale: FormatLocale) -> String {
    // The web divides by 100 as a JavaScript number, and Intl multiplies
    // the result's digits by 100 again.
    let rateNumber = rate.moneyNumber
    let fraction = (rateNumber.isNaN ? 0 : rateNumber) / 100
    let value = Money.dec(fraction) * 100
    let data = locale.data
    return plainNumber(value, minimum: 0, maximum: 4, data: data) + data.percent
  }

  /// `Intl.NumberFormat(locale, { minimumFractionDigits, maximumFractionDigits }).format(value)`.
  public static func number(
    _ value: some MoneyValue, minimumFractionDigits: Int = 0, maximumFractionDigits: Int = 3,
    locale: FormatLocale
  ) -> String {
    plainNumber(
      value.moneyDecimal, minimum: minimumFractionDigits,
      maximum: max(minimumFractionDigits, maximumFractionDigits), data: locale.data)
  }

  /// `currencySymbol`: "KD" (`.local`) or "KWD" in English, "د.ك" or
  /// "د.ك." in Arabic, "$" for dollars in English.
  public static func currencySymbol(
    _ currency: String, locale: FormatLocale, display: CurrencyDisplay = .code
  ) -> String {
    let code = safeCurrency(currency)
    return localize(locale.data.symbols[code] ?? code, code: code, display: display)
  }

  // MARK: Screens

  /// `isolateAmount`: an amount for the screen that reads the same in
  /// right-to-left text and in a left-to-right cell. Arabic amounts are the
  /// figure, its minus sign on the left, then the currency: "-12.500 د.ك",
  /// with the figure and the whole amount isolated (RLI, LRI figure PDI, the
  /// currency, PDI). English amounts are left as they are. Screens only.
  public static func isolateAmount(_ text: String, locale: FormatLocale) -> String {
    guard locale.isArabic else { return text }
    var plain = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 0x200E, 0x200F, 0x061C, 0x2066...0x2069: continue
      default: plain.append(scalar)
      }
    }
    let plainText = String(plain)
    if let parts = figureAndCurrency(plain) {
      return "\u{2067}\u{2066}" + parts.figure + "\u{2069}\u{A0}" + parts.currency + "\u{2069}"
    }
    return "\u{2068}" + plainText + "\u{2069}"
  }

  /// `maskNumber`: a card, account or Civil ID number with only its last
  /// digits showing, "•••• 1234". Short values are hidden entirely.
  public static func maskNumber(_ value: String, visible: Int = 4) -> String {
    let compact = JSText.removingWhitespace(value)
    if compact.isEmpty { return "" }
    if JSText.length(compact) <= visible { return "••••" }
    return "•••• " + JSText.slice(compact, from: -visible)
  }

  // MARK: Dates

  /// `formatDate`: a `yyyy-MM-dd` day in the company's date format. Month
  /// names follow the language ("3 أكتوبر 2026" in Arabic); `locale` is the
  /// locale's medium date ("Oct 3, 2026", "31 Dec 2026"). "" for anything
  /// that is not a date.
  public static func date(_ value: String?, format: DateFormat, locale: FormatLocale) -> String {
    guard let value, !value.isEmpty, ISODates.isISODate(value), let day = ISODates.parse(value) else {
      return ""
    }
    let fields = DateFields(day: day, hour: 0, minute: 0)
    if format == .locale {
      let data = locale.data
      return DatePattern.format(data.mediumDate, fields, names: .intl(data))
    }
    return DatePattern.format(format.rawValue, fields, names: locale.isArabic ? .dateFnsArabic : .dateFnsEnglish)
  }

  /// `formatDateTime`: a moment, "Oct 3, 2026, 11:54 PM". In Arabic, with a
  /// date format, the date is written the way the app writes dates
  /// ("03/10/2026، 11:54 م"). `zone` is the device's, as on the web.
  public static func dateTime(
    _ value: Date, locale: FormatLocale, dateFormat: DateFormat? = nil, zone: TimeZone = .current
  ) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: value)
    let day = CivilDay(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    let fields = DateFields(day: day, hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    let data = locale.data
    let time = DatePattern.time(fields, data: data)
    if locale.isArabic, let dateFormat, !dateFormat.rawValue.isEmpty {
      return date(day.text, format: dateFormat, locale: locale) + "\u{60C} " + time
    }
    return DatePattern.format(data.mediumDate, fields, names: .intl(data)) + data.dateTimeSeparator + time
  }

  /// `formatDateTime` for a stored timestamp ("2026-10-03T20:54:00Z"); ""
  /// when it is empty or not a moment.
  public static func dateTime(
    _ value: String?, locale: FormatLocale, dateFormat: DateFormat? = nil, zone: TimeZone = .current
  ) -> String {
    guard let value, !value.isEmpty, let moment = moment(value) else { return "" }
    return dateTime(moment, locale: locale, dateFormat: dateFormat, zone: zone)
  }

  // MARK: Pieces

  static func safeCurrency(_ currency: String) -> String {
    let letters = currency.unicodeScalars
    guard letters.count == 3, letters.allSatisfy({ ("A"..."Z").contains($0) || ("a"..."z").contains($0) })
    else { return "USD" }
    return currency.uppercased()
  }

  /// Arabic has no familiar symbols for most foreign currencies ("UK£"), so
  /// they are written with their code ("1,234.50 USD"); the dinar keeps د.ك.
  static func arabicCode(_ locale: FormatLocale, _ code: String, _ display: CurrencyDisplay) -> Bool {
    guard locale.isArabic else { return false }
    return !(display == .local && code == "KWD")
  }

  /// CLDR writes "KWD" in English and "د.ك." (with a final dot) in Arabic;
  /// Kuwait writes "KD" and "د.ك".
  static func localize(_ text: String, code: String, display: CurrencyDisplay) -> String {
    guard display == .local, code == "KWD" else { return text }
    var scalars = Array(text.unicodeScalars)
    // text.replace('KWD', 'KD'), then text.replace(/د\.ك\.?/, 'د.ك').
    if let start = firstIndex(of: Array("KWD".unicodeScalars), in: scalars) {
      scalars.replaceSubrange(start..<start + 3, with: Array("KD".unicodeScalars))
    }
    let dinar = Array("\u{62F}.\u{643}".unicodeScalars)
    if let start = firstIndex(of: dinar, in: scalars) {
      let end = start + dinar.count
      if end < scalars.count, scalars[end] == "." { scalars.remove(at: end) }
    }
    var result = String.UnicodeScalarView()
    result.append(contentsOf: scalars)
    return String(result)
  }

  static func firstIndex(of target: [Unicode.Scalar], in scalars: [Unicode.Scalar]) -> Int? {
    guard !target.isEmpty, scalars.count >= target.count else { return nil }
    for start in 0...(scalars.count - target.count) where Array(scalars[start..<start + target.count]) == target {
      return start
    }
    return nil
  }

  /// `decimalsOf`: decimals a number actually uses, at most 6.
  static func decimalsOf(_ value: Double) -> Int {
    guard value.isFinite else { return 0 }
    let text = Money.jsString(value.magnitude)
    if text.contains("e-") { return 6 }
    guard let point = text.firstIndex(of: ".") else { return 0 }
    return min(6, text.distance(from: point, to: text.endIndex) - 1)
  }

  /// An amount with its currency, as `Intl.NumberFormat` with `style:
  /// 'currency'` writes it.
  static func currencyText(
    _ amount: Decimal, code: String, showCode: Bool, minimum: Int, maximum: Int, locale: FormatLocale
  ) -> String {
    let data = locale.data
    let figure = digits(amount, minimum: minimum, maximum: maximum)
    let number = grouped(figure, data: data)
    let symbol = showCode ? code : (data.symbols[code] ?? code)
    let minus = figure.negative ? data.minus : ""
    switch data.currency {
    case .before:
      // CLDR's currency spacing: a symbol that ends in a letter ("KWD") is
      // kept apart from the figure.
      let spaced = symbol.unicodeScalars.last.map { !isSymbolOrSpace($0) } ?? false
      return minus + symbol + (spaced ? "\u{A0}" : "") + number
    case .after(let separator):
      // Arabic-script symbols end with a right-to-left mark.
      let mark = data.currencyLead.isEmpty || !containsArabic(symbol) ? "" : "\u{200F}"
      return data.currencyLead + minus + number + separator + symbol + mark
    }
  }

  static func plainNumber(_ value: Decimal, minimum: Int, maximum: Int, data: LocaleData) -> String {
    let figure = digits(value, minimum: minimum, maximum: maximum)
    return (figure.negative ? data.minus : "") + grouped(figure, data: data)
  }

  /// The figure rounded half away from zero to `maximum` decimals, with at
  /// least `minimum`. Negative when the amount is, even when it rounds to
  /// zero ("-0.000"), as Intl writes it.
  static func digits(_ value: Decimal, minimum: Int, maximum: Int) -> (negative: Bool, integer: String, fraction: String) {
    let amount = value.isNaN ? Decimal(0) : value
    let negative = amount < 0
    var magnitude = negative ? -amount : amount
    var rounded = Decimal()
    NSDecimalRound(&rounded, &magnitude, max(0, maximum), .plain)
    let parts = DigitString(decimal: rounded).plainParts
    var fraction = parts.fraction
    if fraction.count < minimum { fraction += String(repeating: "0", count: minimum - fraction.count) }
    return (negative, parts.integer, fraction)
  }

  static func grouped(_ figure: (negative: Bool, integer: String, fraction: String), data: LocaleData) -> String {
    var integer = ""
    let characters = Array(figure.integer)
    for (index, character) in characters.enumerated() {
      if index > 0, (characters.count - index) % 3 == 0 { integer += data.group }
      integer.append(character)
    }
    return figure.fraction.isEmpty ? integer : integer + data.decimal + figure.fraction
  }

  static func isSymbolOrSpace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol, .spaceSeparator, .lineSeparator,
      .paragraphSeparator:
      true
    default:
      false
    }
  }

  static func containsArabic(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
  }

  /// `^(-?[\d.,]+)\s+(\S.*)$`: the figure and what follows it.
  static func figureAndCurrency(_ scalars: String.UnicodeScalarView) -> (figure: String, currency: String)? {
    var index = scalars.startIndex
    var figure = String.UnicodeScalarView()
    if index < scalars.endIndex, scalars[index] == "-" {
      figure.append("-")
      index = scalars.index(after: index)
    }
    let figureStart = index
    while index < scalars.endIndex, scalars[index].isFigure {
      figure.append(scalars[index])
      index = scalars.index(after: index)
    }
    guard index > figureStart else { return nil }
    let spaceStart = index
    while index < scalars.endIndex, JSText.isWhitespace(scalars[index]) {
      index = scalars.index(after: index)
    }
    guard index > spaceStart, index < scalars.endIndex else { return nil }
    let rest = scalars[index...]
    guard !rest.contains(where: JSText.isLineTerminator) else { return nil }
    return (String(figure), String(String.UnicodeScalarView(rest)))
  }

  /// What `new Date(text)` reads: a timestamp, or a `yyyy-MM-dd` day (UTC
  /// midnight).
  static func moment(_ text: String) -> Date? {
    if let fields = ISODates.fields(text) {
      let day = CivilDay(javaScriptYear: fields.year, month: fields.month, day: fields.day)
      guard day.year == fields.year, day.month == fields.month else { return nil }
      return Date(timeIntervalSince1970: TimeInterval(day.dayNumber) * 86_400)
    }
    return MahamDates.parseTimestamp(text)
  }
}

/// The web's `useFormat()` (`src/app/company.tsx`): formatting bound to the
/// company's currency, currency display and date format, in the interface
/// language. Amounts come isolated for the screen (`isolateAmount`).
public struct CompanyFormat: Hashable, Sendable {
  public let locale: FormatLocale
  public let currency: String
  public let currencyDisplay: Format.CurrencyDisplay
  public let dateFormat: Format.DateFormat

  /// `currencyDisplay` is the company's setting; companies without one
  /// write amounts the Kuwaiti way (`.local`), as on the web.
  public init(
    language: InterfaceLanguage, companyLocale: String?, currency: String,
    currencyDisplay: Format.CurrencyDisplay? = nil, dateFormat: Format.DateFormat
  ) {
    self.locale = .interface(language, companyLocale: companyLocale)
    self.currency = currency
    self.currencyDisplay = currencyDisplay ?? .local
    self.dateFormat = dateFormat
  }

  /// `fmt.money(amount, currency)`.
  public func money(_ amount: some MoneyValue, currency: String? = nil) -> String {
    Format.isolateAmount(
      Format.money(amount, currency: currency ?? self.currency, locale: locale, display: currencyDisplay),
      locale: locale)
  }

  /// The text of the web's `MoneyText`: a foreign currency shows its code
  /// ("USD 1,200.00") so it is never mistaken for the company's own.
  public func moneyText(_ amount: some MoneyValue, currency: String? = nil) -> String {
    guard let currency, !currency.isEmpty, currency != self.currency else { return money(amount) }
    return Format.isolateAmount(Format.money(amount, currency: currency, locale: locale, display: .code), locale: locale)
  }

  /// `fmt.date(value)`.
  public func date(_ value: String?) -> String {
    Format.date(value, format: dateFormat, locale: locale)
  }

  /// `fmt.dateTime(value)`, in the device's time zone.
  public func dateTime(_ value: String?, zone: TimeZone = .current) -> String {
    Format.dateTime(value, locale: locale, dateFormat: dateFormat, zone: zone)
  }

  /// `fmt.quantity(value)`.
  public func quantity(_ value: some MoneyValue) -> String {
    Format.quantity(value, locale: locale)
  }

  /// `fmt.percent(value)`.
  public func percent(_ value: some MoneyValue) -> String {
    Format.percent(value, locale: locale)
  }
}

extension Unicode.Scalar {
  /// `[\d.,]`.
  fileprivate var isFigure: Bool {
    ("0"..."9").contains(self) || self == "." || self == ","
  }
}

// MARK: Date patterns

struct DateFields {
  var day: CivilDay
  var hour: Int
  var minute: Int
}

/// Names for months, weekdays and the half of the day.
struct DateNames: Sendable {
  var monthsAbbreviated: [String]
  var monthsWide: [String]
  var monthsNarrow: [String]
  var weekdaysAbbreviated: [String]
  var weekdaysWide: [String]
  var weekdaysShort: [String]
  var weekdaysNarrow: [String]
  var am: String
  var pm: String

  /// date-fns's `en-US`, its default.
  static let dateFnsEnglish = DateNames(
    monthsAbbreviated: LocaleData.englishMonths,
    monthsWide: [
      "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
      "November", "December",
    ],
    monthsNarrow: ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"],
    weekdaysAbbreviated: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
    weekdaysWide: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"],
    weekdaysShort: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"],
    weekdaysNarrow: ["S", "M", "T", "W", "T", "F", "S"],
    am: "AM", pm: "PM")

  /// date-fns's `ar`.
  static let dateFnsArabic: DateNames = {
    let months = [
      "\u{64A}\u{646}\u{627}\u{64A}\u{631}", "\u{641}\u{628}\u{631}\u{627}\u{64A}\u{631}",
      "\u{645}\u{627}\u{631}\u{633}", "\u{623}\u{628}\u{631}\u{64A}\u{644}", "\u{645}\u{627}\u{64A}\u{648}",
      "\u{64A}\u{648}\u{646}\u{64A}\u{648}", "\u{64A}\u{648}\u{644}\u{64A}\u{648}",
      "\u{623}\u{63A}\u{633}\u{637}\u{633}", "\u{633}\u{628}\u{62A}\u{645}\u{628}\u{631}",
      "\u{623}\u{643}\u{62A}\u{648}\u{628}\u{631}", "\u{646}\u{648}\u{641}\u{645}\u{628}\u{631}",
      "\u{62F}\u{64A}\u{633}\u{645}\u{628}\u{631}",
    ]
    let weekdays = [
      "\u{623}\u{62D}\u{62F}", "\u{627}\u{62B}\u{646}\u{64A}\u{646}", "\u{62B}\u{644}\u{627}\u{62B}\u{627}\u{621}",
      "\u{623}\u{631}\u{628}\u{639}\u{627}\u{621}", "\u{62E}\u{645}\u{64A}\u{633}", "\u{62C}\u{645}\u{639}\u{629}",
      "\u{633}\u{628}\u{62A}",
    ]
    return DateNames(
      monthsAbbreviated: months, monthsWide: months,
      monthsNarrow: [
        "\u{64A}", "\u{641}", "\u{645}", "\u{623}", "\u{645}", "\u{64A}", "\u{64A}", "\u{623}", "\u{633}",
        "\u{623}", "\u{646}", "\u{62F}",
      ],
      weekdaysAbbreviated: weekdays,
      weekdaysWide: weekdays.map { "\u{627}\u{644}" + $0 },
      weekdaysShort: weekdays,
      weekdaysNarrow: ["\u{62D}", "\u{646}", "\u{62B}", "\u{631}", "\u{62E}", "\u{62C}", "\u{633}"],
      am: "\u{635}", pm: "\u{645}")
  }()

  /// The names Intl uses in a locale's medium date and short time.
  static func intl(_ data: LocaleData) -> DateNames {
    var names = dateFnsEnglish
    names.monthsAbbreviated = data.shortMonths
    if case .twelveHour(let am, let pm) = data.clock {
      names.am = am
      names.pm = pm
    }
    return names
  }
}

/// date-fns's `format` for the letters dates use: `y`, `M`, `d`, `E`, `h`,
/// `H`, `m` and `a`, with `'quoted'` text. Other letters are written as they
/// are (date-fns refuses them).
enum DatePattern {
  static func format(_ pattern: String, _ fields: DateFields, names: DateNames) -> String {
    var result = ""
    let characters = Array(pattern)
    var index = 0
    while index < characters.count {
      let character = characters[index]
      if character == "'" {
        // '' is a quote; 'text' is text, with '' inside it a quote.
        if index + 1 < characters.count, characters[index + 1] == "'" {
          result.append("'")
          index += 2
          continue
        }
        index += 1
        while index < characters.count {
          if characters[index] == "'" {
            if index + 1 < characters.count, characters[index + 1] == "'" {
              result.append("'")
              index += 2
              continue
            }
            index += 1
            break
          }
          result.append(characters[index])
          index += 1
        }
        continue
      }
      var end = index + 1
      if character.isLetter || character.isNumber || character == "_" {
        while end < characters.count, characters[end] == character { end += 1 }
      }
      let count = end - index
      result += token(character, count, fields, names) ?? String(characters[index..<end])
      index = end
    }
    return result
  }

  static func token(_ letter: Character, _ count: Int, _ fields: DateFields, _ names: DateNames) -> String? {
    let day = fields.day
    switch letter {
    case "y":
      let year = day.year > 0 ? day.year : 1 - day.year
      return padded(count == 2 ? year % 100 : year, count)
    case "M":
      switch count {
      case 1, 2: return padded(day.month, count)
      case 3: return names.monthsAbbreviated[day.month - 1]
      case 5: return names.monthsNarrow[day.month - 1]
      default: return names.monthsWide[day.month - 1]
      }
    case "d":
      return padded(day.day, count)
    case "E":
      switch count {
      case 1, 2, 3: return names.weekdaysAbbreviated[day.weekday]
      case 5: return names.weekdaysNarrow[day.weekday]
      case 6: return names.weekdaysShort[day.weekday]
      default: return names.weekdaysWide[day.weekday]
      }
    case "h":
      let hour = fields.hour % 12
      return padded(hour == 0 ? 12 : hour, count)
    case "H":
      return padded(fields.hour, count)
    case "m":
      return padded(fields.minute, count)
    case "a":
      return fields.hour >= 12 ? names.pm : names.am
    default:
      return nil
    }
  }

  /// Intl's `timeStyle: 'short'`: "11:54 PM", "23:54", "11:54 م".
  static func time(_ fields: DateFields, data: LocaleData) -> String {
    switch data.clock {
    case .twelveHour:
      return format("h:mm a", fields, names: .intl(data))
    case .twentyFourHour:
      return format("HH:mm", fields, names: .intl(data))
    }
  }

  static func padded(_ value: Int, _ length: Int) -> String {
    let text = String(value.magnitude)
    let zeros = String(repeating: "0", count: max(0, length - text.count))
    return (value < 0 ? "-" : "") + zeros + text
  }
}
