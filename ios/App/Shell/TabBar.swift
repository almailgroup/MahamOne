import SwiftUI

/// The phone's floating tab bar (`src/features/shell/bottom-bar.tsx`): 12pt
/// from the sides and max(12, safe area) from the bottom, a 16pt radius,
/// in Liquid Glass. Five columns 64pt tall: the app's three tabs around the
/// + (the Create sheet; search for those who only look) and More (the
/// drawer, never active). In Arabic, Home is on the right. The bar and the
/// + share a glass container, so the + (glass tinted primary-solid) blends
/// with the bar as it is pressed, and turns into the search square when
/// the person can only look.
struct TabBar: View {
  let app: SuiteApp
  let canCreate: Bool
  let onCreate: () -> Void
  let onSearch: () -> Void
  let onMore: () -> Void
  @Environment(ShellRouter.self) private var router
  @Environment(ShellChrome.self) private var chrome
  @Environment(\.palette) private var palette
  @Namespace private var glass

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.xl, style: .continuous)
    let tabs = app.tabs
    GlassEffectContainer(spacing: 4) {
      HStack(spacing: 0) {
        if tabs.count > 0 { tab(tabs[0]) }
        if tabs.count > 1 { tab(tabs[1]) }
        centre.frame(maxWidth: .infinity)
        if tabs.count > 2 { tab(tabs[2]) }
        more
      }
      .padding(.horizontal, 6)
      .frame(height: 64)
      .frame(maxWidth: 512)
      .glassEffect(.regular, in: shape)
    }
    .padding(.horizontal, 12)
    .padding(.bottom, max(0, 12 - chrome.safeArea.bottom))
    .frame(maxWidth: .infinity)
  }

  private func tab(_ link: NavTopLink) -> some View {
    let active = PathMatch.isActive(router.currentPath, link.to, end: link.end)
    return Button {
      Haptics.play(.selection)
      router.go(path: link.to)
    } label: {
      TabItem(icon: link.icon, label: t(link.label))
        .foregroundStyle(active ? palette.primary(700) : palette.slate(600))
    }
    .buttonStyle(TabItemStyle())
    .accessibilityAddTraits(active ? .isSelected : [])
  }

  @ViewBuilder
  private var centre: some View {
    if canCreate {
      Button {
        Haptics.play(.press)
        onCreate()
      } label: {
        IconView(.plus, size: 24)
          .foregroundStyle(palette.onPrimary)
          .frame(width: 48, height: 48)
      }
      .buttonStyle(CentreButtonStyle())
      .glassEffectID("centre", in: glass)
      .accessibilityLabel(Text(t("Create new")))
    } else {
      Button {
        Haptics.play(.tap)
        onSearch()
      } label: {
        IconView(.search, size: 20)
          .foregroundStyle(palette.slate(600))
          .frame(width: 48, height: 48)
      }
      .buttonStyle(.webGlass(.rounded(WebRadius.xl), tint: palette.slate(100).opacity(0.7)))
      .glassEffectID("centre", in: glass)
      .accessibilityLabel(Text(t("Search")))
    }
  }

  private var more: some View {
    Button {
      Haptics.play(.open)
      onMore()
    } label: {
      TabItem(icon: .menu, label: t("More"))
        .foregroundStyle(palette.slate(600))
    }
    .buttonStyle(TabItemStyle())
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
