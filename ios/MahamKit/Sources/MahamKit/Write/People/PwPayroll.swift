import Foundation

// Staff loans and leave records: the ports of src/db/payroll.ts
// (`createStaffLoan`, `saveStaffLoan`, `cancelStaffLoan`,
// `createLeaveRecord`, `saveLeaveRecord`, `cancelLeaveRecord`), with what
// the pay runs and settlements share (`loadContext`, `loanBalance`).

/// What a payroll action reads of the company (`loadContext`).
struct PwPayrollContext {
  let company: JSONValue
  let precision: Int
  let settings: JSONValue
  let people: JSONValue
  let employees: [JSONValue]
  let leave: [JSONValue]
  let loans: [JSONValue]
  let runs: [JSONValue]
  let settlements: [JSONValue]
  let dayOff: PwDayOff

  init(_ ctx: WriteContext) throws {
    company = try PwPayroll.company(ctx)
    precision = PwM.places(company.pwStr("currency"))
    settings = PwSettings.payroll(ctx)
    people = PwSettings.people(ctx)
    employees = ctx.pwAll("employees")
    leave = ctx.pwAll("leaveRecords")
    loans = ctx.pwAll("staffLoans")
    runs = ctx.pwAll("payRuns")
    settlements = ctx.pwAll("finalSettlements")
    dayOff = PwDayOff(company: company)
  }
}

public enum PwPayroll {
  /// `loadCompany`.
  static func company(_ ctx: WriteContext, _ id: String? = nil) throws -> JSONValue {
    guard let company = ctx.get("companies", id ?? ctx.companyId) else { throw pwFail("Company not found.") }
    return company
  }

  // MARK: Loans

  private static func recoveries(_ loanId: String, _ list: [JSONValue]) -> [Double] {
    list.filter { $0.pwStr("loanId") == loanId }.map { $0.pwNum("amount") }
  }

  /// `loanRecoveredMinor`: recovered by approved pay runs and posted settlements.
  static func recoveredMinor(
    _ loanId: String, runs: [JSONValue], settlements: [JSONValue], _ p: Int, except: String? = nil
  ) -> Int64 {
    var amounts: [Double] = []
    for run in runs where run.pwStr("status") != "draft" && run.pwId != except {
      for line in run.pwList("lines") { amounts += recoveries(loanId, line.pwList("loans")) }
    }
    for s in settlements where s.pwStr("status") != "reversed" {
      amounts += recoveries(loanId, s.pwList("loans"))
    }
    return amounts.reduce(Int64(0)) { $0 + PwM.minor($1, p) }
  }

  /// `loanBalance`: what the employee still owes on a loan.
  public static func loanBalance(
    _ loan: JSONValue, runs: [JSONValue], settlements: [JSONValue], precision p: Int, except: String? = nil
  ) -> Double {
    if loan.pwStr("status") != "active" { return 0 }
    let owed =
      PwM.minor(loan.pwNum("amount"), p) - recoveredMinor(loan.pwId, runs: runs, settlements: settlements, p, except: except)
    return PwM.fromMinor(max(0, owed), p)
  }

  /// `owedPifssLoanId`.
  static func owedLoanId(_ runId: String, _ employeeId: String) -> String { "pifss-\(runId)-\(employeeId)" }

  /// `createStaffLoan(companyId, employeeId, overrides)`.
  static func createLoan(_ ctx: WriteContext, employeeId: String, _ overrides: [String: JSONValue]) -> JSONValue {
    let date = WebJS.present(overrides["date"])?.string ?? ctx.today
    var fields: [String: JSONValue] = [
      "id": .string(ctx.newId()), "companyId": .string(ctx.companyId), "employeeId": .string(employeeId),
      "date": .string(date), "amount": 0, "instalment": 0, "firstPeriod": .string(PwPay.periodOf(date)),
      "paidFromAccountId": .null, "journalId": .null, "status": "active", "cancelJournalId": .null, "notes": "",
      "createdAt": .string(ctx.stamp), "updatedAt": .string(ctx.stamp),
    ]
    for (key, value) in overrides { fields[key] = value }
    return .object(fields)
  }

  /// A new loan as the loan form starts it (`createStaffLoan`, outside an action).
  public static func newLoan(companyId: String, employeeId: String, today: String, now: Date = Date()) -> JSONValue {
    let stamp = Defaults.nowStamp(now)
    return [
      "id": .string(newId()), "companyId": .string(companyId), "employeeId": .string(employeeId),
      "date": .string(today), "amount": 0, "instalment": 0, "firstPeriod": .string(PwPay.periodOf(today)),
      "paidFromAccountId": .null, "journalId": .null, "status": "active", "cancelJournalId": .null, "notes": "",
      "createdAt": .string(stamp), "updatedAt": .string(stamp),
    ]
  }

  /// `saveStaffLoan(input)`: Dr staff advances, Cr bank on the day it was paid;
  /// once recorded, only the instalment, the first month and the notes change.
  @discardableResult
  public static func saveLoan(_ ctx: WriteContext, _ input: JSONValue, text: PwText = .english) throws -> JSONValue {
    let company = try company(ctx, input.pwStr("companyId"))
    let p = PwM.places(company.pwStr("currency"))
    guard let employee = ctx.get("employees", input.pwStr("employeeId")), employee.pwStr("companyId") == company.pwId
    else { throw pwFail("This employee could not be found.") }
    let existing = ctx.get("staffLoans", input.pwId)
    let amount = PwM.round(existing?.pwNum("amount") ?? input.pwNum("amount"), p)
    let instalment = PwM.round(input.pwNum("instalment"), p)
    if existing == nil && !(amount > 0) { throw pwFail("Enter the amount of the loan.") }
    if !(instalment > 0) { throw pwFail("Enter the monthly instalment.") }
    if instalment > amount { throw pwFail("The instalment can’t be more than the loan.") }
    if !PwPay.isPeriod(input.pwStr("firstPeriod")) { throw pwFail("Choose the first month of repayment.") }
    let notes = WebJS.trim(input.pwStr("notes"))
    if let existing {
      if existing.pwStr("status") != "active" { throw pwFail("This loan was cancelled.") }
      let loan = existing.pwMerging([
        "instalment": .number(instalment), "firstPeriod": input["firstPeriod"] ?? .null, "notes": .string(notes),
        "updatedAt": .string(ctx.stamp),
      ])
      ctx.put("staffLoans", loan)
      return loan
    }
    if !PwDates.isDate(input.pwText("date")) { throw pwFail("Enter the date the loan was paid.") }
    try PwLedger.assertOpen(company, text, input.pwText("date"))
    let settings = PwSettings.payroll(ctx)
    let bank = try PwLedger.moneyAccount(ctx, input.pwText("paidFromAccountId"), settings.pwText("bankAccountId"))
    let accounts = PwLedger.ensure(ctx, company, settings, [.advances])
    var loan = input.pwMerging([
      "amount": .number(amount), "instalment": .number(instalment), "notes": .string(notes),
      "paidFromAccountId": .string(bank.pwId), "status": "active", "cancelJournalId": .null,
      "createdAt": .string(ctx.stamp), "updatedAt": .string(ctx.stamp),
    ])
    let reference = text.t("Loan to {name}", ["name": employee.pwStr("name")])
    let journal = try PwLedger.postPayment(
      ctx, debit: accounts[.advances] ?? "", bank: bank.pwId, amount: amount, date: loan.pwStr("date"),
      sourceId: loan.pwId, reference: reference, text: text)
    loan.set("journalId", .string(journal.pwId))
    ctx.put("staffLoans", loan)
    PwLog.add(
      ctx, "payroll", loan.pwId, "loan", "Loan to {name} recorded", vars: ["name": .text(employee.pwStr("name"))],
      arabic: ["name": employee.pwText("nameAr")])
    return loan
  }

  /// `cancelStaffLoan(id)`: a loan nothing was recovered on yet, its payment reversed.
  @discardableResult
  public static func cancelLoan(_ ctx: WriteContext, id: String, text: PwText = .english) throws -> JSONValue {
    guard let loan = ctx.get("staffLoans", id), loan.pwStr("status") == "active" else {
      throw pwFail("This loan was cancelled.")
    }
    if loan.pwTruthy("payRunId") {
      throw pwFail("This PIFSS share was recorded by a pay run: reopening that pay run cancels it.")
    }
    let company = try company(ctx, loan.pwStr("companyId"))
    let p = PwM.places(company.pwStr("currency"))
    if recoveredMinor(loan.pwId, runs: ctx.pwAll("payRuns"), settlements: ctx.pwAll("finalSettlements"), p) > 0 {
      throw pwFail("Part of this loan was recovered, so it can’t be cancelled.")
    }
    try PwLedger.assertOpen(company, text, loan.pwText("date"))
    let cancelJournalId = try PwLedger.reverseEntry(ctx, loan.pwText("journalId"), text: text)
    let next = loan.pwMerging([
      "status": "cancelled", "cancelJournalId": .pwOptional(cancelJournalId), "updatedAt": .string(ctx.stamp),
    ])
    ctx.put("staffLoans", next)
    let employee = ctx.get("employees", loan.pwStr("employeeId"))
    PwLog.add(
      ctx, "payroll", loan.pwId, "loan_cancelled", "Loan to {name} cancelled",
      vars: ["name": .text(employee?.pwStr("name") ?? "")], arabic: ["name": employee?.pwText("nameAr")])
    return next
  }

  // MARK: Leave

  /// A new leave record as the leave form starts it (`createLeaveRecord`).
  public static func newLeaveRecord(
    companyId: String, employeeId: String, start: String, now: Date = Date()
  ) -> JSONValue {
    let stamp = Defaults.nowStamp(now)
    return [
      "id": .string(newId()), "companyId": .string(companyId), "employeeId": .string(employeeId), "type": "annual",
      "kind": "leave", "start": .string(start), "end": .string(start), "days": 0, "status": "approved", "notes": "",
      "createdAt": .string(stamp), "updatedAt": .string(stamp),
    ]
  }

  /// `assertPayUnchanged`: leave that changes pay in an approved or paid run is refused.
  static func assertPayUnchanged(
    _ ctx: WriteContext, _ company: JSONValue, _ employee: JSONValue, before: [JSONValue], after: [JSONValue],
    text: PwText
  ) throws {
    let runs = PwSort.stable(ctx.pwAll("payRuns").filter { $0.pwStr("status") != "draft" }) {
      PwSort.code($0.pwStr("period"), $1.pwStr("period"))
    }
    let dayOff = PwDayOff(company: company)
    for run in runs {
      guard let line = run.pwList("lines").first(where: { $0.pwStr("employeeId") == employee.pwId }) else { continue }
      let period = run.pwStr("period")
      let was = PwLeave.inPeriod(before, period, dayOff, from: line.pwText("hireDate"), to: line.pwText("leavingDate"))
      let now = PwLeave.inPeriod(after, period, dayOff, from: line.pwText("hireDate"), to: line.pwText("leavingDate"))
      if was.calendar.unpaidDays == now.calendar.unpaidDays
        && WebJS.json(.array(was.calendar.reducedPay)) == WebJS.json(.array(now.calendar.reducedPay))
      {
        continue
      }
      let vars = ["name": employee.pwStr("name"), "month": text.period(period, company)]
      throw run.pwStr("status") == "paid"
        ? pwFail(
          "This leave changes the pay of {name} in the {month} pay run, which is already paid. Undo its payment and reopen it first, then update it after the leave.",
          vars)
        : pwFail(
          "This leave changes the pay of {name} in the {month} pay run, which is already approved. Reopen the pay run first, then update it after the leave.",
          vars)
    }
  }

  /// `assertReason`.
  private static func assertReason(
    _ input: JSONValue, _ existing: JSONValue?, _ settings: JSONValue, _ employee: JSONValue, _ text: PwText
  ) throws -> JSONValue {
    guard let reason = PwLeave.reasonOf(input.pwText("reasonId"), settings.pwList("leaveReasons")) else {
      throw pwFail("This leave reason could not be found.")
    }
    if PwLeave.reasonPay[reason.pwStr("pay")] == nil || reason["pay"]?.string == nil {
      throw pwFail(
        "{name} was set up on a newer version of the app. Update the app to record it.",
        ["name": text.localName(reason)])
    }
    if let existing, existing["reasonId"] == input["reasonId"] { return reason }
    if !settings.pwTruthy("leaveReasonsOn") { throw pwFail("The company’s leave reasons are switched off.") }
    if reason.pwTruthy("archived") { throw pwFail("This leave reason is archived.") }
    if PwLeave.reasonsFor([reason], category: employee.pwStr("category")).isEmpty {
      throw pwFail("{reason} isn’t for employees of this category.", ["reason": text.localName(reason)])
    }
    return reason
  }

  /// `saveLeaveRecord(input)`: leave (its days counted from the dates) or a change to a balance.
  @discardableResult
  public static func saveLeave(_ ctx: WriteContext, _ input: JSONValue, text: PwText = .english) throws -> JSONValue {
    let company = try company(ctx, input.pwStr("companyId"))
    guard let employee = ctx.get("employees", input.pwStr("employeeId")), employee.pwStr("companyId") == company.pwId
    else { throw pwFail("This employee could not be found.") }
    let start = input.pwStr("start")
    if !PwDates.isDate(input.pwText("start")) { throw pwFail("Enter the first day.") }
    let existing = ctx.get("leaveRecords", input.pwId)
    let settings = PwSettings.payroll(ctx)
    var plain = input.pwFields
    plain["payPercent"] = nil
    plain["reasonId"] = nil
    var reason: JSONValue?
    if input.pwTruthy("reasonId") { reason = try assertReason(input, existing, settings, employee, text) }
    func reasonFields(_ kind: String) -> [String: JSONValue] {
      guard let reason else { return [:] }
      var fields: [String: JSONValue] = [
        "type": .string(PwLeave.reasonBase(reason.pwStr("pay"))), "reasonId": reason["id"] ?? .null,
      ]
      if kind == "leave" && reason.pwStr("pay") == "half" { fields["payPercent"] = 50 }
      return fields
    }
    var record: [String: JSONValue]
    let kind = input.pwStr("kind")
    if kind == "leave" {
      let end = input.pwStr("end")
      if !PwDates.isDate(input.pwText("end")) || WebJS.less(end, start) {
        throw pwFail("The last day can’t be before the first day.")
      }
      if PwDates.daysBetween(start, end) + 1 > PwLeave.maxSpan { throw pwFail("Leave can’t be longer than a year.") }
      let type = reason.map { PwLeave.reasonBase($0.pwStr("pay")) } ?? input.pwStr("type")
      let days = PwLeave.countDays(type, start, end, PwDayOff(company: company), WebJS.present(settings["leavePolicy"]))
      if days == 0 { throw pwFail("These dates are all weekends or public holidays.") }
      if let reason, reason.pwTruthy("noteRequired"), WebJS.trim(input.pwStr("notes")).isEmpty {
        throw pwFail("Enter a note: {reason} needs one.", ["reason": text.localName(reason)])
      }
      record = plain
      for (key, value) in reasonFields("leave") { record[key] = value }
      record["days"] = .number(Double(days))
    } else {
      let days = PwM.jsRound(input.pwNum("days") * 100) / 100
      if !days.isFinite || (kind == "opening" ? days < 0 : days == 0) || input["days"]?.double == nil {
        throw pwFail("Enter the number of days.")
      }
      if let reason, reason.pwStr("pay") != "balance" || kind != "adjustment" {
        throw pwFail("Only a reason paid from days added by hand has a balance to change.")
      }
      record = plain
      if reason != nil {
        for (key, value) in reasonFields(kind) { record[key] = value }
      } else {
        record["type"] = "annual"
      }
      record["end"] = .string(start)
      record["days"] = .number(days)
    }
    record["notes"] = .string(WebJS.trim(record["notes"]?.string ?? ""))
    record["updatedAt"] = .string(ctx.stamp)
    if existing == nil { record["createdAt"] = record["updatedAt"] }
    let saved = JSONValue.object(record)
    let before = ctx.pwOf("leaveRecords", employee: employee.pwId)
    try assertPayUnchanged(
      ctx, company, employee, before: before, after: before.filter { $0.pwId != saved.pwId } + [saved], text: text)
    ctx.put("leaveRecords", saved)
    if saved.pwStr("kind") == "opening", let opening = WebJS.present(employee["leaveOpening"]),
      !opening.pwTruthy("confirmed")
    {
      ctx.put("employees", employee.pwMerging(["leaveOpening": .null, "updatedAt": .string(ctx.stamp)]))
    }
    PwLog.add(
      ctx, "payroll", saved.pwId, existing == nil ? "leave" : "leave_updated",
      existing == nil ? "Leave recorded for {name}" : "Leave of {name} updated",
      vars: ["name": .text(employee.pwStr("name"))], arabic: ["name": employee.pwText("nameAr")])
    return saved
  }

  /// `cancelLeaveRecord(id)`.
  public static func cancelLeave(_ ctx: WriteContext, id: String, text: PwText = .english) throws {
    guard let record = ctx.get("leaveRecords", id), record.pwStr("status") != "cancelled" else { return }
    let employee = ctx.get("employees", record.pwStr("employeeId"))
    let company = ctx.get("companies", record.pwStr("companyId"))
    let cancelled = record.pwMerging(["status": "cancelled", "updatedAt": .string(ctx.stamp)])
    if let employee, let company {
      let before = ctx.pwOf("leaveRecords", employee: employee.pwId)
      try assertPayUnchanged(
        ctx, company, employee, before: before, after: before.map { $0.pwId == id ? cancelled : $0 }, text: text)
    }
    ctx.put("leaveRecords", cancelled)
    PwLog.add(
      ctx, "payroll", id, "leave_cancelled", "Leave of {name} cancelled",
      vars: ["name": .text(employee?.pwStr("name") ?? "")], arabic: ["name": employee?.pwText("nameAr")])
  }
}
