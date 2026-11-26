import SwiftUI

/// The phone's floating tab bar (`src/features/shell/bottom-bar.tsx`): 12pt
/// from the sides and max(12, safe area) from the bottom, a 16pt radius,
/// in Liquid Glass. Five columns 64pt tall: the app's three tabs around the
/// + and More (the drawer, never active). In Arabic, Home is on the right.
///
/// The + is always there. It opens what can be created in place: the
/// bar's glass grows upwards into a panel (`CreateMenu`, 24pt corners)
/// above the tabs, and the + turns into a ×; a tab, More or the × closes
/// it. While the person's role is loading the panel waits with a spinner;
/// for those who may only look it says so and offers search
/// (`CreateMenuNote`). The bar and the + share a glass container, so the +
/// (glass tinted primary-solid) blends with the bar as it is pressed.
struct TabBar: View {
  let app: SuiteApp
  let groups: [CreateGroup]
  @Binding var createOpen: Bool
  let onChoose: (CreateAction) -> Void
  let onSearch: () -> Void
  let onMore: () -> Void
  @Environment(ShellRouter.self) private var router
  @Environment(ShellChrome.self) private var chrome
  @Environment(SuiteState.self) private var suite
  @Environment(\.palette) private var palette
  @Namespace private var glass

  var body: some View {
    let open = createOpen
    let shape = RoundedRectangle(cornerRadius: open ? WebRadius.xxl : WebRadius.xl, style: .continuous)
    let tabs = app.tabs
    GlassEffectContainer(spacing: 4) {
      VStack(spacing: 0) {
        if open {
          Group {
            if groups.isEmpty {
              CreateMenuNote(loading: !suite.roleKnown) {
                close(haptic: nil)
                onSearch()
              }
            } else {
              CreateMenu(groups: groups, maxHeight: menuHeight) { action in
                close(haptic: nil)
                onChoose(action)
              }
            }
          }
          .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
          .accessibilityAction(.escape) { close(haptic: .close) }
          Rectangle().fill(palette.slate(900).opacity(0.08)).frame(height: 1)
            .padding(.horizontal, 16)
            .transition(.opacity)
        }
        HStack(spacing: 0) {
          if tabs.count > 0 { tab(tabs[0]) }
          if tabs.count > 1 { tab(tabs[1]) }
          centre.frame(maxWidth: .infinity)
          if tabs.count > 2 { tab(tabs[2]) }
          more
        }
        .padding(.horizontal, 6)
        .frame(height: 64)
      }
      .frame(maxWidth: 512)
      // Open, the glass is frosted with the surface, so the actions read clearly.
      .glassEffect(open ? Glass.regular.tint(palette.surface.opacity(0.85)) : .regular, in: shape)
    }
    .padding(.horizontal, 12)
    .padding(.bottom, max(0, 12 - chrome.safeArea.bottom))
    .frame(maxWidth: .infinity)
  }

  /// The most the create menu may take: up to 16pt below the top bar.
  private var menuHeight: CGFloat {
    let above = chrome.safeArea.top + ShellMetrics.topBar + 16
    let below = max(12, chrome.safeArea.bottom) + 64 + 1
    return max(240, chrome.screenSize.height - above - below)
  }

  private func tab(_ link: NavTopLink) -> some View {
    let active = PathMatch.isActive(router.currentPath, link.to, end: link.end)
    return Button {
      Haptics.play(.selection)
      close(haptic: nil)
      router.go(path: link.to)
    } label: {
      TabItem(icon: link.icon, label: t(link.label))
        .foregroundStyle(active ? palette.primary(700) : palette.slate(600))
    }
    .buttonStyle(TabItemStyle())
    .accessibilityAddTraits(active ? .isSelected : [])
  }

  private var centre: some View {
    Button {
      if createOpen {
        close(haptic: .close)
      } else {
        Haptics.play(.press)
        withAnimation(WebMotion.expand) { createOpen = true }
      }
    } label: {
      IconView(.plus, size: 24)
        .rotationEffect(.degrees(createOpen ? 45 : 0))
        .foregroundStyle(palette.onPrimary)
        .frame(width: 48, height: 48)
    }
    .buttonStyle(CentreButtonStyle())
    .glassEffectID("centre", in: glass)
    .accessibilityLabel(Text(createOpen ? t("Close") : t("Create new")))
    .accessibilityAddTraits(createOpen ? .isSelected : [])
  }

  private var more: some View {
    Button {
      Haptics.play(.open)
      close(haptic: nil)
      onMore()
    } label: {
      TabItem(icon: .menu, label: t("More"))
        .foregroundStyle(palette.slate(600))
    }
    .buttonStyle(TabItemStyle())
  }

  /// Closes the create menu, if it is open, with `haptic`.
  private func close(haptic: Haptic?) {
    guard createOpen else { return }
    if let haptic { Haptics.play(haptic) }
    withAnimation(WebMotion.collapse) { createOpen = false }
  }
}

/// A tab's icon over its label (12pt, 500), filling its column. A long
/// label (Arabic) shrinks a little rather than being cut.
private struct TabItem: View {
  let icon: Icon
  let label: String

  var body: some View {
    VStack(spacing: 4) {
      IconView(icon, size: 20)
      Text(label)
        .font(.web(12, .medium))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .padding(.horizontal, 2)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
  }
}

/// Pressed, a tab dims and shrinks a little, so the touch is seen.
private struct TabItemStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    TabItemBody(configuration: configuration)
  }
}

private struct TabItemBody: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let pressed = configuration.isPressed
    configuration.label
      .opacity(pressed ? 0.6 : 1)
      .scaleEffect(pressed && !reduceMotion ? 0.94 : 1)
      .animation(WebMotion.standard, value: pressed)
      .onChange(of: pressed) { _, now in
        if now { Haptics.prepare(.selection) }
      }
  }
}

/// The + button: Liquid Glass tinted primary-solid (pressed: its active
/// shade) with the on-primary +, a 16pt radius, responding to the touch.
private struct CentreButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    CentreButtonBody(configuration: configuration)
  }
}

private struct CentreButtonBody: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.palette) private var palette

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.xl, style: .continuous)
    let pressed = configuration.isPressed
    configuration.label
      .contentShape(shape)
      .glassEffect(
        Glass.regular.tint(pressed ? palette.color(.primarySolidActive) : palette.primarySolid).interactive(),
        in: shape)
      .animation(WebMotion.standard, value: pressed)
      .onChange(of: pressed) { _, now in
        if now { Haptics.prepare(.press) }
      }
  }
}
