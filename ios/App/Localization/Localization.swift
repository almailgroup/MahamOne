import Foundation
import MahamKit
import Synchronization

// The interface wording, as the web's `src/i18n/index.ts` gives it. The
// English text is the key: wrap every string a person reads in `t(_:_:)`
// (or `tp(_:_:_:_:)` for counts). The Arabic comes from
// `Shared/Resources/ar.json`, which `scripts/ios-strings.ts` writes from the
// web's `src/i18n/ar/*.ts`; text missing from it shows in English.
//
//   t("Save")                                         → "حفظ"
//   t("Invoice {number} sent", ["number": number])    → placeholders keep their names
//   tp(n, "{count} invoice", "{count} invoices")      → Arabic picks one of six plural forms
//
// `t` and `tp` can be called from any thread or actor: they read the
// current language from a locked snapshot, which `LanguageStore` replaces
// when the language changes.

/// English or Arabic (`Language` on the web).
typealias Language = InterfaceLanguage

/// Translates interface text: the Arabic in the Arabic interface, or the
/// English key when there is none; `{name}` placeholders are filled from
/// `vars`.
nonisolated func t(_ key: String, _ vars: [String: String] = [:]) -> String {
  Localization.translator.t(key, vars)
}

/// Translates text that depends on a count. `{count}` is replaced with the
/// formatted number ("1,200"). The Arabic entry is keyed by the plural
/// (`other`) text and may give each Arabic plural form.
nonisolated func tp(_ count: Int, _ one: String, _ other: String, _ vars: [String: String] = [:]) -> String {
  Localization.translator.tp(count, one, other, vars)
}

/// `tp` for a count with decimals (up to 3 are shown).
nonisolated func tp(_ count: Double, _ one: String, _ other: String, _ vars: [String: String] = [:]) -> String {
  Localization.translator.tp(count, one, other, vars)
}

/// Fills `{name}` placeholders without translating.
nonisolated func interpolate(_ text: String, _ vars: [String: String]) -> String {
  I18n.interpolate(text, vars)
}

/// The name to show for a record that has an English and an Arabic name
/// (companies, contacts, items, accounts): Arabic in the Arabic interface
/// when there is one, otherwise the main name.
nonisolated func localName(_ name: String, _ nameAr: String?) -> String {
  Localization.translator.localName(name, nameAr)
}

/// The current language and dictionary, readable from anywhere.
nonisolated enum Localization {
  private static let state = Mutex(translator(for: storedLanguage(in: .standard)))

  /// What `t` and `tp` use now.
  static var translator: I18n.Translator {
    state.withLock { $0 }
  }

  /// The current interface language.
  static var language: Language { translator.language }

  /// The locale for numbers, amounts and dates (`interfaceLocale`): Arabic
  /// with Western digits, or the company's locale (`en-KW` by default).
  static func formatLocale(companyLocale: String? = nil) -> FormatLocale {
    .interface(language, companyLocale: companyLocale)
  }

  /// Makes `language` the one `t` and `tp` use.
  static func use(_ language: Language) {
    let next = translator(for: language)
    state.withLock { $0 = next }
  }

  /// The saved choice, or the device's first language when nothing is
  /// saved (the web's `storedLanguage`).
  static func storedLanguage(in defaults: UserDefaults) -> Language {
    InterfaceLanguage.stored(
      defaults.string(forKey: I18n.storageKey), preferredLanguages: Locale.preferredLanguages)
  }

  static func translator(for language: Language) -> I18n.Translator {
    I18n.Translator(language: language, table: language == .ar ? arabic : .empty)
  }

  /// The Arabic dictionary, read from the bundle once.
  static let arabic: I18n.Table = {
    guard let url = Bundle.main.url(forResource: "ar", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let table = try? I18n.Table(json: data)
    else {
      assertionFailure("Shared/Resources/ar.json is missing or unreadable; run scripts/ios-strings.ts")
      return .empty
    }
    return table
  }()
}
