import Foundation

/// Countries, currencies, locales and addresses (src/lib/geo.ts).
public enum Geo {
  public static let countryCodes: [String] =
    ("AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ "
    + "CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR "
    + "GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP "
    + "KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT "
    + "MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW "
    + "SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG "
    + "UM US UY UZ VA VC VE VG VI VN VU WF WS XK YE YT ZA ZM ZW").components(separatedBy: " ")

  public static let commonCurrencies: [String] = [
    "USD", "EUR", "GBP", "AED", "SAR", "QAR", "KWD", "BHD", "OMR", "EGP", "CAD", "AUD", "CHF", "JPY", "CNY", "INR",
    "PKR", "NGN", "ZAR", "KES", "MAD", "TRY", "SEK", "NOK", "DKK", "PLN", "SGD", "HKD", "NZD", "MXN", "BRL",
  ]

  public struct Option: Hashable, Sendable {
    public var value: String
    public var label: String
  }

  /// A country's name in a locale, from the platform's CLDR data as the web
  /// takes it from the browser's (the two may word a few names differently).
  public static func countryName(_ code: String, locale: String = "en") -> String {
    if code.isEmpty { return "" }
    let upper = code.uppercased()
    // Intl.DisplayNames refuses anything but two letters or three digits.
    let scalars = Array(upper.unicodeScalars)
    let letters = scalars.count == 2 && scalars.allSatisfy { $0.value >= 0x41 && $0.value <= 0x5A }
    let digits = scalars.count == 3 && scalars.allSatisfy(WebJS.isDigit)
    guard letters || digits else { return code }
    return displayName(locale) { $0.localizedString(forRegionCode: upper) } ?? code
  }

  public static func countryOptions(locale: String = "en") -> [Option] {
    countryCodes.map { Option(value: $0, label: countryName($0, locale: locale)) }
      .sorted { $0.label.localizedCompare($1.label) == .orderedAscending }
  }

  /// A currency's name in a locale ("Kuwaiti Dinar").
  public static func currencyName(_ code: String, locale: String = "en") -> String {
    let upper = code.uppercased()
    let scalars = Array(upper.unicodeScalars)
    guard scalars.count == 3, scalars.allSatisfy({ $0.value >= 0x41 && $0.value <= 0x5A }) else { return code }
    return displayName(locale) { $0.localizedString(forCurrencyCode: upper) } ?? code
  }

  /// The currencies the web's browsers offer (`Intl.supportedValuesOf('currency')`
  /// in Chrome and Node 22), so both list the same ones.
  public static let supportedCurrencies: [String] = [
    "AED", "AFN", "ALL", "AMD", "ANG", "AOA", "ARS", "AUD", "AWG", "AZN", "BAM", "BBD", "BDT", "BGN", "BHD", "BIF",
    "BMD", "BND", "BOB", "BRL", "BSD", "BTN", "BWP", "BYN", "BZD", "CAD", "CDF", "CHF", "CLP", "CNY", "COP", "CRC",
    "CUC", "CUP", "CVE", "CZK", "DJF", "DKK", "DOP", "DZD", "EGP", "ERN", "ETB", "EUR", "FJD", "FKP", "GBP", "GEL",
    "GHS", "GIP", "GMD", "GNF", "GTQ", "GYD", "HKD", "HNL", "HRK", "HTG", "HUF", "IDR", "ILS", "INR", "IQD", "IRR",
    "ISK", "JMD", "JOD", "JPY", "KES", "KGS", "KHR", "KMF", "KPW", "KRW", "KWD", "KYD", "KZT", "LAK", "LBP", "LKR",
    "LRD", "LSL", "LYD", "MAD", "MDL", "MGA", "MKD", "MMK", "MNT", "MOP", "MRU", "MUR", "MVR", "MWK", "MXN", "MYR",
    "MZN", "NAD", "NGN", "NIO", "NOK", "NPR", "NZD", "OMR", "PAB", "PEN", "PGK", "PHP", "PKR", "PLN", "PYG", "QAR",
    "RON", "RSD", "RUB", "RWF", "SAR", "SBD", "SCR", "SDG", "SEK", "SGD", "SHP", "SLE", "SLL", "SOS", "SRD", "SSP",
    "STN", "SVC", "SYP", "SZL", "THB", "TJS", "TMT", "TND", "TOP", "TRY", "TTD", "TWD", "TZS", "UAH", "UGX", "USD",
    "UYU", "UZS", "VES", "VND", "VUV", "WST", "XAF", "XCD", "XCG", "XDR", "XOF", "XPF", "XSU", "YER", "ZAR", "ZMW",
    "ZWG", "ZWL",
  ]

  /// The common currencies first, then every other one.
  public static func currencyOptions(locale: String = "en") -> [Option] {
    let known = Set(supportedCurrencies)
    let common = commonCurrencies.filter { known.contains($0) }
    let rest = supportedCurrencies.filter { !commonCurrencies.contains($0) }
    return (common + rest).map { Option(value: $0, label: "\($0) — \(currencyName($0, locale: locale))") }
  }

  /// The name in `locale`, else in English (`new Intl.DisplayNames([locale, 'en'])`).
  private static func displayName(_ locale: String, _ name: (Locale) -> String?) -> String? {
    for identifier in [locale, "en"] {
      if let found = name(Locale(identifier: identifier)), !found.isEmpty { return found }
    }
    return nil
  }

  public static let localeOptions: [Option] = [
    Option(value: "en-KW", label: "English (Kuwait)"),
    Option(value: "ar-KW", label: "العربية (الكويت)"),
    Option(value: "en-US", label: "English (United States)"),
    Option(value: "en-GB", label: "English (United Kingdom)"),
    Option(value: "en-AE", label: "English (United Arab Emirates)"),
    Option(value: "en-IN", label: "English (India)"),
    Option(value: "en-CA", label: "English (Canada)"),
    Option(value: "en-AU", label: "English (Australia)"),
    Option(value: "en-IE", label: "English (Ireland)"),
    Option(value: "en-NZ", label: "English (New Zealand)"),
    Option(value: "en-SG", label: "English (Singapore)"),
    Option(value: "en-ZA", label: "English (South Africa)"),
    Option(value: "en-NG", label: "English (Nigeria)"),
    Option(value: "fr-FR", label: "Français (France)"),
    Option(value: "fr-CA", label: "Français (Canada)"),
    Option(value: "fr-BE", label: "Français (Belgique)"),
    Option(value: "fr-CH", label: "Français (Suisse)"),
    Option(value: "de-DE", label: "Deutsch (Deutschland)"),
    Option(value: "de-AT", label: "Deutsch (Österreich)"),
    Option(value: "de-CH", label: "Deutsch (Schweiz)"),
    Option(value: "es-ES", label: "Español (España)"),
    Option(value: "es-MX", label: "Español (México)"),
    Option(value: "pt-PT", label: "Português (Portugal)"),
    Option(value: "pt-BR", label: "Português (Brasil)"),
    Option(value: "it-IT", label: "Italiano (Italia)"),
    Option(value: "nl-NL", label: "Nederlands (Nederland)"),
    Option(value: "nl-BE", label: "Nederlands (België)"),
    Option(value: "sv-SE", label: "Svenska (Sverige)"),
    Option(value: "da-DK", label: "Dansk (Danmark)"),
    Option(value: "nb-NO", label: "Norsk (Norge)"),
    Option(value: "fi-FI", label: "Suomi (Suomi)"),
    Option(value: "pl-PL", label: "Polski (Polska)"),
    Option(value: "tr-TR", label: "Türkçe (Türkiye)"),
  ]

  // MARK: Addresses

  private static let cityStateZip: Set<String> = ["US", "CA", "AU", "PH"]
  private static let cityThenPostcode: Set<String> = ["GB", "IE", "IM", "JE", "GG", "AE", "SA", "QA", "KW", "BH", "OM"]
  private static let kuwaitParts = ["block", "street", "avenue", "building", "floor", "unit", "paci"]

  /// An empty address record (`Address`), in a country.
  public static func emptyAddress(_ country: String = "") -> JSONValue {
    ["line1": "", "line2": "", "city": "", "state": "", "postalCode": "", "country": .string(country)]
  }

  /// A text field of an address; anything else counts as missing.
  private static func field(_ address: JSONValue, _ key: String) -> String? {
    address[key]?.string
  }

  /// Whether nothing of the address is filled in (the country aside).
  public static func isAddressEmpty(_ address: JSONValue?) -> Bool {
    guard let address, !address.isNull else { return true }
    let keys = ["line1", "line2", "city", "state", "postalCode"] + kuwaitParts
    return !keys.contains { key in
      guard let value = field(address, key) else { return false }
      return !WebJS.trim(value).isEmpty
    }
  }

  private static let kuwaitWords: [Bilingual.Language: [String: String]] = [
    .en: [
      "block": "Block", "street": "Street", "avenue": "Avenue", "building": "Building", "floor": "Floor",
      "unit": "Unit", "paci": "PACI no.", "country": "Kuwait", "comma": ", ",
    ],
    .ar: [
      "block": "قطعة", "street": "شارع", "avenue": "جادة", "building": "مبنى", "floor": "الدور",
      "unit": "وحدة", "paci": "الرقم الآلي", "country": "الكويت", "comma": "، ",
    ],
  ]

  /// A Kuwaiti address the way it is written locally:
  /// "Block 3, Street 12, Avenue 4, Building 15, Floor 2, Unit 5",
  /// "Salmiya, Hawalli 22001", "PACI no. 12345678".
  private static func kuwaitAddressLines(_ address: JSONValue, _ language: Bilingual.Language, _ includeCountry: Bool)
    -> [String]
  {
    let words = kuwaitWords[language] ?? [:]
    let comma = words["comma"] ?? ", "
    func part(_ key: String) -> String {
      let value = field(address, key).map(WebJS.trim) ?? ""
      return value.isEmpty ? "" : "\(words[key] ?? key) \(value)"
    }
    let place = [field(address, "city"), field(address, "state")]
      .map { Kuwait.placeName(WebJS.trim($0 ?? ""), language) }
      .filter { !$0.isEmpty }
      .joined(separator: comma)
    var lines = [
      kuwaitParts.filter { $0 != "paci" }.map(part).filter { !$0.isEmpty }.joined(separator: comma),
      WebJS.trim(field(address, "line1") ?? ""),
      WebJS.trim(field(address, "line2") ?? ""),
      [place, WebJS.trim(field(address, "postalCode") ?? "")].filter { !$0.isEmpty }.joined(separator: " "),
      part("paci"),
    ]
    if includeCountry && !isAddressEmpty(address) { lines.append(words["country"] ?? "Kuwait") }
    return lines.filter { !$0.isEmpty }
  }

  /// An address's lines, following common conventions of its country; the
  /// country's name last when `includeCountry`.
  public static func formatAddressLines(_ address: JSONValue?, locale: String = "en", includeCountry: Bool = true)
    -> [String]
  {
    guard let address, !address.isNull else { return [] }
    let country = WebJS.trim(field(address, "country") ?? "").uppercased()
    if country == "KW" {
      return kuwaitAddressLines(address, locale.hasPrefix("ar") ? .ar : .en, includeCountry)
    }
    let line1 = WebJS.trim(field(address, "line1") ?? "")
    let line2 = WebJS.trim(field(address, "line2") ?? "")
    let city = WebJS.trim(field(address, "city") ?? "")
    let state = WebJS.trim(field(address, "state") ?? "")
    let postalCode = WebJS.trim(field(address, "postalCode") ?? "")
    func joined(_ parts: [String], _ separator: String) -> String {
      parts.filter { !$0.isEmpty }.joined(separator: separator)
    }
    var lines = [line1, line2]
    if cityStateZip.contains(country) {
      lines.append(joined([city, joined([state, postalCode], " ")], ", "))
    } else if cityThenPostcode.contains(country) {
      lines.append(joined([joined([city, postalCode], " "), state], ", "))
    } else {
      lines.append(joined([postalCode, city], " "))
      lines.append(state)
    }
    if includeCountry && !country.isEmpty && !isAddressEmpty(address) {
      lines.append(countryName(country, locale: locale))
    }
    return lines.filter { !$0.isEmpty }
  }
}
