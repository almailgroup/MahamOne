import MahamKit
import SwiftUI

// Payroll (`/payroll`), a pay run (`/payroll/runs/:id`), leave
// (`/payroll/leave`), leave reasons (`/payroll/leave-reasons`), staff loans
// (`/payroll/loans`) and the payroll settings (`/payroll/settings`):
// src/apps/people/pages/payroll/*.tsx. Read only.

// MARK: - Accounts the payroll posts to

/// A payroll account as the web looks it up (`PAYROLL_ACCOUNTS`, `payrollAccount`).
struct PeAccountSpec {
  let key: String
  let code: String
  let name: String
  let nameAr: String
  let type: String
}

@MainActor
enum PePayrollAccounts {
  static let specs: [PeAccountSpec] = [
    PeAccountSpec(key: "salaries", code: "6010", name: "Salaries and wages", nameAr: "الرواتب والأجور", type: "expense"),
    PeAccountSpec(key: "allowances", code: "6020", name: "Allowances", nameAr: "البدلات", type: "expense"),
    PeAccountSpec(
      key: "pifssExpense", code: "6030", name: "PIFSS – employer share",
      nameAr: "حصة صاحب العمل في التأمينات الاجتماعية", type: "expense"),
    PeAccountSpec(
      key: "eosExpense", code: "6040", name: "End-of-service indemnity", nameAr: "مكافأة نهاية الخدمة",
      type: "expense"),
    PeAccountSpec(key: "leaveExpense", code: "6050", name: "Leave salary", nameAr: "رواتب الإجازات", type: "expense"),
    PeAccountSpec(
      key: "salariesPayable", code: "2300", name: "Salaries payable", nameAr: "رواتب مستحقة",
      type: "liability_current"),
    PeAccountSpec(
      key: "pifssPayable", code: "2310", name: "PIFSS payable", nameAr: "التأمينات الاجتماعية المستحقة",
      type: "liability_current"),
    PeAccountSpec(
      key: "leaveProvision", code: "2320", name: "Leave salary provision", nameAr: "مخصص الإجازات",
      type: "liability_current"),
    PeAccountSpec(
      key: "eosProvision", code: "2700", name: "End-of-service indemnity provision",
      nameAr: "مخصص مكافأة نهاية الخدمة", type: "liability_non_current"),
    PeAccountSpec(key: "advances", code: "1320", name: "Staff advances", nameAr: "سلف الموظفين", type: "asset_current"),
    PeAccountSpec(
      key: "otherDeductions", code: "4500", name: "Other income", nameAr: "إيرادات أخرى", type: "income_other"),
  ]

  static func label(_ key: String) -> String {
    switch key {
    case "salaries": t("Salaries")
    case "allowances": t("Allowances and overtime")
    case "pifssExpense": t("PIFSS – employer share")
    case "eosExpense": t("End-of-service indemnity")
    case "leaveExpense": t("Leave salary")
    case "salariesPayable": t("Salaries payable")
    case "pifssPayable": t("PIFSS payable")
    case "leaveProvision": t("Leave salary provision")
    case "eosProvision": t("End-of-service indemnity provision")
    case "advances": t("Staff loans and advances")
    default: t("Other deductions")
    }
  }

  /// The company's chart: the Kuwait chart finds accounts by code alone.
  static func kuwaitChart(_ company: JSONValue?) -> Bool {
    if let template = company?.obj("accounting")?.text("template") { return template == "kw" }
    let country = company?.obj("address")?.str("country") ?? ""
    return country == "KW" || country.isEmpty
  }

  /// The account a key posts to when none is chosen (`findSystemAccount`).
  static func found(_ spec: PeAccountSpec, _ one: OneData) -> JSONValue? {
    let kw = kuwaitChart(one.company)
    let usable = one.records(.accounts).filter { !$0.flag("archived") && $0.str("type") == spec.type }
    func named(_ account: JSONValue) -> Bool {
      account.str("name").trimmingCharacters(in: .whitespaces).lowercased() == spec.name.lowercased()
        || account.str("nameAr").trimmingCharacters(in: .whitespaces) == spec.nameAr
    }
    return usable.first { $0.str("code") == spec.code && (kw || named($0)) } ?? usable.first { named($0) }
  }

  /// The account chosen in the settings, else the one found.
  static func account(_ key: String, settings: PePayrollSettings, _ one: OneData) -> JSONValue? {
    if let chosen = settings.accounts[key], let account = one.record(.accounts, chosen), !account.flag("archived") {
      return account
    }
    guard let spec = specs.first(where: { $0.key == key }) else { return nil }
    return found(spec, one)
  }

  /// "6010 Salaries and wages".
  static func text(_ account: JSONValue) -> String {
    account.str("code") + " " + localName(account)
  }
}

// MARK: - Payroll

/// `/payroll`: the pay runs, the latest month's net pay and the PIFSS due.
struct PePayrollPage: View {
  var body: some View {
    PeGate { PePayrollView() }
  }
}

private struct PePayrollView: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let one = model.one
    let runs = one.pePayRuns
    let employees = one.peEmployees
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PePayrollHeader(tab: "runs")
      PwNewPayRunButton()
        .padding(.bottom, 16)
      if employees.isEmpty {
        Card {
          WebEmptyState(
            icon: .userPlus, title: t("Add your employees first"),
            description: t(
              "Pay runs are prepared from the employee records: salary, allowances, IBAN and whether they are insured with PIFSS."
            )
          ) {
            if PwKinds.can(PwKinds.employee) {
              WebButton(t("New employee"), icon: .plus, haptic: .press) { router.push(.newEmployee) }
            }
          }
        }
      } else if runs.isEmpty {
        Card {
          WebEmptyState(
            icon: .handCoins, title: t("No pay runs yet"),
            description: t(
              "Prepare a month’s payroll: pay and overtime, PIFSS, loan instalments, payslips and the bank salary file."
            ))
        }
      } else {
        PePayRunsList(runs: runs, current: employees.filter(\.isCurrent).count)
      }
    }
  }
}

private struct PePayRunsList: View {
  let runs: [PePayRun]
  let current: Int
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let one = model.one
    let format = one.format
    let p = one.pePrecision
    let people = one.pePeopleSettings
    let latest = runs[0]
    let latestTotals = PePayroll.totals(latest.lines, p)
    let posted = runs.first { $0.status != "draft" }
    VStack(alignment: .leading, spacing: 24) {
      VStack(spacing: 16) {
        PeStat(
          label: t("Net pay, {month}", ["month": PePayroll.formatPeriod(latest.period, format)]),
          value: format.money(latestTotals.net),
          hint: tp(latest.lines.count, "{count} employee", "{count} employees"), small: true)
        PeStat(label: t("Current employees"), value: format.count(current), hint: t("Open the register")) {
          router.push(.employees)
        }
        if let posted {
          pifssStat(posted, dueDay: people.pifssDueDay, format: format, p: p)
        }
      }
      ListCard {
        ForEach(runs) { run in
          let totals = PePayroll.totals(run.lines, p)
          ListRow(
            title: PePayroll.formatPeriod(run.period, format), subtitle: when(run, format: format),
            amount: format.money(totals.net)
          ) {
            Badge(status: PePayroll.runStatus(run.status))
          } action: {
            router.push(.payRun(id: run.id))
          }
        }
      }
    }
  }

  private func pifssStat(_ posted: PePayRun, dueDay: Int, format: CompanyFormat, p: Int) -> some View {
    let totals = PePayroll.totals(posted.lines, p)
    let due = PePayroll.payDate(PePayroll.addPeriods(posted.period, 1), payDay: dueDay)
    return PeStat(
      label: t("PIFSS, {month}", ["month": PePayroll.formatPeriod(posted.period, format)]),
      value: format.money(totals.pifssEmployee + totals.pifssEmployer),
      hint: t("Pay by {date}.", ["date": format.date(due)]), small: true)
  }

  private func when(_ run: PePayRun, format: CompanyFormat) -> String {
    if let paid = run.paidOn { return t("Paid on {date}", ["date": format.date(paid)]) }
    return t("Pay date {date}", ["date": format.date(run.payDate)])
  }
}

// MARK: - A pay run

/// `/payroll/runs/:id`: the month's figures, what to check before paying,
/// every employee's pay, PIFSS and the entries in the books.
struct PePayRunPage: View {
  let id: String

  var body: some View {
    PeGate { PePayRunView(id: id) }
  }
}

private struct PePayRunView: View {
  let id: String
  @Environment(AppModel.self) private var model
  @State private var openLine: PePayLine?
  @State private var showingLine = false

  var body: some View {
    let one = model.one
    let run = one.record(.payRuns, id).map { PePayRun($0) }
    let format = one.format
    let p = one.pePrecision
    WebPage(spacing: 0, refresh: { [model] in await model.one.sync() }) {
      if let run {
        PePayRunBody(run: run) { line in
          openLine = line
          showingLine = true
        }
      } else {
        PeNotFound(message: t("This pay run could not be found."), back: t("Back to payroll"))
      }
    }
    .webDialog(isPresented: $showingLine, title: openLine?.displayName ?? "", description: lineDescription) {
      if let line = openLine, let run {
        PePayLineDetail(line: line, rules: run.rules, format: format, precision: p)
      }
    } footer: {
      WebButton(t("Close"), variant: .outline) { showingLine = false }
    }
  }

  private var lineDescription: String? {
    guard let line = openLine else { return nil }
    let text = [line.number, line.job].filter { !$0.isEmpty }.joined(separator: " · ")
    return text.isEmpty ? nil : text
  }
}

private struct PePayRunBody: View {
  let run: PePayRun
  let onLine: (PePayLine) -> Void
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let p = one.pePrecision
    let lines = run.lines
    let month = PePayroll.formatPeriod(run.period, format)
    let totals = PePayroll.totals(lines, p)
    let rules = run.rules
    let flagged = flaggedLines(lines, rules: rules, format: format, p: p)
    let flaggedIds = Set(flagged.map { $0.id })
    let pifssDue = PePayroll.payDate(PePayroll.addPeriods(run.period, 1), payDay: one.pePeopleSettings.pifssDueDay)
    PageHeader(
      t("Payroll for {month}", ["month": month]), description: subtitle(format: format), breadcrumb: t("Payroll"),
      onBreadcrumb: { router.back() })
    VStack(alignment: .leading, spacing: 24) {
      Badge(status: PePayroll.runStatus(run.status))
        .padding(.top, -16)
      PwPayRunActions(runId: run.id)
      VStack(spacing: 12) {
        PePair {
          PeStat(label: t("Gross pay"), value: format.money(totals.gross), small: true)
        } second: {
          PeStat(label: t("Deductions"), value: format.money(totals.deductions), small: true)
        }
        PePair {
          PeStat(label: t("Net pay"), value: format.money(totals.net), tone: .emerald(700), small: true)
        } second: {
          PeStat(
            label: t("Cost to the company"), value: format.money(totals.cost),
            hint: t("With the employer’s PIFSS share"), small: true)
        }
      }
      if run.status == "draft" {
        PeOpeningsCard(run: run)
      }
      if !flagged.isEmpty {
        PeWarningsCard {
          ForEach(flagged) { item in
            PeWarningLine(name: item.line.displayName, texts: item.texts) {
              onLine(item.line)
            }
          }
        }
      }
      Card {
        CardHeader(t("Employees"))
        PeRows {
          ForEach(lines) { line in
            PeLineRow(
              title: line.displayName, detail: lineDetail(line),
              trailing: {
                Text(format.money(line.net))
                  .font(.web(14, .semibold, tabular: true))
                  .foregroundStyle(line.net < 0 ? palette[.red(600)] : palette.slate(900))
                  .environment(\.layoutDirection, .leftToRight)
                if flaggedIds.contains(line.id) { Badge(t("Check"), tone: .amber) }
              }, action: { onLine(line) })
          }
        }
        ListCardFooter {
          HStack {
            Text(t("Total")).font(.web(14, .semibold)).foregroundStyle(palette.slate(900))
            Spacer()
            Text(format.money(totals.net))
              .font(.web(14, .semibold, tabular: true))
              .foregroundStyle(palette.slate(900))
          }
        }
      }
      if run.status != "paid" {
        PeCard(t("Pay date")) {
          PeFigureLine(label: t("Pay date"), value: format.date(run.payDate))
          PeHint(t("Wages are due within 7 days of the end of the month (art. 56)."))
        }
      }
      if run.status == "draft" && totals.otherDeductions > 0 {
        PeCard(t("Other deductions go to")) {
          PeFigureLine(label: t("Other deductions go to"), value: deductionAccount)
          PeHint(t("Fines and recoveries of {amount} this month.", ["amount": format.money(totals.otherDeductions)]))
        }
      }
      PeCard(t("PIFSS"), description: t("Pay by {date}.", ["date": format.date(pifssDue)])) {
        PeAmountList(rows: pifssRows(totals, format: format))
      }
      Card {
        CardHeader(t("In the books"))
        if run.status == "draft" {
          PeCardNote(t("Nothing is posted until the pay run is approved."))
        } else {
          PeRows {
            PeEntryLink(label: t("Salaries"), journalId: run.journalId)
            PeEntryLink(label: t("Provisions"), journalId: run.provisionJournalId)
            PeEntryLink(label: t("Payment"), journalId: run.paymentJournalId)
          }
        }
      }
    }
  }

  private func flaggedLines(_ lines: [PePayLine], rules: PePayRules, format: CompanyFormat, p: Int) -> [PeFlaggedLine] {
    var out: [PeFlaggedLine] = []
    for line in lines {
      let warnings = PePayroll.warnings(line, rules, p)
      if warnings.isEmpty { continue }
      out.append(PeFlaggedLine(line: line, texts: warnings.map { PePayroll.warningText($0, format) }))
    }
    return out
  }

  private func subtitle(format: CompanyFormat) -> String {
    let count = tp(run.lines.count, "{count} employee", "{count} employees")
    let when =
      run.status == "paid" && run.paidOn != nil
      ? t("Paid on {date}", ["date": format.date(run.paidOn)])
      : t("Pay date {date}", ["date": format.date(run.payDate)])
    return count + " · " + when
  }

  private func lineDetail(_ line: PePayLine) -> String {
    var parts: [String] = []
    if !line.number.isEmpty { parts.append(line.number) }
    if line.daysWorked < line.daysInMonth {
      parts.append(t("{days} of {total} days", ["days": String(line.daysWorked), "total": String(line.daysInMonth)]))
    }
    return parts.joined(separator: " · ")
  }

  private var deductionAccount: String {
    let one = model.one
    if let id = run.deductionAccountId, let account = one.record(.accounts, id) {
      return PePayrollAccounts.text(account)
    }
    let found = PePayrollAccounts.account("otherDeductions", settings: one.pePayrollSettings, one)
    return found.map { PePayrollAccounts.text($0) } ?? t("Default account")
  }

  private func pifssRows(_ totals: PeRunTotals, format: CompanyFormat) -> [PeAmount] {
    var rows = PeAmountRows()
    rows.add(t("Employee share"), format.money(totals.pifssEmployee))
    rows.add(t("Employer share"), format.money(totals.pifssEmployer))
    rows.add(t("Total due"), format.money(totals.pifssEmployee + totals.pifssEmployer), strong: true)
    return rows.rows
  }
}

/// A line of a run with what to check on it.
private struct PeFlaggedLine: Identifiable {
  let line: PePayLine
  let texts: [String]
  var id: String { line.id }
}

/// An amber card of things to look at, with its triangle.
private struct PeWarningsCard<Content: View>: View {
  let title: String
  let description: String?
  private let content: Content
  @Environment(\.palette) private var palette

  init(title: String = t("Check before paying"), description: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.description = description
    self.content = content()
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 8) {
        IconView(.triangleAlert, size: 16).foregroundStyle(palette[.amber(500)])
        VStack(alignment: .leading, spacing: 2) {
          Text(title).webText(.cardTitle)
          if let description {
            Text(description).font(.web(14)).foregroundStyle(palette.slate(500))
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
      .overlay(alignment: .bottom) { Rectangle().fill(palette[.amber(100)]).frame(height: 1) }
      VStack(alignment: .leading, spacing: 0) { content }
    }
    .background(palette[.amber(50)].opacity(0.4), in: shape)
    .background(palette.surface, in: shape)
    .border(palette[.amber(200)], in: shape)
  }
}

/// One employee's warnings; the name opens their pay.
private struct PeWarningLine: View {
  let name: String
  let texts: [String]
  let action: () -> Void
  @Environment(\.palette) private var palette

  var body: some View {
    Button {
      Haptics.play(.tap)
      action()
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        Text(name).font(.web(14, .medium)).foregroundStyle(palette.slate(900))
        ForEach(0..<texts.count, id: \.self) { index in
          Text(texts[index]).font(.web(14)).foregroundStyle(palette[.amber(800)])
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .overlay(alignment: .top) { Rectangle().fill(palette[.amber(100)]).frame(height: 1) }
  }
}

/// Staff in a draft run whose leave before they were added isn't known.
private struct PeOpeningsCard: View {
  let run: PePayRun
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let inRun = Set(run.lines.map(\.employeeId))
    let needing = PeLeave.needingOpening(one.peEmployees.filter { inRun.contains($0.id) }, one.peLeaveRecords)
      .sorted { $0.number.localizedStandardCompare($1.number) == .orderedAscending }
    let noOpening = needing.filter { $0.leaveOpening == nil }.count
    let unconfirmed = needing.filter { $0.leaveOpening.map { !$0.confirmed } ?? false }.count
    if !needing.isEmpty {
      PeWarningsCard(title: t("Opening leave balances"), description: description(noOpening, unconfirmed)) {
        FlowLayout(spacing: 16, lineSpacing: 4) {
          ForEach(needing.prefix(12)) { e in
            Button {
              Haptics.play(.tap)
              router.push(.employee(id: e.id))
            } label: {
              Text(e.displayName)
                .font(.web(14, .medium))
                .foregroundStyle(palette.primary(700))
                .frame(minHeight: 32)
            }
            .buttonStyle(.plain)
          }
          if needing.count > 12 {
            Text(tp(needing.count - 12, "and {count} more", "and {count} more"))
              .font(.web(14))
              .foregroundStyle(palette.slate(500))
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
      }
    }
  }

  private func description(_ noOpening: Int, _ unconfirmed: Int) -> String {
    var parts: [String] = []
    if noOpening > 0 {
      parts.append(
        tp(
          noOpening,
          "{count} employee has no opening leave balance: their leave is counted from their hire date.",
          "{count} employees have no opening leave balance: their leave is counted from their hire date."))
    }
    if unconfirmed > 0 {
      parts.append(
        tp(
          unconfirmed,
          "{count} employee in this pay run has leave brought forward that isn’t confirmed: their leave provision counts from the import date, with 0 days before it.",
          "{count} employees in this pay run have leave brought forward that isn’t confirmed: their leave provision counts from the import date, with 0 days before it."
        ))
    }
    return parts.joined(separator: "\n")
  }
}

/// One employee's pay in a run: how it adds up, and what to check (`PayLineDialog`, read only).
private struct PePayLineDetail: View {
  let line: PePayLine
  let rules: PePayRules
  let format: CompanyFormat
  let precision: Int
  @Environment(\.palette) private var palette

  var body: some View {
    let warnings = PePayroll.warnings(line, rules, precision).map { PePayroll.warningText($0, format) }
    VStack(alignment: .leading, spacing: 16) {
      if line.daysWorked < line.daysInMonth {
        PeNote(
          t(
            "Paid for {days} of {total} days this month.",
            ["days": String(line.daysWorked), "total": String(line.daysInMonth)]), tone: .blue)
      }
      if line.overtimeNormal + line.overtimeRestDay + line.overtimeHoliday > 0 {
        VStack(alignment: .leading, spacing: 8) {
          Text(t("Overtime hours")).font(.web(14, .semibold)).foregroundStyle(palette.slate(900))
          PeFigureLine(label: t("Working days (+25%)"), value: format.quantity(line.overtimeNormal))
          PeFigureLine(label: t("Rest days (+50%)"), value: format.quantity(line.overtimeRestDay))
          PeFigureLine(label: t("Public holidays (double)"), value: format.quantity(line.overtimeHoliday))
        }
      }
      if line.absentDays > 0 {
        PeFigureLine(label: t("Unpaid absence (days)"), value: format.quantity(line.absentDays))
      }
      ForEach(0..<line.leaveDetail.count, id: \.self) { index in
        PeHint(leaveText(line.leaveDetail[index]))
      }
      PeAmountList(rows: rows)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .border(palette.slate(200), in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
      ForEach(0..<warnings.count, id: \.self) { index in
        HStack(alignment: .top, spacing: 8) {
          IconView(.triangleAlert, size: 16).foregroundStyle(palette[.amber(500)])
          Text(warnings[index]).font(.web(14)).foregroundStyle(palette[.amber(800)])
        }
      }
    }
  }

  private var rows: [PeAmount] {
    var rows = PeAmountRows()
    rows.add(t("Basic salary"), format.money(line.basic))
    for allowance in line.allowances { rows.add(allowance.displayName, format.money(allowance.amount)) }
    if line.overtimePay > 0 { rows.add(t("Overtime"), format.money(line.overtimePay)) }
    if line.additions > 0 { rows.add(t("Additions"), format.money(line.additions)) }
    if line.absenceDeduction > 0 { rows.add(t("Unpaid days"), "−" + format.money(line.absenceDeduction)) }
    rows.add(t("Gross pay"), format.money(line.gross), strong: true)
    if line.pifssEmployee > 0 { rows.add(t("PIFSS – employee share"), "−" + format.money(line.pifssEmployee)) }
    if line.pifssOwed > 0 {
      rows.add(t("Owed by the employee, not covered by this month’s pay"), "+" + format.money(line.pifssOwed))
    }
    if line.loanDeduction > 0 { rows.add(t("Loan recovery"), "−" + format.money(line.loanDeduction)) }
    if line.otherDeductions > 0 { rows.add(t("Other deductions"), "−" + format.money(line.otherDeductions)) }
    rows.add(t("Net pay"), format.money(line.net), strong: true)
    if line.pifssEmployer > 0 { rows.add(t("PIFSS – employer share"), format.money(line.pifssEmployer), muted: true) }
    return rows.rows
  }

  /// One reason's leave on the line, in a sentence (`useLeaveDetailText`).
  private func leaveText(_ detail: PePayLineLeave) -> String {
    let reason = ["reason": detail.displayName]
    if detail.fromAnnual {
      return tp(
        detail.days, "{reason}: {count} day, taken from annual leave.", "{reason}: {count} days, taken from annual leave.",
        reason)
    }
    if detail.percent >= 100 {
      return tp(detail.days, "{reason}: {count} day on full pay.", "{reason}: {count} days on full pay.", reason)
    }
    if detail.percent <= 0 {
      return tp(detail.days, "{reason}: {count} day without pay.", "{reason}: {count} days without pay.", reason)
    }
    return tp(
      detail.days, "{reason}: {count} day at {percent} pay.", "{reason}: {count} days at {percent} pay.",
      ["reason": detail.displayName, "percent": format.percent(detail.percent)])
  }
}

// MARK: - Leave

/// `/payroll/leave`: the current staff's leave balances and who is away today.
struct PeLeavePage: View {
  var body: some View {
    PeGate { PeLeaveView() }
  }
}

private struct PeLeaveView: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let settings = one.pePayrollSettings
    let records = one.peLeaveRecords
    let today = PeDates.today
    let current = one.peEmployees.filter(\.isCurrent)
      .sorted { $0.number.localizedStandardCompare($1.number) == .orderedAscending }
    let needing = PeLeave.needingOpening(current, records).filter { $0.leaveOpening == nil }.count
    let ownEntitlements = current.contains(where: { ($0.annualLeaveDays ?? 0) > 0 })
    let footer = [
      "date": format.date(today),
      "days": format.quantity(PeMoney.round(PeLeave.annualDaysOn(today, policy: settings.leavePolicy) / 12, 2)),
    ]
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PePayrollHeader(tab: "leave")
      FlowLayout(spacing: 8) {
        WebButton(t("Leave reasons"), icon: .tags, variant: .outline, size: .sm) { router.push(.leaveReasons) }
        PwOpeningsButton()
        if !current.isEmpty { PwRecordLeaveButton() }
      }
      .padding(.bottom, 16)
      if current.isEmpty {
        Card {
          WebEmptyState(
            icon: .plane, title: t("No current employees"),
            description: t("Leave balances show here once you add employees."))
        }
      } else {
        Card {
          if needing > 0 {
            Text(
              tp(
                needing,
                "{count} employee has no opening leave balance: their leave is counted from their hire date.",
                "{count} employees have no opening leave balance: their leave is counted from their hire date.")
            )
            .font(.web(14))
            .foregroundStyle(palette[.amber(900)])
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(palette[.amber(50)].opacity(0.6))
          }
          PeRows {
            ForEach(current) { e in
              let own = records.filter { $0.employeeId == e.id }
              let away = own.first { $0.isTaken && $0.start <= today && $0.end >= today }
              let balance = PeLeave.employeeBalance(e, own, on: today, settings: settings).balance
              PeLineRow(
                title: e.displayName, detail: e.number,
                detail2: away.map {
                  t(
                    "{leave} until {date}",
                    ["leave": PeLeave.label($0, settings.leaveReasons), "date": format.date($0.end)])
                },
                trailing: {
                  Text(format.quantity(balance))
                    .font(.web(14, .medium, tabular: true))
                    .foregroundStyle(palette.slate(900))
                  if let opening = e.leaveOpening, !opening.confirmed { Badge(t("Not confirmed"), tone: .amber) }
                }, action: { router.push(.employee(id: e.id)) })
            }
          }
          ListCardFooter {
            Text(
              ownEntitlements
                ? t(
                  "Balances in days on {date}: {days} days a month, or each employee’s own entitlement, less leave taken.",
                  footer)
                : t("Balances in days on {date}: {days} days a month, less leave taken.", footer)
            )
            .font(.web(12))
          }
        }
      }
    }
  }
}

// MARK: - Leave reasons

/// `/payroll/leave-reasons`: the company's own reasons for leave and the two switches.
struct PeLeaveReasonsPage: View {
  var body: some View {
    PeGate {
      // Editable where the payroll settings may be saved on this iPhone.
      if PwKinds.can(PwKinds.payrollSettings) {
        PwLeaveReasonsView()
      } else {
        PeLeaveReasonsView()
      }
    }
  }
}

private struct PeLeaveReasonsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let settings = one.pePayrollSettings
    let used = Set(one.peLeaveRecords.compactMap(\.reasonId))
    let reasons = settings.leaveReasons.enumerated()
      .sorted { a, b in
        a.element.archived != b.element.archived ? !a.element.archived : a.offset < b.offset
      }
      .map { $0.element }
    let pause = settings.accrualPauseFrom
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PePayrollHeader(
        tab: "reasons",
        description: t("Reasons for leave of the company’s own, besides the six types of the Labour Law."))
      VStack(alignment: .leading, spacing: 24) {
        PeCard(
          t("Leave reasons"),
          description: t(
            "Such as emergency leave or compensatory days. Each one says how its leave is paid and what it does to the balances. Leave keeps the pay it was recorded with."
          )
        ) {
          PeSwitchRow(
            label: t("Offer these reasons when leave is recorded"),
            description: t(
              "Off: leave is recorded with the six types of the Labour Law only, as before. Leave already recorded with a reason keeps its pay either way."
            ), isOn: settings.leaveReasonsOn)
          PeNote(
            t(
              "Ask your auditor to confirm how each reason is paid before you switch them on: leave taken from annual leave lowers the annual leave balance and the leave salary provision, and leave on half pay or without pay lowers the month’s pay."
            ))
          if reasons.isEmpty {
            WebEmptyState(
              icon: .tags, title: t("No leave reasons yet"),
              description: t(
                "We recommend emergency leave taken from annual leave, and compensatory days added by hand. Any other reason starts on full pay; give it the most days a year it allows."
              ))
          } else {
            VStack(spacing: 0) {
              ForEach(reasons) { reason in
                PeReasonLine(reason: reason, inUse: used.contains(reason.id), format: format)
              }
            }
            .padding(.top, -1)
            .clipped()
            .border(palette.slate(200), in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
          }
        }
        PeCard(
          t("Long unpaid leave"),
          description: t(
            "Annual leave is earned for each month of service, counted from the hire date (or the opening balance).")
        ) {
          PeSwitchRow(
            label: t(
              "A month of service with more than {days} days of unpaid leave earns no annual leave", ["days": "15"]),
            description: t(
              "Off: every month of service earns annual leave, as before. Unpaid leave counts in calendar days; leave on half pay doesn’t count."
            ), isOn: pause != nil)
          PeNote(
            t(
              "Ask your auditor to confirm that a month of service with more than 15 days of unpaid leave earns no annual leave before you switch this on: it lowers the annual leave balance, the leave salary provision and the final settlement of staff on long unpaid leave."
            ))
          if let pause {
            PeFigureLine(label: t("From"), value: format.date(pause))
            PeHint(t("Months of service that start before this date earn as before."))
          }
        }
      }
    }
  }
}

/// A leave reason: its name, how it is paid and what older versions make of it.
private struct PeReasonLine: View {
  let reason: PeLeaveReason
  let inUse: Bool
  let format: CompanyFormat
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      FlowLayout(spacing: 8, lineSpacing: 4) {
        Text(reason.displayName).font(.web(14, .medium)).foregroundStyle(palette.slate(900))
        if reason.archived { Badge(t("Archived"), tone: .slate) }
        if inUse { Badge(t("In use"), tone: .blue) }
      }
      Text(details).font(.web(12)).foregroundStyle(palette.slate(500))
      if let older = PeLeave.reasonOlderText(reason) {
        Text(older).font(.web(12)).foregroundStyle(palette.slate(400))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }

  private var details: String {
    var parts = [PeLeave.reasonPayLabel(reason)]
    if let max = reason.maxDaysPerYear {
      parts.append(t("At most {days} days a year", ["days": format.quantity(max)]))
    }
    if !reason.categories.isEmpty {
      let separator = LanguageStore.shared.isArabic ? "، " : ", "
      let names = reason.categories.map { PePeople.categoryLabel($0) }.joined(separator: separator)
      parts.append(t("For: {categories}", ["categories": names]))
    }
    if reason.noteRequired { parts.append(t("A note is needed")) }
    return parts.joined(separator: " · ")
  }
}

// MARK: - Staff loans

/// `/payroll/loans`: every staff loan and advance with what is left to recover.
struct PeLoansPage: View {
  var body: some View {
    PeGate { PeLoansView() }
  }
}

private struct PeLoansView: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let one = model.one
    let format = one.format
    let p = one.pePrecision
    let runs = one.pePayRuns
    let settlements = one.peSettlements
    let byId = Dictionary(one.peEmployees.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let rows = Self.lines(one.peStaffLoans, runs: runs, settlements: settlements, p)
    let outstanding = Self.outstanding(rows, p)
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PePayrollHeader(tab: "loans")
      PwNewLoanButton()
        .padding(.bottom, 16)
      if rows.isEmpty {
        Card {
          WebEmptyState(
            icon: .handCoins, title: t("No loans or advances"),
            description: t(
              "Record an interest-free loan or salary advance; its instalments are deducted in each pay run."))
        }
      } else {
        VStack(alignment: .leading, spacing: 24) {
          PePair {
            PeStat(label: t("Still to recover"), value: format.money(outstanding), small: true)
          } second: {
            PeStat(label: t("Active loans"), value: format.count(rows.filter { $0.balance > 0 }.count))
          }
          ListCard {
            ForEach(rows) { row in
              ListRow(
                title: byId[row.loan.employeeId]?.displayName ?? "—", subtitle: subtitle(row.loan, format: format),
                amount: format.money(row.balance)
              ) {
                PeLoanBadge(loan: row.loan, balance: row.balance)
              } action: {
                router.push(.employee(id: row.loan.employeeId))
              }
            }
          }
        }
      }
    }
  }

  /// Each loan with what is left, the ones still running first, newest first.
  private static func lines(
    _ loans: [PeStaffLoan], runs: [PePayRun], settlements: [PeSettlementRecord], _ p: Int
  ) -> [PeLoanLine] {
    var lines: [PeLoanLine] = []
    for loan in loans {
      let balance: Double = PePayroll.loanBalance(loan, runs: runs, settlements: settlements, p)
      lines.append(PeLoanLine(loan: loan, balance: balance))
    }
    lines.sort { (a: PeLoanLine, b: PeLoanLine) -> Bool in
      let aOpen = a.balance > 0
      let bOpen = b.balance > 0
      if aOpen != bOpen { return aOpen }
      return a.loan.date > b.loan.date
    }
    return lines
  }

  /// What is still to recover, added in minor units.
  private static func outstanding(_ rows: [PeLoanLine], _ p: Int) -> Double {
    var minor: Int64 = 0
    for row in rows { minor += PeMoney.minor(row.balance, p) }
    return PeMoney.fromMinor(minor, p)
  }

  private func subtitle(_ loan: PeStaffLoan, format: CompanyFormat) -> String {
    if loan.payRunId != nil {
      return t(
        "PIFSS share owed from {month}", ["month": PePayroll.formatPeriod(PeDates.period(loan.date), format)])
    }
    return t(
      "Paid on {date}, from {month}",
      ["date": format.date(loan.date), "month": PePayroll.formatPeriod(loan.firstPeriod, format)])
  }
}

/// A loan and what is left on it.
private struct PeLoanLine: Identifiable {
  let loan: PeStaffLoan
  let balance: Double
  var id: String { loan.id }
}

// MARK: - Payroll settings

/// `/payroll/settings`: pay day, the salaries account, working days, the
/// overtime basis, the minimum wage, the PAM file; PIFSS and GCC rates; the
/// leave policy; provisions; the accounts the payroll posts to.
struct PePayrollSettingsPage: View {
  var body: some View {
    PeGate {
      // Editable where the payroll settings may be saved on this iPhone.
      if PwKinds.can(PwKinds.payrollSettings) {
        PwPayrollSettingsView()
      } else {
        PePayrollSettingsView()
      }
    }
  }
}

private struct PePayrollSettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let format = one.format
    let settings = one.pePayrollSettings
    let locked = PeLeave.annualLeaveRecorded(one.peLeaveRecords)
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PePayrollHeader(tab: "settings")
      VStack(alignment: .leading, spacing: 24) {
        PeCard(t("Pay")) {
          PeFigureLine(label: t("Pay day"), value: payDay(settings.payDay))
          PeHint(t("The pay date suggested for each month."))
          PeFigureLine(label: t("Salaries paid from"), value: bankAccount(settings))
          PeFigureLine(label: t("Working days in a month"), value: format.quantity(settings.dailyDivisor))
          PeHint(t("The daily rate is the monthly wage divided by this; 26 for a six-day week (art. 67)."))
          PeFigureLine(
            label: t("Overtime and unpaid absence use"),
            value: settings.rateBase == "basic" ? t("Basic salary only") : t("Basic salary and allowances"))
          PeHint(
            t(
              "Overtime is paid at 125%, on rest days 150% and on public holidays 200% of the hourly rate. Unpaid leave costs a share of the month’s pay."
            ))
          HStack(spacing: 8) {
            PeFigureLine(label: t("Minimum wage"), value: format.money(settings.minimumWage))
            Badge(t("Verify"), tone: .amber)
          }
          PeHint(t("Pay runs warn when net pay is below it. Commonly cited as {amount}.", ["amount": format.money(75)]))
          PeFigureLine(
            label: t("PAM file number"), value: settings.pamFileNumber.isEmpty ? "—" : settings.pamFileNumber)
          PeHint(t("Your company file with the Public Authority for Manpower, for the salary file."))
        }
        PeCard(
          t("PIFSS rates for Kuwaiti staff"),
          description: t(
            "Shares of the insured salary (basic salary and allowances) up to the cap. Rates apply from their date until newer ones."
          ),
          actions: { Badge(t("Verify"), tone: .amber) }
        ) {
          ForEach(0..<settings.pifss.count, id: \.self) { index in
            PeRatesLine(first: t("From"), value: format.date(settings.pifss[index].from), rates: settings.pifss[index])
          }
        }
        PeCard(
          t("GCC nationals"),
          description: t(
            "GCC nationals contribute to their home scheme through PIFSS. Enter the rates of each country you employ; until then they are paid without contributions."
          )
        ) {
          ForEach(0..<settings.gcc.count, id: \.self) { index in
            let scheme = settings.gcc[index]
            PeRatesLine(
              first: t("Country"), value: Geo.countryName(scheme.country, locale: format.locale.identifier),
              rates: scheme)
          }
        }
        PeLeavePolicyCard(policy: settings.leavePolicy, locked: locked)
        PeCard(t("Provisions")) {
          PeSwitchRow(
            label: t("Post end-of-service and leave provisions each month"),
            description: t(
              "When a pay run is approved, the end-of-service provision is brought to what everyone would get at the month end, and the leave salary provision to the value of unused leave."
            ), isOn: settings.provisions)
          PeSwitchRow(
            label: t("Include staff insured with PIFSS in the end-of-service provision"),
            description: t(
              "For Kuwaiti and GCC staff the employer pays only what PIFSS does not cover. Leave it off unless you owe them an indemnity."
            ), isOn: settings.eosForInsured)
        }
        PeCard(
          t("Accounts"),
          description: t("Where the payroll posts. Accounts that are missing are created when first used.")
        ) {
          ForEach(PePayrollAccounts.specs, id: \.key) { spec in
            PeFigureLine(label: PePayrollAccounts.label(spec.key), value: accountText(spec, settings: settings))
          }
        }
      }
    }
  }

  private func payDay(_ day: Int) -> String {
    day >= 31 ? t("Last day of the month") : t("Day {day} of the month", ["day": String(day)])
  }

  private func bankAccount(_ settings: PePayrollSettings) -> String {
    let one = model.one
    if let id = settings.bankAccountId, let account = one.record(.accounts, id) {
      return PePayrollAccounts.text(account)
    }
    if let main = one.records(.accounts).first(where: { $0.str("role") == "bank" }) {
      return t("{account} (default)", ["account": localName(main)])
    }
    return t("Default account")
  }

  private func accountText(_ spec: PeAccountSpec, settings: PePayrollSettings) -> String {
    if let account = PePayrollAccounts.account(spec.key, settings: settings, model.one) {
      return PePayrollAccounts.text(account)
    }
    return t(
      "{code} {name} (created when used)",
      ["code": spec.code, "name": localName(spec.name, spec.nameAr)])
  }
}

/// One set of contribution rates: from when (or which country), the shares and the cap.
private struct PeRatesLine: View {
  let first: String
  let value: String
  let rates: PeRates
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let format = model.one.format
    VStack(alignment: .leading, spacing: 6) {
      PeFigureLine(label: first, value: value)
      HStack(spacing: 12) {
        PeFigureLine(label: t("Employee %"), value: format.quantity(rates.employee))
        PeFigureLine(label: t("Employer %"), value: format.quantity(rates.employer))
        PeFigureLine(label: t("Salary cap"), value: rates.cap.map { format.money($0) } ?? t("None"))
      }
    }
    .padding(.vertical, 6)
    .overlay(alignment: .bottom) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }
}

/// The company's annual leave policy, or the law's.
private struct PeLeavePolicyCard: View {
  let policy: PeLeavePolicy?
  let locked: Bool
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let format = model.one.format
    if let policy {
      PeCard(
        t("Annual leave"),
        description: t(
          "Days a year are earned from their date on; balances before the first date are the law’s and don’t change.")
      ) {
        ForEach(0..<policy.annualDays.count, id: \.self) { index in
          HStack(spacing: 12) {
            PeFigureLine(label: t("From"), value: format.date(policy.annualDays[index].from))
            PeFigureLine(label: t("Days a year"), value: format.quantity(policy.annualDays[index].days))
          }
        }
        PeFigureLine(
          label: t("Months before the first leave"),
          value: tp(policy.firstYearMonths, "{count} month", "{count} months"))
        PeHint(t("Nine under the Labour Law (art. 70); fewer lets new staff take leave sooner."))
        PeFigureLine(
          label: t("Most days carried into a new year"),
          value: policy.carryForwardMax.map { format.quantity($0) } ?? t("No cap"))
        PeHint(
          t(
            "Unused days above it are lost when a new year starts. Leave it empty to carry every day forward: unused days are paid when the employee leaves (art. 73)."
          ))
        PeFigureLine(
          label: t("Leave is counted in"),
          value: policy.counting == "calendar" ? t("Calendar days") : t("Working days"))
        PeHint(
          locked
            ? t("Annual leave has been recorded, so the way it is counted stays as it is.")
            : t("Working days skip Fridays, Saturdays and public holidays."))
      }
    } else {
      PeCard(
        t("Annual leave"),
        description: t(
          "The law’s leave applies: 30 working days a year, 2.5 days for each month of service, usable after nine months (art. 70). Unused days carry forward and are paid when the employee leaves (art. 73)."
        )
      ) {
        Text(
          t(
            "Set a policy for more days a year, contract entitlements, a cap on the days carried forward, or leave counted in calendar days. Balances before the date it applies from don’t change."
          )
        )
        .font(.web(14))
        .foregroundStyle(palette.slate(600))
      }
    }
  }
}
