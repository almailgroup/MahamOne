import MahamKit
import SwiftUI

// What the Maham Tasks screens share: how a row tells its screen what it
// changed, the quick due dates, the task's web link, and the status change
// every menu goes through.

/// What a row's buttons did to a task, for screens that keep their own copy
/// of the tasks (a project's board) instead of reading `TasksStore.myTasks`.
enum TaskRowChange {
  case updated(TaskItem)
  case removed(TaskItem)
}

/// The due dates people pick most, one tap each, as on the website: five
/// o'clock today, tomorrow morning, the start of next week (a Kuwaiti week
/// starts on Sunday).
enum TaskDuePreset: CaseIterable, Identifiable {
  case thisEvening, tomorrow, nextWeek

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .thisEvening: "This evening"
    case .tomorrow: "Tomorrow"
    case .nextWeek: "Next week"
    }
  }

  var symbol: String {
    switch self {
    case .thisEvening: "moon"
    case .tomorrow: "sunrise"
    case .nextWeek: "calendar.badge.clock"
    }
  }

  /// The moment, on this iPhone's clock.
  func date(from now: Date = Date()) -> Date {
    switch self {
    case .thisEvening:
      let evening = TaskDates.at(hour: 17, on: now)
      return evening > now ? evening : TaskDates.nextHour(after: now)
    case .tomorrow:
      return TaskDates.at(hour: 9, on: TaskDates.day(after: now, by: 1))
    case .nextWeek:
      // Sunday is weekday 1. From Friday or Saturday that is the coming
      // Sunday; from Sunday itself, the one after.
      let weekday = TaskDates.calendar.component(.weekday, from: now)
      let ahead = (8 - weekday) % 7
      return TaskDates.at(hour: 9, on: TaskDates.day(after: now, by: ahead == 0 ? 7 : ahead))
    }
  }
}

/// Date arithmetic for due dates, in the Gregorian calendar and this
/// iPhone's time zone (the reader may use another calendar for display).
enum TaskDates {
  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.current
    return calendar
  }

  static func at(hour: Int, on day: Date) -> Date {
    calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
  }

  static func day(after date: Date, by days: Int) -> Date {
    calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
  }

  /// The start of the next hour: 14:20 → 15:00.
  static func nextHour(after date: Date) -> Date {
    calendar.dateInterval(of: .hour, for: date)?.end ?? date.addingTimeInterval(3600)
  }

  /// A due date when one is switched on: five o'clock today, or tomorrow's
  /// once today's has passed.
  static func defaultDue(from now: Date = Date()) -> Date {
    let today = at(hour: 17, on: now)
    return today > now ? today : at(hour: 17, on: day(after: now, by: 1))
  }
}

extension AppModel {
  /// The task's page on the Maham Tasks website: `…/tasks?task=<id>`.
  func taskWebLink(_ task: TaskItem) -> URL? {
    guard let base = services?.config.tasksWebURL,
      var parts = URLComponents(url: base.appending(path: "tasks"), resolvingAgainstBaseURL: false)
    else { return nil }
    parts.queryItems = [URLQueryItem(name: "task", value: task.id)]
    return parts.url
  }
}

extension TasksStore {
  /// A status picked from a menu, under the website's rules: Done goes
  /// through `complete` (In Review when Done is a manager's to give), and
  /// only a manager or an admin reopens a finished task.
  @discardableResult
  func changeStatus(_ task: TaskItem, to status: TaskStatus) async throws -> TaskItem {
    guard status != task.status else { return task }
    if task.isDone, !canManage {
      throw MahamError.permission(String(localized: "Only a manager or admin can reopen a completed task."))
    }
    if status == .done { return try await complete(task) }
    return try await setStatus(task, to: status)
  }
}

/// "Every day", "Every 3 weeks": how often a task comes back.
struct TaskRepeatText: View {
  let unit: RepeatUnit
  let interval: Int

  var body: some View {
    if interval <= 1 {
      switch unit {
      case .day: Text("Repeats daily")
      case .week: Text("Repeats weekly")
      case .month: Text("Repeats monthly")
      case .year: Text("Repeats yearly")
      }
    } else {
      switch unit {
      case .day: Text("Repeats every \(interval) days")
      case .week: Text("Repeats every \(interval) weeks")
      case .month: Text("Repeats every \(interval) months")
      case .year: Text("Repeats every \(interval) years")
      }
    }
  }
}
