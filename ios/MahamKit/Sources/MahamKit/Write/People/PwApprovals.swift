import Foundation

// Salary approval by the Super Admin (#10): the port of
// src/db/payroll-approvals.ts. With the owner's switch on, a draft pay run
// is sent for approval as it stands; it is posted only as it was approved
// (the owner may post at once), and the request is marked done after.

public enum PwApprovals {
  /// `payrollApprovalOn(company, link)`.
  public static func on(_ company: JSONValue?, _ link: PwLink?) -> Bool {
    guard let link else { return false }
    return link.features.contains("payroll_approvals") && Roles.rulesCoverPayroll(Roles.approvalRulesOf(company))
  }

  /// `payrollDetails(request)?.runUpdatedAt`.
  static func runUpdatedAt(_ request: JSONValue) -> String? {
    guard let after = request["after"], case .object = after, let stamp = after.pwText("runUpdatedAt"),
      WebJS.truthy(after["totals"])
    else { return nil }
    return stamp
  }

  /// `askedForRun(request, run)`.
  public static func askedForRun(_ request: JSONValue, _ run: JSONValue) -> Bool {
    runUpdatedAt(request) == run.pwText("updatedAt") && runUpdatedAt(request) != nil
  }

  /// `latestFirst`.
  static func latestFirst(_ a: JSONValue, _ b: JSONValue) -> Int {
    let order = PwSort.localeCompare(b.pwStr("requestedAt"), a.pwStr("requestedAt"))
    return order != 0 ? order : PwSort.localeCompare(b.pwStr("createdAt"), a.pwStr("createdAt"))
  }

  /// `payrollRequests(runId)`: a pay run's requests, the latest first.
  public static func requests(_ ctx: WriteContext, runId: String) -> [JSONValue] {
    sorted(ctx.all("approvals").filter { $0.pwStr("subjectId") == runId && Roles.isPayrollApproval($0) })
  }

  static func sorted(_ requests: [JSONValue]) -> [JSONValue] {
    PwSort.stable(requests.filter { Roles.isPayrollApproval($0) }, by: latestFirst)
  }

  /// Where a pay run is with its approval (`payrollApprovalState`).
  public enum State: Equatable, Sendable {
    case none
    case request(status: String, request: JSONValue, current: Bool)
  }

  public static func state(_ run: JSONValue, _ requests: [JSONValue]) -> State {
    let mine = sorted(requests)
    let approved = mine.first(where: { $0.pwStr("status") == "approved" && askedForRun($0, run) })
    let pending = mine.first(where: { $0.pwStr("status") == "pending" })
    let request = approved ?? pending ?? mine.first
    guard let request else { return .none }
    return .request(status: request.pwStr("status"), request: request, current: askedForRun(request, run))
  }

  /// `payrollWaitText(state)`: why the run can't be posted yet (English).
  public static func waitText(_ state: State) -> String {
    switch state {
    case .none:
      return "This pay run needs the Super Admin’s approval before it is approved. Send it for approval first."
    case .request(let status, _, let current):
      if status == "cancelled" {
        return "This pay run needs the Super Admin’s approval before it is approved. Send it for approval first."
      }
      if !current { return "This pay run changed after it was sent for approval. Send it for approval again." }
      if status == "pending" { return "This pay run is waiting for the Super Admin’s approval." }
      if status == "rejected" {
        return "The Super Admin didn’t approve this pay run. Change it if needed and send it for approval again."
      }
      return "This pay run changed after it was sent for approval. Send it for approval again."
    }
  }

  /// `payrollPostable`: whether this person may post the run now, as far as salary approval goes.
  public static func postable(_ company: JSONValue?, _ link: PwLink?, _ run: JSONValue, _ requests: [JSONValue]) -> Bool
  {
    if !on(company, link) { return true }
    if link?.role == .owner { return true }
    return requests.contains { $0.pwStr("status") == "approved" && askedForRun($0, run) }
  }

  /// `payrollGate`: the request to mark done once the run is posted, or the refusal.
  static func gate(_ company: JSONValue?, _ link: PwLink?, _ run: JSONValue, _ requests: [JSONValue]) throws
    -> JSONValue?
  {
    if !on(company, link) { return nil }
    let mine = sorted(requests)
    if let approved = mine.first(where: { $0.pwStr("status") == "approved" && askedForRun($0, run) }) {
      return approved
    }
    if link?.role == .owner {
      return mine.first(where: { $0.pwStr("status") == "pending" && askedForRun($0, run) })
    }
    throw pwFail(waitText(state(run, mine)))
  }

  static let log: [String: String] = [
    "asked": "Pay run {period} sent for approval",
    "cancelled": "Approval request for pay run {period} cancelled",
    "approved": "Approval given for pay run {period}",
    "rejected": "Approval refused for pay run {period}",
    "expired": "Approval request for pay run {period} expired",
  ]

  /// `logRequest(request, what)` for a pay run's request.
  static func logRequest(_ ctx: WriteContext, _ request: JSONValue, _ what: String) {
    PwLog.add(
      ctx, "payroll", request.pwStr("subjectId"), "approval:" + what, log[what] ?? what,
      vars: ["period": .text(request.pwStr("subjectNumber"))])
  }

  /// `payrollRequestDetails(run, currency)`.
  static func details(_ run: JSONValue, currency: String) -> JSONValue {
    let breakdown = PwPay.breakdown(run.pwList("lines"), PwM.places(currency))
    return [
      "runUpdatedAt": run["updatedAt"] ?? .null, "period": run["period"] ?? .null, "currency": .string(currency),
      "totals": breakdown.totals, "groups": breakdown.departments,
    ]
  }

  /// `requestPayrollApproval(runId, { note, byName })`: a draft sent for the
  /// Super Admin's approval, only when it could be posted as it is.
  @discardableResult
  public static func request(
    _ ctx: WriteContext, runId: String, note: String = "", byName: String = "", link: PwLink?, text: PwText = .english
  ) throws -> JSONValue {
    if let run = ctx.get("payRuns", runId), run.pwStr("status") == "draft", !run.pwList("lines").isEmpty {
      _ = try PwPayRuns.postingChecks(run, PwPayrollContext(ctx), text: text)
    }
    guard let run = ctx.get("payRuns", runId) else { throw pwFail("This pay run could not be found.") }
    if run.pwStr("status") != "draft" { throw pwFail("Only a draft pay run is sent for approval.") }
    if run.pwList("lines").isEmpty { throw pwFail("This pay run has no employees.") }
    let stored = ctx.get("companies", run.pwStr("companyId"))
    guard let company = stored, let link, on(company, link) else {
      throw pwFail("Salary approval is off for this company.")
    }
    if !Roles.canPostPayroll(link.role, link.rolesPermissions) {
      throw pwFail("Your role can’t send pay runs for approval.")
    }
    let existing = requests(ctx, runId: run.pwId)
    if existing.contains(where: { $0.pwStr("status") == "approved" && askedForRun($0, run) }) {
      throw pwFail("This pay run is already approved. You can approve it now.")
    }
    let now = ctx.stamp
    for waiting in existing where waiting.pwStr("status") == "pending" {
      if askedForRun(waiting, run) { throw pwFail("This pay run is already waiting for the Super Admin’s approval.") }
      if waiting.pwStr("requestedBy") != link.userId && !Roles.isApprover(link.role, link.approver) {
        throw pwFail(
          "An earlier version of this pay run is still waiting, sent by someone else. Ask them or an approver to take it back."
        )
      }
      ctx.put(
        "approvals",
        waiting.pwMerging([
          "status": "cancelled", "decidedBy": .string(link.userId), "decidedAt": .string(now), "updatedAt": .string(now),
        ]))
      logRequest(ctx, waiting, "cancelled")
    }
    var fields: [String: JSONValue] = [
      "id": .string(ctx.newId()), "companyId": run["companyId"] ?? .null, "kind": "payroll", "subjectTbl": "payRuns",
      "subjectId": .string(run.pwId), "subjectNumber": run["period"] ?? .null, "before": .null,
      "after": details(run, currency: company.pwStr("currency")),
      "reason": .string(WebJS.prefix(WebJS.trim(note), 1000)), "status": "pending",
      "requestedBy": .string(link.userId), "requestedAt": .string(now), "decidedBy": .null, "decidedAt": .null,
      "decisionNote": "", "createdAt": .string(now), "updatedAt": .string(now),
    ]
    let name = WebJS.trim(byName)
    if !name.isEmpty { fields["requestedByName"] = .string(WebJS.prefix(name, 200)) }
    let request = JSONValue.object(fields)
    ctx.put("approvals", request)
    logRequest(ctx, request, "asked")
    return request
  }

  /// `markPayrollApplied(requestId)`: the request carried out by the posting.
  /// The app saves it on its own after the posting, which stands whatever
  /// becomes of it, as on the web.
  public static func markApplied(_ ctx: WriteContext, requestId: String, link: PwLink?) {
    guard let request = ctx.get("approvals", requestId) else { return }
    let status = request.pwStr("status")
    guard status == "approved" || status == "pending" else { return }
    let company = ctx.get("companies", request.pwStr("companyId"))
    if status == "pending" && link?.role != .owner { return }
    guard link != nil, Roles.approvalRulesOf(company) != nil else { return }
    var fields: [String: JSONValue] = ["status": "applied", "updatedAt": .string(ctx.stamp)]
    if status == "pending" {
      fields["decidedBy"] = .pwOptional(link?.userId)
      fields["decidedAt"] = .string(ctx.stamp)
    }
    ctx.put("approvals", request.pwMerging(fields))
  }
}
