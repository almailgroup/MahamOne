import SwiftUI
import UIKit

private struct FieldInvalidKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// Set by a `Field` with an error: its control draws the red border.
  var fieldInvalid: Bool {
    get { self[FieldInvalidKey.self] }
    set { self[FieldInvalidKey.self] = newValue }
  }
}

/// Label, control, then hint or error (`src/components/ui/form.tsx`): the
/// label 14pt weight 500 slate-700, 6pt above; the hint 12pt slate-500, the
/// error 12pt red-600.
struct Field<Content: View>: View {
  let label: String?
  var hint: String?
  var error: String?
  var optional: Bool
  private let content: Content
  @Environment(\.palette) private var palette

  init(
    _ label: String?, hint: String? = nil, error: String? = nil, optional: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.label = label
    self.hint = hint
    self.error = error
    self.optional = optional
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let label {
        HStack(spacing: 4) {
          Text(label).font(.web(14, .medium)).foregroundStyle(palette.slate(700))
          if optional {
            Text(verbatim: "(\(t("optional")))").font(.web(14)).foregroundStyle(palette.slate(500))
          }
        }
      }
      content.environment(\.fieldInvalid, error != nil)
      if let error {
        Text(error).font(.web(12)).foregroundStyle(palette[.red(600)])
      } else if let hint {
        Text(hint).font(.web(12)).foregroundStyle(palette.slate(500))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// The look of an input: 8pt radius, a slate-300 border on surface, 12pt
/// side padding, shadow-xs, 44pt tall with 16pt text on a phone. Focused: a
/// primary-500 border and a 3pt ring at 15%; invalid: red-400; disabled:
/// slate-50 with slate-500 text.
struct InputChrome: ViewModifier {
  var focused: Bool
  var rounded = false
  @Environment(\.palette) private var palette
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.fieldInvalid) private var invalid

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: rounded ? 22 : WebRadius.md, style: .continuous)
    content
      .font(.web(16))
      .foregroundStyle(isEnabled ? palette.slate(900) : palette.slate(500))
      .frame(minHeight: 44)
      .background(isEnabled ? palette.surface : palette.slate(50), in: shape)
      .border(borderColor, in: shape)
      .background {
        if focused {
          shape.inset(by: -3).fill((invalid ? palette[.red(500)] : palette.primary(500)).opacity(0.15))
        }
      }
      .boxShadow(WebShadow.xs, in: shape)
      .animation(WebMotion.standard, value: focused)
  }

  private var borderColor: Color {
    if invalid { return palette[.red(400)] }
    return focused ? palette.primary(500) : palette.slate(300)
  }
}

/// A text input in the web's look. `leadingIcon` sits inside at the start
/// (the search boxes); `rounded` makes it a pill (the home's find box).
struct TextInput: View {
  @Binding var text: String
  var placeholder: String
  var leadingIcon: Icon?
  var rounded: Bool
  var secure: Bool
  var keyboard: UIKeyboardType
  var contentType: UITextContentType?
  var submitLabel: SubmitLabel
  var onSubmit: (() -> Void)?
  @FocusState private var focused: Bool
  @Environment(\.palette) private var palette

  init(
    text: Binding<String>, placeholder: String = "", leadingIcon: Icon? = nil, rounded: Bool = false,
    secure: Bool = false, keyboard: UIKeyboardType = .default, contentType: UITextContentType? = nil,
    submitLabel: SubmitLabel = .done, onSubmit: (() -> Void)? = nil
  ) {
    _text = text
    self.placeholder = placeholder
    self.leadingIcon = leadingIcon
    self.rounded = rounded
    self.secure = secure
    self.keyboard = keyboard
    self.contentType = contentType
    self.submitLabel = submitLabel
    self.onSubmit = onSubmit
  }

  var body: some View {
    HStack(spacing: 8) {
      if let leadingIcon {
        IconView(leadingIcon, size: 16).foregroundStyle(palette.slate(400))
      }
      ZStack(alignment: .leading) {
        if text.isEmpty {
          Text(placeholder)
            .foregroundStyle(palette.slate(400))
            .lineLimit(1)
            .allowsHitTesting(false)
        }
        field
          .focused($focused)
          .keyboardType(keyboard)
          .textContentType(contentType)
          .submitLabel(submitLabel)
          .onSubmit { onSubmit?() }
      }
    }
    .padding(.horizontal, 12)
    .modifier(InputChrome(focused: focused, rounded: rounded))
    .contentShape(Rectangle())
    .onTapGesture { focused = true }
  }

  @ViewBuilder
  private var field: some View {
    if secure {
      SecureField("", text: $text)
    } else {
      TextField("", text: $text)
    }
  }
}

/// One choice of a `Select`.
struct SelectOption<Value: Hashable>: Identifiable {
  let value: Value
  let label: String
  var id: Value { value }

  init(_ value: Value, _ label: String) {
    self.value = value
    self.label = label
  }
}

/// The web's native select: the field look with a `ChevronDown` at the end;
/// it opens the iPhone's own list, as Safari's select does.
struct Select<Value: Hashable>: View {
  @Binding var selection: Value
  let options: [SelectOption<Value>]
  var placeholder: String
  @Environment(\.palette) private var palette

  init(selection: Binding<Value>, options: [SelectOption<Value>], placeholder: String = "") {
    _selection = selection
    self.options = options
    self.placeholder = placeholder
  }

  var body: some View {
    Menu {
      Picker(selection: $selection) {
        ForEach(options) { option in
          Text(option.label).tag(option.value)
        }
      } label: {
        Text(placeholder)
      }
      .pickerStyle(.inline)
    } label: {
      HStack(spacing: 8) {
        Text(current ?? placeholder)
          .foregroundStyle(current == nil ? palette.slate(400) : palette.slate(900))
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        IconView(.chevronDown, size: 16).foregroundStyle(palette.slate(400))
      }
      .padding(.leading, 12)
      .padding(.trailing, 12)
      .modifier(InputChrome(focused: false))
      .contentShape(Rectangle())
    }
    .menuIndicator(.hidden)
    .menuStyle(.button)
    .buttonStyle(.plain)
  }

  private var current: String? {
    options.first { $0.value == selection }?.label
  }
}

/// The web's `Switch`: a 24×44pt track (primary-solid on, slate-300 off)
/// with a 20pt white knob, after its label and description.
struct Switch: View {
  @Binding var isOn: Bool
  let label: String
  var description: String?
  @Environment(\.palette) private var palette
  @Environment(\.isEnabled) private var isEnabled

  init(_ label: String, description: String? = nil, isOn: Binding<Bool>) {
    self.label = label
    self.description = description
    _isOn = isOn
  }

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text(label).font(.web(14, .medium)).foregroundStyle(palette.slate(800))
        if let description {
          Text(description).font(.web(14)).foregroundStyle(palette.slate(500))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      SwitchTrack(isOn: isOn)
        .opacity(isEnabled ? 1 : 0.5)
    }
    .contentShape(Rectangle())
    .onTapGesture {
      guard isEnabled else { return }
      withAnimation(WebMotion.standard) { isOn.toggle() }
    }
    .accessibilityRepresentation {
      Toggle(isOn: $isOn) { Text(label) }
    }
  }
}

/// The switch's track and knob alone.
struct SwitchTrack: View {
  let isOn: Bool
  @Environment(\.palette) private var palette

  var body: some View {
    Capsule()
      .fill(isOn ? palette.primarySolid : palette.slate(300))
      .frame(width: 44, height: 24)
      .overlay(alignment: isOn ? .trailing : .leading) {
        Circle()
          .fill(Color.white)
          .frame(width: 20, height: 20)
          .boxShadow(WebShadow.sm, in: Circle())
          .padding(2)
      }
  }
}
