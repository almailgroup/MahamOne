import Foundation
import Testing

@testable import MahamKit

@Suite("Sync: the mirror")
struct SyncMirrorTests {
  func newMirror(_ directory: URL = temporaryDirectory()) throws -> Mirror {
    try Mirror.create(directory: directory, state: SyncState(companyId: CO, userId: OWNER, role: .owner, status: .ready, name: "Al Mail Trading"))
  }

  @Test("keeps records, revs, state and outbox across a restart")
  func persists() throws {
    let directory = temporaryDirectory()
    defer { FileIO.remove(directory) }
    let mirror = try newMirror(directory)
    try mirror.write { tx in
      tx.put("clients", "c1", record("c1", ["name": "Gulf Pearl Hotel", "notes": nil]))
      tx.put("documents", "d1", record("d1", ["type": "invoice", "number": "INV-0001"]))
      tx.put("companies", CO, companyRecord())
      tx.setRev("clients", "c1", SyncRev(rev: 7))
      tx.setRev("companies", CO, SyncRev(rev: 9, base: companyRecord()))
      tx.state.cursor = 9
      tx.state.features = ["tables_v16"]
      tx.addOutbox(table: "clients", id: "c1", op: .put, at: Date(timeIntervalSince1970: 1000), group: "g1")
    }
    try mirror.write { tx in tx.delete("documents", "d1") }
    let again = try Mirror.open(directory: directory)
    #expect(again.record("clients", "c1") == record("c1", ["name": "Gulf Pearl Hotel", "notes": nil]))
    #expect(again.record("documents", "d1") == nil)
    #expect(again.rev("clients", "c1") == SyncRev(rev: 7))
    #expect(again.rev("companies", CO)?.base == companyRecord())
    #expect(again.state == mirror.state)
    #expect(again.outbox == mirror.outbox)
    #expect(again.outbox.first?.group == "g1")
    // And after the journal is folded into a snapshot.
    try again.compact(force: true)
    try again.write { tx in tx.put("clients", "c2", record("c2")) }
    let third = try Mirror.open(directory: directory)
    #expect(third.everything() == again.everything())
    #expect(third.state == again.state)
    #expect(third.outbox == again.outbox)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == ["CURRENT", "g2"])
  }

  @Test("a transaction that fails changes nothing, here or on disk")
  func rollback() throws {
    struct Refused: Error {}
    let directory = temporaryDirectory()
    defer { FileIO.remove(directory) }
    let mirror = try newMirror(directory)
    try mirror.write { tx in tx.put("clients", "c1", record("c1", ["name": "A"])) }
    #expect(throws: Refused.self) {
      try mirror.write { tx in
        tx.put("clients", "c1", record("c1", ["name": "B"]))
        tx.state.cursor = 99
        tx.addOutbox(table: "clients", id: "c1", op: .put, at: Date(), group: nil)
        throw Refused()
      }
    }
    #expect(mirror.record("clients", "c1")?["name"] == "A")
    #expect(mirror.state.cursor == 0)
    #expect(mirror.outbox.isEmpty)
    let again = try Mirror.open(directory: directory)
    #expect(again.record("clients", "c1")?["name"] == "A")
    #expect(again.state.cursor == 0)
  }

  @Test("a transaction cut off half way through writing is dropped whole")
  func tornJournal() throws {
    let directory = temporaryDirectory()
    defer { FileIO.remove(directory) }
    let mirror = try newMirror(directory)
    try mirror.write { tx in tx.put("clients", "c1", record("c1")) }
    try mirror.write { tx in
      tx.put("clients", "c2", record("c2"))
      tx.state.cursor = 5
    }
    let journal = directory.appendingPathComponent("g1").appendingPathComponent(MirrorFiles.journal)
    var bytes = try Data(contentsOf: journal)
    bytes.removeLast(9)
    try bytes.write(to: journal)
    let again = try Mirror.open(directory: directory)
    #expect(again.record("clients", "c1") != nil)
    #expect(again.record("clients", "c2") == nil)
    #expect(again.state.cursor == 0)
    // What comes next is kept after the cut.
    try again.write { tx in tx.put("clients", "c3", record("c3")) }
    let third = try Mirror.open(directory: directory)
    #expect(third.record("clients", "c3") != nil)
    #expect(third.record("clients", "c2") == nil)
  }

  @Test("tells screens what changed, after it is saved")
  func notifications() async throws {
    let mirror = try newMirror()
    defer { mirror.destroy() }
    let changes = mirror.changes()
    try mirror.write { tx in tx.put("clients", "c1", record("c1")) }
    try mirror.write { _ in }
    try mirror.write { tx in tx.state.cursor = 4 }
    var iterator = changes.makeAsyncIterator()
    #expect(await iterator.next() == MirrorChange(tables: ["clients"], bookkeeping: false))
    // A transaction that changed nothing tells nothing.
    #expect(await iterator.next() == MirrorChange(tables: [], bookkeeping: true))
  }

  @Test("finds documents by type and number, as the web's index does")
  func documentIndex() throws {
    let mirror = try newMirror()
    defer { mirror.destroy() }
    try mirror.write { tx in
      tx.put("documents", "d1", record("d1", ["type": "invoice", "number": "INV-1"]))
      tx.put("documents", "d2", record("d2", ["type": "invoice", "number": "INV-1"]))
      tx.put("documents", "d3", record("d3", ["type": "quote", "number": "INV-1"]))
    }
    try mirror.write { tx in
      #expect(tx.documents(type: "invoice", number: "INV-1") == ["d1", "d2"])
      tx.put("documents", "d2", record("d2", ["type": "invoice", "number": "INV-2"]))
      #expect(tx.documents(type: "invoice", number: "INV-1") == ["d1"])
      tx.delete("documents", "d1")
      #expect(tx.documents(type: "invoice", number: "INV-1").isEmpty)
    }
  }

  @Test("copes with a company of 50,000 records")
  func large() throws {
    let directory = temporaryDirectory()
    defer { FileIO.remove(directory) }
    let mirror = try newMirror(directory)
    let started = Date()
    for page in 0..<100 {
      try mirror.write { tx in
        for i in 0..<500 {
          let n = page * 500 + i
          let table = ["documents", "activities", "stockMovements", "clients"][n % 4]
          tx.put(
            table, "r\(n)",
            record(
              "r\(n)",
              [
                "type": "invoice", "number": .string("INV-\(n)"), "name": .string("Record number \(n) — سجل"),
                "lines": [["name": "Installation", "quantity": 2, "unitPrice": 150.25], ["name": "Visit", "quantity": 1, "unitPrice": 20]],
                "total": .number(Double(n) * 1.5),
              ]))
          tx.setRev(table, "r\(n)", SyncRev(rev: Int64(n + 1)))
        }
        tx.state.cursor = Int64(page * 500 + 500)
      }
      try mirror.compact()
    }
    let written = Date().timeIntervalSince(started)
    try mirror.compact(force: true)
    let opening = Date()
    let again = try Mirror.open(directory: directory)
    let opened = Date().timeIntervalSince(opening)
    #expect(SyncTables.all.map { again.count($0) }.reduce(0, +) == 50_000)
    #expect(again.state.cursor == 50_000)
    #expect(again.record("documents", "r0")?["lines"]?[0]?["unitPrice"] == 150.25)
    #expect(again.rev("clients", "r49999") == SyncRev(rev: 50_000))
    // Generous bounds (debug build, shared machine): the point is that nothing is quadratic.
    #expect(written < 120, "100 pages of 500 took \(written) s")
    #expect(opened < 30, "opening took \(opened) s")
  }
}
