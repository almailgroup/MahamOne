import Foundation

/// What each role may do, as the database enforces it (supabase/migrations),
/// ported from src/cloud/roles.ts. The app uses the same rules to hide what
/// a person can't open and to refuse a change before the server would.
///
/// A `nil` role is a company kept on this device only, where everything is
/// allowed. Records are raw JSON; a missing record (`nil`) and `null` are the
/// same. Whether a record is private (`isPrivateRecord`) is the sync layer's
/// (Sync/Privacy.swift): the rules that need it take it as a closure.
public enum Roles {
  /// Looks up another record of the same company (an attachment's owner): table, id.
  public typealias RecordLookup = (_ table: String, _ id: String) -> JSONValue?
  /// Whether a record of a table is payroll or people data (`isPrivateRecord`).
  public typealias PrivacyCheck = (_ table: String, _ record: JSONValue?) -> Bool
  /// Finds a warehouse of the company by id, as stored.
  public typealias WarehouseLookup = (_ id: String) -> JSONValue?

  // MARK: Roles

  public static let memberRoles: [MemberRole] = [.owner, .admin, .accountant, .staff, .viewer]

  /// Roles someone can be invited as.
  public static let inviteRoles: [MemberRole] = [.admin, .accountant, .staff, .viewer]

  /// English keys, translated when shown.
  public static let roleLabels: [MemberRole: String] = [
    .owner: "Owner", .admin: "Admin", .accountant: "Accountant", .staff: "Staff", .viewer: "Viewer",
  ]

  public static let roleDescriptions: [MemberRole: String] = [
    .owner: "Everything, including the team and deleting the company.",
    .admin: "Everything except deleting the company. Manages the team.",
    .accountant: "All books and payroll. No team management.",
    .staff: "Sales, purchases, cheques and stock. No payroll or accounting setup.",
    .viewer: "Can look at everything except payroll, and change nothing.",
  ]

  public static func isMemberRole(_ value: JSONValue?) -> Bool {
    guard case .string(let text)? = value else { return false }
    return MemberRole(rawValue: text) != nil
  }

  /// Payroll and people data: only owners, admins and accountants see them.
  public static let peopleTables: [String] = [
    "employees", "payRuns", "payrollSettings", "peopleSettings", "leaveRecords", "staffLoans", "finalSettlements",
    "letterTemplates", "employeeLetters",
    // Manpower costings: salaries, costs and margins.
    "staffingCostings",
  ]

  /// Tables staff may change (the company record only in its document numbers).
  public static let staffTables: [String] = [
    "companies", "clients", "products", "documents", "payments", "recurring", "securityCheques", "expenses",
    "warehouses", "stockMovements", "stockEntries", "landedCosts", "attachments", "activities",
    // To ask for approval; see guardApprovalWrite.
    "approvals",
  ]

  /// Journals staff may make: the ones their own work creates.
  public static let staffJournalKinds: [String] = ["transfer", "cheque_clearing", "cheque_return", "retention_release"]

  private static let people = Set(peopleTables)
  private static let staffSet = Set(staffTables)
  private static let staffJournals = Set(staffJournalKinds)

  /// The register document a renewal is of, or nil for one of an employee's own papers.
  public static func renewedDocumentId(_ renewal: JSONValue?) -> String? {
    if case .string(let id)? = renewal?["documentId"], !id.isEmpty { return id }
    guard case .string(let key)? = renewal?["documentKey"], key.hasPrefix("doc:"), key.utf16.count > 4 else {
      return nil
    }
    return String(key.dropFirst(4))
  }

  /// Sees payroll and people data.
  public static func canSeePeople(_ role: MemberRole?) -> Bool {
    role == nil || role == .owner || role == .admin || role == .accountant
  }

  /// May change anything at all.
  public static func canEdit(_ role: MemberRole?) -> Bool {
    role != .viewer
  }

  /// Invites people and changes roles.
  public static func canManageTeam(_ role: MemberRole?) -> Bool {
    role == .owner || role == .admin
  }

  /// The Super Admin: the owner of the company.
  public static func isSuperAdmin(_ role: MemberRole?) -> Bool {
    role == .owner
  }

  /// Roles only the owner gives once the owner keeps them (Settings → Team).
  public static let seniorRoles: [MemberRole] = [.admin, .accountant]

  /// At most this many admins or accountants approve besides the owner.
  public static let maxApprovers = 2

  /// Decides approval requests: the owner, or an admin or accountant the
  /// owner allowed to (`canApprove`), as almailbooks.is_approver.
  public static func isApprover(_ role: MemberRole?, _ canApprove: Bool?) -> Bool {
    role == .owner || (canApprove == true && (role == .admin || role == .accountant))
  }

  /// May get the morning email alerts of a company: owners and admins, and
  /// accountants once the server has the document alerts.
  public static func getsEmailAlerts(_ role: MemberRole?, documentAlerts: Bool) -> Bool {
    role == .owner || role == .admin || (documentAlerts && role == .accountant)
  }

  /// Gets the changes of the team (the bell and its emails): the owner and the approvers.
  public static func getsChangeFeed(_ role: MemberRole?, _ canApprove: Bool?) -> Bool {
    isApprover(role, canApprove)
  }

  /// Whether a change of the feed is shown to someone who gets the feed:
  /// never their own, and one about payroll or people data only to those who
  /// see them.
  public static func seesChange(actor: String?, isPrivate: Bool, viewer userId: String, role: MemberRole?) -> Bool {
    actor != userId && (!isPrivate || canSeePeople(role))
  }

  /// The roles `me` may invite someone as, or give a member. With the
  /// owner's rule on (`ownerOnly`), admins give staff and viewer only.
  public static func grantableRoles(_ me: MemberRole?, ownerOnly: Bool) -> [MemberRole] {
    if me == .owner { return inviteRoles }
    if me != .admin { return [] }
    return ownerOnly ? inviteRoles.filter { !seniorRoles.contains($0) } : inviteRoles
  }

  /// Whether `me` may change the role of, or remove, a member who is `role`.
  public static func canChangeMember(_ me: MemberRole?, _ role: MemberRole, ownerOnly: Bool) -> Bool {
    if role == .owner { return false }
    if me == .owner { return true }
    return me == .admin && !(ownerOnly && seniorRoles.contains(role))
  }

  // MARK: The owner's limits

  /// How much of an app a member may use. No access is stored as "none"
  /// (named so that it never reads as Optional's `.none`).
  public enum AppAccess: String, CaseIterable, Comparable, Sendable {
    case noAccess = "none"
    case view, edit, manage

    public static func < (a: AppAccess, b: AppAccess) -> Bool {
      allCases.firstIndex(of: a) ?? 0 < allCases.firstIndex(of: b) ?? 0
    }
  }

  /// The apps the owner can limit: every app of Maham One's classic layout.
  public enum CoreApp: String, CaseIterable, Sendable {
    case books, people, crm, compliance
  }

  /// Every app of the suite; Maham Sales and Maham Inventory of the split
  /// layout are Books' pages and follow its limit.
  public enum App: String, CaseIterable, Sendable {
    case books, people, crm, compliance, sales, inventory
  }

  /// What the owner lets a member do, app by app. Limits only ever take
  /// away; none means the role's access.
  public struct Permissions: Hashable, Sendable {
    public var apps: [CoreApp: AppAccess]

    public init(apps: [CoreApp: AppAccess] = [:]) {
      self.apps = apps
    }
  }

  public static let limitApps: [CoreApp] = CoreApp.allCases

  /// The app whose limit an app follows.
  public static func limitApp(of app: App) -> CoreApp {
    switch app {
    case .sales, .inventory, .books: .books
    case .people: .people
    case .crm: .crm
    case .compliance: .compliance
    }
  }

  /// Limits as the server sent them (`company_members.permissions`), keeping
  /// only apps and levels this version knows: what isn't understood limits nothing.
  public static func readPermissions(_ value: JSONValue?) -> Permissions {
    guard case .object(let apps)? = value?["apps"] else { return Permissions() }
    var known: [CoreApp: AppAccess] = [:]
    for app in limitApps {
      if case .string(let limit)? = apps[app.rawValue], let access = AppAccess(rawValue: limit) {
        known[app] = access
      }
    }
    return Permissions(apps: known)
  }

  /// The lower of a role's access and a limit.
  public static func lowerAccess(_ access: AppAccess, _ limit: AppAccess?) -> AppAccess {
    guard let limit else { return access }
    return limit < access ? limit : access
  }

  /// The owner's limit on an app for a member; never for the owner.
  public static func appLimit(_ role: MemberRole?, _ permissions: Permissions?, _ app: App) -> AppAccess? {
    guard let role, role != .owner else { return nil }
    return permissions?.apps[limitApp(of: app)]
  }

  private static let complianceApp: Set<String> = ["complianceDocuments", "renewals", "complianceMarks", "vehicles"]
  private static let booksApp: Set<String> = [
    "clients", "products", "taxRates", "documents", "payments", "recurring", "accounts", "journals", "expenses",
    "vatReturns", "bankTransactions", "securityCheques", "assets", "depreciationRuns", "yearEnds", "warehouses",
    "stockMovements", "stockEntries", "landedCosts", "chequeLayouts", "stockIssues",
  ]

  /// The records a file (an attachment) is kept with, as almailbooks.attachment_app looks them up.
  public static let attachmentOwnerTables: [String] = [
    "employees", "employeeLetters", "letterTemplates", "complianceDocuments", "renewals", "vehicles", "documents",
    "payments", "expenses", "assets", "securityCheques", "products",
  ]

  /// The app a record belongs to, for the owner's limits; nil for what every
  /// app shares (the company record, activity, approval requests), as
  /// almailbooks.record_app. A file is of the app of the record it is kept
  /// with, found with `lookup`; without it, or when that record isn't found,
  /// it has none.
  public static func recordApp(_ table: String, _ record: JSONValue?, lookup: RecordLookup? = nil) -> CoreApp? {
    if table == "attachments" {
      guard case .string(let owner)? = record?["ownerId"], !owner.isEmpty, let lookup else { return nil }
      for tbl in attachmentOwnerTables {
        if let found = WebJS.present(lookup(tbl, owner)) { return recordApp(tbl, found) }
      }
      return nil
    }
    if people.contains(table) { return .people }
    if table == "journals" && record?["kind"] == "payroll" { return .people }
    let employee: Bool = {
      if case .string(let id)? = record?["employeeId"] { return !id.isEmpty }
      return false
    }()
    if (table == "complianceDocuments" || table == "renewals") && employee { return .people }
    if complianceApp.contains(table) { return .compliance }
    if booksApp.contains(table) { return .books }
    return nil
  }

  /// Whether the owner's limits keep this member from storing `record` in
  /// `table` (an app limited to view only or no access), as can_write_record.
  public static func limitBlocksWrite(
    _ role: MemberRole?, _ permissions: Permissions?, _ table: String, _ record: JSONValue?,
    lookup: RecordLookup? = nil
  ) -> Bool {
    guard let app = recordApp(table, record, lookup: lookup) else { return false }
    let limit = appLimit(role, permissions, App(rawValue: app.rawValue) ?? .books)
    return limit == .noAccess || limit == .view
  }

  /// Whether the person has any app limited to view only or no access.
  public static func hasLimits(_ role: MemberRole?, _ permissions: Permissions?) -> Bool {
    limitApps.contains { app in
      let limit = appLimit(role, permissions, App(rawValue: app.rawValue) ?? .books)
      return limit == .noAccess || limit == .view
    }
  }

  // MARK: The company record

  /// The books' settings on the company record (see companyBooksChanged).
  public static let companyBooksFields: [String] = [
    "accounting", "payment", "bankAccount", "emailTemplates", "defaults", "taxesEnabled", "openingBalances",
    "vouchers", "items", "chequePrinting",
  ]

  /// The WAMD number printed with the payment details, empty and none alike.
  private static func wamdPhone(_ row: JSONValue?) -> JSONValue? {
    guard case .object(let kuwait)? = row?["kuwait"] else { return nil }
    let phone = kuwait["wamdPhone"]
    return phone == .string("") ? nil : phone
  }

  /// A numbering rule without its counter (next and period).
  private static func ruleShape(_ rule: JSONValue?) -> JSONValue? {
    guard case .object(var fields)? = rule else { return rule }
    fields["next"] = nil
    fields["period"] = nil
    return .object(fields)
  }

  /// Whether the books' settings on the company record differ, as
  /// almailbooks.company_books_changed: the accounting settings, the payment
  /// details and the WAMD number, email templates, document defaults, taxes,
  /// opening balances, vouchers, items, cheque printing and the numbering
  /// rules, but not their counters, nor employees' numbering, nor a rule
  /// added or removed. A member the owner made Books view only for (or gave
  /// no access) doesn't change them.
  public static func companyBooksChanged(_ before: JSONValue?, _ after: JSONValue?) -> Bool {
    guard let before = WebJS.present(before), let after = WebJS.present(after) else { return false }
    if companyBooksFields.contains(where: { !WebJS.sameData(before[$0], after[$0]) }) { return true }
    if !WebJS.sameData(wamdPhone(before), wamdPhone(after)) { return true }
    func rules(_ row: JSONValue) -> [String: JSONValue] {
      if case .object(let numbering)? = row["numbering"] { return numbering }
      return [:]
    }
    let old = rules(before)
    let next = rules(after)
    return old.keys.contains { key in
      key != "employee" && next[key] != nil && !WebJS.sameData(ruleShape(old[key]), ruleShape(next[key]))
    }
  }

  /// Changes accounting setup: accounts, tax rates, manual journals, year-end.
  public static func canEditAccounting(_ role: MemberRole?) -> Bool {
    role == nil || role == .owner || role == .admin || role == .accountant
  }

  /// Whether `role` may store `record` in `table`. Staff may change only
  /// their tables (never payroll or people data, judged by `isPrivate`), the
  /// journals their work makes, and the company record only in its document
  /// counters (see `staffCompanyChangeOk`).
  public static func canWriteRecord(
    _ role: MemberRole?, _ table: String, _ record: JSONValue?, isPrivate: PrivacyCheck
  ) -> Bool {
    if role == nil || role == .owner || role == .admin || role == .accountant { return true }
    if role != .staff { return false }
    // People tables are private whatever they hold.
    if people.contains(table) || isPrivate(table, record) { return false }
    if table == "journals" { return staffJournals.contains(WebJS.string(WebJS.present(record?["kind"]) ?? "")) }
    return staffSet.contains(table)
  }

  /// Staff saving the company record: only document counters (next, period) may differ.
  public static func staffCompanyChangeOk(_ before: JSONValue?, _ after: JSONValue?) -> Bool {
    guard let before = WebJS.present(before), let after = WebJS.present(after) else { return false }
    func strip(_ row: JSONValue) -> JSONValue {
      var copy = WebJS.spread(row)
      copy["numbering"] = nil
      copy["updatedAt"] = nil
      return .object(copy)
    }
    if !WebJS.sameData(strip(before), strip(after)) { return false }
    let old = WebJS.present(before["numbering"]) ?? .object([:])
    let next = WebJS.present(after["numbering"]) ?? .object([:])
    for (key, rule) in WebJS.spread(old) {
      let changed = WebJS.property(next, key)
      if !WebJS.truthy(changed) { continue }
      func shape(_ r: JSONValue?) -> JSONValue {
        var copy = WebJS.spread(r)
        copy["next"] = nil
        copy["period"] = nil
        return .object(copy)
      }
      if !WebJS.sameData(shape(rule), shape(changed)) { return false }
    }
    return true
  }

  /// Deep equality of JSON data, as the web's `sameData` of roles.ts: a
  /// missing value and null are the same at the top, a field set to null is
  /// not a missing field.
  public static func sameData(_ a: JSONValue?, _ b: JSONValue?) -> Bool {
    WebJS.sameData(a, b)
  }

  // MARK: Approvals

  /// The fields of a document that say what it is, as it is printed and sent
  /// (almailbooks.invoice_content).
  public static let invoiceContentFields: [String] = [
    "type", "number", "clientId", "issueDate", "dueDate", "poNumber", "vendorReference", "currency", "exchangeRate",
    "items", "discount", "discountType", "taxes", "charges", "pricesIncludeTax", "deposit", "depositDueDate", "notes",
    "terms", "footer", "intro", "templateId", "accentColor", "deliveryDate", "deliveryPlace", "retentionPercent",
    "retentionKind", "replacesNumber",
  ]

  /// What a document says (see invoiceContentFields), without nulls, as almailbooks.invoice_content.
  public static func invoiceContent(_ doc: JSONValue?) -> JSONValue {
    var picked: [String: JSONValue] = [:]
    for field in invoiceContentFields { picked[field] = doc?[field] }
    return WebJS.stripNulls(.object(picked))
  }

  /// The company's approval rules (`approvalRules`), or nil while they were never turned on.
  public static func approvalRulesOf(_ company: JSONValue?) -> JSONValue? {
    if case .object(let rules)? = company?["approvalRules"] { return .object(rules) }
    return nil
  }

  /// Whether the rules cover issued documents of this type.
  public static func rulesCoverDocument(_ rules: JSONValue?, _ type: JSONValue?) -> Bool {
    guard case .array(let types)? = rules?["documentTypes"] else { return false }
    return types.contains(.string(type?.string ?? ""))
  }

  /// A document's stage: payments move an issued document within it only.
  public enum DocumentStage: String, Sendable {
    case draft, void, issued
  }

  public static func documentStage(_ status: JSONValue?) -> DocumentStage {
    switch status {
    case .string("draft")?: .draft
    case .string("void")?: .void
    default: .issued
    }
  }

  /// Whether storing `after` over `before` needs an approver, as
  /// records_guard: an issued document of a type the rules cover whose
  /// content changes, or that is voided, comes back from void or goes back
  /// to draft. New documents and drafts never do.
  public static func documentChangeNeedsApproval(_ rules: JSONValue?, _ before: JSONValue?, _ after: JSONValue?)
    -> Bool
  {
    guard WebJS.present(rules) != nil, let old = WebJS.present(before), let next = WebJS.present(after),
      old["status"] != "draft"
    else { return false }
    if !rulesCoverDocument(rules, old["type"]) && !rulesCoverDocument(rules, next["type"]) { return false }
    return !WebJS.sameData(invoiceContent(old), invoiceContent(next))
      || documentStage(old["status"]) != documentStage(next["status"])
  }

  /// The address of a document's payment link, or "" for none.
  private static func paymentLinkUrl(_ row: JSONValue?) -> String {
    switch row?["paymentLink"] {
    case .object(let link)?: link["url"]?.string ?? ""
    default: ""
    }
  }

  /// Whether storing `after` over `before` changes or removes the payment
  /// link of an issued document the rules cover (almailbooks.payment_link_changed).
  /// Adding one where there was none stays open.
  public static func paymentLinkNeedsApprover(_ rules: JSONValue?, _ before: JSONValue?, _ after: JSONValue?) -> Bool {
    guard WebJS.present(rules) != nil, let old = WebJS.present(before), let next = WebJS.present(after),
      old["status"] != "draft"
    else { return false }
    if !rulesCoverDocument(rules, old["type"]) && !rulesCoverDocument(rules, next["type"]) { return false }
    let was = paymentLinkUrl(old)
    return was != "" && was != paymentLinkUrl(next)
  }

  /// A key of `before` kept as it was (or left out, as it was), as almailbooks.kept_key.
  private static func keepKey(_ data: inout [String: JSONValue], _ before: [String: JSONValue], _ key: String) {
    data[key] = before[key]
  }

  /// What the cloud stores when anyone but an approver writes a document: a
  /// copy that would change or remove its payment link keeps the stored one.
  public static func keepPaymentLink(_ rules: JSONValue?, _ before: JSONValue?, _ after: JSONValue) -> JSONValue {
    if !paymentLinkNeedsApprover(rules, before, after) { return after }
    var data = WebJS.spread(after)
    keepKey(&data, WebJS.object(before) ?? [:], "paymentLink")
    return .object(data)
  }

  /// What keeps a record from being deleted (can_delete_record).
  public enum DeleteKeeper: String, Sendable {
    /// Approval requests: always.
    case request
    /// An issued document the rules cover, with "Void instead of delete": it is voided instead.
    case void
    /// An issued document the rules cover: only an approver deletes it (anyone else asks for a void).
    case approver
  }

  /// What keeps a record from being deleted, as can_delete_record; nil when nothing keeps it.
  public static func deleteKeptBy(_ rules: JSONValue?, _ table: String, _ record: JSONValue?, approver: Bool)
    -> DeleteKeeper?
  {
    if table == "approvals" { return .request }
    guard let ruled = WebJS.present(rules), table == "documents", record?["status"] != "draft" else { return nil }
    if !rulesCoverDocument(ruled, record?["type"]) { return nil }
    if ruled["voidInsteadOfDelete"] == true { return .void }
    return approver ? nil : .approver
  }

  /// Whether the rules keep a record from being deleted by anyone, approvers too.
  public static func rulesKeepRecord(_ rules: JSONValue?, _ table: String, _ record: JSONValue?) -> Bool {
    deleteKeptBy(rules, table, record, approver: true) != nil
  }

  /// Whether storing `after` over `before` (nil: new) issues an invoice or
  /// credit note without its number while the company numbers them when
  /// they are issued (`defaults.numberOnIssue`), as records_guard refuses.
  public static func issuesWithoutNumber(_ company: JSONValue?, _ before: JSONValue?, _ after: JSONValue?) -> Bool {
    guard let next = WebJS.present(after), company?["defaults"]?["numberOnIssue"] == true else { return false }
    if next["type"] != "invoice" && next["type"] != "credit" { return false }
    if documentStage(next["status"]) != .issued { return false }
    if !WebJS.trim(WebJS.string(WebJS.present(next["number"]) ?? "")).isEmpty { return false }
    guard let old = WebJS.present(before) else { return true }
    return old["status"] == "draft"
  }

  // MARK: Cheques

  private static func chequeRules(_ rules: JSONValue?) -> [String: JSONValue]? {
    if case .object(let cheques)? = rules?["cheques"] { return cheques }
    return nil
  }

  /// Whether the rules ask an approver to confirm this payment, as
  /// almailbooks.rules_cover_cheque: a cheque the company writes (issued) or
  /// receives (received).
  public static func rulesCoverCheque(_ rules: JSONValue?, _ payment: JSONValue?) -> Bool {
    guard let row = WebJS.present(payment), let cheques = chequeRules(rules), row["method"] == "cheque" else {
      return false
    }
    return cheques[row["direction"] == "out" ? "issued" : "received"] == true
  }

  /// Whether the rules ask an approver to confirm this security cheque: one the company hands over.
  public static func rulesCoverSecurityCheque(_ rules: JSONValue?, _ cheque: JSONValue?) -> Bool {
    guard let row = WebJS.present(cheque) else { return false }
    return row["direction"] == "out" && chequeRules(rules)?["securityOut"] == true
  }

  /// The cheque details of a payment (`payment.cheque`), when it has any.
  private static func chequeOf(_ row: JSONValue?) -> JSONValue? {
    guard let cheque = row?["cheque"] else { return nil }
    switch cheque {
    case .object, .array: return cheque
    default: return nil
    }
  }

  /// What an approver confirms on a cheque payment, as
  /// almailbooks.cheque_content: the money and the account it is booked to,
  /// who it is for and the cheque itself.
  public static func chequeContent(_ payment: JSONValue?) -> JSONValue {
    let row = payment
    let cheque = chequeOf(row)
    let civilId = cheque?["drawerCivilId"]
    let fields: [String: JSONValue?] = [
      "method": row?["method"],
      "direction": WebJS.present(row?["direction"]) ?? "in",
      "clientId": row?["clientId"],
      "date": row?["date"],
      "amount": row?["amount"],
      "currency": row?["currency"],
      "exchangeRate": WebJS.present(row?["exchangeRate"]) ?? 1,
      "accountId": row?["accountId"],
      "number": cheque?["number"],
      "bank": cheque?["bank"],
      "chequeDate": cheque?["date"],
      "drawer": cheque?["drawer"],
      "drawerCivilId": civilId == .string("") ? nil : civilId,
    ]
    return WebJS.stripNulls(.object(fields.compactMapValues { $0 }))
  }

  /// The same for a security cheque, as almailbooks.security_cheque_content.
  public static func securityChequeContent(_ cheque: JSONValue?) -> JSONValue {
    let row = cheque
    let civilId = row?["drawerCivilId"]
    let fields: [String: JSONValue?] = [
      "direction": WebJS.present(row?["direction"]) ?? "in",
      "number": row?["number"],
      "bank": row?["bank"],
      "date": row?["date"],
      "amount": row?["amount"],
      "currency": row?["currency"],
      "drawer": row?["drawer"],
      "drawerCivilId": civilId == .string("") ? nil : civilId,
    ]
    return WebJS.stripNulls(.object(fields.compactMapValues { $0 }))
  }

  /// A cheque number as text without the spaces around it; nil when there is none.
  private static func leafNumber(_ value: JSONValue?) -> String? {
    guard let value = WebJS.present(value) else { return nil }
    return WebJS.trim(WebJS.string(value))
  }

  /// The leaves a cheque records as spoiled, by number.
  private static func spoiledNumbers(_ payment: JSONValue?) -> [String?] {
    guard case .array(let leaves)? = chequeOf(payment)?["spoiledLeaves"] else { return [] }
    return leaves.map { leaf in
      switch leaf {
      case .object, .array: leafNumber(leaf["number"])
      default: nil
      }
    }
  }

  /// Whether storing `after` over `before` (nil: new, or deleted) waits for
  /// an approver, as almailbooks.cheque_change_needs_approver: a new cheque
  /// the rules cover, a change of what is confirmed on one they cover, or
  /// deleting one. A printed cheque moved to its next leaf, with the spoiled
  /// leaf on record, keeps its confirmation; so does one given its first account.
  public static func chequeChangeNeedsApprover(
    _ rules: JSONValue?, _ table: String, _ before: JSONValue?, _ after: JSONValue?
  ) -> Bool {
    let old = WebJS.present(before)
    let next = WebJS.present(after)
    guard WebJS.present(rules) != nil else { return false }
    if table == "payments" {
      if !rulesCoverCheque(rules, old) && !rulesCoverCheque(rules, next) { return false }
      guard let old, let next else { return true }
      var a = WebJS.object(chequeContent(old)) ?? [:]
      var b = WebJS.object(chequeContent(next)) ?? [:]
      let moved = leafNumber(a["number"])
      if !WebJS.sameData(a["number"], b["number"]), let moved, spoiledNumbers(next).contains(moved) {
        a["number"] = nil
        b["number"] = nil
      }
      // A cheque saved before it had an account gets one: only moving it needs an approver.
      if a["accountId"] == nil || a["accountId"] == .string("") {
        a["accountId"] = nil
        b["accountId"] = nil
      }
      return !WebJS.sameData(.object(a), .object(b))
    }
    if table == "securityCheques" {
      if !rulesCoverSecurityCheque(rules, old) && !rulesCoverSecurityCheque(rules, next) { return false }
      guard let old, let next else { return true }
      return !WebJS.sameData(securityChequeContent(old), securityChequeContent(next))
    }
    return false
  }

  /// Whether the approval rules differ between two copies of the company record (the owner's alone).
  public static func approvalRulesChanged(_ before: JSONValue?, _ after: JSONValue?) -> Bool {
    !WebJS.sameData(before?["approvalRules"], after?["approvalRules"])
  }

  // MARK: Payroll approval

  /// Whether the rules keep pay runs for the Super Admin's approval (`approvalRules.payroll`).
  public static func rulesCoverPayroll(_ rules: JSONValue?) -> Bool {
    rules?["payroll"] == true
  }

  /// A request for a pay run's approval (kind payroll, about a pay run).
  public static func isPayrollApproval(_ request: JSONValue?) -> Bool {
    request?["kind"] == "payroll" && request?["subjectTbl"] == "payRuns"
  }

  /// Whether the person may post pay runs, as almailbooks.can_write_record
  /// judges a pay run: an owner, admin or accountant whose People the owner
  /// hasn't made view only (or closed).
  public static func canPostPayroll(_ role: MemberRole?, _ permissions: Permissions?) -> Bool {
    // Pay runs are people data: private whatever they hold.
    canWriteRecord(role, "payRuns", [:], isPrivate: { _, _ in true })
      && !limitBlocksWrite(role, permissions, "payRuns", [:])
  }

  /// A JSON value as `->>` reads it: text, or nil.
  private static func asText(_ value: JSONValue?) -> String? {
    guard let value = WebJS.present(value) else { return nil }
    return value.string ?? WebJS.json(value)
  }

  /// Why the cloud refuses to approve a request for a pay run.
  public enum PayrollRefusal: String, Sendable {
    /// A member approving a pay run they sent themselves ("self").
    case selfApproval = "self"
    /// The pay run changed since the request was sent.
    case stale
    /// A member the owner gave no access to People deciding.
    case people
  }

  /// Why the cloud refuses to decide a request for a pay run with the
  /// company's salary approval on, or nil: a member allowed to approve never
  /// approves a pay run they sent themselves (the owner may), and nobody
  /// approves one that changed since it was sent (`run` is the pay run as
  /// stored). The owner who posts the pay run carries out a waiting request
  /// as it is. A member with no access to People (`peopleShut`) decides none;
  /// they may still take back their own.
  public static func payrollDecisionRefusal(
    _ before: JSONValue?, _ after: JSONValue?, userId: String, owner: Bool, peopleShut: Bool = false,
    run: JSONValue?
  ) -> PayrollRefusal? {
    let old = WebJS.present(before)
    let was: String? = old.map { _ in asText(old?["status"]) ?? "pending" }
    let status = asText(after?["status"]) ?? was
    let decided: Set<String> = ["rejected", "cancelled", "applied"]
    let decision: Bool = {
      guard let was, let status else { return false }
      return status != was && status != "pending" && !decided.contains(was)
    }()
    let takenBack = was == "pending" && status == "cancelled" && asText(old?["requestedBy"]) == userId
    if decision && peopleShut && !owner && !takenBack { return .people }
    if was != "pending" || (status != "approved" && status != "applied") { return nil }
    if asText(old?["requestedBy"]) == userId && !owner { return .selfApproval }
    if status == "applied" && owner { return nil }
    let asked = old?["after"]?["runUpdatedAt"]
    return asText(run?["updatedAt"]) != asText(asked) ? .stale : nil
  }

  private static let approvalFixed = [
    "kind", "subjectTbl", "subjectId", "subjectNumber", "before", "after", "reason", "requestedBy", "requestedByName",
    "requestedAt", "createdAt",
  ]
  private static let decided: Set<String> = ["rejected", "cancelled", "applied"]
  private static let decisions: Set<String> = ["approved", "rejected", "cancelled", "applied"]

  /// What the cloud stores when someone writes an approval request, or why it refuses.
  public enum ApprovalWrite: Hashable, Sendable {
    case data(JSONValue)
    case refused(ApprovalRefusal)
  }

  public enum ApprovalRefusal: String, Sendable {
    case permission, invalid
  }

  /// Who writes an approval request: `now` is the server's time.
  public struct ApprovalWriter: Hashable, Sendable {
    public var userId: String
    public var approver: Bool
    public var owner: Bool
    public var now: String

    public init(userId: String, approver: Bool, owner: Bool = false, now: String) {
      self.userId = userId
      self.approver = approver
      self.owner = owner
      self.now = now
    }
  }

  /// The company's salary approval, once its server has it: `on` with
  /// `approvalRules.payroll`, and whether the person may post pay runs.
  public struct PayrollSwitch: Hashable, Sendable {
    public var on: Bool
    public var poster: Bool

    public init(on: Bool, poster: Bool) {
      self.on = on
      self.poster = poster
    }
  }

  /// What the cloud stores when someone writes an approval request
  /// (records_guard, whether or not the company's rules are on), or why it
  /// refuses: a new request waits, stamped with who asked and when; what was
  /// asked never changes; only an approver decides (whoever asked may take
  /// it back while it waits, and changes nothing else); a decision made
  /// stays made, whatever an older copy says. A decided request sent up new
  /// is kept as it is from the owner and stamped as asked and decided by
  /// anyone else. With salary approval on, a pay run's request sent up
  /// already approved by anyone but the owner waits like any new one, and
  /// whoever posts the approved pay run marks its request done.
  public static func guardApprovalWrite(
    _ before: JSONValue?, _ after: JSONValue, who: ApprovalWriter, payroll: PayrollSwitch? = nil
  ) -> ApprovalWrite {
    let payrollOn = (payroll?.on ?? false) && isPayrollApproval(WebJS.present(before) ?? after)
    let afterFields = WebJS.spread(after)
    guard let old = WebJS.present(before) else {
      let asked = WebJS.present(after["status"]) ?? "pending"
      let selfApproved = payrollOn && (asked == "approved" || asked == "applied")
      if who.approver && asked != "pending" && (who.owner || !selfApproved) {
        if who.owner { return .data(after) }
        var data = afterFields
        if data["requestedBy"] != .string(who.userId) {
          data["requestedByName"] = nil
          data["requestedBy"] = .string(who.userId)
          data["requestedAt"] = .string(who.now)
        }
        if data["decidedBy"] != .string(who.userId) {
          data["decidedBy"] = .string(who.userId)
          data["decidedAt"] = .string(who.now)
        }
        return .data(.object(data))
      }
      var data = afterFields
      data["expired"] = nil
      data["resultId"] = nil
      data["status"] = "pending"
      data["requestedBy"] = .string(who.userId)
      data["requestedAt"] = .string(who.now)
      data["decidedBy"] = .null
      data["decidedAt"] = .null
      data["decisionNote"] = ""
      return .data(.object(data))
    }
    let beforeFields = WebJS.spread(old)
    let was = old["status"]?.string ?? "pending"
    let status = after["status"]?.string ?? was
    // Whoever isn't an approver changes nothing of a request but taking it back.
    var data: [String: JSONValue]
    if who.approver {
      data = afterFields
    } else {
      data = beforeFields
      data["status"] = .string(status)
      if let updatedAt = afterFields["updatedAt"] { data["updatedAt"] = updatedAt }
    }
    for key in approvalFixed { keepKey(&data, beforeFields, key) }
    let kept: [String: JSONValue] = [
      "decidedBy": WebJS.present(beforeFields["decidedBy"]) ?? .null,
      "decidedAt": WebJS.present(beforeFields["decidedAt"]) ?? .null,
      "decisionNote": WebJS.present(beforeFields["decisionNote"]) ?? "",
    ]
    // No decision now (an older copy that still waits, sent again), or one made before.
    if status == was || status == "pending" || decided.contains(was) {
      var same = data.merging(kept) { _, keptValue in keptValue }
      same["status"] = .string(was)
      keepKey(&same, beforeFields, "expired")
      keepKey(&same, beforeFields, "resultId")
      return .data(.object(same))
    }
    if !decisions.contains(status) { return .refused(.invalid) }
    let takenBack = was == "pending" && status == "cancelled" && beforeFields["requestedBy"] == .string(who.userId)
    // The approved pay run posted: done, by whoever may post it.
    let posted = payrollOn && (payroll?.poster ?? false) && was == "approved" && status == "applied"
    if !who.approver && !takenBack && !posted { return .refused(.permission) }
    // Expired only when an approver cancels a waiting request; what it made only when carried out.
    if !(who.approver && was == "pending" && status == "cancelled") { keepKey(&data, beforeFields, "expired") }
    if !(who.approver && status == "applied") { keepKey(&data, beforeFields, "resultId") }
    if was == "approved" && status == "applied" {
      return .data(.object(data.merging(kept) { _, keptValue in keptValue }))
    }
    data["decidedBy"] = .string(who.userId)
    data["decidedAt"] = .string(who.now)
    return .data(.object(data))
  }

  // MARK: Employee letters

  /// Whether the company's letters are on (`PeopleSettings.letters`), as almailbooks.letters_on.
  public static func lettersSwitchedOn(_ settings: JSONValue?) -> Bool {
    settings?["letters"] == true
  }

  /// Issues letters, and changes or voids issued ones: the owner, an admin
  /// or an approver; everyone in a company kept on this device. Accountants
  /// draft them and ask for approval.
  public static func issuesLetters(_ role: MemberRole?, _ canApprove: Bool?) -> Bool {
    role == nil || role == .owner || role == .admin || isApprover(role, canApprove)
  }

  /// Turns the company's letters on or off: the owner or an admin.
  public static func switchesLetters(_ role: MemberRole?) -> Bool {
    role == nil || role == .owner || role == .admin
  }

  /// Turns the company's AI assistant on or off: the owner or an admin.
  public static func switchesAi(_ role: MemberRole?) -> Bool {
    role == nil || role == .owner || role == .admin
  }

  /// Whether a write of the company record changes its AI assistant switch (`ai`).
  public static func aiSwitchChanged(_ before: JSONValue?, _ after: JSONValue?) -> Bool {
    !WebJS.sameData(before?["ai"], after?["ai"])
  }

  /// What the cloud stores when someone writes the company record: for
  /// anyone but the owner or an admin, the AI switch as it was stored (or
  /// left out, as it was).
  public static func keepAiSwitch(_ role: MemberRole?, _ before: JSONValue?, _ after: JSONValue) -> JSONValue {
    if role == .owner || role == .admin { return after }
    var data = WebJS.spread(after)
    keepKey(&data, WebJS.object(before) ?? [:], "ai")
    return .object(data)
  }

  /// A request to issue a letter (kind letter, about an employee letter).
  public static func isLetterApproval(_ request: JSONValue?) -> Bool {
    request?["kind"] == "letter" && request?["subjectTbl"] == "employeeLetters"
  }

  /// What a letter says and is, as almailbooks.letter_content: all of it but
  /// when it was last printed and saved, without nulls.
  public static func letterContent(_ letter: JSONValue?) -> JSONValue {
    var copy = WebJS.spread(WebJS.present(letter))
    copy["printedAt"] = nil
    copy["updatedAt"] = nil
    return WebJS.stripNulls(.object(copy))
  }

  /// Why the cloud refuses to store a letter with the company's letters on.
  public enum LetterRefusal: String, Sendable {
    /// An issued or void letter never goes back to a draft.
    case issued
    /// Only someone who issues letters issues one, or changes or voids an issued one.
    case issuer
  }

  /// Why the cloud refuses to store `after` over `before` (nil: new) with
  /// the company's letters on, as records_guard, or nil. Drafts are anyone's
  /// who may write them; so is marking an issued letter printed.
  public static func letterWriteRefusal(_ before: JSONValue?, _ after: JSONValue?, issuer: Bool) -> LetterRefusal? {
    let old = WebJS.present(before)
    guard let next = WebJS.present(after) else { return nil }
    let was: String? = old.map { asText($0["status"]) ?? "draft" }
    let status = asText(next["status"]) ?? "draft"
    if (was == "issued" || was == "void") && status == "draft" { return .issued }
    if issuer { return nil }
    if status == "draft" && (was == nil || was == "draft") { return nil }
    if let old, WebJS.sameData(letterContent(old), letterContent(next)) { return nil }
    return .issuer
  }

  /// Whether a letter is kept from being deleted with the company's letters
  /// on: once issued (or void) it stays, so its number stays used.
  public static func letterKept(_ letter: JSONValue?) -> Bool {
    (asText(letter?["status"]) ?? "draft") != "draft"
  }

  /// What the cloud stores when a letter that is issued or void is written
  /// again, as almailbooks.issued_letter_kept: it stays as it was issued and
  /// a void one stays void; only when it was last printed (the later of the
  /// two) and saved change, and an issued letter may be voided, with why and
  /// when. Any other letter passes as it is.
  public static func keepIssuedLetter(_ before: JSONValue?, _ after: JSONValue) -> JSONValue {
    guard let old = WebJS.present(before) else { return after }
    let was = asText(old["status"]) ?? "draft"
    if was != "issued" && was != "void" { return after }
    let voiding = was == "issued" && (asText(after["status"]) ?? "draft") == "void"
    var data = WebJS.spread(old)
    data["updatedAt"] = nil
    data["printedAt"] = nil
    if voiding {
      data["status"] = nil
      data["voidReason"] = nil
      data["voidedOn"] = nil
    }
    if let updatedAt = WebJS.present(after["updatedAt"]) { data["updatedAt"] = updatedAt }
    let printed = [asText(old["printedAt"]), asText(after["printedAt"])].compactMap { $0 }
      .max { WebJS.less($0, $1) }
    if let printed { data["printedAt"] = .string(printed) }
    if voiding {
      data["status"] = "void"
      if let reason = WebJS.present(after["voidReason"]) { data["voidReason"] = reason }
      if let on = WebJS.present(after["voidedOn"]) { data["voidedOn"] = on }
    }
    return .object(data)
  }

  /// Whether the People settings are kept from being deleted: while they
  /// have the letters on, by anyone but the owner or an admin.
  public static func peopleSettingsKept(_ role: MemberRole?, _ settings: JSONValue?) -> Bool {
    lettersSwitchedOn(settings) && !switchesLetters(role)
  }

  /// What the cloud stores when anyone but the owner or an admin writes the
  /// People settings: the letters switch as it was stored (or left out).
  public static func keepLettersSwitch(_ role: MemberRole?, _ before: JSONValue?, _ after: JSONValue) -> JSONValue {
    if role == .owner || role == .admin { return after }
    var data = WebJS.spread(after)
    keepKey(&data, WebJS.object(before) ?? [:], "letters")
    return .object(data)
  }

  // MARK: Sub-warehouses and items issued

  /// Sets up sub-warehouses and changes their stock directly: the owner, an
  /// admin or an accountant, as almailbooks.manages_warehouses.
  public static func managesWarehouses(_ role: MemberRole?) -> Bool {
    role == .owner || role == .admin || role == .accountant
  }

  private static func text(_ value: JSONValue?) -> String {
    value?.string ?? ""
  }

  /// A warehouse only those who manage warehouses change: a sub-warehouse,
  /// or one someone looks after, as almailbooks.warehouse_ruled.
  public static func warehouseRuled(_ warehouse: JSONValue?) -> Bool {
    guard let row = WebJS.present(warehouse) else { return false }
    let keeper: Bool = {
      switch row["keeper"] {
      case .object?, .array?: return true
      default: return false
      }
    }()
    return text(row["parentId"]) != "" || keeper
  }

  private static func isSub(_ warehouses: WarehouseLookup, _ id: JSONValue?) -> Bool {
    text(id) != "" && text(warehouses(text(id))?["parentId"]) != ""
  }

  /// A stock entry moves the stock of a sub-warehouse, as almailbooks.entry_in_sub_warehouse.
  public static func entryInSubWarehouse(_ entry: JSONValue?, _ warehouses: WarehouseLookup) -> Bool {
    guard let row = WebJS.present(entry) else { return false }
    return isSub(warehouses, row["warehouseId"]) || isSub(warehouses, row["toWarehouseId"])
  }

  /// The lines of a document that move a sub-warehouse's stock, with its
  /// type and stage, as almailbooks.sub_warehouse_lines, to compare two
  /// copies: JSON text, "[]" for none.
  public static func subWarehouseLines(_ doc: JSONValue?, _ warehouses: WarehouseLookup) -> String {
    let items = doc?["items"]?.array ?? []
    let lines = items.filter { isSub(warehouses, $0["warehouseId"]) }
      .map { item in
        (
          id: text(item["id"]), productId: text(item["productId"]), warehouseId: text(item["warehouseId"]),
          quantity: WebJS.present(item["quantity"]) ?? .null
        )
      }
      .enumerated()
      .sorted { a, b in
        if a.element.id != b.element.id { return WebJS.less(a.element.id, b.element.id) }
        return a.offset < b.offset
      }
      .map(\.element)
    if lines.isEmpty { return "[]" }
    let written = lines.map { line in
      "{\"id\":\(WebJS.quote(line.id)),\"productId\":\(WebJS.quote(line.productId)),"
        + "\"warehouseId\":\(WebJS.quote(line.warehouseId)),\"quantity\":\(WebJS.json(line.quantity))}"
    }
    let type = WebJS.json(WebJS.present(doc?["type"]) ?? .null)
    return "{\"lines\":[\(written.joined(separator: ","))],\"type\":\(type),"
      + "\"stage\":\(WebJS.quote(documentStage(doc?["status"]).rawValue))}"
  }

  /// May ask for items to be issued from a warehouse: a member who manages
  /// warehouses, or who looks after it (a sub-warehouse in use), as
  /// almailbooks.issues_from. Never in a company kept on this device only.
  public static func issuesFromWarehouse(_ role: MemberRole?, userId: String?, _ warehouse: JSONValue?) -> Bool {
    guard let role, role != .viewer else { return false }
    if managesWarehouses(role) { return true }
    guard let row = WebJS.present(warehouse), let userId, !userId.isEmpty else { return false }
    return text(row["parentId"]) != "" && row["archived"] != true && text(row["keeper"]?["userId"]) == userId
  }

  /// The name a request to issue items is stored with: the keeper's name and
  /// job title when the warehouse is theirs, otherwise none (the app names the account).
  public static func issuerName(userId: String?, _ warehouse: JSONValue?) -> String? {
    let keeper = warehouse?["keeper"]
    let name = WebJS.trim(text(keeper?["name"]))
    guard let userId, !userId.isEmpty, !name.isEmpty, text(keeper?["userId"]) == userId else { return nil }
    let title = WebJS.trim(text(keeper?["jobTitle"]))
    return title.isEmpty ? name : "\(name) (\(title))"
  }

  /// Why the cloud refuses a write about warehouses and the stock of sub-warehouses.
  public enum WarehouseRefusal: String, Sendable {
    /// What only those who manage warehouses do.
    case manager
    /// Items issued, written by anyone but an approver.
    case approver
    /// A request to issue items from a warehouse the person may not issue from.
    case keeper
  }

  /// Who writes about warehouses.
  public struct WarehouseWriter: Sendable {
    public var role: MemberRole?
    public var userId: String?
    public var approver: Bool

    public init(role: MemberRole?, userId: String?, approver: Bool) {
      self.role = role
      self.userId = userId
      self.approver = approver
    }
  }

  /// Why the cloud refuses a write about warehouses and the stock of
  /// sub-warehouses (records_guard and can_delete_record of the warehouse
  /// issues migration), or nil when it takes it. `after` nil is a delete.
  public static func warehouseWriteRefusal(
    _ member: WarehouseWriter, _ table: String, _ before: JSONValue?, _ after: JSONValue?,
    warehouses: WarehouseLookup
  ) -> WarehouseRefusal? {
    let manager = managesWarehouses(member.role)
    switch table {
    case "warehouses":
      return !manager && (warehouseRuled(after) || warehouseRuled(before)) ? .manager : nil
    case "stockEntries":
      return !manager && (entryInSubWarehouse(after, warehouses) || entryInSubWarehouse(before, warehouses))
        ? .manager : nil
    case "stockIssues":
      if WebJS.present(after) == nil { return .approver }
      return member.approver ? nil : .approver
    case "documents":
      if manager { return nil }
      // Deleted: one that moves a sub-warehouse's stock is theirs to delete.
      if WebJS.present(after) == nil {
        return subWarehouseLines(before, warehouses) != "[]" ? .manager : nil
      }
      return subWarehouseLines(after, warehouses) != subWarehouseLines(before, warehouses) ? .manager : nil
    case "approvals":
      guard WebJS.present(before) == nil, let request = WebJS.present(after), request["kind"] == "stock_issue" else {
        return nil
      }
      let warehouse = warehouses(text(request["after"]?["warehouseId"]))
      return issuesFromWarehouse(member.role, userId: member.userId, warehouse) ? nil : .keeper
    default:
      return nil
    }
  }
}
