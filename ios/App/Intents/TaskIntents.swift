import AppIntents
import Foundation
import MahamKit
import SwiftUI

// Siri and Shortcuts in the app: add a task, finish one, hear what's due,
// open one. They run in the app's process, on the same model the screens
// use, so a change shows everywhere at once (and reaches the widgets).

/// The app's model, started and signed in, for an intent. Throws the words
/// Siri says when it isn't.
@MainActor
enum IntentAccess {
  static func signedInModel() async throws -> AppModel {
    let model = AppModel.shared
    await model.ensureStarted()
    switch model.phase {
    case .ready, .locked:
      break
    case .notConfigured:
      throw MahamIntentError.notConfigured
    case .secondStep:
      throw MahamIntentError.needsSecondStep
    default:
      throw MahamIntentError.notSignedIn
    }
    if model.tasks.me == nil { await model.tasks.refresh() }
    if model.tasks.notInTasks { throw MahamIntentError.notInTasks }
    return model
  }
}

// MARK: Adding

struct AddTaskIntent: AppIntent {
  static var title: LocalizedStringResource { "Add a task" }

  static var description: IntentDescription {
    IntentDescription("Adds a task for you in Maham Tasks, with a due date if you give one.")
  }

  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

  @Parameter(title: "Title", requestValueDialog: IntentDialog("What's the task?"))
  var taskTitle: String

  @Parameter(title: "Due date")
  var due: Date?

  static var parameterSummary: some ParameterSummary {
    Summary("Add \(\.$taskTitle) to Maham Tasks") {
      \.$due
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<TaskEntity> & ProvidesDialog {
    let model = try await IntentAccess.signedInModel()
    guard let me = model.tasks.me else { throw MahamIntentError.unreachable }
    let title = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let draft = TaskDraft(title: title, dueAt: due, assigneeIds: [me.id])
    if let problem = draft.problem { throw MahamIntentError.failed(problem) }
    do {
      let task = try await model.tasks.create(draft)
      return .result(
        value: TaskEntity(task),
        dialog: IntentDialog("Added “\(task.title)” to Maham Tasks."))
    } catch {
      throw MahamIntentError(error)
    }
  }
}

// MARK: Finishing

struct CompleteTaskEntityIntent: AppIntent {
  static var title: LocalizedStringResource { "Complete a task" }

  static var description: IntentDescription {
    IntentDescription("Marks one of your tasks done in Maham Tasks, or sends it for review when a manager marks it done.")
  }

  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

  @Parameter(title: "Task", requestValueDialog: IntentDialog("Which task?"))
  var task: TaskEntity

  static var parameterSummary: some ParameterSummary {
    Summary("Complete \(\.$task)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let model = try await IntentAccess.signedInModel()
    do {
      guard let item = try await model.tasks.task(task.id) else { throw MahamIntentError.taskNotFound }
      if item.isDone {
        return .result(dialog: IntentDialog("“\(item.title)” is already done."))
      }
      let updated = try await model.tasks.complete(item)
      if updated.isDone {
        return .result(dialog: IntentDialog("Marked “\(updated.title)” done."))
      }
      return .result(dialog: IntentDialog("Sent “\(updated.title)” for review. A manager marks it done."))
    } catch {
      throw MahamIntentError(error)
    }
  }
}

// MARK: Today

struct DueTodayIntent: AppIntent {
  static var title: LocalizedStringResource { "What's due today" }

  static var description: IntentDescription {
    IntentDescription("Tells you which of your tasks are overdue or due today.")
  }

  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
    let model = try await IntentAccess.signedInModel()
    await model.tasks.refresh()
    let focus = model.tasks.plan.focus
    return .result(
      dialog: Self.dialog(for: focus),
      view: DueTodaySnippet(tasks: Array(focus.prefix(6)), total: focus.count))
  }

  /// "You have 3 tasks for today: A, B and C."
  private static func dialog(for focus: [TaskItem]) -> IntentDialog {
    let names = focus.prefix(3).map(\.title).formatted(.list(type: .and))
    switch focus.count {
    case 0:
      return IntentDialog("Nothing is due today. You're all clear.")
    case 1:
      return IntentDialog("You have one task for today: \(names).")
    case 2, 3:
      return IntentDialog("You have \(focus.count) tasks for today: \(names).")
    default:
      return IntentDialog("You have \(focus.count) tasks for today, starting with \(names).")
    }
  }
}

/// What Siri shows under its answer: the tasks, late ones in red.
private struct DueTodaySnippet: View {
  let tasks: [TaskItem]
  let total: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if tasks.isEmpty {
        Label("All clear for today", systemImage: "checkmark.seal.fill")
          .font(.headline)
          .foregroundStyle(Color.green)
      } else {
        ForEach(tasks) { task in
          HStack(spacing: 10) {
            Image(systemName: task.isOverdue() ? "exclamationmark.circle.fill" : "circle")
              .foregroundStyle(task.isOverdue() ? Color.red : Color.secondary)
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
              Text(task.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
              if let due = task.dueAt {
                DueLabel(date: due)
              }
            }
            Spacer(minLength: 8)
            PriorityBars(priority: task.priority)
          }
        }
        if total > tasks.count {
          Text("\(total - tasks.count) more in Maham Tasks")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: Opening

struct OpenTaskIntent: OpenIntent {
  static var title: LocalizedStringResource { "Open task" }

  static var description: IntentDescription {
    IntentDescription("Opens one of your tasks in Maham One.")
  }

  @Parameter(title: "Task")
  var target: TaskEntity

  @MainActor
  func perform() async throws -> some IntentResult {
    // The model is what answers Navigator; make sure it exists.
    _ = AppModel.shared
    Navigator.open(.task(target.id))
    return .result()
  }
}
