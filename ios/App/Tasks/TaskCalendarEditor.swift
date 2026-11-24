import EventKit
import EventKitUI
import SwiftUI
import UIKit

/// iOS's own new-event sheet, filled in from a task: its title, its due
/// moment and half an hour. The sheet runs outside the app, so it needs no
/// calendar permission beyond what it asks for itself (write-only access,
/// NSCalendarsWriteOnlyAccessUsageDescription).
struct TaskCalendarEditor: UIViewControllerRepresentable {
  let title: String
  let start: Date
  let notes: String?
  let url: URL?
  /// Called once the sheet is done: true when the event was saved.
  let onFinish: (Bool) -> Void

  init(title: String, start: Date, notes: String? = nil, url: URL? = nil, onFinish: @escaping (Bool) -> Void) {
    self.title = title
    self.start = start
    self.notes = notes
    self.url = url
    self.onFinish = onFinish
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onFinish: onFinish)
  }

  func makeUIViewController(context: Context) -> EKEventEditViewController {
    let store = EKEventStore()
    let event = EKEvent(eventStore: store)
    event.title = title
    event.startDate = start
    event.endDate = start.addingTimeInterval(30 * 60)
    event.notes = notes
    event.url = url
    let controller = EKEventEditViewController()
    controller.eventStore = store
    controller.event = event
    controller.editViewDelegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {
    context.coordinator.onFinish = onFinish
  }

  @MainActor
  final class Coordinator: NSObject, @preconcurrency EKEventEditViewDelegate {
    var onFinish: (Bool) -> Void

    init(onFinish: @escaping (Bool) -> Void) {
      self.onFinish = onFinish
      super.init()
    }

    func eventEditViewController(
      _ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction
    ) {
      onFinish(action == .saved)
    }
  }
}
