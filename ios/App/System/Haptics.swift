import SwiftUI
import UIKit

/// What a haptic says. Every one plays at the iPhone's full strength
/// (`Haptics.strength`), all over the app.
enum Haptic: Sendable, Equatable {
  /// A button or a row tapped: a light tap.
  case tap
  /// A main action (Save, the + of the tab bar, a confirmed dialog): a firmer tap.
  case press
  /// One choice among several: a tab, a segment, a menu item, a day, an app.
  case selection
  /// A switch turned on or off.
  case toggle
  /// Something that changes the whole screen (the theme, the language) or a
  /// swipe that changes a task.
  case change
  /// A panel opening (the drawer, the create menu).
  case open
  /// A panel or sheet closing.
  case close
  /// Pull to refresh, as it starts.
  case refresh
  /// Done, saved, sent.
  case success
  /// A delete, or something to be careful with.
  case warning
  /// Something refused or failed.
  case error
}

/// The app's haptics, in one place so they feel the same everywhere: each
/// one is a short pattern of impacts played at `strength` (100%) of its
/// intensity, firm enough to be felt through a case: taps are crisp
/// (rigid), main actions and panels firmer (medium); never the soft
/// impact, which is hard to feel. Success, warning and error are UIKit's
/// own. The generators are kept and prepared, so a haptic comes with the
/// touch, not after it. When the iPhone's System Haptics are off, UIKit
/// plays nothing.
///
///     Haptics.play(.tap)
///     .haptic(.selection, trigger: filter)
///     .refreshable { await Haptics.refresh(); await store.refresh() }
@MainActor
enum Haptics {
  /// Every haptic plays at this share of its full strength.
  static let strength: CGFloat = 1

  /// Taps closer together than this are felt as one (a button whose action
  /// also changes a selection). Success, warning and error always play.
  private static let minimumGap: TimeInterval = 0.07

  private enum Weight: Hashable, Sendable {
    case light, medium, heavy, soft, rigid

    var style: UIImpactFeedbackGenerator.FeedbackStyle {
      switch self {
      case .light: .light
      case .medium: .medium
      case .heavy: .heavy
      case .soft: .soft
      case .rigid: .rigid
      }
    }
  }

  /// One impact of a pattern: its weight, its usual intensity (before
  /// `strength`) and when it plays, in milliseconds after the first.
  private struct Beat: Sendable {
    let weight: Weight
    let intensity: CGFloat
    var delay: Int = 0
  }

  private static var generators: [Weight: UIImpactFeedbackGenerator] = [:]
  private static let notifications = UINotificationFeedbackGenerator()
  private static var lastPlayed: TimeInterval = 0

  private static func pattern(_ haptic: Haptic) -> [Beat] {
    switch haptic {
    case .tap: [Beat(weight: .rigid, intensity: 1)]
    case .press: [Beat(weight: .medium, intensity: 1)]
    case .selection: [Beat(weight: .rigid, intensity: 1)]
    case .toggle: [Beat(weight: .rigid, intensity: 1)]
    case .change: [Beat(weight: .medium, intensity: 1)]
    case .open: [Beat(weight: .medium, intensity: 1)]
    case .close: [Beat(weight: .light, intensity: 1)]
    case .refresh: [Beat(weight: .medium, intensity: 1)]
    // UIKit's own (`notification`).
    case .success, .warning, .error: []
    }
  }

  private static func notification(_ haptic: Haptic) -> UINotificationFeedbackGenerator.FeedbackType? {
    switch haptic {
    case .success: .success
    case .warning: .warning
    case .error: .error
    default: nil
    }
  }

  /// Plays a haptic at the app's strength.
  static func play(_ haptic: Haptic) {
    let now = ProcessInfo.processInfo.systemUptime
    let always = haptic == .success || haptic == .warning || haptic == .error
    if !always, now - lastPlayed < minimumGap { return }
    lastPlayed = now
    if let type = notification(haptic) {
      notifications.notificationOccurred(type)
      notifications.prepare()
      return
    }
    for beat in pattern(haptic) {
      if beat.delay == 0 {
        fire(beat)
      } else {
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(beat.delay))
          fire(beat)
        }
      }
    }
  }

  /// Wakes the Taptic Engine for a haptic that is about to play (a button
  /// being pressed), so it is felt without delay.
  static func prepare(_ haptic: Haptic = .tap) {
    if notification(haptic) != nil {
      notifications.prepare()
      return
    }
    var seen = Set<Weight>()
    for beat in pattern(haptic) where seen.insert(beat.weight).inserted {
      generator(beat.weight).prepare()
    }
  }

  /// Pull to refresh's haptic, from a `.refreshable` action.
  nonisolated static func refresh() async {
    await MainActor.run { play(.refresh) }
  }

  private static func fire(_ beat: Beat) {
    let engine = generator(beat.weight)
    engine.impactOccurred(intensity: min(1, max(0, beat.intensity * strength)))
    engine.prepare()
  }

  private static func generator(_ weight: Weight) -> UIImpactFeedbackGenerator {
    if let found = generators[weight] { return found }
    let made = UIImpactFeedbackGenerator(style: weight.style)
    generators[weight] = made
    return made
  }
}

@MainActor
extension View {
  /// Plays a haptic each time `trigger` changes (SwiftUI's `sensoryFeedback`,
  /// at the app's strength).
  func haptic<T: Equatable>(_ haptic: Haptic, trigger: T) -> some View {
    onChange(of: trigger) { _, _ in Haptics.play(haptic) }
  }

  /// Plays a haptic when `trigger` changes and `condition(old, new)` holds.
  func haptic<T: Equatable>(_ haptic: Haptic, trigger: T, condition: @escaping (T, T) -> Bool) -> some View {
    onChange(of: trigger) { old, new in
      if condition(old, new) { Haptics.play(haptic) }
    }
  }

  /// Plays the haptic `choose(old, new)` returns, if any, when `trigger` changes.
  func haptic<T: Equatable>(trigger: T, _ choose: @escaping (T, T) -> Haptic?) -> some View {
    onChange(of: trigger) { old, new in
      if let haptic = choose(old, new) { Haptics.play(haptic) }
    }
  }
}
