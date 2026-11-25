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
    .animation(WebMotion.fade, value: suite.department)
    // The whole shell is rebuilt in the other language, as the web reloads;
    // the page on screen stays.
    .id(LanguageStore.shared.isArabic)
    .overlayHost()
    .background {
      // The screen and its safe area, read with the keyboard down (on
      // appearing and on turning), for the bars that float over the pages.
      GeometryReader { proxy in
        Color.clear
          .onAppear {
            chrome.safeArea = proxy.safeAreaInsets
            chrome.screenSize = proxy.size
          }
          .onChange(of: proxy.size) { _, size in
            chrome.safeArea = proxy.safeAreaInsets
            chrome.screenSize = size
          }
      }
      .ignoresSafeArea()
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
    .onChange(of: model.business.company?.id, initial: true) { _, _ in syncRole() }
    .onChange(of: model.business.loadedOnce) { _, _ in syncRole() }
    .onChange(of: router.currentPath, initial: true) { _, path in
      suite.rememberApp(forPath: path)
    }
    .onChange(of: model.pendingLink, initial: true) { _, link in follow(link) }
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
/// bar, and over them the Create sheet, the drawer and search.
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
        HomePage()
          .navigationDestination(for: Route.self) { route in
            RouteView(route: route)
          }
      }
      .safeAreaInset(edge: .top, spacing: 0) {
        TopBar(onMenu: { open(drawer: true) }, onSearch: { searchOpen = true })
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if chrome.showsTabBar {
          TabBar(
            app: app, canCreate: !groups.isEmpty, onCreate: { open(create: true) },
            onSearch: { searchOpen = true }, onMore: { open(drawer: true) })
        }
      }
      .background(palette.page.ignoresSafeArea())

      if createOpen {
        backdrop { close(create: true) }
        VStack(spacing: 0) {
          Spacer(minLength: 0)
          CreateSheet(
            groups: groups,
            onChoose: { action in
              close(create: true)
              router.go(path: action.to)
            },
            onClose: { close(create: true) })
        }
        .ignoresSafeArea(edges: .bottom)
        .transition(.move(edge: .bottom))
        .zIndex(2)
      }

      if drawerOpen {
        backdrop { close(drawer: true) }
        HStack(spacing: 0) {
          Drawer(onClose: { close(drawer: true) })
          Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .vertical)
        .transition(.move(edge: .leading))
        .zIndex(2)
      }

      if searchOpen {
        SearchScreen(onClose: { withAnimation(WebMotion.fade) { searchOpen = false } })
          .transition(.opacity)
          .zIndex(3)
      }
    }
    .animation(WebMotion.fade, value: searchOpen)
  }

  /// `overlay` at 40%, fading in; a tap closes what is over it.
  private func backdrop(_ onTap: @escaping () -> Void) -> some View {
    palette.overlay.opacity(0.4)
      .ignoresSafeArea()
      .onTapGesture(perform: onTap)
      .transition(.opacity)
      .zIndex(1)
      .accessibilityLabel(Text(t("Close")))
      .accessibilityAddTraits(.isButton)
  }

  private func open(drawer: Bool = false, create: Bool = false) {
    if drawer { withAnimation(WebMotion.drawer) { drawerOpen = true } }
    if create { withAnimation(WebMotion.sheet) { createOpen = true } }
  }

  private func close(drawer: Bool = false, create: Bool = false) {
    if drawer { withAnimation(WebMotion.drawer) { drawerOpen = false } }
    if create { withAnimation(WebMotion.sheet) { createOpen = false } }
  }
}
