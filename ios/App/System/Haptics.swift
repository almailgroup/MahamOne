import SwiftUI

/// The app's haptics, as SwiftUI's sensory feedback. Screens attach one with
/// `.sensoryFeedback(Haptics.done, trigger: …)`; these names keep the same
/// feel everywhere.
enum Haptics {
  /// A task done, a step ticked.
  static let done: SensoryFeedback = .success
  /// Something refused or failed.
  static let failed: SensoryFeedback = .error
  /// A card picked up or dropped on the board, a tab, a picker.
  static let pick: SensoryFeedback = .selection
  /// A swipe that changes something.
  static let change: SensoryFeedback = .impact(weight: .medium)
  /// A delete.
  static let warning: SensoryFeedback = .warning
}
