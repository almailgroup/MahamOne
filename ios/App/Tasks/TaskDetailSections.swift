import MahamKit
import SwiftUI

// The task detail's steps, comments and due-date sheet.

/// A task's steps: ticked in place, added inline.
struct TaskChecklistSection: View {
  @Environment(AppModel.self) private var model
  let taskId: String
  @Binding var steps: [ChecklistItem]
  let loaded: Bool
  @State private var newStep = ""
  @State private var adding = false
  @State private var doneTick = 0
  @FocusState private var fieldFocused: Bool

  /// As the website allows (and the database checks).
  private static let limit = 500

  init(taskId: String, steps: Binding<[ChecklistItem]>, loaded: Bool) {
    self.taskId = taskId
    _steps = steps
    self.loaded = loaded
  }

  var body: some View {
    let done = steps.filter(\.done).count
    GlassSection("Steps", symbol: "checklist") {
      if !steps.isEmpty {
        Text("\(done) of \(steps.count)")
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    } content: {
      VStack(alignment: .leading, spacing: 12) {
        if !steps.isEmpty {
          ProgressView(value: Double(done), total: Double(steps.count))
            .tint(.green)
            .accessibilityHidden(true)
        }
        if !loaded && steps.isEmpty {
          ProgressView()
            .frame(maxWidth: .infinity)
        }
        ForEach(steps) { step in
          stepRow(step)
        }
        addField
      }
    }
    .haptic(.success, trigger: doneTick)
  }

  private func stepRow(_ step: ChecklistItem) -> some View {
    Button {
      toggle(step)
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(step.done ? Color.green : Color.secondary)
          .contentTransition(.symbolEffect(.replace))
        Text(step.content)
          .strikethrough(step.done)
          .foregroundStyle(step.done ? Color.secondary : Color.primary)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(step.done ? .isSelected : [])
    .accessibilityHint(step.done ? Text("Marks the step as not done") : Text("Marks the step done"))
  }

  private var trimmed: String { newStep.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var canAdd: Bool { !trimmed.isEmpty && trimmed.count <= Self.limit && !adding }

  @ViewBuilder
  private var addField: some View {
    HStack(spacing: 8) {
      TextField("Add a step…", text: $newStep)
        .focused($fieldFocused)
        .submitLabel(.done)
        .onSubmit(add)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: .capsule)
      Button(action: add) {
        Group {
          if adding {
            ProgressView()
          } else {
            Image(systemName: "plus")
              .fontWeight(.semibold)
          }
        }
        .frame(width: 20, height: 20)
      }
      .buttonStyle(.glass)
      .buttonBorderShape(.circle)
      .disabled(!canAdd)
      .accessibilityLabel(Text("Add step"))
    }
    if newStep.count > Self.limit {
      Text("A step can be at most 500 characters.")
        .font(.caption)
        .foregroundStyle(.red)
    }
  }

  private func add() {
    let text = trimmed
    guard canAdd else { return }
    adding = true
    Task {
      defer { adding = false }
      do {
        let item = try await model.tasks.addStep(taskId, text)
        steps.append(item)
        newStep = ""
        fieldFocused = true
      } catch {
        model.show(error)
      }
    }
  }

  /// Ticked at once; put back if the database refuses.
  private func toggle(_ step: ChecklistItem) {
    guard let index = steps.firstIndex(where: { $0.id == step.id }) else { return }
    let done = !step.done
    steps[index].done = done
    if done { doneTick += 1 }
    Task {
      do {
        let saved = try await model.tasks.setStep(step, done: done)
        if let current = steps.firstIndex(where: { $0.id == saved.id }) { steps[current] = saved }
      } catch {
        if let current = steps.firstIndex(where: { $0.id == step.id }) { steps[current].done = step.done }
        model.show(error)
      }
    }
  }
}

/// A task's conversation, oldest first, with a box to add to it.
struct TaskCommentsSection: View {
  @Environment(AppModel.self) private var model
  let taskId: String
  @Binding var comments: [TaskComment]
  let loaded: Bool
  @State private var draft = ""
  @State private var sending = false
  @State private var sentTick = 0
  @FocusState private var composing: Bool

  /// As the website allows (and the database checks).
  private static let limit = 5000

  init(taskId: String, comments: Binding<[TaskComment]>, loaded: Bool) {
    self.taskId = taskId
    _comments = comments
    self.loaded = loaded
  }

  var body: some View {
    GlassSection("Comments", symbol: "text.bubble") {
      if !comments.isEmpty {
        Text(comments.count.formatted())
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    } content: {
      VStack(alignment: .leading, spacing: 14) {
        if !loaded && comments.isEmpty {
          ProgressView()
            .frame(maxWidth: .infinity)
        } else if comments.isEmpty {
          Text("No comments yet. Start the discussion.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        ForEach(comments) { comment in
          TaskCommentRow(comment: comment, author: model.tasks.profile(comment.userId))
        }
        composer
      }
    }
    .haptic(.selection, trigger: sentTick)
  }

  private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var canSend: Bool { !trimmed.isEmpty && trimmed.count <= Self.limit && !sending }

  private var composer: some View {
    VStack(alignment: .trailing, spacing: 4) {
      HStack(alignment: .bottom, spacing: 8) {
        TextField("Write a comment", text: $draft, axis: .vertical)
          .lineLimit(1...6)
          .focused($composing)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20, style: .continuous))
        Button(action: send) {
          Group {
            if sending {
              ProgressView()
            } else {
              Image(systemName: "arrow.up")
                .fontWeight(.semibold)
            }
          }
          .frame(width: 22, height: 22)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .disabled(!canSend)
        .accessibilityLabel(Text("Send comment"))
      }
      if draft.count > Self.limit - 500 {
        Text("\(draft.count) of \(Self.limit)")
          .font(.caption)
          .monospacedDigit()
          .foregroundStyle(draft.count > Self.limit ? Color.red : Color.secondary)
      }
    }
  }

  private func send() {
    let text = trimmed
    guard canSend else { return }
    sending = true
    Task {
      defer { sending = false }
      do {
        let comment = try await model.tasks.addComment(taskId, text)
        comments.append(comment)
        draft = ""
        sentTick += 1
      } catch {
        model.show(error)
      }
    }
  }
}

/// One comment: who, when, what.
private struct TaskCommentRow: View {
  let comment: TaskComment
  let author: TasksProfile?

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      if let author {
        AvatarView(profile: author, size: 30)
      } else {
        AvatarView(initials: "?", id: comment.userId ?? comment.id, size: 30)
      }
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          if let author {
            Text(author.displayName)
              .font(.subheadline.weight(.semibold))
          } else {
            Text("Unknown user")
              .font(.subheadline.weight(.semibold))
          }
          Text(comment.createdAt, format: .relative(presentation: .named))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(comment.content)
          .font(.subheadline)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
  }
}

/// A new due date: one of the usual ones, any date and time, or none.
struct TaskRescheduleSheet: View {
  @Environment(\.dismiss) private var dismiss
  private let current: Date?
  private let onPick: (Date?) -> Void
  @State private var date: Date

  init(current: Date?, onPick: @escaping (Date?) -> Void) {
    self.current = current
    self.onPick = onPick
    _date = State(initialValue: current ?? TaskDates.defaultDue())
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Quick picks") {
          ForEach(TaskDuePreset.allCases) { preset in
            let when = preset.date()
            Button {
              pick(when)
            } label: {
              LabeledContent {
                Text(when.relativeDue)
              } label: {
                Label(preset.title, systemImage: preset.symbol)
              }
            }
          }
        }

        Section("Pick a date and time") {
          DatePicker("Due", selection: $date, displayedComponents: [.date, .hourAndMinute])
            .datePickerStyle(.graphical)
        }

        if current != nil {
          Section {
            Button("Clear due date", systemImage: "calendar.badge.minus", role: .destructive) {
              pick(nil)
            }
          }
        }
      }
      .navigationTitle(Text("Due date"))
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", systemImage: "checkmark") { pick(date) }
            .buttonStyle(.glassProminent)
        }
      }
    }
  }

  private func pick(_ date: Date?) {
    onPick(date)
    dismiss()
  }
}
