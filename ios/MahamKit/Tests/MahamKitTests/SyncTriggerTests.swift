import Foundation
import Testing

@testable import MahamKit

/// After src/cloud/manager.test.ts.
@Suite("Sync: when to sync")
struct SyncTriggerTests {
  @Test("backs off from 2 s, doubling up to 5 min, ±20 %")
  func backoff() {
    #expect(SyncEngine.backoff(attempt: 1, random: 0.5) == 2)
    #expect(SyncEngine.backoff(attempt: 2, random: 0.5) == 4)
    #expect(SyncEngine.backoff(attempt: 3, random: 0.5) == 8)
    #expect(SyncEngine.backoff(attempt: 9, random: 0.5) == 300)
    #expect(SyncEngine.backoff(attempt: 30, random: 0.5) == 300)
    #expect(SyncEngine.backoff(attempt: 1, random: 0) == 1.6)
    #expect(SyncEngine.backoff(attempt: 1, random: 1) == 2.4)
  }

  func engine(_ cloud: FakeCloud, clock: ManualClock, writable: Set<String> = []) async throws -> SyncEngine {
    var configuration = SyncConfiguration()
    configuration.clock = clock
    configuration.random = { 0.5 }
    configuration.writableKinds = writable
    return try await downloadedEngine(cloud, configuration: configuration)
  }

  @Test("syncs on start, a second after a change here, and every minute")
  func schedule() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let clock = ManualClock()
    let engine = try await engine(cloud, clock: clock, writable: ["clients"])
    let before = await engine.syncsFinished
    await engine.start()
    #expect(await eventually { await engine.syncsFinished == before + 1 })
    try await engine.perform(group: [.put(table: "clients", record: record("c9", ["name": "New"]))])
    #expect(await eventually { clock.pending.contains(1) })
    clock.advance(0.9)
    try await Task.sleep(nanoseconds: 20_000_000)
    #expect(await engine.syncsFinished == before + 1)
    clock.advance(0.1)
    #expect(await eventually { await engine.syncsFinished == before + 2 })
    #expect(cloud.record(CO, "clients", "c9") != nil)
    // The minute's sync (the timer was set at the start: 1 s has gone by).
    #expect(await eventually { clock.pending.contains(59) })
    clock.advance(59)
    #expect(await eventually { await engine.syncsFinished == before + 3 })
    await engine.stop()
    #expect(await eventually { clock.pending.isEmpty })
  }

  @Test("a sync that may pass is tried again after 2 s, then 4 s")
  func retries() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let clock = ManualClock()
    let engine = try await engine(cloud, clock: clock)
    cloud.failNext("pullRecords", .server, count: 2)
    let before = await engine.syncsFinished
    await engine.start()
    #expect(await eventually { await engine.syncsFinished == before + 1 })
    #expect(await engine.status.phase == .error)
    #expect(await eventually { clock.pending.contains(2) })
    clock.advance(2)
    #expect(await eventually { await engine.syncsFinished == before + 2 })
    #expect(await eventually { clock.pending.contains(4) })
    clock.advance(4)
    #expect(await eventually { await engine.syncsFinished == before + 3 })
    #expect(await engine.status.phase == .idle)
    #expect(await engine.status.syncedOnce)
    await engine.stop()
  }

  @Test("a signal from the cloud syncs half a second later; an earlier request wins")
  func signal() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let clock = ManualClock()
    let engine = try await engine(cloud, clock: clock)
    let before = await engine.syncsFinished
    await engine.start()
    #expect(await eventually { await engine.syncsFinished == before + 1 })
    await engine.cloudSignalled()
    await engine.cloudSignalled()
    #expect(await eventually { clock.pending.contains(0.5) })
    clock.advance(0.5)
    #expect(await eventually { await engine.syncsFinished == before + 2 })
    try await Task.sleep(nanoseconds: 20_000_000)
    #expect(await engine.syncsFinished == before + 2)
    await engine.stop()
  }
}
