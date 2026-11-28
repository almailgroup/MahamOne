import Foundation

/// The port of the web's order writes (src/db/orders.ts): invoices, bills
/// and delivery notes made from orders and invoices, in parts, and delivery
/// notes signed for.
public enum DcOrders {
  /// `partTargets(doc)`: sales orders are invoiced and delivered, purchase
  /// orders billed, invoices delivered.
  public static func partTargets(_ type: String) -> [String] {
    switch type {
    case "sales_order": ["invoice", "delivery_note"]
    case "purchase_order": ["bill"]
    case "invoice": ["delivery_note"]
    default: []
    }
  }

  /// `remainingOf(progress, target)`: what of a line is still to go on the target.
  public static func remainingOf(_ progress: DcLineProgress, _ target: String) -> Double {
    target == "delivery_note" ? progress.toDeliver : progress.toInvoice
  }

  /// `progressOf(doc)`: each line's progress. An invoice made from a sales
  /// order offers no more for delivery than the order still has to deliver.
  public static func progressOf(_ ctx: WriteContext, _ doc: JSONValue) -> [DcLineProgress] {
    let progress = DcProgress.lineProgress(doc, DcDocuments.relatedForProgress(ctx, doc))
    guard doc.dcText("type") == "invoice", let sourceId = doc.dcNonEmpty("sourceId"),
      let order = ctx.get("documents", sourceId), order.dcText("type") == "sales_order"
    else { return progress }
    var orderLines: [String: DcLineProgress] = [:]
    for line in progressOf(ctx, order) { orderLines[line.line.dcId] = line }
    return progress.map { p in
      guard let sourceLine = p.line.dcNonEmpty("sourceLineId"), let ordered = orderLines[sourceLine] else { return p }
      var limited = p
      limited.toDeliver = min(p.toDeliver, ordered.toDeliver)
      return limited
    }
  }

  /// `createFromOrder(sourceId, target, quantities)`: an invoice or delivery
  /// note from a sales order, a bill from a purchase order, or a delivery
  /// note from an invoice; `quantities` (by line id) chooses how much of each
  /// line, by default everything left. Returns the saved document. `reserved`
  /// is the cloud's counter for its number (`DcDocuments.newDraftCounterRequest`).
  @discardableResult
  public static func createFromOrder(
    _ ctx: WriteContext, sourceId: String, target: String, quantities: [String: Double]? = nil,
    reserved: ReservedCounter? = nil, link: DcLink? = nil
  ) throws -> JSONValue {
    guard var source = ctx.get("documents", sourceId), partTargets(source.dcText("type")).contains(target) else {
      throw WriteFailure("Document not found")
    }
    let status = source.dcText("status")
    if status == "cancelled" || status == "void" { throw WriteFailure("This document is cancelled.") }
    // Invoicing or delivering a draft order confirms it.
    if status == "draft", let issued = DcRules.issuedStatus(source.dcText("type")), source.dcText("type") != "invoice" {
      try DcDocuments.setDocumentStatus(ctx, id: source.dcId, status: issued, link: link)
      source = ctx.get("documents", source.dcId) ?? source
    }
    guard let company = ctx.get("companies", source.dcText("companyId")) else {
      throw WriteFailure("Company not found")
    }
    let client = source.dcNonEmpty("clientId").flatMap { ctx.get("clients", $0) }

    let related = DcDocuments.relatedForProgress(ctx, source)
    let progress = progressOf(ctx, source)
    var chosen: [String: Double] = [:]
    for p in progress {
      let left = remainingOf(p, target)
      let wanted = quantities.map { $0[p.line.dcId] ?? 0 } ?? left
      chosen[p.line.dcId] = min(max(0, wanted), left)
    }
    let items = DcProgress.copyLines(source.dcList("items"), chosen) { ctx.shortId() }
    if !items.contains(where: { $0["kind"] == .string("item") }) {
      let number = ["number": source.dcText("number")]
      switch target {
      case "delivery_note": throw WriteFailure("Everything on {number} is already on a delivery note.", number)
      case "bill": throw WriteFailure("Everything on {number} is already billed.", number)
      default: throw WriteFailure("Everything on {number} is already invoiced.", number)
      }
    }

    let type = target
    let fresh = DcDocuments.draftDocument(ctx, company: company, type: type, client: client)
    let earlier = related.filter { d in
      d.dcText("type") == type && d["sourceId"] == .string(source.dcId) && d["status"] != .string("void")
    }
    let completes = progress.allSatisfy { (chosen[$0.line.dcId] ?? 0) >= remainingOf($0, target) }
    let priced = target != "delivery_note"
    let wording: DcPatch =
      target == "bill"
      ? [("notes", JSONValue.string("")), ("terms", JSONValue.string(""))]
      : DcDocuments.carriedWording(company, source, type)
    // Shipping and other charges go on the first invoice or bill only.
    let charges: [JSONValue] =
      priced && earlier.isEmpty ? source.dcList("charges").map { DcJS.merge($0, [("id", .string(ctx.shortId()))]) } : []
    var patch: DcPatch = [
      ("clientId", source["clientId"]),
      ("currency", source["currency"]),
      ("exchangeRate", source["exchangeRate"]),
      // A bill refers to our purchase order; invoices keep the customer's PO number.
      ("poNumber", source.dcText("type") == "purchase_order" ? source["number"] : source["poNumber"]),
      ("items", .array(items)),
      ("discount", priced ? DcProgress.partDiscount(source, lines: items, earlier: earlier, completes: completes) : JSONValue.number(0)),
      ("discountType", source["discountType"]),
      ("taxes", priced ? source["taxes"] : JSONValue.array([])),
      ("charges", .array(charges)),
      ("pricesIncludeTax", source["pricesIncludeTax"]),
    ]
    patch += wording
    patch += [
      ("privateNotes", source["privateNotes"]),
      ("templateId", target == "bill" ? JSONValue.null : source["templateId"]),
    ]
    if target != "bill" && WebJS.truthy(source["accentColor"]) { patch.append(("accentColor", source["accentColor"])) }
    patch += [
      ("deliveryDate", target == "delivery_note" ? fresh["deliveryDate"] : (WebJS.present(source["deliveryDate"]) ?? JSONValue.null)),
      ("deliveryPlace", WebJS.present(source["deliveryPlace"]) ?? JSONValue.string("")),
      ("sourceId", .string(source.dcId)),
    ]
    let saved = try DcDocuments.saveDocument(ctx, DcJS.merge(fresh, patch), reserved: reserved, link: link)
    let text: String =
      switch target {
      case "bill": "Bill {number} created from {source}"
      case "delivery_note": "Delivery note {number} created from {source}"
      default: "Invoice {number} created from {source}"
      }
    ctx.logActivity(
      entity: source.dcText("type"), entityId: source.dcId, action: "converted",
      message: ActivityMessage(text, vars: ["number": saved.dcText("number"), "source": source.dcText("number")]),
      refs: DcDocuments.refs(source))
    return saved
  }

  /// `markDelivered(id, { date, receiverName, receiverCivilId })`: the goods
  /// of a delivery note handed over, and who signed for them.
  public static func markDelivered(
    _ ctx: WriteContext, id: String, date: String, receiverName rawName: String, receiverCivilId: String? = nil,
    link: DcLink? = nil
  ) throws {
    guard let doc = ctx.get("documents", id), doc.dcText("type") == "delivery_note" else {
      throw WriteFailure("Document not found")
    }
    let receiverName = WebJS.trim(rawName)
    let civilId = WebJS.removing(receiverCivilId ?? "") { WebJS.isSpace($0) }
    let message: ActivityMessage? =
      receiverName.isEmpty
      ? nil
      : ActivityMessage(
        "{number} delivered and received by {name}", vars: ["number": doc.dcText("number"), "name": receiverName])
    try DcDocuments.setDocumentStatus(
      ctx, id: id, status: "delivered", message: message,
      patch: [
        ("deliveryDate", .string(date)), ("receiverName", .string(receiverName)),
        ("receiverCivilId", .string(civilId)),
      ], link: link)
  }
}
