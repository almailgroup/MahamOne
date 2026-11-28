import MahamKit
import SwiftUI

// Maham Compliance (`src/apps/compliance/pages/compliance`): the calendar of
// what is due, the documents register and the vehicles with their papers.

// MARK: The header and its tabs

/// "Compliance" with the Calendar / Documents tabs, and Vehicles with the
/// register's extras (`ComplianceHeader`).
private struct SuComplianceHeader: View {
  let current: Route
  let extras: Bool
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PageHeader(t("Compliance"), description: t("Deadlines, licences and staff papers that need renewing."))
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 24) {
          tab(t("Calendar"), .complianceCalendar)
          tab(t("Documents"), .complianceDocuments)
          if extras { tab(t("Vehicles"), .vehicles) }
        }
      }
      .padding(.top, -8)
      .overlay(alignment: .bottom) { Rectangle().fill(palette.slate(200)).frame(height: 1) }
    }
    .padding(.bottom, 24)
  }

  private func tab(_ title: String, _ route: Route) -> some View {
    let active = route == current
    return Button {
      guard !active else { return }
      Haptics.play(.selection)
      router.go(route)
    } label: {
      Text(title)
        .font(.web(14, .medium))
        .foregroundStyle(active ? palette.primary(700) : palette.slate(500))
        .padding(.horizontal, 4)
        .padding(.bottom, 10)
        .frame(minHeight: 44, alignment: .bottom)
        .overlay(alignment: .bottom) {
          Rectangle().fill(active ? palette.primary(600) : Color.clear).frame(height: 2)
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(active ? .isSelected : [])
  }
}

/// Valid, expiring (with the days left) or expired (`ExpiryBadge`).
struct SuExpiryBadge: View {
  let info: SuExpiry

  var body: some View {
    Badge(text, tone: tone)
  }

  private var text: String {
    guard let days = info.daysLeft else { return t("No expiry date") }
    switch info.status {
    case .expired: return t("Expired")
    case .expiring: return days == 0 ? t("Expires today") : tp(days, "Expires in {count} day", "Expires in {count} days")
    case .valid: return t("Valid")
    }
  }

  private var tone: StatusTone {
    guard let days = info.daysLeft else { return .gray }
    switch info.status {
    case .expired: return .red
    case .expiring: return days <= 7 ? .red : .amber
    case .valid: return .green
    }
  }
}

// MARK: The calendar

/// `/compliance`: what is overdue, then each month of the next 90 days.
struct SuComplianceCalendarPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @State private var renewing: SwRenewing?
  @State private var adding: SwDocDraft?

  private static let windowDays = 90

  var body: some View {
    let register = SuRegister(model.one)
    let items = calendar(register)
    WebPage(spacing: 24, refresh: { [model] in await model.one.sync() }) {
      SuComplianceHeader(current: .complianceCalendar, extras: register.extras)
        .padding(.bottom, -24)
      if suLoading(model, empty: register.company == nil) {
        SuLoadingCard()
      } else {
        stats(items, register: register)
        notice(register)
        if items.isEmpty {
          Card {
            WebEmptyState(
              icon: .calendarCheck, title: t("Nothing due in the next 90 days"),
              description: t(
                "Statutory deadlines and documents that expire appear here, with reminders before each date."))
          }
        } else {
          SuCalendarList(items: items, register: register) { entry in
            renewing = SwRenewing(entry: entry, owner: register.owner(entry))
          }
        }
      }
    }
    .swRenewDialog($renewing, model: model)
    .swDocumentDialog($adding, model: model)
  }

  private func calendar(_ register: SuRegister) -> [SuCalendarItem] {
    let today = DocRules.today
    let marks = Set(model.one.records(.complianceMarks).map { $0.str("key") })
    let since = SuDeadlines.overdueSince(register.company?.str("createdAt") ?? "", from: today)
    return SuDeadlines.calendar(
      SuDeadlines.context(register), entries: register.entries, marks: marks, from: today, days: Self.windowDays,
      overdueSince: since)
  }

  @ViewBuilder
  private func stats(_ items: [SuCalendarItem], register: SuRegister) -> some View {
    let format = model.one.format
    let overdue = items.filter { $0.status == .overdue }.count
    let dueIn30 = items.filter { $0.status != .overdue && $0.status != .done && $0.daysLeft <= 30 }.count
    VStack(spacing: 16) {
      SuStat(t("Overdue"), value: format.quantity(Double(overdue)), danger: overdue > 0) {
        Text(t("Deadlines missed and documents expired"))
      }
      SuStat(t("Due in 30 days"), value: format.quantity(Double(dueIn30))) {
        Text(t("Not done yet"))
      }
      SuStat(t("Tracked documents"), value: format.quantity(Double(register.entries.count))) {
        SuLink(t("Open the register"), size: 12) { router.go(.complianceDocuments) }
      }
    }
  }

  /// What to set up first: the legal form (for the right deadlines) and the commercial licence.
  @ViewBuilder
  private func notice(_ register: SuRegister) -> some View {
    let kuwait = register.company?.obj("kuwait") != nil
    let hasLicence = register.documents.contains {
      $0.str("type") == "commercial_licence" && !$0.flag("archived")
    }
    let editor = !SuRole(model).readOnly
    if (!hasLicence && editor) || !kuwait {
      SuNotice {
        if !kuwait {
          Text(
            t(
              "Deadlines follow your legal form and foreign ownership. Set them in the company settings to see the right ones."
            ))
          SuLink(t("Company settings")) { router.push(.settings(section: "company")) }
        }
        if !hasLicence && editor {
          Text(t("Add your commercial licence to be reminded before it expires."))
          if SwComplianceGate.documents, let companyId = register.company?.rid {
            WebButton(t("Add commercial licence"), icon: .plus, variant: .outline, size: .sm) {
              adding = SwDocDraft.new(companyId: companyId, ["type": "commercial_licence"])
            }
          }
        }
      }
    }
  }
}

/// The overdue items, then the rest month by month, and the disclaimer.
private struct SuCalendarList: View {
  let items: [SuCalendarItem]
  let register: SuRegister
  let onRenew: (SuEntry) -> Void
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let overdue = items.filter { $0.status == .overdue }
    let months = groups(items.filter { $0.status != .overdue })
    VStack(alignment: .leading, spacing: 24) {
      if !overdue.isEmpty {
        VStack(spacing: 0) {
          SuHeading(t("Overdue"), tone: .red(700))
          card(overdue)
        }
      }
      ForEach(months, id: \.month) { group in
        VStack(spacing: 0) {
          SuHeading(monthName(group.month))
          card(group.items)
        }
      }
      Text(
        t(
          "Deadlines are worked out from your financial year end and legal form, as commonly applied in Kuwait. They are reminders, not legal advice."
        )
      )
      .font(.web(12))
      .foregroundStyle(palette.slate(500))
    }
  }

  private func card(_ list: [SuCalendarItem]) -> some View {
    ListCard(rows: {
      ForEach(list) { item in
        SuCalendarRow(item: item, register: register, onRenew: onRenew)
      }
    })
  }

  /// Items by the month they fall due, in order.
  private func groups(_ list: [SuCalendarItem]) -> [SuMonthGroup] {
    var out: [SuMonthGroup] = []
    for item in list {
      let month = String(item.dueDate.prefix(7))
      if let last = out.indices.last, out[last].month == month {
        out[last].items.append(item)
      } else {
        out.append(SuMonthGroup(month: month, items: [item]))
      }
    }
    return out
  }

  /// "November 2026" in the interface language.
  private func monthName(_ month: String) -> String {
    let pattern: Format.DateFormat = "MMMM yyyy"
    return Format.date("\(month)-01", format: pattern, locale: model.one.format.locale)
  }
}

private struct SuMonthGroup {
  let month: String
  var items: [SuCalendarItem]
}

/// A deadline or a paper: the day in a tile, the title with its status,
/// what it is for and when, and what a deadline is.
private struct SuCalendarRow: View {
  let item: SuCalendarItem
  let register: SuRegister
  let onRenew: (SuEntry) -> Void
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      line
      SwCalendarAction(item: item, title: title, onRenew: onRenew)
    }
  }

  private var line: some View {
    SuRow(action: action) {
      HStack(alignment: .top, spacing: 16) {
        tile
        VStack(alignment: .leading, spacing: 2) {
          FlowLayout(spacing: 8, lineSpacing: 4) {
            Text(title)
              .font(.web(16, .medium))
              .strikethrough(item.status == .done)
              .foregroundStyle(item.status == .done ? palette.slate(500) : palette.slate(900))
            Badge(t(item.status.label), tone: item.status.tone)
            if item.deadline != nil, item.status != .done {
              Badge(t("Check with your auditor"), tone: .gray)
            }
          }
          Text(suJoin([detail, "\(format.date(item.dueDate)) (\(suDaysText(item.daysLeft)))"]))
            .font(.web(14))
            .foregroundStyle(palette.slate(600))
          if let deadline = item.deadline {
            Text(t(deadline.explanation)).font(.web(12)).foregroundStyle(palette.slate(500)).padding(.top, 2)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var format: CompanyFormat { model.one.format }

  private var tile: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous)
    let colors = tileColors
    let dayPattern: Format.DateFormat = "d"
    let monthPattern: Format.DateFormat = "MMM"
    return VStack(spacing: 0) {
      Text(Format.date(item.dueDate, format: dayPattern, locale: format.locale))
        .font(.web(16, .semibold, tabular: true))
      Text(Format.date(item.dueDate, format: monthPattern, locale: format.locale)).font(.web(12))
    }
    .foregroundStyle(palette.color(colors.text))
    .frame(width: 48, height: 48)
    .background(palette.color(colors.fill), in: shape)
    .accessibilityHidden(true)
  }

  private var tileColors: (fill: Token, text: Token) {
    switch item.status {
    case .overdue: (fill: Token.red(50), text: Token.red(700))
    case .done: (fill: Token.emerald(50), text: Token.emerald(700))
    default: (fill: Token.slate(100), text: Token.slate(700))
    }
  }

  private var title: String {
    if let deadline = item.deadline { return t(deadline.title, deadline.vars) }
    if let entry = item.entry { return SuCompliance.title(entry) }
    return ""
  }

  private var detail: String {
    if let deadline = item.deadline {
      if deadline.monthly {
        let pattern: Format.DateFormat = "MMMM yyyy"
        let month = Format.date("\(deadline.period)-01", format: pattern, locale: format.locale)
        return t("For {month}", ["month": month])
      }
      return t("Year ended {date}", ["date": format.date(deadline.period)])
    }
    guard let entry = item.entry else { return "" }
    return suJoin([register.owner(entry), entry.number])
  }

  /// An employee's paper opens the employee; the rest open the register.
  private var action: (() -> Void)? {
    guard let entry = item.entry else { return nil }
    if let employee = entry.employeeId, entry.recordId == nil {
      return { router.push(.employee(id: employee)) }
    }
    return { router.go(.complianceDocuments) }
  }
}

// MARK: The documents register

/// One line of the register as the list shows it.
private struct SuDocumentRow: Identifiable {
  let entry: SuEntry
  let info: SuExpiry
  let owner: String
  let title: String
  let purpose: String
  /// Files kept with a stored record; nil for an employee's own paper.
  let files: Int?
  let newCopy: SuNewCopy?
  var id: String { entry.key }
}

/// `/compliance/documents`: every tracked paper with its expiry, by status,
/// whom it belongs to and a search; archived papers and drivers without a
/// valid licence apart.
struct SuComplianceDocumentsPage: View {
  @Environment(AppModel.self) private var model
  @State private var status = "all"
  @State private var owner = ""
  @State private var customer = ""
  @State private var query = ""
  @State private var detail: SuDocumentRow? = nil
  @State private var detailOpen = false
  @State private var editing: SwDocDraft?
  @State private var renewing: SwRenewing?

  var body: some View {
    let register = SuRegister(model.one)
    let role = SuRole(model)
    let clients = clientsById(register)
    let rows = documentRows(register, clients: clients, role: role)
    let archived = register.documents.filter { $0.flag("archived") }
    let drivers = role.seesPeople ? register.missing : []
    let format = model.one.format
    WebPage(refresh: { [model] in await model.one.sync() }) {
      SuComplianceHeader(current: .complianceDocuments, extras: register.extras)
      if SwAccess(model).edits && SwComplianceGate.documents, let companyId = register.company?.rid {
        HStack {
          Spacer(minLength: 0)
          WebButton(t("Add document"), icon: .plus, size: .md) {
            let overrides: [String: JSONValue] = owner.isEmpty ? [:] : ["ownerType": .string(owner)]
            editing = SwDocDraft.new(companyId: companyId, overrides)
          }
        }
        .padding(.top, -8)
      }
      if suLoading(model, empty: rows.isEmpty) {
        SuLoadingCard()
      } else if rows.isEmpty && archived.isEmpty && drivers.isEmpty {
        Card {
          WebEmptyState(
            icon: .fileText, title: t("No documents yet"),
            description: t(
              "Add your commercial licence, lease and vehicle papers. Employees’ Civil IDs, residencies and work permits appear here on their own."
            ))
        }
      } else {
        SuRegisterList(
          register: register, rows: rows, archived: archived, drivers: drivers, clients: clients,
          checksDrivers: register.drivingLicences && role.seesPeople, status: $status, owner: $owner,
          customer: $customer, query: $query,
          onRenew: { row in renewing = SwRenewing(entry: row.entry, owner: row.owner) },
          onArchived: { doc in open(doc) }
        ) { row in
          if let doc = register.documents.first(where: { $0.rid == row.entry.recordId }), canEdit {
            open(doc)
          } else {
            detail = row
            detailOpen = true
          }
        }
      }
    }
    .webDialog(isPresented: $detailOpen, title: detail?.title ?? "") {
      if let detail {
        SuDocumentDetail(row: detail, format: format)
      }
    }
    .swDocumentDialog($editing, model: model)
    .swRenewDialog($renewing, model: model)
  }

  /// Editors change stored documents in the form; the rest see their details.
  private var canEdit: Bool { SwAccess(model).edits && SwComplianceGate.documents }

  private func open(_ doc: JSONValue) {
    guard canEdit else { return }
    editing = SwDocDraft(doc, isNew: false)
  }

  /// The customers papers may belong to, with the register's extras.
  private func clientsById(_ register: SuRegister) -> [String: JSONValue] {
    guard register.extras else { return [:] }
    var map: [String: JSONValue] = [:]
    for client in model.one.records(.clients) { map[client.rid] = client }
    return map
  }

  /// The register's lines (confidential ones only for those who see People), by expiry.
  private func documentRows(_ register: SuRegister, clients: [String: JSONValue], role: SuRole) -> [SuDocumentRow] {
    let today = DocRules.today
    let shown = register.entries.filter { role.seesPeople || !$0.confidential }
    let rows = shown.map { entry in
      SuDocumentRow(
        entry: entry, info: SuCompliance.expiry(entry.expiryDate, entry.reminderDays, on: today),
        owner: register.owner(entry, clients: clients), title: SuCompliance.title(entry),
        purpose: register.purpose(entry.purposeId), files: entry.recordId.map { register.files[$0] ?? 0 },
        newCopy: register.newCopies[entry.key])
    }
    return rows.sorted { rowOrder($0, $1) }
  }

  private func rowOrder(_ a: SuDocumentRow, _ b: SuDocumentRow) -> Bool {
    let (ea, eb) = (a.entry.expiryDate ?? "9999", b.entry.expiryDate ?? "9999")
    if ea != eb { return ea < eb }
    return a.title.localizedCompare(b.title) == .orderedAscending
  }
}

/// The register's card: the status chips, whom it belongs to, the customer
/// and the search, then the lines the filters leave.
private struct SuRegisterList: View {
  let register: SuRegister
  let rows: [SuDocumentRow]
  let archived: [JSONValue]
  let drivers: [SuMissingLicence]
  let clients: [String: JSONValue]
  let checksDrivers: Bool
  @Binding var status: String
  @Binding var owner: String
  @Binding var customer: String
  @Binding var query: String
  let onRenew: (SuDocumentRow) -> Void
  let onArchived: (JSONValue) -> Void
  let onOpen: (SuDocumentRow) -> Void

  var body: some View {
    let current = shownStatus
    let customers = customerOptions
    ListCard {
      Segmented(selection: $status, options: chips)
      if current != "drivers" {
        if customers.count > 1 {
          Select(selection: $customer, options: customers)
        }
        Select(selection: $owner, options: ownerOptions)
      }
      TextInput(text: $query, placeholder: t("Search documents…"), leadingIcon: .search)
    } rows: {
      switch current {
      case "drivers": driverRows
      case "archived": archivedRows
      default: documentRows(current)
      }
    }
  }

  // MARK: The filters

  /// Back to every document once a chip has nothing to show any more.
  private var shownStatus: String {
    if status == "drivers", !checksDrivers { return "all" }
    if status == "nofile", !register.extras { return "all" }
    if status == "newcopy", withoutCopy == 0 { return "all" }
    if status == "archived", archived.isEmpty { return "all" }
    return status
  }

  private var withoutCopy: Int { rows.filter { $0.newCopy != nil }.count }

  private var chips: [SegmentOption<String>] {
    var options = [
      SegmentOption("all", t("All"), count: rows.count),
      SegmentOption("expiring", t("Expiring"), count: count(.expiring)),
      SegmentOption("expired", t("Expired"), count: count(.expired)),
      SegmentOption("valid", t("Valid"), count: count(.valid)),
    ]
    if !archived.isEmpty { options.append(SegmentOption("archived", t("Archived"), count: archived.count)) }
    if checksDrivers {
      options.append(SegmentOption("drivers", t("Drivers without a valid licence"), count: drivers.count))
    }
    if register.extras {
      options.append(SegmentOption("nofile", t("No file"), count: rows.filter { $0.files == 0 }.count))
    }
    if withoutCopy > 0 { options.append(SegmentOption("newcopy", t("New copy missing"), count: withoutCopy)) }
    return options
  }

  private func count(_ status: SuExpiryStatus) -> Int {
    rows.filter { $0.info.status == status }.count
  }

  private var ownerOptions: [SelectOption<String>] {
    [SelectOption("", t("Everyone"))] + SuDocTypes.owners.map { SelectOption($0, t(SuDocTypes.ownerLabel($0))) }
  }

  /// "Every customer" and the customers who have papers here.
  private var customerOptions: [SelectOption<String>] {
    guard register.extras else { return [] }
    let ids = Set(rows.compactMap { $0.entry.clientId })
    let named = ids.compactMap { id in clients[id].map { SelectOption(id, localName($0)) } }
    let sorted = named.filter { !$0.label.isEmpty }.sorted { $0.label.localizedCompare($1.label) == .orderedAscending }
    return sorted.isEmpty ? [] : [SelectOption("", t("Every customer"))] + sorted
  }

  private func searchText(_ row: SuDocumentRow) -> String {
    let entry = row.entry
    let employee = register.employee(entry.employeeId)
    let client = entry.clientId.flatMap { clients[$0] }
    let label = SuDocTypes.label(entry.type)
    let names: [String?] = [employee?.str("name"), employee?.str("nameAr"), client?.str("name"), client?.str("nameAr")]
    let parts: [String] = [row.title, t(label), label, row.owner, entry.number, entry.issuer, row.purpose]
    return (parts + names.compactMap { $0 }).joined(separator: " ")
  }

  private func matches(_ row: SuDocumentRow, _ status: String) -> Bool {
    let byStatus: Bool
    switch status {
    case "all": byStatus = true
    case "nofile": byStatus = row.files == 0
    case "newcopy": byStatus = row.newCopy != nil
    default: byStatus = row.info.status.rawValue == status
    }
    let shownCustomer = customerOptions.contains(where: { $0.value == customer }) ? customer : ""
    return byStatus && (owner.isEmpty || row.entry.ownerType == owner)
      && (shownCustomer.isEmpty || row.entry.clientId == shownCustomer) && searchText(row).matches(query)
  }

  // MARK: The lines

  @ViewBuilder
  private func documentRows(_ status: String) -> some View {
    let filtered = rows.filter { matches($0, status) }
    if filtered.isEmpty {
      SuNoMatch(t("No documents match."))
    } else {
      ForEach(filtered) { row in
        SuRegisterRow(row: row, onOpen: onOpen)
        SwRenewAction(entry: row.entry, title: row.title) { onRenew(row) }
      }
    }
  }

  @ViewBuilder
  private var archivedRows: some View {
    ForEach(archived.map(Rec.init)) { record in
      SuArchivedRow(doc: record.raw, register: register) { onArchived(record.raw) }
    }
  }

  /// Drivers are employees: found by their name, number or job title.
  private func driverMatches(_ missing: SuMissingLicence) -> Bool {
    let employee = register.employee(missing.employeeId)
    let fields = ["name", "nameAr", "number", "jobTitle", "jobTitleAr"].map { employee?.str($0) ?? "" }
    return fields.joined(separator: " ").matches(query)
  }

  @ViewBuilder
  private var driverRows: some View {
    let shown = drivers.filter { driverMatches($0) }
    if drivers.isEmpty {
      SuNoMatch(t("Every driver holds a valid driving licence."))
    } else if shown.isEmpty {
      SuNoMatch(t("No employees match."))
    } else {
      ForEach(shown) { missing in
        SuDriverRow(missing: missing, register: register)
      }
    }
  }
}

/// A paper of the register: its name (and Confidential), its type and
/// number, whom it belongs to; its expiry and whether the new copy is missing.
private struct SuRegisterRow: View {
  let row: SuDocumentRow
  let onOpen: (SuDocumentRow) -> Void
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let entry = row.entry
    let format = model.one.format
    SuRow(action: { open() }) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          FlowLayout(spacing: 8, lineSpacing: 4) {
            Text(row.title).font(.web(16, .medium)).foregroundStyle(palette.slate(900))
            if entry.confidential {
              HStack(spacing: 4) {
                IconView(.lock, size: 12)
                Text(t("Confidential"))
              }
              .font(.web(12, .medium))
              .foregroundStyle(palette[.violet(700)])
              .padding(.horizontal, 8)
              .padding(.vertical, 2)
              .background(palette[.violet(50)], in: Capsule())
            }
          }
          let kind = entry.title.isEmpty ? "" : t(SuDocTypes.label(entry.type))
          let line = suJoin([kind, entry.number])
          if !line.isEmpty {
            Text(line).font(.web(12)).foregroundStyle(palette.slate(500))
          }
          Text(row.owner).font(.web(12)).foregroundStyle(palette.slate(500))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .trailing, spacing: 4) {
          SuExpiryBadge(info: row.info)
          if let expiry = entry.expiryDate {
            Text(expiryLine(expiry, format: format)).font(.web(12)).foregroundStyle(palette.slate(500))
          }
          if let copy = row.newCopy {
            Badge(t("New copy missing"), tone: .amber)
            Text(t("Renewed on {date}", ["date": format.date(copy.renewedOn)]))
              .font(.web(12))
              .foregroundStyle(palette.slate(500))
          }
        }
        .multilineTextAlignment(.trailing)
        .fixedSize()
      }
    }
  }

  private func expiryLine(_ expiry: String, format: CompanyFormat) -> String {
    let date = format.date(expiry)
    guard row.info.status == .expired else { return date }
    return "\(date) · \(suDaysText(row.info.daysLeft ?? 0))"
  }

  /// An employee's own paper opens the employee; a stored one shows its details.
  private func open() {
    if row.entry.recordId == nil, let employee = row.entry.employeeId {
      router.push(.employee(id: employee))
    } else {
      onOpen(row)
    }
  }
}

/// An archived paper: its name, whom it belonged to and its number.
private struct SuArchivedRow: View {
  let doc: JSONValue
  let register: SuRegister
  let onOpen: () -> Void
  @Environment(\.palette) private var palette

  var body: some View {
    let entry = SuCompliance.recordEntry(doc, days: register.reminderDays, byType: register.reminderDaysByType)
    SuRow(action: onOpen) {
      HStack(spacing: 12) {
        IconView(.archive, size: 16).foregroundStyle(palette.slate(400))
        VStack(alignment: .leading, spacing: 2) {
          Text(SuCompliance.title(doc)).font(.web(16, .medium)).foregroundStyle(palette.slate(700))
          Text(suJoin([register.owner(entry), doc.str("number")])).font(.web(12)).foregroundStyle(palette.slate(500))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

/// A driver without a valid licence: the employee and what is wrong.
private struct SuDriverRow: View {
  let missing: SuMissingLicence
  let register: SuRegister
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let employee = register.employee(missing.employeeId)
    let name = employee.map { localName($0) } ?? ""
    let job = employee.map { localName($0, key: "jobTitle") } ?? ""
    SuRow(action: { router.push(.employee(id: missing.employeeId)) }) {
      VStack(alignment: .leading, spacing: 6) {
        VStack(alignment: .leading, spacing: 2) {
          Text(name).font(.web(16, .medium)).foregroundStyle(palette.slate(900))
          let line = suJoin([employee?.str("number"), job])
          if !line.isEmpty {
            Text(line).font(.web(12)).foregroundStyle(palette.slate(500))
          }
        }
        state
      }
    }
  }

  private var expiredText: String {
    t("Driving licence expired {date}", ["date": model.one.format.date(missing.document?.text("expiryDate"))])
  }

  @ViewBuilder
  private var state: some View {
    switch missing.reason {
    case .expired:
      Text(expiredText).font(.web(12)).foregroundStyle(palette.slate(500))
    case .undated:
      Badge(t("No expiry date"), tone: .amber)
    case .missing:
      Badge(t("Driving licence missing"), tone: .red)
    }
  }
}

/// A stored paper's details, read only: what the edit dialog of the web shows.
private struct SuDocumentDetail: View {
  let row: SuDocumentRow
  let format: CompanyFormat
  @Environment(\.palette) private var palette

  var body: some View {
    let entry = row.entry
    let list = rows(entry, format: format)
    VStack(alignment: .leading, spacing: 0) {
      ForEach(list.indices, id: \.self) { index in
        let item = list[index]
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(item.label).foregroundStyle(palette.slate(500))
          Spacer(minLength: 8)
          Text(item.value).foregroundStyle(palette.slate(900)).multilineTextAlignment(.trailing)
        }
        .font(.web(14))
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
          if index > 0 { Rectangle().fill(palette.slate(100)).frame(height: 1) }
        }
      }
      if !entry.notes.isEmpty {
        Text(entry.notes)
          .font(.web(14))
          .foregroundStyle(palette.slate(700))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 12)
      }
    }
  }

  private func rows(_ entry: SuEntry, format: CompanyFormat) -> [InfoRow] {
    let list = [
      InfoRow(t("Type"), t(SuDocTypes.label(entry.type))),
      InfoRow(t("Belongs to"), row.owner),
      InfoRow(t("Purpose"), row.purpose),
      InfoRow(t("Number"), entry.number),
      InfoRow(t("Issued by"), entry.issuer),
      InfoRow(t("Issue date"), format.date(entry.issueDate)),
      InfoRow(t("Expiry date"), format.date(entry.expiryDate)),
      InfoRow(t("Renewal cost"), entry.renewalCost > 0 ? format.money(entry.renewalCost) : ""),
      InfoRow(t("Files"), row.files.map { $0 > 0 ? tp($0, "{count} file", "{count} files") : "" } ?? ""),
    ]
    return list.filter { !$0.value.isEmpty }
  }
}

// MARK: Vehicles

/// `/compliance/vehicles`: each vehicle with its driver and its papers.
struct SuVehiclesPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var list = "current"
  @State private var editing: SwVehicleDraft?
  @State private var paper: SwDocDraft?
  @State private var linking = false

  var body: some View {
    let register = SuRegister(model.one)
    WebPage(refresh: { [model] in await model.one.sync() }) {
      SuComplianceHeader(current: .vehicles, extras: register.extras)
      if register.extras {
        SwVehicleActions(register: register, linking: $linking) { editing = $0 }
          .padding(.top, -8)
      }
      if suLoading(model, empty: register.company == nil) {
        SuLoadingCard()
      } else if !register.extras {
        Card {
          WebEmptyState(
            icon: .car, title: t("Vehicles are switched off"),
            description: t(
              "Switch on contracts, customers and vehicles in the compliance settings to keep each vehicle with its papers and its driver."
            ))
        }
      } else if register.vehicles.isEmpty {
        Card {
          WebEmptyState(
            icon: .car, title: t("No vehicles yet"),
            description: t(
              "Add the company’s vehicles to keep their registration, insurance and other papers together."))
        }
      } else {
        SuVehicleList(
          register: register, list: $list, onEdit: { editing = SwVehicleDraft($0, isNew: false) },
          onAddPaper: { addPaper($0, register: register) })
        unlinkedNote(register)
      }
    }
    .swVehicleDialog($editing, model: model)
    .swDocumentDialog($paper, model: model)
  }

  /// A paper for a vehicle: its registration to start with.
  private func addPaper(_ vehicle: JSONValue, register: SuRegister) {
    guard let companyId = register.company?.rid else { return }
    paper = SwDocDraft.new(
      companyId: companyId,
      [
        "ownerType": "vehicle", "vehicleId": .string(vehicle.rid), "ownerName": .string(vehicle.str("plate")),
        "type": "vehicle_registration",
      ])
  }

  /// Vehicle papers that only name a vehicle by its plate.
  @ViewBuilder
  private func unlinkedNote(_ register: SuRegister) -> some View {
    let unlinked = register.documents.filter { doc in
      doc.str("ownerType") == "vehicle" && doc.text("vehicleId") == nil
        && !doc.str("ownerName").trimmingCharacters(in: .whitespaces).isEmpty
    }.count
    if unlinked > 0 {
      VStack(alignment: .leading, spacing: 0) {
        Text(
          tp(
            unlinked, "{count} vehicle paper in the register isn’t linked to a vehicle.",
            "{count} vehicle papers in the register aren’t linked to a vehicle.")
        )
        .font(.web(12))
        .foregroundStyle(palette.slate(500))
        SuLink(t("Open the register"), size: 12) { router.go(.complianceDocuments) }
      }
      .padding(.top, 16)
    }
  }
}

private struct SuVehicleList: View {
  let register: SuRegister
  @Binding var list: String
  let onEdit: (JSONValue) -> Void
  let onAddPaper: (JSONValue) -> Void

  var body: some View {
    let archivedCount = register.vehicles.filter { $0.flag("archived") }.count
    let shown = list == "archived" && archivedCount > 0 ? "archived" : "current"
    let vehicles = register.vehicles
      .filter { $0.flag("archived") == (shown == "archived") }
      .sorted { $0.str("plate").localizedCompare($1.str("plate")) == .orderedAscending }
    if archivedCount > 0 {
      ListCard {
        Segmented(selection: $list, options: options(archived: archivedCount))
      } rows: {
        rows(vehicles)
      }
    } else {
      ListCard(rows: { rows(vehicles) })
    }
  }

  private func options(archived: Int) -> [SegmentOption<String>] {
    [
      SegmentOption("current", t("Current vehicles"), count: register.vehicles.count - archived),
      SegmentOption("archived", t("Archived"), count: archived),
    ]
  }

  @ViewBuilder
  private func rows(_ vehicles: [JSONValue]) -> some View {
    if vehicles.isEmpty {
      SuNoMatch(t("Every vehicle is archived."))
    } else {
      ForEach(vehicles.map(Rec.init)) { record in
        SuVehicleRow(vehicle: record.raw, register: register, onEdit: onEdit, onAddPaper: onAddPaper)
      }
    }
  }
}

/// A vehicle: its plate, what it is and who drives it, then its papers.
private struct SuVehicleRow: View {
  let vehicle: JSONValue
  let register: SuRegister
  let onEdit: (JSONValue) -> Void
  let onAddPaper: (JSONValue) -> Void
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      line
      if SwVehicleActions.editable(model) {
        HStack(spacing: 8) {
          WebButton(t("Add paper"), icon: .filePlus2, variant: .outline, size: .sm) { onAddPaper(vehicle) }
          WebButton(t("Edit"), icon: .pencil, variant: .ghost, size: .sm) { onEdit(vehicle) }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
      }
    }
  }

  private var line: some View {
    let papers = ownPapers
    return SuRow {
      VStack(alignment: .leading, spacing: 0) {
        FlowLayout(spacing: 8, lineSpacing: 4) {
          Text(vehicle.str("plate")).font(.web(16, .medium)).foregroundStyle(palette.slate(900))
          if vehicle.flag("archived") { Badge(t("Archived"), tone: .gray) }
        }
        let line = suJoin([about, driver])
        if !line.isEmpty {
          Text(line).font(.web(12)).foregroundStyle(palette.slate(500)).padding(.top, 2)
        }
        if papers.isEmpty {
          Text(t("No papers yet.")).font(.web(12)).foregroundStyle(palette.slate(500)).padding(.top, 8)
        } else {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(papers.map(Rec.init)) { record in
              paper(record.raw)
            }
          }
          .padding(.leading, 16)
          .overlay(alignment: .leading) { Rectangle().fill(palette.slate(100)).frame(width: 2) }
          .padding(.top, 12)
        }
      }
    }
  }

  /// "Toyota Hilux 2022".
  private var about: String {
    let year = vehicle.number("year").map { String(Int($0)) }
    return suJoin([vehicle.str("make"), vehicle.str("model"), year], " ")
  }

  /// "Driver: Sara", for those who see employees.
  private var driver: String {
    guard SuRole(model).seesPeople, let employee = register.employee(vehicle.text("driverEmployeeId")) else {
      return ""
    }
    return t("Driver: {name}", ["name": localName(employee)])
  }

  /// Its papers (confidential ones only for those who see People), the first to expire first.
  private var ownPapers: [JSONValue] {
    let people = SuRole(model).seesPeople
    let id = vehicle.rid
    let own = register.documents.filter { doc in
      doc.str("vehicleId") == id && !doc.flag("archived") && (people || doc["confidential"]?.bool != true)
    }
    return own.sorted { ($0.text("expiryDate") ?? "9999") < ($1.text("expiryDate") ?? "9999") }
  }

  private func paper(_ doc: JSONValue) -> some View {
    let entry = SuCompliance.recordEntry(doc, days: register.reminderDays, byType: register.reminderDaysByType)
    let info = SuCompliance.expiry(entry.expiryDate, entry.reminderDays, on: DocRules.today)
    let format = model.one.format
    return HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(SuCompliance.title(entry)).font(.web(14)).foregroundStyle(palette.slate(800))
        let line = suJoin([doc.str("number"), entry.expiryDate.map { format.date($0) }])
        if !line.isEmpty {
          Text(line).font(.web(12)).foregroundStyle(palette.slate(500))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      SuExpiryBadge(info: info)
    }
  }
}
