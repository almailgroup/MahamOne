import MahamKit
import UserNotifications

/// A local notification when one of your tasks is due, with Mark Done and
/// Snooze on it. Made on the iPhone from your tasks, so nothing is sent
/// anywhere; at most 50 are waiting at once (iOS keeps 64).
enum Reminders {
  static let category = "task-due"
  static let doneAction = "task-done"
  static let snoozeAction = "task-snooze"
  private static let prefix = "task-"

  /// Asked once, after the first sign-in.
  @discardableResult
  static func requestPermission() async -> Bool {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral: return true
    case .denied: return false
    default:
      return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
  }

  static func registerCategories() {
    let done = UNNotificationAction(
      identifier: doneAction, title: String(localized: "Mark Done"),
      options: [.authenticationRequired], icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
    let snooze = UNNotificationAction(
      identifier: snoozeAction, title: String(localized: "Remind Me in an Hour"),
      options: [], icon: UNNotificationActionIcon(systemImageName: "clock.arrow.circlepath"))
    let category = UNNotificationCategory(
      identifier: category, actions: [done, snooze], intentIdentifiers: [],
      options: [.hiddenPreviewsShowTitle])
    UNUserNotificationCenter.current().setNotificationCategories([category])
  }

  static func schedule(_ tasks: [TaskItem]) async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
    await removeAll()
    let now = Date()
    let due = tasks
      .compactMap { task in task.dueAt.map { (task, $0) } }
      .filter { !$0.0.isDone && $0.1 > now }
      .sorted { $0.1 < $1.1 }
      .prefix(50)
    for (task, date) in due {
      try? await center.add(request(for: task.id, title: task.title, at: date))
    }
  }

  /// Again in an hour (the Snooze button).
  static func snooze(taskId: String, title: String) async {
    let request = request(for: taskId, title: title, at: Date().addingTimeInterval(3600))
    try? await UNUserNotificationCenter.current().add(request)
  }

  static func removeAll() async {
    let center = UNUserNotificationCenter.current()
    let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
    center.removePendingNotificationRequests(withIdentifiers: ours)
  }

  private static func request(for taskId: String, title: String, at date: Date) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = String(localized: "Task due")
    content.body = title
    content.sound = .default
    content.categoryIdentifier = category
    content.threadIdentifier = "tasks"
    content.targetContentIdentifier = taskId
    content.userInfo = ["link": DeepLink.task(taskId).url.absoluteString, "taskId": taskId, "title": title]
    let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    return UNNotificationRequest(identifier: prefix + taskId, content: content, trigger: trigger)
  }
}
