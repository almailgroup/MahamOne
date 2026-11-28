import Foundation

/// The port of the web's manual journals (src/db/accounting.ts: `newJournalLine`,
/// `createJournal`, `journalTotals`, `saveJournal`, `deleteJournal`,
/// `reverseJournal`) and the journal kinds (src/lib/accounting/journal-kinds.ts).
/// Ids are handed out in the web's order, so the records match: a new
/// journal's own id, then the two empty lines `createJournal` starts with,
/// after the ids of the lines it is given.
public enum AwJournals {
  /// `ACCOUNTING_OWNED_KINDS`: written by the accounting and payroll modules only.
  public static let ownedKinds: Set<String> = [
    "payroll", "depreciation", "asset_purchase", "asset_opening", "asset_disposal", "year_end", "retention_release",
  ]

  /// `JOURNAL_KINDS[kind].owner`: where an entry of the kind is managed (an English key).
  public static func owner(_ kind: String) -> String? {
    switch kind {
    case "cheque_clearing", "cheque_return": "Payments"
    case "payroll": "Payroll"
    case "depreciation", "asset_purchase", "asset_opening", "asset_disposal": "Fixed assets"
    case "year_end": "Year-end close"
    case "retention_release": "Retentions"
    default: nil
    }
  }

  /// `isProtected(journal)`: an entry another part of the app owns.
  public static func isProtected(_ journal: JSONValue?) -> Bool {
    guard let kind = journal?.awText("kind") else { return false }
    return ownedKinds.contains(kind)
  }

  /// `ownedError(journal)`.
  static func ownedError(_ journal: JSONValue, _ tr: I18n.Translator) -> WriteFailure {
    if let kind = journal.awText("kind"), let owner = owner(kind) {
      return WriteFailure("This entry is managed in {place}. Change it there.", ["place": tr.t(owner)])
    }
    return WriteFailure("This entry was made by Maham Books and cannot be changed here.")
  }

  // MARK: New records

  /// `newJournalLine()` for a form: an empty line with a new id.
  public static func blankLine(id: String = newId()) -> JSONValue {
    .object([
      "id": .string(id), "accountId": .string(""), "description": .string(""), "debit": .number(0),
      "credit": .number(0), "contactId": .null,
    ])
  }

  /// `newJournalLine(overrides)`: takes the next id.
  public static func newLine(_ ctx: WriteContext, _ overrides: [String: JSONValue?] = [:]) -> JSONValue {
    let base: [String: JSONValue] = [
      "id": .string(ctx.newId()), "accountId": .string(""), "description": .string(""), "debit": .number(0),
      "credit": .number(0), "contactId": .null,
    ]
    return .object(awSpread(base, overrides))
  }

  /// `createJournal(companyId, overrides)`: its id, then two empty lines
  /// (made even when `overrides` has lines), stamped now and dated today.
  public static func create(_ ctx: WriteContext, companyId: String, _ overrides: [String: JSONValue?] = [:])
    -> JSONValue
  {
    let stamp = ctx.stamp
    var base: [String: JSONValue] = ["id": .string(ctx.newId())]
    base["companyId"] = .string(companyId)
    base["number"] = .string("")
    base["date"] = .string(ctx.today)
    base["reference"] = .string("")
    base["notes"] = .string("")
    base["status"] = .string("posted")
    let first = newLine(ctx)
    let second = newLine(ctx)
    base["lines"] = .array([first, second])
    base["createdAt"] = .string(stamp)
    base["updatedAt"] = .string(stamp)
    return .object(awSpread(base, overrides))
  }

  /// `createJournal(companyId, { status })` for a form, outside a save: a new
  /// id and two empty lines, dated today.
  public static func blank(
    companyId: String, today: String, status: String = "posted", now: Date = Date(),
    makeId: () -> String = { newId() }
  ) -> JSONValue {
    let stamp = Defaults.nowStamp(now)
    func line() -> JSONValue {
      .object([
        "id": .string(makeId()), "accountId": .string(""), "description": .string(""), "debit": .number(0),
        "credit": .number(0), "contactId": .null,
      ])
    }
    let id = makeId()
    let lines = [line(), line()]
    return .object([
      "id": .string(id), "companyId": .string(companyId), "number": .string(""), "date": .string(today),
      "reference": .string(""), "notes": .string(""), "status": .string(status), "lines": .array(lines),
      "createdAt": .string(stamp), "updatedAt": .string(stamp),
    ])
  }

  // MARK: Totals

  /// `journalTotals(lines, precision)`: debit, credit and their difference.
  public static func totals(_ lines: [JSONValue], _ precision: Int) -> (debit: Double, credit: Double, difference: Double) {
    var debit = Decimal(0)
    var credit = Decimal(0)
    for line in lines {
      debit += Money.dec(line.awNum("debit"))
      credit += Money.dec(line.awNum("credit"))
    }
    return (awRound(debit, precision), awRound(credit, precision), awRound(debit - credit, precision))
  }

  // MARK: Saving

  /// `saveJournal(input, { system })`: checks the lines, numbers a new
  /// journal from the company's rule, and logs it. `system` is set by the
  /// part of the app that owns the entry.
  @discardableResult
  public static func save(
    _ ctx: WriteContext, _ input: JSONValue, system: Bool = false, tr: I18n.Translator = .english
  ) throws -> JSONValue {
    guard let company = ctx.get("companies", input.awStr("companyId")) else {
      throw WriteFailure("Company not found")
    }
    let existing = ctx.get("journals", input.awId)
    try AwBooks.assertUnlocked(company, [input["date"]?.string, existing?["date"]?.string], tr)
    if let existing, existing.awTruthy("vatReturnId") {
      throw WriteFailure("This entry closes a VAT return. Undo the return to change it.")
    }
    if !system && (isProtected(existing) || isProtected(input)) {
      throw ownedError(existing ?? input, tr)
    }

    let lines = input.awList("lines").filter { line in
      line.awTruthy("accountId") && (awNotZero(line["debit"]) || awNotZero(line["credit"]))
    }
    if lines.contains(where: { awNegative($0["debit"]) || awNegative($0["credit"]) }) {
      throw WriteFailure("Amounts must be positive. Use the other column to reverse.")
    }
    if lines.contains(where: { awNotZero($0["debit"]) && awNotZero($0["credit"]) }) {
      throw WriteFailure("A line can have a debit or a credit, not both.")
    }
    if lines.count < 2 { throw WriteFailure("A journal needs at least two lines with amounts.") }
    let precision = Money.precision(company.awStr("currency"))
    if totals(lines, precision).difference != 0 { throw WriteFailure("Debits and credits must be equal.") }
    for line in lines {
      let account = ctx.get("accounts", line.awStr("accountId"))
      if account == nil || account?.awStr("companyId") != company.awId {
        throw WriteFailure("Choose an account on every line.")
      }
    }

    var fields = input.awFields
    fields["lines"] = .array(lines)
    var number = WebJS.trim(input.awStr("number"))
    let id = input.awId
    if number.isEmpty {
      let rule = WebJS.present(company["numbering"]?["journal"]) ?? Defaults.defaultNumbering()["journal"] ?? .null
      let taken = Set(
        AwBooks.records(ctx, "journals", company.awId).filter { $0.awId != id }.map { $0.awStr("number").lowercased() })
      let allocated = Numbering.allocateNumber(NumberingRule(rule), input.awStr("date"), taken: taken)
      number = allocated.number
      var numbering = WebJS.spread(company["numbering"])
      numbering["journal"] = allocated.rule.raw
      var companyFields = company.awFields
      companyFields["numbering"] = .object(numbering)
      ctx.put("companies", .object(companyFields))
    }
    fields["number"] = .string(number)
    let stamp = ctx.stamp
    fields["updatedAt"] = .string(stamp)
    if existing == nil { fields["createdAt"] = .string(stamp) }
    let journal = JSONValue.object(fields)
    ctx.put("journals", journal)
    ctx.logActivity(
      entity: "journal", entityId: id, action: existing != nil ? "updated" : "created",
      message: ActivityMessage(
        existing != nil ? "Journal {number} updated" : "Journal {number} created", vars: ["number": number]))
    return journal
  }

  /// `deleteJournal(id)`: only an ordinary journal of an open period.
  public static func delete(_ ctx: WriteContext, id: String, tr: I18n.Translator = .english) throws {
    guard let journal = ctx.get("journals", id) else { return }
    if let company = ctx.get("companies", journal.awStr("companyId")) {
      try AwBooks.assertUnlocked(company, [journal["date"]?.string], tr)
    }
    if journal.awTruthy("vatReturnId") {
      throw WriteFailure("This entry closes a VAT return. Undo the return to remove it.")
    }
    // Entries made by fixed assets or the year-end close are reversed, never deleted.
    if isProtected(journal) { throw ownedError(journal, tr) }
    ctx.delete("journals", id)
    ctx.logActivity(
      entity: "journal", entityId: id, action: "deleted",
      message: ActivityMessage("Journal {number} deleted", vars: ["number": journal.awStr("number")]))
  }

  /// `reverseJournal(journal, { date, reference })`: an entry that undoes
  /// it (debits and credits swapped), dated like it unless a date is given.
  @discardableResult
  public static func reverse(
    _ ctx: WriteContext, _ journal: JSONValue, date: String? = nil, reference: String? = nil,
    tr: I18n.Translator = .english
  ) throws -> JSONValue {
    let text = reference ?? tr.t("Reversal of {number}", ["number": journal.awStr("number")])
    var lines: [JSONValue] = []
    for line in journal.awList("lines") {
      lines.append(
        newLine(
          ctx,
          [
            "accountId": line["accountId"], "description": line["description"], "contactId": line["contactId"],
            "debit": line["credit"], "credit": line["debit"],
          ]))
    }
    let overrides: [String: JSONValue?] = [
      "date": date.map(JSONValue.string) ?? journal["date"],
      "reference": .string(text),
      "notes": journal["reference"],
      "status": .string("posted"),
      "kind": journal["kind"],
      "sourceId": WebJS.present(journal["sourceId"]) ?? JSONValue.null,
      "reversalOf": journal["id"],
      "lines": .array(lines),
    ]
    let created = create(ctx, companyId: journal.awStr("companyId"), overrides)
    return try save(ctx, created, system: true, tr: tr)
  }
}
