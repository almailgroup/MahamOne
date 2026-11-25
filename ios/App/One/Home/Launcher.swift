import SwiftUI

/// A round tile of the home: an app, something to create, or an app's tool
/// (`src/suite/home/tiles.ts`).
struct LauncherTile: Identifiable {
  enum Tone {
    case app(AppTone)
    /// primary-100 / primary-700: what can be created.
    case primary
    /// slate-100 / slate-700: the company's own links.
    case neutral

    var background: Token {
      switch self {
      case .app(let tone): tone.background
      case .primary: .primary(100)
      case .neutral: .slate(100)
      }
    }

    var foreground: Token {
      switch self {
      case .app(let tone): tone.foreground
      case .primary: .primary(700)
      case .neutral: .slate(700)
      }
    }
  }

  let id: String
  let label: String
  /// The link's name when it says more than the label ("New invoice").
  var name: String?
  let icon: Icon
  let tone: Tone
  let to: String
  var plus = false
  /// The app the tile opens (or, in the split layout, whose tool it is).
  var app: SuiteAppID?
  /// What the find box matches, normalised.
  let terms: String
}

/// An app's tools on the home, in a card.
struct ToolGroup: Identifiable {
  let app: SuiteApp
  let tiles: [LauncherTile]
  var id: SuiteAppID { app.id }
}

/// The tiles of the home, built from the manifests and the person's access.
enum LauncherTiles {
  /// What the home offers to create, the most used first; at most six.
  private static let quickCreate = ["invoice", "quote", "expense", "payment_in", "bill", "client", "employee"]
  static let maxCreate = 6

  @MainActor
  static func apps(_ suite: SuiteState) -> [LauncherTile] {
    let arabic = LanguageStore.shared.isArabic
    return suite.visibleApps.map { app in
      LauncherTile(
        id: "app:\(app.id.rawValue)", label: app.title(arabic: arabic), icon: app.icon, tone: .app(app.tone),
        to: app.home, app: app.id,
        terms: SearchText.normalize([app.name, app.nameAr, t(app.description)].joined(separator: " ")))
    }
  }

  /// "New invoice", "New employee"… for the apps the person works in: the
  /// most used first, and at least one for each of those apps.
  @MainActor
  static func create(_ suite: SuiteState, current: SuiteAppID) -> [LauncherTile] {
    if suite.readOnly { return [] }
    let allowed = Set(suite.createGroups(current: current).flatMap { $0.actions.map(\.id) })
    let offered = quickCreate.filter { allowed.contains($0) }
    var chosen = Set<String>()
    for app in suite.apps where suite.access(app.id).canEdit {
      let own = Set(app.create.flatMap { $0.actions.map(\.id) })
      if let first = offered.first(where: { own.contains($0) }), chosen.count < maxCreate { chosen.insert(first) }
    }
    for id in offered where chosen.count < maxCreate { chosen.insert(id) }
    return offered.filter { chosen.contains($0) }.compactMap { id in
      guard let action = CreateActions.byId(id) else { return nil }
      return LauncherTile(
        id: "action:\(id)", label: t(action.label), name: t(action.command), icon: action.icon, tone: .primary,
        to: action.to, plus: true,
        terms: SearchText.normalize(
          [t(action.command), action.command, t(action.label), action.keywords ?? ""].joined(separator: " ")))
    }
  }

  /// Each app's main tools.
  @MainActor
  static func tools(_ suite: SuiteState) -> [ToolGroup] {
    let arabic = LanguageStore.shared.isArabic
    let split = suite.layout == .split
    return suite.visibleApps.map { app in
      ToolGroup(
        app: app,
        tiles: app.tools.map { tool in
          LauncherTile(
            id: "tool:\(app.id.rawValue):\(tool.to)", label: t(tool.label), icon: tool.icon, tone: .app(app.tone),
            to: tool.to, app: split ? app.id : nil,
            terms: SearchText.normalize(
              [t(tool.label), tool.label, tool.keywords ?? "", app.title(arabic: arabic)].joined(separator: " ")))
        })
    }
  }

  /// The tiles matching every word typed, each place once.
  static func filter(_ tiles: [LauncherTile], query: String) -> [LauncherTile] {
    let words = SearchText.normalize(query).split(separator: " ").map(String.init)
    guard !words.isEmpty else { return [] }
    var seen = Set<String>()
    return tiles.filter { tile in
      guard words.allSatisfy({ tile.terms.contains($0) }), !seen.contains(tile.to) else { return false }
      seen.insert(tile.to)
      return true
    }
  }
}

/// The home's launcher (`src/suite/home/launcher.tsx`): a box to find an
/// app or tool, then the apps, what can be created and each app's tools,
/// every one a round tile a tap away.
struct Launcher: View {
  /// A line under each app: "4 overdue invoices".
  let stats: [SuiteAppID: String]
  @Environment(SuiteState.self) private var suite
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var query = ""

  var body: some View {
    let current = suite.currentApp(path: router.currentPath).id
    let apps = LauncherTiles.apps(suite)
    let create = LauncherTiles.create(suite, current: current)
    let tools = LauncherTiles.tools(suite)
    let found = LauncherTiles.filter(apps + create + tools.flatMap { $0.tiles }, query: query)
    let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
    VStack(alignment: .leading, spacing: 24) {
      TextInput(
        text: $query, placeholder: t("Find an app or tool…"), leadingIcon: .search, rounded: true,
        submitLabel: .go,
        onSubmit: {
          if let first = found.first {
            Haptics.play(.tap)
            open(first)
          }
        }
      )
      .frame(maxWidth: 448)
      .accessibilityLabel(Text(t("Find an app or tool")))

      if searching {
        if found.isEmpty {
          Text(t("No app or tool matches your search."))
            .font(.web(14))
            .foregroundStyle(palette.slate(500))
            .padding(.vertical, 24)
        } else {
          TileGrid {
            ForEach(found) { tile in RoundTile(tile: tile) { open(tile) } }
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 12) {
          SectionTitle(t("Your apps"))
          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 16) {
            ForEach(apps) { tile in
              RoundTile(tile: tile, large: true, sub: tile.app.flatMap { stats[$0] }, badges: badges(tile)) {
                open(tile)
              }
            }
          }
        }

        if !create.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            SectionTitle(t("Create"))
            TileGrid {
              ForEach(create) { tile in RoundTile(tile: tile) { open(tile) } }
            }
          }
        }

        VStack(alignment: .leading, spacing: 12) {
          SectionTitle(t("Tools"))
          VStack(spacing: 16) {
            ForEach(tools) { group in
              toolCard(group.app, tiles: group.tiles)
            }
          }
        }
      }
    }
  }

  private func badges(_ tile: LauncherTile) -> [String] {
    guard let id = tile.app else { return [] }
    var badges: [String] = []
    if suite.app(id).preview { badges.append(t("Beta")) }
    if suite.access(id) == .view { badges.append(t("View only")) }
    return badges
  }

  private func toolCard(_ app: SuiteApp, tiles: [LauncherTile]) -> some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.xl, style: .continuous)
    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        AppMark(icon: app.icon, tone: app.tone, size: .small)
        Text(app.title(arabic: LanguageStore.shared.isArabic))
          .font(.web(14, .semibold))
          .foregroundStyle(palette.slate(800))
      }
      .padding(.horizontal, 4)
      TileGrid {
        ForEach(tiles) { tile in RoundTile(tile: tile) { open(tile) } }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(palette.surface, in: shape)
    .border(palette.slate(200), in: shape)
    .boxShadow(WebShadow.xs, in: shape)
  }

  private func open(_ tile: LauncherTile) {
    if let app = tile.app { suite.rememberApp(app) }
    router.go(path: tile.to)
  }
}

private struct SectionTitle: View {
  let title: String
  @Environment(\.palette) private var palette

  init(_ title: String) { self.title = title }

  var body: some View {
    Text(title).webText(.sectionTitle).accessibilityAddTraits(.isHeader)
  }
}

/// Tiles at least 76pt wide, as many to a row as fit (`minmax(4.75rem, 1fr)`).
private struct TileGrid<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 4)], spacing: 12) { content }
  }
}

/// A round tile: the icon on its colour in a circle (64pt for an app, 56pt
/// otherwise), the name below; a + badge on what creates something.
private struct RoundTile: View {
  let tile: LauncherTile
  var large = false
  var sub: String?
  var badges: [String] = []
  let action: () -> Void
  @Environment(\.palette) private var palette
  @Environment(\.layoutDirection) private var direction

  var body: some View {
    Button {
      Haptics.play(.tap)
      action()
    } label: {
      VStack(spacing: 6) {
        IconView(tile.icon, size: large ? 28 : 24)
          .foregroundStyle(palette.color(tile.tone.foreground))
          .frame(width: large ? 64 : 56, height: large ? 64 : 56)
          .background(palette.color(tile.tone.background), in: Circle())
          .ring(palette.hairline, in: Circle())
          .boxShadow(WebShadow.xs, in: Circle())
          .overlay(alignment: .bottomTrailing) {
            if tile.plus {
              IconView(.plusBold, size: 12)
                .foregroundStyle(palette.onPrimary)
                .frame(width: 20, height: 20)
                .background(palette.primarySolid, in: Circle())
                .ring(palette.surface, width: 2, in: Circle())
                // Out past the end corner, in either reading direction.
                .offset(x: direction == .rightToLeft ? -2 : 2, y: 2)
            }
          }
        Text(tile.label)
          .font(.web(large ? 14 : 12, .medium))
          .foregroundStyle(palette.slate(800))
          .multilineTextAlignment(.center)
          .lineLimit(2)
        if let sub {
          Text(sub)
            .font(.web(11))
            .foregroundStyle(palette.slate(500))
            .multilineTextAlignment(.center)
            .lineLimit(2)
        }
        if !badges.isEmpty {
          HStack(spacing: 4) {
            ForEach(badges, id: \.self) { Pill($0) }
          }
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 4)
      .padding(.vertical, 8)
      .contentShape(Rectangle())
    }
    .buttonStyle(TileButtonStyle())
    .accessibilityLabel(Text(tile.name ?? tile.label))
  }
}

/// Pressed, the tile takes slate-50 and its circle shrinks a little.
private struct TileButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    TileButtonBody(configuration: configuration)
  }
}

private struct TileButtonBody: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.palette) private var palette
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    configuration.label
      .background(
        configuration.isPressed ? palette.slate(50) : Color.clear,
        in: RoundedRectangle(cornerRadius: WebRadius.xl, style: .continuous)
      )
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
      .animation(WebMotion.standard, value: configuration.isPressed)
      .onChange(of: configuration.isPressed) { _, now in
        if now { Haptics.prepare() }
      }
  }
}
