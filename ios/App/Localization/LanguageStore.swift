import Foundation
import MahamKit
import Observation
import SwiftUI

/// The interface language, English or Arabic, switchable in the app as on
/// the web. The choice is saved (under the web's own key,
/// `almailbooks.language`); on first launch it follows the device's first
/// language, as the web follows the browser's.
///
/// Changing it also changes what `t` and `tp` return. The web remounts the
/// whole app when the language changes, so screens built with `t` should do
/// the same: key the root view on `language` (`.id(language)`) and give it
/// `layoutDirection` and `locale`.
@MainActor
@Observable
final class LanguageStore {
  static let shared = LanguageStore()

  /// English or Arabic; saved, and drives `layoutDirection`.
  var language: Language {
    didSet {
      guard language != oldValue else { return }
      defaults.set(language.rawValue, forKey: I18n.storageKey)
      Localization.use(language)
    }
  }

  /// The interface is in Arabic.
  var isArabic: Bool { language == .ar }

  /// Right to left in Arabic.
  var layoutDirection: LayoutDirection {
    language.isRightToLeft ? .rightToLeft : .leftToRight
  }

  /// The locale for SwiftUI's own text: Arabic (Kuwait) with Western
  /// digits, or English (Kuwait).
  var locale: Locale {
    Locale(identifier: isArabic ? "ar_KW@numbers=latn" : "en_KW")
  }

  /// The locale amounts, numbers and dates are written in, as the web's
  /// `interfaceLocale(company.locale)`.
  func formatLocale(companyLocale: String? = nil) -> FormatLocale {
    .interface(language, companyLocale: companyLocale)
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let language = Localization.storedLanguage(in: defaults)
    self.language = language
    Localization.use(language)
  }
}
