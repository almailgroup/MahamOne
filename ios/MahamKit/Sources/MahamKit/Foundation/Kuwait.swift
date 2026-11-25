import Foundation

/// A name in English and Arabic.
public struct Bilingual: Hashable, Sendable {
  public enum Language: String, Sendable {
    case en, ar
  }

  public var en: String
  public var ar: String

  public init(_ en: String, _ ar: String) {
    self.en = en
    self.ar = ar
  }

  public subscript(language: Language) -> String {
    language == .ar ? ar : en
  }
}

/// Kuwait reference data: governorates and areas, banks, and checks for
/// IBANs, Civil IDs and phone numbers (src/lib/kuwait.ts).
public enum Kuwait {
  public struct Governorate: Hashable, Sendable {
    public var code: String
    public var name: Bilingual
    public var areas: [Bilingual]
  }

  public struct Bank: Hashable, Sendable {
    /// The first four letters of the SWIFT/BIC code, also used in IBANs.
    public var code: String
    public var swift: String
    public var name: Bilingual
  }

  public struct Holiday: Hashable, Sendable {
    /// `yyyy-MM-dd`.
    public var date: String
    public var name: Bilingual
  }

  // MARK: Places

  private static func area(_ en: String, _ ar: String) -> Bilingual { Bilingual(en, ar) }

  /// The six governorates and their main areas (the area field also accepts any text).
  public static let governorates: [Governorate] = [
    Governorate(
      code: "CA", name: Bilingual("Capital", "العاصمة"),
      areas: [
        area("Kuwait City", "مدينة الكويت"),
        area("Sharq", "شرق"),
        area("Mirqab", "المرقاب"),
        area("Qibla", "القبلة"),
        area("Dasman", "دسمان"),
        area("Bneid Al-Gar", "بنيد القار"),
        area("Dasma", "الدسمة"),
        area("Daiya", "الدعية"),
        area("Shuwaikh", "الشويخ"),
        area("Shuwaikh Industrial", "الشويخ الصناعية"),
        area("Sulaibikhat", "الصليبيخات"),
        area("Doha", "الدوحة"),
        area("Granada", "غرناطة"),
        area("Kaifan", "كيفان"),
        area("Shamiya", "الشامية"),
        area("Rawda", "الروضة"),
        area("Adailiya", "العديلية"),
        area("Khaldiya", "الخالدية"),
        area("Qadsiya", "القادسية"),
        area("Mansouriya", "المنصورية"),
        area("Nuzha", "النزهة"),
        area("Faiha", "الفيحاء"),
        area("Yarmouk", "اليرموك"),
        area("Qurtuba", "قرطبة"),
        area("Surra", "السرة"),
        area("Abdullah Al-Salem", "ضاحية عبدالله السالم"),
        area("Nahdha", "النهضة"),
        area("Qairawan", "القيروان"),
      ]),
    Governorate(
      code: "HA", name: Bilingual("Hawalli", "حولي"),
      areas: [
        area("Hawalli", "حولي"),
        area("Salmiya", "السالمية"),
        area("Jabriya", "الجابرية"),
        area("Rumaithiya", "الرميثية"),
        area("Bayan", "بيان"),
        area("Mishref", "مشرف"),
        area("Salwa", "سلوى"),
        area("Shaab", "الشعب"),
        area("Shuhada", "الشهداء"),
        area("Hittin", "حطين"),
        area("Salam", "السلام"),
        area("Siddiq", "الصديق"),
        area("Zahra", "الزهراء"),
        area("Mubarak Al-Abdullah", "مبارك العبدالله"),
        area("Maidan Hawalli", "ميدان حولي"),
        area("Bidaa", "البدع"),
      ]),
    Governorate(
      code: "FA", name: Bilingual("Farwaniya", "الفروانية"),
      areas: [
        area("Farwaniya", "الفروانية"),
        area("Khaitan", "خيطان"),
        area("Jleeb Al-Shuyoukh", "جليب الشيوخ"),
        area("Abbasiya", "العباسية"),
        area("Ardiya", "العارضية"),
        area("Ardiya Industrial", "العارضية الحرفية"),
        area("Rabiya", "الرابية"),
        area("Rehab", "الرحاب"),
        area("Omariya", "العمرية"),
        area("Andalous", "الأندلس"),
        area("Ashbeliya", "إشبيلية"),
        area("Firdous", "الفردوس"),
        area("Riggae", "الرقعي"),
        area("Abdullah Al-Mubarak", "عبدالله المبارك"),
        area("Dhajeej", "الضجيج"),
        area("Sabah Al-Nasser", "صباح الناصر"),
        area("Shadadiya", "الشدادية"),
      ]),
    Governorate(
      code: "MU", name: Bilingual("Mubarak Al-Kabeer", "مبارك الكبير"),
      areas: [
        area("Mubarak Al-Kabeer", "مبارك الكبير"),
        area("Adan", "العدان"),
        area("Qurain", "القرين"),
        area("Qusour", "القصور"),
        area("Sabah Al-Salem", "صباح السالم"),
        area("Messila", "المسيلة"),
        area("Abu Al-Hasaniya", "أبو الحصانية"),
        area("Abu Fatira", "أبو فطيرة"),
        area("Fnaitees", "الفنيطيس"),
        area("Masayel", "المسايل"),
      ]),
    Governorate(
      code: "AH", name: Bilingual("Ahmadi", "الأحمدي"),
      areas: [
        area("Ahmadi", "الأحمدي"),
        area("Fahaheel", "الفحيحيل"),
        area("Mangaf", "المنقف"),
        area("Fintas", "الفنطاس"),
        area("Abu Halifa", "أبو حليفة"),
        area("Mahboula", "المهبولة"),
        area("Egaila", "العقيلة"),
        area("Riqqa", "الرقة"),
        area("Hadiya", "هدية"),
        area("Sabahiya", "الصباحية"),
        area("Fahad Al-Ahmad", "فهد الأحمد"),
        area("Jaber Al-Ali", "جابر العلي"),
        area("Dhaher", "الظهر"),
        area("Wafra", "الوفرة"),
        area("Khairan", "الخيران"),
        area("Sabah Al-Ahmad City", "مدينة صباح الأحمد"),
        area("Ali Sabah Al-Salem", "علي صباح السالم"),
        area("Mina Abdullah", "ميناء عبدالله"),
        area("Shuaiba", "الشعيبة"),
      ]),
    Governorate(
      code: "JA", name: Bilingual("Jahra", "الجهراء"),
      areas: [
        area("Jahra", "الجهراء"),
        area("Saad Al-Abdullah", "سعد العبدالله"),
        area("Oyoun", "العيون"),
        area("Naeem", "النعيم"),
        area("Qasr", "القصر"),
        area("Waha", "الواحة"),
        area("Taima", "تيماء"),
        area("Nasseem", "النسيم"),
        area("Amghara", "أمغرة"),
        area("Sulaibiya", "الصليبية"),
        area("Kabd", "كبد"),
        area("Abdali", "العبدلي"),
        area("Jaber Al-Ahmad City", "مدينة جابر الأحمد"),
      ]),
  ]

  /// A governorate by its English or Arabic name or its code.
  public static func findGovernorate(_ name: String) -> Governorate? {
    let trimmed = WebJS.trim(name)
    let key = trimmed.lowercased()
    if key.isEmpty { return nil }
    return governorates.first { g in
      g.code.lowercased() == key || g.name.en.lowercased() == key || g.name.ar == trimmed
    }
  }

  /// An area by its English or Arabic name.
  public static func findArea(_ name: String) -> Bilingual? {
    let trimmed = WebJS.trim(name)
    let key = trimmed.lowercased()
    if key.isEmpty { return nil }
    for g in governorates {
      if let found = g.areas.first(where: { $0.en.lowercased() == key || $0.ar == trimmed }) { return found }
    }
    return nil
  }

  /// A place name in the wanted language when it is a known Kuwaiti area or
  /// governorate; otherwise the name as it is.
  public static func placeName(_ name: String, _ language: Bilingual.Language) -> String {
    guard let found = findArea(name) ?? findGovernorate(name)?.name else { return name }
    return found[language]
  }

  // MARK: Banks

  public static let banks: [Bank] = [
    Bank(code: "NBOK", swift: "NBOKKWKW", name: Bilingual("National Bank of Kuwait", "بنك الكويت الوطني")),
    Bank(code: "KFHO", swift: "KFHOKWKW", name: Bilingual("Kuwait Finance House", "بيت التمويل الكويتي")),
    Bank(code: "BBYN", swift: "BBYNKWKW", name: Bilingual("Boubyan Bank", "بنك بوبيان")),
    Bank(code: "GULB", swift: "GULBKWKW", name: Bilingual("Gulf Bank", "بنك الخليج")),
    Bank(code: "BRGN", swift: "BRGNKWKW", name: Bilingual("Burgan Bank", "بنك برقان")),
    Bank(code: "COMB", swift: "COMBKWKW", name: Bilingual("Commercial Bank of Kuwait", "البنك التجاري الكويتي")),
    Bank(code: "ABKK", swift: "ABKKKWKW", name: Bilingual("Al Ahli Bank of Kuwait", "البنك الأهلي الكويتي")),
    Bank(code: "WRBA", swift: "WRBAKWKW", name: Bilingual("Warba Bank", "بنك وربة")),
    Bank(code: "KWIB", swift: "KWIBKWKW", name: Bilingual("Kuwait International Bank", "بنك الكويت الدولي")),
  ]

  /// The short names people use for the banks.
  public static let bankShortNames: [String: [String]] = [
    "NBOK": ["NBK"],
    "KFHO": ["KFH", "Bait Al Tamweel", "بيتك"],
    "BBYN": ["Boubyan", "بوبيان"],
    "GULB": ["GBK", "Gulf"],
    "BRGN": ["Burgan", "برقان"],
    "COMB": ["CBK", "Commercial Bank", "التجاري"],
    "ABKK": ["ABK", "Ahli", "Al Ahli", "الاهلي"],
    "WRBA": ["Warba", "وربة"],
    "KWIB": ["KIB", "International Bank", "الدولي"],
  ]

  /// A Kuwaiti bank by its code, SWIFT code, English or Arabic name or short name (NBK, KFH…).
  public static func findBank(_ name: String) -> Bank? {
    let wanted = bankKey(name)
    if wanted.isEmpty { return nil }
    return banks.first { bank in
      ([bank.code, bank.swift, bank.name.en, bank.name.ar] + (bankShortNames[bank.code] ?? []))
        .contains { bankKey($0) == wanted }
    }
  }

  /// Lower case, the alef and taa marbuta variants folded, and each run of
  /// anything but letters and digits one space, trimmed.
  private static func bankKey(_ text: String) -> String {
    var out = String.UnicodeScalarView()
    var gap = false
    for scalar in text.lowercased().unicodeScalars {
      let folded: Unicode.Scalar
      switch scalar.value {
      case 0x0623, 0x0625, 0x0622: folded = "\u{0627}"
      case 0x0629: folded = "\u{0647}"
      default: folded = scalar
      }
      if isLetterOrNumber(folded) {
        // A run at the start or the end is trimmed away.
        if gap && !out.isEmpty { out.append(" ") }
        gap = false
        out.append(folded)
      } else {
        gap = true
      }
    }
    return String(out)
  }

  /// `\p{L}` or `\p{N}`.
  private static func isLetterOrNumber(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
      .decimalNumber, .letterNumber, .otherNumber:
      return true
    default:
      return false
    }
  }

  // MARK: IBAN

  /// The IBAN without spaces or dashes, in upper case.
  public static func compactIban(_ value: String) -> String {
    WebJS.removing(value) { WebJS.isSpace($0) || $0 == "-" }.uppercased()
  }

  /// An IBAN in groups of four for display: "KW81 CBKU 0000 ...".
  public static func formatIban(_ value: String) -> String {
    var out = ""
    for (i, scalar) in compactIban(value).unicodeScalars.enumerated() {
      out.unicodeScalars.append(scalar)
      if i % 4 == 3 { out += " " }
    }
    return WebJS.trim(out)
  }

  /// The IBAN length of the countries whose length is checked.
  public static let ibanLengths: [String: Int] = [
    "KW": 30, "SA": 24, "AE": 23, "BH": 22, "QA": 29, "OM": 23, "JO": 30, "EG": 29, "GB": 22, "DE": 22, "FR": 27,
  ]

  /// Checks the length (for known countries) and the ISO 13616 mod-97 check digits.
  public static func isValidIban(_ value: String) -> Bool {
    let iban = Array(compactIban(value).unicodeScalars)
    // ^[A-Z]{2}\d{2}[A-Z0-9]{10,30}$
    func upper(_ s: Unicode.Scalar) -> Bool { s.value >= 0x41 && s.value <= 0x5A }
    guard iban.count >= 14, iban.count <= 34, upper(iban[0]), upper(iban[1]), WebJS.isDigit(iban[2]),
      WebJS.isDigit(iban[3]), iban[4...].allSatisfy({ upper($0) || WebJS.isDigit($0) })
    else { return false }
    let country = String(String.UnicodeScalarView(iban[0..<2]))
    if let expected = ibanLengths[country], iban.count != expected { return false }
    var remainder = 0
    for scalar in iban[4...] + iban[0..<4] {
      let digits = WebJS.isDigit(scalar) ? String(scalar) : String(Int(scalar.value) - 55)
      for d in digits.unicodeScalars { remainder = (remainder * 10 + Int(d.value - 0x30)) % 97 }
    }
    return remainder == 1
  }

  /// The Kuwaiti bank an IBAN belongs to, when known.
  public static func bankFromIban(_ value: String) -> Bank? {
    let iban = compactIban(value)
    guard iban.hasPrefix("KW") else { return nil }
    let units = Array(iban.utf16)
    let code = String(decoding: units[min(4, units.count)..<min(8, units.count)], as: UTF16.self)
    return banks.first { $0.code == code }
  }

  // MARK: Cards and Civil IDs

  /// A payment card number, such as a salary card: 12 to 19 digits with a
  /// valid Luhn check digit.
  public static func isValidCardNumber(_ value: String) -> Bool {
    let digits = Array(WebJS.removing(value) { WebJS.isSpace($0) || $0 == "-" }.unicodeScalars)
    guard (12...19).contains(digits.count), digits.allSatisfy(WebJS.isDigit) else { return false }
    var sum = 0
    for i in 0..<digits.count {
      var d = Int(digits[digits.count - 1 - i].value - 0x30)
      if i % 2 == 1 {
        d *= 2
        if d > 9 { d -= 9 }
      }
      sum += d
    }
    return sum % 10 == 0
  }

  private static let civilIdWeights = [2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]

  /// A 12-digit Kuwaiti Civil ID: the century digit (2 for the 1900s, 3 for
  /// the 2000s), a real birth date (YYMMDD) and the check digit.
  public static func isValidCivilId(_ value: String) -> Bool {
    let id = Array(WebJS.removing(value, where: WebJS.isSpace).unicodeScalars)
    guard id.count == 12, id[0] == "2" || id[0] == "3", id.allSatisfy(WebJS.isDigit) else { return false }
    let digit = id.map { Int($0.value - 0x30) }
    let year = (digit[0] == 2 ? 1900 : 2000) + digit[1] * 10 + digit[2]
    let month = digit[3] * 10 + digit[4]
    let day = digit[5] * 10 + digit[6]
    guard (1...12).contains(month), day >= 1, day <= CivilDate.daysIn(year, month) else { return false }
    let sum = zip(civilIdWeights, digit).reduce(0) { $0 + $1.0 * $1.1 }
    let check = 11 - sum % 11
    return check < 10 && check == digit[11]
  }

  // MARK: Phones

  /// A Kuwaiti number written as "+965 9988 7766", or nil when it isn't one:
  /// 8 digits, mobiles starting with 4, 5, 6 or 9 and landlines with 2.
  public static func normalizeKuwaitPhone(_ value: String) -> String? {
    var digits = WebJS.removing(value) { !(WebJS.isDigit($0) || $0 == "+") }
    if digits.hasPrefix("+965") {
      digits = String(digits.dropFirst(4))
    } else if digits.hasPrefix("00965") {
      digits = String(digits.dropFirst(5))
    } else if digits.hasPrefix("965") && digits.utf16.count == 11 {
      digits = String(digits.dropFirst(3))
    }
    let scalars = Array(digits.unicodeScalars)
    guard scalars.count == 8, ["2", "4", "5", "6", "9"].contains(scalars[0]), scalars.allSatisfy(WebJS.isDigit)
    else { return nil }
    return "+965 \(digits.prefix(4)) \(digits.dropFirst(4))"
  }

  // MARK: Calendar

  /// The weekend in Kuwait: Friday and Saturday (JavaScript's getDay() numbers).
  public static let weekend = [5, 6]

  private struct IslamicHoliday {
    var month: Int
    var day: Int
    var days: Int
    var name: Bilingual
  }

  private static let islamicHolidays: [IslamicHoliday] = [
    IslamicHoliday(month: 7, day: 27, days: 1, name: Bilingual("Isra and Mi'raj", "الإسراء والمعراج")),
    IslamicHoliday(month: 10, day: 1, days: 3, name: Bilingual("Eid al-Fitr", "عيد الفطر")),
    IslamicHoliday(month: 12, day: 9, days: 1, name: Bilingual("Arafat Day", "يوم عرفة")),
    IslamicHoliday(month: 12, day: 10, days: 3, name: Bilingual("Eid al-Adha", "عيد الأضحى")),
    IslamicHoliday(month: 1, day: 1, days: 1, name: Bilingual("Islamic New Year", "رأس السنة الهجرية")),
    IslamicHoliday(month: 3, day: 12, days: 1, name: Bilingual("Prophet's Birthday", "المولد النبوي الشريف")),
  ]

  /// The Umm al-Qura calendar, read in UTC as the web reads it.
  private static let ummAlQura: Calendar = {
    var calendar = Calendar(identifier: .islamicUmmAlQura)
    calendar.timeZone = .gmt
    return calendar
  }()

  /// The Hijri year, month and day of a day (days since 1970-01-01, UTC).
  private static func hijri(_ day: Int) -> (year: Int, month: Int, day: Int) {
    let parts = ummAlQura.dateComponents(
      [.year, .month, .day], from: Date(timeIntervalSince1970: Double(day) * 86_400))
    return (parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  /// Public holidays of a Gregorian year. Islamic holidays follow the Umm
  /// al-Qura calendar; the official dates depend on the moon sighting and can
  /// move by a day, and the government may add bridge days. A holiday that
  /// starts at the end of December runs on into January, as on the web.
  public static func kuwaitHolidays(_ year: Int) -> [Holiday] {
    var out: [Holiday] = [
      Holiday(date: CivilDate.iso(year, 1, 1), name: Bilingual("New Year's Day", "رأس السنة الميلادية")),
      Holiday(date: CivilDate.iso(year, 2, 25), name: Bilingual("National Day", "العيد الوطني")),
      Holiday(date: CivilDate.iso(year, 2, 26), name: Bilingual("Liberation Day", "عيد التحرير")),
    ]
    let first = CivilDate.days(year, 1, 1)
    let end = CivilDate.days(year + 1, 1, 1)
    for day in first..<end {
      let h = hijri(day)
      guard let holiday = islamicHolidays.first(where: { $0.month == h.month && $0.day == h.day }) else { continue }
      for i in 0..<holiday.days { out.append(Holiday(date: CivilDate.iso(day + i), name: holiday.name)) }
    }
    // A stable sort by date, as Array.prototype.sort.
    return out.enumerated()
      .sorted { a, b in a.element.date == b.element.date ? a.offset < b.offset : a.element.date < b.element.date }
      .map(\.element)
  }

  private static let hijriMonths: [Bilingual] = [
    Bilingual("Muharram", "محرم"),
    Bilingual("Safar", "صفر"),
    Bilingual("Rabiʻ I", "ربيع الأول"),
    Bilingual("Rabiʻ II", "ربيع الآخر"),
    Bilingual("Jumada I", "جمادى الأولى"),
    Bilingual("Jumada II", "جمادى الآخرة"),
    Bilingual("Rajab", "رجب"),
    Bilingual("Shaʻban", "شعبان"),
    Bilingual("Ramadan", "رمضان"),
    Bilingual("Shawwal", "شوال"),
    Bilingual("Dhuʻl-Qiʻdah", "ذو القعدة"),
    Bilingual("Dhuʻl-Hijjah", "ذو الحجة"),
  ]

  /// A date (`yyyy-MM-dd`) in the Hijri (Umm al-Qura) calendar, written as
  /// the web's `Intl` writes it in its long style: "Rabiʻ II 22, 1448 AH",
  /// "22 ربيع الآخر 1448 هـ". Empty for text that isn't a date (where the web
  /// throws).
  public static func formatHijri(_ value: String, _ language: Bilingual.Language) -> String {
    // value.split('-').map(Number), then Date.UTC(y, m - 1, d)
    let parts = value.components(separatedBy: "-").map { WebJS.toNumber(.string($0)) }
    guard parts.count >= 3, parts[0].isFinite, parts[1].isFinite, parts[2].isFinite,
      abs(parts[0]) < 300_000, abs(parts[1]) < 4_000_000, abs(parts[2]) < 100_000_000
    else { return "" }
    var year = Int(parts[0].rounded(.towardZero))
    if (0...99).contains(year) { year += 1900 }
    let month = Int(parts[1].rounded(.towardZero)) - 1
    let day = Int(parts[2].rounded(.towardZero))
    let normalizedYear = year + Int((Double(month) / 12).rounded(.down))
    let normalizedMonth = ((month % 12) + 12) % 12 + 1
    let h = hijri(CivilDate.days(normalizedYear, normalizedMonth, 1) + day - 1)
    guard (1...12).contains(h.month) else { return "" }
    let name = hijriMonths[h.month - 1][language]
    return language == .ar ? "\(h.day) \(name) \(h.year) هـ" : "\(name) \(h.day), \(h.year) AH"
  }
}

/// Proleptic Gregorian calendar arithmetic in days since 1970-01-01, as
/// JavaScript's Date counts (Foundation's Gregorian calendar switches to the
/// Julian one before 1582).
enum CivilDate {
  /// Days from 1970-01-01 to a date.
  static func days(_ year: Int, _ month: Int, _ day: Int) -> Int {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let m = month
    let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146_097 + doe - 719_468
  }

  /// The date `days` after 1970-01-01.
  static func date(_ days: Int) -> (year: Int, month: Int, day: Int) {
    let z = days + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let doe = z - era * 146_097
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let day = doy - (153 * mp + 2) / 5 + 1
    let month = mp < 10 ? mp + 3 : mp - 9
    return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
  }

  static func isLeap(_ year: Int) -> Bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
  }

  static func daysIn(_ year: Int, _ month: Int) -> Int {
    switch month {
    case 2: isLeap(year) ? 29 : 28
    case 4, 6, 9, 11: 30
    default: 31
    }
  }

  static func iso(_ year: Int, _ month: Int, _ day: Int) -> String {
    WebJS.padStart(String(year), 4) + "-" + WebJS.padStart(String(month), 2) + "-" + WebJS.padStart(String(day), 2)
  }

  static func iso(_ days: Int) -> String {
    let d = date(days)
    return iso(d.year, d.month, d.day)
  }
}
