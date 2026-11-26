import MahamKit
import SwiftUI

/// `/inventory/issues` (`src/apps/books/pages/inventory/issues.tsx`): items
/// issued to employees and the issues waiting for an approver; who received
/// what, from which warehouse and when.
struct InvStockIssuesPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(SuiteState.self) private var suite: SuiteState?
  @State private var show = "all"
  @State private var warehouseId = ""
  @State private var query = ""
  @State private var shown = 50

  var body: some View {
    let one = model.one
    let format = one.format
    let inventory = InvInventoryCache.inventory(one)
    let rows = InvIssues.rows(issues: one.records(.stockIssues), requests: one.records(.approvals))
    let visible = filtered(rows)
    let canIssue = InvIssueAccess.canIssue(inventory, role: suite?.role, userId: model.session?.user.id)
    WebPage(refresh: { [model] in await model.one.sync() }) {
      header(canIssue: canIssue)
      ListCard {
        Segmented(selection: $show, options: showOptions(rows))
        if Set(rows.map({ $0.issue.str("warehouseId") })).count > 1 {
          Select(selection: $warehouseId, options: warehouseOptions(rows, inventory: inventory))
        }
        TextInput(text: $query, placeholder: t("Search employees or items…"), leadingIcon: .search)
      } rows: {
        if rows.isEmpty, InvText.loading(one) {
          DataLoadingRow()
        } else if rows.isEmpty {
          emptyState(canIssue: canIssue)
        } else if visible.isEmpty {
          InvNothingMatches()
        } else {
          ForEach(visible.prefix(shown)) { row in
            InvIssueListRow(row: row, inventory: inventory, format: format)
          }
          if visible.count > shown {
            ListShowMore(remaining: visible.count - shown) { shown += 50 }
          }
        }
      }
    }
    .onChange(of: show) { _, _ in shown = 50 }
    .onChange(of: warehouseId) { _, _ in shown = 50 }
    .onChange(of: query) { _, _ in shown = 50 }
  }

  @ViewBuilder
  private func header(canIssue: Bool) -> some View {
    let title = t("Issued items")
    let description = t("Uniforms and other items handed to employees, and who confirmed them.")
    if canIssue {
      PageHeader(title, description: description) {
        WebButton(t("Issue items"), icon: .plus, haptic: .press) { router.push(.newStockIssue) }
      }
    } else {
      PageHeader(title, description: description)
    }
  }

  @ViewBuilder
  private func emptyState(canIssue: Bool) -> some View {
    let title = t("No items issued yet")
    let description = t(
      "Uniforms, shoes and badges handed to employees show here, with who issued them and who confirmed them.")
    if canIssue {
      WebEmptyState(icon: .shirt, title: title, description: description) {
        WebButton(t("Issue items"), icon: .plus) { router.push(.newStockIssue) }
      }
    } else {
      WebEmptyState(icon: .shirt, title: title, description: description)
    }
  }

  private func showOptions(_ rows: [InvIssueRow]) -> [SegmentOption<String>] {
    let waiting = rows.filter { $0.state == .waiting }.count
    return [
      SegmentOption("all", t("All"), count: rows.count),
      SegmentOption("waiting", t("Waiting for approval"), count: waiting),
      SegmentOption("issued", t("Issued")),
      SegmentOption("other", t("Void or rejected")),
    ]
  }

  /// The warehouses items were issued from.
  private func usedWarehouses(_ rows: [InvIssueRow], inventory: InvInventory) -> [JSONValue] {
    let used = Set(rows.map { $0.issue.str("warehouseId") })
    return inventory.warehouses.filter { used.contains($0.rid) }
  }

  private func warehouseOptions(_ rows: [InvIssueRow], inventory: InvInventory) -> [SelectOption<String>] {
    var options = [SelectOption("", t("All warehouses"))]
    for warehouse in usedWarehouses(rows, inventory: inventory) {
      options.append(SelectOption(warehouse.rid, inventory.path(warehouse)))
    }
    return options
  }

  private func filtered(_ rows: [InvIssueRow]) -> [InvIssueRow] {
    let chip = show
    let warehouse = warehouseId
    let text = query
    return rows.filter { row in
      InvIssues.matches(row, chip) && (warehouse.isEmpty || row.issue.str("warehouseId") == warehouse)
        && InvText.found(text, in: InvIssueAccess.searchFields(row.issue))
    }
  }
}

/// An issue in the list: who received the items, "date · number", what
/// was issued, and where it stands.
struct InvIssueListRow: View {
  let row: InvIssueRow
  let inventory: InvInventory
  let format: CompanyFormat
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let issue = row.issue
    let arabic = InvText.arabic
    InvRow(
      title: InvIssues.recipientLabel(issue.obj("recipient"), arabic: arabic),
      subtitle: InvText.joined([format.date(issue.text("date")), issue.text("number") ?? "—"]),
      detail: InvText.joined([
        InvIssues.summary(issue, arabic: arabic), inventory.path(inventory.warehouse(issue.text("warehouseId"))),
      ])
    ) {
      Badge(status: row.state.meta)
    } action: {
      router.push(.stockIssue(id: row.id))
    }
  }
}

/// Who may issue items, and what an issue is found by.
@MainActor
enum InvIssueAccess {
  /// Whether the person may issue items from some warehouse in use
  /// (`issuesFrom`): those who manage warehouses from any, anyone else from
  /// the sub-warehouse they look after.
  static func canIssue(_ inventory: InvInventory, role: MemberRole?, userId: String?) -> Bool {
    inventory.warehouses.contains { warehouse in
      !warehouse.flag("archived") && Roles.issuesFromWarehouse(role, userId: userId, warehouse)
    }
  }

  /// The number, the employee's names, number and job title, and the items' names.
  static func searchFields(_ issue: JSONValue) -> [String] {
    let recipient = issue.obj("recipient")
    var fields = [
      issue.str("number"), recipient?.str("name") ?? "", recipient?.str("nameAr") ?? "",
      recipient?.str("number") ?? "", recipient?.str("jobTitle") ?? "",
    ]
    for line in issue.list("lines") {
      fields.append(line.str("name"))
      fields.append(line.str("nameAr"))
    }
    return fields
  }
}

// MARK: One issue

/// `/inventory/issues/:id` (`issue-view.tsx`): items issued to an employee,
/// or asked for: what, to whom, from where, who issued and confirmed them.
struct InvStockIssuePage: View {
  let id: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(SuiteState.self) private var suite: SuiteState?
  @Environment(\.palette) private var palette

  init(id: String) {
    self.id = id
  }

  var body: some View {
    let one = model.one
    let format = one.format
    let inventory = InvInventoryCache.inventory(one)
    let rows = InvIssues.rows(issues: one.records(.stockIssues), requests: one.records(.approvals))
    let row = rows.first { $0.id == id }
    let issue = row?.issue
    RecordDetailPage(
      record: issue, title: title(issue),
      subtitle: issue.map { InvIssues.recipientLabel($0.obj("recipient"), arabic: InvText.arabic) },
      breadcrumb: t("Issued items")
    ) {
      if let row, let issue {
        if let request = row.request, !row.state.isKept {
          InvIssueRequestCard(
            request: request, issue: issue, warehouse: InvText.name(inventory.warehouse(issue.text("warehouseId"))),
            format: format)
        } else {
          InvIssueCard(row: row, inventory: inventory, format: format, seesPeople: Roles.canSeePeople(suite?.role))
        }
        InvIssueLinesCard(issue: issue, format: format)
        stockLink(inventory.warehouse(issue.text("warehouseId")))
      }
    }
  }

  /// "Items issued ISS-0001", or "Items to issue" before it has a number.
  private func title(_ issue: JSONValue?) -> String {
    guard let number = issue?.text("number") else { return t("Items to issue") }
    return t("Items issued {number}", ["number": number])
  }

  /// "Stock of {warehouse}: Inventory".
  @ViewBuilder
  private func stockLink(_ warehouse: JSONValue?) -> some View {
    if let warehouse {
      HStack(spacing: 4) {
        Text(t("Stock of {warehouse}:", ["warehouse": localName(warehouse)]))
          .foregroundStyle(palette.slate(500))
        Button {
          Haptics.play(.tap)
          router.push(.inventory)
        } label: {
          Text(t("Inventory")).foregroundStyle(palette.primary(700))
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .font(.web(12))
    }
  }
}

/// An issue that was kept: where it stands, to whom, when, from where, who
/// issued and confirmed it, and its notes.
struct InvIssueCard: View {
  let row: InvIssueRow
  let inventory: InvInventory
  let format: CompanyFormat
  let seesPeople: Bool
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let issue = row.issue
    Card {
      HStack(spacing: 8) {
        Badge(status: row.state.meta)
        if let voided = issue.text("voidedAt") {
          Text(t("Voided on {date}", ["date": format.dateTime(voided)]))
            .font(.web(12))
            .foregroundStyle(palette.slate(500))
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 16)
      .padding(.bottom, 4)
      InvFactRows(facts: facts(issue), onOpen: { route in router.push(route) })
        .padding(.bottom, 4)
      if let notes = issue.text("notes") {
        Text(notes)
          .font(.web(14))
          .foregroundStyle(palette.slate(700))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(palette.slate(50), in: RoundedRectangle(cornerRadius: WebRadius.sm, style: .continuous))
          .padding(.horizontal, 20)
          .padding(.bottom, 16)
      }
    }
  }

  private func facts(_ issue: JSONValue) -> [InvFact] {
    let recipient = issue.obj("recipient")
    let name = InvIssues.recipientLabel(recipient, arabic: InvText.arabic)
    var route: Route?
    if seesPeople, let employee = recipient?.text("employeeId") {
      route = .employee(id: employee)
    }
    let warehouse = inventory.path(inventory.warehouse(issue.text("warehouseId")))
    var list: [InvFact] = []
    list.append(InvFact(t("Issued to"), name, route: route))
    list.append(InvFact(t("Employee number"), recipient?.str("number") ?? "", tabular: true))
    list.append(InvFact(t("Date"), format.date(issue.text("date"))))
    list.append(InvFact(t("From warehouse"), warehouse))
    list.append(InvFact(t("Issued by"), InvIssueNames.name(issue.text("issuedByName"))))
    if let approvedAt = issue.text("approvedAt") {
      let approver = InvIssueNames.name(issue.text("approvedByName"))
      let confirmed = t("{name} · {date}", ["name": approver, "date": format.dateTime(approvedAt)])
      list.append(InvFact(t("Confirmed by"), confirmed))
    }
    return list
  }
}

/// The names an issue and its request keep (the team's names aren't on this
/// iPhone): the kept name, or "A team member".
enum InvIssueNames {
  static func name(_ kept: String?) -> String {
    kept ?? t("A team member")
  }
}

/// A request to issue items, as it waits or was decided
/// (`IssueRequestCard`, read only): who issued what to whom, from where and
/// when, who asked, and what was decided.
struct InvIssueRequestCard: View {
  let request: JSONValue
  let issue: JSONValue
  let warehouse: String
  let format: CompanyFormat
  @Environment(\.palette) private var palette

  var body: some View {
    let meta = InvIssues.requestMeta(request.str("status"))
    let arabic = InvText.arabic
    Card {
      VStack(alignment: .leading, spacing: 12) {
        FlowLayout(spacing: 8, lineSpacing: 6) {
          Text(t("Items issued")).font(.web(14, .medium)).foregroundStyle(palette.slate(900))
          Badge(status: meta)
          if request.flag("expired") { Badge(t("Expired"), tone: .gray) }
        }
        Text(issuedLine(arabic: arabic))
          .font(.web(14))
          .foregroundStyle(palette.slate(800))
        lines(arabic: arabic)
        InvFactRows(facts: facts, inset: 0)
        Text(askedLine)
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
        reason
        decision(meta)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(20)
    }
  }

  /// "{issuer} issued to {name}:".
  private func issuedLine(arabic: Bool) -> String {
    let issuer = InvIssueNames.name(request.text("requestedByName"))
    let name = InvIssues.recipientLabel(issue.obj("recipient"), arabic: arabic)
    return t("{issuer} issued to {name}:", ["issuer": issuer, "name": name])
  }

  /// "Asked by {name} · {date}".
  private var askedLine: String {
    let name = InvIssueNames.name(request.text("requestedByName"))
    let date = format.dateTime(request.text("requestedAt"))
    return t("Asked by {name} · {date}", ["name": name, "date": date])
  }

  /// From warehouse, Date, Employee number.
  private var facts: [InvFact] {
    let number = issue.obj("recipient")?.str("number") ?? ""
    return [
      InvFact(t("From warehouse"), warehouse),
      InvFact(t("Date"), format.date(issue.text("date"))),
      InvFact(t("Employee number"), number, tabular: true),
    ]
  }

  private func lines(arabic: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(issue.list("lines").indices), id: \.self) { index in
        line(issue.list("lines")[index], arabic: arabic)
      }
    }
  }

  private func line(_ line: JSONValue, arabic: Bool) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(format.quantity(line.num("quantity")))
        .font(.web(14, .medium, tabular: true))
        .foregroundStyle(palette.slate(900))
        .frame(minWidth: 40, alignment: .trailing)
      Text(InvIssues.lineName(line, arabic: arabic))
        .font(.web(14))
        .foregroundStyle(palette.slate(800))
      if let unit = line.text("unit") {
        Text(unit).font(.web(12)).foregroundStyle(palette.slate(500))
      }
    }
  }

  @ViewBuilder
  private var reason: some View {
    if let reason = request.text("reason") {
      Text(reason)
        .font(.web(14))
        .foregroundStyle(palette.slate(700))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.slate(50), in: RoundedRectangle(cornerRadius: WebRadius.sm, style: .continuous))
    }
  }

  @ViewBuilder
  private func decision(_ meta: StatusMeta) -> some View {
    let status = request.str("status")
    if let decided = request.text("decidedAt"), status != "pending" {
      Text(decidedLine(meta, at: decided))
        .font(.web(12))
        .foregroundStyle(palette.slate(500))
    }
    if status == "approved" {
      Text(
        t(
          "Confirmed, but not recorded yet on this device. Carry it out again, or reject it if it can’t be recorded."
        )
      )
      .font(.web(12))
      .foregroundStyle(palette[.amber(700)])
    }
  }

  /// "{status} by {name} · {date}", and the note given.
  private func decidedLine(_ meta: StatusMeta, at decided: String) -> String {
    let line = t(
      "{status} by {name} · {date}",
      ["status": t(meta.label), "name": InvIssueNames.name(nil), "date": format.dateTime(decided)])
    guard let note = request.text("decisionNote") else { return line }
    return "\(line) · \(note)"
  }
}

/// The items of an issue: each item's name and the quantity with its unit.
struct InvIssueLinesCard: View {
  let issue: JSONValue
  let format: CompanyFormat

  var body: some View {
    let lines = issue.list("lines")
    let arabic = InvText.arabic
    Card {
      InvColumns(t("Item"), t("Quantity"))
      VStack(spacing: 0) {
        ForEach(Array(lines.indices), id: \.self) { index in
          InvRow(
            title: InvIssues.lineName(lines[index], arabic: arabic),
            amount: InvText.quantity(lines[index].num("quantity"), unit: lines[index].str("unit"), format))
        }
      }
    }
  }
}
