import Foundation

/// A box of a VAT return, in minor units (`VatBox`: its id, label, amount and VAT).
public struct AwVatBox: Sendable, Equatable {
  public var id: String
  public var label: String
  public var amount: Int
  public var vat: Int?

  public init(id: String, label: String, amount: Int, vat: Int? = nil) {
    self.id = id
    self.label = label
    self.amount = amount
    self.vat = vat
  }
}

/// A period's return as the books give it now (`vatReturn(...)` and
/// `vatAccountTotals(...)` of src/lib/accounting/vat.ts), worked out from the
/// ledger by the caller: what filing keeps and posts.
public struct AwVatFigures: Sendable, Equatable {
  public var boxes: [AwVatBox]
  /// Positive: to pay; negative: to reclaim (minor units).
  public var net: Int
  /// The output VAT on the output tax account in the period (minor units).
  public var output: Int
  /// The input VAT on the input tax account in the period (minor units).
  public var input: Int

  public init(boxes: [AwVatBox], net: Int, output: Int, input: Int) {
    self.boxes = boxes
    self.net = net
    self.output = output
    self.input = input
  }
}

/// The port of the web's VAT return writes (src/db/vat.ts: `fileVatReturn`,
/// `undoVatReturn`, `recordVatPayment`) and `vatSettings` (chart-setup.ts).
public enum AwVat {
  /// `vatFormatFor(country)`.
  public static func formatFor(_ country: String) -> String {
    let code = country.uppercased()
    if code == "GB" || code == "IM" { return "uk" }
    if code == "AE" { return "ae" }
    return "generic"
  }

  /// `vatSettings(company).format`: the saved settings', or the country's.
  public static func format(_ company: JSONValue) -> String {
    if let saved = WebJS.present(AwBooks.settings(company)["vat"]) { return saved.awStr("format") }
    return formatFor(company["address"]?["country"]?.string ?? "")
  }

  /// `fileVatReturn(companyId, period, { filedOn, reference, lock })`: keeps
  /// the boxes as filed, moves the period's output and input VAT to the VAT
  /// liability account and, when asked, locks the period.
  @discardableResult
  public static func file(
    _ ctx: WriteContext, companyId: String, start: String, end: String, figures: AwVatFigures, filedOn: String,
    reference: String, lock: Bool, tr: I18n.Translator = .english
  ) throws -> JSONValue {
    guard let company = ctx.get("companies", companyId) else { throw WriteFailure("Company not found") }
    let filed = AwBooks.records(ctx, "vatReturns", company.awId).first { $0.awStr("periodStart") == start }
    if filed != nil { throw WriteFailure("This period has already been filed.") }
    let roles = AwBooks.roleMap(AwBooks.records(ctx, "accounts", company.awId))
    let precision = Money.precision(company.awStr("currency"))
    guard let outputTax = roles["output_tax"], let inputTax = roles["input_tax"],
      let settlement = roles["tax_settlement"]
    else { throw WriteFailure("The chart of accounts has no VAT accounts set up.") }

    let id = ctx.newId()
    func entry(_ accountId: String, _ minor: Int, _ description: String) -> JSONValue {
      AwJournals.newLine(
        ctx,
        [
          "accountId": .string(accountId), "description": .string(description),
          "debit": .number(minor > 0 ? awMajor(minor, precision) : 0),
          "credit": .number(minor < 0 ? awMajor(-minor, precision) : 0),
        ])
    }
    let candidates = [
      entry(outputTax, figures.output, tr.t("VAT on sales")),
      entry(inputTax, -figures.input, tr.t("VAT on purchases")),
      entry(settlement, figures.input - figures.output, tr.t("VAT for the period")),
    ]
    let journalLines = candidates.filter { awNotZero($0["debit"]) || awNotZero($0["credit"]) }
    let vars = ["start": start, "end": end]

    var journalId = JSONValue.null
    if journalLines.count >= 2 {
      // Dated at the end of the period, unless that is already locked.
      let lockDate = AwBooks.lockDate(company)
      var date = end
      if let lockDate, !WebJS.less(lockDate, end) { date = ISODates.addDays(lockDate, 1) }
      let notes = reference.isEmpty ? "" : tr.t("Reference {reference}", ["reference": reference])
      let journal = try AwJournals.save(
        ctx,
        AwJournals.create(
          ctx, companyId: company.awId,
          [
            "date": .string(date), "reference": .string(tr.t("VAT return {start} to {end}", vars)),
            "notes": .string(notes), "status": .string("posted"), "vatReturnId": .string(id),
            "lines": .array(journalLines),
          ]), tr: tr)
      journalId = .string(journal.awId)
    }

    let stamp = ctx.stamp
    let boxes: [JSONValue] = figures.boxes.map { box in
      var fields: [String: JSONValue] = [
        "id": .string(box.id), "label": .string(box.label), "amount": .number(Double(box.amount)),
      ]
      if let vat = box.vat { fields["vat"] = .number(Double(vat)) }
      return .object(fields)
    }
    let record: JSONValue = .object([
      "id": .string(id), "companyId": .string(company.awId), "periodStart": .string(start),
      "periodEnd": .string(end), "format": .string(format(company)), "boxes": .array(boxes),
      "net": .number(Double(figures.net)), "currency": company["currency"] ?? .null, "filedOn": .string(filedOn),
      "reference": .string(WebJS.trim(reference)), "journalId": journalId, "paymentJournalId": .null,
      "createdAt": .string(stamp), "updatedAt": .string(stamp),
    ])
    ctx.put("vatReturns", record)

    if lock {
      // Read again: saving the journal moved the company's number counter.
      let current = ctx.get("companies", company.awId) ?? company
      let settings = AwBooks.settings(current)
      let lockNow = settings.awText("lockDate")
      if lockNow == nil || WebJS.less(lockNow ?? "", end) {
        var accounting = settings.awFields
        accounting["lockDate"] = .string(end)
        var fields = current.awFields
        fields["accounting"] = .object(accounting)
        fields["updatedAt"] = .string(stamp)
        ctx.put("companies", .object(fields))
      }
    }
    let currency = company.awStr("currency")
    let amount = awMajor(abs(figures.net), precision)
    var messageVars = vars
    messageVars["amount"] = AwBooks.activityMoney(amount, currency, company["locale"]?.string)
    ctx.logActivity(
      entity: "vat_return", entityId: id, action: "filed",
      message: ActivityMessage(
        figures.net >= 0
          ? "VAT return {start} to {end} filed: {amount} to pay" : "VAT return {start} to {end} filed: {amount} to reclaim",
        vars: messageVars, money: ["amount": (amount: amount, currency: currency)]))
    return record
  }

  /// `undoVatReturn(id)`: removes the filing and its entries. The period must be unlocked.
  public static func undo(_ ctx: WriteContext, id: String, tr: I18n.Translator = .english) throws {
    guard let record = ctx.get("vatReturns", id), let company = ctx.get("companies", record.awStr("companyId")) else {
      return
    }
    let ids = [record.awText("journalId"), record.awText("paymentJournalId")].compactMap { $0 }
    let journals = ids.compactMap { ctx.get("journals", $0) }
    do {
      try AwBooks.assertUnlocked(company, [record["periodEnd"]?.string] + journals.map { $0["date"]?.string }, tr)
    } catch {
      throw WriteFailure(
        "This period is locked. Remove or move the lock date (Settings → Accounting) to undo the return.")
    }
    for journal in journals { ctx.delete("journals", journal.awId) }
    ctx.delete("vatReturns", id)
    ctx.logActivity(
      entity: "vat_return", entityId: id, action: "deleted",
      message: ActivityMessage(
        "VAT return {start} to {end} undone",
        vars: ["start": record.awStr("periodStart"), "end": record.awStr("periodEnd")]))
  }

  /// `recordVatPayment(id, { date, accountId })`: paying the VAT (or
  /// receiving the refund) clears the VAT liability.
  @discardableResult
  public static func recordPayment(
    _ ctx: WriteContext, id: String, date: String, accountId: String, tr: I18n.Translator = .english
  ) throws -> JSONValue {
    guard let record = ctx.get("vatReturns", id) else { throw WriteFailure("Return not found.") }
    if let paid = record.awText("paymentJournalId"), ctx.get("journals", paid) != nil {
      throw WriteFailure("The payment for this return is already recorded.")
    }
    let accounts = AwBooks.records(ctx, "accounts", record.awStr("companyId"))
    guard let settlement = AwBooks.roleMap(accounts)["tax_settlement"] else {
      throw WriteFailure("The chart of accounts has no VAT liability account.")
    }
    let precision = Money.precision(record.awStr("currency"))
    let net = Int(record.awNum("net"))
    let amount = awMajor(abs(net), precision)
    if amount == 0 { throw WriteFailure("There is nothing to pay for this return.") }
    let pay = net > 0
    let vars = ["start": record.awStr("periodStart"), "end": record.awStr("periodEnd")]
    let first = AwJournals.newLine(
      ctx,
      ["accountId": .string(settlement), "debit": .number(pay ? amount : 0), "credit": .number(pay ? 0 : amount)])
    let second = AwJournals.newLine(
      ctx,
      ["accountId": .string(accountId), "debit": .number(pay ? 0 : amount), "credit": .number(pay ? amount : 0)])
    let journal = try AwJournals.save(
      ctx,
      AwJournals.create(
        ctx, companyId: record.awStr("companyId"),
        [
          "date": .string(date),
          "reference": .string(pay ? tr.t("VAT payment {start} to {end}", vars) : tr.t("VAT refund {start} to {end}", vars)),
          "status": .string("posted"), "lines": .array([first, second]),
        ]), tr: tr)
    var fields = record.awFields
    fields["paymentJournalId"] = .string(journal.awId)
    fields["updatedAt"] = .string(ctx.stamp)
    let updated = JSONValue.object(fields)
    ctx.put("vatReturns", updated)
    return updated
  }
}
