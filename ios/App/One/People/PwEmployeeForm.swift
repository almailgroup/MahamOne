import MahamKit
import SwiftUI

// `/employees/new` and `/employees/:id/edit`: the employee form, saved with
// the port of the web's `saveEmployee` (numbers, KWD amounts to the fils,
// the drafts the company's letter templates ask for), refused when the
// record changed elsewhere after the form was opened.

/// The page that replaces the form once saved.
@MainActor
enum PwNav {
  static func replaceTop(_ router: ShellRouter, with route: Route) {
    if router.path.isEmpty {
      router.push(route)
    } else {
      router.path[router.path.count - 1] = route
    }
  }
}

struct PwEmployeeFormPage: View {
  let id: String?
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @State private var draft = PwDraft(nil)
  @State private var loaded = false
  @State private var missing = false
  @State private var openedAt: String?
  @State private var errors: [String: String] = [:]
  @State private var saving = false

  var body: some View {
    WebPage(spacing: 0) {
      if missing {
        PeNotFound(message: t("This employee could not be found."), back: t("Back to employees"))
      } else if loaded {
        PageHeader(title, breadcrumb: t("Employees"), onBreadcrumb: { router.back() })
        PwEmployeeSections(draft: $draft, errors: errors)
      } else {
        Card { DataLoadingRow() }
      }
    }
    .stickyActions {
      if loaded && !missing {
        WebButton(t("Cancel"), variant: .ghost) { router.back() }
        WebButton(t("Save employee"), loading: saving) { Task { await save() } }
      }
    }
    .onAppear(perform: load)
  }

  private var title: String {
    guard id != nil else { return t("New employee") }
    let name = localName(draft.text("name"), draft.fields["nameAr"]?.string)
    return t("Edit {name}", ["name": name.isEmpty ? draft.text("number") : name])
  }

  private func load() {
    guard !loaded, !missing else { return }
    let one = model.one
    guard let companyId = one.companyId else { return }
    if let id {
      guard let record = one.record(.employees, id), record.str("companyId") == companyId else {
        missing = true
        return
      }
      draft = PwDraft(record)
      openedAt = record.text("updatedAt")
    } else {
      draft = PwDraft(PwEmployees.create(companyId: companyId, today: ISODates.today()))
    }
    loaded = true
  }

  /// `validateEmployee`, and a number another employee has.
  private func validate() -> [String: String] {
    var found: [String: String] = [:]
    if draft.text("name").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      found["name"] = t("Enter the employee’s name.")
    }
    let iban = draft.text("iban")
    if !iban.trimmingCharacters(in: .whitespaces).isEmpty && !Kuwait.isValidIban(iban) {
      found["iban"] = t("This IBAN is not valid. Check the number.")
    }
    if draft.text("contractType") == "fixed" {
      let end = draft.text("contractEnd")
      if end.isEmpty {
        found["contractEnd"] = t("Enter the date the contract ends.")
      } else if !draft.text("hireDate").isEmpty && end < draft.text("hireDate") {
        found["contractEnd"] = t("The contract ends before the hire date.")
      }
    }
    if draft.text("status") == "left" {
      let leaving = draft.text("leavingDate")
      if !leaving.isEmpty && !draft.text("hireDate").isEmpty && leaving < draft.text("hireDate") {
        found["leavingDate"] = t("The leaving date is before the hire date.")
      }
      if draft.text("leavingReason").isEmpty { found["leavingReason"] = t("Choose the reason for leaving.") }
    }
    if let days = draft.fields["annualLeaveDays"]?.double, days > 0, days < 30 {
      found["annualLeaveDays"] = t("At least 30 days a year (art. 70).")
    }
    let number = draft.text("number").trimmingCharacters(in: .whitespaces).lowercased()
    if !number.isEmpty,
      model.one.records(.employees).contains(where: { $0.rid != draft.text("id") && $0.str("number").lowercased() == number })
    {
      found["number"] = t("Employee number {number} is already used.", ["number": draft.text("number")])
    }
    return found
  }

  private func save() async {
    errors = validate()
    if !errors.isEmpty {
      model.toast = Toast(kind: .error, message: t("Please fix the highlighted fields."))
      return
    }
    saving = true
    defer { saving = false }
    let input = draft.json
    let expected = id != nil ? openedAt : nil
    let link = model.one.pwLink
    let text = PwText.app
    guard
      let saved = await PwSave.run(model, { ctx in
        try PwEmployees.save(ctx, input, expectedUpdatedAt: expected, link: link, text: text)
      })
    else { return }
    model.confirm(t("{name} saved", ["name": localName(saved.str("name"), saved.text("nameAr"))]))
    PwNav.replaceTop(router, with: .employee(id: saved.rid))
  }
}

// MARK: - Sections

private struct PwEmployeeSections: View {
  @Binding var draft: PwDraft
  let errors: [String: String]

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      PwPersonalCard(draft: $draft, errors: errors)
      PwPapersCard(draft: $draft)
      if draft.text("category") == "expat" || draft.text("category") == "domestic" {
        PwResidencyCard(draft: $draft)
      }
      PwJobCard(draft: $draft, errors: errors)
      PwPayCard(draft: $draft, errors: errors)
      PwStatusCard(draft: $draft, errors: errors)
      Card {
        CardHeader(t("Notes"))
        CardBody {
          Field(nil, hint: t("Internal, never printed.")) {
            TextEditor(text: $draft.text("notes")).frame(minHeight: 88).modifier(InputChrome(focused: false))
          }
        }
      }
    }
    .padding(.bottom, 24)
  }
}

private enum PwEmployeeOptions {
  static let categories = ["kuwaiti", "gcc", "expat", "domestic"]
  static let statuses = ["active", "on_leave", "left"]
  static let payBases = ["monthly", "daily", "hourly", "piece"]
  static let articles = ["18", "17", "19", "20", "22", "24", "other"]

  @MainActor
  static func countries() -> [ComboOption] {
    let language = Localization.language == .ar ? "ar" : "en"
    return Geo.countryOptions(locale: language).map { ComboOption(value: $0.value, label: $0.label) }
  }
}

private struct PwPersonalCard: View {
  @Binding var draft: PwDraft
  let errors: [String: String]

  var body: some View {
    Card {
      CardHeader(t("Personal details"))
      CardBody {
        VStack(alignment: .leading, spacing: 16) {
          Field(t("Name (English)"), error: errors["name"]) { TextInput(text: $draft.text("name")) }
          Field(t("Name (Arabic)"), optional: true) { TextInput(text: $draft.text("nameAr")) }
          Field(t("Employee number"), hint: t("Left empty, the next number is given."), error: errors["number"]) {
            TextInput(text: $draft.text("number"), placeholder: t("Automatic"))
          }
          Field(t("Nationality")) {
            Combobox(selection: nationality, options: PwEmployeeOptions.countries())
          }
          Field(t("Category")) {
            Select(
              selection: $draft.text("category"),
              options: PwEmployeeOptions.categories.map { SelectOption($0, PePeople.categoryLabel($0)) })
          }
          Field(t("Date of birth"), optional: true) { DateField(value: $draft.day("birthDate")) }
          Field(t("Gender"), optional: true) {
            Select(
              selection: $draft.text("gender"),
              options: [SelectOption("", t("Not set")), SelectOption("male", t("Male")), SelectOption("female", t("Female"))])
          }
          Field(t("Mobile"), optional: true) { TextInput(text: $draft.text("phone"), keyboard: .phonePad) }
          Field(t("Email"), optional: true) { TextInput(text: $draft.text("email"), keyboard: .emailAddress) }
        }
      }
    }
  }

  private var nationality: Binding<String?> {
    Binding<String?>(
      get: { draft.text("nationality") },
      set: { draft.fields["nationality"] = .string($0 ?? "") })
  }
}

private struct PwPapersCard: View {
  @Binding var draft: PwDraft

  var body: some View {
    Card {
      CardHeader(t("Civil ID and passport"), description: t("Expiry dates appear in Compliance with reminders."))
      CardBody {
        VStack(alignment: .leading, spacing: 16) {
          Field(t("Civil ID number"), optional: true) { TextInput(text: $draft.text("civilId"), keyboard: .numberPad) }
          Field(t("Civil ID expiry"), optional: true) { DateField(value: $draft.day("civilIdExpiry")) }
          Field(t("Passport number"), optional: true) { TextInput(text: $draft.text("passportNumber")) }
          Field(t("Passport expiry"), optional: true) { DateField(value: $draft.day("passportExpiry")) }
        }
      }
    }
  }
}

private struct PwResidencyCard: View {
  @Binding var draft: PwDraft

  var body: some View {
    Card {
      CardHeader(t("Residency and work permit"))
      CardBody {
        VStack(alignment: .leading, spacing: 16) {
          Field(t("Residency article")) {
            Select(
              selection: $draft.text("residencyArticle"),
              options: PwEmployeeOptions.articles.map { SelectOption($0, PePeople.residencyArticleLabel($0)) })
          }
          Field(t("Residency number"), optional: true) { TextInput(text: $draft.text("residencyNumber")) }
          Field(t("Residency expiry"), optional: true) { DateField(value: $draft.day("residencyExpiry")) }
          Field(t("Work permit number"), optional: true) { TextInput(text: $draft.text("workPermitNumber")) }
          Field(t("Job title on the work permit"), hint: t("As registered with PAM."), optional: true) {
            TextInput(text: $draft.text("pamJobTitle"))
          }
          Field(t("Salary on the work permit"), optional: true) { PwNumberField(value: $draft.number("permitSalary")) }
          Field(t("Work permit expiry"), optional: true) { DateField(value: $draft.day("workPermitExpiry")) }
        }
      }
    }
  }
}

private struct PwJobCard: View {
  @Binding var draft: PwDraft
  let errors: [String: String]

  var body: some View {
    Card {
      CardHeader(t("Job and contract"))
      CardBody {
        VStack(alignment: .leading, spacing: 16) {
          Field(t("Job title (English)"), optional: true) { TextInput(text: $draft.text("jobTitle")) }
          Field(t("Job title (Arabic)"), optional: true) { TextInput(text: $draft.text("jobTitleAr")) }
          Field(t("Department"), optional: true) { TextInput(text: $draft.text("department")) }
          Field(t("Hire date")) { DateField(value: $draft.day("hireDate")) }
          Field(t("Probation ends"), optional: true) { DateField(value: $draft.day("probationEnd")) }
          Field(t("Contract")) {
            Select(
              selection: $draft.text("contractType"),
              options: [SelectOption("unlimited", t("Unlimited")), SelectOption("fixed", t("Fixed term"))])
          }
          if draft.text("contractType") == "fixed" {
            Field(t("Contract ends"), error: errors["contractEnd"]) { DateField(value: $draft.day("contractEnd")) }
          }
          Field(t("Annual leave days"), hint: t("At least 30 days a year (art. 70)."), error: errors["annualLeaveDays"], optional: true) {
            PwOptionalNumberField(value: ownDays)
          }
          if (draft.fields["annualLeaveDays"]?.double ?? 0) > 0 {
            Field(t("Annual leave days from"), optional: true) { DateField(value: $draft.day("annualLeaveDaysFrom")) }
          }
        }
      }
    }
  }

  private var ownDays: Binding<Double?> {
    Binding<Double?>(
      get: { draft.fields["annualLeaveDays"]?.double },
      set: { draft.fields["annualLeaveDays"] = $0.map(JSONValue.number) ?? .null })
  }
}

private struct PwPayCard: View {
  @Binding var draft: PwDraft
  let errors: [String: String]

  var body: some View {
    Card {
      CardHeader(t("Pay"))
      CardBody {
        VStack(alignment: .leading, spacing: 16) {
          Field(t("Pay basis")) {
            Select(
              selection: $draft.text("payBasis"),
              options: PwEmployeeOptions.payBases.map { SelectOption($0, PePeople.payBasisLabel($0)) })
          }
          Field(t("Basic salary")) { PwNumberField(value: $draft.number("basicSalary")) }
          PwAllowancesEditor(draft: $draft)
          Field(t("Bank"), optional: true) {
            Select(
              selection: $draft.text("bank"),
              options: [SelectOption("", t("Choose a bank…"))]
                + Kuwait.banks.map { SelectOption($0.code, Localization.language == .ar ? $0.name.ar : $0.name.en) })
          }
          Field(t("IBAN"), hint: t("The IBAN is used for salaries while there is one."), error: errors["iban"], optional: true) {
            TextInput(text: $draft.text("iban"))
          }
          Field(
            t("Account or salary card number"),
            hint: t("For salaries paid to a salary card or an account without an IBAN."), optional: true
          ) {
            TextInput(text: $draft.text("accountNumber"))
          }
          Field(t("PIFSS number"), hint: t("Social security registration with PIFSS."), optional: true) {
            TextInput(text: $draft.text("pifssNumber"))
          }
        }
      }
    }
  }
}

private struct PwAllowancesEditor: View {
  @Binding var draft: PwDraft

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(t("Allowances")).font(.web(14, .medium))
      ForEach(allowances.indices, id: \.self) { index in
        PwAllowanceRow(allowance: binding(index)) { remove(index) }
      }
      WebButton(t("Add allowance"), icon: .plus, variant: .outline, size: .sm) {
        draft.fields["allowances"] = .array(allowances + [PwEmployees.newAllowance()])
      }
    }
  }

  private var allowances: [JSONValue] { draft.fields["allowances"]?.array ?? [] }

  private func binding(_ index: Int) -> Binding<PwDraft> {
    Binding<PwDraft>(
      get: { PwDraft(allowances.indices.contains(index) ? allowances[index] : nil) },
      set: { changed in
        var list = allowances
        guard list.indices.contains(index) else { return }
        list[index] = changed.json
        draft.fields["allowances"] = .array(list)
      })
  }

  private func remove(_ index: Int) {
    var list = allowances
    guard list.indices.contains(index) else { return }
    list.remove(at: index)
    draft.fields["allowances"] = .array(list)
  }
}

private struct PwAllowanceRow: View {
  @Binding var allowance: PwDraft
  let onRemove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Field(t("Allowance (English)")) { TextInput(text: $allowance.text("name")) }
      Field(t("Allowance (Arabic)"), optional: true) { TextInput(text: $allowance.text("nameAr")) }
      Field(t("Amount")) { PwNumberField(value: $allowance.number("amount")) }
      Switch(t("Counts toward the end-of-service wage"), isOn: $allowance.flag("countsForEos"))
      WebButton(t("Remove allowance"), icon: .trash2, variant: .ghost, size: .sm, action: onRemove)
    }
    .padding(12)
    .modifier(InputChrome(focused: false))
  }
}

private struct PwStatusCard: View {
  @Binding var draft: PwDraft
  let errors: [String: String]

  var body: some View {
    Card {
      CardHeader(t("Employment status"))
      CardBody {
        VStack(alignment: .leading, spacing: 16) {
          Field(t("Status")) {
            Select(
              selection: $draft.text("status"),
              options: PwEmployeeOptions.statuses.map { SelectOption($0, PePeople.statusLabel($0)) })
          }
          if draft.text("status") == "left" {
            Field(t("Leaving date"), error: errors["leavingDate"]) { DateField(value: $draft.day("leavingDate")) }
            Field(t("Reason for leaving"), error: errors["leavingReason"]) {
              Select(
                selection: $draft.text("leavingReason"),
                options: [SelectOption("", t("Choose a reason"))]
                  + PePeople.leavingReasons.map { SelectOption($0, PePeople.leavingReasonLabel($0)) })
            }
          }
        }
      }
    }
  }
}
