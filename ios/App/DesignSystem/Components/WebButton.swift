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

/// The web's button look for any `Button`: `.buttonStyle(.web(.outline, .sm))`.
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

  var body: some View {
    let pressed = configuration.isPressed
    let shape = RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous)
    configuration.label
      .font(.web(size.textSize, .medium))
      .lineLimit(1)
      .foregroundStyle(foreground(pressed))
      .padding(.horizontal, size.padding)
      .frame(
        minWidth: size.isIcon ? CGFloat(44) : nil, maxWidth: fullWidth ? CGFloat.infinity : nil,
        minHeight: 44)
      .background(background(pressed), in: shape)
      .border(variant == .outline ? palette.slate(300) : .clear, in: shape)
      .boxShadow(shadow, in: shape)
      .contentShape(shape)
      .opacity(isEnabled ? 1 : 0.5)
      .animation(WebMotion.standard, value: pressed)
  }

  private var shadow: [BoxShadow] {
    switch variant {
    case .primary, .secondary, .danger: WebShadow.sm
    case .outline: WebShadow.xs
    case .ghost, .subtle: []
    }
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

  private func background(_ pressed: Bool) -> Color {
    switch variant {
    case .primary: pressed ? palette.color(.primarySolidActive) : palette.primarySolid
    case .secondary: pressed ? palette.slate(800) : palette.slate(900)
    case .outline: pressed ? palette.slate(50) : palette.surface
    case .ghost: pressed ? palette.slate(100) : .clear
    case .danger: pressed ? palette.color(.redSolidHover) : palette.redSolid
    case .subtle: pressed ? palette.primary(100) : palette.primary(50)
    }
  }
}

extension ButtonStyle where Self == WebButtonStyle {
  static func web(_ variant: ButtonVariant = .primary, _ size: ButtonSize = .md) -> WebButtonStyle {
    WebButtonStyle(variant: variant, size: size)
  }
}

/// The web's `Button`: a label with an optional 16pt icon before it, or a
/// spinning `Loader2` while `loading` (which also turns it off).
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
  private let action: () -> Void

  init(
    _ title: String, icon: Icon? = nil, variant: ButtonVariant = .primary, size: ButtonSize = .md,
    loading: Bool = false, role: ButtonRole? = nil, action: @escaping () -> Void
  ) {
    self.title = title
    self.icon = icon
    self.accessibility = title
    self.variant = variant
    self.size = size
    self.loading = loading
    self.role = role
    self.action = action
  }

  /// An icon-only button, named for VoiceOver.
  init(
    icon: Icon, label: String, variant: ButtonVariant = .ghost, size: ButtonSize = .icon,
    loading: Bool = false, action: @escaping () -> Void
  ) {
    self.title = nil
    self.icon = icon
    self.accessibility = label
    self.variant = variant
    self.size = size
    self.loading = loading
    self.role = nil
    self.action = action
  }

  var body: some View {
    Button(role: role, action: action) {
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
