import MahamKit
import Observation
import SwiftUI

/// The Maham Tasks department: your tasks, the projects, the team and your
/// notifications, kept on the iPhone between launches and refreshed from the
/// database. Every change goes through `TasksRepository`, under the same
/// rules as the website.
@MainActor
@Observable
final class TasksStore {
  private(set) var me: TasksProfile?
  /// Signed in to Maham One but not in Maham Tasks (no profile, no invite).
  private(set) var notInTasks = false
  private(set) var myTasks: [TaskItem] = []
  private(set) var projects: [TasksProject] = []
  private(set) var team: [TasksProfile] = []
  private(set) var notifications: [TaskNotification] = []
  private(set) var isLoading = false
  private(set) var loadedOnce = false

  /// Errors the shell shows as a toast.
  var onError: (@MainActor (Error) -> Void)?

  private let services: AppServices?

  init(services: AppServices?) {
    self.services = services
    loadCache()
  }

  private var repo: TasksRepository? { services?.tasks }

  // MARK: What screens read

  var plan: DayPlan { DayPlan(tasks: myTasks) }
  var unreadCount: Int { notifications.filter(\.isUnread).count }
  var canManage: Bool { me?.role.canManage ?? false }

  func profile(_ id: String?) -> TasksProfile? {
    guard let id else { return nil }
    return team.first { $0.id == id }
  }

  func project(_ id: String?) -> TasksProject? {
    guard let id else { return nil }
    return projects.first { $0.id == id }
  }

  func assignees(of task: TaskItem) -> [TasksProfile] {
    task.assigneeIds.compactMap { profile($0) }
  }

  // MARK: Loading

  func refresh() async {
    guard let repo else { return }
    isLoading = true
    defer {
      isLoading = false
      loadedOnce = true
    }
    do {
      let me = try await repo.me()
      self.me = me
      notInTasks = false
      async let tasks = repo.myTasks(userId: me.id)
      async let projects = repo.projects()
      async let team = repo.team()
      async let notifications = repo.notifications()
      (myTasks, self.projects, self.team, self.notifications) = try await (tasks, projects, team, notifications)
      saveCache()
      SystemSync.tasksChanged(myTasks, plan: plan, projects: self.projects)
    } catch MahamError.notInTasks {
      notInTasks = true
    } catch MahamError.offline {
      // The cached copy stays on screen.
    } catch {
      onError?(error)
    }
  }

  func reset() {
    me = nil
    notInTasks = false
    myTasks = []
    projects = []
    team = []
    notifications = []
    loadedOnce = false
  }

  // MARK: Reading on demand

  func projectTasks(_ projectId: String) async throws -> [TaskItem] {
    guard let repo else { return [] }
    return try await repo.tasks(projectId: projectId)
  }

  func generalTasks() async throws -> [TaskItem] {
    guard let repo else { return [] }
    return try await repo.generalTasks()
  }

  func task(_ id: String) async throws -> TaskItem? {
    if let local = myTasks.first(where: { $0.id == id }) { return local }
    return try await repo?.task(id: id)
  }

  func search(_ term: String) async throws -> [TaskItem] {
    try await repo?.search(term) ?? []
  }

  func comments(_ taskId: String) async throws -> [TaskComment] {
    try await repo?.comments(taskId: taskId) ?? []
  }

  func checklist(_ taskId: String) async throws -> [ChecklistItem] {
    try await repo?.checklist(taskId: taskId) ?? []
  }

  // MARK: Changing

  @discardableResult
  func create(_ draft: TaskDraft) async throws -> TaskItem {
    guard let repo, let me else { throw MahamError.notInTasks }
    let task = try await repo.createTask(draft, by: me.id)
    if task.assigneeIds.contains(me.id) { upsert(task) }
    changed()
    return task
  }

  @discardableResult
  func update(_ id: String, with draft: TaskDraft) async throws -> TaskItem {
    guard let repo else { throw MahamError.notSignedIn }
    let task = try await repo.updateTask(id, with: draft)
    upsert(task)
    changed()
    return task
  }

  @discardableResult
  func setStatus(_ task: TaskItem, to status: TaskStatus) async throws -> TaskItem {
    guard let repo else { throw MahamError.notSignedIn }
    let updated = try await repo.setStatus(task.id, to: status)
    upsert(updated)
    changed()
    return updated
  }

  /// Done, or In Review when Done is a manager's to give (the database's
  /// review gate refuses the assignee's own Done).
  @discardableResult
  func complete(_ task: TaskItem) async throws -> TaskItem {
    do {
      return try await setStatus(task, to: .done)
    } catch MahamError.permission {
      guard task.status != .inReview else { throw MahamError.permission("A manager marks this done.") }
      return try await setStatus(task, to: .inReview)
    } catch MahamError.server(_, let code, _) where code == "42501" || code == "P0001" {
      return try await setStatus(task, to: .inReview)
    }
  }

  @discardableResult
  func move(_ task: TaskItem, to status: TaskStatus, position: Double) async throws -> TaskItem {
    guard let repo else { throw MahamError.notSignedIn }
    let moved = try await repo.move(task.id, to: status, position: position)
    upsert(moved)
    changed()
    return moved
  }

  @discardableResult
  func reschedule(_ task: TaskItem, to date: Date?) async throws -> TaskItem {
    guard let repo else { throw MahamError.notSignedIn }
    let updated = try await repo.reschedule(task.id, dueAt: date)
    upsert(updated)
    changed()
    return updated
  }

  func trash(_ task: TaskItem) async throws {
    guard let repo else { throw MahamError.notSignedIn }
    try await repo.trash(task.id)
    myTasks.removeAll { $0.id == task.id }
    changed()
  }

  @discardableResult
  func addComment(_ taskId: String, _ text: String) async throws -> TaskComment {
    guard let repo, let me else { throw MahamError.notInTasks }
    return try await repo.addComment(taskId: taskId, content: text, by: me.id)
  }

  @discardableResult
  func addStep(_ taskId: String, _ text: String) async throws -> ChecklistItem {
    guard let repo, let me else { throw MahamError.notInTasks }
    return try await repo.addStep(taskId: taskId, content: text, by: me.id)
  }

  @discardableResult
  func setStep(_ item: ChecklistItem, done: Bool) async throws -> ChecklistItem {
    guard let repo else { throw MahamError.notSignedIn }
    return try await repo.setStep(item.id, done: done)
  }

  func markRead(_ notification: TaskNotification) async {
    guard notification.isUnread, let repo else { return }
    if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
      notifications[index].readAt = Date()
    }
    try? await repo.markRead(notification.id)
    SystemSync.badge(unreadCount)
  }

  func markAllRead() async {
    guard let repo, let me else { return }
    for index in notifications.indices where notifications[index].isUnread {
      notifications[index].readAt = Date()
    }
    do { try await repo.markAllRead(userId: me.id) } catch { onError?(error) }
    SystemSync.badge(unreadCount)
  }

  // MARK: Keeping the copy

  private func upsert(_ task: TaskItem) {
    guard let me else { return }
    if let index = myTasks.firstIndex(where: { $0.id == task.id }) {
      if task.assigneeIds.contains(me.id) {
        myTasks[index] = task
      } else {
        myTasks.remove(at: index)
      }
    } else if task.assigneeIds.contains(me.id) {
      myTasks.append(task)
    }
  }

  private func changed() {
    saveCache()
    SystemSync.tasksChanged(myTasks, plan: plan, projects: projects)
  }

  private struct Cached: Codable {
    var me: TasksProfile?
    var myTasks: [TaskItem]
    var projects: [TasksProject]
    var team: [TasksProfile]
    var notifications: [TaskNotification]
  }

  private func saveCache() {
    services?.cache.save(
      Cached(me: me, myTasks: myTasks, projects: projects, team: team, notifications: notifications),
      as: "tasks")
  }

  private func loadCache() {
    guard let cached = services?.cache.load(Cached.self, as: "tasks") else { return }
    me = cached.me
    myTasks = cached.myTasks
    projects = cached.projects
    team = cached.team
    notifications = cached.notifications
  }
}
