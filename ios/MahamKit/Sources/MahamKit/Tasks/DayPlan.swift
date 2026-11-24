import Foundation

/// Your tasks sorted the way the website's Today page asks about them:
/// what is late, what is due today, what comes next, and what has no date.
public struct DayPlan: Sendable, Equatable {
  public var overdue: [TaskItem]
  public var today: [TaskItem]
  public var upcoming: [TaskItem]
  public var someday: [TaskItem]
  public var doneToday: [TaskItem]

  public init(tasks: [TaskItem], now: Date = Date(), zone: TimeZone = MahamDates.kuwait) {
    let day = LocalDate(now, in: zone)
    var overdue: [TaskItem] = []
    var today: [TaskItem] = []
    var upcoming: [TaskItem] = []
    var someday: [TaskItem] = []
    var doneToday: [TaskItem] = []
    for task in tasks {
      if task.isDone {
        if let updated = task.updatedAt, LocalDate(updated, in: zone) == day { doneToday.append(task) }
        continue
      }
      guard let due = task.dueAt else {
        someday.append(task)
        continue
      }
      // Late as soon as its moment has passed, as the website counts it.
      if due < now {
        overdue.append(task)
      } else if LocalDate(due, in: zone) == day {
        today.append(task)
      } else {
        upcoming.append(task)
      }
    }
    let byDue: (TaskItem, TaskItem) -> Bool = {
      ($0.dueAt ?? .distantFuture, $1.priority.weight, $0.title)
        < ($1.dueAt ?? .distantFuture, $0.priority.weight, $1.title)
    }
    self.overdue = overdue.sorted(by: byDue)
    self.today = today.sorted(by: byDue)
    self.upcoming = upcoming.sorted(by: byDue)
    self.someday = someday.sorted { ($1.priority.weight, $0.title) < ($0.priority.weight, $1.title) }
    self.doneToday = doneToday
  }

  /// What still needs doing today: the late work, then today's.
  public var focus: [TaskItem] { overdue + today }

  public var isClear: Bool { overdue.isEmpty && today.isEmpty }
}
