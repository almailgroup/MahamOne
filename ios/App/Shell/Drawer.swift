import MahamKit
import SwiftUI

/// The phone's menu ("More" or the top bar's menu button): a panel from
/// the start edge, `min(320, width − 48)` wide, on `shell` with 24pt end
/// corners and shadow-2xl (`src/app/layout.tsx` and
/// `src/features/shell/sidebar.tsx`).
struct Drawer: View {
  let onClose: () -> Void
  @Environment(SuiteState.self) private var suite
  @Environment(ShellRouter.self) private var router
  @Environment(ShellChrome.self) private var chrome
  @Environment(\.palette) private var palette
  @Environment(\.layoutDirection) private var direction

  var body: some View {
    let shape = CornerShape.sides(topEnd: WebRadius.xxl, bottomEnd: WebRadius.xxl, direction: direction)
    let app = suite.currentApp(path: router.currentPath)
    VStack(spacing: 8) {
      header
      VStack(alignment: .leading, spacing: 6) {
        Button {
          go(.home)
        } label: {
          SuiteLogo(height: 32)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        CompanySwitcher(onNavigate: onClose)
        AppTiles(onNavigate: onClose)
        CurrentAppRow(app: app) { go(Route(path: app.home)) }
      }
      .padding(.horizontal, 12)

      ScrollView {
        DrawerNavigation(app: app, onNavigate: onClose)
          .padding(.horizontal, 12)
          .padding(.vertical, 4)
      }
      .scrollBounceBehavior(.basedOnSize)

      VStack(spacing: 2) {
        let current = PathMatch.activeLink(
          router.currentPath, app.visibleNav(suite.flags).flatMap(\.links) + app.footer.map { (to: $0.to, end: $0.end) })
        ForEach(app.footer, id: \.to) { link in
          DrawerRow(icon: link.icon, label: t(link.label), active: current == link.to) { go(Route(path: link.to)) }
        }
        AccountCard(onNavigate: onClose)
      }
      .padding(.horizontal, 12)
      .padding(.bottom, max(12, chrome.safeArea.bottom))
    }
    .frame(width: min(320, chrome.screenSize.width - 48))
    .frame(maxHeight: .infinity, alignment: .top)
    .background(palette.shell, in: shape)
    .boxShadow(WebShadow.xxl, in: shape)
  }

  private var header: some View {
    HStack(spacing: 8) {
      Text(t("Menu"))
        .font(.web(14, .semibold))
        .foregroundStyle(palette.slate(600))
        .frame(maxWidth: .infinity, alignment: .leading)
      ThemeMenuButton(onNavigate: onClose)
      Button(action: onClose) {
        IconView(.x, size: 20)
          .foregroundStyle(palette.slate(500))
          .frame(width: 44, height: 44)
          .contentShape(Circle())
      }
      .buttonStyle(PressedFill(radius: 22))
      .accessibilityLabel(Text(t("Close menu")))
    }
    .padding(.leading, 20)
    .padding(.trailing, 12)
    .padding(.top, max(4, chrome.safeArea.top))
  }

  private func go(_ route: Route) {
    onClose()
    router.go(route)
  }
}

/// A drawer row: 44pt, a 12pt radius, 12pt side padding, 14pt weight 500
/// with an 18pt icon. Idle: slate-700 text, slate-500 icon. Active: surface,
/// primary-700 text, a primary-600 icon, shadow-xs and the hairline ring.
struct DrawerRow<Trailing: View>: View {
  let icon: Icon?
  let label: String
  var active = false
  /// A closed group holding the current page takes the active colours, without the pill.
  var tinted = false
  var indent: CGFloat = 0
  private let trailing: Trailing
  let action: () -> Void
  @Environment(\.palette) private var palette

  init(
    icon: Icon?, label: String, active: Bool = false, tinted: Bool = false, indent: CGFloat = 0,
    @ViewBuilder trailing: () -> Trailing, action: @escaping () -> Void
  ) {
    self.icon = icon
    self.label = label
    self.active = active
    self.tinted = tinted
    self.indent = indent
    self.trailing = trailing()
    self.action = action
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    let accent = active || tinted
    Button(action: action) {
      HStack(spacing: 12) {
        if let icon {
          IconView(icon, size: 18).foregroundStyle(accent ? palette.primary(600) : palette.slate(500))
        }
        Text(label)
          .font(.web(14, icon == nil && !active ? .regular : .medium))
          .foregroundStyle(
            accent ? palette.primary(700) : (icon == nil ? palette.slate(600) : palette.slate(700))
          )
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        trailing
      }
      .padding(.leading, indent > 0 ? indent : 12)
      .padding(.trailing, 12)
      .frame(height: 44)
      .background(active ? palette.surface : Color.clear, in: shape)
      .ring(active ? palette.hairline : .clear, in: shape)
      .boxShadow(active ? WebShadow.xs : [], in: shape)
      .contentShape(shape)
    }
    .buttonStyle(PressedFill(radius: WebRadius.lg, color: .surface))
    .accessibilityAddTraits(active ? .isSelected : [])
  }
}

extension DrawerRow where Trailing == EmptyView {
  init(
    icon: Icon?, label: String, active: Bool = false, tinted: Bool = false, indent: CGFloat = 0,
    action: @escaping () -> Void
  ) {
    self.init(
      icon: icon, label: label, active: active, tinted: tinted, indent: indent, trailing: { EmptyView() },
      action: action)
  }
}

/// The open app, linking to its own home: its mark and name, "Beta" on CRM.
struct CurrentAppRow: View {
  let app: SuiteApp
  let action: () -> Void
  @Environment(\.palette) private var palette

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        AppMark(icon: app.icon, tone: app.tone, size: .small)
        Text(app.title(arabic: LanguageStore.shared.isArabic))
          .font(.web(14, .semibold))
          .foregroundStyle(palette.slate(800))
          .lineLimit(1)
        if app.preview { Pill(t("Beta")) }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(PressedFill(radius: WebRadius.lg, color: .surface))
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
    return VStack(spacing: 1) {
      DrawerRow(icon: group.icon, label: t(group.label), tinted: holdsCurrent && !open) {
        // Closed, it points to the end (mirrored in Arabic), as the web's turned chevron.
        IconView(open ? .chevronDown : .chevronRight, size: 16).foregroundStyle(palette.slate(400))
      } action: {
        toggle(group.id)
      }
      if open {
        ForEach(group.children, id: \.to) { child in
          DrawerRow(icon: nil, label: t(child.label), active: current == child.to, indent: 42) {
            go(child.to)
          }
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
