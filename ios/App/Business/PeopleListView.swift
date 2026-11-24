import MahamKit
import SwiftUI

/// The company's employees, for the owner, admins and accountants only: the
/// active first, then those who left. Searched by name, job or number, and
/// narrowed to a department.
struct PeopleListView: View {
  @Environment(AppModel.self) private var model
  @State private var query = ""
  @State private var department: String?

  init() {}

  var body: some View {
    let business = model.business
    Group {
      if business.role.seesPeople {
        list(business)
      } else {
        PeopleLockedView()
      }
    }
    .mahamScreen()
    .navigationTitle("People")
  }

  private func list(_ business: BusinessStore) -> some View {
    let all = business.employees
    let departments = Self.departments(all)
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let chosen = department
    let shown = all.filter { employee in
      if let chosen, employee.department.trimmingCharacters(in: .whitespaces) != chosen { return false }
      return Self.matches(employee, text)
    }
    let byName: (Employee, Employee) -> Bool = {
      BusinessUI.name($0).localizedStandardCompare(BusinessUI.name($1)) == .orderedAscending
    }
    let active = shown.filter(\.isActive).sorted(by: byName)
    let former = shown.filter { !$0.isActive }.sorted(by: byName)
    let today = business.today
    return List {
      if !active.isEmpty {
        Section {
          ForEach(active) { employee in
            NavigationLink(value: employee) {
              BusinessEmployeeRow(employee: employee, today: today)
            }
            .glassRow()
          }
        } header: {
          Text("Active · \(active.count)")
        }
      }
      if !former.isEmpty {
        Section {
          ForEach(former) { employee in
            NavigationLink(value: employee) {
              BusinessEmployeeRow(employee: employee, today: today)
            }
            .glassRow()
          }
        } header: {
          Text("Left the company · \(former.count)")
        }
      }
    }
    .searchable(text: $query, prompt: Text("Name, job or number"))
    .overlay {
      if shown.isEmpty {
        if text.isEmpty && chosen == nil {
          EmptyState(
            title: "No employees yet", symbol: "person.text.rectangle",
            message: "Employees added on mahamone.com show here.")
        } else if !text.isEmpty {
          ContentUnavailableView.search(text: text)
        } else {
          EmptyState(title: "No one in this department", symbol: "person.text.rectangle")
        }
      }
    }
    .toolbar {
      if departments.count > 1 {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Picker("Department", selection: $department) {
              Text("All departments").tag(String?.none)
              ForEach(departments, id: \.self) { name in
                Text(name).tag(String?.some(name))
              }
            }
          } label: {
            Label("Department", systemImage: "line.3.horizontal.decrease.circle")
          }
        }
      }
    }
    .sensoryFeedback(Haptics.pick, trigger: department)
    .refreshable { await business.refreshCompany() }
  }

  private static func departments(_ employees: [Employee]) -> [String] {
    let names = Set(employees.map { $0.department.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  private static func matches(_ employee: Employee, _ text: String) -> Bool {
    guard !text.isEmpty else { return true }
    let arabic: String = employee.nameAr ?? ""
    let fields: [String] = [employee.name, arabic, employee.jobTitle, employee.department, employee.number]
    return fields.contains(where: { $0.localizedStandardContains(text) })
  }
}

/// Said instead of the people screens to the roles that may not see them.
struct PeopleLockedView: View {
  init() {}

  var body: some View {
    EmptyState(
      title: "Not available for your role", symbol: "lock",
      message: "People and payroll are for the owner, admins and accountants.")
  }
}

/// One employee in the list: name, job and department, and a mark when a
/// paper expires within 30 days.
private struct BusinessEmployeeRow: View {
  let employee: Employee
  let today: LocalDate

  var body: some View {
    let name = BusinessUI.name(employee)
    let job = [employee.jobTitle, employee.department]
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
      .joined(separator: " · ")
    let next = employee.expiries.first
    let days = next?.daysLeft(today: today)
    HStack(spacing: 12) {
      AvatarView(initials: BusinessUI.initials(name), id: employee.id, size: 38)
      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .font(.body.weight(.semibold))
          .lineLimit(1)
        if !job.isEmpty {
          Text(job)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 8)
      if let days, days <= 30, employee.isActive {
        Image(systemName: days < 0 ? "exclamationmark.triangle.fill" : "calendar.badge.exclamationmark")
          .foregroundStyle(BusinessUI.expiryTint(days))
          .accessibilityLabel(days < 0 ? Text("A paper has expired") : Text("A paper expires soon"))
      }
      if !employee.number.isEmpty {
        Text(employee.number)
          .font(.caption)
          .foregroundStyle(.tertiary)
          .monospacedDigit()
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}
