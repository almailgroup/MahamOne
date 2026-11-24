import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The signed-in account, as Supabase Auth hands it over.
public struct AuthSession: Codable, Equatable, Sendable {
  public var accessToken: String
  public var refreshToken: String
  public var expiresAt: Date
  public var user: AuthUser

  public init(accessToken: String, refreshToken: String, expiresAt: Date, user: AuthUser) {
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.expiresAt = expiresAt
    self.user = user
  }

  /// "aal2" once the authenticator app's code was entered this session.
  public var assuranceLevel: String {
    (JWT.payload(accessToken)?["aal"] as? String) ?? "aal1"
  }

  public var signedInWithSecondStep: Bool { assuranceLevel == "aal2" }

  /// Within a minute of expiring, or past it.
  public func needsRefresh(now: Date = Date()) -> Bool {
    expiresAt.timeIntervalSince(now) < 60
  }
}

public struct AuthUser: Codable, Equatable, Sendable {
  public var id: String
  public var email: String?
  public var factors: [AuthFactor]

  public init(id: String, email: String?, factors: [AuthFactor] = []) {
    self.id = id
    self.email = email
    self.factors = factors
  }

  enum CodingKeys: String, CodingKey { case id, email, factors }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    email = try c.decodeIfPresent(String.self, forKey: .email)
    factors = (try? c.decodeIfPresent([AuthFactor].self, forKey: .factors)) ?? []
  }

  /// An authenticator app that has been set up (verified).
  public var verifiedTOTP: AuthFactor? {
    factors.first { $0.factorType == "totp" && $0.status == "verified" }
  }
}

public struct AuthFactor: Codable, Equatable, Sendable {
  public var id: String
  public var factorType: String
  public var status: String
  public var friendlyName: String?

  enum CodingKeys: String, CodingKey {
    case id, status
    case factorType = "factor_type"
    case friendlyName = "friendly_name"
  }
}

/// Where the session is kept between launches: the Keychain in the app (and
/// shared with its widgets), memory in tests.
public protocol SessionStore: Sendable {
  func load() -> AuthSession?
  func save(_ session: AuthSession)
  func clear()
}

public final class MemorySessionStore: SessionStore, @unchecked Sendable {
  private let lock = NSLock()
  private var session: AuthSession?

  public init(_ session: AuthSession? = nil) {
    self.session = session
  }

  public func load() -> AuthSession? {
    lock.lock()
    defer { lock.unlock() }
    return session
  }

  public func save(_ session: AuthSession) {
    lock.lock()
    defer { lock.unlock() }
    self.session = session
  }

  public func clear() {
    lock.lock()
    defer { lock.unlock() }
    session = nil
  }
}

/// What signing in with a password led to.
public enum SignInResult: Equatable, Sendable {
  case signedIn(AuthSession)
  /// The account has an authenticator app: `verifySecondStep(code:)` next.
  case needsSecondStep(AuthSession)
}

/// Signing in, keeping the session fresh, and signing out, against Supabase
/// Auth (GoTrue). One instance per app; an actor, so two refreshes never
/// race each other with the same refresh token (which Supabase would treat as
/// reuse and revoke).
public actor AuthService {
  nonisolated public let config: MahamConfig
  private let transport: HTTPTransport
  private let store: SessionStore
  private var refreshing: Task<AuthSession, Error>?

  public init(config: MahamConfig, transport: HTTPTransport, store: SessionStore) {
    self.config = config
    self.transport = transport
    self.store = store
  }

  /// The saved session, as it is (it may need a refresh).
  public var currentSession: AuthSession? { store.load() }

  // MARK: Signing in

  public func signIn(email: String, password: String) async throws -> SignInResult {
    let body = ["email": email.trimmingCharacters(in: .whitespaces).lowercased(), "password": password]
    let session = try await tokenRequest(grant: "password", body: body)
    store.save(session)
    if session.user.verifiedTOTP != nil, !session.signedInWithSecondStep {
      return .needsSecondStep(session)
    }
    return .signedIn(session)
  }

  /// The six-digit code from the authenticator app, after `signIn`.
  public func verifySecondStep(code: String) async throws -> AuthSession {
    let session = try await validSession()
    guard let factor = session.user.verifiedTOTP else { return session }
    let digits = code.filter(\.isNumber)
    guard digits.count == 6 else { throw MahamError.wrongCode }

    let challenge: [String: AnyCodable] = try await authJSON(
      path: "factors/\(factor.id)/challenge", method: "POST", body: [String: String](),
      token: session.accessToken)
    guard let challengeId = challenge["id"]?.value as? String else {
      throw MahamError.decoding("No challenge id")
    }
    do {
      let wire: WireSession = try await authJSON(
        path: "factors/\(factor.id)/verify", method: "POST",
        body: ["challenge_id": challengeId, "code": digits], token: session.accessToken)
      let verified = try wire.session(keeping: session)
      store.save(verified)
      return verified
    } catch MahamError.server(let status, _, _) where (400..<500).contains(status) {
      throw MahamError.wrongCode
    }
  }

  /// A session that is good for at least a minute, refreshed if needed.
  public func validSession() async throws -> AuthSession {
    guard let session = store.load() else { throw MahamError.notSignedIn }
    guard session.needsRefresh() else { return session }
    return try await refresh(session)
  }

  /// Refreshes even if the token still has time (after a 401, or when the
  /// app comes back to the foreground after a long time).
  public func refresh() async throws -> AuthSession {
    guard let session = store.load() else { throw MahamError.notSignedIn }
    return try await refresh(session)
  }

  private func refresh(_ session: AuthSession) async throws -> AuthSession {
    if let refreshing { return try await refreshing.value }
    let task = Task { () throws -> AuthSession in
      do {
        let fresh = try await tokenRequest(
          grant: "refresh_token", body: ["refresh_token": session.refreshToken], keeping: session)
        return fresh
      } catch MahamError.server(let status, _, _) where status == 400 || status == 401 {
        throw MahamError.sessionExpired
      }
    }
    refreshing = task
    defer { refreshing = nil }
    do {
      let fresh = try await task.value
      store.save(fresh)
      return fresh
    } catch MahamError.sessionExpired {
      store.clear()
      throw MahamError.sessionExpired
    }
  }

  // MARK: Signing out and passwords

  /// Signs out on this iPhone only: the same account stays signed in to
  /// Maham One and Maham Tasks elsewhere.
  public func signOut() async {
    if let session = store.load() {
      _ = try? await authJSON(
        path: "logout?scope=local", method: "POST", body: [String: String](),
        token: session.accessToken) as [String: AnyCodable]
    }
    store.clear()
  }

  /// Emails a link to choose a new password; it opens Maham One's website.
  public func sendPasswordReset(email: String) async throws {
    let redirect = config.webURL.absoluteString
    let _: [String: AnyCodable] = try await authJSON(
      path: "recover?redirect_to=\(redirect.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirect)",
      method: "POST", body: ["email": email.trimmingCharacters(in: .whitespaces).lowercased()],
      token: nil)
  }

  // MARK: Wire

  private func tokenRequest(
    grant: String, body: [String: String], keeping previous: AuthSession? = nil
  ) async throws -> AuthSession {
    do {
      let wire: WireSession = try await authJSON(
        path: "token?grant_type=\(grant)", method: "POST", body: body, token: nil)
      return try wire.session(keeping: previous)
    } catch MahamError.server(let status, let code, let message) where status == 400 {
      if grant == "password" {
        if code == "email_not_confirmed" || message.localizedCaseInsensitiveContains("not confirmed") {
          throw MahamError.emailNotConfirmed
        }
        throw MahamError.invalidCredentials
      }
      throw MahamError.server(status: status, code: code, message: message)
    }
  }

  private func authJSON<Body: Encodable, Result: Decodable>(
    path: String, method: String, body: Body, token: String?
  ) async throws -> Result {
    var request = URLRequest(url: URL(string: "auth/v1/\(path)", relativeTo: config.supabaseURL)!)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    request.httpBody = try JSONEncoder().encode(body)
    request.timeoutInterval = 20

    let (data, response) = try await transport.send(request)
    guard (200..<300).contains(response.statusCode) else {
      throw AuthErrorBody.error(status: response.statusCode, data: data)
    }
    if data.isEmpty, let empty = [String: AnyCodable]() as? Result { return empty }
    do {
      return try MahamJSON.decoder().decode(Result.self, from: data)
    } catch {
      throw MahamError.decoding(String(describing: error))
    }
  }
}

/// A session as Supabase Auth sends it.
struct WireSession: Decodable {
  let accessToken: String
  let refreshToken: String
  let expiresIn: Double?
  let expiresAt: Double?
  let user: AuthUser?

  enum CodingKeys: String, CodingKey {
    case user
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresIn = "expires_in"
    case expiresAt = "expires_at"
  }

  func session(keeping previous: AuthSession?, now: Date = Date()) throws -> AuthSession {
    let expiry: Date
    if let expiresAt {
      expiry = Date(timeIntervalSince1970: expiresAt)
    } else if let expiresIn {
      expiry = now.addingTimeInterval(expiresIn)
    } else if let exp = JWT.payload(accessToken)?["exp"] as? Double {
      expiry = Date(timeIntervalSince1970: exp)
    } else {
      expiry = now.addingTimeInterval(3600)
    }
    guard let user = user ?? previous?.user else { throw MahamError.decoding("No user in session") }
    return AuthSession(
      accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiry, user: user)
  }
}

/// Supabase Auth's two error shapes: `{error, error_description}` (older)
/// and `{code, error_code, msg}` (newer).
enum AuthErrorBody {
  static func error(status: Int, data: Data) -> MahamError {
    let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    let code = (object["error_code"] as? String) ?? (object["error"] as? String)
    let message =
      (object["msg"] as? String) ?? (object["error_description"] as? String)
      ?? (object["message"] as? String) ?? "The sign-in service answered \(status)."
    return .server(status: status, code: code, message: message)
  }
}

/// Just enough of an untyped JSON value to read an id out of a reply.
public struct AnyCodable: Codable, @unchecked Sendable, Equatable {
  public let value: Any?

  public init(_ value: Any?) {
    self.value = value
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      value = nil
    } else if let bool = try? container.decode(Bool.self) {
      value = bool
    } else if let int = try? container.decode(Int.self) {
      value = int
    } else if let double = try? container.decode(Double.self) {
      value = double
    } else if let string = try? container.decode(String.self) {
      value = string
    } else if let array = try? container.decode([AnyCodable].self) {
      value = array.map(\.value)
    } else if let object = try? container.decode([String: AnyCodable].self) {
      value = object.mapValues(\.value)
    } else {
      value = nil
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch value {
    case nil: try container.encodeNil()
    case let bool as Bool: try container.encode(bool)
    case let int as Int: try container.encode(int)
    case let double as Double: try container.encode(double)
    case let string as String: try container.encode(string)
    default: try container.encodeNil()
    }
  }

  public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
    String(describing: lhs.value) == String(describing: rhs.value)
  }
}
