import MahamKit
import SwiftUI

// The register's forms, saved natively (src/features/renewals): a
// document added, edited, archived, deleted or made confidential
// (`DocumentDialog`), a paper renewed with its fee (`RenewDialog`), and a
// vehicle (`VehicleDialog`). Each saves through the ports of the web's
// writes (MahamKit/Write/Suite), only once the kinds it changes can be
// saved from this iPhone (`OneWritable`).

// MARK: Who may use them

@MainActor
enum SwComplianceGate {
  /// Adding and editing register documents.
  static var documents: Bool { SwAccess.can(.complianceDocuments, .activities) }
  /// Making one confidential: its renewals, files and fees go with it.
  static var confidential: Bool { documents && SwAccess.can(.renewals, .attachments, .expenses) }
  /// Taking a file off a record.
  static var files: Bool { SwAccess.can(.attachments) }
  /// Renewing a stored document; an employee's own paper changes the employee.
  static func renews(_ entry: SuEntry) -> Bool {
    let owner: Bool = entry.recordId != nil ? SwAccess.can(.complianceDocuments) : SwAccess.can(.employees)
    return owner && SwAccess.can(.renewals, .activities)
  }
  /// Recording the renewal's fee as an expense (and its account when the company has none).
  static var fees: Bool { SwAccess.can(.expenses, .accounts, .companies) }
  /// Marking statutory deadlines done.
  static var marks: Bool { SwAccess.can(.complianceMarks, .activities) }
  /// The company's vehicles.
  static var vehicles: Bool { SwAccess.can(.vehicles, .complianceDocuments, .activities) }
}

// MARK: A register document

/// A register document being added or edited (`DocumentDialog`'s state).
struct SwDocDraft: Identifiable {
  var doc: JSONValue
  /// The reminders as typed ("60, 30, 7"); empty uses the company's.
  var daysText: String
  let isNew: Bool
  /// The document as it was opened.
  let original: JSONValue
  /// A new cost sheet starts confidential, until the switch is changed by hand.
  var confidentialTouched: Bool
  /// Files taken off its form, removed once it is saved.
  var removedFiles: [String] = []
  var id: String { doc.rid }

  init(_ doc: JSONValue, isNew: Bool) {
    self.doc = doc
    original = doc
    self.isNew = isNew
    let days = (doc["reminderDays"]?.array ?? []).compactMap(\.double)
    daysText = days.map { Money.jsString($0) }.joined(separator: ", ")
    confidentialTouched = !isNew
  }

  /// A new document of the company (`createComplianceDocument`).
  static func new(companyId: String, _ overrides: [String: JSONValue] = [:]) -> SwDocDraft {
    SwDocDraft(SwCompliance.newDocument(companyId: companyId, overrides), isNew: true)
  }

  /// What is saved: the reminders read from the text (`parseDays`).
  var input: JSONValue {
    var fields = doc.object ?? [:]
    if let days = SwReminders.parse(daysText) {
      fields["reminderDays"] = .array(days.map { JSONValue.number($0) })
    } else {
      fields["reminderDays"] = .null
    }
    return .object(fields)
  }

  var becomesConfidential: Bool {
    !isNew && original["confidential"] != .bool(true) && doc["confidential"] == .bool(true)
  }
}

extension View {
  /// The document form, open while `draft` is set.
  func swDocumentDialog(_ draft: Binding<SwDocDraft?>, model: AppModel) -> some View {
    modifier(SwDocumentDialog(draft: draft, model: model))
  }
}

private enum SwDocConfirm {
  case confidential, delete
}

private struct SwDocumentDialog: ViewModifier {
  @Binding var draft: SwDocDraft?
  let model: AppModel
  @State private var saving = false
  @State private var confirming: SwDocConfirm?

  func body(content: Content) -> some View {
    content.webDialog(
      isPresented: open, title: title,
      description: t("Licences, contracts, vehicle papers and other documents that expire.")
    ) {
      if let binding = Binding($draft) {
        SwDocumentFields(draft: binding, model: model, register: SuRegister(model.one))
          .webDialog(isPresented: confirmOpen, title: confirmTitle, description: confirmText) {
            EmptyView()
          } footer: {
            SwConfirmFooter(
              label: confirming == .delete ? t("Delete") : t("Make confidential"), danger: confirming == .delete,
              onCancel: { confirming = nil }, onConfirm: confirmed)
          }
      }
    } footer: {
      footer
    }
  }

  private var open: Binding<Bool> {
    Binding(get: { draft != nil }, set: { if !$0 { draft = nil } })
  }

  private var confirmOpen: Binding<Bool> {
    Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
  }

  private var title: String {
    draft?.isNew == false ? t("Edit document") : t("Add document")
  }

  private var confirmTitle: String {
    confirming == .delete ? t("Delete this document?") : t("Make this document confidential?")
  }

  private var confirmText: String {
    confirming == .delete
      ? t("Its files are deleted too. This cannot be undone.")
      : t(
        "Staff and viewers stop seeing it, its files, renewals and activity: their copies are removed from their devices. This can’t be undone."
      )
  }

  @ViewBuilder
  private var footer: some View {
    let editor = SwAccess(model).edits
    if let current = draft, !current.isNew, editor {
      WebButton(
        current.original.flag("archived") ? t("Restore") : t("Archive"),
        icon: current.original.flag("archived") ? .archiveRestore : .archive, variant: .ghost
      ) { archive(current) }
      WebButton(t("Delete"), icon: .trash2, variant: .ghost) { confirming = .delete }
    }
    WebButton(t("Cancel"), variant: .outline) { draft = nil }
    if editor {
      WebButton(draft?.isNew == true ? t("Add document") : t("Save"), loading: saving) { save() }
    }
  }

  private func confirmed() {
    let kind = confirming
    confirming = nil
    guard let current = draft else { return }
    if kind == .delete {
      remove(current)
    } else {
      Task { await commit(current, confidential: true) }
    }
  }

  private func save() {
    guard let current = draft else { return }
    if current.becomesConfidential {
      confirming = .confidential
      return
    }
    Task { await commit(current, confidential: false) }
  }

  private func commit(_ current: SwDocDraft, confidential: Bool) async {
    saving = true
    let input = current.input
    let cloud = model.one.cloud
    let words = SwSave.words
    let removed = current.removedFiles
    let ok = await SwSave.run(model, done: current.isNew ? t("Document added") : t("Document saved")) { ctx in
      if confidential {
        try SwCompliance.makeConfidential(ctx, input, cloud: cloud, removedFiles: removed, words: words)
      } else {
        try SwCompliance.saveDocument(ctx, input, cloud: cloud, words: words)
      }
      // The files taken off the list go once the document is saved.
      for id in removed where ctx.get("attachments", id) != nil {
        SwRenewals.removeAttachment(ctx, id: id)
      }
    }
    saving = false
    if ok { draft = nil }
  }

  private func archive(_ current: SwDocDraft) {
    let archived = !current.original.flag("archived")
    let id = current.original.rid
    Task {
      let ok = await SwSave.run(model, done: archived ? t("Document archived") : t("Document restored")) { ctx in
        SwCompliance.setArchived(ctx, id: id, archived: archived)
      }
      if ok { draft = nil }
    }
  }

  private func remove(_ current: SwDocDraft) {
    let id = current.original.rid
    Task {
      let ok = await SwSave.run(model, done: t("Document deleted")) { ctx in
        try SwCompliance.deleteDocument(ctx, id: id)
      }
      if ok { draft = nil }
    }
  }
}

/// The document's fields, as the web's form asks them.
private struct SwDocumentFields: View {
  @Binding var draft: SwDocDraft
  let model: AppModel
  let register: SuRegister

  private var doc: JSONValue { draft.doc }
  private var extras: Bool { register.extras }
  private var cloudReady: Bool { model.one.cloud?.has("tables_v16") ?? true }
  private var seesPeople: Bool { Roles.canSeePeople(model.business.company?.role) }
  private var readOnly: Bool { !SwAccess(model).edits }
  private var record: Binding<JSONValue> { $draft.doc }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Field(t("Belongs to")) {
        Segmented(selection: ownerBinding, options: owners)
      }
      ownerFields
      Field(t("Document type"), hint: costSheetsWait ? costSheetHint : nil) {
        Select(selection: typeBinding, options: types.map { SelectOption($0, t(SwDocTypes.info($0).label)) })
      }
      Field(t("Title"), optional: !SwDocTypes.needsTitle(doc.str("type"))) {
        TextInput(
          text: SwBind.text(record, ["title"]),
          placeholder: SwDocTypes.needsTitle(doc.str("type")) ? "" : t(SwDocTypes.info(doc.str("type")).label))
      }
      if extras { purposeField }
      Field(t("Document number"), optional: true) { TextInput(text: SwBind.text(record, ["number"])) }
      if showsLicenceClass {
        Field(t("Licence class"), hint: t("As written on the licence."), optional: true) {
          TextInput(text: SwBind.text(record, ["licenceClass"]))
        }
      }
      Field(t("Issued by"), optional: true) {
        TextInput(text: SwBind.text(record, ["issuer"]), placeholder: t("e.g. Ministry of Commerce and Industry"))
      }
      Field(t("Issue date"), optional: true) { DateField(value: SwBind.optional(record, ["issueDate"])) }
      Field(t("Expiry date")) { DateField(value: SwBind.optional(record, ["expiryDate"])) }
      Field(t("Renewal cost"), hint: t("What the next renewal is expected to cost."), optional: true) {
        SwNumberField(value: costBinding)
      }
      Field(t("Reminders (days before expiry)"), hint: t("Leave empty to use the company setting."), optional: true) {
        TextInput(text: $draft.daysText, placeholder: reminderPlaceholder, keyboard: .numbersAndPunctuation)
      }
      Field(t("Notes"), optional: true) { SwTextArea(text: SwBind.text(record, ["notes"]), lines: 2) }
      if showsConfidential { confidentialSwitch }
      SwFileRows(ownerId: doc.rid, removed: $draft.removedFiles, model: model, editable: !readOnly)
    }
    .disabled(readOnly)
  }

  // MARK: Who it belongs to

  private var owners: [SegmentOption<String>] {
    ["company", "employee", "vehicle", "other"].map { SegmentOption($0, t(SwDocTypes.ownerLabel($0))) }
  }

  private var ownerBinding: Binding<String> {
    Binding(get: { doc.str("ownerType") }, set: { setOwner($0) })
  }

  @ViewBuilder
  private var ownerFields: some View {
    switch doc.str("ownerType") {
    case "employee":
      Field(t("Employee"), hint: t("Civil ID, passport, residency and work permit are kept on the employee’s page.")) {
        Combobox(
          selection: SwBind.choice(record, ["employeeId"]), options: employeeOptions,
          placeholder: t("Choose an employee…"), searchPlaceholder: t("Search employees…"), emptyText: t("No matches"))
      }
    case "vehicle":
      if extras {
        Field(t("Vehicle")) {
          Combobox(
            selection: vehicleBinding, options: [ComboOption(value: "", label: t("Not in the list"))] + vehicleOptions,
            placeholder: t("Choose a vehicle…"), searchPlaceholder: t("Search vehicles…"), emptyText: t("No matches"))
        }
        if doc.text("vehicleId") == nil { ownerInput(t("Plate number or model"), optional: false) }
      } else {
        Field(t("Vehicle")) {
          TextInput(text: SwBind.text(record, ["ownerName"]), placeholder: t("Plate number or model"))
        }
      }
    case "other":
      if extras {
        Field(t("Customer"), optional: !SwDocTypes.customerTypes.contains(doc.str("type"))) {
          Combobox(
            selection: customerBinding, options: [ComboOption(value: "", label: t("No customer"))] + customerOptions,
            placeholder: t("Choose a customer…"), searchPlaceholder: t("Search customers…"), emptyText: t("No matches"))
        }
      }
      if doc.text("clientId") == nil { ownerInput(t("Owner"), optional: true) }
    default:
      EmptyView()
    }
  }

  private func ownerInput(_ label: String, optional: Bool) -> some View {
    Field(label, optional: optional) {
      TextInput(text: SwBind.text(record, ["ownerName"]), placeholder: optional ? "" : t("Plate number or model"))
    }
  }

  private var employeeOptions: [ComboOption] {
    let chosen = doc.str("employeeId")
    let list = register.employees.filter { $0.str("status") != "left" || $0.rid == chosen }
    return list.sorted { localName($0).localizedCompare(localName($1)) == .orderedAscending }.map { employee in
      ComboOption(
        value: employee.rid, label: localName(employee), detail: employee.str("number"),
        keywords: "\(employee.str("name")) \(employee.str("nameAr")) \(employee.str("civilId"))")
    }
  }

  private var vehicleOptions: [ComboOption] {
    let chosen = doc.str("vehicleId")
    let list = register.vehicles.filter { !$0.flag("archived") || $0.rid == chosen }
    return list.sorted { $0.str("plate").localizedCompare($1.str("plate")) == .orderedAscending }.map { vehicle in
      let about = suJoin([vehicle.str("make"), vehicle.str("model")], " ")
      return ComboOption(
        value: vehicle.rid, label: vehicle.str("plate"), detail: about.isEmpty ? nil : about,
        keywords: vehicle.str("chassisNumber"))
    }
  }

  private var vehicleBinding: Binding<String?> {
    Binding(
      get: { doc.text("vehicleId") ?? "" },
      set: { value in
        let id = value ?? ""
        var fields = draft.doc.object ?? [:]
        fields["vehicleId"] = id.isEmpty ? .null : .string(id)
        if let vehicle = register.vehicle(id) { fields["ownerName"] = .string(vehicle.str("plate")) }
        draft.doc = .object(fields)
      })
  }

  private var customerOptions: [ComboOption] {
    let chosen = doc.str("clientId")
    let clients = model.one.records(.clients).filter { client in
      (client["isCustomer"] != .bool(false) && !client.flag("archived")) || client.rid == chosen
    }
    return clients.sorted { localName($0).localizedCompare(localName($1)) == .orderedAscending }.map { client in
      ComboOption(
        value: client.rid, label: localName(client), detail: client.str("number"),
        keywords: "\(client.str("name")) \(client.str("nameAr"))")
    }
  }

  private var customerBinding: Binding<String?> {
    Binding(
      get: { doc.text("clientId") ?? "" },
      set: { value in
        let id = value ?? ""
        var fields = draft.doc.object ?? [:]
        fields["clientId"] = id.isEmpty ? .null : .string(id)
        if let client = model.one.record(.clients, id) { fields["ownerName"] = .string(client.str("name")) }
        draft.doc = .object(fields)
      })
  }

  // MARK: The type

  /// The types offered: the owner's, a cost sheet only where it can be kept
  /// confidential, and the document's own type whatever is offered now.
  private func offered(_ owner: String) -> [String] {
    SwDocTypes.registerTypes(for: owner, extras: extras).filter { cloudReady || $0 != "customer_cost" }
  }

  private var types: [String] {
    let list = offered(doc.str("ownerType"))
    let type = doc.str("type")
    return list.contains(type) || !SwDocTypes.isKnown(type) ? list : list + [type]
  }

  private var costSheetsWait: Bool { extras && !cloudReady && doc.str("ownerType") == "other" }

  private var costSheetHint: String {
    t("Customer cost sheets can be added once the owner of the company runs the latest database script.")
  }

  private var typeBinding: Binding<String> {
    Binding(get: { doc.str("type") }, set: { setType($0) })
  }

  private func setType(_ type: String, owner: String? = nil) {
    var fields = draft.doc.object ?? [:]
    if let owner { fields["ownerType"] = .string(owner) }
    let auto = !draft.confidentialTouched && showsConfidential && !confidentialLocked
    fields["type"] = .string(type)
    if auto { fields["confidential"] = .bool(type == "customer_cost") }
    draft.doc = .object(fields)
  }

  private func setOwner(_ owner: String) {
    let allowed = offered(owner)
    let type = doc.str("type")
    setType(allowed.contains(type) ? type : (allowed.first ?? "other"), owner: owner)
  }

  // MARK: The rest

  private var purposeField: some View {
    let chosen = doc.str("purposeId")
    let purposes = (model.one.company?.list("documentPurposes") ?? [])
      .filter { !$0.flag("archived") || $0.rid == chosen }
      .map { ComboOption(value: $0.rid, label: localName($0), keywords: "\($0.str("name")) \($0.str("nameAr"))") }
    return Field(t("Purpose"), optional: true) {
      Combobox(
        selection: SwBind.choice(record, ["purposeId"]),
        options: [ComboOption(value: "", label: t("No purpose"))] + purposes, placeholder: t("Choose a purpose…"),
        searchPlaceholder: t("Search purposes…"), emptyText: t("No matches"),
        createLabel: readOnly ? nil : t("Add purpose"), onCreate: readOnly ? nil : { addPurpose($0) })
    }
  }

  /// A purpose typed in the box (`PurposeDialog` with what was typed): Arabic text is its Arabic name.
  private func addPurpose(_ typed: String) {
    let arabic = typed.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
    let name = arabic ? "" : typed
    let nameAr = arabic ? typed : ""
    Task {
      var added: String?
      _ = await SwSave.run(model) { ctx in
        added = try SwCompliance.addPurpose(ctx, name: name, nameAr: nameAr)["id"]?.string
      }
      if let added { draft.doc = SwBind.set(draft.doc, ["purposeId"], .string(added)) }
    }
  }

  private var showsLicenceClass: Bool {
    let checks = register.drivingLicences
    return doc.str("type") == "driving_licence" && (checks || draft.original.text("licenceClass") != nil)
  }

  private var costBinding: Binding<Double> {
    Binding(
      get: { doc["renewalCost"]?.double ?? 0 },
      set: { draft.doc = SwBind.set(draft.doc, ["renewalCost"], .number($0)) })
  }

  /// The reminders the type uses now (`reminderDaysFor`), as the placeholder.
  private var reminderPlaceholder: String {
    let type = doc.str("type")
    let days = register.reminderDaysByType[type] ?? register.reminderDays
    return days.map(String.init).joined(separator: ", ")
  }

  private var showsConfidential: Bool {
    doc.str("ownerType") != "employee"
      && ((extras && seesPeople) || draft.original["confidential"] == .bool(true))
      && SwComplianceGate.confidential
  }

  private var confidentialLocked: Bool {
    readOnly || draft.original["confidential"] == .bool(true) || !cloudReady
  }

  private var confidentialSwitch: some View {
    let description: String
    if draft.original["confidential"] == .bool(true) {
      description = t("A confidential document stays confidential.")
    } else if !cloudReady {
      description = t("The cloud needs the latest database script first. Ask the owner of the company to run it.")
    } else {
      description = t("Only owners, admins and accountants see it, with its files, renewals and activity.")
    }
    let binding = Binding(
      get: { draft.doc["confidential"] == .bool(true) },
      set: { (on: Bool) in
        draft.confidentialTouched = true
        draft.doc = SwBind.set(draft.doc, ["confidential"], .bool(on))
      })
    return Switch(t("Confidential"), description: description, isOn: binding)
      .disabled(confidentialLocked)
  }
}

/// A record's files: their names, and taking one off the list (removed once the record is saved).
struct SwFileRows: View {
  let ownerId: String
  @Binding var removed: [String]
  let model: AppModel
  var editable = true
  @Environment(\.palette) private var palette

  var body: some View {
    let files = model.one.records(.attachments).filter { $0.str("ownerId") == ownerId && !removed.contains($0.rid) }
    VStack(alignment: .leading, spacing: 8) {
      Text(t("Files")).font(.web(14, .medium)).foregroundStyle(palette.slate(700))
      if files.isEmpty {
        Text(t("Attach a scan of the document to keep it at hand.")).font(.web(14)).foregroundStyle(palette.slate(500))
      }
      ForEach(files.map(Rec.init)) { file in
        row(file.raw)
      }
    }
  }

  private func row(_ file: JSONValue) -> some View {
    HStack(spacing: 8) {
      IconView(.fileText, size: 16).foregroundStyle(palette.slate(400))
      Text(file.str("name")).font(.web(14)).foregroundStyle(palette.slate(800)).lineLimit(1)
      Spacer(minLength: 8)
      if editable && SwComplianceGate.files {
        WebButton(icon: .x, label: t("Remove {name}", ["name": file.str("name")]), variant: .ghost, size: .iconSmall) {
          removed.append(file.rid)
        }
      }
    }
  }
}

// MARK: Renewing

/// A paper being renewed (`RenewDialog`).
struct SwRenewing: Identifiable {
  let entry: SuEntry
  /// Who it belongs to, for the title.
  let owner: String
  var id: String { entry.key }
}

extension View {
  /// The renewal form, open while `renewing` is set.
  func swRenewDialog(_ renewing: Binding<SwRenewing?>, model: AppModel) -> some View {
    modifier(SwRenewDialog(renewing: renewing, model: model))
  }
}

private struct SwRenewDialog: ViewModifier {
  @Binding var renewing: SwRenewing?
  let model: AppModel
  @State private var form = SwRenewForm()
  @State private var saving = false

  func body(content: Content) -> some View {
    content
      .webDialog(isPresented: open, title: title, description: subtitle) {
        if let renewing {
          SwRenewFields(entry: renewing.entry, form: $form, model: model)
        }
      } footer: {
        WebButton(t("Cancel"), variant: .outline) { renewing = nil }
        WebButton(t("Renew"), loading: saving) { save() }
      }
      .onChange(of: renewing?.id, initial: true) { _, _ in
        if let renewing { form = SwRenewForm(renewing.entry) }
      }
  }

  private var open: Binding<Bool> {
    Binding(get: { renewing != nil }, set: { if !$0 { renewing = nil } })
  }

  private var title: String {
    t("Renew {document}", ["document": renewing.map { SuCompliance.title($0.entry) } ?? ""])
  }

  private var subtitle: String? {
    guard let renewing else { return nil }
    guard let expiry = renewing.entry.expiryDate else { return renewing.owner }
    return t("{owner} · expires {date}", ["owner": renewing.owner, "date": model.one.format.date(expiry)])
  }

  private func save() {
    guard let renewing else { return }
    let entry = renewing.entry
    form.error = nil
    if form.newExpiry.isEmpty || form.newExpiry <= (entry.expiryDate ?? form.renewedOn) {
      form.error = t("The new expiry date must be after the current one.")
      return
    }
    let input = form.input(entry, fees: SwComplianceGate.fees)
    let words = SwSave.words
    let document = SuCompliance.title(entry)
    let date = model.one.format.date(form.newExpiry)
    saving = true
    Task {
      do {
        try await model.one.write { ctx in try SwRenewals.renew(ctx, input, words: words) }
        model.confirm(t("{document} renewed until {date}", ["document": document, "date": date]))
        self.renewing = nil
      } catch {
        form.error = SwSave.message(error)
      }
      saving = false
    }
  }
}

/// What the renewal form holds.
struct SwRenewForm {
  var renewedOn = ISODates.today()
  var newExpiry = ""
  var number = ""
  var recordFee = true
  var fee: Double = 0
  /// The expense category; nil is the fee account (made when the company has none).
  var category: String?
  var paidFrom: String?
  var reference = ""
  var note = ""
  var error: String?

  init() {}

  init(_ entry: SuEntry) {
    newExpiry = Self.suggestedExpiry(entry)
    fee = entry.renewalCost
  }

  /// Passports usually last ten years; everything else is renewed for a year at a time.
  static func suggestedExpiry(_ entry: SuEntry) -> String {
    let today = ISODates.today()
    let base = (entry.expiryDate ?? "") > today ? (entry.expiryDate ?? today) : today
    guard let parts = SuDates.parts(base) else { return "" }
    let year = parts.year + (entry.type == "passport" ? 10 : 1)
    let day = min(parts.day, SuDates.daysIn(year: year, month: parts.month))
    return SuDates.iso(year, parts.month, day)
  }

  /// What `renewDocument` is asked; the fee only where expenses can be saved here (`fees`).
  func input(_ entry: SuEntry, fees: Bool) -> SwRenewInput {
    let typed = number.trimmingCharacters(in: .whitespacesAndNewlines)
    let recorded = recordFee && fee > 0 && fees
    return SwRenewInput(
      key: entry.key, newExpiry: newExpiry, renewedOn: renewedOn, number: typed.isEmpty ? nil : typed, note: note,
      fee: recorded
        ? SwRenewalFee(amount: fee, accountId: category, paidFromAccountId: paidFrom, reference: reference) : nil)
  }
}

private struct SwRenewFields: View {
  let entry: SuEntry
  @Binding var form: SwRenewForm
  let model: AppModel
  @Environment(\.palette) private var palette

  private static let newFeeAccount = "__fee_account__"

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Field(t("Renewed on")) {
        DateField(value: Binding(get: { form.renewedOn }, set: { if !$0.isEmpty { form.renewedOn = $0 } }))
      }
      Field(t("New expiry date")) { DateField(value: $form.newExpiry, min: entry.expiryDate) }
      if entry.type != "employment_contract" {
        Field(t("New document number"), hint: t("Only if the renewal changes it."), optional: true) {
          TextInput(text: $form.number, placeholder: entry.number)
        }
      }
      if SwComplianceGate.fees { feeBox }
      Field(t("Note"), optional: true) { SwTextArea(text: $form.note, lines: 2) }
      SwFormError(text: form.error)
    }
  }

  private var feeBox: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    return VStack(alignment: .leading, spacing: 16) {
      Switch(
        t("Record the fee as an expense"),
        description: t("Adds an expense paid from your bank or cash, so the books stay complete."), isOn: $form.recordFee)
      if form.recordFee {
        Field(t("Fee paid")) { SwNumberField(value: $form.fee) }
        Field(t("Paid from")) { Select(selection: paidFromBinding, options: paidFromOptions) }
        Field(t("Category")) {
          Combobox(
            selection: categoryBinding, options: categoryOptions, searchPlaceholder: t("Search accounts…"),
            emptyText: t("No matches"))
        }
        Field(t("Receipt number"), optional: true) { TextInput(text: $form.reference) }
      }
    }
    .padding(16)
    .border(palette.slate(200), in: shape)
  }

  private var accounts: [JSONValue] { model.one.records(.accounts) }

  private var feeAccount: JSONValue? {
    guard let company = model.one.company else { return nil }
    return SwRenewals.findFeeAccount(accounts, company: company, type: entry.type)
  }

  private static func byCode(_ a: JSONValue, _ b: JSONValue) -> Bool {
    a.str("code").compare(b.str("code"), options: .numeric) == .orderedAscending
  }

  /// `isPurchaseCategory`: costs and things bought, never an account the app manages itself.
  private static func isCategory(_ account: JSONValue) -> Bool {
    let managed: Set<String> = [
      "receivable", "payable", "bank", "cash", "credit_card", "output_tax", "input_tax", "tax_settlement",
      "retained_earnings", "opening_balance",
    ]
    if let role = account.text("role"), managed.contains(role) { return false }
    let type = account.str("type")
    if type == "cost_of_sales" || type.hasPrefix("expense") { return true }
    return type.hasPrefix("asset") && type != "asset_cash" && type != "asset_receivable"
  }

  private var categoryOptions: [ComboOption] {
    let chosen = form.category
    let list = accounts.filter { (Self.isCategory($0) && !$0.flag("archived")) || $0.rid == chosen }
      .sorted(by: Self.byCode)
      .map { ComboOption(value: $0.rid, label: "\($0.str("code")) \(localName($0))", keywords: "\($0.str("name")) \($0.str("nameAr"))") }
    guard feeAccount == nil else { return list }
    let spec = SwRenewals.feeAccountName(type: entry.type)
    let name = LanguageStore.shared.isArabic ? spec.nameAr : spec.name
    return [ComboOption(value: Self.newFeeAccount, label: name, detail: t("New account"), keywords: spec.name)] + list
  }

  private var categoryBinding: Binding<String?> {
    Binding(
      get: { form.category ?? feeAccount?.rid ?? Self.newFeeAccount },
      set: { value in
        let id = value ?? ""
        form.category = id.isEmpty || id == Self.newFeeAccount ? nil : id
      })
  }

  private var paidFromOptions: [SelectOption<String>] {
    let bank = accounts.first { $0.str("role") == "bank" }
    let first = bank.map { t("{account} (default)", ["account": localName($0)]) } ?? t("Default account")
    let money = accounts.filter { account in
      let type = account.str("type")
      let kind = type == "asset_cash" || type == "liability_credit_card"
      return kind && (!account.flag("archived") || account.rid == form.paidFrom) && account.rid != bank?.rid
    }
    let options = money.sorted(by: Self.byCode).map { SelectOption($0.rid, "\($0.str("code")) \(localName($0))") }
    return [SelectOption("", first)] + options
  }

  private var paidFromBinding: Binding<String> {
    Binding(get: { form.paidFrom ?? "" }, set: { form.paidFrom = $0.isEmpty ? nil : $0 })
  }
}

// MARK: A vehicle

/// A vehicle being added or edited (`VehicleDialog`'s state).
struct SwVehicleDraft: Identifiable {
  var vehicle: JSONValue
  let isNew: Bool
  let original: JSONValue
  var id: String { vehicle.rid }

  init(_ vehicle: JSONValue, isNew: Bool) {
    self.vehicle = vehicle
    original = vehicle
    self.isNew = isNew
  }
}

extension View {
  /// The vehicle form, open while `draft` is set.
  func swVehicleDialog(_ draft: Binding<SwVehicleDraft?>, model: AppModel) -> some View {
    modifier(SwVehicleDialog(draft: draft, model: model))
  }
}

private struct SwVehicleDialog: ViewModifier {
  @Binding var draft: SwVehicleDraft?
  let model: AppModel
  @State private var saving = false
  @State private var deleting = false

  func body(content: Content) -> some View {
    content.webDialog(
      isPresented: open, title: draft?.isNew == false ? t("Edit vehicle") : t("Add vehicle"),
      description: t("Its registration, insurance and other papers are kept with it.")
    ) {
      if let binding = Binding($draft) {
        SwVehicleFields(draft: binding, model: model, locked: locked)
          .webDialog(isPresented: $deleting, title: t("Delete this vehicle?"), description: t("This cannot be undone.")) {
            EmptyView()
          } footer: {
            SwConfirmFooter(label: t("Delete"), danger: true, onCancel: { deleting = false }) {
              deleting = false
              remove()
            }
          }
      }
    } footer: {
      footer
    }
  }

  private var open: Binding<Bool> {
    Binding(get: { draft != nil }, set: { if !$0 { draft = nil } })
  }

  /// View only, or a cloud without the records of version 16.
  private var locked: Bool {
    !SwAccess(model).edits || !(model.one.cloud?.has("tables_v16") ?? true)
  }

  @ViewBuilder
  private var footer: some View {
    if let current = draft, !current.isNew, !locked {
      WebButton(
        current.original.flag("archived") ? t("Restore") : t("Archive"),
        icon: current.original.flag("archived") ? .archiveRestore : .archive, variant: .ghost
      ) { archive(current) }
      WebButton(t("Delete"), icon: .trash2, variant: .ghost) { deleting = true }
    }
    WebButton(t("Cancel"), variant: .outline) { draft = nil }
    if !locked {
      WebButton(draft?.isNew == true ? t("Add vehicle") : t("Save"), loading: saving) { save() }
    }
  }

  private func save() {
    guard let current = draft else { return }
    let input = current.vehicle
    let cloud = model.one.cloud
    saving = true
    Task {
      let ok = await SwSave.run(model, done: current.isNew ? t("Vehicle added") : t("Vehicle saved")) { ctx in
        try SwVehicles.save(ctx, input, cloud: cloud)
      }
      saving = false
      if ok { draft = nil }
    }
  }

  private func archive(_ current: SwVehicleDraft) {
    let archived = !current.original.flag("archived")
    let id = current.original.rid
    let cloud = model.one.cloud
    Task {
      let ok = await SwSave.run(model, done: archived ? t("Vehicle archived") : t("Vehicle restored")) { ctx in
        try SwVehicles.setArchived(ctx, id: id, archived: archived, cloud: cloud)
      }
      if ok { draft = nil }
    }
  }

  private func remove() {
    guard let id = draft?.original.rid else { return }
    let cloud = model.one.cloud
    Task {
      let ok = await SwSave.run(model, done: t("Vehicle deleted")) { ctx in
        try SwVehicles.delete(ctx, id: id, cloud: cloud)
      }
      if ok { draft = nil }
    }
  }
}

private struct SwVehicleFields: View {
  @Binding var draft: SwVehicleDraft
  let model: AppModel
  let locked: Bool

  private var record: Binding<JSONValue> { $draft.vehicle }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Field(t("Plate number")) { TextInput(text: SwBind.text(record, ["plate"])) }
      Field(t("Make"), optional: true) { TextInput(text: SwBind.text(record, ["make"]), placeholder: "Toyota") }
      Field(t("Model"), optional: true) { TextInput(text: SwBind.text(record, ["model"]), placeholder: "Hilux") }
      Field(t("Year made"), optional: true) { SwNumberField(value: yearBinding, placeholder: "2022") }
      Field(t("Chassis number"), optional: true) { TextInput(text: SwBind.text(record, ["chassisNumber"])) }
      if Roles.canSeePeople(model.business.company?.role) {
        Field(t("Driver"), hint: t("Needs a valid driving licence when the company checks them."), optional: true) {
          Combobox(
            selection: SwBind.choice(record, ["driverEmployeeId"]),
            options: [ComboOption(value: "", label: t("No driver"))] + drivers, placeholder: t("Choose an employee…"),
            searchPlaceholder: t("Search employees…"), emptyText: t("No matches"))
        }
      }
      if !assets.isEmpty {
        Field(t("Fixed asset"), optional: true) {
          Select(selection: SwBind.optional(record, ["assetId"]), options: assetOptions)
        }
      }
      Field(t("Notes"), optional: true) { SwTextArea(text: SwBind.text(record, ["notes"]), lines: 2) }
    }
    .disabled(locked)
  }

  private var yearBinding: Binding<Double> {
    Binding(
      get: { draft.vehicle["year"]?.double ?? 0 },
      set: { draft.vehicle = SwBind.set(draft.vehicle, ["year"], $0 == 0 ? .null : .number($0)) })
  }

  private var drivers: [ComboOption] {
    let chosen = draft.vehicle.str("driverEmployeeId")
    let list = model.one.records(.employees).filter { $0.str("status") != "left" || $0.rid == chosen }
    return list.sorted { localName($0).localizedCompare(localName($1)) == .orderedAscending }.map { employee in
      ComboOption(
        value: employee.rid, label: localName(employee), detail: employee.str("number"),
        keywords: "\(employee.str("name")) \(employee.str("nameAr")) \(employee.str("jobTitle"))")
    }
  }

  private var assets: [JSONValue] {
    let chosen = draft.vehicle.str("assetId")
    return model.one.records(.assets)
      .filter { $0.str("status") == "active" || $0.rid == chosen }
      .sorted { $0.str("number").localizedCompare($1.str("number")) == .orderedAscending }
  }

  private var assetOptions: [SelectOption<String>] {
    [SelectOption("", t("Not in the asset register"))]
      + assets.map { SelectOption($0.rid, suJoin([$0.str("number"), localName($0)], " ")) }
  }
}
