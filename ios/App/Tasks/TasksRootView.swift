import MahamKit
import SwiftUI

/// The Maham Tasks tab: today's work at the top (what is late, what is due,
/// what was finished), then what comes next, then the projects. It shows
/// the copy kept on the iPhone at once and refreshes underneath.
struct TasksRootView: View {
  @Environment(AppModel.self) private var model
  @State private var path = NavigationPath()
  @State private var showingNewTask = false
  @State private var filter: HomeFilter?
  @State private var showingDoneToday = false
  @State private var scrollTick = 0

  var body: some View {
    NavigationStack(path: $path) {
      content
        .navigationTitle("Maham Tasks")
        .taskDestinations()
    }
    .sheet(isPresented: $showingNewTask) {
      TaskEditorView()
    }
    .onChange(of: model.pendingLink, initial: true) { _, link in
      follow(link)
    }
  }

  @ViewBuilder
  private var content: some View {
    if model.tasks.notInTasks {
      NotInTasksView()
    } else if !model.tasks.loadedOnce && model.tasks.myTasks.isEmpty {
      ProgressView()
        .controlSize(.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mahamScreen()
    } else {
      home(model.tasks.plan)
        .toolbar { toolbar }
    }
  }

  // MARK: The list

  private func home(_ plan: DayPlan) -> some View {
    ScrollViewReader { proxy in
      List {
        metrics(plan)
          .id(HomeAnchor.top)
          .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)

        sections(plan)

        projectsSection
      }
      .mahamScreen()
      .refreshable { await model.tasks.refresh() }
      .animation(.smooth, value: model.tasks.myTasks)
      .onChange(of: scrollTick) { _, _ in
        withAnimation(.smooth) { proxy.scrollTo(HomeAnchor.top, anchor: .top) }
      }
    }
  }

  @ViewBuilder
  private func sections(_ plan: DayPlan) -> some View {
    switch filter {
    case .some(.overdue):
      taskSection("Overdue", tasks: plan.overdue, empty: "Nothing is late.", clearable: true)
    case .some(.today):
      taskSection("Due today", tasks: plan.today, empty: "Nothing due today.", clearable: true)
    case .some(.doneToday):
      taskSection("Done today", tasks: plan.doneToday, empty: "Nothing finished yet today.", clearable: true)
    case .none:
      taskSection("Today", tasks: plan.focus, empty: "Nothing due today.", clearable: false)
      if !plan.upcoming.isEmpty {
        taskSection("Upcoming", tasks: plan.upcoming, empty: nil, clearable: false)
      }
      if !plan.someday.isEmpty {
        taskSection("Someday", tasks: plan.someday, empty: nil, clearable: false)
      }
      if !plan.doneToday.isEmpty {
        doneTodaySection(plan.doneToday)
      }
    }
  }

  private func taskSection(
    _ title: LocalizedStringKey, tasks: [TaskItem], empty: LocalizedStringKey?, clearable: Bool
  ) -> some View {
    Section {
      if tasks.isEmpty, let empty {
        Label(empty, systemImage: "checkmark.seal")
          .foregroundStyle(.secondary)
          .glassRow()
      }
      ForEach(tasks) { task in
        row(task)
      }
    } header: {
      HStack(spacing: 6) {
        Text(title)
        if !tasks.isEmpty {
          Text(tasks.count.formatted())
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        Spacer()
        if clearable {
          Button("Show all") {
            withAnimation(.smooth) { filter = nil }
          }
          .font(.subheadline)
        }
      }
    }
  }

  /// Finished today, folded away until asked for.
  private func doneTodaySection(_ done: [TaskItem]) -> some View {
    Section {
      if showingDoneToday {
        ForEach(done) { task in
          row(task)
        }
      }
    } header: {
      Button {
        withAnimation(.smooth) { showingDoneToday.toggle() }
      } label: {
        HStack(spacing: 6) {
          Text("Done today")
          Text(done.count.formatted())
            .monospacedDigit()
            .foregroundStyle(.secondary)
          Spacer()
          Image(systemName: showingDoneToday ? "chevron.down" : "chevron.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityValue(showingDoneToday ? Text("Shown") : Text("Hidden"))
    }
  }

  private func row(_ task: TaskItem) -> some View {
    NavigationLink(value: task) {
      TaskRow(task: task)
    }
    .taskRowActions(task)
    .glassRow()
  }

  private var projectsSection: some View {
    var open: [String: Int] = [:]
    for task in model.tasks.myTasks where !task.isDone {
      if let id = task.projectId { open[id, default: 0] += 1 }
    }
    return Section {
      NavigationLink(value: TasksRoute.general) {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text("General")
            Text("Tasks that aren't in a project")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } icon: {
          Image(systemName: "tray.full")
        }
      }
      .glassRow()

      ForEach(model.tasks.projects) { project in
        NavigationLink(value: project) {
          LabeledContent {
            if let count = open[project.id] {
              Text(count.formatted())
                .monospacedDigit()
                .accessibilityLabel(Text("\(count) open"))
            }
          } label: {
            Label(project.name, systemImage: "folder")
          }
        }
        .glassRow()
      }
    } header: {
      Text("Projects")
    }
  }

  // MARK: The numbers

  @Environment(\.dynamicTypeSize) private var typeSize

  private func metrics(_ plan: DayPlan) -> some View {
    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
    return GlassEffectContainer(spacing: 12) {
      layout {
        tile(.overdue, title: "Overdue", count: plan.overdue.count, symbol: "exclamationmark.circle", tint: .red)
        tile(.today, title: "Today", count: plan.today.count, symbol: "sun.max", tint: .blue)
        tile(.doneToday, title: "Done today", count: plan.doneToday.count, symbol: "checkmark.circle", tint: .green)
      }
    }
  }

  private func tile(
    _ kind: HomeFilter, title: LocalizedStringKey, count: Int, symbol: String, tint: Color
  ) -> some View {
    let selected = filter == kind
    return Button {
      withAnimation(.smooth) {
        filter = selected ? nil : kind
        if kind == .doneToday { showingDoneToday = true }
      }
      scrollTick += 1
    } label: {
      MetricTile(title: title, value: count.formatted(), symbol: symbol, tint: tint)
        .overlay {
          if selected {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
              .strokeBorder(tint, lineWidth: 2)
          }
        }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityHint(Text("Shows only these tasks"))
    .sensoryFeedback(Haptics.pick, trigger: selected)
  }

  // MARK: The toolbar

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Menu("More", systemImage: "ellipsis") {
        Button("My tasks", systemImage: "person.crop.circle") {
          path.append(TasksRoute.myTasks)
        }
        Button("General", systemImage: "tray.full") {
          path.append(TasksRoute.general)
        }
        if let url = model.services?.config.tasksWebURL {
          Divider()
          Link(destination: url) {
            Label("Open Maham Tasks on the web", systemImage: "safari")
          }
        }
      }
    }
    ToolbarSpacer(.fixed, placement: .topBarTrailing)
    ToolbarItem(placement: .topBarTrailing) {
      Button("New task", systemImage: "plus") { showingNewTask = true }
        .buttonStyle(.glassProminent)
    }
  }

  // MARK: Links

  /// A widget, a reminder, Spotlight or Siri asked for something here.
  private func follow(_ link: DeepLink?) {
    guard let link else { return }
    switch link {
    case .today:
      model.pendingLink = nil
      path = NavigationPath()
      withAnimation(.smooth) { filter = nil }
      scrollTick += 1
    case .newTask:
      model.pendingLink = nil
      showingNewTask = true
    case .task(let id):
      model.pendingLink = nil
      Task { await open(taskId: id) }
    case .project(let id):
      model.pendingLink = nil
      Task { await open(projectId: id) }
    default:
      // Another tab's.
      break
    }
  }

  private func open(taskId: String) async {
    do {
      guard let task = try await model.tasks.task(taskId) else {
        model.show(MahamError.permission(String(localized: "That task was deleted, or it isn't shared with you.")))
        return
      }
      var fresh = NavigationPath()
      fresh.append(task)
      path = fresh
    } catch {
      model.show(error)
    }
  }

  private func open(projectId: String) async {
    if model.tasks.project(projectId) == nil {
      await model.tasks.refresh()
    }
    guard let project = model.tasks.project(projectId) else {
      model.show(MahamError.permission(String(localized: "That project was archived, or you're not in it.")))
      return
    }
    var fresh = NavigationPath()
    fresh.append(project)
    path = fresh
  }
}

private enum HomeFilter {
  case overdue, today, doneToday
}

private enum HomeAnchor: Hashable {
  case top
}

/// Signed in to Maham One, but not (yet) in Maham Tasks.
private struct NotInTasksView: View {
  @Environment(AppModel.self) private var model
  @State private var checking = false

  var body: some View {
    VStack(spacing: 20) {
      EmptyState(
        title: "You're not in Maham Tasks yet",
        symbol: "person.crop.circle.badge.questionmark",
        message:
          "Your Maham One account isn't part of Maham Tasks. An admin can invite you on tasks.mahamone.com, and your tasks will show here."
      )
      .frame(maxHeight: 380)

      GlassEffectContainer(spacing: 12) {
        HStack(spacing: 12) {
          Button {
            check()
          } label: {
            if checking {
              ProgressView()
            } else {
              Label("Check again", systemImage: "arrow.clockwise")
            }
          }
          .buttonStyle(.glassProminent)
          .disabled(checking)

          if let url = model.services?.config.tasksWebURL {
            Link(destination: url) {
              Label("Open the website", systemImage: "safari")
            }
            .buttonStyle(.glass)
          }
        }
        .controlSize(.large)
      }
    }
    .padding(.horizontal, 20)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .mahamScreen()
  }

  private func check() {
    checking = true
    Task {
      await model.tasks.refresh()
      checking = false
    }
  }
}
