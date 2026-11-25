import Foundation

/// The port of the web's `src/lib/words.ts`: amounts written out in words,
/// as printed on Kuwaiti invoices, receipts and cheques: "One Thousand Two
/// Hundred Thirty-Four Kuwaiti Dinars and Five Hundred Fils Only" / "فقط ألف
/// ومائتان وأربعة وثلاثون دينارًا كويتيًا وخمسمائة فلس لا غير".
public enum Words {
  /// The grammatical gender a number agrees with in Arabic.
  public enum Gender: String, Sendable {
    case masculine = "m"
    case feminine = "f"
  }

  // MARK: English

  private static let ones = [
    "", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven",
    "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen",
  ]
  private static let tens = [
    "", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety",
  ]
  private static let scales = ["", "Thousand", "Million", "Billion", "Trillion"]

  private static func englishBelowThousand(_ n: Int64) -> String {
    var words: [String] = []
    let hundreds = Int(n / 100)
    let rest = Int(n % 100)
    if hundreds > 0 { words.append("\(ones[hundreds]) Hundred") }
    if rest >= 20 {
      words.append(rest % 10 > 0 ? "\(tens[rest / 10])-\(ones[rest % 10])" : tens[rest / 10])
    } else if rest > 0 {
      words.append(ones[rest])
    }
    return words.joined(separator: " ")
  }

  /// 1234 → "One Thousand Two Hundred Thirty-Four". Like the web, only
  /// the lowest five groups of three digits (up to trillions) are written.
  public static func englishNumber(_ number: Int64) -> String {
    var n = number.magnitude
    if n == 0 { return "Zero" }
    var groups: [String] = []
    var scale = 0
    while n > 0, scale < scales.count {
      let chunk = Int64(n % 1000)
      if chunk > 0 {
        groups.insert(
          [englishBelowThousand(chunk), scales[scale]].filter { !$0.isEmpty }.joined(separator: " "), at: 0)
      }
      n /= 1000
      scale += 1
    }
    return groups.joined(separator: " ")
  }

  private struct EnglishCurrency {
    var one: String
    var many: String
    var minorOne: String
    var minorMany: String
  }

  private static let englishCurrencies: [String: EnglishCurrency] = [
    "KWD": .init(one: "Kuwaiti Dinar", many: "Kuwaiti Dinars", minorOne: "Fils", minorMany: "Fils"),
    "BHD": .init(one: "Bahraini Dinar", many: "Bahraini Dinars", minorOne: "Fils", minorMany: "Fils"),
    "JOD": .init(one: "Jordanian Dinar", many: "Jordanian Dinars", minorOne: "Fils", minorMany: "Fils"),
    "OMR": .init(one: "Omani Rial", many: "Omani Rials", minorOne: "Baisa", minorMany: "Baisa"),
    "SAR": .init(one: "Saudi Riyal", many: "Saudi Riyals", minorOne: "Halala", minorMany: "Halalas"),
    "QAR": .init(one: "Qatari Riyal", many: "Qatari Riyals", minorOne: "Dirham", minorMany: "Dirhams"),
    "AED": .init(one: "UAE Dirham", many: "UAE Dirhams", minorOne: "Fils", minorMany: "Fils"),
    "EGP": .init(one: "Egyptian Pound", many: "Egyptian Pounds", minorOne: "Piastre", minorMany: "Piastres"),
    "USD": .init(one: "US Dollar", many: "US Dollars", minorOne: "Cent", minorMany: "Cents"),
    "EUR": .init(one: "Euro", many: "Euros", minorOne: "Cent", minorMany: "Cents"),
    "GBP": .init(one: "Pound Sterling", many: "Pounds Sterling", minorOne: "Penny", minorMany: "Pence"),
    "INR": .init(one: "Indian Rupee", many: "Indian Rupees", minorOne: "Paisa", minorMany: "Paise"),
  ]

  private static func englishWords(major: Int64, minor: Int64, currency: String, places: Int) -> String {
    let names =
      englishCurrencies[currency] ?? EnglishCurrency(one: currency, many: currency, minorOne: "", minorMany: "")
    var parts: [String] = []
    if major > 0 || minor == 0 {
      parts.append("\(englishNumber(major)) \(major == 1 ? names.one : names.many)")
    }
    if minor > 0 {
      let unit = minor == 1 ? names.minorOne : names.minorMany
      parts.append(unit.isEmpty ? "\(minor)/\(powerOfTen(places))" : "\(englishNumber(minor)) \(unit)")
    }
    return parts.joined(separator: " and ") + " Only"
  }

  // MARK: Arabic

  /// Forms of a counted noun: 1, 2, 3–10, 11–99 and 100s/1000s.
  private struct ArabicNoun {
    var gender: Gender
    /// "دينار كويتي واحد" (said after the noun for 1).
    var one: String
    /// "ديناران كويتيان"
    var two: String
    /// "دنانير كويتية" (3–10)
    var few: String
    /// "دينارًا كويتيًا" (11–99)
    var many: String
    /// "دينار كويتي" (100, 1000, and after compound numbers)
    var single: String
  }

  private static let arabicUnits: [Gender: [String]] = [
    .masculine: ["", "واحد", "اثنان", "ثلاثة", "أربعة", "خمسة", "ستة", "سبعة", "ثمانية", "تسعة", "عشرة"],
    .feminine: ["", "واحدة", "اثنتان", "ثلاث", "أربع", "خمس", "ست", "سبع", "ثماني", "تسع", "عشر"],
  ]
  private static let arabicTens = [
    "", "", "عشرون", "ثلاثون", "أربعون", "خمسون", "ستون", "سبعون", "ثمانون", "تسعون",
  ]
  private static let arabicHundreds = [
    "", "مائة", "مائتان", "ثلاثمائة", "أربعمائة", "خمسمائة", "ستمائة", "سبعمائة", "ثمانمائة", "تسعمائة",
  ]

  private static func units(_ gender: Gender) -> [String] {
    arabicUnits[gender] ?? []
  }

  private static func arabicBelowHundred(_ n: Int, _ gender: Gender) -> String {
    let masculine = gender == .masculine
    if n <= 10 { return units(gender)[n] }
    if n == 11 { return masculine ? "أحد عشر" : "إحدى عشرة" }
    if n == 12 { return masculine ? "اثنا عشر" : "اثنتا عشرة" }
    if n < 20 { return "\(units(gender)[n - 10]) \(masculine ? "عشر" : "عشرة")" }
    let unit = n % 10
    let tensWord = arabicTens[n / 10]
    if unit == 0 { return tensWord }
    let unitWord = unit == 1 ? (masculine ? "واحد" : "إحدى") : units(gender)[unit]
    return "\(unitWord) و\(tensWord)"
  }

  private static func arabicBelowThousand(_ n: Int, _ gender: Gender) -> String {
    let hundreds = n / 100
    let rest = n % 100
    var parts: [String] = []
    if hundreds > 0 { parts.append(arabicHundreds[hundreds]) }
    if rest > 0 { parts.append(arabicBelowHundred(rest, gender)) }
    return parts.joined(separator: " و")
  }

  private struct ArabicScale {
    var one: String
    var two: String
    var few: String
    var many: String
  }

  private static let arabicScales = [
    ArabicScale(one: "ألف", two: "ألفان", few: "آلاف", many: "ألفًا"),
    ArabicScale(one: "مليون", two: "مليونان", few: "ملايين", many: "مليونًا"),
    ArabicScale(one: "مليار", two: "ملياران", few: "مليارات", many: "مليارًا"),
  ]

  /// A count of thousands/millions: "ألف", "ألفان", "ثلاثة آلاف", "أحد عشر ألفًا".
  private static func arabicScale(_ count: Int, _ scale: ArabicScale) -> String {
    if count == 1 { return scale.one }
    if count == 2 { return scale.two }
    let rest = count % 100
    let words = arabicBelowThousand(count, .masculine)
    if rest >= 3, rest <= 10 { return "\(words) \(scale.few)" }
    if rest >= 11 { return "\(words) \(scale.many)" }
    return "\(construct(words)) \(scale.one)"
  }

  /// A dual directly before its noun loses its final ن: "مائتا ألف", "ألفا دينار".
  private static func construct(_ words: String) -> String {
    for stem in ["مائت", "ألف", "مليون", "مليار"] where words.hasSuffix(stem + "ان") {
      return String(words.dropLast(2)) + "ا"
    }
    return words
  }

  /// The number in words, agreeing with a noun of the given gender.
  public static func arabicNumber(_ number: Int64, gender: Gender = .masculine) -> String {
    var rest = number.magnitude
    if rest == 0 { return "صفر" }
    var groups: [Int] = []
    while rest > 0 {
      groups.append(Int(rest % 1000))
      rest /= 1000
    }
    var parts: [String] = []
    var index = groups.count - 1
    while index >= 1 {
      if groups[index] > 0 {
        parts.append(arabicScale(groups[index], arabicScales[min(index, arabicScales.count) - 1]))
      }
      index -= 1
    }
    if groups[0] > 0 { parts.append(arabicBelowThousand(groups[0], gender)) }
    return parts.joined(separator: " و")
  }

  /// A count with its noun: "دينار كويتي واحد", "ثلاثة دنانير كويتية", "مائة دينار كويتي".
  private static func arabicCount(_ n: Int64, _ item: ArabicNoun) -> String {
    if n == 1 { return item.one }
    if n == 2 { return item.two }
    let rest = n % 100
    let words = arabicNumber(n, gender: item.gender)
    if rest >= 3, rest <= 10 { return "\(words) \(item.few)" }
    if rest >= 11 { return "\(words) \(item.many)" }
    return "\(construct(words)) \(item.single)"
  }

  private static let fils = ArabicNoun(
    gender: .masculine, one: "فلس واحد", two: "فلسان", few: "فلوس", many: "فلسًا", single: "فلس")
  private static let cents = ArabicNoun(
    gender: .masculine, one: "سنت واحد", two: "سنتان", few: "سنتات", many: "سنتًا", single: "سنت")

  private static let arabicCurrencies: [String: (major: ArabicNoun, minor: ArabicNoun)] = [
    "KWD": (
      ArabicNoun(
        gender: .masculine, one: "دينار كويتي واحد", two: "ديناران كويتيان", few: "دنانير كويتية",
        many: "دينارًا كويتيًا", single: "دينار كويتي"),
      fils
    ),
    "BHD": (
      ArabicNoun(
        gender: .masculine, one: "دينار بحريني واحد", two: "ديناران بحرينيان", few: "دنانير بحرينية",
        many: "دينارًا بحرينيًا", single: "دينار بحريني"),
      fils
    ),
    "SAR": (
      ArabicNoun(
        gender: .masculine, one: "ريال سعودي واحد", two: "ريالان سعوديان", few: "ريالات سعودية",
        many: "ريالًا سعوديًا", single: "ريال سعودي"),
      ArabicNoun(gender: .feminine, one: "هللة واحدة", two: "هللتان", few: "هللات", many: "هللة", single: "هللة")
    ),
    "AED": (
      ArabicNoun(
        gender: .masculine, one: "درهم إماراتي واحد", two: "درهمان إماراتيان", few: "دراهم إماراتية",
        many: "درهمًا إماراتيًا", single: "درهم إماراتي"),
      fils
    ),
    "USD": (
      ArabicNoun(
        gender: .masculine, one: "دولار أمريكي واحد", two: "دولاران أمريكيان", few: "دولارات أمريكية",
        many: "دولارًا أمريكيًا", single: "دولار أمريكي"),
      cents
    ),
    "EUR": (
      ArabicNoun(gender: .masculine, one: "يورو واحد", two: "يوروان", few: "يوروات", many: "يورو", single: "يورو"),
      cents
    ),
  ]

  private static func arabicWords(major: Int64, minor: Int64, currency: String) -> String? {
    guard let names = arabicCurrencies[currency] else { return nil }
    var parts: [String] = []
    if major > 0 || minor == 0 {
      parts.append(major == 0 ? "صفر \(names.major.single)" : arabicCount(major, names.major))
    }
    if minor > 0 { parts.append(arabicCount(minor, names.minor)) }
    return "فقط \(parts.joined(separator: " و")) لا غير"
  }

  // MARK: Amounts

  /// Splits an amount into whole units and minor units (fils, cents),
  /// ignoring its sign.
  public static func splitAmount(_ amount: some MoneyValue, currency: String) -> (major: Int64, minor: Int64) {
    let places = Money.precision(currency)
    let total = Money.toMinor(amount, places).magnitude
    let factor = UInt64(powerOfTen(places))
    return (Int64(total / factor), Int64(total % factor))
  }

  /// The amount in words in English or Arabic. Currencies without Arabic
  /// names fall back to English.
  public static func amountInWords(_ amount: some MoneyValue, currency: String, language: InterfaceLanguage) -> String {
    let code = currency.uppercased()
    let (major, minor) = splitAmount(amount, currency: code)
    if language == .ar, let arabic = arabicWords(major: major, minor: minor, currency: code) {
      return arabic
    }
    return englishWords(major: major, minor: minor, currency: code, places: Money.precision(code))
  }

  private static func powerOfTen(_ places: Int) -> Int64 {
    var result: Int64 = 1
    for _ in 0..<max(0, places) { result *= 10 }
    return result
  }
}
