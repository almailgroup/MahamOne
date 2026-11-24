import AppIntents
import Foundation

/// Opens the app on a new task: the Control Center control, Shortcuts.
/// It is in the app and the widget extension both, so the system runs it in
/// the app, where AppModel answers Navigator.
struct OpenNewTaskIntent: AppIntent {
  static var title: LocalizedStringResource { "New task" }

  static var description: IntentDescription {
    IntentDescription("Opens Maham One on a new task.")
  }

  static var openAppWhenRun: Bool { true }

  @MainActor
  func perform() async throws -> some IntentResult {
    Navigator.open(.newTask)
    return .result()
  }
}

/// Opens the app on today's tasks: the Control Center control, Siri.
struct OpenTodayIntent: AppIntent {
  static var title: LocalizedStringResource { "Open today" }

  static var description: IntentDescription {
    IntentDescription("Opens Maham One on your tasks for today.")
  }

  static var openAppWhenRun: Bool { true }

  @MainActor
  func perform() async throws -> some IntentResult {
    Navigator.open(.today)
    return .result()
  }
}
