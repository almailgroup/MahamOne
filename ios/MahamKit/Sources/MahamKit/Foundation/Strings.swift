import Foundation

// The rules of the web's `src/i18n/index.ts` and `names.ts`: the English
// text is the key, the Arabic comes from a dictionary (the app's
// `Resources/ar.json`, generated from `src/i18n/ar` by
// `scripts/ios-strings.ts`), text missing from it shows in English, and
// `{name}` placeholders are filled from variables. The app's
// `App/Localization` holds the current language and calls these.

/// The interface language (`Language` on the web).
public enum InterfaceLanguage: String, CaseIterable, Codable, Sendable {
  case en, ar

  /// `isRtl`.
  public var isRightToLeft: Bool { self == .ar }

  /// The page's `lang` on the web: "ar-KW" or "en".
  public var tag: String { self == .ar ? "ar-KW" : "en" }

  /// The web's first-visit choice: Arabic when the browser's (here: the
  /// device's) first language is Arabic, English otherwise.
  public static func preferred(_ languages: [String]) -> InterfaceLanguage {
    guard let first = languages.first else { return .en }
    return first.lowercased().hasPrefix("ar") ? .ar : .en
  }

  /// The web's `storedLanguage()`: the saved choice when it is `en` or
  /// `ar`, otherwise from the device's languages.
  public static func stored(_ saved: String?, preferredLanguages: [String]) -> InterfaceLanguage {
    if let saved, let language = InterfaceLanguage(rawValue: saved) { return language }
    return preferred(preferredLanguages)
  }
}

public enum I18n {
  /// Where the web keeps the language (`localStorage`); the app keeps it in
  /// `UserDefaults` under the same key.
  public static let storageKey = "almailbooks.language"

  /// Arabic's six plural forms; `other` is always there.
  public struct PluralForms: Hashable, Codable, Sendable {
    public var zero: String?
    public var one: String?
    public var two: String?
    public var few: String?
    public var many: String?
    public var other: String

    public init(
      zero: String? = nil, one: String? = nil, two: String? = nil, few: String? = nil, many: String? = nil,
      other: String
    ) {
      self.zero = zero
      self.one = one
      self.two = two
      self.few = few
      self.many = many
      self.other = other
    }

    public subscript(category: PluralCategory) -> String? {
      switch category {
      case .zero: zero
      case .one: one
      case .two: two
      case .few: few
      case .many: many
      case .other: other
      }
    }
  }

  /// A dictionary entry: the translation, or its plural forms.
  public enum Entry: Hashable, Sendable, Decodable {
    case text(String)
    case plural(PluralForms)

    public init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let text = try? container.decode(String.self) {
        self = .text(text)
      } else {
        self = .plural(try container.decode(PluralForms.self))
      }
    }
  }

  /// `Intl.PluralRules` categories.
  public enum PluralCategory: String, CaseIterable, Sendable {
    case zero, one, two, few, many, other
  }

  /// A language's dictionary: English key → entry.
  public struct Table: Sendable {
    public let entries: [String: Entry]

    public init(_ entries: [String: Entry] = [:]) {
      self.entries = entries
    }

    /// Reads `ar.json`: `{ "English": "Arabic" | { "zero": …, "other": … } }`.
    public init(json: Data) throws {
      self.entries = try JSONDecoder().decode([String: Entry].self, from: json)
    }

    public static let empty = Table()

    public subscript(key: String) -> Entry? { entries[key] }

    public var count: Int { entries.count }
  }

  /// `interpolate`: `{name}` (letters, digits and `_`) is replaced by
  /// `vars[name]`; a placeholder without a variable is left as it is.
  public static func interpolate(_ text: String, _ vars: [String: String]) -> String {
    if vars.isEmpty || !text.contains("{") { return text }
    let scalars = Array(text.unicodeScalars)
    var result = String.UnicodeScalarView()
    var index = 0
    while index < scalars.count {
      if scalars[index] == "{" {
        var end = index + 1
        while end < scalars.count, isWordCharacter(scalars[end]) { end += 1 }
        if end > index + 1, end < scalars.count, scalars[end] == "}" {
          var name = String.UnicodeScalarView()
          name.append(contentsOf: scalars[(index + 1)..<end])
          if let value = vars[String(name)] {
            result.append(contentsOf: value.unicodeScalars)
            index = end + 1
            continue
          }
        }
      }
      result.append(scalars[index])
      index += 1
    }
    return String(result)
  }

  /// `\w` in a JavaScript regular expression.
  private static func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
    ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "_"
  }

  /// `new Intl.PluralRules(language).select(count)`. The count is first
  /// rounded to 3 decimals, as Intl does; Arabic: 0 zero, 1 one, 2 two,
  /// 3–10 few and 11–99 many (by the last two digits), anything else other.
  public static func pluralCategory(_ count: Double, language: InterfaceLanguage) -> PluralCategory {
    guard count.isFinite else { return .other }
    let rounded = Money.round(Money.dec(count.magnitude), 3)
    var whole = Decimal()
    var source = rounded
    NSDecimalRound(&whole, &source, 0, .down)
    guard whole == rounded, let n = DigitString(decimal: rounded).int64 else { return .other }
    switch language {
    case .en:
      return n == 1 ? .one : .other
    case .ar:
      if n == 0 { return .zero }
      if n == 1 { return .one }
      if n == 2 { return .two }
      let rest = n % 100
      if (3...10).contains(rest) { return .few }
      if (11...99).contains(rest) { return .many }
      return .other
    }
  }

  /// The web's `localName(record, language)`: the Arabic name in the Arabic
  /// interface when there is one (trimmed), otherwise the main name.
  public static func localName(_ name: String, _ nameAr: String?, language: InterfaceLanguage) -> String {
    guard language == .ar, let nameAr else { return name }
    let trimmed = JSText.trim(nameAr)
    return trimmed.isEmpty ? name : trimmed
  }

  /// A language and its dictionary: what `t` and `tp` read.
  public struct Translator: Sendable {
    public let language: InterfaceLanguage
    public let table: Table

    public init(language: InterfaceLanguage, table: Table) {
      self.language = language
      self.table = table
    }

    public static let english = Translator(language: .en, table: .empty)

    /// `t(text, vars)`: the translation (its `other` form for a plural
    /// entry), or the English text when there is none, with placeholders
    /// filled.
    public func t(_ key: String, _ vars: [String: String] = [:]) -> String {
      let translated: String
      switch table[key] {
      case .text(let text): translated = text
      case .plural(let forms): translated = forms.other
      case nil: translated = key
      }
      return I18n.interpolate(translated, vars)
    }

    /// `tp(count, one, other, vars)`: `{count}` is the formatted number
    /// (unless `vars` gives one). English picks `one` for 1 and `other`
    /// otherwise; Arabic picks the plural form of the entry keyed by
    /// `other`.
    public func tp(_ count: Double, _ one: String, _ other: String, _ vars: [String: String] = [:]) -> String {
      var all = vars
      if all["count"] == nil { all["count"] = formatCount(count) }
      let found = table[other]
      guard language != .en, let found else {
        return I18n.interpolate(count == 1 ? one : other, all)
      }
      switch found {
      case .text(let text):
        return I18n.interpolate(text, all)
      case .plural(let forms):
        let category: PluralCategory =
          count == 0 && !(forms.zero ?? "").isEmpty ? .zero : I18n.pluralCategory(count, language: language)
        return I18n.interpolate(forms[category] ?? forms.other, all)
      }
    }

    public func tp(_ count: Int, _ one: String, _ other: String, _ vars: [String: String] = [:]) -> String {
      tp(Double(count), one, other, vars)
    }

    /// The count as the interface writes numbers, up to 3 decimals.
    public func formatCount(_ count: Double) -> String {
      Format.number(count, maximumFractionDigits: 3, locale: .interface(language))
    }

    /// `localName` in this language.
    public func localName(_ name: String, _ nameAr: String?) -> String {
      I18n.localName(name, nameAr, language: language)
    }
  }
}
