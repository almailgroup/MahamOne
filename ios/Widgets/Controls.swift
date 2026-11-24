import AppIntents
import SwiftUI
import WidgetKit

/// Control Center, the Lock Screen and the Action button: a new task in one
/// press. The intent opens the app, which shows the task editor.
struct NewTaskControl: ControlWidget {
  static let kind = "com.almailgroup.mahamone.control.new-task"

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: Self.kind) {
      ControlWidgetButton(action: OpenNewTaskIntent()) {
        Label("New task", systemImage: "plus.circle")
      }
    }
    .displayName("New task")
    .description("Starts a new task in Maham Tasks.")
  }
}

/// Today's tasks in one press.
struct TodayControl: ControlWidget {
  static let kind = "com.almailgroup.mahamone.control.today"

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: Self.kind) {
      ControlWidgetButton(action: OpenTodayIntent()) {
        Label("Today", systemImage: "checklist")
      }
    }
    .displayName("Today")
    .description("Opens your tasks for today in Maham Tasks.")
  }
}
