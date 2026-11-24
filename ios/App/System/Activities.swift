import Foundation
import MahamKit

/// What a screen tells iOS it is showing (`.userActivity`), so Handoff can
/// open the same thing on a Mac or iPad, and Siri can suggest it again.
/// Each type is listed in Info.plist's NSUserActivityTypes.
enum ActivityType {
  static let task = "com.almailgroup.mahamone.task"
  static let invoice = "com.almailgroup.mahamone.invoice"
  static let client = "com.almailgroup.mahamone.client"

  /// The key in `userInfo` that holds the record's id.
  static let idKey = "id"
}

extension NSUserActivity {
  /// Fills in an activity for a task: its title, its link, and the page on
  /// the web that Handoff opens on a Mac.
  func describe(task: TaskItem, config: MahamConfig?) {
    title = task.title
    userInfo = [ActivityType.idKey: task.id]
    targetContentIdentifier = DeepLink.task(task.id).url.absoluteString
    isEligibleForHandoff = true
    isEligibleForSearch = false
    isEligibleForPrediction = true
    if let config, var parts = URLComponents(url: config.tasksWebURL.appendingPathComponent("tasks"), resolvingAgainstBaseURL: false) {
      parts.queryItems = [URLQueryItem(name: "task", value: task.id)]
      webpageURL = parts.url
    }
  }

  func describe(invoice: SalesDocument, config: MahamConfig?) {
    title = invoice.number
    userInfo = [ActivityType.idKey: invoice.id]
    targetContentIdentifier = DeepLink.invoice(invoice.id).url.absoluteString
    isEligibleForHandoff = true
    isEligibleForSearch = false
    isEligibleForPrediction = false
    if let config { webpageURL = URL(string: "#/invoices/\(invoice.id)", relativeTo: config.webURL)?.absoluteURL }
  }

  func describe(client: Client, config: MahamConfig?) {
    title = client.name
    userInfo = [ActivityType.idKey: client.id]
    targetContentIdentifier = DeepLink.client(client.id).url.absoluteString
    isEligibleForHandoff = true
    isEligibleForSearch = false
    isEligibleForPrediction = true
    if let config { webpageURL = URL(string: "#/clients/\(client.id)", relativeTo: config.webURL)?.absoluteURL }
  }
}
