import Foundation
import MahamKit

// Kuwait private-sector payroll as the web shows it (src/lib/hr/payroll.ts,
// src/db/payroll.ts): pay runs and their totals in minor units, the checks
// before paying, staff loans and what is left on them, and the final
// settlement's figures. Read only: pay runs are shown as they were worked
// out and stored.

/// An allowance on a pay line.
struct PePayLineAllowance: Identifiable {
  let id: String
  let name: String
  let nameAr: String
  let monthly: Double
  let amount: Double

  var displayName: String { localName(name, nameAr) }
}

/// One reason's leave on a pay line, for the payslip.
struct PePayLineLeave {
  let name: String
  let nameAr: String
  let days: Double
  let percent: Double
  let fromAnnual: Bool

  var displayName: String { localName(name, nameAr) }
}

/// Part of a loan recovered from pay or at settlement.
struct PeLoanRecovery {
  let loanId: String
  let amount: Double
}

/// One employee's pay in a pay run (`PayLine`), as stored.
struct PePayLine: Identifiable {
  let raw: JSONValue

  init(_ raw: JSONValue) { self.raw = raw }

  var id: String { raw.rid }
  var employeeId: String { raw.str("employeeId") }
  var number: String { raw.str("number") }
  var name: String { raw.str("name") }
  var nameAr: String { raw.str("nameAr") }
  var displayName: String { localName(name, nameAr) }
  var job: String { localName(raw.str("jobTitle"), raw.text("jobTitleAr")) }
  var department: String? { raw.text("department") }
  var category: String { raw.str("category") }
  var nationality: String { raw.str("nationality") }
  var iban: String { raw.str("iban") }
  var accountNumber: String { raw.str("accountNumber") }
  var permitSalary: Double { raw.num("permitSalary") }
  var monthlyBasic: Double { raw.num("monthlyBasic") }
  var allowances: [PePayLineAllowance] {
    raw.list("allowances").enumerated().map { index, a in
      PePayLineAllowance(
        id: a.text("id") ?? "allowance-\(index)", name: a.str("name"), nameAr: a.str("nameAr"),
        monthly: a.num("monthly"), amount: a.num("amount"))
    }
  }
  var daysWorked: Int { Int(raw.num("daysWorked")) }
  var daysInMonth: Int { Int(raw.num("daysInMonth")) }
  var overtimeNormal: Double { raw.obj("overtime")?.num("normal") ?? 0 }
  var overtimeRestDay: Double { raw.obj("overtime")?.num("restDay") ?? 0 }
  var overtimeHoliday: Double { raw.obj("overtime")?.num("holiday") ?? 0 }
  var absentDays: Double { raw.num("absentDays") }
  var basic: Double { raw.num("basic") }
  var allowanceTotal: Double { raw.num("allowanceTotal") }
  var overtimePay: Double { raw.num("overtimePay") }
  var absenceDeduction: Double { raw.num("absenceDeduction") }
  var additions: Double { raw.num("additions") }
  var gross: Double { raw.num("gross") }
  var pifssEmployee: Double { raw.num("pifssEmployee") }
  var pifssEmployer: Double { raw.num("pifssEmployer") }
  var pifssOwed: Double { raw.num("pifssOwed") }
  var loanDeduction: Double { raw.num("loanDeduction") }
  var otherDeductions: Double { raw.num("otherDeductions") }
  var net: Double { raw.num("net") }
  var loans: [PeLoanRecovery] {
    raw.list("loans").map { PeLoanRecovery(loanId: $0.str("loanId"), amount: $0.num("amount")) }
  }
  var leaveDetail: [PePayLineLeave] {
    raw.list("leaveDetail").map {
      PePayLineLeave(
        name: $0.str("name"), nameAr: $0.str("nameAr"), days: $0.num("days"), percent: $0.num("percent"),
        fromAnnual: $0.flag("fromAnnual"))
    }
  }
}

/// The rules a pay run was worked out with (`PayRules`).
struct PePayRules {
  var dailyDivisor: Double
  var rateBase: String
  var pifss: PeRates?
  var gcc: [PeRates]
  var minimumWage: Double
}

/// One employee's month-end provisions, as a pay run posted them.
struct PeProvisionLine {
  let employeeId: String
  let eos: Double
  let leaveDays: Double
  let leave: Double
}

/// A month's payroll (`PayRun`).
struct PePayRun: Identifiable {
  let raw: JSONValue

  init(_ raw: JSONValue) { self.raw = raw }

  var id: String { raw.rid }
  var period: String { raw.str("period") }
  var status: String { raw.text("status") ?? "draft" }
  var date: String { raw.str("date") }
  var payDate: String { raw.str("payDate") }
  var lines: [PePayLine] { raw.list("lines").map { PePayLine($0) } }
  var rules: PePayRules {
    let rules = raw.obj("rules")
    return PePayRules(
      dailyDivisor: rules?.number("dailyDivisor") ?? 26, rateBase: rules?.text("rateBase") ?? "wage",
      pifss: rules?.obj("pifss").map { PeRates($0) }, gcc: (rules?.list("gcc") ?? []).map { PeRates($0) },
      minimumWage: rules?.number("minimumWage") ?? 0)
  }
  var deductionAccountId: String? { raw.text("deductionAccountId") }
  var journalId: String? { raw.text("journalId") }
  var provisionJournalId: String? { raw.text("provisionJournalId") }
  var paymentJournalId: String? { raw.text("paymentJournalId") }
  /// Null when none were posted.
  var provisions: [PeProvisionLine]? {
    raw["provisions"]?.array.map { list in
      list.map {
        PeProvisionLine(
          employeeId: $0.str("employeeId"), eos: $0.num("eos"), leaveDays: $0.num("leaveDays"), leave: $0.num("leave"))
      }
    }
  }
  var paidOn: String? { raw.text("paidOn") }
}

/// A staff loan or salary advance (`StaffLoan`).
struct PeStaffLoan: Identifiable {
  let raw: JSONValue

  init(_ raw: JSONValue) { self.raw = raw }

  var id: String { raw.rid }
  var employeeId: String { raw.str("employeeId") }
  var date: String { raw.str("date") }
  var amount: Double { raw.num("amount") }
  var instalment: Double { raw.num("instalment") }
  var firstPeriod: String { raw.str("firstPeriod") }
  var status: String { raw.text("status") ?? "active" }
  var payRunId: String? { raw.text("payRunId") }
  var notes: String { raw.str("notes") }
}

/// Salary for the last days worked, paid with the final settlement.
struct PeSettlementSalary {
  let period: String
  let days: Int
  let daysInMonth: Int
  let basic: Double
  let allowances: Double
  let gross: Double
  let pifssEmployee: Double
  let pifssEmployer: Double

  init(
    period: String, days: Int, daysInMonth: Int, basic: Double, allowances: Double, gross: Double,
    pifssEmployee: Double, pifssEmployer: Double
  ) {
    self.period = period
    self.days = days
    self.daysInMonth = daysInMonth
    self.basic = basic
    self.allowances = allowances
    self.gross = gross
    self.pifssEmployee = pifssEmployee
    self.pifssEmployer = pifssEmployer
  }

  init(_ raw: JSONValue) {
    period = raw.str("period")
    days = Int(raw.num("days"))
    daysInMonth = Int(raw.num("daysInMonth"))
    basic = raw.num("basic")
    allowances = raw.num("allowances")
    gross = raw.num("gross")
    pifssEmployee = raw.num("pifssEmployee")
    pifssEmployer = raw.num("pifssEmployer")
  }
}

/// A posted final settlement (`FinalSettlement`).
struct PeSettlementRecord: Identifiable {
  let raw: JSONValue

  init(_ raw: JSONValue) { self.raw = raw }

  var id: String { raw.rid }
  var employeeId: String { raw.str("employeeId") }
  var status: String { raw.str("status") }
  var leavingDate: String { raw.str("leavingDate") }
  var reason: String { raw.str("reason") }
  var years: Double { raw.num("years") }
  var eosWage: Double { raw.num("eosWage") }
  var indemnity: Double { raw.num("indemnity") }
  var noticeMonths: Double { raw.num("noticeMonths") }
  var noticePay: Double { raw.num("noticePay") }
  var leaveDays: Double { raw.num("leaveDays") }
  var leavePay: Double { raw.num("leavePay") }
  var lastSalary: PeSettlementSalary? { raw.obj("lastSalary").map { PeSettlementSalary($0) } }
  var loans: [PeLoanRecovery] {
    raw.list("loans").map { PeLoanRecovery(loanId: $0.str("loanId"), amount: $0.num("amount")) }
  }
  var otherDeductions: Double { raw.num("otherDeductions") }
  var eosProvision: Double { raw.num("eosProvision") }
  var leaveProvision: Double { raw.num("leaveProvision") }
  var net: Double { raw.num("net") }
  var journalId: String? { raw.text("journalId") }
  var paidOn: String? { raw.text("paidOn") }
  var paymentJournalId: String? { raw.text("paymentJournalId") }
}

/// A run's totals, added up in minor units so they match the journal to the fils.
struct PeRunTotals {
  var employees = 0
  var salaries: Double = 0
  var allowances: Double = 0
  var gross: Double = 0
  var overtime: Double = 0
  var absence: Double = 0
  var pifssEmployee: Double = 0
  var pifssEmployer: Double = 0
  var pifssOwed: Double = 0
  var loans: Double = 0
  var otherDeductions: Double = 0
  var deductions: Double = 0
  var net: Double = 0
  var cost: Double = 0
}

/// Something to check on a pay line before approving the run (`PayWarning`).
enum PePayWarning {
  case negativeNet
  case loanCap(Double)
  case deductionCap(Double)
  case minimumWage(Double)
  case permitSalary(Double)
  case iban
  case gccRates(String)
  case pifssRates
  case noSalary
  case pifssOwed(Double, String)
}

/// What a final settlement comes to (`SettlementAmounts`).
struct PeSettlementAmounts {
  let years: Double
  let eosWage: Double
  let monthlyWage: Double
  let eosi: PeEosi.Result?
  let indemnity: Double
  let noticePay: Double
  let leavePay: Double
  let lastSalary: PeSettlementSalary?
  let loanRecovery: Double
  let otherDeductions: Double
  let net: Double
}

/// What a settlement on a day starts from (`SettlementSetup`).
struct PeSettlementSetup {
  let rules: PePayRules
  let eosDivisor: Double
  let leave: PeLeaveBalance
  let loans: [(loan: PeStaffLoan, balance: Double)]
  let provisions: (eos: Double, leave: Double)
  let paidInRun: PePayRun?
}

/// A settlement form filled in with what the law and the records give (`settlementDefaults`).
struct PeSettlementForm {
  var leavingDate: String
  var reason: String
  var noticeMonths: Double
  var leaveDays: Double
  var lastSalaryDays: Double
  var loans: [PeLoanRecovery]
}

@MainActor
enum PePayroll {
  // MARK: Months

  static func isPeriod(_ value: String) -> Bool {
    guard value.utf8.count == 7, let p = PeDates.parts(value + "-01") else { return false }
    return (1...12).contains(p.month)
  }

  static func periodStart(_ period: String) -> String { period + "-01" }

  static func daysInPeriod(_ period: String) -> Int {
    guard let p = PeDates.parts(period + "-01") else { return 30 }
    return PeDates.daysIn(p.year, p.month)
  }

  static func periodEnd(_ period: String) -> String { period + "-" + PeDates.pad(daysInPeriod(period)) }

  static func addPeriods(_ period: String, _ months: Int) -> String {
    PeDates.period(PeDates.addMonths(period + "-01", months))
  }

  /// The pay day in a month; a day past the month's end is its last day.
  static func payDate(_ period: String, payDay: Int) -> String {
    let day = min(max(1, payDay), daysInPeriod(period))
    return period + "-" + PeDates.pad(day)
  }

  /// "September 2026", "سبتمبر 2026".
  static func formatPeriod(_ period: String, _ format: CompanyFormat) -> String {
    guard isPeriod(period) else { return period }
    let text = Format.date(period + "-01", format: Format.DateFormat("MMMM yyyy"), locale: format.locale)
    return text.isEmpty ? period : text
  }

  /// Calendar days of the month the employee was employed.
  static func employedDays(_ period: String, hireDate: String?, leavingDate: String?) -> Int {
    let start = periodStart(period)
    let end = periodEnd(period)
    let from = (hireDate ?? "") > start ? (hireDate ?? start) : start
    let to = (leavingDate.map { $0 < end } ?? false) ? (leavingDate ?? end) : end
    return to < from ? 0 : PeDates.daysBetween(from, to) + 1
  }

  // MARK: Rates

  /// The rates in force on a day: the latest that started by then, else the earliest set.
  static func ratesOn(_ list: [PeRates], _ date: String) -> PeRates? {
    let sorted = list.sorted { $0.from < $1.from }
    return sorted.last { $0.from <= date } ?? sorted.first
  }

  /// PIFSS for Kuwaitis, the home scheme for GCC nationals, none for the rest.
  static func contributionRates(category: String, nationality: String, pifss: PeRates?, gcc: [PeRates]) -> (
    rates: PeRates?, missing: Bool
  ) {
    if category == "kuwaiti" { return (pifss, pifss == nil) }
    if category == "gcc" {
      let scheme = gcc.first { $0.country == nationality.uppercased() }
      return (scheme, scheme == nil)
    }
    return (nil, false)
  }

  /// Employee and employer contributions on the insured salary, for the share of the month employed.
  static func contributions(_ monthlyWage: Decimal, _ fraction: Decimal, _ rates: PeRates, _ p: Int) -> (
    base: Double, employee: Double, employer: Double
  ) {
    var insured = monthlyWage
    if let cap = rates.cap, cap > 0, monthlyWage > PeMoney.dec(cap) { insured = PeMoney.dec(cap) }
    let base = PeMoney.round(insured * fraction, p)
    let employee = PeMoney.round(PeMoney.dec(base) * PeMoney.dec(rates.employee) / Decimal(100), p)
    let employer = PeMoney.round(PeMoney.dec(base) * PeMoney.dec(rates.employer) / Decimal(100), p)
    return (base, employee, employer)
  }

  /// The rules of a month from the payroll settings (`payRulesFor`).
  static func rules(_ settings: PePayrollSettings, period: String) -> PePayRules {
    PePayRules(
      dailyDivisor: settings.dailyDivisor, rateBase: settings.rateBase,
      pifss: ratesOn(settings.pifss, periodStart(period)), gcc: settings.gcc, minimumWage: settings.minimumWage)
  }

  // MARK: Runs

  static func totals(_ lines: [PePayLine], _ p: Int) -> PeRunTotals {
    func m(_ value: Double) -> Int64 { PeMoney.minor(value, p) }
    var salaries: Int64 = 0
    var allowances: Int64 = 0
    var gross: Int64 = 0
    var overtime: Int64 = 0
    var absence: Int64 = 0
    var employee: Int64 = 0
    var employer: Int64 = 0
    var owed: Int64 = 0
    var loans: Int64 = 0
    var other: Int64 = 0
    var net: Int64 = 0
    for line in lines {
      let basic = m(line.basic)
      let lost = m(line.absenceDeduction)
      let fromBasic = min(lost, basic)
      salaries += basic - fromBasic
      allowances += m(line.allowanceTotal) - (lost - fromBasic) + m(line.overtimePay) + m(line.additions)
      gross += m(line.gross)
      overtime += m(line.overtimePay)
      absence += lost
      employee += m(line.pifssEmployee)
      employer += m(line.pifssEmployer)
      owed += m(line.pifssOwed)
      loans += m(line.loanDeduction)
      other += m(line.otherDeductions)
      net += m(line.net)
    }
    func f(_ value: Int64) -> Double { PeMoney.fromMinor(value, p) }
    var totals = PeRunTotals()
    totals.employees = lines.count
    totals.salaries = f(salaries)
    totals.allowances = f(allowances)
    totals.gross = f(gross)
    totals.overtime = f(overtime)
    totals.absence = f(absence)
    totals.pifssEmployee = f(employee)
    totals.pifssEmployer = f(employer)
    totals.pifssOwed = f(owed)
    totals.loans = f(loans)
    totals.otherDeductions = f(other)
    totals.deductions = f(employee - owed + loans + other)
    totals.net = f(net)
    totals.cost = f(gross + employer)
    return totals
  }

  /// A line's deductions: the employee's PIFSS (less what is owed), loans and other deductions.
  static func lineDeductions(_ line: PePayLine, _ p: Int) -> Double {
    let total =
      PeMoney.minor(line.pifssEmployee, p) - PeMoney.minor(line.pifssOwed, p) + PeMoney.minor(line.loanDeduction, p)
      + PeMoney.minor(line.otherDeductions, p)
    return PeMoney.fromMinor(total, p)
  }

  /// A valid IBAN, or no IBAN and an account or salary card number.
  static func hasPayAccount(iban: String, accountNumber: String) -> Bool {
    if !Kuwait.compactIban(iban).isEmpty { return Kuwait.isValidIban(iban) }
    return !accountNumber.filter { !$0.isWhitespace && $0 != "-" }.isEmpty
  }

  /// The checks of a worked-out line against the law (`payLineWarnings`).
  static func warnings(_ line: PePayLine, _ rules: PePayRules, _ p: Int) -> [PePayWarning] {
    func minor(_ value: Double) -> Int64 { PeMoney.minor(value, p) }
    var out: [PePayWarning] = []
    let noAllowance = line.allowances.allSatisfy { minor($0.monthly) == 0 }
    if minor(line.monthlyBasic) == 0 && noAllowance { out.append(.noSalary) }
    if minor(line.net) < 0 { out.append(.negativeNet) }
    if minor(line.pifssOwed) > 0 { out.append(.pifssOwed(line.pifssOwed, line.displayName)) }
    let loanLimit = PeMoney.round(PeMoney.dec(line.gross) * Decimal(10) / Decimal(100), p)
    if minor(line.loanDeduction) > minor(loanLimit) { out.append(.loanCap(loanLimit)) }
    let deductionLimit = PeMoney.round(PeMoney.dec(line.gross) * Decimal(25) / Decimal(100), p)
    if minor(line.loanDeduction) + minor(line.otherDeductions) > minor(deductionLimit) {
      out.append(.deductionCap(deductionLimit))
    }
    if line.category != "domestic" && line.daysWorked > 0 && rules.minimumWage > 0 {
      let minimum = PeMoney.round(
        PeMoney.dec(rules.minimumWage) * Decimal(line.daysWorked) / Decimal(max(1, line.daysInMonth)), p)
      if minor(line.net) >= 0 && minor(line.net) < minor(minimum) { out.append(.minimumWage(minimum)) }
    }
    if line.category == "expat" && minor(line.permitSalary) > minor(line.monthlyBasic) {
      out.append(.permitSalary(line.permitSalary))
    }
    if minor(line.net) > 0 && !hasPayAccount(iban: line.iban, accountNumber: line.accountNumber) {
      out.append(.iban)
    }
    let rates = contributionRates(
      category: line.category, nationality: line.nationality, pifss: rules.pifss, gcc: rules.gcc)
    if rates.missing {
      out.append(line.category == "gcc" ? .gccRates(line.nationality.uppercased()) : .pifssRates)
    }
    return out
  }

  /// A pay line warning in words.
  static func warningText(_ warning: PePayWarning, _ format: CompanyFormat) -> String {
    switch warning {
    case .negativeNet:
      return t("Net pay is below zero. Lower the deductions.")
    case .loanCap(let limit):
      return t("Loan recovery is over 10% of the wage ({limit}), the most the law allows.", ["limit": format.money(limit)])
    case .deductionCap(let limit):
      return t(
        "Deductions are over 25% of the wage ({limit}), the most the law allows.", ["limit": format.money(limit)])
    case .minimumWage(let minimum):
      return t("Net pay is below the minimum wage ({minimum}).", ["minimum": format.money(minimum)])
    case .permitSalary(let permit):
      return t(
        "Basic salary is below the salary on the work permit ({permit}).", ["permit": format.money(permit)])
    case .iban:
      return t("No valid IBAN or salary card number: the salary can’t go in the bank file.")
    case .gccRates(let country):
      return t(
        "No contribution rates for nationals of {country}. Add them in the payroll settings.",
        ["country": Geo.countryName(country, locale: format.locale.identifier)])
    case .pifssRates:
      return t("No PIFSS rates are set. Add them in the payroll settings.")
    case .noSalary:
      return t("No salary on record.")
    case .pifssOwed(let amount, let name):
      return t(
        "PIFSS share not covered by this month’s pay: {amount}, recorded as owed by {name}.",
        ["amount": format.money(amount), "name": name])
    }
  }

  /// A run's status, as a badge.
  static func runStatus(_ status: String) -> StatusMeta {
    switch status {
    case "draft": StatusMeta(label: "Draft", tone: .gray)
    case "approved": StatusMeta(label: "Approved", tone: .blue)
    case "paid": StatusMeta(label: "Paid", tone: .green)
    default: StatusMeta(label: "Unknown status", tone: .gray)
    }
  }

  // MARK: Loans

  /// What approved pay runs and posted settlements recovered of a loan, in minor units.
  static func recoveredMinor(
    _ loanId: String, runs: [PePayRun], settlements: [PeSettlementRecord], _ p: Int
  ) -> Int64 {
    var total: Int64 = 0
    for run in runs where run.status != "draft" {
      for line in run.lines {
        for recovery in line.loans where recovery.loanId == loanId { total += PeMoney.minor(recovery.amount, p) }
      }
    }
    for settlement in settlements where settlement.status != "reversed" {
      for recovery in settlement.loans where recovery.loanId == loanId { total += PeMoney.minor(recovery.amount, p) }
    }
    return total
  }

  /// What the employee still owes on a loan.
  static func loanBalance(
    _ loan: PeStaffLoan, runs: [PePayRun], settlements: [PeSettlementRecord], _ p: Int
  ) -> Double {
    if loan.status != "active" { return 0 }
    let owed = PeMoney.minor(loan.amount, p) - recoveredMinor(loan.id, runs: runs, settlements: settlements, p)
    return PeMoney.fromMinor(max(0, owed), p)
  }

  // MARK: Final settlement

  /// Notice the employer owes when it ends an unlimited contract without notice (art. 44).
  static func noticeMonths(_ reason: String, payBasis: String) -> Double {
    if reason != "termination" { return 0 }
    return payBasis == "monthly" ? 3 : 1
  }

  /// Pay for leave days: the monthly wage over the working days in a month, times the days.
  static func leaveValue(_ days: Double, monthly: Double, divisor: Double, _ p: Int) -> Double {
    if days <= 0 { return 0 }
    let d = divisor > 0 ? divisor : 26
    return PeMoney.round(PeMoney.dec(monthly) / PeMoney.dec(d) * PeMoney.dec(days), p)
  }

  /// Why a final settlement can't be made yet, or nil.
  static func missingText(_ e: PeEmployee) -> String? {
    let wage = PeMoney.sum(e.allowances.map(\.amount)) + PeMoney.dec(e.basicSalary)
    let noHire = e.hireDate == nil
    let noWage = !(wage > 0)
    let vars = ["name": e.displayName]
    if noHire && noWage {
      return t("Add the hire date and the salary to {name}’s record before the final settlement.", vars)
    }
    if noHire { return t("Add the hire date to {name}’s record before the final settlement.", vars) }
    if noWage { return t("Add the salary to {name}’s record before the final settlement.", vars) }
    return nil
  }

  /// What a settlement on a day starts from: rules, leave balance, loans, provisions.
  static func setup(
    _ e: PeEmployee, leavingDate: String, settings: PePayrollSettings, people: PePeopleSettings,
    leave: [PeLeaveRecord], loans: [PeStaffLoan], runs: [PePayRun], settlements: [PeSettlementRecord], _ p: Int
  ) -> PeSettlementSetup {
    let period = PeDates.period(leavingDate)
    let withProvisions = runs.filter { $0.status != "draft" && $0.provisions != nil }
      .sorted { $0.period > $1.period }.first
    let share = withProvisions?.provisions?.first { $0.employeeId == e.id }
    let open = loans.filter { $0.employeeId == e.id && $0.status == "active" }
      .map { (loan: $0, balance: loanBalance($0, runs: runs, settlements: settlements, p)) }
      .filter { $0.balance > 0 }
    let paid = runs.first { run in
      run.period == period && run.status != "draft" && run.lines.contains { $0.employeeId == e.id }
    }
    return PeSettlementSetup(
      rules: rules(settings, period: period), eosDivisor: people.eosDailyDivisor,
      leave: PeLeave.employeeBalance(e, leave, on: leavingDate, settings: settings), loans: open,
      provisions: (share?.eos ?? 0, share?.leave ?? 0), paidInRun: paid)
  }

  /// `computeSettlement`: indemnity, notice pay, unused leave and the last salary, less loans and deductions.
  static func compute(
    _ e: PeEmployee, form: PeSettlementForm, setup: PeSettlementSetup, pifssOffset: Double = 0,
    otherDeductions: Double = 0, _ p: Int
  ) -> PeSettlementAmounts {
    let years = e.hireDate.map { PeEosi.serviceYears($0, form.leavingDate) } ?? 0
    let wageForEos = PeEosi.wage(e.basicSalary, e.allowances, p)
    let monthly = PeMoney.round(PeMoney.sum(e.allowances.map(\.amount)) + PeMoney.dec(e.basicSalary), p)
    let eosi: PeEosi.Result? =
      e.category == "domestic"
      ? nil
      : PeEosi.calculate(
        payBasis: e.payBasis, monthlyWage: wageForEos, years: years, reason: PePeople.eosiReason(form.reason),
        dailyDivisor: setup.eosDivisor, pifssOffset: pifssOffset, precision: p)
    let indemnity = eosi?.payable ?? PeMoney.round(PeMoney.dec(wageForEos) * PeMoney.dec(years), p)
    let noticePay = PeMoney.round(PeMoney.dec(monthly) * PeMoney.dec(max(0, form.noticeMonths)), p)
    let leavePay = leaveValue(form.leaveDays, monthly: monthly, divisor: setup.rules.dailyDivisor, p)

    var lastSalary: PeSettlementSalary?
    let period = PeDates.period(form.leavingDate)
    let daysInMonth = daysInPeriod(period)
    let days = min(max(0, Int(PeMoney.jsRound(form.lastSalaryDays))), daysInMonth)
    if days > 0 {
      let fraction = Decimal(days) / Decimal(daysInMonth)
      let basic = PeMoney.round(PeMoney.dec(e.basicSalary) * fraction, p)
      var parts: [Double] = []
      for allowance in e.allowances { parts.append(PeMoney.round(PeMoney.dec(allowance.amount) * fraction, p)) }
      let allowances = PeMoney.round(PeMoney.sum(parts), p)
      let rates = contributionRates(
        category: e.category, nationality: e.nationality, pifss: setup.rules.pifss, gcc: setup.rules.gcc
      ).rates
      var pifssEmployee = 0.0
      var pifssEmployer = 0.0
      if let rates {
        let shares = contributions(PeMoney.dec(monthly), fraction, rates, p)
        pifssEmployee = shares.employee
        pifssEmployer = shares.employer
      }
      lastSalary = PeSettlementSalary(
        period: period, days: days, daysInMonth: daysInMonth, basic: basic, allowances: allowances,
        gross: PeMoney.round(PeMoney.dec(basic) + PeMoney.dec(allowances), p), pifssEmployee: pifssEmployee,
        pifssEmployer: pifssEmployer)
    }

    let loanRecovery = PeMoney.round(PeMoney.sum(form.loans.map { max(0, $0.amount) }), p)
    let deducted = PeMoney.round(max(0, otherDeductions), p)
    let dues = PeMoney.round(
      PeMoney.dec(indemnity) + PeMoney.dec(noticePay) + PeMoney.dec(leavePay) + PeMoney.dec(lastSalary?.gross ?? 0),
      p)
    let deductions = PeMoney.round(
      PeMoney.dec(lastSalary?.pifssEmployee ?? 0) + PeMoney.dec(loanRecovery) + PeMoney.dec(deducted), p)
    return PeSettlementAmounts(
      years: years, eosWage: wageForEos, monthlyWage: monthly, eosi: eosi, indemnity: indemnity,
      noticePay: noticePay, leavePay: leavePay, lastSalary: lastSalary, loanRecovery: loanRecovery,
      otherDeductions: deducted, net: PeMoney.round(PeMoney.dec(dues) - PeMoney.dec(deductions), p))
  }

  /// The form the web starts from, with loans recovered from what is due as far as it goes.
  static func defaults(
    _ e: PeEmployee, leavingDate: String, reason: String, setup: PeSettlementSetup, _ p: Int
  ) -> PeSettlementForm {
    var form = PeSettlementForm(
      leavingDate: leavingDate, reason: reason, noticeMonths: noticeMonths(reason, payBasis: e.payBasis),
      leaveDays: max(0, setup.leave.balance),
      lastSalaryDays: setup.paidInRun != nil
        ? 0 : Double(employedDays(PeDates.period(leavingDate), hireDate: e.hireDate, leavingDate: leavingDate)),
      loans: [])
    let due = compute(e, form: form, setup: setup, p)
    var available = PeMoney.minor(due.net, p)
    var recoveries: [PeLoanRecovery] = []
    for item in setup.loans {
      let amount = max(0, min(PeMoney.minor(item.balance, p), available))
      available -= amount
      recoveries.append(PeLoanRecovery(loanId: item.loan.id, amount: PeMoney.fromMinor(amount, p)))
    }
    form.loans = recoveries
    return form
  }
}

extension OneData {
  /// The company's pay runs, latest month first.
  var pePayRuns: [PePayRun] {
    records(.payRuns).map { PePayRun($0) }.sorted { $0.period > $1.period }
  }

  var peStaffLoans: [PeStaffLoan] { records(.staffLoans).map { PeStaffLoan($0) } }

  var peSettlements: [PeSettlementRecord] { records(.finalSettlements).map { PeSettlementRecord($0) } }
}
