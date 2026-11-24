import MahamKit
import SwiftUI

/// One employee, for the owner, admins and accountants only: their job, how
/// to reach them, and when their papers expire.
struct EmployeeDetailView: View {
  @Environment(AppModel.self) private var model
  let employee: Employee

  init(employee: Employee) {
    self.employee = employee
  }

  var body: some View {
    let business = model.business
    Group {
      if business.role.seesPeople {
        content(business.employees.first(where: { $0.id == employee.id }) ?? employee, business: business)
      } else {
        PeopleLockedView()
      }
    }
    .mahamScreen()
    .navigationTitle(business.role.seesPeople ? BusinessUI.name(employee) : String(localized: "People"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func content(_ person: Employee, business: BusinessStore) -> some View {
    let today = business.today
    let papers = Self.papers(of: person, documents: business.documents)
    let actions = BusinessContactActions.person(phone: person.phone, email: person.email)
    return ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header(person)
        if !actions.isEmpty {
          BusinessContactActions(actions: actions)
        }
        details(person)
        GlassSection("Document expiry dates", symbol: "calendar.badge.clock") {
          if papers.isEmpty {
            Text("No expiry dates recorded.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          } else {
            VStack(spacing: 10) {
              ForEach(papers) { paper in
                BusinessExpiryRow(expiry: paper, today: today, showsOwner: false)
                if paper.id != papers.last?.id {
                  Divider()
                }
              }
            }
          }
        }
      }
      .padding(.horizontal)
      .padding(.bottom, 32)
      .frame(maxWidth: 760)
      .frame(maxWidth: .infinity)
    }
    .refreshable { await business.refreshCompany() }
  }

  private func header(_ person: Employee) -> some View {
    let name = BusinessUI.name(person)
    let other = BusinessUI.otherName(person.name, person.nameAr)
    let job = person.jobTitle.trimmingCharacters(in: .whitespaces)
    return HStack(alignment: .top, spacing: 14) {
      AvatarView(initials: BusinessUI.initials(name), id: person.id, size: 56)
      VStack(alignment: .leading, spacing: 4) {
        Text(name)
          .font(.title2.bold())
          .lineLimit(3)
        if let other {
          Text(other)
            .font(.headline)
            .foregroundStyle(.secondary)
        }
        if !job.isEmpty {
          Text(job)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        if !person.isActive {
          Text("Left the company")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.14), in: .capsule)
        }
      }
      Spacer(minLength: 0)
    }
    .glassCard()
  }

  @ViewBuilder
  private func details(_ person: Employee) -> some View {
    let job = person.jobTitle.trimmingCharacters(in: .whitespaces)
    let department = person.department.trimmingCharacters(in: .whitespaces)
    let nationality = BusinessUI.nationality(person.nationality)
    let number = person.number.trimmingCharacters(in: .whitespaces)
    let phone = person.phone.trimmingCharacters(in: .whitespaces)
    let email = person.email.trimmingCharacters(in: .whitespaces)
    if !(job.isEmpty && department.isEmpty && nationality.isEmpty && number.isEmpty && phone.isEmpty && email.isEmpty) {
      GlassSection("Details", symbol: "person.text.rectangle") {
        VStack(spacing: 8) {
          if !job.isEmpty { BusinessInfoRow(title: "Job title", value: job) }
          if !department.isEmpty { BusinessInfoRow(title: "Department", value: department) }
          if !nationality.isEmpty { BusinessInfoRow(title: "Nationality", value: nationality) }
          if !number.isEmpty { BusinessInfoRow(title: "Employee number", value: number) }
          if !phone.isEmpty { BusinessInfoRow(title: "Phone", value: phone) }
          if !email.isEmpty { BusinessInfoRow(title: "Email", value: email) }
        }
      }
    }
  }

  /// The employee's own papers and the register's documents filed under
  /// them, soonest first.
  static func papers(of person: Employee, documents: [ComplianceDocument]) -> [Expiry] {
    let register = documents.compactMap { doc -> Expiry? in
      guard doc.employeeId == person.id, let date = doc.expiryDate else { return nil }
      return Expiry(id: doc.id, title: doc.title.isEmpty ? doc.type : doc.title, owner: doc.ownerName, date: date)
    }
    return (person.expiries + register).sorted { $0.date < $1.date }
  }
}
