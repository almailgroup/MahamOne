import Foundation
import Synchronization

/// What one transaction changed in the mirror, for screens to refresh.
public struct MirrorChange: Sendable, Equatable {
  /// The record tables written (records added, changed or deleted).
  public var tables: Set<String>
  /// The sync state, the outbox or the file queue changed.
  public var bookkeeping: Bool

  public init(tables: Set<String>, bookkeeping: Bool) {
    self.tables = tables
    self.bookkeeping = bookkeeping
  }
}

/// The local copy of one company kept in the cloud: its records as the web
/// wrote them (`JSONValue`, keyed by table and id), the server version of
/// each, the sync state, the outbox and the file queue, in an app-supplied
/// folder.
///
/// Every change is a transaction (`write`): it is applied to a copy, saved
/// to the journal (synced to disk), and only then becomes what everyone
/// reads, so a failed or interrupted transaction changes nothing. Screens
/// read from it at any time, and hear of each change through `changes()`.
public final class Mirror: Sendable {
  public let directory: URL
  public let companyId: String

  private struct Inner {
    var data: MirrorData
    var generation: Int
    var journal: FileIO.Appender
    /// While a compaction writes the next generation: the next generation's journal, appended to as well.
    var shadow: FileIO.Appender?
    var shadowBytes = 0
    var journalBytes: Int
    var snapshotBytes: Int
    var compacting = false
    var observers: [Int: AsyncStream<MirrorChange>.Continuation] = [:]
    var nextObserver = 0
  }

  private let inner: Mutex<Inner>

  /// A compaction is due once the journal is this long and longer than the snapshot.
  static let compactAfterBytes = 8 * 1024 * 1024

  private init(directory: URL, companyId: String, inner: Inner) {
    self.directory = directory
    self.companyId = companyId
    self.inner = Mutex(inner)
  }

  // MARK: Opening

  /// Starts an empty mirror in `directory`, replacing whatever was there
  /// (an earlier copy is dropped without telling the cloud).
  public static func create(directory: URL, state: SyncState) throws -> Mirror {
    FileIO.remove(directory)
    try FileIO.makeDirectory(directory)
    let data = MirrorData(state: state)
    let folder = MirrorFiles.generationURL(directory, 1)
    let bytes = try MirrorFiles.writeSnapshot(data, in: folder)
    try FileIO.writeAtomically(Data("1".utf8), to: directory.appendingPathComponent(MirrorFiles.current))
    let journal = try FileIO.Appender(folder.appendingPathComponent(MirrorFiles.journal))
    return Mirror(
      directory: directory, companyId: state.companyId,
      inner: Inner(data: data, generation: 1, journal: journal, journalBytes: 0, snapshotBytes: bytes))
  }

  /// A mirror holding `records` (each table's records, by their "id"), as
  /// if downloaded: for previews and tests; it is never synced.
  public static func seeded(directory: URL, state: SyncState, records: [String: [JSONValue]]) throws -> Mirror {
    let mirror = try create(directory: directory, state: state)
    try mirror.write { tx in
      for (table, list) in records {
        for record in list {
          guard let id = record["id"]?.string else { continue }
          tx.put(table, id, record)
        }
      }
    }
    return mirror
  }

  /// Opens the mirror kept in `directory`: its last snapshot and every
  /// complete transaction after it. Throws `MirrorError.missing` when there is none.
  public static func open(directory: URL) throws -> Mirror {
    let pointer = directory.appendingPathComponent(MirrorFiles.current)
    guard FileManager.default.fileExists(atPath: pointer.path) else { throw MirrorError.missing }
    let text = String(decoding: try FileIO.read(pointer), as: UTF8.self)
    guard let generation = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      throw MirrorError.corrupt("The mirror's CURRENT file is unreadable.")
    }
    let folder = MirrorFiles.generationURL(directory, generation)
    let (data, snapshotBytes, journalBytes) = try MirrorFiles.readGeneration(folder)
    // Generations left behind by a compaction that stopped half way.
    for name in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    where name.hasPrefix("g") && name != "g\(generation)" {
      FileIO.remove(directory.appendingPathComponent(name))
    }
    let journal = try FileIO.Appender(folder.appendingPathComponent(MirrorFiles.journal))
    return Mirror(
      directory: directory, companyId: data.state.companyId,
      inner: Inner(
        data: data, generation: generation, journal: journal, journalBytes: journalBytes,
        snapshotBytes: snapshotBytes))
  }

  /// Removes the mirror's files (the company leaves this device). The
  /// mirror must not be used afterwards.
  public func destroy() {
    let observers = inner.withLock { inner in
      defer { inner.observers = [:] }
      return Array(inner.observers.values)
    }
    // Outside the lock: finishing a stream runs its clean-up, which takes the lock.
    for continuation in observers { continuation.finish() }
    FileIO.remove(directory)
  }

  // MARK: Reading

  public var state: SyncState { inner.withLock { $0.data.state } }

  /// One record, as stored here.
  public func record(_ table: String, _ id: String) -> JSONValue? {
    inner.withLock { $0.data.tables[table]?[id] }
  }

  /// Every record of a table, by id.
  public func recordsById(_ table: String) -> [String: JSONValue] {
    inner.withLock { $0.data.tables[table] ?? [:] }
  }

  /// Every record of a table, in no particular order.
  public func records(_ table: String) -> [JSONValue] {
    Array(recordsById(table).values)
  }

  public func count(_ table: String) -> Int {
    inner.withLock { $0.data.tables[table]?.count ?? 0 }
  }

  /// The server version of a record this device has.
  public func rev(_ table: String, _ id: String) -> SyncRev? {
    inner.withLock { $0.data.revs[table]?[id] }
  }

  /// Every change waiting for the cloud, oldest first, parked ones included.
  public var outbox: [OutboxEntry] {
    inner.withLock { inner in inner.data.outbox.keys.sorted().compactMap { inner.data.outbox[$0] } }
  }

  /// Changes waiting to be sent (`pendingCount`).
  public var pendingCount: Int { inner.withLock { $0.data.outbox.values.filter { !$0.parked }.count } }

  /// Changes the cloud refused, waiting for a retry or an undo (`parkedEntries`).
  public var parkedEntries: [OutboxEntry] { outbox.filter(\.parked) }

  public var fileQueue: [FileTask] {
    inner.withLock { inner in inner.data.fileQueue.keys.sorted().compactMap { inner.data.fileQueue[$0] } }
  }

  /// Told after each transaction that changed something. Each call makes a new stream.
  public func changes() -> AsyncStream<MirrorChange> {
    let (stream, continuation) = AsyncStream<MirrorChange>.makeStream(bufferingPolicy: .bufferingNewest(64))
    let id = inner.withLock { inner in
      let id = inner.nextObserver
      inner.nextObserver += 1
      inner.observers[id] = continuation
      return id
    }
    continuation.onTermination = { [weak self] _ in
      _ = self?.inner.withLock { $0.observers.removeValue(forKey: id) }
    }
    return stream
  }

  // MARK: Transactions

  /// Reads a consistent view of everything at once.
  func read<R: Sendable>(_ body: (MirrorView) throws -> R) rethrows -> R {
    let data = inner.withLock { $0.data }
    return try body(MirrorView(data: data))
  }

  /// One transaction: `body` changes a copy; if it returns, the changes are
  /// saved and take effect together; if it throws, nothing changes.
  @discardableResult
  func write<R: Sendable>(_ body: (inout MirrorTx) throws -> R) throws -> R {
    let (result, change): (R, MirrorChange?) = try inner.withLock { inner in
      var tx = MirrorTx(data: inner.data)
      let result = try body(&tx)
      let ops = tx.finish(from: inner.data)
      guard !ops.isEmpty else { return (result, nil) }
      let line = Journal.line(ops)
      try inner.journal.append(line)
      if let shadow = inner.shadow {
        do {
          try shadow.append(line)
          inner.shadowBytes += line.count
        } catch {
          // The next generation is given up; the current journal has the change.
          inner.shadow = nil
        }
      }
      inner.journalBytes += line.count
      inner.data = tx.data
      return (result, MirrorChange(tables: tx.touched, bookkeeping: tx.bookkeeping))
    }
    if let change {
      let observers = inner.withLock { Array($0.observers.values) }
      for observer in observers { observer.yield(change) }
    }
    return result
  }

  // MARK: Compaction

  /// Whether the journal has grown enough to fold into a new snapshot.
  public var needsCompaction: Bool {
    inner.withLock { $0.journalBytes > max(Self.compactAfterBytes, $0.snapshotBytes) }
  }

  /// Folds the journal into a new snapshot when it has grown (or always, with
  /// `force`). Reads and writes go on meanwhile: transactions are saved in
  /// both journals until the new snapshot is complete and takes over.
  public func compact(force: Bool = false) throws {
    let start: (MirrorData, Int, FileIO.Appender)? = try inner.withLock { inner in
      guard !inner.compacting, force || inner.journalBytes > max(Self.compactAfterBytes, inner.snapshotBytes)
      else { return nil }
      let next = inner.generation + 1
      let folder = MirrorFiles.generationURL(directory, next)
      FileIO.remove(folder)
      try FileIO.makeDirectory(folder)
      let shadow = try FileIO.Appender(folder.appendingPathComponent(MirrorFiles.journal))
      inner.shadow = shadow
      inner.shadowBytes = 0
      inner.compacting = true
      return (inner.data, next, shadow)
    }
    guard let (snapshot, next, shadow) = start else { return }
    let folder = MirrorFiles.generationURL(directory, next)
    do {
      let bytes = try MirrorFiles.writeSnapshot(snapshot, in: folder)
      try inner.withLock { inner in
        defer { inner.compacting = false }
        guard inner.shadow === shadow else {
          throw MirrorError.io("The new snapshot's journal could not be written.")
        }
        try FileIO.writeAtomically(Data(String(next).utf8), to: directory.appendingPathComponent(MirrorFiles.current))
        let old = MirrorFiles.generationURL(directory, inner.generation)
        inner.journal = shadow
        inner.shadow = nil
        inner.journalBytes = inner.shadowBytes
        inner.snapshotBytes = bytes
        inner.generation = next
        FileIO.remove(old)
      }
    } catch {
      inner.withLock { inner in
        if inner.shadow === shadow { inner.shadow = nil }
        inner.compacting = false
      }
      FileIO.remove(folder)
      throw error
    }
  }
}

/// A consistent read-only view of the mirror.
struct MirrorView {
  let data: MirrorData

  var state: SyncState { data.state }
  func record(_ table: String, _ id: String) -> JSONValue? { data.tables[table]?[id] }
  func records(_ table: String) -> [String: JSONValue] { data.tables[table] ?? [:] }
  func rev(_ table: String, _ id: String) -> SyncRev? { data.revs[table]?[id] }
  var outbox: [OutboxEntry] { data.outbox.keys.sorted().compactMap { data.outbox[$0] } }
}

/// The changes of one transaction, applied to a copy as they are made.
struct MirrorTx {
  var data: MirrorData
  private(set) var ops: [MirrorOp] = []
  private(set) var touched: Set<String> = []
  private(set) var bookkeeping = false

  init(data: MirrorData) {
    self.data = data
  }

  private mutating func apply(_ op: MirrorOp) {
    data.apply(op)
    ops.append(op)
  }

  /// The ops to save: those made, and the state and the held company record as they end up.
  mutating func finish(from original: MirrorData) -> [MirrorOp] {
    if data.state != original.state {
      ops.append(.state(data.state))
      bookkeeping = true
    }
    if data.pendingCompany != original.pendingCompany || data.pendingCompanyRev != original.pendingCompanyRev {
      ops.append(.pendingCompany(data.pendingCompany, rev: data.pendingCompanyRev))
      bookkeeping = true
    }
    return ops
  }

  // Records

  var state: SyncState {
    get { data.state }
    set { data.state = newValue }
  }

  var pendingCompany: JSONValue? {
    get { data.pendingCompany }
    set { data.pendingCompany = newValue }
  }

  var pendingCompanyRev: Int64? {
    get { data.pendingCompanyRev }
    set { data.pendingCompanyRev = newValue }
  }

  func record(_ table: String, _ id: String) -> JSONValue? { data.tables[table]?[id] }
  func records(_ table: String) -> [String: JSONValue] { data.tables[table] ?? [:] }

  mutating func put(_ table: String, _ id: String, _ record: JSONValue) {
    touched.insert(table)
    apply(.put(table: table, record: record, id: id))
  }

  mutating func delete(_ table: String, _ id: String) {
    guard data.tables[table]?[id] != nil else { return }
    touched.insert(table)
    apply(.delete(table: table, id: id))
  }

  /// Documents of a type with exactly this number.
  func documents(type: String, number: String) -> Set<String> {
    data.documentNumbers[type + "\u{1F}" + number] ?? []
  }

  // Revs

  func rev(_ table: String, _ id: String) -> SyncRev? { data.revs[table]?[id] }

  mutating func setRev(_ table: String, _ id: String, _ rev: SyncRev) {
    guard data.revs[table]?[id] != rev else { return }
    bookkeeping = true
    apply(.setRev(table: table, id: id, rev: rev))
  }

  mutating func deleteRev(_ table: String, _ id: String) {
    guard data.revs[table]?[id] != nil else { return }
    bookkeeping = true
    apply(.deleteRev(table: table, id: id))
  }

  // Outbox

  var outbox: [OutboxEntry] { data.outbox.keys.sorted().compactMap { data.outbox[$0] } }

  @discardableResult
  mutating func addOutbox(table: String, id: String, op: OutboxEntry.Op, at: Date, group: String?) -> Int64 {
    let entry = OutboxEntry(seq: data.nextSeq, table: table, id: id, op: op, at: at, group: group)
    bookkeeping = true
    apply(.putOutbox(entry))
    return entry.seq
  }

  mutating func updateOutbox(_ entry: OutboxEntry) {
    guard data.outbox[entry.seq] != nil, data.outbox[entry.seq] != entry else { return }
    bookkeeping = true
    apply(.putOutbox(entry))
  }

  mutating func deleteOutbox(_ seqs: [Int64]) {
    let present = seqs.filter { data.outbox[$0] != nil }
    guard !present.isEmpty else { return }
    bookkeeping = true
    apply(.deleteOutbox(present))
  }

  // File queue

  var fileQueue: [FileTask] { data.fileQueue.keys.sorted().compactMap { data.fileQueue[$0] } }

  mutating func addFile(path: String, at: Date, attempts: Int, lastError: String?, userId: String?) {
    bookkeeping = true
    apply(.putFile(FileTask(seq: data.nextFileSeq, path: path, at: at, attempts: attempts, lastError: lastError, userId: userId)))
  }

  mutating func updateFile(_ task: FileTask) {
    guard data.fileQueue[task.seq] != nil, data.fileQueue[task.seq] != task else { return }
    bookkeeping = true
    apply(.putFile(task))
  }

  mutating func deleteFiles(_ seqs: [Int64]) {
    let present = seqs.filter { data.fileQueue[$0] != nil }
    guard !present.isEmpty else { return }
    bookkeeping = true
    apply(.deleteFiles(present))
  }
}
