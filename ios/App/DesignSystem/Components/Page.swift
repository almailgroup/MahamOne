import Observation
import SwiftUI

/// What the shell's bars need to know about the page under them: whether it
/// has scrolled (the top bar's shadow), whether an editor's `StickyActions`
/// bar is up and whether the keyboard is (the tab bar makes way for both).
@MainActor
@Observable
final class ShellChrome {
  var scrolled = false
  var keyboardVisible = false
  private(set) var stickyActions = 0
  /// The screen's safe area and size, measured at the root of the shell.
  var safeArea = EdgeInsets()
  var screenSize = CGSize(width: 390, height: 844)

  var showsTabBar: Bool { stickyActions == 0 && !keyboardVisible }

  func registerStickyActions() { stickyActions += 1 }
  func unregisterStickyActions() { stickyActions = max(0, stickyActions - 1) }
}

/// The bars that float over every page of the shell, and the room a page
/// keeps for them.
enum ShellMetrics {
  /// The top bar (`header.tsx`): 56pt.
  static let topBar: CGFloat = 56
  /// Below the content: the tab bar (64pt, 12pt off the edge) plus a gap,
  /// 96pt with the page's own 20pt, as the web's main has.
  static let bottomRoom: CGFloat = 76
}

/// A page of the shell (`src/app/layout.tsx`'s main): `page` behind, the
/// window scrolls, 16pt at the sides and 20pt at the top; the tab bar's room
/// is kept at the bottom (the bars sit in the safe area, so the last row
/// always scrolls clear of them and of the home indicator). It starts at
/// the top each time it opens. With `refresh`, pulling down reloads it,
/// with the refresh haptic.
struct WebPage<Content: View>: View {
  private let spacing: CGFloat
  private let refresh: (@Sendable () async -> Void)?
  private let content: Content
  @Environment(\.palette) private var palette
  @Environment(ShellChrome.self) private var chrome: ShellChrome?

  /// `spacing` between the page's sections (the home's are 20pt apart).
  init(
    spacing: CGFloat = 0, refresh: (@Sendable () async -> Void)? = nil, @ViewBuilder content: () -> Content
  ) {
    self.spacing = spacing
    self.refresh = refresh
    self.content = content()
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: spacing) { content }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }
    .scrollDismissesKeyboard(.interactively)
    // Room for the bars floating over the page: the top bar above, the tab
    // bar below (the web's main: 96pt plus the safe area at the bottom).
    .contentMargins(.top, ShellMetrics.topBar, for: .scrollContent)
    .contentMargins(.top, ShellMetrics.topBar, for: .scrollIndicators)
    .contentMargins(.bottom, ShellMetrics.bottomRoom, for: .scrollContent)
    .contentMargins(.bottom, ShellMetrics.bottomRoom, for: .scrollIndicators)
    .modifier(PullToRefresh(action: refresh))
    .background(palette.page.ignoresSafeArea())
    .onScrollGeometryChange(for: Bool.self) { geometry in
      geometry.contentOffset.y + geometry.contentInsets.top > 2
    } action: { _, scrolled in
      chrome?.scrolled = scrolled
    }
    .onAppear { chrome?.scrolled = false }
    .toolbar(.hidden, for: .navigationBar)
  }
}

/// Pull to refresh, when the page can reload: the refresh haptic as it starts.
private struct PullToRefresh: ViewModifier {
  let action: (@Sendable () async -> Void)?

  func body(content: Content) -> some View {
    if let action {
      content.refreshable {
        await Haptics.refresh()
        await action()
      }
    } else {
      content
    }
  }
}

/// The web's `PageHeader`: the title (24/32, 600) and a description (14pt
/// slate-500); the actions wrap below with 8pt gaps; 16pt between, 24pt
/// below the header.
struct PageHeader<Actions: View>: View {
  let title: String
  var description: String?
  var breadcrumb: String?
  var onBreadcrumb: (() -> Void)?
  private let actions: Actions
  @Environment(\.palette) private var palette

  init(
    _ title: String, description: String? = nil, breadcrumb: String? = nil,
    onBreadcrumb: (() -> Void)? = nil, @ViewBuilder actions: () -> Actions
  ) {
    self.title = title
    self.description = description
    self.breadcrumb = breadcrumb
    self.onBreadcrumb = onBreadcrumb
    self.actions = actions()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 0) {
        if let breadcrumb {
          // A 44pt touch target around the line, without moving it.
          Button {
            Haptics.play(.tap)
            onBreadcrumb?()
          } label: {
            Text(breadcrumb)
              .font(.web(14))
              .foregroundStyle(palette.slate(500))
              .padding(.horizontal, 8)
              .padding(.vertical, 13)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(onBreadcrumb == nil)
          .padding(.horizontal, -8)
          .padding(.vertical, -13)
          .padding(.bottom, 4)
        }
        Text(title).webText(.pageTitle).lineLimit(2).minimumScaleFactor(0.85).accessibilityAddTraits(.isHeader)
        if let description {
          Text(description).font(.web(14)).foregroundStyle(palette.slate(500)).padding(.top, 4)
        }
      }
      if Actions.self != EmptyView.self {
        FlowLayout(spacing: 8, lineSpacing: 8) { actions }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, 24)
  }
}

extension PageHeader where Actions == EmptyView {
  init(_ title: String, description: String? = nil, breadcrumb: String? = nil, onBreadcrumb: (() -> Void)? = nil) {
    self.init(title, description: description, breadcrumb: breadcrumb, onBreadcrumb: onBreadcrumb) { EmptyView() }
  }
}

/// Views in rows that wrap, as CSS `flex-wrap` does.
struct FlowLayout: Layout {
  var spacing: CGFloat = 8
  var lineSpacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
    let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
    let width = rows.map(\.width).max() ?? 0
    return CGSize(width: width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for row in arrange(width: bounds.width, subviews: subviews) {
      var x = bounds.minX
      for index in row.items {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(
          at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + lineSpacing
    }
  }

  private struct Row {
    var items: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
    var rows: [Row] = []
    var row = Row()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
      if !row.items.isEmpty, needed > width {
        rows.append(row)
        row = Row()
      }
      row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
      row.height = max(row.height, size.height)
      row.items.append(index)
    }
    if !row.items.isEmpty { rows.append(row) }
    return rows
  }
}

/// The web's `EmptyState`: centred, 24×56pt padding, a 48pt primary-50
/// circle with a 24pt primary-600 icon, the title (16pt, 600) and the
/// description (14pt slate-500, at most 384pt wide), then the action.
struct WebEmptyState<Action: View>: View {
  var icon: Icon?
  let title: String
  var description: String?
  private let action: Action
  @Environment(\.palette) private var palette

  init(icon: Icon? = nil, title: String, description: String? = nil, @ViewBuilder action: () -> Action) {
    self.icon = icon
    self.title = title
    self.description = description
    self.action = action()
  }

  var body: some View {
    VStack(spacing: 0) {
      if let icon {
        IconView(icon, size: 24)
          .foregroundStyle(palette.primary(600))
          .frame(width: 48, height: 48)
          .background(palette.primary(50), in: Circle())
          .padding(.bottom, 16)
      }
      Text(title)
        .font(.web(16, .semibold))
        .foregroundStyle(palette.slate(900))
        .multilineTextAlignment(.center)
      if let description {
        Text(description)
          .font(.web(14))
          .foregroundStyle(palette.slate(500))
          .multilineTextAlignment(.center)
          .frame(maxWidth: 384)
          .padding(.top, 4)
      }
      if Action.self != EmptyView.self {
        action.padding(.top, 20)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 24)
    .padding(.vertical, 56)
  }
}

extension WebEmptyState where Action == EmptyView {
  init(icon: Icon? = nil, title: String, description: String? = nil) {
    self.init(icon: icon, title: title, description: description) { EmptyView() }
  }
}

/// No skeletons on the web: a 16pt spinning `Loader2` with 14pt slate-500 text.
struct Spinner: View {
  var label: String?
  @Environment(\.palette) private var palette

  init(_ label: String? = nil) {
    self.label = label
  }

  var body: some View {
    HStack(spacing: 8) {
      SpinningIcon(size: 16)
      if let label {
        Text(label)
      }
    }
    .font(.web(14))
    .foregroundStyle(palette.slate(500))
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(label ?? t("Loading")))
  }
}
