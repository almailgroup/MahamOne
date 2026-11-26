import MahamKit
import SwiftUI

/// The item dialog's contents, read only: on the web a tap on an item opens
/// its dialog (`item-dialog.tsx`) with these fields, and a stock item's
/// movements are a link away (`/reports/stock-movements?item=`); here both
/// are in one dialog.
@MainActor
enum InvItemSheets {
  static func make(_ product: JSONValue, inventory: InvInventory, one: OneData, format: CompanyFormat) -> InvItemSheet {
    let kind = InvKind(product)
    let level = inventory.level(product.rid)
    let isStock = kind == .stock
    return InvItemSheet(
      id: product.rid, title: InvText.name(product), badges: badges(product, kind: kind, level: level),
      facts: facts(product, kind: kind, level: level, one: one, format: format),
      warehouses: isStock ? warehouses(product, level: level, inventory: inventory, format: format) : [],
      movements: isStock ? movements(product, inventory: inventory, format: format) : [], isStock: isStock)
  }

  private static func badges(_ product: JSONValue, kind: InvKind, level: InvStockLevel?) -> [InvBadge] {
    var list = [InvBadge(text: kind.label, tone: kind.tone)]
    let archived = product.flag("archived")
    if archived { list.append(InvBadge(text: t("Archived"), tone: .gray)) }
    if kind == .stock, !archived, InvStock.isLow(product, level) {
      list.append(InvBadge(text: t("Low stock"), tone: .red))
    }
    return list
  }

  private static func facts(
    _ product: JSONValue, kind: InvKind, level: InvStockLevel?, one: OneData, format: CompanyFormat
  ) -> [InvFact] {
    let unit = InvText.unit(product, company: one.company)
    let price = InvText.unitAmount(product.num("unitPrice"), format)
    var list: [InvFact] = []
    list.append(InvFact(t("Type"), kind.label))
    list.append(InvFact(t("SKU"), product.str("sku")))
    list.append(InvFact(t("Name"), product.str("name")))
    list.append(InvFact(t("Arabic name"), product.str("nameAr")))
    list.append(InvFact(t("Description"), product.str("description")))
    list.append(InvFact(t("Arabic description"), product.str("descriptionAr")))
    list.append(InvFact(t("Selling price"), unit.isEmpty ? price : "\(price) / \(unit)", tabular: true))
    if let cost = product.number("costPrice") {
      list.append(InvFact(t("Cost price"), InvText.unitAmount(cost, format), tabular: true))
    }
    list.append(InvFact(t("Unit"), unit))
    if kind == .stock, let reorder = product.number("reorderLevel") {
      list.append(InvFact(t("Reorder level"), format.quantity(reorder), tabular: true))
    }
    if let vendor = product.text("preferredVendorId") {
      list.append(InvFact(t("Preferred vendor"), one.contactName(vendor), route: .contact(.vendor, id: vendor)))
    }
    list.append(InvFact(t("Barcode"), product.str("barcode")))
    list.append(InvFact(t("HS code"), product.str("hsCode")))
    list.append(InvFact(t("Income account"), one.accountName(product.text("incomeAccountId"))))
    list.append(InvFact(t("Default taxes"), taxLabel(product, one: one)))
    if kind == .stock {
      let quantity = level?.quantity ?? 0
      list.append(
        InvFact(
          t("On hand"), InvText.quantity(quantity, unit: product.str("unit"), format),
          tone: quantity < 0 ? .red(600) : nil, strong: true, tabular: true))
      list.append(InvFact(t("Average cost"), InvText.unitAmount(level?.unitCost ?? 0, format), tabular: true))
      list.append(InvFact(t("Stock value"), InvText.money(level?.value ?? 0, format), tabular: true))
    }
    return list
  }

  /// `rateLabel`: "VAT 5%, …", the item's default taxes.
  static func taxLabel(_ product: JSONValue, one: OneData) -> String {
    var labels: [String] = []
    for id in product.list("taxRateIds") {
      guard let rateId = id.string, let rate = one.record(.taxRates, rateId) else { continue }
      labels.append("\(rate.str("name")) \(Money.jsString(rate.num("rate")))%")
    }
    return labels.joined(separator: ", ")
  }

  /// On hand in each warehouse in use (or still holding some), when there is more than one.
  private static func warehouses(
    _ product: JSONValue, level: InvStockLevel?, inventory: InvInventory, format: CompanyFormat
  ) -> [InvFact] {
    guard inventory.warehouses.count > 1 else { return [] }
    var list: [InvFact] = []
    for warehouse in inventory.ordered {
      let quantity = InvStock.onHand(level, warehouse: warehouse.rid)
      if warehouse.flag("archived") && quantity == 0 { continue }
      list.append(
        InvFact(
          inventory.path(warehouse), InvText.quantity(quantity, unit: product.str("unit"), format),
          tone: quantity < 0 ? .red(600) : nil, tabular: true))
    }
    return list
  }

  /// Every movement of the item in date order, with what is on hand after
  /// each one (the stock-movements report).
  private static func movements(_ product: JSONValue, inventory: InvInventory, format: CompanyFormat) -> [InvMovementLine] {
    let id = product.rid
    let unit = product.str("unit")
    let several = inventory.warehouses.count > 1
    let sorted = inventory.movements.filter { $0.str("productId") == id }.sorted { InvStock.precedes($0, $1) }
    var running: Decimal = 0
    var lines: [InvMovementLine] = []
    for movement in sorted {
      let quantity = movement.num("quantity")
      running += Money.dec(quantity)
      let after = Money.toNumber(running)
      var amount: String?
      if quantity != 0 {
        amount = (quantity > 0 ? "+" : "") + InvText.quantity(quantity, unit: unit, format)
      }
      let subtitle = InvText.joined([
        format.date(movement.text("date")), several ? inventory.warehouseName(movement.text("warehouseId")) : nil,
      ])
      let detail = InvText.joined([
        "\(t("Value")) \(InvText.money(movement.num("value"), format))",
        "\(t("On hand")) \(format.quantity(after))",
      ])
      lines.append(
        InvMovementLine(
          id: movement.rid, title: "\(InvLabels.movement(movement.str("sourceType"))) \(movement.str("number"))",
          subtitle: subtitle, detail: detail, amount: amount, negative: quantity < 0,
          route: InvLabels.movementRoute(movement)))
    }
    return lines
  }
}

/// Opens an item's dialog over a page, and follows a link from it.
struct InvItemDialog: ViewModifier {
  let sheet: InvItemSheet?
  @Binding var isPresented: Bool
  let onOpen: (Route) -> Void

  func body(content: Content) -> some View {
    content
      .webDialog(isPresented: $isPresented, title: sheet?.title ?? "") {
        if let sheet {
          InvItemDetails(sheet: sheet, onOpen: onOpen)
        }
      }
  }
}
