import MahamKit
import SwiftUI

// Settings sections changed natively (`src/pages/settings`): each edits a
// copy of the company record and saves it as the web's `useCompanyDraft`
// does (`saveCompany`, after the page's own change), or saves at once what
// the web saves at once (taxes on or off, the AI assistant, the app
// layout, tax rates, the register's extras).

@MainActor
enum SwSettings {
  /// The sections changed here; the others show their values.
  static let native: Set<String> = [
    "company", "compliance", "documents", "numbering", "emails", "labels", "taxes", "accounting", "ai",
  ]

  /// The section's own editor, when it has one.
  @ViewBuilder
  static func section(_ path: String) -> some View {
    switch path {
    case "company": SwCompanyEditor(change: SwProfileChange.tidy) { SwProfileFields(draft: $0) }
    case "compliance": SwComplianceSettings()
    case "documents": SwCompanyEditor(change: SwDocumentsChange.trimmed) { SwDocumentsFields(draft: $0) }
    case "numbering": SwCompanyEditor { SwNumberingFields(draft: $0) }
    case "emails": SwCompanyEditor { SwEmailFields(draft: $0) }
    case "labels": SwCompanyEditor { SwLanguageFields(draft: $0) }
    case "taxes": SwTaxSettings()
    case "accounting": SwCompanyEditor { SwAccountingFields(draft: $0) }
    case "ai": SwAiSettings()
    default: EmptyView()
    }
  }

  /// Math.round(n) of JavaScript.
  static func round(_ value: Double) -> Double { (value + 0.5).rounded(.down) }
}

// MARK: The company's draft

/// A copy of the company record the section's fields edit, saved with Save
/// (`useCompanyDraft`): the page's change (`change`, which may refuse with
/// the web's words), then `saveCompany`. It follows the company while
/// nothing is changed.
struct SwCompanyEditor<Fields: View>: View {
  let change: (JSONValue) throws -> JSONValue
  let fields: (Binding<JSONValue>) -> Fields
  @Environment(AppModel.self) private var model
  @State private var draft: JSONValue = .null
  @State private var base: JSONValue = .null
  @State private var saving = false

  init(
    change: @escaping (JSONValue) throws -> JSONValue = { $0 },
    @ViewBuilder fields: @escaping (Binding<JSONValue>) -> Fields
  ) {
    self.change = change
    self.fields = fields
  }

  var body: some View {
    let company = model.one.company ?? .null
    let editable = SwAccess(model).edits && SwAccess.can(.companies)
    VStack(alignment: .leading, spacing: 24) {
      if draft != .null {
        fields($draft).disabled(!editable)
      }
      if editable && dirty {
        HStack(spacing: 8) {
          Spacer(minLength: 0)
          WebButton(t("Reset"), variant: .outline) { draft = base }
          WebButton(t("Save"), loading: saving) { save() }
        }
      }
    }
    .onChange(of: company, initial: true) { _, latest in
      if !dirty || base == .null {
        base = latest
        draft = latest
      }
    }
  }

  /// Changed from the company as it was opened (`JSON.stringify(draft) !== JSON.stringify(base)`).
  private var dirty: Bool { draft != base }

  private func save() {
    let edited = draft
    let change = self.change
    saving = true
    Task {
      let ok = await SwSave.run(model, done: t("Settings saved")) { ctx in
        let next = try change(edited)
        SwCompany.save(ctx, next)
      }
      saving = false
      if ok, let saved = model.one.company {
        base = saved
        draft = saved
      }
    }
  }
}

/// A company field of the draft at `path`.
@MainActor
private func swText(_ draft: Binding<JSONValue>, _ path: String...) -> Binding<String> {
  SwBind.text(draft, path)
}

/// A card of settings: its title and description, then its fields.
struct SwSettingsCard<Content: View>: View {
  let title: String
  var description: String?
  let content: Content

  init(_ title: String, description: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.description = description
    self.content = content()
  }

  var body: some View {
    Card {
      CardHeader(title, description: description)
      CardBody { content }
    }
  }
}

// MARK: Company profile

enum SwProfileChange {
  /// The profile as `CompanySettings` saves it: a name needed, a Kuwaiti
  /// phone written the Kuwaiti way (as it is on leaving the field), then
  /// `withTidyProfile` with the types known here.
  static func tidy(_ draft: JSONValue) throws -> JSONValue {
    if SwText.trim(draft["name"]?.string).isEmpty { throw WriteFailure("Enter the name of your business.") }
    var company = draft
    let phone = draft["phone"]?.string ?? ""
    if inKuwait(draft), !SwText.trim(phone).isEmpty,
      let normalized = Kuwait.normalizeKuwaitPhone(Money.normalizeDigits(phone)), normalized != phone
    {
      company.set("phone", .string(normalized))
    }
    return SwCompany.withTidyProfile(company, known: SwCompany.typeOptions([draft]))
  }

  static func inKuwait(_ company: JSONValue) -> Bool {
    (company["address"]?["country"]?.string ?? "KW") == "KW"
  }
}

private struct SwProfileFields: View {
  @Binding var draft: JSONValue

  var body: some View {
    SwSettingsCard(t("Business"), description: t("Your names are printed at the top of every document.")) {
      Field(t("Company name")) { TextInput(text: swText($draft, "name")) }
      Field(t("Arabic name"), hint: t("Printed on Arabic invoices."), optional: true) {
        TextInput(text: swText($draft, "nameAr"))
      }
      Field(t("Legal name"), optional: true) { TextInput(text: swText($draft, "legalName")) }
    }
    SwSettingsCard(
      t("Registration"), description: t("Your CR number is printed on documents. The others are kept for your records.")
    ) {
      if SwProfileChange.inKuwait(draft) {
        Field(t("CR No."), hint: t("Commercial registration number")) {
          TextInput(text: swText($draft, "registrationNumber"))
        }
        ForEach(Self.kuwaitIds.indices, id: \.self) { index in
          Field(t(Self.kuwaitIds[index].label)) { TextInput(text: profile(Self.kuwaitIds[index].key)) }
        }
      } else {
        Field(t("Registration label")) { TextInput(text: swText($draft, "registrationLabel")) }
        Field(t("Registration number")) { TextInput(text: swText($draft, "registrationNumber")) }
        Field(t("Tax number label"), hint: t("e.g. VAT No., TRN, Tax ID")) { TextInput(text: swText($draft, "taxIdLabel")) }
        Field(t("Tax number")) { TextInput(text: swText($draft, "taxId")) }
      }
    }
    SwSettingsCard(t("Contact details")) {
      Field(t("Phone")) { TextInput(text: swText($draft, "phone"), keyboard: .phonePad) }
      Field(t("Email")) { TextInput(text: swText($draft, "email"), keyboard: .emailAddress) }
      Field(t("Website"), optional: true) { TextInput(text: swText($draft, "website"), keyboard: .URL) }
    }
    SwSettingsCard(t("Regional settings")) {
      Field(t("Date format")) {
        Select(selection: swText($draft, "dateFormat"), options: dateFormats)
      }
    }
  }

  private static let kuwaitIds: [(key: String, label: String)] = [
    ("licenceNumber", "Commercial licence no."), ("mofTaxCardNumber", "MOF tax card no."),
    ("pamFileNumber", "PAM file no."), ("pifssEmployerNumber", "PIFSS employer no."),
    ("kcciNumber", "KCCI membership no."), ("digitalCommerceNumber", "Digital commerce registration no."),
  ]

  private var dateFormats: [SelectOption<String>] {
    Format.dateFormats.map { SelectOption($0.value.rawValue, t($0.label)) }
  }

  /// A field of the Kuwaiti profile (`setProfile`: the profile with its defaults, then the change).
  private func profile(_ key: String) -> Binding<String> {
    Binding(
      get: { KuwaitRules.kuwaitProfile(draft)[key]?.string ?? "" },
      set: { value in
        var kuwait = KuwaitRules.kuwaitProfile(draft).object ?? [:]
        kuwait[key] = .string(value)
        draft.set("kuwait", .object(kuwait))
      })
  }
}

// MARK: Invoice defaults

enum SwDocumentsChange {
  /// `withVouchers(c, { lines: trimmed })` when the vouchers have signature lines.
  static func trimmed(_ draft: JSONValue) throws -> JSONValue {
    guard case .some(.object(var vouchers)) = draft["vouchers"], let lines = vouchers["lines"], !lines.isNull else {
      return draft
    }
    func trim(_ list: JSONValue?) -> JSONValue {
      let trimmed = (list?.array ?? []).map { line -> JSONValue in
        let fields: [String: JSONValue] = [
          "en": .string(SwText.trim(line["en"]?.string)), "ar": .string(SwText.trim(line["ar"]?.string)),
        ]
        return .object(fields)
      }
      return .array(trimmed)
    }
    let both: [String: JSONValue] = ["in": trim(lines["in"]), "out": trim(lines["out"])]
    vouchers["lines"] = .object(both)
    var company = draft
    company.set("vouchers", .object(vouchers))
    return company
  }
}

private struct SwDocumentsFields: View {
  @Binding var draft: JSONValue

  var body: some View {
    SwSettingsCard(t("Currency and paper"), description: t("Date and number formats are in the company profile.")) {
      Field(t("Paper size")) {
        Select(
          selection: swText($draft, "defaults", "pageSize"),
          options: [SelectOption("A4", "A4"), SelectOption("LETTER", "Letter")])
      }
    }
    SwSettingsCard(t("Due dates")) {
      Field(t("Invoice payment terms (days)")) { SwNumberField(value: days("paymentTermsDays"), blankZero: false) }
      Field(t("Quotes valid for (days)")) { SwNumberField(value: days("quoteValidDays"), blankZero: false) }
    }
    SwSettingsCard(
      t("Default text"), description: t("Filled in on new documents; you can still change it on each one.")
    ) {
      area("invoiceNotes", t("Invoice notes"))
      area("invoiceTerms", t("Invoice terms"))
      Field(t("Quote introduction")) { TextInput(text: swText($draft, "defaults", "quoteIntro")) }
      area("quoteNotes", t("Quote notes"))
      area("quoteTerms", t("Quote terms"))
      area("creditNotes", t("Credit note notes"))
      area("creditTerms", t("Credit note terms"))
      Field(t("Footer")) { TextInput(text: swText($draft, "defaults", "footer")) }
    }
  }

  private func area(_ key: String, _ label: String) -> some View {
    Field(label) { SwTextArea(text: swText($draft, "defaults", key)) }
  }

  /// Whole days, never below 0.
  private func days(_ key: String) -> Binding<Double> {
    Binding(
      get: { draft["defaults"]?[key]?.double ?? 0 },
      set: { draft = SwBind.set(draft, ["defaults", key], .number(max(0, SwSettings.round($0)))) })
  }
}

// MARK: Numbering

private struct SwNumberingFields: View {
  @Binding var draft: JSONValue
  @Environment(AppModel.self) private var model

  private static let kinds: [(key: String, label: String)] = SuSettings.numbered

  var body: some View {
    let ready = model.one.cloud?.has("approvals") ?? true
    let onNow = model.one.company?["defaults"]?["numberOnIssue"] == .bool(true)
    SwSettingsCard(
      t("When invoices get their number"),
      description: t(
        "Numbers are never given twice: a void invoice keeps its number, and an invoice issued in place of one gets a new number that says which it replaces."
      )
    ) {
      if !ready {
        Text(
          t("The cloud needs the latest database script first. Ask the owner of the company to run it.")
            + (onNow
              ? " "
                + t(
                  "Until it has run, turn this off: a device still on an older version could issue a draft without its number."
                ) : ""))
      }
      Switch(t("Number invoices and credit notes when they are issued"), isOn: SwBind.flag($draft, ["defaults", "numberOnIssue"]))
        .disabled(!ready && !onNow)
    }
    SwSettingsCard(t("Number formats"), description: t("How new numbers are built. Numbers already used are skipped.")) {
      ForEach(Self.kinds.indices, id: \.self) { index in
        rule(Self.kinds[index].key, label: t(Self.kinds[index].label))
      }
    }
  }

  private func ruleOf(_ key: String) -> JSONValue {
    swPresent(draft["numbering"]?[key]) ?? Defaults.defaultNumbering()[key] ?? .object([:])
  }

  private func setRule(_ key: String, _ patch: [String: JSONValue]) {
    var rule = ruleOf(key).object ?? [:]
    for (field, value) in patch { rule[field] = value }
    draft = SwBind.set(draft, ["numbering", key], .object(rule))
  }

  private func rule(_ key: String, label: String) -> some View {
    let current = NumberingRule(ruleOf(key))
    let preview = Numbering.previewNumber(current, ISODates.today())
    return VStack(alignment: .leading, spacing: 8) {
      Text(label).font(.web(14, .semibold))
      Text("\(t("Next:")) \(preview)").font(.web(12, tabular: true))
      Field(t("Pattern")) {
        TextInput(
          text: Binding(get: { current.pattern }, set: { setRule(key, ["pattern": .string($0)]) }))
      }
      HStack(spacing: 8) {
        Field(t("Digits")) {
          SwNumberField(
            value: Binding(
              get: { current.padding },
              set: { setRule(key, ["padding": .number(min(10, max(0, SwSettings.round($0))))]) }),
            blankZero: false)
        }
        Field(t("Next counter")) {
          SwNumberField(
            value: Binding(get: { current.next }, set: { setRule(key, ["next": .number(max(1, SwSettings.round($0)))]) }),
            blankZero: false)
        }
      }
      Field(t("Restart counter")) {
        Select(
          selection: Binding(get: { current.reset }, set: { setRule(key, ["reset": .string($0), "period": ""]) }),
          options: [
            SelectOption("never", t("Never")), SelectOption("yearly", t("Every year")),
            SelectOption("monthly", t("Every month")),
          ])
      }
    }
    .padding(.bottom, 8)
  }
}

/// A present value (neither missing nor null).
func swPresent(_ value: JSONValue?) -> JSONValue? {
  guard let value, !value.isNull else { return nil }
  return value
}

// MARK: Email templates

private struct SwEmailFields: View {
  @Binding var draft: JSONValue
  @State private var kind = "invoice"

  var body: some View {
    SwSettingsCard(
      t("Email templates"),
      description: t("Used when you send documents from the app. Your email program opens with the message ready.")
    ) {
      Segmented(
        selection: $kind,
        options: [
          SegmentOption("invoice", t("Invoice")), SegmentOption("quote", t("Quote")),
          SegmentOption("credit", t("Credit note")), SegmentOption("reminder", t("Reminder")),
          SegmentOption("payment", t("Receipt")),
        ])
      Field(t("Subject")) { TextInput(text: swText($draft, "emailTemplates", kind, "subject")) }
      Field(t("Message")) { SwTextArea(text: swText($draft, "emailTemplates", kind, "body"), lines: 8) }
    }
  }
}

// MARK: Language & wording

private struct SwLanguageFields: View {
  @Binding var draft: JSONValue

  private static let languages = ["en", "ar", "ar-en", "fr", "es", "de", "pt", "it", "nl"]

  var body: some View {
    SwSettingsCard(
      t("Document language"), description: t("Language of the words printed on invoices, quotes and credit notes.")
    ) {
      Field(t("Language")) {
        Select(
          selection: swText($draft, "language"),
          options: Self.languages.map { SelectOption($0, t(SuSettings.documentLanguage($0))) })
      }
    }
  }
}

// MARK: Accounting

private struct SwAccountingFields: View {
  @Binding var draft: JSONValue
  @Environment(AppModel.self) private var model

  /// `accountingSettings(company)`: the company's, or the defaults of its country.
  private var settings: [String: JSONValue] {
    if let own = swPresent(draft["accounting"])?.object { return own }
    let country = draft["address"]?["country"]?.string ?? ""
    let template: String
    switch country {
    case "GB": template = "uk"
    case "AE": template = "ae"
    case "KW", "": template = "kw"
    default: template = "generic"
    }
    return ["template": .string(template), "fiscalYearEnd": ["month": 12, "day": 31], "lockDate": .null]
  }

  private func setSettings(_ patch: [String: JSONValue]) {
    var next = settings
    for (key, value) in patch { next[key] = value }
    draft.set("accounting", .object(next))
  }

  private var month: Int { settings["fiscalYearEnd"]?["month"]?.int ?? 12 }
  private var day: Int { settings["fiscalYearEnd"]?["day"]?.int ?? 31 }

  var body: some View {
    SwSettingsCard(
      t("Financial year"),
      description: t("Reports use it for “this year”, and income and expenses start again at zero each year.")
    ) {
      Field(t("Year ends on (month)")) {
        Select(selection: monthBinding, options: (1...12).map { SelectOption($0, monthName($0)) })
      }
      Field(t("Day")) {
        Select(
          selection: dayBinding, options: (1...SuDates.daysIn(year: 2023, month: month)).map { SelectOption($0, "\($0)") })
      }
    }
    SwSettingsCard(
      t("Lock date"),
      description: t(
        "Once a period is reported or filed, lock it so nothing dated on or before the lock date can be added, changed or deleted."
      )
    ) {
      Field(t("Lock transactions up to and including")) {
        DateField(
          value: Binding(
            get: { settings["lockDate"]?.string ?? "" },
            set: { setSettings(["lockDate": $0.isEmpty ? .null : .string($0)]) }))
      }
      if settings["lockDate"]?.string != nil {
        WebButton(t("Remove lock"), variant: .outline, size: .sm) { setSettings(["lockDate": .null]) }
      }
    }
  }

  private func monthName(_ month: Int) -> String {
    let pattern: Format.DateFormat = "MMMM"
    return Format.date(SuDates.iso(2023, month, 1), format: pattern, locale: model.one.format.locale)
  }

  private var monthBinding: Binding<Int> {
    Binding(
      get: { month },
      set: { m in
        let fixed = min(day, SuDates.daysIn(year: 2023, month: m))
        setSettings(["fiscalYearEnd": ["month": .number(Double(m)), "day": .number(Double(fixed))]])
      })
  }

  private var dayBinding: Binding<Int> {
    Binding(
      get: { day },
      set: { d in setSettings(["fiscalYearEnd": ["month": .number(Double(month)), "day": .number(Double(d))]]) })
  }
}

// MARK: AI assistant

/// Settings → AI assistant: the owner or an admin switches it on or off, at once.
private struct SwAiSettings: View {
  @Environment(AppModel.self) private var model
  @State private var busy = false

  var body: some View {
    let on = model.one.company?["ai"]?["on"] == .bool(true)
    SwSettingsCard(t("AI assistant")) {
      Switch(t("Use the AI assistant"), isOn: Binding(get: { on }, set: { change($0) }))
        .disabled(!SwAccess(model).switchesApps || !SwAccess.can(.companies) || busy)
    }
  }

  private func change(_ on: Bool) {
    guard let company = model.one.company else { return }
    busy = true
    Task {
      await SwSave.run(model, done: t("Settings saved")) { ctx in
        SwCompany.save(ctx, SwCompany.withAiSwitch(company, on: on))
      }
      busy = false
    }
  }
}

/// Settings → Team: whether Maham Books is one app or three, for everyone (`AppLayoutSection`).
struct SwAppLayoutCard: View {
  @Environment(AppModel.self) private var model
  @State private var busy = false
  @State private var confirming = false

  var body: some View {
    let split = model.one.company?["appLayout"] == .string("split")
    let name = model.one.company.map { localName($0) } ?? ""
    SwSettingsCard(t("App layout"), description: t("The apps everyone in {company} sees.", ["company": name])) {
      Switch(
        t("Maham Sales and Maham Inventory as their own apps"),
        description: t(
          "Maham Sales has quotes, orders, invoices, payments received and customers; Maham Inventory has items and stock. Maham Books keeps purchases, cheques, banking, accounting and reports, with invoices under Receivables. Pages, addresses and records stay as they are."
        ), isOn: Binding(get: { split }, set: { asked($0) })
      )
      .disabled(!SwAccess(model).switchesApps || !SwAccess.can(.companies) || busy)
      if !SwAccess(model).switchesApps {
        Text(t("Only the owner or an admin changes the app layout.")).font(.web(14))
      }
    }
    .webDialog(isPresented: $confirming, title: t("Give Sales and Inventory their own apps?")) {
      Text(
        t(
          "Everyone in {company} sees Maham Sales, Maham Books and Maham Inventory in place of Maham Books, on each device once it syncs. Pages, addresses and records stay as they are. You can switch back at any time.",
          ["company": name]))
    } footer: {
      SwConfirmFooter(label: t("Switch on"), onCancel: { confirming = false }) {
        confirming = false
        change(true)
      }
    }
  }

  private func asked(_ on: Bool) {
    if on {
      confirming = true
    } else {
      change(false)
    }
  }

  private func change(_ split: Bool) {
    guard let company = model.one.company else { return }
    busy = true
    Task {
      await SwSave.run(model, done: t("App layout saved")) { ctx in
        SwCompany.save(ctx, SwCompany.withAppLayout(company, split: split))
      }
      busy = false
    }
  }
}
