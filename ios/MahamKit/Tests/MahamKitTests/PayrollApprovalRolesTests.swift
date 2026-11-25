import Foundation
import Testing

@testable import MahamKit

/// src/cloud/payroll-approval-roles.test.ts: the device's copy of the salary
/// approval rules of records_guard, so a refusal is instant offline.
@Suite("Payroll approval roles")
struct PayrollApprovalRolesTests {
  static let now = "2026-10-22T08:00:00.000Z"
  static let asked: JSONValue = [
    "id": "req-1", "kind": "payroll", "subjectTbl": "payRuns", "subjectId": "run-1", "status": "pending",
    "requestedBy": "deputy", "after": ["runUpdatedAt": "2026-10-20T08:00:00.000Z"],
  ]
  static let run: JSONValue = ["id": "run-1", "updatedAt": "2026-10-20T08:00:00.000Z"]

  func refusal(
    _ before: JSONValue?, _ after: JSONValue?, _ userId: String, owner: Bool, shut: Bool = false, run: JSONValue?
  )
    -> Roles.PayrollRefusal?
  {
    Roles.payrollDecisionRefusal(before, after, userId: userId, owner: owner, peopleShut: shut, run: run)
  }

  @Test("knows the switch and the requests")
  func switchAndRequests() {
    #expect(Roles.rulesCoverPayroll(["payroll": true]))
    #expect(!Roles.rulesCoverPayroll(["documentTypes": ["invoice"]]))
    #expect(!Roles.rulesCoverPayroll(nil))
    #expect(Roles.isPayrollApproval(Self.asked))
    #expect(!Roles.isPayrollApproval(Self.asked.with(["subjectTbl": "documents"])))
  }

  @Test("lets owners, admins and accountants post pay runs, unless the owner limited People")
  func posting() {
    #expect(Roles.canPostPayroll(.owner, nil))
    #expect(Roles.canPostPayroll(.accountant, nil))
    #expect(!Roles.canPostPayroll(.accountant, Roles.Permissions(apps: [.people: .view])))
    #expect(Roles.canPostPayroll(.admin, Roles.Permissions(apps: [.books: .view])))
    #expect(!Roles.canPostPayroll(.staff, nil))
    #expect(!Roles.canPostPayroll(.viewer, nil))
    #expect(Roles.canPostPayroll(nil, nil))
  }

  @Test("refuses a deputy’s own approval and approving a changed pay run")
  func selfAndStale() {
    let asked = Self.asked
    let run = Self.run
    let approve = asked.with(["status": "approved"])
    #expect(refusal(asked, approve, "deputy", owner: false, run: run) == .selfApproval)
    #expect(refusal(asked, approve, "boss", owner: true, run: run) == nil)
    #expect(refusal(asked.with(["requestedBy": "boss"]), approve, "boss", owner: true, run: run) == nil)
    let changed = run.with(["updatedAt": "2026-10-21T08:00:00.000Z"])
    #expect(refusal(asked, approve, "boss", owner: true, run: changed) == .stale)
    #expect(refusal(asked, approve, "boss", owner: true, run: nil) == .stale)
    // The owner posting carries a waiting request out as it is.
    let applied = asked.with(["status": "applied"])
    #expect(refusal(asked, applied, "boss", owner: true, run: changed) == nil)
    #expect(refusal(asked, applied, "other", owner: false, run: changed) == .stale)
    // Turning it down, or a decision made before, is not looked at.
    #expect(refusal(asked, asked.with(["status": "rejected"]), "deputy", owner: false, run: changed) == nil)
    #expect(refusal(asked.with(["status": "approved"]), applied, "accountant", owner: false, run: changed) == nil)
  }

  @Test("lets no member the owner gave no access to People decide, but whoever asked take it back")
  func peopleShut() {
    let asked = Self.asked
    let run = Self.run
    for status in ["approved", "rejected", "cancelled", "applied"] {
      #expect(
        refusal(asked, asked.with(["status": .string(status)]), "shut", owner: false, shut: true, run: run) == .people)
    }
    // Their own, taken back while it waits.
    #expect(
      refusal(
        asked.with(["requestedBy": "shut"]), asked.with(["requestedBy": "shut", "status": "cancelled"]), "shut",
        owner: false, shut: true, run: run) == nil)
    // No decision (an older copy sent again), or one made before: not looked at.
    #expect(refusal(asked, asked, "shut", owner: false, shut: true, run: run) == nil)
    let rejected = asked.with(["status": "rejected"])
    #expect(refusal(rejected, rejected.with(["status": "approved"]), "shut", owner: false, shut: true, run: run) == nil)
    // The owner is never shut out; nor anyone with People.
    #expect(refusal(asked, asked.with(["status": "approved"]), "shut", owner: true, shut: true, run: run) == nil)
    #expect(refusal(asked, asked.with(["status": "approved"]), "shut", owner: false, shut: false, run: run) == nil)
  }

  @Test("keeps a deputy’s request sent up approved waiting, and lets whoever posts mark it done")
  func sentApproved() {
    let asked = Self.asked
    let who = Roles.ApprovalWriter(userId: "deputy", approver: true, owner: false, now: Self.now)
    let sent = Roles.guardApprovalWrite(
      nil, asked.with(["status": "approved"]), who: who, payroll: Roles.PayrollSwitch(on: true, poster: true))
    guard case .data(let waiting) = sent else {
      Issue.record("refused: \(sent)")
      return
    }
    #expect(waiting["status"] == "pending")
    #expect(waiting["requestedBy"] == "deputy")
    // Off: as before (asked and decided by them).
    let off = Roles.guardApprovalWrite(
      nil, asked.with(["status": "approved"]), who: who, payroll: Roles.PayrollSwitch(on: false, poster: true))
    guard case .data(let decided) = off else {
      Issue.record("refused: \(off)")
      return
    }
    #expect(decided["status"] == "approved")
    #expect(decided["decidedBy"] == "deputy")

    let approved = asked.with(["status": "approved", "decidedBy": "boss", "decidedAt": .string(Self.now)])
    let accountant = Roles.ApprovalWriter(userId: "accountant", approver: false, owner: false, now: Self.now)
    let done = approved.with(["status": "applied", "decidedBy": "accountant"])
    let posted = Roles.guardApprovalWrite(
      approved, done, who: accountant, payroll: Roles.PayrollSwitch(on: true, poster: true))
    guard case .data(let marked) = posted else {
      Issue.record("refused: \(posted)")
      return
    }
    #expect(marked["status"] == "applied")
    #expect(marked["decidedBy"] == "boss")
    #expect(
      Roles.guardApprovalWrite(approved, done, who: accountant, payroll: Roles.PayrollSwitch(on: true, poster: false))
        == .refused(.permission))
    #expect(
      Roles.guardApprovalWrite(approved, done, who: accountant, payroll: Roles.PayrollSwitch(on: false, poster: true))
        == .refused(.permission))
    #expect(Roles.guardApprovalWrite(approved, done, who: accountant) == .refused(.permission))
  }
}
