import MahamKit
import SwiftUI
import UIKit

/// A project's tasks on a board of four columns, one per status, or as a
/// list grouped the same way. Cards are dragged between columns, as on the
/// website.
struct ProjectBoardView: View {
  private let project: TasksProject

  init(project: TasksProject) {
    self.project = project
  }

  var body: some View {
    TaskBoardScreen(scope: .project(project))
  }
}

/// General: the tasks that belong to no project, on the same board.
struct GeneralTasksView: View {
  init() {}

  var body: some View {
    TaskBoardScreen(scope: .general)
  }
}

/// Which tasks a board shows.
enum TaskBoardScope: Hashable {
  case project(TasksProject)
  case general

  var projectId: String? {
    switch self {
    case .project(let project): project.id
    case .general: nil
    }
  }
}

private enum BoardLayout: String {
  case board, list
}

private struct TaskBoardScreen: View {
  @Environment(AppModel.self) private var model
  let scope: TaskBoardScope
  @State private var tasks: [TaskItem] = []
  @State private var loaded = false
  @State private var showingNewTask = false
  @State private var targeted: TaskStatus?
  @State private var dropTick = 0
  @AppStorage("tasks.boardLayout") private var layout: BoardLayout = .board

  var body: some View {
    Group {
      if !loaded && tasks.isEmpty {
        ProgressView()
          .controlSize(.large)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if layout == .board {
        board
      } else {
        list
      }
    }
    .mahamScreen()
    .navigationTitle(title)
    .toolbarTitleDisplayMode(.inline)
    .toolbar { toolbar }
    .task { await load() }
    .refreshable {
      await Haptics.refresh()
      await load()
    }
    .onChange(of: model.tasks.myTasks) { _, mine in merge(mine) }
    .sheet(isPresented: $showingNewTask) {
      TaskEditorView(projectId: scope.projectId, onSaved: { saved in apply(.updated(saved)) })
    }
    .haptic(.selection, trigger: dropTick)
    .haptic(.selection, trigger: layout)
  }

  private var title: Text {
    switch scope {
    case .project(let project): Text(project.name)
    case .general: Text("General")
    }
  }

  private func column(_ status: TaskStatus) -> [TaskItem] {
    tasks.filter { $0.status == status }.sorted { $0.position < $1.position }
  }

  // MARK: The board

  private var board: some View {
    ScrollView(.horizontal) {
      GlassEffectContainer(spacing: 16) {
        HStack(alignment: .top, spacing: 14) {
          ForEach(TaskStatus.allCases) { status in
            TaskBoardColumn(
              status: status, tasks: column(status), isTargeted: targeted == status,
              onChange: apply, onMove: { task, target in _ = move(task, to: target) }
            )
            .containerRelativeFrame(.horizontal) { length, _ in
              // Four across on a wide iPad; one and a bit on an iPhone.
              let wide: CGFloat = 1082
              let gaps: CGFloat = 42
              if length >= wide { return (length - gaps) / 4 }
              return min(length * 0.86, 340)
            }
            .dropDestination(
              for: String.self,
              action: { (ids: [String], _: CGPoint) -> Bool in
                drop(ids, on: status)
              },
              isTargeted: { (inside: Bool) in
                if inside {
                  targeted = status
                } else if targeted == status {
                  targeted = nil
                }
              })
          }
        }
        .scrollTargetLayout()
        .padding(.vertical, 8)
      }
    }
    .scrollTargetBehavior(.viewAligned)
    .contentMargins(.horizontal, 16, for: .scrollContent)
    .scrollIndicators(.hidden)
  }

  // MARK: The list

  private var list: some View {
    List {
      ForEach(TaskStatus.allCases) { status in
        let items = column(status)
        Section {
          if items.isEmpty {
            Text("Nothing here")
              .foregroundStyle(.secondary)
              .glassRow()
          }
          ForEach(items) { task in
            NavigationLink(value: task) {
              TaskRow(task: task, showsProject: false, onChange: apply)
            }
            .taskRowActions(task, onChange: apply)
            .glassRow()
          }
        } header: {
          HStack(spacing: 6) {
            Label(status.label, systemImage: status.symbol)
              .foregroundStyle(status.color)
            Text(items.count.formatted())
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  // MARK: The toolbar

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      if layout == .board {
        Button("Show as list", systemImage: "list.bullet") {
          withAnimation(.smooth) { layout = .list }
        }
      } else {
        Button("Show as board", systemImage: "rectangle.split.3x1") {
          withAnimation(.smooth) { layout = .board }
        }
      }
    }
    ToolbarSpacer(.fixed, placement: .topBarTrailing)
    ToolbarItem(placement: .topBarTrailing) {
      Button("New task", systemImage: "plus") { showingNewTask = true }
        .buttonStyle(.glassProminent)
    }
  }

  // MARK: Loading

  private func load() async {
    if !loaded && tasks.isEmpty {
      // Your own tasks here are on the iPhone already: show them at once.
      tasks = model.tasks.myTasks.filter { $0.projectId == scope.projectId }
    }
    do {
      switch scope {
      case .project(let project):
        tasks = try await model.tasks.projectTasks(project.id)
      case .general:
        tasks = try await model.tasks.generalTasks()
      }
    } catch {
      if !Task.isCancelled, (error as? MahamError) != .offline { model.show(error) }
    }
    loaded = true
  }

  /// Your tasks changed somewhere else (a detail, a swipe): the same here.
  private func merge(_ mine: [TaskItem]) {
    for stored in mine {
      guard let index = tasks.firstIndex(where: { $0.id == stored.id }), tasks[index] != stored else { continue }
      if stored.projectId == scope.projectId {
        tasks[index] = stored
      } else {
        tasks.remove(at: index)
      }
    }
  }

  private func apply(_ change: TaskRowChange) {
    withAnimation(.smooth) {
      switch change {
      case .updated(let task):
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
          if task.projectId == scope.projectId {
            tasks[index] = task
          } else {
            tasks.remove(at: index)
          }
        } else if task.projectId == scope.projectId {
          tasks.append(task)
        }
      case .removed(let task):
        tasks.removeAll { $0.id == task.id }
      }
    }
  }

  // MARK: Moving

  private func drop(_ ids: [String], on status: TaskStatus) -> Bool {
    targeted = nil
    guard let id = ids.first, let task = tasks.first(where: { $0.id == id }) else { return false }
    return move(task, to: status)
  }

  /// To the end of another column: on screen at once, put back if the
  /// database refuses.
  private func move(_ task: TaskItem, to status: TaskStatus) -> Bool {
    guard task.status != status else { return false }
    // The database enforces this too; refusing here keeps the card from
    // jumping into Done and snapping back.
    if !model.tasks.canManage {
      if status == .done {
        model.show(
          MahamError.permission(
            String(localized: "Only a manager or admin can mark a task done. Move it to In Review instead.")))
        return false
      }
      if task.isDone {
        model.show(
          MahamError.permission(String(localized: "Only a manager or admin can reopen a completed task.")))
        return false
      }
    }
    guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return false }
    let last = tasks.filter { $0.status == status && $0.id != task.id }.map(\.position).max() ?? 0
    let position = last + TasksRepository.positionStep
    let before = tasks
    withAnimation(.smooth) {
      tasks[index].status = status
      tasks[index].position = position
    }
    dropTick += 1
    Task {
      do {
        let moved = try await model.tasks.move(task, to: status, position: position)
        apply(.updated(moved))
      } catch {
        withAnimation(.smooth) { tasks = before }
        model.show(error)
      }
    }
    return true
  }
}

/// One status's column: its colour, its count, its cards.
private struct TaskBoardColumn: View {
  @Environment(AppModel.self) private var model
  let status: TaskStatus
  let tasks: [TaskItem]
  let isTargeted: Bool
  let onChange: (TaskRowChange) -> Void
  let onMove: (TaskItem, TaskStatus) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      ScrollView {
        LazyVStack(spacing: 10) {
          ForEach(tasks) { task in
            card(task)
          }
          if tasks.isEmpty {
            Text("Nothing here")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 28)
          }
        }
        .padding(.bottom, 8)
      }
      .scrollIndicators(.hidden)
    }
    .padding(12)
    .frame(maxHeight: .infinity, alignment: .top)
    .glassEffect(
      Glass.regular.tint(status.color.opacity(isTargeted ? 0.3 : 0.1)),
      in: .rect(cornerRadius: 28, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .strokeBorder(status.color.opacity(isTargeted ? 0.9 : 0), lineWidth: 2)
    }
    .animation(.smooth(duration: 0.2), value: isTargeted)
  }

  private var header: some View {
    HStack(spacing: 8) {
      Image(systemName: status.symbol)
        .font(.headline)
        .foregroundStyle(status.color)
      Text(status.label)
        .font(.headline)
      Spacer(minLength: 4)
      Text(tasks.count.formatted())
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(status.color.opacity(0.18), in: .capsule)
    }
    .padding(.horizontal, 4)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }

  private func card(_ task: TaskItem) -> some View {
    let people = model.tasks.assignees(of: task)
    return NavigationLink(value: task) {
      TaskBoardCard(task: task, people: people)
    }
    .buttonStyle(.plain)
    .draggable(task.id) {
      TaskBoardCard(task: task, people: people)
        .frame(width: 260)
    }
    .taskRowActions(task, onChange: onChange)
    .accessibilityActions {
      ForEach(TaskStatus.allCases.filter { $0 != task.status }) { target in
        Button {
          onMove(task, target)
        } label: {
          Text("Move to \(Text(target.label))")
        }
      }
    }
  }
}

/// A task on the board: title, priority, due date, who has it.
struct TaskBoardCard: View {
  let task: TaskItem
  let people: [TasksProfile]

  init(task: TaskItem, people: [TasksProfile]) {
    self.task = task
    self.people = people
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 8) {
        Text(task.title)
          .font(.subheadline.weight(.semibold))
          .strikethrough(task.isDone)
          .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
          .multilineTextAlignment(.leading)
          .lineLimit(4)
        Spacer(minLength: 0)
        PriorityBars(priority: task.priority)
      }
      if task.dueAt != nil || !people.isEmpty {
        HStack(spacing: 8) {
          if let due = task.dueAt {
            DueLabel(date: due, done: task.isDone)
          }
          Spacer(minLength: 0)
          if !people.isEmpty {
            AvatarStack(people: people, size: 22)
          }
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(uiColor: .secondarySystemGroupedBackground).opacity(0.92),
      in: .rect(cornerRadius: 18, style: .continuous)
    )
    .contentShape(.rect(cornerRadius: 18, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}
