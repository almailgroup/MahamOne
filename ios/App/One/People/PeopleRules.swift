import Foundation
import MahamKit

// The read side of Maham People, ported from the web's src/lib/hr
// (employees, departments, eosi), src/lib/compliance and
// src/apps/people/lib/directory: typed views over the raw records, and the
// figures the pages show. Nothing here writes a record.

// MARK: - Days

/// Calendar days written yyyy-MM-dd, with the arithmetic the web gets from
/// date-fns and JavaScript's `Date`: months added clamp to the month's last
/// day, days past a month's end roll into the next.
enum PeDates {
  static var today: String { ISODates.today() }

  /// The year, month and day of `yyyy-MM-dd`; nil for anything else.
  static func parts(_ value: String?) -> (year: Int, month: Int, day: Int)? {
    guard let value, value.utf8.count == 10 else { return nil }
    let pieces = value.split(separator: "-", omittingEmptySubsequences: false)
    guard pieces.count == 3, let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]) else {
      return nil
    }
    return (year, month, day)
  }

  static func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
  }

  static func floorMod(_ a: Int, _ b: Int) -> Int {
    let r = a % b
    return r < 0 ? r + b : r
  }

  /// Days since 1970-01-01 of `new Date(year, month - 1, day)`: months and
  /// days out of range roll over.
  static func number(_ year: Int, _ month: Int, _ day: Int) -> Int {
    let index = month - 1
    let fullYear = year + floorDiv(index, 12)
    let m = floorMod(index, 12) + 1
    let y = m <= 2 ? fullYear - 1 : fullYear
    let era = floorDiv(y, 400)
    let yoe = y - era * 400
    let mp = m > 2 ? m - 3 : m + 9
    let doy = (153 * mp + 2) / 5
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146_097 + doe - 719_468 + (day - 1)
  }

  /// Days since 1970-01-01 of a `yyyy-MM-dd` day.
  static func number(_ value: String?) -> Int? {
    guard let p = parts(value) else { return nil }
    return number(p.year, p.month, p.day)
  }

  /// The day `n` days after 1970-01-01.
  static func civil(_ n: Int) -> (year: Int, month: Int, day: Int) {
    let z = n + 719_468
    let era = floorDiv(z, 146_097)
    let doe = z - era * 146_097
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let day = doy - (153 * mp + 2) / 5 + 1
    let month = mp < 10 ? mp + 3 : mp - 9
    return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
  }

  static func pad(_ n: Int) -> String { n >= 0 && n < 10 ? "0" + String(n) : String(n) }

  static func text(_ year: Int, _ month: Int, _ day: Int) -> String {
    String(year) + "-" + pad(month) + "-" + pad(day)
  }

  static func text(_ n: Int) -> String {
    let d = civil(n)
    return text(d.year, d.month, d.day)
  }

  static func daysIn(_ year: Int, _ month: Int) -> Int {
    switch month {
    case 2: ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) ? 29 : 28
    case 4, 6, 9, 11: 30
    default: 31
    }
  }

  /// `addDaysISO`.
  static func addDays(_ value: String, _ days: Int) -> String {
    guard let n = number(value) else { return value }
    return text(n + days)
  }

  /// Calendar days from `from` to `to` (0 when either isn't a day).
  static func daysBetween(_ from: String, _ to: String) -> Int {
    guard let a = number(from), let b = number(to) else { return 0 }
    return b - a
  }

  /// date-fns `addMonths`: the same day, or the month's last when shorter.
  static func addMonths(_ value: String, _ months: Int) -> String {
    guard let n = number(value) else { return value }
    let d = civil(n)
    let index = d.month - 1 + months
    let year = d.year + floorDiv(index, 12)
    let month = floorMod(index, 12) + 1
    return text(year, month, min(d.day, daysIn(year, month)))
  }

  /// 0 for Sunday, as `Date.getDay()`.
  static func weekday(_ value: String) -> Int {
    guard let n = number(value) else { return 0 }
    return floorMod(n + 4, 7)
  }

  static func isLastDayOfMonth(_ n: Int) -> Bool {
    let d = civil(n)
    return d.day == daysIn(d.year, d.month)
  }

  /// date-fns `differenceInMonths(later, earlier)`: full months between.
  static func differenceInMonths(_ later: String, _ earlier: String) -> Int {
    guard let l = number(later), let e = number(earlier) else { return 0 }
    let sign = l > e ? 1 : (l < e ? -1 : 0)
    let ld = civil(l)
    let ed = civil(e)
    let difference = abs((ld.year - ed.year) * 12 + (ld.month - ed.month))
    if difference < 1 { return 0 }
    var working = ld
    if working.month == 2 && working.day > 27 {
      working = civil(number(working.year, working.month, 30))
    }
    let moved = number(working.year, working.month - sign * difference, working.day)
    let compared = moved > e ? 1 : (moved < e ? -1 : 0)
    var notFull = compared == -sign
    if isLastDayOfMonth(l) && difference == 1 && l > e { notFull = false }
    return sign * (difference - (notFull ? 1 : 0))
  }

  /// Whole months from `from` to the end of `on`.
  static func completedMonths(_ from: String, _ on: String) -> Int {
    if on < from { return 0 }
    return max(0, differenceInMonths(addDays(on, 1), from))
  }

  /// The month of a day: "2026-11".
  static func period(_ value: String) -> String { String(value.prefix(7)) }
}

// MARK: - Amounts

/// Amounts worked out as the web's `money.ts` does: decimals from the
/// number's shortest text, rounded half away from zero.
enum PeMoney {
  static func dec(_ value: Double) -> Decimal { Money.dec(value) }

  static func round(_ value: Decimal, _ places: Int) -> Double {
    Money.toNumber(Money.round(value, places))
  }

  static func round(_ value: Double, _ places: Int) -> Double {
    Money.toNumber(Money.round(value, places))
  }

  static func minor(_ value: Double, _ places: Int) -> Int64 { Money.toMinor(value, places) }

  static func fromMinor(_ minor: Int64, _ places: Int) -> Double {
    Money.toNumber(Money.fromMinor(minor, places))
  }

  /// `Math.round`.
  static func jsRound(_ value: Double) -> Double { (value + 0.5).rounded(.down) }

  /// To two places, as the leave balances are.
  static func twoPlaces(_ value: Double) -> Double { jsRound(value * 100) / 100 }

  static func sum(_ values: [Double]) -> Decimal {
    values.reduce(Decimal(0)) { $0 + Money.dec($1) }
  }
}

// MARK: - Records

/// An allowance on an employee's record.
struct PeAllowance: Identifiable {
  let id: String
  let name: String
  let nameAr: String?
  let amount: Double
  let countsForEos: Bool

  init(_ raw: JSONValue, index: Int) {
    id = raw.text("id") ?? "allowance-\(index)"
    name = raw.str("name")
    nameAr = raw.text("nameAr")
    amount = raw.num("amount")
    countsForEos = raw.flag("countsForEos")
  }

  var displayName: String { localName(name, nameAr) }
}

/// Annual leave brought forward when the leave history starts in the app.
struct PeLeaveOpening {
  let date: String
  let days: Double
  let confirmed: Bool
}

/// An employee and their personnel file (the web's `Employee`), read from the raw record.
struct PeEmployee: Identifiable {
  let raw: JSONValue

  init(_ raw: JSONValue) { self.raw = raw }

  var id: String { raw.rid }
  var number: String { raw.str("number") }
  var name: String { raw.str("name") }
  var nameAr: String? { raw.text("nameAr") }
  /// The name in the language on screen.
  var displayName: String { localName(name, nameAr) }
  var nationality: String { raw.str("nationality") }
  var category: String { raw.str("category") }
  var stateless: Bool { raw.flag("stateless") }
  var birthDate: String? { raw.text("birthDate") }
  var gender: String? { raw.text("gender") }
  var civilId: String { raw.str("civilId") }
  var civilIdExpiry: String? { raw.text("civilIdExpiry") }
  var passportNumber: String { raw.str("passportNumber") }
  var passportExpiry: String? { raw.text("passportExpiry") }
  var residencyArticle: String { raw.str("residencyArticle") }
  var residencyNumber: String { raw.str("residencyNumber") }
  var residencyExpiry: String? { raw.text("residencyExpiry") }
  var workPermitNumber: String { raw.str("workPermitNumber") }
  var workPermitExpiry: String? { raw.text("workPermitExpiry") }
  var pamJobTitle: String { raw.str("pamJobTitle") }
  var permitSalary: Double { raw.num("permitSalary") }
  var centralCardNumber: String { raw.str("centralCardNumber") }
  var centralCardExpiry: String? { raw.text("centralCardExpiry") }
  var jobTitle: String { raw.str("jobTitle") }
  var jobTitleAr: String? { raw.text("jobTitleAr") }
  /// The job title in the language on screen.
  var job: String { localName(jobTitle, jobTitleAr) }
  var drivingLicenceRequired: Bool? { raw["drivingLicenceRequired"]?.bool }
  var department: String { raw.str("department").trimmingCharacters(in: .whitespaces) }
  var hireDate: String? { raw.text("hireDate") }
  var probationEnd: String? { raw.text("probationEnd") }
  var contractType: String { raw.str("contractType") }
  var contractEnd: String? { raw.text("contractEnd") }
  var payBasis: String { raw.text("payBasis") ?? "monthly" }
  var basicSalary: Double { raw.num("basicSalary") }
  var allowances: [PeAllowance] {
    raw.list("allowances").enumerated().map { PeAllowance($0.element, index: $0.offset) }
  }
  var bank: String { raw.str("bank") }
  var iban: String { raw.str("iban") }
  var accountNumber: String { raw.str("accountNumber") }
  var pifssNumber: String { raw.str("pifssNumber") }
  var phone: String { raw.str("phone") }
  var email: String { raw.str("email") }
  var status: String { raw.text("status") ?? "active" }
  var leavingDate: String? { raw.text("leavingDate") }
  var leavingReason: String? { raw.text("leavingReason") }
  var notes: String { raw.str("notes") }
  var photoId: String? { raw.text("photoId") }
  var createdAt: String { raw.str("createdAt") }
  var annualLeaveDays: Double? { raw.number("annualLeaveDays") }
  var annualLeaveDaysFrom: String? { raw.text("annualLeaveDaysFrom") }
  var leaveOpening: PeLeaveOpening? {
    guard let opening = raw.obj("leaveOpening"), let date = opening.text("date") else { return nil }
    return PeLeaveOpening(date: date, days: opening.num("days"), confirmed: opening.flag("confirmed"))
  }

  /// Still on the books (active or on leave).
  var isCurrent: Bool { status != "left" }
}

/// A department of the company's list.
struct PeDepartment {
  let id: String
  let name: String
  let nameAr: String
  let archived: Bool

  var displayName: String { localName(name, nameAr) }
}

/// PIFSS rates, or a GCC national's home scheme.
struct PeRates: Sendable {
  var from: String
  var country: String
  var employer: Double
  var employee: Double
  var cap: Double?

  init(from: String, country: String = "", employer: Double, employee: Double, cap: Double?) {
    self.from = from
    self.country = country
    self.employer = employer
    self.employee = employee
    self.cap = cap
  }

  init(_ raw: JSONValue) {
    from = raw.str("from")
    country = raw.str("country").uppercased()
    employer = raw.num("employer")
    employee = raw.num("employee")
    cap = raw.number("cap")
  }

  /// `PAYROLL_RULES.pifss`.
  static let law = PeRates(from: "2026-01-01", employer: 11.5, employee: 10.5, cap: 2750)
}

/// Days of annual leave a year, from a date on.
struct PeAnnualDays: Sendable {
  let from: String
  let days: Double
}

/// How a company gives annual leave (`LeavePolicy`).
struct PeLeavePolicy: Sendable {
  var annualDays: [PeAnnualDays]
  var firstYearMonths: Int
  var carryForwardMax: Double?
  var counting: String

  init(annualDays: [PeAnnualDays], firstYearMonths: Int, carryForwardMax: Double?, counting: String) {
    self.annualDays = annualDays
    self.firstYearMonths = firstYearMonths
    self.carryForwardMax = carryForwardMax
    self.counting = counting
  }

  init(_ raw: JSONValue) {
    annualDays = raw.list("annualDays").compactMap { row in
      guard let from = row.text("from") else { return nil }
      return PeAnnualDays(from: from, days: row.num("days"))
    }
    firstYearMonths = Int(raw.number("firstYearMonths") ?? 9)
    let cap = raw.number("carryForwardMax")
    carryForwardMax = cap.flatMap { $0 > 0 ? $0 : nil }
    counting = raw.str("counting") == "calendar" ? "calendar" : "working"
  }

  /// `DEFAULT_LEAVE_POLICY`: the law's, until the company saves its own.
  static let law = PeLeavePolicy(annualDays: [], firstYearMonths: 9, carryForwardMax: nil, counting: "working")
}

/// One of the company's own leave reasons (D11).
struct PeLeaveReason: Identifiable {
  let raw: JSONValue

  init(_ raw: JSONValue) { self.raw = raw }

  var id: String { raw.rid }
  var name: String { raw.str("name") }
  var nameAr: String { raw.str("nameAr") }
  var displayName: String { localName(name, nameAr) }
  var archived: Bool { raw.flag("archived") }
  var base: String { raw.str("base") }
  var pay: String { raw.str("pay") }
  var maxDaysPerYear: Double? { raw.number("maxDaysPerYear").flatMap { $0 > 0 ? $0 : nil } }
  var categories: [String] { raw.list("categories").compactMap(\.string) }
  var noteRequired: Bool { raw.flag("noteRequired") }
}

/// The company's payroll settings, with the web's defaults for anything not saved
/// (`getPayrollSettings`).
struct PePayrollSettings {
  let raw: JSONValue?

  var dailyDivisor: Double { raw?.number("dailyDivisor") ?? 26 }
  var rateBase: String { raw?.text("rateBase") == "basic" ? "basic" : "wage" }
  var pifss: [PeRates] { raw?["pifss"]?.array.map { list in list.map { PeRates($0) } } ?? [PeRates.law] }
  var gcc: [PeRates] { (raw?.list("gcc") ?? []).map { PeRates($0) } }
  var minimumWage: Double { raw?.number("minimumWage") ?? 75 }
  var payDay: Int { Int(raw?.number("payDay") ?? 31) }
  var bankAccountId: String? { raw?.text("bankAccountId") }
  var accounts: [String: String] {
    var out: [String: String] = [:]
    for (key, value) in raw?.obj("accounts")?.object ?? [:] {
      if let id = value.string, !id.isEmpty { out[key] = id }
    }
    return out
  }
  var provisions: Bool { raw?["provisions"]?.bool ?? true }
  var eosForInsured: Bool { raw?["eosForInsured"]?.bool ?? false }
  var pamFileNumber: String { raw?.str("pamFileNumber") ?? "" }
  /// The saved policy, or nil for the law's.
  var leavePolicy: PeLeavePolicy? { raw?.obj("leavePolicy").map { PeLeavePolicy($0) } }
  var leaveReasons: [PeLeaveReason] { (raw?.list("leaveReasons") ?? []).map { PeLeaveReason($0) } }
  var leaveReasonsOn: Bool { raw?.flag("leaveReasonsOn") ?? false }
  /// From this day, a month of service with more than 15 days of unpaid leave earns no leave.
  var accrualPauseFrom: String? { raw?.obj("leaveAccrualPause")?.text("from") }
}

/// The company's People and compliance settings, with the web's defaults
/// (`withPeopleDefaults`).
struct PePeopleSettings {
  let raw: JSONValue?

  var kuwaitizationTarget: Double? { raw?.number("kuwaitizationTarget").flatMap { $0 > 0 ? $0 : nil } }
  var eosDailyDivisor: Double { raw?.number("eosDailyDivisor") ?? 26 }
  var reminderDays: [Int] { PeCompliance.normalizeReminderDays(raw?["reminderDays"]) }
  var pifssDueDay: Int { Int(raw?.number("pifssDueDay") ?? 15) }
  var departments: [PeDepartment] {
    (raw?.list("departments") ?? []).compactMap { item in
      let id = item.str("id").trimmingCharacters(in: .whitespaces)
      let nameAr = PePeople.tidy(item.str("nameAr"))
      let name = PePeople.tidy(item.str("name"))
      let english = name.isEmpty ? nameAr : name
      guard !id.isEmpty, !english.isEmpty else { return nil }
      return PeDepartment(id: id, name: english, nameAr: nameAr, archived: item.flag("archived"))
    }
  }
  var drivingLicences: Bool { raw?.flag("drivingLicences") ?? false }
  var reminderDaysByType: [String: [Int]] {
    var out: [String: [Int]] = [:]
    for (type, days) in raw?.obj("reminderDaysByType")?.object ?? [:] {
      let clean = Array(PeCompliance.cleanReminderDays(days).prefix(5))
      if !type.isEmpty, !clean.isEmpty { out[type] = clean }
    }
    return out
  }
  var letters: Bool { raw?.flag("letters") ?? false }
  var costing: PeCostingSettings { PeCostingSettings(raw?.obj("costing")) }
}

extension OneData {
  /// The company's employees.
  var peEmployees: [PeEmployee] { records(.employees).map { PeEmployee($0) } }

  /// One employee, by id.
  func peEmployee(_ id: String) -> PeEmployee? { record(.employees, id).map { PeEmployee($0) } }

  /// The company's payroll settings (one record per company, its id the company's).
  var pePayrollSettings: PePayrollSettings {
    let all = records(.payrollSettings)
    return PePayrollSettings(raw: all.first { $0.rid == companyId } ?? all.first)
  }

  /// The company's People settings.
  var pePeopleSettings: PePeopleSettings {
    let all = records(.peopleSettings)
    return PePeopleSettings(raw: all.first { $0.rid == companyId } ?? all.first)
  }

  /// Decimals of the company's currency (3 for KWD).
  var pePrecision: Int { Money.precision(company?.text("currency") ?? "KWD") }
}

// MARK: - Employees

/// Who an employee is under the law, in words (`src/lib/hr/employees.ts`).
enum PePeople {
  static let gccCountries = ["SA", "AE", "BH", "QA", "OM"]

  /// Stateless (Bedoon): the flag on an expatriate without a country.
  static func isStateless(_ e: PeEmployee) -> Bool {
    e.stateless && e.category == "expat" && e.nationality.trimmingCharacters(in: .whitespaces).isEmpty
  }

  static func needsResidency(_ e: PeEmployee) -> Bool {
    if isStateless(e) { return false }
    return e.category == "expat" || e.category == "domestic"
  }

  static func needsWorkPermit(_ e: PeEmployee) -> Bool { e.category == "expat" }

  static func insuredWithPifss(_ category: String) -> Bool { category == "kuwaiti" || category == "gcc" }

  static func underLabourLaw(_ category: String) -> Bool { category != "domestic" }

  /// The category in words; stateless staff are named so.
  static func categoryLabel(_ e: PeEmployee) -> String {
    if isStateless(e) { return t("Stateless (Bedoon)") }
    return categoryLabel(e.category)
  }

  static func categoryLabel(_ category: String) -> String {
    switch category {
    case "kuwaiti": t("Kuwaiti")
    case "gcc": t("GCC national")
    case "expat": t("Expatriate")
    case "domestic": t("Domestic worker")
    case "stateless": t("Stateless (Bedoon)")
    default: t("Other")
    }
  }

  /// The filters of the lists: the categories, and the stateless on their own.
  static let categoryFilters = ["kuwaiti", "gcc", "expat", "stateless", "domestic"]

  static func inCategory(_ e: PeEmployee, _ filter: String) -> Bool {
    switch filter {
    case "stateless": isStateless(e)
    case "expat": e.category == "expat" && !isStateless(e)
    default: e.category == filter
    }
  }

  static func statusLabel(_ status: String) -> String {
    switch status {
    case "active": t("Active")
    case "on_leave": t("On leave")
    case "left": t("Left")
    default: t("Other")
    }
  }

  static func statusTone(_ status: String) -> StatusTone {
    switch status {
    case "active": .green
    case "on_leave": .blue
    default: .slate
    }
  }

  static func genderLabel(_ gender: String) -> String {
    switch gender {
    case "male": t("Male")
    case "female": t("Female")
    default: ""
    }
  }

  static func contractLabel(_ type: String) -> String {
    type == "fixed" ? t("Fixed term") : t("Unlimited")
  }

  static func payBasisLabel(_ basis: String) -> String {
    switch basis {
    case "daily": t("Daily")
    case "hourly": t("Hourly")
    case "piece": t("Piece rate")
    default: t("Monthly")
    }
  }

  static let leavingReasons = [
    "resignation", "termination", "contract_end", "retirement", "dismissal", "death", "other",
  ]

  static func leavingReasonLabel(_ reason: String) -> String {
    switch reason {
    case "resignation": t("Resignation")
    case "termination": t("Ended by the employer")
    case "contract_end": t("End of fixed-term contract")
    case "retirement": t("Retirement")
    case "dismissal": t("Dismissal for a serious fault (art. 41)")
    case "death": t("Death")
    default: t("Other")
    }
  }

  static func residencyArticleLabel(_ article: String) -> String {
    switch article {
    case "18": t("Article 18 – private sector work")
    case "17": t("Article 17 – government work")
    case "19": t("Article 19 – partner or investor")
    case "20": t("Article 20 – domestic worker")
    case "22": t("Article 22 – family")
    case "24": t("Article 24 – self-sponsored")
    case "other": t("Other")
    default: ""
    }
  }

  /// The end-of-service rule of a leaving reason.
  static func eosiReason(_ reason: String) -> PeEosi.Reason {
    switch reason {
    case "resignation": .resignation
    case "dismissal": .dismissal
    default: .termination
    }
  }

  /// Basic salary and every allowance, to the currency's decimals.
  static func monthlyPay(_ e: PeEmployee, _ precision: Int) -> Double {
    PeMoney.round(PeMoney.sum(e.allowances.map(\.amount)) + PeMoney.dec(e.basicSalary), precision)
  }

  /// Headcount and the Kuwaiti share of the current staff (`workforceSummary`).
  struct Workforce {
    var headcount = 0
    var byCategory: [String: Int] = ["kuwaiti": 0, "gcc": 0, "expat": 0, "domestic": 0]
    var stateless = 0
    var kuwaitiShare: Double?

    func count(_ filter: String) -> Int {
      filter == "stateless" ? stateless : byCategory[filter] ?? 0
    }
  }

  static func workforce(_ employees: [PeEmployee]) -> Workforce {
    var summary = Workforce()
    let current = employees.filter(\.isCurrent)
    for e in current {
      if isStateless(e) {
        summary.stateless += 1
      } else if summary.byCategory[e.category] != nil {
        summary.byCategory[e.category, default: 0] += 1
      }
    }
    summary.headcount = current.count
    let labourLaw = current.count - (summary.byCategory["domestic"] ?? 0)
    if labourLaw > 0 {
      summary.kuwaitiShare = PeMoney.jsRound(Double(summary.byCategory["kuwaiti"] ?? 0) / Double(labourLaw) * 1000) / 10
    }
    return summary
  }

  // MARK: Departments

  /// Trimmed, with runs of spaces as one.
  static func tidy(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  static func departmentKey(_ name: String?) -> String { tidy(name ?? "").lowercased() }

  static func findDepartment(_ list: [PeDepartment], _ name: String?) -> PeDepartment? {
    let key = departmentKey(name)
    if key.isEmpty { return nil }
    return list.first { departmentKey($0.name) == key } ?? list.first { departmentKey($0.nameAr) == key }
  }

  /// A department in the language on screen: its Arabic name from the list, else as kept.
  static func departmentLabel(_ list: [PeDepartment], _ name: String?) -> String {
    if let found = findDepartment(list, name) { return found.displayName }
    return tidy(name ?? "")
  }

  /// The Arabic name of a department kept by its English name, when the list has one.
  static func arabicDepartment(_ list: [PeDepartment], _ name: String) -> String? {
    guard let found = findDepartment(list, name), departmentKey(found.name) == departmentKey(name),
      !found.nameAr.isEmpty
    else { return nil }
    return found.nameAr
  }

  /// First letters of the first and last words of a name ("Ali Hassan" → "AH").
  static func initials(_ name: String) -> String {
    let words = name.split(whereSeparator: \.isWhitespace)
    var letters: [String] = []
    if let first = words.first?.first { letters.append(String(first).uppercased()) }
    if words.count > 1, let last = words.last?.first { letters.append(String(last).uppercased()) }
    let arabic = letters.contains { $0.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) } }
    let joined = letters.joined(separator: arabic ? "\u{200C}" : "")
    return joined.isEmpty ? "?" : joined
  }
}

// MARK: - The directory

/// A contact card: only who someone is and how to reach them.
struct PeContact: Identifiable {
  let id: String
  let name: String
  let nameAr: String?
  let jobTitle: String
  let jobTitleAr: String?
  let department: String
  let departmentAr: String?
  let phone: String
  let email: String
  let onLeave: Bool

  var displayName: String { localName(name, nameAr) }
}

/// A department with its headcount.
struct PeDepartmentCount: Identifiable {
  let name: String
  let nameAr: String?
  var count: Int
  var id: String { name }
  var displayName: String { localName(name, nameAr) }
}

/// What comes up for someone in the next month.
struct PeMilestone: Identifiable {
  enum Kind: String { case probation, contract, joined }
  let employeeId: String
  let kind: Kind
  let date: String
  var id: String { employeeId + ":" + kind.rawValue }

  var label: String {
    switch kind {
    case .probation: t("Probation ends")
    case .contract: t("Contract ends")
    case .joined: t("Starts")
    }
  }
}

/// The staff directory (`src/apps/people/lib/directory.ts`).
enum PeDirectory {
  /// Approved leave covering a day: who is away, and on what.
  static func awayOn(_ records: [PeLeaveRecord], _ day: String) -> [String: PeLeaveRecord] {
    var away: [String: PeLeaveRecord] = [:]
    for r in records where r.kind == "leave" && r.status == "approved" && r.start <= day && day <= r.end {
      away[r.employeeId] = r
    }
    return away
  }

  /// The current staff as contacts, by name.
  static func contacts(_ employees: [PeEmployee], away: Set<String>, list: [PeDepartment]) -> [PeContact] {
    employees.filter(\.isCurrent)
      .map { e in
        PeContact(
          id: e.id, name: e.name, nameAr: e.nameAr, jobTitle: e.jobTitle, jobTitleAr: e.jobTitleAr,
          department: e.department, departmentAr: PePeople.arabicDepartment(list, e.department), phone: e.phone,
          email: e.email, onLeave: away.contains(e.id) || e.status == "on_leave")
      }
      .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
  }

  /// Departments with their headcount, the biggest first; "" for those without one.
  static func departments(_ contacts: [PeContact]) -> [PeDepartmentCount] {
    var groups: [String: PeDepartmentCount] = [:]
    for c in contacts {
      if groups[c.department] != nil {
        groups[c.department]?.count += 1
      } else {
        groups[c.department] = PeDepartmentCount(name: c.department, nameAr: c.departmentAr, count: 1)
      }
    }
    return groups.values.sorted { a, b in
      a.count != b.count ? a.count > b.count : a.name.localizedCompare(b.name) == .orderedAscending
    }
  }

  /// Contacts matching every word typed (phone numbers however they are spaced) and the department chosen.
  static func find(_ contacts: [PeContact], query: String, department: String?) -> [PeContact] {
    let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
    return contacts.filter { c in
      if let department, c.department != department { return false }
      if words.isEmpty { return true }
      let text = [c.name, c.nameAr ?? "", c.jobTitle, c.jobTitleAr ?? "", c.department, c.departmentAr ?? "", c.email]
        .joined(separator: " ")
      let phone = digits(c.phone)
      return words.allSatisfy { word in
        if text.matches(word) { return true }
        let typed = digits(word)
        return !typed.isEmpty && phone.contains(typed)
      }
    }
  }

  /// Letters and digits only, for numbers typed with or without their spaces.
  static func digits(_ text: String) -> String {
    String(String.UnicodeScalarView(Money.normalizeDigits(text).lowercased().unicodeScalars.filter {
      CharacterSet.alphanumerics.contains($0)
    }))
  }

  /// Probation and fixed-term contracts ending, and people who start, in the next `days` days.
  static func comingUp(_ employees: [PeEmployee], today: String, days: Int = 30) -> [PeMilestone] {
    let end = PeDates.addDays(today, days)
    func within(_ date: String?) -> Bool {
      guard let date else { return false }
      return date >= today && date <= end
    }
    var list: [PeMilestone] = []
    for e in employees where e.isCurrent {
      if within(e.probationEnd), let date = e.probationEnd {
        list.append(PeMilestone(employeeId: e.id, kind: .probation, date: date))
      }
      if e.contractType == "fixed", within(e.contractEnd), let date = e.contractEnd {
        list.append(PeMilestone(employeeId: e.id, kind: .contract, date: date))
      }
      if within(e.hireDate), let date = e.hireDate, date != today {
        list.append(PeMilestone(employeeId: e.id, kind: .joined, date: date))
      }
    }
    return list.sorted { a, b in a.date != b.date ? a.date < b.date : a.kind.rawValue < b.kind.rawValue }
  }

  /// Current staff hired in the last `days` days.
  static func newJoiners(_ employees: [PeEmployee], today: String, days: Int = 30) -> [PeEmployee] {
    let since = PeDates.addDays(today, -days)
    return employees.filter { e in
      guard e.isCurrent, let hire = e.hireDate else { return false }
      return hire >= since && hire <= today
    }
  }
}

// MARK: - Papers and their expiry

/// A line of the documents register: a paper on an employee's record, or a stored one.
struct PeRegisterEntry: Identifiable {
  let key: String
  let recordId: String?
  let employeeId: String?
  let type: String
  let title: String
  let number: String
  let expiryDate: String?
  let reminderDays: [Int]
  let licenceClass: String

  var id: String { key }

  /// Its own title, or the document type's name.
  var displayTitle: String {
    let own = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return own.isEmpty ? PeCompliance.typeLabel(type) : own
  }
}

/// Valid, expiring (within the first reminder) or expired.
struct PeExpiry {
  enum Status { case valid, expiring, expired }
  let status: Status
  /// Days to the expiry, negative once expired; nil without an expiry date.
  let daysLeft: Int?
  let reminder: Int?
}

/// Why a driver needs a licence they don't have valid.
enum PeLicenceGap {
  case missing, expired, undated
}

/// The documents register's rules (`src/lib/compliance.ts`).
enum PeCompliance {
  static let defaultReminderDays = [60, 30, 7]

  /// Whole positive days, no repeats, largest first; none stay none.
  static func cleanReminderDays(_ value: JSONValue?) -> [Int] {
    guard let list = value?.array else { return [] }
    var seen = Set<Int>()
    var out: [Int] = []
    for item in list {
      let number = item.double ?? item.string.flatMap { Double($0) }
      guard let number, number.isFinite else { continue }
      let whole = Int(number.rounded(.towardZero))
      if whole > 0, seen.insert(whole).inserted { out.append(whole) }
    }
    return out.sorted(by: >)
  }

  static func normalizeReminderDays(_ value: JSONValue?) -> [Int] {
    let clean = cleanReminderDays(value)
    return clean.isEmpty ? defaultReminderDays : clean
  }

  /// A paper's own days first, then its type's, then the company's.
  static func reminderDays(_ type: String, fallback: [Int], byType: [String: [Int]], own: JSONValue? = nil) -> [Int] {
    let override = cleanReminderDays(own)
    if !override.isEmpty { return override }
    if let days = byType[type], !days.isEmpty { return days }
    return fallback
  }

  static func expiry(_ date: String?, _ reminderDays: [Int], on: String) -> PeExpiry {
    guard let date else { return PeExpiry(status: .valid, daysLeft: nil, reminder: nil) }
    let left = PeDates.daysBetween(on, date)
    if left < 0 { return PeExpiry(status: .expired, daysLeft: left, reminder: nil) }
    let days = reminderDays.isEmpty ? defaultReminderDays : reminderDays
    let reached = days.filter { left <= $0 }
    guard let reminder = reached.min() else { return PeExpiry(status: .valid, daysLeft: left, reminder: nil) }
    return PeExpiry(status: .expiring, daysLeft: left, reminder: reminder)
  }

  /// The papers on an employee's own record that have a number or an expiry date.
  static func employeeDocuments(_ e: PeEmployee, days: [Int], byType: [String: [Int]]) -> [PeRegisterEntry] {
    func entry(_ type: String, _ number: String, _ expiry: String?) -> PeRegisterEntry {
      PeRegisterEntry(
        key: "emp:\(e.id):\(type)", recordId: nil, employeeId: e.id, type: type, title: "", number: number,
        expiryDate: expiry, reminderDays: reminderDays(type, fallback: days, byType: byType), licenceClass: "")
    }
    func has(_ number: String, _ expiry: String?) -> Bool {
      !number.trimmingCharacters(in: .whitespaces).isEmpty || expiry != nil
    }
    var out: [PeRegisterEntry] = []
    if has(e.civilId, e.civilIdExpiry) { out.append(entry("civil_id", e.civilId, e.civilIdExpiry)) }
    if has(e.passportNumber, e.passportExpiry) { out.append(entry("passport", e.passportNumber, e.passportExpiry)) }
    if PePeople.needsResidency(e), has(e.residencyNumber, e.residencyExpiry) {
      out.append(entry("residency", e.residencyNumber, e.residencyExpiry))
    }
    if PePeople.needsWorkPermit(e), has(e.workPermitNumber, e.workPermitExpiry) {
      out.append(entry("work_permit", e.workPermitNumber, e.workPermitExpiry))
    }
    if PePeople.isStateless(e), has(e.centralCardNumber, e.centralCardExpiry) {
      out.append(entry("central_agency_card", e.centralCardNumber, e.centralCardExpiry))
    }
    if e.contractType == "fixed", let end = e.contractEnd { out.append(entry("employment_contract", "", end)) }
    return out
  }

  /// A stored register record as an entry.
  static func recordEntry(_ doc: JSONValue, days: [Int], byType: [String: [Int]]) -> PeRegisterEntry {
    let type = doc.str("type")
    return PeRegisterEntry(
      key: "doc:\(doc.rid)", recordId: doc.rid,
      employeeId: doc.str("ownerType") == "employee" ? doc.text("employeeId") : nil, type: type,
      title: doc.str("title"), number: doc.str("number"), expiryDate: doc.text("expiryDate"),
      reminderDays: reminderDays(type, fallback: days, byType: byType, own: doc["reminderDays"]),
      licenceClass: doc.str("licenceClass"))
  }

  /// What the register tracks: stored records not archived, and the papers of current employees.
  static func registerEntries(
    employees: [PeEmployee], documents: [JSONValue], days: [Int], byType: [String: [Int]]
  ) -> [PeRegisterEntry] {
    let current = Set(employees.filter(\.isCurrent).map(\.id))
    var out: [PeRegisterEntry] = []
    for doc in documents where !doc.flag("archived") {
      if doc.str("ownerType") == "employee", !current.contains(doc.str("employeeId")) { continue }
      out.append(recordEntry(doc, days: days, byType: byType))
    }
    for e in employees where e.isCurrent {
      out.append(contentsOf: employeeDocuments(e, days: days, byType: byType))
    }
    return out
  }

  /// The most urgent paper of each employee: expired first, then the soonest to expire.
  static func worstDocuments(_ entries: [PeRegisterEntry], on: String) -> [String: (PeRegisterEntry, PeExpiry)] {
    var worst: [String: (PeRegisterEntry, PeExpiry)] = [:]
    for entry in entries {
      guard let employeeId = entry.employeeId else { continue }
      let info = expiry(entry.expiryDate, entry.reminderDays, on: on)
      if info.status == .valid { continue }
      if let before = worst[employeeId], (info.daysLeft ?? 0) >= (before.1.daysLeft ?? 0) { continue }
      worst[employeeId] = (entry, info)
    }
    return worst
  }

  /// A kind of document, in words.
  static func typeLabel(_ type: String) -> String {
    switch type {
    case "commercial_licence": t("Commercial licence")
    case "commercial_registration": t("Commercial registration (CR)")
    case "pam_company_file": t("PAM company file")
    case "authorised_signatories": t("Authorised signatories")
    case "pam_salary_certificate": t("PAM salary certificate")
    case "mof_tax_card": t("MOF tax card")
    case "tax_clearance": t("Tax clearance certificate")
    case "kcci_membership": t("KCCI membership")
    case "municipality_licence": t("Municipality licence")
    case "fire_licence": t("Fire department licence")
    case "lease_contract": t("Lease contract")
    case "civil_id": t("Civil ID")
    case "passport": t("Passport")
    case "residency": t("Residency")
    case "work_permit": t("Work permit")
    case "employment_contract": t("Employment contract")
    case "central_agency_card": t("Central Agency review card")
    case "health_insurance": t("Health insurance")
    case "driving_licence": t("Driving licence")
    case "vehicle_registration": t("Vehicle registration")
    case "vehicle_insurance": t("Vehicle insurance")
    case "company_contract": t("Company contract")
    case "client_contract": t("Customer contract")
    case "customer_cost": t("Customer cost sheet")
    default: t("Other document")
    }
  }

  // MARK: Drivers' licences

  /// A job title compared without case, Arabic letter forms, diacritics or punctuation.
  static func titleKey(_ text: String) -> String {
    var out = String.UnicodeScalarView()
    var gap = false
    for scalar in Money.normalizeDigits(text).lowercased().unicodeScalars {
      let value = scalar.value
      if (0x064B...0x0652).contains(value) || value == 0x0670 || value == 0x0640 { continue }
      var folded = scalar
      switch value {
      case 0x0623, 0x0625, 0x0622: folded = "\u{0627}"
      case 0x0649: folded = "\u{064A}"
      case 0x0629: folded = "\u{0647}"
      default: break
      }
      if isLetterOrNumber(folded) {
        if gap && !out.isEmpty { out.append(" ") }
        gap = false
        out.append(folded)
      } else {
        gap = true
      }
    }
    return String(out)
  }

  private static func isLetterOrNumber(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber,
      .letterNumber, .otherNumber:
      true
    default:
      false
    }
  }

  /// A driver's job title, in English, Arabic or on the work permit.
  static func isDriverTitle(_ e: PeEmployee) -> Bool {
    [e.jobTitle, e.jobTitleAr ?? "", e.pamJobTitle].contains { title in
      let key = titleKey(title)
      if key.isEmpty { return false }
      if key.contains("سائق") || key.contains("سايق") { return true }
      return key.split(separator: " ").contains { $0 == "driver" || $0 == "drivers" }
    }
  }

  /// Drives for work: as set on their page, then a vehicle they drive, then their job title.
  static func requiresDrivingLicence(_ e: PeEmployee, vehicles: [JSONValue]) -> Bool {
    if let set = e.drivingLicenceRequired { return set }
    if vehicles.contains(where: { !$0.flag("archived") && $0.str("driverEmployeeId") == e.id }) { return true }
    return isDriverTitle(e)
  }

  /// Current drivers without a valid licence, by employee, with the licence to complete (if any).
  static func missingLicences(
    employees: [PeEmployee], documents: [JSONValue], vehicles: [JSONValue], on: String
  ) -> [String: (gap: PeLicenceGap, documentId: String?)] {
    var byEmployee: [String: [JSONValue]] = [:]
    for doc in documents
    where doc.str("type") == "driving_licence" && doc.str("ownerType") == "employee" && !doc.flag("archived") {
      if let id = doc.text("employeeId") { byEmployee[id, default: []].append(doc) }
    }
    var out: [String: (gap: PeLicenceGap, documentId: String?)] = [:]
    for e in employees where e.isCurrent && requiresDrivingLicence(e, vehicles: vehicles) {
      // The one that expires last; one without an expiry date comes after every dated one.
      let licence = (byEmployee[e.id] ?? []).sorted { a, b in
        let (ea, eb) = (a.text("expiryDate"), b.text("expiryDate"))
        if (ea == nil) != (eb == nil) { return ea != nil }
        return (ea ?? "") > (eb ?? "")
      }.first
      if let expiry = licence?.text("expiryDate"), expiry >= on { continue }
      let gap: PeLicenceGap = licence == nil ? .missing : (licence?.text("expiryDate") != nil ? .expired : .undated)
      out[e.id] = (gap: gap, documentId: licence?.rid)
    }
    return out
  }
}

// MARK: - End of service

/// The end-of-service indemnity under Labour Law 6/2010, articles 51 and 53
/// (`src/lib/hr/eosi.ts`). An estimate, not legal advice.
enum PeEosi {
  enum Reason { case termination, resignation, dismissal }

  struct Portion {
    let years: Double
    let daysPerYear: Double?
    let monthsPerYear: Double?
    let amount: Double
  }

  struct Result {
    let years: Double
    let monthlyWage: Double
    let dailyDivisor: Double
    let dailyWage: Double
    let first: Portion
    let later: Portion
    let gross: Double
    let cap: Double
    let capApplied: Bool
    let capped: Double
    let share: (numerator: Int, denominator: Int)
    let afterShare: Double
    let pifssOffset: Double
    let payable: Double

    var fullShare: Bool { share.numerator == share.denominator }

    /// "In full", "Nothing", "Half" or "Two thirds".
    var shareText: String {
      if share.numerator == share.denominator { return t("In full") }
      if share.numerator == 0 { return t("Nothing") }
      if share.numerator * 2 == share.denominator { return t("Half") }
      return t("Two thirds")
    }
  }

  static func share(_ reason: Reason, years: Int) -> (numerator: Int, denominator: Int) {
    switch reason {
    case .termination: return (1, 1)
    case .dismissal: return (0, 1)
    case .resignation:
      if years >= 10 { return (1, 1) }
      if years >= 5 { return (2, 3) }
      if years >= 3 { return (1, 2) }
      return (0, 1)
    }
  }

  /// `calculateEosi`: each band worked out exactly from the monthly wage and rounded once.
  static func calculate(
    payBasis: String, monthlyWage: Double, years rawYears: Double, reason: Reason, dailyDivisor: Double,
    pifssOffset: Double = 0, precision: Int
  ) -> Result {
    let p = precision
    let divisor = dailyDivisor > 0 ? dailyDivisor : 26
    let wage = PeMoney.dec(max(0, monthlyWage))
    let years = max(0, rawYears)
    let monthly = payBasis == "monthly"
    let firstDays: Double = monthly ? 15 : 10
    let capMonths: Double = monthly ? 18 : 12
    let firstYears = min(years, 5)
    let laterYears = max(0, years - 5)
    let divisorDec = PeMoney.dec(divisor)
    let firstAmount = PeMoney.round(wage * (PeMoney.dec(firstYears) * PeMoney.dec(firstDays)) / divisorDec, p)
    let laterAmount =
      monthly
      ? PeMoney.round(wage * PeMoney.dec(laterYears), p)
      : PeMoney.round(wage * (PeMoney.dec(laterYears) * Decimal(15)) / divisorDec, p)
    let gross = PeMoney.round(PeMoney.dec(firstAmount) + PeMoney.dec(laterAmount), p)
    let cap = PeMoney.round(wage * PeMoney.dec(capMonths), p)
    let capApplied = gross > cap
    let capped = capApplied ? cap : gross
    let parts = share(reason, years: Int((years + 1e-9).rounded(.down)))
    let afterShare = PeMoney.round(
      PeMoney.dec(capped) * Decimal(parts.numerator) / Decimal(parts.denominator), p)
    let offset = PeMoney.round(max(0, pifssOffset), p)
    let payable = max(0, PeMoney.round(PeMoney.dec(afterShare) - PeMoney.dec(offset), p))
    return Result(
      years: years, monthlyWage: Money.toNumber(wage), dailyDivisor: divisor,
      dailyWage: PeMoney.round(wage / divisorDec, p),
      first: Portion(years: firstYears, daysPerYear: firstDays, monthsPerYear: nil, amount: firstAmount),
      later: monthly
        ? Portion(years: laterYears, daysPerYear: nil, monthsPerYear: 1, amount: laterAmount)
        : Portion(years: laterYears, daysPerYear: 15, monthsPerYear: nil, amount: laterAmount),
      gross: gross, cap: cap, capApplied: capApplied, capped: capped, share: parts, afterShare: afterShare,
      pifssOffset: offset, payable: payable)
  }

  /// Years of service from the hire date through `until`, both days counted;
  /// part years pro rata, to 4 decimals (`serviceYears`).
  static func serviceYears(_ hireDate: String, _ until: String) -> Double {
    guard let start = PeDates.number(hireDate), let last = PeDates.number(until) else { return 0 }
    let end = last + 1
    if end <= start { return 0 }
    let startText = PeDates.text(start)
    var whole = PeDates.civil(end).year - PeDates.civil(start).year
    if (PeDates.number(PeDates.addMonths(startText, 12 * whole)) ?? 0) > end { whole -= 1 }
    let anniversary = PeDates.number(PeDates.addMonths(startText, 12 * whole)) ?? start
    let next = PeDates.number(PeDates.addMonths(startText, 12 * (whole + 1))) ?? (anniversary + 365)
    let part = Double(end - anniversary) / Double(max(1, next - anniversary))
    return PeMoney.jsRound((Double(whole) + part) * 10_000) / 10_000
  }

  /// Basic salary and the allowances that count for the indemnity.
  static func wage(_ basic: Double, _ allowances: [PeAllowance], _ precision: Int) -> Double {
    PeMoney.round(
      PeMoney.sum(allowances.filter(\.countsForEos).map(\.amount)) + PeMoney.dec(basic), precision)
  }
}
