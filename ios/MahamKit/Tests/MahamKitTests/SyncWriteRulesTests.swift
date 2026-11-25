import Foundation
import Testing

@testable import MahamKit

/// The capture refusals of src/cloud/outbox.ts, as OutboxRules applies them.
@Suite("Sync: what a write is refused by")
struct SyncWriteRulesTests {
  let rules = OutboxRules()

  func state(_ role: MemberRole, features: [String] = [], permissions: [String: String]? = nil, approver: Bool? = nil)
    -> SyncState
  {
    var state = SyncState(companyId: CO, userId: "user-1", role: role, status: .ready, name: "Al Mail Trading")
    state.features = features
    state.permissions = permissions
    state.approver = approver
    return state
  }

  func refusal(
    _ state: SyncState, _ table: String, _ before: JSONValue?, _ after: JSONValue?,
    records: [String: [String: JSONValue]] = [:]
  ) -> String? {
    rules.refusal(state: state, table: table, before: before, after: after, lookup: { records[$0]?[$1] })
  }

  @Test("viewers change nothing, and nobody changes a company no longer shared")
  func viewers() {
    #expect(refusal(state(.viewer), "clients", nil, record("c1")) == "You can view this company but not change it.")
    var removed = state(.owner)
    removed.status = .removed
    #expect(refusal(removed, "clients", nil, record("c1"))?.hasPrefix("This company is no longer shared with you") == true)
    #expect(refusal(state(.owner), "employees", nil, record("e1")) == nil)
  }

  @Test("the owner's limits: an app made view only, and the books' settings on the company record")
  func limits() {
    let limited = state(.accountant, permissions: ["books": "view"])
    let message = "The owner has made this app view only for you. Ask the owner if you need to change it."
    #expect(refusal(limited, "documents", nil, record("d1", ["type": "invoice"])) == message)
    #expect(refusal(limited, "employees", nil, record("e1")) == nil)
    let company = companyRecord()
    #expect(refusal(limited, "companies", company, company.setting("accounting", ["lockDate": "2026-09-30"])) == message)
    #expect(refusal(limited, "companies", company, company.setting("phone", "+965 1")) == nil)
    // A scan follows the record it is kept with.
    let records: [String: [String: JSONValue]] = ["documents": ["d1": record("d1", ["type": "invoice"])]]
    #expect(refusal(limited, "attachments", nil, record("a1", ["ownerId": "d1"]), records: records) == message)
    // Never the owner.
    #expect(refusal(state(.owner, permissions: ["books": "view"]), "documents", nil, record("d1")) == nil)
  }

  @Test("staff stay out of accounting setup and People, and change the company record only in its counters")
  func staff() {
    let staff = state(.staff)
    let denied = "Your role can’t make this change. Ask an owner, admin or accountant."
    #expect(refusal(staff, "accounts", nil, record("a1")) == denied)
    #expect(refusal(staff, "journals", nil, record("j1", ["kind": "payroll"])) == denied)
    #expect(refusal(staff, "journals", nil, record("j1", ["kind": "transfer"])) == nil)
    #expect(refusal(staff, "employees", nil, record("e1")) == denied)
    #expect(refusal(staff, "clients", record("c1"), nil) == nil)
    let company = companyRecord()
    #expect(refusal(staff, "companies", company, company.setting("phone", "+965 1")) == denied)
    #expect(refusal(staff, "companies", company, nil) == denied)
    #expect(refusal(staff, "companies", company, company.setting("numbering", ["invoice": rule(6), "payment": rule(3)])) == nil)
  }

  @Test("the approval rules: issued documents, deletes, requests, cheques")
  func approvalRules() {
    let company = companyRecord(["approvalRules": ["documentTypes": ["invoice"], "voidInsteadOfDelete": false]])
    let records: [String: [String: JSONValue]] = ["companies": [CO: company]]
    let issued = record("d1", ["type": "invoice", "status": "sent", "number": "INV-0005", "items": [["name": "A", "quantity": 1]]])
    let changed = issued.setting("items", [["name": "A", "quantity": 2]])
    let admin = state(.admin)
    #expect(refusal(admin, "documents", issued, changed, records: records) == "This change needs approval. Send it for approval instead.")
    #expect(refusal(state(.admin, approver: true), "documents", issued, changed, records: records) == nil)
    #expect(refusal(state(.owner), "documents", issued, changed, records: records) == nil)
    #expect(
      refusal(admin, "documents", issued, nil, records: records)
        == "This document is issued, so only an approver can delete it. Ask for a void instead.")
    let voiding = ["companies": [CO: companyRecord(["approvalRules": ["documentTypes": ["invoice"], "voidInsteadOfDelete": true]])]]
    #expect(
      refusal(state(.owner), "documents", issued, nil, records: voiding)
        == "Issued documents are voided, never deleted, so their numbers stay used.")
    #expect(
      refusal(state(.owner), "approvals", record("ap1", ["status": "pending"]), nil, records: records)
        == "Approval requests are kept as the record of who asked and who decided.")
    // Without rules, a draft is anyone's to change.
    #expect(refusal(admin, "documents", issued, changed) == nil)
    // Only the owner changes the rules themselves.
    let plain = companyRecord()
    #expect(refusal(admin, "companies", plain, company) == "Only the owner changes the approval rules.")
    #expect(refusal(state(.owner), "companies", plain, company) == nil)
  }

  @Test("the AI switch is the owner's and the admins'")
  func aiSwitch() {
    let company = companyRecord()
    let switched = company.setting("ai", ["enabled": true])
    #expect(refusal(state(.accountant), "companies", company, switched) == "Only the owner or an admin turns the AI assistant on or off.")
    #expect(refusal(state(.admin), "companies", company, switched) == nil)
  }

  @Test("letters and items issued, once the server has them")
  func lettersAndIssues() {
    let settings = record(CO, ["letters": true])
    let records: [String: [String: JSONValue]] = ["peopleSettings": [CO: settings]]
    let letter = record("l1", ["status": "issued", "employeeId": "e1"])
    let withLetters = state(.accountant, features: ["employee_letters"])
    #expect(
      refusal(withLetters, "employeeLetters", letter, nil, records: records)
        == "Issued letters are kept, so their numbers stay used. Void it instead.")
    #expect(refusal(state(.accountant), "employeeLetters", letter, nil, records: records) == nil)
    #expect(
      refusal(withLetters, "peopleSettings", settings, settings.setting("letters", false))
        == "Only the owner or an admin turns employee letters on or off.")
    let withIssues = state(.owner, features: ["stock_issues"])
    #expect(refusal(withIssues, "stockIssues", record("si1"), nil) == "Items issued are voided, never deleted.")
    #expect(refusal(state(.owner), "stockIssues", record("si1"), nil) == nil)
  }
}
