import Foundation
import MahamKit

// Manpower costing (src/lib/hr/costing.ts): what a post of guards, cleaners
// or other staff costs a month and the price that leaves the company's
// margin; and employee letters (src/lib/hr/letters.ts,
// letter-templates.ts): their kinds, states and the app's own wording.

// MARK: - Costing records

/// A job title's pay on the rate card.
struct PeCostingRate: Identifiable {
  let id: String
  let jobTitle: String
  let jobTitleAr: String?
  let category: String
  let nationality: String
  let basic: Double
  let allowances: Double
  let eosAllowances: Double?
  let otherCosts: Double
  let count: Int?

  init(
    id: String, jobTitle: String, jobTitleAr: String?, category: String, nationality: String, basic: Double,
    allowances: Double, eosAllowances: Double?, otherCosts: Double, count: Int?
  ) {
    self.id = id
    self.jobTitle = jobTitle
    self.jobTitleAr = jobTitleAr
    self.category = category
    self.nationality = nationality
    self.basic = basic
    self.allowances = allowances
    self.eosAllowances = eosAllowances
    self.otherCosts = otherCosts
    self.count = count
  }

  init(_ raw: JSONValue) {
    id = raw.str("id")
    jobTitle = raw.str("jobTitle")
    jobTitleAr = raw.text("jobTitleAr")
    category = PeCosting.category(raw.str("category"))
    nationality = raw.str("nationality")
    basic = raw.num("basic")
    allowances = raw.num("allowances")
    eosAllowances = raw.number("eosAllowances")
    otherCosts = raw.num("otherCosts")
    count = raw.number("count").map { Int($0) }
  }

  var displayTitle: String { localName(jobTitle, jobTitleAr) }
}

/// The company's manpower costing settings: off, 10% overhead and 15% margin until changed.
struct PeCostingSettings {
  let on: Bool
  let overheadPercent: Double
  let marginPercent: Double
  /// The saved rate card; nil until one is saved.
  let rates: [PeCostingRate]?

  init(_ raw: JSONValue?) {
    on = raw?["on"]?.bool == true
    overheadPercent = raw?.number("overheadPercent") ?? 10
    marginPercent = raw?.number("marginPercent") ?? 15
    rates = raw?["rates"]?.array.map { list in list.map { PeCostingRate($0) } }
  }
}

/// What posts are priced with today: the payroll and People settings (`CostingBasis`).
struct PeCostingBasis {
  let precision: Int
  let dailyDivisor: Double
  let rateBase: String
  let pifss: PeRates?
  let gcc: [PeRates]
  let minimumWage: Double
  let eosDivisor: Double
  let eosForInsured: Bool
  let annualLeaveDays: Double
}

/// What needs a second look on a post.
struct PeCostingWarning {
  enum Kind { case overtimeLimit, overtimeYear, restDays, belowMinimumWage, pifssMissing, gccSchemeMissing }
  let kind: Kind
  let jobTitle: String
  let jobTitleAr: String?
  let value: Double
  let days: Double
}

/// One post of a costing, priced.
struct PePricedPost: Identifiable {
  let id: String
  let jobTitle: String
  let jobTitleAr: String?
  let category: String
  let nationality: String
  let headcount: Int
  let hoursPerDay: Double
  let daysPerMonth: Double
  let basic: Double
  let allowances: Double
  let eosAllowances: Double?
  let otherCosts: Double
  /// Per person a month.
  let overtime: Double
  let employerPifss: Double
  let eosi: Double
  let leave: Double
  let cost: Double
  let overhead: Double
  let fullCost: Double
  let sell: Double
  let margin: Double
  /// For the post's headcount.
  let totalCost: Double
  let totalOverhead: Double
  let totalFullCost: Double
  let totalSell: Double
  let totalMargin: Double
  let warnings: [PeCostingWarning]

  var displayTitle: String { localName(jobTitle, jobTitleAr) }
}

/// A costing's totals a month.
struct PeCostingTotals {
  var headcount = 0
  var cost: Double = 0
  var overhead: Double = 0
  var fullCost: Double = 0
  var sell: Double = 0
  var margin: Double = 0
  var marginPercent: Double = 0
  var markupPercent: Double = 0
}

@MainActor
enum PeCosting {
  nonisolated static func category(_ value: String) -> String {
    value == "kuwaiti" || value == "gcc" ? value : "expat"
  }

  nonisolated static func categoryLabel(_ category: String) -> String {
    switch category {
    case "kuwaiti": t("Kuwaiti")
    case "gcc": t("GCC national")
    default: t("Expatriate")
    }
  }

  nonisolated static func statusMeta(_ status: String) -> StatusMeta {
    switch status {
    case "quoted": StatusMeta(label: "Quote made", tone: .blue)
    case "won": StatusMeta(label: "Won", tone: .green)
    case "lost": StatusMeta(label: "Lost", tone: .red)
    default: StatusMeta(label: "Draft", tone: .gray)
    }
  }

  private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
    value.isFinite ? min(high, max(low, value)) : low
  }

  /// A percentage as used in prices: 0 or more, to two decimals.
  static func percentOf(_ value: Double, max high: Double) -> Double {
    PeMoney.round(clamp(value, 0, high), 2)
  }

  /// The sell price that leaves `marginPercent` of it as margin: cost ÷ (1 − margin).
  static func sellPrice(_ cost: Double, marginPercent: Double, _ p: Int = 3) -> Double {
    let margin = percentOf(marginPercent, max: 90)
    return PeMoney.round(PeMoney.dec(cost) / (Decimal(100) - PeMoney.dec(margin)) * Decimal(100), p)
  }

  /// The markup on cost that gives a margin: m ÷ (1 − m).
  static func markup(forMargin marginPercent: Double) -> Double {
    let margin = percentOf(marginPercent, max: 90)
    return PeMoney.round(PeMoney.dec(margin) * Decimal(100) / (Decimal(100) - PeMoney.dec(margin)), 3)
  }

  /// A margin and the markup it makes, in words.
  static func marginExplained(_ typed: Double) -> String {
    let margin = percentOf(typed, max: 90)
    return t(
      "A {margin}% margin is a {markup}% markup on cost: a cost of 100.000 sells at {price}. The margin is a share of the sell price; a markup is added to the cost.",
      [
        "margin": Money.jsString(margin), "markup": Money.jsString(markup(forMargin: margin)),
        "price": String(format: "%.3f", sellPrice(100, marginPercent: margin)),
      ])
  }

  /// What posts are priced with today.
  static func basis(_ payroll: PePayrollSettings, _ people: PePeopleSettings, precision: Int) -> PeCostingBasis {
    let today = PeDates.today
    return PeCostingBasis(
      precision: precision, dailyDivisor: payroll.dailyDivisor, rateBase: payroll.rateBase,
      pifss: PePayroll.ratesOn(payroll.pifss, today), gcc: payroll.gcc, minimumWage: payroll.minimumWage,
      eosDivisor: people.eosDailyDivisor, eosForInsured: payroll.eosForInsured,
      annualLeaveDays: PeLeave.annualDaysOn(today, policy: payroll.leavePolicy))
  }

  /// `pricePost`: what one person of a post costs and sells for a month, and the post's totals.
  static func price(_ raw: JSONValue, basis: PeCostingBasis, overheadPercent: Double, marginPercent: Double)
    -> PePricedPost
  {
    let p = basis.precision
    let headcount = max(1, Int(PeMoney.jsRound(raw.number("headcount") ?? 1)))
    let hours = PeMoney.round(clamp(raw.num("hoursPerDay"), 1, 24), 2)
    let days = PeMoney.round(clamp(raw.num("daysPerMonth"), 1, 31), 2)
    let basic = PeMoney.round(max(0, raw.num("basic")), p)
    let allowances = PeMoney.round(max(0, raw.num("allowances")), p)
    let otherCosts = PeMoney.round(max(0, raw.num("otherCosts")), p)
    var eosAllowances: Double?
    if let value = raw.number("eosAllowances"), value.isFinite {
      let kept = PeMoney.round(max(0, value), p)
      if kept < allowances { eosAllowances = kept }
    }
    let kind = Self.category(raw.str("category"))
    let jobTitle = raw.str("jobTitle")
    let jobTitleAr = raw.text("jobTitleAr")
    var warnings: [PeCostingWarning] = []
    func warn(_ kind: PeCostingWarning.Kind, _ value: Double = 0, _ days: Double = 0) {
      warnings.append(PeCostingWarning(kind: kind, jobTitle: jobTitle, jobTitleAr: jobTitleAr, value: value, days: days))
    }

    let divisor = basis.dailyDivisor > 0 ? basis.dailyDivisor : 26
    let divisorDec = PeMoney.dec(divisor)
    let wage = PeMoney.dec(basic) + PeMoney.dec(allowances)
    let rateWage = basis.rateBase == "basic" ? PeMoney.dec(basic) : wage
    let hourly = rateWage / divisorDec / Decimal(8)
    let overtimeHours = PeMoney.round(max(0, hours - 8), 2)
    let workingDays = min(days, divisor)
    let restDays = PeMoney.round(max(0, days - divisor), 2)
    let overtime = PeMoney.round(
      hourly * PeMoney.dec(overtimeHours) * PeMoney.dec(workingDays) * PeMoney.dec(1.25), p)
    let restDayPay = PeMoney.round(hourly * PeMoney.dec(hours) * PeMoney.dec(restDays) * PeMoney.dec(1.5), p)
    if overtimeHours > 2 {
      warn(.overtimeLimit, overtimeHours)
    } else if overtimeHours > 0 {
      let daysAWeek = PeMoney.round(PeMoney.dec(workingDays) * Decimal(12) / Decimal(52), 1)
      let hoursAYear = PeMoney.round(PeMoney.dec(overtimeHours) * PeMoney.dec(workingDays) * Decimal(12), 0)
      if daysAWeek > 3 || hoursAYear > 180 { warn(.overtimeYear, hoursAYear, daysAWeek) }
    }
    if restDays > 0 { warn(.restDays, restDays) }
    if basic < basis.minimumWage { warn(.belowMinimumWage) }

    var employerPifss = 0.0
    let insured = kind == "kuwaiti" || kind == "gcc"
    if insured {
      let found = PePayroll.contributionRates(
        category: kind, nationality: raw.str("nationality"), pifss: basis.pifss, gcc: basis.gcc)
      if let rates = found.rates {
        employerPifss = PePayroll.contributions(wage, Decimal(1), rates, p).employer
      } else {
        warn(kind == "gcc" ? .gccSchemeMissing : .pifssMissing)
      }
    }

    // The indemnity a month of service earns at the first five years' rate (art. 51).
    let eosWage = PeMoney.dec(basic) + PeMoney.dec(eosAllowances ?? allowances)
    var eosi = 0.0
    if !(insured && !basis.eosForInsured) {
      let year = PeEosi.calculate(
        payBasis: "monthly", monthlyWage: Money.toNumber(eosWage), years: 1, reason: .termination,
        dailyDivisor: basis.eosDivisor, precision: 9)
      eosi = PeMoney.round(PeMoney.dec(year.payable) / Decimal(12), p)
    }
    let leaveDays = basis.annualLeaveDays > 0 ? basis.annualLeaveDays : 30
    let leave = PeMoney.round(wage / divisorDec * PeMoney.dec(leaveDays) / Decimal(12), p)
    let cost = PeMoney.round(
      PeMoney.sum([basic, allowances, overtime, restDayPay, employerPifss, eosi, leave, otherCosts]), p)
    let overheadShare = percentOf(overheadPercent, max: 200)
    let overhead = PeMoney.round(PeMoney.dec(cost) * PeMoney.dec(overheadShare) / Decimal(100), p)
    let fullCost = PeMoney.round(PeMoney.dec(cost) + PeMoney.dec(overhead), p)
    let sell = sellPrice(fullCost, marginPercent: marginPercent, p)
    let margin = PeMoney.round(PeMoney.dec(sell) - PeMoney.dec(fullCost), p)
    func times(_ value: Double) -> Double { PeMoney.round(PeMoney.dec(value) * Decimal(headcount), p) }
    return PePricedPost(
      id: raw.str("id"), jobTitle: jobTitle, jobTitleAr: jobTitleAr, category: kind,
      nationality: kind == "gcc" ? raw.str("nationality") : "", headcount: headcount, hoursPerDay: hours,
      daysPerMonth: days, basic: basic, allowances: allowances, eosAllowances: eosAllowances,
      otherCosts: otherCosts, overtime: PeMoney.round(PeMoney.dec(overtime) + PeMoney.dec(restDayPay), p),
      employerPifss: employerPifss, eosi: eosi, leave: leave, cost: cost, overhead: overhead, fullCost: fullCost,
      sell: sell, margin: margin, totalCost: times(cost), totalOverhead: times(overhead),
      totalFullCost: times(fullCost), totalSell: times(sell), totalMargin: times(margin), warnings: warnings)
  }

  /// `priceCosting`: every post priced, with the totals.
  static func price(_ costing: JSONValue, basis: PeCostingBasis) -> (posts: [PePricedPost], totals: PeCostingTotals) {
    let p = basis.precision
    let posts = costing.list("posts").map {
      price($0, basis: basis, overheadPercent: costing.num("overheadPercent"), marginPercent: costing.num("marginPercent"))
    }
    var totals = PeCostingTotals()
    totals.headcount = posts.reduce(0) { $0 + $1.headcount }
    totals.cost = PeMoney.round(PeMoney.sum(posts.map(\.totalCost)), p)
    totals.overhead = PeMoney.round(PeMoney.sum(posts.map(\.totalOverhead)), p)
    totals.fullCost = PeMoney.round(PeMoney.sum(posts.map(\.totalFullCost)), p)
    totals.sell = PeMoney.round(PeMoney.sum(posts.map(\.totalSell)), p)
    totals.margin = PeMoney.round(PeMoney.sum(posts.map(\.totalMargin)), p)
    if totals.sell > 0 {
      totals.marginPercent = PeMoney.round(PeMoney.dec(totals.margin) * Decimal(100) / PeMoney.dec(totals.sell), 2)
    }
    if totals.fullCost > 0 {
      totals.markupPercent = PeMoney.round(
        PeMoney.dec(totals.margin) * Decimal(100) / PeMoney.dec(totals.fullCost), 2)
    }
    return (posts, totals)
  }

  /// The sell price of a costing a month, as last saved.
  static func monthly(_ costing: JSONValue) -> Double {
    let parts = costing.list("posts").map { PeMoney.dec($0.num("sellPrice")) * PeMoney.dec($0.num("headcount")) }
    return PeMoney.round(parts.reduce(Decimal(0), +), 3)
  }

  /// A warning in words.
  static func warningText(_ warning: PeCostingWarning, _ format: CompanyFormat) -> String {
    let arabic = Localization.language == .ar ? warning.jobTitleAr : nil
    let named = arabic ?? warning.jobTitle
    let title = named.isEmpty ? t("A post") : named
    let value = format.quantity(warning.value)
    switch warning.kind {
    case .overtimeLimit:
      return t(
        "{title}: {value} hours of overtime a day. Article 66 of Labour Law 6/2010 limits overtime to 2 hours a day, 3 days a week and 180 hours a year unless an exemption applies. Confirm with counsel before quoting, or add people to the post.",
        ["title": title, "value": value])
    case .overtimeYear:
      return t(
        "{title}: overtime on about {days} days a week, about {value} hours a year. Article 66 of Labour Law 6/2010 limits overtime to 2 hours a day, 3 days a week and 180 hours a year unless an exemption applies. Confirm with counsel before quoting, or add people to the post.",
        ["title": title, "value": value, "days": format.quantity(warning.days)])
    case .restDays:
      return t(
        "{title}: {value} rest days worked a month, priced at 1.5. Article 67 also gives a day off in lieu for each; relief staff may cost less.",
        ["title": title, "value": value])
    case .belowMinimumWage:
      return t("{title}: the basic salary is below the minimum wage in Payroll settings.", ["title": title])
    case .pifssMissing:
      return t(
        "{title}: no PIFSS rates are set in Payroll settings, so the employer’s share is left out.", ["title": title])
    case .gccSchemeMissing:
      return t(
        "{title}: no rates are set for this GCC nationality in Payroll settings, so the employer’s share is left out.",
        ["title": title])
    }
  }

  /// The rate card from the current salaries: each job title's average pay (`averageRates`).
  static func averageRates(_ employees: [PeEmployee], _ p: Int) -> [PeCostingRate] {
    var groups: [String: [PeEmployee]] = [:]
    var order: [String] = []
    for e in employees {
      if e.status == "left" || e.category == "domestic" || e.payBasis != "monthly" { continue }
      let allowanceSum = PeMoney.sum(e.allowances.map(\.amount))
      if !(e.basicSalary > 0) && !(allowanceSum > 0) { continue }
      let title = PeCompliance.titleKey(e.jobTitle)
      if title.isEmpty { continue }
      let key = title + "|" + category(e.category)
      if groups[key] == nil { order.append(key) }
      groups[key, default: []].append(e)
    }
    var rates: [PeCostingRate] = []
    for key in order {
      let list = groups[key] ?? []
      let kind = String(key.split(separator: "|").last ?? "expat")
      func average(_ pick: (PeEmployee) -> Decimal) -> Double {
        let total = list.reduce(Decimal(0)) { $0 + pick($1) }
        return PeMoney.round(total / Decimal(max(1, list.count)), p)
      }
      let allowances = average { PeMoney.sum($0.allowances.map(\.amount)) }
      let eos = average { PeMoney.sum($0.allowances.filter(\.countsForEos).map(\.amount)) }
      let arabic = mostCommon(list.map { ($0.jobTitleAr ?? "").trimmingCharacters(in: .whitespaces) })
      rates.append(
        PeCostingRate(
          id: key, jobTitle: mostCommon(list.map { $0.jobTitle.trimmingCharacters(in: .whitespaces) }),
          jobTitleAr: arabic.isEmpty ? nil : arabic, category: kind,
          nationality: kind == "gcc" ? mostCommon(list.map(\.nationality)) : "",
          basic: average { PeMoney.dec($0.basicSalary) }, allowances: allowances,
          eosAllowances: eos < allowances ? eos : nil, otherCosts: 0, count: list.count))
    }
    return rates.sorted { a, b in
      (a.count ?? 0) != (b.count ?? 0)
        ? (a.count ?? 0) > (b.count ?? 0) : a.jobTitle.localizedCompare(b.jobTitle) == .orderedAscending
    }
  }

  /// The value most of them have (the first of the most common), or "".
  private static func mostCommon(_ values: [String]) -> String {
    var counts: [String: Int] = [:]
    var order: [String] = []
    for value in values where !value.isEmpty {
      if counts[value] == nil { order.append(value) }
      counts[value, default: 0] += 1
    }
    var best = ""
    var most = 0
    for value in order where (counts[value] ?? 0) > most {
      best = value
      most = counts[value] ?? 0
    }
    return best
  }
}

// MARK: - Letters

/// A letter template: the company's own, or the app's wording until it is changed.
struct PeLetterTemplate: Identifiable {
  let id: String
  let kind: String
  let name: String
  let nameAr: String?
  let language: String
  let subjectEn: String
  let subjectAr: String
  let bodyEn: String
  let bodyAr: String
  let showStamp: Bool
  let showSignature: Bool
  let signatoryName: String
  let signatoryTitle: String
  let autoOn: [String]
  let privateFields: Bool
  let archived: Bool
  let updatedAt: String

  /// One of the app's default templates (its id is `default:<company>:<kind>`).
  var isDefault: Bool { id.hasPrefix("default:") }

  var displayName: String {
    let local = localName(name, nameAr)
    return local.isEmpty ? PeLetters.kindLabel(kind) : local
  }
}

/// The app's starting wording of a kind of letter, in Arabic and English.
struct PeWording: Sendable {
  let name: String
  let nameAr: String
  let subjectEn: String
  let subjectAr: String
  let bodyEn: String
  let bodyAr: String
}

enum PeLetters {
  static let kinds = [
    "salary_certificate", "experience_certificate", "employment_certificate", "warning", "noc", "salary_transfer",
    "custom",
  ]

  /// The kinds the company starts with.
  static let defaultKinds = ["salary_certificate", "experience_certificate", "employment_certificate", "warning", "noc"]

  static func kindLabel(_ kind: String) -> String {
    switch kind {
    case "salary_certificate": t("Salary certificate")
    case "experience_certificate": t("Experience certificate")
    case "employment_certificate": t("Employment certificate")
    case "warning": t("Warning letter")
    case "noc": t("No objection certificate")
    case "salary_transfer": t("Salary transfer letter")
    case "custom": t("Other letter")
    default: t("Letter")
    }
  }

  static func languageLabel(_ language: String) -> String {
    switch language {
    case "en": t("English")
    case "ar-en": t("Arabic and English")
    default: t("Arabic")
    }
  }

  static let triggers = ["joining", "leaving", "salary_change"]

  static func triggerLabel(_ trigger: String) -> String {
    switch trigger {
    case "joining": t("When an employee joins")
    case "leaving": t("When an employee leaves")
    case "salary_change": t("When a salary changes")
    default: trigger
    }
  }

  static func triggerNote(_ trigger: String) -> String {
    switch trigger {
    case "joining": t("Made when they joined")
    case "leaving": t("Made when they left")
    case "salary_change": t("Made when their salary changed")
    default: t("Made automatically")
    }
  }

  static func statusMeta(_ status: String) -> StatusMeta {
    switch status {
    case "issued": StatusMeta(label: "Issued", tone: .green)
    case "void": StatusMeta(label: "Void", tone: .gray)
    default: StatusMeta(label: "Draft", tone: .amber)
    }
  }

  private static func lines(_ rows: String...) -> String { rows.joined(separator: "\n") }

  /// `DEFAULT_WORDING`: the company's data, never translated.
  static let wording: [String: PeWording] = [
    "salary_certificate": PeWording(
      name: "Salary certificate", nameAr: "شهادة راتب", subjectEn: "Salary certificate", subjectAr: "شهادة راتب",
      bodyEn: lines(
        "{letter.addressee}", "",
        "This is to certify that the holder of this certificate is employed by {company.name} as follows:", "",
        "Name: {employee.name}", "Nationality: {employee.nationality}", "Job title: {employee.jobTitle}",
        "Department: {employee.department}", "Date of joining: {employee.hireDate}",
        "Total monthly salary: {salary.total}", "({salary.totalWords})", "",
        "This certificate is issued at the employee’s request, without any liability on the company."),
      bodyAr: lines(
        "{letter.addressee}", "", "تشهد {company.name} بأن صاحب هذه الشهادة يعمل لديها وفق البيانات التالية:", "",
        "الاسم: {employee.name}", "الجنسية: {employee.nationality}", "المسمى الوظيفي: {employee.jobTitle}",
        "القسم: {employee.department}", "تاريخ التعيين: {employee.hireDate}",
        "الراتب الشهري الإجمالي: {salary.total}", "({salary.totalWords})", "",
        "وقد أُعطيت هذه الشهادة بناءً على طلبه دون أدنى مسؤولية على الشركة.")),
    "experience_certificate": PeWording(
      name: "Experience certificate", nameAr: "شهادة خبرة", subjectEn: "Experience certificate",
      subjectAr: "شهادة خبرة",
      bodyEn: lines(
        "{letter.addressee}", "",
        "This is to certify that the holder of this certificate worked for {company.name} as follows:", "",
        "Name: {employee.name}", "Nationality: {employee.nationality}", "Job title: {employee.jobTitle}",
        "Department: {employee.department}",
        "Period of service: from {employee.hireDate} to {service.end} ({service.length})", "",
        "This certificate is issued at the employee’s request, without any liability on the company. We wish them every success."
      ),
      bodyAr: lines(
        "{letter.addressee}", "", "تشهد {company.name} بأن صاحب هذه الشهادة عمل لديها وفق البيانات التالية:", "",
        "الاسم: {employee.name}", "الجنسية: {employee.nationality}", "المسمى الوظيفي: {employee.jobTitle}",
        "القسم: {employee.department}", "مدة الخدمة: من {employee.hireDate} إلى {service.end} ({service.length})", "",
        "وقد أُعطيت هذه الشهادة بناءً على طلبه دون أدنى مسؤولية على الشركة، مع تمنياتنا له بالتوفيق.")),
    "employment_certificate": PeWording(
      name: "Employment certificate", nameAr: "شهادة عمل", subjectEn: "Employment certificate",
      subjectAr: "شهادة عمل",
      bodyEn: lines(
        "{letter.addressee}", "",
        "This is to certify that the holder of this certificate is employed by {company.name} to date as follows:",
        "", "Name: {employee.name}", "Employee number: {employee.number}", "Nationality: {employee.nationality}",
        "Job title: {employee.jobTitle}", "Department: {employee.department}", "Date of joining: {employee.hireDate}",
        "", "This certificate is issued at the employee’s request, without any liability on the company."),
      bodyAr: lines(
        "{letter.addressee}", "", "تشهد {company.name} بأن صاحب هذه الشهادة يعمل لديها حتى تاريخه وفق البيانات التالية:",
        "", "الاسم: {employee.name}", "الرقم الوظيفي: {employee.number}", "الجنسية: {employee.nationality}",
        "المسمى الوظيفي: {employee.jobTitle}", "القسم: {employee.department}", "تاريخ التعيين: {employee.hireDate}", "",
        "وقد أُعطيت هذه الشهادة بناءً على طلبه دون أدنى مسؤولية على الشركة.")),
    "warning": PeWording(
      name: "Warning letter", nameAr: "خطاب إنذار", subjectEn: "Warning", subjectAr: "إنذار",
      bodyEn: lines(
        "To: {employee.name}", "Employee number: {employee.number}", "Job title: {employee.jobTitle}",
        "Department: {employee.department}", "", "The following was noted: {letter.purpose}", "",
        "This breaches the company’s work rules, and this letter is a formal warning. Please follow the work rules from now on: repeating the breach may lead to the penalties set out in the Private Sector Labour Law and the company’s penalties regulation.",
        "", "Please sign below to confirm that you received this letter.", "", "Employee’s signature: ____________",
        "Date received: ____________"),
      bodyAr: lines(
        "إلى: {employee.name}", "الرقم الوظيفي: {employee.number}", "المسمى الوظيفي: {employee.jobTitle}",
        "القسم: {employee.department}", "", "لوحظ ما يلي: {letter.purpose}", "",
        "ويُعد ذلك مخالفة لأنظمة العمل لدى الشركة، لذا نوجّه إليكم هذا الإنذار. نرجو الالتزام بأنظمة العمل مستقبلاً، علماً بأن تكرار المخالفة قد يعرّضكم للجزاءات المنصوص عليها في قانون العمل في القطاع الأهلي ولائحة الجزاءات لدى الشركة.",
        "", "يرجى التوقيع بما يفيد الاستلام.", "", "توقيع الموظف: ____________", "تاريخ الاستلام: ____________")),
    "noc": PeWording(
      name: "No objection certificate", nameAr: "شهادة عدم ممانعة", subjectEn: "No objection certificate",
      subjectAr: "شهادة عدم ممانعة",
      bodyEn: lines(
        "{letter.addressee}", "",
        "{company.name} has no objection to {letter.purpose} for the holder of this certificate, whose details are:",
        "", "Name: {employee.name}", "Nationality: {employee.nationality}", "Job title: {employee.jobTitle}",
        "Date of joining: {employee.hireDate}", "",
        "This certificate is issued at the employee’s request, without any liability on the company."),
      bodyAr: lines(
        "{letter.addressee}", "",
        "تفيد {company.name} بأنه لا مانع لديها من {letter.purpose} لصاحب هذه الشهادة، وبياناته كالتالي:", "",
        "الاسم: {employee.name}", "الجنسية: {employee.nationality}", "المسمى الوظيفي: {employee.jobTitle}",
        "تاريخ التعيين: {employee.hireDate}", "", "وقد أُعطيت هذه الشهادة بناءً على طلبه دون أدنى مسؤولية على الشركة.")),
  ]

  private static func template(_ raw: JSONValue) -> PeLetterTemplate {
    PeLetterTemplate(
      id: raw.rid, kind: raw.str("kind"), name: raw.str("name"), nameAr: raw.text("nameAr"),
      language: raw.text("language") ?? "ar", subjectEn: raw.str("subjectEn"), subjectAr: raw.str("subjectAr"),
      bodyEn: raw.str("bodyEn"), bodyAr: raw.str("bodyAr"), showStamp: raw.flag("showStamp"),
      showSignature: raw.flag("showSignature"), signatoryName: raw.str("signatoryName"),
      signatoryTitle: raw.str("signatoryTitle"), autoOn: raw.list("autoOn").compactMap(\.string),
      privateFields: raw.flag("privateFields"), archived: raw.flag("archived"), updatedAt: raw.str("updatedAt"))
  }

  /// The company's default template of a kind, as it is until someone changes it.
  private static func defaultTemplate(_ kind: String, companyId: String) -> PeLetterTemplate? {
    guard let words = wording[kind] else { return nil }
    return PeLetterTemplate(
      id: "default:\(companyId):\(kind)", kind: kind, name: words.name, nameAr: words.nameAr, language: "ar",
      subjectEn: words.subjectEn, subjectAr: words.subjectAr, bodyEn: words.bodyEn, bodyAr: words.bodyAr,
      showStamp: true, showSignature: true, signatoryName: "", signatoryTitle: "", autoOn: [], privateFields: false,
      archived: false, updatedAt: "")
  }

  private static func kindOrder(_ kind: String) -> Int { kinds.firstIndex(of: kind) ?? kinds.count }

  /// The company's templates, stored and default, by kind then name (`listTemplates`).
  static func templates(stored: [JSONValue], companyId: String) -> [PeLetterTemplate] {
    var list = stored.map { template($0) }
    let ids = Set(list.map(\.id))
    for kind in defaultKinds {
      if let made = defaultTemplate(kind, companyId: companyId), !ids.contains(made.id) { list.append(made) }
    }
    return list.sorted { a, b in
      kindOrder(a.kind) != kindOrder(b.kind)
        ? kindOrder(a.kind) < kindOrder(b.kind) : a.name.localizedCompare(b.name) == .orderedAscending
    }
  }
}
