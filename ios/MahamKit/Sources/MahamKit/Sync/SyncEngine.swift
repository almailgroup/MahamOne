import Foundation
import Synchronization

/// How far an upload or a download has got, for the progress bar.
public struct SyncProgress: Sendable, Equatable {
  public enum Kind: String, Sendable { case upload, download }
  public var kind: Kind
  public var done: Int
  public var total: Int
}

/// A change the cloud took over a newer version it had (the push always
/// wins). The web logs these as a `sync_conflict` activity; the native app
/// will once activities are writable.
public struct ConflictNote: Sendable, Equatable {
  public var table: String
  public var id: String
  /// It was a delete that replaced the newer version.
  public var deleted: Bool
  /// The company record: the settings both devices changed (this device's values were kept).
  public var fields: [[String]]
}

public struct SyncResult: Sendable, Equatable {
  public var pushed = 0
  public var pulled = 0
  public var conflicts = 0
  public var parked = 0
  public var notes: [ConflictNote] = []

  public init() {}
}

/// What a sync engine is doing, for the screens.
public struct SyncStatus: Sendable, Equatable {
  public enum Phase: String, Sendable { case idle, syncing, offline, error }
  public var phase: Phase = .idle
  public var error: CloudErrorCode?
  public var message: String?
  public var progress: SyncProgress?
  /// Caught up with the cloud at least once since the engine started.
  public var syncedOnce = false
}

/// Uploads an attachment's content to Storage before its record is pushed
/// (`uploadContent`): returns where it is, or nil when this device doesn't
/// have the content. Not provided yet: until it is, an attachment with
/// content here waits in the outbox, unsent.
public protocol AttachmentUploader: Sendable {
  func upload(companyId: String, attachment: JSONValue) async throws -> (storagePath: String, contentHash: String)?
}

/// Time for the engine's timers: real time in the app, a hand-moved clock in tests.
public protocol SyncClock: Sendable {
  /// Seconds on a scale that only goes forward.
  func now() -> Double
  func sleep(seconds: Double) async throws
}

public struct SystemSyncClock: SyncClock {
  public init() {}
  public func now() -> Double { ProcessInfo.processInfo.systemUptime }
  public func sleep(seconds: Double) async throws {
    try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
  }
}

public struct SyncConfiguration: Sendable {
  /// The record kinds this app may write. Empty until each kind's rules are
  /// ported and pass the web's tests: until then the engine reads only.
  public var writableKinds: Set<String> = []
  /// The rules a write is refused by before it is made (the web's `refuse*`).
  public var rules: any WriteRules = OutboxRules()
  /// Records per pull (the server gives at most 1000; tests use small pages).
  public var pullPage = 500
  public var clock: any SyncClock = SystemSyncClock()
  /// The wall clock, for the times the engine notes.
  public var now: @Sendable () -> Date = { Date() }
  public var random: @Sendable () -> Double = { Double.random(in: 0..<1) }
  /// Whether the device has a connection (reserve_number is skipped offline).
  public var isOnline: @Sendable () -> Bool = { true }
  public var uploader: (any AttachmentUploader)?
  public var onProgress: (@Sendable (SyncProgress) -> Void)?
  /// Seconds between syncs while the app is open.
  public var interval: Double = 60

  public init() {}
}

/// The sync engine of one company kept in the cloud (src/cloud/sync.ts and
/// manager.ts): sends what is queued in the outbox, then brings in what
/// changed in the cloud since the last rev seen, page by page, each page in
/// one transaction of the mirror.
///
/// Nothing is lost: an outbox entry is removed only once the server has
/// confirmed that exact change; a change the server refuses is parked with
/// its reason; a record with unsent changes here is never overwritten or
/// deleted by what comes from the cloud (the company record is laid over
/// instead, see CompanyPatch). Writing is switched off until record kinds
/// are listed in `SyncConfiguration.writableKinds`.
public actor SyncEngine {
  public nonisolated let mirror: Mirror
  public nonisolated let companyId: String
  public nonisolated let userId: String
  nonisolated let api: any CloudAPI
  nonisolated let config: SyncConfiguration

  static let pushBatch = 200
  static let pushBytes = 512 * 1024
  static let idPage = 1000
  static let catchUpPage = 100
  static let catchUpAtOnce = 8
  static let featuresRecheck: TimeInterval = 10 * 60
  static let permissionsRecheck: TimeInterval = 5 * 60
  static let membershipRecheck: Double = 5 * 60
  static let reserveTimeout: Double = 3
  /// Pauses before a refused file is sent again by itself, after each refusal.
  static let fileRetry: [TimeInterval] = [0, 60, 5 * 60, 15 * 60, 60 * 60, 180 * 60, 360 * 60]
  /// Changes made in more records at once than this are sent one by one.
  static let changeGroupLimit = 20

  // Scheduling (see SyncEngine+Triggers).
  var running: Task<Result<SyncResult, CloudError>, Never>?
  var again = false
  var started = false
  var scheduledAt: Double?
  var scheduledTask: Task<Void, Never>?
  var tickTask: Task<Void, Never>?
  var failures = 0
  var lastAll: Double?
  var lastMembership: Double?
  var statusValue = SyncStatus()
  var statusObservers: [Int: AsyncStream<SyncStatus>.Continuation] = [:]
  var nextStatusObserver = 0
  /// Syncs finished (successfully or not), for tests of the timers.
  var finishedSyncs = 0

  /// `userId`: the signed-in account. A mirror kept for another account on
  /// this device doesn't sync, and nothing is written to it.
  public init(mirror: Mirror, api: any CloudAPI, userId: String, configuration: SyncConfiguration = SyncConfiguration()) {
    self.mirror = mirror
    self.companyId = mirror.companyId
    self.userId = userId
    self.api = api
    self.config = configuration
  }

  /// Brings a company from the cloud to this device: a new mirror in
  /// `directory` (an earlier copy there is replaced), filled by the first sync.
  public static func startDownload(
    _ company: CloudCompany, userId: String, api: any CloudAPI, directory: URL, now: Date = Date()
  ) async throws -> Mirror {
    let info: SyncInfo
    do {
      info = try await api.syncInfo(company: company.id)
    } catch {
      throw CloudError.from(error)
    }
    let state = SyncState(
      companyId: company.id, userId: userId, role: company.role, status: .downloading, name: company.name,
      linkedAt: now, total: info.recordCount)
    return try Mirror.create(directory: directory, state: state)
  }

  public nonisolated var writableKinds: Set<String> { config.writableKinds }

  // MARK: One sync

  /// Sends what is queued, then brings in what changed. Throws a
  /// `CloudError` when it can't. A sync already under way is waited for
  /// (and another one follows it).
  @discardableResult
  public func sync() async throws -> SyncResult {
    if let running {
      again = true
      return try await running.value.get()
    }
    setStatus { $0.phase = .syncing }
    let task = Task { await self.runSync() }
    running = task
    let outcome = await task.value
    running = nil
    finishedSyncs += 1
    switch outcome {
    case .success:
      failures = 0
      setStatus {
        $0 = SyncStatus(phase: .idle, error: nil, message: nil, progress: nil, syncedOnce: true)
      }
    case .failure(let e):
      setStatus {
        $0.phase = e.code == .offline ? .offline : .error
        $0.error = e.code
        $0.message = e.detail
        $0.progress = nil
      }
      if e.code == .notMember {
        Task { await self.refreshMembership() }
      } else if e.retryable {
        failures += 1
        schedule(after: Self.backoff(attempt: failures, random: config.random()))
      }
    }
    if again {
      again = false
      schedule(after: 0)
    }
    return try outcome.get()
  }

  private func runSync() async -> Result<SyncResult, CloudError> {
    var result = SyncResult()
    let state = mirror.state
    guard state.status != .removed, state.userId == userId else { return .success(result) }
    do {
      // What the server has decides what may be sent (see heldForServer).
      if state.features == nil { await refreshFeatures() }
      try retryRefusedFiles()
      try await pushAll(&result)
      try await pullAll(&result)
      try await catchUpTables(&result)
      try await pushAll(&result)
      await refreshFeatures()
      await refreshPermissions(now: result.parked > 0)
      let now = config.now()
      try mirror.write { tx in
        guard tx.state.status != .removed else { return }
        if tx.state.status == .uploading && !tx.outbox.contains(where: { !$0.parked }) { tx.state.status = .ready }
        tx.state.lastSyncAt = now
        tx.state.lastError = nil
        tx.state.lastErrorAt = nil
      }
      // The journal of a first download is folded into the snapshot; a failure here loses nothing.
      try? mirror.compact()
      return .success(result)
    } catch {
      let e = Self.cloudError(error)
      let now = config.now()
      try? mirror.write { tx in
        if e.code == .notMember {
          tx.state.status = .removed
          tx.state.removedReason = "access"
        }
        tx.state.lastError = e.code
        tx.state.lastErrorAt = now
      }
      return .failure(e)
    }
  }

  /// Any error of a sync as a CloudError: a mirror that couldn't be saved is
  /// tried again later, like a server that didn't answer.
  static func cloudError(_ error: Error) -> CloudError {
    if let error = error as? MirrorError {
      return CloudError(.server, "The copy on this device could not be saved: \(error)")
    }
    return CloudError.from(error)
  }

  /// Refused files whose pause is over go back in the queue. Never a
  /// viewer's: viewers can't send files, so retrying would never end.
  func retryRefusedFiles() throws {
    guard Roles.canEdit(mirror.state.role) else { return }
    let now = config.now()
    try mirror.write { tx in
      for var entry in tx.outbox where entry.parked && entry.file {
        guard let at = entry.retryAt, at <= now else { continue }
        entry.parked = false
        entry.retryAt = nil
        tx.updateOutbox(entry)
      }
    }
  }

  func stillLinked() -> Bool {
    let state = mirror.state
    return state.status != .removed && state.userId == userId
  }

  func progress(_ kind: SyncProgress.Kind, done: Int, total: Int) {
    let progress = SyncProgress(kind: kind, done: done, total: total)
    config.onProgress?(progress)
    setStatus { $0.progress = progress }
  }

  // MARK: Receiving

  enum Applied { case applied, stale, gone }

  func pullAll(_ result: inout SyncResult) async throws {
    var resynced = false
    var refetched = false
    while true {
      let state = mirror.state
      if state.status == .removed { return }
      let asked = (since: state.cursor, epoch: state.epoch)
      let rows: [PulledRow]
      do {
        rows = try await api.pullRecords(company: companyId, since: state.cursor, limit: config.pullPage)
      } catch {
        let e = CloudError.from(error)
        guard e.code == .resync else { throw e }
        if !resynced {
          resynced = true
          try await fullResync()
          continue
        }
        // Pulled again from the start and refused again on a later page: the
        // cursor is still below purged_until_rev, which pull_records refuses
        // for any page but the first. (The web stops here, and so never
        // finishes; see catchUpByRecords.)
        guard !refetched else { throw e }
        refetched = true
        try await catchUpByRecords(&result)
        continue
      }
      if !rows.isEmpty {
        let applied = try applyRows(rows, asked: asked)
        if applied == .gone { return }
        // The cursor was reset while the page was on its way: ask again from there.
        if applied == .stale { continue }
      }
      result.pulled += rows.count
      if state.status == .downloading, let total = state.total, total > 0 {
        progress(.download, done: min(total, result.pulled), total: total)
      }
      if rows.count < config.pullPage { break }
    }
    try await finishPull(resynced: resynced)
  }

  /// Stores a page of the cloud's changes in one transaction and moves the
  /// cursor past it (`applyRows`). `asked` is where the page was asked
  /// from: when the cursor was reset meanwhile (a role that now sees more)
  /// the page is thrown away ('stale') and asked for again. With
  /// `keepCursor` (records of a table brought in by themselves) the cursor stays.
  func applyRows(_ rows: [PulledRow], asked: (since: Int64, epoch: Int)?, keepCursor: Bool = false) throws -> Applied {
    let companyId = self.companyId
    return try mirror.write { tx -> Applied in
      let state = tx.state
      if state.status == .removed { return .gone }
      if let asked, state.epoch != asked.epoch || state.cursor < asked.since { return .stale }
      let pending = Set(tx.outbox.map(\.key))
      let hidePeople = !Roles.canSeePeople(state.role)
      let lookup = Privacy.ownersLookup(hidePeople ? Privacy.pageOwners(rows) : [])
      let holding = state.status == .downloading
      var duplicates = OrderedIds(state.duplicates)
      var cursor = state.cursor
      for row in rows {
        if !keepCursor { cursor = max(cursor, row.rev) }
        guard SyncTables.synced.contains(row.tbl) else { continue }
        // Payroll and people data this role may not hold.
        if hidePeople && !row.deleted && Privacy.isPrivateRecord(row.tbl, row.data, lookup: lookup) { continue }
        let local = tx.record(row.tbl, row.id)
        // A record of another company with the same id is never touched.
        if let local, row.tbl != "companies", local["companyId"] != .string(companyId) { continue }
        if pending.contains(RecordKey(tbl: row.tbl, id: row.id)) {
          // This device's own change goes up and wins. The company record is
          // the exception: this device's changes are laid over the newer copy.
          if row.tbl == "companies", row.data != nil, let local {
            Self.rebaseCompanyHere(&tx, companyId: companyId, row: row, local: local, role: state.role)
          }
          continue
        }
        if row.deleted {
          // The company itself is only ever removed by the person, on purpose.
          if row.tbl == "companies" { continue }
          if local != nil { tx.delete(row.tbl, row.id) }
          tx.deleteRev(row.tbl, row.id)
          continue
        }
        guard let data = Privacy.localCopy(companyId: companyId, row: row, local: local) else { continue }
        if row.tbl == "companies" && holding {
          tx.pendingCompany = data
          tx.pendingCompanyRev = row.rev
          continue
        }
        if !SyncJSON.sameData(local, data) { tx.put(row.tbl, row.id, data) }
        tx.setRev(row.tbl, row.id, SyncRev(rev: row.rev, base: row.tbl == "companies" ? data : JSONValue?.none))
        if row.tbl == "documents" { Self.noteDuplicates(tx, data, &duplicates) }
      }
      tx.state.cursor = cursor
      tx.state.duplicates = Self.stillDuplicated(tx, duplicates)
      return .applied
    }
  }

  /// The company record has unsent changes here and a newer copy arrived:
  /// this device's changes (since its base) are laid over the newer copy,
  /// which becomes the base. A counter change the cloud refused goes again.
  static func rebaseCompanyHere(
    _ tx: inout MirrorTx, companyId: String, row: PulledRow, local: JSONValue, role: MemberRole
  ) {
    guard let remote = Privacy.localCopy(companyId: companyId, row: row, local: local) else { return }
    let known = tx.rev("companies", companyId)
    // Staff only ever change counters here, so without a base (synced by an
    // earlier version) their change is the counters.
    let base: JSONValue? = known?.base ?? (role == .staff ? local.setting("numbering", remote["numbering"]) : JSONValue?.none)
    guard let base else {
      // What changed here isn't known: keep this copy, with the cloud's
      // document counters so numbers aren't used twice.
      let numbering = CompanyPatch.mergeNumbering(local["numbering"], remote["numbering"])
      if !SyncJSON.sameData(numbering, local["numbering"]) {
        tx.put("companies", companyId, local.setting("numbering", numbering))
      }
      return
    }
    let ops = CompanyPatch.companyOps(base: base, local: local)
    let data = CompanyPatch.rebaseCompany(current: remote, ops: ops).data
    if !SyncJSON.sameData(data, local) { tx.put("companies", companyId, data) }
    tx.setRev("companies", companyId, SyncRev(rev: row.rev, base: remote))
    // Nothing but counters (or nothing at all) left to send: a refusal of it
    // was about the older copy, so it goes again.
    if ops.isEmpty || CompanyPatch.onlyCounters(ops) {
      for var entry in tx.outbox where entry.table == "companies" && entry.id == companyId && entry.parked {
        entry.parked = false
        entry.error = nil
        entry.detail = nil
        tx.updateOutbox(entry)
      }
    }
  }

  /// Notes a document that arrived with the number of another document here.
  static func noteDuplicates(_ tx: MirrorTx, _ document: JSONValue, _ duplicates: inout OrderedIds) {
    guard case .some(.string(let number)) = document["number"],
      !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      case .some(.string(let type)) = document["type"]
    else { return }
    let same = tx.documents(type: type, number: number)
    guard same.count >= 2 else { return }
    for id in same.sorted() { duplicates.insert(id) }
  }

  /// The noted documents that still share their number with another one.
  static func stillDuplicated(_ tx: MirrorTx, _ ids: OrderedIds) -> [String] {
    ids.items.filter { id in
      guard let document = tx.record("documents", id), case .some(.string(let type)) = document["type"],
        case .some(.string(let number)) = document["number"]
      else { return false }
      return tx.documents(type: type, number: number).count > 1
    }
  }

  /// Ends a pull: a download stores its company last; a resync moves the cursor past purged deletes.
  func finishPull(resynced: Bool) async throws {
    let state = mirror.state
    guard state.status == .downloading || resynced else { return }
    let info: SyncInfo
    do {
      info = try await api.syncInfo(company: companyId)
    } catch {
      throw CloudError.from(error)
    }
    let companyId = self.companyId
    try mirror.write { tx in
      tx.state.cursor = max(tx.state.cursor, info.purgedUntilRev)
      guard tx.state.status == .downloading else { return }
      guard let company = tx.pendingCompany else {
        // The company record isn't in the cloud yet (still uploading): try later.
        throw CloudError(.server, "This company is still being uploaded. Try again soon.")
      }
      tx.put("companies", companyId, company)
      if let rev = tx.pendingCompanyRev, rev != 0 {
        tx.setRev("companies", companyId, SyncRev(rev: rev, base: company))
      }
      tx.state.status = .ready
      tx.pendingCompany = nil
      tx.pendingCompanyRev = nil
    }
  }

  /// The device was away longer than deletes are remembered: keep only what
  /// the cloud still has (and what is waiting to be sent from here), then
  /// bring in everything again.
  func fullResync() async throws {
    var ids = Set<RecordKey>()
    var after: RecordKey?
    do {
      while true {
        let page = try await api.recordIds(company: companyId, after: after, limit: Self.idPage, table: nil)
        ids.formUnion(page)
        if page.count < Self.idPage { break }
        after = page.last
      }
    } catch {
      throw CloudError.from(error)
    }
    try mirror.write { tx in
      let pending = Set(tx.outbox.map(\.key))
      for name in SyncTables.all where name != "companies" {
        for id in tx.records(name).keys {
          let key = RecordKey(tbl: name, id: id)
          guard !ids.contains(key), !pending.contains(key) else { continue }
          tx.delete(name, id)
          tx.deleteRev(name, id)
        }
      }
      // Everything comes again, of every table.
      tx.state.cursor = 0
      tx.state.tables = SyncTables.all
    }
  }

  /// Finishes a pull from the start that pull_records refuses part way.
  ///
  /// pull_records raises almail:resync for any `since` between 0 and
  /// purged_until_rev, so once deletion markers have been purged a company
  /// larger than one page can't be pulled from the start page by page: the
  /// first page's last rev is below purged_until_rev. Nothing can have been
  /// missed, since this pull began at 0. So the rest of the records are read
  /// as they are now (a plain select of `records`, under the same row-level
  /// security), then whatever the cloud deleted meanwhile is removed here
  /// as fullResync removes it (by the cloud's list of ids, taken after the
  /// records were read, so every delete before it shows), and the cursor
  /// moves to purged_until_rev, above which pull_records takes over again.
  func catchUpByRecords(_ result: inout SyncResult) async throws {
    let page = 1000
    while true {
      let state = mirror.state
      if state.status == .removed { return }
      let asked = (since: state.cursor, epoch: state.epoch)
      let rows: [PulledRow]
      do {
        rows = try await api.recordsAfter(company: companyId, since: state.cursor, limit: page)
      } catch {
        throw CloudError.from(error)
      }
      if !rows.isEmpty {
        switch try applyRows(rows, asked: asked) {
        case .gone: return
        // The cursor went back to 0 (a role that sees more): pull_records takes it from there.
        case .stale: return
        case .applied: result.pulled += rows.count
        }
      }
      if state.status == .downloading, let total = state.total, total > 0 {
        progress(.download, done: min(total, result.pulled), total: total)
      }
      if rows.count < page { break }
    }
    var ids = Set<RecordKey>()
    var after: RecordKey?
    let info: SyncInfo
    do {
      while true {
        let keys = try await api.recordIds(company: companyId, after: after, limit: Self.idPage, table: nil)
        ids.formUnion(keys)
        if keys.count < Self.idPage { break }
        after = keys.last
      }
      info = try await api.syncInfo(company: companyId)
    } catch {
      throw CloudError.from(error)
    }
    try mirror.write { tx in
      // Brought in from the start meanwhile (a role that sees more): that pull has it.
      guard tx.state.cursor > 0 else { return }
      let pending = Set(tx.outbox.map(\.key))
      for name in SyncTables.all where name != "companies" {
        for id in tx.records(name).keys {
          let key = RecordKey(tbl: name, id: id)
          guard !ids.contains(key), !pending.contains(key) else { continue }
          tx.delete(name, id)
          tx.deleteRev(name, id)
        }
      }
      tx.state.cursor = max(tx.state.cursor, info.purgedUntilRev)
    }
  }

  // MARK: Tables added later

  /// The tables a link was pulled with (`pulledTables`): a link noted before
  /// database version 16 has none, and pulled without that version's tables.
  static func pulledTables(_ state: SyncState) -> [String] {
    state.tables
      ?? SyncTables.all.filter {
        !SyncTables.v16.contains($0) && !SyncTables.v17.contains($0) && !SyncTables.v18.contains($0)
      }
  }

  /// Brings in the records of the tables this mirror hasn't pulled with
  /// (`catchUpTables`): a version that pulled before moved its cursor past
  /// them, so they would never arrive. Only those tables are read, and
  /// stored as a pull stores them; the cursor stays where it is.
  func catchUpTables(_ result: inout SyncResult) async throws {
    let state = mirror.state
    guard state.status != .removed else { return }
    let known = Set(Self.pulledTables(state))
    let missing = SyncTables.all.filter { !known.contains($0) }
    if missing.isEmpty { return }
    // A pull from the start brings every table anyway.
    if state.cursor > 0 {
      let asked = (since: state.cursor, epoch: state.epoch)
      for name in missing {
        var after: RecordKey?
        while true {
          let page: [RecordKey]
          let rows: [PulledRow]
          do {
            page = try await api.recordIds(company: companyId, after: after, limit: Self.catchUpPage, table: name)
            rows = try await fetchRows(name, page)
          } catch {
            throw CloudError.from(error)
          }
          if !rows.isEmpty {
            // Gone from this device, or everything is coming again from the start.
            guard try applyRows(rows, asked: asked, keepCursor: true) == .applied else { return }
            result.pulled += rows.count
          }
          if page.count < Self.catchUpPage { break }
          after = page.last
        }
      }
    }
    if !Roles.canSeePeople(state.role) { try removeHiddenData() }
    try mirror.write { tx in tx.state.tables = SyncTables.all }
  }

  /// These records as the cloud has them now, as pulled rows; those deleted meanwhile are left out.
  func fetchRows(_ table: String, _ keys: [RecordKey]) async throws -> [PulledRow] {
    var rows: [PulledRow] = []
    let api = self.api
    let companyId = self.companyId
    var start = 0
    while start < keys.count {
      let group = Array(keys[start..<min(keys.count, start + Self.catchUpAtOnce)])
      let found = try await withThrowingTaskGroup(of: (Int, CloudRecord?).self) { tasks in
        for (i, key) in group.enumerated() {
          tasks.addTask { (i, try await api.getRecord(company: companyId, table: table, id: key.id)) }
        }
        var found = [CloudRecord?](repeating: nil, count: group.count)
        for try await (i, record) in tasks { found[i] = record }
        return found
      }
      for (i, record) in found.enumerated() {
        if let record { rows.append(PulledRow(tbl: table, id: group[i].id, data: record.data, rev: record.rev, deleted: false)) }
      }
      start += Self.catchUpAtOnce
    }
    return rows
  }

  // MARK: Features and permissions

  /// Notes what the server has, asked at most every ten minutes; when it
  /// can't be asked, what was known stays.
  func refreshFeatures() async {
    let state = mirror.state
    guard state.status != .removed else { return }
    let now = config.now()
    if state.features != nil, let at = state.featuresAt, now.timeIntervalSince(at) < Self.featuresRecheck { return }
    guard let features = try? await api.serverFeatures(company: companyId) else { return }
    try? mirror.write { tx in
      tx.state.features = features
      tx.state.featuresAt = now
    }
    if features.contains("tables_v16") { try? releaseHeld(features) }
  }

  /// Notes the owner's limits on this person, asked at most every five
  /// minutes, and at once when the server just refused a change (`now`).
  func refreshPermissions(now: Bool) async {
    let state = mirror.state
    guard state.status != .removed, state.has("super_admin") else { return }
    let time = config.now()
    if !now, let at = state.permissionsAt, time.timeIntervalSince(at) < Self.permissionsRecheck { return }
    guard let mine = try? await api.myPermissions(company: companyId) else { return }
    try? notePermissions(mine)
  }

  /// Keeps the owner's limits on this person as the server just said them.
  public func notePermissions(_ mine: MyPermissions) throws {
    let now = config.now()
    try mirror.write { tx in
      tx.state.permissions = mine.apps
      tx.state.approver = mine.approver
      tx.state.seniorRolesOwnerOnly = mine.seniorRolesOwnerOnly
      tx.state.permissionsAt = now
    }
  }

  // MARK: Roles

  /// Applies a role change, in one transaction with what follows from it: a
  /// role that no longer sees payroll and people data loses this device's
  /// copy of it; a role that sees more brings everything in again (a page
  /// asked for under the old role is then thrown away).
  public func applyRole(_ role: MemberRole) throws {
    try mirror.write { tx in
      guard tx.state.role != role else { return }
      let seesMore = !Roles.canSeePeople(tx.state.role) && Roles.canSeePeople(role)
      tx.state.role = role
      // The owner's limits and approvers follow the role: asked again.
      tx.state.permissionsAt = nil
      if seesMore {
        tx.state.cursor = 0
        tx.state.epoch += 1
        tx.state.tables = SyncTables.all
      }
      if !Roles.canSeePeople(role) { Self.removeHiddenRecords(&tx) }
    }
  }

  /// Removes from this device what the person's role may not see (payroll and people data).
  public func removeHiddenData() throws {
    try mirror.write { tx in Self.removeHiddenRecords(&tx) }
  }

  static func removeHiddenRecords(_ tx: inout MirrorTx) {
    let owners = Privacy.privateOwnerIds(tx.data.tables)
    let lookup = Privacy.ownersLookup(owners)
    for name in SyncTables.all where name != "companies" {
      let hidden = tx.records(name).filter { id, record in
        Privacy.peopleTables.contains(name) || Privacy.isPrivateRecord(name, record, lookup: lookup)
          || owners.contains(id)
      }.keys
      guard !hidden.isEmpty else { continue }
      let keys = Set(hidden)
      for id in hidden {
        tx.delete(name, id)
        tx.deleteRev(name, id)
      }
      tx.deleteOutbox(tx.outbox.filter { $0.table == name && keys.contains($0.id) }.map(\.seq))
    }
  }

  // MARK: Membership

  /// Brings the role and name up to date and notices a company this
  /// account has left (my_companies), at most every `throttle` seconds.
  public func refreshMembership(throttle: Double = 0) async {
    let now = config.clock.now()
    if throttle > 0, let last = lastMembership, now - last < throttle { return }
    lastMembership = now
    guard let companies = try? await api.myCompanies() else { return }
    apply(membership: companies)
  }

  /// The account's companies as my_companies just said them (one call can serve every engine).
  public func apply(membership companies: [CloudCompany]) {
    let state = mirror.state
    guard state.userId == userId, state.status != .removed else { return }
    guard let company = companies.first(where: { $0.id == companyId }) else {
      // Still being created by this device's upload, or really gone.
      if state.status == .uploading && state.lastSyncAt == nil { return }
      try? mirror.write { tx in
        tx.state.status = .removed
        tx.state.removedReason = "access"
      }
      return
    }
    if company.name != state.name { try? mirror.write { tx in tx.state.name = company.name } }
    if company.role != state.role {
      try? applyRole(company.role)
      schedule(after: 0)
    }
  }

  // MARK: Numbers

  /// Takes the next counter of `kind` for a new number dated `date` from the
  /// cloud, never below `min` (this device's own next counter − 1). Nil
  /// offline, for a viewer, when the server can't, or with no answer in 3 s:
  /// the device numbers it itself (`cloudCounterReserver`).
  public func reserveNumber(kind: String, date: String, min: Int) async -> ReservedCounter? {
    guard config.isOnline() else { return nil }
    let state = mirror.state
    guard state.userId == userId, state.status == .ready, Roles.canEdit(state.role) else { return nil }
    let api = self.api
    let companyId = self.companyId
    let clock = config.clock
    let settled = Mutex(false)
    return await withCheckedContinuation { (continuation: CheckedContinuation<ReservedCounter?, Never>) in
      let finish: @Sendable (ReservedCounter?) -> Void = { value in
        let first = settled.withLock { done -> Bool in
          defer { done = true }
          return !done
        }
        if first { continuation.resume(returning: value) }
      }
      let work = Task {
        finish(try? await api.reserveNumber(company: companyId, kind: kind, date: date, min: Int64(min)))
      }
      Task {
        try? await clock.sleep(seconds: Self.reserveTimeout)
        finish(nil)
        work.cancel()
      }
    }
  }
}

/// Ids in the order they were first noted.
struct OrderedIds {
  private(set) var items: [String] = []
  private var seen = Set<String>()

  init(_ ids: [String]) {
    for id in ids { insert(id) }
  }

  mutating func insert(_ id: String) {
    if seen.insert(id).inserted { items.append(id) }
  }
}
