import Foundation
import Observation
import SwiftUI

/// Light or dark use the chosen light or dark theme; `system` follows the
/// iPhone's setting. Both choices are kept, so switching between light and
/// dark returns to the theme picked before (`src/lib/themes.ts`).
enum ThemeMode: String, Codable, Sendable, CaseIterable {
  case light, dark, system
}

/// What is saved: `{"mode":"light","light":"classic","dark":"midnight"}`,
/// the web's own shape under the web's own name (`almailbooks.theme`).
struct ThemePreference: Equatable, Sendable {
  var mode: ThemeMode
  var light: ThemeID
  var dark: ThemeID

  static let standard = ThemePreference(mode: .light, light: ThemeID.defaultLight, dark: ThemeID.defaultDark)

  /// Reads the saved JSON, or a bare theme id ("midnight"); anything else is Classic.
  static func parse(_ raw: String?) -> ThemePreference {
    guard let raw, !raw.isEmpty else { return .standard }
    if let id = ThemeID(rawValue: raw) {
      var preference = ThemePreference.standard
      preference.choose(id)
      return preference
    }
    guard let data = raw.data(using: .utf8),
      let fields = try? JSONDecoder().decode([String: String].self, from: data)
    else { return .standard }
    let mode = fields["mode"].flatMap(ThemeMode.init(rawValue:)) ?? .light
    let light = fields["light"].flatMap(ThemeID.init(rawValue:)).flatMap { $0.scheme == .light ? $0 : nil }
    let dark = fields["dark"].flatMap(ThemeID.init(rawValue:)).flatMap { $0.scheme == .dark ? $0 : nil }
    return ThemePreference(mode: mode, light: light ?? ThemeID.defaultLight, dark: dark ?? ThemeID.defaultDark)
  }

  var serialized: String {
    let fields = ["mode": mode.rawValue, "light": light.rawValue, "dark": dark.rawValue]
    guard let data = try? JSONEncoder().encode(fields), let text = String(data: data, encoding: .utf8) else {
      return ""
    }
    return text
  }

  /// The theme on screen, given the iPhone's own light or dark setting.
  func activeTheme(systemScheme: ColorScheme) -> ThemeID {
    let dark = mode == .dark || (mode == .system && systemScheme == .dark)
    return dark ? self.dark : light
  }

  /// Shows a theme: the iPhone's light or dark setting stops deciding.
  mutating func choose(_ id: ThemeID) {
    if id.scheme == .light {
      mode = .light
      light = id
    } else {
      mode = .dark
      dark = id
    }
  }

  /// While following the iPhone: the theme to use when it is light, or dark.
  mutating func chooseForDevice(_ id: ThemeID) {
    mode = .system
    if id.scheme == .light { light = id } else { dark = id }
  }
}

/// The theme preference of this iPhone. Choosing applies at once, all over
/// the app, and is remembered.
@MainActor
@Observable
final class ThemeStore {
  static let shared = ThemeStore()

  static let storageKey = "almailbooks.theme"

  private var preference: ThemePreference
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    preference = ThemePreference.parse(defaults.string(forKey: Self.storageKey))
  }

  var mode: ThemeMode {
    get { preference.mode }
    set { update { $0.mode = newValue } }
  }

  /// The theme for light mode; default Classic.
  var lightTheme: ThemeID {
    get { preference.light }
    set { if newValue.scheme == .light { update { $0.light = newValue } } }
  }

  /// The theme for dark mode; default Midnight.
  var darkTheme: ThemeID {
    get { preference.dark }
    set { if newValue.scheme == .dark { update { $0.dark = newValue } } }
  }

  /// The theme on screen, given the iPhone's own light or dark setting.
  func activeTheme(systemScheme: ColorScheme) -> ThemeID {
    preference.activeTheme(systemScheme: systemScheme)
  }

  /// The palette on screen, given the iPhone's own light or dark setting.
  func palette(for scheme: ColorScheme) -> Palette {
    Palette.of(activeTheme(systemScheme: scheme))
  }

  /// The header's quick switch: shows the theme (light or dark mode follows it).
  func choose(_ id: ThemeID) {
    update { $0.choose(id) }
  }

  /// Settings → Appearance while following the iPhone.
  func chooseForDevice(_ id: ThemeID) {
    update { $0.chooseForDevice(id) }
  }

  /// "Match my device": on follows the iPhone; off keeps the theme on screen now.
  func setFollowsDevice(_ on: Bool, systemScheme: ColorScheme) {
    if on {
      mode = .system
    } else {
      mode = activeTheme(systemScheme: systemScheme).scheme == .dark ? .dark : .light
    }
  }

  private func update(_ change: (inout ThemePreference) -> Void) {
    var next = preference
    change(&next)
    guard next != preference else { return }
    preference = next
    defaults.set(next.serialized, forKey: Self.storageKey)
  }
}
