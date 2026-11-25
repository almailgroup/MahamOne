import Foundation
import Testing

@testable import MahamKit

/// Ports of src/cloud/company-patch.test.ts, and the numbering cases of sync.test.ts.
@Suite("Sync: the company record by field")
struct SyncCompanyPatchTests {
  static let base: JSONValue = [
    "id": "co-1",
    "name": "Al Mail Trading",
    "phone": "",
    "address": ["line1": "Block 4", "city": "Salmiya", "country": "KW"],
    "accounting": ["template": "kw", "lockDate": nil],
    "holidays": [["date": "2026-02-25"]],
    "numbering": ["invoice": rule(5), "payment": rule(3)],
  ]
  var base: JSONValue { Self.base }

  func with(_ value: JSONValue, _ changes: [String: JSONValue]) -> JSONValue {
    var copy = value
    for (key, field) in changes { copy.set(key, field) }
    return copy
  }

  func numbering(_ rules: [String: JSONValue]) -> JSONValue {
    var all = base["numbering"]?.object ?? [:]
    for (key, value) in rules { all[key] = value }
    return .object(all)
  }

  /// Ops in a fixed order (the web visits keys in insertion order; ops never overlap, so order changes nothing).
  func sorted(_ ops: [CompanyOp]) -> [CompanyOp] { ops.sorted { $0.path.joined(separator: ".") < $1.path.joined(separator: ".") } }

  @Test("are the leaves that changed; a counter goes with its period")
  func leaves() {
    let local = with(
      base,
      [
        "address": with(base["address"] ?? nil, ["city": "Hawalli"]),
        "accounting": with(base["accounting"] ?? nil, ["lockDate": "2026-09-30"]),
        "holidays": [["date": "2026-02-26"]],
        "numbering": numbering(["invoice": rule(6)]),
      ])
    #expect(
      sorted(CompanyPatch.companyOps(base: base, local: local))
        == sorted([
          CompanyOp(path: ["address", "city"], value: "Hawalli", base: "Salmiya"),
          CompanyOp(path: ["accounting", "lockDate"], value: "2026-09-30", base: .null),
          CompanyOp(path: ["holidays"], value: [["date": "2026-02-26"]], base: [["date": "2026-02-25"]]),
          CompanyOp(path: ["numbering", "invoice", "next"], value: 6, base: 5),
          CompanyOp(path: ["numbering", "invoice", "period"], value: "2026", base: "2026"),
        ]))
    #expect(CompanyPatch.companyOps(base: base, local: base).isEmpty)
    #expect(
      CompanyPatch.companyOps(base: base, local: base.removing("phone"))
        == [CompanyOp(path: ["phone"], value: nil, base: "")])
    #expect(
      CompanyPatch.companyOps(base: base, local: base.removing("phone"))[0].json
        == ["path": ["phone"], "remove": true, "base": ""])
  }

  @Test("tell numbering a document from changing settings")
  func counters() {
    let counted = with(base, ["numbering": numbering(["invoice": rule(6)])])
    #expect(CompanyPatch.onlyCounters(CompanyPatch.companyOps(base: base, local: counted)))
    let renamed = with(counted, ["numbering": numbering(["invoice": rule(6, "2026", pattern: "F-{counter}")])])
    #expect(!CompanyPatch.onlyCounters(CompanyPatch.companyOps(base: base, local: renamed)))
    #expect(!CompanyPatch.onlyCounters([]))
  }

  @Test("are laid over a newer copy: others’ fields stay, counters never go back, conflicts are named")
  func rebase() {
    let local = with(base, ["phone": "+965 3333 0000", "numbering": numbering(["invoice": rule(6)])])
    let newer = with(
      base,
      [
        "phone": "+965 2222 0000",
        "accounting": with(base["accounting"] ?? nil, ["lockDate": "2026-09-30"]),
        "numbering": numbering(["invoice": rule(9)]),
      ])
    let (data, conflicts) = CompanyPatch.rebaseCompany(current: newer, ops: CompanyPatch.companyOps(base: base, local: local))
    #expect(data["phone"] == "+965 3333 0000")
    #expect(data["accounting"]?["lockDate"] == "2026-09-30")
    #expect(data["numbering"]?["invoice"]?["next"] == 9)
    #expect(data["numbering"]?["invoice"]?["period"] == "2026")
    #expect(data["numbering"]?["payment"]?["next"] == 3)
    #expect(conflicts == [["phone"]])
    // A counter of last year never moves a counter of this year.
    let lastYear = with(base, ["numbering": numbering(["invoice": rule(41, "2025")])])
    let thisYear = with(base, ["numbering": numbering(["invoice": rule(2, "2026")])])
    let merged = CompanyPatch.rebaseCompany(
      current: thisYear,
      ops: CompanyPatch.companyOps(base: with(lastYear, ["numbering": numbering(["invoice": rule(40, "2025")])]), local: lastYear))
    #expect(merged.data["numbering"]?["invoice"]?["next"] == 2)
    #expect(merged.data["numbering"]?["invoice"]?["period"] == "2026")
  }

  @Test("carry a new company type alone, beside documents numbered elsewhere")
  func newCompanyType() {
    let security: JSONValue = ["id": "security", "name": "Security services", "nameAr": "الخدمات الأمنية"]
    let typed = with(base, ["companyType": security])
    let ops = CompanyPatch.companyOps(base: base, local: typed)
    #expect(ops == [CompanyOp(path: ["companyType"], value: security)])
    #expect(ops[0].json == ["path": ["companyType"], "value": security])
    #expect(!CompanyPatch.onlyCounters(ops))
    // Another device numbered an invoice meanwhile: both stay, and nothing clashes.
    let numbered = with(base, ["numbering": numbering(["invoice": rule(9)])])
    let (data, conflicts) = CompanyPatch.rebaseCompany(current: numbered, ops: ops)
    #expect(data["companyType"] == security)
    #expect(data["numbering"]?["invoice"]?["next"] == 9)
    #expect(conflicts.isEmpty)
    // Another type replaces it as a whole; none removes it.
    let guarding: JSONValue = ["id": "type-guarding", "name": "Guarding"]
    let changed = CompanyPatch.rebaseCompany(
      current: typed, ops: CompanyPatch.companyOps(base: typed, local: with(base, ["companyType": guarding])))
    #expect(changed.data["companyType"] == guarding)
    #expect(CompanyPatch.companyOps(base: typed, local: base) == [CompanyOp(path: ["companyType"], value: nil, base: security)])
    // Staff only number documents: a type change is not theirs to make.
    #expect(!Roles.staffCompanyChangeOk(base, typed))
    #expect(!Roles.staffCompanyChangeOk(typed, numbered))
    #expect(Roles.staffCompanyChangeOk(typed, with(typed, ["numbering": numbered["numbering"] ?? nil])))
  }

  @Test("carry a company type as a whole, so two devices’ types never mix")
  func wholeCompanyType() {
    let guarding: JSONValue = ["id": "x", "name": "Guarding"]
    let before = with(base, ["companyType": guarding])
    let events: JSONValue = ["id": "z", "name": "Events", "nameAr": "فعاليات"]
    let patrol: JSONValue = ["id": "y", "name": "Patrol"]
    let ops = CompanyPatch.companyOps(base: before, local: with(before, ["companyType": patrol]))
    #expect(ops == [CompanyOp(path: ["companyType"], value: patrol, base: guarding)])
    // Another device saved Events meanwhile: this device's type replaces it, names and all.
    let (data, conflicts) = CompanyPatch.rebaseCompany(current: with(before, ["companyType": events]), ops: ops)
    #expect(data["companyType"] == patrol)
    #expect(conflicts == [["companyType"]])
  }

  @Test("make the objects on the way and remove fields")
  func paths() {
    let (data, _) = CompanyPatch.rebaseCompany(
      current: ["id": "co-1"],
      ops: [
        CompanyOp(path: ["bankAccount", "iban"], value: "KW00TEST0000000000000000000000"),
        CompanyOp(path: ["website"], value: nil),
      ])
    #expect(data == ["id": "co-1", "bankAccount": ["iban": "KW00TEST0000000000000000000000"]])
  }

  @Test("document numbers never go back (mergeNumbering)")
  func neverBack() {
    let a: JSONValue = ["invoice": rule(10, "2026"), "quote": rule(3, "2026")]
    let b: JSONValue = ["invoice": rule(4, "2026"), "quote": rule(8, "2026"), "letter": rule(2, "2026")]
    let merged = CompanyPatch.mergeNumbering(a, b)
    #expect(merged?["invoice"]?["next"] == 10)
    #expect(merged?["quote"]?["next"] == 8)
    #expect(merged?["letter"]?["next"] == 2)
    // A later period wins, whatever its counter; an older one keeps the newer period.
    #expect(CompanyPatch.mergeNumberingRule(rule(40, "2025"), rule(2, "2026"))?["next"] == 2)
    let older = CompanyPatch.mergeNumberingRule(rule(2, "2026"), rule(40, "2025", pattern: "F-{counter}"))
    #expect(older?["next"] == 2)
    #expect(older?["period"] == "2026")
    #expect(older?["pattern"] == "F-{counter}")
    // A change of reset takes the rule as sent.
    let monthly = rule(1, "2026-11").setting("reset", "monthly")
    #expect(CompanyPatch.mergeNumberingRule(rule(9), monthly) == monthly)
    // A rule missing on one side is kept from the other.
    #expect(CompanyPatch.mergeNumbering(["invoice": rule(3)], [:])?["invoice"]?["next"] == 3)
    #expect(CompanyPatch.mergeNumbering(nil, ["invoice": rule(3)]) == ["invoice": rule(3)])
  }
}
