import MahamKit
import SwiftUI

/// What happened while you were away: Maham Tasks' notifications (assigned,
/// mentioned, review asked, …) and the company's changes in Maham One.
struct InboxView: View {
  @Environment(AppModel.self) private var model
  @State private var path = NavigationPath()
  @State private var section: Pane = .tasks
  @State private var opening: String?

  enum Pane: Hashable, CaseIterable {
    case tasks, company

    var title: LocalizedStringKey {
      switch self {
      case .tasks: "Maham Tasks"
      case .company: "Maham One"
      }
    }
  }

  var body: some View {
    NavigationStack(path: $path) {
      List {
        switch section {
        case .tasks: taskNotifications
        case .company: companyUpdates
        }
      }
      .mahamScreen()
      .navigationTitle("Inbox")
      .safeAreaInset(edge: .top) {
        Picker("Show", selection: $section) {
          ForEach(Pane.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 6)
      }
      .toolbar {
        if section == .tasks, model.tasks.unreadCount > 0 {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Mark all read", systemImage: "checkmark.circle") {
              Task { await model.tasks.markAllRead() }
            }
          }
        }
      }
      .refreshable {
        switch section {
        case .tasks: await model.tasks.refresh()
        case .company: await model.business.refreshCompany()
        }
      }
      .taskDestinations()
      .onChange(of: model.pendingLink, initial: true) { _, link in
        if link == .inbox {
          section = .tasks
          path = NavigationPath()
          model.pendingLink = nil
        }
      }
    }
  }

  @ViewBuilder
  private var taskNotifications: some View {
    let items = model.tasks.notifications
    if items.isEmpty {
      EmptyState(title: "No notifications", symbol: "tray", message: "When someone assigns you a task or mentions you, it shows here.")
        .listRowBackground(Color.clear)
    } else {
      ForEach(items) { item in
        Button {
          open(item)
        } label: {
          NotificationRow(item: item, loading: opening == item.id)
        }
        .buttonStyle(.plain)
        .glassRow()
        .swipeActions(edge: .leading) {
          if item.isUnread {
            Button("Read", systemImage: "envelope.open") {
              Task { await model.tasks.markRead(item) }
            }
            .tint(.blue)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var companyUpdates: some View {
    let items = model.business.updates
    if items.isEmpty {
      EmptyState(title: "No changes yet", symbol: "clock.arrow.circlepath", message: "The team's changes in Maham One show here for owners and approvers.")
        .listRowBackground(Color.clear)
    } else {
      ForEach(items) { event in
        InboxChangeRow(event: event).glassRow()
      }
    }
  }

  private func open(_ item: TaskNotification) {
    Task {
      await model.tasks.markRead(item)
      guard let id = item.taskId else { return }
      opening = item.id
      defer { opening = nil }
      do {
        if let task = try await model.tasks.task(id) {
          path.append(task)
        } else {
          model.show(MahamError.permission("This task is no longer there."))
        }
      } catch {
        model.show(error)
      }
    }
  }
}

private struct NotificationRow: View {
  let item: TaskNotification
  var loading = false

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: item.kind.symbol)
        .font(.body.weight(.semibold))
        .foregroundStyle(item.kind.color)
        .frame(width: 34, height: 34)
        .background(item.kind.color.opacity(0.14), in: .circle)
      VStack(alignment: .leading, spacing: 3) {
        Text(item.title)
          .font(.subheadline.weight(item.isUnread ? .semibold : .regular))
          .foregroundStyle(.primary)
        if let body = item.body, !body.isEmpty {
          Text(body)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(3)
        }
        Text(item.createdAt, format: .relative(presentation: .named))
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      Spacer(minLength: 0)
      if loading {
        ProgressView()
      } else if item.isUnread {
        Circle().fill(.tint).frame(width: 9, height: 9)
          .accessibilityLabel(Text("Unread"))
      }
    }
    .padding(.vertical, 4)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
  }
}

/// One of the team's changes in Maham One, in plain words.
private struct InboxChangeRow: View {
  let event: ChangeEvent

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      AvatarView(initials: initials, id: event.actorName ?? "?", size: 34)
      VStack(alignment: .leading, spacing: 3) {
        Text(sentence)
          .font(.subheadline)
        Text(event.at, format: .relative(presentation: .named))
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      Spacer(minLength: 0)
      if event.important {
        Image(systemName: "exclamationmark.circle.fill")
          .foregroundStyle(.orange)
          .accessibilityLabel(Text("Important"))
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }

  private var initials: String {
    let words = (event.actorName ?? "?").split(separator: " ")
    return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
  }

  private var sentence: String {
    let who = event.actorName ?? String(localized: "Someone")
    let what = event.subjectName ?? thing
    let many = event.count > 1 ? " (×\(event.count))" : ""
    switch event.op {
    case "insert": return String(localized: "\(who) added \(what)") + many
    case "delete": return String(localized: "\(who) removed \(what)") + many
    default: return String(localized: "\(who) changed \(what)") + many
    }
  }

  /// The kind of record, when the change has no name of its own.
  private var thing: String {
    switch event.tbl {
    case "documents": String(localized: "a document")
    case "clients": String(localized: "a client")
    case "employees": String(localized: "an employee")
    case "items": String(localized: "an item")
    case "payments": String(localized: "a payment")
    case "expenses": String(localized: "an expense")
    default: String(localized: "a record")
    }
  }
}
