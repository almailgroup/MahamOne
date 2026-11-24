import Foundation

/// The last answers the app had, kept on the iPhone so a screen opens at once
/// and still shows something offline. The app keeps it in the App Group's
/// container, which its widgets read too.
public struct DiskCache: Sendable {
  public let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  public func save<Value: Encodable>(_ value: Value, as key: String) {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let data = try MahamJSON.encoder().encode(value)
      try data.write(to: url(key), options: [.atomic])
    } catch {
      // A cache that couldn't be written is only a slower next start.
    }
  }

  public func load<Value: Decodable>(_ type: Value.Type, as key: String) -> Value? {
    guard let data = try? Data(contentsOf: url(key)) else { return nil }
    return try? MahamJSON.decoder().decode(type, from: data)
  }

  public func remove(_ key: String) {
    try? FileManager.default.removeItem(at: url(key))
  }

  /// Everything, on signing out: nothing of the account stays behind.
  public func clear() {
    try? FileManager.default.removeItem(at: directory)
  }

  private func url(_ key: String) -> URL {
    let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
    return directory.appendingPathComponent(String(safe) + ".json")
  }
}

/// What the widgets show: written by the app after each refresh, and by the
/// widgets themselves when they fetch.
public struct TodaySnapshot: Codable, Sendable, Equatable {
  public struct Item: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var dueAt: Date?
    public var priority: TaskPriority
    public var overdue: Bool

    public init(_ task: TaskItem, now: Date) {
      id = task.id
      title = task.title
      dueAt = task.dueAt
      priority = task.priority
      overdue = task.isOverdue(now: now)
    }
  }

  public var updatedAt: Date
  public var items: [Item]
  public var overdueCount: Int
  public var todayCount: Int
  public var doneTodayCount: Int
  public var signedIn: Bool

  public init(plan: DayPlan, now: Date = Date(), signedIn: Bool = true) {
    updatedAt = now
    items = plan.focus.prefix(8).map { Item($0, now: now) }
    overdueCount = plan.overdue.count
    todayCount = plan.today.count
    doneTodayCount = plan.doneToday.count
    self.signedIn = signedIn
  }

  public static let signedOut = TodaySnapshot(
    plan: DayPlan(tasks: []), now: Date(timeIntervalSince1970: 0), signedIn: false)

  public static let cacheKey = "today-snapshot"
}
