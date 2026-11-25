import MahamKit
import SwiftUI

/// Everything assigned to you, by status, soonest first, with a filter by
/// title.
struct MyTasksView: View {
  @Environment(AppModel.self) private var model
  @State private var query = ""

  init() {}

  var body: some View {
    let tasks = filtered
    List {
      ForEach(TaskStatus.allCases) { status in
        let group = tasks.filter { $0.status == status }
        if !group.isEmpty {
          Section {
            ForEach(group) { task in
              NavigationLink(value: task) {
                TaskRow(task: task)
              }
              .taskRowActions(task)
              .glassRow()
            }
          } header: {
            HStack(spacing: 6) {
              Label(status.label, systemImage: status.symbol)
                .foregroundStyle(status.color)
              Text(group.count.formatted())
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .overlay {
      if tasks.isEmpty {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          EmptyState(
            title: "No tasks yet", symbol: "checklist",
            message: "Tasks assigned to you show here.")
        } else {
          ContentUnavailableView.search(text: query)
        }
      }
    }
    .mahamScreen()
    .navigationTitle("My tasks")
    .searchable(text: $query, prompt: Text("Filter by title"))
    .refreshable {
      await Haptics.refresh()
      await model.tasks.refresh()
    }
    .animation(.smooth, value: model.tasks.myTasks)
  }

  private var filtered: [TaskItem] {
    let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let all = model.tasks.myTasks.sorted {
      ($0.dueAt ?? .distantFuture, $0.title) < ($1.dueAt ?? .distantFuture, $1.title)
    }
    guard !words.isEmpty else { return all }
    return all.filter { $0.title.localizedStandardContains(words) }
  }
}
