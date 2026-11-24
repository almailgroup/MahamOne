import MahamKit
import SwiftUI
import WidgetKit

/// Today in Maham Tasks on the Home Screen, the Lock Screen and in StandBy:
/// what's late, what's due, and a checkmark to finish a task in place.
struct TodayWidget: Widget {
  static let kind = "com.almailgroup.mahamone.today"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: Self.kind, provider: TodayProvider()) { entry in
      TodayWidgetView(entry: entry)
        .containerBackground(for: .widget) { TodayWidgetBackground() }
    }
    .configurationDisplayName("Today")
    .description("Your overdue and due-today tasks from Maham Tasks.")
    .supportedFamilies([
      .systemSmall, .systemMedium, .systemLarge,
      .accessoryCircular, .accessoryRectangular, .accessoryInline,
    ])
  }
}

struct TodayEntry: TimelineEntry {
  let date: Date
  let snapshot: TodaySnapshot
  /// Drawn redacted, while WidgetKit waits for the real thing.
  var isPlaceholder = false
}

/// The saved snapshot at once; a fresh one from the network for the
/// timeline, then again in half an hour (the app also reloads the widgets
/// whenever your tasks change).
struct TodayProvider: TimelineProvider {
  func placeholder(in context: Context) -> TodayEntry {
    var snapshot = TodayProvider.sample
    if let cached = TodayLoader.cached(), cached.signedIn, !cached.items.isEmpty {
      snapshot = cached
    }
    return TodayEntry(date: Date(), snapshot: snapshot, isPlaceholder: true)
  }

  func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
    let cached = TodayLoader.cached()
    if context.isPreview, cached?.signedIn != true {
      // The widget gallery: show what the widget looks like with tasks in it.
      completion(TodayEntry(date: Date(), snapshot: TodayProvider.sample))
    } else {
      completion(TodayEntry(date: Date(), snapshot: cached ?? .signedOut))
    }
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
    let reply = WidgetReply(completion)
    Task {
      let snapshot = await TodayProvider.fresh()
      let now = Date()
      let entry = TodayEntry(date: now, snapshot: snapshot)
      reply.send(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30 * 60))))
    }
  }

  /// The network, unless the app or a checkmark saved a snapshot a moment ago.
  static func fresh() async -> TodaySnapshot {
    if let cached = TodayLoader.cached(), cached.signedIn,
      Date().timeIntervalSince(cached.updatedAt) < 60
    {
      return cached
    }
    return await TodayLoader.load()
  }

  /// A day with a few tasks in it, for the gallery and the placeholder.
  static var sample: TodaySnapshot {
    let now = Date()
    let tasks = [
      TaskItem(
        id: "sample-1", title: String(localized: "Send the monthly report"), priority: .high,
        dueAt: now.addingTimeInterval(-2 * 3600)),
      TaskItem(
        id: "sample-2", title: String(localized: "Call the new client"), priority: .medium,
        dueAt: now.addingTimeInterval(20 * 60)),
      TaskItem(
        id: "sample-3", title: String(localized: "Review the supplier contract"), priority: .urgent,
        dueAt: now.addingTimeInterval(40 * 60)),
    ]
    return TodaySnapshot(plan: DayPlan(tasks: tasks, now: now), now: now)
  }
}

/// WidgetKit's completion handler, carried into the task that fetches.
private struct WidgetReply<Value>: @unchecked Sendable {
  let send: (Value) -> Void

  init(_ send: @escaping (Value) -> Void) {
    self.send = send
  }
}
