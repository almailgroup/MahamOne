import MahamKit
import Observation
import SwiftUI

/// Where the shell is, as the web's address bar: the page opened from the
/// tab bar, the drawer, the launcher or search (`root`), and the pages
/// pushed over it from links inside pages (`path`). Pages read it with
/// `@Environment(ShellRouter.self)`.
@MainActor
@Observable
final class ShellRouter {
  /// The page opened from the shell; Home at first.
  private(set) var root: Route = .home
  /// The pages pushed over `root`, each with Back to return.
  var path: [Route] = []

  /// The page on screen.
  var current: Route { path.last ?? root }

  /// Its web address, for the tab bar and the drawer.
  var currentPath: String { current.path }

  #if DEBUG
    init() {
      // Preview mode (App/Preview): opens on the page the launch asks for.
      if PreviewMode.isOn {
        root = Route(path: PreviewMode.options.route)
      }
    }
  #endif

  /// A link inside a page: pushed (sliding in, as iOS does), with Back to return.
  func push(_ route: Route) {
    if route == .home {
      go(.home)
    } else {
      path.append(route)
    }
  }

  /// A web address followed from a page ("/invoices/abc").
  func push(path: String) {
    push(Route(path: path))
  }

  /// The tab bar, the drawer, the launcher and search: the page replaces
  /// what was there, as the web's links do, cross-fading into place
  /// (`WebMotion.page`); pages pushed over the old one go with it.
  func go(_ route: Route) {
    guard route != current else { return }
    withAnimation(WebMotion.page) {
      root = route
      path = []
    }
  }

  func go(path: String) {
    go(Route(path: path))
  }

  func back() {
    if !path.isEmpty { path.removeLast() }
  }
}

/// The native app's two departments: Maham One (the web's shell) and Maham Tasks.
enum Department: String, Sendable {
  case one, tasks
}

/// The suite around the pages: which department and which app are open,
/// what the person may do in each app, and the company's settings that
/// show or hide parts of the navigation (`src/suite/current-app.ts`).
@MainActor
@Observable
final class SuiteState {
  // Old storage names stay, as on the web (src/lib/brand.ts).
  private static let lastAppKey = "almailbooks.suite.app"
  private static let departmentKey = "maham.department"

  private var storedDepartment: Department
  private(set) var lastApp: SuiteAppID? = nil

  /// The person's role in the company on screen; nil until it is known.
  var role: MemberRole? = nil
  var roleKnown = false
  var layout: SuiteLayout = .classic
  var flags = NavFlags()
  /// The owner and approvers who turned on "Changes by your team" see the bell.
  var showsUpdatesBell = false

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    storedDepartment = defaults.string(forKey: Self.departmentKey).flatMap(Department.init(rawValue:)) ?? .one
    lastApp = defaults.string(forKey: Self.lastAppKey).flatMap(SuiteAppID.init(rawValue:))
    #if DEBUG
      // Preview mode (App/Preview): the department the launch asks for, and
      // no app remembered from an earlier launch.
      if PreviewMode.isOn {
        storedDepartment = PreviewMode.options.department
        lastApp = nil
      }
    #endif
  }

  /// The department on screen, remembered.
  var department: Department {
    get { storedDepartment }
    set {
      storedDepartment = newValue
      defaults.set(newValue.rawValue, forKey: Self.departmentKey)
    }
  }

  /// The apps of the company's layout.
  var apps: [SuiteApp] { SuiteManifests.apps(layout) }

  /// An app of the layout; one it doesn't have is Books (which holds its pages).
  func app(_ id: SuiteAppID) -> SuiteApp {
    apps.first { $0.id == id } ?? apps.first { $0.id == .books } ?? SuiteManifests.books
  }

  /// What the person may do in an app (`appAccess`): until the role is
  /// known nothing of People shows and the rest is only looked at; Books
  /// (and Sales and Inventory, its pages) is never hidden.
  func access(_ id: SuiteAppID) -> SuiteAccess {
    guard apps.contains(where: { $0.id == id }) else { return .hidden }
    if !roleKnown { return id == .people ? .hidden : .view }
    var access: SuiteAccess = app(id).access[AccessKey(role)] ?? .hidden
    if [.books, .sales, .inventory].contains(id), access == .hidden { access = .view }
    return access
  }

  /// The apps the person may open, in the layout's order.
  var visibleApps: [SuiteApp] { apps.filter { access($0.id).canOpen } }

  /// Viewers make nothing: the create menu says so and offers search.
  var readOnly: Bool { role == .viewer }

  /// The app a page belongs to; nil for the suite's own pages (Home, Settings).
  func appFor(path: String, last: SuiteAppID?) -> SuiteAppID? {
    let segment = PathMatch.firstSegment(path)
    if let last, apps.first(where: { $0.id == last })?.shares.contains(segment) == true { return last }
    return apps.first { $0.owns.contains(segment) }?.id
  }

  /// The app the shell shows for a page: the one the page belongs to, or
  /// the last one on the suite's own pages; never one the person may not open.
  func currentApp(path: String) -> SuiteApp {
    let candidates = [appFor(path: path, last: lastApp), lastApp, appFor(path: path, last: nil)]
    let id = candidates.compactMap { $0 }.first { access($0).canOpen }
    return app(id ?? .books)
  }

  /// Remembers the app of the page being visited, for the suite's own pages.
  func rememberApp(forPath path: String) {
    let candidates = [appFor(path: path, last: lastApp), appFor(path: path, last: nil)]
    if let id = candidates.compactMap({ $0 }).first(where: { access($0).canOpen }) { rememberApp(id) }
  }

  func rememberApp(_ id: SuiteAppID) {
    guard id != lastApp else { return }
    lastApp = id
    defaults.set(id.rawValue, forKey: Self.lastAppKey)
  }

  /// The app opens nothing of the web: an action is offered once its form
  /// is native (an area answers its route; each form checks it may save).
  static func hasNativeForm(_ action: CreateAction) -> Bool {
    AreaPages.page(for: Route(path: action.to)) != nil
  }

  /// What the create menu offers (`createGroups`): the current app's groups
  /// first, then those of the other apps the person works in, each action
  /// once and each group (by its name) once.
  func createGroups(current: SuiteAppID) -> [CreateGroup] {
    if readOnly { return [] }
    let first = app(current)
    let order = [first] + apps.filter { $0.id != first.id }
    var seen = Set<String>()
    var groups: [CreateGroup] = []
    for app in order where access(app.id).canEdit {
      for group in app.create {
        let actions = group.actions.filter {
          !seen.contains($0.id) && (flags.costing || !$0.costingOnly) && Self.hasNativeForm($0)
        }
        actions.forEach { seen.insert($0.id) }
        if actions.isEmpty { continue }
        if let index = groups.firstIndex(where: { $0.label == group.label }) {
          groups[index].actions += actions
        } else {
          groups.append(CreateGroup(label: group.label, actions: actions))
        }
      }
    }
    return groups
  }
}
