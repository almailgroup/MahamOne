import AppIntents
import Foundation
import MahamKit

/// Why an intent couldn't do what was asked, in words Siri, Shortcuts and
/// the widgets can say.
enum MahamIntentError: Error, CustomLocalizedStringResourceConvertible {
  case notConfigured
  case notSignedIn
  case needsSecondStep
  case notInTasks
  case taskNotFound
  case offline
  case unreachable
  /// A message from the app or the database (a catalog key when it is one).
  case failed(String)

  /// The app's own errors, said for Siri.
  init(_ error: any Error) {
    if let known = error as? MahamIntentError {
      self = known
      return
    }
    guard let error = error as? MahamError else {
      self = .failed(error.localizedDescription)
      return
    }
    switch error {
    case .notSignedIn, .sessionExpired: self = .notSignedIn
    case .needsSecondStep: self = .needsSecondStep
    case .notInTasks: self = .notInTasks
    case .offline: self = .offline
    default: self = .failed(error.message)
    }
  }

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .notConfigured:
      "Maham One isn't set up on this iPhone yet."
    case .notSignedIn:
      "Sign in to Maham One first."
    case .needsSecondStep:
      "Open Maham One and enter the code from your authenticator app first."
    case .notInTasks:
      "Your Maham One account is not in Maham Tasks yet. Ask a Maham Tasks admin to invite you."
    case .taskNotFound:
      "That task isn't in Maham Tasks anymore."
    case .offline:
      "You're offline. Try again when you're connected."
    case .unreachable:
      "Maham Tasks can't be reached right now. Try again in a moment."
    case .failed(let message):
      LocalizedStringResource(stringLiteral: message)
    }
  }
}
