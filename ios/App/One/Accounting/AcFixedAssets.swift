import Foundation
import MahamKit

// Fixed assets as the web works them out (`src/lib/accounting/depreciation.ts`,
// `asset-schedule.ts` and the read side of `src/db/assets.ts`): the
// accumulated depreciation an asset should have at the end of a day, in
// integer minor units, its month-by-month schedule, what is already posted,
// and the property and equipment note.

/// The figures depreciation is worked out from (`DepreciationTerms`).
struct AcDepreciationTerms: Sendable {
  let cost: Double
  let salvageValue: Double
  let usefulLifeMonths: Double
  let method: String
  let decliningRate: Double?
  let depreciationStart: String
  let openingDepreciation: Double
  let openingDepreciationDate: String?

  /// `assetTerms(asset)`.
  init(_ asset: JSONValue) {
    cost = asset.num("cost")
    salvageValue = asset.num("salvageValue")
    usefulLifeMonths = asset.num("usefulLifeMonths")
    method = asset.str("method")
    decliningRate = asset.number("decliningRate")
    depreciationStart = asset.str("depreciationStart")
    openingDepreciation = asset.num("openingDepreciation")
    openingDepreciationDate = asset.text("openingDepreciationDate")
  }
}

/// One month of a depreciation schedule (`ScheduleRow`).
struct AcScheduleRow: Sendable {
  let period: String
  let date: String
  let charge: Int
  let accumulated: Int
  let bookValue: Int
}

enum AcDepreciation {
  private struct Segment {
    let period: String
    /// Share of the month covered, 0–1.
    let fraction: Decimal
  }

  /// The months between two dates (both included), as fractions of each month.
  private static func segments(_ from: String, _ to: String) -> [Segment] {
    if to < from { return [] }
    guard var cursor = AcDate.parts(from), let last = AcDate.parts(to) else { return [] }
    var out: [Segment] = []
    while (cursor.y, cursor.m, cursor.d) <= (last.y, last.m, last.d) {
      let days = AcDate.daysIn(cursor.y, cursor.m)
      let sameMonth = cursor.y == last.y && cursor.m == last.m
      let endDay = sameMonth ? last.d : days
      let covered = endDay - cursor.d + 1
      let period = "\(cursor.y)-\(cursor.m < 10 ? "0" : "")\(cursor.m)"
      out.append(Segment(period: period, fraction: covered == days ? 1 : Decimal(covered) / Decimal(days)))
      cursor = cursor.m == 12 ? (cursor.y + 1, 1, 1) : (cursor.y, cursor.m + 1, 1)
      if out.count > 2000 { break }
    }
    return out
  }

  /// Months (with fractions for part months) from `from` to `to`.
  static func elapsedMonths(_ from: String, _ to: String) -> Decimal {
    segments(from, to).reduce(Decimal(0)) { $0 + $1.fraction }
  }

  /// Twice the straight-line rate, e.g. 40% a year for a 5-year life.
  static func defaultDecliningRate(_ months: Double) -> Double {
    if !(months > 0) { return 0 }
    return Money.toNumber(Money.round(Decimal(2400) / Money.dec(months), 2))
  }

  static func decliningRate(_ terms: AcDepreciationTerms) -> Double {
    if let rate = terms.decliningRate, rate > 0 { return rate }
    return defaultDecliningRate(terms.usefulLifeMonths)
  }

  private struct Start {
    let begin: String
    let accumulated: Int
    let used: Decimal
  }

  private static func startOf(_ terms: AcDepreciationTerms, _ p: Int) -> Start {
    let start = terms.depreciationStart
    if terms.openingDepreciation > 0, let openingDate = terms.openingDepreciationDate {
      let after = AcDate.addDays(openingDate, 1)
      return Start(
        begin: after > start ? after : start, accumulated: AcLedger.minor(terms.openingDepreciation, p),
        used: elapsedMonths(start, openingDate))
    }
    return Start(begin: start, accumulated: 0, used: 0)
  }

  /// Cost less salvage value (minor units).
  static func depreciableAmount(_ terms: AcDepreciationTerms, _ p: Int) -> Int {
    max(0, AcLedger.minor(terms.cost, p) - AcLedger.minor(terms.salvageValue, p))
  }

  /// `walk`: the accumulated depreciation at the end of each piece of a month.
  private static func walk(
    _ terms: AcDepreciationTerms, _ p: Int, until: String?, _ visit: (String, Int, Bool) -> Void
  ) -> Int {
    let start = startOf(terms, p)
    let total = depreciableAmount(terms, p)
    var accumulated = start.accumulated
    if accumulated >= total { return accumulated }
    let leftAtStart = total - accumulated
    let lifeLeft = Money.dec(max(0, terms.usefulLifeMonths)) - start.used
    let rate = Money.dec(decliningRate(terms))
    let cost = AcLedger.minor(terms.cost, p)
    let end = until ?? AcDate.addDays(start.begin, 36525)
    var used = Decimal(0)
    for segment in segments(start.begin, end) {
      let left = total - accumulated
      if left <= 0 { break }
      let remaining = lifeLeft - used
      used += segment.fraction
      if remaining <= segment.fraction {
        accumulated = total
      } else if terms.method == "declining_balance" {
        let declining = Decimal(cost - accumulated) * rate * segment.fraction / 1200
        let straight = Decimal(left) * segment.fraction / remaining
        accumulated += min(left, AcLedger.minor(declining > straight ? declining : straight))
      } else {
        let share = AcLedger.minor(Decimal(leftAtStart) * used / lifeLeft)
        accumulated = min(total, start.accumulated + share)
      }
      let partial = segment.period == AcDate.period(end) && end != AcDate.periodEnd(segment.period)
      visit(segment.period, accumulated, partial)
    }
    return accumulated
  }

  /// `accumulatedAt`: what an asset should have at the end of `date`.
  static func accumulatedAt(_ terms: AcDepreciationTerms, _ date: String, _ p: Int) -> Int {
    if date < terms.depreciationStart { return 0 }
    let start = startOf(terms, p)
    if date < start.begin { return start.accumulated }
    return walk(terms, p, until: date) { _, _, _ in }
  }

  /// `depreciationSchedule`: month by month to the end of the useful life.
  static func schedule(_ terms: AcDepreciationTerms, _ p: Int) -> [AcScheduleRow] {
    let start = startOf(terms, p)
    let cost = AcLedger.minor(terms.cost, p)
    var rows: [AcScheduleRow] = []
    var previous = start.accumulated
    _ = walk(terms, p, until: nil) { period, accumulated, partial in
      if partial { return }
      rows.append(
        AcScheduleRow(
          period: period, date: AcDate.periodEnd(period), charge: accumulated - previous, accumulated: accumulated,
          bookValue: cost - accumulated))
      previous = accumulated
    }
    return rows
  }
}

/// The register's figures (`src/db/assets.ts`).
enum AcAssets {
  /// Runs that were not undone.
  static func activeRuns(_ runs: [JSONValue]) -> [JSONValue] {
    runs.filter { $0.text("reversedAt") == nil }
  }

  /// `postedDepreciation`: opening depreciation, every active run, and the
  /// depreciation up to a disposal.
  static func posted(_ asset: JSONValue, _ runs: [JSONValue], _ p: Int, upTo: String? = nil) -> Int {
    var total = AcLedger.minor(asset.num("openingDepreciation"), p)
    let id = asset.rid
    for run in activeRuns(runs) {
      if let upTo, run.str("date") > upTo { continue }
      for line in run.list("lines") where line.str("assetId") == id {
        total += AcLedger.minor(line.num("amount"), p)
      }
    }
    if let disposal = asset.obj("disposal"), upTo == nil || disposal.str("date") <= upTo! {
      total += AcLedger.minor(disposal.num("depreciation"), p)
    }
    return total
  }

  /// `lastDepreciationDate`.
  static func lastDepreciationDate(_ asset: JSONValue, _ runs: [JSONValue]) -> String? {
    var last: String?
    let id = asset.rid
    for run in activeRuns(runs)
    where run.list("lines").contains(where: { $0.str("assetId") == id && $0.num("amount") != 0 }) {
      if last == nil || run.str("date") > last! { last = run.str("date") }
    }
    return last
  }

  /// `bookValue`: 0 once disposed of or void.
  static func bookValue(_ asset: JSONValue, _ runs: [JSONValue], _ p: Int) -> Int {
    let status = asset.str("status")
    if status == "void" || status == "disposed" { return 0 }
    return AcLedger.minor(asset.num("cost"), p) - posted(asset, runs, p)
  }

  /// "5 years", "2 years and 6 months", "18 months" (`lifeText`).
  static func lifeText(_ months: Int) -> String {
    if months <= 0 { return "—" }
    let years = months / 12
    let rest = months % 12
    let monthText = tp(rest, "{count} month", "{count} months")
    let yearText = tp(years, "{count} year", "{count} years")
    if years == 0 { return monthText }
    if rest == 0 { return yearText }
    return t("{years} and {months}", ["years": yearText, "months": monthText])
  }

  /// `AssetStatusBadge`.
  static func status(_ status: String) -> StatusMeta {
    switch status {
    case "active": StatusMeta(label: "In use", tone: .green)
    case "disposed": StatusMeta(label: "Disposed of", tone: .slate)
    case "void": StatusMeta(label: "Void", tone: .gray)
    default: .unknown
    }
  }

  /// `METHOD_LABELS`.
  static func methodLabel(_ method: String) -> String {
    method == "declining_balance" ? "Declining balance" : "Straight line"
  }

  /// `SOURCE_LABELS`.
  static func sourceLabel(_ source: String) -> String {
    switch source {
    case "purchase": "Paid for now"
    case "bill": "From a bill"
    case "opening": "Owned before"
    default: "Already in the books"
    }
  }
}

// MARK: The property and equipment note

/// `AssetScheduleFigures`, minor units.
struct AcScheduleFigures: Sendable {
  var costOpening = 0
  var additions = 0
  var disposals = 0
  var costClosing = 0
  var depreciationOpening = 0
  var charge = 0
  var depreciationOnDisposals = 0
  var depreciationClosing = 0
  var bookValueOpening = 0
  var bookValueClosing = 0

  mutating func add(_ other: AcScheduleFigures) {
    costOpening += other.costOpening
    additions += other.additions
    disposals += other.disposals
    costClosing += other.costClosing
    depreciationOpening += other.depreciationOpening
    charge += other.charge
    depreciationOnDisposals += other.depreciationOnDisposals
    depreciationClosing += other.depreciationClosing
    bookValueOpening += other.bookValueOpening
    bookValueClosing += other.bookValueClosing
  }

  /// The columns of the schedule; disposals reduce cost and depreciation, so they show negative.
  var columns: [Int] {
    [
      costOpening, additions, -disposals, costClosing, depreciationOpening, charge, -depreciationOnDisposals,
      depreciationClosing, bookValueClosing,
    ]
  }

  static let labels = [
    "Cost at start", "Additions", "Disposals", "Cost at end", "Depreciation at start", "Charge for the period",
    "On disposals", "Depreciation at end", "Book value at end",
  ]
}

struct AcScheduleGroup: Sendable {
  let account: AcAccount?
  let accountId: String
  var rows: [(asset: JSONValue, figures: AcScheduleFigures)]
  var totals: AcScheduleFigures
}

enum AcAssetSchedule {
  /// Depreciation of an asset in the books at the end of `date` (minor units).
  static func depreciationAt(_ asset: JSONValue, _ runs: [JSONValue], _ date: String, _ p: Int) -> Int {
    var total = 0
    let openingDate = asset.text("openingDepreciationDate") ?? asset.str("purchaseDate")
    if asset.num("openingDepreciation") > 0, openingDate <= date {
      total += AcLedger.minor(asset.num("openingDepreciation"), p)
    }
    let id = asset.rid
    for run in runs where run.text("reversedAt") == nil && run.str("date") <= date {
      for line in run.list("lines") where line.str("assetId") == id { total += AcLedger.minor(line.num("amount"), p) }
    }
    if let disposal = asset.obj("disposal"), disposal.str("date") <= date {
      total += AcLedger.minor(disposal.num("depreciation"), p)
    }
    return total
  }

  /// `assetScheduleRow`.
  static func row(_ asset: JSONValue, _ runs: [JSONValue], _ range: AcRange, _ p: Int) -> AcScheduleFigures {
    let cost = AcLedger.minor(asset.num("cost"), p)
    let bought = asset.str("purchaseDate")
    let disposedOn = asset.obj("disposal")?.text("date")
    func inBooksAt(_ date: String) -> Bool {
      guard bought <= date else { return false }
      if let disposedOn, disposedOn <= date { return false }
      return true
    }
    let startDay = AcDate.addDays(range.from, -1)
    var f = AcScheduleFigures()
    f.costOpening = inBooksAt(startDay) ? cost : 0
    f.additions = bought >= range.from && bought <= range.to ? cost : 0
    let disposedInPeriod = disposedOn.map { $0 >= range.from && $0 <= range.to } ?? false
    f.disposals = disposedInPeriod ? cost : 0
    f.depreciationOpening = inBooksAt(startDay) ? depreciationAt(asset, runs, startDay, p) : 0
    f.depreciationOnDisposals = disposedInPeriod ? depreciationAt(asset, runs, disposedOn ?? "", p) : 0
    f.depreciationClosing = inBooksAt(range.to) ? depreciationAt(asset, runs, range.to, p) : 0
    f.charge = f.depreciationClosing + f.depreciationOnDisposals - f.depreciationOpening
    f.costClosing = f.costOpening + f.additions - f.disposals
    f.bookValueOpening = f.costOpening - f.depreciationOpening
    f.bookValueClosing = f.costClosing - f.depreciationClosing
    return f
  }

  /// `assetSchedule`: grouped by asset account; void assets are left out.
  static func build(_ assets: [JSONValue], _ runs: [JSONValue], _ books: AcBooks, _ range: AcRange)
    -> (groups: [AcScheduleGroup], totals: AcScheduleFigures)
  {
    let p = books.precision
    var order: [String] = []
    var groups: [String: AcScheduleGroup] = [:]
    var totals = AcScheduleFigures()
    for asset in assets where asset.str("status") != "void" {
      let figures = row(asset, runs, range, p)
      let touched =
        figures.costOpening != 0 || figures.additions != 0 || figures.disposals != 0 || figures.charge != 0
        || figures.depreciationOpening != 0
      if !touched { continue }
      let accountId = asset.str("assetAccountId")
      var group =
        groups[accountId]
        ?? AcScheduleGroup(account: books.account(accountId), accountId: accountId, rows: [], totals: AcScheduleFigures())
      if groups[accountId] == nil { order.append(accountId) }
      group.rows.append((asset, figures))
      group.totals.add(figures)
      totals.add(figures)
      groups[accountId] = group
    }
    var sorted = order.compactMap { groups[$0] }.enumerated().sorted { a, b in
      let order = AcText.compareNumeric(a.element.account?.code ?? "", b.element.account?.code ?? "")
      return order == .orderedSame ? a.offset < b.offset : order == .orderedAscending
    }.map { $0.element }
    for index in sorted.indices {
      sorted[index].rows = sorted[index].rows.enumerated().sorted { a, b in
        let order = AcText.compareNumeric(a.element.asset.str("number"), b.element.asset.str("number"))
        return order == .orderedSame ? a.offset < b.offset : order == .orderedAscending
      }.map { $0.element }
    }
    return (sorted, totals)
  }
}
