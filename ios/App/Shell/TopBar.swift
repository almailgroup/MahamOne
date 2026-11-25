import MahamKit
import SwiftUI

/// The sticky top bar (`src/features/shell/header.tsx`): 56pt tall, surface
/// at 85% with a blur and no border, a soft shadow once the page scrolls.
/// From the start: the menu, the Maham One mark (a link home; hidden below
/// 360pt), a divider, the company's name, then search, the language switch,
/// the updates bell (owners and approvers who turned it on) and the app
/// switcher. Its buttons are Liquid Glass, 44pt.
struct TopBar: View {
  let onMenu: () -> Void
  let onSearch: () -> Void
  @Environment(AppModel.self) private var model
  @Environment(SuiteState.self) private var suite
  @Environment(ShellRouter.self) private var router
  @Environment(ShellChrome.self) private var chrome
  @Environment(\.palette) private var palette
  @State private var narrow = false

  var body: some View {
    HStack(spacing: 8) {
      WebButton(icon: .menu, label: t("Open menu"), variant: .ghost, haptic: .open, action: onMenu)
        .padding(.leading, -4)
      if !narrow {
        Button {
          Haptics.play(.tap)
          router.go(.home)
        } label: {
          Image("SuiteMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 32, height: 32)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: LanguageStore.shared.isArabic ? "مهام ون" : "Maham One"))
        Rectangle().fill(palette.slate(200)).frame(width: 1, height: 20)
      }
      Text(ShellCompany.name(model.business))
        .font(.web(14, .semibold))
        .foregroundStyle(palette.slate(900))
        .lineLimit(1)
        .truncationMode(.tail)
        .layoutPriority(-1)
      Spacer(minLength: 0)
      WebButton(icon: .search, label: t("Search"), variant: .ghost, action: onSearch)
      LanguageSwitch()
      if suite.showsUpdatesBell {
        WebButton(icon: .bell, label: t("Updates"), variant: .ghost) { router.go(.notifications) }
      }
      AppSwitcherButton()
    }
    .padding(.horizontal, 12)
    .frame(height: 56)
    .frame(maxWidth: .infinity)
    .background {
      ZStack {
        Rectangle().fill(.ultraThinMaterial)
        palette.surface.opacity(0.85)
      }
      .ignoresSafeArea(edges: .top)
    }
    .boxShadow(chrome.scrolled ? WebShadow.topBar : [], in: Rectangle())
    .animation(.easeInOut(duration: 0.2), value: chrome.scrolled)
    .onGeometryChange(for: Bool.self) { $0.size.width < 360 } action: { narrow = $0 }
  }
}

/// Switches the interface between English and Arabic: Liquid Glass with an
/// 8pt radius, 14pt weight 500 slate-600, the `Languages` icon and the other
/// language, short ("ع" / "EN"), so the company's name keeps its room on a
/// phone (VoiceOver reads the full name); 44pt tall like the bar's other
/// buttons (a phone's touch size).
struct LanguageSwitch: View {
  @Environment(\.palette) private var palette

  var body: some View {
    let arabic = LanguageStore.shared.isArabic
    Button {
      Haptics.play(.change)
      LanguageStore.shared.language = arabic ? .en : .ar
    } label: {
      HStack(spacing: 4) {
        IconView(.languages, size: 16)
        Text(verbatim: arabic ? "EN" : "ع")
          .lineLimit(1)
          .fixedSize()
      }
      .font(.web(14, .medium))
      .foregroundStyle(palette.slate(600))
      .padding(.horizontal, 8)
      .frame(minWidth: 44, minHeight: 44)
    }
    .buttonStyle(.webGlass(.rounded(WebRadius.md)))
    .accessibilityLabel(Text(verbatim: arabic ? "English" : "العربية"))
  }
}

/// The company on screen, as the shell shows it, from what the app has
/// loaded (`AppModel.business`).
enum ShellCompany {
  @MainActor
  static func name(_ business: BusinessStore) -> String {
    guard let company = business.company else { return "" }
    return displayName(of: company, profile: business.profile?.id == company.id ? business.profile : nil)
  }

  @MainActor
  static func displayName(of company: Company, profile: CompanyProfile?) -> String {
    let arabic = LanguageStore.shared.isArabic
    if arabic, let nameAr = profile?.nameAr, !nameAr.trimmingCharacters(in: .whitespaces).isEmpty { return nameAr }
    return company.name
  }

  /// Up to two initials, for a company without a logo.
  static func initials(_ name: String) -> String {
    name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap { $0.first.map { String($0).uppercased() } }
      .joined()
  }
}
