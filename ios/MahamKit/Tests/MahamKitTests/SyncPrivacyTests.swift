import Foundation
import Testing

@testable import MahamKit

/// Ports of the private-record cases of src/cloud/roles.test.ts.
@Suite("Sync: privacy")
struct SyncPrivacyTests {
  /// Another record of the company, as the database would find it.
  static let others: [String: [String: JSONValue]] = [
    "employees": ["emp-1": ["id": "emp-1", "name": "Rajesh Kumar"]],
    "complianceDocuments": [
      "doc-emp": ["id": "doc-emp", "employeeId": "emp-1"],
      "doc-co": ["id": "doc-co", "employeeId": nil],
    ],
    "renewals": ["ren-emp": ["id": "ren-emp", "employeeId": "emp-1"]],
  ]
  let lookup: Privacy.Lookup = { table, id in SyncPrivacyTests.others[table]?[id] }

  func isPrivate(_ table: String, _ record: JSONValue?, _ lookup: Privacy.Lookup? = nil) -> Bool {
    Privacy.isPrivateRecord(table, record, lookup: lookup)
  }

  @Test("are payroll and people data, whatever they contain")
  func peopleTables() {
    for table in ["employees", "payRuns", "payrollSettings", "leaveRecords", "letterTemplates", "employeeLetters", "staffingCostings"] {
      #expect(isPrivate(table, nil))
      #expect(isPrivate(table, ["id": "x"]))
    }
    #expect(!isPrivate("clients", ["id": "c"]))
  }

  @Test("include an employee’s documents and renewals, not the company’s")
  func documents() {
    #expect(isPrivate("complianceDocuments", ["employeeId": "emp-1"]))
    #expect(!isPrivate("complianceDocuments", ["employeeId": ""]))
    #expect(!isPrivate("complianceDocuments", ["employeeId": nil]))
    #expect(isPrivate("renewals", ["employeeId": "emp-1"]))
  }

  @Test("include payroll journals, which show salaries")
  func journals() {
    #expect(isPrivate("journals", ["kind": "payroll"]))
    #expect(!isPrivate("journals", ["kind": "transfer"]))
    #expect(!isPrivate("journals", ["number": "MJ-1"]))
  }

  @Test("include activity and files about employees and their documents")
  func activityAndFiles() {
    #expect(isPrivate("activities", ["entity": "employee", "entityId": "emp-1"]))
    #expect(isPrivate("activities", ["entity": "payroll", "entityId": "run-1"]))
    #expect(isPrivate("activities", ["entity": "costing", "entityId": "cost-1"]))
    #expect(!isPrivate("activities", ["entity": "invoice", "entityId": "inv-1"]))
    func about(_ id: String, _ extra: [String: JSONValue] = [:]) -> JSONValue {
      var fields: [String: JSONValue] = ["entity": "compliance", "entityId": .string(id)]
      for (k, v) in extra { fields[k] = v }
      return .object(fields)
    }
    #expect(isPrivate("activities", about("doc-emp"), lookup))
    #expect(isPrivate("activities", about("ren-emp"), lookup))
    #expect(!isPrivate("activities", about("doc-co"), lookup))
    // Logged about an employee's document: private without finding the document.
    #expect(isPrivate("activities", about("gone", ["employeeId": "emp-1"])))
    #expect(!isPrivate("activities", about("gone", ["employeeId": nil])))

    func file(_ owner: String) -> JSONValue { ["id": "att", "ownerId": .string(owner)] }
    #expect(isPrivate("attachments", file("emp-1"), lookup))
    #expect(isPrivate("attachments", file("doc-emp"), lookup))
    #expect(isPrivate("attachments", file("ren-emp"), lookup))
    #expect(!isPrivate("attachments", file("doc-co"), lookup))
    #expect(!isPrivate("attachments", file("inv-1"), lookup))
    #expect(!isPrivate("attachments", file("emp-1")))
  }

  @Test("include anything marked private, which can only add privacy")
  func marked() {
    #expect(isPrivate("attachments", ["ownerId": "inv-1", "_private": true], lookup))
    #expect(isPrivate("activities", ["entity": "invoice", "_private": true]))
    #expect(isPrivate("employees", ["_private": false]))
    #expect(!isPrivate("clients", ["_private": "true"]))
  }

  @Test("of database version 16: letters, approvals about people, confidential documents")
  func version16() {
    let records: [String: [String: JSONValue]] = [
      "complianceDocuments": [
        "doc-secret": ["id": "doc-secret", "employeeId": nil, "confidential": true],
        "doc-open": ["id": "doc-open", "employeeId": nil, "confidential": false],
      ],
      "renewals": [
        "ren-secret": ["id": "ren-secret", "documentKey": "doc:doc-secret", "documentId": "doc-secret"],
        "ren-open": ["id": "ren-open", "documentKey": "doc:doc-open", "documentId": "doc-open"],
      ],
      "letterTemplates": ["tpl-1": ["id": "tpl-1"]],
      "employeeLetters": ["let-1": ["id": "let-1", "employeeId": "emp-1"]],
    ]
    let find: Privacy.Lookup = { table, id in records[table]?[id] }
    func approval(_ subject: JSONValue?) -> JSONValue {
      var fields: [String: JSONValue] = ["id": "apr", "kind": "payroll"]
      fields["subjectTbl"] = subject
      return .object(fields)
    }
    #expect(isPrivate("approvals", approval("payRuns")))
    #expect(isPrivate("approvals", approval("employeeLetters")))
    #expect(!isPrivate("approvals", approval("documents")))
    #expect(!isPrivate("approvals", approval(nil)))
    #expect(!isPrivate("vehicles", ["id": "v", "driverEmployeeId": "emp-1"]))
    #expect(!isPrivate("chequeLayouts", ["id": "l"]))

    #expect(isPrivate("complianceDocuments", ["confidential": true]))
    #expect(!isPrivate("complianceDocuments", ["confidential": false]))
    #expect(!isPrivate("complianceDocuments", ["confidential": "true"]))
    #expect(isPrivate("renewals", ["documentKey": "doc:doc-secret"], find))
    #expect(isPrivate("renewals", ["documentId": "doc-secret"], find))
    #expect(!isPrivate("renewals", ["documentKey": "doc:doc-secret"]))
    #expect(!isPrivate("renewals", ["documentKey": "doc:doc-open"], find))
    #expect(!isPrivate("renewals", ["documentKey": "emp:emp-1:passport"], find))
    for owner in ["doc-secret", "ren-secret", "tpl-1", "let-1"] {
      #expect(isPrivate("attachments", ["id": "att", "ownerId": .string(owner)], find), "\(owner)")
    }
    #expect(!isPrivate("attachments", ["id": "att", "ownerId": "doc-open"], find))
    #expect(!isPrivate("attachments", ["id": "att", "ownerId": "ren-open"], find))
    #expect(isPrivate("activities", ["entity": "compliance", "entityId": "doc-secret"], find))
    #expect(isPrivate("activities", ["entity": "compliance", "entityId": "ren-secret"], find))
    #expect(!isPrivate("activities", ["entity": "compliance", "entityId": "doc-open"], find))
    #expect(isPrivate("activities", ["entity": "compliance", "entityId": "doc-gone", "confidential": true]))
    #expect(!isPrivate("activities", ["entity": "compliance", "entityId": "doc-gone", "confidential": "true"]))
  }

  @Test("find the document of a renewal by its id, or else by its key")
  func renewedDocument() {
    #expect(Privacy.renewedDocumentId(["documentId": "d1", "documentKey": "doc:d1"]) == "d1")
    #expect(Privacy.renewedDocumentId(["documentId": nil, "documentKey": "doc:d2"]) == "d2")
    #expect(Privacy.renewedDocumentId(["documentId": "", "documentKey": "emp:e1:passport"]) == nil)
    #expect(Privacy.renewedDocumentId(["documentKey": "doc:"]) == nil)
    #expect(Privacy.renewedDocumentId(nil) == nil)
  }

  @Test("a pulled record is stored without the cloud's mark; files keep content already here")
  func localCopy() {
    let row = PulledRow(tbl: "clients", id: "c1", data: record("c1", ["_private": true, "name": "X"]), rev: 4, deleted: false)
    #expect(Privacy.localCopy(companyId: CO, row: row, local: nil) == record("c1", ["name": "X"]))
    // Not this company's, or not this id: not stored.
    let other = PulledRow(tbl: "clients", id: "c1", data: record("c1", company: "co-2"), rev: 4, deleted: false)
    #expect(Privacy.localCopy(companyId: CO, row: other, local: nil) == nil)
    let wrongId = PulledRow(tbl: "clients", id: "c9", data: record("c1"), rev: 4, deleted: false)
    #expect(Privacy.localCopy(companyId: CO, row: wrongId, local: nil) == nil)
    let company = PulledRow(tbl: "companies", id: CO, data: ["id": .string(CO), "name": "Co"], rev: 4, deleted: false)
    #expect(Privacy.localCopy(companyId: CO, row: company, local: nil) != nil)

    let file = record("a1", ["dataUrl": "", "storagePath": "co-1/a1", "contentHash": "h1"])
    let arrived = PulledRow(tbl: "attachments", id: "a1", data: file, rev: 5, deleted: false)
    // Its content isn't here yet: marked missing, to download.
    #expect(Privacy.localCopy(companyId: CO, row: arrived, local: nil)?["contentMissing"] == 1)
    // The same content is here already: kept.
    let here = file.setting("dataUrl", "data:image/png;base64,AAAA")
    let kept = Privacy.localCopy(companyId: CO, row: arrived, local: here)
    #expect(kept?["dataUrl"] == "data:image/png;base64,AAAA")
    #expect(kept?["contentMissing"] == nil)
    // New content in the cloud: the old one goes.
    let changed = PulledRow(tbl: "attachments", id: "a1", data: file.setting("contentHash", "h2"), rev: 6, deleted: false)
    #expect(Privacy.localCopy(companyId: CO, row: changed, local: here)?["dataUrl"] == "")
  }

  @Test("what is sent leaves this device's bookkeeping and marks files and activity about employees")
  func cloudCopy() {
    let owners: Set<String> = ["e1"]
    let scan = record("a1", ["ownerId": "e1", "contentMissing": 1, "_private": false])
    #expect(Privacy.cloudCopy(table: "attachments", record: scan, privateOwners: owners) == record("a1", ["ownerId": "e1", "_private": true]))
    let receipt = record("a2", ["ownerId": "d1", "contentMissing": 1])
    #expect(Privacy.cloudCopy(table: "attachments", record: receipt, privateOwners: owners) == record("a2", ["ownerId": "d1"]))
    let log = record("act", ["entity": "employee", "entityId": "e1"])
    #expect(Privacy.cloudCopy(table: "activities", record: log, privateOwners: [])["_private"] == .bool(true))
    // Only files and activity are marked; the server judges the rest itself.
    #expect(Privacy.cloudCopy(table: "employees", record: record("e1"), privateOwners: owners)["_private"] == nil)
  }

  @Test("owners of private files: employees, letters, private documents and their renewals")
  func owners() {
    let tables: [String: [String: JSONValue]] = [
      "employees": ["e1": record("e1")],
      "letterTemplates": ["t1": record("t1")],
      "complianceDocuments": ["d-emp": record("d-emp", ["employeeId": "e1"]), "d-sec": record("d-sec", ["confidential": true]), "d-open": record("d-open")],
      "renewals": ["r1": record("r1", ["documentId": "d-sec"]), "r2": record("r2", ["documentId": "d-open"]), "r3": record("r3", ["employeeId": "e1"])],
    ]
    #expect(Privacy.privateOwnerIds(tables) == ["e1", "t1", "d-emp", "d-sec", "r1", "r3"])
  }
}
