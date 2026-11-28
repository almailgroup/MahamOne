import Foundation

// Payroll settings, leave reasons, People settings and departments: the
// ports of src/db/payroll.ts (settings), src/db/people.ts (settings and
// departments), src/lib/hr/people-settings.ts, src/lib/hr/departments.ts,
// the reminder normalizers of src/lib/compliance.ts and the layouts of
// src/lib/hr/salary-file.ts.

public enum PwSettings {
  // MARK: Payroll settings

  static let lastDay = 31.0
  static let gccCountries = ["SA", "AE", "BH", "QA", "OM"]
  static let categoryKeys = ["kuwaiti", "gcc", "expat", "domestic"]
  static let salaryFileColumns = [
    "employeeNumber", "civilId", "nameEn", "nameAr", "iban", "accountNumber", "bankCode", "swift", "amount", "currency",
    "period", "pamFile", "reference",
  ]
  static let presets: [String: JSONValue] = [
    "wps": [
      "columns": [
        "employeeNumber", "civilId", "nameEn", "nameAr", "iban", "accountNumber", "bankCode", "amount", "period", "pamFile",
      ],
      "header": true, "periodFormat": "yyyymm",
    ],
    "transfer": [
      "columns": ["iban", "nameEn", "amount", "currency", "reference"], "header": true, "periodFormat": "yyyymm",
    ],
    "swift": [
      "columns": ["employeeNumber", "nameEn", "iban", "swift", "amount", "currency", "reference"], "header": true,
      "periodFormat": "mm/yyyy",
    ],
  ]

  /// `presetLayout(id)`.
  static func presetLayout(_ id: String) -> JSONValue {
    let key = presets[id] == nil ? "wps" : id
    return (presets[key] ?? .object([:])).pwWith("preset", .string(key))
  }

  /// `currentLayout(layout)`.
  static func currentLayout(_ layout: JSONValue?) -> JSONValue {
    let preset = layout?.pwStr("preset") ?? ""
    if presets[preset] != nil { return presetLayout(preset) }
    return layout ?? .null
  }

  /// `defaultPayrollSettings(companyId)`.
  static func defaultPayroll(companyId: String, stamp: String) -> [String: JSONValue] {
    [
      "id": .string(companyId), "companyId": .string(companyId), "dailyDivisor": 26, "rateBase": "wage",
      "pifss": [PwPay.pifss], "gcc": [], "minimumWage": 75, "payDay": 31, "bankAccountId": .null,
      "accounts": .object([:]), "provisions": true, "eosForInsured": false, "pamFileNumber": "",
      "salaryFile": presetLayout("wps"), "updatedAt": .string(stamp),
    ]
  }

  /// `getPayrollSettings(companyId)`: what is saved, with defaults for anything not set.
  public static func payroll(_ ctx: WriteContext) -> JSONValue {
    payroll(saved: ctx.get("payrollSettings", ctx.companyId), companyId: ctx.companyId, stamp: ctx.stamp)
  }

  /// `getPayrollSettings` of the record saved (nil when none is): the
  /// defaults with what is saved over them, as a settings form starts.
  public static func payroll(saved: JSONValue?, companyId: String, stamp: String) -> JSONValue {
    var settings = defaultPayroll(companyId: companyId, stamp: stamp)
    for (key, value) in WebJS.spread(saved) { settings[key] = value }
    settings["salaryFile"] = currentLayout(settings["salaryFile"])
    return .object(settings)
  }

  /// The day a new leave policy, new days a year or the pause of long
  /// unpaid leave start from: the first of next month (`nextMonthStart`).
  public static func nextMonthStart(_ today: String) -> String {
    let month = PwPay.periodOf(today)
    let year = Int(month.prefix(4)) ?? 1970
    let number = Int(month.suffix(2)) ?? 1
    let next = number == 12 ? (year + 1, 1) : (year, number + 1)
    return String(format: "%04d-%02d-01", next.0, next.1)
  }

  private static func percent(_ value: JSONValue?) -> Double {
    guard let n = value?.double, n.isFinite else { return 0 }
    return min(100, max(0, PwM.round(n, 3)))
  }

  private static func capOf(_ value: JSONValue?) -> JSONValue {
    guard let n = value?.double, n.isFinite, n > 0 else { return .null }
    return .number(PwM.round(n, 3))
  }

  private static func leaveDaysOf(_ n: Double) -> Double { PwM.round(min(366, n), 2) }

  private static func finite(_ value: JSONValue?) -> Double? {
    guard let n = value?.double, n.isFinite else { return nil }
    return n
  }

  /// `normalizeLeavePolicy`.
  static func normalizeLeavePolicy(_ input: JSONValue) -> JSONValue {
    var order: [String] = []
    var byDate: [String: JSONValue] = [:]
    for r in input.pwList("annualDays") {
      let from = r.pwStr("from")
      guard PwDates.isDate(r.pwText("from")), let days = finite(r["days"]) else { continue }
      if byDate[from] == nil { order.append(from) }
      byDate[from] = ["from": .string(from), "days": .number(leaveDaysOf(days))]
    }
    let dates = order.sorted(by: WebJS.less).compactMap { byDate[$0] }
    let cap = finite(input["carryForwardMax"])
    var out = input.pwFields
    out["annualDays"] = .array(dates)
    out["firstYearMonths"] = .number(PwM.whole(input.pwNumber("firstYearMonths"), 0, 9, 9))
    out["carryForwardMax"] = cap.map { $0 <= 0 ? JSONValue.null : .number(leaveDaysOf($0)) } ?? .null
    out["counting"] = input.pwStr("counting") == "calendar" ? "calendar" : "working"
    return .object(out)
  }

  /// `normalizeLeaveReasons`.
  static func normalizeLeaveReasons(_ input: [JSONValue]) -> [JSONValue] {
    var order: [String] = []
    var byId: [String: JSONValue] = [:]
    for r in input {
      guard case .object = r, let id = r.pwText("id"), !id.isEmpty else { continue }
      let pay = r.pwText("pay")
      let known = pay.map { PwLeave.reasonPay[$0] != nil } ?? false
      let all = r.pwList("categories")
      var categories: [JSONValue] = []
      for (i, c) in all.enumerated() {
        guard let text = c.string, categoryKeys.contains(text), all.firstIndex(of: c) == i else { continue }
        categories.append(c)
      }
      var fields = r.pwFields
      for key in ["maxDaysPerYear", "categories", "archived", "noteRequired"] { fields[key] = nil }
      fields["name"] = .string(WebJS.trim(r.pwStr("name")))
      fields["nameAr"] = .string(WebJS.trim(r.pwStr("nameAr")))
      fields["base"] = known ? .string(PwLeave.reasonBase(pay ?? "")) : (r["base"] ?? .null)
      if let max = finite(r["maxDaysPerYear"]), max > 0 { fields["maxDaysPerYear"] = .number(leaveDaysOf(max)) }
      if !categories.isEmpty { fields["categories"] = .array(categories) }
      if r.pwTruthy("noteRequired") { fields["noteRequired"] = true }
      if r.pwTruthy("archived") { fields["archived"] = true }
      if byId[id] == nil { order.append(id) }
      byId[id] = .object(fields)
    }
    return order.compactMap { byId[$0] }
  }

  /// `normalizePayrollSettings`.
  static func normalizePayroll(_ input: JSONValue) -> JSONValue {
    var pifssOrder: [String] = []
    var byDate: [String: JSONValue] = [:]
    for r in input.pwList("pifss") {
      guard PwDates.isDate(r.pwText("from")) else { continue }
      let from = r.pwStr("from")
      if byDate[from] == nil { pifssOrder.append(from) }
      byDate[from] = [
        "from": .string(from), "employer": .number(percent(r["employer"])), "employee": .number(percent(r["employee"])),
        "cap": capOf(r["cap"]),
      ]
    }
    var gccOrder: [String] = []
    var byCountry: [String: JSONValue] = [:]
    for s in input.pwList("gcc") {
      let country = s.pwStr("country").uppercased()
      guard gccCountries.contains(country) else { continue }
      if byCountry[country] == nil { gccOrder.append(country) }
      byCountry[country] = [
        "country": .string(country), "employer": .number(percent(s["employer"])),
        "employee": .number(percent(s["employee"])), "cap": capOf(s["cap"]),
      ]
    }
    let file = input["salaryFile"] ?? .object([:])
    let given = file.pwList("columns")
    var columns: [JSONValue] = []
    for (i, c) in given.enumerated() {
      guard let text = c.string, salaryFileColumns.contains(text), given.firstIndex(of: c) == i else { continue }
      columns.append(c)
    }
    var accounts: [String: JSONValue] = [:]
    for (key, id) in WebJS.spread(input["accounts"]) where PwAccountKey(rawValue: key) != nil && WebJS.truthy(id) {
      accounts[key] = id
    }
    var out = input.pwFields
    out["id"] = input["companyId"] ?? .null
    out["dailyDivisor"] = .number(PwM.whole(input.pwNumber("dailyDivisor"), 1, 31, PwPay.dailyDivisor))
    out["rateBase"] = input.pwStr("rateBase") == "basic" ? "basic" : "wage"
    out["pifss"] = .array(pifssOrder.sorted(by: WebJS.less).compactMap { byDate[$0] })
    out["gcc"] = .array(gccOrder.sorted(by: WebJS.less).compactMap { byCountry[$0] })
    out["minimumWage"] = .number(finite(input["minimumWage"]).map { max(0, PwM.round($0, 3)) } ?? 0)
    out["payDay"] = .number(PwM.whole(input.pwNumber("payDay"), 1, lastDay, lastDay))
    out["accounts"] = .object(accounts)
    out["pamFileNumber"] = .string(WebJS.trim(input.pwStr("pamFileNumber")))
    out["salaryFile"] = file.pwWith("columns", .array(columns.isEmpty ? ["iban", "amount"] : columns))
    if let policy = WebJS.present(input["leavePolicy"]), WebJS.truthy(policy) {
      out["leavePolicy"] = normalizeLeavePolicy(policy)
    }
    if let reasons = input["leaveReasons"], WebJS.truthy(reasons) {
      out["leaveReasons"] = .array(normalizeLeaveReasons(reasons.array ?? []))
    }
    if let pause = input["leaveAccrualPause"] {
      let from = pause["from"]?.string ?? ""
      out["leaveAccrualPause"] = PwDates.isDate(from) ? ["from": .string(from)] : .null
    }
    return .object(out)
  }

  /// `assertLeavePolicy`.
  private static func assertLeavePolicy(_ policy: JSONValue) throws {
    let days = policy.pwList("annualDays")
    if days.isEmpty { throw pwFail("Enter the date the leave policy applies from.") }
    if days.contains(where: { $0.pwNum("days") < PwLeave.annualDays }) {
      throw pwFail("Annual leave can’t be less than 30 days a year (art. 70).")
    }
  }

  /// `assertLeaveReasons`.
  private static func assertLeaveReasons(
    _ reasons: [JSONValue], _ saved: [JSONValue], _ records: [JSONValue], _ text: PwText
  ) throws {
    for r in reasons {
      if r.pwStr("name").isEmpty { throw pwFail("Enter the name of each leave reason.") }
      let before = saved.first { $0.pwId == r.pwId }
      let known = r.pwText("pay").map { PwLeave.reasonPay[$0] != nil } ?? false
      if !known && (before == nil || before?["pay"] != r["pay"]) {
        throw pwFail(
          "{name} was set up on a newer version of the app. Update the app to change it.",
          ["name": text.localName(r)])
      }
    }
    let used = Set(records.compactMap { $0.pwText("reasonId") }.filter { !$0.isEmpty })
    for before in saved where used.contains(before.pwId) {
      guard let now = reasons.first(where: { $0.pwId == before.pwId }) else {
        throw pwFail(
          "Leave is recorded with {name}, so it can’t be removed. Archive it instead.",
          ["name": text.localName(before)])
      }
      if now["pay"] != before["pay"] {
        throw pwFail(
          "Leave is recorded with {name}, so how it is paid can’t change. Archive it and add a new reason.",
          ["name": text.localName(before)])
      }
    }
  }

  /// `savePayrollSettings(input, activity)`.
  @discardableResult
  public static func savePayrollSettings(
    _ ctx: WriteContext, _ input: JSONValue, activity: String = "Payroll settings updated", text: PwText = .english
  ) throws -> JSONValue {
    var settings = normalizePayroll(input)
    settings.set("updatedAt", .string(ctx.stamp))
    if let policy = WebJS.present(settings["leavePolicy"]) { try assertLeavePolicy(policy) }
    let companyId = settings.pwStr("companyId")
    let saved = ctx.get("payrollSettings", companyId)
    let records = { ctx.all("leaveRecords").filter { $0.pwStr("companyId") == companyId } }
    func counting(_ s: JSONValue?) -> String { s?["leavePolicy"]?.pwText("counting") ?? "working" }
    if counting(settings) != counting(saved) {
      if PwLeave.annualLeaveRecorded(records()) {
        throw pwFail("Annual leave has been recorded, so the way it is counted can’t change.")
      }
    }
    let mine = WebJS.present(settings["leaveReasons"]) ?? .array([])
    let before = WebJS.present(saved?["leaveReasons"]) ?? .array([])
    if WebJS.json(mine) != WebJS.json(before) {
      try assertLeaveReasons(mine.array ?? [], before.array ?? [], records(), text)
    }
    ctx.put("payrollSettings", settings)
    PwLog.add(ctx, "payroll", settings.pwId, "settings", activity)
    return settings
  }

  /// `saveLeaveReasonSettings(companyId, changes)`: on top of the settings as they are now.
  @discardableResult
  public static func saveLeaveReasonSettings(_ ctx: WriteContext, _ changes: JSONValue, text: PwText = .english) throws
    -> JSONValue
  {
    let current = payroll(ctx)
    return try savePayrollSettings(ctx, current.pwMerging(changes.pwFields), activity: "Leave reasons updated", text: text)
  }

  /// `updateLeaveReasons(companyId, change)`: the list as it is now, changed.
  @discardableResult
  public static func updateLeaveReasons(
    _ ctx: WriteContext, text: PwText = .english, _ change: ([JSONValue]) -> [JSONValue]
  ) throws -> JSONValue {
    let current = payroll(ctx)
    let reasons = change(current.pwList("leaveReasons"))
    return try savePayrollSettings(
      ctx, current.pwWith("leaveReasons", .array(reasons)), activity: "Leave reasons updated", text: text)
  }

  /// `payRulesFor(settings, period)`.
  static func payRules(_ settings: JSONValue, _ period: String) -> JSONValue {
    [
      "dailyDivisor": settings["dailyDivisor"] ?? .null, "rateBase": settings["rateBase"] ?? .null,
      "pifss": PwPay.ratesOn(settings.pwList("pifss"), PwPay.periodStart(period)) ?? .null,
      "gcc": .array(settings.pwList("gcc")), "minimumWage": settings["minimumWage"] ?? .null,
    ]
  }

  // MARK: People settings

  static let defaultReminderDays: [Double] = [60, 30, 7]

  /// `defaultPeopleSettings` with what is saved over it (`getPeopleSettings`).
  static func people(_ ctx: WriteContext, _ companyId: String? = nil) -> JSONValue {
    let id = companyId ?? ctx.companyId
    var settings: [String: JSONValue] = [
      "id": .string(id), "companyId": .string(id), "kuwaitizationTarget": .null, "eosDailyDivisor": 26,
      "reminderDays": [60, 30, 7], "auditFilingMonths": 3, "pifssDueDay": 15, "updatedAt": .string(ctx.stamp),
    ]
    for (key, value) in WebJS.spread(ctx.get("peopleSettings", id)) { settings[key] = value }
    return .object(settings)
  }

  /// `cleanReminderDays`.
  static func cleanReminderDays(_ value: JSONValue?) -> [Double] {
    guard let list = value?.array else { return [] }
    var seen: [Double] = []
    for item in list {
      let day = PwM.trunc(WebJS.toNumber(item))
      guard day.isFinite, day > 0, !seen.contains(day) else { continue }
      seen.append(day)
    }
    return seen.sorted(by: >)
  }

  /// `wholeDays(value, max)`.
  static func wholeDays(_ value: JSONValue?, _ max: Double) -> Double {
    guard let n = value?.double, n.isFinite else { return 0 }
    let days = PwM.trunc(n)
    return days >= 1 && days <= max ? days : 0
  }

  /// `normalizePeopleSettings`.
  static func normalizePeople(_ input: JSONValue) -> JSONValue {
    var out = input.pwFields
    if let departments = input["departments"], WebJS.truthy(departments) {
      out["departments"] = .array(normalizeDepartments(departments))
    }
    out["id"] = input["companyId"] ?? .null
    let target = finite(input["kuwaitizationTarget"])
    out["kuwaitizationTarget"] = target.map { $0 <= 0 ? JSONValue.null : .number(min(100, PwM.round($0, 1))) } ?? .null
    out["eosDailyDivisor"] = .number(PwM.whole(input.pwNumber("eosDailyDivisor"), 1, 31, 26))
    var reminders = cleanReminderDays(input["reminderDays"])
    if reminders.isEmpty { reminders = defaultReminderDays }
    out["reminderDays"] = .array(reminders.prefix(5).map { .number($0) })
    out["auditFilingMonths"] = .number(PwM.whole(input.pwNumber("auditFilingMonths"), 1, 12, 3))
    out["pifssDueDay"] = .number(PwM.whole(input.pwNumber("pifssDueDay"), 1, 28, 15))
    for key in [
      "reminderDaysByType", "expiredRepeatDays", "newCopyGraceDays", "newCopySince", "expiryUpdates", "letters",
      "costing",
    ] {
      out[key] = nil
    }
    if case .object = input["costing"] ?? .null {
      out["costing"] = PwCosting.normalizeSettings(input["costing"] ?? .null, 3)
    }
    if let byType = input["reminderDaysByType"] {
      var clean: [String: JSONValue] = [:]
      if case .object(let types) = byType {
        for (type, days) in types {
          let list = cleanReminderDays(days).prefix(5)
          if !type.isEmpty && !list.isEmpty { clean[type] = .array(list.map { .number($0) }) }
        }
      }
      if !clean.isEmpty { out["reminderDaysByType"] = .object(clean) }
    }
    let repeatDays = wholeDays(input["expiredRepeatDays"], 90)
    if repeatDays > 0 { out["expiredRepeatDays"] = .number(repeatDays) }
    let grace = wholeDays(input["newCopyGraceDays"], 365)
    if grace > 0 {
      out["newCopyGraceDays"] = .number(grace)
      if PwDates.isDate(input.pwText("newCopySince")) { out["newCopySince"] = input["newCopySince"] }
    }
    if input["expiryUpdates"]?.bool == true { out["expiryUpdates"] = true }
    if input["letters"]?.bool == true { out["letters"] = true }
    return .object(out)
  }

  /// `savePeopleSettings(input)`: the search, departments, letters and costing keep what is saved.
  @discardableResult
  public static func savePeopleSettings(_ ctx: WriteContext, _ input: JSONValue) throws -> JSONValue {
    let companyId = input.pwStr("companyId")
    let stored = ctx.get("peopleSettings", companyId)
    var next = input.pwFields
    next["letters"] = nil
    if let letters = stored?["letters"] { next["letters"] = letters }
    next["costing"] = nil
    if let costing = stored?["costing"] { next["costing"] = costing }
    if let stored {
      next["groupSearch"] = nil
      next["departments"] = nil
      if let search = stored["groupSearch"] { next["groupSearch"] = search }
      if let departments = stored["departments"] { next["departments"] = departments }
    }
    if wholeDays(next["newCopyGraceDays"], 365) > 0 {
      let keep = WebJS.truthy(stored?["newCopyGraceDays"]) && WebJS.truthy(stored?["newCopySince"])
      next["newCopySince"] = keep ? (stored?["newCopySince"] ?? .null) : .string(ctx.today)
    }
    let settings = normalizePeople(.object(next)).pwWith("updatedAt", .string(ctx.stamp))
    ctx.put("peopleSettings", settings)
    PwLog.add(ctx, "compliance", settings.pwId, "settings", "Employee and compliance settings updated")
    return settings
  }

  /// `setGroupSearch(companyId, on)`.
  @discardableResult
  public static func setGroupSearch(_ ctx: WriteContext, _ on: Bool) -> JSONValue {
    let before = people(ctx)
    if (before["groupSearch"]?.bool == true) == on { return before }
    let settings = normalizePeople(before.pwWith("groupSearch", .bool(on))).pwWith("updatedAt", .string(ctx.stamp))
    ctx.put("peopleSettings", settings)
    PwLog.add(
      ctx, "payroll", settings.pwId, "settings",
      on ? "Employees included in the search across companies" : "Employees left out of the search across companies")
    return settings
  }

  // MARK: Departments

  /// `departmentKey(name)`.
  static func departmentKey(_ name: String?) -> String { PwPay.tidy(name).lowercased() }

  private static func tidyValue(_ value: JSONValue?) -> String { value?.string.map { PwPay.tidy($0) } ?? "" }

  /// `normalizeDepartments(list)`.
  static func normalizeDepartments(_ value: JSONValue?) -> [JSONValue] {
    guard let list = value?.array else { return [] }
    var seen = Set<String>()
    var out: [JSONValue] = []
    for item in list {
      guard case .object(var fields) = item else { continue }
      let archived = fields["archived"]?.bool == true
      fields["archived"] = nil
      let id = tidyValue(fields["id"])
      let nameAr = tidyValue(fields["nameAr"])
      let tidied = tidyValue(fields["name"])
      let name = tidied.isEmpty ? nameAr : tidied
      let key = name.lowercased()
      guard !id.isEmpty, !key.isEmpty, !seen.contains(key) else { continue }
      seen.insert(key)
      fields["id"] = .string(id)
      fields["name"] = .string(name)
      fields["nameAr"] = .string(nameAr)
      if archived { fields["archived"] = true }
      out.append(.object(fields))
    }
    return out
  }

  /// `findDepartment(list, name)`.
  static func findDepartment(_ list: [JSONValue], _ name: String?) -> JSONValue? {
    let key = departmentKey(name)
    if key.isEmpty { return nil }
    return list.first { departmentKey($0.pwText("name")) == key }
      ?? list.first { departmentKey($0.pwText("nameAr")) == key }
  }

  private static func departmentList(_ ctx: WriteContext) -> (settings: JSONValue, list: [JSONValue]) {
    let settings = people(ctx)
    return (settings, normalizeDepartments(settings["departments"]))
  }

  private static func putDepartments(_ ctx: WriteContext, _ settings: JSONValue, _ list: [JSONValue]) {
    let next = normalizePeople(settings.pwWith("departments", .array(list))).pwWith("updatedAt", .string(ctx.stamp))
    ctx.put("peopleSettings", next)
  }

  private static func checkNames(_ list: [JSONValue], name rawName: String, nameAr rawArabic: String?, except: String? = nil)
    throws -> (name: String, nameAr: String)
  {
    let nameAr = PwPay.tidy(rawArabic ?? "")
    let tidied = PwPay.tidy(rawName)
    let name = tidied.isEmpty ? nameAr : tidied
    if name.isEmpty { throw pwFail("Enter the department’s name.") }
    let others = list.filter { $0.pwId != except }
    for text in [name, nameAr] where !text.isEmpty {
      if let taken = findDepartment(others, text) {
        throw pwFail("There is already a department called {name}.", ["name": taken.pwStr("name")])
      }
    }
    return (name, nameAr)
  }

  private static func logDepartment(
    _ ctx: WriteContext, _ text: String, _ vars: [String: PwLog.Var], _ arabic: [String: String?] = [:]
  ) {
    let entity = ctx.newId()
    PwLog.add(ctx, "employee", entity, "departments", text, vars: vars, arabic: arabic)
  }

  /// `addDepartment`.
  @discardableResult
  public static func addDepartment(_ ctx: WriteContext, name: String, nameAr: String?) throws -> JSONValue {
    let (settings, list) = departmentList(ctx)
    let id = ctx.newId()
    let names = try checkNames(list, name: name, nameAr: nameAr)
    let department: JSONValue = ["id": .string(id), "name": .string(names.name), "nameAr": .string(names.nameAr)]
    putDepartments(ctx, settings, list + [department])
    logDepartment(ctx, "Department {name} added", ["name": .text(names.name)], ["name": names.nameAr])
    return department
  }

  /// `addDepartmentsInUse`: the departments employees have that aren't listed yet.
  @discardableResult
  public static func addDepartmentsInUse(_ ctx: WriteContext) -> Int {
    let (settings, list) = departmentList(ctx)
    var keys: [String] = []
    var spellings: [String: [(name: String, count: Int)]] = [:]
    for e in ctx.pwAll("employees") {
      let name = PwPay.tidy(e.pwText("department"))
      if name.isEmpty { continue }
      let key = departmentKey(name)
      if spellings[key] == nil {
        keys.append(key)
        spellings[key] = []
      }
      if let at = spellings[key]?.firstIndex(where: { $0.name == name }) {
        spellings[key]?[at].count += 1
      } else {
        spellings[key]?.append((name, 1))
      }
    }
    func byUse(_ a: (name: String, count: Int), _ b: (name: String, count: Int)) -> Int {
      if a.count != b.count { return b.count - a.count }
      let base = PwSort.baseCompare(a.name, b.name)
      return base != 0 ? base : PwSort.code(a.name, b.name)
    }
    let names = keys.compactMap { key in spellings[key].flatMap { PwSort.stable($0, by: byUse).first?.name } }
    let sorted = PwSort.stable(names) { PwSort.localeCompare($0, $1) }
    var added: [JSONValue] = []
    for name in sorted {
      if findDepartment(list + added, name) != nil { continue }
      added.append(["id": .string(ctx.newId()), "name": .string(name), "nameAr": ""])
    }
    if added.isEmpty { return 0 }
    putDepartments(ctx, settings, list + added)
    logDepartment(
      ctx, "Departments added from the employees: {names}",
      ["names": .text(added.map { $0.pwStr("name") }.joined(separator: ", "))])
    return added.count
  }

  /// `updateDepartment`: a new English name goes to every employee in the department.
  @discardableResult
  public static func updateDepartment(_ ctx: WriteContext, id: String, name: String, nameAr: String?) throws -> Int {
    let (settings, list) = departmentList(ctx)
    guard let before = list.first(where: { $0.pwId == id }) else {
      throw pwFail("This department could not be found.")
    }
    let names = try checkNames(list, name: name, nameAr: nameAr, except: id)
    let department = before.pwMerging(["name": .string(names.name), "nameAr": .string(names.nameAr)])
    var moved = 0
    let renamed = names.name != before.pwStr("name")
    if renamed {
      let key = departmentKey(before.pwText("name"))
      for e in ctx.pwAll("employees") where departmentKey(e.pwText("department")) == key {
        ctx.put("employees", e.pwMerging(["department": .string(names.name), "updatedAt": .string(ctx.stamp)]))
        moved += 1
      }
    }
    putDepartments(ctx, settings, list.map { $0.pwId == id ? department : $0 })
    if renamed {
      logDepartment(
        ctx, "Department {from} renamed {to}", ["from": .text(before.pwStr("name")), "to": .text(names.name)],
        ["from": before.pwText("nameAr"), "to": names.nameAr])
    } else if names.nameAr != before.pwStr("nameAr") {
      logDepartment(
        ctx, "Arabic name of the department {name} changed", ["name": .text(names.name)], ["name": names.nameAr])
    }
    return moved
  }

  /// `setDepartmentArchived`.
  public static func setDepartmentArchived(_ ctx: WriteContext, id: String, archived: Bool) throws {
    let (settings, list) = departmentList(ctx)
    guard let before = list.first(where: { $0.pwId == id }) else {
      throw pwFail("This department could not be found.")
    }
    if (before["archived"]?.bool == true) == archived { return }
    let department = before.pwWith("archived", archived ? .bool(true) : nil)
    putDepartments(ctx, settings, list.map { $0.pwId == id ? department : $0 })
    logDepartment(
      ctx, archived ? "Department {name} archived" : "Department {name} restored",
      ["name": .text(department.pwStr("name"))], ["name": department.pwText("nameAr")])
  }

  /// `mergeDepartment`: the employees of a name moved into a listed department.
  @discardableResult
  public static func mergeDepartment(_ ctx: WriteContext, from: String, into intoId: String) throws -> Int {
    let (settings, list) = departmentList(ctx)
    guard let into = list.first(where: { $0.pwId == intoId }) else {
      throw pwFail("This department could not be found.")
    }
    let key = departmentKey(from)
    if key.isEmpty || key == departmentKey(into.pwText("name")) {
      throw pwFail("Choose another department to merge into.")
    }
    var count = 0
    for e in ctx.pwAll("employees") where departmentKey(e.pwText("department")) == key {
      ctx.put("employees", e.pwMerging(["department": into["name"] ?? .null, "updatedAt": .string(ctx.stamp)]))
      count += 1
    }
    let merged = list.first { departmentKey($0.pwText("name")) == key }
    if let merged { putDepartments(ctx, settings, list.filter { $0.pwId != merged.pwId }) }
    logDepartment(
      ctx, "Department {from} merged into {to}",
      ["from": .text(merged?.pwStr("name") ?? PwPay.tidy(from)), "to": .text(into.pwStr("name"))],
      ["from": merged?.pwText("nameAr"), "to": into.pwText("nameAr")])
    return count
  }

  /// `assignDepartment`: employees put in a department (or in none).
  @discardableResult
  public static func assignDepartment(_ ctx: WriteContext, employeeIds: [String], name: String) -> Int {
    let (_, list) = departmentList(ctx)
    let department = findDepartment(list, name)?.pwStr("name") ?? PwPay.tidy(name)
    var changed: [JSONValue] = []
    for id in employeeIds {
      guard let e = ctx.get("employees", id), e.pwStr("companyId") == ctx.companyId,
        e["department"]?.string != department
      else { continue }
      changed.append(e.pwMerging(["department": .string(department), "updatedAt": .string(ctx.stamp)]))
    }
    if changed.isEmpty { return 0 }
    for e in changed { ctx.put("employees", e) }
    let count = changed.count
    let found = findDepartment(list, department)
    if !department.isEmpty {
      logDepartment(
        ctx, count == 1 ? "{count} employee moved to {department}" : "{count} employees moved to {department}",
        ["count": .number(Double(count)), "department": .text(department)], ["department": found?.pwText("nameAr")])
    } else {
      logDepartment(
        ctx,
        count == 1 ? "{count} employee taken out of their department" : "{count} employees taken out of their department",
        ["count": .number(Double(count))])
    }
    return count
  }
}
