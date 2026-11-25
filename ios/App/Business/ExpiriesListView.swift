import MahamKit
import SwiftUI

/// Licences, permits and (for the roles that see people) employees' papers,
/// grouped by how soon they expire: expired, within 30 days, later.
struct ExpiriesListView: View {
  @Environment(AppModel.self) private var model

  init() {}

  var body: some View {
    let business = model.business
    let today = business.today
    let all = BusinessUI.visibleExpiries(in: business)
    let expired = all.filter { $0.daysLeft(today: today) < 0 }
    let soon = all.filter { (0...30).contains($0.daysLeft(today: today)) }
    let later = all.filter { $0.daysLeft(today: today) > 30 }
    // Employees' papers open the employee, for the roles that see them.
    let owners: [String: Employee] = business.role.seesPeople ? Self.owners(business) : [:]
    List {
      section("Expired", expired, today: today, owners: owners)
      section("Within 30 days", soon, today: today, owners: owners)
      section("Later", later, today: today, owners: owners)
    }
    .mahamScreen()
    .navigationTitle("Expiries")
    .overlay {
      if all.isEmpty {
        EmptyState(
          title: "Nothing expires", symbol: "checkmark.seal",
          message: "Licences, permits and papers with an expiry date show here.")
      }
    }
    .refreshable {
      await Haptics.refresh()
      await business.refreshCompany()
    }
  }

  @ViewBuilder
  private func section(
    _ title: LocalizedStringKey, _ items: [Expiry], today: LocalDate, owners: [String: Employee]
  ) -> some View {
    if !items.isEmpty {
      Section {
        ForEach(items) { expiry in
          if let employee = owners[expiry.id] {
            NavigationLink(value: employee) {
              BusinessExpiryRow(expiry: expiry, today: today)
            }
            .glassRow()
          } else {
            BusinessExpiryRow(expiry: expiry, today: today)
              .glassRow()
          }
        }
      } header: {
        HStack {
          Text(title)
          Spacer()
          Text("\(items.count)")
            .monospacedDigit()
        }
      }
    }
  }

  /// Which employee each paper belongs to, by the paper's id.
  private static func owners(_ business: BusinessStore) -> [String: Employee] {
    let byId = Dictionary(business.employees.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var owners: [String: Employee] = [:]
    for employee in business.employees {
      for paper in employee.expiries {
        owners[paper.id] = employee
      }
    }
    for document in business.documents {
      if let id = document.employeeId, let employee = byId[id] {
        owners[document.id] = employee
      }
    }
    return owners
  }
}
