import MahamKit
import SwiftUI

// Employee letters saved natively, as the web's letter dialog and template
// editor save them: a draft made from a template, saved, issued (numbered
// with the cloud's counter and frozen) or sent to an approver; a draft
// deleted, an issued letter voided; the letters switch; a template's
// wording, signature, stamp and automatic drafts.

/// Who may do what with letters on this iPhone (`useLettersView`).
@MainActor
enum PwLetterAccess {
  static func on(_ one: OneData) -> Bool { PwLetters.inEffect(one.pePeopleSettings.raw, one.pwLink) }
  static func canDraft(_ one: OneData) -> Bool { PwLetters.canDraft(one.pwLink) && PwKinds.can(PwKinds.letters) }
  static func canIssue(_ one: OneData) -> Bool { PwLetters.canIssue(one.pwLink) && PwKinds.can(PwKinds.issue) }
  static func asks(_ one: OneData) -> Bool { PwLetters.asksToIssue(one.pwLink) && PwKinds.can(PwKinds.approvals) }

  /// The request waiting to issue a letter (`pendingLetterRequest`).
  static func pending(_ one: OneData, _ letterId: String) -> JSONValue? {
    one.records(.approvals).first {
      $0.str("subjectId") == letterId && $0.str("status") == "pending" && Roles.isLetterApproval($0)
    }
  }

  /// The company's templates, its own and the app's (`useLetterTemplates`).
  static func templates(_ one: OneData) -> [JSONValue] {
    PwLetters.templates(stored: one.records(.letterTemplates), companyId: one.companyId ?? "")
  }

  static func templateName(_ template: JSONValue) -> String {
    let name = localName(template.str("name"), template.text("nameAr"))
    return name.isEmpty ? PeLetters.kindLabel(template.str("kind")) : name
  }
}

/// Issuing a draft: the number from the cloud's counter when it answers, else this iPhone's.
@MainActor
enum PwLetterIssue {
  static func run(_ model: AppModel, id: String) async -> JSONValue? {
    let on = ISODates.today()
    let link = model.one.pwLink
    let local: (kind: String, min: Int)? =
      await PwSave.read(model) { ctx in PwLetters.localNumber(ctx, letterId: id, on: on) } ?? nil
    let reserved = await model.one.reserveNumber(local.map { DcCounterRequest(kind: $0.kind, date: on, min: $0.min) })
    guard
      let issued = await PwSave.run(
        model, { ctx in try PwLetters.issue(ctx, id: id, on: on, reserved: reserved, link: link) })
    else { return nil }
    model.confirm(t("Letter {number} issued", ["number": issued.str("number")]))
    return issued
  }
}

// MARK: - A new letter

/// `/people/letters?new=1`: a letter made from a template, for an employee.
struct PwLetterFormPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @State private var draft: PwDraft?
  @State private var started = false
  @State private var savedId: String?
  @State private var changed = false
  @State private var busy: String?
  @State private var purposeChecked = false
  @State private var confirmingIssue = false
  @State private var confirmingDelete = false
  @State private var asking = false
  @State private var askNote = ""
  @State private var preview: [String: String] = [:]

  var body: some View {
    WebPage {
      PageHeader(title, description: subtitle, breadcrumb: t("Letters"), onBreadcrumb: { router.back() })
      if draft != nil {
        PwLetterDraftFields(
          draft: editable, purposeError: purposeChecked ? missingPurpose : nil, locked: savedId != nil)
        PwLetterPreview(texts: preview, language: draft?.text("language") ?? "ar", title: t("Preview"))
      } else if started {
        Card {
          WebEmptyState(
            icon: .files, title: t("New letter"),
            description: t("There is no letter template to make it from. Add one in Letter templates.")
          ) {
            WebButton(t("Letter templates"), variant: .outline) { router.push(.letterTemplates) }
          }
        }
      }
    }
    .stickyActions { actions }
    .onAppear(perform: start)
    .task(id: draft?.json) { await refreshPreview() }
    .pwConfirm(
      $confirmingIssue, title: t("Issue this letter?"),
      description: t(
        "It gets the next letter number, and its text is frozen as it is now. An issued letter can be voided, never deleted, so its number stays used."
      ), confirmLabel: t("Issue letter")
    ) { Task { await issue() } }
    .pwConfirm(
      $confirmingDelete, title: t("Delete this draft?"), description: t("It has no number yet, so none is used."),
      confirmLabel: t("Delete"), danger: true
    ) { Task { await remove() } }
    .webDialog(
      isPresented: $asking, title: t("Ask for approval to issue this letter?"),
      description: t(
        "The owner, or a member the owner allowed to approve, checks it and issues it. Until then it stays a draft, and can’t be changed unless the request is taken back."
      )
    ) {
      Field(t("Note for the approver"), optional: true) { PwTextArea(text: $askNote) }
    } footer: {
      WebButton(t("Cancel"), variant: .outline) { asking = false }
      WebButton(t("Send for approval"), loading: busy == "ask") { Task { await ask() } }
    }
  }

  @ViewBuilder
  private var actions: some View {
    let one = model.one
    if draft != nil && PwLetterAccess.canDraft(one) {
      if savedId != nil {
        WebButton(t("Delete draft"), icon: .trash2, variant: .ghost) { confirmingDelete = true }
      }
      WebButton(t("Save draft"), variant: .outline, loading: busy == "save") { Task { await save() } }
      if PwLetterAccess.canIssue(one) {
        WebButton(t("Issue letter"), icon: .fileSignature, loading: busy == "issue") {
          if readyToIssue() { confirmingIssue = true }
        }
      } else if PwLetterAccess.asks(one) {
        WebButton(t("Send for approval"), icon: .send, loading: busy == "ask") {
          if readyToIssue() {
            askNote = ""
            asking = true
          }
        }
      }
    }
  }

  private var title: String {
    guard let draft else { return t("New letter") }
    return PeLetters.kindLabel(draft.text("kind"))
  }

  private var subtitle: String {
    guard let employee = model.one.peEmployee(draft?.text("employeeId") ?? "") else {
      return t("Made from a template, with the employee’s record.")
    }
    return employee.displayName + " · " + employee.number
  }

  /// The draft as typed; any change means it is saved again.
  private var editable: Binding<PwDraft> {
    Binding<PwDraft>(
      get: { draft ?? PwDraft(nil) },
      set: {
        draft = $0
        changed = true
      })
  }

  private var missingPurpose: String? { draft.flatMap { PwLetters.missingPurpose($0.json) }.map { t($0) } }

  /// The first template the company has, for no one yet.
  private func start() {
    guard !started else { return }
    started = true
    let usable = PwLetterAccess.templates(model.one).filter { !$0.flag("archived") }
    guard let first = usable.first else { return }
    draft = PwDraft(PwLetters.draftFromTemplate(first, employeeId: "", language: first.str("language")))
  }

  private func refreshPreview() async {
    guard let input = draft?.json else { return }
    let link = model.one.pwLink
    preview = await PwSave.read(model) { ctx in PwLetters.previewDraft(ctx, input, link: link) } ?? [:]
  }

  /// Whether the draft says what it must before it is issued or sent; shows why not.
  private func readyToIssue() -> Bool {
    purposeChecked = true
    guard let missingPurpose else { return true }
    model.toast = Toast(kind: .error, message: missingPurpose)
    return false
  }

  /// Saves the draft when it is new or changed; the letter as stored.
  private func persist() async -> JSONValue? {
    guard var input = draft?.json else { return nil }
    if input.str("employeeId").isEmpty {
      model.toast = Toast(kind: .error, message: t("Choose the employee the letter is for."))
      return nil
    }
    if let savedId, !changed, let stored = model.one.record(.employeeLetters, savedId), stored.str("status") == "draft" {
      return stored
    }
    if let savedId { input.set("id", .string(savedId)) }
    let saving = input
    let link = model.one.pwLink
    guard let saved = await PwSave.run(model, { ctx in try PwLetters.saveDraft(ctx, saving, link: link) }) else {
      return nil
    }
    savedId = saved.rid
    draft = PwDraft(PwLetterDraft.of(saved))
    changed = false
    return saved
  }

  private func save() async {
    busy = "save"
    defer { busy = nil }
    guard await persist() != nil else { return }
    model.confirm(t("Draft saved"))
    router.back()
  }

  private func issue() async {
    busy = "issue"
    defer { busy = nil }
    guard let saved = await persist(), await PwLetterIssue.run(model, id: saved.rid) != nil else { return }
    router.back()
  }

  private func ask() async {
    busy = "ask"
    defer { busy = nil }
    guard let saved = await persist() else { return }
    let id = saved.rid
    let note = askNote
    let link = model.one.pwLink
    let name = model.session?.user.fullName ?? model.session?.user.email ?? ""
    guard
      await PwSave.run(
        model, success: t("Sent for approval"),
        { ctx in try PwLetters.requestIssue(ctx, id: id, note: note, byName: name, link: link) }) != nil
    else { return }
    asking = false
    router.back()
  }

  private func remove() async {
    guard let id = savedId else {
      router.back()
      return
    }
    guard await PwSave.run(model, success: t("Draft deleted"), { ctx in try PwLetters.deleteDraft(ctx, id: id) }) != nil
    else { return }
    router.back()
  }
}

/// `draftOf(letter)`: what of a stored draft is edited.
enum PwLetterDraft {
  static func of(_ letter: JSONValue) -> JSONValue {
    var fields: [String: JSONValue] = [:]
    for key in [
      "id", "companyId", "employeeId", "templateId", "kind", "language", "addressee", "purpose", "subject", "body",
      "subjectEn", "bodyEn", "trigger",
    ] {
      if let value = letter[key] { fields[key] = value }
    }
    return .object(fields)
  }
}

/// The fields of a draft: employee, template, language, addressee, purpose and wording.
private struct PwLetterDraftFields: View {
  @Binding var draft: PwDraft
  let purposeError: String?
  /// Saved once: the employee stays.
  let locked: Bool
  @Environment(AppModel.self) private var model
  @State private var showWording = false

  var body: some View {
    Card {
      CardBody {
        VStack(alignment: .leading, spacing: 16) {
          Field(t("Employee")) {
            Combobox(
              selection: employee, options: employees, placeholder: t("Choose an employee"),
              searchPlaceholder: t("Search employees…"), emptyText: t("No employees found")
            )
            .disabled(locked)
          }
          Field(t("Template")) { Select(selection: template, options: templates) }
          Field(t("Printed in")) { Select(selection: language, options: languages) }
          Field(t("Addressed to"), optional: true) {
            TextInput(text: $draft.text("addressee"), placeholder: t("To whom it may concern"))
          }
          purpose
          PwLetterWording(draft: $draft, open: $showWording)
        }
      }
    }
    .padding(.bottom, 16)
  }

  private var purpose: some View {
    let kind = draft.text("kind")
    let needed = kind == "warning" || kind == "noc"
    return Field(
      PwLetterWords.purposeLabel(kind), hint: PwLetterWords.purposeHint(kind), error: purposeError, optional: !needed
    ) { PwTextArea(text: $draft.text("purpose"), minHeight: 64) }
  }

  private var employee: Binding<String?> {
    Binding<String?>(
      get: { draft.text("employeeId").isEmpty ? nil : draft.text("employeeId") },
      set: { draft.fields["employeeId"] = .string($0 ?? "") })
  }

  /// Those still working first, then by name.
  private var employees: [ComboOption] {
    model.one.peEmployees
      .sorted { a, b in
        a.isCurrent != b.isCurrent ? a.isCurrent : a.displayName.localizedCompare(b.displayName) == .orderedAscending
      }
      .map { e in
        ComboOption(
          value: e.id, label: e.displayName,
          detail: [e.number, e.isCurrent ? "" : t("Left")].filter { !$0.isEmpty }.joined(separator: " · "),
          keywords: [e.name, e.nameAr ?? "", e.number].joined(separator: " "))
      }
  }

  private var allTemplates: [JSONValue] { PwLetterAccess.templates(model.one) }

  private var templates: [SelectOption<String>] {
    let current = draft.text("templateId")
    return allTemplates.filter { !$0.flag("archived") || $0.rid == current }
      .map { SelectOption($0.rid, PwLetterAccess.templateName($0)) }
  }

  /// Another template: its wording, keeping who it is for and to.
  private var template: Binding<String> {
    Binding<String>(
      get: { draft.text("templateId") },
      set: { id in
        guard let next = allTemplates.first(where: { $0.rid == id }) else { return }
        var made = PwLetters.draftFromTemplate(
          next, employeeId: draft.text("employeeId"), language: next.str("language"))
        made.set("addressee", .string(draft.text("addressee")))
        made.set("purpose", .string(draft.text("purpose")))
        if let saved = draft.fields["id"] { made.set("id", saved) }
        draft = PwDraft(made)
      })
  }

  private var languages: [SelectOption<String>] {
    ["ar", "en", "ar-en"].map { SelectOption($0, PeLetters.languageLabel($0)) }
  }

  /// Another language: the template's wording in it.
  private var language: Binding<String> {
    Binding<String>(
      get: { draft.text("language") },
      set: { value in
        var next = draft
        next.fields["language"] = .string(value)
        if let source = allTemplates.first(where: { $0.rid == draft.text("templateId") }) {
          for (key, text) in PwLetters.templateTexts(source, value) { next.fields[key] = text }
        }
        if value != "ar-en" {
          next.fields["subjectEn"] = nil
          next.fields["bodyEn"] = nil
        }
        draft = next
      })
  }
}

/// "Change the wording of this letter": its subject and text, in each language it prints in.
private struct PwLetterWording: View {
  @Binding var draft: PwDraft
  @Binding var open: Bool
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button {
        Haptics.play(.tap)
        withAnimation(WebMotion.standard) { open.toggle() }
      } label: {
        Text(t("Change the wording of this letter"))
          .font(.web(14, .medium))
          .foregroundStyle(palette.primary(700))
      }
      .buttonStyle(.plain)
      if open {
        Text(
          t(
            "Fields in braces, such as {employee.name}, are filled from the employee’s record when the letter is issued. Only this letter changes, not the template."
          )
        )
        .font(.web(12))
        .foregroundStyle(palette.slate(500))
        let english = draft.text("language") == "en"
        PwWordingFields(
          label: english ? t("English") : t("Arabic"), rightToLeft: !english, subject: $draft.text("subject"),
          text: $draft.text("body"))
        if draft.text("language") == "ar-en" {
          PwWordingFields(
            label: t("English"), rightToLeft: false, subject: $draft.text("subjectEn"), text: $draft.text("bodyEn"))
        }
      }
    }
  }
}

/// A subject and a text in one language.
struct PwWordingFields: View {
  let label: String
  let rightToLeft: Bool
  @Binding var subject: String
  @Binding var text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label).font(.web(14, .medium))
      TextInput(text: $subject, placeholder: t("Subject"))
        .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
      PwTextArea(text: $text, minHeight: 200, rightToLeft: rightToLeft)
    }
  }
}

/// What the purpose of each kind of letter is called, and a hint.
enum PwLetterWords {
  static func purposeLabel(_ kind: String) -> String {
    switch kind {
    case "warning": t("What happened")
    case "noc": t("What the company has no objection to")
    default: t("Purpose")
    }
  }

  static func purposeHint(_ kind: String) -> String {
    switch kind {
    case "warning": t("Printed in the letter: the breach, with its date.")
    case "noc": t("For example: their travel abroad, or a driving licence.")
    default: t("Printed only where the text has the purpose field.")
    }
  }
}

/// A letter's filled text, in its own direction: Arabic, English, or both.
private struct PwLetterPreview: View {
  let texts: [String: String]
  let language: String
  let title: String
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.web(12, .medium)).foregroundStyle(palette.slate(500))
      VStack(alignment: .leading, spacing: 16) {
        half(subject: texts["subject"] ?? "", body: texts["body"] ?? "", arabic: language != "en")
        if language == "ar-en" {
          half(subject: texts["subjectEn"] ?? "", body: texts["bodyEn"] ?? "", arabic: false)
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(palette.slate(50), in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
    }
    .padding(.bottom, 24)
  }

  private func half(subject: String, body text: String, arabic: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if !subject.isEmpty {
        Text(verbatim: subject).font(.web(14, .semibold)).foregroundStyle(palette.slate(900))
      }
      Text(verbatim: text).font(.web(14)).foregroundStyle(palette.slate(800))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .environment(\.layoutDirection, arabic ? .rightToLeft : .leftToRight)
  }
}

// MARK: - A letter's actions

/// Where the letter dialog is: showing the letter, or asking before a change.
enum PwLetterStage: Equatable {
  case view, issue, ask, void, delete
}

/// What the dialog says before a change, and the note or reason it asks for.
struct PwLetterStageBody: View {
  let stage: PwLetterStage
  /// The letter's number, for voiding it.
  var number = ""
  @Binding var note: String
  @Environment(\.palette) private var palette

  var body: some View {
    switch stage {
    case .view:
      EmptyView()
    case .issue:
      said(
        t("Issue this letter?"),
        t(
          "It gets the next letter number, and its text is frozen as it is now. An issued letter can be voided, never deleted, so its number stays used."
        ))
    case .ask:
      said(
        t("Ask for approval to issue this letter?"),
        t(
          "The owner, or a member the owner allowed to approve, checks it and issues it. Until then it stays a draft, and can’t be changed unless the request is taken back."
        ))
      Field(t("Note for the approver"), optional: true) { PwTextArea(text: $note, minHeight: 64) }
    case .void:
      said(
        t("Void letter {number}?", ["number": number]),
        t(
          "It keeps its number, which is never given again, and prints as void. Make a new letter in its place if one is needed."
        ))
      Field(t("Why is it void?")) { PwTextArea(text: $note, minHeight: 64) }
    case .delete:
      said(t("Delete this draft?"), t("It has no number yet, so none is used."))
    }
  }

  private func said(_ title: String, _ text: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.web(14, .semibold)).foregroundStyle(palette.slate(900))
      Text(text).font(.web(14)).foregroundStyle(palette.slate(600))
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(palette[.amber(50)], in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
  }
}

/// The letter dialog's buttons: issue, send for approval, delete or void, each asked first.
struct PwLetterFooter: View {
  let letter: JSONValue
  @Binding var stage: PwLetterStage
  @Binding var note: String
  @Binding var busy: Bool
  let onClose: () -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    switch stage {
    case .view: viewButtons
    case .issue: confirm(t("Issue letter"), danger: false)
    case .ask: confirm(t("Send for approval"), danger: false)
    case .void: confirm(t("Void letter"), danger: true)
    case .delete: confirm(t("Delete"), danger: true)
    }
  }

  @ViewBuilder
  private var viewButtons: some View {
    let one = model.one
    let status = letter.str("status")
    WebButton(t("Close"), variant: .outline, action: onClose)
    if status == "draft" && PwLetterAccess.pending(one, letter.rid) == nil && PwLetterAccess.canDraft(one) {
      WebButton(t("Delete draft"), icon: .trash2, variant: .ghost) { stage = .delete }
      if PwLetterAccess.canIssue(one) {
        WebButton(t("Issue letter"), icon: .fileSignature) { if ready() { stage = .issue } }
      } else if PwLetterAccess.asks(one) {
        WebButton(t("Send for approval"), icon: .send) {
          if ready() {
            note = ""
            stage = .ask
          }
        }
      }
    }
    if status == "issued" && PwLetterAccess.canIssue(one) {
      WebButton(t("Void letter"), icon: .ban, variant: .ghost) {
        note = ""
        stage = .void
      }
    }
  }

  @ViewBuilder
  private func confirm(_ label: String, danger: Bool) -> some View {
    WebButton(t("Cancel"), variant: .outline) { stage = .view }
    WebButton(label, variant: danger ? .danger : .primary, loading: busy) { Task { await perform() } }
  }

  /// The change the dialog asked about.
  private func perform() async {
    busy = true
    defer { busy = false }
    switch stage {
    case .view: return
    case .issue: await issue()
    case .ask: await ask()
    case .void: await voidIt()
    case .delete: await remove()
    }
  }

  /// The purpose a warning or certificate prints must be there.
  private func ready() -> Bool {
    guard let missing = PwLetters.missingPurpose(letter) else { return true }
    model.toast = Toast(kind: .error, message: t(missing))
    return false
  }

  private func issue() async {
    guard await PwLetterIssue.run(model, id: letter.rid) != nil else { return }
    stage = .view
    onClose()
  }

  private func ask() async {
    let id = letter.rid
    let typed = note
    let link = model.one.pwLink
    let name = model.session?.user.fullName ?? model.session?.user.email ?? ""
    guard
      await PwSave.run(
        model, success: t("Sent for approval"),
        { ctx in try PwLetters.requestIssue(ctx, id: id, note: typed, byName: name, link: link) }) != nil
    else { return }
    stage = .view
    onClose()
  }

  private func voidIt() async {
    let reason = note.trimmingCharacters(in: .whitespacesAndNewlines)
    if reason.isEmpty {
      model.toast = Toast(kind: .error, message: t("Say why the letter is void."))
      return
    }
    let id = letter.rid
    let link = model.one.pwLink
    guard
      await PwSave.run(
        model, success: t("Letter voided"), { ctx in try PwLetters.voidLetter(ctx, id: id, reason: reason, link: link) }
      ) != nil
    else { return }
    stage = .view
    onClose()
  }

  private func remove() async {
    let id = letter.rid
    guard await PwSave.run(model, success: t("Draft deleted"), { ctx in try PwLetters.deleteDraft(ctx, id: id) }) != nil
    else { return }
    stage = .view
    onClose()
  }
}

// MARK: - The letters switch

/// "Use employee letters", saved when it is turned (`setLettersOn`).
struct PwLettersSwitchRow: View {
  let on: Bool
  @Environment(AppModel.self) private var model
  @State private var busy = false

  var body: some View {
    Switch(
      t("Use employee letters"),
      description: t(
        "Off: nothing changes, as before. On: accountants draft letters and ask for approval; the owner, admins and the members allowed to approve issue them. Each letter gets a number when it is issued (HR-2026-0001, from 1 again each year), which is never used twice."
      ), isOn: Binding<Bool>(get: { on }, set: { value in Task { await turn(value) } })
    )
    .disabled(busy)
  }

  private func turn(_ value: Bool) async {
    busy = true
    defer { busy = false }
    let link = model.one.pwLink
    await PwSave.run(
      model, success: value ? t("Employee letters turned on") : t("Employee letters turned off")
    ) { ctx in try PwLetters.setOn(ctx, value, link: link) }
  }
}

// MARK: - A template

/// A template edited: its names, kind, language, wording, signature, stamp,
/// automatic drafts and private details (`saveTemplate`), archived or
/// restored, or its wording put back to the app's.
struct PwTemplateEditor: View {
  let template: JSONValue
  @Environment(AppModel.self) private var model
  @State private var draft: PwDraft?
  @State private var busy: String?
  @State private var confirmingRestore = false

  var body: some View {
    let value = Binding<PwDraft>(get: { draft ?? PwDraft(template) }, set: { draft = $0 })
    VStack(alignment: .leading, spacing: 24) {
      buttons
      if template.flag("archived") {
        PeNote(t("This template is archived: no new letters are made from it."), tone: .slate)
      }
      PwTemplateMain(value: value)
      PeCard(t("Wording")) {
        PwWordingFields(
          label: t("Arabic"), rightToLeft: true, subject: value.text("subjectAr"), text: value.text("bodyAr"))
        PwWordingFields(
          label: t("English"), rightToLeft: false, subject: value.text("subjectEn"), text: value.text("bodyEn"))
      }
      PwTemplateSignature(value: value)
      PwTemplateTriggers(value: value)
      if PwLetters.canIssue(model.one.pwLink) {
        PeCard(t("Private details")) {
          Switch(
            t("This letter may show the Civil ID, passport number and bank account"),
            description: t(
              "Only where its text asks for them, and only when the owner, an admin or an approver issues it. Otherwise they print masked. A salary transfer letter to a bank may need them."
            ), isOn: value.flag("privateFields"))
        }
      }
    }
    .pwConfirm(
      $confirmingRestore, title: t("Put back the app’s wording?"),
      description: t(
        "The Arabic and English text of this template go back to the app’s wording. Letters already made keep theirs."),
      confirmLabel: t("Restore default")
    ) { Task { await restore() } }
  }

  private var buttons: some View {
    FlowLayout(spacing: 8) {
      WebButton(
        template.flag("archived") ? t("Restore") : t("Archive"),
        icon: template.flag("archived") ? .archiveRestore : .archive, variant: .outline, size: .sm,
        loading: busy == "archive"
      ) { Task { await archive() } }
      .disabled(draft != nil)
      if PwLetters.defaultTemplateKind(template.rid) != nil {
        WebButton(t("Restore default"), icon: .rotateCcw, variant: .outline, size: .sm, loading: busy == "restore") {
          confirmingRestore = true
        }
      }
      WebButton(t("Save template"), size: .sm, loading: busy == "save") { Task { await save() } }
        .disabled(draft == nil)
    }
  }

  private func save() async {
    guard let input = draft?.json else { return }
    busy = "save"
    defer { busy = nil }
    let link = model.one.pwLink
    guard
      await PwSave.run(model, success: t("Template saved"), { ctx in try PwLetters.saveTemplate(ctx, input, link: link) })
        != nil
    else { return }
    draft = nil
  }

  private func archive() async {
    busy = "archive"
    defer { busy = nil }
    let id = template.rid
    let archived = !template.flag("archived")
    let link = model.one.pwLink
    await PwSave.run(model, success: archived ? t("Template archived") : t("Template restored")) { ctx in
      try PwLetters.setTemplateArchived(ctx, id: id, archived: archived, link: link)
    }
  }

  private func restore() async {
    busy = "restore"
    defer { busy = nil }
    let id = template.rid
    let link = model.one.pwLink
    guard
      await PwSave.run(
        model, success: t("The app’s wording is back"),
        { ctx in try PwLetters.restoreDefaultWording(ctx, id: id, link: link) }) != nil
    else { return }
    draft = nil
  }
}

private struct PwTemplateMain: View {
  @Binding var value: PwDraft

  var body: some View {
    PeCard(t("Template")) {
      Field(t("Name (English)")) { TextInput(text: $value.text("name")) }
      Field(t("Name (Arabic)")) { TextInput(text: $value.text("nameAr")) }
      Field(t("Kind of letter")) {
        Select(selection: $value.text("kind"), options: PeLetters.kinds.map { SelectOption($0, PeLetters.kindLabel($0)) })
      }
      Field(t("Printed in"), hint: t("Arabic unless you choose otherwise. Each letter can still be changed.")) {
        Select(
          selection: $value.text("language"),
          options: ["ar", "en", "ar-en"].map { SelectOption($0, PeLetters.languageLabel($0)) })
      }
    }
  }
}

private struct PwTemplateSignature: View {
  @Binding var value: PwDraft

  var body: some View {
    PeCard(t("Signature and stamp")) {
      Field(t("Signed by"), optional: true) { TextInput(text: $value.text("signatoryName")) }
      Field(t("Their title"), optional: true) { TextInput(text: $value.text("signatoryTitle")) }
      Switch(
        t("Print the signature"),
        description: t("The signature of Settings → Company, on issued letters only. Drafts never show it."),
        isOn: $value.flag("showSignature"))
      Switch(
        t("Print the company stamp"), description: t("On issued letters only. Drafts never show it."),
        isOn: $value.flag("showStamp"))
    }
  }
}

private struct PwTemplateTriggers: View {
  @Binding var value: PwDraft

  var body: some View {
    PeCard(
      t("Automatic drafts"),
      description: t(
        "A draft of this letter is made by itself when one of these happens. It is never issued or printed without a person: it waits in People → Letters → Drafts."
      )
    ) {
      ForEach(PeLetters.triggers, id: \.self) { trigger in
        Switch(PeLetters.triggerLabel(trigger), isOn: on(trigger))
      }
      PeHint(t("Employees imported from a file make no drafts."))
    }
  }

  private func on(_ trigger: String) -> Binding<Bool> {
    Binding<Bool>(
      get: { (value.fields["autoOn"]?.array ?? []).contains(.string(trigger)) },
      set: { now in
        var list = value.fields["autoOn"]?.array ?? []
        if now {
          if !list.contains(.string(trigger)) { list.append(.string(trigger)) }
        } else {
          list.removeAll { $0 == .string(trigger) }
        }
        value.fields["autoOn"] = .array(list)
      })
  }
}
