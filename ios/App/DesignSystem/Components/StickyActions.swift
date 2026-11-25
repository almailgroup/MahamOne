import SwiftUI

/// An editor's main buttons (Cancel, Save…) in a bar floating at the bottom
/// of the screen where the tab bar was (`src/components/ui/sticky-actions.tsx`):
/// surface at 95% with a blur, a 16pt radius, a hairline ring and the tab
/// bar's shadow, 10pt padding, the buttons at the end. The tab bar makes way
/// while it is on screen.
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
  @Environment(\.palette) private var palette
  @Environment(ShellChrome.self) private var chrome: ShellChrome?

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.xl, style: .continuous)
    HStack(spacing: 8) {
      Spacer(minLength: 0)
      content
    }
    .padding(10)
    .background {
      shape.fill(palette.surface.opacity(0.95)).background(.ultraThinMaterial, in: shape)
    }
    .ring(palette.hairline, in: shape)
    .boxShadow(WebShadow.floatingBar, in: shape)
    .padding(.horizontal, 12)
    .padding(.bottom, max(0, 12 - (chrome?.safeArea.bottom ?? 0)))
    .onAppear { chrome?.registerStickyActions() }
    .onDisappear { chrome?.unregisterStickyActions() }
  }
}
