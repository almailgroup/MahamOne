import Foundation
import Testing

@testable import MahamKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite("Sync: the Supabase wire")
struct SyncSupabaseTests {
  func api(_ fake: FakeTransport) -> SupabaseCloudAPI {
    let auth = AuthService(config: testConfig, transport: fake, store: MemorySessionStore(signedInSession()))
    return SupabaseCloudAPI(db: DatabaseClient(auth: auth, transport: fake))
  }

  func body(_ request: URLRequest) throws -> JSONValue { try SyncJSON.parse(request.bodyText) }

  @Test("pulls with pull_records and reads its rows, deletion markers included")
  func pull() async throws {
    let fake = FakeTransport { _ in
      .init(
        status: 200,
        body: #"[{"tbl":"clients","id":"c1","data":{"id":"c1","companyId":"co-1","n":1.5},"rev":12,"deleted":false},{"tbl":"documents","id":"d1","data":null,"rev":"13","deleted":true}]"#
      )
    }
    let rows = try await api(fake).pullRecords(company: "co-1", since: 7, limit: 500)
    #expect(rows == [
      PulledRow(tbl: "clients", id: "c1", data: ["id": "c1", "companyId": "co-1", "n": 1.5], rev: 12, deleted: false),
      PulledRow(tbl: "documents", id: "d1", data: nil, rev: 13, deleted: true),
    ])
    let request = try #require(fake.sent.first)
    #expect(request.path == "/rest/v1/rpc/pull_records")
    #expect(request.httpMethod == "POST")
    #expect(try body(request) == ["p_company": "co-1", "p_since": 7, "p_limit": 500])
    #expect(request.timeoutInterval == 120)
  }

  @Test("pushes whole records and deletes with their base rev, as the web does")
  func push() async throws {
    let fake = FakeTransport { _ in
      .init(status: 200, body: #"[{"tbl":"clients","id":"c1","rev":20,"conflict":true},{"tbl":"clients","id":"c2","rev":null,"conflict":false}]"#)
    }
    let results = try await api(fake).pushRecords(
      company: "co-1",
      changes: [
        PushChange(tbl: "clients", id: "c1", data: ["id": "c1", "companyId": "co-1"], baseRev: 4),
        PushChange(tbl: "clients", id: "c2", data: nil, baseRev: nil),
      ])
    #expect(results == [
      PushResult(tbl: "clients", id: "c1", rev: 20, conflict: true),
      PushResult(tbl: "clients", id: "c2", rev: nil, conflict: false),
    ])
    #expect(try body(#require(fake.sent.first)) == [
      "p_company": "co-1",
      "p_changes": [
        ["tbl": "clients", "id": "c1", "data": ["id": "c1", "companyId": "co-1"], "base_rev": 4],
        ["tbl": "clients", "id": "c2", "deleted": true, "base_rev": nil],
      ],
    ])
  }

  @Test("reads the database's own error codes")
  func errors() async throws {
    let replies: [(Int, String, CloudErrorCode)] = [
      (400, #"{"code":"P0001","message":"almail:resync This device has been away too long; a full sync is needed."}"#, .resync),
      (403, #"{"code":"42501","message":"almail:not_member You are not a member of this company."}"#, .notMember),
      (403, #"{"code":"42501","message":"new row violates row-level security policy"}"#, .permission),
      (400, #"{"code":"22023","message":"almail:invalid Send at most 500 changes at once."}"#, .invalid),
      (400, #"{"code":"23514","message":"check constraint"}"#, .invalid),
      (400, #"{"code":"P0001","message":"almail:approval_required This change needs approval."}"#, .approvalRequired),
      (503, #"{"message":"Service unavailable"}"#, .server),
    ]
    for (status, text, code) in replies {
      let fake = FakeTransport { _ in .init(status: status, body: text) }
      await #expect(throws: CloudError.self) { _ = try await api(fake).pullRecords(company: "co-1", since: 1, limit: 500) }
      do {
        _ = try await api(fake).pullRecords(company: "co-1", since: 1, limit: 500)
      } catch let error as CloudError {
        #expect(error.code == code, "\(text)")
      }
    }
    #expect(CloudError.from(MahamError.offline).code == .offline)
    #expect(CloudError.from(MahamError.offline).retryable)
    #expect(CloudError.from(MahamError.sessionExpired).code == .auth)
    #expect(!CloudError(.permission).retryable)
  }

  @Test("a function the server doesn't have yet is nil, and isn't asked again for ten minutes")
  func missingFunction() async throws {
    let fake = FakeTransport { request in
      request.path.hasSuffix("patch_company")
        ? .init(status: 404, body: #"{"code":"PGRST202","message":"Could not find the function public.patch_company"}"#)
        : .init(status: 200, body: "[]")
    }
    let cloud = api(fake)
    #expect(try await cloud.patchCompany(company: "co-1", ops: [CompanyOp(path: ["phone"], value: "1", base: "")]) == nil)
    #expect(try await cloud.patchCompany(company: "co-1", ops: []) == nil)
    #expect(fake.sent.filter { $0.path.hasSuffix("patch_company") }.count == 1)
    #expect(try body(#require(fake.sent.first)) == [
      "p_company": "co-1", "p_ops": [["path": ["phone"], "value": "1", "base": ""]],
    ])
  }

  @Test("reads features, the owner's limits (only what it knows), counters and the company's sync info")
  func smallAnswers() async throws {
    let fake = FakeTransport { request in
      switch request.path {
      case "/rest/v1/rpc/server_features": .init(status: 200, body: #"["tables_v16","super_admin"]"#)
      case "/rest/v1/rpc/my_permissions":
        .init(status: 200, body: #"[{"permissions":{"apps":{"books":"view","people":"weird","zzz":"none"}},"can_approve":true,"is_owner":false,"senior_roles_owner_only":null}]"#)
      case "/rest/v1/rpc/reserve_number": .init(status: 200, body: #"[{"counter":42,"period":"2026"}]"#)
      case "/rest/v1/rpc/company_sync_info": .init(status: 200, body: #"[{"purged_until_rev":"77","record_count":12,"max_rev":90}]"#)
      case "/rest/v1/rpc/my_companies":
        .init(status: 200, body: #"[{"id":"co-1","name":"Al Mail","role":"superuser","created_at":"2026-10-04T00:00:00Z","members":3}]"#)
      case "/rest/v1/records":
        .init(status: 200, body: #"[{"data":{"id":"c1","companyId":"co-1"},"rev":5}]"#)
      default: .init(status: 404, body: "{}")
      }
    }
    let cloud = api(fake)
    #expect(try await cloud.serverFeatures(company: "co-1") == ["tables_v16", "super_admin"])
    #expect(try await cloud.myPermissions(company: "co-1") == MyPermissions(apps: ["books": "view"], approver: true))
    #expect(try await cloud.reserveNumber(company: "co-1", kind: "invoice", date: "2026-11-25", min: 4) == ReservedCounter(counter: 42, period: "2026"))
    #expect(try await cloud.syncInfo(company: "co-1") == SyncInfo(purgedUntilRev: 77, recordCount: 12, maxRev: 90))
    // A role a newer server knows and this version doesn't: the least.
    #expect(try await cloud.myCompanies().first?.role == .viewer)
    #expect(try await cloud.getRecord(company: "co-1", table: "clients", id: "c1") == CloudRecord(data: ["id": "c1", "companyId": "co-1"], rev: 5))
    let select = try #require(fake.sent.last)
    #expect(select.httpMethod == "GET")
    #expect(select.query.contains("tbl=eq.clients"))
    #expect(select.query.contains("company_id=eq.co-1"))
    let reserve = try #require(fake.sent.first { $0.path.hasSuffix("reserve_number") })
    #expect(try body(reserve) == ["p_company": "co-1", "p_kind": "invoice", "p_date": "2026-11-25", "p_min": 4])
  }
}
