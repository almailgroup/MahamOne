import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Sends a request and hands back the body and the response. The app uses
/// URLSession; tests use a fake that answers from a script.
public protocol HTTPTransport: Sendable {
  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
  let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    do {
      let (data, response) = try await data(for: request)
      guard let http = response as? HTTPURLResponse else {
        throw MahamError.server(status: 0, code: nil, message: "No answer from the server.")
      }
      return (data, http)
    } catch let error as URLError {
      switch error.code {
      case .notConnectedToInternet, .networkConnectionLost, .timedOut,
        .cannotFindHost, .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff:
        throw MahamError.offline
      default:
        throw MahamError.server(status: 0, code: nil, message: error.localizedDescription)
      }
    }
  }

  private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    #if canImport(FoundationNetworking)
      // Linux's URLSession has no async API on every version: bridge it.
      try await withCheckedThrowingContinuation { continuation in
        session.dataTask(with: request) { data, response, error in
          if let error {
            continuation.resume(throwing: error)
          } else if let data, let response {
            continuation.resume(returning: (data, response))
          } else {
            continuation.resume(throwing: URLError(.badServerResponse))
          }
        }.resume()
      }
    #else
      try await session.data(for: request)
    #endif
  }
}

/// JSON as Supabase writes it: snake_case keys are named in each model's
/// CodingKeys, dates are ISO 8601 with up to microseconds.
public enum MahamJSON {
  public static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let text = try container.decode(String.self)
      guard let date = MahamDates.parseTimestamp(text) else {
        throw DecodingError.dataCorruptedError(
          in: container, debugDescription: "Not a timestamp: \(text)")
      }
      return date
    }
    return decoder
  }

  public static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(MahamDates.timestamp(date))
    }
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}
