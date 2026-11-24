import AppIntents
import Foundation
import MahamKit
import WidgetKit

/// The widgets' checkmark: Done, or In Review when Done is a manager's to
/// give (the database's review gate refuses the assignee's own Done), then
/// the widgets again. Runs in the widget extension, with the session the app
/// shares with it.
struct CompleteTaskIntent: AppIntent {
  static var title: LocalizedStringResource { "Complete task" }

  static var description: IntentDescription {
    IntentDescription("Marks one of your tasks done in Maham Tasks, or sends it for review.")
  }

  /// Only the widgets' buttons run it; Shortcuts has CompleteTaskEntityIntent.
  static var isDiscoverable: Bool { false }

  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

  @Parameter(title: "Task ID")
  var taskId: String

  init() {}

  init(taskId: String) {
    self.taskId = taskId
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    var problem: MahamIntentError?
    do {
      try await Self.complete(taskId)
    } catch {
      problem = MahamIntentError(error)
    }
    // Whatever happened, the widgets show what the database now holds.
    await TodayLoader.load()
    WidgetCenter.shared.reloadAllTimelines()
    if let problem { throw problem }
    return .result()
  }

  /// The same rule as the app's TasksStore.complete.
  private static func complete(_ id: String) async throws {
    guard let services = AppServices.shared else { throw MahamIntentError.notConfigured }
    guard await services.auth.currentSession != nil else { throw MahamIntentError.notSignedIn }
    let repo = services.tasks
    guard let task = try await repo.task(id: id) else { throw MahamIntentError.taskNotFound }
    guard !task.isDone else { return }
    do {
      _ = try await repo.setStatus(id, to: .done)
    } catch MahamError.permission {
      guard task.status != .inReview else { throw MahamError.permission("A manager marks this done.") }
      _ = try await repo.setStatus(id, to: .inReview)
    } catch MahamError.server(_, let code, _) where code == "42501" || code == "P0001" {
      _ = try await repo.setStatus(id, to: .inReview)
    }
  }
}
