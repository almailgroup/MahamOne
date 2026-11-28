import Foundation

// The port of the web's src/lib/hr/leave.ts: leave types and the company's
// reasons, counting leave days around weekends and holidays, what leave in a
// month does to pay, and annual leave balances (accrual, openings, the
// carry-forward cap and the pause for long unpaid leave).

/// Whether a day is a day off: the Kuwaiti weekend or a public holiday of the company (`DayOff`).
final class PwDayOff {
  private let own: [String]
  private var cache: [Int: Set<String>] = [:]

  /// `companyDayOff(company)`: its own list for a year it changed, else the official estimates.
  init(company: JSONValue?) {
    own = (company?.pwList("holidays") ?? []).compactMap { $0.pwText("date") }
  }

  func callAsFunction(_ date: String) -> Bool {
    let weekday = PwDates.weekday(date)
    if Kuwait.weekend.contains(weekday) { return true }
    let year = Int(WebJS.prefix(date, 4)) ?? 0
    if let days = cache[year] { return days.contains(date) }
    let prefix = String(year) + "-"
    let mine = own.filter { $0.hasPrefix(prefix) }
    let days = Set(mine.isEmpty ? Kuwait.kuwaitHolidays(year).map(\.date) : mine)
    cache[year] = days
    return days.contains(date)
  }
}

enum PwLeave {
  static let annualDays = 30.0
  static let firstYearMonths = 9.0
  static let maxSpan = 366
  static let pauseDays = 15
  static let addedAtHireDays = 31

  // MARK: Types and reasons

  struct TypeInfo {
    let label: String
    let days: Double?
    let counting: String
  }

  static let types: [String: TypeInfo] = [
    "annual": TypeInfo(label: "Annual leave", days: 30, counting: "working"),
    "sick": TypeInfo(label: "Sick leave", days: 75, counting: "working"),
    "maternity": TypeInfo(label: "Maternity leave", days: 70, counting: "calendar"),
    "hajj": TypeInfo(label: "Hajj leave", days: 21, counting: "calendar"),
    "bereavement": TypeInfo(label: "Bereavement leave", days: 3, counting: "working"),
    "unpaid": TypeInfo(label: "Unpaid leave", days: nil, counting: "calendar"),
  ]

  static let typeOrder = ["annual", "sick", "maternity", "hajj", "bereavement", "unpaid"]

  /// `leaveTypeInfo`: also for a type a newer version saved.
  static func typeInfo(_ type: String) -> TypeInfo {
    types[type] ?? TypeInfo(label: "Other leave", days: nil, counting: "working")
  }

  struct PayInfo {
    let label: String
    let base: String
    let percent: Double
  }

  /// `LEAVE_REASON_PAY`.
  static let reasonPay: [String: PayInfo] = [
    "full": PayInfo(label: "Full pay", base: "bereavement", percent: 100),
    "half": PayInfo(label: "Half pay", base: "unpaid", percent: 50),
    "unpaid": PayInfo(label: "Without pay", base: "unpaid", percent: 0),
    "annual": PayInfo(label: "Taken from annual leave", base: "annual", percent: 100),
    "balance": PayInfo(label: "Full pay, from days added by hand", base: "bereavement", percent: 100),
  ]

  static let reasonPayOrder = ["full", "half", "unpaid", "annual", "balance"]

  /// `leaveReasonBase(pay)`.
  static func reasonBase(_ pay: String) -> String { reasonPay[pay]?.base ?? "bereavement" }

  /// `reasonOf(record, reasons)`.
  static func reasonOf(_ reasonId: String?, _ reasons: [JSONValue]) -> JSONValue? {
    guard let reasonId, !reasonId.isEmpty else { return nil }
    return reasons.first { $0.pwStr("id") == reasonId }
  }

  /// `reasonsFor(reasons, employee)`: not archived, and for their category.
  static func reasonsFor(_ reasons: [JSONValue], category: String?) -> [JSONValue] {
    reasons.filter { r in
      guard !r.pwTruthy("archived") else { return false }
      let categories = r.pwList("categories").compactMap(\.string)
      if categories.isEmpty || r["categories"]?.array == nil { return true }
      guard let category else { return true }
      return categories.contains(category)
    }
  }

  /// `unpaidShare(record)`.
  static func unpaidShare(_ record: JSONValue) -> Double {
    guard let percent = record.pwNumber("payPercent"), percent.isFinite else { return 0 }
    return min(100, max(0, PwM.jsRound(percent)))
  }

  /// `leaveCounting(type, policy)`.
  static func counting(_ type: String, _ policy: JSONValue?) -> String {
    if type == "annual", let policy = WebJS.present(policy) {
      return policy.pwStr("counting") == "calendar" ? "calendar" : "working"
    }
    return typeInfo(type).counting
  }

  /// `leavePolicyStart(policy)`.
  static func policyStart(_ policy: JSONValue?) -> String? {
    let dates = (policy?.pwList("annualDays") ?? []).map { $0.pwStr("from") }.sorted(by: WebJS.less)
    return dates.first
  }

  /// `annualLeaveRecorded(records)`.
  static func annualLeaveRecorded(_ records: [JSONValue]) -> Bool {
    records.contains {
      $0.pwStr("type") == "annual" && $0.pwStr("kind") == "leave" && $0.pwStr("status") != "cancelled"
    }
  }

  static func isTaken(_ r: JSONValue) -> Bool { r.pwStr("kind") == "leave" && r.pwStr("status") == "approved" }

  /// `isOpeningRecord`.
  static func isOpening(_ r: JSONValue) -> Bool {
    r.pwStr("kind") == "opening" && r.pwStr("type") == "annual" && r.pwStr("status") == "approved"
  }

  // MARK: Counting days

  /// `countedDates`: working days, or every day for calendar-day leave.
  static func countedDates(
    _ type: String, _ start: String, _ end: String, _ isDayOff: PwDayOff, _ policy: JSONValue? = nil
  ) -> [String] {
    if start.isEmpty || end.isEmpty || WebJS.less(end, start) { return [] }
    let calendar = counting(type, policy) == "calendar"
    var out: [String] = []
    var date = start
    var i = 0
    while i < maxSpan && !WebJS.less(end, date) {
      if calendar || !isDayOff(date) { out.append(date) }
      date = PwDates.addDays(date, 1)
      i += 1
    }
    return out
  }

  static func countDays(
    _ type: String, _ start: String, _ end: String, _ isDayOff: PwDayOff, _ policy: JSONValue? = nil
  ) -> Int {
    countedDates(type, start, end, isDayOff, policy).count
  }

  /// Every date from `start` to `end` (at most a year of them).
  static func calendarDates(_ start: String, _ end: String) -> [String] {
    var out: [String] = []
    var date = start
    var i = 0
    while i < maxSpan && !WebJS.less(end, date) {
      out.append(date)
      date = PwDates.addDays(date, 1)
      i += 1
    }
    return out
  }

  /// `sickPercent(daysBefore)`.
  static func sickPercent(_ daysBefore: Int) -> Double {
    let tiers: [(days: Int, percent: Double)] = [(15, 100), (10, 75), (10, 50), (10, 25), (30, 0)]
    var limit = 0
    for tier in tiers {
      limit += tier.days
      if daysBefore < limit { return tier.percent }
    }
    return 0
  }

  /// `sickDayRates`: each sick day of a year with its share of pay.
  static func sickDayRates(_ records: [JSONValue], _ year: Int, _ isDayOff: PwDayOff) -> [String: Double] {
    var days = Set<String>()
    let prefix = String(year) + "-"
    for r in records where r.pwStr("type") == "sick" && isTaken(r) {
      for d in countedDates("sick", r.pwStr("start"), r.pwStr("end"), isDayOff) where d.hasPrefix(prefix) {
        days.insert(d)
      }
    }
    var rates: [String: Double] = [:]
    for (i, d) in days.sorted(by: WebJS.less).enumerated() { rates[d] = sickPercent(i) }
    return rates
  }

  // MARK: A month's leave and pay

  struct PayDays {
    var unpaidDays: Int
    /// `{ percent, days }`, the highest share first.
    var reducedPay: [JSONValue]

    var json: JSONValue { ["unpaidDays": .number(Double(unpaidDays)), "reducedPay": .array(reducedPay)] }
  }

  struct ByReason {
    var reasonId: String
    var type: String
    var days: Int
    var percent: Double
  }

  struct PeriodLeave {
    var calendar: PayDays
    var working: PayDays
    var byReason: [ByReason]?
  }

  private static func payDays(_ shares: [Double]) -> PayDays {
    var unpaid = 0
    var reduced: [Double: Int] = [:]
    for percent in shares {
      if percent == 0 {
        unpaid += 1
      } else if percent < 100 {
        reduced[percent, default: 0] += 1
      }
    }
    let list = reduced.sorted { $0.key > $1.key }.map { entry -> JSONValue in
      ["percent": .number(entry.key), "days": .number(Double(entry.value))]
    }
    return PayDays(unpaidDays: unpaid, reducedPay: list)
  }

  /// `leaveInPeriod`: what an employee's leave in a month means for their pay.
  static func inPeriod(
    _ records: [JSONValue], _ period: String, _ isDayOff: PwDayOff, from employedFrom: String? = nil,
    to employedTo: String? = nil, policy: JSONValue? = nil
  ) -> PeriodLeave {
    let start = PwPay.periodStart(period)
    let end = PwPay.periodEnd(period)
    let inMonth = { (d: String) in !WebJS.less(d, start) && !WebJS.less(end, d) }
    let first = (employedFrom.map { !$0.isEmpty && WebJS.less(start, $0) } ?? false) ? employedFrom! : start
    let last = (employedTo.map { !$0.isEmpty && WebJS.less($0, end) } ?? false) ? employedTo! : end
    let paidDay = { (d: String) in !WebJS.less(d, first) && !WebJS.less(last, d) }
    var pay: [String: Double] = [:]
    func lower(_ d: String, _ percent: Double) { pay[d] = min(pay[d] ?? 100, percent) }
    let sick = sickDayRates(records, Int(WebJS.prefix(period, 4)) ?? 0, isDayOff)
    var reasonOrder: [String] = []
    var reasons: [String: (entry: ByReason, first: String)] = [:]
    let usePolicy = WebJS.present(policy)
    for r in records {
      let rStart = r.pwStr("start")
      let rEnd = r.pwStr("end")
      guard isTaken(r), !WebJS.less(rEnd, start), !WebJS.less(end, rStart) else { continue }
      let type = r.pwStr("type")
      let counted = countedDates(type, rStart, rEnd, isDayOff)
      let share = type == "unpaid" ? unpaidShare(r) : 100
      if let reasonId = r.pwText("reasonId"), !reasonId.isEmpty {
        let own = usePolicy != nil ? countedDates(type, rStart, rEnd, isDayOff, usePolicy) : counted
        let days = own.filter { inMonth($0) && paidDay($0) }
        let key = reasonId + ":" + type + ":" + WebJS.numberString(share)
        if let firstDay = days.first {
          if let before = reasons[key] {
            var entry = before.entry
            entry.days += days.count
            reasons[key] = (entry, WebJS.less(firstDay, before.first) ? firstDay : before.first)
          } else {
            reasonOrder.append(key)
            reasons[key] = (ByReason(reasonId: reasonId, type: type, days: days.count, percent: share), firstDay)
          }
        }
      }
      if type == "unpaid" && share < 100 {
        for d in calendarDates(rStart, rEnd) where inMonth(d) && paidDay(d) { lower(d, share) }
      }
      guard type == "sick" else { continue }
      let working = Set(counted)
      var tierDay: String? = counted.first
      for d in calendarDates(rStart, rEnd) {
        if working.contains(d) { tierDay = d }
        guard inMonth(d), paidDay(d) else { continue }
        let percent = tierDay.map { sick[$0] ?? 100 } ?? 100
        if percent < 100 { lower(d, percent) }
      }
    }
    let workingShares = pay.filter { !isDayOff($0.key) }.map { $0.value }
    var byReason: [ByReason]?
    if !reasonOrder.isEmpty {
      let entries = reasonOrder.compactMap { reasons[$0] }
      byReason = PwSort.stable(entries) { a, b in
        let order = PwSort.code(a.first, b.first)
        return order != 0 ? order : PwSort.localeCompare(a.entry.reasonId, b.entry.reasonId)
      }.map { $0.entry }
    }
    return PeriodLeave(calendar: payDays(Array(pay.values)), working: payDays(workingShares), byReason: byReason)
  }

  // MARK: Accrual

  struct Rate {
    let from: String?
    let days: Double
  }

  /// `accrualRates`.
  static func accrualRates(_ policy: JSONValue?, _ entitlement: Double?, _ entitlementFrom: String?) -> [Rate] {
    let dated = PwSort.stable(policy?.pwList("annualDays") ?? []) { PwSort.code($0.pwStr("from"), $1.pwStr("from")) }
      .map { Rate(from: $0.pwStr("from"), days: $0.pwNum("days")) }
    let company = [Rate(from: nil, days: annualDays)] + dated
    guard let entitlement, entitlement > 0 else { return company }
    guard let entitlementFrom, !entitlementFrom.isEmpty else { return [Rate(from: nil, days: entitlement)] }
    return company.filter { $0.from == nil || WebJS.less($0.from!, entitlementFrom) }
      + [Rate(from: entitlementFrom, days: entitlement)]
  }

  static func rateOn(_ rates: [Rate], _ date: String) -> Double {
    var days = rates.first?.days ?? annualDays
    for r in rates where r.from == nil || !WebJS.less(date, r.from!) { days = r.days }
    return days
  }

  /// `annualDaysOn`.
  static func annualDaysOn(_ date: String, _ policy: JSONValue?, _ entitlement: Double? = nil, _ from: String? = nil)
    -> Double
  {
    rateOn(accrualRates(WebJS.present(policy), entitlement, from), date)
  }

  /// `accrualOptions(settings)`: the date the pause applies from.
  static func pauseFrom(_ settings: JSONValue?) -> String? {
    guard let from = settings?["leaveAccrualPause"]?.pwText("from"), !from.isEmpty else { return nil }
    return from
  }

  typealias Paused = (String, String) -> Bool

  /// `pausedMonthsOf`.
  static func pausedMonths(_ records: [JSONValue], _ pauseFrom: String?) -> Paused? {
    guard let from = pauseFrom else { return nil }
    var unpaid = Set<String>()
    for r in records where r.pwStr("type") == "unpaid" && isTaken(r) && unpaidShare(r) <= 0 {
      for d in calendarDates(r.pwStr("start"), r.pwStr("end")) { unpaid.insert(d) }
    }
    if unpaid.count <= pauseDays { return nil }
    let days = Array(unpaid)
    return { first, next in
      !WebJS.less(first, from)
        && days.filter { !WebJS.less($0, first) && WebJS.less($0, next) }.count > pauseDays
    }
  }

  private static func monthEarned(_ first: String, _ next: String, _ rates: [Rate]) -> Double {
    let length = Double(PwDates.daysBetween(first, next))
    var earned = 0.0
    var start = first
    for change in rates {
      guard let from = change.from, WebJS.less(first, from), WebJS.less(from, next) else { continue }
      earned += (rateOn(rates, start) * Double(PwDates.daysBetween(start, from))) / length / 12
      start = from
    }
    return earned + (rateOn(rates, start) * Double(PwDates.daysBetween(start, next))) / length / 12
  }

  private static func pausedBetween(_ from: String, _ on: String, _ paused: Paused?) -> [String] {
    guard let paused else { return [] }
    var out: [String] = []
    let months = PwDates.completedMonths(from, on)
    for i in 0..<max(0, months) {
      let first = PwDates.addMonths(from, i)
      if paused(first, PwDates.addMonths(from, i + 1)) { out.append(first) }
    }
    return out
  }

  /// `earnedDays`.
  private static func earnedDays(_ from: String, _ on: String, _ rates: [Rate], _ paused: Paused?) -> Double {
    let lost = pausedBetween(from, on, paused).reduce(0.0) { total, first in
      total + monthEarned(first, PwDates.addMonths(first, 1), rates)
    }
    let months = PwDates.completedMonths(from, on)
    let last = PwDates.addDays(PwDates.addMonths(from, months), -1)
    let changes = rates.compactMap(\.from)
    if !changes.contains(where: { WebJS.less(from, $0) && !WebJS.less(last, $0) }) {
      return (Double(months) * rateOn(rates, from)) / 12 - lost
    }
    var earned = 0.0
    for i in 0..<max(0, months) {
      let first = PwDates.addMonths(from, i)
      let next = PwDates.addMonths(from, i + 1)
      let length = Double(PwDates.daysBetween(first, next))
      var start = first
      for change in changes where WebJS.less(first, change) && WebJS.less(change, next) {
        earned += (rateOn(rates, start) * Double(PwDates.daysBetween(start, change))) / length / 12
        start = change
      }
      earned += (rateOn(rates, start) * Double(PwDates.daysBetween(start, next))) / length / 12
    }
    return earned - lost
  }

  // MARK: Balances

  struct Opening {
    let date: String
    let days: Double
    let record: JSONValue?
  }

  private static func openings(_ annual: [JSONValue], _ brought: JSONValue?) -> [Opening] {
    let records = annual.filter { $0.pwStr("kind") == "opening" }
    var out = records.map { Opening(date: $0.pwStr("start"), days: $0.pwNum("days"), record: $0) }
    if let brought = WebJS.present(brought), brought.pwTruthy("confirmed") || records.isEmpty {
      out.append(Opening(date: brought.pwStr("date"), days: brought.pwNum("days"), record: nil))
    }
    return out
  }

  private static func sameDay(_ a: Opening, _ b: Opening) -> Int {
    let order = (b.record != nil ? 1 : 0) - (a.record != nil ? 1 : 0)
    if order != 0 { return order }
    return PwSort.code(b.record?.pwStr("createdAt") ?? "", a.record?.pwStr("createdAt") ?? "")
  }

  private static func latestFirst(_ a: Opening, _ b: Opening) -> Int {
    let order = PwSort.code(b.date, a.date)
    return order != 0 ? order : sameDay(a, b)
  }

  private static func earliestFirst(_ a: Opening, _ b: Opening) -> Int {
    let order = PwSort.code(a.date, b.date)
    return order != 0 ? order : sameDay(a, b)
  }

  private static func forfeited(
    _ from: String, _ on: String, _ opening: Double, _ records: [JSONValue], _ rates: [Rate], _ policy: JSONValue?,
    _ paused: Paused?
  ) -> Double {
    guard let policy = WebJS.present(policy), let cap = policy.pwNumber("carryForwardMax"),
      let start = policyStart(policy)
    else { return 0 }
    func sum(_ kind: String, _ until: String) -> Double {
      records.filter { $0.pwStr("kind") == kind && !WebJS.less(until, $0.pwStr("start")) }
        .reduce(0.0) { $0 + $1.pwNum("days") }
    }
    func heldOn(_ date: String, _ lostBefore: Double) -> Double {
      PwM.two(
        opening + earnedDays(from, date, rates, paused) + sum("adjustment", date) - sum("leave", date) - lostBefore)
    }
    let dayBefore = PwDates.addDays(start, -1)
    let lawDays = WebJS.less(from, start) ? max(0, heldOn(dayBefore, 0)) : 0
    var lost = 0.0
    var year = Int(WebJS.prefix(from, 4)) ?? 0
    while WebJS.less(String(year) + "-12-31", on) {
      let yearEnd = String(year) + "-12-31"
      if WebJS.less(String(year + 1) + "-01-01", start) {
        year += 1
        continue
      }
      let held = heldOn(yearEnd, lost)
      let kept = max(0, lawDays - (sum("leave", yearEnd) - sum("leave", dayBefore)))
      if held - kept > cap { lost += held - kept - cap }
      year += 1
    }
    return PwM.two(lost)
  }

  struct Balance {
    var from: String?
    var opening: Double = 0
    var accrued: Double = 0
    var adjusted: Double = 0
    var taken: Double = 0
    var forfeited: Double?
    var pausedMonths: Int?
    var balance: Double = 0
    var eligibleFrom: String?
  }

  /// `annualLeaveBalance`.
  static func annualBalance(
    _ records: [JSONValue], hireDate: String?, on: String, brought: JSONValue?, policy: JSONValue?,
    entitlement: Double?, entitlementFrom: String?, pauseFrom: String?
  ) -> Balance {
    let policy = WebJS.present(policy)
    let rates = accrualRates(policy, entitlement, entitlementFrom)
    let paused = pausedMonths(records, pauseFrom)
    let annual = records.filter { $0.pwStr("type") == "annual" && $0.pwStr("status") == "approved" }
    let firstMonths = Int(policy?.pwNumber("firstYearMonths") ?? firstYearMonths)
    let hire = (hireDate ?? "").isEmpty ? nil : hireDate
    let eligibleFrom = hire.map { h in PwDates.day(h).map { $0.adding(months: firstMonths).text } ?? ISODates.invalid }
    let all = openings(annual, brought)
    let opening = PwSort.stable(all.filter { !WebJS.less(on, $0.date) }, by: latestFirst).first
    if opening == nil {
      if let hire, WebJS.less(on, hire) { return Balance(from: hire, eligibleFrom: eligibleFrom) }
      if let next = PwSort.stable(all.filter { WebJS.less(on, $0.date) }, by: earliestFirst).first {
        let earned = earnedDays(PwDates.addDays(on, 1), PwDates.addDays(next.date, -1), rates, paused)
        let between = annual.filter {
          WebJS.less(on, $0.pwStr("start")) && WebJS.less($0.pwStr("start"), next.date) && $0.pwStr("kind") != "opening"
        }
        func sum(_ kind: String) -> Double {
          between.filter { $0.pwStr("kind") == kind }.reduce(0.0) { $0 + $1.pwNum("days") }
        }
        let balance = PwM.two(max(0, next.days - earned + sum("leave") - sum("adjustment")))
        return Balance(
          from: next.date, opening: next.days, accrued: PwM.two(balance - next.days), adjusted: 0, taken: 0,
          balance: balance, eligibleFrom: eligibleFrom)
      }
    }
    let start: String?
    if let opening {
      if opening.record == nil, let hire, WebJS.less(opening.date, hire) {
        start = hire
      } else {
        start = opening.date
      }
    } else {
      start = hire
    }
    guard let from = start, !WebJS.less(on, from) else { return Balance(from: start, eligibleFrom: eligibleFrom) }
    let after = annual.filter {
      !WebJS.less($0.pwStr("start"), from) && !WebJS.less(on, $0.pwStr("start")) && $0.pwStr("kind") != "opening"
    }
    let accrued = PwM.two(earnedDays(from, on, rates, paused))
    let pausedCount = pausedBetween(from, on, paused).count
    let adjusted = PwM.two(after.filter { $0.pwStr("kind") == "adjustment" }.reduce(0.0) { $0 + $1.pwNum("days") })
    let taken = PwM.two(after.filter { $0.pwStr("kind") == "leave" }.reduce(0.0) { $0 + $1.pwNum("days") })
    let openingDays = opening?.days ?? 0
    let lost = forfeited(from, on, openingDays, after, rates, policy, paused)
    return Balance(
      from: from, opening: openingDays, accrued: accrued, adjusted: adjusted, taken: taken,
      forfeited: lost > 0 ? lost : nil, pausedMonths: pausedCount > 0 ? pausedCount : nil,
      balance: PwM.two(openingDays + accrued + adjusted - taken - lost), eligibleFrom: eligibleFrom)
  }

  /// `employeeLeaveBalance`.
  static func employeeBalance(
    _ employee: JSONValue, _ records: [JSONValue], on: String, policy: JSONValue?, pauseFrom: String?
  ) -> Balance {
    annualBalance(
      records.filter { $0.pwStr("employeeId") == employee.pwId }, hireDate: employee.pwText("hireDate"), on: on,
      brought: employee["leaveOpening"], policy: policy, entitlement: employee.pwNumber("annualLeaveDays"),
      entitlementFrom: employee.pwText("annualLeaveDaysFrom"), pauseFrom: pauseFrom)
  }

  /// `employeesNeedingLeaveOpening`.
  static func needingOpening(_ employees: [JSONValue], _ records: [JSONValue]) -> [JSONValue] {
    var byEmployee: [String: [JSONValue]] = [:]
    for r in records where isOpening(r) { byEmployee[r.pwStr("employeeId"), default: []].append(r) }
    return employees.filter { e in
      if e.pwStr("status") == "left" { return false }
      let list = openings(byEmployee[e.pwId] ?? [], e["leaveOpening"])
      if list.contains(where: { $0.record != nil }) { return false }
      if !list.isEmpty { return !(e["leaveOpening"]?.pwTruthy("confirmed") ?? false) }
      let added = e.pwText("createdAt").map { WebJS.prefix($0, 10) } ?? ""
      let hire = e.pwStr("hireDate")
      if hire.isEmpty || added.isEmpty { return true }
      return WebJS.less(hire, PwDates.addDays(added, -addedAtHireDays))
    }
  }
}
