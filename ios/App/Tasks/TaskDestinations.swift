import MahamKit
import SwiftUI

/// Places in Maham Tasks that are not a task or a project.
enum TasksRoute: Hashable {
  /// Tasks that belong to no project.
  case general
  /// Everything assigned to you, by status.
  case myTasks
}

extension View {
  /// Where a Maham Tasks link goes: a task to its detail, a project to its
  /// board, General and My tasks to their lists. Every tab's NavigationStack
  /// applies this once, on its root view.
  func taskDestinations() -> some View {
    self
      .navigationDestination(for: TaskItem.self) { task in
        TaskDetailView(task: task)
      }
      .navigationDestination(for: TasksProject.self) { project in
        ProjectBoardView(project: project)
      }
      .navigationDestination(for: TasksRoute.self) { route in
        switch route {
        case .general: GeneralTasksView()
        case .myTasks: MyTasksView()
        }
      }
  }
}
