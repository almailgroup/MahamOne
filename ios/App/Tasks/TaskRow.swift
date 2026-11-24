import MahamKit
import SwiftUI

/// One task in a list: a button that finishes it, its title, where it
/// belongs, when it is due, how urgent it is and who has it. Callers wrap it
/// in `NavigationLink(value: task)` and add `.taskRowActions(task)`.
struct TaskRow: View {
  @Environment(AppModel.self) private var model
  let task: TaskItem
  private let showsProject: Bool
  private let onChange: ((TaskRowChange) -> Void)?

  /// `onChange` is for screens with their own copy of the tasks; screens
  /// that read `model.tasks` leave it out.
  init(task: TaskItem, showsProject: Bool = true, onChange: ((TaskRowChange) -> Void)? = nil) {
    self.task = task
    self.showsProject = showsProject
    self.onChange = onChange
  }

  var body: some View {
    let project = showsProject ? model.tasks.project(task.projectId) : nil
    let people = model.tasks.assignees(of: task)
    HStack(alignment: .center, spacing: 12) {
      TaskStatusButton(task: task, onChange: onChange)

      VStack(alignment: .leading, spacing: 4) {
        Text(task.title)
          .font(.body.weight(.medium))
          .strikethrough(task.isDone)
          .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
          .multilineTextAlignment(.leading)
          .lineLimit(3)

        if project != nil || task.dueAt != nil || task.repeatEvery != nil {
          HStack(spacing: 10) {
            if let due = task.dueAt {
              DueLabel(date: due, done: task.isDone)
            }
            if let project {
              Label(project.name, systemImage: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            if task.repeatEvery != nil {
              Image(systemName: "repeat")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Repeats"))
            }
          }
        }
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 6) {
        PriorityBars(priority: task.priority)
        if !people.isEmpty {
          AvatarStack(people: people, size: 22)
        }
      }
    }
    .padding(.vertical, 2)
    .contentShape(.rect)
  }
}

/// The circle in front of a task: a tap finishes it (or sends it for review
/// when Done is a manager's), another reopens it.
struct TaskStatusButton: View {
  @Environment(AppModel.self) private var model
  let task: TaskItem
  private let onChange: ((TaskRowChange) -> Void)?
  /// Shown at once, before the database answers.
  @State private var pendingDone: Bool?
  @State private var bounce = 0
  @State private var doneTick = 0

  init(task: TaskItem, onChange: ((TaskRowChange) -> Void)? = nil) {
    self.task = task
    self.onChange = onChange
  }

  private var showsDone: Bool { pendingDone ?? task.isDone }

  var body: some View {
    Button(action: toggle) {
      Image(systemName: showsDone ? TaskStatus.done.symbol : task.status.symbol)
        .font(.title2)
        .foregroundStyle(showsDone ? TaskStatus.done.color : task.status.color)
        .contentTransition(.symbolEffect(.replace))
        .symbolEffect(.bounce, value: bounce)
        .frame(minWidth: 36, minHeight: 36)
        .contentShape(.circle)
    }
    .buttonStyle(.borderless)
    .disabled(pendingDone != nil)
    .sensoryFeedback(Haptics.done, trigger: doneTick)
    .accessibilityLabel(showsDone ? Text("Mark as not done") : Text("Mark done"))
    .accessibilityValue(Text(task.status.label))
  }

  private func toggle() {
    let reopening = task.isDone
    pendingDone = !reopening
    bounce += 1
    // The haptic now: the row may leave the list once the change lands.
    if !reopening { doneTick += 1 }
    Task {
      do {
        let updated = try await model.tasks.changeStatus(task, to: reopening ? .todo : .done)
        if !reopening, !updated.isDone {
          model.confirm(String(localized: "Sent for review."))
        }
        onChange?(.updated(updated))
      } catch {
        model.show(error)
      }
      pendingDone = nil
    }
  }
}

extension View {
  /// A task row's swipes and long-press menu: Done on the leading edge;
  /// Tomorrow and Delete on the trailing edge; status, reschedule, share and
  /// delete in the menu.
  func taskRowActions(_ task: TaskItem, onChange: ((TaskRowChange) -> Void)? = nil) -> some View {
    modifier(TaskRowActions(task: task, onChange: onChange))
  }
}

private struct TaskRowActions: ViewModifier {
  @Environment(AppModel.self) private var model
  let task: TaskItem
  let onChange: ((TaskRowChange) -> Void)?
  @State private var confirmingDelete = false
  @State private var doneTick = 0
  @State private var changeTick = 0
  @State private var deleteTick = 0

  func body(content: Content) -> some View {
    content
      .swipeActions(edge: .leading, allowsFullSwipe: true) {
        if task.isDone {
          Button("Reopen", systemImage: "arrow.uturn.backward") { setStatus(.todo) }
            .tint(.gray)
        } else {
          Button("Mark done", systemImage: "checkmark") { setStatus(.done) }
            .tint(.green)
        }
      }
      .swipeActions(edge: .trailing, allowsFullSwipe: true) {
        Button("Tomorrow", systemImage: "sunrise") { reschedule(TaskDuePreset.tomorrow.date()) }
          .tint(.orange)
        Button("Delete", systemImage: "trash") { confirmingDelete = true }
          .tint(.red)
      }
      .contextMenu { menu }
      .confirmationDialog("Delete this task?", isPresented: $confirmingDelete, titleVisibility: .visible) {
        Button("Delete", role: .destructive) { trash() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("It goes to the bin for 30 days. You can restore it on the website.")
      }
      .sensoryFeedback(Haptics.done, trigger: doneTick)
      .sensoryFeedback(Haptics.change, trigger: changeTick)
      .sensoryFeedback(Haptics.warning, trigger: deleteTick)
  }

  @ViewBuilder
  private var menu: some View {
    Section("Status") {
      ForEach(TaskStatus.allCases) { status in
        Button {
          setStatus(status)
        } label: {
          Label(status.label, systemImage: status == task.status ? "checkmark" : status.symbol)
        }
        .disabled(status == task.status)
      }
    }

    Menu("Reschedule", systemImage: "calendar") {
      ForEach(TaskDuePreset.allCases) { preset in
        Button(preset.title, systemImage: preset.symbol) { reschedule(preset.date()) }
      }
      if task.dueAt != nil {
        Divider()
        Button("No date", systemImage: "calendar.badge.minus") { reschedule(nil) }
      }
    }

    if let url = model.taskWebLink(task) {
      ShareLink(item: url, subject: Text(task.title)) {
        Label("Share link", systemImage: "square.and.arrow.up")
      }
    }

    Divider()

    Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
  }

  private func setStatus(_ status: TaskStatus) {
    if status == .done { doneTick += 1 } else { changeTick += 1 }
    Task {
      do {
        let updated = try await model.tasks.changeStatus(task, to: status)
        if status == .done, !updated.isDone {
          model.confirm(String(localized: "Sent for review."))
        }
        onChange?(.updated(updated))
      } catch {
        model.show(error)
      }
    }
  }

  private func reschedule(_ date: Date?) {
    changeTick += 1
    Task {
      do {
        let updated = try await model.tasks.reschedule(task, to: date)
        onChange?(.updated(updated))
        if let due = updated.dueAt {
          model.confirm(String(localized: "Moved to \(due.relativeDue)."))
        } else {
          model.confirm(String(localized: "Due date cleared."))
        }
      } catch {
        model.show(error)
      }
    }
  }

  private func trash() {
    deleteTick += 1
    Task {
      do {
        try await model.tasks.trash(task)
        onChange?(.removed(task))
        model.confirm(String(localized: "Task deleted."))
      } catch {
        model.show(error)
      }
    }
  }
}
