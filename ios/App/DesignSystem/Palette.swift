import SwiftUI

/// One theme's colours, named as on the web (`Themes.generated.swift`).
/// Views read the palette on screen with `@Environment(\.palette)`.
///
///     palette.color(.slate(900))   // main text
///     palette[.primary(700)]       // links
///     palette.surface              // cards, inputs, menus
struct Palette: Sendable {
  let theme: ThemeID
  private let colors: [String: Color]

  init(theme: ThemeID) {
    self.theme = theme
    let values = ThemeColors.colors(of: theme)
    var map: [String: Color] = [:]
    for (index, name) in ThemeVariables.names.enumerated() where index < values.count {
      map[name] = values[index]
    }
    colors = map
  }

  var scheme: ColorScheme { theme.scheme }
  var isDark: Bool { theme.scheme == .dark }

  func color(_ token: Token) -> Color {
    colors[token.name] ?? .clear
  }

  subscript(_ token: Token) -> Color { color(token) }

  // MARK: Shorthands for the everyday colours

  func primary(_ step: Int) -> Color { color(.primary(step)) }
  func slate(_ step: Int) -> Color { color(.slate(step)) }
  var surface: Color { color(.surface) }
  var page: Color { color(.page) }
  var shell: Color { color(.shell) }
  var overlay: Color { color(.overlay) }
  var primarySolid: Color { color(.primarySolid) }
  var onPrimary: Color { color(.onPrimary) }
  var redSolid: Color { color(.redSolid) }

  /// slate-900 at 5%: the hairline ring around floating panels.
  var hairline: Color { color(.slate(900)).opacity(0.05) }

  // MARK: Every theme, worked out once

  private static let all: [ThemeID: Palette] = Dictionary(
    uniqueKeysWithValues: ThemeID.allCases.map { ($0, Palette(theme: $0)) })

  static func of(_ theme: ThemeID) -> Palette {
    all[theme] ?? Palette(theme: theme)
  }
}

private struct PaletteKey: EnvironmentKey {
  static let defaultValue: Palette = Palette.of(.classic)
}

extension EnvironmentValues {
  /// The palette of the theme on screen (set by `.webTheme()`).
  var palette: Palette {
    get { self[PaletteKey.self] }
    set { self[PaletteKey.self] = newValue }
  }
}
