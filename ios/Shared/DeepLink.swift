import Foundation

/// Somewhere the app was asked to open: a link, a widget, Spotlight, Siri,
/// a reminder. The app and its widgets share it.
enum DeepLink: Hashable, Sendable {
  case today
  case newTask
  case task(String)
  case project(String)
  case invoice(String)
  case client(String)
  case inbox

  /// `mahamone://today`, `mahamone://new-task`, `mahamone://task/<id>`,
  /// `mahamone://project/<id>`, `mahamone://invoice/<id>`,
  /// `mahamone://client/<id>`, `mahamone://inbox`.
  init?(url: URL) {
    guard url.scheme == "mahamone" else { return nil }
    let parts = [url.host ?? ""] + url.pathComponents.filter { $0 != "/" }
    let id = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
    switch (parts.first ?? "", id) {
    case ("today", _): self = .today
    case ("new-task", _): self = .newTask
    case ("inbox", _): self = .inbox
    case ("task", let id?): self = .task(id)
    case ("project", let id?): self = .project(id)
    case ("invoice", let id?): self = .invoice(id)
    case ("client", let id?): self = .client(id)
    default: return nil
    }
  }

  init?(string: String) {
    guard let url = URL(string: string) else { return nil }
    self.init(url: url)
  }

  var url: URL {
    switch self {
    case .today: URL(string: "mahamone://today")!
    case .newTask: URL(string: "mahamone://new-task")!
    case .inbox: URL(string: "mahamone://inbox")!
    case .task(let id): URL(string: "mahamone://task/\(Self.safe(id))")!
    case .project(let id): URL(string: "mahamone://project/\(Self.safe(id))")!
    case .invoice(let id): URL(string: "mahamone://invoice/\(Self.safe(id))")!
    case .client(let id): URL(string: "mahamone://client/\(Self.safe(id))")!
    }
  }

  private static func safe(_ id: String) -> String {
    id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? id
  }
}

/// How an App Intent running inside the app (Siri, Shortcuts, a Control
/// Center control) tells the app where to go. The app sets `handler` when it
/// starts; a link that arrives first waits for it.
@MainActor
enum Navigator {
  static var handler: ((DeepLink) -> Void)? {
    didSet {
      if let handler, let waiting {
        self.waiting = nil
        handler(waiting)
      }
    }
  }

  private static var waiting: DeepLink?

  static func open(_ link: DeepLink) {
    if let handler {
      handler(link)
    } else {
      waiting = link
    }
  }
}
