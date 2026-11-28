import Foundation

/// One levy or transfer of a year-end close, in the company currency (`CloseYearInput.lines`).
public struct AwYearEndLine: Sendable, Equatable {
  /// statutory_reserve, voluntary_reserve, kfas, zakat, nlst or income_tax.
  public var kind: String
  public var base: Double
  public var rate: Double
  public var amount: Double

  public init(kind: String, base: Double, rate: Double, amount: Double) {
    self.kind = kind
    self.base = base
    self.rate = rate
    self.amount = amount
  }
}

/// The port of the web's year-end close (src/db/accounting.ts: `closeYear`,
/// `reopenYear`).
public enum AwYearEnd {
  /// `YEAR_END_LABELS`: an English key for each kind.
  public static func label(_ kind: String) -> String {
    switch kind {
    case "statutory_reserve": "Transfer to statutory reserve"
    case "voluntary_reserve": "Transfer to voluntary reserve"
    case "kfas": "KFAS contribution"
    case "zakat": "Zakat"
    case "nlst": "National Labour Support Tax"
    case "income_tax": "Income tax"
    default: kind
    }
  }

  /// `YEAR_END_ACCOUNTS`: the expense (or retained earnings, nil) debited and the account credited.
  static func accounts(_ kind: String) -> (debit: AwSpec?, credit: AwSpec)? {
    let debit: AwSpec?
    let credit: AwSpec
    switch kind {
    case "statutory_reserve":
      debit = nil
      credit = AwSpec.statutoryReserve
    case "voluntary_reserve":
      debit = nil
      credit = AwSpec.voluntaryReserve
    case "kfas":
      debit = AwSpec.kfas
      credit = AwSpec.kfasPayable
    case "zakat":
      debit = AwSpec.zakat
      credit = AwSpec.zakatPayable
    case "nlst":
      debit = AwSpec.nlst
      credit = AwSpec.nlstPayable
    case "income_tax":
      debit = AwSpec.incomeTax
      credit = AwSpec.incomeTaxPayable
    default:
      return nil
    }
    return (debit: debit, credit: credit)
  }

  /// `closeYear(companyId, input)`: posts the levies (expense against the
  /// amount payable) and the transfers to the reserves on the last day of
  /// the year, optionally locks the year, and keeps the close.
  @discardableResult
  public static func close(
    _ ctx: WriteContext, companyId: String, yearStart: String, yearEnd: String, profitBeforeLevies: Double,
    lines input: [AwYearEndLine], lock: Bool, tr: I18n.Translator = .english
  ) throws -> JSONValue {
    guard let company = ctx.get("companies", companyId) else { throw WriteFailure("Company not found") }
    let p = Money.precision(company.awStr("currency"))
    let closes = AwBooks.records(ctx, "yearEnds", companyId).filter { $0.awStr("status") == "closed" }
    if closes.contains(where: { $0.awStr("yearEnd") == yearEnd }) {
      throw WriteFailure("This financial year is already closed.")
    }
    if closes.contains(where: { WebJS.less(yearEnd, $0.awStr("yearEnd")) }) {
      throw WriteFailure("A later year is already closed. Years are closed in order.")
    }
    if input.contains(where: { !($0.amount >= 0) }) { throw WriteFailure("Amounts can’t be negative.") }
    try AwBooks.assertUnlocked(company, [yearEnd], tr)
    guard let retained = AwBooks.roleMap(AwBooks.records(ctx, "accounts", companyId))["retained_earnings"] else {
      throw WriteFailure("The chart of accounts has no retained earnings account.")
    }

    let id = ctx.newId()
    var lines: [JSONValue] = []
    for line in input {
      let amount = awRound(line.amount, p)
      if amount == 0 { continue }
      guard let pair = accounts(line.kind) else { continue }
      let debit = pair.debit.map { AwAccounts.ensureSpec(ctx, company, $0).awId } ?? retained
      let credit = AwAccounts.ensureSpec(ctx, company, pair.credit).awId
      lines.append(
        .object([
          "kind": .string(line.kind), "base": .number(awRound(line.base, p)), "rate": .number(line.rate),
          "amount": .number(amount), "debitAccountId": .string(debit), "creditAccountId": .string(credit),
        ]))
    }
    let year = AwBooks.financialYearLabel(yearStart, yearEnd)
    var journalIds: [String] = []
    func post(_ reference: String, _ entries: [JSONValue]) throws {
      if entries.isEmpty { return }
      var journalLines: [JSONValue] = []
      for entry in entries {
        let description = JSONValue.string(tr.t(label(entry.awStr("kind"))))
        journalLines.append(
          AwJournals.newLine(
            ctx, ["accountId": entry["debitAccountId"], "debit": entry["amount"], "description": description]))
        journalLines.append(
          AwJournals.newLine(
            ctx, ["accountId": entry["creditAccountId"], "credit": entry["amount"], "description": description]))
      }
      let journal = try AwJournals.save(
        ctx,
        AwJournals.create(
          ctx, companyId: companyId,
          [
            "date": .string(yearEnd), "kind": .string("year_end"), "sourceId": .string(id),
            "reference": .string(reference), "status": .string("posted"), "lines": .array(journalLines),
          ]),
        system: true, tr: tr)
      journalIds.append(journal.awId)
    }
    let isReserve = { (line: JSONValue) -> Bool in
      line.awStr("kind") == "statutory_reserve" || line.awStr("kind") == "voluntary_reserve"
    }
    try post(tr.t("KFAS, Zakat, NLST and income tax for {year}", ["year": year]), lines.filter { !isReserve($0) })
    try post(tr.t("Transfers to reserves for {year}", ["year": year]), lines.filter(isReserve))

    let fresh = ctx.get("companies", companyId) ?? company
    let settings = AwBooks.settings(fresh)
    let lockDate = settings.awText("lockDate")
    let lockedTo: String? = lock && (lockDate == nil || WebJS.less(lockDate ?? "", yearEnd)) ? yearEnd : nil
    if let lockedTo {
      var accounting = settings.awFields
      accounting["lockDate"] = .string(lockedTo)
      var companyFields = fresh.awFields
      companyFields["accounting"] = .object(accounting)
      companyFields["updatedAt"] = .string(ctx.stamp)
      ctx.put("companies", .object(companyFields))
    }
    let stamp = ctx.stamp
    let close: JSONValue = .object([
      "id": .string(id), "companyId": .string(companyId), "yearStart": .string(yearStart),
      "yearEnd": .string(yearEnd), "profitBeforeLevies": .number(awRound(profitBeforeLevies, p)),
      "lines": .array(lines), "journalIds": .array(journalIds.map(JSONValue.string)),
      "lockedTo": lockedTo.map(JSONValue.string) ?? .null, "status": .string("closed"),
      "reversalJournalIds": .array([]), "createdAt": .string(stamp), "updatedAt": .string(stamp),
    ])
    ctx.put("yearEnds", close)
    ctx.logActivity(
      entity: "year_end", entityId: id, action: "closed",
      message: ActivityMessage("Financial year {year} closed", vars: ["year": year]))
    return close
  }

  /// `reopenYear(id)`: reverses a closed year's entries. The year must not be locked.
  public static func reopen(_ ctx: WriteContext, id: String, tr: I18n.Translator = .english) throws {
    guard let close = ctx.get("yearEnds", id), close.awStr("status") == "closed" else { return }
    guard let company = ctx.get("companies", close.awStr("companyId")) else {
      throw WriteFailure("Company not found")
    }
    let later = AwBooks.records(ctx, "yearEnds", close.awStr("companyId")).first {
      $0.awStr("status") == "closed" && WebJS.less(close.awStr("yearEnd"), $0.awStr("yearEnd"))
    }
    if let later {
      throw WriteFailure(
        "Reopen {year} first.",
        ["year": AwBooks.financialYearLabel(later.awStr("yearStart"), later.awStr("yearEnd"))])
    }
    try AwBooks.assertUnlocked(company, [close["yearEnd"]?.string], tr)
    var reversals: [JSONValue] = []
    for journalId in close.awList("journalIds") {
      guard let journal = ctx.get("journals", journalId.string ?? "") else { continue }
      reversals.append(.string(try AwJournals.reverse(ctx, journal, tr: tr).awId))
    }
    var fields = close.awFields
    fields["status"] = .string("reopened")
    fields["reversalJournalIds"] = .array(reversals)
    fields["updatedAt"] = .string(ctx.stamp)
    ctx.put("yearEnds", .object(fields))
    ctx.logActivity(
      entity: "year_end", entityId: id, action: "reopened",
      message: ActivityMessage(
        "Financial year {year} reopened",
        vars: ["year": AwBooks.financialYearLabel(close.awStr("yearStart"), close.awStr("yearEnd"))]))
  }
}
