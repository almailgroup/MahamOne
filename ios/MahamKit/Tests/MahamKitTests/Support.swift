import Foundation

@testable import MahamKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A network that answers from a script and remembers what it was asked.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
  struct Reply {
    var status: Int
    var body: String
  }

  private let lock = NSLock()
  private var handler: (URLRequest) -> Reply
  private(set) var requests: [URLRequest] = []

  init(_ handler: @escaping (URLRequest) -> Reply) {
    self.handler = handler
  }

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let reply: Reply = lock.withLock {
      requests.append(request)
      return handler(request)
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
    return (Data(reply.body.utf8), response)
  }

  var sent: [URLRequest] { lock.withLock { requests } }
}

extension URLRequest {
  var bodyText: String { httpBody.map { String(decoding: $0, as: UTF8.self) } ?? "" }
  var path: String { url?.path ?? "" }
  var query: String { url?.query ?? "" }
}

/// A JWT whose payload says what a test needs (the signature is not checked).
func token(aal: String = "aal1", expiresIn: TimeInterval = 3600, role: String = "authenticated") -> String {
  func base64url(_ json: String) -> String {
    Data(json.utf8).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
  let exp = Int(Date().addingTimeInterval(expiresIn).timeIntervalSince1970)
  return base64url(#"{"alg":"HS256"}"#) + "."
    + base64url(#"{"aal":"\#(aal)","exp":\#(exp),"role":"\#(role)","sub":"user-1"}"#) + ".sig"
}

func sessionJSON(aal: String = "aal1", factors: String = "[]", refresh: String = "refresh-1") -> String {
  #"{"access_token":"\#(token(aal: aal))","refresh_token":"\#(refresh)","expires_in":3600,"user":{"id":"user-1","email":"noor@example.com","factors":\#(factors)}}"#
}

let testConfig = try! MahamConfig(
  supabaseURL: URL(string: "https://example.supabase.co")!, publishableKey: "sb_publishable_test")

func signedInSession(expiresIn: TimeInterval = 3600, aal: String = "aal1") -> AuthSession {
  AuthSession(
    accessToken: token(aal: aal, expiresIn: expiresIn), refreshToken: "refresh-1",
    expiresAt: Date().addingTimeInterval(expiresIn),
    user: AuthUser(id: "user-1", email: "noor@example.com"))
}
