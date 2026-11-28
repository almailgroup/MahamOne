import Foundation

/// What the document ports need of the web's accounting (src/db/accounting.ts,
/// src/db/chart-setup.ts, src/lib/accounting/charts.ts, src/db/posting.ts and
/// the bill lines of src/db/assets.ts): the lock date, the retention
/// accounts, and what an issued document posts with.
public enum DcBooks {
  // MARK: The lock date

  /// `accountingSettings(company).lockDate`: none for a company without accounting settings.
  public static func lockDate(_ company: JSONValue?) -> String? {
    guard let settings = WebJS.present(company?["accounting"]) else { return nil }
    guard let lock = settings["lockDate"]?.string, !lock.isEmpty else { return nil }
    return lock
  }

  /// `accountingSettings(company).template`.
  static func template(_ company: JSONValue) -> String {
    if let settings = WebJS.present(company["accounting"]) { return settings["template"]?.string ?? "" }
    let country = company["address"]?["country"]?.string ?? ""
    if country == "GB" { return "uk" }
    if country == "AE" { return "ae" }
    if country == "KW" || country.isEmpty { return "kw" }
    return "generic"
  }

  /// `LockedPeriodError`: the lock date as the company writes dates.
  static func lockedPeriod(_ lock: String, _ company: JSONValue) -> WriteFailure {
    let format = Format.DateFormat(company["dateFormat"]?.string ?? "dd/MM/yyyy")
    let locale = company["locale"]?.string ?? ""
    let date = Format.date(lock, format: format, locale: FormatLocale(locale.isEmpty ? "en-KW" : locale))
    return WriteFailure(
      "The books are locked up to {date}. Change the lock date in Settings → Accounting to edit earlier transactions.",
      ["date": date])
  }

  /// `assertUnlocked(company, ...dates)`: refused when a date is on or before the lock date.
  public static func assertUnlocked(_ company: JSONValue, _ dates: String?...) throws {
    guard let lock = lockDate(company) else { return }
    for date in dates {
      if let date, !date.isEmpty, date <= lock { throw lockedPeriod(lock, company) }
    }
  }

  // MARK: Accounts

  /// `roleMap(accounts)`: the account of each role, active accounts first.
  static func roleMap(_ accounts: [JSONValue]) -> [String: String] {
    var roles: [String: String] = [:]
    for account in DcJS.activeFirst(accounts) {
      guard let role = account.dcNonEmpty("role"), roles[role] == nil else { continue }
      roles[role] = account.dcId
    }
    return roles
  }

  /// An account the postings look up by code (`AccountSpec`).
  struct Spec: Sendable {
    let code: String
    let name: String
    let nameAr: String
    let type: String
    /// What `match` finds in a name (in lower case).
    let words: [String]

    func matches(_ name: String) -> Bool {
      words.contains { name.contains($0) }
    }
  }

  /// /retentions? (receivable|held by customers)/i
  static let retentionsReceivable = Spec(
    code: "1110", name: "Retentions receivable", nameAr: "محتجزات مدينة", type: "asset_current",
    words: [
      "retention receivable", "retentions receivable", "retention held by customers", "retentions held by customers",
    ])

  /// /retentions? (payable|held from vendors)/i
  static let retentionsPayable = Spec(
    code: "2010", name: "Retentions payable", nameAr: "محتجزات دائنة", type: "liability_current",
    words: ["retention payable", "retentions payable", "retention held from vendors", "retentions held from vendors"])

  /// `findSpecAccount`.
  static func findSpecAccount(_ accounts: [JSONValue], _ spec: Spec, template: String) -> JSONValue? {
    let candidates = DcJS.activeFirst(
      accounts.filter { $0.dcText("type") == spec.type && !WebJS.truthy($0["role"]) })
    if template == "kw", let byCode = candidates.first(where: { $0.dcText("code") == spec.code }) { return byCode }
    if let byName = candidates.first(where: {
      WebJS.trim($0.dcText("name")).lowercased() == spec.name.lowercased()
    }) {
      return byName
    }
    if let byArabic = candidates.first(where: { WebJS.trim($0["nameAr"]?.string ?? "") == spec.nameAr && $0["nameAr"]?.string != nil }) {
      return byArabic
    }
    return candidates.first { spec.matches($0.dcText("name").lowercased()) }
  }

  /// `freeCode`: the spec's code when free, else the next free one after it.
  static func freeCode(_ accounts: [JSONValue], _ wanted: String) -> String {
    let taken = Set(accounts.map { $0.dcText("code") })
    if !taken.contains(wanted) { return wanted }
    guard let base = Int(wanted) else {
      var i = 2
      while taken.contains("\(wanted)-\(i)") { i += 1 }
      return "\(wanted)-\(i)"
    }
    let width = wanted.count
    var next = base + 1
    while taken.contains(WebJS.padStart(String(next), width)) { next += 1 }
    return WebJS.padStart(String(next), width)
  }

  /// `ensureSpecAccount(company, 'retentionsReceivable' | 'retentionsPayable')`:
  /// the account, made (and logged) when the chart doesn't have it.
  @discardableResult
  static func ensureSpecAccount(_ ctx: WriteContext, _ company: JSONValue, _ spec: Spec) -> JSONValue {
    let companyId = company.dcId
    let accounts = ctx.all("accounts") { $0["companyId"] == .string(companyId) }
    if let found = findSpecAccount(accounts, spec, template: template(company)) { return found }
    let stamp = JSONValue.string(ctx.stamp)
    let account: JSONValue = .object([
      "id": .string(ctx.newId()), "companyId": .string(companyId), "code": .string(freeCode(accounts, spec.code)),
      "name": .string(spec.name), "type": .string(spec.type), "description": "", "role": .null, "bank": .null,
      "archived": false, "createdAt": stamp, "updatedAt": stamp, "nameAr": .string(spec.nameAr),
    ])
    ctx.put("accounts", account)
    ctx.logActivity(
      entity: "account", entityId: account.dcId, action: "created",
      message: ActivityMessage(
        "Account {code} {name} created", vars: ["code": account.dcText("code"), "name": spec.name],
        arabic: ["name": spec.nameAr]))
    return account
  }

  // MARK: What an issued document posts with (src/db/posting.ts)

  /// `postingSnapshot(doc, taxExempt, productAccounts)`.
  static func postingSnapshot(_ doc: JSONValue, taxExempt: Bool, productAccounts: [String: JSONValue]) -> JSONValue {
    var accounts: [String: JSONValue] = [:]
    let type = doc.dcText("type")
    if type == "invoice" || type == "credit" {
      for item in doc.dcList("items") {
        guard let productId = item.dcNonEmpty("productId") else { continue }
        guard item["kind"] != .string("heading"), let account = productAccounts[productId], WebJS.truthy(account)
        else { continue }
        accounts[item.dcId] = account
      }
    }
    return .object(["taxExempt": .bool(taxExempt), "accounts": .object(accounts)])
  }

  /// `currentPosting(doc, client)`: the contact and products as they are now.
  static func currentPosting(_ ctx: WriteContext, _ doc: JSONValue, client: JSONValue?) -> JSONValue {
    let ids = DcJS.unique(doc.dcList("items").compactMap { $0.dcNonEmpty("productId") })
    var accounts: [String: JSONValue] = [:]
    for id in ids {
      guard let product = ctx.get("products", id) else { continue }
      accounts[product.dcId] = product["incomeAccountId"] ?? .null
    }
    return postingSnapshot(doc, taxExempt: WebJS.truthy(client?["taxExempt"]), productAccounts: accounts)
  }

  /// `withPosting(doc, client, existing)`: in the books with its snapshot,
  /// otherwise without one; an edit keeps what it was issued with.
  static func withPosting(_ ctx: WriteContext, _ doc: JSONValue, client: JSONValue?, existing: JSONValue?) -> JSONValue {
    if !DcRules.isPosted(doc) { return DcJS.merge(doc, [("posting", nil)]) }
    let fresh = currentPosting(ctx, doc, client: client)
    var before: JSONValue?
    if let existing, DcRules.isPosted(existing), existing["clientId"] == doc["clientId"] {
      before = WebJS.truthy(existing["posting"]) ? existing["posting"] : nil
    }
    guard let before, let existing else { return DcJS.merge(doc, [("posting", fresh)]) }
    var accounts = fresh["accounts"]?.object ?? [:]
    let kept = before["accounts"]?.object ?? [:]
    let earlier = existing.dcList("items")
    for item in doc.dcList("items") {
      guard let was = earlier.first(where: { $0["id"] == item["id"] }), was["productId"] == item["productId"] else {
        continue
      }
      let id = item.dcId
      if let account = kept[id], WebJS.truthy(account) { accounts[id] = account } else { accounts[id] = nil }
    }
    var posting: [String: JSONValue] = ["accounts": .object(accounts)]
    if let taxExempt = before["taxExempt"] { posting["taxExempt"] = taxExempt }
    return DcJS.merge(doc, [("posting", .object(posting))])
  }

  /// `freezeLockedPostings(company, affected)`: issued documents of a closed
  /// period that still follow the settings get the snapshot they post with now.
  static func freezeLockedPostings(_ ctx: WriteContext, _ company: JSONValue, affected: (JSONValue) -> Bool) {
    guard let lock = lockDate(company) else { return }
    let companyId = company.dcId
    let docs = ctx.all("documents") { d in
      d["companyId"] == .string(companyId) && !WebJS.truthy(d["posting"]) && DcRules.isPosted(d)
        && d.dcText("issueDate") <= lock && affected(d)
    }
    if docs.isEmpty { return }
    let exempt = Set(
      ctx.all("clients") { $0["companyId"] == .string(companyId) && WebJS.truthy($0["taxExempt"]) }.map(\.dcId))
    var accounts: [String: JSONValue] = [:]
    for product in ctx.all("products", where: { $0["companyId"] == .string(companyId) }) {
      accounts[product.dcId] = product["incomeAccountId"] ?? .null
    }
    for doc in docs {
      let snapshot = postingSnapshot(
        doc, taxExempt: exempt.contains(doc.dcText("clientId")), productAccounts: accounts)
      ctx.put("documents", DcJS.merge(doc, [("posting", snapshot)]))
    }
  }

  // MARK: Assets made from bills (src/db/assets.ts)

  /// A line of a posted bill booked to a fixed asset account (`BillAssetLine`).
  struct AssetLine {
    let lineId: String
    let lineName: String
    let accountId: String
    let cost: Double
  }

  /// `billAssetLines(company, [bill], accounts, [])`.
  static func billAssetLines(_ company: JSONValue, _ bill: JSONValue, accounts: [JSONValue]) -> [AssetLine] {
    guard bill.dcText("type") == "bill", DcRules.isPosted(bill) else { return [] }
    let p = Money.precision(company.dcText("currency"))
    var byId: [String: JSONValue] = [:]
    for account in accounts { byId[account.dcId] = account }
    let fallback = roleMap(accounts)["expense"]
    let result = DcCalc.computeDocument(bill)
    let ratio =
      result.subtotal == 0
      ? Decimal(1) : (Money.dec(result.subtotal) - Money.dec(result.discount)) / Money.dec(result.subtotal)
    let rate = rateOf(bill, company.dcText("currency"))
    var out: [AssetLine] = []
    for (index, line) in bill.dcList("items").enumerated() where line["kind"] != .string("heading") {
      var accountId = fallback
      if let own = line.dcNonEmpty("accountId"), byId[own] != nil { accountId = own }
      guard let accountId, let account = byId[accountId] else { continue }
      let type = account.dcText("type")
      guard type == "asset_fixed" || type == "asset_non_current" else { continue }
      let lineNet = index < result.lines.count ? result.lines[index].net : 0
      var net = Money.dec(lineNet) * ratio
      let charged = (line.dcList("taxes") + bill.dcList("taxes")).filter { !DcCalc.isReverseCharge($0) }
      if WebJS.truthy(bill["pricesIncludeTax"]) && !charged.isEmpty {
        var sum = Decimal(0)
        for tax in charged { sum += DcJS.dec(tax["rate"]) }
        net = net / (sum / 100 + 1)
      }
      out.append(
        AssetLine(
          lineId: line.dcId, lineName: line.dcText("name"), accountId: account.dcId,
          cost: DcJS.round(net * Money.dec(rate), p)))
    }
    return out
  }

  /// `rateOf(item, { companyCurrency })`.
  static func rateOf(_ record: JSONValue, _ companyCurrency: String) -> Double {
    if record["currency"] == .string(companyCurrency) { return 1 }
    if case .number(let rate)? = record["exchangeRate"], rate.isFinite, rate > 0 { return rate }
    return 1
  }
}
