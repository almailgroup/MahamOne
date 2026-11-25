import Foundation

/// When to sync (src/cloud/manager.ts): on start, soon after a change here
/// (1 s), when the app comes back into view or online, every minute while it
/// is open, and 500 ms after the cloud signals a change. Failures that may
/// pass are retried with growing pauses (2 s doubling to 5 min, ±20 %);
/// changes are never dropped in between.
///
/// Realtime: the web subscribes to `postgres_changes` on
/// `public.sync_signals` filtered by `company_id=eq.<id>`. The app's
/// Realtime client (not part of the engine yet) calls `cloudSignalled()`
/// on each signal; until then the minute's poll brings changes in.
extension SyncEngine {
  /// Pause before retry number `attempt` (1, 2, …), in seconds.
  public static func backoff(attempt: Int, random: Double) -> Double {
    let base = min(2000 * pow(2, Double(max(1, attempt) - 1)), 5 * 60_000)
    return (base * (0.8 + 0.4 * random)).rounded() / 1000
  }

  /// Starts syncing: now, then every minute, and on the other triggers.
  public func start() {
    guard !started else { return }
    started = true
    let interval = config.interval
    let clock = config.clock
    tickTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await clock.sleep(seconds: interval)
        } catch {
          return
        }
        guard let self, await self.tick() else { return }
      }
    }
    schedule(after: 0)
    Task { await self.refreshMembership() }
  }

  /// Stops the timers. A sync under way finishes; nothing is lost.
  public func stop() {
    started = false
    tickTask?.cancel()
    tickTask = nil
    scheduledTask?.cancel()
    scheduledTask = nil
    scheduledAt = nil
  }

  /// The minute's sync; false once stopped.
  private func tick() async -> Bool {
    guard started else { return false }
    syncAll()
    await refreshMembership(throttle: Self.membershipRecheck)
    return started
  }

  /// The app came back into view (focus): a sync unless one ran in the last 30 s.
  public func appBecameActive() async {
    syncAll(throttle: 30)
    await refreshMembership(throttle: Self.membershipRecheck)
  }

  /// The device is online again.
  public func networkBecameAvailable() {
    syncAll()
  }

  /// The cloud says the company changed (a Realtime signal on sync_signals).
  public func cloudSignalled() {
    schedule(after: 0.5)
  }

  /// Syncs now, at most once per `throttle` seconds.
  func syncAll(throttle: Double = 0) {
    let now = config.clock.now()
    if throttle > 0, let last = lastAll, now - last < throttle { return }
    lastAll = now
    schedule(after: 0)
  }

  /// Syncs after `delay` seconds; an earlier request wins.
  func schedule(after delay: Double) {
    guard started else { return }
    let clock = config.clock
    let at = clock.now() + delay
    if let current = scheduledAt, current <= at { return }
    scheduledTask?.cancel()
    scheduledAt = at
    scheduledTask = Task { [weak self] in
      do {
        try await clock.sleep(seconds: delay)
      } catch {
        return
      }
      guard let self else { return }
      await self.fire(at: at)
    }
  }

  private func fire(at: Double) async {
    guard scheduledAt == at else { return }
    scheduledAt = nil
    scheduledTask = nil
    _ = try? await sync()
  }

  // MARK: Status

  public var status: SyncStatus { statusValue }

  /// The status now, then each change of it.
  public func statusUpdates() -> AsyncStream<SyncStatus> {
    let (stream, continuation) = AsyncStream<SyncStatus>.makeStream(bufferingPolicy: .bufferingNewest(16))
    let id = nextStatusObserver
    nextStatusObserver += 1
    statusObservers[id] = continuation
    continuation.yield(statusValue)
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeStatusObserver(id) }
    }
    return stream
  }

  private func removeStatusObserver(_ id: Int) {
    statusObservers[id] = nil
  }

  func setStatus(_ change: (inout SyncStatus) -> Void) {
    var next = statusValue
    change(&next)
    guard next != statusValue else { return }
    statusValue = next
    for observer in statusObservers.values { observer.yield(next) }
  }

  /// Syncs finished since the engine was made (for tests of the timers).
  var syncsFinished: Int { finishedSyncs }
}
