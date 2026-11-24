import AppIntents
import MahamKit
import SwiftUI
import WidgetKit

// The Today widget's faces, one per size. Every layout is leading-aligned
// so it mirrors for Arabic, and the parts that carry meaning are marked
// accentable for the tinted and clear Home Screens.

/// The brand's colour for the widget's headers.
private var brand: Color { .indigo }

struct TodayWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: TodayEntry

  var body: some View {
    content
      .redacted(reason: entry.isPlaceholder ? .placeholder : [])
      .widgetURL(DeepLink.today.url)
  }

  @ViewBuilder
  private var content: some View {
    let snapshot = entry.snapshot
    if !snapshot.signedIn {
      TodaySignedOutView(family: family)
    } else {
      switch family {
      case .systemSmall:
        TodaySmallView(snapshot: snapshot)
      case .systemMedium:
        TodayListView(snapshot: snapshot, limit: 3)
      case .systemLarge, .systemExtraLarge:
        TodayListView(snapshot: snapshot, limit: 7)
      case .accessoryCircular:
        TodayCircularView(snapshot: snapshot)
      case .accessoryRectangular:
        TodayRectangularView(snapshot: snapshot)
      case .accessoryInline:
        TodayInlineView(snapshot: snapshot)
      default:
        TodaySmallView(snapshot: snapshot)
      }
    }
  }
}

/// A quiet wash of the brand's indigo on the Home Screen; nothing on the
/// Lock Screen, and nothing when iOS tints or clears the widget.
struct TodayWidgetBackground: View {
  @Environment(\.widgetFamily) private var family
  @Environment(\.widgetRenderingMode) private var renderingMode

  var body: some View {
    switch family {
    case .accessoryCircular, .accessoryRectangular, .accessoryInline:
      Color.clear
    default:
      if renderingMode == .fullColor {
        LinearGradient(
          colors: [brand.opacity(0.16), Color.purple.opacity(0.06), Color.clear],
          startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .background(.background)
      } else {
        Color.clear
      }
    }
  }
}

// MARK: Pieces

/// "Today", with the checklist.
private struct TodayHeader: View {
  var body: some View {
    Label("Today", systemImage: "checklist")
      .font(.caption.weight(.semibold))
      .foregroundStyle(brand)
      .lineLimit(1)
      .widgetAccentable()
  }
}

/// When a task is due: the time for today, the day otherwise; red when late.
private struct TodayDueText: View {
  let due: Date
  let overdue: Bool

  var body: some View {
    Text(label)
      .foregroundStyle(overdue ? Color.red : Color.secondary)
      .lineLimit(1)
      .accessibilityLabel(overdue ? Text("Overdue, \(label)") : Text(label))
  }

  private var label: String {
    if Calendar.current.isDateInToday(due) {
      return due.formatted(date: .omitted, time: .shortened)
    }
    return due.formatted(.dateTime.day().month(.abbreviated))
  }
}

/// A number over its name: "2 / Overdue".
private struct TodayCount: View {
  let value: Int
  let title: LocalizedStringKey
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(value, format: .number)
        .font(.title3.weight(.bold))
        .monospacedDigit()
        .foregroundStyle(tint)
        .widgetAccentable()
      Text(title)
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

/// One task: a checkmark that finishes it here, and its title, which opens it.
private struct TodayTaskRow: View {
  let item: TodaySnapshot.Item

  var body: some View {
    HStack(spacing: 10) {
      Button(intent: CompleteTaskIntent(taskId: item.id)) {
        Image(systemName: "circle")
          .font(.title3.weight(.medium))
          .foregroundStyle(item.overdue ? Color.red : Color.secondary)
          .contentShape(.circle)
      }
      .buttonStyle(.plain)
      .widgetAccentable(item.overdue)
      .accessibilityLabel(Text("Mark \(item.title) done"))

      Link(destination: DeepLink.task(item.id).url) {
        HStack(spacing: 6) {
          if item.priority == .urgent || item.priority == .high {
            Image(systemName: "flag.fill")
              .font(.caption2)
              .foregroundStyle(item.priority == .urgent ? Color.red : Color.orange)
              .accessibilityHidden(true)
          }
          Text(item.title)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
          Spacer(minLength: 4)
          if let due = item.dueAt {
            TodayDueText(due: due, overdue: item.overdue)
              .font(.caption.weight(.medium))
          }
        }
        .contentShape(.rect)
      }
    }
    .invalidatableContent()
  }
}

/// Nothing left for today.
private struct TodayAllClear: View {
  let doneToday: Int

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "checkmark.seal.fill")
        .font(.title2)
        .foregroundStyle(Color.green)
        .widgetAccentable()
      Text("All clear for today")
        .font(.headline)
      if doneToday > 0 {
        Text("\(doneToday) done today")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: Home Screen

/// The three numbers and what comes next.
private struct TodaySmallView: View {
  let snapshot: TodaySnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      TodayHeader()
      HStack(alignment: .top, spacing: 4) {
        TodayCount(
          value: snapshot.overdueCount, title: "Overdue",
          tint: snapshot.overdueCount > 0 ? Color.red : Color.secondary)
        TodayCount(value: snapshot.todayCount, title: "Today", tint: Color.primary)
        TodayCount(value: snapshot.doneTodayCount, title: "Done", tint: Color.green)
      }
      Spacer(minLength: 0)
      if let next = snapshot.items.first {
        VStack(alignment: .leading, spacing: 1) {
          HStack(spacing: 4) {
            Text("Next")
            if let due = next.dueAt {
              Text(verbatim: "·")
              TodayDueText(due: due, overdue: next.overdue)
            }
          }
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          Text(next.title)
            .font(.footnote.weight(.semibold))
            .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
      } else {
        Label("All clear", systemImage: "checkmark.seal")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(Color.green)
          .widgetAccentable()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

/// Up to `limit` of today's tasks, each with its checkmark.
private struct TodayListView: View {
  let snapshot: TodaySnapshot
  let limit: Int

  var body: some View {
    let shown = Array(snapshot.items.prefix(limit))
    let total = snapshot.overdueCount + snapshot.todayCount
    VStack(alignment: .leading, spacing: limit > 3 ? 10 : 7) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        TodayHeader()
        Spacer(minLength: 8)
        HStack(spacing: 8) {
          if snapshot.overdueCount > 0 {
            Text("\(snapshot.overdueCount) overdue")
              .foregroundStyle(Color.red)
              .widgetAccentable()
          }
          Text("\(snapshot.todayCount) today")
            .foregroundStyle(.secondary)
          if snapshot.doneTodayCount > 0 {
            Label {
              Text(snapshot.doneTodayCount, format: .number)
            } icon: {
              Image(systemName: "checkmark")
            }
            .foregroundStyle(Color.green)
            .accessibilityLabel(Text("\(snapshot.doneTodayCount) done today"))
          }
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
      }
      if shown.isEmpty {
        TodayAllClear(doneToday: snapshot.doneTodayCount)
      } else {
        ForEach(shown) { item in
          TodayTaskRow(item: item)
        }
        Spacer(minLength: 0)
        if total > shown.count {
          Text("\(total - shown.count) more")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

// MARK: Lock Screen

/// Done today against all of today's work, with what's left in the middle.
private struct TodayCircularView: View {
  let snapshot: TodaySnapshot

  var body: some View {
    let due = snapshot.overdueCount + snapshot.todayCount
    let total = due + snapshot.doneTodayCount
    Gauge(value: Double(snapshot.doneTodayCount), in: 0...Double(max(total, 1))) {
      Image(systemName: "checklist")
    } currentValueLabel: {
      Text(due, format: .number)
    }
    .gaugeStyle(.accessoryCircularCapacity)
    .widgetAccentable()
    .accessibilityElement()
    .accessibilityLabel(Text("\(due) due today, \(snapshot.doneTodayCount) done"))
  }
}

/// How many are due, and the next one.
private struct TodayRectangularView: View {
  let snapshot: TodaySnapshot

  var body: some View {
    let due = snapshot.overdueCount + snapshot.todayCount
    VStack(alignment: .leading, spacing: 1) {
      Label {
        Text("\(due) due today")
      } icon: {
        Image(systemName: "checklist")
      }
      .font(.headline)
      .widgetAccentable()
      if let next = snapshot.items.first {
        Text(next.title)
          .font(.body)
          .lineLimit(2)
      } else {
        Text("All clear")
          .font(.body)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// "3 due today", above the clock.
private struct TodayInlineView: View {
  let snapshot: TodaySnapshot

  var body: some View {
    Label("\(snapshot.overdueCount + snapshot.todayCount) due today", systemImage: "checklist")
  }
}

// MARK: Signed out

private struct TodaySignedOutView: View {
  let family: WidgetFamily

  var body: some View {
    switch family {
    case .accessoryInline:
      Text("Sign in to Maham One")
    case .accessoryCircular:
      ZStack {
        AccessoryWidgetBackground()
        Image(systemName: "person.crop.circle")
          .font(.title2)
          .widgetAccentable()
      }
      .accessibilityLabel(Text("Sign in to Maham One"))
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 1) {
        Label("Maham One", systemImage: "checklist")
          .font(.headline)
          .widgetAccentable()
        Text("Sign in to Maham One")
          .font(.body)
          .lineLimit(2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    default:
      VStack(alignment: .leading, spacing: 8) {
        TodayHeader()
        Spacer(minLength: 0)
        Image(systemName: "person.crop.circle")
          .font(.title2)
          .foregroundStyle(brand)
          .widgetAccentable()
        Text("Sign in to Maham One")
          .font(.headline)
          .lineLimit(2)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }
}
