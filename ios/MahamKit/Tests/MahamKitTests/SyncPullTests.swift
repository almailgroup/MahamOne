import Foundation
import Synchronization
import Testing

@testable import MahamKit

/// What a test saw while a sync was under way.
final class Seen: Sendable {
  let values = Mutex<[String]>([])
  func note(_ value: String) { values.withLock { $0.append(value) } }
  var all: [String] { values.withLock { $0 } }
}

/// Records as stored here, without this device's own bookkeeping, to compare with the cloud.
func comparable(_ all: [String: [String: JSONValue]]) -> [String: [String: JSONValue]] {
  all.mapValues { $0.mapValues { $0.removing("contentMissing") } }
}

@Suite("Sync: reading")
struct SyncPullTests {
  func config(page: Int = 500, writable: Set<String> = [], now: TestNow? = nil) -> SyncConfiguration {
    var configuration = SyncConfiguration()
    configuration.pullPage = page
    configuration.writableKinds = writable
    if let now { configuration.now = { now.date } }
    return configuration
  }

  @Test("a first download brings every record page by page, the company record last")
  func firstDownload() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let seen = Seen()
    let engine = try await downloadedEngine(
      cloud, configuration: config(page: 4),
      wrap: { mirror, base in
        InterceptedAPI(base: base, afterPull: { _ in seen.note(mirror.record("companies", CO) == nil ? "no company" : "company") })
      })
    let mirror = engine.mirror
    // Pulled in pages; the company appeared only once everything else was here.
    #expect(seen.all.count >= 4)
    #expect(Set(seen.all) == ["no company"])
    #expect(comparable(mirror.everything()) == cloud.visible(to: OWNER))
    #expect(mirror.state.status == .ready)
    #expect(mirror.state.cursor == cloud.currentRev)
    #expect(mirror.outbox.isEmpty)
    // Every record's server version, and the company's base copy.
    for row in cloud.rows(CO) { #expect(mirror.rev(row.tbl, row.id)?.rev == row.rev) }
    #expect(mirror.rev("companies", CO)?.base == cloud.record(CO, "companies", CO))
    // Files arrive without their content: marked to download.
    #expect(mirror.record("attachments", "a-inv")?["contentMissing"] == 1)
    // Nothing comes back from the cloud with the cloud's private mark.
    #expect(mirror.record("attachments", "a-emp")?["_private"] == nil)
    // The copy survives a restart.
    let again = try Mirror.open(directory: mirror.directory)
    #expect(again.everything() == mirror.everything())
    #expect(again.state == mirror.state)
  }

  @Test("a first download moves the cursor up to purged_until_rev")
  func purgedCursor() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    cloud.addMember(CO, STAFF, .staff)
    // The last changes are of People's data, which staff don't see, and its delete was purged.
    cloud.seed(CO, "employees", record("e2", ["name": "Left"]))
    cloud.remove(CO, "employees", "e2")
    cloud.purgeMarkers(CO)
    let purged = cloud.currentRev
    let engine = try await downloadedEngine(cloud, user: STAFF, role: .staff)
    #expect(engine.mirror.state.cursor == purged)
    // So the next pull is an ordinary one, not a resync.
    let calls = cloud.calls.count
    try await engine.sync()
    #expect(!cloud.calls[calls...].contains { $0.hasSuffix("recordIds") })
  }

  @Test("changes from other devices arrive, deletes included, and the cursor counts tables it doesn't know")
  func incremental() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let engine = try await downloadedEngine(cloud, configuration: config(page: 3))
    let mirror = engine.mirror
    let changes = mirror.changes()
    let cursor = mirror.state.cursor
    for i in 0..<5 { cloud.seed(CO, "products", record("p\(i)", ["name": .string("Item \(i)"), "unitPrice": 1])) }
    cloud.seed(CO, "clients", record("c1", ["name": "Gulf Pearl Hotel – Salmiya"]))
    cloud.remove(CO, "documents", "d1")
    // A record of another company with an id of this one's, and a table of a newer version.
    cloud.seed(CO, "clients", record("c9", ["name": "Elsewhere"], company: "co-2"))
    cloud.seed(CO, "futureThings", record("f1"))
    let result = try await engine.sync()
    #expect(result.pulled == 9)
    #expect(mirror.count("products") == 5)
    #expect(mirror.record("clients", "c1")?["name"] == "Gulf Pearl Hotel – Salmiya")
    #expect(mirror.record("documents", "d1") == nil)
    #expect(mirror.rev("documents", "d1") == nil)
    #expect(mirror.record("clients", "c9") == nil)
    #expect(mirror.recordsById("futureThings").isEmpty)
    #expect(mirror.state.cursor > cursor)
    #expect(mirror.state.cursor == cloud.currentRev)
    #expect(mirror.outbox.isEmpty)
    // Screens heard of the pages.
    var iterator = changes.makeAsyncIterator()
    let first = await iterator.next()
    #expect(first?.tables.contains("products") == true)
  }

  @Test("a record with a change waiting here is never overwritten or deleted by a pull; the push then wins")
  func pendingWins() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let engine = try await downloadedEngine(cloud, configuration: config(writable: ["clients"]))
    let mirror = engine.mirror
    let cursor = mirror.state.cursor
    // Another device renames c1 and deletes c2...
    cloud.seed(CO, "clients", record("c1", ["name": "Their name"]))
    cloud.remove(CO, "clients", "c2")
    // ...while this one changed both.
    try await engine.perform(group: [.put(table: "clients", record: record("c1", ["name": "Gulf Pearl Hotel", "phone": "+965 2222 3333"]))])
    try await engine.perform(group: [.put(table: "clients", record: record("c2", ["name": "Salmiya Stores", "notes": "Still a customer"]))])
    let rows = try await cloud.client(OWNER).pullRecords(company: CO, since: cursor, limit: 500)
    #expect(try await engine.applyRows(rows, asked: nil) == .applied)
    #expect(mirror.record("clients", "c1")?["phone"] == "+965 2222 3333")
    #expect(mirror.record("clients", "c1")?["name"] == "Gulf Pearl Hotel")
    #expect(mirror.record("clients", "c2")?["notes"] == "Still a customer")
    #expect(mirror.state.cursor == cloud.currentRev)
    let result = try await engine.sync()
    #expect(cloud.record(CO, "clients", "c1")?["phone"] == "+965 2222 3333")
    #expect(cloud.record(CO, "clients", "c2")?["notes"] == "Still a customer")
    // The rename here replaced a newer one, and the change came back after a delete: both noted.
    #expect(result.conflicts == 2)
    #expect(Set(result.notes.map(\.id)) == ["c1", "c2"])
    #expect(mirror.outbox.isEmpty)
  }

  @Test("a full resync keeps only what the cloud still has (and unsent changes), then brings in the rest")
  func resync() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let engine = try await downloadedEngine(cloud, configuration: config(writable: ["clients"]))
    let mirror = engine.mirror
    // Long ago, another device deleted c3 and the cloud forgot the delete.
    cloud.remove(CO, "clients", "c3")
    cloud.seed(CO, "products", record("new-item", ["name": "New", "unitPrice": 1]))
    cloud.purgeMarkers(CO)
    // Meanwhile this device made a change it has not sent.
    cloud.offline = true
    try await engine.perform(group: [.put(table: "clients", record: record("mine", ["name": "Made here"]))])
    await #expect(throws: CloudError.self) { try await engine.sync() }
    cloud.offline = false
    // Pretend the device was last in sync long ago.
    try mirror.write { tx in tx.state.cursor = 1 }
    try await engine.sync()
    #expect(mirror.record("clients", "c3") == nil)
    #expect(mirror.record("clients", "mine") != nil)
    #expect(cloud.record(CO, "clients", "mine") != nil)
    #expect(mirror.record("products", "new-item") != nil)
    #expect(mirror.record("clients", "c1") != nil && mirror.record("clients", "c2") != nil)
    #expect(comparable(mirror.everything()) == cloud.visible(to: OWNER))
    // And the next sync is an ordinary one.
    let calls = cloud.calls.count
    try await engine.sync()
    #expect(!cloud.calls[calls...].contains { $0.hasSuffix("recordIds") })
  }

  @Test("a company larger than a page downloads even after deletes were purged")
  func downloadAfterPurge() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    for i in 0..<30 { cloud.seed(CO, "products", record("p\(i)", ["name": .string("Item \(i)")])) }
    for i in 0..<5 { cloud.remove(CO, "products", "p\(i * 3)") }
    cloud.purgeMarkers(CO)
    for i in 30..<34 { cloud.seed(CO, "products", record("p\(i)", ["name": .string("Item \(i)")])) }
    let purged = cloud.state.withLock { $0.companies[CO]?.purgedUntilRev ?? 0 }
    // The web stops at the second page here: pull_records refuses since < purged_until_rev.
    await #expect(throws: CloudError(.resync, "almail:resync")) {
      _ = try await cloud.client(OWNER).pullRecords(company: CO, since: 4, limit: 4)
    }
    let engine = try await downloadedEngine(cloud, configuration: config(page: 4))
    let mirror = engine.mirror
    #expect(mirror.state.status == .ready)
    #expect(comparable(mirror.everything()) == cloud.visible(to: OWNER))
    #expect(mirror.count("products") == 29)
    #expect(mirror.state.cursor >= purged)
    #expect(cloud.calls.contains("\(OWNER) recordsAfter"))
    // From here on, ordinary pulls.
    cloud.seed(CO, "products", record("p99"))
    cloud.remove(CO, "products", "p1")
    let calls = cloud.calls.count
    try await engine.sync()
    #expect(mirror.record("products", "p99") != nil)
    #expect(mirror.record("products", "p1") == nil)
    #expect(!cloud.calls[calls...].contains { $0.hasSuffix("recordsAfter") || $0.hasSuffix("recordIds") })
  }

  @Test("staff never hold payroll and people data")
  func privacy() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    cloud.addMember(CO, STAFF, .staff)
    let engine = try await downloadedEngine(cloud, user: STAFF, role: .staff)
    let mirror = engine.mirror
    for (table, id) in privateIds { #expect(mirror.record(table, id) == nil, "\(table) \(id)") }
    #expect(mirror.record("attachments", "a-inv") != nil)
    #expect(mirror.record("journals", "j-tr") != nil)
    #expect(mirror.record("complianceDocuments", "doc-co") != nil)
    // A page that has them anyway (asked for under another role) is filtered here too.
    let rows = [
      PulledRow(tbl: "employees", id: "e9", data: record("e9"), rev: 900, deleted: false),
      PulledRow(tbl: "attachments", id: "a9", data: record("a9", ["ownerId": "e9"]), rev: 901, deleted: false),
      PulledRow(tbl: "renewals", id: "r9", data: record("r9", ["employeeId": "e9"]), rev: 902, deleted: false),
      PulledRow(tbl: "activities", id: "x9", data: record("x9", ["entity": "costing"]), rev: 903, deleted: false),
      PulledRow(tbl: "clients", id: "c9", data: record("c9"), rev: 904, deleted: false),
    ]
    #expect(try await engine.applyRows(rows, asked: nil) == .applied)
    #expect(mirror.record("employees", "e9") == nil)
    #expect(mirror.record("attachments", "a9") == nil)
    #expect(mirror.record("renewals", "r9") == nil)
    #expect(mirror.record("activities", "x9") == nil)
    #expect(mirror.record("clients", "c9") != nil)
    #expect(mirror.state.cursor == 904)
  }

  @Test("a demotion takes payroll and people data off this device; a promotion brings it in again")
  func roles() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    cloud.addMember(CO, ACCOUNTANT, .accountant)
    let engine = try await downloadedEngine(cloud, user: ACCOUNTANT, role: .accountant)
    let mirror = engine.mirror
    for (table, id) in privateIds { #expect(mirror.record(table, id) != nil) }
    let cursor = mirror.state.cursor
    cloud.addMember(CO, ACCOUNTANT, .staff)
    try await engine.applyRole(.staff)
    for (table, id) in privateIds {
      #expect(mirror.record(table, id) == nil, "\(table) \(id)")
      #expect(mirror.rev(table, id) == nil)
    }
    #expect(mirror.record("clients", "c1") != nil)
    #expect(mirror.state.cursor == cursor)
    cloud.addMember(CO, ACCOUNTANT, .accountant)
    try await engine.applyRole(.accountant)
    #expect(mirror.state.cursor == 0)
    #expect(mirror.state.epoch == 1)
    try await engine.sync()
    for (table, id) in privateIds { #expect(mirror.record(table, id) != nil) }
  }

  @Test("a promotion brings in the people data even when a pull is under way")
  func promotionDuringPull() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    cloud.addMember(CO, STAFF, .staff)
    let noticed = Mutex(false)
    let holder = Mutex<SyncEngine?>(nil)
    let engine = try await downloadedEngine(
      cloud, user: STAFF, role: .staff,
      wrap: { _, base in
        InterceptedAPI(
          base: base,
          afterPull: { _ in
            guard let engine = holder.withLock({ $0 }), !noticed.withLock({ $0 }) else { return }
            noticed.withLock { $0 = true }
            cloud.addMember(CO, STAFF, .accountant)
            try? await engine.applyRole(.accountant)
          })
      })
    #expect(engine.mirror.record("employees", "e1") == nil)
    cloud.seed(CO, "products", record("p-new"))
    holder.withLock { $0 = engine }
    try await engine.sync()
    #expect(engine.mirror.record("employees", "e1") != nil)
    #expect(engine.mirror.record("products", "p-new") != nil)
  }

  @Test("a demotion leaves no people data, even with a page pulled before it")
  func demotionDuringPull() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    cloud.addMember(CO, ACCOUNTANT, .accountant)
    let armed = Mutex<SyncEngine?>(nil)
    let engine = try await downloadedEngine(
      cloud, user: ACCOUNTANT, role: .accountant,
      wrap: { _, base in
        InterceptedAPI(
          base: base,
          afterPull: { _ in
            guard let engine = armed.withLock({ e -> SyncEngine? in defer { e = nil }; return e }) else { return }
            cloud.addMember(CO, ACCOUNTANT, .staff)
            try? await engine.applyRole(.staff)
          })
      })
    cloud.seed(CO, "employees", record("e2", ["name": "New hire", "basicSalary": 500]))
    armed.withLock { $0 = engine }
    try await engine.sync()
    #expect(engine.mirror.record("employees", "e2") == nil)
    #expect(engine.mirror.record("employees", "e1") == nil)
  }

  @Test("asks what the server has every ten minutes, and the owner's limits every five")
  func featuresAndPermissions() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    cloud.set { $0.features = ["tables_v16", "super_admin"]; $0.permissions[OWNER] = ["books": "view"] }
    let now = TestNow()
    let engine = try await downloadedEngine(cloud, configuration: config(now: now))
    func count(_ method: String) -> Int { cloud.calls.filter { $0 == "\(OWNER) \(method)" }.count }
    #expect(count("serverFeatures") == 1)
    #expect(count("myPermissions") == 1)
    #expect(engine.mirror.state.features == ["tables_v16", "super_admin"])
    #expect(engine.mirror.state.permissions == ["books": "view"])
    now.advance(4 * 60)
    try await engine.sync()
    #expect(count("serverFeatures") == 1)
    #expect(count("myPermissions") == 1)
    now.advance(2 * 60)
    try await engine.sync()
    #expect(count("serverFeatures") == 1)
    #expect(count("myPermissions") == 2)
    now.advance(5 * 60)
    try await engine.sync()
    #expect(count("serverFeatures") == 2)
    // When it can't be asked, what was known stays.
    cloud.failNext("serverFeatures", .server)
    now.advance(11 * 60)
    try await engine.sync()
    #expect(engine.mirror.state.features == ["tables_v16", "super_admin"])
  }

  @Test("notices a new role, a new name, and a company this account has left")
  func membership() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let engine = try await downloadedEngine(cloud)
    await engine.apply(membership: [CloudCompany(id: CO, name: "Al Mail Group", role: .viewer)])
    #expect(engine.mirror.state.name == "Al Mail Group")
    #expect(engine.mirror.state.role == .viewer)
    #expect(engine.mirror.record("employees", "e1") == nil)
    await engine.apply(membership: [])
    #expect(engine.mirror.state.status == .removed)
    #expect(engine.mirror.state.removedReason == "access")
    // Its copy stays, read only, until the person decides; syncing stops.
    #expect(engine.mirror.record("clients", "c1") != nil)
    let calls = cloud.calls.count
    try await engine.sync()
    #expect(cloud.calls.count == calls)
  }

  @Test("stops syncing a company the person no longer belongs to")
  func notMember() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let engine = try await downloadedEngine(cloud)
    cloud.removeMember(CO, OWNER)
    await #expect(throws: CloudError.self) { try await engine.sync() }
    #expect(engine.mirror.state.status == .removed)
    #expect(engine.mirror.state.lastError == .notMember)
  }

  @Test("brings in the records of tables an older version didn't pull")
  func catchUp() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    cloud.seed(CO, "stockIssues", record("si1", ["status": "posted"]))
    let engine = try await downloadedEngine(cloud)
    let mirror = engine.mirror
    // As if this copy had been pulled by a version without stockIssues.
    try mirror.write { tx in
      tx.delete("stockIssues", "si1")
      tx.deleteRev("stockIssues", "si1")
      tx.state.tables = SyncTables.all.filter { $0 != "stockIssues" }
    }
    let cursor = mirror.state.cursor
    try await engine.sync()
    #expect(mirror.record("stockIssues", "si1") != nil)
    #expect(mirror.state.tables == SyncTables.all)
    #expect(mirror.state.cursor == cursor)
  }
}
