import SwiftUI

/// Everything that can be created, as a sheet from the bottom (`NewSheet`
/// in `src/features/shell/bottom-bar.tsx`), the only bottom sheet of the
/// web app: 24pt top corners, at most 88% of the screen, surface, over
/// `overlay` at 40%; "Create new" with a round close button (Liquid
/// Glass); the groups' tiles three to a row, the current app's groups first.
/// Choosing or closing plays a haptic; so does a tap on the backdrop
/// (felt as the sheet goes).
struct CreateSheet: View {
  let groups: [CreateGroup]
  let onChoose: (CreateAction) -> Void
  let onClose: () -> Void
  @Environment(ShellChrome.self) private var chrome
  @Environment(\.palette) private var palette
  @Environment(\.layoutDirection) private var direction
  /// Closed by its own buttons, which played their haptic already.
  @State private var closedHere = false

  var body: some View {
    // The whole sheet when it fits; else its tiles scroll under the title.
    ViewThatFits(in: .vertical) {
      sheet(scrolls: false)
      sheet(scrolls: true)
    }
    .frame(maxWidth: .infinity, maxHeight: chrome.screenSize.height * 0.88, alignment: .bottom)
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .accessibilityAction(.escape) { close() }
    .onDisappear {
      if !closedHere { Haptics.play(.close) }
    }
  }

  private func sheet(scrolls: Bool) -> some View {
    let shape = CornerShape.sides(topStart: WebRadius.xxl, topEnd: WebRadius.xxl, direction: direction)
    return VStack(spacing: 0) {
      HStack(spacing: 12) {
        Text(t("Create new")).webText(.cardTitle)
          .accessibilityAddTraits(.isHeader)
          .frame(maxWidth: .infinity, alignment: .leading)
        GlassIconButton(.x, label: t("Close"), haptic: nil) { close() }
          .padding(.trailing, -8)
      }
      .padding(.horizontal, 20)
      .padding(.top, 16)
      .padding(.bottom, 8)

      if scrolls {
        ScrollView { tiles }
      } else {
        tiles
      }
    }
    .frame(maxWidth: .infinity)
    .background(palette.surface, in: shape)
    .boxShadow(WebShadow.xxl, in: shape)
  }

  private var tiles: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(groups, id: \.label) { group in
        section(group)
      }
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 16 + chrome.safeArea.bottom)
  }

  private func section(_ group: CreateGroup) -> some View {
    let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
    return VStack(alignment: .leading, spacing: 6) {
      Text(t(group.label))
        .font(.web(12, .semibold))
        .foregroundStyle(palette.slate(500))
        .padding(.horizontal, 8)
        .accessibilityAddTraits(.isHeader)
      LazyVGrid(columns: columns, spacing: 6) {
        ForEach(group.actions) { action in
          Button {
            closedHere = true
            Haptics.play(.selection)
            onChoose(action)
          } label: {
            VStack(spacing: 6) {
              IconView(action.icon, size: 20)
                .foregroundStyle(palette.primary(700))
                .frame(width: 40, height: 40)
                .background(palette.primary(50), in: Circle())
              Text(t(action.label))
                .font(.web(12, .medium))
                .foregroundStyle(palette.slate(700))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(.horizontal, 4)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
          }
          .buttonStyle(PressedFill(radius: WebRadius.lg))
        }
      }
    }
    .padding(.vertical, 8)
  }

  private func close() {
    closedHere = true
    Haptics.play(.close)
    onClose()
  }
}
