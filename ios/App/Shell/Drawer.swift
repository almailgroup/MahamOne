import MahamKit
import SwiftUI

/// The phone's menu ("More" or the top bar's menu button): a panel from
/// the start edge, `min(320, width − 48)` wide, on `shell` with 24pt end
/// corners. At the top, fixed: the Maham One logo (home), the theme and
/// close buttons (Liquid Glass). Under it everything scrolls as one: the
/// company, the apps, then the open app's pages and its settings. The
/// signed-in person stays at the bottom. What closes it from inside plays
/// its own haptic; a tap on the backdrop is felt as it goes.
struct Drawer: View {
  let onClose: () -> Void
  @Environment(SuiteState.self) private var suite
  @Environment(ShellRouter.self) private var router
  @Environment(ShellChrome.self) private var chrome
  @Environment(\.palette) private var palette
  @Environment(\.layoutDirection) private var direction
  /// Closed by its own buttons and rows, which played their haptic already.
  @State private var closedHere = false

  var body: some View {
    let shape = CornerShape.sides(topEnd: WebRadius.xxl, bottomEnd: WebRadius.xxl, direction: direction)
    let app = suite.currentApp(path: router.currentPath)
    VStack(spacing: 0) {
      header

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          CompanySwitcher(onNavigate: closeHere)
            .padding(.bottom, 24)

          DrawerCaption(t("Apps"))
          AppTiles(onNavigate: closeHere)
            .padding(.bottom, 24)

          HStack(spacing: 8) {
            DrawerCaption(app.title(arabic: LanguageStore.shared.isArabic), bottom: 0)
            if app.preview { Pill(t("Beta")) }
          }
          .padding(.bottom, 8)
          DrawerNavigation(app: app, onNavigate: closeHere)

          if !app.footer.isEmpty {
            Rectangle().fill(palette.slate(200)).frame(height: 1)
              .padding(.horizontal, 12)
              .padding(.vertical, 12)
            let current = PathMatch.activeLink(
              router.currentPath,
              app.visibleNav(suite.flags).flatMap(\.links) + app.footer.map { (to: $0.to, end: $0.end) })
            VStack(spacing: 2) {
              ForEach(app.footer, id: \.to) { link in
                DrawerRow(icon: link.icon, label: t(link.label), active: current == link.to) {
                  Haptics.play(.selection)
                  go(Route(path: link.to))
                }
              }
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 16)
      }
      .scrollBounceBehavior(.basedOnSize)

      AccountCard(onNavigate: closeHere)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, max(12, chrome.safeArea.bottom))
        .overlay(alignment: .top) {
          Rectangle().fill(palette.slate(200)).frame(height: 1)
        }
    }
    .frame(width: min(320, chrome.screenSize.width - 48))
    .frame(maxHeight: .infinity, alignment: .top)
    .background(palette.shell, in: shape)
    .boxShadow(WebShadow.xxl, in: shape)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text(t("Menu")))
    .accessibilityAddTraits(.isModal)
    .accessibilityAction(.escape) {
      Haptics.play(.close)
      closeHere()
    }
    .onDisappear {
      if !closedHere { Haptics.play(.close) }
    }
  }

  /// The logo (a link home), the theme and close buttons.
  private var header: some View {
    HStack(spacing: 8) {
      Button {
        Haptics.play(.tap)
        go(.home)
      } label: {
        SuiteLogo(height: 26)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(PressedScale())
      .frame(maxWidth: .infinity, alignment: .leading)
      ThemeMenuButton(onNavigate: closeHere)
      GlassIconButton(.x, label: t("Close menu"), haptic: .close, action: closeHere)
    }
    .padding(.leading, 20)
    .padding(.trailing, 12)
    .padding(.top, chrome.safeArea.top + 4)
    .padding(.bottom, 12)
  }

  private func go(_ route: Route) {
    closeHere()
    router.go(route)
  }

  /// Closes the drawer from one of its own controls (which played its haptic).
  private func closeHere() {
    closedHere = true
    onClose()
  }
}

/// A heading of the menu ("APPS", the open app's name): 12pt, 600,
/// slate-500, upper case and a little spaced in English.
struct DrawerCaption: View {
  let text: String
  var bottom: CGFloat = 10
  @Environment(\.palette) private var palette

  init(_ text: String, bottom: CGFloat = 10) {
    self.text = text
    self.bottom = bottom
  }

  var body: some View {
    // No letter spacing in Arabic: it breaks the joined letters apart.
    Text(text)
      .font(.web(12, .semibold))
      .textCase(.uppercase)
      .kerning(LanguageStore.shared.isArabic ? 0 : 0.6)
      .foregroundStyle(palette.slate(500))
      .lineLimit(1)
      .padding(.horizontal, 12)
      .padding(.bottom, bottom)
      .accessibilityAddTraits(.isHeader)
  }
}

/// A menu row: 44pt (a sub-page 40pt), a 12pt radius. A page: a 20pt
/// slate-500 icon and its name, 15pt weight 500 slate-800. A sub-page
/// lines up with the names, 14pt slate-600. The page on screen is tinted
/// primary (its icon and name primary-700, bold); a closed group holding
/// it takes the colours without the tint. Pressed, a row fills slate-100.
struct DrawerRow<Trailing: View>: View {
  let icon: Icon?
  let label: String
  var active = false
  /// A closed group holding the current page takes the active colours, without the fill.
  var tinted = false
  /// A sub-page of a group: no icon, lined up with the pages' names.
  var child = false
  private let trailing: Trailing
  let action: () -> Void
  @Environment(\.palette) private var palette

  init(
    icon: Icon?, label: String, active: Bool = false, tinted: Bool = false, child: Bool = false,
    @ViewBuilder trailing: () -> Trailing, action: @escaping () -> Void
  ) {
    self.icon = icon
    self.label = label
    self.active = active
    self.tinted = tinted
    self.child = child
    self.trailing = trailing()
    self.action = action
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    let accent = active || tinted
    Button(action: action) {
      HStack(spacing: 12) {
        if let icon {
          IconView(icon, size: 20)
            .foregroundStyle(accent ? palette.primary(600) : palette.slate(500))
            .frame(width: 20)
        }
        Text(label)
          .font(.web(child ? 14 : 15, active ? .semibold : (child ? .regular : .medium)))
          .foregroundStyle(accent ? palette.primary(700) : (child ? palette.slate(600) : palette.slate(800)))
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        trailing
      }
      .padding(.leading, child ? 44 : 12)
      .padding(.trailing, 12)
      .frame(minHeight: child ? 40 : 44)
      .background(active ? palette.primary(500).opacity(0.12) : Color.clear, in: shape)
      .contentShape(shape)
    }
    .buttonStyle(PressedFill(radius: WebRadius.lg, color: .slate(100)))
    .accessibilityAddTraits(active ? .isSelected : [])
  }
}

extension DrawerRow where Trailing == EmptyView {
  init(
    icon: Icon?, label: String, active: Bool = false, tinted: Bool = false, child: Bool = false,
    action: @escaping () -> Void
  ) {
    self.init(
      icon: icon, label: label, active: active, tinted: tinted, child: child, trailing: { EmptyView() },
      action: action)
  }
}

/// The app's navigation, groups folding open (`SidebarContent`). Sales and
/// Integrations start open; each group remembers being open or closed, and
/// the group of the page on screen opens.
struct DrawerNavigation: View {
  let app: SuiteApp
  let onNavigate: () -> Void
  @Environment(SuiteState.self) private var suite
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @AppStorage("almailbooks.nav.groups") private var savedGroups = "{}"

  private static let defaultOpen: Set<String> = ["sales", "integrations"]

  var body: some View {
    let nav = app.visibleNav(suite.flags)
    let links = nav.flatMap(\.links) + app.footer.map { (to: $0.to, end: $0.end) }
    let current = PathMatch.activeLink(router.currentPath, links)
    VStack(spacing: 2) {
      ForEach(Array(nav.enumerated()), id: \.offset) { _, entry in
        switch entry {
        case .link(let link):
          DrawerRow(icon: link.icon, label: t(link.label), active: current == link.to) {
            Haptics.play(.selection)
            go(link.to)
          }
        case .group(let group):
          if !group.children.isEmpty {
            groupView(group, current: current)
          }
        }
      }
    }
    .onAppear { openGroup(holding: current, in: nav) }
  }

  private func groupView(_ group: NavGroup, current: String?) -> some View {
    let open = isOpen(group.id)
    let holdsCurrent = group.children.contains { $0.to == current }
    return VStack(spacing: 2) {
      DrawerRow(icon: group.icon, label: t(group.label), tinted: holdsCurrent && !open) {
        // Closed, it points to the end (mirrored in Arabic), as the web's turned chevron.
        IconView(open ? .chevronDown : .chevronRight, size: 16).foregroundStyle(palette.slate(400))
      } action: {
        Haptics.play(.selection)
        toggle(group.id)
      }
      .accessibilityValue(Text(open ? t("Open") : t("Closed")))
      if open {
        VStack(spacing: 2) {
          ForEach(group.children, id: \.to) { child in
            DrawerRow(icon: nil, label: t(child.label), active: current == child.to, child: true) {
              Haptics.play(.selection)
              go(child.to)
            }
          }
        }
        // A thin line under the group's icon joins its pages to it.
        .overlay(alignment: .leading) {
          Rectangle().fill(palette.slate(200)).frame(width: 1.5)
            .padding(.vertical, 6)
            .padding(.leading, 21.25)
        }
        .padding(.bottom, 4)
      }
    }
  }

  private func go(_ path: String) {
    onNavigate()
    router.go(path: path)
  }

  // MARK: Open and closed groups, remembered on this iPhone

  private var state: [String: Bool] {
    guard let data = savedGroups.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([String: Bool].self, from: data)
    else { return [:] }
    return decoded
  }

  private func isOpen(_ id: String) -> Bool {
    state[id] ?? Self.defaultOpen.contains(id)
  }

  private func save(_ next: [String: Bool]) {
    guard let data = try? JSONEncoder().encode(next), let text = String(data: data, encoding: .utf8) else { return }
    savedGroups = text
  }

  private func toggle(_ id: String) {
    var next = state
    next[id] = !isOpen(id)
    withAnimation(WebMotion.standard) { save(next) }
  }

  private func openGroup(holding current: String?, in nav: [NavEntry]) {
    for entry in nav {
      if case .group(let group) = entry, group.children.contains(where: { $0.to == current }), !isOpen(group.id) {
        var next = state
        next[group.id] = true
        save(next)
      }
    }
  }
}
