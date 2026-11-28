import Foundation
import Testing

@testable import MahamKit

/// The inventory writes (Write/Inventory) against the web's own outputs
/// (Fixtures/writes-inventory.json, written by
/// ios/scripts/web-fixtures/writes-inventory.gen.ts): warehouses, items and
/// their codes, stock entries, landed costs, items issued to employees, the
/// stock of documents and its costing at the weighted average. Each
/// scenario names the web function it ran (`input.action`) and its
/// arguments.
@Suite("Writes: inventory, as the web saves it")
struct WriteInventoryTests {
  @Test("every inventory write leaves the records the web leaves, or is refused with the web's words")
  func scenarios() throws {
    let scenarios = try WriteParity.scenarios("inventory")
    #expect(scenarios.count > 100)
    for scenario in scenarios {
      let context = scenario.context()
      do {
        try IwPort.run(scenario.input, context)
        if let error = scenario.error {
          Issue.record("\(scenario.name): the web refused it (\(error)); the port saved it")
          continue
        }
        WriteParity.assertMatches(scenario.applying(context.changes), scenario.after, scenario: scenario.name)
      } catch let failure as WriteFailure {
        if scenario.error == nil {
          Issue.record("\(scenario.name): the web saved it; the port refused it (\(failure.description))")
        } else {
          #expect(failure.description == scenario.error, "\(scenario.name)")
        }
      } catch {
        Issue.record("\(scenario.name): \(error)")
      }
    }
  }

  @Test("decimal.js-light cuts to 40 digits; only toDecimalPlaces rounds")
  func decimals() {
    let third = IwDecimal(1001).dividedBy(IwDecimal(3))
    #expect(third.description == "333.6666666666666666666666666666666666666")
    // 1.5 × 1001 / 3 is half a unit exactly, but the cut quotient is just below it.
    #expect(IwCosting.whole(IwDecimal(1.5).times(third)) == 500)
    #expect(IwCosting.whole(IwDecimal(1501.5).dividedBy(IwDecimal(3))) == 501)
    #expect(IwDecimal(5).dividedBy(IwDecimal(7)).times(IwDecimal(3.5)).toDecimalPlaces(0).toNumber() == 2)
    #expect(IwDecimal(-2.5).toDecimalPlaces(0).toNumber() == -3)
    #expect(IwDecimal(0.0005).toDecimalPlaces(3).toNumber() == 0.001)
    #expect(IwDecimal(0.00049).toDecimalPlaces(3).toNumber() == 0)
    #expect(IwDecimal(0.1).plus(IwDecimal(0.2)).toNumber() == 0.3)
    #expect(IwDecimal(12.5).minus(IwDecimal(12.5)).isZero)
    #expect(IwDecimal(9.995).toDecimalPlaces(2).toNumber() == 10)
    #expect(IwMoney.toMinor(1.0005, 3) == 1001)
    #expect(IwMoney.fromMinor(-6875, 3) == -6.875)
    #expect(IwMoney.jsRound(-2.5) == -2)
    #expect(IwMoney.jsRound(2.5) == 3)
    #expect(IwDecimal(1).dividedBy(IwDecimal("12345678901234567890123")).description.hasPrefix("0.0000000000000000000000810000007"))
  }

  @Test("numbers of stock records carry on from the highest")
  func numbers() {
    #expect(InventoryWrites.nextNumber("ADJ", []) == "ADJ-0001")
    #expect(InventoryWrites.nextNumber("ADJ", ["ADJ-0007", "ADJ-x", "OPN-0099", "ADJ-12345"]) == "ADJ-12346")
    #expect(InventoryWrites.nextNumber("LC", ["LC-0001", "LC-0002"]) == "LC-0003")
  }
}

/// Runs a scenario's web function on the port.
enum IwPort {
  static func run(_ input: JSONValue, _ ctx: WriteContext) throws {
    switch input["action"]?.string ?? "" {
    case "syncDocumentStock":
      try InventoryWrites.syncDocumentStock(ctx, documentId: input["documentId"]?.string ?? "")
    case "recost":
      try InventoryWrites.recost(ctx, productIds: (input["productIds"]?.array ?? []).compactMap(\.string))
    case "rebuildStock":
      try InventoryWrites.rebuildStock(ctx)
    case "saveWarehouse":
      try InventoryWrites.saveWarehouse(ctx, input["warehouse"] ?? .null)
    case "ensureDefaultWarehouse":
      InventoryWrites.ensureDefaultWarehouse(ctx)
    case "saveItem":
      let product = input["product"] ?? .null
      let start = opening(input["opening"])
      // What the web asked the cloud's counter for, when it asked.
      let request = InventoryWrites.itemCounterRequest(ctx, product, opening: start)
      if let asked = input["request"], asked.object != nil {
        #expect(request?.kind == asked["kind"]?.string && request?.date == asked["date"]?.string)
        #expect(request?.min == asked["min"]?.int)
      }
      var reserved: ReservedCounter?
      if let given = input["reserved"], given.object != nil {
        reserved = ReservedCounter(counter: given["counter"]?.int ?? 0, period: given["period"]?.string ?? "")
      }
      try InventoryWrites.saveItem(ctx, product, opening: start, reserved: reserved)
    case "deleteItem":
      try InventoryWrites.deleteItem(ctx, id: input["id"]?.string ?? "")
    case "assignItemCodes":
      try InventoryWrites.assignItemCodes(ctx)
    case "recordStockEntry":
      try InventoryWrites.recordStockEntry(ctx, entry(input["entry"] ?? .null))
    case "voidStockEntry":
      try InventoryWrites.voidStockEntry(ctx, id: input["id"]?.string ?? "")
    case "saveLandedCost":
      try InventoryWrites.saveLandedCost(ctx, landedCost(input["cost"] ?? .null))
    case "voidLandedCost":
      try InventoryWrites.voidLandedCost(ctx, id: input["id"]?.string ?? "")
    case "issueStock":
      let issuer = input["issuer"] ?? .null
      try IwStockIssues.issueStock(
        ctx, issue(input["issue"] ?? .null),
        issuer: IwStockIssues.Issuer(userId: issuer["userId"]?.string, name: issuer["name"]?.string ?? ""),
        link: link(input["link"]))
    case "voidStockIssue":
      try IwStockIssues.voidStockIssue(ctx, id: input["id"]?.string ?? "", link: link(input["link"]))
    case "applyStockIssueRequest":
      try IwStockIssues.applyStockIssueRequest(ctx, input["request"] ?? .null)
    case let other:
      Issue.record("no port for \(other)")
    }
  }

  static func opening(_ value: JSONValue?) -> InventoryWrites.OpeningStock? {
    guard let value, value.object != nil else { return nil }
    return InventoryWrites.OpeningStock(
      warehouseId: value["warehouseId"]?.string ?? "", quantity: value["quantity"]?.double ?? 0,
      unitCost: value["unitCost"]?.double ?? 0, date: value["date"]?.string ?? "")
  }

  static func entry(_ value: JSONValue) -> InventoryWrites.StockEntryInput {
    InventoryWrites.StockEntryInput(
      kind: value["kind"]?.string ?? "", date: value["date"]?.string ?? "",
      warehouseId: value["warehouseId"]?.string ?? "", toWarehouseId: value["toWarehouseId"]?.string,
      reason: value["reason"]?.string, reference: value["reference"]?.string ?? "",
      notes: value["notes"]?.string ?? "",
      lines: (value["lines"]?.array ?? []).map { line in
        InventoryWrites.StockEntryInput.Line(
          productId: line["productId"]?.string ?? "", quantity: line["quantity"]?.double ?? 0,
          unitCost: line["unitCost"]?.double)
      })
  }

  static func landedCost(_ value: JSONValue) -> InventoryWrites.LandedCostInput {
    InventoryWrites.LandedCostInput(
      billId: value["billId"]?.string ?? "", sourceLineIds: (value["sourceLineIds"]?.array ?? []).compactMap(\.string),
      targetBillId: value["targetBillId"]?.string ?? "",
      targetLineIds: (value["targetLineIds"]?.array ?? []).compactMap(\.string),
      method: value["method"]?.string ?? "value", notes: value["notes"]?.string ?? "")
  }

  static func issue(_ value: JSONValue) -> IwStockIssues.Input {
    IwStockIssues.Input(
      date: value["date"]?.string ?? "", warehouseId: value["warehouseId"]?.string ?? "",
      recipient: value["recipient"] ?? .null,
      lines: (value["lines"]?.array ?? []).map { line in
        IwStockIssues.Input.Line(productId: line["productId"]?.string ?? "", quantity: line["quantity"]?.double ?? 0)
      },
      notes: value["notes"]?.string ?? "")
  }

  static func link(_ value: JSONValue?) -> IwStockIssues.Link? {
    guard let value, value.object != nil else { return nil }
    return IwStockIssues.Link(
      role: MemberRole(rawValue: value["role"]?.string ?? "") ?? .viewer, userId: value["userId"]?.string ?? "",
      approver: value["approver"]?.bool ?? false, features: value["features"]?.array?.compactMap(\.string))
  }
}
