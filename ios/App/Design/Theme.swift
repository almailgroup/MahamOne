import MahamKit
import SwiftUI

// The colours Maham One and Maham Tasks use on the web, for the same
// meanings: a task's status, its priority, an invoice's state.

extension TaskStatus {
  var color: Color {
    switch self {
    case .todo: .gray
    case .inProgress: .blue
    case .inReview: .purple
    case .done: .green
    }
  }

  var label: LocalizedStringKey { LocalizedStringKey(title) }
}

extension TaskPriority {
  var color: Color {
    switch self {
    case .low: .gray
    case .medium: .blue
    case .high: .orange
    case .urgent: .red
    }
  }

  var label: LocalizedStringKey { LocalizedStringKey(title) }
}

extension DocumentStatus {
  var color: Color {
    switch self {
    case .draft, .other: .gray
    case .sent, .issued, .delivered: .blue
    case .partial: .orange
    case .paid, .accepted, .applied: .green
    case .invoiced, .converted: .indigo
    case .void, .declined, .cancelled: .red
    }
  }

  var label: LocalizedStringKey { LocalizedStringKey(title) }
}

extension MemberRole {
  var label: LocalizedStringKey { LocalizedStringKey(title) }
}

extension NotificationKind {
  var color: Color {
    switch self {
    case .taskAssigned, .taskUnblocked: .blue
    case .taskCommented, .taskMentioned, .directMessage: .indigo
    case .taskReviewRequested: .purple
    case .taskCompleted: .green
    case .reminderFailed: .orange
    case .taskUnassigned, .other: .gray
    }
  }
}

/// A stable colour for a person, from their id, so an avatar keeps its
/// colour everywhere.
enum PersonColor {
  static let palette: [Color] = [.indigo, .teal, .orange, .pink, .blue, .green, .purple, .brown, .cyan, .mint]

  static func of(_ id: String) -> Color {
    let sum = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fff_ffff }
    return palette[sum % palette.count]
  }
}

extension Date {
  /// "Today 3:00 PM", "Tomorrow", "Mon 12 Nov", in the reader's language.
  var relativeDue: String {
    let calendar = Calendar.current
    let time = formatted(date: .omitted, time: .shortened)
    if calendar.isDateInToday(self) { return String(localized: "Today \(time)") }
    if calendar.isDateInTomorrow(self) { return String(localized: "Tomorrow \(time)") }
    if calendar.isDateInYesterday(self) { return String(localized: "Yesterday \(time)") }
    let sameYear = calendar.isDate(self, equalTo: .now, toGranularity: .year)
    return formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year(sameYear ? .omitted : .defaultDigits))
  }
}

extension LocalDate {
  /// The day as the reader's calendar writes it.
  var display: String {
    start(in: .current).formatted(date: .abbreviated, time: .omitted)
  }
}
