import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Which part of the database a request is for: Maham One's tables are in
/// `public`, Maham Tasks' in `tasks` (see docs/maham-tasks.md).
public enum DatabaseSchema: String, Sendable {
  case maham = "public"
  case tasks = "tasks"
}

/// A PostgREST filter or modifier, as a query item.
public struct Query: Sendable, Equatable {
  public let name: String
  public let value: String

  public init(_ name: String, _ value: String) {
    self.name = name
    self.value = value
  }

  public static func select(_ columns: String) -> Query { Query("select", columns) }
  public static func eq(_ column: String, _ value: String) -> Query { Query(column, "eq.\(value)") }
  public static func neq(_ column: String, _ value: String) -> Query { Query(column, "neq.\(value)") }
  public static func gte(_ column: String, _ value: String) -> Query { Query(column, "gte.\(value)") }
  public static func lt(_ column: String, _ value: String) -> Query { Query(column, "lt.\(value)") }
  public static func isNull(_ column: String) -> Query { Query(column, "is.null") }
  public static func notNull(_ column: String) -> Query { Query(column, "not.is.null") }
  public static func ilike(_ column: String, _ pattern: String) -> Query {
    Query(column, "ilike.\(pattern)")
  }
  public static func `in`(_ column: String, _ values: [String]) -> Query {
    Query(column, "in.(\(values.map(quoted).joined(separator: ",")))")
  }
  public static func order(_ column: String, ascending: Bool = true, nullsLast: Bool = true) -> Query
  {
    Query("order", "\(column).\(ascending ? "asc" : "desc")\(nullsLast ? ".nullslast" : ".nullsfirst")")
  }
  public static func limit(_ count: Int) -> Query { Query("limit", String(count)) }

  /// A value inside `in.(…)`: quoted when it holds a separator.
  static func quoted(_ value: String) -> String {
    let special = CharacterSet(charactersIn: ",.:()\" ")
    guard value.rangeOfCharacter(from: special) != nil else { return value }
    return "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }
}

/// Talks to the database (PostgREST) as the signed-in person. Every read and
/// write runs under the database's rules: the app never holds a key that
/// could see more than its user.
public struct DatabaseClient: Sendable {
  public let auth: AuthService
  private let transport: HTTPTransport

  public init(auth: AuthService, transport: HTTPTransport) {
    self.auth = auth
    self.transport = transport
  }

  // MARK: Reading

  public func select<Row: Decodable>(
    _ table: String, schema: DatabaseSchema, _ query: [Query]
  ) async throws -> [Row] {
    let data = try await send(method: "GET", path: table, schema: schema, query: query)
    return try decode([Row].self, from: data)
  }

  /// Every row, a page at a time (PostgREST answers at most 1000 per page).
  public func selectAll<Row: Decodable>(
    _ table: String, schema: DatabaseSchema, _ query: [Query], pageSize: Int = 1000
  ) async throws -> [Row] {
    var rows: [Row] = []
    var offset = 0
    while true {
      let page: [Row] = try await select(
        table, schema: schema, query + [Query("limit", String(pageSize)), Query("offset", String(offset))])
      rows += page
      if page.count < pageSize { return rows }
      offset += pageSize
    }
  }

  // MARK: Writing

  @discardableResult
  public func insert<Values: Encodable, Row: Decodable>(
    _ table: String, schema: DatabaseSchema, _ values: Values, returning columns: String = "*"
  ) async throws -> [Row] {
    let data = try await send(
      method: "POST", path: table, schema: schema, query: [.select(columns)],
      body: try MahamJSON.encoder().encode(values), prefer: "return=representation")
    return try decode([Row].self, from: data)
  }

  /// Inserts without reading anything back.
  public func insert<Values: Encodable>(
    _ table: String, schema: DatabaseSchema, _ values: Values
  ) async throws {
    _ = try await send(
      method: "POST", path: table, schema: schema, query: [],
      body: try MahamJSON.encoder().encode(values), prefer: "return=minimal")
  }

  /// Updates the rows the filters match, and returns them: an empty answer
  /// means the rules let none of them change.
  @discardableResult
  public func update<Values: Encodable, Row: Decodable>(
    _ table: String, schema: DatabaseSchema, _ values: Values, where filters: [Query],
    returning columns: String = "*"
  ) async throws -> [Row] {
    let data = try await send(
      method: "PATCH", path: table, schema: schema, query: filters + [.select(columns)],
      body: try MahamJSON.encoder().encode(values), prefer: "return=representation")
    return try decode([Row].self, from: data)
  }

  public func delete(_ table: String, schema: DatabaseSchema, where filters: [Query]) async throws {
    _ = try await send(method: "DELETE", path: table, schema: schema, query: filters, prefer: "return=minimal")
  }

  // MARK: Functions

  public func rpc<Params: Encodable, Result: Decodable>(
    _ function: String, schema: DatabaseSchema, _ params: Params
  ) async throws -> Result {
    let data = try await send(
      method: "POST", path: "rpc/\(function)", schema: schema, query: [],
      body: try MahamJSON.encoder().encode(params))
    return try decode(Result.self, from: data)
  }

  // MARK: Wire

  private func send(
    method: String, path: String, schema: DatabaseSchema, query: [Query], body: Data? = nil,
    prefer: String? = nil, retried: Bool = false
  ) async throws -> Data {
    let session = try await auth.validSession()
    var components = URLComponents(
      url: auth.config.supabaseURL.appendingPathComponent("rest/v1/\(path)"),
      resolvingAgainstBaseURL: false)!
    if !query.isEmpty {
      components.percentEncodedQueryItems = query.map {
        URLQueryItem(name: Self.encode($0.name), value: Self.encode($0.value))
      }
    }
    var request = URLRequest(url: components.url!)
    request.httpMethod = method
    request.timeoutInterval = 30
    request.setValue(auth.config.publishableKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue(schema.rawValue, forHTTPHeaderField: "Accept-Profile")
    if let body {
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(schema.rawValue, forHTTPHeaderField: "Content-Profile")
    }
    if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }

    let (data, response) = try await transport.send(request)
    switch response.statusCode {
    case 200..<300:
      return data
    case 401 where !retried:
      // An expired token the clock didn't catch: refresh once and retry.
      _ = try await auth.refresh()
      return try await send(
        method: method, path: path, schema: schema, query: query, body: body, prefer: prefer,
        retried: true)
    case 401:
      throw MahamError.sessionExpired
    default:
      throw Self.error(status: response.statusCode, data: data)
    }
  }

  /// Percent-encodes a query value, leaving PostgREST's own punctuation.
  static func encode(_ value: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&+=#")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }

  /// PostgREST's error body: `{code, message, details, hint}`.
  static func error(status: Int, data: Data) -> MahamError {
    let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    let code = object["code"] as? String
    let message = (object["message"] as? String) ?? "The server answered \(status)."
    if status == 403 || code == "42501" {
      return .permission(message)
    }
    return .server(status: status, code: code, message: message)
  }

  private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
      return try MahamJSON.decoder().decode(type, from: data)
    } catch {
      throw MahamError.decoding(String(describing: error))
    }
  }
}

/// Nothing to send (a function without parameters).
public struct NoParams: Encodable, Sendable {
  public init() {}
}
