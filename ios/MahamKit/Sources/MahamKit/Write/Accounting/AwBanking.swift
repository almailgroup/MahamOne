import Foundation

/// A line of a bank statement, as read from the file or typed in (`StatementLine`).
public struct AwStatementLine: Sendable, Equatable {
  public var date: String
  public var description: String
  public var reference: String
  /// Positive is money in, negative money out.
  public var amount: Double
  /// The running balance after the line, when the bank gives it.
  public var balance: Double?
  /// The day the bank counts the money from, when the statement has its own column.
  public var valueDate: String?

  public init(
    date: String, description: String, reference: String = "", amount: Double, balance: Double? = nil,
    valueDate: String? = nil
  ) {
    self.date = date
    self.description = description
    self.reference = reference
    self.amount = amount
    self.balance = balance
    self.valueDate = valueDate
  }

  /// A line as the web keeps it in a test or an import (`{ date, description, … }`).
  public init(_ value: JSONValue) {
    date = value.awStr("date")
    description = value.awStr("description")
    reference = value.awStr("reference")
    amount = value.awNum("amount")
    balance = value["balance"]?.double
    valueDate = value.awText("valueDate")
  }
}

/// What a statement line becomes when the books don't have it yet, of the
/// kinds ported here (`CreateAction`'s transfer and account).
public enum AwCreateAction: Sendable, Equatable {
  /// A transfer from or to another of the company's own accounts.
  case transfer(otherAccountId: String)
  /// A journal against another account ("other").
  case account(accountId: String)
}

/// The port of the web's banking writes (src/db/banking.ts and the
/// fingerprints of src/lib/banking/statement.ts).
public enum AwBanking {
  // MARK: Importing

  /// `n.toFixed(4)`: the nearest number with four decimals, exactly as
  /// JavaScript writes it (a tie goes away from zero).
  static func fixed4(_ value: Double) -> String {
    if value.isNaN { return "NaN" }
    if value == 0 { return "0.0000" }
    let magnitude = abs(value)
    if magnitude >= 1e21 { return WebJS.numberString(value) }
    // printf rounds the exact value, a tie to even; JavaScript takes the larger of a tie.
    var text = String(format: "%.4f", magnitude)
    // A tie at the fifth decimal is exactly an odd number of 32nds: (2n + 1) / 20000.
    let y = magnitude * 32
    if y.rounded() == y, y < 9_007_199_254_740_992, y.truncatingRemainder(dividingBy: 2) == 1 {
      let units = (Int64(y) * 625 + 1) / 2
      text = String(units / 10000) + "." + WebJS.padStart(String(units % 10000), 4)
    }
    return (value < 0 ? "-" : "") + text
  }

  /// `fingerprints(accountId, lines)`: keys that tell statement lines apart,
  /// identical lines of one day by their order.
  public static func fingerprints(_ accountId: String, _ lines: [AwStatementLine]) -> [String] {
    var seen: [String: Int] = [:]
    return lines.map { line in
      let key = [accountId, line.date, fixed4(line.amount), collapse(line.description)].joined(separator: "|")
      let n = (seen[key] ?? 0) + 1
      seen[key] = n
      return "\(key)#\(n)"
    }
  }

  /// `description.trim().toLowerCase().replace(/\s+/g, ' ')`.
  private static func collapse(_ text: String) -> String {
    var out = String.UnicodeScalarView()
    var inSpace = false
    for scalar in WebJS.trim(text).lowercased().unicodeScalars {
      if WebJS.isSpace(scalar) {
        if !inSpace { out.append(" ") }
        inSpace = true
      } else {
        out.append(scalar)
        inSpace = false
      }
    }
    return String(out)
  }

  /// `importStatement(companyId, accountId, lines, fileName, format)`: adds
  /// the lines not imported before (overlapping statements are normal). With
  /// `format`, the account remembers the layout (`.null` forgets it; nil
  /// leaves it as it is).
  @discardableResult
  public static func importStatement(
    _ ctx: WriteContext, companyId: String, accountId: String, lines: [AwStatementLine], fileName: String,
    format: JSONValue? = nil
  ) throws -> (added: Int, duplicates: Int, transactions: [JSONValue]) {
    guard let company = ctx.get("companies", companyId), let account = ctx.get("accounts", accountId),
      account.awStr("companyId") == companyId
    else { throw WriteFailure("Choose the account the statement belongs to.") }
    let precision = Money.precision(company.awStr("currency"))
    let keys = fingerprints(accountId, lines)
    let existing = Set(ctx.all("bankTransactions") { $0.awStr("accountId") == accountId }.map { $0.awStr("fingerprint") })
    let importId = ctx.newId()
    let stamp = ctx.stamp
    var rows: [JSONValue] = []
    for (index, line) in lines.enumerated() where !existing.contains(keys[index]) {
      var fields: [String: JSONValue] = [
        "id": .string(ctx.newId()), "companyId": .string(companyId), "accountId": .string(accountId),
        "date": .string(line.date), "description": .string(WebJS.trim(line.description)),
        "reference": .string(WebJS.trim(line.reference)), "amount": .number(awRound(line.amount, precision)),
        "balance": line.balance.map { JSONValue.number(awRound($0, precision)) } ?? JSONValue.null,
      ]
      if let valueDate = line.valueDate, !valueDate.isEmpty { fields["valueDate"] = .string(valueDate) }
      fields["fingerprint"] = .string(keys[index])
      fields["importId"] = .string(importId)
      fields["position"] = .number(Double(index))
      fields["match"] = .null
      fields["ignored"] = .bool(false)
      fields["createdAt"] = .string(stamp)
      fields["updatedAt"] = .string(stamp)
      rows.append(.object(fields))
    }
    for row in rows { ctx.put("bankTransactions", row) }
    if let format { rememberFormat(ctx, account, format, stamp) }
    let text: String
    if !fileName.isEmpty {
      text =
        rows.count == 1
        ? "{count} statement line imported into {account} from {file}"
        : "{count} statement lines imported into {account} from {file}"
    } else {
      text = rows.count == 1 ? "{count} statement line imported into {account}" : "{count} statement lines imported into {account}"
    }
    AwActivity.log(
      ctx, entity: "bank", entityId: importId, action: "imported", text: text,
      vars: [
        "count": .number(Double(rows.count)), "account": account["name"] ?? .null, "file": .string(fileName),
      ],
      arabic: ["account": account["nameAr"]?.string])
    return (added: rows.count, duplicates: lines.count - rows.count, transactions: rows)
  }

  /// `rememberFormat(account, format)`: an unchanged layout writes nothing.
  private static func rememberFormat(_ ctx: WriteContext, _ account: JSONValue, _ format: JSONValue, _ stamp: String) {
    if WebJS.sameData(account["statementFormat"] ?? .null, format) { return }
    var fields = account.awFields
    fields.removeValue(forKey: "statementFormat")
    if WebJS.truthy(format) { fields["statementFormat"] = format }
    fields["updatedAt"] = .string(stamp)
    ctx.put("accounts", .object(fields))
  }

  // MARK: Matching

  /// `setMatch(id, match, ignored)`.
  private static func setMatch(_ ctx: WriteContext, _ id: String, _ match: JSONValue, ignored: Bool = false) throws {
    guard let line = ctx.get("bankTransactions", id) else { throw WriteFailure("Statement line not found.") }
    var fields = line.awFields
    fields["match"] = match
    fields["ignored"] = .bool(ignored)
    fields["updatedAt"] = .string(ctx.stamp)
    ctx.put("bankTransactions", .object(fields))
  }

  /// A match (`BankMatch`): "payment", "expense" or "journal", and the record's id.
  public static func match(source: String, id: String) -> JSONValue {
    .object(["source": .string(source), "id": .string(id)])
  }

  /// `matchTransaction(id, match)`: a book entry is matched to one line only.
  public static func matchLine(_ ctx: WriteContext, id: String, source: String, recordId: String) throws {
    let taken = ctx.all("bankTransactions").first { line in
      line.awId != id && line["match"]?["source"]?.string == source && line["match"]?["id"]?.string == recordId
    }
    if taken != nil { throw WriteFailure("That transaction is already matched to another line.") }
    try setMatch(ctx, id, match(source: source, id: recordId))
  }

  /// `unmatchTransaction(id)`.
  public static func unmatchLine(_ ctx: WriteContext, id: String) throws {
    try setMatch(ctx, id, .null)
  }

  /// `ignoreTransaction(id, ignored)`: left out of the reconciliation on purpose (or restored).
  public static func ignoreLine(_ ctx: WriteContext, id: String, ignored: Bool) throws {
    try setMatch(ctx, id, .null, ignored: ignored)
  }

  /// `deleteTransaction(id)`.
  public static func deleteLine(_ ctx: WriteContext, id: String) {
    ctx.delete("bankTransactions", id)
  }

  // MARK: Transfers

  /// `saveTransfer(input)`: moves money between two of the company's own accounts.
  @discardableResult
  public static func saveTransfer(
    _ ctx: WriteContext, companyId: String, from: String, to: String, date: String, amount: Double,
    reference: String? = nil, tr: I18n.Translator = .english
  ) throws -> JSONValue {
    if from == to { throw WriteFailure("Choose two different accounts.") }
    if !(amount > 0) { throw WriteFailure("Enter the amount transferred.") }
    guard let source = ctx.get("accounts", from), let target = ctx.get("accounts", to) else {
      throw WriteFailure("Choose both accounts.")
    }
    let fromName = tr.localName(source.awStr("name"), source["nameAr"]?.string)
    let toName = tr.localName(target.awStr("name"), target["nameAr"]?.string)
    let typed = WebJS.trim(reference ?? "")
    let text = typed.isEmpty ? tr.t("Transfer from {from} to {to}", ["from": fromName, "to": toName]) : typed
    let first = AwJournals.newLine(
      ctx,
      [
        "accountId": .string(target.awId), "debit": .number(amount),
        "description": .string(tr.t("From {account}", ["account": fromName])),
      ])
    let second = AwJournals.newLine(
      ctx,
      [
        "accountId": .string(source.awId), "credit": .number(amount),
        "description": .string(tr.t("To {account}", ["account": toName])),
      ])
    let journal = AwJournals.create(
      ctx, companyId: companyId,
      [
        "date": .string(date), "kind": .string("transfer"), "reference": .string(text),
        "status": .string("posted"), "lines": .array([first, second]),
      ])
    return try AwJournals.save(ctx, journal, tr: tr)
  }

  /// `createFromTransaction(id, action)` for a transfer or another account:
  /// records the statement line in the books and matches it to the journal.
  @discardableResult
  public static func createFromLine(
    _ ctx: WriteContext, id: String, action: AwCreateAction, tr: I18n.Translator = .english
  ) throws -> JSONValue {
    guard let line = ctx.get("bankTransactions", id) else { throw WriteFailure("Statement line not found.") }
    guard let company = ctx.get("companies", line.awStr("companyId")) else { throw WriteFailure("Company not found") }
    let amount = abs(line.awNum("amount"))
    let reference = line.awStr("reference")
    let memo = reference.isEmpty ? line.awStr("description") : reference
    let into = line.awNum("amount") > 0
    let account = line.awStr("accountId")
    let journal: JSONValue
    switch action {
    case .transfer(let other):
      journal = try saveTransfer(
        ctx, companyId: company.awId, from: into ? other : account, to: into ? account : other,
        date: line.awStr("date"), amount: amount, reference: memo, tr: tr)
    case .account(let other):
      let short = WebJS.prefix(memo, 120)
      let description = line["description"] ?? .null
      let first = AwJournals.newLine(
        ctx,
        [
          "accountId": .string(account), "debit": .number(into ? amount : 0), "credit": .number(into ? 0 : amount),
          "description": description,
        ])
      let second = AwJournals.newLine(
        ctx,
        [
          "accountId": .string(other), "debit": .number(into ? 0 : amount), "credit": .number(into ? amount : 0),
          "description": description,
        ])
      journal = try AwJournals.save(
        ctx,
        AwJournals.create(
          ctx, companyId: company.awId,
          [
            "date": line["date"], "reference": .string(short.isEmpty ? tr.t("Bank transaction") : short),
            "status": .string("posted"), "lines": .array([first, second]),
          ]), tr: tr)
    }
    let found = match(source: "journal", id: journal.awId)
    try setMatch(ctx, line.awId, found)
    return found
  }
}
