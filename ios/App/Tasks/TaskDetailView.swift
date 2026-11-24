import MahamKit
import SwiftUI
import UIKit

/// One task, everything about it: its status and priority (changed in
/// place), when it is due, where it belongs, who has it, its steps and its
/// comments, and what can be done with it.
struct TaskDetailView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var task: TaskItem
  @State private var comments: [TaskComment] = []
  @State private var steps: [ChecklistItem] = []
  @State private var loaded = false
  /// Deleted, or no longer shared with you.
  @State private var missing = false
  @State private var working = false
  @State private var focusing = false
  @State private var showingEditor = false
  @State private var showingReschedule = false
  @State private var showingCalendar = false
  @State private var confirmingDelete = false
  @State private var doneTick = 0
  @State private var changeTick = 0
  @State private var deleteTick = 0

  init(task: TaskItem) {
    _task = State(initialValue: task)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if missing {
          NoticeBanner(
            text: "This task was deleted, or it isn't shared with you any more.", symbol: "trash",
            tint: .orange)
        }
        header
        actions
        if let text = task.description, !text.isEmpty {
          GlassSection("Description", symbol: "text.alignleft") {
            Text(text)
              .font(.body)
              .textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        people
        TaskChecklistSection(taskId: task.id, steps: $steps, loaded: loaded)
        TaskCommentsSection(taskId: task.id, comments: $comments, loaded: loaded)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(maxWidth: 760)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
    .mahamScreen()
    .navigationTitle(task.title)
    .toolbarTitleDisplayMode(.inline)
    .toolbar { toolbar }
    .task(id: task.id) { await load() }
    .onAppear { focusing = FocusSession.activeTaskId == task.id }
    .onChange(of: model.tasks.myTasks.first(where: { $0.id == task.id })) { _, stored in
      // A change made elsewhere (a swipe on another screen, a refresh).
      if let stored, stored != task { task = stored }
    }
    .userActivity(ActivityType.task, isActive: !missing) { activity in
      activity.describe(task: task, config: model.services?.config)
    }
    .sheet(isPresented: $showingEditor) {
      TaskEditorView(editing: task, onSaved: { saved in task = saved })
    }
    .sheet(isPresented: $showingReschedule) {
      TaskRescheduleSheet(current: task.dueAt) { date in reschedule(date) }
    }
    .sheet(isPresented: $showingCalendar) {
      TaskCalendarEditor(
        title: task.title, start: task.dueAt ?? TaskDates.nextHour(after: Date()),
        notes: task.description, url: model.taskWebLink(task)
      ) { saved in
        showingCalendar = false
        if saved { model.confirm(String(localized: "Added to your calendar.")) }
      }
      .ignoresSafeArea()
    }
    .confirmationDialog("Delete this task?", isPresented: $confirmingDelete, titleVisibility: .visible) {
      Button("Delete", role: .destructive) { trash() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("It goes to the bin for 30 days. You can restore it on the website.")
    }
    .sensoryFeedback(Haptics.done, trigger: doneTick)
    .sensoryFeedback(Haptics.pick, trigger: changeTick)
    .sensoryFeedback(Haptics.warning, trigger: deleteTick)
  }

  // MARK: The parts

  private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        statusMenu
        priorityMenu
        Spacer(minLength: 0)
      }

      Text(task.title)
        .font(.title2.weight(.bold))
        .strikethrough(task.isDone)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 10) {
        Button {
          showingReschedule = true
        } label: {
          if let due = task.dueAt {
            DueLabel(date: due, done: task.isDone)
          } else {
            Label("Add a due date", systemImage: "calendar.badge.plus")
              .font(.caption.weight(.medium))
          }
        }
        .buttonStyle(.plain)
        .disabled(working || missing)
        .accessibilityHint(Text("Changes the due date"))

        if let project = model.tasks.project(task.projectId) {
          NavigationLink(value: project) {
            Label(project.name, systemImage: "folder")
              .font(.subheadline.weight(.medium))
          }
        } else if task.projectId == nil {
          Label("General", systemImage: "tray.full")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        if let unit = task.repeatEvery {
          Label {
            TaskRepeatText(unit: unit, interval: task.repeatInterval)
          } icon: {
            Image(systemName: "repeat")
          }
          .font(.subheadline)
          .foregroundStyle(.secondary)
        }
      }
    }
    .glassCard()
  }

  private var statusMenu: some View {
    Menu {
      ForEach(TaskStatus.allCases) { status in
        Button {
          changeStatus(status)
        } label: {
          if status == task.status {
            Label(status.label, systemImage: "checkmark")
          } else {
            Label(status.label, systemImage: status.symbol)
          }
        }
      }
    } label: {
      HStack(spacing: 4) {
        StatusBadge(status: task.status)
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
      }
    }
    .disabled(working || missing)
    .accessibilityLabel(Text("Status: \(Text(task.status.label))"))
    .accessibilityHint(Text("Changes the status"))
  }

  private var priorityMenu: some View {
    Menu {
      ForEach(TaskPriority.allCases) { priority in
        Button {
          setPriority(priority)
        } label: {
          if priority == task.priority {
            Label(priority.label, systemImage: "checkmark")
          } else {
            Text(priority.label)
          }
        }
      }
    } label: {
      HStack(spacing: 6) {
        PriorityBars(priority: task.priority)
        Text(task.priority.label)
          .font(.caption.weight(.semibold))
          .foregroundStyle(task.priority.color)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(task.priority.color.opacity(0.14), in: .capsule)
    }
    .disabled(working || missing)
    .accessibilityLabel(Text("Priority: \(Text(task.priority.label))"))
    .accessibilityHint(Text("Changes the priority"))
  }

  private var actions: some View {
    GlassEffectContainer(spacing: 12) {
      VStack(spacing: 12) {
        completeButton
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 12) { secondaryButtons }
          VStack(spacing: 12) { secondaryButtons }
        }
      }
      .controlSize(.large)
    }
    .disabled(missing)
  }

  @ViewBuilder
  private var completeButton: some View {
    if task.isDone {
      Button {
        changeStatus(.todo)
      } label: {
        Label("Reopen", systemImage: "arrow.uturn.backward")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.glass)
      .disabled(working)
    } else if task.status == .inReview && !model.tasks.canManage {
      Label("Waiting for a manager's review", systemImage: "hourglass")
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .capsule)
    } else {
      Button {
        changeStatus(.done)
      } label: {
        Label("Complete", systemImage: "checkmark.circle")
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.glassProminent)
      .tint(.green)
      .disabled(working)
    }
  }

  @ViewBuilder
  private var secondaryButtons: some View {
    Button(action: toggleFocus) {
      if focusing {
        Label("Stop focus", systemImage: "stop.circle")
          .frame(maxWidth: .infinity)
      } else {
        Label("Start focus", systemImage: "timer")
          .frame(maxWidth: .infinity)
      }
    }
    .buttonStyle(.glass)

    Button {
      showingCalendar = true
    } label: {
      Label("Add to Calendar", systemImage: "calendar.badge.plus")
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.glass)

    if let url = model.taskWebLink(task) {
      ShareLink(item: url, subject: Text(task.title)) {
        Label("Share", systemImage: "square.and.arrow.up")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.glass)
    }
  }

  @ViewBuilder
  private var people: some View {
    let assignees = model.tasks.assignees(of: task)
    GlassSection("Assigned to", symbol: "person.2") {
      if assignees.isEmpty {
        if task.assigneeIds.isEmpty {
          Text("No one yet.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else {
          Text("\(task.assigneeIds.count) people")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      } else {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(assignees) { person in
            HStack(spacing: 12) {
              AvatarView(profile: person, size: 32)
              VStack(alignment: .leading, spacing: 1) {
                Text(person.displayName)
                  .font(.subheadline.weight(.medium))
                if let job = person.jobTitle, !job.isEmpty {
                  Text(job)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }
            .accessibilityElement(children: .combine)
          }
        }
      }
    }
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Button("Edit", systemImage: "pencil") { showingEditor = true }
        .disabled(missing)
    }
    ToolbarItem(placement: .topBarTrailing) {
      Menu("More", systemImage: "ellipsis") {
        Button("Change due date", systemImage: "calendar") { showingReschedule = true }
        if let url = model.taskWebLink(task) {
          Button("Copy link", systemImage: "link") {
            UIPasteboard.general.url = url
            model.confirm(String(localized: "Link copied."))
          }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
      }
      .disabled(missing)
    }
  }

  // MARK: Loading

  private func load() async {
    let id = task.id
    let store = model.tasks
    let repo = model.services?.tasks
    async let fetchedTask: TaskItem? = Self.latest(id, repo: repo, store: store)
    async let fetchedComments: [TaskComment] = store.comments(id)
    async let fetchedSteps: [ChecklistItem] = store.checklist(id)
    do {
      let (found, foundComments, foundSteps) = try await (fetchedTask, fetchedComments, fetchedSteps)
      if let found {
        task = found
        missing = false
      } else {
        missing = true
      }
      comments = foundComments
      steps = foundSteps
    } catch {
      // Leaving the screen cancels the load; offline keeps what is shown.
      if !Task.isCancelled, (error as? MahamError) != .offline { model.show(error) }
    }
    loaded = true
  }

  /// The task as the database has it now, not the copy kept on the iPhone.
  private static func latest(_ id: String, repo: TasksRepository?, store: TasksStore) async throws
    -> TaskItem?
  {
    if let repo { return try await repo.task(id: id) }
    return try await store.task(id)
  }

  // MARK: Changing

  private func changeStatus(_ status: TaskStatus) {
    guard status != task.status, !working else { return }
    working = true
    Task {
      defer { working = false }
      do {
        let updated = try await model.tasks.changeStatus(task, to: status)
        task = updated
        if updated.isDone {
          doneTick += 1
        } else {
          changeTick += 1
        }
        if status == .done, !updated.isDone {
          model.confirm(String(localized: "Sent for review."))
        }
      } catch {
        model.show(error)
      }
    }
  }

  private func setPriority(_ priority: TaskPriority) {
    guard priority != task.priority, !working else { return }
    var draft = TaskDraft(task)
    draft.priority = priority
    working = true
    Task {
      defer { working = false }
      do {
        task = try await model.tasks.update(task.id, with: draft)
        changeTick += 1
      } catch {
        model.show(error)
      }
    }
  }

  private func reschedule(_ date: Date?) {
    guard !working else { return }
    working = true
    Task {
      defer { working = false }
      do {
        task = try await model.tasks.reschedule(task, to: date)
        changeTick += 1
      } catch {
        model.show(error)
      }
    }
  }

  private func toggleFocus() {
    if focusing {
      FocusSession.stop()
      focusing = false
    } else {
      FocusSession.start(task)
      focusing = true
    }
    changeTick += 1
  }

  private func trash() {
    guard !working else { return }
    working = true
    deleteTick += 1
    Task {
      defer { working = false }
      do {
        try await model.tasks.trash(task)
        if FocusSession.activeTaskId == task.id { FocusSession.stop() }
        model.confirm(String(localized: "Task deleted."))
        dismiss()
      } catch {
        model.show(error)
      }
    }
  }
}
