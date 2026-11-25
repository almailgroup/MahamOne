import Foundation

/// The rules a change is refused by before it is made, as the server would
/// refuse it (the web's `refuse*` in src/cloud/outbox.ts).
public protocol WriteRules: Sendable {
  /// Why the person may not make this change (words they can act on), or
  /// nil. `lookup` finds the company's other records as they stand in this
  /// action: the company record, pay runs, People settings, warehouses, the
  /// records files are kept with.
  func refusal(state: SyncState, table: String, before: JSONValue?, after: JSONValue?, lookup: Privacy.Lookup)
    -> String?
}

/// The web's capture refusals, ported from src/cloud/outbox.ts (`refuse`:
/// `refuseByRole`, then `refuseLetters`, `refuseWarehouses` and
/// `refuseByRules`) on the port of src/cloud/roles.ts (Access/Roles.swift),
/// with the web's own words.
public struct OutboxRules: WriteRules {
  /// The time approval requests are judged at (`new Date().toISOString()`).
  public var now: @Sendable () -> Date

  public init(now: @Sendable @escaping () -> Date = { Date() }) {
    self.now = now
  }

  /// Tables whose changes the company's approval rules decide on (`RULED`).
  static let ruled: Set<String> = ["documents", "approvals", "payments", "securityCheques"]
  /// Tables whose changes the sub-warehouses decide on (`WAREHOUSE_RULED`).
  static let warehouseRuled: Set<String> = ["warehouses", "stockEntries", "stockIssues", "documents", "approvals"]

  public func refusal(
    state: SyncState, table: String, before: JSONValue?, after: JSONValue?, lookup: Privacy.Lookup
  ) -> String? {
    let permissions = Roles.readPermissions(
      .object(["apps": .object((state.permissions ?? [:]).mapValues { .string($0) })]))
    let company = Self.ruled.contains(table) ? lookup("companies", state.companyId) : nil
    // Only used while this call runs.
    return withoutActuallyEscaping(lookup) { lookup in
      // The records files are kept with, looked up only for someone the owner limited.
      let owners: Roles.RecordLookup? =
        table == "attachments" && Roles.hasLimits(state.role, permissions) ? lookup : nil
      return byRole(state, permissions, table, before, after, owners)
        ?? letters(state, table, before, after, settings: lookup("peopleSettings", state.companyId))
        ?? warehouses(state, table, before, after, lookup)
        ?? byRules(state, permissions, table, before, after, company: company, lookup)
    }
  }

  func byRole(
    _ state: SyncState, _ permissions: Roles.Permissions, _ table: String, _ before: JSONValue?, _ after: JSONValue?,
    _ owners: Roles.RecordLookup?
  ) -> String? {
    if state.status == .removed {
      return "This company is no longer shared with you. Keep it as a company on this device or remove it."
    }
    if state.role == .viewer { return "You can view this company but not change it." }
    // The owner's limits on this person, as the server applies them.
    func limited(_ row: JSONValue?) -> Bool {
      guard let row else { return false }
      return Roles.limitBlocksWrite(state.role, permissions, table, row, lookup: owners)
    }
    let books = Roles.appLimit(state.role, permissions, .books)
    if limited(before) || limited(after)
      || (table == "companies" && (books == .view || books == .noAccess) && Roles.companyBooksChanged(before, after))
    {
      return "The owner has made this app view only for you. Ask the owner if you need to change it."
    }
    guard state.role == .staff else { return nil }
    let denied = "Your role can’t make this change. Ask an owner, admin or accountant."
    if table == "companies" {
      guard after != nil, let before else { return denied }
      return Roles.staffCompanyChangeOk(before, after) ? nil : denied
    }
    let isPrivate: Roles.PrivacyCheck = { Privacy.isPrivateRecord($0, $1) }
    if let before, !Roles.canWriteRecord(.staff, table, before, isPrivate: isPrivate) { return denied }
    if let after, !Roles.canWriteRecord(.staff, table, after, isPrivate: isPrivate) { return denied }
    return nil
  }

  func letters(_ state: SyncState, _ table: String, _ before: JSONValue?, _ after: JSONValue?, settings: JSONValue?)
    -> String?
  {
    guard state.has("employee_letters") else { return nil }
    let switchMessage = "Only the owner or an admin turns employee letters on or off."
    if table == "peopleSettings" {
      guard let after else {
        // Deleting the settings would turn the letters off.
        return before.map { Roles.peopleSettingsKept(state.role, $0) } == true ? switchMessage : nil
      }
      return !Roles.switchesLetters(state.role) && !Roles.sameData(before?["letters"], after["letters"])
        ? switchMessage : nil
    }
    guard table == "employeeLetters", Roles.lettersSwitchedOn(settings) else { return nil }
    guard after != nil else {
      return before.map(Roles.letterKept) == true
        ? "Issued letters are kept, so their numbers stay used. Void it instead." : nil
    }
    switch Roles.letterWriteRefusal(before, after, issuer: Roles.issuesLetters(state.role, state.approver)) {
    case .issued: return "This letter is already issued, so it stays issued."
    case .issuer: return "Only the owner, an admin or an approver issues letters. Ask for approval instead."
    case nil: return nil
    }
  }

  func warehouses(_ state: SyncState, _ table: String, _ before: JSONValue?, _ after: JSONValue?, _ lookup: Privacy.Lookup)
    -> String?
  {
    guard Self.warehouseRuled.contains(table), state.has("stock_issues") else { return nil }
    if table == "stockIssues" && after == nil { return "Items issued are voided, never deleted." }
    let member = Roles.WarehouseWriter(
      role: state.role, userId: state.userId, approver: Roles.isApprover(state.role, state.approver))
    switch Roles.warehouseWriteRefusal(member, table, before, after, warehouses: { lookup("warehouses", $0) }) {
    case .approver: return "Only an approver records items issued. Send them for approval instead."
    case .keeper: return "You can only issue items from the sub-warehouse you look after."
    case .manager:
      return "Only the owner, an admin or an accountant sets up sub-warehouses or changes their stock directly."
    case nil: return nil
    }
  }

  func byRules(
    _ state: SyncState, _ permissions: Roles.Permissions, _ table: String, _ before: JSONValue?, _ after: JSONValue?,
    company: JSONValue?, _ lookup: Privacy.Lookup
  ) -> String? {
    if table == "companies" {
      guard let after else { return nil }
      if state.role != .owner && Roles.approvalRulesChanged(before, after) {
        return "Only the owner changes the approval rules."
      }
      return !Roles.switchesAi(state.role) && Roles.aiSwitchChanged(before, after)
        ? "Only the owner or an admin turns the AI assistant on or off." : nil
    }
    let rules = Roles.approvalRulesOf(company)
    let approver = Roles.isApprover(state.role, state.approver)
    if after == nil {
      guard let before else { return nil }
      switch Roles.deleteKeptBy(rules, table, before, approver: approver) {
      case .request: return "Approval requests are kept as the record of who asked and who decided."
      case .void: return "Issued documents are voided, never deleted, so their numbers stay used."
      case .approver: return "This document is issued, so only an approver can delete it. Ask for a void instead."
      case nil: break
      }
    }
    if table == "documents" && Roles.issuesWithoutNumber(company, before, after) {
      return "This invoice has no number yet. Issue it again to give it one."
    }
    if table == "approvals", let after {
      // Salary approval (#10), once the company's server has it.
      let payroll = Roles.PayrollSwitch(
        on: Roles.rulesCoverPayroll(rules) && state.has("payroll_approvals"),
        poster: Roles.canPostPayroll(state.role, permissions))
      let who = Roles.ApprovalWriter(
        userId: state.userId, approver: approver, owner: state.role == .owner, now: MahamDates.timestamp(now()))
      if case .refused = Roles.guardApprovalWrite(before, after, who: who, payroll: payroll) {
        return "Only an approver decides approval requests."
      }
      let request = before ?? after
      guard payroll.on, Roles.isPayrollApproval(request) else { return nil }
      let run = request["subjectId"]?.string.flatMap { lookup("payRuns", $0) }
      switch Roles.payrollDecisionRefusal(
        before, after, userId: state.userId, owner: state.role == .owner,
        peopleShut: Roles.appLimit(state.role, permissions, .people) == .noAccess, run: run)
      {
      case .people: return "The owner has given you no access to Maham People, so you don’t decide pay runs."
      case .selfApproval: return "Only the owner approves a pay run they sent for approval themselves."
      case .stale:
        return "This pay run changed after it was sent for approval. Reject this request; it can be sent again."
      case nil: return nil
      }
    }
    guard rules != nil else { return nil }
    if table == "payments" || table == "securityCheques" {
      // A cheque the rules keep for approvers: recorded, changed or deleted by them only.
      return !approver && Roles.chequeChangeNeedsApprover(rules, table, before, after)
        ? "This cheque needs confirmation. Send it for confirmation instead." : nil
    }
    if table == "documents", after != nil {
      if approver { return nil }
      if Roles.documentChangeNeedsApproval(rules, before, after) {
        return "This change needs approval. Send it for approval instead."
      }
      return Roles.paymentLinkNeedsApprover(rules, before, after)
        ? "Only an approver can change or remove the payment link of an issued invoice. You can add one where there is none."
        : nil
    }
    return nil
  }
}
