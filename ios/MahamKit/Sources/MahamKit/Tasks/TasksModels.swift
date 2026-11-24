import Foundation

// Maham Tasks' rows (the `tasks` schema of Maham One's database), as the
// website reads them (maham-tasks/src/lib/supabase/database.types.ts).

public enum TaskStatus: String, Codable, CaseIterable, Sendable, Identifiable {
  case todo
  case inProgress = "in_progress"
  case inReview = "in_review"
  case done

  public var id: String { rawValue }

  /// The words the website uses, as string-catalog keys.
  public var title: String {
    switch self {
    case .todo: "To Do"
    case .inProgress: "In Progress"
    case .inReview: "In Review"
    case .done: "Done"
    }
  }

  public var symbol: String {
    switch self {
    case .todo: "circle"
    case .inProgress: "circle.lefthalf.filled"
    case .inReview: "eye.circle"
    case .done: "checkmark.circle.fill"
    }
  }
}

public enum TaskPriority: String, Codable, CaseIterable, Sendable, Identifiable {
  case low, medium, high, urgent

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .low: "Low"
    case .medium: "Medium"
    case .high: "High"
    case .urgent: "Urgent"
    }
  }

  /// Filled bars out of four, as the website draws it.
  public var weight: Int {
    switch self {
    case .low: 1
    case .medium: 2
    case .high: 3
    case .urgent: 4
    }
  }
}

public enum TasksRole: String, Codable, Sendable {
  case admin, manager, member

  public var canManage: Bool { self != .member }
}

public enum RepeatUnit: String, Codable, CaseIterable, Sendable {
  case day, week, month, year
}

public struct TasksProfile: Codable, Identifiable, Hashable, Sendable {
  public let id: String
  public var email: String
  public var fullName: String?
  public var avatarURL: String?
  public var role: TasksRole
  public var jobTitle: String?

  enum CodingKeys: String, CodingKey {
    case id, email, role
    case fullName = "full_name"
    case avatarURL = "avatar_url"
    case jobTitle = "job_title"
  }

  public var displayName: String {
    if let fullName, !fullName.isEmpty { return fullName }
    return email
  }

  /// Up to two letters for an avatar.
  public var initials: String {
    let words = displayName.split(whereSeparator: { $0 == " " || $0 == "@" || $0 == "." })
    return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
  }
}

public struct TasksProject: Codable, Identifiable, Hashable, Sendable {
  public let id: String
  public var name: String
  public var description: String?
  public var archivedAt: Date?
  public var createdAt: Date?

  enum CodingKeys: String, CodingKey {
    case id, name, description
    case archivedAt = "archived_at"
    case createdAt = "created_at"
  }
}

/// A task with the ids of the people it is assigned to.
public struct TaskItem: Codable, Identifiable, Hashable, Sendable {
  public let id: String
  public var projectId: String?
  public var title: String
  public var description: String?
  public var status: TaskStatus
  public var priority: TaskPriority
  public var dueAt: Date?
  public var followUpAt: Date?
  public var followUpNote: String?
  public var position: Double
  public var createdBy: String?
  public var repeatEvery: RepeatUnit?
  public var repeatInterval: Int
  public var createdAt: Date?
  public var updatedAt: Date?
  public var assigneeIds: [String]

  enum CodingKeys: String, CodingKey {
    case id, title, description, status, priority, position
    case projectId = "project_id"
    case dueAt = "due_at"
    case followUpAt = "follow_up_at"
    case followUpNote = "follow_up_note"
    case createdBy = "created_by"
    case repeatEvery = "repeat_every"
    case repeatInterval = "repeat_interval"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case assignees
  }

  private struct Assignment: Codable { let user_id: String }

  public init(
    id: String, projectId: String? = nil, title: String, description: String? = nil,
    status: TaskStatus = .todo, priority: TaskPriority = .medium, dueAt: Date? = nil,
    followUpAt: Date? = nil, followUpNote: String? = nil, position: Double = 0,
    createdBy: String? = nil, repeatEvery: RepeatUnit? = nil, repeatInterval: Int = 1,
    createdAt: Date? = nil, updatedAt: Date? = nil, assigneeIds: [String] = []
  ) {
    self.id = id
    self.projectId = projectId
    self.title = title
    self.description = description
    self.status = status
    self.priority = priority
    self.dueAt = dueAt
    self.followUpAt = followUpAt
    self.followUpNote = followUpNote
    self.position = position
    self.createdBy = createdBy
    self.repeatEvery = repeatEvery
    self.repeatInterval = repeatInterval
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.assigneeIds = assigneeIds
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
    title = try c.decode(String.self, forKey: .title)
    description = try c.decodeIfPresent(String.self, forKey: .description)
    status = (try? c.decode(TaskStatus.self, forKey: .status)) ?? .todo
    priority = (try? c.decode(TaskPriority.self, forKey: .priority)) ?? .medium
    dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
    followUpAt = try c.decodeIfPresent(Date.self, forKey: .followUpAt)
    followUpNote = try c.decodeIfPresent(String.self, forKey: .followUpNote)
    position = (try? c.decode(Double.self, forKey: .position)) ?? 0
    createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy)
    repeatEvery = try? c.decodeIfPresent(RepeatUnit.self, forKey: .repeatEvery)
    repeatInterval = (try? c.decode(Int.self, forKey: .repeatInterval)) ?? 1
    createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    if let assigned = try? c.decodeIfPresent([Assignment].self, forKey: .assignees) {
      assigneeIds = assigned.map(\.user_id)
    } else if let ids = try? c.decodeIfPresent([String].self, forKey: .assignees) {
      assigneeIds = ids
    } else {
      assigneeIds = []
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encodeIfPresent(projectId, forKey: .projectId)
    try c.encode(title, forKey: .title)
    try c.encodeIfPresent(description, forKey: .description)
    try c.encode(status, forKey: .status)
    try c.encode(priority, forKey: .priority)
    try c.encodeIfPresent(dueAt, forKey: .dueAt)
    try c.encodeIfPresent(followUpAt, forKey: .followUpAt)
    try c.encodeIfPresent(followUpNote, forKey: .followUpNote)
    try c.encode(position, forKey: .position)
    try c.encodeIfPresent(createdBy, forKey: .createdBy)
    try c.encodeIfPresent(repeatEvery, forKey: .repeatEvery)
    try c.encode(repeatInterval, forKey: .repeatInterval)
    try c.encodeIfPresent(createdAt, forKey: .createdAt)
    try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    try c.encode(assigneeIds, forKey: .assignees)
  }

  public var isDone: Bool { status == .done }

  /// Not done, and due before now.
  public func isOverdue(now: Date = Date()) -> Bool {
    guard !isDone, let dueAt else { return false }
    return dueAt < now
  }
}

public struct TaskComment: Codable, Identifiable, Hashable, Sendable {
  public let id: String
  public var taskId: String
  public var userId: String?
  public var content: String
  public var createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id, content
    case taskId = "task_id"
    case userId = "user_id"
    case createdAt = "created_at"
  }
}

public struct ChecklistItem: Codable, Identifiable, Hashable, Sendable {
  public let id: String
  public var taskId: String
  public var content: String
  public var done: Bool
  public var position: Double

  enum CodingKeys: String, CodingKey {
    case id, content, done, position
    case taskId = "task_id"
  }
}

public enum NotificationKind: String, Codable, Sendable {
  case taskAssigned = "task_assigned"
  case taskUnassigned = "task_unassigned"
  case taskCommented = "task_commented"
  case taskMentioned = "task_mentioned"
  case taskReviewRequested = "task_review_requested"
  case taskCompleted = "task_completed"
  case directMessage = "direct_message"
  case reminderFailed = "reminder_failed"
  case taskUnblocked = "task_unblocked"
  case other

  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = NotificationKind(rawValue: value) ?? .other
  }

  public var symbol: String {
    switch self {
    case .taskAssigned: "person.crop.circle.badge.plus"
    case .taskUnassigned: "person.crop.circle.badge.minus"
    case .taskCommented: "text.bubble"
    case .taskMentioned: "at"
    case .taskReviewRequested: "eye"
    case .taskCompleted: "checkmark.seal"
    case .directMessage: "paperplane"
    case .reminderFailed: "exclamationmark.triangle"
    case .taskUnblocked: "lock.open"
    case .other: "bell"
    }
  }
}

public struct TaskNotification: Codable, Identifiable, Hashable, Sendable {
  public let id: String
  public var kind: NotificationKind
  public var title: String
  public var body: String?
  public var taskId: String?
  public var projectId: String?
  public var actorId: String?
  public var readAt: Date?
  public var createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id, title, body
    case kind = "type"
    case taskId = "task_id"
    case projectId = "project_id"
    case actorId = "actor_id"
    case readAt = "read_at"
    case createdAt = "created_at"
  }

  public var isUnread: Bool { readAt == nil }
}

/// What a person fills in to make or change a task.
public struct TaskDraft: Sendable, Equatable {
  public var title: String
  public var description: String
  public var status: TaskStatus
  public var priority: TaskPriority
  public var dueAt: Date?
  public var projectId: String?
  public var assigneeIds: [String]
  public var steps: [String]
  public var repeatEvery: RepeatUnit?
  public var repeatInterval: Int

  public init(
    title: String = "", description: String = "", status: TaskStatus = .todo,
    priority: TaskPriority = .medium, dueAt: Date? = nil, projectId: String? = nil,
    assigneeIds: [String] = [], steps: [String] = [], repeatEvery: RepeatUnit? = nil,
    repeatInterval: Int = 1
  ) {
    self.title = title
    self.description = description
    self.status = status
    self.priority = priority
    self.dueAt = dueAt
    self.projectId = projectId
    self.assigneeIds = assigneeIds
    self.steps = steps
    self.repeatEvery = repeatEvery
    self.repeatInterval = repeatInterval
  }

  public init(_ task: TaskItem) {
    self.init(
      title: task.title, description: task.description ?? "", status: task.status,
      priority: task.priority, dueAt: task.dueAt, projectId: task.projectId,
      assigneeIds: task.assigneeIds, repeatEvery: task.repeatEvery,
      repeatInterval: task.repeatInterval)
  }

  /// The website's rules (maham-tasks/src/lib/validation.ts): a title of
  /// 1–200 characters, a description of up to 20,000.
  public var problem: String? {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "Give the task a title." }
    if trimmed.count > 200 { return "Keep the title to 200 characters." }
    if description.count > 20_000 { return "Keep the description to 20,000 characters." }
    if !(1...365).contains(repeatInterval) { return "Repeat every 1 to 365." }
    return nil
  }
}
