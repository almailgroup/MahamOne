import SwiftUI

/// An editor's main buttons (Cancel, Save…) in a bar floating at the bottom
/// of the screen where the tab bar was (`src/components/ui/sticky-actions.tsx`):
/// Liquid Glass like the tab bar, a 16pt radius, 10pt padding, the buttons
/// at the end. Tinted buttons are glass that blends with the bar; the
/// others take a fill, since glass can't sit on glass. The tab bar makes
/// way while it is on screen.
///
///     EditorForm()
///       .stickyActions {
///         WebButton(t("Cancel"), variant: .outline) { … }
///         WebButton(t("Save")) { … }
///       }
extension View {
  func stickyActions<Buttons: View>(@ViewBuilder _ buttons: () -> Buttons) -> some View {
    safeAreaInset(edge: .bottom, spacing: 0) {
      StickyActions(content: buttons)
    }
  }
}

struct StickyActions<Content: View>: View {
  private let content: Content
  @Environment(ShellChrome.self) private var chrome: ShellChrome?

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.xl, style: .continuous)
    GlassEffectContainer(spacing: 4) {
      HStack(spacing: 8) {
        Spacer(minLength: 0)
        content
      }
      .padding(10)
      .glassEffect(.regular, in: shape)
    }
    .environment(\.webButtonOnGlass, true)
    .padding(.horizontal, 12)
    .padding(.bottom, max(0, 12 - (chrome?.safeArea.bottom ?? 0)))
    .onAppear { chrome?.registerStickyActions() }
    .onDisappear { chrome?.unregisterStickyActions() }
  }
}
