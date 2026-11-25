import Foundation

/// One record change of a user action.
public enum RecordChange: Sendable, Equatable {
  /// Stores the record whole (its `id` names it).
  case put(table: String, record: JSONValue)
  case delete(table: String, id: String)

  public var table: String {
    switch self {
    case .put(let table, _), .delete(let table, _): table
    }
  }
}

/// Why a user action was not saved. Nothing of it was.
public enum SyncWriteError: Error, Equatable, Sendable {
  /// This app does not write records of this kind yet (see `SyncConfiguration.writableKinds`).
  case notWritable(String)
  /// The rules refuse it; the message says why, in words the person can act on.
  case refused(String)
  /// The record is not one this company can store (its id, its company).
  case invalid(String)
}

/// What `perform` saved.
public struct PerformOutcome: Sendable, Equatable {
  /// The outbox group of the action's changes.
  public var group: String
  /// Changes queued for the cloud (a record saved unchanged queues nothing).
  public var queued: Int
}

extension SyncEngine {
  // MARK: Capturing a write

  /// Applies a user action's record changes to the mirror and queues them for
  /// the cloud, in one transaction with one outbox group: all of it or, when
  /// anything is refused, none of it. A record saved unchanged (`sameData`)
  /// queues nothing. Kinds not in `writableKinds` are refused; the list is
  /// empty until their rules are ported.
  @discardableResult
  public func perform(group changes: [RecordChange]) throws -> PerformOutcome {
    for change in changes where !config.writableKinds.contains(change.table) {
      throw SyncWriteError.notWritable(change.table)
    }
    let group = shortId()
    let at = config.now()
    let companyId = self.companyId
    let userId = self.userId
    let rules = config.rules
    let outcome = try mirror.write { tx -> PerformOutcome in
      guard tx.state.userId == userId else {
        throw SyncWriteError.refused("This company is kept for another account on this device.")
      }
      if tx.state.status == .downloading {
        throw SyncWriteError.refused("This company is still being downloaded. Try again in a moment.")
      }
      var queued = 0
      for change in changes {
        let id: String
        let after: JSONValue?
        switch change {
        case .put(let table, let record):
          guard case .some(.string(let recordId)) = record["id"], !recordId.isEmpty, recordId.utf16.count <= 128
          else { throw SyncWriteError.invalid("A record needs an id of 1 to 128 characters.") }
          if table == "companies" ? recordId != companyId : record["companyId"] != .string(companyId) {
            throw SyncWriteError.invalid("This record belongs to another company.")
          }
          id = recordId
          after = record
        case .delete(_, let recordId):
          id = recordId
          after = nil
        }
        let table = change.table
        let before = tx.record(table, id)
        let view = MirrorView(data: tx.data)
        if let reason = rules.refusal(
          state: tx.state, table: table, before: before, after: after, lookup: { view.record($0, $1) })
        {
          throw SyncWriteError.refused(reason)
        }
        if let after {
          tx.put(table, id, after)
          if SyncJSON.sameData(before, after) { continue }
        } else {
          guard before != nil else { continue }
          tx.delete(table, id)
        }
        tx.addOutbox(table: table, id: id, op: after == nil ? .delete : .put, at: at, group: group)
        queued += 1
      }
      return PerformOutcome(group: group, queued: queued)
    }
    if outcome.queued > 0 { schedule(after: 1) }
    return outcome
  }

  // MARK: Sending

  struct Outgoing {
    var change: PushChange
    var seqs: [Int64]
    /// The transactions its changes were made in (OutboxEntry.group).
    var groups: [String] = []
    /// Attachment content uploaded with this change.
    var file: (storagePath: String, contentHash: String)?
    /// The company record: this device's copy as sent, kept as the base of its later changes.
    var base: JSONValue?
    /// The company record: fields that had also changed in the cloud.
    var companyConflicts: [[String]] = []
  }

  /// The company record's change: the fields changed since the cloud's copy this device had.
  struct CompanyOutgoing {
    var seqs: [Int64]
    /// The record as it is here, as the cloud keeps it.
    var local: JSONValue
    /// Nil when that copy isn't known.
    var ops: [CompanyOp]?
    var baseRev: Int64?
  }

  struct Plan {
    var batch: [Outgoing] = []
    var company: CompanyOutgoing?
    /// Entries were dropped or parked: the outbox moved on, even with nothing to send.
    var progressed = false
  }

  func pushAll(_ result: inout SyncResult) async throws {
    let state = mirror.state
    let total = state.status == .uploading ? (state.total ?? 0) : 0
    while true {
      let entries = Array(mirror.read { $0.outbox.filter { !$0.parked } }.prefix(Self.pushBatch * 5))
      if entries.isEmpty { return }
      let plan = try await buildBatch(entries, &result, role: mirror.state.role)
      // The company may have left this device while the batch was prepared.
      guard stillLinked() else { return }
      if let company = plan.company { try await sendCompany(company, &result) }
      if !plan.batch.isEmpty { try await sendBatch(plan.batch, &result) }
      if plan.company == nil && plan.batch.isEmpty && !plan.progressed { return }
      if total > 0 { progress(.upload, done: max(0, total - mirror.pendingCount), total: total) }
    }
  }

  /// Parks entries the server refused, with the reason. A refused file
  /// (`file`) that may be taken later (`retry`) is sent again by itself after
  /// a pause that grows with each refusal.
  func park(_ seqs: [Int64], _ error: CloudError, file: Bool = false, retry: Bool = false) throws {
    let now = config.now()
    try mirror.write { tx in Self.park(&tx, seqs, error, file: file, retry: retry, now: now) }
  }

  static func park(_ tx: inout MirrorTx, _ seqs: [Int64], _ error: CloudError, file: Bool, retry: Bool, now: Date) {
    let wanted = Set(seqs)
    for var entry in tx.outbox where wanted.contains(entry.seq) {
      entry.parked = true
      entry.error = error.code.rawValue
      entry.detail = String(error.detail.utf16.prefix(500)) ?? String(error.detail.prefix(500))
      entry.file = file
      let attempts = (entry.attempts ?? 0) + 1
      if retry && attempts <= fileRetry.count {
        entry.attempts = attempts
        entry.retryAt = now.addingTimeInterval(fileRetry[attempts - 1])
      } else {
        entry.attempts = nil
        entry.retryAt = nil
      }
      tx.updateOutbox(entry)
    }
  }

  /// A stock movement of items issued: it waits with them for the server to take them.
  static func issueMovement(_ table: String, _ record: JSONValue?) -> Bool {
    table == "stockMovements" && record?["sourceType"] == .string("issue")
  }

  /// Records a server without the tables of later versions must not get
  /// (`heldForServer`): they wait in the outbox, parked as server_outdated,
  /// until the owner runs the migration (see releaseHeld).
  static func heldForServer(_ view: MirrorView) -> (String, JSONValue) -> Bool {
    let state = view.state
    let costings = !state.has("staffing_costings")
    let issues = !state.has("stock_issues")
    let heldCosting: (String, JSONValue) -> Bool = { name, record in
      (issues && (SyncTables.v18.contains(name) || issueMovement(name, record)))
        || (costings
          && (SyncTables.v17.contains(name) || (name == "activities" && record["entity"] == .string("costing"))))
    }
    if state.has("tables_v16") { return heldCosting }
    let confidential = Set(
      view.records("complianceDocuments").filter { $0.value["confidential"] == .bool(true) }.keys)
    return { name, record in
      heldCosting(name, record) || SyncTables.v16.contains(name)
        || (name == "complianceDocuments" && record["confidential"] == .bool(true))
        || (name == "renewals" && confidential.contains(Privacy.renewedDocumentId(record) ?? ""))
    }
  }

  /// Puts parked for want of the migration go back in the queue once the server has it.
  func releaseHeld(_ features: [String]) throws {
    let costings = features.contains("staffing_costings")
    let issues = features.contains("stock_issues")
    try mirror.write { tx in
      for var entry in tx.outbox where entry.parked && entry.error == CloudErrorCode.serverOutdated.rawValue {
        let record = tx.record(entry.table, entry.id)
        let waitsForIssues =
          SyncTables.v18.contains(entry.table) || (entry.table == "stockMovements" && Self.issueMovement(entry.table, record))
        let waitsForCostings =
          SyncTables.v17.contains(entry.table)
          || (entry.table == "activities" && record?["entity"] == .string("costing"))
        guard issues || !waitsForIssues, costings || !waitsForCostings else { continue }
        entry.parked = false
        entry.error = nil
        entry.detail = nil
        tx.updateOutbox(entry)
      }
    }
  }

  /// The batch without the records at its end whose transaction has changes
  /// left out of it, unless nothing else would be left to send.
  static func withWholeChanges(_ batch: [Outgoing], _ entries: [OutboxEntry]) -> [Outgoing] {
    let sent = Set(batch.flatMap(\.seqs))
    let cut = Set(entries.filter { $0.group != nil && !sent.contains($0.seq) }.compactMap(\.group))
    if cut.isEmpty { return batch }
    var kept = batch
    while let last = kept.last, last.groups.contains(where: { cut.contains($0) }) { kept.removeLast() }
    return kept.isEmpty ? batch : kept
  }

  /// The batch in the parts the cloud takes or refuses whole: the records
  /// changed in one local transaction together; large transactions are taken
  /// record by record.
  static func changesOf(_ batch: [Outgoing]) -> [[Outgoing]] {
    var sizes: [String: Int] = [:]
    for item in batch { for g in item.groups { sizes[g, default: 0] += 1 } }
    var parent = Array(batch.indices)
    func root(_ i: Int) -> Int {
      var i = i
      while parent[i] != i {
        parent[i] = parent[parent[i]]
        i = parent[i]
      }
      return i
    }
    var first: [String: Int] = [:]
    for (i, item) in batch.enumerated() {
      for g in item.groups where (sizes[g] ?? 0) <= changeGroupLimit {
        if let j = first[g] {
          parent[root(i)] = root(j)
        } else {
          first[g] = i
        }
      }
    }
    var order: [Int] = []
    var parts: [Int: [Outgoing]] = [:]
    for (i, item) in batch.enumerated() {
      let r = root(i)
      if parts[r] == nil { order.append(r) }
      parts[r, default: []].append(item)
    }
    return order.compactMap { parts[$0] }
  }

  func buildBatch(_ entries: [OutboxEntry], _ result: inout SyncResult, role: MemberRole) async throws -> Plan {
    struct Group {
      var table: String
      var id: String
      var seqs: [Int64]
      var last: OutboxEntry
      var made: [String]
    }
    var order: [RecordKey] = []
    var groups: [RecordKey: Group] = [:]
    for entry in entries {
      let key = entry.key
      if groups[key] == nil {
        order.append(key)
        groups[key] = Group(table: entry.table, id: entry.id, seqs: [], last: entry, made: [])
      }
      groups[key]?.seqs.append(entry.seq)
      if let group = entry.group, groups[key]?.made.contains(group) == false { groups[key]?.made.append(group) }
      if let last = groups[key]?.last, entry.seq >= last.seq { groups[key]?.last = entry }
    }
    let view = mirror.read { $0 }
    let held = Self.heldForServer(view)
    let privateOwners = Privacy.privateOwnerIds(view.data.tables)
    var plan = Plan()
    var dropped: [Int64] = []
    var parked: [([Int64], CloudError, Bool, Bool)] = []
    var bytes = 0
    var full = false
    for key in order {
      guard let group = groups[key] else { continue }
      if plan.batch.count >= Self.pushBatch {
        full = true
        break
      }
      if !SyncTables.synced.contains(group.table) {
        // Not something the cloud keeps: drop it.
        dropped += group.seqs
        plan.progressed = true
        continue
      }
      let record = view.record(group.table, group.id)
      let ours =
        record.map { group.table == "companies" ? group.id == companyId : $0["companyId"] == .string(companyId) }
        ?? false
      let base = view.rev(group.table, group.id)?.rev
      guard let record, ours else {
        if group.last.op != .delete {
          // Gone from this device without being deleted: nothing to tell the cloud.
          dropped += group.seqs
          plan.progressed = true
          continue
        }
        let item = Outgoing(
          change: PushChange(tbl: group.table, id: group.id, data: nil, baseRev: base), seqs: group.seqs,
          groups: group.made)
        bytes += SyncJSON.jsLength(item.change.json)
        plan.batch.append(item)
        continue
      }
      if group.last.op != .delete && held(group.table, record) {
        parked.append((group.seqs, CloudError(.serverOutdated, "The cloud needs the latest database script first."), false, false))
        result.parked += 1
        plan.progressed = true
        continue
      }
      if group.table == "companies" {
        let local = Privacy.cloudCopy(table: group.table, record: record, privateOwners: privateOwners)
        let known = view.rev("companies", companyId)
        plan.company = CompanyOutgoing(
          seqs: group.seqs, local: local, ops: known?.base.map { CompanyPatch.companyOps(base: $0, local: local) },
          baseRev: base)
        continue
      }
      var data = Privacy.cloudCopy(table: group.table, record: record, privateOwners: privateOwners)
      var item = Outgoing(
        change: PushChange(tbl: group.table, id: group.id, data: data, baseRev: base), seqs: group.seqs,
        groups: group.made)
      if group.table == "attachments", case .some(.string(let content)) = record["dataUrl"], !content.isEmpty {
        guard let uploader = config.uploader else {
          // No way to send its content yet: it waits here, unsent and whole.
          continue
        }
        do {
          item.file = try await uploader.upload(companyId: companyId, attachment: record)
        } catch {
          // A file Storage refuses waits with its reason; the rest goes on.
          let e = CloudError.from(error)
          if e.retryable || e.code == .notMember { throw e }
          parked.append((group.seqs, e, true, e.code == .permission && Roles.canEdit(role)))
          result.parked += 1
          plan.progressed = true
          continue
        }
        if let file = item.file {
          data.set("dataUrl", .string(""))
          data.set("storagePath", .string(file.storagePath))
          data.set("contentHash", .string(file.contentHash))
          item.change.data = data
        }
      }
      let size = SyncJSON.jsLength(item.change.json)
      if !plan.batch.isEmpty && bytes + size > Self.pushBytes {
        full = true
        break
      }
      bytes += size
      plan.batch.append(item)
    }
    if !dropped.isEmpty || !parked.isEmpty {
      let now = config.now()
      try mirror.write { tx in
        tx.deleteOutbox(dropped)
        for (seqs, error, file, retry) in parked { Self.park(&tx, seqs, error, file: file, retry: retry, now: now) }
      }
    }
    // A change made with others goes with them: what the batch had no room
    // for waits, with the rest of its transaction, for the next one.
    if full { plan.batch = Self.withWholeChanges(plan.batch, entries) }
    plan.batch = plan.batch.enumerated().sorted { a, b in
      let left = SyncTables.order(a.element.change.tbl)
      let right = SyncTables.order(b.element.change.tbl)
      return left != right ? left < right : a.offset < b.offset
    }.map(\.element)
    return plan
  }

  /// Sends the company record's change: the changed fields, merged into the
  /// cloud's copy. A server that can't merge gets the whole record, laid
  /// over the copy it has now, so fields others changed stay.
  func sendCompany(_ item: CompanyOutgoing, _ result: inout SyncResult) async throws {
    if let ops = item.ops, ops.isEmpty {
      // Nothing differs from the cloud's copy this device has.
      try mirror.write { tx in tx.deleteOutbox(item.seqs) }
      return
    }
    var data = item.local
    var baseRev = item.baseRev
    var conflicts: [[String]] = []
    do {
      if let ops = item.ops {
        if let answer = try await api.patchCompany(company: companyId, ops: ops) {
          try confirmCompany(item, rev: answer.rev)
          result.pushed += 1
          if !answer.conflicts.isEmpty {
            result.notes.append(ConflictNote(table: "companies", id: companyId, deleted: false, fields: answer.conflicts))
            result.conflicts += 1
          }
          return
        }
        if let current = try await api.getRecord(company: companyId, table: "companies", id: companyId) {
          let rebased = CompanyPatch.rebaseCompany(current: current.data, ops: ops)
          data = rebased.data
          conflicts = rebased.conflicts
          baseRev = current.rev
        }
      }
    } catch {
      let e = CloudError.from(error)
      if e.stopsSending { throw e }
      try park(item.seqs, e)
      result.parked += 1
      return
    }
    try await sendBatch(
      [
        Outgoing(
          change: PushChange(tbl: "companies", id: companyId, data: data, baseRev: baseRev), seqs: item.seqs,
          // This device's copy as sent, not the merged one: the fields others
          // changed arrive with the next pull.
          base: item.local, companyConflicts: conflicts)
      ], &result)
  }

  /// The cloud merged this device's company change: forget it, and keep what was sent as the new base.
  func confirmCompany(_ item: CompanyOutgoing, rev: Int64) throws {
    let companyId = self.companyId
    try mirror.write { tx in
      tx.deleteOutbox(item.seqs)
      tx.deleteOutbox(tx.outbox.filter { $0.table == "companies" && $0.id == companyId && $0.parked }.map(\.seq))
      tx.setRev("companies", companyId, SyncRev(rev: rev, base: item.local))
    }
  }

  func sendBatch(_ batch: [Outgoing], _ result: inout SyncResult) async throws {
    let results: [PushResult]
    do {
      results = try await api.pushRecords(company: companyId, changes: batch.map(\.change))
    } catch {
      let e = CloudError.from(error)
      if e.stopsSending { throw e }
      // The server refused something in the batch: find it by halves and
      // park it, with whatever was changed with it (see changesOf).
      let parts = Self.changesOf(batch)
      if parts.count == 1 {
        try park(batch.flatMap(\.seqs), e)
        result.parked += batch.count
        return
      }
      let half = (parts.count + 1) / 2
      try await sendBatch(parts[..<half].flatMap { $0 }, &result)
      try await sendBatch(parts[half...].flatMap { $0 }, &result)
      return
    }
    try confirm(batch, results, &result)
  }

  /// Changes of these are expected on several devices at once and merge on
  /// their own: their conflicts are not noted (`QUIET`).
  static let quiet: Set<String> = ["companies", "activities", "stockMovements", "syncRevs", "approvals"]

  /// The server has these changes: forget them here, note their versions and conflicts.
  func confirm(_ batch: [Outgoing], _ results: [PushResult], _ result: inout SyncResult) throws {
    var byKey: [RecordKey: PushResult] = [:]
    for answer in results { byKey[RecordKey(tbl: answer.tbl, id: answer.id)] = answer }
    let companyId = self.companyId
    let userId = self.userId
    let now = config.now()
    let conflicts: [Outgoing] = try mirror.write { tx in
      var conflicts: [Outgoing] = []
      for item in batch {
        let key = RecordKey(tbl: item.change.tbl, id: item.change.id)
        let answer = byKey[key]
        tx.deleteOutbox(item.seqs)
        // A later version got through: an earlier refusal no longer matters.
        tx.deleteOutbox(tx.outbox.filter { $0.key == key && $0.parked }.map(\.seq))
        if item.change.deleted {
          if key.tbl == "attachments" {
            // Its file goes from Storage; Storage isn't reached from here yet,
            // so the removal waits in the file queue.
            tx.addFile(path: "\(companyId)/\(key.id)", at: now, attempts: 0, lastError: nil, userId: userId)
          }
          tx.deleteRev(key.tbl, key.id)
        } else if let rev = answer?.rev {
          tx.setRev(key.tbl, key.id, SyncRev(rev: rev, base: item.base))
        }
        if let file = item.file, var local = tx.record(key.tbl, key.id) {
          local.set("storagePath", .string(file.storagePath))
          local.set("contentHash", .string(file.contentHash))
          tx.put(key.tbl, key.id, local)
        }
        if answer?.conflict == true { conflicts.append(item) }
      }
      return conflicts
    }
    result.pushed += batch.count
    for item in conflicts where !Self.quiet.contains(item.change.tbl) {
      result.notes.append(ConflictNote(table: item.change.tbl, id: item.change.id, deleted: item.change.deleted, fields: []))
      result.conflicts += 1
    }
    for item in batch where !item.companyConflicts.isEmpty {
      result.notes.append(ConflictNote(table: "companies", id: companyId, deleted: false, fields: item.companyConflicts))
      result.conflicts += 1
    }
  }

  // MARK: Refused changes

  /// Sends the refused changes again (after the role was changed, say).
  public func retryParked() throws {
    try mirror.write { tx in
      for var entry in tx.outbox where entry.parked {
        entry.parked = false
        entry.error = nil
        entry.detail = nil
        entry.file = false
        entry.attempts = nil
        entry.retryAt = nil
        tx.updateOutbox(entry)
      }
    }
    schedule(after: 0)
  }

  public enum DiscardOutcome: Sendable, Equatable {
    case undone
    /// The cloud never had the record: undoing it would delete it from this device.
    case notInCloud
  }

  /// Gives up a refused change: this device takes the record back as the
  /// cloud has it. A record the cloud never had is deleted from this device
  /// only with `deleteNew`; the company record never is. What was changed
  /// with it, and held back with it, goes back as the cloud has it too.
  public func discardParked(table: String, id: String, deleteNew: Bool = false) async throws -> DiscardOutcome {
    let key = RecordKey(tbl: table, id: id)
    let made = Set(mirror.outbox.filter { $0.key == key && $0.parked }.compactMap(\.group))
    let outcome = try await discardOne(key, deleteNew: deleteNew)
    guard outcome == .undone, !made.isEmpty else { return outcome }
    var others: [RecordKey] = []
    for entry in mirror.parkedEntries
    where entry.group.map(made.contains) == true && entry.table != "companies" && entry.key != key
      && !others.contains(entry.key)
    {
      others.append(entry.key)
    }
    for other in others { _ = try await discardOne(other, deleteNew: true) }
    return outcome
  }

  private func discardOne(_ key: RecordKey, deleteNew: Bool) async throws -> DiscardOutcome {
    let remote: CloudRecord?
    do {
      remote = try await api.getRecord(company: companyId, table: key.tbl, id: key.id)
    } catch {
      throw CloudError.from(error)
    }
    let companyId = self.companyId
    return try mirror.write { tx -> DiscardOutcome in
      let local = tx.record(key.tbl, key.id)
      if remote == nil, local != nil, !deleteNew || key.tbl == "companies" { return .notInCloud }
      tx.deleteOutbox(tx.outbox.filter { $0.key == key }.map(\.seq))
      guard let remote else {
        tx.delete(key.tbl, key.id)
        tx.deleteRev(key.tbl, key.id)
        return .undone
      }
      let row = PulledRow(tbl: key.tbl, id: key.id, data: remote.data, rev: remote.rev, deleted: false)
      let data = Privacy.localCopy(companyId: companyId, row: row, local: local)
      if let data { tx.put(key.tbl, key.id, data) }
      tx.setRev(key.tbl, key.id, SyncRev(rev: remote.rev, base: key.tbl == "companies" ? data : JSONValue?.none))
      return .undone
    }
  }
}
