import Foundation
import Testing

@testable import MahamKit

/// The People and payroll write ports (MahamKit/Write/People) against the
/// web's own outputs (Fixtures/writes-people.json, written by
/// ios/scripts/web-fixtures/writes-people.gen.ts): every scenario starts from
/// the web's records with the web's ids and clock, runs the port, and must
/// leave every table as the web did, or refuse with the web's words.
@Suite("People and payroll writes match the web")
struct WritePeopleTests {
  /// The sync's own bookkeeping, which no port writes.
  static let bookkeeping: Set<String> = ["meta", "syncState", "outbox", "syncRevs", "fileQueue"]

  static func records(_ tables: [String: [JSONValue]]) -> [String: [JSONValue]] {
    tables.filter { !bookkeeping.contains($0.key) }
  }

  @Test("every scenario of the web's fixtures")
  func scenarios() throws {
    let scenarios = try WriteParity.scenarios("people")
    #expect(scenarios.count > 100)
    for scenario in scenarios {
      let ctx = scenario.context()
      // The person's link as the action started (`db.syncState`, which the fixtures don't dump).
      let link = PwLink(row: scenario.input["link"])
      var failure: String?
      do {
        try Self.run(scenario.input, ctx, link: link)
      } catch let refused as WriteFailure {
        failure = refused.description
      }
      if let error = scenario.error {
        #expect(failure == error, "\(scenario.name): the web refused with “\(error)”")
        continue
      }
      #expect(failure == nil, "\(scenario.name): refused with “\(failure ?? "")”")
      WriteParity.assertMatches(
        Self.records(scenario.applying(ctx.changes)), Self.records(scenario.after), scenario: scenario.name)
    }
  }

  @Test("a refused action writes nothing the app would keep")
  func refusals() throws {
    // OneData.write throws before the engine sees any change, as Dexie rolls a transaction back.
    for scenario in try WriteParity.scenarios("people") where scenario.error != nil {
      #expect(
        Self.records(scenario.before).mapValues(\.count) == Self.records(scenario.after).mapValues(\.count),
        "\(scenario.name)")
    }
  }

  @Test("pay lines worked out as the web's golden figures")
  func payLines() {
    // KD 3,000 a month insured up to KD 2,750 (11.5% and 10.5%).
    let rules: JSONValue = [
      "dailyDivisor": 26, "rateBase": "wage", "pifss": ["from": "2026-01-01", "employer": 11.5, "employee": 10.5, "cap": 2750],
      "gcc": [], "minimumWage": 75,
    ]
    let line: JSONValue = [
      "category": "kuwaiti", "nationality": "KW", "monthlyBasic": 2600,
      "allowances": [["id": "a", "name": "Social", "monthly": 400, "amount": 0]], "daysWorked": 30, "daysInMonth": 30,
      "overtime": ["normal": 0, "restDay": 0, "holiday": 0], "absentDays": 0, "unpaidLeaveDays": 0, "reducedPay": [],
      "adjustments": [], "loans": [],
    ]
    let worked = PwPay.calculate(line, rules, 3)
    #expect(worked.pwNum("gross") == 3000)
    #expect(worked.pwNum("pifssEmployee") == 288.75)
    #expect(worked.pwNum("pifssEmployer") == 316.25)
    #expect(worked.pwNum("net") == 2711.25)
    // KD 510 ÷ 26 ÷ 8 × 2 hours × 1.25, for an expatriate who joined on the 16th.
    let joiner: JSONValue = [
      "category": "expat", "nationality": "IN", "monthlyBasic": 450,
      "allowances": [["id": "h", "name": "Housing", "monthly": 60, "amount": 0]], "daysWorked": 15, "daysInMonth": 30,
      "overtime": ["normal": 2, "restDay": 0, "holiday": 0], "absentDays": 0, "unpaidLeaveDays": 0, "reducedPay": [],
      "adjustments": [["id": "u", "type": "deduction", "amount": 5, "note": "Uniform"]], "loans": [],
    ]
    let paid = PwPay.calculate(joiner, rules, 3)
    #expect(paid.pwNum("overtimePay") == 6.13)
    #expect(paid.pwNum("net") == 256.13)
  }

  @Test("the indemnity and years of service as the web works them out")
  func endOfService() {
    #expect(PwPay.serviceYears("2023-10-01", "2026-09-30") == 3)
    // KD 600 a month, 26-day divisor: 75 days come to KD 1,730.769.
    let five = PwPay.eosi(
      payBasis: "monthly", monthlyWage: 600, years: 5, reason: "termination", divisor: 26, precision: 3)
    #expect(five.payable == 1730.769)
    let share = PwPay.eosiShare("resignation", 6)
    #expect(share.numerator == 2 && share.denominator == 3)
  }

  @Test("the settings a form starts from, and the first of next month")
  func settingsStart() {
    #expect(PwSettings.nextMonthStart("2026-11-28") == "2026-12-01")
    #expect(PwSettings.nextMonthStart("2026-12-31") == "2027-01-01")
    // Nothing saved: the web's defaults; what is saved stands over them.
    let none = PwSettings.payroll(saved: nil, companyId: "c1", stamp: "2026-11-28T09:00:00.000Z")
    #expect(none.pwNum("dailyDivisor") == 26 && none.pwNum("payDay") == 31 && none.pwStr("rateBase") == "wage")
    #expect(none["salaryFile"]?.pwStr("preset") == "wps")
    let saved = PwSettings.payroll(
      saved: ["id": "c1", "companyId": "c1", "payDay": 25, "provisions": false], companyId: "c1", stamp: "x")
    #expect(saved.pwNum("payDay") == 25 && saved["provisions"] == false && saved.pwNum("minimumWage") == 75)
  }

  // MARK: Running the web's function's port

  static func run(_ input: JSONValue, _ ctx: WriteContext, link: PwLink?) throws {
    let a = input["args"] ?? .object([:])
    let s = { (key: String) in a.pwStr(key) }
    switch input.pwStr("fn") {
    case "saveEmployee":
      try PwEmployees.save(ctx, a["employee"] ?? .null, expectedUpdatedAt: a.pwText("expectedUpdatedAt"), link: link)
    case "setLeaveOpening":
      try PwEmployees.setLeaveOpening(ctx, employeeId: s("employeeId"), date: s("date"), days: a.pwNum("days"))
    case "setEmployeePhoto":
      try PwEmployees.setPhoto(ctx, employeeId: s("employeeId"), name: s("name"), dataUrl: s("dataUrl"))
    case "removeEmployeePhoto":
      PwEmployees.removePhoto(ctx, employeeId: s("employeeId"))
    case "deleteEmployee":
      try PwEmployees.delete(ctx, id: s("id"))
    case "addDepartment":
      try PwSettings.addDepartment(ctx, name: s("name"), nameAr: a.pwText("nameAr"))
    case "addDepartmentsInUse":
      PwSettings.addDepartmentsInUse(ctx)
    case "updateDepartment":
      try PwSettings.updateDepartment(ctx, id: s("id"), name: s("name"), nameAr: a.pwText("nameAr"))
    case "setDepartmentArchived":
      try PwSettings.setDepartmentArchived(ctx, id: s("id"), archived: a.pwFlag("archived"))
    case "mergeDepartment":
      try PwSettings.mergeDepartment(ctx, from: s("from"), into: s("intoId"))
    case "assignDepartment":
      PwSettings.assignDepartment(ctx, employeeIds: a.pwList("employeeIds").compactMap(\.string), name: s("name"))
    case "savePeopleSettings":
      try PwSettings.savePeopleSettings(ctx, a["settings"] ?? .null)
    case "setGroupSearch":
      PwSettings.setGroupSearch(ctx, a.pwFlag("on"))
    case "savePayrollSettings":
      try PwSettings.savePayrollSettings(ctx, a["settings"] ?? .null)
    case "saveLeaveReasonSettings":
      try PwSettings.saveLeaveReasonSettings(ctx, a["changes"] ?? .object([:]))
    case "updateLeaveReasons":
      let reasons = a.pwList("reasons")
      try PwSettings.updateLeaveReasons(ctx) { _ in reasons }
    case "saveLeaveRecord":
      try PwPayroll.saveLeave(ctx, a["record"] ?? .null)
    case "cancelLeaveRecord":
      try PwPayroll.cancelLeave(ctx, id: s("id"))
    case "setLeaveOpeningForEveryone":
      try PwEmployees.setLeaveOpeningForEveryone(ctx, date: s("date"), days: a.pwNum("days"))
    case "setLeaveOpeningsFromSheet":
      let entries = a.pwList("entries").map { (employeeId: $0.pwStr("employeeId"), date: $0.pwStr("date"), days: $0.pwNum("days")) }
      try PwEmployees.setLeaveOpeningsFromSheet(ctx, entries)
    case "saveStaffLoan":
      try PwPayroll.saveLoan(ctx, a["loan"] ?? .null)
    case "cancelStaffLoan":
      try PwPayroll.cancelLoan(ctx, id: s("id"))
    case "createPayRun":
      try PwPayRuns.create(ctx, period: s("period"))
    case "refreshPayRun":
      try PwPayRuns.refresh(ctx, id: s("id"))
    case "updatePayLine":
      try PwPayRuns.updateLine(ctx, runId: s("runId"), lineId: s("lineId"), changes(a["changes"]))
    case "updatePayRun":
      let c = a["changes"] ?? .object([:])
      let account: String?? = c["deductionAccountId"].map { $0.string }
      try PwPayRuns.updateRun(
        ctx, id: s("id"), payDate: c.pwText("payDate"), deductionAccountId: account, notes: c.pwText("notes"))
    case "deletePayRun":
      try PwPayRuns.delete(ctx, id: s("id"))
    case "approvePayRun":
      let approved = try PwPayRuns.approve(ctx, id: s("id"), link: link)
      if let request = approved.requestId { PwApprovals.markApplied(ctx, requestId: request, link: link) }
    case "payPayRun":
      try PwPayRuns.pay(ctx, id: s("id"), date: s("date"), bankAccountId: a.pwText("bankAccountId"))
    case "undoPayRunPayment":
      try PwPayRuns.undoPayment(ctx, id: s("id"))
    case "reopenPayRun":
      try PwPayRuns.reopen(ctx, id: s("id"))
    case "requestPayrollApproval":
      try PwApprovals.request(ctx, runId: s("runId"), note: s("note"), byName: s("byName"), link: link)
    case "postSettlement":
      try PwSettlements.post(ctx, PwSettlements.Form(a["form"] ?? .null))
    case "paySettlement":
      try PwSettlements.pay(ctx, id: s("id"), date: s("date"))
    case "reverseSettlement":
      try PwSettlements.reverse(ctx, id: s("id"))
    case "setLettersOn":
      try PwLetters.setOn(ctx, a.pwFlag("on"), link: link)
    case "saveTemplate":
      try PwLetters.saveTemplate(ctx, a["template"] ?? .null, link: link)
    case "setTemplateArchived":
      try PwLetters.setTemplateArchived(ctx, id: s("id"), archived: a.pwFlag("archived"), link: link)
    case "restoreDefaultWording":
      try PwLetters.restoreDefaultWording(ctx, id: s("id"), link: link)
    case "saveLetterDraft":
      try PwLetters.saveDraft(ctx, a["draft"] ?? .null, link: link)
    case "deleteLetterDraft":
      try PwLetters.deleteDraft(ctx, id: s("id"))
    case "issueLetter":
      try PwLetters.issue(ctx, id: s("id"), on: s("on"), link: link)
    case "voidLetter":
      try PwLetters.voidLetter(ctx, id: s("id"), reason: s("reason"), link: link)
    case "markLettersPrinted":
      PwLetters.markPrinted(ctx, ids: a.pwList("ids").compactMap(\.string))
    case "requestLetterIssue":
      try PwLetters.requestIssue(ctx, id: s("id"), note: s("note"), byName: s("byName"), link: link)
    case "setCostingsOn":
      try PwCosting.setOn(ctx, a.pwFlag("on"), link: link)
    case "saveCostingSettings":
      let i = a["input"] ?? .object([:])
      try PwCosting.saveSettings(
        ctx, overheadPercent: i.pwNum("overheadPercent"), marginPercent: i.pwNum("marginPercent"),
        rates: i["rates"]?.array, link: link)
    case "saveCosting":
      try PwCosting.save(ctx, a["costing"] ?? .null, link: link)
    case "setCostingStatus":
      try PwCosting.setStatus(ctx, id: s("id"), status: s("status"), link: link)
    case "deleteCosting":
      try PwCosting.delete(ctx, id: s("id"), link: link)
    default:
      Issue.record("No port for \(input.pwStr("fn"))")
    }
  }

  static func changes(_ value: JSONValue?) -> PwPayRuns.LineChanges {
    var changes = PwPayRuns.LineChanges()
    guard let value else { return changes }
    if let overtime = value["overtime"] {
      changes.overtime = (overtime.pwNum("normal"), overtime.pwNum("restDay"), overtime.pwNum("holiday"))
    }
    changes.absentDays = value.pwNumber("absentDays")
    changes.adjustments = value["adjustments"]?.array
    changes.loans = value["loans"]?.array
    return changes
  }
}
