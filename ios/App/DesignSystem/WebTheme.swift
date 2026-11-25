import SwiftUI

/// The theme, the fonts and the reading direction for a tree of screens:
/// the palette of the theme on screen (`@Environment(\.palette)`), its light
/// or dark scheme, Inter and IBM Plex Sans Arabic at the web's 14pt body
/// size in slate-900, and right to left in Arabic. Put it at the root of
/// every window, sheet and cover that shows the web's design.
private struct WebThemeModifier: ViewModifier {
  @Environment(\.colorScheme) private var systemScheme

  func body(content: Content) -> some View {
    let store = ThemeStore.shared
    let arabic = LanguageStore.shared.isArabic
    let theme = store.activeTheme(systemScheme: systemScheme)
    let palette = Palette.of(theme)
    content
      .font(.web(14))
      .foregroundStyle(palette.slate(900))
      .tint(palette.primarySolid)
      .environment(\.palette, palette)
      .environment(\.colorScheme, theme.scheme)
      .environment(\.layoutDirection, arabic ? .rightToLeft : .leftToRight)
      // Western digits in Arabic too, as on the web (ar-KW-u-nu-latn).
      .environment(\.locale, Locale(identifier: arabic ? "ar_KW@numbers=latn" : "en_KW"))
      .preferredColorScheme(store.mode == .system ? nil : theme.scheme)
  }
}

extension View {
  /// The web's palette, fonts and layout direction for this screen tree.
  func webTheme() -> some View {
    modifier(WebThemeModifier())
  }

  /// The screens from before the rebuild (signing in, the lock, Maham
  /// Tasks) keep the system's fonts, text colour and accent under `.webTheme()`.
  func systemDesign() -> some View {
    font(.body).foregroundStyle(.primary).tint(nil)
  }
}
