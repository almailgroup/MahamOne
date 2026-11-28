import MahamKit
import SwiftUI

// The chart of accounts' dialog (src/apps/books/pages/accounting/chart.tsx
// `AccountDialog`): a new account or an edit, with the bank details of bank,
// cash and card accounts; deleting an account nothing uses.

@MainActor
enum AwAccountTypeHints {
  /// `ACCOUNT_TYPES[type].hint`: shown under the type when picking it.
  static func hint(_ type: String) -> String {
    switch type {
    case "asset_cash": "Bank accounts, cash on hand"
    case "asset_receivable": "Money customers owe you"
    case "asset_current": "Stock, deposits, VAT to reclaim"
    case "asset_prepayments": "Costs paid in advance"
    case "asset_fixed": "Equipment, vehicles, property"
    case "asset_non_current": "Long-term investments and other assets"
    case "liability_payable": "Money you owe suppliers"
    case "liability_credit_card": "Company cards"
    case "liability_current": "VAT due, wages payable, accruals"
    case "liability_non_current": "Loans repayable after a year"
    case "equity": "Capital, drawings, retained earnings"
    case "income": "Sales of goods and services"
    case "income_other": "Interest, grants, gains"
    case "expense_direct_cost": "Direct costs of what you sell"
    case "expense": "Running costs of the business"
    case "expense_depreciation": "Wear of fixed assets"
    case "expense_other": "Interest, tax, FX losses"
    default: ""
    }
  }

  /// The type choices, by group: "Assets · Bank & cash".
  static var options: [SelectOption<String>] {
    AcAccountTypes.order.map { SelectOption($0.type, "\(t($0.group.label)) · \(t($0.label))") }
  }

  /// `suggestCode`: the next free code after the last account of the same type, e.g. 7600 → 7610.
  static func suggestCode(_ accounts: [JSONValue], type: String) -> String {
    let codes = accounts.filter { $0.str("type") == type }.compactMap { number($0.str("code")) }.sorted()
    let taken = Set(accounts.map { $0.str("code") })
    var next = codes.last.map { $0 + 10 } ?? 9000
    while taken.contains(Money.jsString(next)) { next += 1 }
    return Money.jsString(next)
  }

  /// `Number(code)` where it is finite: a blank code counts as 0.
  private static func number(_ code: String) -> Double? {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return 0 }
    guard let value = Double(trimmed), value.isFinite else { return nil }
    return value
  }
}

extension View {
  /// The account dialog while `account` is set: a new account (one the chart
  /// doesn't have yet) or one to edit.
  func awAccountDialog(_ account: Binding<JSONValue?>) -> some View {
    modifier(AwAccountDialog(account: account))
  }
}

private struct AwAccountDialog: ViewModifier {
  @Binding var account: JSONValue?
  @Environment(AppModel.self) private var model
  @State private var draft: JSONValue = .null
  @State private var deleting = false
  @State private var saving = false
  @State private var error: String?

  func body(content: Content) -> some View {
    content
      .webDialog(isPresented: shown, title: title, description: deleting ? deleteText : nil) {
        if deleting {
          AwFormError(text: error)
        } else {
          form
        }
      } footer: {
        footer
      }
      .onChange(of: account?.rid, initial: true) { _, _ in
        if let account {
          draft = account
          deleting = false
          saving = false
          error = nil
        }
      }
  }

  private var shown: Binding<Bool> {
    Binding(get: { account != nil }, set: { if !$0 { account = nil } })
  }

  private var original: JSONValue { account ?? .null }
  private var isNew: Bool { model.one.record(.accounts, original.rid) == nil }
  private var system: Bool { original.text("role") != nil }

  private var title: String {
    let name = ["code": original.str("code"), "name": localName(original)]
    if deleting { return t("Delete {code} {name}?", name) }
    return isNew ? t("New account") : t("Edit {code} {name}", name)
  }

  private var deleteText: String { t("The account has never been used, so nothing else changes.") }

  // MARK: The form

  private var type: String { draft.str("type") }
  private var bank: JSONValue { draft.obj("bank") ?? .object([:]) }
  private var iban: String { Kuwait.compactIban(bank.str("iban")) }
  private var ibanValid: Bool { iban.isEmpty || Kuwait.isValidIban(iban) }

  @ViewBuilder
  private var form: some View {
    if system {
      AcNotice(
        t(
          "Maham Books posts to this account automatically, so its type is fixed. You can rename it or change its code."
        ), icon: .lock, tone: .slate)
    }
    Field(t("Code")) {
      TextInput(text: text("code"), keyboard: .numbersAndPunctuation)
        .environment(\.layoutDirection, .leftToRight)
    }
    Field(t("Name")) {
      TextInput(text: text("name"))
    }
    Field(t("Name in Arabic"), hint: t("Shown in the Arabic interface and on Arabic reports."), optional: true) {
      TextInput(text: text("nameAr"))
        .environment(\.layoutDirection, .rightToLeft)
    }
    Field(t("Type"), hint: t(AwAccountTypeHints.hint(type))) {
      Select(selection: typeBinding, options: AwAccountTypeHints.options)
        .disabled(system)
    }
    Field(t("Description"), optional: true) {
      AwTextArea(text: text("description"))
    }
    if AcAccountTypes.isMoneyAccount(type) {
      bankDetails
    }
    if !system && !isNew {
      Switch(
        t("Archived"), description: t("Hidden from lists for new transactions. Its history stays in the reports."),
        isOn: archivedBinding)
    }
    AwFormError(text: error)
  }

  @ViewBuilder
  private var bankDetails: some View {
    Text(t("Bank details")).font(.web(14, .medium))
    Field(t("IBAN"), hint: ibanHint, error: ibanValid ? nil : t("This IBAN is not valid. Check it against a bank statement."), optional: true) {
      TextInput(text: ibanBinding, placeholder: "KW81 CBKU 0000 0000 0000 1234 5601 01")
        .environment(\.layoutDirection, .leftToRight)
    }
    Field(t("Bank"), optional: true) {
      TextInput(text: bankText("institution"))
    }
    Field(t("Account number"), optional: true) {
      TextInput(text: bankText("accountNumber"))
        .environment(\.layoutDirection, .leftToRight)
    }
    Field(t("BIC / SWIFT"), optional: true) {
      TextInput(text: bankText("bic"))
        .environment(\.layoutDirection, .leftToRight)
    }
  }

  /// The bank an IBAN names, or how a Kuwaiti IBAN looks.
  private var ibanHint: String {
    if !iban.isEmpty, ibanValid, let known = Kuwait.bankFromIban(iban) {
      return LanguageStore.shared.isArabic ? known.name.ar : known.name.en
    }
    return t("Kuwaiti IBANs have 30 characters and start with KW.")
  }

  @ViewBuilder
  private var footer: some View {
    if deleting {
      WebButton(t("Cancel"), variant: .outline) {
        deleting = false
        error = nil
      }
      WebButton(t("Delete"), variant: .danger, loading: saving) { remove() }
    } else {
      if !isNew && !system {
        WebButton(t("Delete"), variant: .ghost) { askDelete() }
      }
      WebButton(t("Cancel"), variant: .outline) { account = nil }
      WebButton(isNew ? t("Create account") : t("Save"), loading: saving) { save() }
        .disabled(!ibanValid)
    }
  }

  // MARK: Bindings

  private func set(_ key: String, _ value: JSONValue) {
    var fields = draft.object ?? [:]
    fields[key] = value
    draft = .object(fields)
  }

  private func text(_ key: String) -> Binding<String> {
    Binding(get: { draft.str(key) }, set: { set(key, .string($0)) })
  }

  private var typeBinding: Binding<String> {
    Binding(get: { type }, set: { set("type", .string($0)) })
  }

  private var archivedBinding: Binding<Bool> {
    Binding(get: { draft.flag("archived") }, set: { set("archived", .bool($0)) })
  }

  private func setBank(_ key: String, _ value: String) {
    var fields = bank.object ?? [:]
    for name in ["institution", "accountNumber", "iban", "bic"] where fields[name] == nil {
      fields[name] = .string("")
    }
    fields[key] = .string(value)
    set("bank", .object(fields))
  }

  private func bankText(_ key: String) -> Binding<String> {
    Binding(get: { bank.str(key) }, set: { setBank(key, $0) })
  }

  /// The IBAN as typed; once it is valid, a Kuwaiti one fills in its bank and SWIFT code.
  private var ibanBinding: Binding<String> {
    Binding(
      get: { bank.str("iban") },
      set: { typed in
        setBank("iban", typed)
        let compact = Kuwait.compactIban(typed)
        guard !compact.isEmpty, Kuwait.isValidIban(compact), let found = Kuwait.bankFromIban(compact) else { return }
        if bank.str("institution").isEmpty {
          setBank("institution", LanguageStore.shared.isArabic ? found.name.ar : found.name.en)
        }
        if bank.str("bic").isEmpty { setBank("bic", found.swift) }
      })
  }

  // MARK: Saving

  private func save() {
    var fields = draft.object ?? [:]
    // Only bank, cash and card accounts keep bank details.
    if !AcAccountTypes.isMoneyAccount(type) || draft.obj("bank") == nil { fields["bank"] = .null }
    let input = JSONValue.object(fields)
    let created = isNew
    saving = true
    error = nil
    Task {
      let saved = await AwSave.run(model, failed: { error = $0 }) { ctx, _ in try AwAccounts.save(ctx, input) }
      saving = false
      guard saved != nil else { return }
      model.confirm(created ? t("Account created") : t("Account saved"))
      account = nil
    }
  }

  private func askDelete() {
    let target = original
    error = nil
    Task {
      let used = await AwSave.run(model, failed: { error = $0 }) { ctx, _ in AwAccounts.inUse(ctx, target) }
      if used == true {
        error = t("This account is used by transactions or settings. Archive it instead.")
      } else if used == false {
        deleting = true
      }
    }
  }

  private func remove() {
    let id = original.rid
    saving = true
    Task {
      let deleted = await AwSave.perform(model, failed: { error = $0 }) { ctx, _ in try AwAccounts.delete(ctx, id: id) }
      saving = false
      if deleted {
        model.confirm(t("Account deleted"))
        account = nil
      }
    }
  }
}
