import SwiftUI

/// The phone's floating tab bar (`src/features/shell/bottom-bar.tsx`): 12pt
/// from the sides and max(12, safe area) from the bottom, a 16pt radius,
/// surface at 95% with a blur, a hairline ring and a soft shadow. Five
/// columns 64pt tall: the app's three tabs around the + (the Create sheet;
/// search for those who only look) and More (the drawer, never active).
/// In Arabic, Home is on the right.
struct TabBar: View {
  let app: SuiteApp
  let canCreate: Bool
  let onCreate: () -> Void
  let onSearch: () -> Void
  let onMore: () -> Void
  @Environment(ShellRouter.self) private var router
  @Environment(ShellChrome.self) private var chrome
  @Environment(\.palette) private var palette

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.xl, style: .continuous)
    let tabs = app.tabs
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
    .background {
      ZStack {
        shape.fill(.ultraThinMaterial)
        shape.fill(palette.surface.opacity(0.95))
      }
    }
    .ring(palette.hairline, in: shape)
    .boxShadow(WebShadow.floatingBar, in: shape)
    .padding(.horizontal, 12)
    .padding(.bottom, max(0, 12 - chrome.safeArea.bottom))
    .frame(maxWidth: .infinity)
  }

  private func tab(_ link: NavTopLink) -> some View {
    let active = PathMatch.isActive(router.currentPath, link.to, end: link.end)
    return Button {
      router.go(path: link.to)
    } label: {
      VStack(spacing: 4) {
        IconView(link.icon, size: 20)
        Text(t(link.label)).font(.web(12, .medium)).lineLimit(1)
      }
      .foregroundStyle(active ? palette.primary(700) : palette.slate(600))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(active ? .isSelected : [])
  }

  @ViewBuilder
  private var centre: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.xl, style: .continuous)
    if canCreate {
      Button(action: onCreate) {
        IconView(.plus, size: 24)
          .foregroundStyle(palette.onPrimary)
          .frame(width: 48, height: 48)
      }
      .buttonStyle(CentreButtonStyle())
      .accessibilityLabel(Text(t("Create new")))
    } else {
      Button(action: onSearch) {
        IconView(.search, size: 20)
          .foregroundStyle(palette.slate(600))
          .frame(width: 48, height: 48)
          .background(palette.slate(100), in: shape)
          .contentShape(shape)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(t("Search")))
    }
  }

  private var more: some View {
    Button(action: onMore) {
      VStack(spacing: 4) {
        IconView(.menu, size: 20)
        Text(t("More")).font(.web(12, .medium)).lineLimit(1)
      }
      .foregroundStyle(palette.slate(600))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// The + button: primary-solid (pressed: its active shade), a 16pt radius,
/// shadow-lg in primary-solid at 30%.
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
    configuration.label
      .background(configuration.isPressed ? palette.color(.primarySolidActive) : palette.primarySolid, in: shape)
      .boxShadow(WebShadow.lg(tinted: palette.primarySolid.opacity(0.3)), in: shape)
      .contentShape(shape)
  }
}
