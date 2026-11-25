import Foundation
import Synchronization
import Testing

@testable import MahamKit

@Suite("Sync: writing")
struct SyncPushTests {
  func config(_ writable: Set<String>, rules: (any WriteRules)? = nil) -> SyncConfiguration {
    var configuration = SyncConfiguration()
    configuration.writableKinds = writable
    if let rules { configuration.rules = rules }
    return configuration
  }

  @Test("is switched off: kinds not listed are refused, and nothing is written")
  func gated() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let engine = try await downloadedEngine(cloud)
    #expect(engine.writableKinds.isEmpty)
    let mirror = engine.mirror
    let before = mirror.everything()
    await #expect(throws: SyncWriteError.notWritable("clients")) {
      try await engine.perform(group: [.put(table: "clients", record: record("c1", ["name": "Changed"]))])
    }
    // One kind listed doesn't let the other through: the action is refused whole.
    let partly = try await downloadedEngine(cloud, configuration: config(["clients"]))
    await #expect(throws: SyncWriteError.notWritable("documents")) {
      try await partly.perform(group: [
        .put(table: "clients", record: record("c1", ["name": "Changed"])),
        .delete(table: "documents", id: "d1"),
      ])
    }
    #expect(mirror.everything() == before)
    #expect(mirror.outbox.isEmpty)
    #expect(partly.mirror.record("clients", "c1")?["name"] == "Gulf Pearl Hotel")
    #expect(partly.mirror.outbox.isEmpty)
  }

  @Test("a copy kept for another account neither syncs nor takes changes")
  func otherAccount() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let mine = try await downloadedEngine(cloud, configuration: config(["clients"]))
    cloud.addMember(CO, STAFF, .staff)
    let theirs = SyncEngine(mirror: mine.mirror, api: cloud.client(STAFF), userId: STAFF, configuration: config(["clients"]))
    let calls = cloud.calls.count
    try await theirs.sync()
    #expect(cloud.calls.count == calls)
    await #expect(throws: SyncWriteError.self) {
      try await theirs.perform(group: [.put(table: "clients", record: record("c1", ["name": "X"]))])
    }
    #expect(mine.mirror.outbox.isEmpty)
    #expect(throws: MirrorError.missing) { try Mirror.open(directory: temporaryDirectory()) }
  }

  @Test("a record saved unchanged queues nothing (sameData), a delete of nothing neither")
  func unchanged() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let engine = try await downloadedEngine(cloud, configuration: config(["clients"]))
    let mirror = engine.mirror
    let same = try #require(mirror.record("clients", "c1"))
    #expect(try await engine.perform(group: [.put(table: "clients", record: same)]).queued == 0)
    #expect(try await engine.perform(group: [.delete(table: "clients", id: "nobody")]).queued == 0)
    #expect(mirror.outbox.isEmpty)
    // The web's sameData: a field now null where there was none is a change.
    #expect(try await engine.perform(group: [.put(table: "clients", record: same.setting("notes", .null))]).queued == 1)
    let outcome = try await engine.perform(group: [
      .put(table: "clients", record: same.setting("notes", "VIP")), .delete(table: "clients", id: "c2"),
    ])
    #expect(outcome.queued == 2)
    let entries = mirror.outbox
    #expect(entries.count == 3)
    #expect(entries.suffix(2).allSatisfy { $0.group == outcome.group })
    #expect(entries.last?.op == .delete)
    #expect(mirror.record("clients", "c2") == nil)
  }

  @Test("an action is one transaction: a refusal saves none of it")
  func atomic() async throws {
    struct NoVIPs: WriteRules {
      func refusal(state: SyncState, table: String, before: JSONValue?, after: JSONValue?, lookup: Privacy.Lookup) -> String? {
        after?["vip"] == .bool(true) ? "No VIPs." : nil
      }
    }
    let cloud = FakeCloud()
    seedCompany(cloud)
    let engine = try await downloadedEngine(cloud, configuration: config(["clients"], rules: NoVIPs()))
    await #expect(throws: SyncWriteError.refused("No VIPs.")) {
      try await engine.perform(group: [
        .put(table: "clients", record: record("c4", ["name": "First"])),
        .put(table: "clients", record: record("c5", ["vip": true])),
      ])
    }
    #expect(engine.mirror.record("clients", "c4") == nil)
    #expect(engine.mirror.outbox.isEmpty)
    // Records that aren't this company's are refused before anything is written.
    await #expect(throws: SyncWriteError.self) {
      try await engine.perform(group: [.put(table: "clients", record: record("c6", company: "co-2"))])
    }
    await #expect(throws: SyncWriteError.self) {
      try await engine.perform(group: [.put(table: "clients", record: ["companyId": .string(CO)])])
    }
  }

  @Test("viewers change nothing; staff stay out of accounting setup and People")
  func roleRules() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    cloud.addMember(CO, "user-viewer", .viewer)
    cloud.addMember(CO, STAFF, .staff)
    let kinds: Set<String> = ["clients", "accounts", "journals", "companies"]
    let viewer = try await downloadedEngine(cloud, user: "user-viewer", role: .viewer, configuration: config(kinds))
    await #expect(throws: SyncWriteError.refused("You can view this company but not change it.")) {
      try await viewer.perform(group: [.put(table: "clients", record: record("c1", ["name": "X"]))])
    }
    let staff = try await downloadedEngine(cloud, user: STAFF, role: .staff, configuration: config(kinds))
    #expect(try await staff.perform(group: [.put(table: "clients", record: record("c7"))]).queued == 1)
    await #expect(throws: SyncWriteError.self) {
      try await staff.perform(group: [.put(table: "accounts", record: record("acc-1"))])
    }
    await #expect(throws: SyncWriteError.self) {
      try await staff.perform(group: [.put(table: "journals", record: record("j9", ["kind": "payroll"]))])
    }
    #expect(try await staff.perform(group: [.put(table: "journals", record: record("j8", ["kind": "transfer"]))]).queued == 1)
    let company = try #require(staff.mirror.record("companies", CO))
    await #expect(throws: SyncWriteError.self) {
      try await staff.perform(group: [.put(table: "companies", record: company.setting("phone", "+965 1"))])
    }
    var counted = company
    counted.set("numbering", ["invoice": rule(6), "payment": rule(3)])
    #expect(try await staff.perform(group: [.put(table: "companies", record: counted)]).queued == 1)
  }

  @Test("pushes in batches of at most 200, owners first, a transaction together, each record as it is now")
  func batching() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let engine = try await downloadedEngine(cloud, configuration: config(["clients", "activities", "employees"]))
    let mirror = engine.mirror
    for i in 0..<198 { try await engine.perform(group: [.put(table: "clients", record: record("n\(i)", ["name": .string("Client \(i)")]))]) }
    // One transaction whose records would straddle the 200th place.
    try await engine.perform(group: [
      .put(table: "activities", record: record("act-new", ["entity": "client", "entityId": "n-g", "action": "created"])),
      .put(table: "employees", record: record("e7", ["name": "Fatima"])),
      .put(table: "clients", record: record("n-g", ["name": "Client of the group"])),
    ])
    for i in 200..<250 { try await engine.perform(group: [.put(table: "clients", record: record("n\(i)", ["name": .string("Client \(i)")]))]) }
    // Changed twice: sent once, as it is now.
    try await engine.perform(group: [.put(table: "clients", record: record("n7", ["name": "Client 7, renamed"]))])
    let cursor = mirror.state.cursor
    var result = SyncResult()
    try await engine.pushAll(&result)
    let pushes = cloud.pushes
    #expect(pushes.map(\.count) == [198, 53])
    #expect(result.pushed == 251)
    // The transaction waited for the next batch, whole.
    #expect(!pushes[0].contains { ["act-new", "e7", "n-g"].contains($0.id) })
    // In PUSH_ORDER: employees before clients before activities.
    let second = pushes[1].map(\.tbl)
    #expect(second.first == "employees")
    #expect(second.last == "activities")
    #expect(second.dropFirst().dropLast().allSatisfy { $0 == "clients" })
    // Each record once, as it is now.
    let sent: [PushChange] = pushes.flatMap { $0 }
    let n7: [PushChange] = sent.filter { $0.id == "n7" }
    #expect(n7.count == 1)
    #expect(n7.first?.data?["name"] == "Client 7, renamed")
    #expect(cloud.record(CO, "clients", "n7")?["name"] == "Client 7, renamed")
    // Confirmed: the outbox is empty and the server's revs are kept; the cursor stays.
    #expect(mirror.outbox.isEmpty)
    #expect(mirror.rev("clients", "n7")?.rev == cloud.rev(CO, "clients", "n7"))
    #expect(mirror.rev("employees", "e7")?.rev == cloud.rev(CO, "employees", "e7"))
    #expect(mirror.state.cursor == cursor)
    // The next pull brings them back, changing nothing here.
    try await engine.sync()
    #expect(mirror.state.cursor == cloud.currentRev)
    #expect(mirror.record("clients", "n7")?["name"] == "Client 7, renamed")
    #expect(mirror.outbox.isEmpty)
  }

  @Test("keeps a batch under 512 KB, and sends a removed record's delete with its base rev")
  func bytes() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let engine = try await downloadedEngine(cloud, configuration: config(["clients"]))
    let large = String(repeating: "x", count: 200 * 1024)
    for i in 0..<4 { try await engine.perform(group: [.put(table: "clients", record: record("big\(i)", ["notes": .string(large)]))]) }
    try await engine.perform(group: [.delete(table: "clients", id: "c3")])
    try await engine.sync()
    let pushes = cloud.pushes
    #expect(pushes.count == 2)
    #expect(pushes.map(\.count) == [2, 3])
    #expect(pushes.allSatisfy { batch in batch.map { SyncJSON.jsLength($0.json) }.reduce(0, +) <= 512 * 1024 })
    let all: [PushChange] = pushes.flatMap { $0 }
    let delete = try #require(all.first { $0.id == "c3" })
    #expect(delete.deleted)
    #expect(delete.baseRev != nil)
    #expect(delete.json["deleted"] == .bool(true))
    #expect(cloud.record(CO, "clients", "c3") == nil)
    #expect(engine.mirror.rev("clients", "c3") == nil)
  }

  @Test("parks a change the server refuses, with what was changed with it, and sends the rest")
  func parking() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let engine = try await downloadedEngine(cloud, configuration: config(["clients", "accounts"]))
    let mirror = engine.mirror
    // The server knows better: this person is staff now.
    cloud.addMember(CO, OWNER, .staff)
    let refused = try await engine.perform(group: [
      .put(table: "accounts", record: record("acc-1", ["name": "Renamed by staff"])),
      .put(table: "clients", record: record("x1", ["name": "Made with it"])),
    ])
    try await engine.perform(group: [.put(table: "clients", record: record("y1", ["name": "Allowed for staff"]))])
    let result = try await engine.sync()
    #expect(result.parked == 2)
    let parked = mirror.parkedEntries
    #expect(parked.map(\.id).sorted() == ["acc-1", "x1"])
    #expect(parked.allSatisfy { $0.error == "permission" && $0.group == refused.group })
    #expect(cloud.record(CO, "clients", "y1") != nil)
    #expect(cloud.record(CO, "clients", "x1") == nil)
    #expect(cloud.record(CO, "accounts", "acc-1") == nil)
    // Parked changes still win over the cloud's copy here.
    #expect(mirror.record("clients", "x1") != nil)

    // "Try again" after the role is put back.
    cloud.addMember(CO, OWNER, .owner)
    try await engine.retryParked()
    try await engine.sync()
    #expect(mirror.outbox.isEmpty)
    #expect(cloud.record(CO, "accounts", "acc-1") != nil)
  }

  @Test("“Undo my change” takes the record back as the cloud has it, and what was made with it")
  func discard() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let engine = try await downloadedEngine(cloud, configuration: config(["clients"]))
    let mirror = engine.mirror
    cloud.addMember(CO, OWNER, .viewer)
    try await engine.perform(group: [
      .put(table: "clients", record: record("c1", ["name": "Renamed"])),
      .put(table: "clients", record: record("new-1", ["name": "New"])),
    ])
    _ = try await engine.sync()
    #expect(mirror.parkedEntries.count == 2)
    // A record the cloud never had is deleted here only once agreed.
    #expect(try await engine.discardParked(table: "clients", id: "new-1") == .notInCloud)
    #expect(mirror.record("clients", "new-1") != nil)
    #expect(try await engine.discardParked(table: "clients", id: "c1") == .undone)
    #expect(mirror.record("clients", "c1")?["name"] == "Gulf Pearl Hotel")
    #expect(mirror.record("clients", "new-1") == nil)
    #expect(mirror.outbox.isEmpty)
  }

  @Test("keeps every change while offline, and on a server error, and sends them later")
  func retryable() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let engine = try await downloadedEngine(cloud, configuration: config(["clients"]))
    try await engine.perform(group: [.put(table: "clients", record: record("off", ["name": "Made offline"]))])
    cloud.offline = true
    await #expect(throws: CloudError.self) { try await engine.sync() }
    #expect(engine.mirror.pendingCount == 1)
    #expect(engine.mirror.state.lastError == .offline)
    cloud.offline = false
    cloud.failNext("pushRecords", .server)
    await #expect(throws: CloudError.self) { try await engine.sync() }
    #expect(engine.mirror.pendingCount == 1)
    try await engine.sync()
    #expect(engine.mirror.outbox.isEmpty)
    #expect(cloud.record(CO, "clients", "off") != nil)
    #expect(engine.mirror.state.lastError == nil)
  }

  // MARK: The company record

  @Test("is sent as the fields that changed; others' fields stay, both devices' changes are noted")
  func companyPatch() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let engine = try await downloadedEngine(cloud, configuration: config(["companies"]))
    let mirror = engine.mirror
    // Another device changes the phone and the website.
    var theirs = try #require(cloud.record(CO, "companies", CO))
    theirs.set("phone", "+965 2222 0000")
    theirs.set("website", "gulf.example")
    cloud.seed(CO, "companies", theirs)
    // This one, from its older copy, changes the phone and numbers an invoice.
    var mine = try #require(mirror.record("companies", CO))
    mine.set("phone", "+965 3333 0000")
    mine.set("numbering", ["invoice": rule(6), "payment": rule(3)])
    try await engine.perform(group: [.put(table: "companies", record: mine)])
    let result = try await engine.sync()
    let ops = try #require(cloud.patches.last)
    #expect(Set(ops.map { $0.path.joined(separator: ".") }) == ["phone", "numbering.invoice.next", "numbering.invoice.period"])
    #expect(ops.first { $0.path == ["phone"] }?.base == "")
    #expect(cloud.pushes.isEmpty)
    let cloudCopy = try #require(cloud.record(CO, "companies", CO))
    #expect(cloudCopy["phone"] == "+965 3333 0000")
    #expect(cloudCopy["website"] == "gulf.example")
    #expect(cloudCopy["numbering"]?["invoice"]?["next"] == 6)
    #expect(result.conflicts == 1)
    #expect(result.notes == [ConflictNote(table: "companies", id: CO, deleted: false, fields: [["phone"]])])
    // The merged copy came back; it is the base of later changes.
    #expect(mirror.record("companies", CO)?["website"] == "gulf.example")
    #expect(mirror.rev("companies", CO)?.base == cloudCopy)
    #expect(mirror.outbox.isEmpty)
    // Saved again unchanged: nothing to send.
    let calls = cloud.patches.count
    try await engine.perform(group: [.put(table: "companies", record: try #require(mirror.record("companies", CO)))])
    try await engine.sync()
    #expect(cloud.patches.count == calls)
  }

  @Test("lays this device's unsent changes over a newer copy from the cloud")
  func companyRebasedHere() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let engine = try await downloadedEngine(cloud, configuration: config(["companies"]))
    let mirror = engine.mirror
    let cursor = mirror.state.cursor
    try await engine.perform(group: [.put(table: "companies", record: try #require(mirror.record("companies", CO)).setting("website", "almail.example"))])
    cloud.seed(CO, "companies", try #require(cloud.record(CO, "companies", CO)).setting("phone", "+965 2222 0000"))
    _ = try await engine.applyRows(try await cloud.client(OWNER).pullRecords(company: CO, since: cursor, limit: 100), asked: nil)
    #expect(mirror.record("companies", CO)?["website"] == "almail.example")
    #expect(mirror.record("companies", CO)?["phone"] == "+965 2222 0000")
    try await engine.sync()
    #expect(cloud.record(CO, "companies", CO)?["website"] == "almail.example")
    #expect(cloud.record(CO, "companies", CO)?["phone"] == "+965 2222 0000")
  }

  @Test("lets staff number documents after the owner changed the company details")
  func staffCounters() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    cloud.addMember(CO, STAFF, .staff)
    let staff = try await downloadedEngine(cloud, user: STAFF, role: .staff, configuration: config(["companies"]))
    cloud.seed(CO, "companies", try #require(cloud.record(CO, "companies", CO)).setting("phone", "+965 2222 0000"))
    let company = try #require(staff.mirror.record("companies", CO))
    try await staff.perform(group: [.put(table: "companies", record: company.setting("numbering", ["invoice": rule(6), "payment": rule(3)]))])
    let result = try await staff.sync()
    #expect(result.parked == 0)
    #expect(staff.mirror.record("companies", CO)?["phone"] == "+965 2222 0000")
    #expect(cloud.record(CO, "companies", CO)?["numbering"]?["invoice"]?["next"] == 6)
  }

  @Test("on a server without patch_company: fetched, laid over, and sent whole")
  func companyLegacy() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let engine = try await downloadedEngine(cloud, configuration: config(["companies"]))
    cloud.set { $0.legacy = true }
    cloud.seed(CO, "companies", try #require(cloud.record(CO, "companies", CO)).setting("phone", "+965 2222 0000"))
    let mine = try #require(engine.mirror.record("companies", CO)).setting("website", "almail.example")
    try await engine.perform(group: [.put(table: "companies", record: mine)])
    try await engine.sync()
    #expect(cloud.record(CO, "companies", CO)?["phone"] == "+965 2222 0000")
    #expect(cloud.record(CO, "companies", CO)?["website"] == "almail.example")
    let whole = try #require(cloud.pushes.last?.first)
    #expect(whole.tbl == "companies" && whole.data?["phone"] == "+965 2222 0000")
    #expect(whole.baseRev == cloud.rows(CO, "companies").first.map { $0.rev - 1 })
    #expect(engine.mirror.outbox.isEmpty)
    #expect(engine.mirror.record("companies", CO)?["phone"] == "+965 2222 0000")
  }

  // MARK: Numbers

  @Test("takes numbers from the cloud's counter, never below this device's own")
  func reserve() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    let engine = try await downloadedEngine(cloud)
    #expect(await engine.reserveNumber(kind: "invoice", date: "2026-11-25", min: 4) == ReservedCounter(counter: 5, period: "2026"))
    #expect(await engine.reserveNumber(kind: "invoice", date: "2026-11-25", min: 9) == ReservedCounter(counter: 9, period: "2026"))
    #expect(cloud.record(CO, "companies", CO)?["numbering"]?["invoice"]?["next"] == 10)
    // A date in an earlier period, or a kind without a rule: numbered on the device.
    #expect(await engine.reserveNumber(kind: "invoice", date: "2025-12-31", min: 1) == nil)
    #expect(await engine.reserveNumber(kind: "quote", date: "2026-11-25", min: 1) == nil)
    // Errors are answered with nil, too.
    cloud.failNext("reserveNumber", .server)
    #expect(await engine.reserveNumber(kind: "invoice", date: "2026-11-25", min: 1) == nil)
  }

  @Test("skips the cloud's counter offline, for a viewer, and after three seconds")
  func reserveSkipped() async throws {
    let cloud = FakeCloud()
    seedCompany(cloud)
    cloud.addMember(CO, "user-viewer", .viewer)
    let viewer = try await downloadedEngine(cloud, user: "user-viewer", role: .viewer)
    #expect(await viewer.reserveNumber(kind: "invoice", date: "2026-11-25", min: 1) == nil)
    var offline = SyncConfiguration()
    offline.isOnline = { false }
    let away = try await downloadedEngine(cloud, configuration: offline)
    #expect(await away.reserveNumber(kind: "invoice", date: "2026-11-25", min: 1) == nil)
    #expect(!cloud.calls.contains { $0.hasSuffix("reserveNumber") })

    let clock = ManualClock()
    var timed = SyncConfiguration()
    timed.clock = clock
    let slow = try await downloadedEngine(cloud, configuration: timed)
    cloud.set { $0.reserveDelay = 30 }
    let answer = Task { await slow.reserveNumber(kind: "invoice", date: "2026-11-25", min: 1) }
    #expect(await eventually { clock.pending.contains(3) })
    clock.advance(3)
    #expect(await answer.value == nil)
  }
}
