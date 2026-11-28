import MahamKit
import SwiftUI

// Saving natively in the accounting pages: the pages that only make or
// change records (`/journals/new`, `/assets/new`, `/assets/:id/edit`), which
// kinds of record may be saved on this iPhone yet, who may change what, one
// user action through the ports of the web's writes (MahamKit/Write/Accounting)
// with refusals shown in the reader's language, and the inputs and
// confirmations the accounting forms share.

/// The accounting pages that create or change records, answered natively
/// once those records can be saved on this iPhone (`OneWritable`); nil until
/// then, and for every other route.
@MainActor
enum AccountingWriteArea {
  static func page(for route: Route) -> AnyView? {
    switch route {
    case .newJournal:
      AwWrite.journals ? AnyView(AwJournalEditorPage(id: nil)) : nil
    case .newAsset:
      AwWrite.assets ? AnyView(AwAssetFormPage(id: nil)) : nil
    case .editAsset(let id):
      AwWrite.assets ? AnyView(AwAssetFormPage(id: id)) : nil
    default:
      nil
    }
  }
}

/// Which accounting actions may save on this iPhone yet: every kind of
/// record the action writes is in `OneWritable.kinds`.
@MainActor
enum AwWrite {
  static func can(_ kinds: [RecordKind]) -> Bool {
    for kind in kinds where !OneData.canWrite(kind) { return false }
    return true
  }

  /// An account of the chart, and the activity log.
  static var accounts: Bool { can([.accounts, .activities]) }
  /// A journal: the journal, the company's counter, the activity log.
  static var journals: Bool { can([.journals, .companies, .activities]) }
  /// An asset and the journal of its purchase or opening balance.
  static var assets: Bool { can([.assets, .journals, .companies, .activities]) }
  /// A disposal also makes the gain or loss account when the chart has none.
  static var disposals: Bool { assets && can([.accounts]) }
  /// A depreciation run and its journal.
  static var depreciation: Bool { can([.depreciationRuns, .journals, .companies, .activities]) }
  /// Statement lines typed in.
  static var statementLines: Bool { can([.bankTransactions, .activities]) }
  /// Matching, ignoring and deleting statement lines.
  static var matching: Bool { can([.bankTransactions]) }
  /// A statement line recorded in the books (a transfer or a journal) and matched.
  static var recording: Bool { journals && matching }
  /// A VAT return filed, paid or undone.
  static var vat: Bool { can([.vatReturns, .journals, .companies, .activities]) }
  /// A year closed (the reserve and levy accounts it may make) or reopened.
  static var yearEnd: Bool { can([.yearEnds, .journals, .companies, .accounts, .activities]) }
}

/// Who may change what in the accounting pages, as the server lets them:
/// viewers and members the owner made Books view only for change nothing;
/// staff record transfers but not the accounting setup (accounts, journals,
/// assets, statement lines, VAT, the year-end close).
@MainActor
struct AwAccess {
  let role: MemberRole?
  let booksEditable: Bool

  init(_ model: AppModel, _ suite: SuiteState?) {
    role = model.business.company?.role
    booksEditable = suite.map { $0.access(.books).canEdit } ?? true
  }

  /// Changes anything in the books.
  var edits: Bool { role != .viewer && booksEditable }
  /// Changes the accounting setup: owners, admins and accountants.
  var accounting: Bool { edits && Roles.canEditAccounting(role) }
}

/// One user action saved through the ports of the web's writes.
@MainActor
enum AwSave {
  /// The words the web stores in the interface language (its `t` inside a write).
  static var words: I18n.Translator { Localization.translator }

  /// Saves one action (`model.one.write`); `done` confirms it. A refusal
  /// shows as the app's toast in the reader's language, and gives nil.
  /// In a dialog, which covers the toasts, `failed` shows the refusal instead.
  @discardableResult
  static func run<T>(
    _ model: AppModel, done: String? = nil, failed: ((String) -> Void)? = nil,
    _ body: (WriteContext, I18n.Translator) throws -> T
  ) async -> T? {
    let tr = words
    do {
      let result = try await model.one.write { ctx in try body(ctx, tr) }
      if let done { model.confirm(done) }
      return result
    } catch {
      let text = message(error)
      if let failed {
        failed(text)
      } else {
        model.toast = Toast(kind: .error, message: text)
      }
      return nil
    }
  }

  /// `run` for an action that gives nothing back: whether it was saved.
  @discardableResult
  static func perform(
    _ model: AppModel, done: String? = nil, failed: ((String) -> Void)? = nil,
    _ body: (WriteContext, I18n.Translator) throws -> Void
  ) async -> Bool {
    let saved: Void? = await run(model, done: done, failed: failed, body)
    return saved != nil
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
}

// MARK: Accounts to choose from

@MainActor
enum AwPick {
  /// "1520 Office equipment and computers", in the language being read (`accountLabel`).
  static func label(_ account: JSONValue?) -> String {
    guard let account else { return "—" }
    return "\(account.str("code")) \(localName(account))"
  }

  /// By code, as numbers where they are numbers (`byCode`), keeping the order of equals.
  static func byCode(_ accounts: [JSONValue]) -> [JSONValue] {
    accounts.enumerated().sorted { x, y in
      let order = AcText.compareNumeric(x.element.str("code"), y.element.str("code"))
      return order == .orderedSame ? x.offset < y.offset : order == .orderedAscending
    }.map { $0.element }
  }

  /// Options of a searchable account field: code and name, found by either name.
  static func options(_ accounts: [JSONValue]) -> [ComboOption] {
    accounts.map { account in
      ComboOption(
        value: account.rid, label: label(account),
        keywords: "\(account.str("name")) \(account.str("nameAr"))")
    }
  }

  /// Options of a plain account select, with "Choose an account…" first.
  static func select(_ accounts: [JSONValue], placeholder: String = t("Choose an account…")) -> [SelectOption<String>] {
    [SelectOption("", placeholder)] + accounts.map { SelectOption($0.rid, label($0)) }
  }

  /// Bank, cash and card accounts in use, by code.
  static func money(_ one: OneData) -> [JSONValue] {
    byCode(
      one.records(.accounts).filter {
        AcAccountTypes.isMoneyAccount($0.str("type")) && !$0.flag("archived")
      })
  }
}

// MARK: Inputs

/// A number typed in a field (`NumberInput`): Arabic-Indic digits too, left to
/// right, aligned to the end; `blankZero` shows 0 as empty. It shows the
/// value again once it loses focus.
struct AwAmountField: View {
  @Binding var value: Double
  var placeholder: String
  var blankZero: Bool
  @State private var text = ""
  @FocusState private var focused: Bool
  @Environment(\.palette) private var palette

  init(value: Binding<Double>, placeholder: String = "", blankZero: Bool = true) {
    _value = value
    self.placeholder = placeholder
    self.blankZero = blankZero
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
    .onAppear { text = shown(value) }
    .onChange(of: text) { _, typed in
      if focused { value = Money.parseAmount(typed) }
    }
    .onChange(of: value) { _, now in
      if !focused { text = shown(now) }
    }
    .onChange(of: focused) { _, now in
      if !now { text = shown(value) }
    }
  }

  private func shown(_ number: Double) -> String {
    if !number.isFinite { return "" }
    return blankZero && number == 0 ? "" : Money.jsString(number)
  }
}

/// A text area (`Textarea`) in the input's look, growing with its text.
struct AwTextArea: View {
  @Binding var text: String
  var lines: Int
  @FocusState private var focused: Bool

  init(text: Binding<String>, lines: Int = 2) {
    _text = text
    self.lines = lines
  }

  var body: some View {
    TextField("", text: $text, axis: .vertical)
      .lineLimit(lines...max(lines, 12))
      .focused($focused)
      .font(.web(16))
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .modifier(InputChrome(focused: focused))
  }
}

// MARK: Confirmations

/// A confirmation (`useConfirm`): a title, what happens, Cancel and the action.
struct AwConfirm: Identifiable {
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
  func awConfirm(_ confirm: Binding<AwConfirm?>) -> some View {
    modifier(AwConfirmModifier(confirm: confirm))
  }
}

private struct AwConfirmModifier: ViewModifier {
  @Binding var confirm: AwConfirm?

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

/// "Discard unsaved changes?" before leaving an editor with changes (`useUnsavedGuard`).
@MainActor
enum AwUnsaved {
  static func confirm(_ leave: @escaping () -> Void) -> AwConfirm {
    AwConfirm(
      title: t("Discard unsaved changes?"), description: t("You have changes that have not been saved yet."),
      confirmLabel: t("Discard changes"), cancelLabel: t("Keep editing"), danger: true, action: leave)
  }
}

/// A refusal shown in a dialog, where the toasts don't show (red-600, 14pt).
struct AwFormError: View {
  let text: String?
  @Environment(\.palette) private var palette

  init(text: String?) {
    self.text = text
  }

  var body: some View {
    if let text, !text.isEmpty {
      HStack(alignment: .top, spacing: 8) {
        IconView(.circleAlert, size: 16).padding(.top, 1)
        Text(text).fixedSize(horizontal: false, vertical: true)
      }
      .font(.web(14))
      .foregroundStyle(palette[.red(600)])
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// A short line of help or warning under a form's controls.
struct AwHint: View {
  let text: String
  var tone: Token = .slate(500)
  @Environment(\.palette) private var palette

  init(_ text: String, tone: Token = .slate(500)) {
    self.text = text
    self.tone = tone
  }

  var body: some View {
    Text(text)
      .font(.web(14))
      .foregroundStyle(palette.color(tone))
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }
}
