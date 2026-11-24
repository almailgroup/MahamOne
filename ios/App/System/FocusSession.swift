import ActivityKit
import Foundation
import MahamKit
import Observation

/// Focusing on one task: a Live Activity on the Lock Screen and in the
/// Dynamic Island with a timer running since you started (the widget
/// extension draws it: FocusLiveActivity). One focus at a time; starting
/// another ends the first.
@MainActor
enum FocusSession {
  /// The task being focused on, if any. Views that read it are redrawn
  /// after `start` and `stop`.
  static var activeTaskId: String? {
    _ = changes.count
    return live().first?.attributes.taskId
  }

  static func start(_ task: TaskItem) {
    stop()
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      AppModel.shared.toast = Toast(
        kind: .error,
        message: String(localized: "Turn on Live Activities for Maham One in Settings to focus on a task."))
      return
    }
    let attributes = FocusActivityAttributes(taskId: task.id, title: task.title)
    let state = FocusActivityAttributes.ContentState(
      started: Date(), projectName: AppModel.shared.tasks.project(task.projectId)?.name)
    do {
      _ = try Activity<FocusActivityAttributes>.request(
        attributes: attributes, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
    } catch {
      AppModel.shared.toast = Toast(
        kind: .error, message: String(localized: "The focus couldn't start. Try again in a moment."))
    }
    changes.count += 1
  }

  static func stop() {
    let ids = live().map(\.id)
    guard !ids.isEmpty else { return }
    ending.formUnion(ids)
    changes.count += 1
    Task.detached {
      for activity in Activity<FocusActivityAttributes>.activities where ids.contains(activity.id) {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }
  }

  // MARK: Keeping track

  /// Activities asked to end that iOS may not have ended yet.
  private static var ending: Set<String> = []
  private static let changes = FocusChanges()

  private static func live() -> [Activity<FocusActivityAttributes>] {
    let all = Activity<FocusActivityAttributes>.activities
    let present = Set(all.map(\.id))
    ending.formIntersection(present)
    return all.filter { activity in
      (activity.activityState == .active || activity.activityState == .stale)
        && !ending.contains(activity.id)
    }
  }
}

/// Bumped on every start and stop, so SwiftUI reads `activeTaskId` again.
@MainActor
@Observable
private final class FocusChanges {
  var count = 0
}
