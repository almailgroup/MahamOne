import Foundation

// MARK: Tables

/// The record kinds the cloud keeps (`DATA_TABLES` in src/db/db.ts, as
/// `RecordKind`) and the order they are sent in (`PUSH_ORDER`).
public enum SyncTables {
  public static let all: [String] = RecordKind.allCases.map(\.rawValue)

  public static let synced: Set<String> = Set(all)

  static func order(_ table: String) -> Int { RecordKind.pushOrder(of: table) }

  /// Tables of database version 16, 17 and 18 (see heldForServer).
  static let v16: [String] = ["chequeLayouts", "vehicles", "approvals", "letterTemplates", "employeeLetters"]
  static let v17: [String] = ["staffingCostings"]
  static let v18: [String] = ["stockIssues"]
}

// MARK: Errors

/// The codes the database and the network end a request with (src/cloud/api.ts).
public enum CloudErrorCode: String, Sendable, Codable, CaseIterable {
  case offline, auth, permission, invalid, resync, limit, server
  case notMember = "not_member"
  case tooLarge = "too_large"
  case companyTaken = "company_taken"
  case companyExists = "company_exists"
  case alreadyMember = "already_member"
  case inviteInvalid = "invite_invalid"
  case inviteRevoked = "invite_revoked"
  case inviteUsed = "invite_used"
  case inviteExpired = "invite_expired"
  case inviteWrongEmail = "invite_wrong_email"
  case emailUnconfirmed = "email_unconfirmed"
  /// The company's server lacks a migration the record needs: it waits here until it is run.
  case serverOutdated = "server_outdated"
  /// The company's approval rules: an approver must make this change.
  case approvalRequired = "approval_required"
}

/// A request the cloud refused or could not answer, with a code the sync acts on.
public struct CloudError: Error, Equatable, Sendable {
  public var code: CloudErrorCode
  /// The server's own words, for the record.
  public var detail: String

  public init(_ code: CloudErrorCode, _ detail: String = "") {
    self.code = code
    self.detail = detail
  }

  /// Worth trying again later as it is (connection, server, session).
  public var retryable: Bool { code == .offline || code == .server || code == .auth }

  /// Retried with backoff rather than parked (`not_member` and `resync` stop the sync instead).
  var stopsSending: Bool { retryable || code == .notMember || code == .resync }

  /// What went wrong, as the web's `cloudError` reads it: the database's own
  /// errors start with "almail:<code>"; row-level security refusals are
  /// permission; constraint failures are invalid.
  public static func from(_ error: Error) -> CloudError {
    if let error = error as? CloudError { return error }
    guard let error = error as? MahamError else { return CloudError(.server, String(describing: error)) }
    let message = error.message
    if let tagged = tag(in: message) { return CloudError(tagged, message) }
    switch error {
    case .offline: return CloudError(.offline, message)
    case .sessionExpired, .notSignedIn, .needsSecondStep: return CloudError(.auth, message)
    case .permission: return CloudError(.permission, message)
    case .server(let status, let code, _):
      if code == "42501" || message.range(of: "row-level security", options: .caseInsensitive) != nil
        || message.range(of: "permission denied", options: .caseInsensitive) != nil
      {
        return CloudError(.permission, message)
      }
      if code == "23514" || code == "22023" || code == "23505" { return CloudError(.invalid, message) }
      if status == 401 || message.range(of: "jwt", options: .caseInsensitive) != nil
        || message.range(of: "token is expired", options: .caseInsensitive) != nil
        || message.range(of: "not authenticated", options: .caseInsensitive) != nil
      {
        return CloudError(.auth, message)
      }
      return CloudError(.server, message)
    default:
      return CloudError(.server, message)
    }
  }

  /// The code in "almail:<code>", when it is one the app knows.
  static func tag(in message: String) -> CloudErrorCode? {
    guard let range = message.range(of: "almail:") else { return nil }
    let rest = message[range.upperBound...]
    let word = rest.prefix { ($0 >= "a" && $0 <= "z") || $0 == "_" }
    return CloudErrorCode(rawValue: String(word))
  }
}

// MARK: Wire

/// A record or a deletion marker, as pull_records gives them.
public struct PulledRow: Sendable, Equatable {
  public var tbl: String
  public var id: String
  /// Nil for a deleted record.
  public var data: JSONValue?
  public var rev: Int64
  public var deleted: Bool

  public init(tbl: String, id: String, data: JSONValue?, rev: Int64, deleted: Bool) {
    self.tbl = tbl
    self.id = id
    self.data = data
    self.rev = rev
    self.deleted = deleted
  }
}

/// One change sent with push_records: a whole record, or a delete.
public struct PushChange: Sendable, Equatable {
  public var tbl: String
  public var id: String
  /// Nil for a delete.
  public var data: JSONValue?
  /// The server version this device last had, if any.
  public var baseRev: Int64?

  public init(tbl: String, id: String, data: JSONValue?, baseRev: Int64?) {
    self.tbl = tbl
    self.id = id
    self.data = data
    self.baseRev = baseRev
  }

  public var deleted: Bool { data == nil }

  /// `{tbl, id, data, base_rev}` or `{tbl, id, deleted: true, base_rev}`, as the web sends them.
  public var json: JSONValue {
    var fields: [String: JSONValue] = [
      "tbl": .string(tbl), "id": .string(id), "base_rev": baseRev.map { .number(Double($0)) } ?? .null,
    ]
    if let data { fields["data"] = data } else { fields["deleted"] = .bool(true) }
    return .object(fields)
  }
}

public struct PushResult: Sendable, Equatable {
  public var tbl: String
  public var id: String
  /// The new server version; nil for deleting something that was never stored.
  public var rev: Int64?
  /// The server had a newer version (or a newer delete) that this one replaced.
  public var conflict: Bool

  public init(tbl: String, id: String, rev: Int64?, conflict: Bool) {
    self.tbl = tbl
    self.id = id
    self.rev = rev
    self.conflict = conflict
  }
}

public struct RecordKey: Sendable, Hashable, Codable {
  public var tbl: String
  public var id: String

  public init(tbl: String, id: String) {
    self.tbl = tbl
    self.id = id
  }
}

public struct SyncInfo: Sendable, Equatable {
  public var purgedUntilRev: Int64
  public var recordCount: Int
  public var maxRev: Int64

  public init(purgedUntilRev: Int64, recordCount: Int, maxRev: Int64) {
    self.purgedUntilRev = purgedUntilRev
    self.recordCount = recordCount
    self.maxRev = maxRev
  }
}

/// A company the signed-in person is a member of (my_companies).
public struct CloudCompany: Sendable, Equatable {
  public var id: String
  public var name: String
  public var role: MemberRole
  public var createdAt: String
  public var members: Int

  public init(id: String, name: String, role: MemberRole, createdAt: String = "", members: Int = 1) {
    self.id = id
    self.name = name
    self.role = role
    self.createdAt = createdAt
    self.members = members
  }
}

/// The signed-in person's own limits in a company (my_permissions).
public struct MyPermissions: Sendable, Equatable {
  /// The owner's limits per app, only the apps and levels this version knows (`readPermissions`).
  public var apps: [String: String]
  public var approver: Bool
  public var owner: Bool
  public var seniorRolesOwnerOnly: Bool

  public init(apps: [String: String] = [:], approver: Bool = false, owner: Bool = false, seniorRolesOwnerOnly: Bool = false) {
    self.apps = apps
    self.approver = approver
    self.owner = owner
    self.seniorRolesOwnerOnly = seniorRolesOwnerOnly
  }

  static let limitApps = ["books", "people", "crm", "compliance"]
  static let accessLevels: Set<String> = ["none", "view", "edit", "manage"]

  /// Limits as the server sent them, keeping only apps and levels this
  /// version knows (a newer server may know more): what isn't understood limits nothing.
  static func readApps(_ value: JSONValue?) -> [String: String] {
    guard case .some(.object(let apps)) = value?["apps"] else { return [:] }
    var known: [String: String] = [:]
    for app in limitApps {
      if case .some(.string(let limit)) = apps[app], accessLevels.contains(limit) { known[app] = limit }
    }
    return known
  }
}

public struct CompanyPatchResult: Sendable, Equatable {
  public var rev: Int64
  /// Fields that had also changed in the cloud; this device's value was kept.
  public var conflicts: [[String]]

  public init(rev: Int64, conflicts: [[String]]) {
    self.rev = rev
    self.conflicts = conflicts
  }
}

// MARK: Local bookkeeping

/// A company kept in the cloud, as known on this device (the web's `CloudLink`).
public struct SyncState: Sendable, Equatable {
  public enum Status: String, Sendable, Codable {
    /// Being copied to the cloud (the outbox holds every record).
    case uploading
    /// Being copied to this device (the company record comes last).
    case downloading
    case ready
    /// No longer in the cloud, or no longer a member.
    case removed
  }

  public var companyId: String
  /// The account the company was linked with; another account's companies don't sync.
  public var userId: String
  public var role: MemberRole
  public var status: Status
  /// The highest server rev applied here.
  public var cursor: Int64
  /// The name in the cloud, shown before the company itself has arrived.
  public var name: String
  public var linkedAt: Date
  public var lastSyncAt: Date?
  public var lastError: CloudErrorCode?
  public var lastErrorAt: Date?
  /// Records to copy, for the progress bar.
  public var total: Int?
  /// "deleted" by its owner, or "access" withdrawn.
  public var removedReason: String?
  /// Bumped when the cursor goes back to 0 (a role that sees more): a page
  /// asked for before that is thrown away and asked for again.
  public var epoch: Int
  /// Documents that arrived with a number another document here already has.
  public var duplicates: [String]
  /// The tables this device pulls the company with (see catchUpTables).
  public var tables: [String]?
  /// What the server has beyond the first migrations, as last asked (server_features).
  public var features: [String]?
  public var featuresAt: Date?
  /// The owner's limits on this person, app by app (my_permissions). Nil: the role's access.
  public var permissions: [String: String]?
  /// The owner allowed this person to approve requests.
  public var approver: Bool?
  public var seniorRolesOwnerOnly: Bool?
  public var permissionsAt: Date?

  public init(
    companyId: String, userId: String, role: MemberRole, status: Status, name: String,
    linkedAt: Date = Date(), total: Int? = nil
  ) {
    self.companyId = companyId
    self.userId = userId
    self.role = role
    self.status = status
    self.cursor = 0
    self.name = name
    self.linkedAt = linkedAt
    self.total = total
    self.epoch = 0
    self.duplicates = []
    // Pulled from the start with every table this version has.
    self.tables = SyncTables.all
  }

  /// Whether the company's server has said it has a feature (`linkHasFeature`).
  public func has(_ feature: String) -> Bool { features?.contains(feature) ?? false }
}

/// A change made here that the server has not confirmed yet.
public struct OutboxEntry: Sendable, Equatable {
  public enum Op: String, Sendable, Codable {
    case put, delete
  }

  public var seq: Int64
  public var table: String
  public var id: String
  public var op: Op
  public var at: Date
  /// The server refused the change; it waits for a retry or an undo.
  public var parked: Bool
  /// The local transaction that made the change: sent, refused and undone together.
  public var group: String?
  /// The error code of a parked change.
  public var error: String?
  /// The server's own explanation.
  public var detail: String?
  /// It was the file of an attachment the cloud refused, not the record.
  public var file: Bool
  /// A refused file sent again by itself: refusals so far, and when next.
  public var attempts: Int?
  public var retryAt: Date?

  public init(
    seq: Int64, table: String, id: String, op: Op, at: Date, parked: Bool = false, group: String? = nil
  ) {
    self.seq = seq
    self.table = table
    self.id = id
    self.op = op
    self.at = at
    self.parked = parked
    self.group = group
    self.file = false
  }

  var key: RecordKey { RecordKey(tbl: table, id: id) }
}

/// A file to remove from Storage, kept until it is gone.
public struct FileTask: Sendable, Equatable {
  public var seq: Int64
  public var path: String
  public var at: Date
  public var attempts: Int
  public var lastError: String?
  /// The account that removed the file's record; only that account removes the file.
  public var userId: String?
  /// Retrying stopped: shown as a problem until tried again.
  public var failed: Bool

  public init(seq: Int64, path: String, at: Date, attempts: Int, lastError: String? = nil, userId: String? = nil) {
    self.seq = seq
    self.path = path
    self.at = at
    self.attempts = attempts
    self.lastError = lastError
    self.userId = userId
    self.failed = false
  }
}

/// The server version of a record this device has.
public struct SyncRev: Sendable, Equatable {
  public var rev: Int64
  /// The company record only: the copy that rev stands for, so this device
  /// knows which of its fields it changed since (see CompanyPatch).
  public var base: JSONValue?

  public init(rev: Int64, base: JSONValue? = nil) {
    self.rev = rev
    self.base = base
  }
}

// MARK: Persisted form

extension SyncState {
  var json: JSONValue {
    var fields: [String: JSONValue] = [
      "companyId": .string(companyId), "userId": .string(userId), "role": .string(role.rawValue),
      "status": .string(status.rawValue), "cursor": .number(Double(cursor)), "name": .string(name),
      "linkedAt": .date(linkedAt), "epoch": .number(Double(epoch)),
      "duplicates": .array(duplicates.map { .string($0) }),
    ]
    fields["lastSyncAt"] = lastSyncAt.map { .date($0) }
    fields["lastError"] = lastError.map { .string($0.rawValue) }
    fields["lastErrorAt"] = lastErrorAt.map { .date($0) }
    fields["total"] = total.map { .number(Double($0)) }
    fields["removedReason"] = removedReason.map { .string($0) }
    fields["tables"] = tables.map { .array($0.map { .string($0) }) }
    fields["features"] = features.map { .array($0.map { .string($0) }) }
    fields["featuresAt"] = featuresAt.map { .date($0) }
    fields["permissions"] = permissions.map { .object($0.mapValues { .string($0) }) }
    fields["approver"] = approver.map { .bool($0) }
    fields["seniorRolesOwnerOnly"] = seniorRolesOwnerOnly.map { .bool($0) }
    fields["permissionsAt"] = permissionsAt.map { .date($0) }
    return .object(fields)
  }

  init?(json: JSONValue) {
    guard let companyId = json["companyId"]?.string, let userId = json["userId"]?.string,
      let role = json["role"]?.string, let status = json["status"]?.string.flatMap(Status.init(rawValue:))
    else { return nil }
    self.init(
      companyId: companyId, userId: userId, role: (MemberRole(rawValue: role) ?? .viewer), status: status,
      name: json["name"]?.string ?? "", linkedAt: json["linkedAt"]?.dateValue ?? Date(timeIntervalSince1970: 0))
    cursor = json["cursor"]?.int64Value ?? 0
    lastSyncAt = json["lastSyncAt"]?.dateValue
    lastError = json["lastError"]?.string.flatMap(CloudErrorCode.init(rawValue:))
    lastErrorAt = json["lastErrorAt"]?.dateValue
    total = json["total"]?.int
    removedReason = json["removedReason"]?.string
    epoch = json["epoch"]?.int ?? 0
    duplicates = json["duplicates"]?.array?.compactMap(\.string) ?? []
    tables = json["tables"]?.array?.compactMap(\.string)
    features = json["features"]?.array?.compactMap(\.string)
    featuresAt = json["featuresAt"]?.dateValue
    permissions = json["permissions"]?.object?.compactMapValues(\.string)
    approver = json["approver"]?.bool
    seniorRolesOwnerOnly = json["seniorRolesOwnerOnly"]?.bool
    permissionsAt = json["permissionsAt"]?.dateValue
  }
}

extension OutboxEntry {
  var json: JSONValue {
    var fields: [String: JSONValue] = [
      "seq": .number(Double(seq)), "table": .string(table), "id": .string(id), "op": .string(op.rawValue),
      "at": .date(at), "parked": .bool(parked), "file": .bool(file),
    ]
    fields["group"] = group.map { .string($0) }
    fields["error"] = error.map { .string($0) }
    fields["detail"] = detail.map { .string($0) }
    fields["attempts"] = attempts.map { .number(Double($0)) }
    fields["retryAt"] = retryAt.map { .date($0) }
    return .object(fields)
  }

  init?(json: JSONValue) {
    guard let seq = json["seq"]?.int64Value, let table = json["table"]?.string, let id = json["id"]?.string,
      let op = json["op"]?.string.flatMap(Op.init(rawValue:))
    else { return nil }
    self.init(
      seq: seq, table: table, id: id, op: op, at: json["at"]?.dateValue ?? Date(timeIntervalSince1970: 0),
      parked: json["parked"]?.bool ?? false, group: json["group"]?.string)
    error = json["error"]?.string
    detail = json["detail"]?.string
    file = json["file"]?.bool ?? false
    attempts = json["attempts"]?.int
    retryAt = json["retryAt"]?.dateValue
  }
}

extension FileTask {
  var json: JSONValue {
    var fields: [String: JSONValue] = [
      "seq": .number(Double(seq)), "path": .string(path), "at": .date(at),
      "attempts": .number(Double(attempts)), "failed": .bool(failed),
    ]
    fields["lastError"] = lastError.map { .string($0) }
    fields["userId"] = userId.map { .string($0) }
    return .object(fields)
  }

  init?(json: JSONValue) {
    guard let seq = json["seq"]?.int64Value, let path = json["path"]?.string else { return nil }
    self.init(
      seq: seq, path: path, at: json["at"]?.dateValue ?? Date(timeIntervalSince1970: 0),
      attempts: json["attempts"]?.int ?? 0, lastError: json["lastError"]?.string, userId: json["userId"]?.string)
    failed = json["failed"]?.bool ?? false
  }
}

extension JSONValue {
  /// A time as the mirror keeps its own times: seconds since 2001 (Date's
  /// own number, so it reads back exactly).
  static func date(_ date: Date) -> JSONValue { .number(date.timeIntervalSinceReferenceDate) }

  var dateValue: Date? { double.map { Date(timeIntervalSinceReferenceDate: $0) } }

  var int64Value: Int64? {
    guard case .number(let value) = self, value.rounded() == value, abs(value) < 9.2e18 else { return nil }
    return Int64(value)
  }
}
