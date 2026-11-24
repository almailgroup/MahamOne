import ActivityKit
import SwiftUI
import WidgetKit

/// The task you're focusing on, on the Lock Screen and in the Dynamic
/// Island, with the time since you started. A tap opens the task.
struct FocusLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: FocusActivityAttributes.self) { context in
      FocusLockScreenView(context: context)
        .widgetURL(DeepLink.task(context.attributes.taskId).url)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          FocusBadge(size: 40)
        }
        DynamicIslandExpandedRegion(.trailing) {
          FocusTimer(started: context.state.started)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.indigo)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 96, alignment: .trailing)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(alignment: .leading, spacing: 2) {
            Text(context.attributes.title)
              .font(.headline)
              .lineLimit(1)
            if let project = context.state.projectName {
              Text(project)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text("Focusing since \(context.state.started.formatted(date: .omitted, time: .shortened))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      } compactLeading: {
        Image(systemName: "scope")
          .foregroundStyle(Color.indigo)
          .accessibilityLabel(Text("Focus"))
      } compactTrailing: {
        FocusTimer(started: context.state.started)
          .font(.caption.weight(.semibold))
          .foregroundStyle(Color.indigo)
          .multilineTextAlignment(.trailing)
          .frame(maxWidth: 52, alignment: .trailing)
      } minimal: {
        Image(systemName: "scope")
          .foregroundStyle(Color.indigo)
          .accessibilityLabel(Text("Focus"))
      }
      .widgetURL(DeepLink.task(context.attributes.taskId).url)
      .keylineTint(Color.indigo)
    }
  }
}

/// Minutes and seconds since the focus started, kept by the system.
private struct FocusTimer: View {
  let started: Date

  var body: some View {
    Text(timerInterval: started...Date.distantFuture, countsDown: false)
      .monospacedDigit()
  }
}

/// The focus symbol on its tinted circle.
private struct FocusBadge: View {
  var size: CGFloat = 44

  var body: some View {
    Image(systemName: "scope")
      .font(.system(size: size * 0.45, weight: .semibold))
      .foregroundStyle(Color.indigo)
      .frame(width: size, height: size)
      .background(Color.indigo.opacity(0.18), in: .circle)
      .accessibilityHidden(true)
  }
}

/// The Lock Screen's banner: what you're on, its project, and the timer.
private struct FocusLockScreenView: View {
  let context: ActivityViewContext<FocusActivityAttributes>

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      FocusBadge()
      VStack(alignment: .leading, spacing: 2) {
        Text("Focusing on")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Text(context.attributes.title)
          .font(.headline)
          .lineLimit(2)
        if let project = context.state.projectName {
          Text(project)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      FocusTimer(started: context.state.started)
        .font(.title2.weight(.semibold))
        .foregroundStyle(Color.indigo)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 110, alignment: .trailing)
    }
    .padding(16)
    .accessibilityElement(children: .combine)
  }
}
