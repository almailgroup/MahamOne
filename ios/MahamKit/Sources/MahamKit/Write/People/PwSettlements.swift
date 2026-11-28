import Foundation

// Final settlements: the port of src/db/payroll.ts (`settlementSetup`,
// `settlementDefaults`, `settlementInput`, `settlementMissingText`,
// `postSettlement`, `paySettlement`, `reverseSettlement`).

public enum PwSettlements {
  static let leavingReasons = ["resignation", "termination", "contract_end", "retirement", "dismissal", "death", "other"]

  /// What a settlement form holds (`SettlementForm`).
  public struct Form: Sendable, Equatable {
    public var employeeId: String
    public var leavingDate: String
    public var reason: String
    public var pifssOffset: Double
    public var indemnityOverride: Double?
    public var noticeMonths: Double
    public var leaveDays: Double
    public var lastSalaryDays: Double
    /// `{ loanId, amount }`.
    public var loans: [JSONValue]
    public var otherDeductions: Double
    public var deductionNote: String
    public var notes: String

    public init(
      employeeId: String, leavingDate: String, reason: String, pifssOffset: Double = 0,
      indemnityOverride: Double? = nil, noticeMonths: Double = 0, leaveDays: Double = 0, lastSalaryDays: Double = 0,
      loans: [JSONValue] = [], otherDeductions: Double = 0, deductionNote: String = "", notes: String = ""
    ) {
      self.employeeId = employeeId
      self.leavingDate = leavingDate
      self.reason = reason
      self.pifssOffset = pifssOffset
      self.indemnityOverride = indemnityOverride
      self.noticeMonths = noticeMonths
      self.leaveDays = leaveDays
      self.lastSalaryDays = lastSalaryDays
      self.loans = loans
      self.otherDeductions = otherDeductions
      self.deductionNote = deductionNote
      self.notes = notes
    }

    /// The form as the web's JSON keeps it.
    public init(_ json: JSONValue) {
      self.init(
        employeeId: json.pwStr("employeeId"), leavingDate: json.pwStr("leavingDate"), reason: json.pwStr("reason"),
        pifssOffset: json.pwNum("pifssOffset"), indemnityOverride: json.pwNumber("indemnityOverride"),
        noticeMonths: json.pwNum("noticeMonths"), leaveDays: json.pwNum("leaveDays"),
        lastSalaryDays: json.pwNum("lastSalaryDays"), loans: json.pwList("loans"),
        otherDeductions: json.pwNum("otherDeductions"), deductionNote: json.pwStr("deductionNote"),
        notes: json.pwStr("notes"))
    }
  }

  /// What a settlement on a date starts from (`SettlementSetup`).
  public struct Setup: Sendable {
    public var rules: JSONValue
    public var eosDivisor: Double
    public var leaveBalance: Double
    /// The employee's active loans and what is left on them.
    public var loans: [(loan: JSONValue, balance: Double)]
    /// The employee's share of the provisions held.
    public var provisions: (eos: Double, leave: Double)
    /// An approved pay run already pays the leaving month.
    public var paidInRun: JSONValue?
  }

  /// `settlementSetup(employee, leavingDate, data, precision)`.
  static func makeSetup(_ employee: JSONValue, _ leavingDate: String, _ c: PwPayrollContext) -> Setup {
    let period = PwPay.periodOf(leavingDate)
    let p = c.precision
    let withProvisions = PwSort.stable(
      c.runs.filter { $0.pwStr("status") != "draft" && WebJS.truthy($0["provisions"]) }
    ) { PwSort.localeCompare($1.pwStr("period"), $0.pwStr("period")) }.first
    let share = withProvisions?.pwList("provisions").first { $0.pwStr("employeeId") == employee.pwId }
    let balance = PwLeave.employeeBalance(
      employee, c.leave, on: leavingDate, policy: WebJS.present(c.settings["leavePolicy"]),
      pauseFrom: PwLeave.pauseFrom(c.settings)
    ).balance
    let loans = c.loans.filter { $0.pwStr("employeeId") == employee.pwId && $0.pwStr("status") == "active" }
      .map { (loan: $0, balance: PwPayroll.loanBalance($0, runs: c.runs, settlements: c.settlements, precision: p)) }
      .filter { $0.balance > 0 }
    let paidInRun = c.runs.first { r in
      r.pwStr("period") == period && r.pwStr("status") != "draft"
        && r.pwList("lines").contains { $0.pwStr("employeeId") == employee.pwId }
    }
    return Setup(
      rules: PwSettings.payRules(c.settings, period), eosDivisor: c.people.pwNum("eosDailyDivisor"),
      leaveBalance: balance, loans: loans,
      provisions: (share?.pwNum("eos") ?? 0, share?.pwNum("leave") ?? 0), paidInRun: paidInRun)
  }

  /// `settlementInput`.
  static func input(_ employee: JSONValue, _ form: Form, _ setup: Setup, _ p: Int) -> PwPay.SettlementInput {
    PwPay.SettlementInput(
      employee: employee, leavingDate: form.leavingDate, reason: form.reason, rules: setup.rules,
      eosDivisor: setup.eosDivisor, pifssOffset: form.pifssOffset, indemnityOverride: form.indemnityOverride,
      noticeMonths: form.noticeMonths, leaveDays: form.leaveDays, lastSalaryDays: form.lastSalaryDays,
      loans: form.loans, otherDeductions: form.otherDeductions, eosProvision: setup.provisions.eos,
      leaveProvision: setup.provisions.leave, precision: p)
  }

  /// `settlementDefaults`: a form filled in with what the law and the records give.
  static func defaults(_ employee: JSONValue, _ leavingDate: String, _ reason: String, _ setup: Setup, _ p: Int) -> Form {
    var form = Form(
      employeeId: employee.pwId, leavingDate: leavingDate, reason: reason,
      noticeMonths: PwPay.noticeMonths(reason, employee.pwStr("payBasis")), leaveDays: max(0, setup.leaveBalance),
      lastSalaryDays: setup.paidInRun != nil
        ? 0 : Double(PwPay.lastMonthDays(employee.pwText("hireDate"), leavingDate)))
    let due = PwPay.settlement(input(employee, form, setup, p))
    var available = PwM.minor(due.net, p)
    form.loans = setup.loans.map { entry in
      let amount = max(0, min(PwM.minor(entry.balance, p), available))
      available -= amount
      return ["loanId": .string(entry.loan.pwId), "amount": .number(PwM.fromMinor(amount, p))]
    }
    return form
  }

  /// What the settlement page starts from: the setup, the form the law and
  /// the records give, and what it comes to.
  public struct Draft: Sendable {
    public var setup: Setup
    public var form: Form
  }

  /// The settlement form an employee leaving on a date starts with.
  public static func draft(_ ctx: WriteContext, employeeId: String, leavingDate: String, reason: String) throws -> Draft {
    guard let employee = ctx.get("employees", employeeId) else { throw pwFail("This employee could not be found.") }
    let c = try PwPayrollContext(ctx)
    let setup = makeSetup(employee, leavingDate, c)
    return Draft(setup: setup, form: defaults(employee, leavingDate, reason, setup, c.precision))
  }

  /// What a form comes to (`computeSettlement(settlementInput(...))`): indemnity, notice, leave, last salary, net.
  public static func amounts(_ ctx: WriteContext, _ form: Form, _ setup: Setup) -> (
    indemnity: Double, noticePay: Double, leavePay: Double, lastSalary: Double, deductions: Double, net: Double
  )? {
    guard let employee = ctx.get("employees", form.employeeId), let company = ctx.pwCompany else { return nil }
    let a = PwPay.settlement(input(employee, form, setup, PwM.places(company.pwStr("currency"))))
    return (a.indemnity, a.noticePay, a.leavePay, a.lastSalary?.pwNum("gross") ?? 0, a.deductions, a.net)
  }

  /// `settlementMissingText(employee)` (English, with its name).
  public static func missingText(_ employee: JSONValue, text: PwText = .english) -> WriteFailure? {
    let missing = PwPay.settlementMissing(employee)
    let vars = ["name": text.localName(employee)]
    if missing.hireDate && missing.wage {
      return pwFail("Add the hire date and the salary to {name}’s record before the final settlement.", vars)
    }
    if missing.hireDate { return pwFail("Add the hire date to {name}’s record before the final settlement.", vars) }
    if missing.wage { return pwFail("Add the salary to {name}’s record before the final settlement.", vars) }
    return nil
  }

  /// `postSettlement(form)`: posted on the leaving date, and the employee marked as left.
  @discardableResult
  public static func post(_ ctx: WriteContext, _ form: Form, text: PwText = .english) throws -> JSONValue {
    guard let employee = ctx.get("employees", form.employeeId) else {
      throw pwFail("This employee could not be found.")
    }
    let c = try PwPayrollContext(ctx)
    let company = c.company
    let p = c.precision
    if c.settlements.contains(where: { $0.pwStr("employeeId") == employee.pwId && $0.pwStr("status") != "reversed" }) {
      throw pwFail("This employee already has a final settlement.")
    }
    if let missing = missingText(employee, text: text) { throw missing }
    if form.reason.isEmpty || !leavingReasons.contains(form.reason) { throw pwFail("Choose the reason for leaving.") }
    if !PwDates.isDate(form.leavingDate) { throw pwFail("Enter the leaving date.") }
    let hire = employee.pwStr("hireDate")
    if !hire.isEmpty && WebJS.less(form.leavingDate, hire) {
      throw pwFail("The leaving date can’t be before the hire date.")
    }
    try PwLedger.assertOpen(company, text, form.leavingDate)
    let setup = makeSetup(employee, form.leavingDate, c)
    if setup.paidInRun != nil && form.lastSalaryDays > 0 {
      throw pwFail("The pay run of this month already pays this employee. Set the last salary days to 0.")
    }
    for recovery in form.loans {
      let loan = setup.loans.first { $0.loan.pwId == recovery.pwStr("loanId") }
      if PwM.minor(recovery.pwNum("amount"), p) > PwM.minor(loan?.balance ?? 0, p) {
        throw pwFail("A loan recovery is more than what is left on the loan.")
      }
    }
    let amounts = PwPay.settlement(input(employee, form, setup, p))
    if amounts.net < 0 {
      throw pwFail("The deductions are more than what is due. Lower the loan recovery or other deductions.")
    }
    let id = ctx.newId()
    let list = PwPay.settlementPostings(amounts, eos: setup.provisions.eos, leave: setup.provisions.leave, p)
    var keys: [PwAccountKey] = []
    for posting in list where !keys.contains(posting.key) { keys.append(posting.key) }
    let accounts = PwLedger.ensure(ctx, company, c.settings, keys)
    let journal = try PwLedger.postEntry(
      ctx, company, accounts, list, date: form.leavingDate, sourceId: id,
      reference: text.t("Final settlement – {name}", ["name": employee.pwStr("name")]), text: text)
    let stamp = ctx.stamp
    let settlement: JSONValue = [
      "id": .string(id), "companyId": .string(company.pwId), "employeeId": .string(employee.pwId), "status": "posted",
      "leavingDate": .string(form.leavingDate), "reason": .string(form.reason), "years": .number(amounts.years),
      "eosWage": .number(amounts.eosWage), "indemnity": .number(amounts.indemnity),
      "pifssOffset": .number(PwM.round(max(0, form.pifssOffset), p)), "noticeMonths": .number(max(0, form.noticeMonths)),
      "noticePay": .number(amounts.noticePay), "leaveDays": .number(max(0, form.leaveDays)),
      "leavePay": .number(amounts.leavePay), "lastSalary": amounts.lastSalary ?? .null,
      "loans": .array(form.loans.filter { PwM.minor($0.pwNum("amount"), p) > 0 }),
      "otherDeductions": .number(amounts.otherDeductions), "deductionNote": .string(WebJS.trim(form.deductionNote)),
      "eosProvision": .number(setup.provisions.eos), "leaveProvision": .number(setup.provisions.leave),
      "net": .number(amounts.net), "journalId": .pwOptional(journal?.pwId), "paidOn": .null,
      "paymentJournalId": .null, "bankAccountId": .null, "reversalJournalIds": [], "notes": .string(WebJS.trim(form.notes)),
      "createdAt": .string(stamp), "updatedAt": .string(stamp),
    ]
    ctx.put("finalSettlements", settlement)
    let vars: [String: PwLog.Var] = ["name": .text(employee.pwStr("name")), "number": .text(employee.pwStr("number"))]
    let arabic: [String: String?] = ["name": employee.pwText("nameAr")]
    if employee.pwStr("status") != "left" || employee["leavingDate"]?.string != form.leavingDate
      || employee["leavingReason"]?.string != form.reason
    {
      ctx.put(
        "employees",
        employee.pwMerging([
          "status": "left", "leavingDate": .string(form.leavingDate), "leavingReason": .string(form.reason),
          "updatedAt": .string(stamp),
        ]))
      if employee.pwStr("status") != "left" {
        PwLog.add(
          ctx, "employee", employee.pwId, "left", "Employee {name} ({number}) marked as left", vars: vars,
          arabic: arabic)
      }
    }
    PwLog.add(ctx, "payroll", id, "settlement", "Final settlement for {name} posted", vars: vars, arabic: arabic)
    return settlement
  }

  static func load(_ ctx: WriteContext, _ id: String) throws -> JSONValue {
    guard let settlement = ctx.get("finalSettlements", id) else { throw pwFail("This settlement could not be found.") }
    return settlement
  }

  /// `paySettlement(id, { date, bankAccountId })`: Dr salaries payable, Cr bank.
  @discardableResult
  public static func pay(
    _ ctx: WriteContext, id: String, date: String, bankAccountId: String? = nil, text: PwText = .english
  ) throws -> JSONValue {
    let settlement = try load(ctx, id)
    if settlement.pwStr("status") != "posted" { throw pwFail("This settlement can’t be paid.") }
    let company = try PwPayroll.company(ctx, settlement.pwStr("companyId"))
    if !PwDates.isDate(date) { throw pwFail("Enter the payment date.") }
    try PwLedger.assertOpen(company, text, date)
    let settings = PwSettings.payroll(ctx)
    let bank = try PwLedger.moneyAccount(ctx, bankAccountId, settings.pwText("bankAccountId"))
    let employee = ctx.get("employees", settlement.pwStr("employeeId"))
    let name = employee?.pwStr("name") ?? ""
    var paymentJournalId: String?
    if settlement.pwNum("net") > 0 {
      let accounts = PwLedger.ensure(ctx, company, settings, [.salariesPayable])
      let journal = try PwLedger.postPayment(
        ctx, debit: accounts[.salariesPayable] ?? "", bank: bank.pwId, amount: settlement.pwNum("net"), date: date,
        sourceId: settlement.pwId, reference: text.t("Final settlement – {name} paid", ["name": name]), text: text)
      paymentJournalId = journal.pwId
    }
    let next = settlement.pwMerging([
      "status": "paid", "paidOn": .string(date), "bankAccountId": .string(bank.pwId),
      "paymentJournalId": .pwOptional(paymentJournalId), "updatedAt": .string(ctx.stamp),
    ])
    ctx.put("finalSettlements", next)
    PwLog.add(
      ctx, "payroll", id, "settlement_paid", "Final settlement for {name} paid", vars: ["name": .text(name)],
      arabic: ["name": employee?.pwText("nameAr")])
    return next
  }

  /// `reverseSettlement(id)`: an unpaid settlement reversed, or the payment of a paid one.
  @discardableResult
  public static func reverse(_ ctx: WriteContext, id: String, text: PwText = .english) throws -> JSONValue {
    let settlement = try load(ctx, id)
    let company = try PwPayroll.company(ctx, settlement.pwStr("companyId"))
    let employee = ctx.get("employees", settlement.pwStr("employeeId"))
    let vars: [String: PwLog.Var] = ["name": .text(employee?.pwStr("name") ?? "")]
    let arabic: [String: String?] = ["name": employee?.pwText("nameAr")]
    var next: JSONValue
    let reversals = settlement.pwList("reversalJournalIds")
    switch settlement.pwStr("status") {
    case "paid":
      try PwLedger.assertOpen(company, text, settlement.pwText("paidOn"))
      let reversal = try PwLedger.reverseEntry(ctx, settlement.pwText("paymentJournalId"), text: text)
      next = settlement.pwMerging([
        "status": "posted", "paidOn": .null, "paymentJournalId": .null,
        "reversalJournalIds": .array(reversals + (reversal.map { [.string($0)] } ?? [])),
      ])
      PwLog.add(
        ctx, "payroll", id, "settlement_payment_undone", "Payment of the final settlement for {name} undone",
        vars: vars, arabic: arabic)
    case "posted":
      try PwLedger.assertOpen(company, text, settlement.pwText("leavingDate"))
      let reversal = try PwLedger.reverseEntry(ctx, settlement.pwText("journalId"), text: text)
      next = settlement.pwMerging([
        "status": "reversed", "reversalJournalIds": .array(reversals + (reversal.map { [.string($0)] } ?? [])),
      ])
      PwLog.add(
        ctx, "payroll", id, "settlement_reversed", "Final settlement for {name} reversed", vars: vars, arabic: arabic)
    default:
      throw pwFail("This settlement was reversed.")
    }
    next.set("updatedAt", .string(ctx.stamp))
    ctx.put("finalSettlements", next)
    return next
  }
}
