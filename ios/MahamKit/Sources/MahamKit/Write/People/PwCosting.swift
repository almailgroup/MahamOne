import Foundation

// Manpower costing (#3): the ports of src/db/costings.ts (the switch, the
// settings and rate card, costings saved, marked and deleted) and the
// pricing of src/lib/hr/costing.ts (`normalizeCostingSettings`,
// `pricePost`, `priceCosting`).

public enum PwCosting {
  static let overheadDefault = 10.0
  static let marginDefault = 15.0
  static let maxMargin = 90.0
  static let maxOverhead = 200.0
  public static let statuses = ["draft", "quoted", "won", "lost"]

  // MARK: Who

  /// `costingsAvailable(link)`.
  public static func available(_ link: PwLink?) -> Bool { PwLink.has(link, "staffing_costings") }

  /// `canSeeCostings(link)`.
  public static func canSee(_ link: PwLink?) -> Bool {
    guard let link else { return true }
    return !link.removed && Roles.canSeePeople(link.role)
  }

  /// `canEditCostings(link)`.
  public static func canEdit(_ link: PwLink?) -> Bool {
    guard let link else { return true }
    return canSee(link) && link.mayWrite("staffingCostings")
  }

  private static func assertMayEdit(_ link: PwLink?) throws {
    if !canEdit(link) { throw pwFail("Only the owner, an admin or an accountant makes manpower costings.") }
    if !available(link) {
      throw pwFail("The cloud needs the latest database script first. Ask the owner of the company to run it.")
    }
  }

  // MARK: Settings

  private static func clamp(_ value: Double?, _ low: Double, _ high: Double) -> Double {
    guard let value, value.isFinite else { return low }
    return min(high, max(low, value))
  }

  /// `percentOf(value, max)`.
  static func percentOf(_ value: Double?, _ high: Double) -> Double { PwM.round(clamp(value, 0, high), 2) }

  /// `costingSettingsOf(saved)`.
  static func settingsOf(_ saved: JSONValue?) -> (on: Bool, overhead: Double, margin: Double, rates: [JSONValue]?) {
    let number = { (value: JSONValue?, fallback: Double) -> Double in
      guard let n = value?.double, n.isFinite else { return fallback }
      return n
    }
    return (
      saved?["on"]?.bool == true, number(saved?["overheadPercent"], overheadDefault),
      number(saved?["marginPercent"], marginDefault), saved?["rates"]?.array
    )
  }

  /// The company's costing settings as the page shows them.
  public static func settings(_ ctx: WriteContext) -> (on: Bool, overhead: Double, margin: Double, rates: [JSONValue]?) {
    settingsOf(PwSettings.people(ctx)["costing"])
  }

  private static func amountOf(_ value: JSONValue?, _ p: Int) -> Double {
    guard let n = value?.double, n.isFinite else { return 0 }
    return PwM.round(max(0, n), p)
  }

  private static func eosAllowancesOf(_ input: JSONValue, _ allowances: Double, _ p: Int) -> Double? {
    guard let n = input["eosAllowances"]?.double, n.isFinite else { return nil }
    let kept = PwM.round(max(0, n), p)
    return kept < allowances ? kept : nil
  }

  /// `normalizeRate(input, precision)`.
  static func normalizeRate(_ input: JSONValue, _ p: Int) -> JSONValue {
    let raw = input.pwStr("category")
    let category = ["kuwaiti", "gcc", "expat"].contains(raw) ? raw : "expat"
    let nationality = category == "gcc" ? WebJS.trim(input.pwText("nationality") ?? "").uppercased() : ""
    let jobTitleAr = WebJS.trim(input.pwText("jobTitleAr") ?? "")
    let other = amountOf(input["otherCosts"], p)
    let allowances = amountOf(input["allowances"], p)
    let eos = eosAllowancesOf(input, allowances, p)
    let id = input.pwText("id").flatMap { $0.isEmpty ? nil : $0 } ?? shortIdPlaceholder
    var fields: [String: JSONValue] = [
      "id": .string(id), "jobTitle": .string(WebJS.trim(input.pwText("jobTitle") ?? "")),
      "category": .string(category), "basic": .number(amountOf(input["basic"], p)), "allowances": .number(allowances),
    ]
    if !jobTitleAr.isEmpty { fields["jobTitleAr"] = .string(jobTitleAr) }
    if !nationality.isEmpty { fields["nationality"] = .string(nationality) }
    if let eos { fields["eosAllowances"] = .number(eos) }
    if other != 0 { fields["otherCosts"] = .number(other) }
    if let count = input["count"]?.double, count > 0 { fields["count"] = .number(PwM.jsRound(count)) }
    return .object(fields)
  }

  /// Marks a rate without an id: it is given one from the action's ids (`shortId()`).
  private static let shortIdPlaceholder = "\u{0}"

  /// `normalizeCostingSettings(input, precision)`; rates without an id get one from `ctx`.
  static func normalizeSettings(_ input: JSONValue, _ p: Int, ctx: WriteContext? = nil) -> JSONValue {
    let s = settingsOf(input)
    var out: [String: JSONValue] = [
      "on": .bool(s.on), "overheadPercent": .number(percentOf(s.overhead, maxOverhead)),
      "marginPercent": .number(percentOf(s.margin, maxMargin)),
    ]
    if let rates = s.rates {
      let normalized = rates.map { rate -> JSONValue in
        var made = normalizeRate(rate, p)
        if made.pwStr("id") == shortIdPlaceholder { made.set("id", .string(ctx?.shortId() ?? shortId())) }
        return made
      }
      out["rates"] = .array(normalized.filter { !$0.pwStr("jobTitle").isEmpty })
    }
    return .object(out)
  }

  private static func update(
    _ ctx: WriteContext, link: PwLink?, _ message: String,
    _ change: (_ on: Bool, _ overhead: Double, _ margin: Double, _ rates: [JSONValue]?) -> JSONValue
  ) throws -> JSONValue {
    try assertMayEdit(link)
    let company = ctx.pwCompany
    let p = PwM.places(company?.pwText("currency") ?? "KWD")
    let before = PwSettings.people(ctx)
    let current = settingsOf(before["costing"])
    let next = normalizeSettings(change(current.on, current.overhead, current.margin, current.rates), p, ctx: ctx)
    if let stored = before["costing"], WebJS.truthy(stored), WebJS.json(normalizeSettings(stored, p, ctx: ctx)) == WebJS.json(next)
    {
      return next
    }
    let settings = PwSettings.normalizePeople(before.pwWith("costing", next)).pwWith("updatedAt", .string(ctx.stamp))
    ctx.put("peopleSettings", settings)
    PwLog.add(ctx, "costing", settings.pwId, "settings", message, refs: ActivityRefs(confidential: true))
    return next
  }

  /// `setCostingsOn(companyId, on)`.
  @discardableResult
  public static func setOn(_ ctx: WriteContext, _ on: Bool, link: PwLink?) throws -> JSONValue {
    try update(ctx, link: link, on ? "Manpower costing turned on" : "Manpower costing turned off") { _, overhead, margin, rates in
      var fields: [String: JSONValue] = [
        "on": .bool(on), "overheadPercent": .number(overhead), "marginPercent": .number(margin),
      ]
      if let rates { fields["rates"] = .array(rates) }
      return .object(fields)
    }
  }

  /// `saveCostingSettings(companyId, { overheadPercent, marginPercent, rates })`.
  @discardableResult
  public static func saveSettings(
    _ ctx: WriteContext, overheadPercent: Double, marginPercent: Double, rates newRates: [JSONValue]?, link: PwLink?
  ) throws -> JSONValue {
    try update(ctx, link: link, "Manpower costing settings updated") { on, _, _, rates in
      var fields: [String: JSONValue] = [
        "on": .bool(on), "overheadPercent": .number(overheadPercent), "marginPercent": .number(marginPercent),
      ]
      if let list = newRates ?? rates { fields["rates"] = .array(list) }
      return .object(fields)
    }
  }

  // MARK: Pricing

  /// What posts are priced with (`CostingBasis`).
  struct Basis {
    var precision: Int
    var dailyDivisor: Double
    var rateBase: String
    var pifss: JSONValue?
    var gcc: [JSONValue]
    var minimumWage: Double
    var eosDivisor: Double
    var eosForInsured: Bool
    var annualLeaveDays: Double
  }

  /// `costingBasis(companyId)`: the company's payroll and People settings today.
  static func basis(_ ctx: WriteContext) -> Basis {
    let payroll = PwSettings.payroll(ctx)
    let people = PwSettings.people(ctx)
    return Basis(
      precision: PwM.places(ctx.pwCompany?.pwText("currency") ?? "KWD"), dailyDivisor: payroll.pwNum("dailyDivisor"),
      rateBase: payroll.pwStr("rateBase"), pifss: PwPay.ratesOn(payroll.pwList("pifss"), ctx.today),
      gcc: payroll.pwList("gcc"), minimumWage: payroll.pwNum("minimumWage"), eosDivisor: people.pwNum("eosDailyDivisor"),
      eosForInsured: payroll.pwTruthy("eosForInsured"),
      annualLeaveDays: PwLeave.annualDaysOn(ctx.today, WebJS.present(payroll["leavePolicy"])))
  }

  /// `sellPriceFor(cost, marginPercent, precision)`.
  static func sellPrice(_ cost: Double, _ marginPercent: Double, _ p: Int) -> Double {
    let margin = percentOf(marginPercent, maxMargin)
    return PwM.round(PwM.dec(cost) / (100 - PwM.dec(margin)) * 100, p)
  }

  /// One post priced (`pricePost`): the post as kept, and what it sells for in all.
  static func pricePost(_ input: JSONValue, _ b: Basis, overhead overheadPercent: Double, margin marginPercent: Double)
    -> (post: JSONValue, sell: Double, fullCost: Double, margin: Double, cost: Double)
  {
    let p = b.precision
    let headcount = max(1, PwM.jsRound(input.pwNumber("headcount").flatMap { $0.isFinite ? $0 : nil } ?? 1))
    let basic = PwM.round(max(0, truthyNumber(input["basic"])), p)
    let allowances = PwM.round(max(0, truthyNumber(input["allowances"])), p)
    let otherCosts = PwM.round(max(0, truthyNumber(input["otherCosts"])), p)
    let hoursPerDay = PwM.round(clamp(input.pwNumber("hoursPerDay"), 1, 24), 2)
    let daysPerMonth = PwM.round(clamp(input.pwNumber("daysPerMonth"), 1, 31), 2)
    var post = input.pwMerging([
      "headcount": .number(headcount), "hoursPerDay": .number(hoursPerDay), "daysPerMonth": .number(daysPerMonth),
      "basic": .number(basic), "allowances": .number(allowances), "otherCosts": .number(otherCosts),
    ])
    let eosAllowances = eosAllowancesOf(input, allowances, p)
    post.set("eosAllowances", eosAllowances.map(JSONValue.number))
    let raw = post.pwStr("category")
    let category = raw == "kuwaiti" || raw == "gcc" ? raw : "expat"

    let divisor = b.dailyDivisor > 0 ? b.dailyDivisor : PwPay.dailyDivisor
    let wage = PwM.dec(basic) + PwM.dec(allowances)
    let rateWage = b.rateBase == "basic" ? PwM.dec(basic) : wage
    let hourly = rateWage / PwM.dec(divisor) / 8
    let overtimeHours = PwM.round(max(0, hoursPerDay - 8), 2)
    let workingDays = min(daysPerMonth, divisor)
    let restDays = PwM.round(max(0, daysPerMonth - divisor), 2)
    let overtime = PwM.round(hourly * PwM.dec(overtimeHours) * PwM.dec(workingDays) * PwM.dec(1.25), p)
    let restDayPay = PwM.round(hourly * PwM.dec(hoursPerDay) * PwM.dec(restDays) * PwM.dec(1.5), p)

    var employerPifss = 0.0
    let insured = category == "kuwaiti" || category == "gcc"
    if insured {
      let rules: JSONValue = ["pifss": b.pifss ?? .null, "gcc": .array(b.gcc)]
      let found = PwPay.contributionRates(category: category, nationality: post.pwStr("nationality"), rules: rules)
      if let rates = found.rates { employerPifss = PwPay.contributions(wage, 1, rates, p).employer }
    }
    let eosWage = PwM.dec(basic) + PwM.dec(eosAllowances ?? allowances)
    let eosi: Double =
      insured && !b.eosForInsured
      ? 0
      : PwM.round(
        PwM.dec(
          PwPay.eosi(
            payBasis: "monthly", monthlyWage: PwM.num(eosWage), years: 1, reason: "termination", divisor: b.eosDivisor,
            precision: 9
          ).payable) / 12, p)
    let leaveDays = b.annualLeaveDays > 0 ? b.annualLeaveDays : 30
    let leave = PwM.round(wage / PwM.dec(divisor) * PwM.dec(leaveDays) / 12, p)
    let cost = PwM.round(
      PwM.dec(basic) + PwM.dec(allowances) + PwM.dec(overtime) + PwM.dec(restDayPay) + PwM.dec(employerPifss)
        + PwM.dec(eosi) + PwM.dec(leave) + PwM.dec(otherCosts), p)
    let share = percentOf(overheadPercent, maxOverhead)
    let overhead = PwM.round(PwM.dec(cost) * PwM.dec(share) / 100, p)
    let fullCost = PwM.round(PwM.dec(cost) + PwM.dec(overhead), p)
    let sell = sellPrice(fullCost, marginPercent, p)
    let margin = PwM.round(PwM.dec(sell) - PwM.dec(fullCost), p)
    var priced = post.pwMerging([
      "category": .string(category), "overtimeMonthly": .number(PwM.round(PwM.dec(overtime) + PwM.dec(restDayPay), p)),
      "employerPifss": .number(employerPifss), "eosiMonthly": .number(eosi), "leaveMonthly": .number(leave),
      "monthlyCost": .number(cost), "sellPrice": .number(sell),
    ])
    if category != "gcc" { priced.set("nationality", nil) }
    let times = { (n: Double) in PwM.round(PwM.dec(n) * PwM.dec(headcount), p) }
    return (priced, times(sell), times(fullCost), times(margin), times(cost))
  }

  /// `input.x || 0` for a number.
  private static func truthyNumber(_ value: JSONValue?) -> Double {
    guard let n = value?.double, n != 0, !n.isNaN else { return 0 }
    return n
  }

  /// `priced(input, basis)`: a costing as it is kept, worked out again with today's settings.
  static func priced(_ input: JSONValue, _ b: Basis) -> JSONValue {
    let overhead = percentOf(input.pwNumber("overheadPercent"), maxOverhead)
    let margin = percentOf(input.pwNumber("marginPercent"), maxMargin)
    let posts = input.pwList("posts").map { pricePost($0, b, overhead: overhead, margin: margin).post }.map { post in
      var kept = post.pwWith("jobTitle", .string(WebJS.trim(post.pwStr("jobTitle"))))
      let arabic = WebJS.trim(post.pwStr("jobTitleAr"))
      if !arabic.isEmpty { kept.set("jobTitleAr", .string(arabic)) }
      return kept
    }
    let status = input.pwStr("status")
    return input.pwMerging([
      "name": .string(WebJS.trim(input.pwStr("name"))),
      "clientId": input.pwTruthy("clientId") ? input["clientId"]! : .null,
      "quoteId": input.pwTruthy("quoteId") ? input["quoteId"]! : .null,
      "status": .string(statuses.contains(status) ? status : "draft"),
      "notes": WebJS.present(input["notes"]) ?? "", "overheadPercent": .number(overhead),
      "marginPercent": .number(margin), "posts": .array(posts),
    ])
  }

  /// What a costing comes to, priced with today's settings (`priceCosting` totals).
  public static func totals(_ ctx: WriteContext, _ costing: JSONValue) -> (
    headcount: Double, cost: Double, fullCost: Double, sell: Double, margin: Double
  ) {
    let b = basis(ctx)
    let overhead = percentOf(costing.pwNumber("overheadPercent"), maxOverhead)
    let margin = percentOf(costing.pwNumber("marginPercent"), maxMargin)
    let priced = costing.pwList("posts").map { pricePost($0, b, overhead: overhead, margin: margin) }
    func add(_ values: [Double]) -> Double { PwM.round(PwM.total(values), b.precision) }
    let headcount = priced.reduce(0.0) { $0 + $1.post.pwNum("headcount") }
    return (
      headcount, add(priced.map { $0.cost }), add(priced.map { $0.fullCost }), add(priced.map { $0.sell }),
      add(priced.map { $0.margin })
    )
  }

  // MARK: Costings

  /// `newCosting(companyId, settings, clientId)`: not saved yet.
  public static func newCosting(
    companyId: String, overheadPercent: Double, marginPercent: Double, clientId: String? = nil, now: Date = Date()
  ) -> JSONValue {
    let stamp = Defaults.nowStamp(now)
    return [
      "id": .string(newId()), "companyId": .string(companyId), "name": "", "clientId": .pwOptional(clientId),
      "quoteId": .null, "status": "draft", "posts": [], "overheadPercent": .number(overheadPercent),
      "marginPercent": .number(marginPercent), "notes": "", "createdAt": .string(stamp), "updatedAt": .string(stamp),
    ]
  }

  /// `newPost(rate)`: one person, 8 hours a day, 26 days a month.
  public static func newPost(rate: JSONValue? = nil) -> JSONValue {
    var fields: [String: JSONValue] = [
      "id": .string(shortId()), "jobTitle": rate?["jobTitle"] ?? "", "category": rate?["category"] ?? "expat",
      "headcount": 1, "hoursPerDay": 8, "daysPerMonth": 26, "basic": rate?["basic"] ?? 0,
      "allowances": rate?["allowances"] ?? 0, "employerPifss": 0, "eosiMonthly": 0, "leaveMonthly": 0,
      "otherCosts": rate?["otherCosts"] ?? 0, "monthlyCost": 0, "sellPrice": 0,
    ]
    if let arabic = rate?.pwText("jobTitleAr"), !arabic.isEmpty { fields["jobTitleAr"] = .string(arabic) }
    if rate?.pwStr("category") == "gcc", let nationality = rate?.pwText("nationality"), !nationality.isEmpty {
      fields["nationality"] = .string(nationality)
    }
    if let eos = rate?["eosAllowances"] { fields["eosAllowances"] = eos }
    return .object(fields)
  }

  /// `saveCosting(input)`: worked out again with today's settings.
  @discardableResult
  public static func save(_ ctx: WriteContext, _ input: JSONValue, link: PwLink?) throws -> JSONValue {
    if WebJS.trim(input.pwStr("name")).isEmpty { throw pwFail("Give the costing a name.") }
    if input.pwList("posts").contains(where: { WebJS.trim($0.pwStr("jobTitle")).isEmpty }) {
      throw pwFail("Give each post a job title.")
    }
    let b = basis(ctx)
    try assertMayEdit(link)
    let existing = ctx.get("staffingCostings", input.pwId)
    if let existing, existing.pwStr("companyId") != input.pwStr("companyId") { throw pwFail("Costing not found") }
    let created = WebJS.present(existing?["createdAt"]) ?? WebJS.present(input["createdAt"]) ?? .string(ctx.stamp)
    let costing = priced(input, b).pwMerging(["createdAt": created, "updatedAt": .string(ctx.stamp)])
    ctx.put("staffingCostings", costing)
    PwLog.add(
      ctx, "costing", costing.pwId, existing == nil ? "created" : "updated",
      existing == nil ? "Manpower costing {name} created" : "Manpower costing {name} updated",
      vars: ["name": .text(costing.pwStr("name"))],
      refs: ActivityRefs(clientId: costing.pwText("clientId"), confidential: true))
    return costing
  }

  /// `setCostingStatus(id, status)`.
  @discardableResult
  public static func setStatus(_ ctx: WriteContext, id: String, status: String, link: PwLink?) throws -> JSONValue {
    guard let costing = ctx.get("staffingCostings", id) else { throw pwFail("Costing not found") }
    try assertMayEdit(link)
    if !statuses.contains(status) { throw pwFail("Costing not found") }
    if costing.pwStr("status") == status { return costing }
    let next = costing.pwMerging(["status": .string(status), "updatedAt": .string(ctx.stamp)])
    ctx.put("staffingCostings", next)
    let text =
      status == "won"
      ? "Manpower costing {name} marked as won"
      : status == "lost" ? "Manpower costing {name} marked as lost" : "Manpower costing {name} updated"
    PwLog.add(
      ctx, "costing", id, "status", text, vars: ["name": .text(costing.pwStr("name"))],
      refs: ActivityRefs(clientId: costing.pwText("clientId"), confidential: true))
    return next
  }

  /// `deleteCosting(id)`: a quote made from it stays.
  public static func delete(_ ctx: WriteContext, id: String, link: PwLink?) throws {
    guard let costing = ctx.get("staffingCostings", id) else { return }
    try assertMayEdit(link)
    ctx.delete("staffingCostings", id)
    PwLog.add(
      ctx, "costing", id, "deleted", "Manpower costing {name} deleted", vars: ["name": .text(costing.pwStr("name"))],
      refs: ActivityRefs(clientId: costing.pwText("clientId"), confidential: true))
  }
}
