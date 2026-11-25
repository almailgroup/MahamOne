import SwiftUI

/// Everything that can be created (the web's `NewSheet` in
/// `src/features/shell/bottom-bar.tsx`), opening in place: the tab bar's
/// glass grows upwards around it, the page stays where it is, and the +
/// turns into a ×. The current app's groups come first; each group's
/// actions sit four to a row, an icon in a primary circle over its name.
/// When everything doesn't fit above the tab bar, it scrolls.
struct CreateMenu: View {
  let groups: [CreateGroup]
  /// The most it may take, so it stays below the top bar.
  let maxHeight: CGFloat
  let onChoose: (CreateAction) -> Void
  @Environment(\.palette) private var palette

  var body: some View {
    // All of it when it fits; else the actions scroll under the title.
    ViewThatFits(in: .vertical) {
      menu(scrolls: false)
      menu(scrolls: true)
    }
    .frame(maxHeight: maxHeight)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text(t("Create new")))
  }

  private func menu(scrolls: Bool) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(t("Create new"))
        .font(.web(16, .semibold))
        .foregroundStyle(palette.slate(900))
        .accessibilityAddTraits(.isHeader)
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 6)
      if scrolls {
        ScrollView { sections }
          .scrollBounceBehavior(.basedOnSize)
      } else {
        sections
      }
    }
  }

  private var sections: some View {
    VStack(alignment: .leading, spacing: 14) {
      ForEach(groups, id: \.label) { group in
        section(group)
      }
    }
    .padding(.horizontal, 8)
    .padding(.top, 6)
    .padding(.bottom, 10)
  }

  private func section(_ group: CreateGroup) -> some View {
    let columns = Array(repeating: GridItem(.flexible(), spacing: 2, alignment: .top), count: 4)
    return VStack(alignment: .leading, spacing: 6) {
      // No letter spacing in Arabic: it breaks the joined letters apart.
      Text(t(group.label))
        .font(.web(12, .semibold))
        .textCase(.uppercase)
        .kerning(LanguageStore.shared.isArabic ? 0 : 0.6)
        .foregroundStyle(palette.slate(500))
        .padding(.horizontal, 10)
        .accessibilityAddTraits(.isHeader)
      LazyVGrid(columns: columns, spacing: 2) {
        ForEach(group.actions) { action in
          Button {
            Haptics.play(.selection)
            onChoose(action)
          } label: {
            VStack(spacing: 6) {
              IconView(action.icon, size: 20)
                .foregroundStyle(palette.primary(700))
                .frame(width: 46, height: 46)
                .background(palette.primary(500).opacity(0.14), in: Circle())
              Text(t(action.label))
                .font(.web(11, .medium))
                .foregroundStyle(palette.slate(800))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .top)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
          }
          .buttonStyle(PressedFill(radius: WebRadius.lg, color: .slate(100)))
          .accessibilityLabel(Text(t(action.command)))
        }
      }
    }
  }
}
