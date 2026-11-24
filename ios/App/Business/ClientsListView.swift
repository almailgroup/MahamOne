import MahamKit
import SwiftUI

/// The company's clients, A to Z, searched by name, number, city, phone or
/// email. Archived clients stay hidden unless asked for.
struct ClientsListView: View {
  @Environment(AppModel.self) private var model
  @State private var query = ""
  @State private var showArchived = false

  init() {}

  private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// The clients under one letter.
  private struct LetterGroup: Identifiable {
    let id: String
    let clients: [Client]
  }

  var body: some View {
    let business = model.business
    let hasArchived = business.clients.contains(where: \.archived)
    let text = term
    let shown = business.clients.filter { client in
      (showArchived || !client.archived) && Self.matches(client, text)
    }
    let groups = Self.groups(shown)
    List {
      ForEach(groups) { group in
        Section {
          ForEach(group.clients) { client in
            NavigationLink(value: client) {
              ClientRow(client: client)
            }
            .glassRow()
          }
        } header: {
          Text(group.id)
        }
      }
    }
    .mahamScreen()
    .navigationTitle("Clients")
    .searchable(text: $query, prompt: Text("Name, number or city"))
    .overlay {
      if shown.isEmpty {
        if text.isEmpty {
          EmptyState(
            title: "No clients yet", symbol: "person.2",
            message: "Clients added on mahamone.com show here.")
        } else {
          ContentUnavailableView.search(text: text)
        }
      }
    }
    .toolbar {
      if hasArchived {
        ToolbarItem(placement: .topBarTrailing) {
          Toggle(isOn: $showArchived) {
            Label("Show archived", systemImage: "archivebox")
          }
          .toggleStyle(.button)
        }
      }
    }
    .sensoryFeedback(Haptics.pick, trigger: showArchived)
    .refreshable { await business.refreshCompany() }
  }

  private static func matches(_ client: Client, _ text: String) -> Bool {
    guard !text.isEmpty else { return true }
    let arabic: String = client.nameAr ?? ""
    let fields: [String] = [client.name, arabic, client.number, client.city, client.email, client.phone]
    if fields.contains(where: { $0.localizedStandardContains(text) }) { return true }
    return client.contacts.contains(where: { $0.name.localizedStandardContains(text) })
  }

  /// A to Z by the name in use; anything that doesn't start with a letter
  /// under "#", last.
  private static func groups(_ clients: [Client]) -> [LetterGroup] {
    let sorted = clients.sorted {
      BusinessUI.name($0).localizedStandardCompare(BusinessUI.name($1)) == .orderedAscending
    }
    var order: [String] = []
    var members: [String: [Client]] = [:]
    for client in sorted {
      let key = letter(client)
      if members[key] == nil { order.append(key) }
      members[key, default: []].append(client)
    }
    let letters = order.filter { $0 != "#" } + order.filter { $0 == "#" }
    return letters.map { LetterGroup(id: $0, clients: members[$0] ?? []) }
  }

  private static func letter(_ client: Client) -> String {
    let name = BusinessUI.name(client).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = name.first, first.isLetter else { return "#" }
    return String(first).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).uppercased()
  }
}

/// One client in a list: initials, name, number and city, and what they
/// still owe (red when some of it is overdue).
struct ClientRow: View {
  @Environment(AppModel.self) private var model
  let client: Client

  init(client: Client) {
    self.client = client
  }

  var body: some View {
    let business = model.business
    let name = BusinessUI.name(client)
    let open = business.invoices(for: client.id).filter(\.isOpen)
    let balance = open.reduce(0.0) { $0 + $1.totals.balance }
    let late = open.contains { $0.isOverdue(today: business.today) }
    let details = [client.number, client.city]
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
      .joined(separator: " · ")
    HStack(spacing: 12) {
      AvatarView(initials: BusinessUI.initials(name), id: client.id, size: 38)
      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .font(.body.weight(.semibold))
          .lineLimit(1)
        if !details.isEmpty {
          Text(details)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        if client.archived {
          Text("Archived")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 8)
      if balance > 0.0005 {
        VStack(alignment: .trailing, spacing: 2) {
          Text(business.format(balance))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(late ? Color.red : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          if late {
            Text("Overdue")
              .font(.caption2)
              .foregroundStyle(.red)
          } else {
            Text("Open")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}
