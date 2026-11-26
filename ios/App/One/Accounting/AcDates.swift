import Foundation
import MahamKit

// Calendar days written "yyyy-MM-dd", worked out as the web's `src/lib/dates.ts`
// does with JavaScript's `Date` (months and days past their end roll over).

enum AcDate {
  /// The year, month (1–12) and day of a date; nil when it isn't one.
  static func parts(_ date: String) -> (y: Int, m: Int, d: Int)? {
    let pieces = date.split(separator: "-")
    guard pieces.count == 3, let y = Int(pieces[0]), let m = Int(pieces[1]), let d = Int(pieces[2]) else { return nil }
    return (y, m, d)
  }

  static func daysIn(_ year: Int, _ month: Int) -> Int {
    switch month {
    case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
    case 4, 6, 9, 11: 30
    default: 31
    }
  }

  private static func two(_ value: Int) -> String {
    value < 10 ? "0\(value)" : "\(value)"
  }

  /// `toISODate(new Date(year, monthIndex, day))`: the month index is 0-based
  /// and may run past the year; the day may be 0 (the month before's last) or
  /// past the month's end.
  static func make(_ year: Int, _ monthIndex: Int, _ day: Int) -> String {
    var y = year + monthIndex / 12
    var m = monthIndex % 12
    if m < 0 {
      m += 12
      y -= 1
    }
    let first = "\(y)-\(two(m + 1))-01"
    return day == 1 ? first : ISODates.addDays(first, day - 1)
  }

  /// "2026-03" of a date.
  static func period(_ date: String) -> String { String(date.prefix(7)) }

  /// Last day of a "yyyy-MM" month (`periodEnd`).
  static func periodEnd(_ period: String) -> String {
    let pieces = period.split(separator: "-")
    guard pieces.count == 2, let y = Int(pieces[0]), let m = Int(pieces[1]) else { return period }
    return make(y, m, 0)
  }

  /// The month `months` after a "yyyy-MM" month (`shiftPeriod`).
  static func shiftPeriod(_ period: String, _ months: Int) -> String {
    let pieces = period.split(separator: "-")
    guard pieces.count == 2, let y = Int(pieces[0]), let m = Int(pieces[1]) else { return period }
    return String(make(y, m - 1 + months, 1).prefix(7))
  }

  static func addDays(_ date: String, _ days: Int) -> String { ISODates.addDays(date, days) }

  /// Calendar days from `from` to `to`.
  static func daysBetween(_ from: String, _ to: String) -> Int { ISODates.daysBetween(from, to) ?? 0 }

  static var today: String { ISODates.today() }

  /// `presetRange` (src/lib/reports.ts).
  static func presetRange(_ preset: String, _ today: String) -> AcRange {
    guard let t = parts(today) else { return AcRange(from: today, to: today) }
    let y = t.y
    let m = t.m - 1
    let q = m / 3
    switch preset {
    case "this-month": return AcRange(from: make(y, m, 1), to: make(y, m + 1, 0))
    case "last-month": return AcRange(from: make(y, m - 1, 1), to: make(y, m, 0))
    case "this-quarter": return AcRange(from: make(y, q * 3, 1), to: make(y, q * 3 + 3, 0))
    case "last-quarter": return AcRange(from: make(y, q * 3 - 3, 1), to: make(y, q * 3, 0))
    case "this-year": return AcRange(from: make(y, 0, 1), to: make(y, 11, 31))
    case "last-year": return AcRange(from: make(y - 1, 0, 1), to: make(y - 1, 11, 31))
    default: return AcRange(from: "0000-01-01", to: "9999-12-31")
    }
  }

  // MARK: Words

  /// "March 2026" in the interface language (`monthLabel`).
  static func monthLabel(_ period: String, arabic: Bool) -> String {
    let pieces = period.split(separator: "-")
    guard pieces.count >= 2, let y = Int(pieces[0]), let m = Int(pieces[1]) else { return period }
    return monthName(m, arabic: arabic, short: false) + " " + "\(y)"
  }

  /// A month's name ("March", "Mar"; "مارس").
  static func monthName(_ month: Int, arabic: Bool, short: Bool) -> String {
    let calendar = arabic ? arabicCalendar : englishCalendar
    let names = short && !arabic ? calendar.shortStandaloneMonthSymbols : calendar.standaloneMonthSymbols
    guard month >= 1, month <= names.count else { return "\(month)" }
    return names[month - 1]
  }

  private static let englishCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_GB")
    return calendar
  }()

  private static let arabicCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "ar_KW@numbers=latn")
    return calendar
  }()

  /// A VAT period's name (`periodName`): "October 2026", or "Jul – Sep 2026" for a quarter.
  static func periodName(_ start: String, _ end: String, arabic: Bool) -> String {
    guard let a = parts(start), let b = parts(end) else { return start }
    if a.y == b.y, a.m == b.m { return monthLabel(start, arabic: arabic) }
    let first = monthName(a.m, arabic: arabic, short: true)
    let last = monthName(b.m, arabic: arabic, short: true)
    if a.y == b.y { return "\(first) – \(last) \(b.y)" }
    return "\(first) \(a.y) – \(last) \(b.y)"
  }
}

// MARK: Financial years

/// `fiscalYearStart`, `fiscalYearEnd` and the comparative periods (`src/lib/accounting/statements.ts`).
enum AcFiscal {
  /// Last day of the financial year that ends in `year` (Feb 29 clamps to Feb 28).
  static func yearEndIn(_ year: Int, _ end: AcFiscalEnd) -> String {
    let last = AcDate.daysIn(year, end.month)
    return AcDate.make(year, end.month - 1, min(end.day, last))
  }

  /// First day of the financial year containing `date`.
  static func start(_ date: String, _ end: AcFiscalEnd) -> String {
    guard let year = AcDate.parts(date)?.y else { return date }
    let endThisYear = yearEndIn(year, end)
    return date <= endThisYear
      ? AcDate.addDays(yearEndIn(year - 1, end), 1) : AcDate.addDays(endThisYear, 1)
  }

  /// Last day of the financial year containing `date`.
  static func end(_ date: String, _ end: AcFiscalEnd) -> String {
    guard let year = AcDate.parts(date)?.y else { return date }
    let endThisYear = yearEndIn(year, end)
    return date <= endThisYear ? endThisYear : yearEndIn(year + 1, end)
  }

  /// `previousYearRange`: the same period a year earlier; month ends stay month ends.
  static func previousYear(_ range: AcRange) -> AcRange {
    func shift(_ date: String) -> String {
      guard let d = AcDate.parts(date) else { return date }
      let year = d.y - 1
      let day = d.d == AcDate.daysIn(d.y, d.m) ? AcDate.daysIn(year, d.m) : min(d.d, AcDate.daysIn(year, d.m))
      return AcDate.make(year, d.m - 1, day)
    }
    return AcRange(from: shift(range.from), to: shift(range.to))
  }

  /// `comparativeDate`: the end of the previous financial year.
  static func comparativeDate(_ asOf: String, _ end: AcFiscalEnd) -> String {
    AcDate.addDays(start(asOf, end), -1)
  }

  /// `isFinancialYear`: the range is exactly one financial year.
  static func isFinancialYear(_ range: AcRange, _ end: AcFiscalEnd) -> Bool {
    start(range.from, end) == range.from && self.end(range.from, end) == range.to
  }

  /// `financialYearLabel`: "2026", or "2025–2026".
  static func label(_ start: String, _ end: String) -> String {
    let a = String(start.prefix(4))
    let b = String(end.prefix(4))
    return a == b ? b : "\(a)–\(b)"
  }

  /// `financialYears`: from the year holding `first` to the one holding `now`, latest first.
  static func years(_ first: String?, _ end: AcFiscalEnd, _ now: String) -> [AcRange] {
    var years: [AcRange] = []
    var last = self.end(now, end)
    let stop = first.map { $0 < now ? $0 : now } ?? now
    for _ in 0..<50 {
      let from = start(last, end)
      years.append(AcRange(from: from, to: last))
      if from <= stop { break }
      last = AcDate.addDays(from, -1)
    }
    return years
  }

  /// The period presets of the statements (`periodRange`).
  static func periodRange(_ preset: String, _ end: AcFiscalEnd, custom: AcRange, today: String) -> AcRange {
    switch preset {
    case "this-year": return AcRange(from: start(today, end), to: self.end(today, end))
    case "last-year":
      let lastEnd = AcDate.addDays(start(today, end), -1)
      return AcRange(from: start(lastEnd, end), to: lastEnd)
    case "custom": return custom
    default: return AcDate.presetRange(preset, today)
    }
  }

  /// The "as at" presets (`asOfDate`).
  static func asOfDate(_ preset: String, _ end: AcFiscalEnd, custom: String, today: String) -> String {
    switch preset {
    case "last-month": return AcDate.presetRange("last-month", today).to
    case "last-quarter": return AcDate.presetRange("last-quarter", today).to
    case "year-end": return self.end(today, end)
    case "last-year": return AcDate.addDays(start(today, end), -1)
    case "custom": return custom
    default: return today
    }
  }
}
