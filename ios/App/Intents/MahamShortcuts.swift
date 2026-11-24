import AppIntents

/// What Siri, Spotlight and the Shortcuts app offer without any setting up.
struct MahamShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: AddTaskIntent(),
      phrases: [
        "Add a task in \(.applicationName)",
        "Add a task to \(.applicationName)",
        "New \(.applicationName) task",
      ],
      shortTitle: "Add a task",
      systemImageName: "plus.circle")
    AppShortcut(
      intent: DueTodayIntent(),
      phrases: [
        "What's due today in \(.applicationName)",
        "What's due in \(.applicationName)",
        "What are my tasks today in \(.applicationName)",
      ],
      shortTitle: "Due today",
      systemImageName: "checklist")
    AppShortcut(
      intent: CompleteTaskEntityIntent(),
      phrases: [
        "Complete a task in \(.applicationName)",
        "Mark a task done in \(.applicationName)",
      ],
      shortTitle: "Complete a task",
      systemImageName: "checkmark.circle")
    AppShortcut(
      intent: OpenTodayIntent(),
      phrases: [
        "Open today in \(.applicationName)",
        "Show my day in \(.applicationName)",
      ],
      shortTitle: "Open today",
      systemImageName: "sun.max")
  }
}
