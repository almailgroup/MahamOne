import MahamKit
import SwiftUI
import UserNotifications
import WidgetKit

/// Settings kept on this iPhone (Settings screen, `@AppStorage` keys).
enum Preferences {
  static let spotlightKey = "spotlightEnabled"
  static let remindersKey = "remindersEnabled"
  static let lockKey = "lockEnabled"
  static let briefingKey = "briefingEnabled"

  static var spotlight: Bool { UserDefaults.standard.object(forKey: spotlightKey) as? Bool ?? true }
  static var reminders: Bool { UserDefaults.standard.object(forKey: remindersKey) as? Bool ?? true }
  static var briefing: Bool { UserDefaults.standard.object(forKey: briefingKey) as? Bool ?? true }
}

/// What the rest of iOS hears after the app's data changes: the widgets'
/// snapshot, Spotlight, the due-date reminders and the icon's badge.
@MainActor
enum SystemSync {
  static func tasksChanged(_ tasks: [TaskItem], plan: DayPlan, projects: [TasksProject]) {
    AppServices.shared?.cache.save(TodaySnapshot(plan: plan), as: TodaySnapshot.cacheKey)
    WidgetCenter.shared.reloadAllTimelines()
    let open = tasks.filter { !$0.isDone }
    if Preferences.spotlight {
      Task { await Spotlight.index(tasks: open, projects: projects) }
    }
    if Preferences.reminders {
      Task { await Reminders.schedule(open) }
    }
  }

  static func businessChanged(clients: [Client], invoices: [SalesDocument], expiries: [Expiry]) {
    if Preferences.spotlight {
      let active = clients.filter { !$0.archived }
      Task { await Spotlight.index(clients: active) }
    }
  }

  static func badge(_ count: Int) {
    UNUserNotificationCenter.current().setBadgeCount(count, withCompletionHandler: nil)
  }

  /// Nothing of the account stays in iOS once you sign out.
  static func signedOut() {
    AppServices.shared?.cache.save(TodaySnapshot.signedOut, as: TodaySnapshot.cacheKey)
    WidgetCenter.shared.reloadAllTimelines()
    BriefingCache.clear()
    FocusSession.stop()
    Task {
      await Spotlight.removeAll()
      await Reminders.removeAll()
    }
    badge(0)
  }

  /// Settings switched off: take back what was given.
  static func spotlightTurnedOff() {
    Task { await Spotlight.removeAll() }
  }

  static func remindersTurnedOff() {
    Task { await Reminders.removeAll() }
  }
}
