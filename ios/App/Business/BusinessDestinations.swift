import MahamKit
import SwiftUI

extension View {
  /// Where an invoice, a client or an employee pushed as a value opens. Each
  /// NavigationStack that shows Maham One records registers these once, on
  /// its root (the Maham One tab, Home, Search).
  func businessDestinations() -> some View {
    self
      .navigationDestination(for: SalesDocument.self) { invoice in
        InvoiceDetailView(invoice: invoice)
      }
      .navigationDestination(for: Client.self) { client in
        ClientDetailView(client: client)
      }
      .navigationDestination(for: Employee.self) { employee in
        EmployeeDetailView(employee: employee)
      }
  }
}

/// The lists the Maham One tab pushes on its own stack. Records are pushed as
/// themselves (see `businessDestinations`).
enum BusinessRoute: Hashable {
  case invoices(InvoiceFilter)
  case clients
  case people
  case expiries
  case updates
}

/// The screen for a route.
struct BusinessRouteView: View {
  let route: BusinessRoute

  init(route: BusinessRoute) {
    self.route = route
  }

  var body: some View {
    switch route {
    case .invoices(let filter):
      InvoicesListView(filter: filter)
    case .clients:
      ClientsListView()
    case .people:
      PeopleListView()
    case .expiries:
      ExpiriesListView()
    case .updates:
      TeamUpdatesView()
    }
  }
}
