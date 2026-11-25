import Foundation
import Testing

@testable import MahamKit

/// The web's isPrivateRecord (src/cloud/roles.ts), for these tests only: the
/// app's own is the sync layer's (Sync/Privacy.swift), and the rules take it
/// as a closure.
func webIsPrivate(_ table: String, _ record: JSONValue?, _ lookup: Roles.RecordLookup? = nil) -> Bool {
  if Roles.peopleTables.contains(table) { return true }
  guard let record, !record.isNull else { return false }
  if record["_private"] == true { return true }
  func present(_ row: JSONValue?) -> Bool { row != nil && row != .null }
  func employeeOwned(_ row: JSONValue?) -> Bool {
    if case .string(let id)? = row?["employeeId"] { return !id.isEmpty }
    return false
  }
  func privateDocument(_ row: JSONValue?) -> Bool { employeeOwned(row) || row?["confidential"] == true }
  func privateRenewal(_ row: JSONValue?) -> Bool {
    if employeeOwned(row) { return true }
    guard let documentId = Roles.renewedDocumentId(row), let lookup else { return false }
    return privateDocument(lookup("complianceDocuments", documentId))
  }
  switch table {
  case "complianceDocuments": return privateDocument(record)
  case "renewals": return privateRenewal(record)
  case "journals": return record["kind"] == "payroll"
  case "approvals":
    if case .string(let subject)? = record["subjectTbl"] { return Roles.peopleTables.contains(subject) }
    return false
  case "activities":
    if record["entity"] == "employee" || record["entity"] == "payroll" || record["entity"] == "costing" { return true }
    if employeeOwned(record) || record["confidential"] == true { return true }
    guard record["entity"] == "compliance", let lookup, case .string(let id)? = record["entityId"] else { return false }
    return privateDocument(lookup("complianceDocuments", id)) || privateRenewal(lookup("renewals", id))
  case "attachments":
    guard let lookup, case .string(let owner)? = record["ownerId"] else { return false }
    return present(lookup("employees", owner)) || present(lookup("letterTemplates", owner))
      || present(lookup("employeeLetters", owner)) || privateDocument(lookup("complianceDocuments", owner))
      || privateRenewal(lookup("renewals", owner))
  default:
    return false
  }
}

/// canWriteRecord with the web's privacy rule and a lookup, as the web calls it.
func canWrite(_ role: MemberRole?, _ table: String, _ record: JSONValue?, _ lookup: Roles.RecordLookup? = nil) -> Bool {
  Roles.canWriteRecord(role, table, record) { webIsPrivate($0, $1, lookup) }
}

/// src/cloud/roles.test.ts. Its checks of isPrivateRecord alone belong to the
/// sync layer's port of it; the checks of who writes what are here.
@Suite("Roles")
struct RolesTests {
  static let others: [String: [String: JSONValue]] = [
    "employees": ["emp-1": ["id": "emp-1", "name": "Rajesh Kumar"]],
    "complianceDocuments": [
      "doc-emp": ["id": "doc-emp", "employeeId": "emp-1"],
      "doc-co": ["id": "doc-co", "employeeId": nil],
    ],
    "renewals": ["ren-emp": ["id": "ren-emp", "employeeId": "emp-1"]],
  ]
  static func lookup(_ table: String, _ id: String) -> JSONValue? { others[table]?[id] }

  // MARK: private records

  @Test("leave out the scans of a payment, which staff may add and viewers only see")
  func paymentScans() {
    let payment: JSONValue = ["id": "pay-1", "method": "cheque", "amount": 120]
    let find: Roles.RecordLookup = { table, id in
      table == "payments" && id == "pay-1" ? payment : Self.lookup(table, id)
    }
    let scan: JSONValue = ["id": "att-pay", "ownerId": "pay-1", "name": "cheque.jpg"]
    #expect(canWrite(.staff, "attachments", scan, find))
    #expect(canWrite(.staff, "payments", payment, find))
    #expect(!canWrite(.viewer, "attachments", scan, find))
    #expect(!canWrite(.viewer, "payments", payment, find))
  }

  static let v16: [String: [String: JSONValue]] = [
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

  @Test("find the document of a renewal by its id, or else by its key")
  func renewedDocument() {
    #expect(Roles.renewedDocumentId(["documentId": "d1", "documentKey": "doc:d1"]) == "d1")
    #expect(Roles.renewedDocumentId(["documentId": nil, "documentKey": "doc:d2"]) == "d2")
    #expect(Roles.renewedDocumentId(["documentId": "", "documentKey": "emp:e1:passport"]) == nil)
    #expect(Roles.renewedDocumentId(["documentKey": "doc:"]) == nil)
    #expect(Roles.renewedDocumentId(nil) == nil)
  }

  @Test("tables of database version 16 are written by owners, admins and accountants, never by staff or viewers")
  func v16Writers() {
    let find: Roles.RecordLookup = { table, id in Self.v16[table]?[id] }
    for table in ["chequeLayouts", "vehicles", "approvals", "letterTemplates", "employeeLetters"] {
      let record: JSONValue = ["id": "x", "subjectTbl": "documents"]
      // Staff ask for approval, of anything but payroll and people data.
      #expect(canWrite(.staff, table, record, find) == (table == "approvals"), "\(table)")
      #expect(!canWrite(.viewer, table, record, find), "\(table)")
      for role in [MemberRole.owner, .admin, .accountant, nil] {
        #expect(canWrite(role, table, record, find), "\(String(describing: role)) \(table)")
      }
    }
    #expect(!canWrite(.staff, "approvals", ["subjectTbl": "payRuns"], find))
  }

  // MARK: roles

  @Test("decide who sees people data, edits, manages the team and the accounting setup")
  func roleTable() {
    let table = Roles.memberRoles.map { role in
      [Roles.canSeePeople(role), Roles.canEdit(role), Roles.canManageTeam(role), Roles.canEditAccounting(role)]
    }
    #expect(Roles.memberRoles.map(\.rawValue) == ["owner", "admin", "accountant", "staff", "viewer"])
    #expect(
      table == [
        [true, true, true, true],
        [true, true, true, true],
        [true, true, false, true],
        [false, true, false, false],
        [false, false, false, false],
      ])
    // A company kept on this device only: everything.
    #expect([Roles.canSeePeople(nil), Roles.canEdit(nil), Roles.canEditAccounting(nil)] == [true, true, true])
    #expect(!Roles.canManageTeam(nil))
  }

  @Test("let staff change sales, purchases, cheques, stock and files, never people data")
  func staffWrites() {
    func staff(_ table: String, _ record: JSONValue = ["id": "x"]) -> Bool {
      canWrite(.staff, table, record, Self.lookup)
    }
    for table in ["clients", "documents", "payments", "expenses", "securityCheques"] {
      #expect(staff(table), "\(table)")
    }
    #expect(staff("stockMovements"))
    #expect(staff("attachments", ["ownerId": "inv-1"]))
    #expect(!staff("attachments", ["ownerId": "emp-1"]))
    #expect(!staff("complianceDocuments", ["employeeId": nil]))
    for table in ["accounts", "taxRates", "assets", "yearEnds", "employees", "payRuns"] {
      #expect(!staff(table), "\(table)")
    }
    #expect(staff("journals", ["kind": "transfer"]))
    #expect(staff("journals", ["kind": "cheque_clearing"]))
    #expect(!staff("journals", ["number": "MJ-1"]))
    #expect(!staff("journals", ["kind": "payroll"]))
    #expect(!staff("journals", ["kind": "year_end"]))
  }

  @Test("let viewers change nothing, and the others everything")
  func viewersAndOthers() {
    #expect(!canWrite(.viewer, "clients", ["id": "c"]))
    #expect(!canWrite(.viewer, "activities", ["id": "a"]))
    for role in [MemberRole.owner, .admin, .accountant, nil] {
      #expect(canWrite(role, "employees", ["id": "e"]))
      #expect(canWrite(role, "journals", ["kind": "payroll"]))
    }
  }

  @Test("let staff change only the document counters of the company")
  func staffCompany() {
    let company: JSONValue = [
      "id": "co", "name": "Al Mail Trading", "updatedAt": "2026-10-01T00:00:00.000Z",
      "numbering": [
        "invoice": ["pattern": "INV-{counter}", "next": 5, "padding": 4, "reset": "yearly", "period": "2026"]
      ],
    ]
    let invoice = company["numbering"]?["invoice"] ?? .null
    let counters = company.with([
      "updatedAt": "2026-10-04T00:00:00.000Z",
      "numbering": [
        "invoice": invoice.with(["next": 6]),
        "quote": ["pattern": "QUO-{counter}", "next": 1, "padding": 4, "reset": "never", "period": ""],
      ],
    ])
    #expect(Roles.staffCompanyChangeOk(company, counters))
    #expect(
      !Roles.staffCompanyChangeOk(
        company, company.with(["numbering": ["invoice": invoice.with(["pattern": "X-{counter}"])]])))
    #expect(!Roles.staffCompanyChangeOk(company, company.with(["name": "Someone else"])))
    #expect(!Roles.staffCompanyChangeOk(nil, company))
  }

  @Test("compare JSON data the way it is stored")
  func sameData() {
    #expect(Roles.sameData(["a": 1, "b": ["c": [1, 2]]], ["b": ["c": [1, 2]], "a": 1]))
    #expect(Roles.sameData(["a": 1], ["a": 1]))
    // A field set to null is not a missing field; a missing value is null.
    #expect(!Roles.sameData(["a": nil], [:]))
    #expect(Roles.sameData([nil], [nil]))
    #expect(Roles.sameData(nil, .null))
    #expect(!Roles.sameData([1, 2], [2, 1]))
    #expect(!Roles.sameData(["a": 1], ["a": "1"]))
    #expect(!Roles.sameData(["a": []], ["a": [:]]))
  }

  // MARK: the Super Admin

  @Test("is the owner, who approves with up to two admins or accountants")
  func superAdmin() {
    #expect(Roles.memberRoles.filter(Roles.isSuperAdmin) == [.owner])
    #expect(!Roles.isSuperAdmin(nil))
    #expect(Roles.memberRoles.filter { Roles.isApprover($0, false) } == [.owner])
    #expect(Roles.memberRoles.filter { Roles.isApprover($0, true) } == [.owner, .admin, .accountant])
    #expect(Roles.maxApprovers == 2)
  }

  @Test("keeps admins and accountants for the owner to give once the owner says so")
  func grantable() {
    #expect(Roles.grantableRoles(.owner, ownerOnly: true) == [.admin, .accountant, .staff, .viewer])
    #expect(Roles.grantableRoles(.admin, ownerOnly: false) == [.admin, .accountant, .staff, .viewer])
    #expect(Roles.grantableRoles(.admin, ownerOnly: true) == [.staff, .viewer])
    for role in [MemberRole.accountant, .staff, .viewer, nil] {
      #expect(Roles.grantableRoles(role, ownerOnly: false) == [])
    }
    // Nobody changes the owner; admins change everyone else, unless the owner keeps them.
    #expect(
      Roles.memberRoles.filter { Roles.canChangeMember(.owner, $0, ownerOnly: true) } == [
        .admin, .accountant, .staff, .viewer,
      ])
    #expect(
      Roles.memberRoles.filter { Roles.canChangeMember(.admin, $0, ownerOnly: false) } == [
        .admin, .accountant, .staff, .viewer,
      ])
    #expect(Roles.memberRoles.filter { Roles.canChangeMember(.admin, $0, ownerOnly: true) } == [.staff, .viewer])
    #expect(!Roles.canChangeMember(.accountant, .staff, ownerOnly: false))
  }

  // MARK: the owner's limits on a member

  @Test("only ever take away, and never from the owner")
  func limits() {
    #expect(Roles.lowerAccess(.manage, .view) == .view)
    #expect(Roles.lowerAccess(.view, .edit) == .view)
    #expect(Roles.lowerAccess(.edit, nil) == .edit)
    #expect(Roles.lowerAccess(.noAccess, .manage) == .noAccess)
    #expect(Roles.AppAccess(rawValue: "none") == .noAccess)
    let limits = Roles.Permissions(apps: [.books: .view, .people: .noAccess])
    #expect(Roles.appLimit(.admin, limits, .books) == .view)
    #expect(Roles.appLimit(.admin, limits, .crm) == nil)
    #expect(Roles.appLimit(.owner, limits, .books) == nil)
    #expect(Roles.appLimit(nil, limits, .books) == nil)
    #expect(Roles.appLimit(.staff, nil, .books) == nil)
    // Maham Sales and Maham Inventory follow Books.
    #expect(Roles.appLimit(.admin, limits, .sales) == .view)
    #expect(Roles.appLimit(.admin, limits, .inventory) == .view)
  }

  @Test("keep only what this version knows from the server")
  func readPermissions() {
    #expect(Roles.readPermissions(nil) == Roles.Permissions())
    #expect(Roles.readPermissions([:]) == Roles.Permissions())
    #expect(Roles.readPermissions(["apps": []]) == Roles.Permissions())
    #expect(
      Roles.readPermissions(["apps": ["books": "view", "people": "none", "later": "none", "crm": "boss"]])
        == Roles.Permissions(apps: [.books: .view, .people: .noAccess]))
  }

  @Test("put each record in an app, as the server does")
  func recordApps() {
    #expect(Roles.recordApp("documents", [:]) == .books)
    #expect(Roles.recordApp("journals", ["kind": "transfer"]) == .books)
    #expect(Roles.recordApp("journals", ["kind": "payroll"]) == .people)
    #expect(Roles.recordApp("employees", [:]) == .people)
    #expect(Roles.recordApp("complianceDocuments", ["employeeId": "emp-1"]) == .people)
    #expect(Roles.recordApp("complianceDocuments", ["employeeId": nil]) == .compliance)
    #expect(Roles.recordApp("vehicles", [:]) == .compliance)
    // What every app shares, and kinds this version doesn't know.
    for table in ["companies", "activities", "attachments", "approvals", "later"] {
      #expect(Roles.recordApp(table, [:]) == nil, "\(table)")
    }
  }

  @Test("block writes to an app made view only or turned off")
  func blockedWrites() {
    let limits = Roles.Permissions(apps: [.books: .view, .compliance: .noAccess, .people: .edit])
    #expect(Roles.limitBlocksWrite(.staff, limits, "documents", [:]))
    #expect(Roles.limitBlocksWrite(.admin, limits, "vehicles", [:]))
    #expect(!Roles.limitBlocksWrite(.accountant, limits, "employees", [:]))
    #expect(!Roles.limitBlocksWrite(.staff, limits, "activities", [:]))
    #expect(!Roles.limitBlocksWrite(.owner, limits, "documents", [:]))
    #expect(!Roles.limitBlocksWrite(.staff, nil, "documents", [:]))
  }
}
