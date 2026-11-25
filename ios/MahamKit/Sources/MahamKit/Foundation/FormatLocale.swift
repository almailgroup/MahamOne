import Foundation

/// The locale amounts, numbers and dates are written in, named as the web
/// names it (`"en-KW"`, `"ar-KW-u-nu-latn"`).
///
/// The formatting is done by hand, so it reads the same on every platform,
/// and matches what Node's `Intl` writes (ICU 78, CLDR 48) for:
///
/// - English (`en`, `en-KW`, `en-US`): "KWD 1,234.500", "$1,234.50", "Oct 3, 2026".
/// - British English (`en-GB`): "US$1,234.50", "3 Oct 2026", "23:54".
/// - German (`de`, `de-DE`): "1.234,50 €", "03.10.2026".
/// - Arabic with Western digits (`ar…`, as `ar-KW-u-nu-latn`): "1,234.500 د.ك.".
///
/// Other locales are written as `en-KW` is.
public struct FormatLocale: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
  public let identifier: String

  public init(_ identifier: String) {
    self.identifier = identifier
  }

  public init(stringLiteral value: String) {
    self.init(value)
  }

  /// English as Kuwait writes it, the web's default company locale.
  public static let englishKuwait = FormatLocale("en-KW")

  /// Arabic with Western digits (1, 2, 3), which is what Kuwaiti invoices,
  /// banks and KNET receipts use.
  public static let arabicKuwait = FormatLocale("ar-KW-u-nu-latn")

  /// The web's `interfaceLocale(companyLocale)`: Arabic with Western digits
  /// in the Arabic interface, otherwise the company's own locale (`en-KW`
  /// when it has none).
  public static func interface(_ language: InterfaceLanguage, companyLocale: String? = nil) -> FormatLocale {
    if language == .ar { return .arabicKuwait }
    guard let companyLocale, !companyLocale.isEmpty else { return .englishKuwait }
    return FormatLocale(companyLocale)
  }

  /// `locale.toLowerCase().startsWith('ar')`.
  public var isArabic: Bool { identifier.lowercased().hasPrefix("ar") }

  public var description: String { identifier }

  var data: LocaleData {
    let lower = identifier.lowercased()
    if lower.hasPrefix("ar") { return .arabic }
    let language = lower.split(whereSeparator: { $0 == "-" || $0 == "_" })
    if language.first == "de", language.count == 1 || language[1] == "de" { return .german }
    if language.first == "en", language.count > 1, language[1] == "gb" { return .britishEnglish }
    return .english
  }
}

/// How a locale writes numbers, amounts and dates (from CLDR, as ICU 78
/// writes them).
struct LocaleData: Sendable {
  enum CurrencyPosition: Sendable {
    /// "$1,234.50", "KWD 1,234.500".
    case before
    /// "1.234,50 €", with this between the figure and the currency.
    case after(String)
  }

  enum Clock: Sendable {
    case twelveHour(am: String, pm: String)
    case twentyFourHour
  }

  var decimal: String
  var group: String
  var minus: String
  /// What follows the figure of a percentage.
  var percent: String
  var currency: CurrencyPosition
  /// Written before an amount (Arabic's right-to-left mark).
  var currencyLead: String
  /// Currency symbols that are not their code.
  var symbols: [String: String]
  /// `dateStyle: 'medium'`, in date-fns pattern letters.
  var mediumDate: String
  var shortMonths: [String]
  var clock: Clock
  /// Between the date and the time.
  var dateTimeSeparator: String

  /// English: also how `en-KW` and `en-US` write.
  static let english = LocaleData(
    decimal: ".", group: ",", minus: "-", percent: "%", currency: .before, currencyLead: "",
    symbols: englishSymbols, mediumDate: "MMM d, y", shortMonths: englishMonths,
    clock: .twelveHour(am: "AM", pm: "PM"), dateTimeSeparator: ", ")

  static let britishEnglish: LocaleData = {
    var data = english
    data.symbols["USD"] = "US$"
    data.symbols["JPY"] = "JP\u{A5}"
    data.mediumDate = "d MMM y"
    data.shortMonths[8] = "Sept"
    data.clock = .twentyFourHour
    return data
  }()

  static let german = LocaleData(
    decimal: ",", group: ".", minus: "-", percent: "\u{A0}%", currency: .after("\u{A0}"),
    currencyLead: "", symbols: germanSymbols, mediumDate: "dd.MM.y", shortMonths: englishMonths,
    clock: .twentyFourHour, dateTimeSeparator: ", ")

  /// Arabic with Western digits; the minus sign and percent sign carry
  /// left-to-right marks.
  static let arabic = LocaleData(
    decimal: ".", group: ",", minus: "\u{200E}-", percent: "\u{200E}%\u{200E}",
    currency: .after("\u{A0}"), currencyLead: "\u{200F}", symbols: arabicSymbols,
    mediumDate: "dd\u{200F}/MM\u{200F}/y", shortMonths: englishMonths,
    clock: .twelveHour(am: "\u{635}", pm: "\u{645}"), dateTimeSeparator: "\u{60C} ")

  static let englishMonths = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ]

  static let englishSymbols: [String: String] = [
    "AUD": "A$", "BRL": "R$", "CAD": "CA$", "CNY": "CN\u{A5}", "EUR": "\u{20AC}", "GBP": "\u{A3}",
    "HKD": "HK$", "ILS": "\u{20AA}", "INR": "\u{20B9}", "JPY": "\u{A5}", "KRW": "\u{20A9}",
    "MXN": "MX$", "NZD": "NZ$", "PHP": "\u{20B1}", "TWD": "NT$", "USD": "$", "VND": "\u{20AB}",
    "XAF": "FCFA", "XCD": "EC$", "XCG": "Cg.", "XOF": "F\u{202F}CFA", "XPF": "CFPF", "XXX": "\u{A4}",
  ]

  static let germanSymbols: [String: String] = [
    "ATS": "\u{F6}S", "AUD": "AU$", "BGM": "BGK", "BGO": "BGJ", "BRL": "R$", "CAD": "CA$",
    "CNY": "CN\u{A5}", "DEM": "DM", "EUR": "\u{20AC}", "GBP": "\u{A3}", "HKD": "HK$", "ILS": "\u{20AA}",
    "INR": "\u{20B9}", "JPY": "\u{A5}", "KRW": "\u{20A9}", "MXN": "MX$", "NZD": "NZ$", "THB": "\u{E3F}",
    "TWD": "NT$", "USD": "$", "VND": "\u{20AB}", "XAF": "FCFA", "XCD": "EC$", "XCG": "Cg.",
    "XOF": "F\u{202F}CFA", "XPF": "CFPF",
  ]

  static let arabicSymbols: [String: String] = [
    "AED": "\u{62F}.\u{625}.", "AUD": "AU$", "BHD": "\u{62F}.\u{628}.", "BRL": "R$", "CAD": "CA$",
    "CNY": "CN\u{A5}", "DZD": "\u{62F}.\u{62C}.", "EGP": "\u{62C}.\u{645}.", "EUR": "\u{20AC}",
    "GBP": "UK\u{A3}", "HKD": "HK$", "ILS": "\u{20AA}", "INR": "\u{20B9}", "IQD": "\u{62F}.\u{639}.",
    "IRR": "\u{631}.\u{625}.", "JOD": "\u{62F}.\u{623}.", "JPY": "JP\u{A5}", "KRW": "\u{20A9}",
    "KWD": "\u{62F}.\u{643}.", "LBP": "\u{644}.\u{644}.", "LYD": "\u{62F}.\u{644}.",
    "MAD": "\u{62F}.\u{645}.", "MRU": "\u{623}.\u{645}.", "MXN": "MX$", "NZD": "NZ$",
    "OMR": "\u{631}.\u{639}.", "QAR": "\u{631}.\u{642}.", "SAR": "\u{631}.\u{633}.",
    "SDD": "\u{62F}.\u{633}.", "SDG": "\u{62C}.\u{633}.", "SYP": "\u{644}.\u{633}.", "THB": "\u{E3F}",
    "TND": "\u{62F}.\u{62A}.", "TWD": "NT$", "USD": "US$", "VND": "\u{20AB}", "XAF": "FCFA",
    "XCD": "EC$", "XCG": "Cg.", "XOF": "F\u{202F}CFA", "XPF": "CFPF", "XXX": "\u{A4}",
    "YER": "\u{631}.\u{64A}.",
  ]
}
