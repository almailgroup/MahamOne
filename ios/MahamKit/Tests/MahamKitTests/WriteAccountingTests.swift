import Foundation
import Testing

@testable import MahamKit

/// The accounting writes (Write/Accounting) against the web's own outputs
/// (Fixtures/writes-accounting.json, written by
/// ios/scripts/web-fixtures/writes-accounting.gen.ts): the chart of accounts,
/// manual journals, the year-end close, fixed assets and depreciation, bank
/// statement lines and transfers, and VAT returns. Each scenario names the
/// web function it ran (`input.op`) and its arguments.
@Suite("Writes: accounting, banking and VAT, as the web saves them")
struct WriteAccountingTests {
  @Test("every accounting write leaves the records the web leaves, or is refused with the web's words")
  func scenarios() throws {
    let scenarios = try WriteParity.scenarios("accounting")
    #expect(scenarios.count > 100)
    #expect(scenarios.contains { $0.input["language"]?.string == "ar" })
    for scenario in scenarios {
      let context = scenario.context()
      let tr = AccountingPort.translator(scenario.input)
      do {
        try AccountingPort.run(scenario.input, context, tr: tr)
        if let error = scenario.error {
          Issue.record("\(scenario.name): the web refused it (\(error)); the port saved it")
          continue
        }
        WriteParity.assertMatches(scenario.applying(context.changes), scenario.after, scenario: scenario.name)
      } catch let failure as WriteFailure {
        if scenario.error == nil {
          Issue.record("\(scenario.name): the web saved it; the port refused it (\(failure.description))")
        } else {
          // The web throws the words in the reader's language; the app shows them with `t`.
          #expect(tr.t(failure.message, failure.vars) == scenario.error, "\(scenario.name)")
        }
      } catch {
        Issue.record("\(scenario.name): \(error)")
      }
    }
  }

  @Test("toFixed(4) as JavaScript writes it, ties away from zero")
  func fixedDecimals() {
    #expect(AwBanking.fixed4(-3.2) == "-3.2000")
    #expect(AwBanking.fixed4(100.0004) == "100.0004")
    #expect(AwBanking.fixed4(0) == "0.0000")
    #expect(AwBanking.fixed4(-0.0) == "0.0000")
    // 0.03125 is exactly halfway: JavaScript takes the larger, printf the even one.
    #expect(AwBanking.fixed4(0.03125) == "0.0313")
    #expect(AwBanking.fixed4(-0.03125) == "-0.0313")
    #expect(AwBanking.fixed4(1.03125) == "1.0313")
    // As doubles, 2.00005 is a hair below halfway and 1.00005 a hair above.
    #expect(AwBanking.fixed4(2.00005) == "2.0000")
    #expect(AwBanking.fixed4(1.00005) == "1.0001")
    #expect(AwBanking.fixed4(12.5) == "12.5000")
  }

  @Test("statement lines told apart by their order on the same day")
  func fingerprints() {
    let lines = [
      AwStatementLine(date: "2026-10-01", description: "  Coffee  ", amount: -3.2),
      AwStatementLine(date: "2026-10-01", description: "COFFEE", amount: -3.2),
      AwStatementLine(date: "2026-10-02", description: "Deposit\tfrom   client", amount: 100),
    ]
    #expect(
      AwBanking.fingerprints("a1", lines) == [
        "a1|2026-10-01|-3.2000|coffee#1", "a1|2026-10-01|-3.2000|coffee#2", "a1|2026-10-02|100.0000|deposit from client#1",
      ])
  }

  @Test("asset numbers in number order")
  func numberOrder() {
    #expect(AwText.numericLess("FA-0002", "FA-0010"))
    #expect(!AwText.numericLess("FA-0010", "FA-0002"))
    #expect(AwText.numericLess("FA-9", "FA-10"))
    #expect(!AwText.numericLess("FA-0001", "FA-0001"))
  }

  @Test("the months of a run and a depreciation schedule's figures")
  func months() {
    #expect(AwDepreciation.periodEnd("2026-02") == "2026-02-28")
    #expect(AwDepreciation.periodEnd("2028-02") == "2028-02-29")
    #expect(AwDepreciation.periodEnd("2026-12") == "2026-12-31")
    #expect(AwDepreciation.shiftPeriod("2026-01", -1) == "2025-12")
    #expect(AwDepreciation.shiftPeriod("2026-12", 1) == "2027-01")
    #expect(AwAssets.suggestedPeriod([], today: "2026-03-10") == "2026-02")
    #expect(AwBooks.monthLabel("2026-03", .english) == "March 2026")
    #expect(AwBooks.financialYearLabel("2025-07-01", "2026-06-30") == "2025–2026")
  }
}

/// Runs the port of the web function a scenario ran (`input.op`).
enum AccountingPort {
  struct Unknown: Error, CustomStringConvertible {
    let op: String
    var description: String { "no port for \(op)" }
  }

  /// The reader's language of the scenario: English, or Arabic with the web's words it used.
  static func translator(_ input: JSONValue) -> I18n.Translator {
    guard input["language"]?.string == "ar", let words = input["arabic"],
      let data = try? words.data(), let table = try? I18n.Table(json: data)
    else { return .english }
    return I18n.Translator(language: .ar, table: table)
  }

  static func run(_ input: JSONValue, _ ctx: WriteContext, tr: I18n.Translator) throws {
    func text(_ key: String) -> String { input[key]?.string ?? "" }
    func number(_ key: String) -> Double { input[key]?.double ?? 0 }
    func flag(_ key: String) -> Bool { input[key]?.bool ?? false }
    let op = text("op")
    switch op {
    case "saveAccount":
      try AwAccounts.save(ctx, input["account"] ?? .null)
    case "deleteAccount":
      try AwAccounts.delete(ctx, id: text("id"))
    case "saveJournal":
      try AwJournals.save(ctx, input["journal"] ?? .null, tr: tr)
    case "deleteJournal":
      try AwJournals.delete(ctx, id: text("id"), tr: tr)
    case "reverseJournal":
      guard let journal = ctx.get("journals", text("id")) else { throw Unknown(op: "reverseJournal of a journal not there") }
      try AwJournals.reverse(ctx, journal, date: input["date"]?.string, reference: input["reference"]?.string, tr: tr)
    case "closeYear":
      let lines = (input["lines"]?.array ?? []).map { line in
        AwYearEndLine(
          kind: line["kind"]?.string ?? "", base: line["base"]?.double ?? 0, rate: line["rate"]?.double ?? 0,
          amount: line["amount"]?.double ?? 0)
      }
      try AwYearEnd.close(
        ctx, companyId: text("companyId"), yearStart: text("yearStart"), yearEnd: text("yearEnd"),
        profitBeforeLevies: number("profitBeforeLevies"), lines: lines, lock: flag("lock"), tr: tr)
    case "reopenYear":
      try AwYearEnd.reopen(ctx, id: text("id"), tr: tr)
    case "saveAsset":
      try AwAssets.save(ctx, input["asset"] ?? .null, tr: tr)
    case "voidAsset":
      try AwAssets.voidAsset(ctx, id: text("id"), tr: tr)
    case "disposeAsset":
      try AwAssets.dispose(
        ctx, id: text("id"), date: text("date"), proceeds: number("proceeds"),
        depositAccountId: input["depositAccountId"]?.string, notes: input["notes"]?.string, tr: tr)
    case "undoDisposal":
      try AwAssets.undoDisposal(ctx, id: text("id"), tr: tr)
    case "runDepreciation":
      try AwAssets.runDepreciation(ctx, companyId: text("companyId"), period: text("period"), tr: tr)
    case "reverseDepreciationRun":
      try AwAssets.reverseRun(ctx, id: text("id"), tr: tr)
    case "importStatement":
      let lines = (input["lines"]?.array ?? []).map { AwStatementLine($0) }
      let format: JSONValue? = flag("hasFormat") ? (input["format"] ?? .null) : nil
      try AwBanking.importStatement(
        ctx, companyId: text("companyId"), accountId: text("accountId"), lines: lines, fileName: text("fileName"),
        format: format)
    case "matchTransaction":
      try AwBanking.matchLine(
        ctx, id: text("id"), source: input["match"]?["source"]?.string ?? "",
        recordId: input["match"]?["id"]?.string ?? "")
    case "unmatchTransaction":
      try AwBanking.unmatchLine(ctx, id: text("id"))
    case "ignoreTransaction":
      try AwBanking.ignoreLine(ctx, id: text("id"), ignored: flag("ignored"))
    case "deleteTransaction":
      AwBanking.deleteLine(ctx, id: text("id"))
    case "saveTransfer":
      try AwBanking.saveTransfer(
        ctx, companyId: text("companyId"), from: text("from"), to: text("to"), date: text("date"),
        amount: number("amount"), reference: input["reference"]?.string, tr: tr)
    case "createFromTransaction":
      let action = input["action"] ?? .null
      let kind = action["kind"]?.string ?? ""
      let made: AwCreateAction =
        kind == "transfer"
        ? .transfer(otherAccountId: action["otherAccountId"]?.string ?? "")
        : .account(accountId: action["accountId"]?.string ?? "")
      try AwBanking.createFromLine(ctx, id: text("id"), action: made, tr: tr)
    case "fileVatReturn":
      let figures = input["figures"] ?? .null
      let boxes = (figures["boxes"]?.array ?? []).map { box in
        AwVatBox(
          id: box["id"]?.string ?? "", label: box["label"]?.string ?? "", amount: box["amount"]?.int ?? 0,
          vat: box["vat"]?.int)
      }
      let given = AwVatFigures(
        boxes: boxes, net: figures["net"]?.int ?? 0, output: figures["output"]?.int ?? 0,
        input: figures["input"]?.int ?? 0)
      try AwVat.file(
        ctx, companyId: text("companyId"), start: input["period"]?["start"]?.string ?? "",
        end: input["period"]?["end"]?.string ?? "", figures: given, filedOn: text("filedOn"),
        reference: text("reference"), lock: flag("lock"), tr: tr)
    case "undoVatReturn":
      try AwVat.undo(ctx, id: text("id"), tr: tr)
    case "recordVatPayment":
      try AwVat.recordPayment(ctx, id: text("id"), date: text("date"), accountId: text("accountId"), tr: tr)
    default:
      throw Unknown(op: op)
    }
  }
}
