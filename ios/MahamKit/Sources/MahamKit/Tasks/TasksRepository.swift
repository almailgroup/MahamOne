import Foundation

/// Maham Tasks' data, read and written as the website does
/// (maham-tasks/src/lib/data/*.ts), under the same database rules: the review
/// gate, who may edit what, and notifications are all the database's.
public struct TasksRepository: Sendable {
  public let db: DatabaseClient

  /// Gap between neighbours on the board, as the website leaves it.
  public static let positionStep = 1024.0

  /// Tasks with the ids of everyone they're assigned to.
  static let taskColumns = "*,assignees:task_assignments(user_id)"

  public init(db: DatabaseClient) {
    self.db = db
  }

  private var schema: DatabaseSchema { .tasks }

  // MARK: People

  /// Your Maham Tasks profile. Signing in is what accepts an invite
  /// (`tasks.join`), as on the website; without a profile or an invite,
  /// `MahamError.notInTasks`.
  public func me() async throws -> TasksProfile {
    let session = try await db.auth.validSession()
    let id = session.user.id
    if let profile = try await profile(id) { return profile }
    let joined: Bool = (try? await db.rpc("join", schema: schema, NoParams())) ?? false
    if joined, let profile = try await profile(id) { return profile }
    throw MahamError.notInTasks
  }

  private func profile(_ id: String) async throws -> TasksProfile? {
    let rows: [TasksProfile] = try await db.select(
      "profiles", schema: schema, [.select("id,email,full_name,avatar_url,role,job_title"), .eq("id", id)])
    return rows.first
  }

  public func team() async throws -> [TasksProfile] {
    try await db.select(
      "profiles", schema: schema,
      [.select("id,email,full_name,avatar_url,role,job_title"), .order("full_name")])
  }

  // MARK: Projects

  public func projects(includeArchived: Bool = false) async throws -> [TasksProject] {
    var query: [Query] = [.select("id,name,description,archived_at,created_at"), .order("name")]
    if !includeArchived { query.append(.isNull("archived_at")) }
    return try await db.select("projects", schema: schema, query)
  }

  // MARK: Reading tasks

  /// Open and finished tasks assigned to you, not in the bin.
  public func myTasks(userId: String) async throws -> [TaskItem] {
    try await db.selectAll(
      "tasks", schema: schema,
      [
        .select(Self.taskColumns + ",mine:task_assignments!inner()"),
        .eq("mine.user_id", userId),
        .isNull("deleted_at"),
        .order("due_at"),
      ])
  }

  /// Every task of a project you can see, in board order.
  public func tasks(projectId: String) async throws -> [TaskItem] {
    try await db.selectAll(
      "tasks", schema: schema,
      [
        .select(Self.taskColumns), .eq("project_id", projectId), .isNull("deleted_at"),
        .order("position"),
      ])
  }

  /// General tasks: assigned work that belongs to no project.
  public func generalTasks() async throws -> [TaskItem] {
    try await db.selectAll(
      "tasks", schema: schema,
      [.select(Self.taskColumns), .isNull("project_id"), .isNull("deleted_at"), .order("position")])
  }

  public func task(id: String) async throws -> TaskItem? {
    let rows: [TaskItem] = try await db.select(
      "tasks", schema: schema, [.select(Self.taskColumns), .eq("id", id), .isNull("deleted_at")])
    return rows.first
  }

  /// Titles that contain the words, newest first.
  public func search(_ term: String, limit: Int = 30) async throws -> [TaskItem] {
    let words = term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard words.count >= 2 else { return [] }
    let pattern = "*\(words.replacingOccurrences(of: "*", with: ""))*"
    return try await db.select(
      "tasks", schema: schema,
      [
        .select(Self.taskColumns), .ilike("title", pattern), .isNull("deleted_at"),
        .order("updated_at", ascending: false), .limit(limit),
      ])
  }

  // MARK: Writing tasks

  /// After the last task in the column it lands in.
  func nextPosition(projectId: String?, status: TaskStatus) async throws -> Double {
    var query: [Query] = [
      .select("position"), .eq("status", status.rawValue), .isNull("deleted_at"),
      .order("position", ascending: false), .limit(1),
    ]
    query.append(projectId.map { .eq("project_id", $0) } ?? .isNull("project_id"))
    struct Row: Decodable { let position: Double }
    let rows: [Row] = try await db.select("tasks", schema: schema, query)
    return (rows.first?.position ?? 0) + Self.positionStep
  }

  public func createTask(_ draft: TaskDraft, by userId: String) async throws -> TaskItem {
    if let problem = draft.problem { throw MahamError.permission(problem) }
    let position = try await nextPosition(projectId: draft.projectId, status: draft.status)

    struct NewTask: Encodable {
      let project_id: String?
      let title: String
      let description: String?
      let status: TaskStatus
      let priority: TaskPriority
      let due_at: Date?
      let repeat_every: RepeatUnit?
      let repeat_interval: Int
      let position: Double
      let created_by: String

      func encode(to encoder: Encoder) throws {
        // Nulls are sent as nulls (the encoder would otherwise leave them out).
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(project_id, forKey: .project_id)
        try c.encode(title, forKey: .title)
        try c.encode(description, forKey: .description)
        try c.encode(status, forKey: .status)
        try c.encode(priority, forKey: .priority)
        try c.encode(due_at, forKey: .due_at)
        try c.encode(repeat_every, forKey: .repeat_every)
        try c.encode(repeat_interval, forKey: .repeat_interval)
        try c.encode(position, forKey: .position)
        try c.encode(created_by, forKey: .created_by)
      }
      enum Key: String, CodingKey {
        case project_id, title, description, status, priority, due_at, repeat_every,
          repeat_interval, position, created_by
      }
    }

    let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
    let rows: [TaskItem] = try await db.insert(
      "tasks", schema: schema,
      [
        NewTask(
          project_id: draft.projectId, title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
          description: description.isEmpty ? nil : description, status: draft.status,
          priority: draft.priority, due_at: draft.dueAt, repeat_every: draft.repeatEvery,
          repeat_interval: draft.repeatInterval, position: position, created_by: userId)
      ], returning: Self.taskColumns)
    guard var task = rows.first else { throw MahamError.permission("") }

    if !draft.assigneeIds.isEmpty {
      try await db.insert(
        "task_assignments", schema: schema,
        draft.assigneeIds.map { ["task_id": task.id, "user_id": $0] })
      task.assigneeIds = draft.assigneeIds
    }

    let steps = draft.steps
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && $0.count <= 500 }
      .prefix(50)
    if !steps.isEmpty {
      struct Step: Encodable {
        let task_id: String
        let content: String
        let position: Double
        let created_by: String
      }
      try await db.insert(
        "task_checklist_items", schema: schema,
        steps.enumerated().map {
          Step(
            task_id: task.id, content: $0.element, position: Double($0.offset + 1) * Self.positionStep,
            created_by: userId)
        })
    }
    return task
  }

  public func updateTask(_ id: String, with draft: TaskDraft) async throws -> TaskItem {
    if let problem = draft.problem { throw MahamError.permission(problem) }
    struct Change: Encodable {
      let title: String
      let description: String?
      let status: TaskStatus
      let priority: TaskPriority
      let due_at: Date?
      let repeat_every: RepeatUnit?
      let repeat_interval: Int

      func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(title, forKey: .title)
        try c.encode(description, forKey: .description)
        try c.encode(status, forKey: .status)
        try c.encode(priority, forKey: .priority)
        try c.encode(due_at, forKey: .due_at)
        try c.encode(repeat_every, forKey: .repeat_every)
        try c.encode(repeat_interval, forKey: .repeat_interval)
      }
      enum Key: String, CodingKey {
        case title, description, status, priority, due_at, repeat_every, repeat_interval
      }
    }
    let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
    let rows: [TaskItem] = try await db.update(
      "tasks", schema: schema,
      Change(
        title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
        description: description.isEmpty ? nil : description, status: draft.status,
        priority: draft.priority, due_at: draft.dueAt, repeat_every: draft.repeatEvery,
        repeat_interval: draft.repeatInterval),
      where: [.eq("id", id)], returning: Self.taskColumns)
    guard var task = rows.first else {
      throw MahamError.permission("You can't edit this task.")
    }
    try await syncAssignees(task: id, current: task.assigneeIds, wanted: draft.assigneeIds)
    task.assigneeIds = draft.assigneeIds
    return task
  }

  func syncAssignees(task: String, current: [String], wanted: [String]) async throws {
    let toAdd = wanted.filter { !current.contains($0) }
    let toRemove = current.filter { !wanted.contains($0) }
    if !toAdd.isEmpty {
      try await db.insert(
        "task_assignments", schema: schema, toAdd.map { ["task_id": task, "user_id": $0] })
    }
    if !toRemove.isEmpty {
      try await db.delete(
        "task_assignments", schema: schema, where: [.eq("task_id", task), .in("user_id", toRemove)])
    }
  }

  /// A new status. Done waits for a manager or an admin when the task is
  /// someone else's to review: the database refuses, and this says so.
  @discardableResult
  public func setStatus(_ id: String, to status: TaskStatus) async throws -> TaskItem {
    try await change(id, ["status": status.rawValue], refusal: "You can't change this task's status.")
  }

  /// A drop on the board: the column and the place in it.
  @discardableResult
  public func move(_ id: String, to status: TaskStatus, position: Double) async throws -> TaskItem {
    struct Move: Encodable {
      let status: TaskStatus
      let position: Double
    }
    let rows: [TaskItem] = try await db.update(
      "tasks", schema: schema, Move(status: status, position: position), where: [.eq("id", id)],
      returning: Self.taskColumns)
    guard let task = rows.first else { throw MahamError.permission("You can't move this task.") }
    return task
  }

  @discardableResult
  public func reschedule(_ id: String, dueAt: Date?) async throws -> TaskItem {
    struct Due: Encodable {
      let due_at: Date?
      func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(due_at, forKey: .due_at)
      }
      enum Key: String, CodingKey { case due_at }
    }
    let rows: [TaskItem] = try await db.update(
      "tasks", schema: schema, Due(due_at: dueAt), where: [.eq("id", id)],
      returning: Self.taskColumns)
    guard let task = rows.first else { throw MahamError.permission("You can't reschedule this task.") }
    return task
  }

  private func change(_ id: String, _ values: [String: String], refusal: String) async throws -> TaskItem {
    let rows: [TaskItem] = try await db.update(
      "tasks", schema: schema, values, where: [.eq("id", id)], returning: Self.taskColumns)
    guard let task = rows.first else { throw MahamError.permission(refusal) }
    return task
  }

  /// To the bin for thirty days, as on the website (`tasks.trash_task`).
  public func trash(_ id: String) async throws {
    let done: Bool = try await db.rpc("trash_task", schema: schema, ["task": id])
    if !done { throw MahamError.permission("You can't delete this task.") }
  }

  public func restore(_ id: String) async throws {
    let done: Bool = try await db.rpc("restore_task", schema: schema, ["task": id])
    if !done { throw MahamError.permission("This task can't be restored.") }
  }

  // MARK: Comments

  public func comments(taskId: String) async throws -> [TaskComment] {
    try await db.select(
      "comments", schema: schema,
      [.select("id,task_id,user_id,content,created_at"), .eq("task_id", taskId), .order("created_at")])
  }

  @discardableResult
  public func addComment(taskId: String, content: String, by userId: String) async throws
    -> TaskComment
  {
    let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw MahamError.permission("Write something first.") }
    guard text.count <= 5000 else { throw MahamError.permission("Keep a comment to 5000 characters.") }
    let rows: [TaskComment] = try await db.insert(
      "comments", schema: schema, [["task_id": taskId, "user_id": userId, "content": text]],
      returning: "id,task_id,user_id,content,created_at")
    guard let comment = rows.first else { throw MahamError.permission("") }
    return comment
  }

  // MARK: Steps (the checklist)

  public func checklist(taskId: String) async throws -> [ChecklistItem] {
    try await db.select(
      "task_checklist_items", schema: schema,
      [.select("id,task_id,content,done,position"), .eq("task_id", taskId), .order("position")])
  }

  @discardableResult
  public func addStep(taskId: String, content: String, by userId: String) async throws
    -> ChecklistItem
  {
    let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.count <= 500 else {
      throw MahamError.permission("A step is 1 to 500 characters.")
    }
    struct Last: Decodable { let position: Double }
    let last: [Last] = try await db.select(
      "task_checklist_items", schema: schema,
      [.select("position"), .eq("task_id", taskId), .order("position", ascending: false), .limit(1)])
    struct Step: Encodable {
      let task_id: String
      let content: String
      let position: Double
      let created_by: String
    }
    let rows: [ChecklistItem] = try await db.insert(
      "task_checklist_items", schema: schema,
      [
        Step(
          task_id: taskId, content: text, position: (last.first?.position ?? 0) + Self.positionStep,
          created_by: userId)
      ], returning: "id,task_id,content,done,position")
    guard let item = rows.first else { throw MahamError.permission("") }
    return item
  }

  @discardableResult
  public func setStep(_ id: String, done: Bool) async throws -> ChecklistItem {
    let rows: [ChecklistItem] = try await db.update(
      "task_checklist_items", schema: schema, ["done": done], where: [.eq("id", id)],
      returning: "id,task_id,content,done,position")
    guard let item = rows.first else { throw MahamError.permission("You can't tick this step.") }
    return item
  }

  // MARK: Notifications

  public func notifications(limit: Int = 50) async throws -> [TaskNotification] {
    try await db.select(
      "notifications", schema: schema,
      [
        .select("id,type,title,body,task_id,project_id,actor_id,read_at,created_at"),
        .order("created_at", ascending: false), .limit(limit),
      ])
  }

  public func markRead(_ id: String) async throws {
    let _: [IdRow] = try await db.update(
      "notifications", schema: schema, ["read_at": MahamDates.timestamp(Date())],
      where: [.eq("id", id), .isNull("read_at")], returning: "id")
  }

  public func markAllRead(userId: String) async throws {
    let _: [IdRow] = try await db.update(
      "notifications", schema: schema, ["read_at": MahamDates.timestamp(Date())],
      where: [.eq("user_id", userId), .isNull("read_at")], returning: "id")
  }
}

struct IdRow: Decodable {
  let id: String
}
