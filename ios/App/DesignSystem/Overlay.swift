import Observation
import SwiftUI

/// Which edge of its button a panel lines up with, in the reading direction
/// (Radix's `align`).
enum PanelAlignment: Sendable {
  case start, end
}

/// The panels anchored to a button (menus, the calendar, searchable
/// selects, the app switcher), drawn above everything by an `overlayHost()`
/// at the root of the screen, as Radix portals them on the web. One at a time.
@MainActor
@Observable
final class OverlayCenter {
  struct Panel: Identifiable {
    let id: UUID
    /// The button, in window coordinates.
    let anchor: CGRect
    let alignment: PanelAlignment
    let direction: LayoutDirection
    let width: CGFloat?
    let content: AnyView
    let onDismiss: () -> Void
  }

  private(set) var panel: Panel? = nil

  func present(_ panel: Panel) {
    if let current = self.panel, current.id != panel.id { current.onDismiss() }
    withAnimation(WebMotion.fade) { self.panel = panel }
  }

  /// Closes the panel (its owner's binding goes back to false).
  func dismiss() {
    guard let current = panel else { return }
    withAnimation(WebMotion.fade) { panel = nil }
    current.onDismiss()
  }

  /// Closes this owner's panel, if it is the one open.
  func dismiss(id: UUID) {
    guard panel?.id == id else { return }
    withAnimation(WebMotion.fade) { panel = nil }
  }
}

private struct OverlayCenterKey: EnvironmentKey {
  static let defaultValue: OverlayCenter? = nil
}

/// Closes the anchored panel a view is in: `@Environment(\.dismissPanel)`,
/// then `dismissPanel()`. Menu items call it once chosen.
struct PanelDismiss {
  let action: () -> Void

  @MainActor
  func callAsFunction() { action() }
}

private struct PanelDismissKey: EnvironmentKey {
  static var defaultValue: PanelDismiss { PanelDismiss(action: {}) }
}

extension EnvironmentValues {
  /// The nearest `overlayHost()`, if any.
  var overlayCenter: OverlayCenter? {
    get { self[OverlayCenterKey.self] }
    set { self[OverlayCenterKey.self] = newValue }
  }

  /// Closes the anchored panel this view is in (does nothing outside one).
  var dismissPanel: PanelDismiss {
    get { self[PanelDismissKey.self] }
    set { self[PanelDismissKey.self] = newValue }
  }
}

/// Draws the open panel over the screen; a tap outside closes it.
private struct OverlayLayer: View {
  let center: OverlayCenter
  @State private var size: CGSize = .zero

  /// Room kept between a panel and the screen's edges (Radix's collision padding).
  private let margin: CGFloat = 12
  /// The gap between the button and its panel (Radix's side offset).
  private let gap: CGFloat = 6

  var body: some View {
    GeometryReader { proxy in
      if let panel = center.panel {
        let screen = proxy.frame(in: .global)
        let origin = position(of: panel, in: screen)
        ZStack(alignment: .topLeading) {
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture { center.dismiss() }
            .accessibilityLabel(Text(t("Close")))
            .accessibilityAddTraits(.isButton)
          panel.content
            .environment(\.layoutDirection, panel.direction)
            .frame(width: panel.width)
            .fixedSize(horizontal: panel.width == nil, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .offset(x: origin.x, y: origin.y)
            .opacity(size == .zero ? 0 : 1)
            .id(panel.id)
        }
        .frame(width: screen.width, height: screen.height, alignment: .topLeading)
        .environment(\.layoutDirection, .leftToRight)
        .transition(.opacity)
      }
    }
    .ignoresSafeArea()
    .onChange(of: center.panel?.id) { _, _ in size = .zero }
  }

  /// Below the button when it fits, else above; lined up with its start or
  /// end edge; kept on screen.
  private func position(of panel: OverlayCenter.Panel, in screen: CGRect) -> CGPoint {
    let anchor = panel.anchor.offsetBy(dx: -screen.minX, dy: -screen.minY)
    let width = panel.width ?? size.width
    let height = size.height
    let alignRight = (panel.alignment == .end) == (panel.direction == .leftToRight)
    var x = alignRight ? anchor.maxX - width : anchor.minX
    x = min(max(margin, x), max(margin, screen.width - width - margin))
    let below = anchor.maxY + gap
    let above = anchor.minY - gap - height
    var y = below
    if below + height > screen.height - margin, above >= margin { y = above }
    y = max(margin, min(y, screen.height - height - margin))
    return CGPoint(x: x, y: y)
  }
}

private struct OverlayHostModifier: ViewModifier {
  @State private var center = OverlayCenter()

  func body(content: Content) -> some View {
    content
      .environment(\.overlayCenter, center)
      .overlay { OverlayLayer(center: center) }
  }
}

/// Anchors a panel to this view while `isPresented` is true.
private struct AnchoredPanelModifier<Panel: View>: ViewModifier {
  @Binding var isPresented: Bool
  let alignment: PanelAlignment
  let width: CGFloat?
  let panel: () -> Panel

  @Environment(\.overlayCenter) private var center
  @Environment(\.layoutDirection) private var direction
  @State private var frame: CGRect = .zero
  @State private var id = UUID()

  func body(content: Content) -> some View {
    content
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
      .onChange(of: isPresented) { _, open in
        guard let center else { return }
        if open {
          let binding = $isPresented
          let close = PanelDismiss { binding.wrappedValue = false }
          center.present(
            OverlayCenter.Panel(
              id: id, anchor: frame, alignment: alignment, direction: direction, width: width,
              content: AnyView(panel().environment(\.dismissPanel, close)),
              onDismiss: { binding.wrappedValue = false }))
        } else {
          center.dismiss(id: id)
        }
      }
      .onDisappear {
        if isPresented { center?.dismiss(id: id) }
      }
      .popover(isPresented: center == nil ? $isPresented : .constant(false)) {
        let binding = $isPresented
        panel()
          .environment(\.dismissPanel, PanelDismiss { binding.wrappedValue = false })
          .presentationCompactAdaptation(.popover)
      }
  }
}

extension View {
  /// Puts the anchored panels of the views inside over them. At the root of
  /// the shell, and in every dialog (which covers the shell's).
  func overlayHost() -> some View {
    modifier(OverlayHostModifier())
  }

  /// A panel anchored to this view, as the web's Radix popovers and menus:
  /// below it (above when there is no room), lined up with its `alignment`
  /// edge, `width` wide or as wide as it needs. A tap outside closes it.
  func anchoredPanel<Panel: View>(
    isPresented: Binding<Bool>, alignment: PanelAlignment = .end, width: CGFloat? = nil,
    @ViewBuilder panel: @escaping () -> Panel
  ) -> some View {
    modifier(AnchoredPanelModifier(isPresented: isPresented, alignment: alignment, width: width, panel: panel))
  }
}
