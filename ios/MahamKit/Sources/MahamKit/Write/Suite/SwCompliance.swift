import Foundation

/// The port of the documents register's writes (src/db/renewals.ts, the
/// register records, its extras and purposes, and the compliance marks;
/// src/db/files.ts): the same reads and writes, in the same order, refused
/// with the web's words.
public enum SwCompliance {
  // MARK: Register records

  /// `createComplianceDocument(companyId, overrides)`: a new register record
  /// for the form (its id and stamp are made when the form opens).
  public static func newDocument(
    companyId: String, id: String = newId(), stamp: String = Defaults.nowStamp(), _ overrides: [String: JSONValue] = [:]
  ) -> JSONValue {
    var fields: [String: JSONValue] = [
      "id": .string(id), "companyId": .string(companyId), "type": "commercial_licence", "title": "", "number": "",
      "issuer": "", "issueDate": .null, "expiryDate": .null, "renewalCost": 0, "reminderDays": .null,
      "ownerType": "company", "employeeId": .null, "ownerName": "", "notes": "", "archived": false,
      "createdAt": .string(stamp), "updatedAt": .string(stamp),
    ]
    for (key, value) in overrides { fields[key] = value }
    return .object(fields)
  }

  /// The title a document is known by (`doc.title || documentTypeInfo(doc.type).label`).
  static func titleOf(_ doc: [String: JSONValue]) -> String {
    let title = SwField.text(doc, "title")
    return title.isEmpty ? SwDocTypes.info(SwField.text(doc, "type")).label : title
  }

  /// The activity's refs for a document: its employee, and the mark of a confidential one.
  static func refs(_ doc: [String: JSONValue], confidential: Bool? = nil) -> ActivityRefs {
    ActivityRefs(
      employeeId: SwField.id(doc["employeeId"]), confidential: confidential ?? SwField.isTrue(doc, "confidential"))
  }

  /// `preparedDocument`: the document as it is saved, checked against the company's records.
  static func prepared(
    _ ctx: WriteContext, _ input: [String: JSONValue], existing: [String: JSONValue]?
  ) throws -> (company: [String: JSONValue], doc: [String: JSONValue]) {
    guard let company = ctx.get("companies", SwField.text(input, "companyId"))?.object else {
      throw WriteFailure("Company not found")
    }
    let companyId = SwField.text(company, "id")
    let type = SwField.text(input, "type")
    let ownerType = SwField.text(input, "ownerType")
    if SwDocTypes.info(type).fromEmployee {
      throw WriteFailure("Civil ID, passport, residency and work permit are kept on the employee’s page.")
    }
    if ownerType == "employee" {
      let employee = SwField.id(input["employeeId"]).flatMap { ctx.get("employees", $0)?.object }
      guard let employee, employee["companyId"] == .string(companyId) else {
        throw WriteFailure("Choose the employee the document belongs to.")
      }
    }
    var ownerName = ownerType == "employee" ? "" : SwText.trim(input["ownerName"]?.string)
    // A customer's paper is kept under Other, a vehicle's under its vehicle.
    let clientId = ownerType == "other" ? SwField.id(input["clientId"]) : nil
    if let clientId {
      guard let client = ctx.get("clients", clientId)?.object, client["companyId"] == .string(companyId) else {
        throw WriteFailure("Choose a customer of this company.")
      }
      ownerName = SwField.text(client, "name")
    } else if SwDocTypes.customerTypes.contains(type) {
      throw WriteFailure("Choose the customer the document belongs to.")
    }
    let vehicleId = ownerType == "vehicle" ? SwField.id(input["vehicleId"]) : nil
    if let vehicleId {
      guard let vehicle = ctx.get("vehicles", vehicleId)?.object, vehicle["companyId"] == .string(companyId) else {
        throw WriteFailure("Choose a vehicle of this company.")
      }
      ownerName = SwField.text(vehicle, "plate")
    }
    if ownerType == "vehicle" && ownerName.isEmpty {
      throw WriteFailure("Enter the vehicle’s plate number or name.")
    }
    if SwDocTypes.needsTitle(type) && SwText.trim(input["title"]?.string).isEmpty {
      throw WriteFailure("Enter the document’s title.")
    }
    let purposeId = SwField.id(input["purposeId"])
    if let purposeId, existing?["purposeId"] != .string(purposeId) {
      let purposes = company["documentPurposes"]?.array ?? []
      if !purposes.contains(where: { $0["id"] == .string(purposeId) }) {
        throw WriteFailure("Choose a purpose from the list.")
      }
    }
    if let issue = SwField.id(input["issueDate"]), let expiry = SwField.id(input["expiryDate"]),
      WebJS.less(expiry, issue)
    {
      throw WriteFailure("The expiry date is before the issue date.")
    }
    let confidential = existing.map { SwField.isTrue($0, "confidential") } == true || SwField.isTrue(input, "confidential")
    var doc = input
    doc["title"] = .string(SwText.trim(input["title"]?.string))
    doc["number"] = .string(SwText.trim(input["number"]?.string))
    doc["issuer"] = .string(SwText.trim(input["issuer"]?.string))
    // Only a driving licence has a class.
    if input["licenceClass"] != nil {
      doc["licenceClass"] = .string(type == "driving_licence" ? SwText.trim(input["licenceClass"]?.string) : "")
    }
    doc["ownerName"] = .string(ownerName)
    doc["employeeId"] = ownerType == "employee" ? (input["employeeId"] ?? .null) : .null
    // The links are written only once there is something to say.
    if input["clientId"] != nil || clientId != nil { doc["clientId"] = SwField.string(clientId) }
    if input["vehicleId"] != nil || vehicleId != nil { doc["vehicleId"] = SwField.string(vehicleId) }
    if input["purposeId"] != nil { doc["purposeId"] = SwField.string(purposeId) }
    if confidential {
      doc["confidential"] = true
    } else if input["confidential"] != nil {
      doc["confidential"] = false
    }
    let cost = max(0, WebJS.toNumber(input["renewalCost"]))
    doc["renewalCost"] = .number(SwMoney.round(cost, currency: SwField.text(company, "currency")))
    let hasDays = (input["reminderDays"]?.array?.isEmpty == false)
    doc["reminderDays"] = hasDays ? .array(SwReminders.normalize(input["reminderDays"]).map { .number($0) }) : .null
    doc["updatedAt"] = .string(ctx.stamp)
    if existing == nil { doc["createdAt"] = doc["updatedAt"] }
    return (company, doc)
  }

  /// `cloudKeepingConfidential`: the company's link to the cloud, once a
  /// confidential document may be kept there (its server has the records of
  /// version 16).
  @discardableResult
  static func cloudKeepingConfidential(_ cloud: SwCloud?) throws -> SwCloud? {
    if let cloud, !cloud.has("tables_v16") {
      throw WriteFailure(
        "The cloud needs the latest database script first. Ask the owner of the company to run it.")
    }
    return cloud
  }

  /// `saveComplianceDocument(input, { log })`: saves a register document;
  /// with `log` false no activity is written (imports). A document already
  /// in the cloud is made confidential with `makeConfidential`, never by
  /// saving it with the mark.
  @discardableResult
  public static func saveDocument(
    _ ctx: WriteContext, _ input: JSONValue, cloud: SwCloud?, log: Bool = true, words: I18n.Translator = .english
  ) throws -> JSONValue {
    let fields = SwField.fields(input)
    let existing = ctx.get("complianceDocuments", SwField.text(fields, "id"))?.object
    let doc = try prepared(ctx, fields, existing: existing).doc
    // A customer's cost sheet is kept confidential: never added where the mark can't be kept yet.
    if SwField.text(doc, "type") == "customer_cost" && existing?["type"] != .string("customer_cost") {
      try cloudKeepingConfidential(cloud)
    }
    if SwField.truthy(doc, "confidential") && existing.map({ SwField.isTrue($0, "confidential") }) != true {
      let link = try cloudKeepingConfidential(cloud)
      if link != nil && existing != nil {
        throw WriteFailure("This document is in the cloud already: make it confidential from its form.")
      }
      // Fees already recorded for it lose its name, number and note.
      if let existing {
        let renewals = renewalsOf(ctx, existing)
        let numbers =
          [SwField.text(existing, "number"), SwField.text(doc, "number")]
          + renewals.map { $0["number"]?.string ?? "" }
        scrubFees(ctx, renewals, numbers: numbers, words: words)
      }
    }
    ctx.put("complianceDocuments", .object(doc))
    guard log else { return .object(doc) }
    let id = SwField.text(doc, "id")
    ctx.logActivity(
      entity: "compliance", entityId: id, action: existing != nil ? "updated" : "created",
      message: ActivityMessage(
        existing != nil ? "Document {title} updated" : "Document {title} added", vars: ["title": titleOf(doc)]),
      refs: refs(doc))
    return .object(doc)
  }

  /// The renewals of a stored document (`where('documentKey').equals(recordKey(id))`, of its company).
  static func renewalsOf(_ ctx: WriteContext, _ doc: [String: JSONValue]) -> [[String: JSONValue]] {
    let key = JSONValue.string(SwDocTypes.recordKey(SwField.text(doc, "id")))
    let company = doc["companyId"]
    return ctx.all("renewals").compactMap(\.object).filter { $0["documentKey"] == key && $0["companyId"] == company }
  }

  /// `scrubFees`: the fees of these renewals as a confidential document's
  /// are recorded, without its name, number or note.
  static func scrubFees(
    _ ctx: WriteContext, _ renewals: [[String: JSONValue]], numbers: [String], words: I18n.Translator
  ) {
    let known = Set(numbers.map { SwText.trim($0) }.filter { !$0.isEmpty })
    for renewal in renewals {
      guard let expenseId = SwField.id(renewal["expenseId"]), let expense = ctx.get("expenses", expenseId)?.object
      else { continue }
      let description = words.t("Document renewal fee")
      let stored = SwField.text(expense, "reference")
      let reference = known.contains(SwText.trim(stored)) ? "" : stored
      if expense["description"] == .string(description) && expense["reference"] == .string(reference)
        && expense["notes"] == .string("")
      {
        continue
      }
      var next = expense
      next["description"] = .string(description)
      next["reference"] = .string(reference)
      next["notes"] = ""
      next["updatedAt"] = .string(ctx.stamp)
      ctx.put("expenses", .object(next))
    }
  }

  /// `setDocumentArchived(id, archived)`: stops (or resumes) tracking a document; it keeps its renewals.
  public static func setArchived(_ ctx: WriteContext, id: String, archived: Bool) {
    guard var doc = ctx.get("complianceDocuments", id)?.object else { return }
    doc["archived"] = .bool(archived)
    doc["updatedAt"] = .string(ctx.stamp)
    ctx.put("complianceDocuments", .object(doc))
    ctx.logActivity(
      entity: "compliance", entityId: id, action: archived ? "archived" : "restored",
      message: ActivityMessage(
        archived ? "Document {title} archived" : "Document {title} restored", vars: ["title": titleOf(doc)]),
      refs: refs(doc))
  }

  /// `deleteComplianceDocument(id)`: deletes a document added by mistake;
  /// renewed documents are archived instead.
  public static func deleteDocument(_ ctx: WriteContext, id: String) throws {
    guard let doc = ctx.get("complianceDocuments", id)?.object else { return }
    let key = JSONValue.string(SwDocTypes.recordKey(id))
    if ctx.all("renewals").contains(where: { $0["documentKey"] == key }) {
      throw WriteFailure("This document has renewals on record. Archive it instead.")
    }
    for file in ctx.all("attachments") where file["ownerId"] == .string(id) {
      if let fileId = file["id"]?.string { ctx.delete("attachments", fileId) }
    }
    ctx.delete("complianceDocuments", id)
    if SwField.isTrue(doc, "confidential") {
      // Once it is gone nothing else tells that its activity is private.
      let unmarked = ctx.all("activities").compactMap(\.object).filter {
        $0["entityId"] == .string(id) && $0["entity"] == .string("compliance") && $0["confidential"] != .bool(true)
      }
      for activity in unmarked {
        var marked = activity
        marked["confidential"] = true
        ctx.put("activities", .object(marked))
      }
    }
    ctx.logActivity(
      entity: "compliance", entityId: id, action: "deleted",
      message: ActivityMessage("Document {title} deleted", vars: ["title": titleOf(doc)]), refs: refs(doc))
  }

  /// `makeDocumentConfidential(input, { removedFiles })`: marks a document
  /// confidential with the changes in `input`. In the cloud, a document
  /// already saved is saved again under a new id with its renewals, files
  /// and activity, and the old ones are deleted. Every file must be on this
  /// device.
  @discardableResult
  public static func makeConfidential(
    _ ctx: WriteContext, _ input: JSONValue, cloud: SwCloud?, removedFiles: [String] = [],
    words: I18n.Translator = .english
  ) throws -> JSONValue {
    var fields = SwField.fields(input)
    let existing = ctx.get("complianceDocuments", SwField.text(fields, "id"))?.object
    let link = try cloudKeepingConfidential(cloud)
    guard let existing, !SwField.isTrue(existing, "confidential"), link != nil else {
      fields["confidential"] = true
      return try saveDocument(ctx, .object(fields), cloud: cloud, words: words)
    }
    let existingId = SwField.text(existing, "id")
    let oldKey = SwDocTypes.recordKey(existingId)
    let renewals = renewalsOf(ctx, existing).sorted { WebJS.less(SwField.text($0, "id"), SwField.text($1, "id")) }
    var ids: [String: String] = [existingId: ctx.newId()]
    for renewal in renewals { ids[SwField.text(renewal, "id")] = ctx.newId() }
    let removed = Set(removedFiles)
    // `where('ownerId').anyOf(…)`: by owner, then by id.
    let stored = ctx.all("attachments").compactMap(\.object)
      .filter { ids[SwField.text($0, "ownerId")] != nil && $0["ownerId"]?.string != nil }
      .sorted { a, b in
        let (oa, ob) = (SwField.text(a, "ownerId"), SwField.text(b, "ownerId"))
        if oa != ob { return WebJS.less(oa, ob) }
        return WebJS.less(SwField.text(a, "id"), SwField.text(b, "id"))
      }
    let files = stored.filter { !(SwField.text($0, "ownerId") == existingId && removed.contains(SwField.text($0, "id"))) }
    if files.contains(where: { !SwField.truthy($0, "dataUrl") }) {
      throw WriteFailure("Some of its files are not on this device yet. Open them once, then try again.")
    }
    let activities = ctx.all("activities").compactMap(\.object)
      .filter {
        ids[SwField.text($0, "entityId")] != nil && $0["entityId"]?.string != nil
          && $0["entity"] == .string("compliance") && $0["companyId"] == existing["companyId"]
      }
      .sorted { a, b in
        let (ea, eb) = (SwField.text(a, "entityId"), SwField.text(b, "entityId"))
        if ea != eb { return WebJS.less(ea, eb) }
        return WebJS.less(SwField.text(a, "id"), SwField.text(b, "id"))
      }

    let id = ids[existingId] ?? ""
    var edited = fields
    edited["id"] = .string(id)
    edited["confidential"] = true
    edited["createdAt"] = existing["createdAt"] ?? .null
    var doc = try prepared(ctx, edited, existing: existing).doc
    doc["createdAt"] = existing["createdAt"] ?? .null
    ctx.put("complianceDocuments", .object(doc))
    // Its files under new ids too: a renewal's new copy follows its file.
    var fileIds: [String: String] = [:]
    for file in files { fileIds[SwField.text(file, "id")] = ctx.newId() }
    for renewal in renewals {
      var copy = renewal
      copy["id"] = .string(ids[SwField.text(renewal, "id")] ?? "")
      copy["documentKey"] = .string(SwDocTypes.recordKey(id))
      copy["documentId"] = .string(id)
      if let copyId = SwField.id(renewal["newCopyId"]) {
        copy["newCopyId"] = SwField.string(fileIds[copyId])
      }
      ctx.put("renewals", .object(copy))
    }
    for file in files {
      var copy = file
      copy["id"] = .string(fileIds[SwField.text(file, "id")] ?? "")
      copy["ownerId"] = .string(ids[SwField.text(file, "ownerId")] ?? "")
      // The new copy is uploaded under its own id.
      copy.removeValue(forKey: "storagePath")
      copy.removeValue(forKey: "contentHash")
      copy.removeValue(forKey: "contentMissing")
      if file["docKey"] == .string(oldKey) { copy["docKey"] = .string(SwDocTypes.recordKey(id)) }
      ctx.put("attachments", .object(copy))
    }
    for activity in activities {
      var copy = activity
      copy["id"] = .string(ctx.newId())
      copy["entityId"] = .string(ids[SwField.text(activity, "entityId")] ?? "")
      copy["confidential"] = true
      ctx.put("activities", .object(copy))
    }
    scrubFees(
      ctx, renewals, numbers: [SwField.text(existing, "number")] + renewals.map { $0["number"]?.string ?? "" },
      words: words)
    for activity in activities { ctx.delete("activities", SwField.text(activity, "id")) }
    for file in stored { ctx.delete("attachments", SwField.text(file, "id")) }
    for renewal in renewals { ctx.delete("renewals", SwField.text(renewal, "id")) }
    ctx.delete("complianceDocuments", existingId)
    ctx.logActivity(
      entity: "compliance", entityId: id, action: "updated",
      message: ActivityMessage("Document {title} made confidential", vars: ["title": titleOf(doc)]),
      refs: refs(doc, confidential: true))
    return .object(doc)
  }

  // MARK: The register's extras

  /// `setRegisterExtras(companyId, on)`: contracts, customers' papers, vehicles and confidential documents.
  public static func setRegisterExtras(_ ctx: WriteContext, on: Bool) {
    guard var company = ctx.get("companies", ctx.companyId)?.object else { return }
    if SwField.isTrue(company, "registerExtras") == on { return }
    company["registerExtras"] = .bool(on)
    company["updatedAt"] = .string(ctx.stamp)
    ctx.put("companies", .object(company))
    ctx.logActivity(
      entity: "company", entityId: ctx.companyId, action: "updated",
      message: ActivityMessage(
        on
          ? "Contracts, customers and vehicles switched on in the register"
          : "Contracts, customers and vehicles switched off in the register"))
  }

  /// `setFileFinder(companyId, on)` (src/db/files.ts): the Files page and search over files and papers.
  public static func setFileFinder(_ ctx: WriteContext, on: Bool) {
    guard var company = ctx.get("companies", ctx.companyId)?.object else { return }
    if SwField.isTrue(company, "fileFinder") == on { return }
    company["fileFinder"] = .bool(on)
    company["updatedAt"] = .string(ctx.stamp)
    ctx.put("companies", .object(company))
    ctx.logActivity(
      entity: "company", entityId: ctx.companyId, action: "updated",
      message: ActivityMessage(
        on ? "Finding files and papers switched on" : "Finding files and papers switched off"))
  }

  /// `findPurpose(list, names, exceptId)`: the purpose with either of these names, in either language.
  public static func findPurpose(
    _ list: [JSONValue], name: String, nameAr: String?, exceptId: String? = nil
  ) -> JSONValue? {
    let keys = [name, nameAr ?? ""].map(SwText.normalizeSearch).filter { !$0.isEmpty }
    return list.first { purpose in
      if let exceptId, purpose["id"] == .string(exceptId) { return false }
      let names = [purpose["name"]?.string, purpose["nameAr"]?.string]
      return names.contains { keys.contains(SwText.normalizeSearch($0 ?? "")) }
    }
  }

  /// `saveDocumentPurposes(companyId, input)`: the list as edited in
  /// Compliance → Settings. Purposes are archived, never removed.
  @discardableResult
  public static func savePurposes(_ ctx: WriteContext, _ input: [JSONValue]) throws -> [JSONValue] {
    guard var company = ctx.get("companies", ctx.companyId)?.object else { throw WriteFailure("Company not found") }
    let before = company["documentPurposes"]?.array ?? []
    var list: [JSONValue] = []
    for item in input {
      let nameAr = SwText.tidy(item["nameAr"]?.string)
      let typed = SwText.tidy(item["name"]?.string)
      let name = typed.isEmpty ? nameAr : typed
      if name.isEmpty {
        // A row left empty: a new one is dropped, one in use keeps its name.
        if let kept = before.first(where: { $0["id"] == item["id"] }) {
          if WebJS.truthy(item["archived"]) {
            var archived = SwField.fields(kept)
            archived["archived"] = true
            list.append(.object(archived))
          } else {
            list.append(kept)
          }
        }
        continue
      }
      if let taken = findPurpose(list, name: name, nameAr: nameAr, exceptId: item["id"]?.string) {
        throw WriteFailure("There is already a purpose called {name}.", ["name": taken["name"]?.string ?? ""])
      }
      var purpose: [String: JSONValue] = ["id": item["id"] ?? .null, "name": .string(name), "nameAr": .string(nameAr)]
      if WebJS.truthy(item["archived"]) { purpose["archived"] = true }
      list.append(.object(purpose))
    }
    // One this list didn't have (added meanwhile on another screen) stays.
    for purpose in before where !list.contains(where: { $0["id"] == purpose["id"] }) { list.append(purpose) }
    if WebJS.json(.array(list)) == WebJS.json(.array(before)) { return before }
    company["documentPurposes"] = .array(list)
    company["updatedAt"] = .string(ctx.stamp)
    ctx.put("companies", .object(company))
    ctx.logActivity(
      entity: "company", entityId: ctx.companyId, action: "updated", message: ActivityMessage("Document purposes updated"))
    return list
  }

  /// `addDocumentPurpose(companyId, input)`: a purpose named like one on the
  /// list, in either language, is that one (restored when archived).
  @discardableResult
  public static func addPurpose(_ ctx: WriteContext, name typedName: String, nameAr typedArabic: String?) throws -> JSONValue {
    guard var company = ctx.get("companies", ctx.companyId)?.object else { throw WriteFailure("Company not found") }
    let nameAr = SwText.tidy(typedArabic)
    let typed = SwText.tidy(typedName)
    let name = typed.isEmpty ? nameAr : typed
    if name.isEmpty { throw WriteFailure("Enter the purpose’s name.") }
    let list = company["documentPurposes"]?.array ?? []
    if let same = findPurpose(list, name: name, nameAr: nameAr) {
      if !WebJS.truthy(same["archived"]) { return same }
      return try setPurposeArchived(ctx, id: same["id"]?.string ?? "", archived: false)
    }
    let purpose: JSONValue = ["id": .string(ctx.newId()), "name": .string(name), "nameAr": .string(nameAr)]
    company["documentPurposes"] = .array(list + [purpose])
    company["updatedAt"] = .string(ctx.stamp)
    ctx.put("companies", .object(company))
    ctx.logActivity(
      entity: "company", entityId: ctx.companyId, action: "updated",
      message: ActivityMessage("Document purpose {name} added", vars: ["name": name], arabic: ["name": nameAr]))
    return purpose
  }

  /// `setDocumentPurposeArchived(companyId, id, archived)`: documents keep it.
  @discardableResult
  public static func setPurposeArchived(_ ctx: WriteContext, id: String, archived: Bool) throws -> JSONValue {
    let company = ctx.get("companies", ctx.companyId)?.object
    let list = company?["documentPurposes"]?.array ?? []
    guard var fields = company, let found = list.first(where: { $0["id"] == .string(id) }) else {
      throw WriteFailure("Purpose not found")
    }
    var next = SwField.fields(found)
    if archived {
      next["archived"] = true
    } else {
      next.removeValue(forKey: "archived")
    }
    let updated = JSONValue.object(next)
    fields["documentPurposes"] = .array(list.map { $0["id"] == .string(id) ? updated : $0 })
    fields["updatedAt"] = .string(ctx.stamp)
    ctx.put("companies", .object(fields))
    return updated
  }

  // MARK: Statutory deadlines

  /// `markComplianceDone(companyId, key, { doneOn, note, label })`: a
  /// statutory deadline marked as done; `label` names it in the activity log.
  @discardableResult
  public static func markDone(
    _ ctx: WriteContext, key: String, doneOn: String? = nil, note: String? = nil, label: String? = nil
  ) -> JSONValue {
    let mark: JSONValue = [
      "id": .string("\(ctx.companyId):\(key)"), "companyId": .string(ctx.companyId), "key": .string(key),
      "doneOn": .string(doneOn ?? ctx.today), "note": .string(note.map { SwText.trim($0) } ?? ""),
      "createdAt": .string(ctx.stamp),
    ]
    ctx.put("complianceMarks", mark)
    let item = (label ?? "").isEmpty ? key : (label ?? key)
    ctx.logActivity(
      entity: "compliance", entityId: "\(ctx.companyId):\(key)", action: "done",
      message: ActivityMessage("{item} marked as done", vars: ["item": item]))
    return mark
  }

  /// `clearComplianceMark(companyId, key, label)`.
  public static func clearMark(_ ctx: WriteContext, key: String, label: String? = nil) {
    let id = "\(ctx.companyId):\(key)"
    guard ctx.get("complianceMarks", id) != nil else { return }
    ctx.delete("complianceMarks", id)
    let item = (label ?? "").isEmpty ? key : (label ?? key)
    ctx.logActivity(
      entity: "compliance", entityId: id, action: "reopened",
      message: ActivityMessage("{item} marked as not done", vars: ["item": item]))
  }
}
