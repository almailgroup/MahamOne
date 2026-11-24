import MahamKit
import SwiftUI

/// One search across both departments: tasks (on the server, so it finds
/// the team's too), and the company's clients and invoices (on the iPhone).
struct SearchView: View {
  @Environment(AppModel.self) private var model
  @State private var text = ""
  @State private var tasks: [TaskItem] = []
  @State private var searching = false

  private var term: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    NavigationStack {
      List {
        if term.isEmpty {
          Section {
            Label("Search tasks, clients and invoices.", systemImage: "magnifyingglass")
              .foregroundStyle(.secondary)
          }
          .listRowBackground(Color.clear)
        } else {
          if !tasks.isEmpty {
            Section("Tasks") {
              ForEach(tasks) { task in
                NavigationLink(value: task) { TaskRow(task: task) }.glassRow()
              }
            }
          }
          if !clients.isEmpty {
            Section("Clients") {
              ForEach(clients) { client in
                NavigationLink(value: client) { ClientRow(client: client) }.glassRow()
              }
            }
          }
          if !invoices.isEmpty {
            Section("Invoices") {
              ForEach(invoices) { invoice in
                NavigationLink(value: invoice) { InvoiceRow(invoice: invoice) }.glassRow()
              }
            }
          }
        }
      }
      .mahamScreen()
      .navigationTitle("Search")
      .searchable(text: $text, prompt: Text("Tasks, clients, invoices"))
      .overlay {
        if !term.isEmpty, !searching, tasks.isEmpty, clients.isEmpty, invoices.isEmpty {
          ContentUnavailableView.search(text: term)
        }
      }
      .task(id: term) { await search() }
      .taskDestinations()
      .businessDestinations()
    }
  }

  private var clients: [Client] {
    guard !term.isEmpty else { return [] }
    return model.business.clients
      .filter { client in
        [client.name, client.nameAr ?? "", client.number, client.email, client.phone, client.city]
          .contains { $0.localizedStandardContains(term) }
      }
      .prefix(20)
      .map { $0 }
  }

  private var invoices: [SalesDocument] {
    guard !term.isEmpty else { return [] }
    let business = model.business
    return business.invoices
      .filter { invoice in
        invoice.number.localizedStandardContains(term)
          || (business.client(invoice.clientId)?.name.localizedStandardContains(term) ?? false)
          || invoice.poNumber.localizedStandardContains(term)
      }
      .sorted { ($0.issueDate ?? LocalDate(year: 1970, month: 1, day: 1)) > ($1.issueDate ?? LocalDate(year: 1970, month: 1, day: 1)) }
      .prefix(20)
      .map { $0 }
  }

  /// Waits for a pause in typing, then asks the server.
  private func search() async {
    guard term.count >= 2, !model.tasks.notInTasks else {
      tasks = []
      return
    }
    searching = true
    defer { searching = false }
    do {
      try await Task.sleep(for: .milliseconds(300))
      tasks = try await model.tasks.search(term)
    } catch is CancellationError {
    } catch {
      tasks = model.tasks.myTasks.filter { $0.title.localizedStandardContains(term) }
    }
  }
}
