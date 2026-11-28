import Foundation

/// How far one line of an order (or invoice) has gone (`LineProgress`).
public struct DcLineProgress: Sendable, Equatable {
  public var line: JSONValue
  public var ordered: Double
  /// On invoices (sales orders) or bills (purchase orders) that are not void.
  public var invoiced: Double
  /// On delivery notes marked as delivered.
  public var delivered: Double
  /// On delivery notes not signed for yet.
  public var inDelivery: Double
  /// Still to invoice or bill.
  public var toInvoice: Double
  /// Still to put on a delivery note.
  public var toDeliver: Double
}

/// The web's order rules (src/lib/orders.ts): what of an order has been
/// invoiced, billed and delivered, worked out from the documents made from it.
public enum DcProgress {
  /// `invoiceTypeOf`: invoices for sales orders, bills for purchase orders.
  public static func invoiceTypeOf(_ type: String) -> String {
    type == "purchase_order" ? "bill" : "invoice"
  }

  private struct Done {
    var invoiced = Decimal(0)
    var delivered = Decimal(0)
    var inDelivery = Decimal(0)
  }

  private static func positive(_ value: Decimal) -> Double {
    value < 0 ? 0 : Money.toNumber(value)
  }

  /// `lineProgress(source, related)`: each item line of `source` (a sales
  /// order, purchase order or invoice), from the documents made from it and,
  /// for a sales order, the delivery notes of its invoices.
  public static func lineProgress(_ source: JSONValue, _ related: [JSONValue]) -> [DcLineProgress] {
    let sourceType = source.dcText("type")
    let sourceId = source.dcId
    let invoices =
      sourceType == "sales_order" || sourceType == "purchase_order"
      ? related.filter { d in
        d.dcText("type") == invoiceTypeOf(sourceType) && d["sourceId"] == .string(sourceId)
          && d["status"] != .string("void")
      } : []
    let invoiceIds = Set(invoices.map(\.dcId))
    // Invoice line → order line, so delivery notes made from an invoice count for the order.
    var viaInvoice: [String: String] = [:]
    for invoice in invoices {
      for line in invoice.dcList("items") {
        if let sourceLine = line.dcNonEmpty("sourceLineId") { viaInvoice[line.dcId] = sourceLine }
      }
    }
    var totals: [String: Done] = [:]
    for invoice in invoices {
      for line in invoice.dcList("items") where line["kind"] == .string("item") {
        guard let target = line.dcNonEmpty("sourceLineId") else { continue }
        totals[target, default: Done()].invoiced += DcJS.dec(line["quantity"])
      }
    }
    for note in related {
      guard note.dcText("type") == "delivery_note", note["status"] != .string("cancelled"),
        let noteSource = note.dcNonEmpty("sourceId")
      else { continue }
      let direct = noteSource == sourceId
      if !direct && !invoiceIds.contains(noteSource) { continue }
      let delivered = note["status"] == .string("delivered")
      for line in note.dcList("items") {
        guard line["kind"] == .string("item"), let sourceLine = line.dcNonEmpty("sourceLineId") else { continue }
        guard let target = direct ? sourceLine : viaInvoice[sourceLine], !target.isEmpty else { continue }
        let quantity = DcJS.dec(line["quantity"])
        if delivered {
          totals[target, default: Done()].delivered += quantity
        } else {
          totals[target, default: Done()].inDelivery += quantity
        }
      }
    }
    return source.dcList("items").filter { $0["kind"] == .string("item") }.map { line in
      let done = totals[line.dcId] ?? Done()
      let ordered = DcJS.dec(line["quantity"])
      return DcLineProgress(
        line: line, ordered: line["quantity"]?.double ?? .nan, invoiced: Money.toNumber(done.invoiced),
        delivered: Money.toNumber(done.delivered), inDelivery: Money.toNumber(done.inDelivery),
        toInvoice: positive(ordered - done.invoiced), toDeliver: positive(ordered - done.delivered - done.inDelivery))
    }
  }

  /// Lines actually ordered (zero and negative quantities are notes or returns).
  private static func counted(_ progress: [DcLineProgress]) -> [DcLineProgress] {
    progress.filter { $0.ordered > 0 }
  }

  /// `orderStatus`: a sales or purchase order's status after its invoices or
  /// bills changed; drafts and cancelled orders keep theirs.
  public static func orderStatus(type: String, status: String, _ progress: [DcLineProgress]) -> String {
    if type != "sales_order" && type != "purchase_order" { return status }
    if status == "draft" || status == "cancelled" { return status }
    let lines = counted(progress)
    let all = !lines.isEmpty && lines.allSatisfy { $0.invoiced >= $0.ordered }
    let any = lines.contains { $0.invoiced > 0 }
    if type == "sales_order" { return all ? "invoiced" : any ? "partially_invoiced" : "confirmed" }
    return all ? "billed" : any ? "partially_billed" : "issued"
  }

  /// `deliveryStatusOf`: how much of an order has been delivered and signed for.
  public static func deliveryStatusOf(_ progress: [DcLineProgress]) -> String {
    let lines = counted(progress)
    if !lines.isEmpty && lines.allSatisfy({ $0.delivered >= $0.ordered }) { return "delivered" }
    return lines.contains { $0.delivered > 0 } ? "partially_delivered" : "not_delivered"
  }

  /// `copyLines`: the lines of a new document for the chosen quantities, each
  /// pointing back to its source line; a heading is kept when an item under it is.
  public static func copyLines(_ items: [JSONValue], _ quantities: [String: Double], newId: () -> String) -> [JSONValue] {
    var result: [JSONValue] = []
    var heading: JSONValue?
    for item in items {
      if item["kind"] == .string("heading") {
        heading = item
        continue
      }
      let quantity = quantities[item.dcId] ?? 0
      if !(quantity > 0) { continue }
      if let pending = heading {
        result.append(DcJS.merge(pending, [("id", .string(newId())), ("sourceLineId", nil)]))
        heading = nil
      }
      result.append(
        DcJS.merge(item, [("id", .string(newId())), ("quantity", .number(quantity)), ("sourceLineId", .string(item.dcId))]))
    }
    return result
  }

  /// `partDiscount`: the document discount of an invoice or bill made from
  /// part of an order. A percentage applies as it is; a fixed amount is shared
  /// by value, the last part taking what is left.
  public static func partDiscount(
    _ order: JSONValue, lines: [JSONValue], earlier: [JSONValue], completes: Bool
  ) -> JSONValue {
    let discount = order["discount"] ?? .null
    if order["discountType"] == .string("percent") || !WebJS.truthy(order["discount"]) { return discount }
    let p = Money.precision(order.dcText("currency"))
    if completes {
      var used = Decimal(0)
      for doc in earlier where doc["discountType"] == .string("amount") { used += DcJS.dec(doc["discount"]) }
      return .number(max(0, DcJS.round(DcJS.dec(order["discount"]) - used, p)))
    }
    let subtotal = { (items: [JSONValue]) -> Double in
      DcCalc.calculate(
        items: items, discount: .number(0), discountType: .string("percent"), taxes: [], charges: [],
        pricesIncludeTax: false, precision: DcJS.precision(of: order), deposit: .number(0)
      ).subtotal
    }
    let whole = subtotal(order.dcList("items"))
    if whole == 0 || whole.isNaN { return .number(0) }
    return .number(DcJS.round(DcJS.dec(order["discount"]) * Money.dec(subtotal(lines)) / Money.dec(whole), p))
  }
}
