import SwiftUI

/// A colour of the theme, named as on the web: `.primary(600)` is
/// `--color-primary-600`, `.surface` is `--color-surface`. Steps are the
/// web's: 50, 100, 200 … 900, 950.
///
/// Roles (`src/index.css`): `page` behind the cards, `surface` for cards,
/// inputs and menus, `shell` behind the drawer, `overlay` (at 40%) behind
/// dialogs, `primarySolid` behind `onPrimary` text, `redSolid` behind white.
enum Token: Hashable, Sendable {
  case primary(Int)
  case slate(Int)
  case red(Int)
  case amber(Int)
  case emerald(Int)
  case blue(Int)
  case violet(Int)
  case indigo(Int)
  case sky(Int)
  case teal(Int)

  case surface
  case page
  case shell
  case overlay
  case primarySolid
  case primarySolidHover
  case primarySolidActive
  case onPrimary
  case redSolid
  case redSolidHover

  case chart1
  case chart2
  case chartGrid
  case chartAxis
  case chartHover
  /// Unpaid invoices by age, 1 (newest) to 5.
  case aging(Int)
  case scrollbarThumb

  /// The web's variable without `--color-`: "primary-600", "surface".
  var name: String {
    switch self {
    case .primary(let step): "primary-\(step)"
    case .slate(let step): "slate-\(step)"
    case .red(let step): "red-\(step)"
    case .amber(let step): "amber-\(step)"
    case .emerald(let step): "emerald-\(step)"
    case .blue(let step): "blue-\(step)"
    case .violet(let step): "violet-\(step)"
    case .indigo(let step): "indigo-\(step)"
    case .sky(let step): "sky-\(step)"
    case .teal(let step): "teal-\(step)"
    case .surface: "surface"
    case .page: "page"
    case .shell: "shell"
    case .overlay: "overlay"
    case .primarySolid: "primary-solid"
    case .primarySolidHover: "primary-solid-hover"
    case .primarySolidActive: "primary-solid-active"
    case .onPrimary: "on-primary"
    case .redSolid: "red-solid"
    case .redSolidHover: "red-solid-hover"
    case .chart1: "chart-1"
    case .chart2: "chart-2"
    case .chartGrid: "chart-grid"
    case .chartAxis: "chart-axis"
    case .chartHover: "chart-hover"
    case .aging(let n): "aging-\(n)"
    case .scrollbarThumb: "scrollbar-thumb"
    }
  }
}

/// The colour ramps every theme defines, for picking one by name (an app's tone).
enum Ramp: String, Sendable, CaseIterable {
  case primary, slate, red, amber, emerald, blue, violet, indigo, sky, teal

  func token(_ step: Int) -> Token {
    switch self {
    case .primary: .primary(step)
    case .slate: .slate(step)
    case .red: .red(step)
    case .amber: .amber(step)
    case .emerald: .emerald(step)
    case .blue: .blue(step)
    case .violet: .violet(step)
    case .indigo: .indigo(step)
    case .sky: .sky(step)
    case .teal: .teal(step)
    }
  }
}
