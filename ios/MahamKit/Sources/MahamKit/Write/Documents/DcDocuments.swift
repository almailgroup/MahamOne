import Foundation

/// A counter to take from the cloud before a write that gives a document its
/// number (the web's `reserveCounter` request): the app asks
/// `SyncEngine.reserveNumber(kind:date:min:)` for it, then passes the
/// answer to the write as `reserved` (nil numbers it on this device).
public struct DcCounterRequest: Sendable, Equatable {
  public var kind: String
  public var date: String
  /// This device's own next counter less one: the one taken is never lower.
  public var min: Int

  public init(kind: String, date: String, min: Int) {
    self.kind = kind
    self.date = date
    self.min = min
  }
}

/// The port of the web's document writes (src/db/documents.ts): drafts,
/// saving (numbers, totals, statuses, what it posts with, retention),
/// statuses, deleting, copies, reissues and conversions, with the web's reads,
/// writes and refusals in the web's order.
public enum DcDocuments {
  /// `{ ...record, ...patch }` (a nil value takes the field away), for the app's forms.
  public static func applying(_ record: JSONValue, _ patch: DcPatch) -> JSONValue {
    DcJS.merge(record, patch)
  }

  // MARK: Words of the activity log

  /// `LOG`: what the log says of each type.
  static func logKey(_ type: String, _ what: String) -> String {
    let noun: String =
      switch type {
      case "quote": "Quote"
      case "credit": "Credit note"
      case "bill": "Bill"
      case "vendor_credit": "Vendor credit"
      case "proforma": "Proforma invoice"
      case "sales_order": "Sales order"
      case "purchase_order": "Purchase order"
      case "delivery_note": "Delivery note"
      default: "Invoice"
      }
    return "\(noun) {number} \(what)"
  }

  /// `logText(doc, what)`: by its number or, without one, as a draft.
  static func logText(_ doc: JSONValue, _ what: String) -> ActivityMessage {
    let type = doc.dcText("type")
    let number = doc.dcText("number")
    if WebJS.trim(number).isEmpty, type == "invoice" || type == "credit" {
      let noun = type == "invoice" ? "invoice" : "credit note"
      return ActivityMessage("Draft \(noun) \(what)", vars: ["number": number])
    }
    return ActivityMessage(logKey(type, what), vars: ["number": number])
  }

  /// `statusMessage(doc, status)`.
  static func statusMessage(_ doc: JSONValue, _ status: String) -> ActivityMessage {
    let vars = ["number": doc.dcText("number")]
    let was = doc.dcText("status")
    if was == "void" || was == "cancelled" { return ActivityMessage("{number} restored", vars: vars) }
    let type = doc.dcText("type")
    if status == "sent" && (type == "bill" || type == "vendor_credit") {
      return ActivityMessage("{number} marked as open", vars: vars)
    }
    let text: String =
      switch status {
      case "sent": "{number} marked as sent"
      case "accepted": "{number} marked as accepted"
      case "declined": "{number} marked as declined"
      case "void": "{number} voided"
      case "confirmed": "{number} confirmed"
      case "issued": "{number} issued"
      case "delivered": "{number} marked as delivered"
      case "cancelled": "{number} cancelled"
      case "draft": "{number} moved back to draft"
      default: "{number} updated"
      }
    return ActivityMessage(text, vars: vars)
  }

  static func refs(_ doc: JSONValue, document: Bool = true) -> ActivityRefs {
    ActivityRefs(clientId: doc.dcNonEmpty("clientId"), documentId: document ? doc.dcId : nil)
  }

  // MARK: Drafts

  /// `defaultTaxes(company)`: the company's default rates, not archived.
  public static func defaultTaxes(_ ctx: WriteContext, _ company: JSONValue) -> [JSONValue] {
    let ids = company["defaults"]?["defaultTaxRateIds"]?.array ?? []
    return ids.compactMap { id -> JSONValue? in
      guard let id = id.string, let rate = ctx.get("taxRates", id), !WebJS.truthy(rate["archived"]) else { return nil }
      return DcCalc.taxLineOf(rate)
    }
  }

  /// `defaultWording(company, type)`: the company's notes and terms of a type.
  public static func defaultWording(_ company: JSONValue, _ type: String) -> (notes: JSONValue?, terms: JSONValue?) {
    let d = company["defaults"]
    switch type {
    case "invoice": return (d?["invoiceNotes"], d?["invoiceTerms"])
    case "quote": return (d?["quoteNotes"], d?["quoteTerms"])
    case "credit": return (d?["creditNotes"], d?["creditTerms"])
    default: return (.string(""), .string(""))
    }
  }

  /// `carriedWording(company, source, type)`: what was written for the source
  /// carries over; the old type's default wording becomes the new type's.
  public static func carriedWording(_ company: JSONValue, _ source: JSONValue, _ type: String) -> DcPatch {
    let before = defaultWording(company, source.dcText("type"))
    let after = defaultWording(company, type)
    func keep(_ value: JSONValue?, _ standard: JSONValue?, _ fallback: JSONValue?) -> JSONValue? {
      let text = WebJS.trim(value?.string ?? "")
      return !text.isEmpty && text != WebJS.trim(standard?.string ?? "") ? value : fallback
    }
    return [
      ("notes", keep(source["notes"], before.notes, after.notes)),
      ("terms", keep(source["terms"], before.terms, after.terms)),
    ]
  }

  /// `createDocument(companyId, type, overrides)`: a new draft, dated today.
  static func createDocument(_ ctx: WriteContext, companyId: String, type: String, _ overrides: DcPatch) -> JSONValue {
    let stamp = JSONValue.string(ctx.stamp)
    var fields: [String: JSONValue] = [
      "id": .string(ctx.newId()), "companyId": .string(companyId), "type": .string(type), "number": "",
      "status": "draft", "clientId": "", "issueDate": .string(ctx.today), "dueDate": .null, "poNumber": "",
      "currency": "KWD", "items": [], "discount": 0, "discountType": "percent", "taxes": [], "charges": [],
      "pricesIncludeTax": false, "deposit": 0, "depositDueDate": .null, "notes": "", "terms": "", "footer": "",
      "privateNotes": "", "templateId": .null, "totals": Defaults.emptyTotals(), "sentAt": .null, "paidAt": .null,
      "sourceId": .null, "convertedToId": .null, "recurringId": .null, "archived": false, "createdAt": stamp,
      "updatedAt": stamp,
    ]
    DcJS.apply(&fields, overrides)
    return .object(fields)
  }

  /// `newLineItem(taxes)`: an empty line.
  public static func newLineItem(_ ctx: WriteContext, taxes: [JSONValue] = []) -> JSONValue {
    newLine(id: ctx.shortId(), taxes: taxes)
  }

  /// An empty line with this id (`newLineItem`).
  public static func newLine(id: String, taxes: [JSONValue] = []) -> JSONValue {
    .object([
      "id": .string(id), "kind": "item", "productId": .null, "name": "", "description": "", "quantity": 1,
      "unit": "", "unitPrice": 0, "discount": 0, "discountType": "percent", "taxes": .array(taxes),
    ])
  }

  /// `newHeading()`: a section heading.
  public static func newHeading(id: String) -> JSONValue {
    DcJS.merge(newLine(id: id), [("kind", JSONValue.string("heading")), ("quantity", JSONValue.number(0))])
  }

  /// `draftDocument(company, type, client)`: a new, unsaved document from the
  /// company's (and the contact's) defaults.
  public static func draftDocument(_ ctx: WriteContext, company: JSONValue, type: String, client: JSONValue?)
    -> JSONValue
  {
    let issueDate = ctx.today
    let d = company["defaults"]
    let terms = DcJS.orElse(client?["paymentTermsDays"], d?["paymentTermsDays"])
    let taxes = defaultTaxes(ctx, company)
    let wording = defaultWording(company, type)
    let priced = type != "delivery_note"
    var dueDate: JSONValue = .null
    if type == "invoice" || type == "bill" {
      dueDate = .string(ISODates.addDays(issueDate, days(terms)))
    } else if type == "quote" || type == "proforma" {
      dueDate = .string(ISODates.addDays(issueDate, days(d?["quoteValidDays"])))
    }
    var patch = DcRules.retentionDefaults(client, type: type, issueDate: issueDate)
    patch += [
      ("clientId", client?["id"] ?? .string("")),
      ("issueDate", .string(issueDate)),
      ("dueDate", dueDate),
      ("deliveryDate", type == "delivery_note" ? JSONValue.string(issueDate) : JSONValue.null),
      ("currency", DcJS.orText(client?["currency"], company["currency"])),
      ("taxes", .array(WebJS.truthy(d?["documentTaxes"]) && priced ? taxes : [])),
      ("notes", wording.notes),
      ("terms", wording.terms),
    ]
    if type == "quote", let intro = d?["quoteIntro"]?.string, !WebJS.trim(intro).isEmpty {
      patch.append(("intro", .string(intro)))
    }
    patch += [
      ("footer", type == "bill" || type == "vendor_credit" ? JSONValue.string("") : d?["footer"]),
      ("pricesIncludeTax", DcRules.isPurchaseType(type) ? JSONValue.bool(false) : d?["pricesIncludeTax"]),
    ]
    // The line's id is taken before the document's, as the web makes them.
    let line = newLineItem(ctx, taxes: WebJS.truthy(d?["lineTaxes"]) && priced ? taxes : [])
    patch.append(("items", .array([line])))
    return createDocument(ctx, companyId: company.dcId, type: type, patch)
  }

  /// A number of days as `addDays` takes it (fractions cut).
  static func days(_ value: JSONValue?) -> Int {
    guard let n = value?.double, n.isFinite else { return 0 }
    return Int(n.rounded(.towardZero))
  }

  // MARK: Payments and totals

  /// `paidAmount(doc)`: paid (invoices, bills) or applied (credit notes,
  /// vendor credits) so far; void payments don't count.
  public static func paidAmount(_ ctx: WriteContext, _ doc: JSONValue) -> Double {
    let id = doc.dcId
    let type = doc.dcText("type")
    if type == "invoice" || type == "bill" {
      let payments = ctx.all("payments") { p in
        p.dcList("documentIds").contains(.string(id)) && !WebJS.truthy(p["voided"])
      }
      return payments.reduce(0.0) { sum, p in
        sum
          + p.dcList("allocations").filter { $0["documentId"] == .string(id) }.reduce(0.0) { s, a in
            s + (a["amount"]?.double ?? 0)
          }
      }
    }
    if type == "credit" || type == "vendor_credit" {
      let uses = ctx.all("payments") { p in p["creditId"] == .string(id) && !WebJS.truthy(p["voided"]) }
      return uses.reduce(0.0) { sum, p in sum + (p["amount"]?.double ?? 0) }
    }
    return 0
  }

  /// `applyTotals(doc, paid, client)`: the cached totals and the status
  /// payments move it to.
  public static func applyTotals(_ ctx: WriteContext, _ doc: JSONValue, paid: Double, client: JSONValue?) -> JSONValue {
    let result = DcCalc.computeDocument(
      doc, paid: paid, taxExempt: DcCalc.documentTaxExempt(doc, contact: client))
    var totals: [String: JSONValue] = [
      "subtotal": .number(result.subtotal), "discount": .number(result.discount),
      "taxTotal": .number(result.taxTotal), "total": .number(result.total), "paid": .number(result.paid),
      "balance": .number(result.balance),
    ]
    if result.retention != 0 { totals["retention"] = .number(result.retention) }
    let type = doc.dcText("type")
    var status = doc["status"] ?? .null
    if DcRules.postsToLedger(type) && doc["status"] != .string("void") {
      let due = DcJS.round(Money.dec(result.total) - Money.dec(result.retentionHeld), DcJS.precision(of: doc))
      status = .string(
        DcRules.settledStatus(type: type, status: doc.dcText("status"), total: due, paid: result.paid))
    }
    let settled = status == .string("paid") || status == .string("applied")
    var fields = WebJS.spread(doc)
    fields["totals"] = .object(totals)
    fields["status"] = status
    fields["paidAt"] = settled ? (WebJS.present(doc["paidAt"]) ?? .string(ctx.stamp)) : .null
    if status != .string("draft") && !WebJS.truthy(doc["sentAt"]) {
      fields["sentAt"] = .string(ctx.stamp)
    } else {
      fields["sentAt"] = doc["sentAt"]
    }
    return .object(fields)
  }

  /// `recalculateDocuments(ids)`: their totals and statuses again, their
  /// `updatedAt` kept.
  public static func recalculateDocuments(_ ctx: WriteContext, _ ids: [String]) {
    for id in DcJS.unique(ids) {
      guard let doc = ctx.get("documents", id) else { continue }
      let client = doc.dcNonEmpty("clientId").flatMap { ctx.get("clients", $0) }
      let updated = applyTotals(ctx, doc, paid: paidAmount(ctx, doc), client: client)
      ctx.put("documents", DcJS.merge(updated, [("updatedAt", doc["updatedAt"])]))
    }
  }

  // MARK: Orders

  /// `documentsCreatedFrom(id)`.
  public static func documentsCreatedFrom(_ ctx: WriteContext, _ id: String) -> [JSONValue] {
    ctx.all("documents") { $0["sourceId"] == .string(id) }
  }

  /// `relatedForProgress(doc)`: what an order's (or invoice's) progress is
  /// worked out from.
  public static func relatedForProgress(_ ctx: WriteContext, _ doc: JSONValue) -> [JSONValue] {
    let direct = documentsCreatedFrom(ctx, doc.dcId)
    if doc.dcText("type") != "sales_order" { return direct }
    let invoiceIds = Set(direct.filter { $0.dcText("type") == "invoice" }.map(\.dcId))
    if invoiceIds.isEmpty { return direct }
    let notes = ctx.all("documents") { d in
      guard let source = d["sourceId"]?.string else { return false }
      return invoiceIds.contains(source) && d.dcText("type") == "delivery_note"
    }
    return direct + notes
  }

  /// `refreshOrder(id)`: an order's stored status and delivery progress brought up to date.
  static func refreshOrder(_ ctx: WriteContext, _ id: String?) {
    guard let id, !id.isEmpty, let order = ctx.get("documents", id) else { return }
    let type = order.dcText("type")
    guard type == "sales_order" || type == "purchase_order" else { return }
    let progress = DcProgress.lineProgress(order, relatedForProgress(ctx, order))
    var fields = WebJS.spread(order)
    fields["status"] = .string(DcProgress.orderStatus(type: type, status: order.dcText("status"), progress))
    if type == "sales_order" { fields["deliveryStatus"] = .string(DcProgress.deliveryStatusOf(progress)) }
    if fields["status"] != order["status"] || fields["deliveryStatus"] != order["deliveryStatus"] {
      ctx.put("documents", .object(fields))
    }
  }

  /// `refreshOrdersOf(doc)`: the order itself, the one it was made from and,
  /// for a delivery note of an invoice, the invoice's order.
  static func refreshOrdersOf(_ ctx: WriteContext, _ doc: JSONValue) {
    refreshOrder(ctx, doc.dcId)
    guard let sourceId = doc.dcNonEmpty("sourceId") else { return }
    refreshOrder(ctx, sourceId)
    if doc.dcText("type") == "delivery_note", let source = ctx.get("documents", sourceId),
      source.dcText("type") == "invoice"
    {
      refreshOrder(ctx, source["sourceId"]?.string)
    }
  }

  /// `refreshOrdersFor(ids)`: the orders that depend on these documents.
  public static func refreshOrdersFor(_ ctx: WriteContext, _ ids: [String]) {
    for id in DcJS.unique(ids) {
      if let doc = ctx.get("documents", id) { refreshOrdersOf(ctx, doc) }
    }
  }

  // MARK: Numbers

  /// `takenNumbers(companyId, type, exceptId)`: in lower case, trimmed.
  static func takenNumbers(_ ctx: WriteContext, companyId: String, type: String, except: String?) -> Set<String> {
    Set(
      ctx.all("documents") { d in
        d["companyId"] == .string(companyId) && d["type"] == .string(type) && (except == nil || d.dcId != except)
      }.map { WebJS.trim($0.dcText("number")).lowercased() })
  }

  static func sameNumber(_ a: String, _ b: String) -> Bool {
    WebJS.trim(a).lowercased() == WebJS.trim(b).lowercased()
  }

  /// `isNumberTaken(companyId, type, number, exceptId)`: another document of
  /// this kind has the number (a document keeps the number it was saved with).
  public static func isNumberTaken(
    _ ctx: WriteContext, companyId: String, type: String, number: String, except: String? = nil
  ) -> Bool {
    if let except, let own = ctx.get("documents", except), own.dcText("type") == type,
      sameNumber(own.dcText("number"), number)
    {
      return false
    }
    return takenNumbers(ctx, companyId: companyId, type: type, except: except)
      .contains(WebJS.trim(number).lowercased())
  }

  /// `suggestNumber(company, type, issueDate, clientNumber)`: the next number, to show before saving.
  public static func suggestNumber(
    _ ctx: WriteContext, company: JSONValue, type: String, issueDate: String, clientNumber: String = ""
  ) -> String {
    let taken = takenNumbers(ctx, companyId: company.dcId, type: type, except: nil)
    return Numbering.allocateNumber(DcRules.rule(company, type), issueDate, clientNumber: clientNumber) {
      taken.contains($0.lowercased())
    }.number
  }

  /// `reserveFor(company, input)`: what to ask the cloud's counter for; none
  /// when saving is going to be refused for the locked period.
  static func reservation(_ ctx: WriteContext, company: JSONValue, type: String, status: String, issueDate: String, id: String?)
    -> DcCounterRequest?
  {
    if DcRules.isPosted(type: type, status: status) {
      do { try DcBooks.assertUnlocked(company, issueDate) } catch { return nil }
    }
    let taken = takenNumbers(ctx, companyId: company.dcId, type: type, except: id)
    let local = Numbering.allocateNumber(DcRules.rule(company, type), issueDate) { taken.contains($0.lowercased()) }
    return DcCounterRequest(kind: type, date: issueDate, min: Int(local.rule.next) - 1)
  }

  /// `reserveDocumentCounter(input)`: the counter a document without a number
  /// takes from the cloud as it is saved, or nil to number it here (a draft
  /// that waits for its number, or one saved again).
  public static func counterRequest(_ ctx: WriteContext, _ input: JSONValue) -> DcCounterRequest? {
    if !WebJS.trim(input.dcText("number")).isEmpty { return nil }
    let existing = ctx.get("documents", input.dcId)
    guard let company = ctx.get("companies", input.dcText("companyId")) else { return nil }
    if DcRules.waitsForNumber(company: company, input) { return nil }
    if let existing,
      !WebJS.trim(existing.dcText("number")).isEmpty || !DcRules.waitsForNumber(company: company, existing)
    {
      return nil
    }
    return reservation(
      ctx, company: company, type: input.dcText("type"), status: input.dcText("status"),
      issueDate: input.dcText("issueDate"), id: input.dcId)
  }

  /// `reserveIssueCounter(id, status)`: the counter a document without a
  /// number takes as it is issued.
  public static func issueCounterRequest(_ ctx: WriteContext, id: String, status: String) -> DcCounterRequest? {
    if status == "draft" { return nil }
    guard let doc = ctx.get("documents", id), WebJS.trim(doc.dcText("number")).isEmpty,
      let company = ctx.get("companies", doc.dcText("companyId"))
    else { return nil }
    return reservation(
      ctx, company: company, type: doc.dcText("type"), status: status, issueDate: doc.dcText("issueDate"), id: id)
  }

  /// The counter a new draft of `type`, dated today, takes as it is saved
  /// (duplicating, converting, reissuing, making from an order).
  public static func newDraftCounterRequest(_ ctx: WriteContext, companyId: String, type: String) -> DcCounterRequest? {
    guard let company = ctx.get("companies", companyId) else { return nil }
    if DcRules.waitsForNumber(company: company, type: type, status: "draft") { return nil }
    return reservation(ctx, company: company, type: type, status: "draft", issueDate: ctx.today, id: nil)
  }

  /// `giveNumber(company, doc, client, reserved)`: the next number of its
  /// kind, and the company's counter moved on. Returns the company as saved.
  @discardableResult
  static func giveNumber(
    _ ctx: WriteContext, _ company: JSONValue, _ doc: inout [String: JSONValue], client: JSONValue?,
    reserved: ReservedCounter?
  ) -> JSONValue {
    let type = doc["type"]?.string ?? ""
    let taken = takenNumbers(ctx, companyId: company.dcId, type: type, except: doc["id"]?.string)
    let allocated = Numbering.allocateFrom(
      DcRules.rule(company, type), doc["issueDate"]?.string ?? "",
      clientNumber: WebJS.present(client?["number"])?.string ?? "", reserved: reserved
    ) { taken.contains($0.lowercased()) }
    doc["number"] = .string(allocated.number)
    var numbering = WebJS.spread(company["numbering"])
    numbering[type] = allocated.rule.raw
    let saved = DcJS.merge(company, [("numbering", .object(numbering))])
    ctx.put("companies", saved)
    return saved
  }

  // MARK: Saving

  /// `withRetention(doc, existing)`: only invoices and bills hold one back,
  /// and releases are only ever recorded by the retention module.
  static func withRetention(_ doc: JSONValue, existing: JSONValue?) -> JSONValue {
    var fields = WebJS.spread(doc)
    fields["retentionReleases"] = existing?["retentionReleases"]
    if !DcCalc.takesRetention(doc["type"]?.string) {
      fields["retentionPercent"] = nil
      fields["retentionKind"] = nil
    }
    if (fields["retentionReleases"]?.array ?? []).isEmpty { fields["retentionReleases"] = nil }
    return .object(fields)
  }

  /// `assertCurrencyKept(existing, next)`.
  static func assertCurrencyKept(_ ctx: WriteContext, _ existing: JSONValue?, _ next: JSONValue) throws {
    guard let existing, existing["currency"] != next["currency"] else { return }
    let id = existing.dcId
    let payments = ctx.all("payments")
    let count =
      payments.filter { $0.dcList("documentIds").contains(.string(id)) }.count
      + payments.filter { $0["creditId"] == .string(id) }.count
    if count > 0 {
      throw WriteFailure(
        "Payments or credits are recorded on {number}, so its currency can’t change.",
        ["number": existing.dcText("number")])
    }
  }

  static func assetLabel(_ asset: JSONValue) -> String {
    WebJS.trim("\(asset.dcText("number")) \(asset.dcText("name"))")
  }

  /// `assetsFromBill(doc)`: assets in the register made from lines of a bill.
  static func assetsFromBill(_ ctx: WriteContext, _ doc: JSONValue) -> [JSONValue] {
    guard doc.dcText("type") == "bill" else { return [] }
    let companyId = doc.dcText("companyId")
    let id = doc.dcId
    return ctx.all("assets") { a in
      a["companyId"] == .string(companyId) && a["billId"] == .string(id) && a["status"] != .string("void")
    }
  }

  /// `assertNoAssets(doc)`.
  static func assertNoAssets(_ ctx: WriteContext, _ doc: JSONValue) throws {
    if let asset = assetsFromBill(ctx, doc).first {
      throw WriteFailure(
        "Asset {asset} was made from this bill. Void the asset first.", ["asset": assetLabel(asset)])
    }
  }

  /// `assertAssetLinesKept(company, existing, next, accounts)`.
  static func assertAssetLinesKept(
    _ ctx: WriteContext, _ company: JSONValue, _ existing: JSONValue, _ next: JSONValue, accounts: [JSONValue]
  ) throws {
    let assets = assetsFromBill(ctx, existing)
    if assets.isEmpty { return }
    if !DcRules.isPosted(next) { try assertNoAssets(ctx, existing) }
    let p = Money.precision(company.dcText("currency"))
    let before = DcBooks.billAssetLines(company, existing, accounts: accounts)
    let after = DcBooks.billAssetLines(company, next, accounts: accounts)
    for asset in assets {
      let lineId = asset.dcText("billLineId")
      guard let was = before.first(where: { $0.lineId == lineId }) else { continue }
      let now = after.first { $0.lineId == lineId }
      let same = now.map { $0.accountId == was.accountId && Money.toMinor($0.cost, p) == Money.toMinor(was.cost, p) }
      if same != true {
        throw WriteFailure(
          "Asset {asset} was made from line “{line}” of this bill, so the line can’t change. Void the asset first.",
          ["asset": assetLabel(asset), "line": was.lineName])
      }
    }
  }

  /// `saveDocument(input)`: a number when it has none, the totals, the
  /// company's counter; the orders it belongs to brought up to date. Returns
  /// the stored document. `reserved` is the cloud's counter for its number
  /// (`counterRequest`), `link` the person's link to the company.
  @discardableResult
  public static func saveDocument(
    _ ctx: WriteContext, _ input: JSONValue, reserved: ReservedCounter? = nil, link: DcLink? = nil
  ) throws -> JSONValue {
    guard let company = ctx.get("companies", input.dcText("companyId")) else {
      throw WriteFailure("Company not found")
    }
    let existing = ctx.get("documents", input.dcId)
    if DcRules.isPosted(input) || existing.map({ DcRules.isPosted($0) }) == true {
      try DcBooks.assertUnlocked(company, input["issueDate"]?.string, existing?["issueDate"]?.string)
    }
    let client = input.dcNonEmpty("clientId").flatMap { ctx.get("clients", $0) }
    var doc = withRetention(
      DcJS.merge(input, [("number", .string(WebJS.trim(input.dcText("number"))))]), existing: existing)
    try assertCurrencyKept(ctx, existing, doc)
    // What it posts with is fixed when it is issued and kept through edits.
    doc = DcBooks.withPosting(ctx, doc, client: client, existing: existing)
    if let existing, existing.dcText("type") == "bill" {
      let accounts = ctx.all("accounts") { $0["companyId"] == .string(company.dcId) }
      try assertAssetLinesKept(ctx, company, existing, doc, accounts: accounts)
    }

    let number = doc.dcText("number")
    let taken = takenNumbers(ctx, companyId: company.dcId, type: doc.dcText("type"), except: doc.dcId)
    if number.isEmpty {
      // A draft numbered when it is issued keeps none until then.
      if !DcRules.waitsForNumber(company: company, doc) {
        var fields = WebJS.spread(doc)
        giveNumber(ctx, company, &fields, client: client, reserved: reserved)
        doc = .object(fields)
      }
    } else if taken.contains(number.lowercased()),
      // Saved again with the number it has: never refused.
      !(existing.map { $0["type"] == doc["type"] && sameNumber($0.dcText("number"), number) } ?? false)
    {
      throw WriteFailure("The number {number} is already used by another document.", ["number": number])
    }

    doc = applyTotals(ctx, doc, paid: existing.map { paidAmount(ctx, $0) } ?? 0, client: client)
    let retention = doc["totals"]?["retention"]
    if Money.dec(DcCalc.releasedRetention(doc)) > DcJS.dec(WebJS.present(retention) ?? .number(0)) {
      throw WriteFailure("More retention has been released than this document would hold. Undo a release first.")
    }
    if DcRules.isPosted(doc) && WebJS.truthy(retention) {
      // Held-back money waits in 1110 Retentions receivable (2010 payable).
      DcBooks.ensureSpecAccount(
        ctx, company, doc.dcText("type") == "bill" ? DcBooks.retentionsPayable : DcBooks.retentionsReceivable)
    }
    // An issued invoice the company's rules keep for approvers: sent for approval instead.
    if let existing { try DcApprovals.assertApproved(company, link, before: existing, after: doc) }
    var fields = WebJS.spread(doc)
    fields["updatedAt"] = .string(ctx.stamp)
    if existing == nil { fields["createdAt"] = fields["updatedAt"] }
    doc = .object(fields)
    ctx.put("documents", doc)
    try InventoryWrites.syncDocumentStock(ctx, documentId: doc.dcId)

    let what = existing == nil ? "created" : "updated"
    ctx.logActivity(
      entity: doc.dcText("type"), entityId: doc.dcId, action: what, message: logText(doc, what), refs: refs(doc))
    refreshOrdersOf(ctx, doc)
    return ctx.get("documents", doc.dcId) ?? doc
  }

  // MARK: Statuses

  /// Money paid against a document stays on its payments as unapplied credit (`freePayments`).
  static func freePayments(_ ctx: WriteContext, _ id: String) {
    let payments = ctx.all("payments") { $0.dcList("documentIds").contains(.string(id)) }
    for payment in payments {
      let allocations = payment.dcList("allocations").filter { $0["documentId"] != .string(id) }
      ctx.put(
        "payments",
        DcJS.merge(
          payment,
          [
            ("allocations", .array(allocations)),
            ("documentIds", .array(allocations.map { $0["documentId"] ?? .null })),
          ]))
    }
  }

  /// `takeOffCredits(doc, company)`: the credit notes applied to a document
  /// leaving the books taken off it, or, for a credit, its own applications.
  /// Returns the other documents to recalculate.
  static func takeOffCredits(_ ctx: WriteContext, _ doc: JSONValue, company: JSONValue) throws -> [String] {
    let type = doc.dcText("type")
    let credit = type == "credit" || type == "vendor_credit"
    if !credit && type != "invoice" && type != "bill" { return [] }
    let id = doc.dcId
    let applications = ctx.all("payments") { p in
      (credit ? p["creditId"] == .string(id) : p.dcList("documentIds").contains(.string(id)))
        && p["method"] == .string("credit_note")
    }
    var touched: [String] = []
    for application in applications {
      var ids = application.dcList("documentIds").compactMap(\.string)
      if let creditId = application.dcNonEmpty("creditId") { ids.append(creditId) }
      let related = ids.compactMap { ctx.get("documents", $0) }
      if related.contains(where: { $0["currency"] != company["currency"] }) {
        try DcBooks.assertUnlocked(company, application["date"]?.string)
      }
      touched += ids
      let rest = credit ? [] : application.dcList("allocations").filter { $0["documentId"] != .string(id) }
      if rest.isEmpty {
        ctx.delete("payments", application.dcId)
        for file in ctx.all("attachments", where: { $0["ownerId"] == .string(application.dcId) }) {
          ctx.delete("attachments", file.dcId)
        }
        ctx.logActivity(
          entity: "payment", entityId: application.dcId, action: "deleted",
          message: ActivityMessage("Payment {number} deleted", vars: ["number": application.dcText("number")]),
          refs: ActivityRefs(clientId: application.dcNonEmpty("clientId")))
        continue
      }
      var removed = Decimal(0)
      for allocation in application.dcList("allocations") where allocation["documentId"] == .string(id) {
        removed += DcJS.dec(allocation["amount"])
      }
      ctx.put(
        "payments",
        DcJS.merge(
          application,
          [
            ("amount", .number(DcJS.round(DcJS.dec(application["amount"]) - removed, Money.precision(application.dcText("currency"))))),
            ("allocations", .array(rest)),
            ("documentIds", .array(rest.map { $0["documentId"] ?? .null })),
            ("updatedAt", .string(ctx.stamp)),
          ]))
    }
    return DcJS.unique(touched).filter { $0 != id }
  }

  /// `setDocumentStatus(id, status, message, patch, { freePaid })`: a new
  /// status, with `patch` stored with it (who signed a delivery note, why it
  /// was voided). With `freePaid`, the money paid against a voided document
  /// stays as the customer's unapplied credit. `reserved`: the cloud's counter
  /// for a draft that gets its number now (`issueCounterRequest`).
  public static func setDocumentStatus(
    _ ctx: WriteContext, id: String, status: String, message: ActivityMessage? = nil, patch: DcPatch = [],
    freePaid: Bool = false, reserved: ReservedCounter? = nil, link: DcLink? = nil
  ) throws {
    guard let doc = ctx.get("documents", id) else { return }
    var company = ctx.get("companies", doc.dcText("companyId"))
    let type = doc.dcText("type")
    let wasStatus = doc.dcText("status")
    let posted = DcRules.isPosted(type: type, status: status)
    if let company, DcRules.isPosted(doc) != posted {
      try DcBooks.assertUnlocked(company, doc["issueDate"]?.string)
    }
    if DcRules.hasActiveReleases(doc) && !posted {
      throw WriteFailure("Undo the retention releases on this document first.")
    }
    var fields = WebJS.spread(doc)
    DcJS.apply(&fields, patch)
    fields["status"] = .string(status)
    fields["updatedAt"] = .string(ctx.stamp)
    if status == "void" && wasStatus != "void" {
      // Who voided it and when: once corrections go by a new number, or a reason is given.
      if DcApprovals.correctsByNewNumber(company) || patch.contains(where: { $0.0 == "voidReason" && $0.1 != nil }) {
        fields["voidedAt"] = .string(ctx.stamp)
        fields["voidedBy"] = link.map { JSONValue.string($0.userId) } ?? JSONValue.null
      }
    } else if wasStatus == "void" && status != "void" {
      if fields["voidedAt"] != nil { fields["voidedAt"] = .null }
      if fields["voidedBy"] != nil { fields["voidedBy"] = .null }
      fields["voidReason"] = nil
    }
    var next = JSONValue.object(fields)
    // An issued invoice the company's rules keep for approvers: sent for approval instead.
    try DcApprovals.assertApproved(company, link, before: doc, after: next)
    // Issued now: a draft that waited for its number gets it.
    if let current = company, status != "draft", WebJS.trim(next.dcText("number")).isEmpty {
      let client = doc.dcNonEmpty("clientId").flatMap { ctx.get("clients", $0) }
      var numbered = WebJS.spread(next)
      company = giveNumber(ctx, current, &numbered, client: client, reserved: reserved)
      next = .object(numbered)
    }
    // Leaving the books: assets made from it are refused, credits applied to (or from) it are taken off.
    let leaving = DcRules.isPosted(doc) && !posted
    if leaving { try assertNoAssets(ctx, doc) }
    var credited: [String] = []
    if leaving, let company { credited = try takeOffCredits(ctx, doc, company: company) }
    // Voided under the company's rules: money paid against it becomes the customer's unapplied credit.
    if status == "void" && wasStatus != "void", let company {
      if freePaid || (link != nil && Roles.rulesCoverDocument(Roles.approvalRulesOf(company), doc["type"])) {
        freePayments(ctx, id)
      }
    }
    if status == DcRules.issuedStatus(type) && !WebJS.truthy(doc["sentAt"]) {
      next = DcJS.merge(next, [("sentAt", .string(ctx.stamp))])
    }
    if DcRules.postsToLedger(type) && status != "void" && status != "draft" {
      // Let payments decide between sent, partial and paid.
      let client = doc.dcNonEmpty("clientId").flatMap { ctx.get("clients", $0) }
      // Issued now: what it posts with is fixed from now on.
      if !DcRules.isPosted(doc) { next = DcBooks.withPosting(ctx, next, client: client, existing: nil) }
      next = applyTotals(ctx, DcJS.merge(next, [("status", "sent")]), paid: paidAmount(ctx, doc), client: client)
    } else if leaving {
      // Voided or back to draft: its totals follow what is still applied to it; the status stays as asked.
      let client = doc.dcNonEmpty("clientId").flatMap { ctx.get("clients", $0) }
      let totals = applyTotals(ctx, next, paid: paidAmount(ctx, doc), client: client)["totals"] ?? .null
      next = DcJS.merge(next, [("totals", totals), ("paidAt", .null)])
    }
    if let company, DcRules.isPosted(next), WebJS.truthy(next["totals"]?["retention"]) {
      DcBooks.ensureSpecAccount(
        ctx, company, next.dcText("type") == "bill" ? DcBooks.retentionsPayable : DcBooks.retentionsReceivable)
    }
    ctx.put("documents", next)
    // The credit is free again, and what it was applied to is owed again.
    recalculateDocuments(ctx, credited)
    try InventoryWrites.syncDocumentStock(ctx, documentId: id)
    let logged = DcJS.merge(doc, [("number", next["number"])])
    ctx.logActivity(
      entity: type, entityId: id, action: "status:\(status)", message: message ?? statusMessage(logged, status),
      refs: refs(doc))
    // A confirmed order picks up the invoices already made from it.
    refreshOrdersOf(ctx, next)
  }

  /// `markSent(id)`: a draft taken out of the office (sent, open, confirmed or issued).
  public static func markSent(_ ctx: WriteContext, id: String, reserved: ReservedCounter? = nil, link: DcLink? = nil)
    throws
  {
    guard let doc = ctx.get("documents", id), doc["status"] == .string("draft") else { return }
    if let status = DcRules.issuedStatus(doc.dcText("type")) {
      try setDocumentStatus(ctx, id: id, status: status, reserved: reserved, link: link)
    }
  }

  // MARK: Deleting

  /// `deleteDocument(id)`: payments keep their money as unapplied credit,
  /// credits applied are taken off, and what it came from or replaced is
  /// opened again. Under the company's rules an issued document is voided
  /// instead (or, for anyone but an approver, asked to be).
  public static func deleteDocument(_ ctx: WriteContext, id: String, link: DcLink? = nil) throws {
    guard let doc = ctx.get("documents", id) else { return }
    let company = ctx.get("companies", doc.dcText("companyId"))
    if DcApprovals.voidsInsteadOfDeleting(company, link, doc) {
      if !DcApprovals.approverOf(link) {
        throw DcApprovalRequired(kind: "invoice_void", subject: doc, proposal: DcJS.merge(doc, [("status", "void")]))
      }
      throw WriteFailure(
        "{number} is issued, so it is voided instead of deleted: its number stays used.",
        ["number": doc.dcText("number")])
    }
    if let company, DcRules.isPosted(doc) { try DcBooks.assertUnlocked(company, doc["issueDate"]?.string) }
    if DcRules.hasActiveReleases(doc) { throw WriteFailure("Undo the retention releases on this document first.") }
    try assertNoAssets(ctx, doc)
    for file in ctx.all("attachments", where: { $0["ownerId"] == .string(id) }) {
      ctx.delete("attachments", file.dcId)
    }
    let credited = try company.map { try takeOffCredits(ctx, doc, company: $0) } ?? []
    freePayments(ctx, id)
    recalculateDocuments(ctx, credited)
    // Documents created from this one lose the link.
    for made in documentsCreatedFrom(ctx, id) {
      ctx.put("documents", DcJS.merge(made, [("sourceId", .null)]))
    }
    // The void document it was to replace can be issued again.
    if let replacesId = doc.dcNonEmpty("replacesId"), let replaced = ctx.get("documents", replacesId),
      replaced["replacedById"] == .string(id)
    {
      ctx.put("documents", DcJS.merge(replaced, [("replacedById", .null), ("updatedAt", .string(ctx.stamp))]))
    }
    // A quote or proforma converted into this document can be converted again.
    if let sourceId = doc.dcNonEmpty("sourceId"), let source = ctx.get("documents", sourceId),
      source["convertedToId"] == .string(id)
    {
      let reopened = source["status"] == .string("invoiced") || source["status"] == .string("converted")
      ctx.put(
        "documents",
        DcJS.merge(
          source, [("convertedToId", JSONValue.null), ("status", reopened ? JSONValue.string("accepted") : source["status"])]))
    }
    ctx.delete("documents", id)
    try InventoryWrites.syncDocumentStock(ctx, documentId: id)
    ctx.logActivity(
      entity: doc.dcText("type"), entityId: id, action: "deleted", message: logText(doc, "deleted"),
      refs: refs(doc, document: false))
    refreshOrdersOf(ctx, doc)
  }

  // MARK: Copies

  /// `duplicateDocument(id, asType, overrides)`: a copy as a new draft (new
  /// number, today's date), saved. Returns it.
  @discardableResult
  public static func duplicateDocument(
    _ ctx: WriteContext, id: String, asType: String? = nil, overrides: DcPatch = [], reserved: ReservedCounter? = nil,
    link: DcLink? = nil
  ) throws -> JSONValue {
    guard let source = ctx.get("documents", id) else { throw WriteFailure("Document not found") }
    guard let company = ctx.get("companies", source.dcText("companyId")) else {
      throw WriteFailure("Company not found")
    }
    let sourceType = source.dcText("type")
    let type = asType ?? sourceType
    let client = source.dcNonEmpty("clientId").flatMap { ctx.get("clients", $0) }
    let fresh = draftDocument(ctx, company: company, type: type, client: client)
    // A copy is a document of its own: it does not count towards an order.
    let items = source.dcList("items").map { DcJS.merge($0, [("id", .string(ctx.shortId())), ("sourceLineId", nil)]) }
    let charges = source.dcList("charges").map { DcJS.merge($0, [("id", .string(ctx.shortId()))]) }
    let same = type == sourceType
    var patch: DcPatch = [
      ("clientId", source["clientId"]),
      ("currency", source["currency"]),
      // A credit note of a dollar invoice is booked at the invoice's rate.
      ("exchangeRate", source["exchangeRate"]),
      ("poNumber", source["poNumber"]),
      ("items", .array(items)),
      ("discount", source["discount"]),
      ("discountType", source["discountType"]),
      ("taxes", source["taxes"]),
      ("charges", .array(charges)),
      ("pricesIncludeTax", source["pricesIncludeTax"]),
      ("notes", same ? source["notes"] : fresh["notes"]),
      ("terms", same ? source["terms"] : fresh["terms"]),
      ("footer", source["footer"]),
      ("privateNotes", source["privateNotes"]),
      ("templateId", source["templateId"]),
    ]
    if WebJS.truthy(source["accentColor"]) { patch.append(("accentColor", source["accentColor"])) }
    // A copy of a quote keeps its introduction; another type of document has none.
    if same { patch.append(("intro", source["intro"])) }
    patch += [
      // Credit notes don't print where the goods went.
      ("deliveryPlace", type == "credit" || type == "vendor_credit" ? JSONValue.string("") : (WebJS.present(source["deliveryPlace"]) ?? JSONValue.string(""))),
      ("totals", Defaults.emptyTotals()),
    ]
    patch += overrides
    return try saveDocument(ctx, DcJS.merge(fresh, patch), reserved: reserved, link: link)
  }

  /// `reissueDocument(id)`: a new draft in place of a void invoice or credit
  /// note, printing "Replaces …", linked both ways. Returns the new draft.
  @discardableResult
  public static func reissueDocument(
    _ ctx: WriteContext, id: String, reserved: ReservedCounter? = nil, link: DcLink? = nil
  ) throws -> JSONValue {
    guard let source = ctx.get("documents", id) else { throw WriteFailure("Document not found") }
    if source["status"] != .string("void") { throw WriteFailure("Only a void document is issued again.") }
    if let replacedBy = source.dcNonEmpty("replacedById"), ctx.get("documents", replacedBy) != nil {
      throw WriteFailure("{number} has already been issued again.", ["number": source.dcText("number")])
    }
    let copy = try duplicateDocument(
      ctx, id: id, asType: source.dcText("type"),
      overrides: [
        ("replacesId", .string(source.dcId)),
        ("replacesNumber", source["number"]),
        // The credit note of an invoice keeps pointing at that invoice.
        ("sourceId", source["sourceId"]),
        ("issueDate", .string(ctx.today)),
      ], reserved: reserved, link: link)
    if let current = ctx.get("documents", id) {
      ctx.put("documents", DcJS.merge(current, [("replacedById", .string(copy.dcId)), ("updatedAt", .string(ctx.stamp))]))
    }
    return copy
  }

  /// `CONVERSIONS`: what each type turns into, one to one.
  public static func conversions(_ type: String) -> [String] {
    switch type {
    case "quote": ["invoice", "proforma", "sales_order"]
    case "proforma": ["invoice"]
    default: []
    }
  }

  /// `convertDocument(sourceId, to)`: a quote into an invoice, proforma or
  /// sales order, or a proforma into an invoice; both point at each other.
  @discardableResult
  public static func convertDocument(
    _ ctx: WriteContext, sourceId: String, to: String, reserved: ReservedCounter? = nil, link: DcLink? = nil
  ) throws -> JSONValue {
    guard let source = ctx.get("documents", sourceId), conversions(source.dcText("type")).contains(to) else {
      throw WriteFailure("Document not found")
    }
    guard let company = ctx.get("companies", source.dcText("companyId")) else {
      throw WriteFailure("Company not found")
    }
    let deposit = to == "invoice" || to == "proforma"
    var overrides: DcPatch = [("sourceId", .string(source.dcId))]
    overrides += carriedWording(company, source, to)
    overrides += [
      ("exchangeRate", source["exchangeRate"]),
      ("deposit", deposit ? source["deposit"] : JSONValue.number(0)),
      ("depositDueDate", deposit ? source["depositDueDate"] : JSONValue.null),
      ("deliveryDate", WebJS.present(source["deliveryDate"]) ?? JSONValue.null),
    ]
    let linked = try duplicateDocument(ctx, id: sourceId, asType: to, overrides: overrides, reserved: reserved, link: link)
    if let current = ctx.get("documents", source.dcId) {
      let status = source.dcText("type") == "quote" && to == "invoice" ? "invoiced" : "converted"
      ctx.put(
        "documents",
        DcJS.merge(
          current,
          [("status", .string(status)), ("convertedToId", .string(linked.dcId)), ("updatedAt", .string(ctx.stamp))]))
    }
    let target = linked.dcText("number")
    let message: ActivityMessage
    if !WebJS.trim(target).isEmpty {
      let text: String =
        switch to {
        case "proforma": "{number} converted to proforma invoice {target}"
        case "sales_order": "{number} converted to sales order {target}"
        default: "{number} converted to invoice {target}"
        }
      message = ActivityMessage(text, vars: ["number": source.dcText("number"), "target": target])
    } else {
      // A draft invoice numbered when it is issued has no number yet.
      message = ActivityMessage("{number} converted to a draft invoice", vars: ["number": source.dcText("number")])
    }
    ctx.logActivity(
      entity: source.dcText("type"), entityId: source.dcId, action: "converted", message: message, refs: refs(source))
    return linked
  }
}
