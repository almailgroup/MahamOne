import SwiftUI

/// Liquid Glass (iOS 26) in the web's colours. Buttons and the floating
/// bars are glass; cards, lists, inputs and text keep the web's look.
///
/// Tinted glass shows a little of what is behind it, so on light themes it
/// is tinted one step deeper (the web's own hover shade): white on-primary
/// and white-on-red text then keeps at least 4.5:1 against the glass in
/// every theme. Dark themes keep the solid colour, which the dark page
/// behind only deepens. Pressed, the tint takes the web's active shade.
enum WebGlass {
  /// A primary button's tint: primary-solid (one step deeper on light themes).
  static func primaryTint(_ palette: Palette, pressed: Bool) -> Color {
    if pressed { return palette.color(.primarySolidActive) }
    return palette.isDark ? palette.primarySolid : palette.color(.primarySolidHover)
  }

  /// A danger button's tint: red-solid (one step deeper on light themes).
  static func dangerTint(_ palette: Palette, pressed: Bool) -> Color {
    if palette.isDark {
      return pressed ? palette.color(.redSolidHover) : palette.redSolid
    }
    return pressed ? palette[.red(800)] : palette.color(.redSolidHover)
  }

  /// Drawn over clear glass while it is pressed: a light veil of slate-900
  /// (dark on light themes, light on dark ones), as the web's pressed fills.
  static func pressedVeil(_ palette: Palette) -> Color {
    palette.slate(900).opacity(0.08)
  }

  /// A control's fill when it sits on a glass bar (glass can't sit on glass).
  static func onGlassFill(_ palette: Palette, pressed: Bool) -> Color {
    palette.slate(900).opacity(pressed ? 0.12 : 0.06)
  }
}

private struct ButtonOnGlassKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// Set by a glass bar (`StickyActions`) for the buttons on it: tinted
  /// buttons stay glass and blend with the bar; the others take a fill,
  /// since glass can't sit on glass.
  var webButtonOnGlass: Bool {
    get { self[ButtonOnGlassKey.self] }
    set { self[ButtonOnGlassKey.self] = newValue }
  }
}

/// The shape of a glass button.
enum GlassButtonShape: Sendable {
  case circle
  case rounded(CGFloat)

  var shape: AnyShape {
    switch self {
    case .circle: AnyShape(Circle())
    case .rounded(let radius): AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
  }
}

/// Glass, or nothing (for a button sitting on a glass bar).
struct OptionalGlass<S: Shape>: ViewModifier {
  let glass: Glass?
  let shape: S

  func body(content: Content) -> some View {
    if let glass {
      content.glassEffect(glass, in: shape)
    } else {
      content
    }
  }
}

/// Liquid Glass behind a button's own label (icon buttons, a menu's
/// trigger, the language switch): interactive glass, optionally tinted, a
/// veil while pressed. The label sets its own size (at least 44pt).
///
///     Button { … } label: { IconView(.x, size: 20).frame(width: 44, height: 44) }
///       .buttonStyle(.webGlass(.circle))
struct WebGlassButtonStyle: ButtonStyle {
  var shape: GlassButtonShape = .rounded(WebRadius.md)
  var tint: Color?

  func makeBody(configuration: Configuration) -> some View {
    WebGlassButtonBody(configuration: configuration, shape: shape.shape, tint: tint)
  }
}

private struct WebGlassButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let shape: AnyShape
  let tint: Color?
  @Environment(\.palette) private var palette
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.webButtonOnGlass) private var onGlass

  var body: some View {
    let pressed = configuration.isPressed
    configuration.label
      .background(veil(pressed), in: shape)
      .contentShape(shape)
      .modifier(OptionalGlass(glass: onGlass ? nil : Glass.regular.tint(tint).interactive(), shape: shape))
      .opacity(isEnabled ? 1 : 0.5)
      .animation(WebMotion.standard, value: pressed)
      .onChange(of: pressed) { _, now in
        if now { Haptics.prepare() }
      }
  }

  private func veil(_ pressed: Bool) -> Color {
    if onGlass { return WebGlass.onGlassFill(palette, pressed: pressed) }
    return pressed ? WebGlass.pressedVeil(palette) : .clear
  }
}

extension ButtonStyle where Self == WebGlassButtonStyle {
  /// Liquid Glass behind the button's own label.
  static func webGlass(_ shape: GlassButtonShape = .rounded(WebRadius.md), tint: Color? = nil) -> WebGlassButtonStyle {
    WebGlassButtonStyle(shape: shape, tint: tint)
  }
}

/// A 44pt glass button with an icon (close buttons, the theme button),
/// named for VoiceOver.
struct GlassIconButton: View {
  let icon: Icon
  let label: String
  var iconSize: CGFloat = 20
  var color: Token = .slate(500)
  var shape: GlassButtonShape = .circle
  var haptic: Haptic? = .tap
  let action: () -> Void
  @Environment(\.palette) private var palette

  init(
    _ icon: Icon, label: String, iconSize: CGFloat = 20, color: Token = .slate(500),
    shape: GlassButtonShape = .circle, haptic: Haptic? = .tap, action: @escaping () -> Void
  ) {
    self.icon = icon
    self.label = label
    self.iconSize = iconSize
    self.color = color
    self.shape = shape
    self.haptic = haptic
    self.action = action
  }

  var body: some View {
    Button {
      if let haptic { Haptics.play(haptic) }
      action()
    } label: {
      IconView(icon, size: iconSize)
        .foregroundStyle(palette.color(color))
        .frame(width: 44, height: 44)
    }
    .buttonStyle(.webGlass(shape))
    .accessibilityLabel(Text(label))
  }
}
