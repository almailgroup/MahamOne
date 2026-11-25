import SwiftUI

/// `src/components/ui/button.tsx`'s variants.
enum ButtonVariant: Sendable {
  /// primary-solid, on-primary text, shadow-sm.
  case primary
  /// slate-900 fill, surface text.
  case secondary
  /// slate-300 border on surface, slate-700, shadow-xs.
  case outline
  /// slate-600 text, slate-100 when pressed.
  case ghost
  /// red-solid, white text.
  case danger
  /// primary-50 fill, primary-700 text.
  case subtle
}

/// The web's sizes. On a phone every button is at least 44pt tall (and icon
/// buttons 44pt wide); the size sets the text and the side padding.
enum ButtonSize: Sendable {
  case xs, sm, md, lg
  /// A square icon button (`size="icon"`).
  case icon
  /// The smaller square (`size="icon-sm"`); 44pt on a phone too.
  case iconSmall

  var textSize: CGFloat {
    switch self {
    case .xs: 12
    case .lg: 16
    default: 14
    }
  }

  var padding: CGFloat {
    switch self {
    case .xs: 8
    case .sm: 12
    case .md: 16
    case .lg: 20
    case .icon, .iconSmall: 0
    }
  }

  var isIcon: Bool { self == .icon || self == .iconSmall }
}

private struct ButtonFullWidthKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// Buttons stretch to the width they are given (a dialog's footer).
  var webButtonFullWidth: Bool {
    get { self[ButtonFullWidthKey.self] }
    set { self[ButtonFullWidthKey.self] = newValue }
  }
}

/// The web's button for any `Button`, in Liquid Glass:
/// `.buttonStyle(.web(.outline, .sm))`. The sizes (at least 44pt on a
/// phone), the 8pt radius and the labels are the web's; the colours keep
/// their meaning: primary is glass tinted primary-solid with on-primary
/// text, danger red-solid with white, secondary slate-900 with surface;
/// outline, ghost and subtle are clear glass with the web's text colours
/// (subtle tinted primary-50). Pressed, the tint takes the web's active
/// shade and clear glass a light veil, and the glass itself responds.
/// On a glass bar (`StickyActions`) the clear ones take a fill instead,
/// since glass can't sit on glass.
struct WebButtonStyle: ButtonStyle {
  var variant: ButtonVariant = .primary
  var size: ButtonSize = .md

  func makeBody(configuration: Configuration) -> some View {
    WebButtonBody(configuration: configuration, variant: variant, size: size)
  }
}

private struct WebButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let variant: ButtonVariant
  let size: ButtonSize
  @Environment(\.palette) private var palette
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.webButtonFullWidth) private var fullWidth
  @Environment(\.webButtonOnGlass) private var onGlass

  var body: some View {
    let pressed = configuration.isPressed
    let shape = RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous)
    configuration.label
      .font(.web(size.textSize, .medium))
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .foregroundStyle(foreground(pressed))
      .padding(.horizontal, size.padding)
      .frame(
        minWidth: size.isIcon ? CGFloat(44) : nil, maxWidth: fullWidth ? CGFloat.infinity : nil,
        minHeight: 44)
      .background(veil(pressed), in: shape)
      .contentShape(shape)
      .modifier(OptionalGlass(glass: glass(pressed), shape: shape))
      .opacity(isEnabled ? 1 : 0.5)
      .animation(WebMotion.standard, value: pressed)
      .onChange(of: pressed) { _, now in
        if now { Haptics.prepare(variant.haptic) }
      }
  }

  private var isTinted: Bool {
    switch variant {
    case .primary, .secondary, .danger, .subtle: true
    case .outline, .ghost: false
    }
  }

  /// The glass, or none for a clear button on a glass bar.
  private func glass(_ pressed: Bool) -> Glass? {
    switch variant {
    case .primary:
      return Glass.regular.tint(WebGlass.primaryTint(palette, pressed: pressed)).interactive()
    case .danger:
      return Glass.regular.tint(WebGlass.dangerTint(palette, pressed: pressed)).interactive()
    case .secondary:
      return Glass.regular.tint(pressed ? palette.slate(800) : palette.slate(900)).interactive()
    case .subtle:
      return Glass.regular.tint(pressed ? palette.primary(100) : palette.primary(50)).interactive()
    case .outline, .ghost:
      return onGlass ? nil : Glass.regular.interactive()
    }
  }

  /// Drawn over the glass, under the label: the pressed veil of clear
  /// glass, or the fill of a clear button on a glass bar.
  private func veil(_ pressed: Bool) -> Color {
    if isTinted { return .clear }
    if onGlass { return WebGlass.onGlassFill(palette, pressed: pressed) }
    return pressed ? WebGlass.pressedVeil(palette) : .clear
  }

  private func foreground(_ pressed: Bool) -> Color {
    switch variant {
    case .primary: palette.onPrimary
    case .secondary: palette.surface
    case .outline: pressed ? palette.slate(900) : palette.slate(700)
    case .ghost: pressed ? palette.slate(900) : palette.slate(600)
    case .danger: .white
    case .subtle: palette.primary(700)
    }
  }
}

extension ButtonVariant {
  /// The haptic a button of this kind plays: a firmer tap for the main
  /// actions, the warning for a destructive one, a light tap for the rest.
  var haptic: Haptic {
    switch self {
    case .primary, .secondary: .press
    case .danger: .warning
    case .outline, .ghost, .subtle: .tap
    }
  }
}

extension ButtonStyle where Self == WebButtonStyle {
  static func web(_ variant: ButtonVariant = .primary, _ size: ButtonSize = .md) -> WebButtonStyle {
    WebButtonStyle(variant: variant, size: size)
  }
}

/// The web's `Button`: a label with an optional 16pt icon before it, or a
/// spinning `Loader2` while `loading` (which also turns it off). A tap
/// plays its variant's haptic (`haptic` to choose another).
///
///     WebButton(t("Save"), loading: saving) { save() }
///     WebButton(t("New invoice"), icon: .plus, variant: .outline, size: .sm) { … }
///     WebButton(icon: .search, label: t("Search"), variant: .ghost) { … }
struct WebButton: View {
  private let title: String?
  private let icon: Icon?
  private let accessibility: String
  private let variant: ButtonVariant
  private let size: ButtonSize
  private let loading: Bool
  private let role: ButtonRole?
  private let haptic: Haptic
  private let action: () -> Void

  init(
    _ title: String, icon: Icon? = nil, variant: ButtonVariant = .primary, size: ButtonSize = .md,
    loading: Bool = false, role: ButtonRole? = nil, haptic: Haptic? = nil, action: @escaping () -> Void
  ) {
    self.title = title
    self.icon = icon
    self.accessibility = title
    self.variant = variant
    self.size = size
    self.loading = loading
    self.role = role
    self.haptic = haptic ?? variant.haptic
    self.action = action
  }

  /// An icon-only button, named for VoiceOver.
  init(
    icon: Icon, label: String, variant: ButtonVariant = .ghost, size: ButtonSize = .icon,
    loading: Bool = false, haptic: Haptic? = nil, action: @escaping () -> Void
  ) {
    self.title = nil
    self.icon = icon
    self.accessibility = label
    self.variant = variant
    self.size = size
    self.loading = loading
    self.role = nil
    self.haptic = haptic ?? variant.haptic
    self.action = action
  }

  var body: some View {
    Button(role: role) {
      Haptics.play(haptic)
      action()
    } label: {
      HStack(spacing: 8) {
        if loading {
          SpinningIcon(size: 16)
        } else if let icon {
          IconView(icon, size: 16)
        }
        if let title {
          Text(title)
        }
      }
    }
    .buttonStyle(WebButtonStyle(variant: variant, size: size))
    .disabled(loading)
    .accessibilityLabel(Text(accessibility))
  }
}
