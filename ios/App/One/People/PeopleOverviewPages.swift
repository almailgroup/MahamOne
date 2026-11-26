import MahamKit
import SwiftUI
import UIKit

// Maham People's home (`/people`), the staff directory (`/people/directory`)
// and the employees of the companies searched (`/people/all`):
// src/apps/people/pages/overview/{index,directory,all-companies}.tsx.

// MARK: - Overview

/// `/people`: the headcount, who is away today, what comes up in the next
/// month and the departments. No salaries: those stay in Payroll.
struct PeOverviewPage: View {
  var body: some View {
    PeGate { PeOverviewView() }
  }
}

/// What the overview shows, worked out from the records.
@MainActor
private struct PeOverviewData {
  var byId: [String: PeEmployee] = [:]
  var contacts: [PeContact] = []
  var away: [PeLeaveRecord] = []
  var groups: [PeDepartmentCount] = []
  var upcoming: [PeMilestone] = []
  var joiners = 0
  var papers = 0
  var reasons: [PeLeaveReason] = []
  var lettersOn = false
  var toPrint = 0

  static func make(_ one: OneData) -> PeOverviewData {
    let today = PeDates.today
    let employees = one.peEmployees
    let people = one.pePeopleSettings
    let awayMap = PeDirectory.awayOn(one.peLeaveRecords, today)
    let byId = Dictionary(employees.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let contacts = PeDirectory.contacts(employees, away: Set(awayMap.keys), list: people.departments)
    let entries = PeCompliance.registerEntries(
      employees: employees, documents: one.records(.complianceDocuments), days: people.reminderDays,
      byType: people.reminderDaysByType)
    var papers = 0
    for entry in entries {
      guard let id = entry.employeeId, byId[id] != nil else { continue }
      if PeCompliance.expiry(entry.expiryDate, entry.reminderDays, on: today).status != .valid { papers += 1 }
    }
    var data = PeOverviewData()
    data.byId = byId
    data.contacts = contacts
    data.away = awayMap.values.filter { byId[$0.employeeId] != nil }.sorted { $0.end < $1.end }
    data.groups = PeDirectory.departments(contacts)
    data.upcoming = PeDirectory.comingUp(employees, today: today)
    data.joiners = PeDirectory.newJoiners(employees, today: today).count
    data.papers = papers
    data.reasons = one.pePayrollSettings.leaveReasons
    data.lettersOn = people.letters
    data.toPrint =
      people.letters
      ? one.records(.employeeLetters).filter { $0.str("status") == "issued" && $0.text("printedAt") == nil }.count : 0
    return data
  }
}

private struct PeOverviewView: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let data = PeOverviewData.make(one)
    let biggest = data.groups.first?.count ?? 0
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(t("Overview"), description: subtitle) {
        WebButton(t("Directory"), icon: .idCard, variant: .outline) { router.push(.directory) }
        WebButton(t("Add employee"), icon: .userPlus, haptic: .press) { router.push(.newEmployee) }
      }
      VStack(alignment: .leading, spacing: 20) {
        VStack(spacing: 12) {
          PePair {
            PeStat(label: t("Employees"), value: format.count(data.contacts.count), icon: .usersRound) {
              router.push(.employees)
            }
          } second: {
            PeStat(label: t("Away today"), value: format.count(data.away.count), icon: .plane) {
              router.push(.leave)
            }
          }
          PePair {
            PeStat(label: t("Joined in the last 30 days"), value: format.count(data.joiners), icon: .userPlus) {
              router.push(.employees)
            }
          } second: {
            PeStat(
              label: t("Papers to renew"), value: format.count(data.papers), icon: .fileWarning,
              tone: data.papers > 0 ? .amber(700) : nil
            ) {
              router.push(.complianceDocuments)
            }
          }
        }
        awayCard(data, format: format)
        comingUpCard(data, format: format)
        departmentsCard(data, biggest: biggest, format: format)
        VStack(spacing: 12) {
          PeShortcut(icon: .wallet, label: t("Pay runs")) { router.push(.payroll) }
          PeShortcut(icon: .calendarDays, label: t("Leave")) { router.push(.leave) }
          PeShortcut(icon: .handCoins, label: t("Staff loans")) { router.push(.loans) }
          if data.lettersOn {
            PeShortcut(icon: .mails, label: lettersLabel(data.toPrint)) { router.push(.letters) }
          }
        }
      }
    }
  }

  private var subtitle: String {
    let app = SuiteManifests.people.title(arabic: LanguageStore.shared.isArabic)
    let company = model.one.company.map { localName($0) } ?? ShellCompany.name(model.business)
    return company.isEmpty ? app : app + " · " + company
  }

  private func lettersLabel(_ count: Int) -> String {
    count > 0 ? tp(count, "Letters: {count} to print", "Letters: {count} to print") : t("Letters")
  }

  private func awayCard(_ data: PeOverviewData, format: CompanyFormat) -> some View {
    Card {
      CardHeader(t("Away today"))
      if data.away.isEmpty {
        PeCardNote(t("Everyone is in today."))
      } else {
        PeRows {
          ForEach(data.away) { record in
            let name = data.byId[record.employeeId]?.displayName ?? ""
            let leave = PeLeave.label(record, data.reasons)
            let until = t("Until {date}", ["date": format.date(record.end)])
            PePersonRow(name: name, detail: leave + " · " + until) {
              router.push(.employee(id: record.employeeId))
            }
          }
        }
      }
    }
  }

  private func comingUpCard(_ data: PeOverviewData, format: CompanyFormat) -> some View {
    Card {
      CardHeader(t("Coming up"), description: tp(30, "In the next {count} day", "In the next {count} days"))
      if data.upcoming.isEmpty {
        PeCardNote(t("Nothing in the next month."))
      } else {
        PeRows {
          ForEach(data.upcoming.prefix(8)) { milestone in
            let name = data.byId[milestone.employeeId]?.displayName ?? ""
            PePersonRow(name: name, detail: milestone.label + " · " + format.date(milestone.date)) {
              router.push(.employee(id: milestone.employeeId))
            }
          }
        }
      }
    }
  }

  private func departmentsCard(_ data: PeOverviewData, biggest: Int, format: CompanyFormat) -> some View {
    Card {
      CardHeader(t("Departments"))
      if data.groups.isEmpty {
        PeCardNote(t("No employees yet"))
      } else {
        VStack(spacing: 10) {
          ForEach(data.groups.prefix(8)) { group in
            PeDepartmentBar(
              name: group.displayName.isEmpty ? t("No department") : group.displayName,
              count: format.count(group.count), share: Double(group.count) / Double(max(1, biggest))
            ) {
              router.push(.directory)
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
      }
    }
  }
}

/// Someone in a card's list: their initials, name and a line about them.
struct PePersonRow: View {
  let name: String
  let detail: String
  var image: UIImage?
  let action: () -> Void
  @Environment(\.palette) private var palette

  var body: some View {
    Button {
      Haptics.play(.tap)
      action()
    } label: {
      HStack(spacing: 12) {
        PeAvatar(name: name, size: 36, image: image)
        VStack(alignment: .leading, spacing: 2) {
          Text(name)
            .font(.web(14, .medium))
            .foregroundStyle(palette.slate(800))
            .lineLimit(1)
          Text(detail)
            .font(.web(12))
            .foregroundStyle(palette.slate(500))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 8)
      .frame(minHeight: 52)
      .contentShape(Rectangle())
    }
    .buttonStyle(PressedFill(radius: 0, color: .slate(50)))
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }
}

/// A department with its headcount and a bar of its share of the biggest.
private struct PeDepartmentBar: View {
  let name: String
  let count: String
  let share: Double
  let action: () -> Void
  @Environment(\.palette) private var palette

  var body: some View {
    Button {
      Haptics.play(.tap)
      action()
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(name)
            .font(.web(14))
            .foregroundStyle(palette.slate(700))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
          Text(count)
            .font(.web(14, tabular: true))
            .foregroundStyle(palette.slate(500))
        }
        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule().fill(palette.slate(100))
            Capsule()
              .fill(palette[.emerald(500)])
              .frame(width: proxy.size.width * max(0.04, min(1, share)))
          }
        }
        .frame(height: 6)
      }
      .frame(minHeight: 36)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// A shortcut to a page of Payroll (`Shortcut`).
private struct PeShortcut: View {
  let icon: Icon
  let label: String
  let action: () -> Void
  @Environment(\.palette) private var palette

  var body: some View {
    Button {
      Haptics.play(.tap)
      action()
    } label: {
      Card {
        HStack(spacing: 12) {
          IconView(icon, size: 16).foregroundStyle(palette[.emerald(700)])
          Text(label)
            .font(.web(14, .medium))
            .foregroundStyle(palette.slate(700))
            .frame(maxWidth: .infinity, alignment: .leading)
          IconView(.arrowRight, size: 16).foregroundStyle(palette.slate(400))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
      }
    }
    .buttonStyle(PressedScale())
  }
}

// MARK: - Directory

/// `/people/directory`: who works here and how to reach them, a card per person.
struct PeDirectoryPage: View {
  var body: some View {
    PeGate { PeDirectoryView() }
  }
}

private struct PeDirectoryView: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @State private var query = ""
  @State private var department = "*"

  var body: some View {
    let one = model.one
    let away = Set(PeDirectory.awayOn(one.peLeaveRecords, PeDates.today).keys)
    let contacts = PeDirectory.contacts(one.peEmployees, away: away, list: one.pePeopleSettings.departments)
    let groups = PeDirectory.departments(contacts)
    let shown = PeDirectory.find(contacts, query: query, department: department == "*" ? nil : department)
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(t("Directory"), description: tp(contacts.count, "{count} employee", "{count} employees"))
      if contacts.isEmpty {
        Card {
          WebEmptyState(icon: .usersRound, title: t("No employees yet")) {
            WebButton(t("Add employee"), haptic: .press) { router.push(.newEmployee) }
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 8) {
          TextInput(text: $query, placeholder: t("Name, job, phone…"), leadingIcon: .search)
          if groups.count > 1 {
            Select(selection: $department, options: departmentOptions(groups))
          }
        }
        .padding(.bottom, 16)
        if shown.isEmpty {
          Card { WebEmptyState(icon: .search, title: t("No one matches your search")) }
        } else {
          VStack(spacing: 12) {
            ForEach(shown) { contact in
              PeContactCard(contact: contact)
            }
          }
        }
      }
    }
  }

  private func departmentOptions(_ groups: [PeDepartmentCount]) -> [SelectOption<String>] {
    var options = [SelectOption("*", t("All departments"))]
    for group in groups {
      let name = group.displayName.isEmpty ? t("No department") : group.displayName
      options.append(SelectOption(group.name, "\(name) (\(group.count))"))
    }
    return options
  }
}

/// A person's contact card: their job and department, phone and email.
private struct PeContactCard: View {
  let contact: PeContact
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    Card {
      HStack(alignment: .top, spacing: 12) {
        PeAvatar(name: contact.displayName, size: 48)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 8) {
            Button {
              Haptics.play(.tap)
              router.push(.employee(id: contact.id))
            } label: {
              Text(contact.displayName)
                .font(.web(14, .semibold))
                .foregroundStyle(palette.slate(900))
                .lineLimit(1)
            }
            .buttonStyle(.plain)
            if contact.onLeave { Badge(t("On leave"), tone: .amber) }
          }
          Text(jobLine)
            .font(.web(14))
            .foregroundStyle(palette.slate(600))
            .lineLimit(1)
          VStack(alignment: .leading, spacing: 0) {
            if let url = PeContactLinks.phone(contact.phone) {
              PeContactLink(icon: .phone, text: contact.phone, url: url)
            }
            if let url = PeContactLinks.email(contact.email) {
              PeContactLink(icon: .mail, text: contact.email, url: url)
            }
          }
          .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(16)
    }
  }

  private var jobLine: String {
    let job = localName(contact.jobTitle, contact.jobTitleAr)
    let department = localName(contact.department, contact.departmentAr)
    let parts = [job, department].filter { !$0.isEmpty }
    return parts.isEmpty ? "—" : parts.joined(separator: " · ")
  }
}

/// A phone number or an email address that opens.
struct PeContactLink: View {
  let icon: Icon
  let text: String
  let url: URL
  @Environment(\.palette) private var palette

  var body: some View {
    Link(destination: url) {
      HStack(spacing: 6) {
        IconView(icon, size: 14)
        Text(verbatim: text)
          .font(.web(14))
          .lineLimit(1)
          .environment(\.layoutDirection, .leftToRight)
      }
      .foregroundStyle(palette.primary(700))
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
  }
}

// MARK: - All companies

/// `/people/all`: the employees of the companies searched, found from one
/// place. Only the company open on this iPhone has its records here; no
/// pay, IBAN or Civil ID shows.
struct PeAllCompaniesPage: View {
  var body: some View {
    PeGate { PeAllCompaniesView() }
  }
}

private struct PeAllCompaniesView: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var view = "current"
  @State private var query = ""
  @State private var category = ""
  @State private var department = ""
  @State private var shownCount = 50

  var body: some View {
    let employees = model.one.peEmployees
    let current = employees.filter(\.isCurrent).count
    let departments = Array(Set(employees.map(\.department).filter { !$0.isEmpty })).sorted {
      $0.localizedCompare($1) == .orderedAscending
    }
    let shown = filtered(employees)
    let company = model.one.company.map { localName($0) } ?? ShellCompany.name(model.business)
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(
        t("All companies"),
        description: tp(1, "Employees of {count} company on this device", "Employees of {count} companies on this device"))
      ListCard {
        Segmented(
          selection: $view,
          options: [
            SegmentOption("current", t("Current employees"), count: current),
            SegmentOption("left", t("Left"), count: employees.count - current),
            SegmentOption("all", t("All"), count: employees.count),
          ])
        TextInput(text: $query, placeholder: t("Search employees…"), leadingIcon: .search)
        Select(selection: $category, options: categoryOptions)
        if !departments.isEmpty {
          Select(selection: $department, options: departmentOptions(departments))
        }
      } rows: {
        if shown.isEmpty {
          PeCardNote(employees.isEmpty ? t("No employees yet") : t("No employees match."), centered: true)
        } else {
          ForEach(shown.prefix(shownCount)) { e in
            PeLineRow(
              title: e.displayName, detail: [e.number, e.job].filter { !$0.isEmpty }.joined(separator: " · ")
            ) {
              PeAvatar(name: e.displayName, size: 40)
            } trailing: {
              Text(company)
                .font(.web(14))
                .foregroundStyle(palette.slate(600))
                .lineLimit(1)
              if e.status != "active" {
                Badge(PePeople.statusLabel(e.status), tone: e.status == "left" ? .slate : .blue)
              }
            } action: {
              router.push(.employee(id: e.id))
            }
          }
          if shown.count > shownCount {
            ListShowMore(remaining: shown.count - shownCount) { shownCount += 50 }
          }
        }
      }
    }
    .onChange(of: query) { _, _ in shownCount = 50 }
    .onChange(of: view) { _, _ in shownCount = 50 }
  }

  private var categoryOptions: [SelectOption<String>] {
    var options = [SelectOption("", t("All categories"))]
    for filter in PePeople.categoryFilters {
      options.append(SelectOption(filter, PePeople.categoryLabel(filter)))
    }
    return options
  }

  private func departmentOptions(_ names: [String]) -> [SelectOption<String>] {
    var options = [SelectOption("", t("All departments"))]
    for name in names { options.append(SelectOption(name, name)) }
    return options
  }

  /// `findEmployees`: the view, category and department chosen, and every word typed.
  private func filtered(_ employees: [PeEmployee]) -> [PeEmployee] {
    let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
    return employees.filter { e in
      if !department.isEmpty && e.department != department { return false }
      if !category.isEmpty && !PePeople.inCategory(e, category) { return false }
      if view == "current" && !e.isCurrent { return false }
      if view == "left" && e.isCurrent { return false }
      if words.isEmpty { return true }
      let text = [e.name, e.nameAr ?? "", e.number, e.jobTitle, e.jobTitleAr ?? "", e.department, e.email]
        .joined(separator: " ")
      let numbers = [PeDirectory.digits(e.phone), PeDirectory.digits(e.civilId)].filter { !$0.isEmpty }
      return words.allSatisfy { word in
        if text.matches(word) { return true }
        let typed = PeDirectory.digits(word)
        return !typed.isEmpty && numbers.contains { $0.contains(typed) }
      }
    }
    .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
  }
}
