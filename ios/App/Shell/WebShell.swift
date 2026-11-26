import Combine
import MahamKit
import SwiftUI
import UIKit

/// The app once you're in: Maham One as the web shows it on a phone
/// (`src/app/layout.tsx`), or Maham Tasks, the second department, chosen
/// from the app switcher.
struct WebShell: View {
  @Environment(AppModel.self) private var model
  @State private var router = ShellRouter()
  @State private var suite = SuiteState()
  @State private var chrome = ShellChrome()

  var body: some View {
    ZStack {
      switch suite.department {
      case .one:
        OneShell()
          .transition(.opacity)
      case .tasks:
        TasksDepartment()
          .transition(.opacity)
      }
    }
    .animation(WebMotion.department, value: suite.department)
    // The whole shell is rebuilt in the other language, as the web reloads;
    // the page on screen stays.
    .id(LanguageStore.shared.isArabic)
    .overlayHost()
    .background {
      // The screen and its safe area, read with the keyboard down (on
      // appearing and on turning), for the bars that float over the pages.
      // The reader keeps the safe area (one that ignores it reads zero
      // insets); the screen is its size plus the insets.
      GeometryReader { proxy in
        Color.clear
          .onAppear { measure(proxy) }
          .onChange(of: proxy.size) { _, _ in measure(proxy) }
          .onChange(of: proxy.safeAreaInsets) { _, _ in measure(proxy) }
      }
      .ignoresSafeArea(.keyboard)
    }
    .environment(router)
    .environment(suite)
    .environment(chrome)
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
      chrome.keyboardVisible = true
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
      chrome.keyboardVisible = false
    }
    .onChange(of: model.business.company?.id, initial: true) { _, _ in
      syncRole()
      model.openCompanyData()
    }
    .onChange(of: model.business.loadedOnce) { _, _ in syncRole() }
    .onChange(of: router.currentPath, initial: true) { _, path in
      suite.rememberApp(forPath: path)
    }
    .onChange(of: model.pendingLink, initial: true) { _, link in follow(link) }
  }

  private func measure(_ proxy: GeometryProxy) {
    let insets = proxy.safeAreaInsets
    chrome.safeArea = insets
    chrome.screenSize = CGSize(
      width: proxy.size.width + insets.leading + insets.trailing,
      height: proxy.size.height + insets.top + insets.bottom)
  }

  /// The person's role in the company on screen: until the companies are
  /// loaded it isn't known, and nothing of People shows.
  private func syncRole() {
    if let company = model.business.company {
      suite.role = company.role
      suite.roleKnown = true
    } else {
      suite.role = nil
      suite.roleKnown = false
    }
  }

  /// A widget, a reminder, Spotlight or Siri asked for something.
  private func follow(_ link: DeepLink?) {
    guard let link else { return }
    switch link {
    case .today, .newTask, .task, .project, .inbox:
      // Maham Tasks follows these itself once it is on screen.
      suite.department = .tasks
    case .invoice(let id):
      model.pendingLink = nil
      suite.department = .one
      router.go(.salesDocument(.invoice, id: id))
    case .client(let id):
      model.pendingLink = nil
      suite.department = .one
      router.go(.contact(.customer, id: id))
    }
  }
}

/// The Maham One department: the pages under the top bar, the floating tab
/// bar (whose + opens the create menu in place), and over them the drawer
/// and search.
private struct OneShell: View {
  @Environment(ShellRouter.self) private var router
  @Environment(SuiteState.self) private var suite
  @Environment(ShellChrome.self) private var chrome
  @Environment(\.palette) private var palette
  @State private var drawerOpen = false
  @State private var createOpen = false
  @State private var searchOpen = false

  var body: some View {
    @Bindable var router = router
    let app = suite.currentApp(path: router.currentPath)
    let groups = suite.createGroups(current: app.id)
    ZStack {
      NavigationStack(path: $router.path) {
        // The page opened from the shell cross-fades into place; pages
        // opened from links slide in over it.
        ZStack {
          RouteView(route: router.root)
            .id(router.root)
            .pageSwap()
        }
        .navigationDestination(for: Route.self) { route in
          RouteView(route: route)
        }
      }
      // The bars float over the pages, as on the web (a sticky header and a
      // fixed tab bar): the pages scroll under them, and leave room for them
      // with their own margins (WebPage, ShellMetrics). A safe-area inset
      // around the NavigationStack doesn't reach its pages.
      .overlay(alignment: .top) {
        TopBar(onMenu: { open(drawer: true) }, onSearch: { searchOpen = true })
      }
      .background(palette.page.ignoresSafeArea())

      // The create menu dims the page (and the top bar) but not the tab
      // bar it grows from.
      if createOpen {
        backdrop(z: 1) {
          Haptics.play(.close)
          withAnimation(WebMotion.collapse) { createOpen = false }
        }
      }

      if chrome.showsTabBar {
        VStack(spacing: 0) {
          Spacer(minLength: 0)
          TabBar(
            app: app, groups: groups, createOpen: $createOpen,
            onChoose: { action in router.go(path: action.to) },
            onSearch: { searchOpen = true }, onMore: { open(drawer: true) })
        }
        .zIndex(2)
      }

      if drawerOpen {
        backdrop(z: 3) { close(drawer: true) }
        HStack(spacing: 0) {
          Drawer(onClose: { close(drawer: true) })
          Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .vertical)
        .transition(.move(edge: .leading))
        .zIndex(4)
      }

      if searchOpen {
        SearchScreen(onClose: { withAnimation(WebMotion.fade) { searchOpen = false } })
          .transition(.opacity)
          .zIndex(5)
      }
    }
    .animation(WebMotion.fade, value: searchOpen)
    // Leaving the page, or the keyboard coming up, folds the menu away.
    .onChange(of: router.currentPath) { _, _ in createOpen = false }
    .onChange(of: chrome.showsTabBar) { _, shows in
      if !shows { createOpen = false }
    }
    #if DEBUG
      // Preview mode (App/Preview): opens the overlay the launch asks for.
      .previewOverlay(drawer: { open(drawer: true) }, create: { open(create: true) }, search: { searchOpen = true })
    #endif
  }

  /// `overlay` at 40%, fading in, at `z`; a tap closes what is over it.
  private func backdrop(z: Double, _ onTap: @escaping () -> Void) -> some View {
    palette.overlay.opacity(0.4)
      .ignoresSafeArea()
      .onTapGesture(perform: onTap)
      .transition(.opacity)
      .zIndex(z)
      .accessibilityLabel(Text(t("Close")))
      .accessibilityAddTraits(.isButton)
  }

  private func open(drawer: Bool = false, create: Bool = false) {
    if drawer { withAnimation(WebMotion.drawer) { drawerOpen = true } }
    if create { withAnimation(WebMotion.expand) { createOpen = true } }
  }

  private func close(drawer: Bool = false) {
    if drawer { withAnimation(WebMotion.drawer) { drawerOpen = false } }
  }
}
