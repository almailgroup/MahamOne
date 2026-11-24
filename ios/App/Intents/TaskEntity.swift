import AppIntents
import Foundation
import MahamKit

/// One of your Maham Tasks tasks, as Siri, Shortcuts and Spotlight see it.
struct TaskEntity: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    TypeDisplayRepresentation(name: "Task")
  }

  static var defaultQuery: TaskEntityQuery { TaskEntityQuery() }

  let id: String
  let title: String
  let dueAt: Date?

  init(_ task: TaskItem) {
    id = task.id
    title = task.title
    dueAt = task.dueAt
  }

  var displayRepresentation: DisplayRepresentation {
    if let dueAt {
      DisplayRepresentation(
        title: "\(title)",
        subtitle: "Due \(dueAt.formatted(date: .abbreviated, time: .shortened))",
        image: DisplayRepresentation.Image(systemName: "checklist"))
    } else {
      DisplayRepresentation(
        title: "\(title)",
        image: DisplayRepresentation.Image(systemName: "checklist"))
    }
  }
}

/// Finds your tasks: by id (yours first, then the database), by words in the
/// title, and today's for suggestions.
struct TaskEntityQuery: EntityStringQuery {
  @MainActor
  func entities(for identifiers: [String]) async throws -> [TaskEntity] {
    let model = try await IntentAccess.signedInModel()
    var found: [TaskEntity] = []
    for id in identifiers {
      do {
        if let task = try await model.tasks.task(id) { found.append(TaskEntity(task)) }
      } catch {
        throw MahamIntentError(error)
      }
    }
    return found
  }

  @MainActor
  func entities(matching string: String) async throws -> [TaskEntity] {
    let model = try await IntentAccess.signedInModel()
    let term = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else { return try await suggestedEntities() }
    // Yours on this iPhone first (they work offline), then the database's.
    var tasks = model.tasks.myTasks.filter { !$0.isDone && $0.title.localizedStandardContains(term) }
    if let services = AppServices.shared, let remote = try? await services.tasks.search(term) {
      let known = Set(tasks.map(\.id))
      tasks += remote.filter { !$0.isDone && !known.contains($0.id) }
    }
    return tasks.prefix(30).map { TaskEntity($0) }
  }

  @MainActor
  func suggestedEntities() async throws -> [TaskEntity] {
    let model = try await IntentAccess.signedInModel()
    let plan = model.tasks.plan
    let tasks = plan.focus.isEmpty ? Array((plan.upcoming + plan.someday).prefix(10)) : plan.focus
    return tasks.map { TaskEntity($0) }
  }
}
