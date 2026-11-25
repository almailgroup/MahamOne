import SwiftUI

/// The web's corner radii (Tailwind `rounded-*`).
enum WebRadius {
  /// rounded-md
  static let sm: CGFloat = 6
  /// rounded-lg: buttons, inputs.
  static let md: CGFloat = 8
  /// rounded-xl: cards, dialogs.
  static let lg: CGFloat = 12
  /// rounded-2xl: tab bar, panels, tiles.
  static let xl: CGFloat = 16
  /// rounded-3xl: drawer, sheet.
  static let xxl: CGFloat = 24
}

/// One CSS `box-shadow` layer: offset, blur, spread and colour, as on the web.
struct BoxShadow: Sendable {
  var color: Color
  var x: CGFloat = 0
  var y: CGFloat
  var blur: CGFloat
  var spread: CGFloat = 0
}

/// Tailwind's shadows and the shell's own, layer for layer.
enum WebShadow {
  static let xs = [BoxShadow(color: .black.opacity(0.05), y: 1, blur: 2)]
  static let sm = [
    BoxShadow(color: .black.opacity(0.1), y: 1, blur: 3),
    BoxShadow(color: .black.opacity(0.1), y: 1, blur: 2, spread: -1),
  ]
  static let md = [
    BoxShadow(color: .black.opacity(0.1), y: 4, blur: 6, spread: -1),
    BoxShadow(color: .black.opacity(0.1), y: 2, blur: 4, spread: -2),
  ]
  static let lg = [
    BoxShadow(color: .black.opacity(0.1), y: 10, blur: 15, spread: -3),
    BoxShadow(color: .black.opacity(0.1), y: 4, blur: 6, spread: -4),
  ]
  static let xl = [
    BoxShadow(color: .black.opacity(0.1), y: 20, blur: 25, spread: -5),
    BoxShadow(color: .black.opacity(0.1), y: 8, blur: 10, spread: -6),
  ]
  static let xxl = [BoxShadow(color: .black.opacity(0.25), y: 25, blur: 50, spread: -12)]

  /// rgb(15 23 42): Tailwind's slate-900, which the shell's shadows are tinted with.
  private static let ink = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255)

  /// The top bar once the page has scrolled.
  static let topBar = [BoxShadow(color: ink.opacity(0.35), y: 10, blur: 24, spread: -18)]
  /// The floating tab bar and an editor's action bar.
  static let floatingBar = [BoxShadow(color: ink.opacity(0.3), y: 10, blur: 30, spread: -8)]

  /// `shadow-lg shadow-<colour>/30`: the layers of shadow-lg in one colour.
  static func lg(tinted color: Color) -> [BoxShadow] {
    lg.map { BoxShadow(color: color, x: $0.x, y: $0.y, blur: $0.blur, spread: $0.spread) }
  }
}

/// The web's motion: `cubic-bezier(.16,1,.3,1)` unless noted.
enum WebMotion {
  /// Fade, 150ms ease-out.
  static var fade: Animation { .easeOut(duration: 0.15) }
  /// Pop-in (dialogs), 160ms.
  static var popIn: Animation { .timingCurve(0.16, 1, 0.3, 1, duration: 0.16) }
  /// The drawer, 200ms.
  static var drawer: Animation { .timingCurve(0.16, 1, 0.3, 1, duration: 0.2) }
  /// The Create sheet, 220ms.
  static var sheet: Animation { .timingCurve(0.16, 1, 0.3, 1, duration: 0.22) }
  /// Other transitions (colours, the switch), 150ms `cubic-bezier(.4,0,.2,1)`.
  static var standard: Animation { .timingCurve(0.4, 0, 0.2, 1, duration: 0.15) }
}

/// The layers of a CSS box-shadow: drawn outside the shape only, as CSS
/// does, so a see-through bar doesn't darken under itself.
private struct BoxShadowLayers<S: InsettableShape>: View {
  let shadows: [BoxShadow]
  let shape: S

  var body: some View {
    ZStack {
      ForEach(shadows.indices, id: \.self) { index in
        let layer = shadows[index]
        shape
          .inset(by: max(0, -layer.spread))
          .fill(Color.black)
          .shadow(color: layer.color, radius: layer.blur / 2, x: layer.x, y: layer.y)
      }
      shape.fill(Color.black).blendMode(.destinationOut)
    }
    .compositingGroup()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// A rectangle with each corner's radius on its physical side. Shapes are
/// not mirrored in Arabic, so `start`/`end` corners are worked out with the
/// layout direction (see `.startEndCorners`).
struct CornerShape: InsettableShape {
  var topLeft: CGFloat = 0
  var topRight: CGFloat = 0
  var bottomRight: CGFloat = 0
  var bottomLeft: CGFloat = 0
  var insetAmount: CGFloat = 0

  nonisolated func path(in rect: CGRect) -> Path {
    let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
    let limit = max(0, min(r.width, r.height) / 2)
    let tl = min(max(0, topLeft - insetAmount), limit)
    let tr = min(max(0, topRight - insetAmount), limit)
    let br = min(max(0, bottomRight - insetAmount), limit)
    let bl = min(max(0, bottomLeft - insetAmount), limit)
    var path = Path()
    path.move(to: CGPoint(x: r.minX + tl, y: r.minY))
    path.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
    path.addArc(
      tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + tr), radius: tr)
    path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
    path.addArc(
      tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - br, y: r.maxY), radius: br)
    path.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
    path.addArc(
      tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - bl), radius: bl)
    path.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
    path.addArc(
      tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + tl, y: r.minY), radius: tl)
    path.closeSubpath()
    return path
  }

  nonisolated func inset(by amount: CGFloat) -> CornerShape {
    var copy = self
    copy.insetAmount += amount
    return copy
  }

  /// Corners on the start and end sides, in the reading direction.
  static func sides(
    topStart: CGFloat = 0, topEnd: CGFloat = 0, bottomEnd: CGFloat = 0, bottomStart: CGFloat = 0,
    direction: LayoutDirection
  ) -> CornerShape {
    direction == .rightToLeft
      ? CornerShape(topLeft: topEnd, topRight: topStart, bottomRight: bottomStart, bottomLeft: bottomEnd)
      : CornerShape(topLeft: topStart, topRight: topEnd, bottomRight: bottomEnd, bottomLeft: bottomStart)
  }
}

extension View {
  /// A CSS box-shadow under a view of this shape.
  func boxShadow<S: InsettableShape>(_ shadows: [BoxShadow], in shape: S) -> some View {
    background { BoxShadowLayers(shadows: shadows, shape: shape) }
  }

  /// Tailwind's `ring-1`: a hairline drawn just outside the shape.
  func ring<S: InsettableShape>(_ color: Color, width: CGFloat = 1, in shape: S) -> some View {
    overlay {
      shape.inset(by: -width).strokeBorder(color, lineWidth: width).allowsHitTesting(false)
    }
  }

  /// Tailwind's `ring-1 ring-inset` and `border`: a hairline just inside the shape.
  func border<S: InsettableShape>(_ color: Color, width: CGFloat = 1, in shape: S) -> some View {
    overlay {
      shape.strokeBorder(color, lineWidth: width).allowsHitTesting(false)
    }
  }
}

/// Runs a change without animating it: a page replaced from the tab bar, a
/// cover put up for a centred dialog that animates itself.
@MainActor
func withoutAnimation(_ change: () -> Void) {
  var transaction = Transaction()
  transaction.disablesAnimations = true
  withTransaction(transaction, change)
}
