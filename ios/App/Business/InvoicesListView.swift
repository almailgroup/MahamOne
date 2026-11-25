import MahamKit
import SwiftUI

/// Which invoices the list shows.
enum InvoiceFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
  case open, overdue, paid, all

  var id: Self { self }

  var label: LocalizedStringKey {
    switch self {
    case .open: "Open"
    case .overdue: "Overdue"
    case .paid: "Paid"
    case .all: "All"
    }
  }

  func matches(_ invoice: SalesDocument, today: LocalDate) -> Bool {
    switch self {
    case .open: invoice.isOpen
    case .overdue: invoice.isOverdue(today: today)
    case .paid: invoice.status == .paid
    case .all: true
    }
  }
}

/// The company's invoices, newest first: open, overdue, paid or all of them,
/// searched by number, client or PO number.
struct InvoicesListView: View {
  @Environment(AppModel.self) private var model
  @State private var filter: InvoiceFilter
  @State private var query = ""

  init(filter: InvoiceFilter = .open) {
    _filter = State(initialValue: filter)
  }

  private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    let business = model.business
    let shown = invoices(business)
    List {
      Section {
        Picker("Show", selection: $filter) {
          ForEach(InvoiceFilter.allCases) { option in
            Text(option.label).tag(option)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

      if !shown.isEmpty {
        Section {
          ForEach(shown) { invoice in
            NavigationLink(value: invoice) {
              InvoiceRow(invoice: invoice)
            }
            .glassRow()
          }
        } header: {
          Text("\(shown.count) invoices")
        } footer: {
          if filter == .open || filter == .overdue {
            Text("Balance \(business.format(BusinessUI.openBalance(shown)))")
          }
        }
      }
    }
    .mahamScreen()
    .navigationTitle("Invoices")
    .searchable(text: $query, prompt: Text("Number or client"))
    .overlay {
      if shown.isEmpty {
        if term.isEmpty {
          EmptyState(title: emptyTitle, symbol: "doc.text", message: emptyMessage)
        } else {
          ContentUnavailableView.search(text: term)
        }
      }
    }
    .haptic(.selection, trigger: filter)
    .refreshable {
      await Haptics.refresh()
      await business.refreshCompany()
    }
  }

  private func invoices(_ business: BusinessStore) -> [SalesDocument] {
    let today = business.today
    let clients = Dictionary(business.clients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let text = term
    let floor = LocalDate(year: 1, month: 1, day: 1)
    return business.invoices
      .filter { filter.matches($0, today: today) }
      .filter { invoice in
        guard !text.isEmpty else { return true }
        if invoice.number.localizedStandardContains(text) || invoice.poNumber.localizedStandardContains(text) {
          return true
        }
        guard let client = clients[invoice.clientId] else { return false }
        return client.name.localizedStandardContains(text)
          || (client.nameAr ?? "").localizedStandardContains(text)
          || client.number.localizedStandardContains(text)
      }
      .sorted { ($0.issueDate ?? floor) > ($1.issueDate ?? floor) }
  }

  private var emptyTitle: LocalizedStringKey {
    switch filter {
    case .open: "Nothing owed"
    case .overdue: "Nothing overdue"
    case .paid: "No paid invoices"
    case .all: "No invoices yet"
    }
  }

  private var emptyMessage: LocalizedStringKey {
    switch filter {
    case .open: "Invoices that are sent and not yet paid show here."
    case .overdue: "Invoices past their due date show here."
    case .paid: "Invoices paid in full show here."
    case .all: "Invoices made on mahamone.com show here."
    }
  }
}

/// One invoice in a list: its number and state, the client, the dates, and
/// what is still owed (or its total, once settled).
struct InvoiceRow: View {
  @Environment(AppModel.self) private var model
  let invoice: SalesDocument
  var showsClient: Bool

  init(invoice: SalesDocument, showsClient: Bool = true) {
    self.invoice = invoice
    self.showsClient = showsClient
  }

  var body: some View {
    let business = model.business
    let overdue = invoice.isOverdue(today: business.today)
    let amount = invoice.isOpen ? invoice.totals.balance : invoice.totals.total
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(invoice.number.isEmpty ? "—" : invoice.number)
            .font(.body.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
          DocumentBadge(status: invoice.status, overdue: overdue)
        }
        if showsClient {
          clientName(business)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        HStack(spacing: 10) {
          if let issued = invoice.issueDate {
            Text("Issued \(issued.display)")
          }
          if let due = invoice.dueDate {
            Text("Due \(due.display)")
              .foregroundStyle(overdue ? Color.red : Color.secondary)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 2) {
        Text(BusinessUI.money(amount, currency: invoice.currency, in: business))
          .font(.subheadline.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(overdue ? Color.red : Color.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        Group {
          if invoice.isOpen {
            Text("Balance")
          } else {
            Text("Total")
          }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }

  private func clientName(_ business: BusinessStore) -> Text {
    if let client = business.client(invoice.clientId) {
      return Text(BusinessUI.name(client))
    }
    return Text("Unknown client")
  }
}
