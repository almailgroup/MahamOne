import Foundation
import MahamKit

// Leave under Labour Law 6/2010, as the web works it out (src/lib/hr/leave.ts):
// annual leave earned for each month of service (art. 70) and carried
// forward (art. 73), sick leave in tiers (art. 69), the company's leave
// policy and its own leave reasons. Read only: balances are worked out from
// the leave records, never written.

/// A leave record (`LeaveRecord`): leave taken, an opening balance or a balance change.
struct PeLeaveRecord: Identifiable {
  let raw: JSONValue

  init(_ raw: JSONValue) { self.raw = raw }

  var id: String { raw.rid }
  var employeeId: String { raw.str("employeeId") }
  var type: String { raw.str("type") }
  var kind: String { raw.str("kind") }
  var start: String { raw.str("start") }
  var end: String { raw.str("end") }
  var days: Double { raw.num("days") }
  var status: String { raw.str("status") }
  var notes: String { raw.str("notes") }
  var reasonId: String? { raw.text("reasonId") }
  var payPercent: Double? { raw.number("payPercent") }
  var createdAt: String { raw.str("createdAt") }

  /// Leave taken and not cancelled.
  var isTaken: Bool { kind == "leave" && status == "approved" }
}

/// Fridays, Saturdays and the company's public holidays (its own list for a
/// year it changed, else the official estimates), as `companyDayOff`.
@MainActor
final class PeDayOff {
  private let own: [String]
  private var cache: [Int: Set<String>] = [:]

  init(company: JSONValue?) {
    own = (company?.list("holidays") ?? []).compactMap { $0.text("date") }
  }

  func isOff(_ date: String) -> Bool {
    let weekday = PeDates.weekday(date)
    if weekday == 5 || weekday == 6 { return true }
    guard let year = Int(date.prefix(4)) else { return false }
    if let days = cache[year] { return days.contains(date) }
    let prefix = String(year) + "-"
    let mine = own.filter { $0.hasPrefix(prefix) }
    let days = Set(mine.isEmpty ? PeHolidays.official(year) : mine)
    cache[year] = days
    return days.contains(date)
  }
}

/// Kuwait's official holidays of a year, worked out once.
@MainActor
enum PeHolidays {
  private static var years: [Int: [String]] = [:]

  static func official(_ year: Int) -> [String] {
    if let found = years[year] { return found }
    let dates = Kuwait.kuwaitHolidays(year).map(\.date)
    years[year] = dates
    return dates
  }
}

/// An employee's annual leave balance on a day (`LeaveBalance`).
struct PeLeaveBalance {
  var from: String?
  var opening: Double = 0
  var accrued: Double = 0
  var adjusted: Double = 0
  var taken: Double = 0
  var forfeited: Double = 0
  var pausedMonths = 0
  var balance: Double = 0
  var eligibleFrom: String?
}

@MainActor
enum PeLeave {
  // MARK: Types and reasons

  static func typeLabel(_ type: String) -> String {
    switch type {
    case "annual": t("Annual leave")
    case "sick": t("Sick leave")
    case "maternity": t("Maternity leave")
    case "hajj": t("Hajj leave")
    case "bereavement": t("Bereavement leave")
    case "unpaid": t("Unpaid leave")
    default: t("Other leave")
    }
  }

  /// Maternity, Hajj and unpaid leave run in calendar days; the rest in working days.
  static func typeCounting(_ type: String) -> String {
    ["maternity", "hajj", "unpaid"].contains(type) ? "calendar" : "working"
  }

  /// Annual leave is counted as the company's policy says; other leave by its type.
  static func counting(_ type: String, policy: PeLeavePolicy?) -> String {
    if type == "annual", let policy { return policy.counting == "calendar" ? "calendar" : "working" }
    return typeCounting(type)
  }

  /// How a reason's leave is paid, in words.
  static func reasonPayLabel(_ reason: PeLeaveReason) -> String {
    switch reason.pay {
    case "full": t("Full pay")
    case "half": t("Half pay")
    case "unpaid": t("Without pay")
    case "annual": t("Taken from annual leave")
    case "balance": t("Full pay, from days added by hand")
    default: t("Other leave")
    }
  }

  /// What older versions make of a reason's leave.
  static func reasonOlderText(_ reason: PeLeaveReason) -> String? {
    switch reason.pay {
    case "full", "balance": return t("Older versions show it as bereavement leave, paid in full.")
    case "half": return t("Older versions show it as unpaid leave and pay nothing for it.")
    case "unpaid": return t("Older versions show it as unpaid leave.")
    case "annual": return t("Older versions show it as annual leave.")
    default: return nil
    }
  }

  static func reasonOf(_ record: PeLeaveRecord, _ reasons: [PeLeaveReason]) -> PeLeaveReason? {
    guard let id = record.reasonId else { return nil }
    return reasons.first { $0.id == id }
  }

  /// Reasons offered for an employee's new leave: not archived, and for their category.
  static func reasonsFor(_ reasons: [PeLeaveReason], category: String) -> [PeLeaveReason] {
    reasons.filter { !$0.archived && ($0.categories.isEmpty || $0.categories.contains(category)) }
  }

  /// A record's leave in words: its reason's name, or its type's.
  static func label(_ record: PeLeaveRecord, _ reasons: [PeLeaveReason]) -> String {
    if let reason = reasonOf(record, reasons) { return reason.displayName }
    return typeLabel(record.type)
  }

  /// Share of pay of a day of unpaid leave: what a reason paid in part fixed, otherwise nothing.
  static func unpaidShare(_ record: PeLeaveRecord) -> Double {
    guard let percent = record.payPercent, percent.isFinite else { return 0 }
    return min(100, max(0, PeMoney.jsRound(percent)))
  }

  // MARK: Counting days

  /// The days a leave counts: working days, or every day for calendar-day leave.
  static func countedDates(
    _ type: String, _ start: String, _ end: String, _ dayOff: PeDayOff, policy: PeLeavePolicy? = nil
  ) -> [String] {
    guard !start.isEmpty, !end.isEmpty, end >= start else { return [] }
    let calendar = counting(type, policy: policy) == "calendar"
    var out: [String] = []
    var date = start
    var index = 0
    while index < 366 && date <= end {
      if calendar || !dayOff.isOff(date) { out.append(date) }
      date = PeDates.addDays(date, 1)
      index += 1
    }
    return out
  }

  /// Every day from `start` to `end`.
  static func calendarDates(_ start: String, _ end: String) -> [String] {
    var out: [String] = []
    guard !start.isEmpty, !end.isEmpty else { return out }
    var date = start
    var index = 0
    while index < 366 && date <= end {
      out.append(date)
      date = PeDates.addDays(date, 1)
      index += 1
    }
    return out
  }

  /// A leave's days in a calendar year; one crossing 31 December is split by its dates when `dayOff` is given.
  static func daysInYear(
    _ record: PeLeaveRecord, year: Int, dayOff: PeDayOff? = nil, policy: PeLeavePolicy? = nil
  ) -> Double {
    let prefix = String(year) + "-"
    let startsIn = record.start.hasPrefix(prefix)
    let end = record.end.isEmpty ? record.start : record.end
    if startsIn && end.hasPrefix(prefix) { return record.days }
    guard let dayOff else { return startsIn ? record.days : 0 }
    let dates = countedDates(record.type, record.start, end, dayOff, policy: policy)
    return Double(dates.filter { $0.hasPrefix(prefix) }.count)
  }

  /// Days of a reason's leave in a calendar year.
  static func reasonDaysInYear(
    _ records: [PeLeaveRecord], reasonId: String, year: Int, dayOff: PeDayOff? = nil, policy: PeLeavePolicy? = nil
  ) -> Double {
    var total = 0.0
    for r in records where r.reasonId == reasonId && r.isTaken {
      total += daysInYear(r, year: year, dayOff: dayOff, policy: policy)
    }
    return PeMoney.twoPlaces(total)
  }

  /// A reason's own balance on a day: the days added less the leave taken with it.
  static func reasonBalance(_ records: [PeLeaveRecord], reasonId: String, on: String) -> (
    added: Double, taken: Double, balance: Double
  ) {
    var added = 0.0
    var taken = 0.0
    for r in records where r.reasonId == reasonId && r.status == "approved" && r.start <= on {
      if r.kind == "adjustment" { added += r.days }
      if r.kind == "leave" { taken += r.days }
    }
    let a = PeMoney.twoPlaces(added)
    let b = PeMoney.twoPlaces(taken)
    return (a, b, PeMoney.twoPlaces(a - b))
  }

  // MARK: Sick leave

  /// Sick leave in a calendar year: days at each share of pay, in order (art. 69).
  static let sickTiers: [(days: Int, percent: Double)] = [(15, 100), (10, 75), (10, 50), (10, 25), (30, 0)]

  static func sickPercent(_ daysBefore: Int) -> Double {
    var limit = 0
    for tier in sickTiers {
      limit += tier.days
      if daysBefore < limit { return tier.percent }
    }
    return 0
  }

  static func sickDayRates(_ records: [PeLeaveRecord], year: Int, dayOff: PeDayOff) -> [String: Double] {
    var days = Set<String>()
    let prefix = String(year) + "-"
    for r in records where r.type == "sick" && r.isTaken {
      for d in countedDates("sick", r.start, r.end, dayOff) where d.hasPrefix(prefix) { days.insert(d) }
    }
    var rates: [String: Double] = [:]
    for (index, day) in days.sorted().enumerated() { rates[day] = sickPercent(index) }
    return rates
  }

  /// Sick days taken in a year at each share of pay, in the tiers' order.
  static func sickDaysByTier(_ records: [PeLeaveRecord], year: Int, dayOff: PeDayOff) -> [(percent: Double, days: Int)]
  {
    var counts: [Double: Int] = [:]
    for percent in sickDayRates(records, year: year, dayOff: dayOff).values { counts[percent, default: 0] += 1 }
    return sickTiers.map { (percent: $0.percent, days: counts[$0.percent] ?? 0) }
  }

  // MARK: Annual leave

  private struct Rate {
    let from: String?
    let days: Double
  }

  private static func accrualRates(_ policy: PeLeavePolicy, _ entitlement: Double?, _ entitlementFrom: String?)
    -> [Rate]
  {
    let dated = policy.annualDays.sorted { $0.from < $1.from }.map { Rate(from: $0.from, days: $0.days) }
    let company = [Rate(from: nil, days: 30)] + dated
    guard let entitlement, entitlement > 0 else { return company }
    guard let entitlementFrom else { return [Rate(from: nil, days: entitlement)] }
    let before = company.filter { rate in
      guard let from = rate.from else { return true }
      return from < entitlementFrom
    }
    return before + [Rate(from: entitlementFrom, days: entitlement)]
  }

  private static func rateOn(_ rates: [Rate], _ date: String) -> Double {
    var days = rates.first?.days ?? 30
    for rate in rates {
      if let from = rate.from {
        if from <= date { days = rate.days }
      } else {
        days = rate.days
      }
    }
    return days
  }

  /// Days of annual leave a year on a day: the employee's own entitlement, or the policy's.
  static func annualDaysOn(
    _ date: String, policy: PeLeavePolicy?, entitlement: Double? = nil, entitlementFrom: String? = nil
  ) -> Double {
    rateOn(accrualRates(policy ?? .law, entitlement, entitlementFrom), date)
  }

  /// The first date of a policy: balances before it are the law's.
  static func policyStart(_ policy: PeLeavePolicy) -> String? {
    policy.annualDays.map(\.from).sorted().first
  }

  /// Whether a month of service, from `first` to the day before `next`, earns no annual leave.
  private typealias Paused = (String, String) -> Bool

  private static func pausedMonthsOf(_ records: [PeLeaveRecord], pauseFrom: String?) -> Paused? {
    guard let from = pauseFrom else { return nil }
    var unpaid = Set<String>()
    for r in records where r.type == "unpaid" && r.isTaken && unpaidShare(r) <= 0 {
      for d in calendarDates(r.start, r.end) { unpaid.insert(d) }
    }
    if unpaid.count <= 15 { return nil }
    let days = Array(unpaid)
    return { first, next in
      first >= from && days.filter { $0 >= first && $0 < next }.count > 15
    }
  }

  private static func changes(_ rates: [Rate]) -> [(from: String, days: Double)] {
    rates.compactMap { rate in rate.from.map { (from: $0, days: rate.days) } }
  }

  private static func monthEarned(_ first: String, _ next: String, _ rates: [Rate]) -> Double {
    let length = Double(PeDates.daysBetween(first, next))
    guard length > 0 else { return 0 }
    var earned = 0.0
    var start = first
    for change in changes(rates) where change.from > first && change.from < next {
      earned += rateOn(rates, start) * Double(PeDates.daysBetween(start, change.from)) / length / 12
      start = change.from
    }
    return earned + rateOn(rates, start) * Double(PeDates.daysBetween(start, next)) / length / 12
  }

  private static func pausedMonthsBetween(_ from: String, _ on: String, _ paused: Paused?) -> [String] {
    guard let paused else { return [] }
    var out: [String] = []
    let months = PeDates.completedMonths(from, on)
    for index in 0..<max(0, months) {
      let first = PeDates.addMonths(from, index)
      if paused(first, PeDates.addMonths(from, index + 1)) { out.append(first) }
    }
    return out
  }

  private static func earnedDays(_ from: String, _ on: String, _ rates: [Rate], _ paused: Paused?) -> Double {
    var lost = 0.0
    for first in pausedMonthsBetween(from, on, paused) {
      lost += monthEarned(first, PeDates.addMonths(first, 1), rates)
    }
    let months = PeDates.completedMonths(from, on)
    let dated = changes(rates)
    let last = PeDates.addDays(PeDates.addMonths(from, months), -1)
    if !dated.contains(where: { $0.from > from && $0.from <= last }) {
      return Double(months) * rateOn(rates, from) / 12 - lost
    }
    var earned = 0.0
    for index in 0..<max(0, months) {
      let first = PeDates.addMonths(from, index)
      let next = PeDates.addMonths(from, index + 1)
      earned += monthEarned(first, next, rates)
    }
    return earned - lost
  }

  private struct Opening {
    let date: String
    let days: Double
    let record: PeLeaveRecord?
  }

  private static func openings(_ annual: [PeLeaveRecord], _ brought: PeLeaveOpening?) -> [Opening] {
    let records = annual.filter { $0.kind == "opening" }
    var out = records.map { Opening(date: $0.start, days: $0.days, record: $0) }
    if let brought, brought.confirmed || records.isEmpty {
      out.append(Opening(date: brought.date, days: brought.days, record: nil))
    }
    return out
  }

  private static func compare(_ a: String, _ b: String) -> Int { a < b ? -1 : (a > b ? 1 : 0) }

  /// On the same day a record counts before leave brought forward, and a newer record first.
  private static func sameDay(_ a: Opening, _ b: Opening) -> Int {
    let records = (b.record != nil ? 1 : 0) - (a.record != nil ? 1 : 0)
    if records != 0 { return records }
    return compare(b.record?.createdAt ?? "", a.record?.createdAt ?? "")
  }

  private static func latestFirst(_ a: Opening, _ b: Opening) -> Bool {
    let byDate = compare(b.date, a.date)
    return (byDate != 0 ? byDate : sameDay(a, b)) < 0
  }

  private static func earliestFirst(_ a: Opening, _ b: Opening) -> Bool {
    let byDate = compare(a.date, b.date)
    return (byDate != 0 ? byDate : sameDay(a, b)) < 0
  }

  private static func forfeitedDays(
    _ from: String, _ on: String, _ opening: Double, _ records: [PeLeaveRecord], _ rates: [Rate],
    _ policy: PeLeavePolicy, _ paused: Paused?
  ) -> Double {
    guard let cap = policy.carryForwardMax, let start = policyStart(policy) else { return 0 }
    func sum(_ kind: String, _ until: String) -> Double {
      records.filter { $0.kind == kind && $0.start <= until }.reduce(0) { $0 + $1.days }
    }
    func heldOn(_ date: String, _ lostBefore: Double) -> Double {
      PeMoney.twoPlaces(
        opening + earnedDays(from, date, rates, paused) + sum("adjustment", date) - sum("leave", date) - lostBefore)
    }
    let dayBefore = PeDates.addDays(start, -1)
    let lawDays = from < start ? max(0, heldOn(dayBefore, 0)) : 0
    var lost = 0.0
    var year = Int(from.prefix(4)) ?? 0
    while String(year) + "-12-31" < on {
      let yearEnd = String(year) + "-12-31"
      if String(year + 1) + "-01-01" >= start {
        let held = heldOn(yearEnd, lost)
        let kept = max(0, lawDays - (sum("leave", yearEnd) - sum("leave", dayBefore)))
        if held - kept > cap { lost += held - kept - cap }
      }
      year += 1
    }
    return PeMoney.twoPlaces(lost)
  }

  /// The annual leave balance on a day (`annualLeaveBalance`): the latest opening
  /// balance by then (or nothing from the hire date), the days earned for each
  /// month of service since, adjustments, less the annual leave taken; days
  /// over the policy's carry-forward cap are lost at each new year.
  static func annualBalance(
    _ records: [PeLeaveRecord], hireDate: String?, on: String, brought: PeLeaveOpening?, policy: PeLeavePolicy?,
    entitlement: Double?, entitlementFrom: String?, pauseFrom: String?
  ) -> PeLeaveBalance {
    let rules = policy ?? .law
    let rates = accrualRates(rules, entitlement, entitlementFrom)
    let paused = pausedMonthsOf(records, pauseFrom: pauseFrom)
    let annual = records.filter { $0.type == "annual" && $0.status == "approved" }
    let eligibleFrom = hireDate.map { PeDates.addMonths($0, rules.firstYearMonths) }
    let all = openings(annual, brought)
    let opening = all.filter { $0.date <= on }.sorted(by: latestFirst).first
    if opening == nil {
      if let hireDate, hireDate > on { return PeLeaveBalance(from: hireDate, eligibleFrom: eligibleFrom) }
      if let next = all.filter({ $0.date > on }).sorted(by: earliestFirst).first {
        let earned = earnedDays(PeDates.addDays(on, 1), PeDates.addDays(next.date, -1), rates, paused)
        let between = annual.filter { $0.start > on && $0.start < next.date && $0.kind != "opening" }
        let leave = between.filter { $0.kind == "leave" }.reduce(0) { $0 + $1.days }
        let adjustments = between.filter { $0.kind == "adjustment" }.reduce(0) { $0 + $1.days }
        let balance = PeMoney.twoPlaces(max(0, next.days - earned + leave - adjustments))
        return PeLeaveBalance(
          from: next.date, opening: next.days, accrued: PeMoney.twoPlaces(balance - next.days), balance: balance,
          eligibleFrom: eligibleFrom)
      }
    }
    var from = hireDate
    if let opening {
      from = opening.record == nil && (hireDate ?? "") > opening.date ? hireDate : opening.date
    }
    guard let from, from <= on else { return PeLeaveBalance(from: from, eligibleFrom: eligibleFrom) }
    let after = annual.filter { $0.start >= from && $0.start <= on && $0.kind != "opening" }
    let accrued = PeMoney.twoPlaces(earnedDays(from, on, rates, paused))
    let pausedMonths = pausedMonthsBetween(from, on, paused).count
    let adjusted = PeMoney.twoPlaces(after.filter { $0.kind == "adjustment" }.reduce(0) { $0 + $1.days })
    let taken = PeMoney.twoPlaces(after.filter { $0.kind == "leave" }.reduce(0) { $0 + $1.days })
    let openingDays = opening?.days ?? 0
    let forfeited = forfeitedDays(from, on, openingDays, after, rates, rules, paused)
    return PeLeaveBalance(
      from: from, opening: openingDays, accrued: accrued, adjusted: adjusted, taken: taken, forfeited: forfeited,
      pausedMonths: pausedMonths, balance: PeMoney.twoPlaces(openingDays + accrued + adjusted - taken - forfeited),
      eligibleFrom: eligibleFrom)
  }

  /// An employee's annual leave balance on a day (`employeeLeaveBalance`).
  static func employeeBalance(
    _ e: PeEmployee, _ records: [PeLeaveRecord], on: String, settings: PePayrollSettings
  ) -> PeLeaveBalance {
    annualBalance(
      records.filter { $0.employeeId == e.id }, hireDate: e.hireDate, on: on, brought: e.leaveOpening,
      policy: settings.leavePolicy, entitlement: e.annualLeaveDays, entitlementFrom: e.annualLeaveDaysFrom,
      pauseFrom: settings.accrualPauseFrom)
  }

  /// Annual leave has been recorded in the company: the way it is counted stays as it is.
  static func annualLeaveRecorded(_ records: [PeLeaveRecord]) -> Bool {
    records.contains { $0.type == "annual" && $0.kind == "leave" && $0.status != "cancelled" }
  }

  /// Current staff whose leave before they were added here isn't known
  /// (`employeesNeedingLeaveOpening`).
  static func needingOpening(_ employees: [PeEmployee], _ records: [PeLeaveRecord]) -> [PeEmployee] {
    var byEmployee: [String: [PeLeaveRecord]] = [:]
    for r in records where r.kind == "opening" && r.type == "annual" && r.status == "approved" {
      byEmployee[r.employeeId, default: []].append(r)
    }
    return employees.filter { e in
      if e.status == "left" { return false }
      let list = openings(byEmployee[e.id] ?? [], e.leaveOpening)
      if list.contains(where: { $0.record != nil }) { return false }
      if !list.isEmpty { return !(e.leaveOpening?.confirmed ?? false) }
      let added = String(e.createdAt.prefix(10))
      guard let hire = e.hireDate, !added.isEmpty else { return true }
      return hire < PeDates.addDays(added, -31)
    }
  }
}

extension OneData {
  /// The company's leave records.
  var peLeaveRecords: [PeLeaveRecord] { records(.leaveRecords).map { PeLeaveRecord($0) } }
}
