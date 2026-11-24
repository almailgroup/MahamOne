import Foundation
import Testing

@testable import MahamKit

@Suite("Dates")
struct DateTests {
  @Test("reads Supabase's timestamps, microseconds and all")
  func timestamps() throws {
    let expected = try #require(MahamDates.parseTimestamp("2026-11-24T10:15:00.123Z"))
    #expect(MahamDates.parseTimestamp("2026-11-24T10:15:00.123456+00:00") == expected)
    #expect(MahamDates.parseTimestamp("2026-11-24T13:15:00.123+03:00") == expected)
    #expect(MahamDates.parseTimestamp("2026-11-24 10:15:00.123+00") == expected)
    #expect(MahamDates.parseTimestamp("2026-11-24T10:15:00Z") != nil)
    #expect(MahamDates.parseTimestamp("yesterday") == nil)
  }

  @Test("writes what it reads")
  func roundTrip() throws {
    let date = Date(timeIntervalSince1970: 1_795_000_000.25)
    #expect(MahamDates.parseTimestamp(MahamDates.timestamp(date)) == date)
  }

  @Test("calendar days")
  func localDates() throws {
    let day = try #require(LocalDate("2026-11-24"))
    #expect(day.description == "2026-11-24")
    #expect(day < LocalDate(year: 2026, month: 12, day: 1))
    #expect(day.days(to: LocalDate(year: 2026, month: 12, day: 1)) == 7)
    #expect(day.adding(days: 8) == LocalDate(year: 2026, month: 12, day: 2))
    #expect(LocalDate("2026-13-01") == nil)
    // 22:30 UTC is already the next day in Kuwait.
    let late = try #require(MahamDates.parseTimestamp("2026-11-24T22:30:00Z"))
    #expect(LocalDate(late, in: MahamDates.kuwait) == LocalDate(year: 2026, month: 11, day: 25))
  }
}

@Suite("Configuration")
struct ConfigTests {
  @Test("takes the publishable key and refuses a secret one")
  func keys() throws {
    let url = URL(string: "https://example.supabase.co")!
    #expect(throws: Never.self) { try MahamConfig(supabaseURL: url, publishableKey: "sb_publishable_x") }
    #expect(throws: MahamError.self) { try MahamConfig(supabaseURL: url, publishableKey: "sb_secret_x") }
    #expect(throws: MahamError.self) {
      try MahamConfig(supabaseURL: url, publishableKey: token(role: "service_role"))
    }
    #expect(throws: MahamError.self) { try MahamConfig(supabaseURL: url, publishableKey: " ") }
  }

  @Test("reads the app's settings")
  func info() throws {
    let config = try MahamConfig.fromInfoDictionary([
      "SupabaseURL": "https://example.supabase.co", "SupabasePublishableKey": "sb_publishable_x",
    ])
    #expect(config.supabaseURL.host == "example.supabase.co")
    #expect(throws: MahamError.self) {
      try MahamConfig.fromInfoDictionary(["SupabaseURL": "http://insecure", "SupabasePublishableKey": "k"])
    }
  }
}

@Suite("Signing in")
struct AuthTests {
  @Test("a password signs in, and the session is kept")
  func password() async throws {
    let fake = FakeTransport { _ in .init(status: 200, body: sessionJSON()) }
    let store = MemorySessionStore()
    let auth = AuthService(config: testConfig, transport: fake, store: store)

    let result = try await auth.signIn(email: " Noor@Example.com ", password: "secret")
    guard case .signedIn(let session) = result else {
      Issue.record("expected signed in, got \(result)")
      return
    }
    #expect(session.user.email == "noor@example.com")
    #expect(store.load() == session)
    let request = try #require(fake.sent.first)
    #expect(request.path == "/auth/v1/token")
    #expect(request.query == "grant_type=password")
    #expect(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_test")
    #expect(request.bodyText.contains(#""email":"noor@example.com""#))
  }

  @Test("an account with an authenticator app asks for the code next")
  func secondStep() async throws {
    let factors = #"[{"id":"factor-1","factor_type":"totp","status":"verified"}]"#
    let fake = FakeTransport { request in
      switch request.path {
      case "/auth/v1/token": .init(status: 200, body: sessionJSON(factors: factors))
      case "/auth/v1/factors/factor-1/challenge": .init(status: 200, body: #"{"id":"challenge-1"}"#)
      case "/auth/v1/factors/factor-1/verify":
        request.bodyText.contains(#""code":"123456""#)
          ? .init(status: 200, body: sessionJSON(aal: "aal2", factors: factors))
          : .init(status: 422, body: #"{"msg":"Invalid TOTP code entered"}"#)
      default: .init(status: 404, body: "{}")
      }
    }
    let auth = AuthService(config: testConfig, transport: fake, store: MemorySessionStore())

    guard case .needsSecondStep = try await auth.signIn(email: "noor@example.com", password: "x") else {
      Issue.record("expected the second step")
      return
    }
    await #expect(throws: MahamError.wrongCode) { try await auth.verifySecondStep(code: "000000") }
    let session = try await auth.verifySecondStep(code: "123 456")
    #expect(session.signedInWithSecondStep)
    #expect(fake.sent.last?.bodyText.contains(#""challenge_id":"challenge-1""#) == true)
  }

  @Test("a wrong password says so")
  func wrongPassword() async throws {
    let fake = FakeTransport { _ in
      .init(status: 400, body: #"{"error":"invalid_grant","error_description":"Invalid login credentials"}"#)
    }
    let auth = AuthService(config: testConfig, transport: fake, store: MemorySessionStore())
    await #expect(throws: MahamError.invalidCredentials) {
      try await auth.signIn(email: "noor@example.com", password: "wrong")
    }
  }

  @Test("an expiring session is refreshed once, however many ask at the same time")
  func refresh() async throws {
    let fake = FakeTransport { _ in .init(status: 200, body: sessionJSON(refresh: "refresh-2")) }
    let store = MemorySessionStore(signedInSession(expiresIn: 10))
    let auth = AuthService(config: testConfig, transport: fake, store: store)

    async let first = auth.validSession()
    async let second = auth.validSession()
    let (a, b) = try await (first, second)
    #expect(a.refreshToken == "refresh-2")
    #expect(b.refreshToken == "refresh-2")
    #expect(fake.sent.count == 1)
    #expect(fake.sent.first?.query == "grant_type=refresh_token")
  }

  @Test("a refresh the server refuses signs out")
  func revoked() async throws {
    let fake = FakeTransport { _ in .init(status: 400, body: #"{"msg":"Invalid Refresh Token"}"#) }
    let store = MemorySessionStore(signedInSession(expiresIn: 0))
    let auth = AuthService(config: testConfig, transport: fake, store: store)
    await #expect(throws: MahamError.sessionExpired) { try await auth.validSession() }
    #expect(store.load() == nil)
  }

  @Test("signing out forgets the session on this iPhone only")
  func signOut() async throws {
    let fake = FakeTransport { _ in .init(status: 204, body: "") }
    let store = MemorySessionStore(signedInSession())
    let auth = AuthService(config: testConfig, transport: fake, store: store)
    await auth.signOut()
    #expect(store.load() == nil)
    #expect(fake.sent.first?.url?.absoluteString.contains("logout?scope=local") == true)
  }
}

@Suite("Database client")
struct DatabaseTests {
  func client(_ fake: FakeTransport, session: AuthSession = signedInSession()) -> DatabaseClient {
    let auth = AuthService(config: testConfig, transport: fake, store: MemorySessionStore(session))
    return DatabaseClient(auth: auth, transport: fake)
  }

  @Test("asks as the signed-in person, in the right schema")
  func headers() async throws {
    let fake = FakeTransport { _ in .init(status: 200, body: "[]") }
    let db = client(fake)
    let _: [TasksProject] = try await db.select(
      "projects", schema: .tasks, [.select("id,name"), .in("id", ["a", "b c"]), .isNull("archived_at")])
    let request = try #require(fake.sent.first)
    #expect(request.path == "/rest/v1/projects")
    #expect(request.value(forHTTPHeaderField: "Accept-Profile") == "tasks")
    #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
    #expect(request.query.contains("id=in.(a,%22b%20c%22)"))
    #expect(request.query.contains("archived_at=is.null"))
  }

  @Test("an expired token is refreshed and the request tried again")
  func retry() async throws {
    let first = Flag()
    let fake = FakeTransport { request in
      if request.path == "/auth/v1/token" { return .init(status: 200, body: sessionJSON(refresh: "r2")) }
      return first.take()
        ? .init(status: 401, body: #"{"message":"JWT expired"}"#)
        : .init(status: 200, body: "[]")
    }
    let db = client(fake)
    let _: [TasksProject] = try await db.select("projects", schema: .tasks, [])
    #expect(fake.sent.map(\.path) == ["/rest/v1/projects", "/auth/v1/token", "/rest/v1/projects"])
  }

  @Test("the database's refusals become permission errors")
  func refusal() async throws {
    let fake = FakeTransport { _ in
      .init(status: 403, body: #"{"code":"42501","message":"new row violates row-level security policy"}"#)
    }
    let db = client(fake)
    await #expect(throws: MahamError.permission("new row violates row-level security policy")) {
      let _: [TaskItem] = try await db.insert("tasks", schema: .tasks, [["title": "x"]])
    }
  }
}

/// True the first time it is asked, false after.
final class Flag: @unchecked Sendable {
  private let lock = NSLock()
  private var used = false

  func take() -> Bool {
    lock.withLock {
      defer { used = true }
      return !used
    }
  }
}
