import Foundation
import Synchronization

@testable import MahamKit

/// An in-memory cloud with the database's rules, after src/cloud/testing/fake-cloud.ts:
/// one global rev sequence, hard deletes with markers, purged markers
/// (purged_until_rev), conflicts as notes, the numbering merge, roles and
/// private data (row-level security). Each `client(user)` is one person's view.
final class FakeCloud: Sendable {
  struct Row: Sendable {
    var company: String
    var tbl: String
    var id: String
    var data: JSONValue
    var rev: Int64
  }

  struct Marker: Sendable {
    var company: String
    var tbl: String
    var id: String
    var rev: Int64
    var isPrivate: Bool
  }

  struct State: Sendable {
    var companies: [String: (name: String, purgedUntilRev: Int64)] = [:]
    var members: [String: [String: MemberRole]] = [:]
    var records: [String: Row] = [:]
    var markers: [String: Marker] = [:]
    var rev: Int64 = 0
    var calls: [String] = []
    var pushes: [[PushChange]] = []
    var patches: [[CompanyOp]] = []
    var offline = false
    var failures: [String: [CloudError]] = [:]
    /// A server without patch_company, reserve_number and server_features.
    var legacy = false
    var features: [String] = ["tables_v16"]
    var permissions: [String: [String: String]] = [:]
    /// Seconds reserve_number waits before answering.
    var reserveDelay: Double = 0
  }

  let state = Mutex(State())

  func key(_ company: String, _ tbl: String, _ id: String) -> String { "\(company)/\(tbl)/\(id)" }

  // MARK: Setting up

  func addCompany(_ id: String, name: String = "Al Mail Trading", owner: String) {
    state.withLock {
      $0.companies[id] = (name, 0)
      $0.members[id, default: [:]][owner] = .owner
    }
  }

  func addMember(_ company: String, _ user: String, _ role: MemberRole) {
    state.withLock { $0.members[company, default: [:]][user] = role }
  }

  func removeMember(_ company: String, _ user: String) {
    state.withLock { $0.members[company]?[user] = nil }
  }

  /// A record written straight into the server (as another device's push would).
  @discardableResult
  func seed(_ company: String, _ tbl: String, _ data: JSONValue) -> Int64 {
    state.withLock { s in
      guard let id = data["id"]?.string else { return 0 }
      s.rev += 1
      s.records[key(company, tbl, id)] = Row(company: company, tbl: tbl, id: id, data: data, rev: s.rev)
      s.markers[key(company, tbl, id)] = nil
      return s.rev
    }
  }

  /// A record deleted straight in the server, with its marker.
  func remove(_ company: String, _ tbl: String, _ id: String) {
    state.withLock { s in
      let k = key(company, tbl, id)
      guard let row = s.records.removeValue(forKey: k) else { return }
      s.rev += 1
      let isPrivate = Privacy.isPrivateRecord(tbl, row.data, lookup: Self.lookup(s, company))
      s.markers[k] = Marker(company: company, tbl: tbl, id: id, rev: s.rev, isPrivate: isPrivate)
    }
  }

  /// Forgets every deletion marker, as the daily job does after 30 days.
  func purgeMarkers(_ company: String) {
    state.withLock { s in
      var purged = s.companies[company]?.purgedUntilRev ?? 0
      for (k, marker) in s.markers where marker.company == company {
        purged = max(purged, marker.rev)
        s.markers[k] = nil
      }
      s.companies[company]?.purgedUntilRev = purged
    }
  }

  func failNext(_ method: String, _ code: CloudErrorCode, count: Int = 1) {
    state.withLock { s in
      for _ in 0..<count { s.failures[method, default: []].append(CloudError(code, "almail:\(code.rawValue)")) }
    }
  }

  var offline: Bool {
    get { state.withLock { $0.offline } }
    set { state.withLock { $0.offline = newValue } }
  }

  func set(_ change: (inout State) -> Void) { state.withLock { change(&$0) } }

  func record(_ company: String, _ tbl: String, _ id: String) -> JSONValue? {
    state.withLock { $0.records[key(company, tbl, id)]?.data }
  }

  func rev(_ company: String, _ tbl: String, _ id: String) -> Int64? {
    state.withLock { $0.records[key(company, tbl, id)]?.rev }
  }

  func rows(_ company: String, _ tbl: String? = nil) -> [Row] {
    state.withLock { s in s.records.values.filter { $0.company == company && (tbl == nil || $0.tbl == tbl) } }
  }

  var calls: [String] { state.withLock { $0.calls } }
  var pushes: [[PushChange]] { state.withLock { $0.pushes } }
  var patches: [[CompanyOp]] { state.withLock { $0.patches } }
  var currentRev: Int64 { state.withLock { $0.rev } }

  func client(_ user: String) -> FakeClient { FakeClient(cloud: self, user: user) }

  // MARK: The rules

  static func lookup(_ s: State, _ company: String) -> Privacy.Lookup {
    { tbl, id in s.records["\(company)/\(tbl)/\(id)"]?.data }
  }

  static func role(_ s: State, _ company: String, _ user: String) -> MemberRole? { s.members[company]?[user] }

  static func canRead(_ s: State, _ company: String, _ user: String, _ tbl: String, _ data: JSONValue) -> Bool {
    guard let role = role(s, company, user) else { return false }
    if Roles.canSeePeople(role) { return true }
    return !Privacy.isPrivateRecord(tbl, data, lookup: lookup(s, company))
  }

  static func canWrite(_ s: State, _ company: String, _ user: String, _ tbl: String, _ data: JSONValue) -> Bool {
    guard let role = role(s, company, user) else { return false }
    switch role {
    case .owner, .admin, .accountant: return true
    case .viewer: return false
    case .staff:
      if Privacy.isPrivateRecord(tbl, data, lookup: lookup(s, company)) { return false }
      if tbl == "journals" {
        return Roles.staffJournalKinds.contains(data["kind"]?.string ?? "")
      }
      return Roles.staffTables.contains(tbl)
    }
  }

  func begin(_ user: String, _ method: String) throws {
    try state.withLock { s in
      s.calls.append("\(user) \(method)")
      if s.offline { throw CloudError(.offline, "Failed to fetch") }
      if var queued = s.failures[method], !queued.isEmpty {
        let error = queued.removeFirst()
        s.failures[method] = queued
        throw error
      }
    }
  }

  static func member(_ s: State, _ company: String, _ user: String) throws -> MemberRole {
    guard let role = role(s, company, user) else { throw CloudError(.notMember, "almail:not_member") }
    return role
  }

  static func applyChange(_ s: inout State, _ company: String, _ user: String, _ role: MemberRole, _ change: PushChange)
    throws -> PushResult
  {
    let k = "\(company)/\(change.tbl)/\(change.id)"
    let old = s.records[k]
    let visibleOld = old.flatMap { canRead(s, company, user, $0.tbl, $0.data) ? $0 : nil }
    let marker = s.markers[k]
    let base = change.baseRev ?? 0
    guard let data = change.data else {
      // Never stored, or hidden from this person: nothing to do.
      guard let visibleOld else { return PushResult(tbl: change.tbl, id: change.id, rev: marker?.rev, conflict: false) }
      if change.tbl == "companies" || !canWrite(s, company, user, change.tbl, visibleOld.data) {
        throw CloudError(.permission, "almail:permission You cannot delete this record.")
      }
      let isPrivate = Privacy.isPrivateRecord(change.tbl, visibleOld.data, lookup: lookup(s, company))
      s.records[k] = nil
      s.rev += 1
      s.markers[k] = Marker(company: company, tbl: change.tbl, id: change.id, rev: s.rev, isPrivate: isPrivate)
      return PushResult(tbl: change.tbl, id: change.id, rev: s.rev, conflict: visibleOld.rev > base)
    }
    if SyncJSON.jsLength(data) > 1_048_576 { throw CloudError(.tooLarge, "almail:too_large") }
    if data["id"] != .string(change.id)
      || (change.tbl == "companies" ? change.id != company : data["companyId"] != .string(company))
    {
      throw CloudError(.invalid, "almail:invalid")
    }
    if old != nil && visibleOld == nil { throw CloudError(.permission, "almail:permission") }
    if let old, !canWrite(s, company, user, change.tbl, old.data) { throw CloudError(.permission, "almail:permission") }
    if !canWrite(s, company, user, change.tbl, data) { throw CloudError(.permission, "almail:permission") }
    if change.tbl == "companies" && role == .staff {
      guard let old, Roles.staffCompanyChangeOk(old.data, data) else {
        throw CloudError(.permission, "almail:permission")
      }
    }
    var stored = data
    if change.tbl == "companies", let old, let numbering = CompanyPatch.mergeNumbering(old.data["numbering"], data["numbering"]) {
      stored.set("numbering", numbering)
    }
    s.rev += 1
    s.records[k] = Row(company: company, tbl: change.tbl, id: change.id, data: stored, rev: s.rev)
    s.markers[k] = nil
    let conflict =
      (old.map { $0.rev > base && !SyncJSON.sameData($0.data, data) } ?? false)
      || (old == nil && (marker.map { $0.rev > base } ?? false))
    return PushResult(tbl: change.tbl, id: change.id, rev: s.rev, conflict: conflict)
  }
}

/// One person's view of the fake cloud.
struct FakeClient: CloudAPI {
  let cloud: FakeCloud
  let user: String

  func myCompanies() async throws -> [CloudCompany] {
    try cloud.begin(user, "myCompanies")
    return cloud.state.withLock { s in
      s.companies.compactMap { id, company in
        FakeCloud.role(s, id, user).map { CloudCompany(id: id, name: company.name, role: $0) }
      }
    }
  }

  func pushRecords(company: String, changes: [PushChange]) async throws -> [PushResult] {
    try cloud.begin(user, "pushRecords")
    return try cloud.state.withLock { s in
      s.pushes.append(changes)
      let role = try FakeCloud.member(s, company, user)
      // All or nothing, like one database transaction.
      var copy = s
      let results = try changes.map { try FakeCloud.applyChange(&copy, company, user, role, $0) }
      copy.calls = s.calls
      copy.pushes = s.pushes
      s = copy
      return results
    }
  }

  func pullRecords(company: String, since: Int64, limit: Int) async throws -> [PulledRow] {
    try cloud.begin(user, "pullRecords")
    return try cloud.state.withLock { s in
      let role = try FakeCloud.member(s, company, user)
      var rows: [PulledRow] = s.records.values.filter {
        $0.company == company && $0.rev > since && FakeCloud.canRead(s, company, user, $0.tbl, $0.data)
      }.map { PulledRow(tbl: $0.tbl, id: $0.id, data: $0.data, rev: $0.rev, deleted: false) }
      for marker in s.markers.values where marker.company == company && marker.rev > since {
        if marker.isPrivate && !Roles.canSeePeople(role) { continue }
        rows.append(PulledRow(tbl: marker.tbl, id: marker.id, data: nil, rev: marker.rev, deleted: true))
      }
      rows.sort { $0.rev < $1.rev }
      let purged = s.companies[company]?.purgedUntilRev ?? 0
      if since > 0 && since < purged { throw CloudError(.resync, "almail:resync") }
      return Array(rows.prefix(min(max(limit, 1), 1000)))
    }
  }

  func recordIds(company: String, after: RecordKey?, limit: Int, table: String?) async throws -> [RecordKey] {
    try cloud.begin(user, "recordIds")
    return try cloud.state.withLock { s in
      _ = try FakeCloud.member(s, company, user)
      let less: (RecordKey, RecordKey) -> Bool = { a, b in
        a.tbl == b.tbl ? SyncJSON.jsLess(a.id, b.id) : SyncJSON.jsLess(a.tbl, b.tbl)
      }
      let keys = s.records.values
        .filter { $0.company == company && (table == nil || $0.tbl == table) }
        .filter { FakeCloud.canRead(s, company, user, $0.tbl, $0.data) }
        .map { RecordKey(tbl: $0.tbl, id: $0.id) }
        .sorted(by: less)
      let start = after.map { after in keys.firstIndex { less(after, $0) } ?? keys.count } ?? 0
      return Array(keys[start...].prefix(limit))
    }
  }

  func syncInfo(company: String) async throws -> SyncInfo {
    try cloud.begin(user, "syncInfo")
    return try cloud.state.withLock { s in
      _ = try FakeCloud.member(s, company, user)
      let visible = s.records.values.filter {
        $0.company == company && FakeCloud.canRead(s, company, user, $0.tbl, $0.data)
      }
      return SyncInfo(
        purgedUntilRev: s.companies[company]?.purgedUntilRev ?? 0, recordCount: visible.count,
        maxRev: visible.map(\.rev).max() ?? 0)
    }
  }

  func getRecord(company: String, table: String, id: String) async throws -> CloudRecord? {
    try cloud.begin(user, "getRecord")
    return try cloud.state.withLock { s in
      _ = try FakeCloud.member(s, company, user)
      guard let row = s.records["\(company)/\(table)/\(id)"], FakeCloud.canRead(s, company, user, table, row.data)
      else { return nil }
      return CloudRecord(data: row.data, rev: row.rev)
    }
  }

  // A select of public.records under row-level security.
  func recordsAfter(company: String, since: Int64, limit: Int) async throws -> [PulledRow] {
    try cloud.begin(user, "recordsAfter")
    return try cloud.state.withLock { s in
      _ = try FakeCloud.member(s, company, user)
      return Array(
        s.records.values
          .filter { $0.company == company && $0.rev > since && FakeCloud.canRead(s, company, user, $0.tbl, $0.data) }
          .sorted { $0.rev < $1.rev }
          .prefix(limit)
          .map { PulledRow(tbl: $0.tbl, id: $0.id, data: $0.data, rev: $0.rev, deleted: false) })
    }
  }

  // Mirrors public.patch_company.
  func patchCompany(company: String, ops: [CompanyOp]) async throws -> CompanyPatchResult? {
    try cloud.begin(user, "patchCompany")
    return try cloud.state.withLock { s in
      if s.legacy { return nil }
      s.patches.append(ops)
      let role = try FakeCloud.member(s, company, user)
      let k = "\(company)/companies/\(company)"
      guard let old = s.records[k] else { return nil }
      if ops.count > 500 || ops.contains(where: { $0.path.first == "id" || $0.path.isEmpty || $0.path.count > 8 }) {
        throw CloudError(.invalid, "almail:invalid")
      }
      if !FakeCloud.canWrite(s, company, user, "companies", old.data) { throw CloudError(.permission, "almail:permission") }
      let (data, conflicts) = CompanyPatch.rebaseCompany(current: old.data, ops: ops)
      if role == .staff && !Roles.staffCompanyChangeOk(old.data, data) {
        throw CloudError(.permission, "almail:permission")
      }
      if SyncJSON.sameData(data, old.data) { return CompanyPatchResult(rev: old.rev, conflicts: conflicts) }
      s.rev += 1
      s.records[k] = FakeCloud.Row(company: company, tbl: "companies", id: company, data: data, rev: s.rev)
      return CompanyPatchResult(rev: s.rev, conflicts: conflicts)
    }
  }

  // Mirrors public.reserve_number.
  func reserveNumber(company: String, kind: String, date: String, min: Int64) async throws -> ReservedCounter? {
    try cloud.begin(user, "reserveNumber")
    let delay = cloud.state.withLock { $0.reserveDelay }
    if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
    return try cloud.state.withLock { s in
      if s.legacy { return nil }
      _ = try FakeCloud.member(s, company, user)
      let k = "\(company)/companies/\(company)"
      guard let row = s.records[k] else { return nil }
      if !FakeCloud.canWrite(s, company, user, "companies", row.data) { throw CloudError(.permission, "almail:permission") }
      guard case .some(.object(var rule)) = row.data["numbering"]?[kind] else { return nil }
      let reset = rule["reset"]?.string ?? "never"
      let period = reset == "yearly" ? String(date.prefix(4)) : reset == "monthly" ? String(date.prefix(7)) : ""
      let rulePeriod = rule["period"]?.string ?? ""
      var counter = Swift.max(1, Int64(rule["next"]?.double ?? 1))
      if reset != "never" && rulePeriod != "" && period != rulePeriod {
        if SyncJSON.jsLess(period, rulePeriod) { return nil }
        counter = 1
      }
      counter = Swift.max(counter, min, 1)
      rule["next"] = .number(Double(counter + 1))
      rule["period"] = .string(period)
      var data = row.data
      var numbering = data["numbering"]?.object ?? [:]
      numbering[kind] = .object(rule)
      data.set("numbering", .object(numbering))
      s.rev += 1
      s.records[k] = FakeCloud.Row(company: company, tbl: "companies", id: company, data: data, rev: s.rev)
      return ReservedCounter(counter: Int(counter), period: period)
    }
  }

  func serverFeatures(company: String) async throws -> [String] {
    try cloud.begin(user, "serverFeatures")
    return try cloud.state.withLock { s in
      _ = try FakeCloud.member(s, company, user)
      return s.legacy ? [] : s.features
    }
  }

  func myPermissions(company: String) async throws -> MyPermissions? {
    try cloud.begin(user, "myPermissions")
    return try cloud.state.withLock { s in
      let role = try FakeCloud.member(s, company, user)
      guard s.features.contains("super_admin") else { return nil }
      return MyPermissions(apps: s.permissions[user] ?? [:], approver: role == .owner, owner: role == .owner)
    }
  }
}

/// A view of the cloud that lets a test act while a pull is on its way.
struct InterceptedAPI: CloudAPI {
  let base: any CloudAPI
  /// Runs after the server answered a pull, before the page reaches the engine.
  var afterPull: @Sendable (_ count: Int) async -> Void = { _ in }
  var beforePush: @Sendable ([PushChange]) async -> Void = { _ in }

  func myCompanies() async throws -> [CloudCompany] { try await base.myCompanies() }
  func pushRecords(company: String, changes: [PushChange]) async throws -> [PushResult] {
    await beforePush(changes)
    return try await base.pushRecords(company: company, changes: changes)
  }
  func pullRecords(company: String, since: Int64, limit: Int) async throws -> [PulledRow] {
    let rows = try await base.pullRecords(company: company, since: since, limit: limit)
    await afterPull(rows.count)
    return rows
  }
  func recordIds(company: String, after: RecordKey?, limit: Int, table: String?) async throws -> [RecordKey] {
    try await base.recordIds(company: company, after: after, limit: limit, table: table)
  }
  func syncInfo(company: String) async throws -> SyncInfo { try await base.syncInfo(company: company) }
  func getRecord(company: String, table: String, id: String) async throws -> CloudRecord? {
    try await base.getRecord(company: company, table: table, id: id)
  }
  func recordsAfter(company: String, since: Int64, limit: Int) async throws -> [PulledRow] {
    try await base.recordsAfter(company: company, since: since, limit: limit)
  }
  func patchCompany(company: String, ops: [CompanyOp]) async throws -> CompanyPatchResult? {
    try await base.patchCompany(company: company, ops: ops)
  }
  func reserveNumber(company: String, kind: String, date: String, min: Int64) async throws -> ReservedCounter? {
    try await base.reserveNumber(company: company, kind: kind, date: date, min: min)
  }
  func serverFeatures(company: String) async throws -> [String] { try await base.serverFeatures(company: company) }
  func myPermissions(company: String) async throws -> MyPermissions? { try await base.myPermissions(company: company) }
}

/// A clock that only moves when the test moves it.
final class ManualClock: SyncClock {
  private struct Sleeper {
    var at: Double
    var continuation: CheckedContinuation<Void, Error>
  }

  private let inner = Mutex<(now: Double, sleepers: [Int: Sleeper], next: Int)>((0, [:], 0))

  func now() -> Double { inner.withLock { $0.now } }

  func sleep(seconds: Double) async throws {
    let id = inner.withLock { s -> Int in
      s.next += 1
      return s.next
    }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let due = inner.withLock { s -> Bool in
          if seconds <= 0 { return true }
          s.sleepers[id] = Sleeper(at: s.now + seconds, continuation: continuation)
          return false
        }
        if due { continuation.resume() }
      }
    } onCancel: {
      let sleeper = inner.withLock { $0.sleepers.removeValue(forKey: id) }
      sleeper?.continuation.resume(throwing: CancellationError())
    }
  }

  /// Pending sleeps, as seconds from now.
  var pending: [Double] {
    inner.withLock { s in s.sleepers.values.map { $0.at - s.now }.sorted() }
  }

  /// Moves time on, waking every sleep that is due.
  func advance(_ seconds: Double) {
    let due = inner.withLock { s -> [CheckedContinuation<Void, Error>] in
      s.now += seconds
      let ready = s.sleepers.filter { $0.value.at <= s.now }
      for id in ready.keys { s.sleepers[id] = nil }
      return ready.values.sorted { $0.at < $1.at }.map(\.continuation)
    }
    for continuation in due { continuation.resume() }
  }
}
