import MahamKit
import SwiftUI

// Saving People and payroll natively: the pages that create records
// (`PeopleWriteArea`), which tables each action writes (its buttons stay
// hidden until every one of them may be saved here, `OneWritable`), and how
// a save runs: the port of the web's function in one `model.one.write`, the
// web's words in the reader's language when it is refused.

/// The People pages that create or change a record: a new or changed
/// employee, a new letter, a new costing. Nil for a kind not writable yet.
@MainActor
enum PeopleWriteArea {
  static func page(for route: Route) -> AnyView? {
    switch route {
    case .newEmployee:
      PwKinds.can(PwKinds.employee) ? AnyView(PeGate { PwEmployeeFormPage(id: nil) }) : nil
    case .editEmployee(let id):
      PwKinds.can(PwKinds.employee) ? AnyView(PeGate { PwEmployeeFormPage(id: id) }) : nil
    case .newLetter:
      PwKinds.can(PwKinds.letters) ? AnyView(PeGate { PwLetterFormPage() }) : nil
    case .newCosting:
      PwKinds.can(PwKinds.costings) ? AnyView(PeGate { PwCostingEditorPage(id: nil) }) : nil
    default:
      nil
    }
  }
}

/// The tables each action writes (what the port puts), all of which must be writable.
@MainActor
enum PwKinds {
  static let employee: [RecordKind] = [.employees, .companies, .activities, .employeeLetters]
  static let employeeDelete: [RecordKind] = [
    .employees, .attachments, .activities, .renewals, .complianceDocuments, .employeeLetters, .expenses,
  ]
  static let photo: [RecordKind] = [.employees, .attachments]
  static let departments: [RecordKind] = [.peopleSettings, .employees, .activities]
  static let peopleSettings: [RecordKind] = [.peopleSettings, .activities]
  static let payrollSettings: [RecordKind] = [.payrollSettings, .activities]
  static let leave: [RecordKind] = [.leaveRecords, .employees, .activities]
  static let openings: [RecordKind] = [.employees, .leaveRecords, .activities]
  static let payRun: [RecordKind] = [.payRuns, .activities]
  /// Posting: the run, its entries, accounts made, the journal counter, PIFSS shares owed.
  static let posting: [RecordKind] = [.payRuns, .journals, .accounts, .companies, .activities, .staffLoans]
  static let approvals: [RecordKind] = [.approvals, .activities]
  static let loan: [RecordKind] = [.staffLoans, .journals, .accounts, .companies, .activities]
  static let settlement: [RecordKind] = [
    .finalSettlements, .employees, .journals, .accounts, .companies, .activities,
  ]
  static let letters: [RecordKind] = [.employeeLetters, .activities]
  static let issue: [RecordKind] = [.employeeLetters, .companies, .activities]
  static let lettersSwitch: [RecordKind] = [.peopleSettings, .companies, .activities]
  static let templates: [RecordKind] = [.letterTemplates, .activities]
  static let costings: [RecordKind] = [.staffingCostings, .activities]
  static let costingSwitch: [RecordKind] = [.peopleSettings, .activities]

  static func can(_ kinds: [RecordKind]) -> Bool {
    for kind in kinds where !OneData.canWrite(kind) { return false }
    return true
  }
}

extension OneData {
  /// The person's link to the company, for the ports (`db.syncState` on the web).
  var pwLink: PwLink? {
    guard let link = writeLink else { return nil }
    return PwLink(
      userId: link.userId, role: link.role, approver: link.approver, features: Array(cloud?.features ?? []))
  }
}

extension PwText {
  /// What the web's `t` stores and says, in the language on screen.
  static var app: PwText {
    PwText(language: Localization.language) { key, vars in t(key, vars) }
  }
}

/// How a People save runs and what it says.
@MainActor
enum PwSave {
  /// Saves one action through the port. On a refusal, the web's words in a
  /// toast (or to `failed`, for a dialog that shows them in itself); on
  /// success, `success` when given. Nil when nothing was saved.
  @discardableResult
  static func run<T>(
    _ model: AppModel, success: String? = nil, failed: ((String) -> Void)? = nil,
    _ body: (WriteContext) throws -> T
  ) async -> T? {
    do {
      let result = try await model.one.write(body)
      if let success { model.confirm(success) }
      return result
    } catch {
      if let failed {
        failed(message(error))
      } else {
        model.toast = Toast(kind: .error, message: message(error))
      }
      return nil
    }
  }

  /// A refused save in the reader's language.
  static func message(_ error: Error) -> String {
    if let failure = error as? WriteFailure { return t(failure.message, failure.vars) }
    if let refused = error as? SyncWriteError {
      switch refused {
      case .refused(let reason), .invalid(let reason): return t(reason)
      case .notWritable: return t("Could not save the changes.")
      }
    }
    if let failure = error as? MahamError { return failure.message }
    return t("Something went wrong.")
  }

  /// Reads the company with the ports' view of it (nothing is saved).
  static func read<T>(_ model: AppModel, _ body: (WriteContext) throws -> T) async -> T? {
    try? await model.one.write(body)
  }
}

// MARK: - Fields

/// A JSON record edited by a form, field by field.
struct PwDraft {
  var fields: [String: JSONValue]

  init(_ record: JSONValue?) { fields = record?.object ?? [:] }

  var json: JSONValue { .object(fields) }

  func text(_ key: String) -> String { fields[key]?.string ?? "" }
  func number(_ key: String) -> Double { fields[key]?.double ?? 0 }
  func flag(_ key: String) -> Bool { fields[key]?.bool == true }
}

@MainActor
extension Binding where Value == PwDraft {
  /// A text field of the record.
  func text(_ key: String) -> Binding<String> {
    Binding<String>(
      get: { wrappedValue.text(key) },
      set: { wrappedValue.fields[key] = .string($0) })
  }

  /// A day of the record ("" for none, kept as null).
  func day(_ key: String) -> Binding<String> {
    Binding<String>(
      get: { wrappedValue.text(key) },
      set: { wrappedValue.fields[key] = $0.isEmpty ? .null : .string($0) })
  }

  /// A number of the record.
  func number(_ key: String) -> Binding<Double> {
    Binding<Double>(
      get: { wrappedValue.number(key) },
      set: { wrappedValue.fields[key] = .number($0) })
  }

  /// A switch of the record.
  func flag(_ key: String) -> Binding<Bool> {
    Binding<Bool>(
      get: { wrappedValue.flag(key) },
      set: { wrappedValue.fields[key] = .bool($0) })
  }
}

@MainActor
extension Binding where Value == [PwDraft] {
  /// One row of a list being edited; a row just removed reads as empty
  /// rather than past the end, while the list redraws.
  func row(_ index: Int) -> Binding<PwDraft> {
    Binding<PwDraft>(
      get: { wrappedValue.indices.contains(index) ? wrappedValue[index] : PwDraft(nil) },
      set: { if wrappedValue.indices.contains(index) { wrappedValue[index] = $0 } })
  }
}

/// A number typed as text, read the way the web reads amounts (`parseAmount`):
/// empty for 0. What is typed sets the number; a number set from elsewhere
/// shows once the field isn't being typed in.
struct PwNumberField: View {
  @Binding var value: Double
  var placeholder: String = ""
  /// A minus sign may be typed (the number pad has none).
  var allowNegative = false

  var body: some View {
    PwTypedNumber(
      value: Binding<Double?>(get: { value }, set: { value = $0 ?? 0 }), placeholder: placeholder,
      allowNegative: allowNegative, blankZero: true)
  }
}

/// A number that may be left empty (`null`), such as a limit or days of one's own.
struct PwOptionalNumberField: View {
  @Binding var value: Double?
  var placeholder: String = ""

  var body: some View {
    PwTypedNumber(value: $value, placeholder: placeholder, allowNegative: false, blankZero: false)
  }
}

private struct PwTypedNumber: View {
  @Binding var value: Double?
  let placeholder: String
  let allowNegative: Bool
  let blankZero: Bool
  @State private var text = ""
  @FocusState private var focused: Bool
  @Environment(\.palette) private var palette

  var body: some View {
    ZStack(alignment: .leading) {
      if text.isEmpty {
        Text(placeholder).foregroundStyle(palette.slate(400)).lineLimit(1).allowsHitTesting(false)
      }
      TextField("", text: $text)
        .keyboardType(allowNegative ? .numbersAndPunctuation : .decimalPad)
        .focused($focused)
        .accessibilityLabel(Text(placeholder))
    }
    .font(.web(16, tabular: true))
    .padding(.horizontal, 12)
    .modifier(InputChrome(focused: focused))
    .environment(\.layoutDirection, .leftToRight)
    .contentShape(Rectangle())
    .onTapGesture { focused = true }
    .onAppear { text = shown(value) }
    .onChange(of: text) { _, typed in
      if focused { value = read(typed) }
    }
    .onChange(of: value) { _, now in
      if !focused { text = shown(now) }
    }
    .onChange(of: focused) { _, now in
      if !now { text = shown(value) }
    }
  }

  private func read(_ typed: String) -> Double? {
    let trimmed = typed.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return blankZero ? 0 : nil }
    return Money.parseAmount(trimmed)
  }

  private func shown(_ number: Double?) -> String {
    guard let number else { return "" }
    if blankZero && number == 0 { return "" }
    return Money.jsString(number)
  }
}

/// Text of several lines (the web's `Textarea`), in the field look.
struct PwTextArea: View {
  @Binding var text: String
  var minHeight: CGFloat = 88
  var rightToLeft: Bool?

  var body: some View {
    TextEditor(text: $text)
      .scrollContentBackground(.hidden)
      .font(.web(16))
      .frame(minHeight: minHeight)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .modifier(InputChrome(focused: false))
      .environment(\.layoutDirection, direction)
  }

  private var direction: LayoutDirection {
    guard let rightToLeft else { return Localization.language.isRightToLeft ? .rightToLeft : .leftToRight }
    return rightToLeft ? .rightToLeft : .leftToRight
  }
}

/// A month, yyyy-MM, chosen from the months around today.
struct PwMonthSelect: View {
  @Binding var period: String
  @Environment(AppModel.self) private var model

  var body: some View {
    Select(selection: $period, options: options)
  }

  private var options: [SelectOption<String>] {
    let today = ISODates.today()
    let format = model.one.format
    var list: [SelectOption<String>] = []
    for offset in stride(from: 3, through: -24, by: -1) {
      let period = PePayroll.addPeriods(String(today.prefix(7)), offset)
      list.append(SelectOption(period, PePayroll.formatPeriod(period, format)))
    }
    return list
  }
}

/// The company's bank and cash accounts, for "Paid from".
@MainActor
enum PwAccounts {
  static func cash(_ one: OneData) -> [SelectOption<String>] {
    one.records(.accounts)
      .filter { $0.str("type") == "asset_cash" && !$0.flag("archived") }
      .sorted { $0.str("code") < $1.str("code") }
      .map { SelectOption($0.rid, [$0.str("code"), localName($0.str("name"), $0.text("nameAr"))].joined(separator: " ")) }
  }

  /// The bank account payroll pays from: the one chosen in the settings, else the main bank account.
  static func defaultCash(_ one: OneData) -> String {
    let options = cash(one)
    let chosen = one.pePayrollSettings.raw?.text("bankAccountId")
    if let chosen, options.contains(where: { $0.value == chosen }) { return chosen }
    let bank = one.records(.accounts).first { $0.text("role") == "bank" && !$0.flag("archived") }?.rid
    return bank ?? options.first?.value ?? ""
  }
}

/// A confirmation in the web's words: a title, what happens, and the button that does it.
struct PwConfirm: ViewModifier {
  @Binding var isPresented: Bool
  let title: String
  let description: String
  let confirmLabel: String
  var danger = false
  var cancelLabel: String?
  let action: () -> Void

  func body(content: Content) -> some View {
    content.webDialog(isPresented: $isPresented, title: title, description: description) {
      EmptyView()
    } footer: {
      WebButton(cancelLabel ?? t("Cancel"), variant: .outline) { isPresented = false }
      WebButton(confirmLabel, variant: danger ? .danger : .primary) {
        isPresented = false
        action()
      }
    }
  }
}

extension View {
  func pwConfirm(
    _ isPresented: Binding<Bool>, title: String, description: String, confirmLabel: String, danger: Bool = false,
    cancelLabel: String? = nil, action: @escaping () -> Void
  ) -> some View {
    modifier(
      PwConfirm(
        isPresented: isPresented, title: title, description: description, confirmLabel: confirmLabel, danger: danger,
        cancelLabel: cancelLabel, action: action))
  }
}
