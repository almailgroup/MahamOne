import Foundation

// The port of the web's src/lib/hr/payroll.ts and src/lib/hr/eosi.ts:
// months, contribution rates, pay lines, run totals and postings,
// provisions and the final settlement, on the records as JSON (a pay line
// keeps every field it has, as the web's spreads do).

enum PwPay {
  static let dailyDivisor = 26.0
  static let hoursPerDay = 8.0
  static let overtimeNormal = 1.25
  static let overtimeRestDay = 1.5
  static let overtimeHoliday = 2.0
  static let loanCapPercent = 10.0
  static let deductionCapPercent = 25.0
  static let minimumWage = 75.0
  /// `PAYROLL_RULES.pifss`.
  static let pifss: JSONValue = ["from": "2026-01-01", "employer": 11.5, "employee": 10.5, "cap": 2750]

  // MARK: Months

  /// `isPeriod`: yyyy-MM.
  static func isPeriod(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard bytes.count == 7, bytes[4] == UInt8(ascii: "-") else { return false }
    let digits = bytes[0..<4] + bytes[5..<7]
    guard digits.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }) else { return false }
    let month = Int(bytes[5] - 48) * 10 + Int(bytes[6] - 48)
    return month >= 1 && month <= 12
  }

  static func periodOf(_ date: String) -> String { WebJS.prefix(date, 7) }

  static func periodStart(_ period: String) -> String { period + "-01" }

  /// `new Date(year, month, 0).getDate()`.
  static func daysInPeriod(_ period: String) -> Int {
    let parts = period.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count >= 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return 30 }
    return PwDates.make(year, month + 1, 0).day
  }

  static func periodEnd(_ period: String) -> String {
    period + "-" + CivilDay.twoDigits(daysInPeriod(period))
  }

  static func addPeriods(_ period: String, _ months: Int) -> String {
    let parts = period.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count >= 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return period }
    let day = PwDates.make(year, month + months, 1)
    return String(day.year) + "-" + CivilDay.twoDigits(day.month)
  }

  /// `payDateFor`: the pay day in a month; a day past the month's end is its last day.
  static func payDate(_ period: String, _ payDay: Double) -> String {
    let rounded = PwM.jsRound(payDay)
    let wanted = rounded.isNaN || rounded == 0 ? 1 : rounded
    let day = min(max(1, wanted), Double(daysInPeriod(period)))
    return period + "-" + CivilDay.twoDigits(Int(day))
  }

  /// `employedDays`: calendar days of the month the employee was employed.
  static func employedDays(_ period: String, hire: String?, leaving: String?) -> Int {
    let start = periodStart(period)
    let end = periodEnd(period)
    let from = (hire.map { !$0.isEmpty && WebJS.less(start, $0) } ?? false) ? hire! : start
    let to = (leaving.map { !$0.isEmpty && WebJS.less($0, end) } ?? false) ? leaving! : end
    return WebJS.less(to, from) ? 0 : PwDates.daysBetween(from, to) + 1
  }

  // MARK: Rates

  /// `ratesOn`: the latest that started by then, else the earliest set.
  static func ratesOn(_ list: [JSONValue], _ date: String) -> JSONValue? {
    if list.isEmpty { return nil }
    let sorted = PwSort.stable(list) { PwSort.code($0.pwStr("from"), $1.pwStr("from")) }
    return sorted.reversed().first { !WebJS.less(date, $0.pwStr("from")) } ?? sorted.first
  }

  /// `contributionRates`: PIFSS for Kuwaitis, the home scheme for GCC nationals, none for the rest.
  static func contributionRates(category: String, nationality: String, rules: JSONValue) -> (
    rates: JSONValue?, missing: Bool
  ) {
    if category == "kuwaiti" {
      let rates = WebJS.present(rules["pifss"])
      return (rates, rates == nil)
    }
    if category == "gcc" {
      let code = nationality.uppercased()
      let scheme = (rules["gcc"]?.array ?? []).first { $0.pwStr("country") == code }
      return (scheme, scheme == nil)
    }
    return (nil, false)
  }

  /// `contributions`: on the monthly wage up to the cap, for the share of the month.
  static func contributions(_ monthlyWage: Decimal, _ fraction: Decimal, _ rates: JSONValue, _ p: Int) -> (
    base: Double, employee: Double, employer: Double
  ) {
    let cap = rates["cap"]?.double
    let insured: Decimal = {
      if let cap, cap > 0, monthlyWage > PwM.dec(cap) { return PwM.dec(cap) }
      return monthlyWage
    }()
    let base = PwM.round(insured * fraction, p)
    let employee = PwM.round(PwM.dec(base) * PwM.dec(rates.pwNum("employee")) / 100, p)
    let employer = PwM.round(PwM.dec(base) * PwM.dec(rates.pwNum("employer")) / 100, p)
    return (base, employee, employer)
  }

  /// `dailyRate`: the monthly amount over the working days in a month, not rounded.
  static func dailyRate(_ monthly: Decimal, _ divisor: Double) -> Decimal {
    monthly / PwM.dec(divisor > 0 ? divisor : dailyDivisor)
  }

  // MARK: Pay lines

  /// `monthlyWage`: basic salary plus all allowances, for a full month.
  static func monthlyWage(_ line: JSONValue) -> Decimal {
    PwM.dec(line.pwNum("monthlyBasic")) + PwM.total(line.pwList("allowances").map { $0.pwNum("monthly") })
  }

  static func rateWage(_ line: JSONValue, _ rules: JSONValue) -> Decimal {
    rules.pwStr("rateBase") == "basic" ? PwM.dec(line.pwNum("monthlyBasic")) : monthlyWage(line)
  }

  /// `lineLeave`.
  static func lineLeave(_ line: JSONValue) -> (unpaidDays: Double, reducedPay: [JSONValue], calendar: Bool) {
    if let calendar = WebJS.present(line["calendarLeave"]) {
      return (calendar.pwNum("unpaidDays"), calendar.pwList("reducedPay"), true)
    }
    return (line.pwNum("unpaidLeaveDays"), line.pwList("reducedPay"), line.pwStr("leaveBasis") == "calendar")
  }

  /// `calculatePayLine`: works a line out from what was entered.
  static func calculate(_ line: JSONValue, _ rules: JSONValue, _ p: Int) -> JSONValue {
    let daysInMonth = max(1, line.pwNum("daysInMonth"))
    let daysWorked = min(max(0, line.pwNum("daysWorked")), daysInMonth)
    let fraction = PwM.dec(daysWorked) / PwM.dec(daysInMonth)
    let monthlyBasic = line.pwNum("monthlyBasic")
    let sourceAllowances = line.pwList("allowances")

    func earnedFor(_ share: Decimal) -> Decimal {
      PwM.dec(PwM.round(PwM.dec(monthlyBasic) * share, p))
        + PwM.total(sourceAllowances.map { PwM.round(PwM.dec($0.pwNum("monthly")) * share, p) })
    }
    let basic = PwM.round(PwM.dec(monthlyBasic) * fraction, p)
    let allowances = sourceAllowances.map { a in
      a.pwWith("amount", .number(PwM.round(PwM.dec(a.pwNum("monthly")) * fraction, p)))
    }
    let allowanceTotal = PwM.round(PwM.total(allowances.map { $0.pwNum("amount") }), p)
    let earned = PwM.dec(basic) + PwM.dec(allowanceTotal)

    let daily = dailyRate(rateWage(line, rules), rules.pwNum("dailyDivisor"))
    let hourly = daily / PwM.dec(hoursPerDay)
    let hours = line["overtime"] ?? .object([:])
    let normal = PwM.dec(hours.pwNum("normal")) * PwM.dec(overtimeNormal)
    let restDay = PwM.dec(hours.pwNum("restDay")) * PwM.dec(overtimeRestDay)
    let holiday = PwM.dec(hours.pwNum("holiday")) * PwM.dec(overtimeHoliday)
    let weighted = normal + restDay + holiday
    let overtime = PwM.round(hourly * weighted, p)

    let leave = lineLeave(line)
    let leaveDays = PwM.dec(max(0, leave.unpaidDays)) + reducedDays(leave.reducedPay)
    var leaveLost = Decimal(0)
    if leave.calendar {
      let paidDays = leaveDays > PwM.dec(daysWorked) ? Decimal(0) : PwM.dec(daysWorked) - leaveDays
      leaveLost = earned - earnedFor(paidDays / PwM.dec(daysInMonth))
    }
    let atDailyRate = PwM.dec(max(0, line.pwNum("absentDays"))) + (leave.calendar ? 0 : leaveDays)
    let lost = PwM.dec(PwM.round(daily * atDailyRate, p)) + leaveLost
    let absenceDeduction = PwM.round(lost > earned ? earned : lost, p)

    let adjustments = line.pwList("adjustments")
    let additions = PwM.round(
      PwM.total(adjustments.filter { $0.pwStr("type") == "addition" }.map { max(0, $0.pwNum("amount")) }), p)
    let otherDeductions = PwM.round(
      PwM.total(adjustments.filter { $0.pwStr("type") == "deduction" }.map { max(0, $0.pwNum("amount")) }), p)
    let gross = PwM.round(
      earned + PwM.dec(overtime) + PwM.dec(additions) - PwM.dec(absenceDeduction), p)

    let rates = contributionRates(
      category: line.pwStr("category"), nationality: line.pwStr("nationality"), rules: rules
    ).rates
    let pifss = rates.map { contributions(monthlyWage(line), fraction, $0, p) } ?? (base: 0, employee: 0, employer: 0)
    let loanDeduction = PwM.round(PwM.total(line.pwList("loans").map { max(0, $0.pwNum("amount")) }), p)
    let uncovered = PwM.dec(pifss.employee) - PwM.dec(gross)
    let pifssOwed = uncovered > 0 ? PwM.round(uncovered, p) : 0
    let net = PwM.round(
      PwM.dec(gross) - PwM.dec(pifss.employee) + PwM.dec(pifssOwed) - PwM.dec(loanDeduction)
        - PwM.dec(otherDeductions), p)

    var out = line.pwFields
    out["pifssOwed"] = nil
    let worked: [String: JSONValue] = [
      "daysWorked": .number(daysWorked), "daysInMonth": .number(daysInMonth), "allowances": .array(allowances),
      "basic": .number(basic), "allowanceTotal": .number(allowanceTotal), "overtimePay": .number(overtime),
      "absenceDeduction": .number(absenceDeduction), "additions": .number(additions), "gross": .number(gross),
      "pifssBase": .number(pifss.base), "pifssEmployee": .number(pifss.employee),
      "pifssEmployer": .number(pifss.employer), "loanDeduction": .number(loanDeduction),
      "otherDeductions": .number(otherDeductions), "net": .number(net),
    ]
    for (key, value) in worked { out[key] = value }
    if pifssOwed > 0 { out["pifssOwed"] = .number(pifssOwed) }
    return .object(out)
  }

  /// The reduced-pay days a line loses, as decimals all the way (`total(... .times().dividedBy())`).
  private static func reducedDays(_ reduced: [JSONValue]) -> Decimal {
    var sum = Decimal(0)
    for r in reduced {
      let share = 100 - min(100, max(0, r.pwNum("percent")))
      sum += PwM.dec(max(0, r.pwNum("days"))) * PwM.dec(share) / 100
    }
    return sum
  }

  /// `payLineWarnings` codes (the ones payroll checks before posting, and the pages show).
  static func warnings(_ line: JSONValue, _ rules: JSONValue, _ p: Int) -> [String] {
    var out: [String] = []
    let minor = { (n: Double) in PwM.minor(n, p) }
    if minor(line.pwNum("monthlyBasic")) == 0
      && line.pwList("allowances").allSatisfy({ minor($0.pwNum("monthly")) == 0 })
    {
      out.append("no_salary")
    }
    if minor(line.pwNum("net")) < 0 { out.append("negative_net") }
    if minor(line.pwNum("pifssOwed")) > 0 { out.append("pifss_owed") }
    let gross = PwM.dec(line.pwNum("gross"))
    let loanLimit = PwM.round(gross * PwM.dec(loanCapPercent) / 100, p)
    if minor(line.pwNum("loanDeduction")) > minor(loanLimit) { out.append("loan_cap") }
    let deductionLimit = PwM.round(gross * PwM.dec(deductionCapPercent) / 100, p)
    if minor(line.pwNum("loanDeduction")) + minor(line.pwNum("otherDeductions")) > minor(deductionLimit) {
      out.append("deduction_cap")
    }
    let worked = line.pwNum("daysWorked")
    if line.pwStr("category") != "domestic" && worked > 0 && rules.pwNum("minimumWage") > 0 {
      let minimum = PwM.round(
        PwM.dec(rules.pwNum("minimumWage")) * PwM.dec(worked) / PwM.dec(max(1, line.pwNum("daysInMonth"))), p)
      if minor(line.pwNum("net")) >= 0 && minor(line.pwNum("net")) < minor(minimum) { out.append("minimum_wage") }
    }
    if line.pwStr("category") == "expat" && minor(line.pwNum("permitSalary")) > minor(line.pwNum("monthlyBasic")) {
      out.append("permit_salary")
    }
    if minor(line.pwNum("net")) > 0
      && !hasPayAccount(iban: line.pwStr("iban"), accountNumber: line.pwText("accountNumber"))
    {
      out.append("iban")
    }
    if contributionRates(category: line.pwStr("category"), nationality: line.pwStr("nationality"), rules: rules)
      .missing
    {
      out.append(line.pwStr("category") == "gcc" ? "gcc_rates" : "pifss_rates")
    }
    return out
  }

  /// `hasPayAccount` of salary-file.ts.
  static func hasPayAccount(iban: String, accountNumber: String?) -> Bool {
    if !Kuwait.compactIban(iban).isEmpty { return Kuwait.isValidIban(iban) }
    let account = WebJS.removing(accountNumber ?? "") { WebJS.isSpace($0) || $0 == "-" }
    return !account.isEmpty
  }

  // MARK: Totals

  struct Totals: Sendable {
    var employees = 0
    var salaries = 0.0
    var allowances = 0.0
    var gross = 0.0
    var overtime = 0.0
    var absence = 0.0
    var pifssEmployee = 0.0
    var pifssEmployer = 0.0
    var pifssOwed = 0.0
    var loans = 0.0
    var otherDeductions = 0.0
    var deductions = 0.0
    var net = 0.0
    var cost = 0.0
  }

  /// `payRunTotals`: in minor units, so they match the journal to the fils.
  static func totals(_ lines: [JSONValue], _ p: Int) -> Totals {
    let m = { (n: Double) in PwM.minor(n, p) }
    var salaries: Int64 = 0
    var allowances: Int64 = 0
    var gross: Int64 = 0
    var overtime: Int64 = 0
    var absence: Int64 = 0
    var pifssEmployee: Int64 = 0
    var pifssEmployer: Int64 = 0
    var pifssOwed: Int64 = 0
    var loans: Int64 = 0
    var other: Int64 = 0
    var net: Int64 = 0
    for line in lines {
      let basic = m(line.pwNum("basic"))
      let lost = m(line.pwNum("absenceDeduction"))
      let fromBasic = min(lost, basic)
      salaries += basic - fromBasic
      allowances +=
        m(line.pwNum("allowanceTotal")) - (lost - fromBasic) + m(line.pwNum("overtimePay"))
        + m(line.pwNum("additions"))
      gross += m(line.pwNum("gross"))
      overtime += m(line.pwNum("overtimePay"))
      absence += lost
      pifssEmployee += m(line.pwNum("pifssEmployee"))
      pifssEmployer += m(line.pwNum("pifssEmployer"))
      pifssOwed += m(line.pwNum("pifssOwed"))
      loans += m(line.pwNum("loanDeduction"))
      other += m(line.pwNum("otherDeductions"))
      net += m(line.pwNum("net"))
    }
    let f = { (n: Int64) in PwM.fromMinor(n, p) }
    var out = Totals()
    out.employees = lines.count
    out.salaries = f(salaries)
    out.allowances = f(allowances)
    out.gross = f(gross)
    out.overtime = f(overtime)
    out.absence = f(absence)
    out.pifssEmployee = f(pifssEmployee)
    out.pifssEmployer = f(pifssEmployer)
    out.pifssOwed = f(pifssOwed)
    out.loans = f(loans)
    out.otherDeductions = f(other)
    out.deductions = f(pifssEmployee - pifssOwed + loans + other)
    out.net = f(net)
    out.cost = f(gross + pifssEmployer)
    return out
  }

  // MARK: Totals by department and position (#10)

  /// `tidyText`: trimmed, with runs of white space as one space.
  static func tidy(_ text: String?) -> String {
    guard let text else { return "" }
    var out = String.UnicodeScalarView()
    var space = false
    for scalar in WebJS.trim(text).unicodeScalars {
      if WebJS.isSpace(scalar) {
        space = true
        continue
      }
      if space {
        out.append(" ")
        space = false
      }
      out.append(scalar)
    }
    return String(out)
  }

  private struct Sums {
    var employees = 0
    var gross: Int64 = 0
    var deductions: Int64 = 0
    var net: Int64 = 0
    var pifssEmployer: Int64 = 0
  }

  private static func sums(_ lines: [JSONValue], _ p: Int) -> [String: JSONValue] {
    var s = Sums()
    let m = { (n: Double) in PwM.minor(n, p) }
    for line in lines {
      s.employees += 1
      s.gross += m(line.pwNum("gross"))
      s.deductions +=
        m(line.pwNum("pifssEmployee")) - m(line.pwNum("pifssOwed")) + m(line.pwNum("loanDeduction"))
        + m(line.pwNum("otherDeductions"))
      s.net += m(line.pwNum("net"))
      s.pifssEmployer += m(line.pwNum("pifssEmployer"))
    }
    let f = { (n: Int64) in JSONValue.number(PwM.fromMinor(n, p)) }
    return [
      "employees": .number(Double(s.employees)), "gross": f(s.gross), "deductions": f(s.deductions),
      "net": f(s.net), "pifssEmployer": f(s.pifssEmployer), "cost": f(s.gross + s.pifssEmployer),
    ]
  }

  private static func buckets(_ lines: [JSONValue], _ field: String) -> [(key: String, lines: [JSONValue])] {
    var order: [String] = []
    var map: [String: (key: String, lines: [JSONValue])] = [:]
    for line in lines {
      let name = tidy(line.pwText(field))
      let id = name.lowercased()
      if map[id] == nil {
        order.append(id)
        map[id] = (name, [line])
      } else {
        map[id]?.lines.append(line)
      }
    }
    return order.compactMap { map[$0] }
  }

  /// Named first, then "none" (''), then "other" (null).
  private static func byName(_ a: String, _ b: String) -> Int {
    let rank = { (x: String) in x.isEmpty ? 1 : 0 }
    let order = rank(a) - rank(b)
    return order != 0 ? order : PwSort.baseCompare(a, b)
  }

  /// `payrollBreakdown(lines, precision)`: totals, and by department and position.
  static func breakdown(_ lines: [JSONValue], _ p: Int) -> (totals: JSONValue, departments: JSONValue) {
    let departments = buckets(lines, "department").map { department -> (String, JSONValue) in
      let positions = buckets(department.lines, "jobTitle").map { position -> (String, JSONValue) in
        var fields = sums(position.lines, p)
        fields["jobTitle"] = .string(position.key)
        fields["jobTitleAr"] = .string(
          position.lines.map { tidy($0.pwText("jobTitleAr")) }.first { !$0.isEmpty } ?? "")
        return (position.key, .object(fields))
      }
      let sorted = PwSort.stable(positions) { byName($0.0, $1.0) }.map { $0.1 }
      var fields = sums(department.lines, p)
      fields["department"] = .string(department.key)
      fields["positions"] = .array(sorted)
      return (department.key, .object(fields))
    }
    let sorted = PwSort.stable(departments) { byName($0.0, $1.0) }.map { $0.1 }
    return (.object(sums(lines, p)), .array(sorted))
  }

  // MARK: Postings

  static let labels: [String: String] = [
    "salaries": "Basic salaries", "allowances": "Allowances and overtime", "pifssExpense": "PIFSS – employer share",
    "salariesPayable": "Net salaries payable", "pifssPayable": "PIFSS contributions", "advances": "Loan recoveries",
    "pifssOwed": "PIFSS shares owed by employees", "otherDeductions": "Other deductions",
    "eosExpense": "End-of-service indemnity", "eosProvision": "End-of-service indemnity provision",
    "leaveExpense": "Leave salary", "leaveProvision": "Leave salary provision", "noticePay": "Notice pay",
  ]

  private static func label(_ key: String) -> String { labels[key] ?? key }

  /// `postings(entries)`: merged by account, side and description, without zeros.
  static func postings(_ entries: [(PwAccountKey, Int64, String)]) -> [PwPosting] {
    var order: [String] = []
    var merged: [String: PwPosting] = [:]
    for (key, amount, description) in entries where amount != 0 {
      let id = key.rawValue + "|" + (amount > 0 ? "dr" : "cr") + "|" + description
      if let before = merged[id] {
        merged[id] = PwPosting(key: key, amount: before.amount + amount, description: description)
      } else {
        order.append(id)
        merged[id] = PwPosting(key: key, amount: amount, description: description)
      }
    }
    return order.compactMap { merged[$0] }
  }

  /// `payRunPostings`.
  static func runPostings(_ t: Totals, _ p: Int) -> [PwPosting] {
    let m = { (n: Double) in PwM.minor(n, p) }
    return postings([
      (.salaries, m(t.salaries), label("salaries")),
      (.allowances, m(t.allowances), label("allowances")),
      (.pifssExpense, m(t.pifssEmployer), label("pifssExpense")),
      (.advances, m(t.pifssOwed), label("pifssOwed")),
      (.salariesPayable, -m(t.net), label("salariesPayable")),
      (.pifssPayable, -(m(t.pifssEmployee) + m(t.pifssEmployer)), label("pifssPayable")),
      (.advances, -m(t.loans), label("advances")),
      (.otherDeductions, -m(t.otherDeductions), label("otherDeductions")),
    ])
  }

  /// `provisionPostings`.
  static func provisionPostings(_ eosChange: Int64, _ leaveChange: Int64) -> [PwPosting] {
    postings([
      (.eosExpense, eosChange, label("eosExpense")),
      (.eosProvision, -eosChange, label("eosProvision")),
      (.leaveExpense, leaveChange, label("leaveExpense")),
      (.leaveProvision, -leaveChange, label("leaveProvision")),
    ])
  }

  // MARK: End of service (eosi.ts)

  struct Eosi: Sendable {
    var payable: Double
    var json: JSONValue
  }

  /// `calculateEosi`.
  static func eosi(
    payBasis: String, monthlyWage: Double, years rawYears: Double, reason: String, divisor rawDivisor: Double?,
    pifssOffset: Double = 0, precision p: Int = 3
  ) -> Eosi {
    let divisor: Double = (rawDivisor ?? 0) > 0 ? (rawDivisor ?? 26) : 26
    let wage = PwM.dec(max(0, monthlyWage))
    let years = max(0, rawYears)
    let monthly = payBasis == "monthly"
    let firstDays = monthly ? 15.0 : 10.0
    let capMonths = monthly ? 18.0 : 12.0
    let firstYears = min(years, 5)
    let laterYears = max(0, years - 5)
    let days = { (n: Decimal) in wage * n / PwM.dec(divisor) }
    let firstAmount = PwM.round(days(PwM.dec(firstYears) * PwM.dec(firstDays)), p)
    let laterAmount =
      monthly
      ? PwM.round(wage * PwM.dec(laterYears) * 1, p) : PwM.round(days(PwM.dec(laterYears) * 15), p)
    let gross = PwM.round(PwM.dec(firstAmount) + PwM.dec(laterAmount), p)
    let cap = PwM.round(wage * PwM.dec(capMonths), p)
    let capApplied = gross > cap
    let capped = capApplied ? cap : gross
    let share = eosiShare(reason, (years + 1e-9).rounded(.down))
    let afterShare = PwM.round(PwM.dec(capped) * Decimal(share.numerator) / Decimal(share.denominator), p)
    let offset = PwM.round(max(0, pifssOffset), p)
    let payable = max(0, PwM.round(PwM.dec(afterShare) - PwM.dec(offset), p))
    let first: JSONValue = [
      "years": .number(firstYears), "daysPerYear": .number(firstDays), "monthsPerYear": .null,
      "amount": .number(firstAmount),
    ]
    let later: JSONValue =
      monthly
      ? ["years": .number(laterYears), "daysPerYear": .null, "monthsPerYear": 1, "amount": .number(laterAmount)]
      : ["years": .number(laterYears), "daysPerYear": 15, "monthsPerYear": .null, "amount": .number(laterAmount)]
    let json: JSONValue = [
      "rulesVersion": "KW-LL-6-2010", "years": .number(years), "monthlyWage": .number(PwM.num(wage)),
      "dailyDivisor": .number(divisor), "dailyWage": .number(PwM.round(wage / PwM.dec(divisor), p)),
      "first": first, "later": later, "gross": .number(gross), "cap": .number(cap), "capApplied": .bool(capApplied),
      "capped": .number(capped),
      "share": ["numerator": .number(Double(share.numerator)), "denominator": .number(Double(share.denominator))],
      "afterShare": .number(afterShare), "pifssOffset": .number(offset), "payable": .number(payable),
    ]
    return Eosi(payable: payable, json: json)
  }

  /// `eosiShare`.
  static func eosiShare(_ reason: String, _ years: Double) -> (numerator: Int, denominator: Int) {
    if reason == "termination" { return (1, 1) }
    if reason == "dismissal" { return (0, 1) }
    if years >= 10 { return (1, 1) }
    if years >= 5 { return (2, 3) }
    if years >= 3 { return (1, 2) }
    return (0, 1)
  }

  /// `eosiReasonFor`.
  static func eosiReason(_ reason: String) -> String {
    if reason == "resignation" { return "resignation" }
    if reason == "dismissal" { return "dismissal" }
    return "termination"
  }

  /// `serviceYears`: from the hire date through `until`, both days counted.
  static func serviceYears(_ hireDate: String, _ until: String) -> Double {
    guard let start = PwDates.day(hireDate), let last = PwDates.day(until) else { return 0 }
    let end = last.adding(days: 1)
    if end.dayNumber <= start.dayNumber { return 0 }
    var whole = end.year - start.year
    if start.adding(months: whole * 12).dayNumber > end.dayNumber { whole -= 1 }
    let anniversary = start.adding(months: whole * 12)
    let next = start.adding(months: (whole + 1) * 12)
    let part = Double(end.dayNumber - anniversary.dayNumber) / Double(next.dayNumber - anniversary.dayNumber)
    return PwM.jsRound((Double(whole) + part) * 10_000) / 10_000
  }

  /// `eosWage`: basic salary plus the allowances that count.
  static func eosWage(_ basic: Double, _ allowances: [JSONValue], _ p: Int) -> Double {
    let counting = allowances.filter { $0.pwTruthy("countsForEos") }
    return PwM.round(PwM.dec(basic) + PwM.total(counting.map { $0.pwNum("amount") }), p)
  }

  /// `eosProvisionFor`: the indemnity on a date if the employer ended the contract then.
  static func eosProvision(_ employee: JSONValue, on: String, divisor: Double, _ p: Int) -> Double {
    let hire = employee.pwStr("hireDate")
    if employee.pwStr("category") == "domestic" || hire.isEmpty || WebJS.less(on, hire) { return 0 }
    let wage = eosWage(employee.pwNum("basicSalary"), employee.pwList("allowances"), p)
    if wage <= 0 { return 0 }
    return eosi(
      payBasis: employee.pwStr("payBasis"), monthlyWage: wage, years: serviceYears(hire, on), reason: "termination",
      divisor: divisor, precision: p
    ).payable
  }

  /// `leaveValue`: pay for leave days.
  static func leaveValue(_ days: Double, _ monthly: Double, _ divisor: Double, _ p: Int) -> Double {
    if days <= 0 { return 0 }
    return PwM.round(dailyRate(PwM.dec(monthly), divisor) * PwM.dec(days), p)
  }

  // MARK: Final settlement

  /// `noticeMonthsFor`.
  static func noticeMonths(_ reason: String, _ payBasis: String) -> Double {
    if reason != "termination" { return 0 }
    return payBasis == "monthly" ? 3 : 1
  }

  /// `settlementMissing`.
  static func settlementMissing(_ employee: JSONValue) -> (hireDate: Bool, wage: Bool) {
    let wage =
      PwM.total(employee.pwList("allowances").map { $0.pwNum("amount") }) + PwM.dec(employee.pwNum("basicSalary"))
    return (!employee.pwTruthy("hireDate"), !(wage > 0))
  }

  /// `lastMonthDays`.
  static func lastMonthDays(_ hireDate: String?, _ leavingDate: String) -> Int {
    employedDays(periodOf(leavingDate), hire: hireDate, leaving: leavingDate)
  }

  struct SettlementInput {
    var employee: JSONValue
    var leavingDate: String
    var reason: String
    var rules: JSONValue
    var eosDivisor: Double
    var pifssOffset: Double
    var indemnityOverride: Double?
    var noticeMonths: Double
    var leaveDays: Double
    var lastSalaryDays: Double
    var loans: [JSONValue]
    var otherDeductions: Double
    var eosProvision: Double
    var leaveProvision: Double
    var precision: Int
  }

  struct SettlementAmounts {
    var years: Double
    var eosWage: Double
    var monthlyWage: Double
    var eosi: JSONValue?
    var indemnity: Double
    var noticePay: Double
    var leavePay: Double
    var lastSalary: JSONValue?
    var loanRecovery: Double
    var otherDeductions: Double
    var dues: Double
    var deductions: Double
    var net: Double
  }

  /// `computeSettlement`.
  static func settlement(_ input: SettlementInput) -> SettlementAmounts {
    let p = input.precision
    let e = input.employee
    let hire = e.pwStr("hireDate")
    let years = hire.isEmpty ? 0 : serviceYears(hire, input.leavingDate)
    let wageForEos = eosWage(e.pwNum("basicSalary"), e.pwList("allowances"), p)
    let monthly = PwM.round(
      PwM.total(e.pwList("allowances").map { $0.pwNum("amount") }) + PwM.dec(e.pwNum("basicSalary")), p)
    let rule: Eosi? =
      e.pwStr("category") == "domestic"
      ? nil
      : PwPay.eosi(
        payBasis: e.pwStr("payBasis"), monthlyWage: wageForEos, years: years, reason: eosiReason(input.reason),
        divisor: input.eosDivisor, pifssOffset: input.pifssOffset, precision: p)
    let worked = rule?.payable ?? PwM.round(PwM.dec(wageForEos) * PwM.dec(years), p)
    let indemnity = input.indemnityOverride.map { PwM.round(max(0, $0), p) } ?? worked
    let noticePay = PwM.round(PwM.dec(monthly) * PwM.dec(max(0, input.noticeMonths)), p)
    let leavePay = leaveValue(input.leaveDays, monthly, input.rules.pwNum("dailyDivisor"), p)

    var lastSalary: JSONValue?
    let period = periodOf(input.leavingDate)
    let daysInMonth = daysInPeriod(period)
    let days = Int(min(max(0, PwM.jsRound(input.lastSalaryDays)), Double(daysInMonth)))
    var lastGross = 0.0
    var lastPifssEmployee = 0.0
    if days > 0 {
      let fraction = Decimal(days) / Decimal(daysInMonth)
      let basic = PwM.round(PwM.dec(e.pwNum("basicSalary")) * fraction, p)
      let allowances = PwM.round(
        PwM.total(e.pwList("allowances").map { PwM.round(PwM.dec($0.pwNum("amount")) * fraction, p) }), p)
      let rates = contributionRates(
        category: e.pwStr("category"), nationality: e.pwStr("nationality"), rules: input.rules
      ).rates
      let pifss = rates.map { contributions(PwM.dec(monthly), fraction, $0, p) } ?? (base: 0, employee: 0, employer: 0)
      lastGross = PwM.round(PwM.dec(basic) + PwM.dec(allowances), p)
      lastPifssEmployee = pifss.employee
      lastSalary = [
        "period": .string(period), "days": .number(Double(days)), "daysInMonth": .number(Double(daysInMonth)),
        "basic": .number(basic), "allowances": .number(allowances), "gross": .number(lastGross),
        "pifssEmployee": .number(pifss.employee), "pifssEmployer": .number(pifss.employer),
      ]
    }
    let loanRecovery = PwM.round(PwM.total(input.loans.map { max(0, $0.pwNum("amount")) }), p)
    let otherDeductions = PwM.round(max(0, input.otherDeductions), p)
    let dues = PwM.round(
      PwM.dec(indemnity) + PwM.dec(noticePay) + PwM.dec(leavePay) + PwM.dec(lastGross), p)
    let deductions = PwM.round(
      PwM.dec(lastPifssEmployee) + PwM.dec(loanRecovery) + PwM.dec(otherDeductions), p)
    return SettlementAmounts(
      years: years, eosWage: wageForEos, monthlyWage: monthly, eosi: rule?.json, indemnity: indemnity,
      noticePay: noticePay, leavePay: leavePay, lastSalary: lastSalary, loanRecovery: loanRecovery,
      otherDeductions: otherDeductions, dues: dues, deductions: deductions,
      net: PwM.round(PwM.dec(dues) - PwM.dec(deductions), p))
  }

  /// `settlementPostings`.
  static func settlementPostings(_ a: SettlementAmounts, eos: Double, leave: Double, _ p: Int) -> [PwPosting] {
    let m = { (n: Double) in PwM.minor(n, p) }
    let last = a.lastSalary
    return postings([
      (.eosProvision, m(eos), label("eosProvision")),
      (.eosExpense, m(a.indemnity) - m(eos), label("eosExpense")),
      (.leaveProvision, m(leave), label("leaveProvision")),
      (.leaveExpense, m(a.leavePay) - m(leave), label("leaveExpense")),
      (.salaries, m(a.noticePay), label("noticePay")),
      (.salaries, m(last?.pwNum("basic") ?? 0), label("salaries")),
      (.allowances, m(last?.pwNum("allowances") ?? 0), label("allowances")),
      (.pifssExpense, m(last?.pwNum("pifssEmployer") ?? 0), label("pifssExpense")),
      (
        .pifssPayable, -(m(last?.pwNum("pifssEmployee") ?? 0) + m(last?.pwNum("pifssEmployer") ?? 0)),
        label("pifssPayable")
      ),
      (.advances, -m(a.loanRecovery), label("advances")),
      (.otherDeductions, -m(a.otherDeductions), label("otherDeductions")),
      (.salariesPayable, -m(a.net), label("salariesPayable")),
    ])
  }
}
