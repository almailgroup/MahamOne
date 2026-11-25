import Foundation

// The port of the web's `src/lib/dates.ts`: calendar days written
// `yyyy-MM-dd`, compared as text. The web reads them with JavaScript's
// `new Date(year, month - 1, day)`, and the port keeps what that does with
// unusual input: a day past the month's end rolls into the next month
// ("2026-02-30" is March 2), years 0–99 are read as 1900–1999, and text that
// is not a date gives "NaN-NaN-NaN".

public enum ISODates {
  /// How often a recurring document repeats (`Frequency` in the web's
  /// `db/types.ts`).
  public enum Frequency: String, CaseIterable, Codable, Sendable {
    case weekly, biweekly, monthly, bimonthly, quarterly, semiannually, yearly

    /// The English label; show it with `t(_:)`.
    public var label: String {
      switch self {
      case .weekly: "Weekly"
      case .biweekly: "Every 2 weeks"
      case .monthly: "Monthly"
      case .bimonthly: "Every 2 months"
      case .quarterly: "Quarterly"
      case .semiannually: "Every 6 months"
      case .yearly: "Yearly"
      }
    }
  }

  /// `FREQUENCIES`, in the web's order.
  public static let frequencies: [(value: Frequency, label: String)] = Frequency.allCases.map {
    ($0, $0.label)
  }

  /// What the web's `toISODate` writes for an invalid date.
  public static let invalid = "NaN-NaN-NaN"

  /// True for `yyyy-MM-dd` text that names a real day.
  public static func isISODate(_ value: String) -> Bool {
    guard let parts = fields(value) else { return false }
    let day = CivilDay(javaScriptYear: parts.year, month: parts.month, day: parts.day)
    return day.year == parts.year && day.month == parts.month
  }

  /// The day as the web's `parseISODate` reads it, written back as
  /// `yyyy-MM-dd`; nil when the text is not in that form.
  public static func normalized(_ value: String) -> String? {
    parse(value)?.text
  }

  /// Today in a time zone, as `yyyy-MM-dd` (the web uses the device's zone).
  public static func today(in zone: TimeZone = .current, now: Date = Date()) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let parts = calendar.dateComponents([.year, .month, .day], from: now)
    return CivilDay(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1).text
  }

  /// The day of a moment in a time zone, as `yyyy-MM-dd` (`toISODate(date)`).
  public static func string(from date: Date, in zone: TimeZone = .current) -> String {
    today(in: zone, now: date)
  }

  /// `addDaysISO`: the day `days` after (or before) `value`.
  public static func addDays(_ value: String, _ days: Int) -> String {
    guard let day = parse(value) else { return invalid }
    return day.adding(days: days).text
  }

  /// Calendar days from `from` to `to` (positive when `to` is later); nil
  /// where the web gets NaN.
  public static func daysBetween(_ from: String, _ to: String) -> Int? {
    guard let start = parse(from), let end = parse(to) else { return nil }
    return end.dayNumber - start.dayNumber
  }

  /// Date of the n-th occurrence (0-based) of a schedule. Computed from the
  /// start date each time so month-end dates don't drift (Jan 31 -> Feb 28 ->
  /// Mar 31).
  public static func occurrenceDate(_ start: String, _ frequency: Frequency, _ index: Int) -> String {
    guard let day = parse(start) else { return invalid }
    let result: CivilDay
    switch frequency {
    case .weekly: result = day.adding(days: 7 * index)
    case .biweekly: result = day.adding(days: 14 * index)
    case .monthly: result = day.adding(months: index)
    case .bimonthly: result = day.adding(months: index * 2)
    case .quarterly: result = day.adding(months: index * 3)
    case .semiannually: result = day.adding(months: index * 6)
    case .yearly: result = day.adding(months: index * 12)
    }
    return result.text
  }

  // MARK: Reading

  /// The numbers in `^(\d{4})-(\d{2})-(\d{2})$`.
  static func fields(_ value: String) -> (year: Int, month: Int, day: Int)? {
    let bytes = Array(value.utf8)
    guard bytes.count == 10, bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-") else {
      return nil
    }
    func number(_ range: Range<Int>) -> Int? {
      var result = 0
      for index in range {
        let byte = bytes[index]
        guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
        result = result * 10 + Int(byte - UInt8(ascii: "0"))
      }
      return result
    }
    guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10) else {
      return nil
    }
    return (year, month, day)
  }

  /// `parseISODate`: nil where the web gets an invalid date.
  static func parse(_ value: String) -> CivilDay? {
    guard let parts = fields(value) else { return nil }
    return CivilDay(javaScriptYear: parts.year, month: parts.month, day: parts.day)
  }
}

/// A day of the proleptic Gregorian calendar, which JavaScript's `Date` uses.
struct CivilDay: Hashable, Sendable {
  let year: Int
  let month: Int
  let day: Int

  /// A day already in range.
  init(year: Int, month: Int, day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }

  /// `new Date(year, month - 1, day)`: out-of-range months and days roll
  /// over, and years 0–99 mean 1900–1999.
  init(javaScriptYear year: Int, month: Int, day: Int) {
    let fullYear = (0...99).contains(year) ? 1900 + year : year
    let monthIndex = month - 1
    let first = CivilDay(
      year: fullYear + Self.floorDivide(monthIndex, 12), month: Self.floorModulo(monthIndex, 12) + 1, day: 1)
    self = CivilDay(dayNumber: first.dayNumber + day - 1)
  }

  /// Days since 1970-01-01.
  init(dayNumber: Int) {
    // Howard Hinnant's civil_from_days.
    let z = dayNumber + 719_468
    let era = Self.floorDivide(z, 146_097)
    let dayOfEra = z - era * 146_097
    let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let mp = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * mp + 2) / 5 + 1
    let month = mp < 10 ? mp + 3 : mp - 9
    self.init(year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month: month, day: day)
  }

  /// Days since 1970-01-01.
  var dayNumber: Int {
    // Howard Hinnant's days_from_civil.
    let y = month <= 2 ? year - 1 : year
    let era = Self.floorDivide(y, 400)
    let yearOfEra = y - era * 400
    let mp = month > 2 ? month - 3 : month + 9
    let dayOfYear = (153 * mp + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
  }

  /// 0 for Sunday, as `Date.getDay()`.
  var weekday: Int { Self.floorModulo(dayNumber + 4, 7) }

  func adding(days: Int) -> CivilDay { CivilDay(dayNumber: dayNumber + days) }

  /// date-fns `addMonths`: the same day of the month, or the month's last
  /// day when it is shorter.
  func adding(months: Int) -> CivilDay {
    if months == 0 { return self }
    let index = month - 1 + months
    let targetYear = year + Self.floorDivide(index, 12)
    let targetMonth = Self.floorModulo(index, 12) + 1
    let length = Self.daysIn(year: targetYear, month: targetMonth)
    return CivilDay(year: targetYear, month: targetMonth, day: min(day, length))
  }

  /// `yyyy-MM-dd` the way the web's `toISODate` writes it (the year is not
  /// padded).
  var text: String {
    String(year) + "-" + Self.twoDigits(month) + "-" + Self.twoDigits(day)
  }

  static func daysIn(year: Int, month: Int) -> Int {
    switch month {
    case 2:
      let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
      return leap ? 29 : 28
    case 4, 6, 9, 11:
      return 30
    default:
      return 31
    }
  }

  static func twoDigits(_ value: Int) -> String {
    value < 10 && value >= 0 ? "0" + String(value) : String(value)
  }

  static func floorDivide(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
  }

  static func floorModulo(_ a: Int, _ b: Int) -> Int {
    let r = a % b
    return r < 0 ? r + b : r
  }
}
