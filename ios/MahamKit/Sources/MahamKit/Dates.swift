import Foundation

/// Dates as both databases write them.
///
/// Timestamps (`timestamptz`) come as ISO 8601 with up to six fractional
/// digits and an offset (`2026-11-24T10:15:00.123456+00:00`). Maham One's
/// calendar dates (an invoice's due date, a passport's expiry) are plain
/// `yyyy-MM-dd`: a day, not a moment, so they are kept as `LocalDate`.
public enum MahamDates {
  /// The company's working time zone. Kuwait has no daylight saving.
  public static let kuwait = TimeZone(identifier: "Asia/Kuwait") ?? TimeZone(secondsFromGMT: 3 * 3600)!

  /// Parses a Supabase timestamp. Fractional seconds beyond milliseconds are
  /// dropped, because not every platform's ISO 8601 parser reads them.
  public static func parseTimestamp(_ text: String) -> Date? {
    var value = text.trimmingCharacters(in: .whitespaces)
    if value.count >= 11, value[value.index(value.startIndex, offsetBy: 10)] == " " {
      // Postgres's own text form: "2026-11-24 10:15:00+00".
      value.replaceSubrange(
        value.index(value.startIndex, offsetBy: 10)...value.index(value.startIndex, offsetBy: 10),
        with: "T")
    }
    // Split off the zone: "Z", "+00:00", "+0000" or "+00".
    var zone = "Z"
    var body = value
    if value.hasSuffix("Z") {
      body = String(value.dropLast())
    } else if let index = value.lastIndex(where: { $0 == "+" || $0 == "-" }),
      value.distance(from: value.startIndex, to: index) > 10
    {
      zone = String(value[index...])
      body = String(value[..<index])
      if zone.count == 3 { zone += ":00" }
      if zone.count == 5 { zone.insert(":", at: zone.index(zone.startIndex, offsetBy: 3)) }
    }
    // Keep at most three fractional digits.
    if let dot = body.firstIndex(of: ".") {
      let fraction = body[body.index(after: dot)...].prefix(3)
      body = String(body[..<dot]) + (fraction.isEmpty ? "" : "." + fraction.padding(toLength: 3, withPad: "0", startingAt: 0))
    }
    let normalised = body + (zone == "Z" ? "Z" : zone)
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFraction.date(from: normalised) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: normalised)
  }

  /// A timestamp to send: UTC, milliseconds.
  public static func timestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
  }
}

/// A calendar day with no time or zone: `2026-11-24`.
public struct LocalDate: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
  public let year: Int
  public let month: Int
  public let day: Int

  public init(year: Int, month: Int, day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }

  public init?(_ text: String) {
    let parts = text.prefix(10).split(separator: "-")
    guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
      (1...12).contains(m), (1...31).contains(d)
    else { return nil }
    self.init(year: y, month: m, day: d)
  }

  /// The day a moment falls on, in a time zone.
  public init(_ date: Date, in zone: TimeZone = MahamDates.kuwait) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let value = LocalDate(text) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a date: \(text)")
    }
    self = value
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }

  public var description: String {
    String(format: "%04d-%02d-%02d", year, month, day)
  }

  public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }

  /// Midnight of this day, in a time zone.
  public func start(in zone: TimeZone = MahamDates.kuwait) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
  }

  /// Whole days from `self` to `other` (negative when `other` is earlier).
  public func days(to other: LocalDate) -> Int {
    let utc = TimeZone(secondsFromGMT: 0)!
    let seconds = other.start(in: utc).timeIntervalSince(start(in: utc))
    return Int((seconds / 86_400).rounded())
  }

  public func adding(days: Int) -> LocalDate {
    let utc = TimeZone(secondsFromGMT: 0)!
    return LocalDate(start(in: utc).addingTimeInterval(Double(days) * 86_400), in: utc)
  }
}
