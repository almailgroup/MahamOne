import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public enum MirrorError: Error, Equatable, Sendable {
  /// The files couldn't be read or written (the disk is full, say). Nothing was changed.
  case io(String)
  /// A file of the mirror isn't what the mirror wrote.
  case corrupt(String)
  /// There is no mirror in this directory.
  case missing
}

/// One change inside a mirror transaction, as it is applied and as the
/// journal keeps it. Replaying the journal applies the same changes the
/// same way (`MirrorData.apply`).
enum MirrorOp: Equatable {
  case put(table: String, record: JSONValue, id: String)
  case delete(table: String, id: String)
  case setRev(table: String, id: String, rev: SyncRev)
  case deleteRev(table: String, id: String)
  case state(SyncState)
  case pendingCompany(JSONValue?, rev: Int64?)
  case putOutbox(OutboxEntry)
  case deleteOutbox([Int64])
  case putFile(FileTask)
  case deleteFiles([Int64])

  var json: JSONValue {
    switch self {
    case .put(let table, let record, let id): ["p", .string(table), .string(id), record]
    case .delete(let table, let id): ["d", .string(table), .string(id)]
    case .setRev(let table, let id, let rev):
      ["r", .string(table), .string(id), .number(Double(rev.rev)), rev.base ?? .null]
    case .deleteRev(let table, let id): ["x", .string(table), .string(id)]
    case .state(let state): ["s", state.json]
    case .pendingCompany(let record, let rev): ["c", record ?? .null, rev.map { .number(Double($0)) } ?? .null]
    case .putOutbox(let entry): ["o", entry.json]
    case .deleteOutbox(let seqs): ["O", .array(seqs.map { .number(Double($0)) })]
    case .putFile(let task): ["f", task.json]
    case .deleteFiles(let seqs): ["F", .array(seqs.map { .number(Double($0)) })]
    }
  }

  init(json: JSONValue) throws {
    guard case .array(let parts) = json, let kind = parts.first?.string else {
      throw MirrorError.corrupt("A journal entry has no kind.")
    }
    func text(_ i: Int) throws -> String {
      guard parts.indices.contains(i), let value = parts[i].string else {
        throw MirrorError.corrupt("A journal entry is incomplete.")
      }
      return value
    }
    func value(_ i: Int) throws -> JSONValue {
      guard parts.indices.contains(i) else { throw MirrorError.corrupt("A journal entry is incomplete.") }
      return parts[i]
    }
    func seqs(_ i: Int) throws -> [Int64] {
      guard let items = try value(i).array else { throw MirrorError.corrupt("A journal entry is incomplete.") }
      return items.compactMap(\.int64Value)
    }
    switch kind {
    case "p": self = .put(table: try text(1), record: try value(3), id: try text(2))
    case "d": self = .delete(table: try text(1), id: try text(2))
    case "r":
      guard let rev = try value(3).int64Value else { throw MirrorError.corrupt("A journal rev is not a number.") }
      let base = try value(4)
      self = .setRev(table: try text(1), id: try text(2), rev: SyncRev(rev: rev, base: base.nonNull))
    case "x": self = .deleteRev(table: try text(1), id: try text(2))
    case "s":
      guard let state = SyncState(json: try value(1)) else { throw MirrorError.corrupt("A journal state is unreadable.") }
      self = .state(state)
    case "c":
      let record = try value(1)
      self = .pendingCompany(record.nonNull, rev: try value(2).int64Value)
    case "o":
      guard let entry = OutboxEntry(json: try value(1)) else { throw MirrorError.corrupt("A journal outbox entry is unreadable.") }
      self = .putOutbox(entry)
    case "O": self = .deleteOutbox(try seqs(1))
    case "f":
      guard let task = FileTask(json: try value(1)) else { throw MirrorError.corrupt("A journal file task is unreadable.") }
      self = .putFile(task)
    case "F": self = .deleteFiles(try seqs(1))
    default: throw MirrorError.corrupt("A journal entry of an unknown kind: \(kind).")
    }
  }
}

/// Everything the mirror keeps for one company.
struct MirrorData {
  var tables: [String: [String: JSONValue]] = [:]
  var revs: [String: [String: SyncRev]] = [:]
  var state: SyncState
  /// While downloading: the company record, stored once everything else is here.
  var pendingCompany: JSONValue?
  var pendingCompanyRev: Int64?
  var outbox: [Int64: OutboxEntry] = [:]
  var nextSeq: Int64 = 1
  var fileQueue: [Int64: FileTask] = [:]
  var nextFileSeq: Int64 = 1
  /// Documents by type and number (the web's [companyId+type+number] index), worked out, not stored.
  var documentNumbers: [String: Set<String>] = [:]

  init(state: SyncState) {
    self.state = state
  }

  static func numberKey(_ document: JSONValue?) -> String? {
    guard case .some(.string(let type)) = document?["type"], case .some(.string(let number)) = document?["number"]
    else { return nil }
    return type + "\u{1F}" + number
  }

  mutating func index(_ table: String, id: String, before: JSONValue?, after: JSONValue?) {
    guard table == "documents" else { return }
    if let key = Self.numberKey(before) {
      documentNumbers[key]?.remove(id)
      if documentNumbers[key]?.isEmpty == true { documentNumbers[key] = nil }
    }
    if let key = Self.numberKey(after) { documentNumbers[key, default: []].insert(id) }
  }

  mutating func apply(_ op: MirrorOp) {
    switch op {
    case .put(let table, let record, let id):
      let before = tables[table]?[id]
      tables[table, default: [:]][id] = record
      index(table, id: id, before: before, after: record)
    case .delete(let table, let id):
      let before = tables[table]?.removeValue(forKey: id)
      index(table, id: id, before: before, after: nil)
    case .setRev(let table, let id, let rev):
      revs[table, default: [:]][id] = rev
    case .deleteRev(let table, let id):
      revs[table]?[id] = nil
    case .state(let next):
      state = next
    case .pendingCompany(let record, let rev):
      pendingCompany = record
      pendingCompanyRev = rev
    case .putOutbox(let entry):
      outbox[entry.seq] = entry
      nextSeq = max(nextSeq, entry.seq + 1)
    case .deleteOutbox(let seqs):
      for seq in seqs { outbox[seq] = nil }
    case .putFile(let task):
      fileQueue[task.seq] = task
      nextFileSeq = max(nextFileSeq, task.seq + 1)
    case .deleteFiles(let seqs):
      for seq in seqs { fileQueue[seq] = nil }
    }
  }

  mutating func reindex() {
    documentNumbers = [:]
    for (id, document) in tables["documents"] ?? [:] {
      if let key = Self.numberKey(document) { documentNumbers[key, default: []].insert(id) }
    }
  }
}

/// The mirror's files: a snapshot (one JSON file per table, the revs, and a
/// state file) in a generation folder named by `CURRENT`, and a journal
/// that each transaction appends to, checksummed, before it counts as done.
/// A compaction writes a new generation and switches `CURRENT` with one
/// rename, so a crash at any moment leaves the last complete state.
enum MirrorFiles {
  static let current = "CURRENT"
  static let journal = "journal.log"
  static let stateFile = "state.json"
  static let revsFile = "revs.json"

  static func generationURL(_ directory: URL, _ generation: Int) -> URL {
    directory.appendingPathComponent("g\(generation)", isDirectory: true)
  }

  /// `t-<table>.json` for a name of plain letters and digits (every table
  /// the cloud has), `h-<hex of its UTF-8>.json` for anything else.
  static func tableFile(_ table: String) -> String {
    let plain =
      !table.isEmpty
      && table.unicodeScalars.allSatisfy {
        ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)
      }
    return plain ? "t-\(table).json" : "h-" + hex(Array(table.utf8)) + ".json"
  }

  static func tableName(fromFile name: String) -> String? {
    guard name.hasSuffix(".json") else { return nil }
    let stem = String(name.dropFirst(2).dropLast(5))
    if name.hasPrefix("t-") { return stem }
    guard name.hasPrefix("h-"), stem.count % 2 == 0 else { return nil }
    var bytes: [UInt8] = []
    var index = stem.startIndex
    while index < stem.endIndex {
      let next = stem.index(index, offsetBy: 2)
      guard let byte = UInt8(stem[index..<next], radix: 16) else { return nil }
      bytes.append(byte)
      index = next
    }
    return String(validating: bytes, as: UTF8.self)
  }

  static func hex(_ bytes: [UInt8]) -> String {
    let digits = Array("0123456789abcdef")
    return String(bytes.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 0x0F)]] })
  }

  // MARK: Snapshot

  /// Writes a whole generation's snapshot, every file synced to disk. The
  /// journal is not touched: it is opened (and made) by its appender.
  static func writeSnapshot(_ data: MirrorData, in folder: URL) throws -> Int {
    try FileIO.makeDirectory(folder)
    var bytes = 0
    for (table, records) in data.tables where !records.isEmpty {
      let file = SyncJSON.data(.object(records))
      bytes += file.count
      try FileIO.writeAtomically(file, to: folder.appendingPathComponent(tableFile(table)))
    }
    var revs: [String: JSONValue] = [:]
    for (table, entries) in data.revs where !entries.isEmpty {
      revs[table] = .object(
        entries.mapValues { rev in
          rev.base.map { .array([.number(Double(rev.rev)), $0]) } ?? .number(Double(rev.rev))
        })
    }
    let revsFile = SyncJSON.data(.object(revs))
    bytes += revsFile.count
    try FileIO.writeAtomically(revsFile, to: folder.appendingPathComponent(Self.revsFile))
    var state: [String: JSONValue] = [
      "version": 1,
      "state": data.state.json,
      "outbox": .array(data.outbox.keys.sorted().compactMap { data.outbox[$0]?.json }),
      "fileQueue": .array(data.fileQueue.keys.sorted().compactMap { data.fileQueue[$0]?.json }),
      "nextSeq": .number(Double(data.nextSeq)),
      "nextFileSeq": .number(Double(data.nextFileSeq)),
    ]
    state["pendingCompany"] = data.pendingCompany
    state["pendingCompanyRev"] = data.pendingCompanyRev.map { .number(Double($0)) }
    let stateFile = SyncJSON.data(.object(state))
    bytes += stateFile.count
    try FileIO.writeAtomically(stateFile, to: folder.appendingPathComponent(Self.stateFile))
    return bytes
  }

  /// Reads a generation: its snapshot, then its journal (a torn last entry is
  /// dropped and cut off). Returns the data, the snapshot's size and the journal's good length.
  static func readGeneration(_ folder: URL) throws -> (MirrorData, snapshotBytes: Int, journalBytes: Int) {
    let stateData = try FileIO.read(folder.appendingPathComponent(stateFile))
    let stateJSON = try SyncJSON.parse(stateData)
    guard let state = stateJSON["state"].flatMap(SyncState.init(json:)) else {
      throw MirrorError.corrupt("The mirror's state file is unreadable.")
    }
    var data = MirrorData(state: state)
    var bytes = stateData.count
    data.pendingCompany = stateJSON["pendingCompany"]?.nonNull
    data.pendingCompanyRev = stateJSON["pendingCompanyRev"]?.int64Value
    for entry in stateJSON["outbox"]?.array ?? [] {
      guard let entry = OutboxEntry(json: entry) else { throw MirrorError.corrupt("An outbox entry is unreadable.") }
      data.outbox[entry.seq] = entry
    }
    for task in stateJSON["fileQueue"]?.array ?? [] {
      guard let task = FileTask(json: task) else { throw MirrorError.corrupt("A file task is unreadable.") }
      data.fileQueue[task.seq] = task
    }
    data.nextSeq = max(stateJSON["nextSeq"]?.int64Value ?? 1, (data.outbox.keys.max() ?? 0) + 1)
    data.nextFileSeq = max(stateJSON["nextFileSeq"]?.int64Value ?? 1, (data.fileQueue.keys.max() ?? 0) + 1)

    let revsData = try FileIO.read(folder.appendingPathComponent(revsFile))
    bytes += revsData.count
    for (table, entries) in try SyncJSON.parse(revsData).object ?? [:] {
      var revs: [String: SyncRev] = [:]
      for (id, value) in entries.object ?? [:] {
        if let rev = value.int64Value {
          revs[id] = SyncRev(rev: rev)
        } else if let pair = value.array, pair.count == 2, let rev = pair[0].int64Value {
          revs[id] = SyncRev(rev: rev, base: pair[1])
        } else {
          throw MirrorError.corrupt("A rev is unreadable.")
        }
      }
      data.revs[table] = revs
    }

    let names: [String]
    do {
      names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    } catch {
      throw MirrorError.io("Couldn't list the mirror: \(error)")
    }
    for name in names {
      guard let table = tableName(fromFile: name) else { continue }
      let content = try FileIO.read(folder.appendingPathComponent(name))
      bytes += content.count
      guard case .object(let records) = try SyncJSON.parse(content) else {
        throw MirrorError.corrupt("The mirror's \(table) file is unreadable.")
      }
      data.tables[table] = records
    }

    let journalURL = folder.appendingPathComponent(journal)
    let journalData = (try? FileIO.read(journalURL)) ?? Data()
    let good = try Journal.replay(journalData, into: &data)
    if good < journalData.count { try FileIO.truncate(journalURL, to: good) }
    data.reindex()
    return (data, bytes, good)
  }

}

/// Journal lines: `<16 hex digits of FNV-1a 64> <JSON array of ops>\n`.
enum Journal {
  static func line(_ ops: [MirrorOp]) -> Data {
    var json: [UInt8] = []
    SyncJSON.write(.array(ops.map(\.json)), into: &json)
    let sum = String(fnv(json), radix: 16)
    var out = Array((String(repeating: "0", count: 16 - sum.count) + sum).utf8)
    out.append(0x20)
    out.append(contentsOf: json)
    out.append(0x0A)
    return Data(out)
  }

  /// Applies every complete, intact entry; returns the length of the good part.
  static func replay(_ journal: Data, into data: inout MirrorData) throws -> Int {
    let bytes = [UInt8](journal)
    var start = 0
    while start < bytes.count {
      guard let end = bytes[start...].firstIndex(of: 0x0A) else { break }
      let line = bytes[start..<end]
      guard line.count > 17, line[line.startIndex + 16] == 0x20,
        let sum = UInt64(String(decoding: line.prefix(16), as: UTF8.self), radix: 16)
      else { break }
      let json = Array(line.dropFirst(17))
      guard fnv(json) == sum, let value = try? SyncJSON.parse(Data(json)), case .array(let items) = value else {
        break
      }
      let ops = try items.map(MirrorOp.init(json:))
      for op in ops { data.apply(op) }
      start = end + 1
    }
    return start
  }

  static func fnv(_ bytes: [UInt8]) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in bytes {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01B3
    }
    return hash
  }
}

/// Plain file work, synced to disk where it matters.
enum FileIO {
  static func read(_ url: URL) throws -> Data {
    do {
      return try Data(contentsOf: url)
    } catch {
      throw MirrorError.io("Couldn't read \(url.lastPathComponent): \(error)")
    }
  }

  static func makeDirectory(_ url: URL) throws {
    do {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    } catch {
      throw MirrorError.io("Couldn't make \(url.lastPathComponent): \(error)")
    }
  }

  static func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
  }

  /// Writes a file whole: a temporary file, synced, then renamed over the old one.
  static func writeAtomically(_ data: Data, to url: URL) throws {
    let folder = url.deletingLastPathComponent()
    let temporary = folder.appendingPathComponent(".\(url.lastPathComponent).tmp")
    let fd = open(temporary.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    guard fd >= 0 else { throw MirrorError.io("Couldn't write \(url.lastPathComponent) (\(errno)).") }
    do {
      try writeAll(fd, data)
      guard fsync(fd) == 0 else { throw MirrorError.io("Couldn't save \(url.lastPathComponent) (\(errno)).") }
    } catch {
      close(fd)
      remove(temporary)
      throw error
    }
    close(fd)
    guard rename(temporary.path, url.path) == 0 else {
      remove(temporary)
      throw MirrorError.io("Couldn't replace \(url.lastPathComponent) (\(errno)).")
    }
    syncDirectory(folder)
  }

  static func writeAll(_ fd: Int32, _ data: Data) throws {
    try data.withUnsafeBytes { raw in
      guard var pointer = raw.baseAddress else { return }
      var left = raw.count
      while left > 0 {
        #if canImport(Darwin)
          let written = Darwin.write(fd, pointer, left)
        #else
          let written = Glibc.write(fd, pointer, left)
        #endif
        if written < 0 {
          if errno == EINTR { continue }
          throw MirrorError.io("Couldn't write (\(errno)).")
        }
        left -= written
        pointer = pointer.advanced(by: written)
      }
    }
  }

  static func syncDirectory(_ url: URL) {
    let fd = open(url.path, O_RDONLY)
    guard fd >= 0 else { return }
    _ = fsync(fd)
    close(fd)
  }

  static func truncate(_ url: URL, to length: Int) throws {
    let fd = open(url.path, O_WRONLY)
    guard fd >= 0 else { throw MirrorError.io("Couldn't open \(url.lastPathComponent) (\(errno)).") }
    defer { close(fd) }
    guard ftruncate(fd, off_t(length)) == 0, fsync(fd) == 0 else {
      throw MirrorError.io("Couldn't cut \(url.lastPathComponent) (\(errno)).")
    }
  }

  /// A journal open for appending.
  final class Appender: @unchecked Sendable {
    let fd: Int32

    init(_ url: URL) throws {
      fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
      guard fd >= 0 else { throw MirrorError.io("Couldn't open the journal (\(errno)).") }
      // The new file's name is in its folder for good.
      _ = fsync(fd)
      FileIO.syncDirectory(url.deletingLastPathComponent())
    }

    /// Appends and syncs to disk: once this returns, the entry survives a crash.
    func append(_ data: Data) throws {
      try FileIO.writeAll(fd, data)
      guard fsync(fd) == 0 else { throw MirrorError.io("Couldn't save the journal (\(errno)).") }
    }

    deinit { close(fd) }
  }
}
