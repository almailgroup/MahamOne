import ActivityKit
import Foundation

/// The Live Activity of a task you're focusing on: on the Lock Screen and in
/// the Dynamic Island, with a timer running since you started. The app
/// starts and ends it (FocusSession); the widget extension draws it.
struct FocusActivityAttributes: ActivityAttributes, Sendable {
  struct ContentState: Codable, Hashable, Sendable {
    /// When the focus started: the timer counts up from here.
    var started: Date
    var projectName: String?
  }

  var taskId: String
  var title: String
}
