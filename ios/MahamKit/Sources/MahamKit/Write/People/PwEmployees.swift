import Foundation

// Employees: the ports of src/db/people.ts (`createEmployee`,
// `newAllowance`, `saveEmployee`, leave brought forward, photos,
// `deleteEmployee`) and src/db/leave-openings.ts (the openings set for many
// employees at once).

public enum PwEmployees {
  // MARK: New records

  /// `createEmployee(companyId, overrides)`: a new employee as the form starts it.
  public static func create(companyId: String, today: String, now: Date = Date()) -> JSONValue {
    let stamp = Defaults.nowStamp(now)
    return [
      "id": .string(newId()), "companyId": .string(companyId), "number": "", "name": "", "nameAr": "",
      "nationality": "KW", "category": "kuwaiti", "birthDate": .null, "gender": .null, "civilId": "",
      "civilIdExpiry": .null, "passportNumber": "", "passportExpiry": .null, "residencyArticle": "18",
      "residencyNumber": "", "residencyExpiry": .null, "workPermitNumber": "", "pamJobTitle": "", "permitSalary": 0,
      "workPermitExpiry": .null, "jobTitle": "", "jobTitleAr": "", "department": "", "hireDate": .string(today),
      "probationEnd": .null, "contractType": "unlimited", "contractEnd": .null, "payBasis": "monthly",
      "basicSalary": 0, "allowances": [], "bank": "", "iban": "", "accountNumber": "", "pifssNumber": "",
      "phone": "", "email": "", "status": "active", "leavingDate": .null, "leavingReason": .null, "notes": "",
      "createdAt": .string(stamp), "updatedAt": .string(stamp),
    ]
  }

  /// `newAllowance(overrides)`.
  public static func newAllowance(name: String = "", nameAr: String = "", amount: Double = 0, countsForEos: Bool = true)
    -> JSONValue
  {
    [
      "id": .string(shortId()), "name": .string(name), "nameAr": .string(nameAr), "amount": .number(amount),
      "countsForEos": .bool(countsForEos),
    ]
  }

  /// `isStateless(employee)`.
  static func isStateless(_ e: JSONValue) -> Bool {
    e["stateless"]?.bool == true && e.pwStr("category") == "expat" && WebJS.trim(e.pwStr("nationality")).isEmpty
  }

  /// `compactAccountNumber`.
  static func compactAccount(_ value: String?) -> String {
    WebJS.removing(Money.normalizeDigits(value ?? "")) { WebJS.isSpace($0) || $0 == "-" }.uppercased()
  }

  // MARK: Saving

  /// `saveEmployee(input, { expectedUpdatedAt })`, then the letter drafts the
  /// company's templates ask for (`autoDrafts`), as the web makes them once
  /// the employee is saved.
  @discardableResult
  public static func save(
    _ ctx: WriteContext, _ input: JSONValue, expectedUpdatedAt: String? = nil, log: Bool = true,
    link: PwLink? = nil, text: PwText = .english
  ) throws -> JSONValue {
    let before = ctx.get("employees", input.pwId)
    let saved = try saveRecord(ctx, input, expectedUpdatedAt: expectedUpdatedAt, log: log)
    if log { PwLetters.autoDrafts(ctx, before: before, after: saved, link: link, text: text) }
    return saved
  }

  private static func saveRecord(_ ctx: WriteContext, _ input: JSONValue, expectedUpdatedAt: String?, log: Bool) throws
    -> JSONValue
  {
    guard let company = ctx.get("companies", input.pwStr("companyId")) else { throw pwFail("Company not found") }
    let name = WebJS.trim(input.pwStr("name"))
    if name.isEmpty { throw pwFail("Enter the employee’s name.") }
    let places = PwM.places(company.pwStr("currency"))
    let existing = ctx.get("employees", input.pwId)
    if let existing, let expectedUpdatedAt, existing["updatedAt"]?.string != expectedUpdatedAt {
      throw pwFail(
        "This employee was changed somewhere else after you opened the form. Reload the page to see the changes, then make yours again."
      )
    }
    if let existing, input.pwStr("status") != "left" {
      let settled = ctx.pwOf("finalSettlements", employee: existing.pwId).filter { $0.pwStr("status") != "reversed" }
      if !settled.isEmpty {
        throw pwFail(
          "{name} has a final settlement, so they stay marked as left. Reverse the settlement to make them current again.",
          ["name": existing.pwStr("name")])
      }
    }
    var e = input.pwFields
    let left = input.pwStr("status") == "left"
    e["name"] = .string(name)
    e["nameAr"] = .string(WebJS.trim(input.pwStr("nameAr")))
    e["number"] = .string(WebJS.trim(input.pwStr("number")))
    e["jobTitle"] = .string(WebJS.trim(input.pwStr("jobTitle")))
    e["jobTitleAr"] = .string(WebJS.trim(input.pwStr("jobTitleAr")))
    e["department"] = .string(WebJS.trim(input.pwStr("department")))
    e["civilId"] = .string(WebJS.removing(input.pwStr("civilId"), where: WebJS.isSpace))
    if let card = input["centralCardNumber"] { e["centralCardNumber"] = .string(WebJS.trim(card.string ?? "")) }
    e["iban"] = .string(Kuwait.compactIban(input.pwStr("iban")))
    e["accountNumber"] = .string(compactAccount(input.pwText("accountNumber")))
    e["birthDate"] = input.pwTruthy("birthDate") ? input["birthDate"]! : .null
    let gender = input.pwStr("gender")
    e["gender"] = gender == "male" || gender == "female" ? .string(gender) : .null
    e["photoId"] = existing.map { WebJS.present($0["photoId"]) ?? .null } ?? (WebJS.present(input["photoId"]) ?? .null)
    e["leaveOpening"] =
      existing.map { WebJS.present($0["leaveOpening"]) ?? .null } ?? (WebJS.present(input["leaveOpening"]) ?? .null)
    let phone = WebJS.trim(input.pwStr("phone"))
    e["phone"] = .string(phone.isEmpty ? "" : (Kuwait.normalizeKuwaitPhone(input.pwStr("phone")) ?? phone))
    e["email"] = .string(WebJS.trim(input.pwStr("email")))
    e["basicSalary"] = .number(PwM.round(max(0, input.pwNum("basicSalary")), places))
    e["permitSalary"] = .number(PwM.round(max(0, input.pwNum("permitSalary")), places))
    let allowances = input.pwList("allowances").map { a -> JSONValue in
      a.pwMerging([
        "name": .string(WebJS.trim(a.pwStr("name"))), "nameAr": .string(WebJS.trim(a.pwStr("nameAr"))),
        "amount": .number(PwM.round(max(0, a.pwNum("amount")), places)),
      ])
    }.filter { !$0.pwStr("name").isEmpty || !$0.pwStr("nameAr").isEmpty || $0.pwNum("amount") > 0 }
    e["allowances"] = .array(allowances)
    e["contractEnd"] = input.pwStr("contractType") == "fixed" ? (input["contractEnd"] ?? .null) : .null
    e["leavingDate"] = left ? (WebJS.present(input["leavingDate"]) ?? .string(ctx.today)) : .null
    e["leavingReason"] = left ? (WebJS.present(input["leavingReason"]) ?? .null) : .null
    e["updatedAt"] = .string(ctx.stamp)
    if !isStateless(.object(e)) { e["stateless"] = nil }
    if let days = e["annualLeaveDays"] {
      let value = days.double
      if value == nil || !(value!.isFinite) || value! <= 0 {
        e["annualLeaveDays"] = .null
      } else if value! < PwLeave.annualDays {
        throw pwFail("Annual leave can’t be less than 30 days a year (art. 70).")
      } else {
        e["annualLeaveDays"] = .number(PwM.round(min(366, value!), 2))
      }
    }
    if e["annualLeaveDaysFrom"] != nil && !WebJS.truthy(e["annualLeaveDays"]) { e["annualLeaveDaysFrom"] = .null }

    let others = ctx.pwAll("employees").filter { $0.pwId != input.pwId }
    let taken = Set(others.map { $0.pwStr("number").lowercased() })
    let number = e["number"]?.string ?? ""
    if !number.isEmpty && taken.contains(number.lowercased()) {
      throw pwFail("Employee number {number} is already used.", ["number": number])
    }
    if number.isEmpty {
      let stored = WebJS.present(company["numbering"]?["employee"])
      let rule = NumberingRule(stored ?? Numbering.defaultRules()["employee"]!.raw)
      let date = WebJS.present(e["hireDate"])?.string ?? ctx.today
      let allocated = Numbering.allocateNumber(rule, date) { taken.contains($0.lowercased()) }
      e["number"] = .string(allocated.number)
      var numbering = WebJS.spread(company["numbering"])
      numbering["employee"] = allocated.rule.raw
      ctx.put("companies", company.pwWith("numbering", .object(numbering)))
    }
    if existing == nil { e["createdAt"] = e["updatedAt"] }
    let employee = JSONValue.object(e)
    ctx.put("employees", employee)
    if !log { return employee }
    let vars: [String: PwLog.Var] = [
      "name": .text(employee.pwStr("name")), "number": .text(employee.pwStr("number")),
    ]
    let arabic: [String: String?] = ["name": employee.pwText("nameAr")]
    if existing == nil {
      PwLog.add(ctx, "employee", employee.pwId, "created", "Employee {name} ({number}) added", vars: vars, arabic: arabic)
    } else if existing?.pwStr("status") != "left" && employee.pwStr("status") == "left" {
      PwLog.add(
        ctx, "employee", employee.pwId, "left", "Employee {name} ({number}) marked as left", vars: vars, arabic: arabic)
    } else {
      PwLog.add(
        ctx, "employee", employee.pwId, "updated", "Employee {name} ({number}) updated", vars: vars, arabic: arabic)
    }
    return employee
  }

  // MARK: Leave brought forward

  /// `checkLeaveOpening`.
  static func checkOpening(date: String, days rawDays: Double) throws -> (date: String, days: Double) {
    if !PwDates.isDate(date) { throw pwFail("Enter the date.") }
    let days = PwM.jsRound(rawDays * 100) / 100
    if !days.isFinite || days < 0 { throw pwFail("Enter the number of days.") }
    return (date, days)
  }

  /// `putLeaveOpening`.
  @discardableResult
  static func putOpening(_ ctx: WriteContext, _ employee: JSONValue, date: String, days: Double, replace: Bool = false)
    -> JSONValue
  {
    let updated = employee.pwMerging([
      "leaveOpening": ["date": .string(date), "days": .number(days), "confirmed": true],
      "updatedAt": .string(ctx.stamp),
    ])
    ctx.put("employees", updated)
    if replace {
      for record in ctx.pwOf("leaveRecords", employee: employee.pwId)
      where PwLeave.isOpening(record) && !WebJS.less(record.pwStr("start"), date) {
        ctx.put("leaveRecords", record.pwMerging(["status": "cancelled", "updatedAt": .string(ctx.stamp)]))
      }
    }
    return updated
  }

  /// `setLeaveOpening(employeeId, { date, days })`.
  @discardableResult
  public static func setLeaveOpening(_ ctx: WriteContext, employeeId: String, date: String, days: Double) throws
    -> JSONValue
  {
    guard let employee = ctx.get("employees", employeeId) else {
      throw pwFail("This employee could not be found.")
    }
    let checked = try checkOpening(date: date, days: days)
    let updated = putOpening(ctx, employee, date: date, days: checked.days)
    PwLog.add(
      ctx, "employee", employee.pwId, "leave_opening", "Leave brought forward for {name}: {days} days on {date}",
      vars: ["name": .text(employee.pwStr("name")), "days": .number(checked.days), "date": .text(date)],
      arabic: ["name": employee.pwText("nameAr")])
    return updated
  }

  /// `setLeaveOpeningsFromSheet(companyId, entries)`: each one's own, replacing the one they had.
  @discardableResult
  public static func setLeaveOpeningsFromSheet(
    _ ctx: WriteContext, _ entries: [(employeeId: String, date: String, days: Double)]
  ) throws -> Int {
    let checked = try entries.map { entry -> (String, String, Double) in
      let opening = try checkOpening(date: entry.date, days: entry.days)
      return (entry.employeeId, opening.date, opening.days)
    }
    if checked.isEmpty { throw pwFail("There is nothing to set.") }
    var count = 0
    for (id, date, days) in checked {
      guard let employee = ctx.get("employees", id), employee.pwStr("companyId") == ctx.companyId else { continue }
      putOpening(ctx, employee, date: date, days: days, replace: true)
      count += 1
    }
    if count > 0 {
      let entity = ctx.newId()
      PwLog.add(
        ctx, "employee", entity, "leave_opening",
        count == 1
          ? "Leave brought forward set for {count} employee from a spreadsheet"
          : "Leave brought forward set for {count} employees from a spreadsheet",
        vars: ["count": .number(Double(count))])
    }
    return count
  }

  /// `setLeaveOpeningForEveryone(companyId, { date, days })`: everyone who needs one.
  @discardableResult
  public static func setLeaveOpeningForEveryone(_ ctx: WriteContext, date: String, days: Double) throws -> Int {
    let opening = try checkOpening(date: date, days: days)
    let targets = PwLeave.needingOpening(ctx.pwAll("employees"), ctx.pwAll("leaveRecords"))
    if targets.isEmpty { throw pwFail("Every current employee has an opening leave balance already.") }
    for employee in targets { putOpening(ctx, employee, date: opening.date, days: opening.days) }
    let entity = ctx.newId()
    PwLog.add(
      ctx, "employee", entity, "leave_opening",
      targets.count == 1
        ? "Leave brought forward set for {count} employee: {days} days on {date}"
        : "Leave brought forward set for {count} employees: {days} days on {date}",
      vars: ["count": .number(Double(targets.count)), "days": .number(opening.days), "date": .text(opening.date)])
    return targets.count
  }

  /// The employees who still need leave brought forward (`employeesNeedingLeaveOpening`).
  public static func needingOpening(employees: [JSONValue], records: [JSONValue]) -> [JSONValue] {
    PwLeave.needingOpening(employees, records)
  }

  // MARK: Photos

  /// `setEmployeePhoto(employeeId, { name, dataUrl })`: a small square JPEG, replacing the one they had.
  @discardableResult
  public static func setPhoto(_ ctx: WriteContext, employeeId: String, name: String, dataUrl: String) throws
    -> JSONValue
  {
    guard let employee = ctx.get("employees", employeeId) else {
      throw pwFail("This employee could not be found.")
    }
    let attachment: JSONValue = [
      "id": .string(ctx.newId()), "companyId": employee["companyId"] ?? .null, "ownerId": .string(employee.pwId),
      "name": .string(withoutExtension(name) + ".jpg"), "type": "image/jpeg",
      "size": .number(PwM.jsRound(Double(dataUrl.utf16.count) * 3 / 4)), "dataUrl": .string(dataUrl),
      "createdAt": .string(ctx.stamp),
    ]
    ctx.put("attachments", attachment)
    if let old = employee.pwText("photoId"), !old.isEmpty { ctx.delete("attachments", old) }
    let updated = employee.pwMerging(["photoId": .string(attachment.pwId), "updatedAt": .string(ctx.stamp)])
    ctx.put("employees", updated)
    return updated
  }

  /// `name.replace(/\.[a-z0-9]{1,5}$/i, '')`.
  static func withoutExtension(_ name: String) -> String {
    let units = Array(name.utf16)
    var i = units.count
    var length = 0
    while i > 0, length < 6 {
      let u = units[i - 1]
      let alnum = (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A)
      if !alnum { break }
      i -= 1
      length += 1
    }
    // The longest run of up to five letters or digits after a dot, as the pattern takes it.
    for take in stride(from: min(length, 5), through: 1, by: -1) {
      let dot = units.count - take - 1
      if dot >= 0 && units[dot] == 0x2E { return String(decoding: units[0..<dot], as: UTF16.self) }
    }
    return name
  }

  /// `removeEmployeePhoto(employeeId)`.
  public static func removePhoto(_ ctx: WriteContext, employeeId: String) {
    guard let employee = ctx.get("employees", employeeId), let photo = employee.pwText("photoId"), !photo.isEmpty
    else { return }
    ctx.delete("attachments", photo)
    ctx.put("employees", employee.pwMerging(["photoId": .null, "updatedAt": .string(ctx.stamp)]))
  }

  // MARK: Deleting

  /// `employeeHasPayrollHistory`: pay-run lines, loans, leave or a settlement.
  public static func hasPayrollHistory(_ ctx: WriteContext, _ employee: JSONValue) -> Bool {
    let id = employee.pwId
    let inRuns = ctx.all("payRuns").contains { run in
      run.pwStr("companyId") == employee.pwStr("companyId") && run.pwList("lines").contains { $0.pwStr("employeeId") == id }
    }
    return inRuns || !ctx.pwOf("staffLoans", employee: id).isEmpty || !ctx.pwOf("leaveRecords", employee: id).isEmpty
      || !ctx.pwOf("finalSettlements", employee: id).isEmpty
  }

  /// Issued or void letters, which keep their numbers.
  static func keptLetters(_ ctx: WriteContext, _ id: String) -> Int {
    ctx.pwOf("employeeLetters", employee: id).filter { $0.pwStr("status") != "draft" }.count
  }

  /// `deleteEmployee(id)`: the employee and everything about them.
  public static func delete(_ ctx: WriteContext, id: String, text: PwText = .english) throws {
    guard let employee = ctx.get("employees", id) else { return }
    if hasPayrollHistory(ctx, employee) {
      throw pwFail(
        "This employee has payroll records, which are part of the accounts. Mark them as left instead.")
    }
    if keptLetters(ctx, id) > 0 {
      throw pwFail(
        "This employee has letters issued to them, which keep their numbers. Mark them as left instead.")
    }
    let documents = ctx.pwOf("complianceDocuments", employee: id)
    let renewals = ctx.pwOf("renewals", employee: id)
    let owners = Set([id] + documents.map(\.pwId) + renewals.map(\.pwId))
    let files = ctx.all("attachments").filter { owners.contains($0.pwStr("ownerId")) }
    let names = [employee.pwStr("name"), employee.pwStr("nameAr")].filter { !WebJS.trim($0).isEmpty }
    func plain(_ text: String) -> String {
      WebJS.removing(Money.normalizeDigits(text)) { WebJS.isSpace($0) || $0 == "-" }.uppercased()
    }
    let numberList =
      [
        employee.pwStr("civilId"), employee.pwStr("passportNumber"), employee.pwStr("residencyNumber"),
        employee.pwStr("workPermitNumber"), employee.pwStr("centralCardNumber"),
      ] + documents.map { $0.pwStr("number") } + renewals.map { $0.pwStr("number") }
    let numbers = Set(numberList.map(plain).filter { !$0.isEmpty })
    let number = employee.pwStr("number")
    func unnamed(_ text: String) -> String {
      names.reduce(text) { out, name in out.components(separatedBy: name).joined(separator: number) }
    }
    for renewal in renewals {
      guard let expenseId = renewal.pwText("expenseId"), !expenseId.isEmpty, let expense = ctx.get("expenses", expenseId)
      else { continue }
      let reference = expense.pwStr("reference")
      let notes = expense.pwStr("notes")
      let trimmedNotes = WebJS.trim(notes)
      let scrubbed: [String: String] = [
        "description": text.t("Document renewal fee"),
        "reference": numbers.contains(plain(reference)) ? "" : unnamed(reference),
        "notes": !trimmedNotes.isEmpty && trimmedNotes == WebJS.trim(renewal.pwStr("note")) ? "" : unnamed(notes),
      ]
      if scrubbed["description"] != expense.pwStr("description") || scrubbed["reference"] != reference
        || scrubbed["notes"] != notes
      {
        ctx.put("expenses", expense.pwMerging(scrubbed.mapValues(JSONValue.string)).pwWith("updatedAt", .string(ctx.stamp)))
      }
    }
    for file in files { ctx.delete("attachments", file.pwId) }
    for activity in ctx.all("activities") {
      let about = owners.contains(activity.pwStr("entityId"))
      let mine = activity.pwStr("companyId") == employee.pwStr("companyId") && activity.pwStr("employeeId") == id
      if about || mine { ctx.delete("activities", activity.pwId) }
    }
    for renewal in renewals { ctx.delete("renewals", renewal.pwId) }
    for document in documents { ctx.delete("complianceDocuments", document.pwId) }
    for letter in ctx.pwOf("employeeLetters", employee: id) { ctx.delete("employeeLetters", letter.pwId) }
    ctx.delete("employees", id)
    PwLog.add(ctx, "employee", id, "deleted", "Employee {number} deleted", vars: ["number": .text(number)])
  }
}
