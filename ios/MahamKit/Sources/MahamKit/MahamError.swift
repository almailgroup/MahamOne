import Foundation

/// Everything that can go wrong, in words a person can act on. The app shows
/// `message` (translated through its string catalog, where the text is a key).
public enum MahamError: Error, Equatable, Sendable {
  case configuration(String)
  case notSignedIn
  case sessionExpired
  case invalidCredentials
  case emailNotConfirmed
  /// The account has an authenticator app: the code is asked for next.
  case needsSecondStep
  case wrongCode
  /// Signed in to Maham One, but not (yet) in Maham Tasks.
  case notInTasks
  case offline
  case permission(String)
  case server(status: Int, code: String?, message: String)
  case decoding(String)

  public var message: String {
    switch self {
    case .configuration(let detail): detail
    case .notSignedIn: "Sign in to continue."
    case .sessionExpired: "You were signed out. Sign in again."
    case .invalidCredentials: "That email and password don't match."
    case .emailNotConfirmed: "Confirm your email first, from the link Maham One sent you."
    case .needsSecondStep: "Enter the code from your authenticator app."
    case .wrongCode: "That code didn't work. Try the newest one."
    case .notInTasks:
      "Your Maham One account is not in Maham Tasks yet. Ask a Maham Tasks admin to invite you."
    case .offline: "You're offline. What's shown was saved on this iPhone."
    case .permission(let detail): detail.isEmpty ? "You don't have permission for that." : detail
    case .server(_, _, let message): message
    case .decoding: "Something came back in a form the app didn't expect."
    }
  }
}

extension MahamError: LocalizedError {
  public var errorDescription: String? { message }
}
