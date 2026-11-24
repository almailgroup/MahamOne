import MahamKit
import SwiftUI

/// A new task, or changes to one: the same fields as the website's task
/// dialog, checked by the same rules (`TaskDraft.problem`) before saving.
struct TaskEditorView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  private let editing: TaskItem?
  private let onSaved: ((TaskItem) -> Void)?
  @State private var draft: TaskDraft
  /// What the form started as, to tell whether there is anything to lose.
  @State private var initial: TaskDraft
  @State private var hasDue: Bool
  @State private var due: Date
  @State private var steps: [EditableStep] = []
  @State private var newStep = ""
  @State private var working = false
  @State private var tried = false
  @State private var prepared = false
  @State private var confirmingDiscard = false
  @State private var failTick = 0
  @State private var pickTick = 0
  @FocusState private var focus: Field?

  private enum Field: Hashable { case title, newStep }

  /// As the website allows.
  private static let stepLimit = 500
  private static let maxSteps = 50

  /// `editing` changes a task; without it the sheet makes one, in
  /// `projectId` when given. `onSaved` hears the saved task.
  init(editing: TaskItem? = nil, projectId: String? = nil, onSaved: ((TaskItem) -> Void)? = nil) {
    self.editing = editing
    self.onSaved = onSaved
    let start: TaskDraft
    if let editing {
      start = TaskDraft(editing)
    } else {
      start = TaskDraft(projectId: projectId)
    }
    _draft = State(initialValue: start)
    _initial = State(initialValue: start)
    _hasDue = State(initialValue: start.dueAt != nil)
    _due = State(initialValue: start.dueAt ?? TaskDates.defaultDue())
  }

  var body: some View {
    NavigationStack {
      Form {
        titleSection
        detailsSection
        dueSection
        projectSection
        assigneesSection
        if editing == nil {
          stepsSection
        }
        repeatSection
      }
      .navigationTitle(editing == nil ? Text("New task") : Text("Edit task"))
      .toolbarTitleDisplayMode(.inline)
      .toolbar { toolbar }
      .interactiveDismissDisabled(hasChanges || working)
      .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
        Button("Discard changes", role: .destructive) { dismiss() }
        Button("Keep editing", role: .cancel) {}
      }
      .sensoryFeedback(Haptics.failed, trigger: failTick)
      .onAppear(perform: prepare)
    }
  }

  // MARK: The form

  private var titleSection: some View {
    Section {
      TextField("Title", text: $draft.title)
        .font(.headline)
        .focused($focus, equals: .title)
        .submitLabel(.done)
      TextField("Description", text: $draft.description, axis: .vertical)
        .lineLimit(3...12)
    } footer: {
      if tried, let message = problem {
        Text(LocalizedStringKey(message))
          .foregroundStyle(.red)
      }
    }
  }

  private var detailsSection: some View {
    Section {
      Picker("Status", selection: $draft.status) {
        ForEach(TaskStatus.allCases) { status in
          Label(status.label, systemImage: status.symbol)
            .tag(status)
        }
      }
      Picker("Priority", selection: $draft.priority) {
        ForEach(TaskPriority.allCases) { priority in
          Text(priority.label)
            .tag(priority)
        }
      }
    }
  }

  private var dueSection: some View {
    Section {
      Toggle(isOn: $hasDue.animation(.smooth)) {
        Label("Due date", systemImage: "calendar")
      }
      if hasDue {
        DatePicker("Due", selection: $due, displayedComponents: [.date, .hourAndMinute])
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(TaskDuePreset.allCases) { preset in
              Button(preset.title) { due = preset.date() }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
          }
          .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
      }
    }
  }

  private var projectSection: some View {
    Section {
      Picker(selection: $draft.projectId) {
        Text("None").tag(String?.none)
        ForEach(projectChoices) { project in
          Text(project.name).tag(Optional(project.id))
        }
      } label: {
        Label("Project", systemImage: "folder")
      }
      .disabled(editing != nil)
    } footer: {
      if editing != nil {
        Text("A task's project is changed on the website.")
      }
    }
  }

  private var assigneesSection: some View {
    Section {
      ForEach(people) { person in
        let chosen = draft.assigneeIds.contains(person.id)
        Button {
          toggleAssignee(person.id)
        } label: {
          HStack(spacing: 12) {
            AvatarView(profile: person, size: 30)
            VStack(alignment: .leading, spacing: 1) {
              if person.id == model.tasks.me?.id {
                Text("\(person.displayName) (you)")
              } else {
                Text(person.displayName)
              }
              if let job = person.jobTitle, !job.isEmpty {
                Text(job)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            .foregroundStyle(Color.primary)
            Spacer(minLength: 8)
            Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
              .font(.title3)
              .foregroundStyle(chosen ? Color.accentColor : Color.secondary)
              .contentTransition(.symbolEffect(.replace))
          }
          .contentShape(.rect)
        }
        .accessibilityAddTraits(chosen ? .isSelected : [])
      }
    } header: {
      Text("Assigned to")
    } footer: {
      if draft.assigneeIds.isEmpty {
        Text("No one is assigned yet.")
      }
    }
    .sensoryFeedback(Haptics.pick, trigger: pickTick)
  }

  private var stepsSection: some View {
    Section {
      ForEach($steps) { $step in
        TextField("Step", text: $step.text, axis: .vertical)
      }
      .onDelete { offsets in steps.remove(atOffsets: offsets) }

      if steps.count < Self.maxSteps {
        HStack(spacing: 8) {
          TextField("Add a step…", text: $newStep)
            .focused($focus, equals: .newStep)
            .submitLabel(.next)
            .onSubmit(addStep)
          Button("Add step", systemImage: "plus.circle.fill", action: addStep)
            .labelStyle(.iconOnly)
            .font(.title3)
            .buttonStyle(.borderless)
            .disabled(newStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    } header: {
      Text("Steps")
    } footer: {
      if steps.contains(where: { $0.text.count > Self.stepLimit }) {
        Text("A step can be at most 500 characters.")
          .foregroundStyle(.red)
      }
    }
  }

  private var repeatSection: some View {
    Section {
      Picker(selection: $draft.repeatEvery) {
        Text("Does not repeat").tag(RepeatUnit?.none)
        Text("Daily").tag(RepeatUnit?.some(.day))
        Text("Weekly").tag(RepeatUnit?.some(.week))
        Text("Monthly").tag(RepeatUnit?.some(.month))
        Text("Yearly").tag(RepeatUnit?.some(.year))
      } label: {
        Label("Repeat", systemImage: "repeat")
      }
      if let unit = draft.repeatEvery {
        Stepper(value: $draft.repeatInterval, in: 1...365) {
          TaskRepeatText(unit: unit, interval: draft.repeatInterval)
        }
      }
    } footer: {
      if draft.repeatEvery != nil {
        Text("Closing it opens the next one, dated from this one.")
      }
    }
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      Button("Cancel", systemImage: "xmark") {
        if hasChanges {
          confirmingDiscard = true
        } else {
          dismiss()
        }
      }
      .disabled(working)
    }
    ToolbarItem(placement: .confirmationAction) {
      if working {
        ProgressView()
      } else {
        Button("Save", systemImage: "checkmark", action: save)
          .buttonStyle(.glassProminent)
      }
    }
  }

  // MARK: What the form says

  private var people: [TasksProfile] {
    let team = model.tasks.team
    if team.isEmpty, let me = model.tasks.me { return [me] }
    return team
  }

  /// The open projects, and the task's own even if it was archived.
  private var projectChoices: [TasksProject] {
    let projects = model.tasks.projects
    guard let id = draft.projectId, !projects.contains(where: { $0.id == id }),
      let own = model.tasks.project(id)
    else { return projects }
    return projects + [own]
  }

  /// The draft as it would be saved.
  private var result: TaskDraft {
    var result = draft
    result.dueAt = hasDue ? due : nil
    result.steps =
      editing == nil
      ? steps.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
      : []
    return result
  }

  private var problem: String? {
    if let problem = result.problem { return problem }
    if steps.contains(where: { $0.text.count > Self.stepLimit }) {
      return "A step can be at most 500 characters."
    }
    return nil
  }

  private var hasChanges: Bool {
    result != initial || !newStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  // MARK: Doing

  private func prepare() {
    guard !prepared else { return }
    prepared = true
    if editing == nil {
      // Yours unless you say otherwise, as on the website.
      if draft.assigneeIds.isEmpty, let me = model.tasks.me {
        draft.assigneeIds = [me.id]
        initial.assigneeIds = [me.id]
      }
      Task {
        try? await Task.sleep(for: .milliseconds(450))
        focus = .title
      }
    }
  }

  private func toggleAssignee(_ id: String) {
    if let index = draft.assigneeIds.firstIndex(of: id) {
      draft.assigneeIds.remove(at: index)
    } else {
      draft.assigneeIds.append(id)
    }
    pickTick += 1
  }

  private func addStep() {
    let text = newStep.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, steps.count < Self.maxSteps else { return }
    steps.append(EditableStep(text: text))
    newStep = ""
    focus = .newStep
  }

  private func save() {
    guard !working else { return }
    if problem != nil {
      tried = true
      failTick += 1
      focus = .title
      return
    }
    let finished = result
    let editingId = editing?.id
    working = true
    Task {
      defer { working = false }
      do {
        let saved: TaskItem
        if let editingId {
          saved = try await model.tasks.update(editingId, with: finished)
        } else {
          saved = try await model.tasks.create(finished)
        }
        onSaved?(saved)
        model.confirm(editingId == nil ? String(localized: "Task added.") : String(localized: "Saved."))
        dismiss()
      } catch {
        model.show(error)
      }
    }
  }
}

/// A step being written, before the task exists.
private struct EditableStep: Identifiable, Equatable {
  let id = UUID()
  var text: String
}
