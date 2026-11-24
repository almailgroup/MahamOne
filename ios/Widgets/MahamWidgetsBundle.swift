import MahamKit
import SwiftUI
import WidgetKit

@main
struct MahamWidgetsBundle: WidgetBundle {
  var body: some Widget {
    TodayWidget()
  }
}

/// A first widget, to prove the build: replaced by the real ones.
struct TodayWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "com.almailgroup.mahamone.today", provider: TodayProvider()) { entry in
      Text("\(entry.snapshot.todayCount)")
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Today")
  }
}

struct TodayEntry: TimelineEntry {
  let date: Date
  let snapshot: TodaySnapshot
}

struct TodayProvider: TimelineProvider {
  func placeholder(in context: Context) -> TodayEntry {
    TodayEntry(date: .now, snapshot: .signedOut)
  }

  func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
    completion(placeholder(in: context))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
    completion(Timeline(entries: [placeholder(in: context)], policy: .never))
  }
}
