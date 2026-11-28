import MahamKit
import SwiftUI
import UIKit

/// The pages that create or change sales and purchase documents and
/// contacts (`/invoices/new`, `/bills/:id/edit`, `/clients/new`, …),
/// answered natively once those records can be saved on the iPhone
/// (`OneWritable`); nil until then, and for every other route. New items
/// (`/products?new=1`) are the inventory's form (`InventoryWriteArea`).
@MainActor
enum DocumentsWriteArea {
  static func page(for route: Route) -> AnyView? {
    switch route {
    case .newSalesDocument(let kind):
      DcWrite.documents ? AnyView(DcEditorPage(type: DocType(kind), id: nil)) : nil
    case .editSalesDocument(let kind, let id):
      DcWrite.documents ? AnyView(DcEditorPage(type: DocType(kind), id: id)) : nil
    case .newPurchaseDocument(let kind):
      DcWrite.documents ? AnyView(DcEditorPage(type: DocType(kind), id: nil)) : nil
    case .editPurchaseDocument(let kind, let id):
      DcWrite.documents ? AnyView(DcEditorPage(type: DocType(kind), id: id)) : nil
    case .newContact(let kind):
      DcWrite.contacts ? AnyView(DcContactFormPage(kind: kind, id: nil)) : nil
    case .editContact(let kind, let id):
      DcWrite.contacts ? AnyView(DcContactFormPage(kind: kind, id: id)) : nil
    default:
      nil
    }
  }
}

/// What the document, contact and item forms share: which of them may save
/// on this iPhone yet, and the web's words for a save that was refused.
@MainActor
enum DcWrite {
  /// Every kind of record is writable (`OneWritable.kinds`).
  static func can(_ kinds: [RecordKind]) -> Bool {
    for kind in kinds where !OneData.canWrite(kind) { return false }
    return true
  }

  /// Saving a document: the document, the company's counter, the activity log.
  static var documents: Bool { can([.documents, .companies, .activities]) }
  /// Leaving the books or deleting: payments and credits are freed or taken off.
  static var documentsWithPayments: Bool { documents && can([.payments, .attachments]) }
  /// Saving a client or vendor (and its number on the company).
  static var contacts: Bool { can([.clients, .companies, .activities]) }
  /// Sending a change of an issued document for approval.
  static var approvals: Bool { can([.approvals, .activities]) }

  /// Viewers only look (the sync rules refuse their changes anyway).
  static func edits(_ model: AppModel) -> Bool {
    guard let role = model.one.writeLink?.role else { return false }
    return role != .viewer
  }

  /// A refused save in the reader's language (the web's words through `t`).
  static func message(_ error: Error) -> String {
    if let failure = error as? WriteFailure { return t(failure.message, failure.vars) }
    if let approval = error as? DcApprovalRequired { return t(approval.failure.message, approval.failure.vars) }
    if let refused = error as? SyncWriteError {
      switch refused {
      case .refused(let reason), .invalid(let reason): return t(reason)
      case .notWritable: return t("Could not save.")
      }
    }
    if let failure = error as? MahamError { return failure.message }
    return t("Something went wrong.")
  }

  static func fail(_ model: AppModel, _ error: Error) {
    model.toast = Toast(kind: .error, message: message(error))
  }

  /// The document type's name in the singular, in lower case, as the web's `documentNoun`.
  static func noun(_ type: DocType) -> String {
    t(type.singular).lowercased()
  }

  /// "Invoice INV-2026-0001 saved", or "Draft invoice saved" without a number yet.
  static func savedText(_ type: DocType, number: String) -> String {
    number.isEmpty
      ? t("Draft {document} saved", ["document": noun(type)])
      : t("{document} {number} saved", ["document": t(type.singular), "number": number])
  }

  /// "Invoice INV-2026-0002 created", or "Draft invoice created".
  static func createdText(_ doc: JSONValue) -> String {
    let type = DocType(rawValue: doc.str("type")) ?? .invoice
    let number = doc.str("number")
    return number.isEmpty
      ? t("Draft {document} created", ["document": noun(type)])
      : t("{document} {number} created", ["document": t(type.singular), "number": number])
  }

  /// The route of a document's editor.
  static func editRoute(_ type: DocType, id: String) -> Route {
    switch type {
    case .invoice: .editSalesDocument(.invoice, id: id)
    case .quote: .editSalesDocument(.quote, id: id)
    case .credit: .editSalesDocument(.credit, id: id)
    case .proforma: .editSalesDocument(.proforma, id: id)
    case .salesOrder: .editSalesDocument(.salesOrder, id: id)
    case .deliveryNote: .editSalesDocument(.deliveryNote, id: id)
    case .bill: .editPurchaseDocument(.bill, id: id)
    case .vendorCredit: .editPurchaseDocument(.vendorCredit, id: id)
    case .purchaseOrder: .editPurchaseDocument(.purchaseOrder, id: id)
    }
  }

  /// The route of a document's own page.
  static func viewRoute(_ doc: JSONValue) -> Route {
    (DocType(rawValue: doc.str("type")) ?? .invoice).route(doc.rid)
  }
}

/// A number typed in a field: Arabic-Indic digits too, left to right,
/// aligned to the end (`NumberInput`). Shows the value again once it loses focus.
struct DcAmountField: View {
  @Binding var value: Double
  var placeholder: String
  @State private var text = ""
  @FocusState private var focused: Bool
  @Environment(\.palette) private var palette

  init(value: Binding<Double>, placeholder: String = "") {
    _value = value
    self.placeholder = placeholder
  }

  var body: some View {
    ZStack(alignment: .trailing) {
      if text.isEmpty {
        Text(placeholder).foregroundStyle(palette.slate(400)).allowsHitTesting(false)
      }
      TextField("", text: $text)
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .focused($focused)
        .accessibilityLabel(Text(placeholder))
    }
    .font(.web(16, tabular: true))
    .padding(.horizontal, 12)
    .modifier(InputChrome(focused: focused))
    .environment(\.layoutDirection, .leftToRight)
    .onAppear { text = DcAmountField.shown(value) }
    .onChange(of: text) { _, typed in
      if focused { value = Money.parseAmount(typed) }
    }
    .onChange(of: value) { _, now in
      if !focused { text = DcAmountField.shown(now) }
    }
    .onChange(of: focused) { _, now in
      if !now { text = DcAmountField.shown(value) }
    }
  }

  /// The number as JavaScript writes it ("12.5", "0").
  static func shown(_ value: Double) -> String {
    value.isFinite ? Money.jsString(value) : "0"
  }
}

/// A text area (`Textarea`): the field's look, growing with its text.
struct DcTextArea: View {
  @Binding var text: String
  var placeholder: String
  var lines: Int
  @FocusState private var focused: Bool
  @Environment(\.palette) private var palette

  init(text: Binding<String>, placeholder: String = "", lines: Int = 3) {
    _text = text
    self.placeholder = placeholder
    self.lines = lines
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      if text.isEmpty {
        Text(placeholder).foregroundStyle(palette.slate(400)).allowsHitTesting(false)
      }
      TextField("", text: $text, axis: .vertical)
        .lineLimit(lines...max(lines, 12))
        .focused($focused)
        .accessibilityLabel(Text(placeholder))
    }
    .font(.web(16))
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .modifier(InputChrome(focused: focused))
  }
}

/// A plain text field (`Input`); left to right for codes, numbers and emails.
struct DcTextField: View {
  @Binding var text: String
  var placeholder: String = ""
  var keyboard: UIKeyboardType = .default
  var leftToRight = false

  var body: some View {
    if leftToRight {
      TextInput(text: $text, placeholder: placeholder, keyboard: keyboard)
        .environment(\.layoutDirection, .leftToRight)
    } else {
      TextInput(text: $text, placeholder: placeholder, keyboard: keyboard)
    }
  }
}

/// A confirmation (`useConfirm`): a title, what happens, Cancel and the action.
struct DcConfirm: Identifiable {
  let id = UUID()
  let title: String
  let description: String
  let confirmLabel: String
  var cancelLabel: String = t("Cancel")
  var danger = false
  let action: () -> Void
}

extension View {
  /// Shows `confirm` as the web's confirmation dialog while it is set.
  func dcConfirm(_ confirm: Binding<DcConfirm?>) -> some View {
    modifier(DcConfirmModifier(confirm: confirm))
  }
}

private struct DcConfirmModifier: ViewModifier {
  @Binding var confirm: DcConfirm?

  func body(content: Content) -> some View {
    content.webDialog(isPresented: shown, title: confirm?.title ?? "", description: confirm?.description) {
      EmptyView()
    } footer: {
      WebButton(confirm?.cancelLabel ?? t("Cancel"), variant: .outline) { confirm = nil }
      WebButton(confirm?.confirmLabel ?? t("OK"), variant: confirm?.danger == true ? .danger : .primary) {
        let action = confirm?.action
        confirm = nil
        action?()
      }
    }
  }

  private var shown: Binding<Bool> {
    Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })
  }
}
