import Foundation

/// The signed-in person's link to a company kept in the cloud, as the web's
/// write functions read it from `db.syncState` (`CloudLink`): who they are,
/// their role, and whether the owner lets them approve. Nil is the web's
/// `null`: a company kept on that device only, with nobody to ask.
public struct DcLink: Sendable, Equatable {
  public var userId: String
  public var role: MemberRole
  /// The owner allowed this admin or accountant to approve requests.
  public var approver: Bool

  public init(userId: String, role: MemberRole, approver: Bool = false) {
    self.userId = userId
    self.role = role
    self.approver = approver
  }
}

/// A change of an issued document that waits for an approver
/// (`ApprovalRequiredError`): the person is asked to send it for approval
/// (`DcApprovals.requestApproval`) with what it would have saved.
public struct DcApprovalRequired: Error, Sendable, CustomStringConvertible {
  /// What to ask for (`invoice_edit`, `invoice_void`, `invoice_unvoid`);
  /// nil for a change that can't be asked for (back to draft).
  public let kind: String?
  public let subject: JSONValue
  /// The document as it would have been saved.
  public let proposal: JSONValue
  public let failure: WriteFailure

  init(kind: String?, subject: JSONValue, proposal: JSONValue) {
    self.kind = kind
    self.subject = subject
    self.proposal = proposal
    let number = ["number": subject.dcText("number")]
    failure =
      kind != nil
      ? WriteFailure("{number} is issued, so this change needs approval. Send it for approval instead.", number)
      : WriteFailure("{number} is issued, so only an approver can make this change.", number)
  }

  public var description: String { failure.description }
}

/// The web's approval rules for documents (src/db/approvals.ts on
/// src/cloud/roles.ts, ported in Access/Roles.swift).
public enum DcApprovals {
  /// `approverOf(link)`: everyone in a company kept on a device only.
  public static func approverOf(_ link: DcLink?) -> Bool {
    guard let link else { return true }
    return Roles.isApprover(link.role, link.approver)
  }

  /// `rulesInEffect(company, link)`: none for a company kept on a device only.
  public static func rulesInEffect(_ company: JSONValue?, _ link: DcLink?) -> JSONValue? {
    guard link != nil else { return nil }
    return Roles.approvalRulesOf(company)
  }

  /// `approvalsOn(company)`: the owner has turned approvals of Books on.
  public static func approvalsOn(_ company: JSONValue?) -> Bool {
    guard case .object(let rules)? = Roles.approvalRulesOf(company) else { return false }
    return ["documentTypes", "voidInsteadOfDelete", "cheques"].contains { rules[$0] != nil } || rules["payroll"] == nil
  }

  /// `correctsByNewNumber(company)`: voided with why, who and when, and issued again in its place.
  public static func correctsByNewNumber(_ company: JSONValue?) -> Bool {
    approvalsOn(company) || company?["defaults"]?["numberOnIssue"] == .bool(true)
  }

  /// `changeKind(before, after)`.
  public static func changeKind(_ before: JSONValue, _ after: JSONValue) -> String? {
    let was = before.dcText("status")
    let now = after.dcText("status")
    if now == "void" && was != "void" { return "invoice_void" }
    if was == "void" && now != "void" && now != "draft" { return "invoice_unvoid" }
    if now == "draft" { return nil }
    return "invoice_edit"
  }

  /// `assertApproved(company, link, before, after)`: refused (to be sent for
  /// approval) when the person isn't an approver and the rules cover it.
  public static func assertApproved(_ company: JSONValue?, _ link: DcLink?, before: JSONValue, after: JSONValue) throws {
    if approverOf(link) { return }
    let rules = rulesInEffect(company, link)
    if !Roles.documentChangeNeedsApproval(rules, before, after) { return }
    throw DcApprovalRequired(kind: changeKind(before, after), subject: before, proposal: after)
  }

  /// `voidsInsteadOfDeleting(company, link, doc)`.
  public static func voidsInsteadOfDeleting(_ company: JSONValue?, _ link: DcLink?, _ doc: JSONValue) -> Bool {
    Roles.deleteKeptBy(rulesInEffect(company, link), "documents", doc, approver: approverOf(link)) != nil
  }

  /// `waitsForApproval(company, link, doc)`: issued documents of this type wait for an approver.
  public static func waitsForApproval(_ company: JSONValue?, _ link: DcLink?, _ doc: JSONValue) -> Bool {
    if approverOf(link) || doc["status"] == .string("draft") { return false }
    return Roles.rulesCoverDocument(rulesInEffect(company, link), doc["type"])
  }

  /// `pendingRequestFor(subjectId)`: the request waiting on a record.
  public static func pendingRequest(_ ctx: WriteContext, subjectId: String) -> JSONValue? {
    ctx.all("approvals").first { $0["subjectId"] == .string(subjectId) && $0["status"] == .string("pending") }
  }

  /// `requestApproval({ kind, subject, proposal, reason, byName })` for a
  /// document: an edit (the document as it would be saved), a void or an
  /// un-void, one request at a time. Returns the request.
  @discardableResult
  public static func requestApproval(
    _ ctx: WriteContext, kind: String, subject: JSONValue, proposal: JSONValue? = nil, reason rawReason: String,
    byName: String? = nil, link: DcLink?
  ) throws -> JSONValue {
    let reason = WebJS.trim(rawReason)
    if reason.isEmpty { throw WriteFailure("Say why, for the approver.") }
    let number = subject.dcText("number")
    if pendingRequest(ctx, subjectId: subject.dcId) != nil {
      throw WriteFailure("A request on {number} is already waiting for approval.", ["number": number])
    }
    let before: JSONValue
    let after: JSONValue
    switch kind {
    case "invoice_edit":
      guard let proposal else { throw WriteFailure("Nothing to send for approval.") }
      before = Roles.invoiceContent(subject)
      after = Roles.invoiceContent(proposal)
      if Roles.sameData(before, after) { throw WriteFailure("Nothing has changed.") }
    case "invoice_void":
      before = .object(["status": subject["status"] ?? .null])
      after = .object(["status": "void", "voidReason": .string(reason)])
    case "invoice_unvoid":
      before = .object(["status": "void"])
      after = .object(["status": "sent"])
    default:
      throw WriteFailure("Nothing to send for approval.")
    }
    let now = JSONValue.string(ctx.stamp)
    var request: [String: JSONValue] = [
      "id": .string(ctx.newId()), "companyId": subject["companyId"] ?? .null, "kind": .string(kind),
      "subjectTbl": "documents", "subjectId": .string(subject.dcId), "subjectNumber": .string(number),
      "before": before, "after": after, "reason": .string(reason), "status": "pending",
      // The cloud stamps both with its own.
      "requestedBy": .string(link?.userId ?? ""), "requestedAt": now, "decidedBy": .null, "decidedAt": .null,
      "decisionNote": "", "createdAt": now, "updatedAt": now,
    ]
    let name = WebJS.trim(byName ?? "")
    if !name.isEmpty { request["requestedByName"] = .string(WebJS.prefix(name, 200)) }
    let stored = JSONValue.object(request)
    ctx.put("approvals", stored)
    // logRequest(request, 'asked'): on the activity of the document it is about.
    let doc = ctx.get("documents", subject.dcId)
    let clientId = doc?.dcNonEmpty("clientId")
    ctx.logActivity(
      entity: doc?["type"]?.string ?? "invoice", entityId: subject.dcId, action: "approval:asked",
      message: ActivityMessage("Approval asked for on {number}", vars: ["number": number]),
      refs: ActivityRefs(clientId: clientId, documentId: subject.dcId))
    return stored
  }
}
