import Foundation
import MahamKit

/// Your day for the widgets: fetched over the network with the session the
/// app and its widgets share, kept in the App Group's cache, and read back
/// from there when there is no network. The app writes the same snapshot
/// after each of its own refreshes (SystemSync).
enum TodayLoader {
  /// The last snapshot the app or a widget saved, without the network.
  static func cached() -> TodaySnapshot? {
    AppServices.shared?.cache.load(TodaySnapshot.self, as: TodaySnapshot.cacheKey)
  }

  /// Your tasks, fresh: saved for next time and returned. Without a session,
  /// `.signedOut`; offline (or when the server can't answer), the saved copy.
  @discardableResult
  static func load(now: Date = Date()) async -> TodaySnapshot {
    guard let services = AppServices.shared else { return .signedOut }
    guard await services.auth.currentSession != nil else { return .signedOut }
    do {
      let me = try await services.tasks.me()
      let tasks = try await services.tasks.myTasks(userId: me.id)
      let snapshot = TodaySnapshot(plan: DayPlan(tasks: tasks, now: now), now: now)
      services.cache.save(snapshot, as: TodaySnapshot.cacheKey)
      return snapshot
    } catch MahamError.notSignedIn {
      return signedOut(services)
    } catch MahamError.sessionExpired {
      return signedOut(services)
    } catch MahamError.notInTasks {
      // Signed in to Maham One but not in Maham Tasks: nothing to do.
      let empty = TodaySnapshot(plan: DayPlan(tasks: [], now: now), now: now)
      services.cache.save(empty, as: TodaySnapshot.cacheKey)
      return empty
    } catch {
      return cached() ?? TodaySnapshot(plan: DayPlan(tasks: [], now: now), now: now)
    }
  }

  /// The session is gone: nothing of the account stays on the widgets.
  private static func signedOut(_ services: AppServices) -> TodaySnapshot {
    services.cache.save(TodaySnapshot.signedOut, as: TodaySnapshot.cacheKey)
    return .signedOut
  }
}
