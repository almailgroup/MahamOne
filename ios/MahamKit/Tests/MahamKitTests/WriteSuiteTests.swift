import Foundation
import Testing

@testable import MahamKit

/// The suite's write ports (Write/Suite) against the web's own outputs
/// (Fixtures/writes-suite.json, from ios/scripts/web-fixtures/writes-suite.gen.ts):
/// each scenario runs the port its `input.fn` names on the same records,
/// ids and clock, and must leave every table as the web did, or refuse with
/// the web's words and change nothing.
@Suite("Suite writes, as the web saves them")
struct WriteSuiteTests {
  @Test("every scenario of the web")
  func webScenarios() throws {
    let scenarios = try WriteParity.scenarios("suite")
    #expect(scenarios.count > 80)
    for scenario in scenarios {
      let context = scenario.context()
      var thrown: String?
      do {
        try SuiteCalls.run(context, scenario.input)
      } catch let failure as WriteFailure {
        thrown = failure.description
      } catch {
        thrown = "\(error)"
      }
      #expect(thrown == scenario.error, "\(scenario.name)")
      // A refused action writes nothing (the app keeps none of its changes).
      let changes = thrown == nil ? context.changes : []
      WriteParity.assertMatches(scenario.applying(changes), scenario.after, scenario: scenario.name)
    }
  }

  @Test("the settings pages change the company as the web's do")
  func companyChanges() throws {
    let scenarios = try WriteParity.scenarios("suite").filter { $0.input["fn"] == .string("saveCompany") }
    #expect(scenarios.count >= 10)
    for scenario in scenarios {
      guard let change = scenario.input["change"], let from = change["from"], let saved = scenario.input["company"]
      else {
        Issue.record("\(scenario.name): no change")
        continue
      }
      let mine = SuiteCalls.company(change, from: from)
      #expect(mine?.sameData(saved) == true, "\(scenario.name): \(mine.map { WriteParity.difference($0, saved) } ?? "nothing")")
    }
  }

  @Test("tidies text and compares names as the web does")
  func text() {
    #expect(SwText.tidy("  Hi \t ace\n van ") == "Hi ace van")
    #expect(SwText.normalizeSearch("أحمد") == SwText.normalizeSearch("احمد"))
    #expect(SwText.normalizeSearch("Café  ٣٤") == "cafe 34")
    #expect(SwText.plateKey(" 12 / 34-567 ") == SwText.plateKey("12/34567"))
    #expect(SwReminders.parse("60, 30، 7 7") == [60, 30, 7])
    #expect(SwReminders.parse("  ") == nil)
    #expect(SwReminders.normalize(.array([])) == [60, 30, 7])
  }
}

/// The ports the scenarios name, called with their inputs.
enum SuiteCalls {
  static func text(_ input: JSONValue, _ key: String) -> String { input[key]?.string ?? "" }

  static func cloud(_ input: JSONValue) -> SwCloud? {
    input["cloud"]?.array.map { SwCloud(features: $0.compactMap(\.string)) }
  }

  static func file(_ value: JSONValue?) -> SwFile? {
    guard let value, !value.isNull else { return nil }
    return SwFile(name: text(value, "name"), type: text(value, "type"), dataUrl: text(value, "dataUrl"))
  }

  static func tag(_ value: JSONValue?) -> SwCopyTag? {
    guard let value, !value.isNull else { return nil }
    return SwCopyTag(docKey: text(value, "docKey"), validUntil: value["validUntil"]?.string)
  }

  static func renewInput(_ input: JSONValue) -> SwRenewInput {
    var fee: SwRenewalFee?
    if let given = input["fee"], !given.isNull {
      fee = SwRenewalFee(
        amount: given["amount"]?.double ?? 0, accountId: given["accountId"]?.string,
        paidFromAccountId: given["paidFromAccountId"]?.string, reference: given["reference"]?.string)
    }
    return SwRenewInput(
      key: text(input, "key"), newExpiry: text(input, "newExpiry"), renewedOn: text(input, "renewedOn"),
      number: input["number"]?.string, note: input["note"]?.string, fee: fee, copy: Self.file(input["copy"]))
  }

  static func run(_ ctx: WriteContext, _ input: JSONValue) throws {
    let cloud = Self.cloud(input)
    let id = text(input, "id")
    let on = input["on"]?.bool ?? false
    let archived = input["archived"]?.bool ?? false
    switch text(input, "fn") {
    case "saveDocument": try SwCompliance.saveDocument(ctx, input["doc"] ?? .null, cloud: cloud)
    case "makeConfidential":
      let removed = (input["removedFiles"]?.array ?? []).compactMap(\.string)
      try SwCompliance.makeConfidential(ctx, input["doc"] ?? .null, cloud: cloud, removedFiles: removed)
    case "setArchived": SwCompliance.setArchived(ctx, id: id, archived: archived)
    case "deleteDocument": try SwCompliance.deleteDocument(ctx, id: id)
    case "markDone":
      SwCompliance.markDone(
        ctx, key: text(input, "key"), doneOn: input["doneOn"]?.string, note: input["note"]?.string,
        label: input["label"]?.string)
    case "clearMark": SwCompliance.clearMark(ctx, key: text(input, "key"), label: input["label"]?.string)
    case "setRegisterExtras": SwCompliance.setRegisterExtras(ctx, on: on)
    case "setFileFinder": SwCompliance.setFileFinder(ctx, on: on)
    case "savePurposes": try SwCompliance.savePurposes(ctx, input["list"]?.array ?? [])
    case "addPurpose": try SwCompliance.addPurpose(ctx, name: text(input, "name"), nameAr: input["nameAr"]?.string)
    case "setPurposeArchived": try SwCompliance.setPurposeArchived(ctx, id: id, archived: archived)
    case "renew": try SwRenewals.renew(ctx, renewInput(input))
    case "markNewCopy": try SwRenewals.markNewCopy(ctx, fileId: text(input, "fileId"), tag: Self.tag(input["tag"]))
    case "addNewCopy":
      guard let file = Self.file(input["file"]), let tag = Self.tag(input["tag"]) else { return }
      SwRenewals.addNewCopy(ctx, ownerId: text(input, "ownerId"), file: file, tag: tag)
    case "saveVehicle": try SwVehicles.save(ctx, input["vehicle"] ?? .null, cloud: cloud)
    case "setVehicleArchived": try SwVehicles.setArchived(ctx, id: id, archived: archived, cloud: cloud)
    case "deleteVehicle": try SwVehicles.delete(ctx, id: id, cloud: cloud)
    case "linkVehiclePapers": try SwVehicles.linkPapers(ctx, cloud: cloud)
    case "saveCompany": SwCompany.save(ctx, input["company"] ?? .null)
    case "saveTaxRate": SwCompany.saveTaxRate(ctx, input["rate"] ?? .null)
    case "addTaxRate": SwCompany.addTaxRate(ctx, name: text(input, "name"))
    case "deleteTaxRate": SwCompany.deleteTaxRate(ctx, id: id)
    case "addAttachment":
      guard let file = Self.file(input["file"]) else { return }
      SwRenewals.addAttachment(ctx, ownerId: text(input, "ownerId"), file: file)
    case "removeAttachment": SwRenewals.removeAttachment(ctx, id: id)
    default: Issue.record("No port for \(text(input, "fn"))")
    }
  }

  /// A settings page's change, made by the port from the company the web made it from.
  static func company(_ change: JSONValue, from: JSONValue) -> JSONValue? {
    let on = change["on"]?.bool ?? false
    let type = text(change, "type")
    switch text(change, "kind") {
    case "taxes": return SwCompany.withTaxes(from, enabled: on)
    case "appLayout": return SwCompany.withAppLayout(from, split: on)
    case "ai": return SwCompany.withAiSwitch(from, on: on)
    case "template": return SwCompany.withTemplate(from, type: type, templateId: text(change, "templateId"))
    case "sameAsInvoices": return SwCompany.withSameAsInvoices(from, type: type, same: change["same"]?.bool ?? false)
    case "profile": return SwCompany.withTidyProfile(from, known: SwCompany.typeOptions([]))
    default: return nil
    }
  }
}
