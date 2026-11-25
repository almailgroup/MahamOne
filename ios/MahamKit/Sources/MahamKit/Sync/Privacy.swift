import Foundation

/// Payroll and people data: who may hold it, and the record as this device
/// stores it or the cloud keeps it. Ported from `isPrivateRecord` and
/// `renewedDocumentId` in src/cloud/roles.ts, and `localCopy`, `cloudCopy`,
/// `pageOwners` and `privateOwnerIds` in src/cloud/sync.ts. The server's own
/// rule is `almailbooks.record_is_private`.
public enum Privacy {
  /// Payroll and people data: only owners, admins and accountants see them (PEOPLE_TABLES).
  public static let peopleTables: Set<String> = [
    "employees", "payRuns", "payrollSettings", "peopleSettings", "leaveRecords", "staffLoans",
    "finalSettlements", "letterTemplates", "employeeLetters", "staffingCostings",
  ]

  /// Finds another record of the same company (an attachment's owner); nil when there is none.
  public typealias Lookup = (_ table: String, _ id: String) -> JSONValue?

  /// The register document a renewal is of, or nil for one of an employee's own papers.
  public static func renewedDocumentId(_ renewal: JSONValue?) -> String? {
    if let id = SyncJSON.nonEmptyString(renewal?["documentId"]) { return id }
    guard case .some(.string(let key)) = renewal?["documentKey"] else { return nil }
    // As key.startsWith('doc:') && key.length > 4 ? key.slice(4) : null.
    let prefix = Array("doc:".unicodeScalars)
    let scalars = Array(key.unicodeScalars)
    guard scalars.count > prefix.count, Array(scalars[0..<prefix.count]) == prefix,
      key.utf16.count > 4
    else { return nil }
    var rest = String.UnicodeScalarView()
    rest.append(contentsOf: scalars[prefix.count...])
    return String(rest)
  }

  /// Whether a record is payroll or people data. `lookup` finds the record
  /// an attachment, an activity or a renewal is about; without it only the
  /// record itself is judged.
  public static func isPrivateRecord(_ table: String, _ record: JSONValue?, lookup: Lookup? = nil) -> Bool {
    if peopleTables.contains(table) { return true }
    guard let record, case .object = record else { return false }
    if record["_private"] == .bool(true) { return true }
    func employeeOwned(_ row: JSONValue?) -> Bool { SyncJSON.nonEmptyString(row?["employeeId"]) != nil }
    // An employee's paper in the register, or one marked confidential.
    func privateDocument(_ row: JSONValue?) -> Bool {
      employeeOwned(row) || row?["confidential"] == .bool(true)
    }
    // A renewal of either (the document is found with `lookup`).
    func privateRenewal(_ row: JSONValue?) -> Bool {
      if employeeOwned(row) { return true }
      guard let documentId = renewedDocumentId(row), let lookup else { return false }
      return privateDocument(lookup("complianceDocuments", documentId))
    }
    switch table {
    case "complianceDocuments":
      return privateDocument(record)
    case "renewals":
      return privateRenewal(record)
    case "journals":
      return record["kind"] == .string("payroll")
    case "approvals":
      // A request about payroll or people data (a pay run…).
      guard case .some(.string(let subject)) = record["subjectTbl"] else { return false }
      return peopleTables.contains(subject)
    case "activities":
      if record["entity"] == .string("employee") || record["entity"] == .string("payroll") { return true }
      // About a manpower costing (#3), even once it is deleted.
      if record["entity"] == .string("costing") { return true }
      // Logged about an employee's documents, or a confidential one: private
      // even once they are deleted.
      if employeeOwned(record) || record["confidential"] == .bool(true) { return true }
      guard record["entity"] == .string("compliance"), let lookup,
        case .some(.string(let entityId)) = record["entityId"]
      else { return false }
      return privateDocument(lookup("complianceDocuments", entityId))
        || privateRenewal(lookup("renewals", entityId))
    case "attachments":
      guard let lookup, case .some(.string(let owner)) = record["ownerId"] else { return false }
      return lookup("employees", owner) != nil
        || lookup("letterTemplates", owner) != nil
        || lookup("employeeLetters", owner) != nil
        || privateDocument(lookup("complianceDocuments", owner))
        || privateRenewal(lookup("renewals", owner))
    default:
      return false
    }
  }

  /// A lookup over a set of owner ids: any owner in the set makes the
  /// record private, whatever kind it is (as the web's sync builds it).
  static func ownersLookup(_ owners: Set<String>) -> Lookup {
    { _, id in owners.contains(id) ? JSONValue.object(["employeeId": .string(id)]) : JSONValue?.none }
  }

  /// Ids of employees, letters, private register documents and their
  /// renewals in a page of changes (`pageOwners`).
  static func pageOwners(_ rows: [PulledRow]) -> Set<String> {
    var owners = Set<String>()
    for row in rows {
      guard !row.deleted, let data = row.data else { continue }
      if row.tbl == "employees" || row.tbl == "letterTemplates" || row.tbl == "employeeLetters"
        || (row.tbl == "complianceDocuments" && isPrivateRecord(row.tbl, data))
      {
        owners.insert(row.id)
      }
    }
    for row in rows {
      guard !row.deleted, let data = row.data, row.tbl == "renewals" else { continue }
      let documentId = renewedDocumentId(data)
      if isPrivateRecord(row.tbl, data) || (documentId.map { owners.contains($0) } ?? false) {
        owners.insert(row.id)
      }
    }
    return owners
  }

  /// Ids of employees, letters, private register documents (an employee's,
  /// or confidential) and their renewals: what makes a file private
  /// (`privateOwnerIds`).
  static func privateOwnerIds(_ tables: [String: [String: JSONValue]]) -> Set<String> {
    var owners = Set<String>()
    for name in ["employees", "letterTemplates", "employeeLetters"] {
      owners.formUnion((tables[name] ?? [:]).keys)
    }
    for (id, document) in tables["complianceDocuments"] ?? [:]
    where SyncJSON.truthy(document["employeeId"]) || document["confidential"] == .bool(true) {
      owners.insert(id)
    }
    for (id, renewal) in tables["renewals"] ?? [:] {
      let documentId = renewedDocumentId(renewal)
      if SyncJSON.truthy(renewal["employeeId"]) || (documentId.map { owners.contains($0) } ?? false) {
        owners.insert(id)
      }
    }
    return owners
  }

  /// A record from the cloud as this device stores it, or nil when it is
  /// not one of this company's records. `_private` is the cloud's mark and
  /// is not kept; attachments keep content already here (`localCopy`).
  public static func localCopy(companyId: String, row: PulledRow, local: JSONValue?) -> JSONValue? {
    guard let data = row.data, case .object(var copy) = data, data["id"] == .string(row.id) else {
      return nil
    }
    if row.tbl == "companies" ? row.id != companyId : data["companyId"] != .string(companyId) {
      return nil
    }
    copy["_private"] = nil
    if row.tbl == "attachments" {
      var same = false
      var kept: JSONValue?
      if let local, case .some(.string(let content)) = local["dataUrl"], !content.isEmpty {
        same = SyncJSON.strictEqual(local["contentHash"], copy["contentHash"])
          || !SyncJSON.truthy(copy["storagePath"])
        kept = .string(content)
      }
      if same, let kept {
        copy["dataUrl"] = kept
      } else if case .some(.string) = copy["dataUrl"] {
        // Kept as the cloud has it.
      } else {
        copy["dataUrl"] = .string("")
      }
      if copy["dataUrl"] == .string(""), SyncJSON.nonEmptyString(copy["storagePath"]) != nil {
        copy["contentMissing"] = 1
      } else {
        copy["contentMissing"] = nil
      }
    }
    return .object(copy)
  }

  /// The record as the cloud keeps it (`cloudCopy`): without this device's
  /// bookkeeping (`_private`, `contentMissing`), and with files and activity
  /// about employees and private documents marked `_private: true`.
  public static func cloudCopy(table: String, record: JSONValue, privateOwners: Set<String>) -> JSONValue {
    var data = record.removing("_private", "contentMissing")
    if table == "attachments" || table == "activities",
      isPrivateRecord(table, data, lookup: ownersLookup(privateOwners))
    {
      data.set("_private", .bool(true))
    }
    return data
  }
}
