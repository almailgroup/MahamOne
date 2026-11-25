import Foundation
import Synchronization

/// One record as the cloud has it now (and this person may see it).
public struct CloudRecord: Sendable, Equatable {
  public var data: JSONValue
  public var rev: Int64

  public init(data: JSONValue, rev: Int64) {
    self.data = data
    self.rev = rev
  }
}

/// What the sync engine asks of the cloud (the web's `CloudApi`, the part
/// the sync uses). In the app it is Supabase (`SupabaseCloudAPI`); in tests
/// an in-memory server with the same rules. Every error thrown is a
/// `CloudError`.
public protocol CloudAPI: Sendable {
  func myCompanies() async throws -> [CloudCompany]
  /// push_records: at most 500 changes; the push always wins.
  func pushRecords(company: String, changes: [PushChange]) async throws -> [PushResult]
  /// pull_records: records and deletion markers with rev > since, in rev order.
  func pullRecords(company: String, since: Int64, limit: Int) async throws -> [PulledRow]
  /// company_record_ids: ids of every record the caller may read, after `after`, in (tbl, id) order.
  func recordIds(company: String, after: RecordKey?, limit: Int, table: String?) async throws -> [RecordKey]
  /// company_sync_info.
  func syncInfo(company: String) async throws -> SyncInfo
  func getRecord(company: String, table: String, id: String) async throws -> CloudRecord?
  /// The records (not deletion markers) with rev > since, in rev order, as
  /// the caller may read them: a plain select of `public.records` under the
  /// same row-level security as pull_records. Used only where pull_records
  /// refuses a pull from the start (see SyncEngine.catchUpByRecords).
  func recordsAfter(company: String, since: Int64, limit: Int) async throws -> [PulledRow]
  /// patch_company: nil when the server can't (an older version) or the record isn't there yet.
  func patchCompany(company: String, ops: [CompanyOp]) async throws -> CompanyPatchResult?
  /// reserve_number: nil when the server can't, or numbers this one on the device.
  func reserveNumber(company: String, kind: String, date: String, min: Int64) async throws -> ReservedCounter?
  /// server_features: empty on a server without it.
  func serverFeatures(company: String) async throws -> [String]
  /// my_permissions: nil when the server doesn't have it yet.
  func myPermissions(company: String) async throws -> MyPermissions?
}

/// The cloud as Supabase: the database's functions, called as the signed-in
/// person over PostgREST (src/cloud/supabase-api.ts).
public final class SupabaseCloudAPI: CloudAPI {
  private let db: DatabaseClient
  private let timeout: TimeInterval
  /// Functions this server doesn't have, until when (asked again after ten minutes).
  private let missingUntil = Mutex<[String: Date]>([:])
  private static let recheck: TimeInterval = 10 * 60

  /// `timeout`: how long one request may go unanswered (the web gives up after two minutes).
  public init(db: DatabaseClient, timeout: TimeInterval = 120) {
    self.db = db
    self.timeout = timeout
  }

  private func call(_ name: String, _ params: [String: JSONValue]) async throws -> JSONValue {
    let data: Data
    do {
      data = try await db.rpcData(name, schema: .maham, body: SyncJSON.data(.object(params)), timeout: timeout)
    } catch {
      throw CloudError.from(error)
    }
    if data.isEmpty { return .null }
    do {
      return try SyncJSON.parse(data)
    } catch {
      throw CloudError(.server, "The cloud answered \(name) in a form the app didn't expect.")
    }
  }

  /// A function added by a later migration: nil when the server doesn't have
  /// it yet (PostgREST answers PGRST202 or 404) or answers with nothing.
  private func optionalCall(_ name: String, _ params: [String: JSONValue]) async throws -> JSONValue? {
    if let until = missingUntil.withLock({ $0[name] }), until > Date() { return nil }
    let data: Data
    do {
      data = try await db.rpcData(name, schema: .maham, body: SyncJSON.data(.object(params)), timeout: timeout)
    } catch let error as MahamError {
      if case .server(let status, let code, _) = error, status == 404 || code == "PGRST202" {
        missingUntil.withLock { $0[name] = Date().addingTimeInterval(Self.recheck) }
        return nil
      }
      throw CloudError.from(error)
    } catch {
      throw CloudError.from(error)
    }
    if data.isEmpty { return nil }
    let value: JSONValue
    do {
      value = try SyncJSON.parse(data)
    } catch {
      throw CloudError(.server, "The cloud answered \(name) in a form the app didn't expect.")
    }
    return value.nonNull
  }

  private static func rows(_ value: JSONValue) -> [JSONValue] { value.array ?? [] }

  /// A bigint as PostgREST writes it (a number, or a string for very large ones).
  static func int64(_ value: JSONValue?) -> Int64? {
    switch value {
    case .some(.number): return value?.int64Value
    case .some(.string(let text)): return Int64(text)
    default: return nil
    }
  }

  static func text(_ value: JSONValue?) -> String {
    switch value {
    case .none, .some(.null): return ""
    case .some(.string(let text)): return text
    case .some(let other): return SyncJSON.string(other)
    }
  }

  public func myCompanies() async throws -> [CloudCompany] {
    try Self.rows(await call("my_companies", [:])).compactMap { row in
      guard let id = row["id"]?.string else { return nil }
      return CloudCompany(
        id: id, name: Self.text(row["name"]), role: (MemberRole(rawValue: Self.text(row["role"])) ?? .viewer),
        createdAt: Self.text(row["created_at"]), members: Int(Self.int64(row["members"]) ?? 0))
    }
  }

  public func pushRecords(company: String, changes: [PushChange]) async throws -> [PushResult] {
    let answer = try await call(
      "push_records", ["p_company": .string(company), "p_changes": .array(changes.map(\.json))])
    return Self.rows(answer).map { row in
      PushResult(
        tbl: Self.text(row["tbl"]), id: Self.text(row["id"]), rev: Self.int64(row["rev"]),
        conflict: row["conflict"] == .bool(true))
    }
  }

  public func pullRecords(company: String, since: Int64, limit: Int) async throws -> [PulledRow] {
    let answer = try await call(
      "pull_records",
      ["p_company": .string(company), "p_since": .number(Double(since)), "p_limit": .number(Double(limit))])
    return try Self.rows(answer).map { row in
      guard let rev = Self.int64(row["rev"]) else {
        throw CloudError(.server, "A pulled row has no rev.")
      }
      let deleted = row["deleted"] == .bool(true)
      let data = row["data"]?.nonNull
      return PulledRow(tbl: Self.text(row["tbl"]), id: Self.text(row["id"]), data: deleted ? nil : data, rev: rev, deleted: deleted)
    }
  }

  public func recordIds(company: String, after: RecordKey?, limit: Int, table: String?) async throws -> [RecordKey] {
    let answer = try await call(
      "company_record_ids",
      [
        "p_company": .string(company), "p_tbl": table.map { .string($0) } ?? .null,
        "p_after_tbl": .string(after?.tbl ?? ""), "p_after_id": .string(after?.id ?? ""),
        "p_limit": .number(Double(limit)),
      ])
    return Self.rows(answer).map { RecordKey(tbl: Self.text($0["tbl"]), id: Self.text($0["id"])) }
  }

  public func syncInfo(company: String) async throws -> SyncInfo {
    let row = Self.rows(try await call("company_sync_info", ["p_company": .string(company)])).first
    return SyncInfo(
      purgedUntilRev: Self.int64(row?["purged_until_rev"]) ?? 0,
      recordCount: Int(Self.int64(row?["record_count"]) ?? 0),
      maxRev: Self.int64(row?["max_rev"]) ?? 0)
  }

  private struct RecordRow: Decodable {
    var data: JSONValue
    var rev: Int64
  }

  public func getRecord(company: String, table: String, id: String) async throws -> CloudRecord? {
    let rows: [RecordRow]
    do {
      rows = try await db.select(
        "records", schema: .maham,
        [.select("data,rev"), .eq("company_id", company), .eq("tbl", table), .eq("id", id), .limit(1)])
    } catch {
      throw CloudError.from(error)
    }
    return rows.first.map { CloudRecord(data: $0.data, rev: $0.rev) }
  }

  private struct PagedRow: Decodable {
    var tbl: String
    var id: String
    var data: JSONValue
    var rev: Int64
  }

  public func recordsAfter(company: String, since: Int64, limit: Int) async throws -> [PulledRow] {
    let rows: [PagedRow]
    do {
      rows = try await db.select(
        "records", schema: .maham,
        [
          .select("tbl,id,data,rev"), .eq("company_id", company), Query("rev", "gt.\(since)"),
          .order("rev"), .limit(limit),
        ])
    } catch {
      throw CloudError.from(error)
    }
    return rows.map { PulledRow(tbl: $0.tbl, id: $0.id, data: $0.data, rev: $0.rev, deleted: false) }
  }

  public func patchCompany(company: String, ops: [CompanyOp]) async throws -> CompanyPatchResult? {
    guard
      let answer = try await optionalCall(
        "patch_company", ["p_company": .string(company), "p_ops": .array(ops.map(\.json))]),
      let row = Self.rows(answer).first, let rev = Self.int64(row["rev"])
    else { return nil }
    let conflicts = (row["conflicts"]?.array ?? []).map { path in (path.array ?? []).map { Self.text($0) } }
    return CompanyPatchResult(rev: rev, conflicts: conflicts)
  }

  public func reserveNumber(company: String, kind: String, date: String, min: Int64) async throws -> ReservedCounter? {
    guard
      let answer = try await optionalCall(
        "reserve_number",
        ["p_company": .string(company), "p_kind": .string(kind), "p_date": .string(date), "p_min": .number(Double(min))]),
      let row = Self.rows(answer).first, let counter = Self.int64(row["counter"])
    else { return nil }
    return ReservedCounter(counter: Int(counter), period: Self.text(row["period"]))
  }

  public func serverFeatures(company: String) async throws -> [String] {
    guard let answer = try await optionalCall("server_features", [:]), case .array(let items) = answer else {
      return []
    }
    return items.compactMap(\.string)
  }

  public func myPermissions(company: String) async throws -> MyPermissions? {
    guard let answer = try await optionalCall("my_permissions", ["p_company": .string(company)]) else {
      return nil
    }
    let row = Self.rows(answer).first
    return MyPermissions(
      apps: MyPermissions.readApps(row?["permissions"]), approver: row?["can_approve"] == .bool(true),
      owner: row?["is_owner"] == .bool(true), seniorRolesOwnerOnly: row?["senior_roles_owner_only"] == .bool(true))
  }
}
