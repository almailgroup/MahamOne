import MahamKit
import SwiftUI

// Saving the inventory natively (MahamKit/Write/Inventory): the routes of
// the forms, who may save what, one action through the ports of the web's
// writes with its refusal in the reader's language, and the small inputs
// the forms share.

/// The inventory's forms, by route: New item, Adjust stock (also a
/// transfer or opening stock), Issue items and Allocate landed costs.
@MainActor
enum InventoryWriteArea {
  static func page(for route: Route) -> AnyView? {
    switch route {
    case .newProduct: AnyView(IwItemFormPage())
    case .newStockAdjustment: AnyView(IwEntryFormPage())
    case .newStockIssue: AnyView(IwIssueFormPage())
    case .newLandedCost: AnyView(IwLandedCostFormPage())
    default: nil
    }
  }
}

/// Which inventory actions this iPhone may save yet: each needs every kind
/// of record its port writes to be writable (`OneWritable`).
@MainActor
enum IwGate {
  private static func can(_ kinds: RecordKind...) -> Bool {
    kinds.allSatisfy { OneData.canWrite($0) }
  }

  /// `saveItem`: the item, its code's counter, the stock accounts and the
  /// main store, the documents it moves stock on and its opening stock.
  static var items: Bool {
    can(.products, .companies, .accounts, .activities, .warehouses, .stockMovements, .stockEntries, .documents)
  }

  /// `deleteItem`: the item and its pictures.
  static var deleteItems: Bool { can(.products, .attachments, .activities) }

  /// `saveWarehouse`.
  static var warehouses: Bool { can(.warehouses, .activities) }

  /// `recordStockEntry` and `voidStockEntry`.
  static var entries: Bool { can(.stockEntries, .stockMovements, .accounts, .activities, .warehouses) }

  /// `saveLandedCost` and `voidLandedCost`.
  static var landedCosts: Bool { can(.landedCosts, .stockMovements, .accounts, .activities, .warehouses) }

  /// `issueStock` (recorded at once, or sent for approval) and `voidStockIssue`.
  static var issues: Bool {
    can(.stockIssues, .stockMovements, .accounts, .activities, .approvals, .warehouses)
  }

  /// `rebuildStock`.
  static var rebuild: Bool { can(.stockMovements, .warehouses) }

  /// Viewers only look.
  static func edits(_ model: AppModel) -> Bool {
    guard let role = model.one.writeLink?.role else { return false }
    return role != .viewer
  }
}

/// One inventory action saved (`model.one.write`); a refusal shows as the
/// app's toast in the reader's language.
@MainActor
enum IwSave {
  @discardableResult
  static func run<T>(_ model: AppModel, done: ((T) -> String?)? = nil, _ body: (WriteContext) throws -> T) async -> T? {
    do {
      let result = try await model.one.write(body)
      if let message = done?(result) { model.confirm(message) }
      return result
    } catch {
      model.toast = Toast(kind: .error, message: message(error))
      return nil
    }
  }

  /// The web's words of the port's or the sync rules' refusal, in the reader's language.
  static func message(_ error: Error) -> String {
    if let failure = error as? WriteFailure { return t(failure.message, failure.vars) }
    if let refused = error as? SyncWriteError {
      switch refused {
      case .refused(let text), .invalid(let text): return t(text)
      case .notWritable: return t("Could not save.")
      }
    }
    if let failure = error as? MahamError { return t(failure.message) }
    return t("Could not save.")
  }

  /// The person's place in the company for the issue writes (`CloudLink`).
  static func link(_ model: AppModel) -> IwStockIssues.Link? {
    guard let link = model.one.writeLink else { return nil }
    // `link.features`: what the server has, as last asked (none until it answers).
    let features = model.one.cloud.map { Array($0.features) } ?? []
    return IwStockIssues.Link(role: link.role, userId: link.userId, approver: link.approver, features: features)
  }
}

/// What a page asks of the form it opens (the web's `?kind=`, `?from=`, …):
/// taken once, by the form that opens next.
@MainActor
enum IwIntent {
  private static var itemKind: String?
  private static var pendingEntry: (kind: String, from: String?, to: String?, item: String?)?
  private static var issueWarehouse: String?
  private static var landedBill: String?

  static func newItem(kind: String) { itemKind = kind }
  static func takeItemKind() -> String {
    defer { itemKind = nil }
    return itemKind ?? "service"
  }

  static func entry(kind: String, from: String? = nil, to: String? = nil, item: String? = nil) {
    pendingEntry = (kind: kind, from: from, to: to, item: item)
  }

  static func takeEntry() -> (kind: String, from: String?, to: String?, item: String?) {
    defer { pendingEntry = nil }
    return pendingEntry ?? (kind: "adjustment", from: nil, to: nil, item: nil)
  }

  static func issue(warehouse: String?) { issueWarehouse = warehouse }
  static func takeIssueWarehouse() -> String? {
    defer { issueWarehouse = nil }
    return issueWarehouse
  }

  static func landedCost(bill: String?) { landedBill = bill }
  static func takeLandedBill() -> String? {
    defer { landedBill = nil }
    return landedBill
  }
}

/// A number typed in a text field, as the web's `NumberInput` reads it
/// (Arabic digits and separators too); `blankZero` shows 0 as empty;
/// without `allowNegative` a minus sign is dropped.
struct IwNumberField: View {
  @Binding var value: Double
  var blankZero = false
  var allowNegative = true
  var placeholder = ""
  @State private var text = ""
  @State private var shown: Double?

  var body: some View {
    TextInput(
      text: $text, placeholder: placeholder, keyboard: allowNegative ? .numbersAndPunctuation : .decimalPad
    )
    .onAppear { sync() }
    .onChange(of: value) { _, _ in
      if shown != value { sync() }
    }
    .onChange(of: text) { _, typed in
      let parsed = Money.parseAmount(typed)
      var number = parsed.isFinite ? parsed : 0
      if !allowNegative, number < 0 { number = -number }
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

/// A multi-line text field in the input's look (`Textarea`).
struct IwTextArea: View {
  @Binding var text: String
  var lines = 2
  @FocusState private var focused: Bool

  var body: some View {
    TextField("", text: $text, axis: .vertical)
      .lineLimit(lines...max(lines, 10))
      .focused($focused)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .modifier(InputChrome(focused: focused))
  }
}

/// The web's `Checkbox` with its label and an optional line under it.
struct IwCheckRow: View {
  let label: String
  var description: String?
  let checked: Bool
  var trailing: String?
  let toggle: () -> Void
  @Environment(\.palette) private var palette
  @Environment(\.isEnabled) private var isEnabled

  /// The box: primary with a white check when ticked, a slate-300 border when not.
  private var box: some View {
    let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
    return ZStack {
      shape.fill(checked ? palette.primarySolid : palette.surface)
      shape.strokeBorder(checked ? palette.primarySolid : palette.slate(300), lineWidth: 1)
      if checked {
        IconView(.check, size: 12).foregroundStyle(Color.white)
      }
    }
    .frame(width: 16, height: 16)
  }

  var body: some View {
    Button {
      Haptics.play(.selection)
      toggle()
    } label: {
      HStack(alignment: .top, spacing: 10) {
        box.padding(.top, 2)
        VStack(alignment: .leading, spacing: 2) {
          Text(label)
            .font(.web(14))
            .foregroundStyle(palette.slate(isEnabled ? 900 : 500))
            .multilineTextAlignment(.leading)
          if let description {
            Text(description).font(.web(12)).foregroundStyle(palette.slate(500))
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if let trailing {
          Text(trailing).font(.web(14, tabular: true)).foregroundStyle(palette.slate(700))
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .opacity(isEnabled ? 1 : 0.5)
    .accessibilityAddTraits(checked ? .isSelected : [])
  }
}

/// A confirmation dialog's footer: Cancel and the action (red when it voids or deletes).
struct IwConfirmFooter: View {
  let label: String
  var danger = true
  let onCancel: () -> Void
  let onConfirm: () -> Void

  var body: some View {
    WebButton(t("Cancel"), variant: .outline) { onCancel() }
    WebButton(label, variant: danger ? .danger : .primary) { onConfirm() }
  }
}

/// A form's line of words in amber (a warning) or slate (a note).
struct IwNote: View {
  let text: String
  var warning = false
  @Environment(\.palette) private var palette

  var body: some View {
    Text(text)
      .font(.web(12))
      .foregroundStyle(warning ? palette[.amber(800)] : palette.slate(500))
      .padding(.horizontal, warning ? 12 : 0)
      .padding(.vertical, warning ? 8 : 0)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(warning ? palette[.amber(50)] : Color.clear, in: RoundedRectangle(cornerRadius: WebRadius.md))
  }
}
