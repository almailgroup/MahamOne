import CoreSpotlight
import MahamKit
import UniformTypeIdentifiers

/// Your open tasks and the company's clients in the iPhone's search. Each
/// item's identifier is the app's own link, so a tap opens it in place
/// (MahamOneApp's `onContinueUserActivity`). Invoices and employees are
/// left out: Spotlight shows results without the app's Face ID lock.
enum Spotlight {
  static let tasksDomain = "tasks"
  static let clientsDomain = "clients"

  static func index(tasks: [TaskItem], projects: [TasksProject]) async {
    let names = Dictionary(projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    let items = tasks.map { task in
      let attributes = CSSearchableItemAttributeSet(contentType: .content)
      attributes.title = task.title
      var details: [String] = [NSLocalizedString(task.status.title, comment: "A task's status")]
      if let project = task.projectId.flatMap({ names[$0] }) { details.append(project) }
      if let due = task.dueAt { details.append(due.formatted(date: .abbreviated, time: .shortened)) }
      attributes.contentDescription = details.joined(separator: " · ")
      attributes.dueDate = task.dueAt
      attributes.keywords = [String(localized: "Task"), "Maham Tasks"]
      return CSSearchableItem(
        uniqueIdentifier: DeepLink.task(task.id).url.absoluteString,
        domainIdentifier: tasksDomain, attributeSet: attributes)
    }
    await replace(domain: tasksDomain, with: items)
  }

  static func index(clients: [Client]) async {
    let items = clients.map { client in
      let attributes = CSSearchableItemAttributeSet(contentType: .contact)
      attributes.title = client.name
      attributes.alternateNames = [client.nameAr].compactMap { $0 }
      attributes.contentDescription = [client.number, client.city].filter { !$0.isEmpty }.joined(separator: " · ")
      attributes.keywords = [String(localized: "Client"), "Maham One"]
      return CSSearchableItem(
        uniqueIdentifier: DeepLink.client(client.id).url.absoluteString,
        domainIdentifier: clientsDomain, attributeSet: attributes)
    }
    await replace(domain: clientsDomain, with: items)
  }

  static func removeAll() async {
    try? await CSSearchableIndex.default().deleteAllSearchableItems()
  }

  private static func replace(domain: String, with items: [CSSearchableItem]) async {
    let index = CSSearchableIndex.default()
    try? await index.deleteSearchableItems(withDomainIdentifiers: [domain])
    guard !items.isEmpty else { return }
    try? await index.indexSearchableItems(items)
  }
}
