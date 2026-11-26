import MahamKit
import SwiftUI

// The documents register and the compliance calendar (`src/lib/compliance.ts`,
// `src/db/renewals.ts`): papers that expire (company licences, employees'
// papers, vehicles…) and the statutory deadlines that follow from the
// financial year end and the legal form. Read from the records only.

// MARK: Types of document

enum SuDocTypes {
  /// Each type's name (an English key) and who it usually belongs to.
  static let labels: [String: String] = [
    "commercial_licence": "Commercial licence",
    "commercial_registration": "Commercial registration (CR)",
    "pam_company_file": "PAM company file",
    "authorised_signatories": "Authorised signatories",
    "pam_salary_certificate": "PAM salary certificate",
    "mof_tax_card": "MOF tax card",
    "tax_clearance": "Tax clearance certificate",
    "kcci_membership": "KCCI membership",
    "municipality_licence": "Municipality licence",
    "fire_licence": "Fire department licence",
    "lease_contract": "Lease contract",
    "civil_id": "Civil ID",
    "passport": "Passport",
    "residency": "Residency",
    "work_permit": "Work permit",
    "employment_contract": "Employment contract",
    "central_agency_card": "Central Agency review card",
    "health_insurance": "Health insurance",
    "driving_licence": "Driving licence",
    "vehicle_registration": "Vehicle registration",
    "vehicle_insurance": "Vehicle insurance",
    "company_contract": "Company contract",
    "client_contract": "Customer contract",
    "customer_cost": "Customer cost sheet",
    "other": "Other document",
  ]

  /// A type's name (English key); one a newer version saved is an other document.
  static func label(_ type: String) -> String { labels[type] ?? "Other document" }

  /// Whose a kind of owner is, in words (English key).
  static func ownerLabel(_ owner: String) -> String {
    switch owner {
    case "company": "Company"
    case "employee": "Employee"
    case "vehicle": "Vehicle"
    default: "Other"
    }
  }

  static let owners = ["company", "employee", "vehicle", "other"]
}

// MARK: Expiry

enum SuExpiryStatus: String, Sendable {
  case valid, expiring, expired
}

/// Valid, expiring (within the first reminder) or expired, and the days left.
struct SuExpiry: Sendable {
  let status: SuExpiryStatus
  /// Days to the expiry (negative once expired); nil without an expiry date.
  let daysLeft: Int?
}

// MARK: The register

/// A line of the register: a stored record (`doc:<id>`) or a paper on an
/// employee's file (`emp:<employeeId>:<type>`).
struct SuEntry: Identifiable, Sendable {
  let key: String
  let recordId: String?
  let employeeId: String?
  let type: String
  let title: String
  let number: String
  let issuer: String
  let issueDate: String?
  let expiryDate: String?
  let renewalCost: Double
  let reminderDays: [Int]
  let ownerType: String
  let ownerName: String
  var purposeId: String?
  var clientId: String?
  var vehicleId: String?
  var confidential = false
  var notes = ""
  var id: String { key }
}

/// A renewed paper whose new copy is missing.
struct SuNewCopy: Sendable {
  let renewedOn: String
  let due: String
}

/// A current employee who drives for work and holds no valid licence.
struct SuMissingLicence: Identifiable, Sendable {
  enum Reason: Sendable { case missing, expired, undated }
  let employeeId: String
  let reason: Reason
  let document: JSONValue?
  var id: String { employeeId }
}

/// The company's register, read once per page.
@MainActor
struct SuRegister {
  let company: JSONValue?
  let settings: JSONValue?
  let employees: [JSONValue]
  let documents: [JSONValue]
  let vehicles: [JSONValue]
  let reminderDays: [Int]
  let reminderDaysByType: [String: [Int]]
  let entries: [SuEntry]
  /// Files kept with each register record.
  let files: [String: Int]
  let newCopies: [String: SuNewCopy]
  /// The company checks that drivers hold a valid licence.
  let drivingLicences: Bool
  let missing: [SuMissingLicence]

  init(_ one: OneData, today: String = DocRules.today) {
    let company = one.company
    let settings = one.record(.peopleSettings, company?.rid ?? "") ?? one.records(.peopleSettings).first
    let employees = one.records(.employees)
    let documents = one.records(.complianceDocuments)
    let vehicles = one.records(.vehicles)
    let days = SuCompliance.normalizeReminderDays(settings?["reminderDays"])
    let byType = SuCompliance.reminderDaysByType(settings?["reminderDaysByType"])
    let entries = SuCompliance.registerEntries(
      employees: employees, documents: documents, reminderDays: days, byType: byType)
    let attachments = one.records(.attachments)
    var counts: [String: Int] = [:]
    for file in attachments { counts[file.str("ownerId"), default: 0] += 1 }
    let checks = settings?["drivingLicences"]?.bool == true
    self.company = company
    self.settings = settings
    self.employees = employees
    self.documents = documents
    self.vehicles = vehicles
    self.reminderDays = days
    self.reminderDaysByType = byType
    self.entries = entries
    self.files = counts
    self.newCopies = SuCompliance.newCopies(
      entries: entries, renewals: one.records(.renewals), files: attachments, settings: settings, on: today)
    self.drivingLicences = checks
    self.missing =
      checks
      ? SuCompliance.missingLicences(employees: employees, documents: documents, vehicles: vehicles, on: today) : []
  }

  /// Contracts, customers' papers, vehicles and confidential documents (Compliance → Settings).
  var extras: Bool { company?["registerExtras"]?.bool == true }

  func employee(_ id: String?) -> JSONValue? {
    guard let id, !id.isEmpty else { return nil }
    return employees.first { $0.rid == id }
  }

  func vehicle(_ id: String?) -> JSONValue? {
    guard let id, !id.isEmpty else { return nil }
    return vehicles.first { $0.rid == id }
  }

  /// Who a document belongs to, in the interface language (`entryOwner`):
  /// an employee, the company, a customer, the name on the paper, a vehicle's plate.
  func owner(_ entry: SuEntry, clients: [String: JSONValue] = [:]) -> String {
    if entry.ownerType == "employee" {
      let name = employee(entry.employeeId).map { localName($0) } ?? ""
      return name.isEmpty ? t("Employee") : name
    }
    if entry.ownerType == "company" { return company.map { localName($0) } ?? "" }
    if let id = entry.clientId, let client = clients[id] { return localName(client) }
    if !entry.ownerName.isEmpty { return entry.ownerName }
    let plate = vehicle(entry.vehicleId)?.str("plate") ?? ""
    return plate.isEmpty ? t(SuDocTypes.ownerLabel(entry.ownerType)) : plate
  }

  /// A purpose's name, or "" for none.
  func purpose(_ id: String?) -> String {
    guard let id, !id.isEmpty else { return "" }
    let purposes = company?.list("documentPurposes") ?? []
    return purposes.first { $0.rid == id }.map { localName($0) } ?? ""
  }
}

enum SuCompliance {
  static let defaultReminderDays = [60, 30, 7]
  static let maxReminders = 5

  /// Reminder days cleaned up (whole, positive, no repeats, largest first); none: 60, 30 and 7.
  static func normalizeReminderDays(_ value: JSONValue?) -> [Int] {
    let clean = cleanReminderDays(value)
    return clean.isEmpty ? defaultReminderDays : clean
  }

  /// Reminder days cleaned up, never filled in.
  static func cleanReminderDays(_ value: JSONValue?) -> [Int] {
    guard let list = value?.array else { return [] }
    var seen = Set<Int>()
    for item in list {
      let number = item.double ?? Double(item.string ?? "")
      guard let number, number.isFinite else { continue }
      let days = Int(number.rounded(.towardZero))
      if days > 0 { seen.insert(days) }
    }
    return seen.sorted(by: >)
  }

  /// The company's reminders by document type (#18).
  static func reminderDaysByType(_ value: JSONValue?) -> [String: [Int]] {
    guard let fields = value?.object else { return [:] }
    var out: [String: [Int]] = [:]
    for (type, days) in fields {
      let clean = Array(cleanReminderDays(days).prefix(maxReminders))
      if !type.isEmpty, !clean.isEmpty { out[type] = clean }
    }
    return out
  }

  /// A paper's own days, else its type's, else the company's.
  static func entryReminderDays(
    _ type: String, fallback: [Int], byType: [String: [Int]], override: JSONValue? = nil
  ) -> [Int] {
    let own = cleanReminderDays(override)
    if !own.isEmpty { return own }
    if let days = byType[type], !days.isEmpty { return days }
    return fallback
  }

  /// Valid, expiring (within the first reminder) or expired on `on`. A
  /// paper is still valid on its expiry date; without one it is valid.
  static func expiry(_ expiryDate: String?, _ reminderDays: [Int], on: String) -> SuExpiry {
    guard let expiryDate, !expiryDate.isEmpty else { return SuExpiry(status: .valid, daysLeft: nil) }
    guard let daysLeft = ISODates.daysBetween(on, expiryDate) else { return SuExpiry(status: .valid, daysLeft: nil) }
    if daysLeft < 0 { return SuExpiry(status: .expired, daysLeft: daysLeft) }
    let days = reminderDays.isEmpty ? defaultReminderDays : reminderDays
    let reached = days.contains { daysLeft <= $0 }
    return SuExpiry(status: reached ? .expiring : .valid, daysLeft: daysLeft)
  }

  // MARK: Employees

  static func isCurrent(_ employee: JSONValue) -> Bool { employee.str("status") != "left" }

  static func isStateless(_ employee: JSONValue) -> Bool {
    employee.flag("stateless") && employee.str("category") == "expat"
      && employee.str("nationality").trimmingCharacters(in: .whitespaces).isEmpty
  }

  static func needsResidency(_ employee: JSONValue) -> Bool {
    if isStateless(employee) { return false }
    let category = employee.str("category")
    return category == "expat" || category == "domestic"
  }

  static func needsWorkPermit(_ employee: JSONValue) -> Bool { employee.str("category") == "expat" }

  static func insuredWithPifss(_ employee: JSONValue) -> Bool {
    let category = employee.str("category")
    return category == "kuwaiti" || category == "gcc"
  }

  /// The papers on an employee's own record, as register entries: only
  /// those with a number or an expiry date.
  static func employeeEntries(_ employee: JSONValue, days: [Int], byType: [String: [Int]]) -> [SuEntry] {
    var out: [SuEntry] = []
    func add(_ type: String, _ numberKey: String?, _ expiryKey: String) {
      let number = numberKey.map { employee.str($0) } ?? ""
      let expiry = employee.text(expiryKey)
      guard !number.trimmingCharacters(in: .whitespaces).isEmpty || expiry != nil else { return }
      out.append(
        SuEntry(
          key: "emp:\(employee.rid):\(type)", recordId: nil, employeeId: employee.rid, type: type, title: "",
          number: number, issuer: "", issueDate: nil, expiryDate: expiry, renewalCost: 0,
          reminderDays: entryReminderDays(type, fallback: days, byType: byType), ownerType: "employee",
          ownerName: ""))
    }
    add("civil_id", "civilId", "civilIdExpiry")
    add("passport", "passportNumber", "passportExpiry")
    if needsResidency(employee) { add("residency", "residencyNumber", "residencyExpiry") }
    if needsWorkPermit(employee) { add("work_permit", "workPermitNumber", "workPermitExpiry") }
    if isStateless(employee) { add("central_agency_card", "centralCardNumber", "centralCardExpiry") }
    if employee.str("contractType") == "fixed", employee.text("contractEnd") != nil {
      add("employment_contract", nil, "contractEnd")
    }
    return out
  }

  /// A stored record as a register entry.
  static func recordEntry(_ doc: JSONValue, days: [Int], byType: [String: [Int]]) -> SuEntry {
    let type = doc.str("type")
    let owner = doc.str("ownerType")
    var entry = SuEntry(
      key: "doc:\(doc.rid)", recordId: doc.rid, employeeId: owner == "employee" ? doc.text("employeeId") : nil,
      type: type, title: doc.str("title"), number: doc.str("number"), issuer: doc.str("issuer"),
      issueDate: doc.text("issueDate"), expiryDate: doc.text("expiryDate"), renewalCost: doc.num("renewalCost"),
      reminderDays: entryReminderDays(type, fallback: days, byType: byType, override: doc["reminderDays"]),
      ownerType: owner, ownerName: doc.str("ownerName"))
    entry.purposeId = doc.text("purposeId")
    entry.clientId = doc.text("clientId")
    entry.vehicleId = doc.text("vehicleId")
    entry.confidential = doc["confidential"]?.bool == true
    entry.notes = doc.str("notes")
    return entry
  }

  /// Everything the register tracks: stored records not archived (of
  /// current employees, for theirs) and current employees' own papers.
  static func registerEntries(
    employees: [JSONValue], documents: [JSONValue], reminderDays: [Int], byType: [String: [Int]]
  ) -> [SuEntry] {
    let current = employees.filter(isCurrent)
    let ids = Set(current.map(\.rid))
    let stored = documents.filter { doc in
      !doc.flag("archived") && (doc.str("ownerType") != "employee" || ids.contains(doc.str("employeeId")))
    }
    let records = stored.map { recordEntry($0, days: reminderDays, byType: byType) }
    let papers = current.flatMap { employeeEntries($0, days: reminderDays, byType: byType) }
    return records + papers
  }

  /// A paper's name: its own title or the document type's.
  static func title(_ entry: SuEntry) -> String {
    let own = entry.title.trimmingCharacters(in: .whitespaces)
    return own.isEmpty ? t(SuDocTypes.label(entry.type)) : own
  }

  /// A stored record's name.
  static func title(_ doc: JSONValue) -> String {
    let own = doc.str("title").trimmingCharacters(in: .whitespaces)
    return own.isEmpty ? t(SuDocTypes.label(doc.str("type"))) : own
  }

  // MARK: The new copy of a renewed paper (#18)

  /// Renewed papers whose new copy is missing on `on`, by the entry's key.
  static func newCopies(
    entries: [SuEntry], renewals: [JSONValue], files: [JSONValue], settings: JSONValue?, on: String
  ) -> [String: SuNewCopy] {
    let grace = wholeDays(settings?["newCopyGraceDays"], max: 365)
    guard grace > 0 else { return [:] }
    let latest = latestRenewals(renewals)
    let since = settings?.text("newCopySince")
    var out: [String: SuNewCopy] = [:]
    for entry in entries {
      guard let renewal = latest[entry.key], let expiry = entry.expiryDate, renewal.str("newExpiry") == expiry
      else { continue }
      if let since, String(renewal.str("createdAt").prefix(10)) < since { continue }
      let due = ISODates.addDays(renewal.str("renewedOn"), grace)
      guard on > due else { continue }
      let copyId = renewal.text("newCopyId")
      let copied = files.contains { file in
        (copyId != nil && file.rid == copyId) || (file.str("docKey") == entry.key && (file.text("validUntil") ?? "") >= expiry)
      }
      if !copied { out[entry.key] = SuNewCopy(renewedOn: renewal.str("renewedOn"), due: due) }
    }
    return out
  }

  /// Each entry's latest renewal (the latest new expiry, then the latest made).
  static func latestRenewals(_ renewals: [JSONValue]) -> [String: JSONValue] {
    var latest: [String: JSONValue] = [:]
    for renewal in renewals {
      guard let key = renewal["documentKey"]?.string, let expiry = renewal["newExpiry"]?.string else { continue }
      guard let before = latest[key] else {
        latest[key] = renewal
        continue
      }
      let earlier = before.str("newExpiry")
      if expiry > earlier || (expiry == earlier && renewal.str("createdAt") > before.str("createdAt")) {
        latest[key] = renewal
      }
    }
    return latest
  }

  /// Whole days between 1 and `max`, or 0.
  static func wholeDays(_ value: JSONValue?, max: Int) -> Int {
    guard let number = value?.double, number.isFinite else { return 0 }
    let days = Int(number.rounded(.towardZero))
    return days >= 1 && days <= max ? days : 0
  }

  // MARK: Drivers' licences

  /// A job title compared without case, Arabic letter forms or punctuation.
  static func titleKey(_ text: String) -> String {
    let low: Unicode.Scalar = "\u{064B}"
    let high: Unicode.Scalar = "\u{0652}"
    let marks = CharacterSet(charactersIn: low...high).union(CharacterSet(charactersIn: "\u{0670}\u{0640}"))
    var kept = String.UnicodeScalarView()
    for scalar in text.lowercased().unicodeScalars where !marks.contains(scalar) {
      kept.append(scalar)
    }
    var key = String(kept)
    let forms: [(String, String)] = [("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ى", "ي"), ("ة", "ه")]
    for (from, to) in forms {
      key = key.replacingOccurrences(of: from, with: to)
    }
    let words = key.components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
    return words.filter { !$0.isEmpty }.joined(separator: " ")
  }

  /// The job title is a driver's ("Driver", "Bus Driver", سائق).
  static func isDriverTitle(_ employee: JSONValue) -> Bool {
    [employee.str("jobTitle"), employee.str("jobTitleAr"), employee.str("pamJobTitle")].contains { title in
      let key = titleKey(title)
      if key.isEmpty { return false }
      if key.contains("سائق") || key.contains("سايق") { return true }
      return key.split(separator: " ").contains { $0 == "driver" || $0 == "drivers" }
    }
  }

  /// The employee drives for work: their own setting, a vehicle they drive, their job title.
  static func requiresLicence(_ employee: JSONValue, vehicles: [JSONValue]) -> Bool {
    if let own = employee["drivingLicenceRequired"]?.bool { return own }
    if vehicles.contains(where: { !$0.flag("archived") && $0.str("driverEmployeeId") == employee.rid }) { return true }
    return isDriverTitle(employee)
  }

  /// The employee's licence that expires last (one without a date after every dated one).
  static func currentLicence(_ documents: [JSONValue], employeeId: String) -> JSONValue? {
    let held = documents.filter { doc in
      doc.str("type") == "driving_licence" && !doc.flag("archived") && doc.str("ownerType") == "employee"
        && doc.str("employeeId") == employeeId
    }
    return held.sorted(by: licenceOrder).first
  }

  static func licenceOrder(_ a: JSONValue, _ b: JSONValue) -> Bool {
    let (ea, eb) = (a.text("expiryDate"), b.text("expiryDate"))
    if (ea == nil) != (eb == nil) { return ea != nil }
    return (ea ?? "") > (eb ?? "")
  }

  /// Current employees who drive for work without a valid licence.
  static func missingLicences(
    employees: [JSONValue], documents: [JSONValue], vehicles: [JSONValue], on: String
  ) -> [SuMissingLicence] {
    var out: [SuMissingLicence] = []
    for employee in employees where isCurrent(employee) && requiresLicence(employee, vehicles: vehicles) {
      let licence = currentLicence(documents, employeeId: employee.rid)
      let expiry = licence?.text("expiryDate")
      if let expiry, expiry >= on { continue }
      let reason: SuMissingLicence.Reason = licence == nil ? .missing : expiry != nil ? .expired : .undated
      out.append(SuMissingLicence(employeeId: employee.rid, reason: reason, document: licence))
    }
    return out
  }
}

// MARK: Statutory deadlines

/// A deadline that follows from the year end or the month (PIFSS).
struct SuDeadline: Sendable {
  let key: String
  /// An English key; `vars` fill it.
  let title: String
  let vars: [String: String]
  /// The year end ("2026-12-31") or the month paid for ("2026-10").
  let period: String
  let monthly: Bool
  let dueDate: String
  let explanation: String
}

enum SuCalendarStatus: String, Sendable {
  case overdue, dueSoon, upcoming, done

  var label: String {
    switch self {
    case .overdue: "Overdue"
    case .dueSoon: "Due soon"
    case .upcoming: "Upcoming"
    case .done: "Done"
    }
  }

  var tone: StatusTone {
    switch self {
    case .overdue: .red
    case .dueSoon: .amber
    case .upcoming: .blue
    case .done: .green
    }
  }
}

/// A line of the calendar: a deadline or a paper that expires.
struct SuCalendarItem: Identifiable, Sendable {
  let key: String
  let dueDate: String
  let daysLeft: Int
  let status: SuCalendarStatus
  let deadline: SuDeadline?
  let entry: SuEntry?
  var id: String { key }
}

enum SuDeadlines {
  /// Statutory items within this many days are "due soon".
  static let dueSoonDays = 14
  static let overdueLookbackDays = 365

  /// What a company's deadlines depend on.
  struct Context: Sendable {
    var yearEndMonth = 12
    var yearEndDay = 31
    var legalForm = "wll"
    var foreignOwnership = 0.0
    var auditFilingMonths = 3.0
    var pifssDueDay = 15.0
    var pifss = false
  }

  @MainActor
  static func context(_ register: SuRegister) -> Context {
    var ctx = Context()
    let end = register.company?.obj("accounting")?.obj("fiscalYearEnd")
    ctx.yearEndMonth = end?["month"]?.int ?? 12
    ctx.yearEndDay = end?["day"]?.int ?? 31
    let profile = KuwaitRules.kuwaitProfile(register.company)
    ctx.legalForm = profile.str("legalForm")
    ctx.foreignOwnership = profile.num("foreignOwnershipPercent")
    ctx.auditFilingMonths = register.settings?.number("auditFilingMonths") ?? 3
    ctx.pifssDueDay = register.settings?.number("pifssDueDay") ?? 15
    let employer = !profile.str("pifssEmployerNumber").trimmingCharacters(in: .whitespaces).isEmpty
    let insured = register.employees.contains { SuCompliance.isCurrent($0) && SuCompliance.insuredWithPifss($0) }
    ctx.pifss = employer || insured
    return ctx
  }

  /// End of the financial year that ends in `year`.
  static func yearEnd(in year: Int, _ ctx: Context) -> String {
    let month = min(12, max(1, ctx.yearEndMonth == 0 ? 12 : ctx.yearEndMonth))
    let last = SuDates.daysIn(year: year, month: month)
    let day = min(last, max(1, ctx.yearEndDay == 0 ? last : ctx.yearEndDay))
    return SuDates.iso(year, month, day)
  }

  /// `day` of the month `months` after the month of `date` (within that month).
  static func dayOfMonthAfter(_ date: String, _ months: Int, _ day: Int) -> String {
    guard let start = SuDates.parts(date) else { return date }
    let target = SuDates.addMonths(year: start.year, month: start.month, months)
    let last = SuDates.daysIn(year: target.year, month: target.month)
    return SuDates.iso(target.year, target.month, min(day, last))
  }

  /// `months` after a date; a month end stays at the month end.
  static func monthsAfter(_ date: String, _ months: Int) -> String {
    guard let start = SuDates.parts(date) else { return date }
    let target = SuDates.addMonths(year: start.year, month: start.month, months)
    let last = SuDates.daysIn(year: target.year, month: target.month)
    let endOfMonth = start.day == SuDates.daysIn(year: start.year, month: start.month)
    return SuDates.iso(target.year, target.month, endOfMonth ? last : min(start.day, last))
  }

  static func filesAuditedStatements(_ form: String) -> Bool {
    form != "sole_proprietorship" && form != "freelance"
  }

  static func paysIncomeTax(_ ctx: Context) -> Bool {
    ctx.legalForm == "foreign_branch" || ctx.foreignOwnership > 0
  }

  private static let texts: [String: (title: String, explanation: String)] = [
    "audited_statements": (
      "Audited financial statements to MOCI",
      "Companies file their audited statements with the Ministry of Commerce each year; the licence renewal needs them."
    ),
    "income_tax_return": (
      "Income tax declaration",
      "Foreign shareholders’ share of the profit is taxed at 15%. The declaration is due by the 15th day of the fourth month after the year end."
    ),
    "income_tax_instalment": (
      "Income tax instalment {number} of 4",
      "The tax can be paid in four instalments: the 15th day of the 4th, 6th, 9th and 12th months after the year end."
    ),
    "zakat": (
      "Zakat return",
      "Kuwaiti shareholding companies pay Zakat of 1% of net profit, filed with the Ministry of Finance."
    ),
    "kfas": (
      "KFAS contribution",
      "Shareholding companies contribute 1% of net profit to the Kuwait Foundation for the Advancement of Sciences."
    ),
    "nlst": (
      "NLST return",
      "Companies listed on Boursa Kuwait pay the National Labour Support Tax of 2.5% of net profit."
    ),
    "pifss": (
      "PIFSS contributions",
      "Monthly social security contributions for Kuwaiti and GCC staff, paid to PIFSS by the due day of the next month."
    ),
  ]

  private static func deadline(
    _ rule: String, key: String, period: String, monthly: Bool, due: String, vars: [String: String] = [:]
  ) -> SuDeadline {
    let text = texts[rule] ?? (title: rule, explanation: "")
    return SuDeadline(
      key: "\(key):\(period)", title: text.title, vars: vars, period: period, monthly: monthly, dueDate: due,
      explanation: text.explanation)
  }

  /// The deadlines of the financial year ending on `end`.
  static func yearDeadlines(_ ctx: Context, _ end: String) -> [SuDeadline] {
    var out: [SuDeadline] = []
    func add(_ rule: String, _ due: String, key: String? = nil, vars: [String: String] = [:]) {
      out.append(deadline(rule, key: key ?? rule, period: end, monthly: false, due: due, vars: vars))
    }
    if filesAuditedStatements(ctx.legalForm) {
      let months = Int(ctx.auditFilingMonths.rounded(.towardZero))
      add("audited_statements", monthsAfter(end, max(1, months == 0 ? 3 : months)))
    }
    let fourth = dayOfMonthAfter(end, 4, 15)
    if paysIncomeTax(ctx) {
      add("income_tax_return", fourth)
      for (index, month) in [4, 6, 9, 12].enumerated() {
        add(
          "income_tax_instalment", dayOfMonthAfter(end, month, 15), key: "income_tax_instalment_\(index + 1)",
          vars: ["number": "\(index + 1)"])
      }
    }
    if KuwaitRules.isShareholding(ctx.legalForm) {
      add("zakat", fourth)
      add("kfas", fourth)
    }
    if ctx.legalForm == "ksc_listed" { add("nlst", fourth) }
    return out
  }

  /// The PIFSS payment for the contributions of `month` ("2026-10").
  static func pifssDeadline(_ month: String, _ ctx: Context) -> SuDeadline {
    let whole = Int(ctx.pifssDueDay.rounded(.towardZero))
    let day = min(28, max(1, whole == 0 ? 15 : whole))
    return deadline(
      "pifss", key: "pifss", period: month, monthly: true, due: dayOfMonthAfter("\(month)-01", 1, day))
  }

  /// Deadlines falling due from `from` to `to`, by due date.
  static func deadlines(_ ctx: Context, from: String, to: String) -> [SuDeadline] {
    guard to >= from, let first = SuDates.parts(from)?.year, let last = SuDates.parts(to)?.year else { return [] }
    var out: [SuDeadline] = []
    for year in (first - 2)...max(first - 2, last) {
      out += yearDeadlines(ctx, yearEnd(in: year, ctx))
    }
    if ctx.pifss {
      var cursor = dayOfMonthAfter(from, -1, 1)
      while cursor <= to {
        out.append(pifssDeadline(String(cursor.prefix(7)), ctx))
        cursor = dayOfMonthAfter(cursor, 1, 1)
      }
    }
    return out.filter { $0.dueDate >= from && $0.dueDate <= to }.sorted(by: deadlineOrder)
  }

  static func deadlineOrder(_ a: SuDeadline, _ b: SuDeadline) -> Bool {
    a.dueDate != b.dueDate ? a.dueDate < b.dueDate : a.key < b.key
  }

  /// The earliest due date reported as overdue: when the company started, at most a year back.
  static func overdueSince(_ createdAt: String, from: String) -> String {
    let started = String(createdAt.prefix(10))
    let lookback = ISODates.addDays(from, -overdueLookbackDays)
    return started > lookback ? started : lookback
  }

  /// The calendar from `from` for `days` days, with what is overdue.
  static func calendar(
    _ ctx: Context, entries: [SuEntry], marks: Set<String>, from: String, days: Int, overdueSince: String
  ) -> [SuCalendarItem] {
    let to = ISODates.addDays(from, max(0, days))
    let since = overdueSince < from ? overdueSince : from
    var items: [SuCalendarItem] = []
    for deadline in deadlines(ctx, from: since, to: to) {
      let done = marks.contains(deadline.key)
      let left = ISODates.daysBetween(from, deadline.dueDate) ?? 0
      if done && left < 0 { continue }
      let status = deadlineStatus(done: done, daysLeft: left)
      items.append(
        SuCalendarItem(
          key: deadline.key, dueDate: deadline.dueDate, daysLeft: left, status: status, deadline: deadline,
          entry: nil))
    }
    for entry in entries {
      guard let expiry = entry.expiryDate, expiry <= to else { continue }
      let info = SuCompliance.expiry(expiry, entry.reminderDays, on: from)
      items.append(
        SuCalendarItem(
          key: entry.key, dueDate: expiry, daysLeft: info.daysLeft ?? 0, status: itemStatus(info.status),
          deadline: nil, entry: entry))
    }
    return items.sorted { $0.dueDate != $1.dueDate ? $0.dueDate < $1.dueDate : $0.key < $1.key }
  }

  static func deadlineStatus(done: Bool, daysLeft: Int) -> SuCalendarStatus {
    if done { return .done }
    if daysLeft < 0 { return .overdue }
    return daysLeft <= dueSoonDays ? .dueSoon : .upcoming
  }

  static func itemStatus(_ status: SuExpiryStatus) -> SuCalendarStatus {
    switch status {
    case .expired: .overdue
    case .expiring: .dueSoon
    case .valid: .upcoming
    }
  }
}
