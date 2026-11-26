import LocalAuthentication
import MahamKit
import SwiftUI

// Settings (`src/pages/settings`, `src/features/shell/settings-sections.tsx`):
// the sections in a row that scrolls sideways, as on a phone, each with its
// current values. The company's settings are changed on the web ("Edit on
// the web" opens the section there); this iPhone's own are changed here:
// the language, the appearance, the Face ID lock and signing out.

/// A section of Settings.
struct SuSettingsItem: Identifiable, Sendable {
  let path: String
  let label: String
  let icon: Icon
  var id: String { path }
}

enum SuSettings {
  /// The sections, in the web's order (`SETTINGS_GROUPS`).
  static let items: [SuSettingsItem] = [
    SuSettingsItem(path: "company", label: "Company profile", icon: .building2),
    SuSettingsItem(path: "companies", label: "Companies", icon: .layers),
    SuSettingsItem(path: "links", label: "Links", icon: .link2),
    SuSettingsItem(path: "compliance", label: "Compliance and files", icon: .shieldCheck),
    SuSettingsItem(path: "account", label: "Your account", icon: .userRound),
    SuSettingsItem(path: "alerts", label: "Email alerts", icon: .bellRing),
    SuSettingsItem(path: "team", label: "Team", icon: .usersRound),
    SuSettingsItem(path: "approvals", label: "Approvals", icon: .clipboardCheck),
    SuSettingsItem(path: "ai", label: "AI assistant", icon: .sparkles),
    SuSettingsItem(path: "cloud", label: "Cloud and sync", icon: .cloud),
    SuSettingsItem(path: "documents", label: "Invoice defaults", icon: .fileCog),
    SuSettingsItem(path: "numbering", label: "Numbering", icon: .hash),
    SuSettingsItem(path: "items", label: "Items and units", icon: .package),
    SuSettingsItem(path: "emails", label: "Email templates", icon: .mail),
    SuSettingsItem(path: "labels", label: "Language & wording", icon: .languages),
    SuSettingsItem(path: "payments", label: "Payment details", icon: .wallet),
    SuSettingsItem(path: "taxes", label: "Taxes", icon: .percent),
    SuSettingsItem(path: "accounting", label: "Accounting", icon: .bookOpen),
    SuSettingsItem(path: "import", label: "Import data", icon: .fileUp),
    SuSettingsItem(path: "data", label: "Backup & data", icon: .database),
    SuSettingsItem(path: "appearance", label: "Appearance", icon: .palette),
  ]

  /// The section asked for; any other opens the company profile, as on the web.
  static func resolve(_ section: String?) -> String {
    guard let section, items.contains(where: { $0.path == section }) else { return "company" }
    return section
  }

  /// Numbered kinds, as Settings → Numbering lists them.
  static let numbered: [(key: String, label: String)] = [
    ("invoice", "Invoices"), ("quote", "Quotes"), ("credit", "Credit notes"), ("proforma", "Proforma invoices"),
    ("sales_order", "Sales orders"), ("delivery_note", "Delivery notes"), ("payment", "Payments received"),
    ("client", "Clients and vendors"), ("product", "Item codes (SKU)"), ("purchase_order", "Purchase orders"),
    ("bill", "Bills"), ("vendor_credit", "Vendor credits"), ("payment_made", "Payments made"),
    ("expense", "Expenses"), ("journal", "Manual journals"),
  ]

  /// The languages documents print in.
  static func documentLanguage(_ value: String) -> String {
    switch value {
    case "ar-en": "Arabic and English"
    case "ar": "Arabic"
    case "fr": "French"
    case "es": "Spanish"
    case "de": "German"
    case "pt": "Portuguese"
    case "it": "Italian"
    case "nl": "Dutch"
    default: "English"
    }
  }

  /// The chart of accounts a company started from.
  static func chartName(_ template: String) -> String {
    switch template {
    case "kw": "Kuwait"
    case "uk": "United Kingdom"
    case "ae": "United Arab Emirates"
    default: "Standard chart"
    }
  }

  /// Switched on or off, in words, and the colour the web gives it.
  static func switched(_ label: String, _ on: Bool) -> InfoRow {
    let tone: Token = on ? Token.emerald(700) : Token.slate(500)
    return InfoRow(label, on ? t("Switched on") : t("Switched off"), strong: on, tone: tone)
  }
}

/// `/settings`, `/settings/:section`.
struct SuSettingsPage: View {
  let section: String?
  @State private var current: String
  @Environment(AppModel.self) private var model

  init(section: String?) {
    self.section = section
    _current = State(initialValue: SuSettings.resolve(section))
  }

  var body: some View {
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(t("Settings"), description: t("Your company details and how your documents are created."))
      SuSettingsTabs(current: $current)
        .padding(.bottom, 24)
      SuSettingsSectionView(path: current)
    }
  }
}

/// The sections in one row that scrolls sideways, the open one kept in view.
private struct SuSettingsTabs: View {
  @Binding var current: String
  @Environment(\.palette) private var palette

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 4) {
          ForEach(SuSettings.items) { item in
            tab(item).id(item.path)
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
      }
      .padding(.horizontal, -16)
      .onChange(of: current, initial: true) { _, path in
        withAnimation(WebMotion.standard) { proxy.scrollTo(path, anchor: .center) }
      }
    }
  }

  private func tab(_ item: SuSettingsItem) -> some View {
    let active = item.path == current
    let shape = RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous)
    return Button {
      guard !active else { return }
      Haptics.play(.selection)
      current = item.path
    } label: {
      HStack(spacing: 10) {
        IconView(item.icon, size: 16).foregroundStyle(active ? palette.primary(600) : palette.slate(400))
        Text(t(item.label)).lineLimit(1)
      }
      .font(.web(14, .medium))
      .foregroundStyle(active ? palette.primary(700) : palette.slate(600))
      .padding(.horizontal, 12)
      .frame(minHeight: 44)
      .background {
        if active {
          shape.fill(palette.surface).boxShadow(WebShadow.xs, in: shape)
        }
      }
      .overlay {
        if active { shape.strokeBorder(palette.slate(200), lineWidth: 1) }
      }
      .contentShape(shape)
    }
    .buttonStyle(PressedFill(radius: WebRadius.md, color: .slate(100)))
    .accessibilityAddTraits(active ? .isSelected : [])
  }
}

/// A section's cards.
private struct SuSettingsSectionView: View {
  let path: String
  @Environment(AppModel.self) private var model

  var body: some View {
    let values = SuSettingsValues(model: model)
    VStack(alignment: .leading, spacing: 24) {
      switch path {
      case "account":
        SuAccountSettings()
      case "appearance":
        SuAppearanceSettings()
      case "cloud":
        SuCloudSettings()
        editButton
      default:
        ForEach(values.cards(path)) { card in
          SuValuesCard(card.title, description: card.description, rows: card.rows)
        }
        editButton
      }
    }
  }

  /// Opens the section on the web, where it is changed (viewers only look).
  @ViewBuilder
  private var editButton: some View {
    if !SuRole(model).readOnly {
      HStack {
        Spacer(minLength: 0)
        SuWebButton(t("Edit on the web"), path: "/settings/\(path)", size: .md)
      }
    }
  }
}

/// A card of a section: its title, description and values.
struct SuSettingsCard: Identifiable {
  let title: String
  var description: String?
  var rows: [InfoRow]
  var id: String { title }

  init(_ title: String, description: String? = nil, rows: [InfoRow]) {
    self.title = title
    self.description = description
    self.rows = rows
  }
}

/// The company's settings, read from its record, section by section.
@MainActor
struct SuSettingsValues {
  let one: OneData
  let company: JSONValue?
  let role: SuRole
  let companyName: String
  let members: Int
  let companies: [Company]

  init(model: AppModel) {
    let record = model.one.company
    one = model.one
    company = record
    role = SuRole(model)
    companyName = record.map { localName($0) } ?? (model.business.company?.name ?? "")
    members = model.business.company?.members ?? 1
    companies = model.business.companies
  }

  private var format: CompanyFormat { one.format }
  private func str(_ key: String) -> String { company?.str(key) ?? "" }
  private func obj(_ key: String) -> JSONValue? { company?.obj(key) }

  func cards(_ path: String) -> [SuSettingsCard] {
    switch path {
    case "company": companyCards
    case "companies": companiesCards
    case "links": linksCards
    case "compliance": complianceCards
    case "alerts": alertsCards
    case "team": teamCards
    case "approvals": approvalsCards
    case "ai": aiCards
    case "documents": documentsCards
    case "numbering": numberingCards
    case "items": itemsCards
    case "emails": emailsCards
    case "labels": labelsCards
    case "payments": paymentsCards
    case "taxes": taxesCards
    case "accounting": accountingCards
    case "import": importCards
    case "data": dataCards
    default: companyCards
    }
  }

  // MARK: Business

  private var companyCards: [SuSettingsCard] {
    let kuwait = KuwaitRules.kuwaitProfile(company)
    let form = KuwaitRules.legalForms.first { $0.value == kuwait.str("legalForm") }
    let formName = form.map { LanguageStore.shared.isArabic ? $0.labelAr : $0.label } ?? ""
    let foreign = kuwait.num("foreignOwnershipPercent")
    let branding = obj("branding")
    let template = SuTemplate.all.first { $0.id == (branding?.text("templateId") ?? SuTemplate.defaultId) }
    return [
      SuSettingsCard(
        t("Business"), description: t("Your names are printed at the top of every document."),
        rows: [
          InfoRow(t("Company name"), str("name")), InfoRow(t("Arabic name"), str("nameAr")),
          InfoRow(t("Legal name"), str("legalName")),
        ]),
      SuSettingsCard(
        t("Registration"),
        description: t("Your CR number is printed on documents. The others are kept for your records."),
        rows: [
          InfoRow(t("Legal form"), formName), InfoRow(t("Commercial licence no."), kuwait.str("licenceNumber")),
          InfoRow(t("CR No."), str("registrationNumber")), InfoRow(t("Tax number"), str("taxId")),
          InfoRow(t("PAM file no."), kuwait.str("pamFileNumber")),
          InfoRow(t("PIFSS employer no."), kuwait.str("pifssEmployerNumber")),
          InfoRow(t("MOF tax card no."), kuwait.str("mofTaxCardNumber")),
          InfoRow(t("KCCI membership no."), kuwait.str("kcciNumber")),
          InfoRow(t("Digital commerce registration no."), kuwait.str("digitalCommerceNumber")),
          InfoRow(t("Foreign ownership (%)"), foreign > 0 ? format.percent(foreign) : ""),
        ]),
      SuSettingsCard(
        t("Contact details"),
        rows: [
          InfoRow(t("Email"), str("email")), InfoRow(t("Phone"), str("phone")), InfoRow(t("Website"), str("website")),
        ]),
      SuSettingsCard(t("Address"), rows: [InfoRow(t("Address"), address)]),
      SuSettingsCard(
        t("Branding"),
        description: t("Your logo and colour on documents, and the stamp and signature that make them official."),
        rows: [
          InfoRow(t("Brand colour"), branding?.str("accentColor") ?? ""),
          InfoRow(t("Template"), template.map { t($0.name) } ?? ""),
        ]),
      SuSettingsCard(
        t("Regional settings"),
        description: t("How amounts and dates are written, your working week and public holidays."),
        rows: [
          InfoRow(t("Default currency"), format.currency),
          InfoRow(t("Date format"), format.date(DocRules.today)),
          InfoRow(t("Number format"), format.money(1234.5)),
        ]),
    ]
  }

  /// The address on its lines.
  private var address: String {
    guard let address = obj("address") else { return "" }
    let street = suJoin(
      ["block", "street", "avenue", "building", "floor", "unit"].map { address.text($0) }, ", ")
    let lines: [String?] = [
      address.text("line1"), address.text("line2"), street, suJoin([address.text("city"), address.text("state")], ", "),
      suJoin([address.text("postalCode"), address.text("country")], " "),
    ]
    return suJoin(lines, "\n")
  }

  private var companiesCards: [SuSettingsCard] {
    [
      SuSettingsCard(
        t("Companies"), description: t("Run several businesses or brands, each with its own clients, numbering and branding."),
        rows: companies.map { InfoRow($0.name, t($0.role.title)) })
    ]
  }

  private var linksCards: [SuSettingsCard] {
    let links = company?.list("links") ?? []
    let rows = links.map { link in
      InfoRow(localName(link, key: "label"), link.str("url"))
    }
    return [
      SuSettingsCard(
        t("Links in the sidebar"),
        description: t(
          "Your other tools, such as a task manager. They show in the sidebar for everyone in this company and open in a new tab."
        ), rows: rows)
    ]
  }

  private var complianceCards: [SuSettingsCard] {
    let settings = one.record(.peopleSettings, company?.rid ?? "") ?? one.records(.peopleSettings).first
    var rows = [
      SuSettings.switched(t("Find files and papers"), company?["fileFinder"]?.bool == true),
      SuSettings.switched(t("Contracts, customers and vehicles"), company?["registerExtras"]?.bool == true),
    ]
    if role.seesPeople {
      rows.append(SuSettings.switched(t("Check drivers’ licences"), settings?["drivingLicences"]?.bool == true))
    }
    return [
      SuSettingsCard(
        t("Compliance and files"),
        description: t(
          "Reminders and deadlines, drivers’ licences, contracts, customers’ papers and vehicles in the register, and the Files page with files and papers in search, for Books too."
        ), rows: rows)
    ]
  }

  // MARK: Account and team

  private var alertsCards: [SuSettingsCard] {
    [
      SuSettingsCard(
        t("Email alerts"),
        description: t(
          "Every morning at 8:00 (Kuwait time) when something in {company} needs attention, and every Sunday a summary of everything still open.",
          ["company": companyName]), rows: [])
    ]
  }

  private var teamCards: [SuSettingsCard] {
    let roleName = role.role.map { t($0.title) } ?? ""
    return [
      SuSettingsCard(
        t("Team"), description: t("Everyone here works on {company} from their own device.", ["company": companyName]),
        rows: [InfoRow(t("Role"), roleName), InfoRow(t("Members"), format.count(members))])
    ]
  }

  private var approvalsCards: [SuSettingsCard] {
    let rules = obj("approvalRules")
    let types = (rules?.list("documentTypes") ?? []).compactMap(\.string)
    let cheques = rules?.obj("cheques")
    return [
      SuSettingsCard(
        t("Approvals"),
        description: t("Changes to issued invoices and credit notes that wait for the owner (the Super Admin)."),
        rows: [
          SuSettings.switched(t("Issued invoices need an approver to change"), types.contains("invoice")),
          SuSettings.switched(t("Issued credit notes need an approver to change"), types.contains("credit")),
        ]),
      SuSettingsCard(
        t("Cheques"),
        rows: [
          SuSettings.switched(t("Cheques issued"), cheques?.flag("issued") ?? false),
          SuSettings.switched(t("Security cheques given"), cheques?.flag("securityOut") ?? false),
          SuSettings.switched(t("Cheques received"), cheques?.flag("received") ?? false),
        ]),
      SuSettingsCard(t("Pay runs"), rows: [SuSettings.switched(t("Pay runs"), rules?.flag("payroll") ?? false)]),
    ]
  }

  private var aiCards: [SuSettingsCard] {
    [
      SuSettingsCard(
        t("AI assistant"),
        rows: [SuSettings.switched(t("Use the AI assistant"), obj("ai")?.flag("on") ?? false)])
    ]
  }

  // MARK: Documents

  private var documentsCards: [SuSettingsCard] {
    let defaults = obj("defaults")
    return [
      SuSettingsCard(
        t("Currency and paper"), description: t("Date and number formats are in the company profile."),
        rows: [
          InfoRow(t("Default currency"), format.currency),
          InfoRow(t("Paper size"), defaults?.str("pageSize") == "LETTER" ? "Letter" : "A4"),
        ]),
      SuSettingsCard(
        t("Due dates"),
        rows: [
          InfoRow(t("Invoice payment terms (days)"), days(defaults, "paymentTermsDays")),
          InfoRow(t("Quotes valid for (days)"), days(defaults, "quoteValidDays")),
        ]),
      SuSettingsCard(
        t("Default text"), description: t("Filled in on new documents; you can still change it on each one."),
        rows: [
          InfoRow(t("Notes"), defaults?.str("invoiceNotes") ?? ""),
          InfoRow(t("Terms"), defaults?.str("invoiceTerms") ?? ""),
          InfoRow(t("Quote introduction"), defaults?.str("quoteIntro") ?? ""),
          InfoRow(t("Footer"), defaults?.str("footer") ?? ""),
        ]),
    ]
  }

  private var numberingCards: [SuSettingsCard] {
    let onIssue = obj("defaults")?.flag("numberOnIssue") ?? false
    var rows: [InfoRow] = []
    for kind in SuSettings.numbered {
      rows.append(InfoRow(t(kind.label), nextNumber(kind.key)))
    }
    return [
      SuSettingsCard(
        t("When invoices get their number"),
        description: t(
          "Numbers are never given twice: a void invoice keeps its number, and an invoice issued in place of one gets a new number that says which it replaces."
        ), rows: [SuSettings.switched(t("Number invoices and credit notes when they are issued"), onIssue)]),
      SuSettingsCard(
        t("Number formats"), description: t("How new numbers are built. Numbers already used are skipped."), rows: rows),
    ]
  }

  /// A number of days, as the company writes numbers.
  private func days(_ defaults: JSONValue?, _ key: String) -> String {
    guard let value = defaults?.number(key), value.isFinite else { return "" }
    return format.count(Int(value.rounded()))
  }

  /// The next number a kind gets (`previewNumber`).
  private func nextNumber(_ key: String) -> String {
    let today = DocRules.today
    let stored = obj("numbering")?.obj(key).map { NumberingRule($0) }
    guard let rule = stored ?? Numbering.defaultRules()[key] else { return "" }
    return Numbering.formatNumber(rule, Numbering.currentCounter(rule, today), today)
  }

  private var itemsCards: [SuSettingsCard] {
    let items = obj("items")
    return [
      SuSettingsCard(
        t("Units"),
        description: t(
          "Pick units from a list with Arabic names, printed on Arabic documents. Units typed before stay as they are."),
        rows: [SuSettings.switched(t("Units from a list"), items?.flag("units") ?? false)]),
      SuSettingsCard(
        t("Item codes (SKU)"),
        description: t("Codes for items, printed on labels as a QR code that any scanner types into item search."),
        rows: [SuSettings.switched(t("Give new items a code"), items?.flag("autoSku") ?? false)]),
      SuSettingsCard(
        t("Item pictures"),
        description: t(
          "Pictures of your items, to tell them apart in lists and to show customers on quotes and invoices."),
        rows: [SuSettings.switched(t("Give items pictures"), items?.flag("images") ?? false)]),
    ]
  }

  private var emailsCards: [SuSettingsCard] {
    let templates = obj("emailTemplates")
    let kinds: [(key: String, label: String)] = [
      ("invoice", "Invoice"), ("quote", "Quote"), ("credit", "Credit note"), ("reminder", "Reminder"),
      ("payment", "Receipt"),
    ]
    let rows = kinds.map { kind in InfoRow(t(kind.label), templates?.obj(kind.key)?.str("subject") ?? "") }
    return [
      SuSettingsCard(
        t("Email templates"),
        description: t("Used when you send documents from the app. Your email program opens with the message ready."),
        rows: rows)
    ]
  }

  private var labelsCards: [SuSettingsCard] {
    let labels = obj("labels")?.object ?? [:]
    var custom: [InfoRow] = []
    for key in labels.keys.sorted() {
      if let word = labels[key]?.string, !word.isEmpty { custom.append(InfoRow(key, word)) }
    }
    return [
      SuSettingsCard(
        t("Document language"), description: t("Language of the words printed on invoices, quotes and credit notes."),
        rows: [InfoRow(t("Language"), t(SuSettings.documentLanguage(str("language"))))]),
      SuSettingsCard(
        t("Custom wording"),
        description: t(
          "Change any printed word, for example “Tax invoice” instead of “Invoice”. Leave a field empty to use the standard word."
        ), rows: custom),
    ]
  }

  // MARK: Money

  private var paymentsCards: [SuSettingsCard] {
    let bank = obj("bankAccount")
    let payment = obj("payment")
    let bankName = bank?.text("bankName") ?? bank?.str("bankCode") ?? ""
    return [
      SuSettingsCard(
        t("Bank account"), description: t("Printed on invoices while a balance is due, so customers know how to pay."),
        rows: [
          InfoRow(t("Bank"), bankName), InfoRow(t("Account name"), bank?.str("accountName") ?? ""),
          InfoRow(t("IBAN"), bank?.str("iban") ?? ""), InfoRow(t("Account number"), bank?.str("accountNumber") ?? ""),
          InfoRow(t("SWIFT code"), bank?.str("swift") ?? ""),
        ]),
      SuSettingsCard(t("Payment instructions"), rows: [InfoRow(t("Instructions"), payment?.str("instructions") ?? "")]),
      SuSettingsCard(
        t("Online payment link"),
        description: t("A link where customers can pay by KNET or card, e.g. from MyFatoorah, Tap or your bank."),
        rows: [
          InfoRow(t("Payment link"), payment?.str("paymentLink") ?? ""),
          SuSettings.switched(t("Print a QR code"), payment?.flag("showQrCode") ?? false),
        ]),
      SuSettingsCard(
        t("Cheque printing"),
        description: t(
          "Print cheques issued to vendors straight onto Burgan Bank and KFH cheque leaves. Every print is recorded on the cheque; nothing is posted."
        ), rows: [SuSettings.switched(t("Print cheques issued"), company?["chequePrinting"]?.bool == true)]),
    ]
  }

  private var taxesCards: [SuSettingsCard] {
    let rates = one.records(.taxRates).filter { !$0.flag("archived") }
    let enabled = company?["taxesEnabled"]?.bool ?? !rates.isEmpty
    let defaults = obj("defaults")
    return [
      SuSettingsCard(
        t("Tax"), description: t("Kuwait has no VAT today, so most businesses leave this off."),
        rows: [SuSettings.switched(t("This business charges tax"), enabled)]),
      SuSettingsCard(
        t("Tax rates"),
        description: t(
          "Rates you can pick on invoices and bills. Starred rates are applied to new items. The kind decides where each rate goes on your tax return."
        ), rows: rates.map { InfoRow(localName($0), format.percent($0.num("rate"))) }),
      SuSettingsCard(
        t("How taxes are applied"),
        rows: [
          SuSettings.switched(t("Tax per line item"), defaults?.flag("lineTaxes") ?? false),
          SuSettings.switched(t("Tax on the invoice total"), defaults?.flag("documentTaxes") ?? false),
          SuSettings.switched(t("Prices include tax"), defaults?.flag("pricesIncludeTax") ?? false),
        ]),
    ]
  }

  private var accountingCards: [SuSettingsCard] {
    let accounting = obj("accounting")
    let end = accounting?.obj("fiscalYearEnd")
    let month = min(12, max(1, end?["month"]?.int ?? 12))
    let day = min(SuDates.daysIn(year: 2026, month: month), max(1, end?["day"]?.int ?? 31))
    let pattern: Format.DateFormat = "d MMMM"
    let yearEnd = Format.date(SuDates.iso(2026, month, day), format: pattern, locale: format.locale)
    let country = obj("address")?.str("country").uppercased() ?? ""
    let fallback = country == "KW" ? "kw" : country == "AE" ? "ae" : country == "GB" ? "uk" : "generic"
    let chart = t(SuSettings.chartName(accounting?.text("template") ?? fallback))
    return [
      SuSettingsCard(
        t("Financial year"),
        description: t("Reports use it for “this year”, and income and expenses start again at zero each year."),
        rows: [InfoRow(t("Year ends on (month)"), yearEnd)]),
      SuSettingsCard(
        t("Lock date"),
        description: t(
          "Once a period is reported or filed, lock it so nothing dated on or before the lock date can be added, changed or deleted."
        ), rows: [InfoRow(t("Lock transactions up to and including"), format.date(accounting?.text("lockDate")))]),
      SuSettingsCard(
        t("VAT returns"),
        description: t("Maham Books works out each return from your books. You then submit the figures to the tax office."),
        rows: [SuSettings.switched(t("Registered for VAT"), accounting?.obj("vat")?.flag("registered") ?? false)]),
      SuSettingsCard(
        t("Chart of accounts"),
        description: t(
          "Started from the {chart} chart. Rename accounts or add new ones in the chart of accounts.", ["chart": chart]),
        rows: []),
    ]
  }

  // MARK: Data

  private var importCards: [SuSettingsCard] {
    [
      SuSettingsCard(
        t("Import data"),
        description: t(
          "Bring your records over from a spreadsheet or another accounting system. Files are read in this browser and never uploaded."
        ), rows: [])
    ]
  }

  private var dataCards: [SuSettingsCard] {
    [
      SuSettingsCard(t("Back up"), rows: []),
      SuSettingsCard(
        t("Import from a spreadsheet"),
        description: t("Bring in customers, products, opening balances and open invoices from CSV files."), rows: []),
    ]
  }
}

// MARK: This iPhone's own settings

/// Your account: who is signed in and the language; the Face ID lock; the
/// password (on the web); signing out.
private struct SuAccountSettings: View {
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette
  @State private var signingOut = false

  var body: some View {
    @Bindable var bindable = model
    let email = model.session?.user.email ?? ""
    Card {
      CardHeader(
        t("Your account"), description: t("Your name is shown to your team. Your language is used on every device."))
      CardBody {
        HStack(spacing: 12) {
          Avatar(email: email)
          Text(email)
            .font(.web(16, .medium))
            .foregroundStyle(palette.slate(900))
            .lineLimit(1)
            .environment(\.layoutDirection, .leftToRight)
        }
        Field(t("Language")) {
          Select(selection: languageBinding, options: [SelectOption(Language.en, "English"), SelectOption(Language.ar, "العربية")])
        }
      }
    }
    if Biometrics.isAvailable {
      Card {
        CardBody {
          Switch(
            lockTitle, description: t("Asks again when you come back after five minutes away."),
            isOn: $bindable.lockEnabled)
        }
      }
    }
    Card {
      CardHeader(t("Password"), description: t("Change the password you sign in with.")) {
        SuWebButton(t("Edit on the web"), path: "/settings/account")
      }
    }
    Card {
      CardHeader(t("Sign out"), description: t("Sign out on this device. Your other devices stay signed in.")) {
        WebButton(t("Sign out"), icon: .logOut, variant: .outline, size: .sm) { signingOut = true }
      }
    }
    .webDialog(isPresented: $signingOut, title: t("Sign out?")) {
      Text(t("You can sign in again at any time."))
    } footer: {
      WebButton(t("Cancel"), variant: .outline) { signingOut = false }
      WebButton(t("Sign out")) {
        signingOut = false
        Task {
          await model.signOut()
          model.confirm(t("Signed out"))
        }
      }
    }
  }

  /// The interface language, changed at once all over the app.
  private var languageBinding: Binding<Language> {
    Binding(
      get: { LanguageStore.shared.language },
      set: { LanguageStore.shared.language = $0 })
  }

  private var lockTitle: String {
    switch Biometrics.kind {
    case .touchID: t("Lock with Touch ID")
    case .opticID: t("Lock with Optic ID")
    default: t("Lock with Face ID")
    }
  }
}

/// Appearance (`appearance.tsx`): match the device, the light and the dark themes.
private struct SuAppearanceSettings: View {
  @Environment(\.palette) private var palette
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let store = ThemeStore.shared
    let following = store.mode == .system
    Card {
      CardHeader(
        t("Appearance"),
        description: t("Choose how Maham One looks on this device. Documents always print on white paper."))
      CardBody {
        Switch(
          t("Match my device"),
          description: following
            ? t("Showing {theme}. Pick one light and one dark theme below.", ["theme": t(palette.theme.nameKey)])
            : t("Use a light theme by day and a dark one when this device is set to dark."),
          isOn: followBinding)
        group(
          t("Light themes"), hint: following ? t("When your device is light") : nil, ids: ThemeID.lightThemes,
          checked: checked(.light, store: store))
        group(
          t("Dark themes"), hint: following ? t("When your device is dark") : nil, ids: ThemeID.darkThemes,
          checked: checked(.dark, store: store))
      }
    }
  }

  private var followBinding: Binding<Bool> {
    Binding(
      get: { ThemeStore.shared.mode == .system },
      set: { ThemeStore.shared.setFollowsDevice($0, systemScheme: scheme) })
  }

  /// Following the device, each group has its own choice; otherwise the theme on screen.
  private func checked(_ group: ColorScheme, store: ThemeStore) -> ThemeID? {
    if store.mode == .system { return group == .light ? store.lightTheme : store.darkTheme }
    return palette.theme.scheme == group ? palette.theme : nil
  }

  private func group(_ title: String, hint: String?, ids: [ThemeID], checked: ThemeID?) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(title).font(.web(14, .semibold)).foregroundStyle(palette.slate(900))
        if let hint {
          Text(hint).font(.web(14)).foregroundStyle(palette.slate(500))
        }
      }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
        ForEach(ids, id: \.self) { id in
          themeCard(id, checked: id == checked)
        }
      }
    }
  }

  private func themeCard(_ id: ThemeID, checked: Bool) -> some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous)
    return Button {
      if !checked { Haptics.play(.change) }
      choose(id)
    } label: {
      HStack(spacing: 10) {
        ThemeSwatch(theme: id, checked: checked)
        Text(t(id.nameKey))
          .font(.web(14, .medium))
          .foregroundStyle(palette.slate(800))
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 10)
      .frame(minHeight: 48)
      .background(palette.surface, in: shape)
      .overlay {
        shape.strokeBorder(checked ? palette.primary(600) : palette.slate(200), lineWidth: checked ? 2 : 1)
      }
      .contentShape(shape)
    }
    .buttonStyle(PressedScale())
    .accessibilityAddTraits(checked ? .isSelected : [])
  }

  /// Following the device, the theme for its light or dark setting; otherwise the theme shown.
  private func choose(_ id: ThemeID) {
    let store = ThemeStore.shared
    if store.mode == .system {
      store.chooseForDevice(id)
    } else {
      store.choose(id)
    }
  }
}

/// Cloud and sync: whether the company is up to date on this iPhone, and Sync now.
private struct SuCloudSettings: View {
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    Card {
      CardHeader(t("Cloud and sync")) {
        WebButton(t("Sync now"), icon: .refreshCw, variant: .outline, size: .sm, loading: model.one.syncing) {
          Task {
            await model.refreshAll()
            model.confirm(t("Sync finished"))
          }
        }
      }
      CardBody {
        SyncStatusLine(syncing: model.one.syncing || model.business.isLoading)
        switch model.one.phase {
        case .failed(let message):
          Text(message).font(.web(14)).foregroundStyle(palette[.red(600)])
        case .downloading(let done, let total) where total > 0:
          Text(t("Downloading {done} of {total}", ["done": "\(done)", "total": "\(total)"]))
            .font(.web(14))
            .foregroundStyle(palette.slate(500))
        default:
          EmptyView()
        }
      }
    }
  }
}
