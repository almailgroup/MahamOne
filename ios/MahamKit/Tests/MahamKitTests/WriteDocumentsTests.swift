import Foundation
import Testing

@testable import MahamKit

/// The document ports (MahamKit/Write/Documents) against the web's own
/// outputs (Fixtures/writes-documents.json, written by
/// ios/scripts/web-fixtures/writes-documents.gen.ts): every scenario's port
/// must leave every table as the web did, or refuse with the web's words and
/// leave nothing changed.
@Suite("Documents: saved as the web saves them")
struct WriteDocumentsTests {
  @Test func everyScenarioMatchesTheWeb() throws {
    let scenarios = try WriteParity.scenarios("documents")
    #expect(!scenarios.isEmpty)
    for scenario in scenarios {
      let context = scenario.context()
      do {
        try DocumentScenario.run(scenario.input, context)
        if let error = scenario.error {
          Issue.record("\(scenario.name): the web refused (\(error)); the port didn't")
          continue
        }
        WriteParity.assertMatches(scenario.applying(context.changes), scenario.after, scenario: scenario.name)
      } catch {
        guard let expected = scenario.error else {
          Issue.record("\(scenario.name): the port refused (\(DocumentScenario.message(error))); the web didn't")
          continue
        }
        #expect(DocumentScenario.message(error) == expected, "\(scenario.name)")
        // A refusal leaves everything as it was, on the web too.
        WriteParity.assertMatches(scenario.before, scenario.after, scenario: scenario.name + " (refused)")
      }
    }
  }

  /// What the web asked the cloud's counter for, the port asks too.
  @Test func cloudNumbersAreAskedForAsTheWebAsks() throws {
    var asked = 0
    for scenario in try WriteParity.scenarios("documents") {
      guard let request = scenario.input["request"], request.object != nil else { continue }
      asked += 1
      let context = scenario.context()
      let mine = DocumentScenario.counterRequest(scenario.input, context)
      #expect(mine?.kind == request["kind"]?.string, "\(scenario.name)")
      #expect(mine?.date == request["date"]?.string, "\(scenario.name)")
      #expect(mine?.min == request["min"]?.int, "\(scenario.name)")
    }
    #expect(asked > 0)
  }

  @Test func totalsRoundAsTheWebDoes() {
    // 3 × 1.2345 = 3.7035, KWD to 3 places: 3.704 (half away from zero).
    let line: JSONValue = ["kind": "item", "quantity": 3, "unitPrice": 1.2345, "discount": 0, "discountType": "percent"]
    let result = DcCalc.calculate(
      items: [line], discount: 0, discountType: "percent", taxes: [], charges: [], pricesIncludeTax: false,
      precision: 3)
    #expect(result.total == 3.704)
    // 5% retention of 1,234.567 is 61.728.
    #expect(DcCalc.retentionOf(1234.567, 5, 3) == 61.728)
  }
}

/// Runs a scenario's action (`input.action`) with the port.
enum DocumentScenario {
  static func message(_ error: Error) -> String {
    if let failure = error as? WriteFailure { return failure.description }
    if let approval = error as? DcApprovalRequired { return approval.description }
    return String(describing: error)
  }

  static func link(_ input: JSONValue) -> DcLink? {
    guard let link = input["link"], link.object != nil else { return nil }
    return DcLink(
      userId: link["userId"]?.string ?? "", role: MemberRole(rawValue: link["role"]?.string ?? "") ?? .owner,
      approver: link["approver"]?.bool ?? false)
  }

  static func reserved(_ input: JSONValue) -> ReservedCounter? {
    guard let reserved = input["reserved"], let counter = reserved["counter"]?.int else { return nil }
    return ReservedCounter(counter: counter, period: reserved["period"]?.string ?? "")
  }

  static func patch(_ value: JSONValue?) -> DcPatch {
    (value?.object ?? [:]).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
  }

  /// The draft the web made for a new document, with the scenario's changes.
  static func draft(_ input: JSONValue, _ ctx: WriteContext) -> JSONValue {
    let company = ctx.get("companies", ctx.companyId) ?? .null
    let client = input["clientId"]?.string.flatMap { ctx.get("clients", $0) }
    let fresh = DcDocuments.draftDocument(ctx, company: company, type: input["type"]?.string ?? "", client: client)
    return DcJS.merge(fresh, object: input["patch"])
  }

  static func run(_ input: JSONValue, _ ctx: WriteContext) throws {
    let id = input["id"]?.string ?? ""
    let cloud = DocumentScenario.link(input)
    let counter = DocumentScenario.reserved(input)
    switch input["action"]?.string ?? "" {
    case "draftAndSave":
      try DcDocuments.saveDocument(ctx, draft(input, ctx), reserved: counter, link: cloud)
    case "saveDocument":
      try DcDocuments.saveDocument(ctx, input["document"] ?? .null, reserved: counter, link: cloud)
    case "markSent":
      try DcDocuments.markSent(ctx, id: id, reserved: counter, link: cloud)
    case "setDocumentStatus":
      try DcDocuments.setDocumentStatus(
        ctx, id: id, status: input["status"]?.string ?? "", patch: patch(input["patch"]),
        freePaid: input["freePaid"]?.bool ?? false, reserved: counter, link: cloud)
    case "deleteDocument":
      try DcDocuments.deleteDocument(ctx, id: id, link: cloud)
    case "duplicateDocument":
      try DcDocuments.duplicateDocument(
        ctx, id: id, asType: input["asType"]?.string, overrides: patch(input["overrides"]), reserved: counter,
        link: cloud)
    case "reissueDocument":
      try DcDocuments.reissueDocument(ctx, id: id, reserved: counter, link: cloud)
    case "convertDocument":
      try DcDocuments.convertDocument(ctx, sourceId: id, to: input["to"]?.string ?? "", reserved: counter, link: cloud)
    case "createFromOrder":
      let quantities = input["quantities"]?.object.map { $0.compactMapValues(\.double) }
      try DcOrders.createFromOrder(
        ctx, sourceId: id, target: input["target"]?.string ?? "", quantities: quantities, reserved: counter,
        link: cloud)
    case "markDelivered":
      try DcOrders.markDelivered(
        ctx, id: id, date: input["date"]?.string ?? "", receiverName: input["receiverName"]?.string ?? "",
        receiverCivilId: input["receiverCivilId"]?.string, link: cloud)
    case "saveClient":
      try DcRecords.saveClient(ctx, input["client"] ?? .null)
    case "deleteClient":
      try DcRecords.deleteClient(ctx, id: id)
    case "setCreditHold":
      DcRecords.setCreditHold(ctx, clientId: id, hold: input["hold"]?.bool ?? false)
    case "saveProduct":
      DcRecords.saveProduct(ctx, input["product"] ?? .null)
    case "requestApproval":
      try DcApprovals.requestApproval(
        ctx, kind: input["kind"]?.string ?? "", subject: input["subject"] ?? .null, proposal: input["proposal"],
        reason: input["reason"]?.string ?? "", byName: input["byName"]?.string, link: cloud)
    default:
      Issue.record("Unknown action \(input["action"]?.string ?? "")")
    }
  }

  /// The counter the port asks the cloud for before the scenario's action.
  static func counterRequest(_ input: JSONValue, _ ctx: WriteContext) -> DcCounterRequest? {
    let id = input["id"]?.string ?? ""
    switch input["action"]?.string ?? "" {
    case "draftAndSave":
      return DcDocuments.counterRequest(ctx, draft(input, ctx))
    case "saveDocument":
      return DcDocuments.counterRequest(ctx, input["document"] ?? .null)
    case "markSent":
      let type = ctx.get("documents", id)?["type"]?.string ?? ""
      return DcDocuments.issueCounterRequest(ctx, id: id, status: DcRules.issuedStatus(type) ?? "")
    case "convertDocument":
      return DcDocuments.newDraftCounterRequest(ctx, companyId: ctx.companyId, type: input["to"]?.string ?? "")
    default:
      return nil
    }
  }
}
