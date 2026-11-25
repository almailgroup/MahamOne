import Foundation
import Synchronization

@testable import MahamKit

let OWNER = "user-owner"
let STAFF = "user-staff"
let ACCOUNTANT = "user-accountant"
let CO = "co-1"

/// A numbering rule as the web's company-patch tests write it.
func rule(_ next: Int, _ period: String = "2026", pattern: String = "INV-{counter}") -> JSONValue {
  ["pattern": .string(pattern), "next": .number(Double(next)), "padding": 4, "reset": "yearly", "period": .string(period)]
}

func companyRecord(_ fields: [String: JSONValue] = [:]) -> JSONValue {
  var record: [String: JSONValue] = [
    "id": .string(CO), "name": "Al Mail Trading", "phone": "", "website": "",
    "address": ["line1": "Block 4", "city": "Salmiya", "country": "KW"],
    "accounting": ["template": "kw", "lockDate": nil],
    "numbering": ["invoice": rule(5), "payment": rule(3)],
  ]
  for (key, value) in fields { record[key] = value }
  return .object(record)
}

func record(_ id: String, _ fields: [String: JSONValue] = [:], company: String = CO) -> JSONValue {
  var record: [String: JSONValue] = ["id": .string(id), "companyId": .string(company)]
  for (key, value) in fields { record[key] = value }
  return .object(record)
}

/// The folder this test run keeps its mirrors in. Runs that ended more than
/// an hour ago are swept away (never one that may still be running).
let syncTestRoot: URL = {
  let manager = FileManager.default
  let temporary = manager.temporaryDirectory
  let cutoff = Date().addingTimeInterval(-3600)
  for name in (try? manager.contentsOfDirectory(atPath: temporary.path)) ?? [] where name.hasPrefix("maham-sync-tests-") {
    let url = temporary.appendingPathComponent(name)
    let modified = (try? manager.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    if let modified, modified < cutoff { try? manager.removeItem(at: url) }
  }
  return temporary.appendingPathComponent("maham-sync-tests-\(UUID().uuidString)", isDirectory: true)
}()

func temporaryDirectory() -> URL {
  syncTestRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

/// A wall clock a test moves by hand.
final class TestNow: Sendable {
  private let value = Mutex(Date(timeIntervalSince1970: 1_795_000_000))
  var date: Date { value.withLock { $0 } }
  func advance(_ seconds: TimeInterval) { value.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

/// A company in the cloud as the web would have uploaded it: the company
/// record, customers, an invoice with its receipt, and People's data with
/// what makes files and activity private.
func seedCompany(_ cloud: FakeCloud) {
  cloud.addCompany(CO, owner: OWNER)
  cloud.seed(CO, "companies", companyRecord())
  cloud.seed(CO, "clients", record("c1", ["name": "Gulf Pearl Hotel"]))
  cloud.seed(CO, "clients", record("c2", ["name": "Salmiya Stores"]))
  cloud.seed(CO, "clients", record("c3", ["name": "Hawalli Traders"]))
  cloud.seed(CO, "documents", record("d1", ["type": "invoice", "number": "INV-0001", "clientId": "c1", "total": 300.5]))
  cloud.seed(CO, "attachments", record("a-inv", ["ownerId": "d1", "name": "receipt.pdf", "dataUrl": "", "storagePath": "co-1/a-inv"]))
  cloud.seed(CO, "activities", record("act-inv", ["entity": "invoice", "entityId": "d1", "action": "created"]))
  cloud.seed(CO, "journals", record("j-tr", ["kind": "transfer", "number": "MJ-1"]))
  cloud.seed(CO, "employees", record("e1", ["name": "Rajesh Kumar", "basicSalary": 450]))
  cloud.seed(CO, "payRuns", record("pr1", ["period": "2026-10"]))
  cloud.seed(CO, "journals", record("j-pay", ["kind": "payroll", "number": "MJ-2"]))
  cloud.seed(CO, "complianceDocuments", record("doc-emp", ["employeeId": "e1", "kind": "passport"]))
  cloud.seed(CO, "complianceDocuments", record("doc-co", ["employeeId": nil, "kind": "licence"]))
  cloud.seed(CO, "renewals", record("ren-emp", ["employeeId": "e1"]))
  cloud.seed(CO, "attachments", record("a-emp", ["ownerId": "e1", "name": "passport.jpg", "dataUrl": "", "_private": true]))
  cloud.seed(CO, "activities", record("act-emp", ["entity": "employee", "entityId": "e1", "action": "updated"]))
}

/// What only owners, admins and accountants hold, of seedCompany.
let privateIds: [(String, String)] = [
  ("employees", "e1"), ("payRuns", "pr1"), ("journals", "j-pay"), ("complianceDocuments", "doc-emp"),
  ("renewals", "ren-emp"), ("attachments", "a-emp"), ("activities", "act-emp"),
]

/// A device of `user` that downloaded the company and synced once.
func downloadedEngine(
  _ cloud: FakeCloud, user: String = OWNER, role: MemberRole = .owner, configuration: SyncConfiguration = SyncConfiguration(),
  wrap: (@Sendable (Mirror, any CloudAPI) -> any CloudAPI)? = nil, directory: URL = temporaryDirectory()
) async throws -> SyncEngine {
  let base = cloud.client(user)
  let mirror = try await SyncEngine.startDownload(
    CloudCompany(id: CO, name: "Al Mail Trading", role: role), userId: user, api: base, directory: directory)
  let api = wrap?(mirror, base) ?? base
  let engine = SyncEngine(mirror: mirror, api: api, userId: user, configuration: configuration)
  try await engine.sync()
  return engine
}

/// Waits (briefly) until `condition` holds.
func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
  for _ in 0..<400 {
    if await condition() { return true }
    try? await Task.sleep(nanoseconds: 5_000_000)
  }
  return await condition()
}

extension Mirror {
  /// Every record here, by table and id (what a test compares with the cloud).
  func everything() -> [String: [String: JSONValue]] {
    var all: [String: [String: JSONValue]] = [:]
    for table in SyncTables.all {
      let records = recordsById(table)
      if !records.isEmpty { all[table] = records }
    }
    return all
  }
}

extension FakeCloud {
  /// What `user` may read of the company, by table and id, without the cloud's `_private` mark.
  func visible(to user: String) -> [String: [String: JSONValue]] {
    state.withLock { s in
      var all: [String: [String: JSONValue]] = [:]
      for row in s.records.values where row.company == CO && FakeCloud.canRead(s, CO, user, row.tbl, row.data) {
        all[row.tbl, default: [:]][row.id] = row.data.removing("_private")
      }
      return all
    }
  }
}
