import MahamKit
import SwiftUI

// Saving natively in the suite's pages: one user action through the ports
// of the web's writes (MahamKit/Write/Suite), refused with the web's words
// in the reader's language; who may change what; and the bindings the
// forms edit a record's fields with.

@MainActor
enum SwSave {
  /// Saves one action (`model.one.write`); a refusal shows as the app's
  /// toast, in the reader's language. `done` confirms it.
  @discardableResult
  static func run(_ model: AppModel, done: String? = nil, _ body: (WriteContext) throws -> Void) async -> Bool {
    do {
      try await model.one.write(body)
      if let done { model.confirm(done) }
      return true
    } catch {
      model.toast = Toast(kind: .error, message: message(error))
      return false
    }
  }

  /// What went wrong, in the reader's language: the web's words of the
  /// port's or the sync rules' refusal.
  static func message(_ error: Error) -> String {
    if let failure = error as? WriteFailure { return t(failure.message, failure.vars) }
    if let refused = error as? SyncWriteError {
      switch refused {
      case .refused(let text), .invalid(let text): return t(text)
      case .notWritable: return t("Something went wrong. Try again in a moment.")
      }
    }
    if let failure = error as? MahamError { return t(failure.message) }
    return t("Something went wrong. Try again in a moment.")
  }

  /// The words the web stores in the interface language (`t` inside a write).
  static var words: I18n.Translator { Localization.translator }
}

/// Who may change what in the suite's pages, as the web lets them: viewers
/// only look; the rest change records (the sync rules refuse what their
/// role can't, with the web's words).
@MainActor
struct SwAccess {
  let role: MemberRole?

  init(_ model: AppModel) {
    role = model.business.company?.role
  }

  /// Changes the register, vehicles and the company's settings.
  var edits: Bool { role != nil && role != .viewer }
  /// Chooses the design of documents (Templates): owners, admins and accountants.
  var designs: Bool { role == .owner || role == .admin || role == .accountant }
  /// Switches the AI assistant and the app layout: the owner and admins.
  var switchesApps: Bool { role == .owner || role == .admin }

  /// Whether a kind of record can be saved from this iPhone yet (`OneWritable`).
  static func can(_ kinds: RecordKind...) -> Bool {
    kinds.allSatisfy { OneData.canWrite($0) }
  }
}

// MARK: Editing a record's fields

/// Bindings into a record kept as JSON while a form edits it.
@MainActor
enum SwBind {
  /// A text field at `path` ("" when missing).
  static func text(_ record: Binding<JSONValue>, _ path: [String]) -> Binding<String> {
    Binding(
      get: { get(record.wrappedValue, path)?.string ?? "" },
      set: { record.wrappedValue = set(record.wrappedValue, path, .string($0)) })
  }

  /// A yes/no field at `path` (false when missing).
  static func flag(_ record: Binding<JSONValue>, _ path: [String]) -> Binding<Bool> {
    Binding(
      get: { get(record.wrappedValue, path)?.bool ?? false },
      set: { record.wrappedValue = set(record.wrappedValue, path, .bool($0)) })
  }

  /// A text field that is null when empty (`value || null`), for choices and dates.
  static func optional(_ record: Binding<JSONValue>, _ path: [String]) -> Binding<String> {
    Binding(
      get: { get(record.wrappedValue, path)?.string ?? "" },
      set: { record.wrappedValue = set(record.wrappedValue, path, $0.isEmpty ? .null : .string($0)) })
  }

  /// A choice of a `Combobox`: nil and "" are null.
  static func choice(_ record: Binding<JSONValue>, _ path: [String]) -> Binding<String?> {
    Binding(
      get: { get(record.wrappedValue, path)?.string },
      set: { value in
        let stored: JSONValue = (value ?? "").isEmpty ? .null : .string(value ?? "")
        record.wrappedValue = set(record.wrappedValue, path, stored)
      })
  }

  static func get(_ value: JSONValue?, _ path: [String]) -> JSONValue? {
    var at = value
    for key in path { at = at?[key] }
    return at
  }

  /// The record with `value` at `path`; the objects on the way are made when missing.
  static func set(_ value: JSONValue, _ path: [String], _ new: JSONValue) -> JSONValue {
    guard let head = path.first else { return new }
    var fields = value.object ?? [:]
    let child = fields[head] ?? .object([:])
    fields[head] = path.count == 1 ? new : set(child, Array(path.dropFirst()), new)
    return .object(fields)
  }
}

/// A number typed in a text field, as the web's `NumberInput` reads it
/// (Arabic digits and separators too); `blankZero` shows 0 as empty.
struct SwNumberField: View {
  @Binding var value: Double
  var blankZero = true
  var placeholder = ""
  @State private var text = ""
  @State private var shown: Double?

  var body: some View {
    TextInput(text: $text, placeholder: placeholder, keyboard: .decimalPad)
      .onAppear { sync() }
      .onChange(of: value) { _, _ in
        if shown != value { sync() }
      }
      .onChange(of: text) { _, typed in
        let parsed = Money.parseAmount(typed)
        let number = parsed.isFinite ? parsed : 0
        shown = number
        if number != value { value = number }
      }
      .environment(\.layoutDirection, .leftToRight)
  }

  private func sync() {
    shown = value
    text = blankZero && value == 0 ? "" : Money.jsString(value)
  }
}

/// A form's error line (red-600, 14pt), as the web's `FormError`.
struct SwFormError: View {
  let text: String?
  @Environment(\.palette) private var palette

  var body: some View {
    if let text, !text.isEmpty {
      Text(text)
        .font(.web(14))
        .foregroundStyle(palette[.red(600)])
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isStaticText)
    }
  }
}

/// A multi-line text field in the input's look (`Textarea`).
struct SwTextArea: View {
  @Binding var text: String
  var lines = 3
  @FocusState private var focused: Bool

  var body: some View {
    TextField("", text: $text, axis: .vertical)
      .lineLimit(lines...max(lines, 12))
      .focused($focused)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .modifier(InputChrome(focused: focused))
  }
}

/// A confirmation dialog's footer: Cancel and the action (red when it deletes).
struct SwConfirmFooter: View {
  let label: String
  var danger = false
  let onCancel: () -> Void
  let onConfirm: () -> Void

  var body: some View {
    WebButton(t("Cancel"), variant: .outline) { onCancel() }
    WebButton(label, variant: danger ? .danger : .primary) { onConfirm() }
  }
}
