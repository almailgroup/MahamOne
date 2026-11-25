#if DEBUG
  // Preview mode's overlay (see PreviewMode.swift): what `-MahamOverlay` asks
  // for, opened once the Maham One shell is on screen, as a tap would open it.

  import SwiftUI

  extension View {
    /// Opens the overlay the launch asks for (nothing outside preview mode).
    /// The drawer, the create menu and search are the shell's own: it hands
    /// over its `open` functions. The app switcher hangs from a top bar
    /// button whose state is its own, so its panel is opened here, from a
    /// stand-in drawn where that button is.
    ///
    /// `theme` opens the drawer only. The theme menu's panel is private to
    /// Shell/ThemeMenu.swift and its button keeps its own state, so the
    /// screenshot script taps the drawer's "Theme" button itself (AXe).
    func previewOverlay(
      drawer: @escaping () -> Void, create: @escaping () -> Void, search: @escaping () -> Void
    ) -> some View {
      modifier(PreviewOverlayModifier(openDrawer: drawer, openCreate: create, openSearch: search))
    }
  }

  private struct PreviewOverlayModifier: ViewModifier {
    let openDrawer: () -> Void
    let openCreate: () -> Void
    let openSearch: () -> Void
    @Environment(ShellChrome.self) private var chrome
    @State private var switcherOpen = false

    /// Once a launch: back in Maham One from Maham Tasks, nothing opens again.
    @MainActor private static var opened = false

    func body(content: Content) -> some View {
      content
        .overlay {
          if PreviewMode.isOn { switcherAnchor }
        }
        .task { await openOnce() }
    }

    private func openOnce() async {
      guard PreviewMode.isOn, !Self.opened else { return }
      Self.opened = true
      // The shell first fades in and measures the screen.
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      switch PreviewMode.options.overlay {
      case .none: break
      case .drawer, .theme: openDrawer()
      case .create: openCreate()
      case .search: openSearch()
      case .switcher: switcherOpen = true
      }
    }

    /// An invisible 44pt button over the top bar's app switcher (its last
    /// button: 12pt from the end, in the middle of the 56pt bar under the
    /// status bar), with the switcher's own panel and width. If the bar's
    /// layout changes, only where the panel hangs from moves.
    private var switcherAnchor: some View {
      Color.clear
        .frame(width: 44, height: 44)
        .anchoredPanel(isPresented: $switcherOpen, alignment: .end, width: min(368, chrome.screenSize.width - 24)) {
          AppSwitcherPanel()
        }
        .padding(.top, chrome.safeArea.top + 6)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
  }
#endif
