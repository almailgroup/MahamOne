import Foundation

/// The figures depreciation is worked out from (`DepreciationTerms`, `assetTerms(asset)`).
public struct AwDepreciationTerms: Sendable {
  public var cost: Double
  public var salvageValue: Double
  public var usefulLifeMonths: Double
  public var method: String
  public var decliningRate: Double?
  public var depreciationStart: String
  public var openingDepreciation: Double
  public var openingDepreciationDate: String?

  public init(_ asset: JSONValue) {
    cost = asset.awNum("cost")
    salvageValue = asset.awNum("salvageValue")
    usefulLifeMonths = asset.awNum("usefulLifeMonths")
    method = asset.awStr("method")
    decliningRate = asset["decliningRate"]?.double
    depreciationStart = asset.awStr("depreciationStart")
    openingDepreciation = asset.awNum("openingDepreciation")
    openingDepreciationDate = asset.awText("openingDepreciationDate")
  }
}

/// The port of src/lib/accounting/depreciation.ts: the depreciation an asset
/// should have at the end of a day, in integer minor units. Part months
/// count by days.
public enum AwDepreciation {
  /// `periodOf(date)`: `yyyy-MM`.
  public static func periodOf(_ date: String) -> String { WebJS.prefix(date, 7) }

  /// `periodEnd(period)`: the month's last day.
  public static func periodEnd(_ period: String) -> String {
    let parts = period.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count >= 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return ISODates.invalid }
    return CivilDay(javaScriptYear: year, month: month + 1, day: 0).text
  }

  /// `shiftPeriod(period, months)`.
  public static func shiftPeriod(_ period: String, _ months: Int) -> String {
    let parts = period.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count >= 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return period }
    let day = CivilDay(javaScriptYear: year, month: month + months, day: 1)
    return String(day.year) + "-" + CivilDay.twoDigits(day.month)
  }

  private struct Segment {
    let period: String
    /// Share of the month covered, 0–1.
    let fraction: Decimal
  }

  /// The months between two dates (both included), as fractions of each month.
  private static func segments(_ from: String, _ to: String) -> [Segment] {
    if WebJS.less(to, from) { return [] }
    guard var cursor = ISODates.parse(from), let last = ISODates.parse(to) else { return [] }
    var out: [Segment] = []
    while cursor.dayNumber <= last.dayNumber {
      let days = CivilDay.daysIn(year: cursor.year, month: cursor.month)
      let sameMonth = cursor.year == last.year && cursor.month == last.month
      let endDay = sameMonth ? last.day : days
      let covered = endDay - cursor.day + 1
      let period = String(cursor.year) + "-" + CivilDay.twoDigits(cursor.month)
      out.append(Segment(period: period, fraction: covered == days ? 1 : Decimal(covered) / Decimal(days)))
      cursor = CivilDay(javaScriptYear: cursor.year, month: cursor.month + 1, day: 1)
    }
    return out
  }

  /// `elapsedMonths(from, to)`.
  public static func elapsedMonths(_ from: String, _ to: String) -> Decimal {
    segments(from, to).reduce(Decimal(0)) { $0 + $1.fraction }
  }

  /// `defaultDecliningRate(months)`: twice the straight-line rate.
  public static func defaultDecliningRate(_ months: Double) -> Double {
    if !(months > 0) { return 0 }
    return awRound(Decimal(2400) / Money.dec(months), 2)
  }

  /// `decliningRateOf(terms)`.
  public static func decliningRate(_ terms: AwDepreciationTerms) -> Double {
    if let rate = terms.decliningRate, rate != 0, !rate.isNaN, rate > 0 { return rate }
    return defaultDecliningRate(terms.usefulLifeMonths)
  }

  private struct Start {
    let begin: String
    let accumulated: Int
    let used: Decimal
  }

  private static func startOf(_ terms: AwDepreciationTerms, _ p: Int) -> Start {
    let start = terms.depreciationStart
    if terms.openingDepreciation > 0, let openingDate = terms.openingDepreciationDate {
      let after = ISODates.addDays(openingDate, 1)
      return Start(
        begin: WebJS.less(start, after) ? after : start, accumulated: awMinor(terms.openingDepreciation, p),
        used: elapsedMonths(start, openingDate))
    }
    return Start(begin: start, accumulated: 0, used: 0)
  }

  /// `depreciableAmount(terms)`: cost less salvage value (minor units).
  public static func depreciableAmount(_ terms: AwDepreciationTerms, _ p: Int) -> Int {
    max(0, awMinor(terms.cost, p) - awMinor(terms.salvageValue, p))
  }

  /// `walk(...)` up to `until`: the accumulated depreciation at its end.
  private static func walk(_ terms: AwDepreciationTerms, _ p: Int, until: String) -> Int {
    let start = startOf(terms, p)
    let total = depreciableAmount(terms, p)
    var accumulated = start.accumulated
    if accumulated >= total { return accumulated }
    let leftAtStart = total - accumulated
    let lifeLeft = Money.dec(max(0, terms.usefulLifeMonths)) - start.used
    // Yearly rate in percent; divided by 1,200 for a month (last, to stay exact).
    let rate = Money.dec(decliningRate(terms))
    let cost = awMinor(terms.cost, p)
    var used = Decimal(0)
    for segment in segments(start.begin, until) {
      let left = total - accumulated
      if left <= 0 { break }
      // Life left before this piece of the month.
      let remaining = lifeLeft - used
      used += segment.fraction
      if remaining <= segment.fraction {
        // The useful life ends in this month (or has already ended).
        accumulated = total
      } else if terms.method == "declining_balance" {
        let declining = Decimal(cost - accumulated) * rate * segment.fraction / 1200
        // Switch to straight line once it gives more, so the asset reaches its
        // salvage value exactly when its life ends.
        let straight = Decimal(left) * segment.fraction / remaining
        accumulated += min(left, awMinor(declining > straight ? declining : straight, 0))
      } else {
        // Straight line: what is left is spread evenly over the life that is left.
        let share = awMinor(Decimal(leftAtStart) * used / lifeLeft, 0)
        accumulated = min(total, start.accumulated + share)
      }
    }
    return accumulated
  }

  /// `accumulatedAt(terms, date)`: the accumulated depreciation (minor units)
  /// an asset should have at the end of `date`, including what was charged
  /// before it was entered.
  public static func accumulatedAt(_ terms: AwDepreciationTerms, _ date: String, _ p: Int) -> Int {
    if WebJS.less(date, terms.depreciationStart) { return 0 }
    let start = startOf(terms, p)
    if WebJS.less(date, start.begin) { return start.accumulated }
    return walk(terms, p, until: date)
  }
}
