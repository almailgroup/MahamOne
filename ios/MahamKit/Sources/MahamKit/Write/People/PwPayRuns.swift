import Foundation

// Pay runs: the port of src/db/payroll.ts (`createPayRun`, `refreshPayRun`,
// `updatePayLine`, `updatePayRun`, `deletePayRun`, `approvePayRun`,
// `payPayRun`, `undoPayRunPayment`, `reopenPayRun`) with its lines worked out
// from the employees, their leave and their loans.

public enum PwPayRuns {
  // MARK: Lines

  /// `onPayroll`: hired by the month's end, not gone before its start, not paid in a settlement.
  static func onPayroll(_ e: JSONValue, _ period: String, _ settlements: [JSONValue]) -> Bool {
    let hire = e.pwStr("hireDate")
    if !hire.isEmpty && WebJS.less(PwPay.periodEnd(period), hire) { return false }
    if e.pwStr("status") == "left" {
      let leaving = e.pwStr("leavingDate")
      if leaving.isEmpty || WebJS.less(leaving, PwPay.periodStart(period)) { return false }
    }
    return !settlements.contains { s in
      s.pwStr("employeeId") == e.pwId && s.pwStr("status") != "reversed"
        && s["lastSalary"]?.pwText("period") == period
    }
  }

  private static func sortLines(_ lines: [JSONValue]) -> [JSONValue] {
    PwSort.stable(lines) { a, b in
      let order = PwSort.localeCompare(a.pwStr("number"), b.pwStr("number"), numeric: true)
      return order != 0 ? order : PwSort.localeCompare(a.pwStr("name"), b.pwStr("name"))
    }
  }

  /// `loanRecoveries`: instalments due in the month on the employee's active loans.
  private static func loanRecoveries(
    _ employeeId: String, _ period: String, _ c: PwPayrollContext, runId: String, previous: [JSONValue]?
  ) -> [JSONValue] {
    let loans = PwSort.stable(c.loans) { a, b in
      let order = PwSort.localeCompare(a.pwStr("date"), b.pwStr("date"))
      return order != 0 ? order : PwSort.localeCompare(a.pwStr("createdAt"), b.pwStr("createdAt"))
    }
    var out: [JSONValue] = []
    for loan in loans {
      if loan.pwStr("employeeId") != employeeId || loan.pwStr("status") != "active"
        || WebJS.less(period, loan.pwStr("firstPeriod"))
      {
        continue
      }
      let left = PwPayroll.loanBalance(loan, runs: c.runs, settlements: c.settlements, precision: c.precision, except: runId)
      if left <= 0 { continue }
      let before = previous?.first { $0.pwStr("loanId") == loan.pwId }
      let amount = min(before.map { $0.pwNum("amount") } ?? loan.pwNum("instalment"), left)
      if before != nil || amount > 0 {
        out.append(["loanId": .string(loan.pwId), "amount": .number(PwM.round(amount, c.precision))])
      }
    }
    return out
  }

  /// `leaveDetailOf`: the month's leave of the company's reasons, for the payslip.
  private static func leaveDetail(_ byReason: [PwLeave.ByReason], _ reasons: [JSONValue]) -> JSONValue? {
    if byReason.isEmpty { return nil }
    return .array(
      byReason.map { x in
        let reason = PwLeave.reasonOf(x.reasonId, reasons)
        var fields: [String: JSONValue] = [
          "reasonId": .string(x.reasonId),
          "name": reason?["name"].flatMap { WebJS.present($0) } ?? .string(PwLeave.typeInfo(x.type).label),
          "nameAr": reason?["nameAr"].flatMap { WebJS.present($0) } ?? "",
          "days": .number(Double(x.days)), "percent": .number(x.percent),
        ]
        if x.type == "annual" { fields["fromAnnual"] = true }
        return .object(fields)
      })
  }

  /// `buildLine`: an employee's line, keeping what was entered on `previous`.
  private static func buildLine(
    _ ctx: WriteContext, _ e: JSONValue, _ run: JSONValue, _ c: PwPayrollContext, previous: JSONValue?
  ) -> JSONValue {
    let period = run.pwStr("period")
    let leavingDate: JSONValue = e.pwStr("status") == "left" ? (e["leavingDate"] ?? .null) : .null
    let leave = PwLeave.inPeriod(
      c.leave.filter { $0.pwStr("employeeId") == e.pwId }, period, c.dayOff, from: e.pwText("hireDate"),
      to: leavingDate.string, policy: WebJS.present(c.settings["leavePolicy"]))
    let id = previous?.pwText("id") ?? ctx.newId()
    var line: [String: JSONValue] = [
      "id": .string(id), "employeeId": .string(e.pwId), "number": e["number"] ?? .null, "name": e["name"] ?? .null,
      "nameAr": WebJS.present(e["nameAr"]) ?? "", "jobTitle": e["jobTitle"] ?? .null,
      "jobTitleAr": WebJS.present(e["jobTitleAr"]) ?? "", "department": .string(WebJS.trim(e.pwStr("department"))),
      "category": e["category"] ?? .null, "nationality": e["nationality"] ?? .null, "civilId": e["civilId"] ?? .null,
      "iban": e["iban"] ?? .null, "accountNumber": WebJS.present(e["accountNumber"]) ?? "",
      "hireDate": e["hireDate"] ?? .null, "leavingDate": leavingDate, "permitSalary": e["permitSalary"] ?? .null,
      "monthlyBasic": e["basicSalary"] ?? .null,
      "allowances": .array(
        e.pwList("allowances").map { a in
          [
            "id": a["id"] ?? .null, "name": a["name"] ?? .null, "nameAr": WebJS.present(a["nameAr"]) ?? "",
            "monthly": a["amount"] ?? .null, "amount": 0,
          ]
        }),
      "daysWorked": .number(
        Double(PwPay.employedDays(period, hire: e.pwText("hireDate"), leaving: leavingDate.string))),
      "daysInMonth": .number(Double(PwPay.daysInPeriod(period))),
      "overtime": WebJS.present(previous?["overtime"]) ?? ["normal": 0, "restDay": 0, "holiday": 0],
      "absentDays": WebJS.present(previous?["absentDays"]) ?? 0,
      "unpaidLeaveDays": .number(Double(leave.working.unpaidDays)), "reducedPay": .array(leave.working.reducedPay),
      "calendarLeave": leave.calendar.json,
      "adjustments": WebJS.present(previous?["adjustments"]) ?? [],
      "loans": .array(
        loanRecoveries(e.pwId, period, c, runId: run.pwId, previous: previous.map { $0.pwList("loans") })),
    ]
    for key in [
      "basic", "allowanceTotal", "overtimePay", "absenceDeduction", "additions", "gross", "pifssBase", "pifssEmployee",
      "pifssEmployer", "loanDeduction", "otherDeductions", "net",
    ] {
      line[key] = 0
    }
    if PwEmployees.isStateless(e), e.pwTruthy("centralCardNumber") { line["centralCardNumber"] = e["centralCardNumber"] }
    if let byReason = leave.byReason, let detail = leaveDetail(byReason, c.settings.pwList("leaveReasons")) {
      line["leaveDetail"] = detail
    }
    let p = c.precision
    let rules = run["rules"] ?? .object([:])
    let worked = PwPay.calculate(.object(line), rules, p)
    // PIFSS shares owed from earlier months are recovered only from pay that
    // covers them, within the 10% of the wage loan recoveries may take.
    func owed(_ r: JSONValue) -> Bool {
      c.loans.first { $0.pwId == r.pwStr("loanId") }.map { $0.pwTruthy("payRunId") } ?? false
    }
    let recovering = worked.pwList("loans")
    let owedMinor = recovering.filter(owed).reduce(Int64(0)) { $0 + PwM.minor($1.pwNum("amount"), p) }
    if owedMinor == 0 { return worked }
    let otherMinor = PwM.minor(worked.pwNum("loanDeduction"), p) - owedMinor
    let cap = PwM.minor(
      PwM.round(PwM.dec(worked.pwNum("gross")) * PwM.dec(PwPay.loanCapPercent) / 100, p), p)
    var room = max(0, min(cap - otherMinor, PwM.minor(worked.pwNum("net"), p) + owedMinor))
    var loans: [JSONValue] = []
    for r in recovering {
      if !owed(r) {
        loans.append(r)
        continue
      }
      let amount = min(PwM.minor(r.pwNum("amount"), p), room)
      room -= amount
      if amount > 0 { loans.append(r.pwWith("amount", .number(PwM.fromMinor(amount, p)))) }
    }
    return PwPay.calculate(worked.pwWith("loans", .array(loans)), rules, p)
  }

  /// `linesFor`: employees on the payroll in the month, as lines.
  static func linesFor(_ ctx: WriteContext, _ run: JSONValue, _ c: PwPayrollContext, previous: [JSONValue] = [])
    -> [JSONValue]
  {
    var before: [String: JSONValue] = [:]
    for line in previous { before[line.pwStr("employeeId")] = line }
    let period = run.pwStr("period")
    let lines = c.employees.filter { onPayroll($0, period, c.settlements) }.map {
      buildLine(ctx, $0, run, c, previous: before[$0.pwId])
    }
    return sortLines(lines)
  }

  // MARK: Stamps

  /// Milliseconds of a `toISOString()` stamp; nil for anything else (`Date.parse` is NaN).
  static func milliseconds(_ stamp: String) -> Int64? {
    let bytes = Array(stamp.utf8)
    guard bytes.count == 24, bytes[4] == 45, bytes[7] == 45, bytes[10] == 84, bytes[13] == 58, bytes[16] == 58,
      bytes[19] == 46, bytes[23] == 90
    else { return nil }
    func number(_ range: Range<Int>) -> Int? {
      var n = 0
      for i in range {
        guard bytes[i] >= 48 && bytes[i] <= 57 else { return nil }
        n = n * 10 + Int(bytes[i] - 48)
      }
      return n
    }
    guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10), let hour = number(11..<13),
      let minute = number(14..<16), let second = number(17..<19), let ms = number(20..<23)
    else { return nil }
    let days = Int64(CivilDay(year: year, month: month, day: day).dayNumber)
    return ((days * 24 + Int64(hour)) * 60 + Int64(minute)) * 60_000 + Int64(second) * 1000 + Int64(ms)
  }

  /// `changedStamp(run)`: always later than when the draft was last changed.
  static func changedStamp(_ ctx: WriteContext, _ run: JSONValue) -> String {
    let now = ctx.stamp
    let updatedAt = run.pwStr("updatedAt")
    if WebJS.less(updatedAt, now) { return now }
    guard let before = milliseconds(updatedAt) else { return now }
    return Defaults.isoString(milliseconds: before + 1)
  }

  static func loadRun(_ ctx: WriteContext, _ id: String) throws -> JSONValue {
    guard let run = ctx.get("payRuns", id) else { throw pwFail("This pay run could not be found.") }
    return run
  }

  static func assertDraft(_ run: JSONValue) throws {
    if run.pwStr("status") != "draft" { throw pwFail("Only a draft pay run can be changed. Reopen it first.") }
  }

  // MARK: Drafts

  /// `createPayRun(companyId, period)`: every employee on the payroll that month.
  @discardableResult
  public static func create(_ ctx: WriteContext, period: String) throws -> JSONValue {
    if !PwPay.isPeriod(period) { throw pwFail("Choose a month.") }
    let c = try PwPayrollContext(ctx)
    if c.runs.contains(where: { $0.pwStr("period") == period }) {
      throw pwFail("There is already a pay run for this month.")
    }
    var run: JSONValue = [
      "id": .string(ctx.newId()), "companyId": .string(ctx.companyId), "period": .string(period), "status": "draft",
      "date": .string(PwPay.periodEnd(period)),
      "payDate": .string(PwPay.payDate(period, c.settings.pwNumber("payDay") ?? .nan)), "lines": [],
      "rules": PwSettings.payRules(c.settings, period), "deductionAccountId": .null, "journalId": .null,
      "provisionJournalId": .null, "provisions": .null, "paidOn": .null, "paymentJournalId": .null,
      "bankAccountId": .null, "reversalJournalIds": [], "notes": "", "createdAt": .string(ctx.stamp),
      "updatedAt": .string(ctx.stamp),
    ]
    let lines = linesFor(ctx, run, c)
    run.set("lines", .array(lines))
    if lines.isEmpty { throw pwFail("No employees were on the payroll in this month.") }
    ctx.put("payRuns", run)
    PwLog.add(ctx, "payroll", run.pwId, "created", "Pay run {period} prepared", vars: ["period": .text(period)])
    return run
  }

  /// `refreshPayRun(id)`: a draft brought up to date, keeping overtime, absence and adjustments.
  @discardableResult
  public static func refresh(_ ctx: WriteContext, id: String) throws -> JSONValue {
    let run = try loadRun(ctx, id)
    try assertDraft(run)
    let c = try PwPayrollContext(ctx)
    let rules = PwSettings.payRules(c.settings, run.pwStr("period"))
    var next = run.pwMerging(["rules": rules, "updatedAt": .string(changedStamp(ctx, run))])
    let lines = linesFor(ctx, next, c, previous: run.pwList("lines"))
    next.set("lines", .array(lines))
    // Nothing changed: the run stays as it is, so an approval of it still holds.
    if Roles.sameData(next["rules"], run["rules"]) && Roles.sameData(next["lines"], run["lines"]) { return run }
    ctx.put("payRuns", next)
    return next
  }

  /// What is entered for one employee (`PayLineChanges`).
  public struct LineChanges: Sendable {
    public var overtime: (normal: Double, restDay: Double, holiday: Double)?
    public var absentDays: Double?
    /// `{ id, type, amount, note }`.
    public var adjustments: [JSONValue]?
    /// `{ loanId, amount }`.
    public var loans: [JSONValue]?

    public init(
      overtime: (normal: Double, restDay: Double, holiday: Double)? = nil, absentDays: Double? = nil,
      adjustments: [JSONValue]? = nil, loans: [JSONValue]? = nil
    ) {
      self.overtime = overtime
      self.absentDays = absentDays
      self.adjustments = adjustments
      self.loans = loans
    }
  }

  /// `updatePayLine(runId, lineId, changes)`.
  @discardableResult
  public static func updateLine(_ ctx: WriteContext, runId: String, lineId: String, _ changes: LineChanges) throws
    -> JSONValue
  {
    let run = try loadRun(ctx, runId)
    try assertDraft(run)
    let company = try PwPayroll.company(ctx, run.pwStr("companyId"))
    let p = PwM.places(company.pwStr("currency"))
    func hours(_ n: Double) -> Double { n.isFinite ? max(0, PwM.jsRound(n * 100) / 100) : 0 }
    func money(_ n: Double) -> Double { n.isFinite ? max(0, PwM.round(n, p)) : 0 }
    let rules = run["rules"] ?? .object([:])
    let lines = run.pwList("lines").map { line -> JSONValue in
      guard line.pwStr("id") == lineId else { return line }
      var next = line.pwFields
      if let overtime = changes.overtime {
        next["overtime"] = [
          "normal": .number(hours(overtime.normal)), "restDay": .number(hours(overtime.restDay)),
          "holiday": .number(hours(overtime.holiday)),
        ]
      }
      if let absent = changes.absentDays {
        next["absentDays"] = .number(min(hours(absent), line.pwNum("daysInMonth")))
      }
      if let adjustments = changes.adjustments {
        let tidy = adjustments.map { a -> JSONValue in
          let id = a.pwStr("id")
          return [
            "id": .string(id.isEmpty ? ctx.shortId() : id),
            "type": a.pwStr("type") == "deduction" ? "deduction" : "addition",
            "amount": .number(money(a["amount"]?.double ?? .nan)), "note": .string(WebJS.trim(a.pwStr("note"))),
          ]
        }
        next["adjustments"] = .array(tidy.filter { $0.pwNum("amount") > 0 || !$0.pwStr("note").isEmpty })
      }
      if let loans = changes.loans {
        next["loans"] = .array(
          line.pwList("loans").map { l in
            guard let changed = loans.first(where: { $0.pwStr("loanId") == l.pwStr("loanId") }) else { return l }
            return l.pwWith("amount", .number(money(changed["amount"]?.double ?? .nan)))
          })
      }
      return PwPay.calculate(.object(next), rules, p)
    }
    let next = run.pwMerging(["lines": .array(lines), "updatedAt": .string(changedStamp(ctx, run))])
    ctx.put("payRuns", next)
    return next
  }

  /// `updatePayRun(id, changes)`: the pay date (until paid), the deductions account or the notes.
  @discardableResult
  public static func updateRun(
    _ ctx: WriteContext, id: String, payDate: String? = nil, deductionAccountId: String?? = nil, notes: String? = nil
  ) throws -> JSONValue {
    let run = try loadRun(ctx, id)
    var next = run.pwWith("updatedAt", .string(changedStamp(ctx, run)))
    if let payDate {
      if run.pwStr("status") == "paid" { throw pwFail("This pay run is already paid.") }
      if !PwDates.isDate(payDate) { throw pwFail("Enter the pay date.") }
      next.set("payDate", .string(payDate))
    }
    if let deductionAccountId {
      try assertDraft(run)
      next.set("deductionAccountId", .pwOptional(deductionAccountId))
    }
    if let notes { next.set("notes", .string(WebJS.trim(notes))) }
    ctx.put("payRuns", next)
    return next
  }

  /// `deletePayRun(id)`: a draft that was never approved.
  public static func delete(_ ctx: WriteContext, id: String) throws {
    let run = try loadRun(ctx, id)
    try assertDraft(run)
    if !run.pwList("reversalJournalIds").isEmpty {
      throw pwFail("This pay run was approved before, so it is kept. Change it and approve it again.")
    }
    ctx.delete("payRuns", id)
    PwLog.add(ctx, "payroll", id, "deleted", "Pay run {period} deleted", vars: ["period": .text(run.pwStr("period"))])
  }

  // MARK: Posting

  /// `employedOn`: employed at the end of a day.
  private static func employedOn(_ e: JSONValue, _ date: String) -> Bool {
    let hire = e.pwStr("hireDate")
    if !hire.isEmpty && WebJS.less(date, hire) { return false }
    let leaving = e.pwStr("leavingDate")
    return !(e.pwStr("status") == "left" && !leaving.isEmpty && !WebJS.less(date, leaving))
  }

  /// `provisionLines`: each current employee's indemnity and unused leave at a month end.
  static func provisionLines(_ c: PwPayrollContext, _ date: String, _ rules: JSONValue) -> [JSONValue] {
    let p = c.precision
    let pause = PwLeave.pauseFrom(c.settings)
    let policy = WebJS.present(c.settings["leavePolicy"])
    return c.employees.filter { employedOn($0, date) }.map { e in
      let insured = ["kuwaiti", "gcc"].contains(e.pwStr("category"))
      let eos =
        !c.settings.pwTruthy("eosForInsured") && insured
        ? 0 : PwPay.eosProvision(e, on: date, divisor: c.people.pwNum("eosDailyDivisor"), p)
      let balance = PwLeave.employeeBalance(e, c.leave, on: date, policy: policy, pauseFrom: pause).balance
      let leaveDays = max(0, balance)
      let wage = e.pwList("allowances").reduce(PwM.minor(e.pwNum("basicSalary"), p)) {
        $0 + PwM.minor($1.pwNum("amount"), p)
      }
      return [
        "employeeId": .string(e.pwId), "eos": .number(eos), "leaveDays": .number(leaveDays),
        "leave": .number(PwPay.leaveValue(leaveDays, PwM.fromMinor(wage, p), rules.pwNum("dailyDivisor"), p)),
      ]
    }
  }

  /// `assertLeaveDetail`: a line without the month's leave by reason is worked out again first.
  private static func assertLeaveDetail(_ lines: [JSONValue], _ run: JSONValue, _ c: PwPayrollContext) throws {
    let withReasons = Set(
      c.leave.filter { $0.pwTruthy("reasonId") && $0.pwStr("kind") == "leave" }.map { $0.pwStr("employeeId") })
    if withReasons.isEmpty { return }
    for line in lines {
      if line.pwTruthy("leaveDetail") || !withReasons.contains(line.pwStr("employeeId")) { continue }
      let leave = PwLeave.inPeriod(
        c.leave.filter { $0.pwStr("employeeId") == line.pwStr("employeeId") }, run.pwStr("period"), c.dayOff,
        from: line.pwText("hireDate"), to: line.pwText("leavingDate"), policy: WebJS.present(c.settings["leavePolicy"]))
      if leave.byReason != nil {
        throw pwFail(
          "The pay of {name} doesn’t show their leave by reason: it was worked out before that leave was recorded, or on an older version of the app. Click Update from records, then approve.",
          ["name": line.pwStr("name")])
      }
    }
  }

  /// `postingChecks`: what stops a draft from being posted; the lines as they are posted.
  static func postingChecks(_ run: JSONValue, _ c: PwPayrollContext, text: PwText) throws -> [JSONValue] {
    let p = c.precision
    if run.pwList("lines").isEmpty { throw pwFail("This pay run has no employees.") }
    let rules = run["rules"] ?? .object([:])
    let lines = run.pwList("lines").map { PwPay.calculate($0, rules, p) }
    let negative = lines.filter { PwPay.warnings($0, rules, p).contains("negative_net") }
    if !negative.isEmpty {
      throw pwFail(
        "Net pay can’t be below zero. Lower the deductions of {names}.",
        ["names": negative.map { $0.pwStr("name") }.joined(separator: ", ")])
    }
    for line in lines {
      let settled = c.settlements.contains { s in
        s.pwStr("employeeId") == line.pwStr("employeeId") && s.pwStr("status") != "reversed"
          && s["lastSalary"]?.pwText("period") == run.pwStr("period")
      }
      if settled {
        throw pwFail(
          "{name} was paid for this month in a final settlement. Update the pay run.", ["name": line.pwStr("name")])
      }
      for recovery in line.pwList("loans") {
        let loan = c.loans.first { $0.pwId == recovery.pwStr("loanId") }
        let left =
          loan?.pwStr("status") == "active"
          ? PwPayroll.loanBalance(loan!, runs: c.runs, settlements: c.settlements, precision: p, except: run.pwId) : 0
        if PwM.minor(recovery.pwNum("amount"), p) > PwM.minor(left, p) {
          throw pwFail(
            "The loan recovery of {name} is more than what is left on the loan. Update the pay run.",
            ["name": line.pwStr("name")])
        }
      }
    }
    try assertLeaveDetail(lines, run, c)
    try PwLedger.assertOpen(c.company, text, run.pwText("date"))
    return lines
  }

  /// What approving a run did: the run, and the request to mark done after (#10).
  public struct Approved: Sendable {
    public var run: JSONValue
    /// Save `PwApprovals.markApplied` with it on its own, once the posting is saved.
    public var requestId: String?
  }

  /// `approvePayRun(id)`: posted in one entry on the month's last day, then the provisions.
  @discardableResult
  public static func approve(_ ctx: WriteContext, id: String, link: PwLink?, text: PwText = .english) throws
    -> Approved
  {
    let run = try loadRun(ctx, id)
    try assertDraft(run)
    let c = try PwPayrollContext(ctx)
    let company = c.company
    let p = c.precision
    let lines = try postingChecks(run, c, text: text)
    let done = try PwApprovals.gate(company, link, run, PwApprovals.requests(ctx, runId: run.pwId))
    let totals = PwPay.totals(lines, p)
    let period = run.pwStr("period")
    var keys: [PwAccountKey] = [.salaries, .allowances, .pifssExpense, .salariesPayable, .pifssPayable, .advances]
    if totals.otherDeductions > 0 { keys.append(.otherDeductions) }
    let accounts = PwLedger.ensure(
      ctx, company, c.settings, keys, overrides: [.otherDeductions: run.pwText("deductionAccountId")])
    let journal = try PwLedger.postEntry(
      ctx, company, accounts, PwPay.runPostings(totals, p), date: run.pwStr("date"), sourceId: run.pwId,
      reference: text.t("Payroll {period}", ["period": period]), text: text)

    var provisions: JSONValue = .null
    var provisionJournal: JSONValue?
    if c.settings.pwTruthy("provisions") {
      let shares = provisionLines(c, run.pwStr("date"), run["rules"] ?? .object([:]))
      provisions = .array(shares)
      let provisionAccounts = PwLedger.ensure(
        ctx, company, c.settings, [.eosExpense, .eosProvision, .leaveExpense, .leaveProvision])
      let eosTarget = shares.reduce(Int64(0)) { $0 + PwM.minor($1.pwNum("eos"), p) }
      let leaveTarget = shares.reduce(Int64(0)) { $0 + PwM.minor($1.pwNum("leave"), p) }
      let eosId = provisionAccounts[.eosProvision] ?? ""
      let leaveId = provisionAccounts[.leaveProvision] ?? ""
      let held = try PwLedger.balances(ctx, company, [eosId, leaveId], on: run.pwStr("date"))
      let eosHeld = -(held[eosId] ?? 0)
      let leaveHeld = -(held[leaveId] ?? 0)
      provisionJournal = try PwLedger.postEntry(
        ctx, company, provisionAccounts, PwPay.provisionPostings(eosTarget - eosHeld, leaveTarget - leaveHeld),
        date: run.pwStr("date"), sourceId: run.pwId,
        reference: text.t("Payroll provisions {period}", ["period": period]), text: text)
    }

    // The PIFSS shares the pay didn't cover are owed by the employees: a loan
    // recovers each one from a later salary, at most 10% of the wage a month.
    for line in lines {
      let owed = line.pwNum("pifssOwed")
      if !(owed > 0) { continue }
      let cap = PwM.round(PwPay.monthlyWage(line) * PwM.dec(PwPay.loanCapPercent) / 100, p)
      let loan = PwPayroll.createLoan(
        ctx, employeeId: line.pwStr("employeeId"),
        [
          "id": .string(PwPayroll.owedLoanId(run.pwId, line.pwStr("employeeId"))), "date": run["date"] ?? .null,
          "amount": .number(owed), "instalment": .number(cap > 0 && cap < owed ? cap : owed),
          "firstPeriod": .string(PwPay.addPeriods(period, 1)), "payRunId": .string(run.pwId),
        ])
      ctx.put("staffLoans", loan)
    }

    let next = run.pwMerging([
      "lines": .array(lines), "status": "approved", "journalId": .pwOptional(journal?.pwId),
      "provisionJournalId": .pwOptional(provisionJournal?.pwId), "provisions": provisions,
      "updatedAt": .string(ctx.stamp),
    ])
    ctx.put("payRuns", next)
    PwLog.add(ctx, "payroll", run.pwId, "approved", "Pay run {period} approved", vars: ["period": .text(period)])
    return Approved(run: next, requestId: done?.pwId)
  }

  /// `payPayRun(id, { date, bankAccountId })`: Dr salaries payable, Cr bank on the payment date.
  @discardableResult
  public static func pay(_ ctx: WriteContext, id: String, date: String, bankAccountId: String? = nil, text: PwText = .english)
    throws -> JSONValue
  {
    let run = try loadRun(ctx, id)
    if run.pwStr("status") != "approved" { throw pwFail("Approve the pay run before recording the payment.") }
    let c = try PwPayrollContext(ctx)
    if !PwDates.isDate(date) { throw pwFail("Enter the payment date.") }
    try PwLedger.assertOpen(c.company, text, date)
    let bank = try PwLedger.moneyAccount(ctx, bankAccountId, c.settings.pwText("bankAccountId"))
    let net = PwPay.totals(run.pwList("lines"), c.precision).net
    var paymentJournalId: String?
    if net > 0 {
      let accounts = PwLedger.ensure(ctx, c.company, c.settings, [.salariesPayable])
      let journal = try PwLedger.postPayment(
        ctx, debit: accounts[.salariesPayable] ?? "", bank: bank.pwId, amount: net, date: date, sourceId: run.pwId,
        reference: text.t("Salaries {period} paid", ["period": run.pwStr("period")]), text: text)
      paymentJournalId = journal.pwId
    }
    let next = run.pwMerging([
      "status": "paid", "paidOn": .string(date), "bankAccountId": .string(bank.pwId),
      "paymentJournalId": .pwOptional(paymentJournalId), "updatedAt": .string(ctx.stamp),
    ])
    ctx.put("payRuns", next)
    PwLog.add(ctx, "payroll", run.pwId, "paid", "Pay run {period} paid", vars: ["period": .text(run.pwStr("period"))])
    return next
  }

  /// `undoPayRunPayment(id)`: the payment reversed on its date.
  @discardableResult
  public static func undoPayment(_ ctx: WriteContext, id: String, text: PwText = .english) throws -> JSONValue {
    let run = try loadRun(ctx, id)
    if run.pwStr("status") != "paid" { throw pwFail("This pay run is not paid.") }
    let company = try PwPayroll.company(ctx, run.pwStr("companyId"))
    try PwLedger.assertOpen(company, text, run.pwText("paidOn"))
    let reversal = try PwLedger.reverseEntry(ctx, run.pwText("paymentJournalId"), text: text)
    let next = run.pwMerging([
      "status": "approved", "paidOn": .null, "paymentJournalId": .null,
      "reversalJournalIds": .array(run.pwList("reversalJournalIds") + (reversal.map { [.string($0)] } ?? [])),
      "updatedAt": .string(ctx.stamp),
    ])
    ctx.put("payRuns", next)
    PwLog.add(
      ctx, "payroll", run.pwId, "payment_undone", "Payment of pay run {period} undone",
      vars: ["period": .text(run.pwStr("period"))])
    return next
  }

  /// `reopenPayRun(id)`: an approved, unpaid run back to a draft, its entries reversed.
  @discardableResult
  public static func reopen(_ ctx: WriteContext, id: String, text: PwText = .english) throws -> JSONValue {
    let run = try loadRun(ctx, id)
    if run.pwStr("status") == "paid" { throw pwFail("Undo the payment before reopening the pay run.") }
    if run.pwStr("status") != "approved" { throw pwFail("This pay run is not approved.") }
    let company = try PwPayroll.company(ctx, run.pwStr("companyId"))
    try PwLedger.assertOpen(company, text, run.pwText("date"))
    let owed = ctx.pwAll("staffLoans").filter { $0.pwStr("payRunId") == run.pwId && $0.pwStr("status") == "active" }
    if !owed.isEmpty {
      let p = PwM.places(company.pwStr("currency"))
      let runs = ctx.pwAll("payRuns")
      let settlements = ctx.pwAll("finalSettlements")
      if let recovered = owed.first(where: {
        PwPayroll.recoveredMinor($0.pwId, runs: runs, settlements: settlements, p) > 0
      }) {
        let name =
          run.pwList("lines").first { $0.pwStr("employeeId") == recovered.pwStr("employeeId") }?.pwStr("name") ?? ""
        throw pwFail(
          "The PIFSS share {name} owed from this pay run was already recovered from a later salary or a final settlement. Reopen or reverse that first.",
          ["name": name])
      }
      for loan in owed { ctx.put("staffLoans", loan.pwMerging(["status": "cancelled", "updatedAt": .string(ctx.stamp)])) }
    }
    let first = try PwLedger.reverseEntry(ctx, run.pwText("journalId"), text: text)
    let second = try PwLedger.reverseEntry(ctx, run.pwText("provisionJournalId"), text: text)
    let reversals = [first, second].compactMap { $0 }.map { JSONValue.string($0) }
    let next = run.pwMerging([
      "status": "draft", "journalId": .null, "provisionJournalId": .null, "provisions": .null,
      "reversalJournalIds": .array(run.pwList("reversalJournalIds") + reversals), "updatedAt": .string(ctx.stamp),
    ])
    ctx.put("payRuns", next)
    PwLog.add(
      ctx, "payroll", run.pwId, "reopened", "Pay run {period} reopened", vars: ["period": .text(run.pwStr("period"))])
    return next
  }

  /// The checks of approving, for the page to say beforehand what stops it (`assertPayRunPostable`).
  public static func assertPostable(_ ctx: WriteContext, id: String, text: PwText = .english) throws {
    guard let run = ctx.get("payRuns", id), run.pwStr("status") == "draft", !run.pwList("lines").isEmpty else { return }
    _ = try postingChecks(run, PwPayrollContext(ctx), text: text)
  }
}
