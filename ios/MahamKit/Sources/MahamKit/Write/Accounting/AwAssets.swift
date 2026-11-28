import Foundation

/// A line of a posted bill booked to a fixed asset account (`BillAssetLine`).
public struct AwBillAssetLine: Sendable {
  public let bill: JSONValue
  public let line: JSONValue
  /// The fixed or non-current asset account the line was booked to.
  public let accountId: String
  /// The line's value without tax, after the bill's discount, in the company currency.
  public let cost: Double
  /// The asset already made from the line.
  public let assetId: String?
}

/// What selling or scrapping an asset on a date would post, in minor units (`DisposalPreview`).
public struct AwDisposalPreview: Sendable, Equatable {
  public let depreciation: Int
  public let accumulated: Int
  public let cost: Int
  public let bookValue: Int
  public let proceeds: Int
  /// Positive gain, negative loss.
  public let gain: Int
}

/// The port of the web's fixed asset register (src/db/assets.ts): assets
/// post through system journals (the purchase or opening balance, monthly
/// depreciation runs, disposals), and nothing posted is deleted: it is
/// reversed.
public enum AwAssets {
  // MARK: Figures

  /// `createAsset(companyId, overrides)` for a form: a new id, dated today.
  public static func blank(
    companyId: String, overrides: [String: JSONValue] = [:], today: String, now: Date = Date(), id: String = newId()
  ) -> JSONValue {
    let stamp = Defaults.nowStamp(now)
    let base: [String: JSONValue] = [
      "id": .string(id), "companyId": .string(companyId), "number": .string(""), "name": .string(""),
      "description": .string(""), "assetAccountId": .string(""), "accumulatedAccountId": .string(""),
      "expenseAccountId": .string(""), "purchaseDate": .string(today), "depreciationStart": .string(today),
      "cost": .number(0), "salvageValue": .number(0), "usefulLifeMonths": .number(60),
      "method": .string("straight_line"), "decliningRate": .null, "openingDepreciation": .number(0),
      "openingDepreciationDate": .null, "source": .string("purchase"), "billId": .null, "billLineId": .null,
      "vendorId": .null, "paidFromAccountId": .null, "journalId": .null, "location": .string(""),
      "custodian": .string(""), "serialNumber": .string(""), "notes": .string(""), "status": .string("active"),
      "disposal": .null, "createdAt": .string(stamp), "updatedAt": .string(stamp),
    ]
    return .object(base.merging(overrides) { _, new in new })
  }

  /// `activeRuns(runs)`: runs that were not undone.
  public static func activeRuns(_ runs: [JSONValue]) -> [JSONValue] {
    runs.filter { !$0.awTruthy("reversedAt") }
  }

  /// `postedDepreciation(asset, runs, precision, upTo)`: what was charged
  /// before it was entered, every run not undone, and the depreciation up to
  /// its disposal (minor units).
  public static func postedDepreciation(_ asset: JSONValue, _ runs: [JSONValue], _ p: Int, upTo: String? = nil) -> Int {
    var total = awMinor(asset.awNum("openingDepreciation"), p)
    let id = asset.awId
    for run in activeRuns(runs) {
      if let upTo, WebJS.less(upTo, run.awStr("date")) { continue }
      for line in run.awList("lines") where line.awStr("assetId") == id {
        total += awMinor(line.awNum("amount"), p)
      }
    }
    if let disposal = WebJS.present(asset["disposal"]),
      upTo == nil || !WebJS.less(upTo ?? "", disposal.awStr("date"))
    {
      total += awMinor(disposal.awNum("depreciation"), p)
    }
    return total
  }

  /// `lastDepreciationDate(asset, runs)`: the last run that charged the asset.
  public static func lastDepreciationDate(_ asset: JSONValue, _ runs: [JSONValue]) -> String? {
    var last: String?
    let id = asset.awId
    for run in activeRuns(runs) {
      let charged = run.awList("lines").contains { $0.awStr("assetId") == id && awNotZero($0["amount"]) }
      if charged, last == nil || WebJS.less(last ?? "", run.awStr("date")) { last = run.awStr("date") }
    }
    return last
  }

  /// `depreciationDue(assets, runs, date)`: what each asset in use still needs
  /// up to `date` (minor units), by number.
  public static func depreciationDue(_ assets: [JSONValue], _ runs: [JSONValue], _ date: String, _ p: Int)
    -> [(asset: JSONValue, amount: Int)]
  {
    let due = assets.filter {
      $0.awStr("status") == "active" && !WebJS.less(date, $0.awStr("depreciationStart"))
    }.map { asset in
      (
        asset: asset,
        amount: AwDepreciation.accumulatedAt(AwDepreciationTerms(asset), date, p) - postedDepreciation(asset, runs, p)
      )
    }.filter { $0.amount > 0 }
    let ordered = due.enumerated().sorted { a, b in
      if AwText.numericLess(a.element.asset.awStr("number"), b.element.asset.awStr("number")) { return true }
      if AwText.numericLess(b.element.asset.awStr("number"), a.element.asset.awStr("number")) { return false }
      return a.offset < b.offset
    }
    return ordered.map { $0.element }
  }

  /// `suggestedPeriod(runs, now)`: the month after the last run, or the
  /// month before this one when nothing ran yet.
  public static func suggestedPeriod(_ runs: [JSONValue], today: String) -> String {
    let done = activeRuns(runs).map { $0.awStr("period") }
    let current = AwDepreciation.periodOf(today)
    guard let last = done.max(by: WebJS.less) else { return AwDepreciation.shiftPeriod(current, -1) }
    let next = AwDepreciation.shiftPeriod(last, 1)
    return WebJS.less(current, next) ? current : next
  }

  /// `assetLabel(asset)`: "FA-0001 Laptops".
  static func label(_ asset: JSONValue) -> String {
    WebJS.trim("\(asset.awStr("number")) \(asset.awStr("name"))")
  }

  // MARK: Bills

  /// The line amounts, subtotal and discount `computeDocument` gives a bill.
  private static func lineNets(_ doc: JSONValue) -> (nets: [Decimal], subtotal: Decimal, discount: Decimal) {
    let currency = doc.awText("currency") ?? "KWD"
    let p = max(0, min(6, Money.precision(currency)))
    var nets: [Decimal] = []
    for item in doc.awList("items") {
      if item.awStr("kind") == "heading" {
        nets.append(0)
        continue
      }
      let gross = Money.dec(item.awNum("quantity")) * Money.dec(item.awNum("unitPrice"))
      let value = Money.dec(item.awNum("discount"))
      let percent = (WebJS.present(item["discountType"])?.string ?? "percent") == "percent"
      nets.append(Money.round(gross - (percent ? gross * value / 100 : value), p))
    }
    let subtotal = nets.reduce(Decimal(0), +)
    let value = Money.dec(doc.awNum("discount"))
    let percent = (WebJS.present(doc["discountType"])?.string ?? "percent") == "percent"
    let discount = Money.round(percent ? subtotal * value / 100 : value, p)
    return (nets, Money.round(subtotal, p), discount)
  }

  /// `isPosted(doc)`: an invoice, credit note, bill or vendor credit, issued and not void.
  static func isPosted(_ doc: JSONValue) -> Bool {
    let type = doc.awStr("type")
    guard ["invoice", "credit", "bill", "vendor_credit"].contains(type) else { return false }
    let status = doc.awStr("status")
    return status != "draft" && status != "void"
  }

  /// `rateOf(item)`: the company-currency value of one unit of the record's currency.
  static func rateOf(_ item: JSONValue, _ companyCurrency: String) -> Double {
    if item["currency"]?.string == companyCurrency { return 1 }
    if let rate = item["exchangeRate"]?.double, rate.isFinite, rate > 0 { return rate }
    return 1
  }

  /// `billAssetLines(company, bills, accounts, assets)`: lines of posted bills
  /// booked to fixed asset accounts, the purchases an asset can be made
  /// from; the cost leaves out tax and shares the bill's discount.
  public static func billAssetLines(
    company: JSONValue, bills: [JSONValue], accounts: [JSONValue], assets: [JSONValue]
  ) -> [AwBillAssetLine] {
    let p = Money.precision(company.awStr("currency"))
    var byId: [String: JSONValue] = [:]
    for account in accounts { byId[account.awId] = account }
    let fallback = AwBooks.roleMap(accounts)["expense"]
    var linked: [String: String] = [:]
    for asset in assets where asset.awStr("status") != "void" {
      if let line = asset.awText("billLineId") { linked[line] = asset.awId }
    }
    var out: [AwBillAssetLine] = []
    for bill in bills {
      if bill.awStr("type") != "bill" || !isPosted(bill) { continue }
      let result = lineNets(bill)
      let ratio = result.subtotal.isZero ? Decimal(1) : (result.subtotal - result.discount) / result.subtotal
      let rate = Money.dec(rateOf(bill, company.awStr("currency")))
      for (index, line) in bill.awList("items").enumerated() {
        if line.awStr("kind") == "heading" { continue }
        let own = line.awText("accountId").flatMap { byId[$0] != nil ? $0 : nil }
        guard let accountId = own ?? fallback, let account = byId[accountId],
          AwAccountTypes.isFixedAsset(account.awStr("type"))
        else { continue }
        var net = (index < result.nets.count ? result.nets[index] : 0) * ratio
        let charged = (line.awList("taxes") + bill.awList("taxes")).filter { $0.awStr("kind") != "reverse_charge" }
        if bill.awTruthy("pricesIncludeTax"), !charged.isEmpty {
          let sum = charged.reduce(Decimal(0)) { $0 + Money.dec($1.awNum("rate")) }
          net = net / (sum / 100 + 1)
        }
        out.append(
          AwBillAssetLine(
            bill: bill, line: line, accountId: account.awId, cost: awRound(net * rate, p),
            assetId: linked[line.awStr("id")]))
      }
    }
    // Newest bill first; the order of lines stays.
    return out.enumerated().sorted { a, b in
      let x = a.element.bill.awStr("issueDate")
      let y = b.element.bill.awStr("issueDate")
      if x != y { return WebJS.less(y, x) }
      return a.offset < b.offset
    }.map { $0.element }
  }

  // MARK: Saving

  static let financialFields = [
    "assetAccountId", "accumulatedAccountId", "expenseAccountId", "purchaseDate", "depreciationStart", "cost",
    "salvageValue", "usefulLifeMonths", "method", "decliningRate", "openingDepreciation", "openingDepreciationDate",
    "source", "billId", "billLineId", "paidFromAccountId",
  ]

  /// `financialChange(before, after)`: the figures depreciation depends on differ.
  static func financialChange(_ before: JSONValue, _ after: JSONValue) -> Bool {
    financialFields.contains { field in
      WebJS.json(WebJS.present(before[field]) ?? .null) != WebJS.json(WebJS.present(after[field]) ?? .null)
    }
  }

  private static func isWholeNumber(_ value: JSONValue?) -> Bool {
    guard case .number(let number)? = value else { return false }
    return number.isFinite && number.rounded(.towardZero) == number
  }

  /// `validate(asset, accounts, precision)`.
  static func validate(_ asset: JSONValue, _ accounts: [String: JSONValue], _ p: Int) throws {
    if WebJS.trim(asset.awStr("name")).isEmpty { throw WriteFailure("Enter a name for the asset.") }
    guard let category = accounts[asset.awStr("assetAccountId")], AwAccountTypes.isFixedAsset(category.awStr("type"))
    else { throw WriteFailure("Choose the fixed asset account the asset is kept in.") }
    guard let accumulated = accounts[asset.awStr("accumulatedAccountId")],
      AwAccountTypes.group(accumulated.awStr("type")) == "asset"
    else { throw WriteFailure("Choose the accumulated depreciation account.") }
    if accumulated.awId == category.awId { throw WriteFailure("Use a separate account for accumulated depreciation.") }
    guard let expense = accounts[asset.awStr("expenseAccountId")], AwAccountTypes.group(expense.awStr("type")) == "expense"
    else { throw WriteFailure("Choose the depreciation expense account.") }
    let purchaseDate = asset.awStr("purchaseDate")
    let start = asset.awStr("depreciationStart")
    if !ISODates.isISODate(purchaseDate) || !ISODates.isISODate(start) {
      throw WriteFailure("Enter the purchase date and when depreciation starts.")
    }
    if WebJS.less(start, purchaseDate) { throw WriteFailure("Depreciation can’t start before the asset was bought.") }
    let cost = awMinor(asset.awNum("cost"), p)
    if !(cost > 0) { throw WriteFailure("Enter the cost of the asset.") }
    let salvage = awMinor(asset.awNum("salvageValue"), p)
    if salvage < 0 || salvage >= cost { throw WriteFailure("The salvage value must be less than the cost.") }
    if !isWholeNumber(asset["usefulLifeMonths"]) || asset.awNum("usefulLifeMonths") < 1 {
      throw WriteFailure("Enter the useful life in whole months.")
    }
    if asset.awStr("method") == "declining_balance", let rate = WebJS.present(asset["decliningRate"]) {
      let value = rate.double ?? .nan
      if value < 0 || value > 100 { throw WriteFailure("The yearly rate must be between 0% and 100%.") }
    }
    let opening = awMinor(asset.awNum("openingDepreciation"), p)
    if opening < 0 || opening > cost - salvage {
      throw WriteFailure("Depreciation already charged can’t be more than the cost less the salvage value.")
    }
    if opening > 0 {
      if asset.awStr("source") == "purchase" { throw WriteFailure("A new purchase has no depreciation charged yet.") }
      guard let date = asset.awText("openingDepreciationDate"), ISODates.isISODate(date) else {
        throw WriteFailure("Enter the date the depreciation already charged runs to.")
      }
      if WebJS.less(date, start) {
        throw WriteFailure("The depreciation already charged must end after depreciation starts.")
      }
    }
    if asset.awStr("source") == "purchase" {
      let from = asset.awText("paidFromAccountId").flatMap { accounts[$0] }
      guard let from, AwAccountTypes.isMoneyAccount(from.awStr("type")) else {
        throw WriteFailure("Choose the bank, cash or card account the asset was paid from.")
      }
    }
  }

  /// The entry recording the cost (purchase) or the opening balance of an asset (`acquisitionLines`).
  private static func acquisitionLines(_ ctx: WriteContext, _ company: JSONValue, _ asset: JSONValue, _ accounts: [JSONValue])
    throws -> (kind: String, date: String, lines: [JSONValue])?
  {
    let p = Money.precision(company.awStr("currency"))
    let text = JSONValue.string(label(asset))
    let source = asset.awStr("source")
    if source == "purchase" {
      let first = AwJournals.newLine(
        ctx, ["accountId": asset["assetAccountId"], "debit": asset["cost"], "description": text])
      let second = AwJournals.newLine(
        ctx,
        [
          "accountId": WebJS.present(asset["paidFromAccountId"]) ?? .string(""), "credit": asset["cost"],
          "description": text,
        ])
      return ("asset_purchase", asset.awStr("purchaseDate"), [first, second])
    }
    if source == "opening" {
      guard let equity = AwBooks.roleMap(accounts)["opening_balance"] else {
        throw WriteFailure("The chart of accounts has no opening balance account.")
      }
      let opening = awRound(asset.awNum("openingDepreciation"), p)
      let net = awMajor(awMinor(asset.awNum("cost"), p) - awMinor(opening, p), p)
      let openingDate = asset.awText("openingDepreciationDate")
      let date = opening > 0 && openingDate != nil ? openingDate ?? "" : asset.awStr("purchaseDate")
      let lines = [
        AwJournals.newLine(ctx, ["accountId": asset["assetAccountId"], "debit": asset["cost"], "description": text]),
        AwJournals.newLine(
          ctx, ["accountId": asset["accumulatedAccountId"], "credit": .number(opening), "description": text]),
        AwJournals.newLine(ctx, ["accountId": .string(equity), "credit": .number(net), "description": text]),
      ].filter { awNotZero($0["debit"]) || awNotZero($0["credit"]) }
      return ("asset_opening", date, lines)
    }
    return nil
  }

  /// `sameEntry(journal, wanted)`: same kind, date, accounts and amounts.
  private static func sameEntry(
    _ journal: JSONValue, _ wanted: (kind: String, date: String, lines: [JSONValue]), _ p: Int
  ) -> Bool {
    func key(_ lines: [JSONValue]) -> String {
      lines.map { line in
        (line.awStr("accountId"), awMinor(line.awNum("debit"), p), awMinor(line.awNum("credit"), p))
      }.filter { $0.1 != 0 || $0.2 != 0 }.map { "\($0.0)|\($0.1)|\($0.2)" }.sorted(by: WebJS.less).joined(
        separator: "\n")
    }
    return journal.awStr("kind") == wanted.kind && journal.awStr("date") == wanted.date
      && key(journal.awList("lines")) == key(wanted.lines)
  }

  /// `nextNumber(assets)`: the next free asset number, "FA-0007".
  static func nextNumber(_ assets: [JSONValue]) -> String {
    var highest = 0.0
    for asset in assets {
      // /(\d+)\s*$/: the digits at the end, spaces after them allowed.
      var scalars = Array(asset.awStr("number").unicodeScalars)
      while let last = scalars.last, WebJS.isSpace(last) { scalars.removeLast() }
      var digits: [Unicode.Scalar] = []
      while let last = scalars.last, WebJS.isDigit(last) {
        digits.insert(last, at: 0)
        scalars.removeLast()
      }
      let text = String(String.UnicodeScalarView(digits))
      let value = text.isEmpty ? 0 : (Double(text) ?? 0)
      if value.isFinite && value > highest { highest = value }
    }
    return "FA-" + WebJS.padStart(WebJS.numberString(highest + 1), 4)
  }

  /// `saveAsset(input)`: adds or updates an asset. Its figures change only
  /// while nothing is depreciated; the purchase or opening entry follows it.
  @discardableResult
  public static func save(_ ctx: WriteContext, _ input: JSONValue, tr: I18n.Translator = .english) throws -> JSONValue {
    guard let company = ctx.get("companies", input.awStr("companyId")) else { throw WriteFailure("Company not found") }
    let p = Money.precision(company.awStr("currency"))
    let source = input.awStr("source")
    var fields = input.awFields
    fields.removeValue(forKey: "nameAr")
    if let nameAr = input["nameAr"]?.string.map(WebJS.trim), !nameAr.isEmpty { fields["nameAr"] = .string(nameAr) }
    fields["name"] = .string(WebJS.trim(input.awStr("name")))
    fields["number"] = .string(WebJS.trim(input.awStr("number")))
    fields["cost"] = .number(awRound(input.awNum("cost"), p))
    fields["salvageValue"] = .number(awRound(input.awNum("salvageValue"), p))
    fields["openingDepreciation"] = .number(awRound(input.awNum("openingDepreciation"), p))
    fields = awSpread(
      fields,
      [
        "openingDepreciationDate": input.awNum("openingDepreciation") > 0
          ? input["openingDepreciationDate"] : JSONValue.null,
        "decliningRate": input.awStr("method") == "declining_balance"
          ? (WebJS.present(input["decliningRate"]) ?? JSONValue.null) : JSONValue.null,
        "paidFromAccountId": source == "purchase" ? input["paidFromAccountId"] : JSONValue.null,
        "billId": source == "bill" ? input["billId"] : JSONValue.null,
        "billLineId": source == "bill" ? input["billLineId"] : JSONValue.null,
      ])
    let companyId = company.awId
    let accounts = AwBooks.records(ctx, "accounts", companyId)
    let assets = AwBooks.records(ctx, "assets", companyId)
    let runs = AwBooks.records(ctx, "depreciationRuns", companyId)
    let id = input.awId
    let existing = ctx.get("assets", id)
    var accountsById: [String: JSONValue] = [:]
    for account in accounts { accountsById[account.awId] = account }
    try validate(.object(fields), accountsById, p)

    if source == "bill" {
      var found: JSONValue? = nil
      if let billId = fields["billId"]?.string, !billId.isEmpty { found = ctx.get("documents", billId) }
      guard let bill = found, bill.awStr("companyId") == companyId, bill.awStr("type") == "bill", isPosted(bill) else {
        throw WriteFailure("Choose a bill that has been entered (not a draft or void).")
      }
      let lineId = fields["billLineId"] ?? .null
      guard
        let line = billAssetLines(company: company, bills: [bill], accounts: accounts, assets: []).first(where: {
          $0.line["id"] == lineId
        })
      else { throw WriteFailure("Choose the bill line the asset was bought on.") }
      if line.accountId != fields["assetAccountId"]?.string {
        throw WriteFailure("The bill booked this line to another account. Use the same fixed asset account.")
      }
      if let other = assets.first(where: {
        $0.awId != id && $0.awStr("status") != "void" && ($0["billLineId"] ?? .null) == lineId
      }) {
        throw WriteFailure("Asset {number} was already made from this bill line.", ["number": other.awStr("number")])
      }
      fields["vendorId"] = bill.awText("clientId").map(JSONValue.string) ?? .null
    }

    if let existing {
      if existing.awStr("status") == "void" { throw WriteFailure("This asset is void.") }
      if financialChange(existing, .object(fields)) {
        if existing.awStr("status") == "disposed" {
          throw WriteFailure("Undo the disposal before changing the figures of this asset.")
        }
        if lastDepreciationDate(existing, runs) != nil {
          throw WriteFailure(
            "Depreciation has been posted for this asset, so its figures can’t change. Undo the depreciation runs first."
          )
        }
      }
      // Status and disposal are only changed by disposing or voiding.
      fields = awSpread(fields, ["status": existing["status"], "disposal": existing["disposal"]])
    } else {
      fields["status"] = .string("active")
      fields["disposal"] = .null
    }
    let number = fields["number"]?.string ?? ""
    if number.isEmpty {
      fields["number"] = .string(nextNumber(assets))
    } else if assets.contains(where: { $0.awId != id && $0.awStr("number") == number }) {
      throw WriteFailure("Asset number {number} is already used.", ["number": number])
    }

    // Keep the purchase or opening entry in step with the asset. In a locked
    // period an entry whose date, accounts and amounts stay the same is left
    // as it is: only the asset's details changed (name, location, notes…).
    let asset = JSONValue.object(fields)
    let wanted = try acquisitionLines(ctx, company, asset, accounts)
    let current = asset.awText("journalId").flatMap { ctx.get("journals", $0) }
    let lock = AwBooks.lockDate(company)
    var kept = false
    if let wanted, let current, let lock, !WebJS.less(lock, current.awStr("date")) {
      kept = sameEntry(current, wanted, p)
    }
    if kept {
      // The entry already posts what the asset needs.
    } else if let wanted {
      var reuse: JSONValue? = nil
      if let current, current.awStr("kind") == wanted.kind { reuse = current }
      let base = reuse ?? AwJournals.create(ctx, companyId: companyId, ["status": .string("posted")])
      let reference =
        wanted.kind == "asset_purchase"
        ? tr.t("Purchase of {asset}", ["asset": label(asset)])
        : tr.t("Opening balance of {asset}", ["asset": label(asset)])
      let entry = awSpread(
        base.awFields,
        [
          "date": .string(wanted.date), "kind": .string(wanted.kind), "sourceId": .string(id),
          "reference": .string(reference), "status": .string("posted"), "lines": .array(wanted.lines),
        ])
      let journal = try AwJournals.save(ctx, .object(entry), system: true, tr: tr)
      if let current, current.awId != journal.awId { try AwJournals.reverse(ctx, current, tr: tr) }
      fields["journalId"] = .string(journal.awId)
    } else if let current {
      try AwJournals.reverse(ctx, current, tr: tr)
      fields["journalId"] = .null
    }

    let stamp = ctx.stamp
    fields["updatedAt"] = .string(stamp)
    if existing == nil { fields["createdAt"] = .string(stamp) }
    let saved = JSONValue.object(fields)
    ctx.put("assets", saved)
    let savedNumber = saved.awStr("number")
    ctx.logActivity(
      entity: "asset", entityId: id, action: existing != nil ? "updated" : "created",
      message: ActivityMessage(existing != nil ? "Asset {number} updated" : "Asset {number} added", vars: ["number": savedNumber]))
    return saved
  }

  /// `voidAsset(id)`: an asset entered by mistake leaves the register, its
  /// purchase or opening entry reversed. Only before any depreciation.
  public static func voidAsset(_ ctx: WriteContext, id: String, tr: I18n.Translator = .english) throws {
    guard let asset = ctx.get("assets", id), asset.awStr("status") != "void" else { return }
    if asset.awStr("status") == "disposed" { throw WriteFailure("Undo the disposal before voiding the asset.") }
    let runs = AwBooks.records(ctx, "depreciationRuns", asset.awStr("companyId"))
    if lastDepreciationDate(asset, runs) != nil {
      throw WriteFailure("Depreciation has been posted for this asset. Undo those runs first, or dispose of it.")
    }
    var voidJournalId = JSONValue.null
    if let journal = asset.awText("journalId").flatMap({ ctx.get("journals", $0) }) {
      voidJournalId = .string(try AwJournals.reverse(ctx, journal, tr: tr).awId)
    }
    var fields = asset.awFields
    fields["status"] = .string("void")
    fields["voidJournalId"] = voidJournalId
    fields["updatedAt"] = .string(ctx.stamp)
    ctx.put("assets", .object(fields))
    ctx.logActivity(
      entity: "asset", entityId: id, action: "voided",
      message: ActivityMessage("Asset {number} voided", vars: ["number": asset.awStr("number")]))
  }

  // MARK: Disposal

  /// `disposalPreview(asset, runs, input)`: what disposing of it on a date would post.
  public static func disposalPreview(_ asset: JSONValue, _ runs: [JSONValue], date: String, proceeds: Double, _ p: Int)
    -> AwDisposalPreview
  {
    let posted = postedDepreciation(asset, runs, p)
    let target = AwDepreciation.accumulatedAt(AwDepreciationTerms(asset), date, p)
    let depreciation = max(0, target - posted)
    let accumulated = posted + depreciation
    let cost = awMinor(asset.awNum("cost"), p)
    let received = awMinor(proceeds, p)
    return AwDisposalPreview(
      depreciation: depreciation, accumulated: accumulated, cost: cost, bookValue: cost - accumulated,
      proceeds: received, gain: received - (cost - accumulated))
  }

  /// `disposeAsset(id, input)`: sells or scraps an asset in one entry
  /// (depreciation to the day, cost and accumulated depreciation out, the
  /// money received, the gain or loss).
  @discardableResult
  public static func dispose(
    _ ctx: WriteContext, id: String, date: String, proceeds: Double, depositAccountId: String?, notes: String?,
    tr: I18n.Translator = .english
  ) throws -> JSONValue {
    guard let asset = ctx.get("assets", id) else { throw WriteFailure("Asset not found") }
    if asset.awStr("status") != "active" { throw WriteFailure("Only assets in use can be disposed of.") }
    guard let company = ctx.get("companies", asset.awStr("companyId")) else { throw WriteFailure("Company not found") }
    let p = Money.precision(company.awStr("currency"))
    if !ISODates.isISODate(date) { throw WriteFailure("Enter the date of the disposal.") }
    if WebJS.less(date, asset.awStr("purchaseDate")) {
      throw WriteFailure("The asset can’t be disposed of before it was bought.")
    }
    try AwBooks.assertUnlocked(company, [date], tr)
    let runs = AwBooks.records(ctx, "depreciationRuns", company.awId)
    if let last = lastDepreciationDate(asset, runs), WebJS.less(date, last) {
      let format = Format.DateFormat(company["dateFormat"]?.string ?? "dd/MM/yyyy")
      let locale = FormatLocale.interface(tr.language, companyLocale: company["locale"]?.string)
      throw WriteFailure(
        "Depreciation has been posted up to {date}. Choose a later date or undo those runs first.",
        ["date": Format.date(last, format: format, locale: locale)])
    }
    if proceeds < 0 { throw WriteFailure("The sale price can’t be negative.") }
    let accounts = AwBooks.records(ctx, "accounts", company.awId)
    var deposit: JSONValue? = nil
    if let wanted = depositAccountId, !wanted.isEmpty { deposit = accounts.first { $0.awId == wanted } }
    if awMinor(proceeds, p) > 0, deposit.map({ AwAccountTypes.group($0.awStr("type")) == "asset" }) != true {
      throw WriteFailure("Choose the account the money from the sale went into.")
    }

    let preview = disposalPreview(asset, runs, date: date, proceeds: proceeds, p)
    let disposal = AwAccounts.ensureSpec(ctx, company, .disposal)
    let text = JSONValue.string(label(asset))
    let toDate = JSONValue.string(tr.t("Depreciation to {date}", ["date": date]))
    func major(_ minor: Int) -> JSONValue { .number(awMajor(minor, p)) }
    let gainText = preview.gain >= 0 ? tr.t("Gain on disposal") : tr.t("Loss on disposal")
    let candidates = [
      AwJournals.newLine(
        ctx, ["accountId": asset["expenseAccountId"], "debit": major(preview.depreciation), "description": toDate]),
      AwJournals.newLine(
        ctx, ["accountId": asset["accumulatedAccountId"], "credit": major(preview.depreciation), "description": toDate]),
      AwJournals.newLine(
        ctx, ["accountId": asset["accumulatedAccountId"], "debit": major(preview.accumulated), "description": text]),
      AwJournals.newLine(ctx, ["accountId": asset["assetAccountId"], "credit": major(preview.cost), "description": text]),
      AwJournals.newLine(
        ctx, ["accountId": .string(deposit?.awId ?? ""), "debit": major(preview.proceeds), "description": text]),
      AwJournals.newLine(
        ctx,
        [
          "accountId": .string(disposal.awId), "debit": preview.gain < 0 ? major(-preview.gain) : JSONValue.number(0),
          "credit": preview.gain > 0 ? major(preview.gain) : JSONValue.number(0), "description": .string(gainText),
        ]),
    ]
    let lines = candidates.filter { $0.awTruthy("accountId") && (awNotZero($0["debit"]) || awNotZero($0["credit"])) }
    let trimmedNotes = WebJS.trim(notes ?? "")
    let journal = try AwJournals.save(
      ctx,
      AwJournals.create(
        ctx, companyId: company.awId,
        [
          "date": .string(date), "kind": .string("asset_disposal"), "sourceId": .string(asset.awId),
          "reference": .string(tr.t("Disposal of {asset}", ["asset": label(asset)])), "notes": .string(trimmedNotes),
          "status": .string("posted"), "lines": .array(lines),
        ]),
      system: true, tr: tr)
    var fields = asset.awFields
    fields["status"] = .string("disposed")
    fields["disposal"] = .object([
      "date": .string(date), "proceeds": major(preview.proceeds),
      "depositAccountId": deposit.map { JSONValue.string($0.awId) } ?? JSONValue.null, "depreciation": major(preview.depreciation),
      "gain": major(preview.gain), "journalId": .string(journal.awId), "notes": .string(trimmedNotes),
    ])
    fields["updatedAt"] = .string(ctx.stamp)
    let updated = JSONValue.object(fields)
    ctx.put("assets", updated)
    ctx.logActivity(
      entity: "asset", entityId: id, action: "disposed",
      message: ActivityMessage("Asset {number} disposed of", vars: ["number": asset.awStr("number")]))
    return updated
  }

  /// `undoDisposal(id)`: a reversing entry; the asset is in use again.
  public static func undoDisposal(_ ctx: WriteContext, id: String, tr: I18n.Translator = .english) throws {
    guard let asset = ctx.get("assets", id), let disposal = WebJS.present(asset["disposal"]) else { return }
    if let journal = ctx.get("journals", disposal.awStr("journalId")) { try AwJournals.reverse(ctx, journal, tr: tr) }
    var fields = asset.awFields
    fields["status"] = .string("active")
    fields["disposal"] = .null
    fields["updatedAt"] = .string(ctx.stamp)
    ctx.put("assets", .object(fields))
    ctx.logActivity(
      entity: "asset", entityId: id, action: "updated",
      message: ActivityMessage("Disposal of asset {number} undone", vars: ["number": asset.awStr("number")]))
  }

  // MARK: Depreciation runs

  /// `runDepreciation(companyId, period)`: one journal charging every asset
  /// up to the end of a month. A month run again changes nothing (the run
  /// is returned, `created` false); months skipped are caught up; months
  /// are run in order.
  @discardableResult
  public static func runDepreciation(
    _ ctx: WriteContext, companyId: String, period: String, tr: I18n.Translator = .english
  ) throws -> (run: JSONValue?, created: Bool) {
    guard let company = ctx.get("companies", companyId) else { throw WriteFailure("Company not found") }
    let p = Money.precision(company.awStr("currency"))
    let shape = period.unicodeScalars.map { $0 }
    let valid =
      shape.count == 7 && shape[4] == "-" && shape.enumerated().allSatisfy { $0.offset == 4 || WebJS.isDigit($0.element) }
    if !valid { throw WriteFailure("Choose a month.") }
    let date = AwDepreciation.periodEnd(period)
    if WebJS.less(AwDepreciation.periodOf(ctx.today), period) {
      throw WriteFailure("Depreciation can only be run for months that have started.")
    }
    let runs = AwBooks.records(ctx, "depreciationRuns", companyId)
    let active = activeRuns(runs)
    if let same = active.first(where: { $0.awStr("period") == period }) {
      let found: JSONValue? = same
      return (run: found, created: false)
    }
    let later = active.filter { WebJS.less(period, $0.awStr("period")) }.map { $0.awStr("period") }
    if let latest = later.max(by: WebJS.less) {
      throw WriteFailure(
        "Depreciation has already been run for {month}. Undo that run first.",
        ["month": AwBooks.monthLabel(latest, tr)])
    }
    try AwBooks.assertUnlocked(company, [date], tr)
    let assets = AwBooks.records(ctx, "assets", companyId)
    let due = depreciationDue(assets, runs, date, p)
    if due.isEmpty { return (run: nil, created: false) }

    let id = ctx.newId()
    let month = AwBooks.monthLabel(period, tr)
    var lines: [JSONValue] = []
    for item in due {
      let text = JSONValue.string(label(item.asset))
      let amount = JSONValue.number(awMajor(item.amount, p))
      lines.append(
        AwJournals.newLine(ctx, ["accountId": item.asset["expenseAccountId"], "debit": amount, "description": text]))
      lines.append(
        AwJournals.newLine(ctx, ["accountId": item.asset["accumulatedAccountId"], "credit": amount, "description": text]))
    }
    let journal = try AwJournals.save(
      ctx,
      AwJournals.create(
        ctx, companyId: companyId,
        [
          "date": .string(date), "kind": .string("depreciation"), "sourceId": .string(id),
          "reference": .string(tr.t("Depreciation for {month}", ["month": month])), "status": .string("posted"),
          "lines": .array(lines),
        ]),
      system: true, tr: tr)
    let stamp = ctx.stamp
    let runLines: [JSONValue] = due.map { item in
      .object(["assetId": .string(item.asset.awId), "amount": .number(awMajor(item.amount, p))])
    }
    let run: JSONValue = .object([
      "id": .string(id), "companyId": .string(companyId), "period": .string(period), "date": .string(date),
      "journalId": .string(journal.awId), "lines": .array(runLines),
      "total": .number(awMajor(due.reduce(0) { $0 + $1.amount }, p)), "reversalJournalId": .null,
      "reversedAt": .null, "createdAt": .string(stamp), "updatedAt": .string(stamp),
    ])
    ctx.put("depreciationRuns", run)
    ctx.logActivity(
      entity: "asset", entityId: id, action: "depreciation",
      message: ActivityMessage("Depreciation for {month} posted", vars: ["month": month]))
    let made: JSONValue? = run
    return (run: made, created: true)
  }

  /// `reverseDepreciationRun(id)`: undoes the latest run with a reversing entry, so it can be run again.
  public static func reverseRun(_ ctx: WriteContext, id: String, tr: I18n.Translator = .english) throws {
    guard let run = ctx.get("depreciationRuns", id), !run.awTruthy("reversedAt") else { return }
    guard let company = ctx.get("companies", run.awStr("companyId")) else { throw WriteFailure("Company not found") }
    let runs = activeRuns(AwBooks.records(ctx, "depreciationRuns", company.awId))
    if runs.contains(where: { WebJS.less(run.awStr("period"), $0.awStr("period")) }) {
      throw WriteFailure("Undo the later depreciation runs first.")
    }
    let assets = run.awList("lines").compactMap { ctx.get("assets", $0.awStr("assetId")) }
    if let disposed = assets.first(where: { $0.awStr("status") == "disposed" }) {
      throw WriteFailure(
        "Asset {number} has been disposed of since. Undo the disposal first.", ["number": disposed.awStr("number")])
    }
    try AwBooks.assertUnlocked(company, [run["date"]?.string], tr)
    let journal = ctx.get("journals", run.awStr("journalId"))
    let month = AwBooks.monthLabel(run.awStr("period"), tr)
    var reversalId = JSONValue.null
    if let journal {
      let reversal = try AwJournals.reverse(
        ctx, journal, reference: tr.t("Reversal of depreciation for {month}", ["month": month]), tr: tr)
      reversalId = .string(reversal.awId)
    }
    var fields = run.awFields
    fields["reversalJournalId"] = reversalId
    fields["reversedAt"] = .string(ctx.stamp)
    fields["updatedAt"] = .string(ctx.stamp)
    ctx.put("depreciationRuns", .object(fields))
    ctx.logActivity(
      entity: "asset", entityId: id, action: "depreciation_reversed",
      message: ActivityMessage("Depreciation for {month} undone", vars: ["month": month]))
  }
}
