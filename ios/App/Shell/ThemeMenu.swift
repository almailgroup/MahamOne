import SwiftUI

/// The palette button in the drawer's header (`src/features/theme/menu.tsx`):
/// a 44pt round Liquid Glass button opening every theme as a swatch, light
/// and dark, the one on screen checked; choosing applies at once. "Match my
/// device" follows the iPhone.
struct ThemeMenuButton: View {
  let onNavigate: () -> Void
  @State private var open = false

  var body: some View {
    GlassIconButton(.palette, label: t("Theme"), iconSize: 16) { open = true }
      .anchoredPanel(isPresented: $open, alignment: .end) {
        ThemeMenuPanel(onNavigate: onNavigate)
      }
  }
}

private struct ThemeMenuPanel: View {
  let onNavigate: () -> Void
  @Environment(\.palette) private var palette
  @Environment(\.dismissPanel) private var dismissPanel
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let store = ThemeStore.shared
    let current = palette.theme
    let shape = RoundedRectangle(cornerRadius: WebRadius.xl, style: .continuous)
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: 16) {
        Text(t("Theme")).font(.web(14, .semibold)).foregroundStyle(palette.slate(900))
        Spacer(minLength: 0)
        Text(t(current.nameKey)).font(.web(12)).foregroundStyle(palette.slate(500)).lineLimit(1)
      }
      .padding(.horizontal, 4)
      .padding(.bottom, 8)
      VStack(alignment: .leading, spacing: 8) {
        row(t("Light themes"), ThemeID.lightThemes, current: current, store: store)
        row(t("Dark themes"), ThemeID.darkThemes, current: current, store: store)
      }
      FollowDeviceSwitch()
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.slate(50), in: RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous))
        .padding(.top, 12)
      Button {
        Haptics.play(.tap)
        dismissPanel()
        onNavigate()
        router.go(.settings(section: "appearance"))
      } label: {
        HStack(spacing: 8) {
          Text(t("All appearance settings")).font(.web(14, .medium))
          Spacer(minLength: 0)
          IconView(.arrowRight, size: 16)
        }
        .foregroundStyle(palette.primary(700))
        .padding(.horizontal, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(.top, 8)
    }
    .padding(12)
    .frame(width: 5 * 44 + 4 * 4 + 24)
    .background(palette.surface, in: shape)
    .ring(palette.hairline, in: shape)
    .boxShadow(WebShadow.xl, in: shape)
  }

  private func row(_ label: String, _ ids: [ThemeID], current: ThemeID, store: ThemeStore) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.web(12, .medium)).foregroundStyle(palette.slate(500)).padding(.horizontal, 4)
      LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 4), count: 5), spacing: 4) {
        ForEach(ids, id: \.self) { id in
          let checked = id == current
          Button {
            if !checked { Haptics.play(.change) }
            store.choose(id)
          } label: {
            ThemeSwatch(theme: id, checked: checked)
              .frame(width: 44, height: 44)
              .overlay {
                if checked { Circle().strokeBorder(palette.primary(600), lineWidth: 2) }
              }
              .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(t(id.nameKey)))
          .accessibilityAddTraits(checked ? .isSelected : [])
        }
      }
    }
  }
}

/// "Match my device": on, the iPhone's light or dark setting picks the theme.
private struct FollowDeviceSwitch: View {
  @State private var on = ThemeStore.shared.mode == .system
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    Switch(t("Match my device"), isOn: $on)
      .onChange(of: on) { _, value in
        ThemeStore.shared.setFollowsDevice(value, systemScheme: scheme)
      }
      // Choosing a swatch shows that theme: the iPhone stops deciding.
      .onChange(of: ThemeStore.shared.mode) { _, mode in
        on = mode == .system
      }
  }
}

/// A round swatch: the theme's backdrop with its accent in the middle.
struct ThemeSwatch: View {
  let theme: ThemeID
  var checked = false

  var body: some View {
    let colors = Palette.of(theme)
    Circle()
      .fill(colors.shell)
      .frame(width: 28, height: 28)
      .border(Color.black.opacity(0.15), in: Circle())
      .overlay {
        ZStack {
          Circle().fill(colors.primarySolid).frame(width: 16, height: 16)
          if checked {
            IconView(.checkBold, size: 12).foregroundStyle(colors.onPrimary)
          }
        }
      }
      .accessibilityHidden(true)
  }
}
