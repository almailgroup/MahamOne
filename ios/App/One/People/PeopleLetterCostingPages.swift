import MahamKit
import SwiftUI

// Employee letters (`/people/letters`), the letter templates
// (`/people/letters/templates`, `/people/letters/templates/:id`) and
// manpower costing (`/people/costing`, `/people/costing/:id`):
// src/apps/people/pages/letters/*.tsx and costing/*.tsx. Read only.

// MARK: - Letters in a list

/// Letters, the latest first, each opening its text.
struct PeLetterRows: View {
  let letters: [JSONValue]
  var showEmployee = true
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette
  @State private var open: JSONValue?
  @State private var showing = false
  /// Issuing, sending, voiding or deleting the letter open, asked first (`PwLetterFooter`).
  @State private var stage = PwLetterStage.view
  @State private var note = ""
  @State private var busy = false

  var body: some View {
    let one = model.one
    let format = one.format
    VStack(spacing: 0) {
      ForEach(letters.map(Rec.init)) { record in
        let letter = record.raw
        let status = letter.str("status")
        PeLineRow(
          title: letter.text("number") ?? t("Draft"), detail: detail(letter, one: one),
          detail2: format.date(letter.text("issuedOn") ?? String(letter.str("createdAt").prefix(10))),
          trailing: {
            Badge(status: PeLetters.statusMeta(status))
            if status == "issued" && letter.text("printedAt") == nil { Badge(t("To print"), tone: .violet) }
          },
          action: {
            open = letter
            stage = .view
            showing = true
          })
      }
    }
    .webDialog(isPresented: $showing, title: dialogTitle, description: dialogDescription(one)) {
      if let letter = current(one) {
        PeLetterDetail(letter: letter, format: format)
        PwLetterStageBody(stage: stage, number: letter.str("number"), note: $note)
      }
    } footer: {
      if let letter = current(one) {
        PwLetterFooter(letter: letter, stage: $stage, note: $note, busy: $busy) { showing = false }
      } else {
        WebButton(t("Close"), variant: .outline) { showing = false }
      }
    }
  }

  /// The letter open, as it is saved now.
  private func current(_ one: OneData) -> JSONValue? {
    guard let open else { return nil }
    return one.record(.employeeLetters, open.rid) ?? open
  }

  /// The employee (in the company's list) and the kind of letter, with what made a draft.
  private func detail(_ letter: JSONValue, one: OneData) -> String {
    var parts: [String] = []
    if showEmployee {
      let employee = one.peEmployee(letter.str("employeeId"))
      parts.append(employee?.displayName ?? t("An employee no longer here"))
    }
    parts.append(PeLetters.kindLabel(letter.str("kind")))
    if let trigger = letter.text("trigger"), letter.str("status") == "draft" {
      parts.append(PeLetters.triggerNote(trigger))
    }
    return parts.joined(separator: " · ")
  }

  private var dialogTitle: String {
    guard let letter = open else { return "" }
    return PeLetters.kindLabel(letter.str("kind"))
  }

  private func dialogDescription(_ one: OneData) -> String? {
    guard let letter = open else { return nil }
    let name = one.peEmployee(letter.str("employeeId"))?.displayName ?? t("An employee no longer here")
    return [letter.text("number") ?? t("Draft"), name].joined(separator: " · ")
  }

  /// The latest first: by the day issued (or made), then when made.
  static func sorted(_ letters: [JSONValue]) -> [JSONValue] {
    letters.sorted { a, b in
      let da = a.text("issuedOn") ?? a.str("createdAt")
      let db = b.text("issuedOn") ?? b.str("createdAt")
      return da != db ? da > db : a.str("createdAt") > b.str("createdAt")
    }
  }
}

/// An employee's letters on a card.
struct PeLetterList: View {
  let letters: [JSONValue]
  var showEmployee = true
  let title: String
  @Environment(ShellRouter.self) private var router

  static func sorted(_ letters: [JSONValue]) -> [JSONValue] { PeLetterRows.sorted(letters) }

  var body: some View {
    Card {
      CardHeader(title) {
        if PwKinds.can(PwKinds.letters) {
          WebButton(t("New letter"), icon: .filePlus2, size: .sm) { router.push(.newLetter) }
        }
      }
      PeRows {
        PeLetterRows(letters: letters, showEmployee: showEmployee)
      }
    }
  }
}

/// A letter's details and its text, as it was filled in (the web's letter dialog, read only).
private struct PeLetterDetail: View {
  let letter: JSONValue
  let format: CompanyFormat
  @Environment(\.palette) private var palette

  var body: some View {
    let language = letter.text("language") ?? "ar"
    let status = letter.str("status")
    VStack(alignment: .leading, spacing: 12) {
      FlowLayout(spacing: 8, lineSpacing: 6) {
        Badge(status: PeLetters.statusMeta(status))
        if let issued = letter.text("issuedOn") {
          Text(t("Issued on {date}", ["date": format.date(issued)]))
            .font(.web(14))
            .foregroundStyle(palette.slate(600))
        }
        if let trigger = letter.text("trigger") {
          Badge(PeLetters.triggerNote(trigger), tone: .blue)
        }
        if status == "issued" && letter.text("printedAt") == nil {
          Badge(t("Not printed yet"), tone: .violet)
        }
      }
      if status == "void" {
        PeNote(
          t(
            "Void on {date}: {reason}",
            ["date": format.date(letter.text("voidedOn")), "reason": letter.str("voidReason")]), tone: .slate)
      }
      PeFigureLine(label: t("Printed in"), value: PeLetters.languageLabel(language))
      if let addressee = letter.text("addressee") {
        PeFigureLine(label: t("Addressed to"), value: addressee)
      }
      if let purpose = letter.text("purpose") {
        PeFigureLine(label: purposeLabel(letter.str("kind")), value: purpose)
      }
      PeLetterText(subject: letter.str("subject"), text: letter.str("body"), arabic: language != "en")
      if language == "ar-en" {
        PeLetterText(subject: letter.str("subjectEn"), text: letter.str("bodyEn"), arabic: false)
      }
    }
  }

  /// What the purpose of a kind of letter is called.
  private func purposeLabel(_ kind: String) -> String {
    switch kind {
    case "warning": t("What happened")
    case "noc": t("What the company has no objection to")
    default: t("Purpose")
    }
  }
}

/// A letter's subject and text, in the direction of its language.
private struct PeLetterText: View {
  let subject: String
  let text: String
  let arabic: Bool
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !subject.isEmpty {
        Text(verbatim: subject).font(.web(14, .semibold)).foregroundStyle(palette.slate(900))
      }
      Text(verbatim: text)
        .font(.web(14))
        .foregroundStyle(palette.slate(700))
        .multilineTextAlignment(.leading)
        .textSelection(.enabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(palette.slate(50), in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
    .environment(\.layoutDirection, arabic ? .rightToLeft : .leftToRight)
  }
}

// MARK: - Letters

/// `/people/letters`: the letters to print, drafts, issued and void letters.
struct PeLettersPage: View {
  var body: some View {
    PeGate { PeLettersView() }
  }
}

private struct PeLettersView: View {
  @Environment(AppModel.self) private var model
  @Environment(SuiteState.self) private var suite
  @Environment(ShellRouter.self) private var router
  /// The tab chosen; empty until one is, when the web's choice stands.
  @State private var tab = ""
  @State private var query = ""

  var body: some View {
    let one = model.one
    let on = one.pePeopleSettings.letters
    let letters = PeLetterRows.sorted(one.records(.employeeLetters))
    let counts = tabCounts(letters)
    let chosen = tab.isEmpty ? defaultTab(counts) : tab
    let shown = letters.filter { inTab($0, chosen) && matches($0, one: one) }
    let canSwitch = suite.role == nil || suite.role == .owner || suite.role == .admin
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(t("Letters"), description: t("Letters to and about employees, made from the company’s templates.")) {
        if on {
          WebButton(t("Letter templates"), icon: .files, variant: .outline) { router.push(.letterTemplates) }
          if PwKinds.can(PwKinds.letters) {
            WebButton(t("New letter"), icon: .filePlus2, haptic: .press) { router.push(.newLetter) }
          }
        }
      }
      if !on {
        PeLettersSwitch(on: false, canSwitch: canSwitch)
      } else {
        VStack(alignment: .leading, spacing: 24) {
          ListCard {
            Segmented(
              selection: Binding(get: { chosen }, set: { tab = $0 }),
              options: [
                SegmentOption("print", t("To print"), count: counts["print"]),
                SegmentOption("drafts", t("Drafts"), count: counts["drafts"]),
                SegmentOption("issued", t("Issued")), SegmentOption("void", t("Void")),
              ])
            TextInput(text: $query, placeholder: t("Search by name or number"), leadingIcon: .search)
          } rows: {
            if shown.isEmpty {
              PeLettersEmpty(tab: chosen)
            } else {
              PeLetterRows(letters: shown)
            }
          }
          if canSwitch { PeLettersSwitch(on: true, canSwitch: true) }
        }
      }
    }
  }

  private func tabCounts(_ letters: [JSONValue]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for key in ["print", "drafts", "issued", "void"] {
      counts[key] = letters.filter { inTab($0, key) }.count
    }
    return counts
  }

  private func inTab(_ letter: JSONValue, _ tab: String) -> Bool {
    let status = letter.str("status")
    switch tab {
    case "print": return status == "issued" && letter.text("printedAt") == nil
    case "drafts": return status == "draft"
    case "issued": return status == "issued"
    default: return status == "void"
    }
  }

  private func defaultTab(_ counts: [String: Int]) -> String {
    if (counts["print"] ?? 0) > 0 { return "print" }
    if (counts["drafts"] ?? 0) > 0 { return "drafts" }
    return "issued"
  }

  private func matches(_ letter: JSONValue, one: OneData) -> Bool {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    if q.isEmpty { return true }
    let employee = one.peEmployee(letter.str("employeeId"))
    let text = [letter.str("number"), employee?.name ?? "", employee?.nameAr ?? "", employee?.number ?? ""]
      .joined(separator: " ").lowercased()
    return text.contains(q)
  }
}

/// What an empty tab of letters says.
private struct PeLettersEmpty: View {
  let tab: String
  @Environment(ShellRouter.self) private var router

  var body: some View {
    WebEmptyState(icon: .mails, title: title, description: description) {
      if tab != "void" {
        if PwKinds.can(PwKinds.letters) {
          WebButton(t("New letter"), icon: .filePlus2, variant: .outline) { router.push(.newLetter) }
        }
      }
    }
  }

  private var title: String {
    switch tab {
    case "print": t("Nothing to print")
    case "drafts": t("No drafts")
    case "issued": t("No letters issued yet")
    default: t("No void letters")
    }
  }

  private var description: String? {
    switch tab {
    case "print": return t("Letters show here once they are issued, until they are printed.")
    case "drafts":
      return t(
        "Drafts made by hand, and those the templates make when an employee joins, leaves or has their salary changed. A person checks and issues each one."
      )
    default: return nil
    }
  }
}

/// The letters switch (off until the owner or an admin turns it on), with what to know before.
private struct PeLettersSwitch: View {
  let on: Bool
  let canSwitch: Bool
  @Environment(\.palette) private var palette

  var body: some View {
    PeCard(
      t("Employee letters"),
      description: t(
        "Salary, experience and employment certificates, warning letters and no objection certificates, filled from each employee’s record and printed with the company’s letterhead."
      )
    ) {
      if canSwitch && PwKinds.can(PwKinds.lettersSwitch) {
        PwLettersSwitchRow(on: on)
      } else if canSwitch {
        PeSwitchRow(
          label: t("Use employee letters"),
          description: t(
            "Off: nothing changes, as before. On: accountants draft letters and ask for approval; the owner, admins and the members allowed to approve issue them. Each letter gets a number when it is issued (HR-2026-0001, from 1 again each year), which is never used twice."
          ), isOn: on)
      } else {
        Text(
          on
            ? t("Employee letters are on. Only the owner or an admin turns them off.")
            : t("Employee letters are off. Ask the owner or an admin to turn them on.")
        )
        .font(.web(14))
        .foregroundStyle(palette.slate(600))
      }
      PeNote(
        t(
          "Warning letters and no objection certificates have legal weight under the Labour Law: ask your lawyer to check their wording in Letter templates before they are issued. Letters are printed, never emailed, and only the owner, admins and approvers print the company stamp on them."
        ))
    }
  }
}

// MARK: - Letter templates

/// `/people/letters/templates`: the wording of each kind of letter.
struct PeLetterTemplatesPage: View {
  var body: some View {
    PeGate { PeLetterTemplatesView() }
  }
}

private struct PeLetterTemplatesView: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let one = model.one
    let templates = PeLetters.templates(stored: one.records(.letterTemplates), companyId: one.companyId ?? "")
    let active = templates.filter { !$0.archived }
    let archived = templates.filter(\.archived)
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(
        t("Letter templates"),
        description: t(
          "The wording of each kind of letter. Fields in braces are filled from the employee’s record; the text itself is the company’s, in Arabic and English."
        ), breadcrumb: t("Letters"), onBreadcrumb: { router.back() })
      if !one.pePeopleSettings.letters {
        Card {
          WebEmptyState(
            icon: .files, title: t("Employee letters are off"), description: t("Turn them on in People → Letters first.")
          ) {
            WebButton(t("Letters"), variant: .outline) { router.push(.letters) }
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 24) {
          PeTemplateList(title: t("Templates"), templates: active)
          if !archived.isEmpty { PeTemplateList(title: t("Archived"), templates: archived) }
        }
      }
    }
  }
}

private struct PeTemplateList: View {
  let title: String
  let templates: [PeLetterTemplate]
  @Environment(ShellRouter.self) private var router

  var body: some View {
    PeListCard(title) {
      ForEach(templates) { template in
        PeLineRow(
          title: template.displayName,
          detail: PeLetters.kindLabel(template.kind) + " · " + PeLetters.languageLabel(template.language),
          trailing: {
            if template.isDefault && template.updatedAt.isEmpty { Badge(t("The app’s wording"), tone: .gray) }
            ForEach(template.autoOn, id: \.self) { trigger in
              Badge(PeLetters.triggerLabel(trigger), tone: .blue)
            }
            if template.privateFields { Badge(t("Private details"), tone: .amber) }
          },
          action: { router.push(.letterTemplate(id: template.id)) })
      }
    }
  }
}

/// `/people/letters/templates/:id`: a template's wording, signature, stamp and automatic drafts.
struct PeLetterTemplatePage: View {
  let id: String

  var body: some View {
    PeGate { PeLetterTemplateView(id: id) }
  }
}

private struct PeLetterTemplateView: View {
  let id: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let wanted = id.removingPercentEncoding ?? id
    let template = PeLetters.templates(stored: one.records(.letterTemplates), companyId: one.companyId ?? "")
      .first { $0.id == wanted }
    WebPage(refresh: { [model] in await model.one.sync() }) {
      if let template {
        PageHeader(template.displayName, breadcrumb: t("Letter templates"), onBreadcrumb: { router.back() })
        if let raw = editable(one, wanted) {
          // Editable where templates may be saved on this iPhone and letters are on (`saveTemplate`).
          PwTemplateEditor(template: raw).id(raw.str("updatedAt"))
        } else {
          PeTemplateDetail(template: template)
        }
      } else {
        PeNotFound(message: t("This template could not be found."), back: t("Letter templates"))
      }
    }
  }

  /// The template as the editor starts from it, when the person may change it here.
  private func editable(_ one: OneData, _ id: String) -> JSONValue? {
    guard PwKinds.can(PwKinds.templates), PwLetterAccess.on(one), PwLetters.canDraft(one.pwLink) else { return nil }
    return PwLetterAccess.templates(one).first { $0.rid == id }
  }
}

private struct PeTemplateDetail: View {
  let template: PeLetterTemplate
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      if template.archived {
        PeNote(t("This template is archived: no new letters are made from it."), tone: .slate)
      }
      PeCard(t("Template")) {
        PeFigureLine(label: t("Name (English)"), value: template.name.isEmpty ? "—" : template.name)
        PeFigureLine(label: t("Name (Arabic)"), value: template.nameAr ?? "—")
        PeFigureLine(label: t("Kind of letter"), value: PeLetters.kindLabel(template.kind))
        PeFigureLine(label: t("Printed in"), value: PeLetters.languageLabel(template.language))
        PeHint(t("Arabic unless you choose otherwise. Each letter can still be changed."))
      }
      PeCard(t("Wording")) {
        Text(t("Arabic")).font(.web(14, .medium)).foregroundStyle(palette.slate(800))
        PeLetterText(subject: template.subjectAr, text: template.bodyAr, arabic: true)
        Text(t("English")).font(.web(14, .medium)).foregroundStyle(palette.slate(800))
        PeLetterText(subject: template.subjectEn, text: template.bodyEn, arabic: false)
      }
      PeCard(t("Signature and stamp")) {
        PeFigureLine(label: t("Signed by"), value: template.signatoryName.isEmpty ? "—" : template.signatoryName)
        PeFigureLine(label: t("Their title"), value: template.signatoryTitle.isEmpty ? "—" : template.signatoryTitle)
        PeSwitchRow(
          label: t("Print the signature"),
          description: t("The signature of Settings → Company, on issued letters only. Drafts never show it."),
          isOn: template.showSignature)
        PeSwitchRow(
          label: t("Print the company stamp"), description: t("On issued letters only. Drafts never show it."),
          isOn: template.showStamp)
      }
      PeCard(
        t("Automatic drafts"),
        description: t(
          "A draft of this letter is made by itself when one of these happens. It is never issued or printed without a person: it waits in People → Letters → Drafts."
        )
      ) {
        ForEach(PeLetters.triggers, id: \.self) { trigger in
          PeSwitchRow(label: PeLetters.triggerLabel(trigger), isOn: template.autoOn.contains(trigger))
        }
        PeHint(t("Employees imported from a file make no drafts."))
      }
      PeCard(t("Private details")) {
        PeSwitchRow(
          label: t("This letter may show the Civil ID, passport number and bank account"),
          description: t(
            "Only where its text asks for them, and only when the owner, an admin or an approver issues it. Otherwise they print masked. A salary transfer letter to a bank may need them."
          ), isOn: template.privateFields)
      }
    }
  }
}

// MARK: - Manpower costing

/// `/people/costing`: the company's costings, their overhead and margin, and the rate card.
struct PeCostingsPage: View {
  var body: some View {
    PeGate { PeCostingsView() }
  }
}

private struct PeCostingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(SuiteState.self) private var suite
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let one = model.one
    let format = one.format
    let settings = one.pePeopleSettings.costing
    let canEdit = suite.access(.people).canEdit
    let costings = one.records(.staffingCostings).sorted { $0.str("updatedAt") > $1.str("updatedAt") }
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(
        t("Manpower costing"),
        description: t("Posts priced from staff cost, with overhead and a margin, and the quotes they make.")
      ) {
        if settings.on && canEdit {
          if PwKinds.can(PwKinds.costings) {
            WebButton(t("New costing"), icon: .plus, haptic: .press) { router.push(.newCosting) }
          }
        }
      }
      if !settings.on {
        PeCostingSwitch(on: false, canEdit: canEdit)
      } else {
        VStack(alignment: .leading, spacing: 24) {
          if costings.isEmpty {
            Card {
              WebEmptyState(
                icon: .calculator, title: t("No costings yet"),
                description: t(
                  "A costing prices the posts a customer asks for: guards, cleaners and other staff, their hours and days. It makes a quote with sell prices only."
                )
              ) {
                if canEdit {
                  if PwKinds.can(PwKinds.costings) {
                    WebButton(t("New costing"), icon: .plus, variant: .outline) { router.push(.newCosting) }
                  }
                }
              }
            }
          } else {
            ListCard {
              ForEach(costings.map(Rec.init)) { record in
                let costing = record.raw
                ListRow(
                  title: costing.str("name"), subtitle: customer(costing, one: one),
                  amount: format.money(PeCosting.monthly(costing))
                ) {
                  Badge(status: PeCosting.statusMeta(costing.str("status")))
                } action: {
                  router.push(.costing(id: costing.rid))
                }
              }
            }
          }
          PeCard(t("Overhead and margin"), description: t("Used by new costings. Each costing can change them.")) {
            PeFigureLine(label: t("Overhead (%)"), value: format.quantity(settings.overheadPercent))
            PeHint(t("Added to the cost of each post."))
            PeFigureLine(label: t("Margin (% of the sell price)"), value: format.quantity(settings.marginPercent))
            PeHint(t("At most {max}%.", ["max": "90"]))
            PeHint(PeCosting.marginExplained(settings.marginPercent))
          }
          PeRateCard(settings: settings)
          if canEdit { PeCostingSwitch(on: true, canEdit: true) }
        }
      }
    }
  }

  /// The costing's customer, also one archived or no longer here.
  private func customer(_ costing: JSONValue, one: OneData) -> String {
    guard let id = costing.text("clientId") else { return "—" }
    guard let client = one.record(.clients, id) else { return t("A customer no longer here") }
    let name = localName(client)
    return client.flag("archived") ? name + " · " + t("Archived") : name
  }
}

/// The costing switch, read only here.
private struct PeCostingSwitch: View {
  let on: Bool
  let canEdit: Bool
  @Environment(\.palette) private var palette

  var body: some View {
    PeCard(
      t("Manpower costing"),
      description: t(
        "Price posts of guards, cleaners and other staff from what they cost, with overhead and a margin, and make a quote for the customer with sell prices only."
      )
    ) {
      if canEdit && PwKinds.can(PwKinds.costingSwitch) {
        PwCostingSwitchRow(on: on)
      } else if canEdit {
        PeSwitchRow(
          label: t("Use manpower costing"),
          description: t(
            "Off: nothing changes, as before. On: the owner, admins and accountants make costings here. Costings, their salaries, costs and margins stay private like payroll: staff and viewers never see them, and the quote shows the sell prices only."
          ), isOn: on)
      } else {
        Text(
          on
            ? t("Manpower costing is on.")
            : t("Manpower costing is off. Ask the owner, an admin or an accountant to turn it on.")
        )
        .font(.web(14))
        .foregroundStyle(palette.slate(600))
      }
      PeNote(
        t(
          "Hours past 8 a day are priced as overtime at 1.25. Article 66 of Labour Law 6/2010 limits overtime to 2 hours a day, 3 days a week and 180 hours a year unless an exemption applies, so a post with more is flagged. Confirm with counsel before quoting such a post."
        ))
    }
  }
}

/// The rate card: pay per job title, from the current salaries until one is saved.
private struct PeRateCard: View {
  let settings: PeCostingSettings
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let fromSalaries = settings.rates == nil
    let rates = settings.rates ?? PeCosting.averageRates(one.peEmployees, one.pePrecision)
    Card {
      CardHeader(
        t("Rate card"),
        description: t(
          "The pay of each job title that posts are priced from, per person a month. Costings copy it into their posts, where it can be changed."
        ))
      if fromSalaries {
        PeNote(
          t(
            "Worked out on this device from the current salaries: the average of each job title. An average of one person is their salary. Save it to keep it, or change it first."
          ), tone: .slate
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
      }
      if rates.isEmpty {
        WebEmptyState(
          icon: .calculator, title: t("No job titles yet"),
          description: t("Add the job titles you price, or add employees with their job titles."))
      } else {
        PeRows {
          ForEach(rates) { rate in
            PeLineRow(
              title: rate.displayTitle, detail: PeCosting.categoryLabel(rate.category),
              detail2: pay(rate, format: format),
              trailing: {
                Text(rate.count.map { format.count($0) } ?? "—")
                  .font(.web(14, tabular: true))
                  .foregroundStyle(palette.slate(500))
              })
          }
        }
        .padding(.top, fromSalaries ? 12 : 0)
      }
    }
  }

  private func pay(_ rate: PeCostingRate, format: CompanyFormat) -> String {
    var parts = [
      t("Basic salary") + " " + format.money(rate.basic), t("Allowances") + " " + format.money(rate.allowances),
    ]
    if let eos = rate.eosAllowances {
      parts.append(t("Allowances for indemnity") + " " + format.money(eos))
    }
    if rate.otherCosts > 0 { parts.append(t("Other costs") + " " + format.money(rate.otherCosts)) }
    return parts.joined(separator: " · ")
  }
}

/// `/people/costing/:id`: a costing's posts, priced from today's payroll settings, and its totals.
struct PeCostingPage: View {
  let id: String

  var body: some View {
    PeGate { PeCostingView(id: id) }
  }
}

private struct PeCostingView: View {
  let id: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let one = model.one
    let costing = one.record(.staffingCostings, id)
    WebPage(refresh: { [model] in await model.one.sync() }) {
      if let costing, one.pePeopleSettings.costing.on {
        if PwKinds.can(PwKinds.costings) && PwCosting.canEdit(one.pwLink) {
          // Editable where costings may be saved on this iPhone (`saveCosting`).
          PwCostingEditor(id: id)
        } else {
          PeCostingDetail(costing: costing)
        }
      } else if model.one.hasData, model.one.phase == .ready {
        Card {
          WebEmptyState(
            icon: .calculator, title: costing == nil ? t("Costing not found") : t("Manpower costing is off")
          ) {
            WebButton(t("Manpower costing"), icon: .arrowLeft, variant: .outline) { router.push(.costings) }
          }
        }
      } else {
        Card { DataLoadingRow() }
      }
    }
  }
}

private struct PeCostingDetail: View {
  let costing: JSONValue
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let basis = PeCosting.basis(one.pePayrollSettings, one.pePeopleSettings, precision: one.pePrecision)
    let priced = PeCosting.price(costing, basis: basis)
    let quote = costing.text("quoteId").flatMap { one.record(.documents, $0) }
    PageHeader(
      costing.text("name") ?? t("New costing"), breadcrumb: t("Manpower costing"), onBreadcrumb: { router.back() }
    ) {
      if let quote {
        WebButton(
          t("Quote {number}", ["number": quote.text("number") ?? t("Draft")]), icon: .scrollText, variant: .outline
        ) {
          router.push(.salesDocument(.quote, id: quote.rid))
        }
      }
    }
    VStack(alignment: .leading, spacing: 24) {
      Badge(status: PeCosting.statusMeta(costing.str("status")))
        .padding(.top, -16)
      InfoCard(rows: details(format: format, one: one))
      TextCard(title: t("Internal notes"), text: costing.text("notes"))
      if priced.posts.isEmpty {
        Card {
          CardHeader(t("Posts"), description: postsDescription(basis))
          WebEmptyState(
            icon: .calculator, title: t("No posts yet"),
            description: t("Add the posts the customer asks for, from the rate card or by hand."))
        }
      } else {
        VStack(alignment: .leading, spacing: 12) {
          Text(t("Posts")).webText(.cardTitle)
          Text(postsDescription(basis)).font(.web(14)).foregroundStyle(palette.slate(500))
          ForEach(priced.posts) { post in
            PePostCard(post: post, format: format)
          }
        }
      }
      PeCard(
        t("Totals a month"),
        description: t(
          "The quote shows the job titles, hours, days, people and sell prices only. Costs, salaries and the margin stay here."
        ) + " " + t("The sell prices are before tax: tax, when the company charges it, is added on top.")
      ) {
        PeAmountList(rows: totalRows(priced.totals, format: format))
      }
    }
  }

  private func postsDescription(_ basis: PeCostingBasis) -> String {
    t(
      "Pay per person a month. Hours past 8 a day are overtime at 1.25; days past {days} a month are rest days worked, at 1.5.",
      ["days": Money.jsString(basis.dailyDivisor)])
  }

  private func details(format: CompanyFormat, one: OneData) -> [InfoRow] {
    var rows: [InfoRow] = []
    let client = costing.text("clientId").flatMap { one.record(.clients, $0) }
    rows.append(InfoRow(t("Customer"), client.map { localName($0) } ?? "—"))
    rows.append(InfoRow(t("Overhead (%)"), format.quantity(costing.num("overheadPercent")), tabular: true))
    rows.append(InfoRow(t("Margin (% of the sell price)"), format.quantity(costing.num("marginPercent")), tabular: true))
    rows.append(InfoRow(t("Status"), t(PeCosting.statusMeta(costing.str("status")).label)))
    return rows
  }

  private func totalRows(_ totals: PeCostingTotals, format: CompanyFormat) -> [PeAmount] {
    var rows = PeAmountRows()
    rows.add(t("Headcount"), format.count(totals.headcount))
    rows.add(t("Cost a month"), format.money(totals.cost))
    rows.add(t("Overhead"), format.money(totals.overhead))
    rows.add(t("Sell price a month"), format.money(totals.sell), strong: true)
    rows.add(t("Margin"), format.money(totals.margin))
    rows.add(t("Margin of the sell price"), Money.jsString(totals.marginPercent) + "%")
    rows.add(t("Markup on cost"), Money.jsString(totals.markupPercent) + "%")
    return rows.rows
  }
}

/// One post of a costing: who, how many and how long, their pay, and what it all costs and sells for.
private struct PePostCard: View {
  let post: PePricedPost
  let format: CompanyFormat
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    Card {
      CardHeader(post.displayTitle.isEmpty ? t("A post") : post.displayTitle, description: subtitle)
      VStack(alignment: .leading, spacing: 12) {
        PeAmountList(rows: rows)
        ForEach(0..<post.warnings.count, id: \.self) { index in
          HStack(alignment: .top, spacing: 8) {
            IconView(.triangleAlert, size: 16).foregroundStyle(palette[.amber(500)])
            Text(PeCosting.warningText(post.warnings[index], format))
              .font(.web(14))
              .foregroundStyle(palette[.amber(800)])
          }
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
    }
  }

  private var subtitle: String {
    var parts = [PeCosting.categoryLabel(post.category)]
    if post.category == "gcc" && !post.nationality.isEmpty {
      parts.append(Geo.countryName(post.nationality, locale: format.locale.identifier))
    }
    parts.append(t("Headcount") + " " + format.count(post.headcount))
    parts.append(t("Hours a day") + " " + format.quantity(post.hoursPerDay))
    parts.append(t("Days a month") + " " + format.quantity(post.daysPerMonth))
    return parts.joined(separator: " · ")
  }

  private var rows: [PeAmount] {
    var rows = PeAmountRows()
    rows.add(t("Basic salary"), format.money(post.basic))
    rows.add(t("Allowances"), format.money(post.allowances))
    if let eos = post.eosAllowances { rows.add(t("Allowances for indemnity"), format.money(eos)) }
    rows.add(t("Other costs"), format.money(post.otherCosts))
    rows.add(t("Overtime"), format.money(post.overtime), muted: true)
    rows.add(t("Employer PIFSS"), format.money(post.employerPifss), muted: true)
    rows.add(t("Indemnity"), format.money(post.eosi), muted: true)
    rows.add(t("Leave"), format.money(post.leave), muted: true)
    rows.add(t("Cost a person"), format.money(post.cost))
    rows.add(t("With overhead"), format.money(post.fullCost))
    rows.add(t("Sell price a person"), format.money(post.sell), strong: true)
    rows.add(t("A month"), format.money(post.totalSell), strong: true)
    return rows.rows
  }
}
