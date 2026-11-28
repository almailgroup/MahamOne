import MahamKit
import SwiftUI
import UIKit

// The employees list (`/employees`), an employee's page (`/employees/:id`)
// and their final settlement (`/employees/:id/settlement`):
// src/apps/people/pages/people/{list,detail}.tsx, payroll/settlement.tsx,
// and the tabs of src/features/payroll/employee-tabs.tsx.

// MARK: - The list

/// `/employees`: the staff, their papers, the headcount and the Kuwaiti share.
struct PeEmployeesPage: View {
  var body: some View {
    PeGate { PeEmployeesView() }
  }
}

private struct PeEmployeesView: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var view = "current"
  @State private var category = ""
  @State private var department = ""
  @State private var expiringOnly = false
  @State private var driversOnly = false
  @State private var query = ""
  @State private var shownCount = 50

  var body: some View {
    let one = model.one
    let format = one.format
    let employees = one.peEmployees
    let people = one.pePeopleSettings
    let today = PeDates.today
    let entries = PeCompliance.registerEntries(
      employees: employees, documents: one.records(.complianceDocuments), days: people.reminderDays,
      byType: people.reminderDaysByType)
    let worst = PeCompliance.worstDocuments(entries, on: today)
    let licences: [String: (gap: PeLicenceGap, documentId: String?)] =
      people.drivingLicences
      ? PeCompliance.missingLicences(
        employees: employees, documents: one.records(.complianceDocuments), vehicles: one.records(.vehicles),
        on: today) : [:]
    let summary = PePeople.workforce(employees)
    let current = employees.filter(\.isCurrent)
    let withExpiring = current.filter { worst[$0.id] != nil }.count
    let shown = filtered(employees, worst: worst, licences: licences, list: people.departments)
    let departmentChoices = departmentOptions(employees, people.departments)
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(t("Employees"), description: t("Your staff, their papers and end-of-service estimates.")) {
        if PwKinds.can(PwKinds.employee) {
          WebButton(t("New employee"), icon: .plus, haptic: .press) { router.push(.newEmployee) }
        }
      }
      if employees.isEmpty {
        Card {
          WebEmptyState(
            icon: .idCard, title: t("No employees yet"),
            description: t(
              "Add your staff to track Civil IDs, residencies and work permits, and to estimate end-of-service pay.")
          ) {
            if PwKinds.can(PwKinds.employee) {
              WebButton(t("New employee"), icon: .plus, haptic: .press) { router.push(.newEmployee) }
            }
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 24) {
          VStack(spacing: 16) {
            PeHeadcountCard(summary: summary, format: format)
            PeKuwaitiShareCard(share: summary.kuwaitiShare, target: people.kuwaitizationTarget, format: format)
            PePapersCard(count: withExpiring, format: format)
          }
          ListCard {
            Segmented(
              selection: $view,
              options: [
                SegmentOption("current", t("Current employees"), count: current.count),
                SegmentOption("left", t("Left"), count: employees.count - current.count),
                SegmentOption("all", t("All"), count: employees.count),
              ])
            Select(selection: $category, options: categoryOptions)
            if departmentChoices.count > 1 {
              Select(selection: $department, options: departmentChoices)
            }
            FlowLayout(spacing: 8, lineSpacing: 8) {
              WebButton(
                t("Documents expiring"), icon: .fileWarning, variant: expiringOnly ? .subtle : .outline, size: .sm
              ) {
                expiringOnly.toggle()
              }
              if people.drivingLicences {
                WebButton(
                  t("Drivers without a valid licence"), icon: .car, variant: driversOnly ? .subtle : .outline,
                  size: .sm
                ) {
                  driversOnly.toggle()
                }
              }
            }
            TextInput(text: $query, placeholder: t("Search employees…"), leadingIcon: .search)
          } rows: {
            if shown.isEmpty {
              PeCardNote(t("No employees match."), centered: true)
            } else {
              ForEach(shown.prefix(shownCount)) { e in
                let detail = [e.number, e.job].filter { !$0.isEmpty }.joined(separator: " · ")
                PeLineRow(title: e.displayName, detail: detail) {
                  PeAvatar(name: e.displayName, size: 44)
                } trailing: {
                  PeDocumentCell(employee: e, worst: worst[e.id], licence: licences[e.id]?.gap)
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

  /// The list's departments and those employees have, by name in the language.
  private func departmentOptions(_ employees: [PeEmployee], _ list: [PeDepartment]) -> [SelectOption<String>] {
    var names = Set(employees.map(\.department).filter { !$0.isEmpty })
    for d in list where !d.archived { names.insert(d.name) }
    let labelled = names.map { (name: $0, label: PePeople.departmentLabel(list, $0)) }
      .sorted { $0.label.localizedCompare($1.label) == .orderedAscending }
    var options = [SelectOption("", t("All departments"))]
    for item in labelled { options.append(SelectOption(item.name, item.label)) }
    return options
  }

  private func filtered(
    _ employees: [PeEmployee], worst: [String: (PeRegisterEntry, PeExpiry)],
    licences: [String: (gap: PeLicenceGap, documentId: String?)], list: [PeDepartment]
  ) -> [PeEmployee] {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    return employees.filter { e in
      if view == "left" && e.isCurrent { return false }
      if view == "current" && !e.isCurrent { return false }
      if !category.isEmpty && !PePeople.inCategory(e, category) { return false }
      if !department.isEmpty && e.department != department { return false }
      if expiringOnly && worst[e.id] == nil { return false }
      if driversOnly && licences[e.id] == nil { return false }
      if q.isEmpty { return true }
      let arabicDepartment = PePeople.findDepartment(list, e.department)?.nameAr ?? ""
      let text = [
        e.name, e.nameAr ?? "", e.number, e.civilId, e.jobTitle, e.jobTitleAr ?? "", e.department, arabicDepartment,
        e.phone, e.email,
      ].joined(separator: " ").lowercased()
      return text.contains(q)
    }
    .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
  }
}

/// The most urgent paper of an employee, or the driving licence they lack.
private struct PeDocumentCell: View {
  let employee: PeEmployee
  let worst: (PeRegisterEntry, PeExpiry)?
  let licence: PeLicenceGap?
  @Environment(\.palette) private var palette

  var body: some View {
    let noLicence = (licence == .missing || licence == .undated) && worst?.1.status != .expired
    if noLicence {
      Badge(licence == .undated ? t("No expiry date") : t("Missing"), tone: licence == .undated ? .amber : .red)
      Text(t("Driving licence")).font(.web(12)).foregroundStyle(palette.slate(500))
    } else if let worst, employee.isCurrent {
      PeExpiryBadge(info: worst.1)
      Text(worst.0.displayTitle).font(.web(12)).foregroundStyle(palette.slate(500)).lineLimit(1)
    } else {
      Text(verbatim: "—").font(.web(12)).foregroundStyle(palette.slate(500))
    }
  }
}

/// Headcount, with the count of each category.
private struct PeHeadcountCard: View {
  let summary: PePeople.Workforce
  let format: CompanyFormat
  @Environment(\.palette) private var palette

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: 8) {
        Text(t("Headcount")).font(.web(14, .medium)).foregroundStyle(palette.slate(500))
        Text(format.count(summary.headcount))
          .font(.web(24, .semibold, tabular: true))
          .foregroundStyle(palette.slate(900))
        FlowLayout(spacing: 12, lineSpacing: 4) {
          ForEach(PePeople.categoryFilters.filter { summary.count($0) > 0 }, id: \.self) { filter in
            HStack(spacing: 4) {
              Text(PePeople.categoryLabel(filter) + ":")
              Text(format.count(summary.count(filter)))
                .font(.web(12, .medium, tabular: true))
                .foregroundStyle(palette.slate(700))
            }
            .font(.web(12, tabular: true))
            .foregroundStyle(palette.slate(500))
          }
        }
      }
      .padding(20)
    }
  }
}

/// The Kuwaiti share of the staff against the company's target.
private struct PeKuwaitiShareCard: View {
  let share: Double?
  let target: Double?
  let format: CompanyFormat
  @Environment(\.palette) private var palette

  var body: some View {
    let below = target != nil && share != nil && (share ?? 0) < (target ?? 0)
    Card {
      VStack(alignment: .leading, spacing: 8) {
        Text(t("Kuwaiti staff")).font(.web(14, .medium)).foregroundStyle(palette.slate(500))
        Text(share.map { format.percent($0) } ?? "—")
          .font(.web(24, .semibold, tabular: true))
          .foregroundStyle(below ? palette[.amber(700)] : palette.slate(900))
        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule().fill(palette.slate(100))
            Capsule()
              .fill(below ? palette[.amber(500)] : palette[.emerald(500)])
              .frame(width: proxy.size.width * min(100, share ?? 0) / 100)
            if let target {
              Rectangle()
                .fill(palette.slate(700))
                .frame(width: 2)
                .padding(.leading, max(0, proxy.size.width * min(100, target) / 100 - 2))
            }
          }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .padding(.top, 4)
        Text(note(below: below))
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
      }
      .padding(20)
    }
  }

  private func note(below: Bool) -> String {
    guard let target else { return t("Without domestic workers. Set a target to track it.") }
    let vars = ["target": format.percent(target)]
    return below ? t("Below the {target} target.", vars) : t("Meets the {target} target.", vars)
  }
}

/// Employees with a paper expiring or expired, and the way to the register.
private struct PePapersCard: View {
  let count: Int
  let format: CompanyFormat
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: 8) {
        Text(t("Papers to renew")).font(.web(14, .medium)).foregroundStyle(palette.slate(500))
        Text(format.count(count))
          .font(.web(24, .semibold, tabular: true))
          .foregroundStyle(count > 0 ? palette[.amber(700)] : palette.slate(900))
        Text(count > 0 ? t("Employees with a document expiring or expired.") : t("Every employee’s papers are valid."))
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
        Button {
          Haptics.play(.tap)
          router.push(.complianceDocuments)
        } label: {
          Text(t("Open the register"))
            .font(.web(12, .medium))
            .foregroundStyle(palette.primary(700))
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .padding(20)
    }
  }
}

// MARK: - An employee

/// `/employees/:id`: the employee's papers, end-of-service estimate, details
/// and pay, with tabs for leave, loans, end of service, letters and items.
struct PeEmployeePage: View {
  let id: String

  var body: some View {
    PeGate { PeEmployeeView(id: id) }
  }
}

private struct PeEmployeeView: View {
  let id: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var tab = "overview"

  var body: some View {
    let one = model.one
    let employee = one.peEmployee(id)
    WebPage(spacing: 16, refresh: { [model] in await model.one.sync() }) {
      if let employee {
        PeEmployeeHeader(employee: employee)
        Segmented(selection: $tab, options: tabs)
        switch tab {
        case "leave": PeLeaveTab(employee: employee)
        case "loans": PeLoansTab(employee: employee)
        case "eos": PeEndOfServiceTab(employee: employee)
        case "letters": PeEmployeeLettersTab(employee: employee)
        case "issued": PeIssuedItemsTab(employee: employee)
        default: PeEmployeeOverview(employee: employee)
        }
      } else {
        PeNotFound(message: t("This employee could not be found."), back: t("Back to employees"))
      }
    }
  }

  private var tabs: [SegmentOption<String>] {
    [
      SegmentOption("overview", t("Overview")), SegmentOption("leave", t("Leave")),
      SegmentOption("loans", t("Loans")), SegmentOption("eos", t("End of service")),
      SegmentOption("letters", t("Letters")), SegmentOption("issued", t("Issued items")),
    ]
  }
}

/// The breadcrumb, the photo, the name with the status and category, and who they are.
private struct PeEmployeeHeader: View {
  let employee: PeEmployee
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let departments = model.one.pePeopleSettings.departments
    let line = [employee.number, employee.job, PePeople.departmentLabel(departments, employee.department)]
      .filter { !$0.isEmpty }.joined(separator: " · ")
    VStack(alignment: .leading, spacing: 8) {
      Button {
        Haptics.play(.tap)
        router.back()
      } label: {
        HStack(spacing: 4) {
          IconView(.chevronLeft, size: 14)
          Text(t("Employees"))
        }
        .font(.web(14))
        .foregroundStyle(palette.slate(500))
        .frame(minHeight: 32)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      HStack(alignment: .center, spacing: 16) {
        PeAvatar(name: employee.displayName, size: 72, image: PePhotos.image(model.one, id: employee.photoId))
        VStack(alignment: .leading, spacing: 6) {
          Text(employee.displayName)
            .webText(.pageTitle)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .accessibilityAddTraits(.isHeader)
          FlowLayout(spacing: 6, lineSpacing: 6) {
            Badge(PePeople.statusLabel(employee.status), tone: PePeople.statusTone(employee.status))
            Badge(PePeople.categoryLabel(employee), tone: .gray)
          }
        }
      }
      if !line.isEmpty {
        Text(line).font(.web(14)).foregroundStyle(palette.slate(500))
      }
      if let arabic = employee.nameAr {
        Text(LanguageStore.shared.isArabic ? employee.name : arabic)
          .font(.web(14))
          .foregroundStyle(palette.slate(500))
      }
      if PwKinds.can(PwKinds.employee) {
        WebButton(t("Edit"), icon: .pencil, variant: .outline, size: .sm) {
          router.push(.editEmployee(id: employee.id))
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, 8)
  }
}

/// The Overview tab: papers, the end-of-service estimate, the personnel
/// file, renewals, details, pay and notes.
private struct PeEmployeeOverview: View {
  let employee: PeEmployee
  @Environment(AppModel.self) private var model

  var body: some View {
    let people = model.one.pePeopleSettings
    VStack(alignment: .leading, spacing: 24) {
      PeDocumentsCard(employee: employee)
      PeEosiCard(employee: employee, divisor: people.eosDailyDivisor)
      PePersonnelFileCard(employee: employee)
      PeRenewalsCard(employee: employee)
      PeDetailsCard(employee: employee)
      PePayCard(employee: employee)
      TextCard(title: t("Notes"), text: employee.notes)
    }
  }
}

/// The employee's papers: those on their record and those in the register.
private struct PeDocumentsCard: View {
  let employee: PeEmployee
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let people = one.pePeopleSettings
    let today = PeDates.today
    let records = one.records(.complianceDocuments).filter { $0.str("employeeId") == employee.id }
    let entries = entriesFor(records, people: people)
    let missing: (gap: PeLicenceGap, documentId: String?)? =
      people.drivingLicences
      ? PeCompliance.missingLicences(
        employees: [employee], documents: records, vehicles: one.records(.vehicles), on: today)[employee.id] : nil
    let licenceMissing = missing?.gap == .missing
    let undated: String? = missing?.gap == .undated ? missing?.documentId : nil
    Card {
      CardHeader(
        t("Documents"),
        description: employee.isCurrent
          ? t("Reminders appear in Compliance before each expiry date.")
          : t("Not tracked any more: this employee has left."))
      if entries.isEmpty && !licenceMissing {
        PeCardNote(t("No documents yet. Add the Civil ID, passport and residency on the employee’s form."), centered: true)
      } else {
        PeRows {
          if licenceMissing {
            PeLineRow(
              title: t("Driving licence missing"), detail: t("Drives for work, but no driving licence is on file."),
              trailing: { Badge(t("Missing"), tone: .red) })
          }
          ForEach(entries) { entry in
            PeLineRow(
              title: entry.displayTitle, detail: detail(entry, format: format),
              trailing: {
                if employee.isCurrent, let recordId = entry.recordId, recordId == undated {
                  Badge(t("No expiry date"), tone: .amber)
                } else if employee.isCurrent {
                  PeExpiryBadge(info: PeCompliance.expiry(entry.expiryDate, entry.reminderDays, on: today))
                }
              })
          }
        }
      }
    }
  }

  private func entriesFor(_ records: [JSONValue], people: PePeopleSettings) -> [PeRegisterEntry] {
    var entries = PeCompliance.employeeDocuments(
      employee, days: people.reminderDays, byType: people.reminderDaysByType)
    for record in records where !record.flag("archived") {
      entries.append(PeCompliance.recordEntry(record, days: people.reminderDays, byType: people.reminderDaysByType))
    }
    return entries
  }

  private func detail(_ entry: PeRegisterEntry, format: CompanyFormat) -> String {
    var parts: [String] = []
    if !entry.number.isEmpty { parts.append(entry.number) }
    if !entry.licenceClass.isEmpty { parts.append(t("Class {class}", ["class": entry.licenceClass])) }
    if let expiry = entry.expiryDate { parts.append(t("Expires {date}", ["date": format.date(expiry)])) }
    return parts.isEmpty ? t("No expiry date") : parts.joined(separator: " · ")
  }
}

/// "End-of-service estimate today": what the employee would get if the
/// employer ended the contract and if they resigned (art. 51 and 53).
struct PeEosiCard: View {
  let employee: PeEmployee
  let divisor: Double
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette
  @State private var open = false

  var body: some View {
    let left = employee.status == "left"
    let title = left ? t("End of service at leaving") : t("End-of-service estimate today")
    if !PePeople.underLabourLaw(employee.category) {
      PeCard(title) {
        Text(
          t(
            "Domestic workers are covered by Law 68/2015, which gives one month’s wage for each year of service. Check with your lawyer."
          )
        )
        .font(.web(14))
        .foregroundStyle(palette.slate(600))
      }
    } else if employee.hireDate == nil || employee.basicSalary <= 0 {
      PeCard(title) {
        Text(t("Add the hire date and the basic salary to see an estimate."))
          .font(.web(14))
          .foregroundStyle(palette.slate(500))
      }
    } else {
      estimate(title: title, left: left)
    }
  }

  private func estimate(title: String, left: Bool) -> some View {
    let one = model.one
    let format = one.format
    let p = one.pePrecision
    let until = left ? (employee.leavingDate ?? PeDates.today) : PeDates.today
    let years = PeEosi.serviceYears(employee.hireDate ?? until, until)
    let wage = PeEosi.wage(employee.basicSalary, employee.allowances, p)
    let results = outcomes(years: years, wage: wage, left: left, p: p)
    let main = results[0].1
    return PeCard(title, description: t("Labour Law 6/2010, articles 51 and 53. An estimate, not legal advice.")) {
      if left && employee.leavingReason == nil {
        Text(t("The reason for leaving isn’t recorded."))
          .font(.web(14))
          .foregroundStyle(palette[.amber(800)])
      }
      ForEach(0..<results.count, id: \.self) { index in
        PeOutcomeBox(label: results[index].0, result: results[index].1, format: format)
      }
      VStack(alignment: .leading, spacing: 8) {
        PeFigureLine(label: t("Years of service"), value: format.quantity(PeMoney.jsRound(years * 100) / 100))
        PeFigureLine(label: t("Monthly wage"), value: format.money(wage))
        PeFigureLine(
          label: t("Daily wage (÷ {days})", ["days": format.quantity(main.dailyDivisor)]),
          value: format.money(main.dailyWage))
      }
      Rectangle().fill(palette.slate(100)).frame(height: 1)
      Button {
        Haptics.play(.tap)
        withAnimation(WebMotion.standard) { open.toggle() }
      } label: {
        HStack {
          Text(t("How it is worked out")).font(.web(14, .medium)).foregroundStyle(palette.slate(700))
          Spacer()
          IconView(.chevronDown, size: 16)
            .foregroundStyle(palette.slate(500))
            .rotationEffect(.degrees(open ? 180 : 0))
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if open {
        PeAmountList(rows: breakdown(main, format: format))
        Text(explanation)
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
      }
    }
  }

  /// One amount for a known reason for leaving; otherwise both ways it could end.
  private func outcomes(years: Double, wage: Double, left: Bool, p: Int) -> [(String?, PeEosi.Result)] {
    func result(_ reason: PeEosi.Reason) -> PeEosi.Result {
      PeEosi.calculate(
        payBasis: employee.payBasis, monthlyWage: wage, years: years, reason: reason, dailyDivisor: divisor, precision: p)
    }
    if left, let reason = employee.leavingReason, reason != "other" {
      return [(nil, result(PePeople.eosiReason(reason)))]
    }
    return [(t("If you end the contract"), result(.termination)), (t("If they resign"), result(.resignation))]
  }

  private func breakdown(_ result: PeEosi.Result, format: CompanyFormat) -> [PeAmount] {
    let years = { (n: Double) in format.quantity(PeMoney.jsRound(n * 100) / 100) }
    var rows = PeAmountRows()
    rows.add(
      t(
        "First {years} years × {days} days",
        ["years": years(result.first.years), "days": format.quantity(result.first.daysPerYear ?? 0)]),
      format.money(result.first.amount))
    if result.later.monthsPerYear != nil {
      rows.add(t("Later {years} years × one month", ["years": years(result.later.years)]), format.money(result.later.amount))
    } else {
      rows.add(
        t(
          "Later {years} years × {days} days",
          ["years": years(result.later.years), "days": format.quantity(result.later.daysPerYear ?? 0)]),
        format.money(result.later.amount))
    }
    if result.capApplied { rows.add(t("Limited to the cap"), format.money(result.cap)) }
    if !result.fullShare {
      rows.add(t("Share on resignation: {share}", ["share": result.shareText]), format.money(result.afterShare))
    }
    return rows.rows
  }

  private var explanation: String {
    let rule =
      employee.payBasis == "monthly"
      ? t(
        "15 days’ wage for each of the first 5 years, then a month’s wage for each year, at most 18 months’ wage. Part years count pro rata."
      )
      : t(
        "10 days’ wage for each of the first 5 years, then 15 days for each year, at most 12 months’ wage. Part years count pro rata."
      )
    return rule + " "
      + t(
        "The daily wage is the monthly wage divided by the working days in a month; amounts are rounded to the fils at the end."
      )
  }
}

/// One way the employment could end, and what it pays.
private struct PeOutcomeBox: View {
  let label: String?
  let result: PeEosi.Result
  let format: CompanyFormat
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let label {
        Text(label).font(.web(14)).foregroundStyle(palette.slate(600))
      }
      Text(format.money(result.payable))
        .font(.web(24, .semibold, tabular: true))
        .foregroundStyle(palette.slate(900))
      if !result.fullShare {
        Text(
          result.share.numerator == 0
            ? t("Nothing before 3 years of service.")
            : t("{share} of the full amount.", ["share": result.shareText])
        )
        .font(.web(12))
        .foregroundStyle(palette.slate(500))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(palette.slate(50), in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
  }
}

/// A small figure: its label over its value.
struct PeFigureLine: View {
  let label: String
  let value: String
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.web(14)).foregroundStyle(palette.slate(500))
      Text(value).font(.web(14, .medium, tabular: true)).foregroundStyle(palette.slate(900))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// The personnel file: copies of the contract, work permit and Civil ID (art. 80).
private struct PePersonnelFileCard: View {
  let employee: PeEmployee
  @Environment(AppModel.self) private var model

  var body: some View {
    let format = model.one.format
    let files = model.one.records(.attachments)
      .filter { $0.str("ownerId") == employee.id && $0.rid != employee.photoId }
      .sorted { $0.str("createdAt") > $1.str("createdAt") }
    Card {
      CardHeader(
        t("Personnel file"),
        description: t("Keep copies of the contract, work permit and Civil ID here (Labour Law art. 80)."))
      if files.isEmpty {
        PeCardNote(t("No files yet."))
      } else {
        PeRows {
          ForEach(files.map(Rec.init)) { file in
            PeLineRow(title: file.raw.str("name"), detail: format.date(String(file.raw.str("createdAt").prefix(10))))
          }
        }
      }
    }
  }
}

/// The renewals of the employee's papers, the latest first.
private struct PeRenewalsCard: View {
  let employee: PeEmployee
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let format = model.one.format
    let history = model.one.records(.renewals)
      .filter { $0.str("employeeId") == employee.id }
      .sorted { $0.str("renewedOn") > $1.str("renewedOn") }
    if !history.isEmpty {
      PeListCard(t("Renewals")) {
        ForEach(history.map(Rec.init)) { record in
          let renewal = record.raw
          PeLineRow(
            title: PeCompliance.typeLabel(renewal.str("type")),
            detail: t(
              "Renewed on {date}, valid until {expiry}",
              ["date": format.date(renewal.text("renewedOn")), "expiry": format.date(renewal.text("newExpiry"))]),
            trailing: {
              if renewal.num("fee") > 0 {
                Text(format.money(renewal.num("fee")))
                  .font(.web(14, tabular: true))
                  .foregroundStyle(palette.slate(700))
              }
            })
        }
      }
    }
  }
}

/// Who the employee is: nationality, papers' numbers, dates, contract and contact.
private struct PeDetailsCard: View {
  let employee: PeEmployee
  @Environment(AppModel.self) private var model

  var body: some View {
    InfoCard(t("Details"), rows: rows(model.one.format))
  }

  private func rows(_ format: CompanyFormat) -> [InfoRow] {
    let e = employee
    let dash = "—"
    var rows: [InfoRow] = []
    let country = Geo.countryName(e.nationality, locale: format.locale.identifier)
    rows.append(InfoRow(t("Nationality"), country.isEmpty ? dash : country))
    if let gender = e.gender { rows.append(InfoRow(t("Gender"), PePeople.genderLabel(gender))) }
    if let birth = e.birthDate { rows.append(InfoRow(t("Date of birth"), format.date(birth))) }
    rows.append(InfoRow(t("Civil ID number"), e.civilId.isEmpty ? dash : e.civilId, tabular: true))
    if PePeople.needsResidency(e) {
      let article = PePeople.residencyArticleLabel(e.residencyArticle)
      rows.append(InfoRow(t("Residency article"), article.isEmpty ? dash : article))
    }
    if !e.pifssNumber.isEmpty { rows.append(InfoRow(t("PIFSS number"), e.pifssNumber, tabular: true)) }
    rows.append(InfoRow(t("Hire date"), e.hireDate.map { format.date($0) } ?? dash))
    if let hire = e.hireDate {
      let years = PeEosi.serviceYears(hire, e.leavingDate ?? PeDates.today)
      rows.append(InfoRow(t("Years of service"), format.quantity(PeMoney.jsRound(years * 100) / 100), tabular: true))
    }
    if let probation = e.probationEnd { rows.append(InfoRow(t("Probation ends"), format.date(probation))) }
    let contract =
      e.contractType == "fixed" && e.contractEnd != nil
      ? t("Fixed term until {date}", ["date": format.date(e.contractEnd)]) : PePeople.contractLabel(e.contractType)
    rows.append(InfoRow(t("Contract"), contract))
    if e.status == "left" {
      var left: [String] = []
      if let date = e.leavingDate { left.append(format.date(date)) }
      if let reason = e.leavingReason { left.append(PePeople.leavingReasonLabel(reason)) }
      rows.append(InfoRow(t("Left on"), left.isEmpty ? dash : left.joined(separator: " · ")))
    }
    rows.append(InfoRow(t("Mobile"), e.phone.isEmpty ? dash : e.phone, tabular: true))
    rows.append(InfoRow(t("Email"), e.email.isEmpty ? dash : e.email))
    return rows
  }
}

/// The pay: basis, basic salary, allowances, the monthly total, the bank and
/// the account number masked until asked for.
private struct PePayCard: View {
  let employee: PeEmployee
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette
  @State private var showNumber = false

  var body: some View {
    let one = model.one
    let format = one.format
    let e = employee
    let bank = Kuwait.banks.first { $0.code == e.bank } ?? Kuwait.bankFromIban(e.iban)
    let bankName = bank.map { $0.name[LanguageStore.shared.isArabic ? .ar : .en] } ?? e.bank
    Card {
      CardHeader(t("Pay"))
      VStack(spacing: 0) {
        PeValueLine(label: t("Pay basis"), value: PePeople.payBasisLabel(e.payBasis), first: true)
        PeValueLine(label: t("Basic salary"), value: format.money(e.basicSalary), tabular: true)
        ForEach(e.allowances) { allowance in
          PeValueLine(label: allowance.displayName, value: format.money(allowance.amount), tabular: true)
        }
        PeValueLine(
          label: t("Monthly pay"), value: format.money(PePeople.monthlyPay(e, one.pePrecision)), strong: true,
          tabular: true)
        if bank != nil || !e.iban.isEmpty {
          PeValueLine(
            label: t("Bank"), value: bankName.isEmpty ? "—" : bankName,
            below: e.iban.isEmpty ? nil : Kuwait.formatIban(e.iban))
        }
        if !e.accountNumber.isEmpty {
          HStack(spacing: 12) {
            Text(t("Account or salary card number"))
              .font(.web(14))
              .foregroundStyle(palette.slate(500))
              .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: showNumber ? e.accountNumber : Format.maskNumber(e.accountNumber))
              .font(.system(size: 12, design: .monospaced))
              .foregroundStyle(palette.slate(700))
              .environment(\.layoutDirection, .leftToRight)
            WebButton(
              icon: showNumber ? .eyeOff : .eye,
              label: showNumber ? t("Hide the number") : t("Show the whole number"), size: .iconSmall
            ) {
              showNumber.toggle()
            }
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 4)
          .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
        }
      }
      .padding(.vertical, 4)
    }
  }
}

/// A label and its value on a card's line, with an optional line under the value.
struct PeValueLine: View {
  let label: String
  let value: String
  var below: String?
  var strong = false
  var tabular = false
  var first = false
  @Environment(\.palette) private var palette

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(label)
        .font(.web(14, strong ? .medium : .regular))
        .foregroundStyle(strong ? palette.slate(700) : palette.slate(500))
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 2) {
        Text(value)
          .font(.web(14, strong ? .semibold : .regular, tabular: tabular))
          .foregroundStyle(palette.slate(900))
          .multilineTextAlignment(.trailing)
          .textSelection(.enabled)
        if let below {
          Text(verbatim: below)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(palette.slate(500))
            .environment(\.layoutDirection, .leftToRight)
            .textSelection(.enabled)
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 11)
    .overlay(alignment: .top) {
      if !first { Rectangle().fill(palette.slate(100)).frame(height: 1) }
    }
  }
}

// MARK: - The Leave tab

private struct PeLeaveTab: View {
  let employee: PeEmployee
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let settings = one.pePayrollSettings
    let records = one.peLeaveRecords.filter { $0.employeeId == employee.id }
    let today = PeDates.today
    let year = Int(today.prefix(4)) ?? 2026
    let dayOff = PeDayOff(company: one.company)
    let policy = settings.leavePolicy ?? .law
    let balance = PeLeave.employeeBalance(employee, records, on: today, settings: settings)
    let days = PeLeave.annualDaysOn(
      today, policy: policy, entitlement: employee.annualLeaveDays, entitlementFrom: employee.annualLeaveDaysFrom)
    let ownDays = (employee.annualLeaveDays ?? 0) > 0 && (employee.annualLeaveDaysFrom.map { $0 <= today } ?? true)
    let yearly = ["days": format.quantity(days), "monthly": format.quantity(PeMoney.round(days / 12, 2))]
    let sick = PeLeave.sickDaysByTier(records, year: year, dayOff: dayOff)
    let reasons = reasonRows(settings, records: records)
    VStack(alignment: .leading, spacing: 24) {
      if employee.isCurrent {
        FlowLayout(spacing: 8) {
          PwRecordLeaveButton(employeeId: employee.id)
          PwRecordLeaveButton(employeeId: employee.id, balance: true)
        }
      }
      PeCard(
        t("Annual leave"),
        description: ownDays
          ? t("{days} days a year in their contract, {monthly} days for each month of service.", yearly)
          : t("{days} days a year, {monthly} days for each month of service (art. 70).", yearly)
      ) {
        Text(tp(balance.balance, "{count} day", "{count} days"))
          .font(.web(30, .semibold, tabular: true))
          .foregroundStyle(palette.slate(900))
        PeAmountList(rows: balanceRows(balance, format: format))
        if balance.pausedMonths > 0 {
          Text(
            tp(
              balance.pausedMonths,
              "{count} month of service with more than 15 days of unpaid leave earned no leave.",
              "{count} months of service with more than 15 days of unpaid leave earned no leave.")
          )
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
        }
        if let brought = employee.leaveOpening {
          PeBroughtForward(brought: brought, format: format, employeeId: employee.id)
        }
        if let eligible = balance.eligibleFrom, today < eligible {
          Text(firstLeaveText(format.date(eligible), months: policy.firstYearMonths))
            .font(.web(12))
            .foregroundStyle(palette.slate(500))
        }
      }
      PeCard(
        t("Sick leave in {year}", ["year": String(year)]), description: t("Paid in tiers over the year (art. 69).")
      ) {
        PeAmountList(rows: sickRows(sick, format: format))
      }
      if !reasons.isEmpty {
        PeListCard(
          t("The company’s leave reasons in {year}", ["year": String(year)]),
          description: t("Days taken this year, and the days added for reasons that have them.")
        ) {
          ForEach(reasons) { reason in
            PeLineRow(title: reason.displayName, detail: PeLeave.reasonPayLabel(reason), trailing: {
              Text(reasonTaken(reason, records: records, year: year, dayOff: dayOff, policy: policy, format: format))
                .font(.web(14, tabular: true))
                .foregroundStyle(palette.slate(700))
              if reason.pay == "balance" {
                Text(
                  t(
                    "Balance {days} days",
                    ["days": format.quantity(PeLeave.reasonBalance(records, reasonId: reason.id, on: today).balance)])
                )
                .font(.web(14, .medium, tabular: true))
                .foregroundStyle(palette.slate(900))
              }
            })
          }
        }
      }
      PeLeaveRecordsCard(records: records, reasons: settings.leaveReasons)
    }
  }

  /// The company's reasons this employee has leave of, or could have.
  private func reasonRows(_ settings: PePayrollSettings, records: [PeLeaveRecord]) -> [PeLeaveReason] {
    let used = Set(records.compactMap(\.reasonId))
    return settings.leaveReasons.filter { reason in
      if used.contains(reason.id) { return true }
      guard settings.leaveReasonsOn else { return false }
      let offered = !PeLeave.reasonsFor([reason], category: employee.category).isEmpty
      return offered && (reason.pay == "balance" || reason.maxDaysPerYear != nil)
    }
  }

  private func reasonTaken(
    _ reason: PeLeaveReason, records: [PeLeaveRecord], year: Int, dayOff: PeDayOff, policy: PeLeavePolicy,
    format: CompanyFormat
  ) -> String {
    let taken = PeLeave.reasonDaysInYear(records, reasonId: reason.id, year: year, dayOff: dayOff, policy: policy)
    if let max = reason.maxDaysPerYear {
      return t("{used} of {days} days", ["used": format.quantity(taken), "days": format.quantity(max)])
    }
    return tp(taken, "{count} day taken", "{count} days taken")
  }

  private func balanceRows(_ balance: PeLeaveBalance, format: CompanyFormat) -> [PeAmount] {
    var rows = PeAmountRows()
    if balance.opening != 0 {
      rows.add(
        t("Opening balance on {date}", ["date": format.date(balance.from)]), format.quantity(balance.opening))
    }
    rows.add(
      balance.from.map { t("Earned since {date}", ["date": format.date($0)]) } ?? t("Earned"),
      format.quantity(balance.accrued))
    if balance.adjusted != 0 { rows.add(t("Balance adjustments"), format.quantity(balance.adjusted)) }
    rows.add(t("Taken"), "−" + format.quantity(balance.taken))
    if balance.forfeited != 0 { rows.add(t("Over the carry-forward cap"), "−" + format.quantity(balance.forfeited)) }
    return rows.rows
  }

  private func sickRows(_ sick: [(percent: Double, days: Int)], format: CompanyFormat) -> [PeAmount] {
    var rows = PeAmountRows()
    for (index, tier) in PeLeave.sickTiers.enumerated() {
      let used = index < sick.count ? sick[index].days : 0
      let label =
        tier.percent == 100
        ? t("Full pay")
        : tier.percent == 0 ? t("Without pay") : t("{percent} pay", ["percent": format.percent(tier.percent)])
      rows.add(
        label, t("{used} of {days} days", ["used": format.count(used), "days": format.count(tier.days)]))
    }
    return rows.rows
  }

  private func firstLeaveText(_ date: String, months: Int) -> String {
    if months == 9 {
      return t("Annual leave can be taken from {date}, after nine months of service.", ["date": date])
    }
    return tp(
      months, "Annual leave can be taken from {date}, after {count} month of service.",
      "Annual leave can be taken from {date}, after {count} months of service.", ["date": date])
  }
}

/// The leave the employee brought forward, and whether anyone has checked it.
private struct PeBroughtForward: View {
  let brought: PeLeaveOpening
  let format: CompanyFormat
  /// Whose it is, for changing or confirming it on this iPhone.
  var employeeId: String?
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(t("Leave brought forward"))
          .font(.web(14, .medium))
          .foregroundStyle(palette.slate(900))
          .frame(maxWidth: .infinity, alignment: .leading)
        Badge(brought.confirmed ? t("Confirmed") : t("Not confirmed"), tone: brought.confirmed ? .green : .amber)
      }
      Text(
        t(
          "{days} days on {date}. Leave counts from this date.",
          ["days": format.quantity(brought.days), "date": format.date(brought.date)])
      )
      .font(.web(14))
      .foregroundStyle(palette.slate(600))
      if !brought.confirmed {
        Text(
          t(
            "Imported with 0 days. Enter what they had left on that day, from your records before, or confirm it."
          )
        )
        .font(.web(12))
        .foregroundStyle(palette[.amber(800)])
      }
      if let employeeId {
        PwLeaveOpeningButtons(employeeId: employeeId)
      }
    }
    .padding(12)
    .border(palette.slate(200), in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
  }
}

/// Every leave record of the employee, the latest first.
private struct PeLeaveRecordsCard: View {
  let records: [PeLeaveRecord]
  let reasons: [PeLeaveReason]
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let format = model.one.format
    let list = records.sorted { a, b in a.start != b.start ? a.start > b.start : a.createdAt > b.createdAt }
    Card {
      CardHeader(t("Leave records"))
      if list.isEmpty {
        PeCardNote(t("No leave recorded yet."), centered: true)
      } else {
        PeRows {
          ForEach(list) { record in
            PeLineRow(
              title: title(record), detail: detail(record, format: format),
              trailing: {
                if record.status == "cancelled" { Badge(t("Cancelled"), tone: .slate) }
                Text(tp(record.days, "{count} day", "{count} days"))
                  .font(.web(14, tabular: true))
                  .foregroundStyle(record.status == "cancelled" ? palette.slate(500) : palette.slate(700))
                  .strikethrough(record.status == "cancelled")
                if record.status == "approved" { PwCancelLeaveButton(recordId: record.id) }
              })
          }
        }
      }
    }
  }

  private func title(_ record: PeLeaveRecord) -> String {
    switch record.kind {
    case "opening":
      return t("Opening balance")
    case "adjustment":
      return PeLeave.reasonOf(record, reasons) != nil
        ? t("Days added: {reason}", ["reason": PeLeave.label(record, reasons)]) : t("Balance adjustment")
    default:
      return PeLeave.label(record, reasons)
    }
  }

  private func detail(_ record: PeLeaveRecord, format: CompanyFormat) -> String {
    let dates =
      record.kind == "leave" && record.start != record.end && !record.end.isEmpty
      ? t("{start} to {end}", ["start": format.date(record.start), "end": format.date(record.end)])
      : format.date(record.start)
    return record.notes.isEmpty ? dates : dates + " · " + record.notes
  }
}

// MARK: - The Loans tab

private struct PeLoansTab: View {
  let employee: PeEmployee
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let p = one.pePrecision
    let runs = one.pePayRuns
    let settlements = one.peSettlements
    let loans = one.peStaffLoans.filter { $0.employeeId == employee.id }.sorted { $0.date > $1.date }
    if employee.isCurrent {
      PwNewLoanButton(employeeId: employee.id)
    }
    if loans.isEmpty {
      Card {
        WebEmptyState(
          icon: .handCoins, title: t("No loans or advances"),
          description: t("Loans are interest-free and recovered from pay in monthly instalments."))
      }
    } else {
      PeListCard(t("Loans and advances")) {
        ForEach(loans) { loan in
          let balance = PePayroll.loanBalance(loan, runs: runs, settlements: settlements, p)
          let recovered = PeMoney.fromMinor(
            PePayroll.recoveredMinor(loan.id, runs: runs, settlements: settlements, p), p)
          PeLineRow(
            title: loanTitle(loan, format: format), detail: loanDetail(loan, format: format),
            detail2: loan.status == "active" ? progress(loan, balance: balance, recovered: recovered, format: format) : nil,
            trailing: {
              PeLoanBadge(loan: loan, balance: balance)
              if loan.status == "active" && recovered == 0 && loan.payRunId == nil {
                PwCancelLoanButton(loanId: loan.id)
              }
            })
        }
      }
    }
  }

  private func loanTitle(_ loan: PeStaffLoan, format: CompanyFormat) -> String {
    if loan.payRunId != nil {
      return t(
        "PIFSS share of {amount} owed from the {month} pay",
        ["amount": format.money(loan.amount), "month": PePayroll.formatPeriod(PeDates.period(loan.date), format)])
    }
    return t(
      "Loan of {amount} paid on {date}", ["amount": format.money(loan.amount), "date": format.date(loan.date)])
  }

  private func loanDetail(_ loan: PeStaffLoan, format: CompanyFormat) -> String {
    let line = t(
      "{amount} a month from {month}",
      ["amount": format.money(loan.instalment), "month": PePayroll.formatPeriod(loan.firstPeriod, format)])
    return loan.notes.isEmpty ? line : line + " · " + loan.notes
  }

  private func progress(_ loan: PeStaffLoan, balance: Double, recovered: Double, format: CompanyFormat) -> String {
    let p = model.one.pePrecision
    let line = t(
      "Recovered {recovered}, left {balance}",
      ["recovered": format.money(recovered), "balance": format.money(balance)])
    guard balance > 0 else { return line }
    let left = Int(
      (Double(PeMoney.minor(balance, p)) / Double(max(1, PeMoney.minor(loan.instalment, p)))).rounded(.up))
    return line + " · " + tp(left, "{count} instalment to go", "{count} instalments to go")
  }
}

/// Cancelled, repaid or active.
struct PeLoanBadge: View {
  let loan: PeStaffLoan
  let balance: Double

  var body: some View {
    if loan.status == "cancelled" {
      Badge(t("Cancelled"), tone: .slate)
    } else if balance == 0 {
      Badge(t("Repaid"), tone: .green)
    } else {
      Badge(t("Active"), tone: .blue)
    }
  }
}

// MARK: - The End of service tab

private struct PeEndOfServiceTab: View {
  let employee: PeEmployee
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let live = one.peSettlements.first { $0.employeeId == employee.id && $0.status != "reversed" }
    let withProvisions = one.pePayRuns.first { $0.status != "draft" && $0.provisions != nil }
    let share = withProvisions?.provisions?.first { $0.employeeId == employee.id }
    VStack(alignment: .leading, spacing: 24) {
      PeCard(
        t("Final settlement"),
        description: t(
          "Indemnity, notice pay, unused leave and the last salary, less loans, with the settlement sheet and its entry."
        )
      ) {
        if let live {
          VStack(alignment: .leading, spacing: 4) {
            Text(format.money(live.net))
              .font(.web(24, .semibold, tabular: true))
              .foregroundStyle(palette.slate(900))
            Text(settlementState(live, format: format))
              .font(.web(14))
              .foregroundStyle(palette.slate(500))
          }
          WebButton(t("Open the settlement"), variant: .outline, size: .sm) {
            router.push(.settlement(employeeId: employee.id))
          }
        } else {
          WebButton(t("Start the final settlement"), icon: .userMinus, size: .sm) {
            router.push(.settlement(employeeId: employee.id))
          }
        }
      }
      if let run = withProvisions {
        PeCard(
          t("Provisions in the books"),
          description: t(
            "As at {date}, from the {month} pay run.",
            ["date": format.date(run.date), "month": PePayroll.formatPeriod(run.period, format)])
        ) {
          PeAmountList(rows: provisionRows(share, format: format))
          Button {
            Haptics.play(.tap)
            router.push(.payRun(id: run.id))
          } label: {
            Text(t("Open the pay run"))
              .font(.web(12, .medium))
              .foregroundStyle(palette.primary(700))
              .frame(minHeight: 32)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      PeEosiCard(employee: employee, divisor: one.pePeopleSettings.eosDailyDivisor)
    }
  }

  private func settlementState(_ live: PeSettlementRecord, format: CompanyFormat) -> String {
    if live.status == "paid", let paid = live.paidOn {
      return t("Paid on {date}", ["date": format.date(paid)])
    }
    return t("Posted on {date}, not paid yet", ["date": format.date(live.leavingDate)])
  }

  private func provisionRows(_ share: PeProvisionLine?, format: CompanyFormat) -> [PeAmount] {
    var rows = PeAmountRows()
    rows.add(t("End-of-service indemnity"), format.money(share?.eos ?? 0))
    rows.add(
      t("Leave salary ({days} days)", ["days": format.quantity(share?.leaveDays ?? 0)]),
      format.money(share?.leave ?? 0))
    return rows.rows
  }
}

// MARK: - The Letters tab

private struct PeEmployeeLettersTab: View {
  let employee: PeEmployee
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let one = model.one
    let letters = PeLetterList.sorted(one.records(.employeeLetters).filter { $0.str("employeeId") == employee.id })
    if !one.pePeopleSettings.letters {
      Card {
        WebEmptyState(
          icon: .mails, title: t("Employee letters are off"), description: t("Turn them on in People → Letters first.")
        ) {
          WebButton(t("Letters"), variant: .outline) { router.push(.letters) }
        }
      }
    } else if letters.isEmpty {
      Card {
        WebEmptyState(
          icon: .mails, title: t("No letters yet"),
          description: t(
            "Salary, experience and employment certificates, warning letters and no objection certificates, filled from their record."
          )
        ) {
          if PwKinds.can(PwKinds.letters) {
            WebButton(t("New letter"), icon: .filePlus2, haptic: .press) { router.push(.newLetter) }
          }
        }
      }
    } else {
      PeLetterList(letters: letters, showEmployee: false, title: t("Letters"))
    }
  }
}

// MARK: - The Issued items tab

private struct PeIssuedItemsTab: View {
  let employee: PeEmployee
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let issues = one.records(.stockIssues)
      .filter { $0.obj("recipient")?.str("employeeId") == employee.id }
      .sorted { a, b in
        a.str("date") != b.str("date") ? a.str("date") > b.str("date") : a.str("createdAt") > b.str("createdAt")
      }
    let held = heldItems(issues)
    if issues.isEmpty {
      Card {
        WebEmptyState(
          icon: .shirt, title: t("No items issued yet"),
          description: t("Uniforms and other items issued to this employee show here."))
      }
    } else {
      VStack(alignment: .leading, spacing: 24) {
        Card {
          CardHeader(t("Items held"), description: t("Everything issued to them and confirmed, item by item."))
          if held.isEmpty {
            PeCardNote(t("Nothing confirmed yet."))
          } else {
            PeRows {
              ForEach(held) { item in
                PeLineRow(
                  title: item.name, detail: item.unit,
                  trailing: {
                    Text(format.quantity(item.quantity))
                      .font(.web(14, .medium, tabular: true))
                      .foregroundStyle(palette.slate(900))
                  })
              }
            }
          }
        }
        PeListCard(t("Issued items")) {
          ForEach(issues.map(Rec.init)) { record in
            let issue = record.raw
            PeLineRow(
              title: format.date(issue.text("date")), detail: issue.text("number") ?? "—",
              detail2: itemsText(issue, format: format)
            ) {
              if issue.str("status") == "void" {
                Badge(t("Void"), tone: .gray)
              } else {
                Badge(t("Issued"), tone: .green)
              }
            } action: {
              router.push(.stockIssue(id: issue.rid))
            }
          }
        }
      }
    }
  }

  private func itemsText(_ issue: JSONValue, format: CompanyFormat) -> String {
    let warehouse = issue.text("warehouseId").flatMap { model.one.record(.warehouses, $0) }.map { localName($0) }
    var lines: [String] = []
    for line in issue.list("lines") {
      lines.append(format.quantity(line.num("quantity")) + " " + localName(line))
    }
    let items = lines.joined(separator: ", ")
    guard let warehouse, !warehouse.isEmpty else { return items }
    return items + " · " + warehouse
  }

  /// What they hold: the items of every issue kept and not void.
  private func heldItems(_ issues: [JSONValue]) -> [PeHeldItem] {
    var held: [String: PeHeldItem] = [:]
    for issue in issues where issue.str("status") != "void" {
      for line in issue.list("lines") {
        let key = line.str("productId")
        let before = held[key]?.quantity ?? 0
        held[key] = PeHeldItem(
          id: key, name: localName(line), unit: line.str("unit"),
          quantity: Money.toNumber(PeMoney.dec(before) + PeMoney.dec(line.num("quantity"))))
      }
    }
    return held.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
  }
}

/// An item an employee holds, and how many.
private struct PeHeldItem: Identifiable {
  let id: String
  let name: String
  let unit: String
  let quantity: Double
}

// MARK: - The final settlement

/// `/employees/:id/settlement`: the posted settlement, or what one would
/// come to, worked out from the records as the web's form starts.
struct PeSettlementPage: View {
  let employeeId: String

  var body: some View {
    PeGate { PeSettlementView(employeeId: employeeId) }
  }
}

private struct PeSettlementView: View {
  let employeeId: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  /// The reason looked at, when the record has none: nothing is saved.
  @State private var chosenReason = ""

  var body: some View {
    let one = model.one
    let employee = one.peEmployee(employeeId)
    let live = one.peSettlements.first { $0.employeeId == employeeId && $0.status != "reversed" }
    WebPage(spacing: 0, refresh: { [model] in await model.one.sync() }) {
      if let employee {
        if let live {
          PePostedSettlement(employee: employee, settlement: live)
          // Paid from the bank, its payment undone, or reversed, on this iPhone.
          PwSettlementActions(employeeId: employeeId)
            .padding(.top, 16)
        } else if PwKinds.can(PwKinds.settlement) {
          PageHeader(
            t("Final settlement"),
            description: t(
              "Everything due on leaving, worked out from the records. Check each amount before posting."),
            breadcrumb: employee.displayName, onBreadcrumb: { router.back() })
          PwSettlementActions(employeeId: employeeId)
        } else {
          estimate(employee)
        }
      } else {
        PeNotFound(message: t("This employee could not be found."), back: t("Back to employees"))
      }
    }
  }

  private func knownReason(_ e: PeEmployee) -> String {
    guard let reason = e.leavingReason, reason != "other" else { return "" }
    return reason
  }

  @ViewBuilder
  private func estimate(_ e: PeEmployee) -> some View {
    let missing = PePayroll.missingText(e)
    let reason = chosenReason.isEmpty ? knownReason(e) : chosenReason
    PageHeader(
      t("Final settlement"),
      description: t(
        "Everything due on leaving, worked out from the records. Check each amount before posting."),
      breadcrumb: e.displayName, onBreadcrumb: { router.back() })
    if let missing {
      Card {
        Text(missing)
          .font(.web(14))
          .foregroundStyle(palette[.red(700)])
          .padding(24)
      }
    } else {
      PeSettlementEstimate(employee: e, reason: reason, chosenReason: $chosenReason)
    }
  }
}

/// What a settlement would come to on the leaving date, for the reason chosen.
private struct PeSettlementEstimate: View {
  let employee: PeEmployee
  let reason: String
  @Binding var chosenReason: String
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let p = one.pePrecision
    let leavingDate = employee.leavingDate ?? PeDates.today
    let setup = PePayroll.setup(
      employee, leavingDate: leavingDate, settings: one.pePayrollSettings, people: one.pePeopleSettings,
      leave: one.peLeaveRecords, loans: one.peStaffLoans, runs: one.pePayRuns, settlements: one.peSettlements, p)
    VStack(alignment: .leading, spacing: 24) {
      PeCard(t("Leaving")) {
        PeFigureLine(label: t("Leaving date"), value: format.date(leavingDate))
        Field(t("Reason"), error: reason.isEmpty ? t("Choose the reason for leaving.") : nil) {
          Select(
            selection: Binding(get: { reason }, set: { chosenReason = $0 }), options: reasonOptions,
            placeholder: t("Choose a reason"))
        }
      }
      if reason.isEmpty {
        Card {
          Text(
            t(
              "Choose the reason for leaving first: it decides the end-of-service indemnity and the notice pay."
            )
          )
          .font(.web(14))
          .foregroundStyle(palette.slate(600))
          .padding(24)
        }
      } else {
        figures(setup: setup, leavingDate: leavingDate, format: format, p: p)
      }
    }
  }

  private var reasonOptions: [SelectOption<String>] {
    var options = [SelectOption("", t("Choose a reason"))]
    for value in PePeople.leavingReasons { options.append(SelectOption(value, PePeople.leavingReasonLabel(value))) }
    return options
  }

  @ViewBuilder
  private func figures(setup: PeSettlementSetup, leavingDate: String, format: CompanyFormat, p: Int) -> some View {
    let form = PePayroll.defaults(employee, leavingDate: leavingDate, reason: reason, setup: setup, p)
    let amounts = PePayroll.compute(employee, form: form, setup: setup, p)
    let month = PePayroll.formatPeriod(PeDates.period(leavingDate), format)
    PeCard(
      t("End-of-service indemnity"),
      description: amounts.eosi != nil
        ? t("Labour Law 6/2010, articles 51 and 53. An estimate, not legal advice.")
        : t("Domestic workers: one month’s wage for each year of service (Law 68/2015).")
    ) {
      PeFigureLine(label: t("Years of service"), value: format.quantity(PeMoney.jsRound(amounts.years * 100) / 100))
      PeFigureLine(label: t("Monthly wage"), value: format.money(amounts.eosWage))
      if let eosi = amounts.eosi {
        PeFigureLine(label: t("Share paid"), value: eosi.shareText)
      }
      Text(format.money(amounts.indemnity))
        .font(.web(18, .semibold, tabular: true))
        .foregroundStyle(palette.slate(900))
    }
    PeCard(t("Notice, leave and last salary")) {
      PeFigureLine(label: t("Notice pay (months)"), value: format.quantity(form.noticeMonths))
      PeHint(
        t(
          "When the employer ends an unlimited contract without notice: 3 months for monthly-paid staff, 1 for others (art. 44)."
        ))
      PeFigureLine(label: t("Unused leave (days)"), value: format.quantity(form.leaveDays))
      PeHint(
        t(
          "Balance on the leaving date: {days} days. Paid out on leaving (art. 73).",
          ["days": format.quantity(setup.leave.balance)]))
      PeFigureLine(label: t("Last salary (days)"), value: format.quantity(form.lastSalaryDays))
      PeHint(
        setup.paidInRun != nil
          ? t("The {month} pay run already pays this month.", ["month": month])
          : t("Days worked in {month}.", ["month": month]))
    }
    if !setup.loans.isEmpty {
      PeCard(t("Deductions")) {
        ForEach(0..<setup.loans.count, id: \.self) { index in
          let item = setup.loans[index]
          let recovery = form.loans.first { $0.loanId == item.loan.id }?.amount ?? 0
          PeFigureLine(
            label: t(
              "Loan of {amount} from {date}",
              ["amount": format.money(item.loan.amount), "date": format.date(item.loan.date)]),
            value: format.money(recovery))
          PeHint(t("Left on the loan: {amount}.", ["amount": format.money(item.balance)]))
        }
      }
    }
    PeCard(t("Settlement")) {
      PeAmountList(rows: PeSettlementRows.rows(amounts.breakdown(form), format: format))
      if setup.provisions.eos > 0 || setup.provisions.leave > 0 {
        PeHint(
          t(
            "Releases {eos} of the end-of-service provision and {leave} of the leave provision; the difference is expensed.",
            ["eos": format.money(setup.provisions.eos), "leave": format.money(setup.provisions.leave)]))
      }
      if amounts.net < 0 {
        Text(
          t("The deductions are more than what is due. Lower the loan recovery or other deductions.")
        )
        .font(.web(14))
        .foregroundStyle(palette[.red(600)])
      }
    }
  }
}

/// A hint under a figure (12pt slate-500).
struct PeHint: View {
  let text: String
  @Environment(\.palette) private var palette

  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .font(.web(12))
      .foregroundStyle(palette.slate(500))
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// What a settlement pays and deducts, as its breakdown shows it.
struct PeSettlementFigures {
  let indemnity: Double
  let noticeMonths: Double
  let noticePay: Double
  let leaveDays: Double
  let leavePay: Double
  let lastSalary: PeSettlementSalary?
  let loanRecovery: Double
  let otherDeductions: Double
  let net: Double
}

extension PeSettlementAmounts {
  func breakdown(_ form: PeSettlementForm) -> PeSettlementFigures {
    PeSettlementFigures(
      indemnity: indemnity, noticeMonths: form.noticeMonths, noticePay: noticePay, leaveDays: form.leaveDays,
      leavePay: leavePay, lastSalary: lastSalary, loanRecovery: loanRecovery, otherDeductions: otherDeductions,
      net: net)
  }
}

/// The settlement's breakdown: what is due and deducted, and the net amount (`Breakdown`).
enum PeSettlementRows {
  static func rows(_ figures: PeSettlementFigures, format: CompanyFormat) -> [PeAmount] {
    var rows = PeAmountRows()
    rows.add(t("End-of-service indemnity"), format.money(figures.indemnity))
    if figures.noticePay > 0 {
      rows.add(
        t("Notice pay ({months} months)", ["months": format.quantity(figures.noticeMonths)]),
        format.money(figures.noticePay))
    }
    if figures.leavePay > 0 {
      rows.add(
        t("Unused leave ({days} days)", ["days": format.quantity(figures.leaveDays)]), format.money(figures.leavePay))
    }
    if let last = figures.lastSalary {
      rows.add(
        t("Last salary ({days} of {total} days)", ["days": String(last.days), "total": String(last.daysInMonth)]),
        format.money(last.gross))
      if last.pifssEmployee > 0 { rows.add(t("PIFSS – employee share"), "−" + format.money(last.pifssEmployee)) }
    }
    if figures.loanRecovery > 0 { rows.add(t("Loan recovery"), "−" + format.money(figures.loanRecovery)) }
    if figures.otherDeductions > 0 { rows.add(t("Other deductions"), "−" + format.money(figures.otherDeductions)) }
    rows.add(t("Net amount due"), format.money(figures.net), strong: true)
    return rows.rows
  }
}

/// A settlement that was posted: its amounts and its entries in the books.
private struct PePostedSettlement: View {
  let employee: PeEmployee
  let settlement: PeSettlementRecord
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let format = model.one.format
    let paid = settlement.status == "paid"
    let figures = PeSettlementFigures(
      indemnity: settlement.indemnity, noticeMonths: settlement.noticeMonths, noticePay: settlement.noticePay,
      leaveDays: settlement.leaveDays, leavePay: settlement.leavePay, lastSalary: settlement.lastSalary,
      loanRecovery: settlement.loans.reduce(0) { $0 + $1.amount }, otherDeductions: settlement.otherDeductions,
      net: settlement.net)
    VStack(alignment: .leading, spacing: 8) {
      Button {
        Haptics.play(.tap)
        router.back()
      } label: {
        HStack(spacing: 4) {
          IconView(.chevronLeft, size: 14)
          Text(employee.displayName)
        }
        .font(.web(14))
        .foregroundStyle(palette.slate(500))
        .frame(minHeight: 32)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      Text(t("Final settlement")).webText(.pageTitle).accessibilityAddTraits(.isHeader)
      Badge(paid ? t("Paid") : t("Not paid yet"), tone: paid ? .green : .blue)
      Text(
        t("Left on {date}", ["date": format.date(settlement.leavingDate)]) + " · "
          + PePeople.leavingReasonLabel(settlement.reason)
      )
      .font(.web(14))
      .foregroundStyle(palette.slate(500))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, 24)
    VStack(alignment: .leading, spacing: 24) {
      PeCard(
        t("Amounts"),
        description: t(
          "{years} years of service; indemnity on a monthly wage of {wage}.",
          [
            "years": format.quantity(PeMoney.jsRound(settlement.years * 100) / 100),
            "wage": format.money(settlement.eosWage),
          ])
      ) {
        PeAmountList(rows: PeSettlementRows.rows(figures, format: format))
      }
      Card {
        CardHeader(t("In the books"))
        PeRows {
          PeEntryLink(label: t("Settlement"), journalId: settlement.journalId)
          PeEntryLink(label: t("Payment"), journalId: settlement.paymentJournalId)
        }
        if settlement.eosProvision > 0 || settlement.leaveProvision > 0 {
          Text(
            t(
              "Released from the provisions: {eos} end of service and {leave} leave salary.",
              ["eos": format.money(settlement.eosProvision), "leave": format.money(settlement.leaveProvision)])
          )
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
        }
      }
    }
  }
}
