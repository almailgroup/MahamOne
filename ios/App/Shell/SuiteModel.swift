import MahamKit
import SwiftUI

// The suite's shape (`src/suite/types.ts`): each app of Maham One describes
// itself in a manifest (Shell/SuiteManifests.swift), and the shell (drawer,
// app switcher, tab bar, create menu, search, home) is built from them.
// Labels are the web's English keys; `t()` them when shown.

/// The apps of Maham One: the classic four, and Sales and Inventory of the split layout.
enum SuiteAppID: String, CaseIterable, Sendable {
  case books, people, crm, compliance, sales, inventory
}

/// How a company lays out its apps (`Company.appLayout`): today's four, or
/// Maham Books split into Sales, Books (finance) and Inventory.
enum SuiteLayout: Sendable {
  case classic, split
}

/// What someone may do in an app: nothing (`none` on the web: it is
/// hidden), look, work in it, or set it up.
enum SuiteAccess: Int, Comparable, Sendable {
  case hidden, view, edit, manage

  static func < (a: SuiteAccess, b: SuiteAccess) -> Bool { a.rawValue < b.rawValue }

  var canOpen: Bool { self != .hidden }
  var canEdit: Bool { self == .edit || self == .manage }
}

/// Who opens an app: a role in a cloud company, or a company kept on this device only.
enum AccessKey: Hashable, Sendable {
  case device, owner, admin, accountant, staff, viewer

  init(_ role: MemberRole?) {
    switch role {
    case .owner: self = .owner
    case .admin: self = .admin
    case .accountant: self = .accountant
    case .staff: self = .staff
    case .viewer: self = .viewer
    case nil: self = .device
    }
  }
}

/// An app's colours: its icon on a tint (`APP_TONES` in `src/suite/switcher.tsx`).
enum AppTone: Sendable {
  case indigo, emerald, sky, amber, violet, teal
  /// Maham Tasks, the native app's second department.
  case blue

  var background: Token {
    switch self {
    case .indigo: .indigo(100)
    case .emerald: .emerald(100)
    case .sky: .sky(100)
    case .amber: .amber(100)
    case .violet: .violet(100)
    case .teal: .teal(100)
    case .blue: .blue(100)
    }
  }

  var foreground: Token {
    switch self {
    case .indigo: .indigo(700)
    case .emerald: .emerald(700)
    case .sky: .sky(700)
    case .amber: .amber(800)
    case .violet: .violet(700)
    case .teal: .teal(800)
    case .blue: .blue(700)
    }
  }
}

/// Shown only with a company setting on (`src/features/shell/nav.ts`).
enum NavCondition: Sendable {
  /// VAT returns: taxes are on.
  case taxes
  /// Compliance → Vehicles: the register's extras.
  case registerExtras
  /// Compliance → Files: the document finder.
  case fileFinder
  /// Approvals, once the owner turned them on.
  case approvals
  /// People → Approvals, with salary approval on.
  case payrollApprovals
  /// Manpower costing, where it can be used.
  case costing
}

/// The company settings that show or hide navigation entries.
struct NavFlags: Sendable {
  var taxes = false
  var registerExtras = false
  var fileFinder = false
  var approvals = false
  var payrollApprovals = false
  var costing = false

  func shows(_ condition: NavCondition?) -> Bool {
    switch condition {
    case nil: true
    case .taxes: taxes
    case .registerExtras: registerExtras
    case .fileFinder: fileFinder
    case .approvals: approvals
    case .payrollApprovals: payrollApprovals
    case .costing: costing
    }
  }
}

/// A page in a navigation group (no icon of its own).
struct NavLink: Sendable, Hashable {
  let to: String
  let label: String
  var keywords: String?
  var only: NavCondition?

  init(_ to: String, _ label: String, keywords: String? = nil, only: NavCondition? = nil) {
    self.to = to
    self.label = label
    self.keywords = keywords
    self.only = only
  }
}

/// A top-level entry of the drawer, a footer link or a tab.
struct NavTopLink: Sendable, Hashable {
  let to: String
  let label: String
  let icon: Icon
  /// Only this exact path is active (Home).
  var end: Bool
  var keywords: String?
  var only: NavCondition?

  init(
    _ to: String, _ label: String, icon: Icon, end: Bool = false, keywords: String? = nil,
    only: NavCondition? = nil
  ) {
    self.to = to
    self.label = label
    self.icon = icon
    self.end = end
    self.keywords = keywords
    self.only = only
  }
}

/// A group of the drawer that folds open.
struct NavGroup: Sendable, Hashable {
  let id: String
  let label: String
  let icon: Icon
  var children: [NavLink]
}

enum NavEntry: Sendable, Hashable {
  case link(NavTopLink)
  case group(NavGroup)
}

/// Something that can be created (`src/features/shell/create.ts`).
struct CreateAction: Sendable, Hashable, Identifiable {
  let id: String
  /// "Invoice".
  let label: String
  /// "New invoice" (search, the home's tiles).
  let command: String
  let to: String
  let icon: Icon
  var keywords: String?
  /// Offered only while manpower costing is in effect.
  var costingOnly = false
}

struct CreateGroup: Sendable, Hashable {
  let label: String
  var actions: [CreateAction]
}

/// One of an app's main pages, as a round tile on the home.
struct SuiteTool: Sendable, Hashable {
  let to: String
  let label: String
  let icon: Icon
  var keywords: String?

  init(_ to: String, _ label: String, icon: Icon, keywords: String? = nil) {
    self.to = to
    self.label = label
    self.icon = icon
    self.keywords = keywords
  }
}

/// An app's manifest (`src/suite/types.ts`).
struct SuiteApp: Sendable, Identifiable {
  let id: SuiteAppID
  /// "Maham Books", untranslated.
  let name: String
  let nameAr: String
  /// An English key.
  let description: String
  let icon: Icon
  let tone: AppTone
  /// Where the app opens.
  let home: String
  /// First path segments of its pages.
  let owns: [String]
  /// Other apps' pages it lists too; opened from here they keep its drawer.
  var shares: [String] = []
  let nav: [NavEntry]
  let footer: [NavTopLink]
  let create: [CreateGroup]
  let tools: [SuiteTool]
  /// The phone's three tabs around the + button.
  let tabs: [NavTopLink]
  let access: [AccessKey: SuiteAccess]
  /// A first version ("Beta").
  var preview = false

  /// The name in the language on screen.
  func title(arabic: Bool) -> String { arabic ? nameAr : name }

  /// The drawer's entries for this company (`visibleNav`).
  func visibleNav(_ flags: NavFlags) -> [NavEntry] {
    nav.compactMap { entry -> NavEntry? in
      switch entry {
      case .link(let link):
        return flags.shows(link.only) ? entry : nil
      case .group(var group):
        group.children = group.children.filter { flags.shows($0.only) }
        return .group(group)
      }
    }
  }
}

extension NavEntry {
  /// Every link of the entry, a group opened.
  var links: [(to: String, end: Bool)] {
    switch self {
    case .link(let link): [(link.to, link.end)]
    case .group(let group): group.children.map { ($0.to, false) }
    }
  }
}

/// Path matching, as the web's router and `src/features/shell/nav.ts`.
enum PathMatch {
  /// "/invoices" for "/invoices/x?y=1#z".
  static func pathOnly(_ path: String) -> String {
    let cut = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
    let bare = cut.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
    return bare.isEmpty ? "/" : String(bare)
  }

  /// "invoices" for "/invoices/x/edit", "" for "/".
  static func firstSegment(_ path: String) -> String {
    pathOnly(path).split(separator: "/").first.map(String.init) ?? ""
  }

  /// Whether a link is the current page or one of its sub-pages.
  static func isActive(_ pathname: String, _ to: String, end: Bool = false) -> Bool {
    let target = pathOnly(to)
    if target == "/" || end { return pathname == target }
    return pathname == target || pathname.hasPrefix(target + "/")
  }

  /// The link of the current page: the one matching it most closely.
  static func activeLink(_ pathname: String, _ links: [(to: String, end: Bool)]) -> String? {
    var best: String?
    for link in links {
      let target = pathOnly(link.to)
      guard isActive(pathname, target, end: link.end) else { continue }
      if best == nil || target.count > (best?.count ?? 0) { best = target }
    }
    return best
  }
}
