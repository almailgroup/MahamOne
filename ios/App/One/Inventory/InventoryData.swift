import Foundation
import MahamKit

/// The company's stock as the web's `useInventory` gives it: the items,
/// the stock items, the warehouses (the default first, archived last, then
/// by name), the movements and every stock item's level, in the company
/// currency's precision.
@MainActor
struct InvInventory {
  let products: [JSONValue]
  /// Stock items, archived ones included.
  let stockItems: [JSONValue]
  /// Every warehouse, archived ones included; the default one first.
  let warehouses: [JSONValue]
  /// The default warehouse, when it is in use.
  let defaultWarehouse: JSONValue?
  let movements: [JSONValue]
  /// On hand and value of each stock item after everything recorded.
  let levels: [String: InvStockLevel]
  /// Minor-unit digits of the company currency.
  let precision: Int

  init(_ one: OneData) {
    let products = one.records(.products)
    let movements = one.records(.stockMovements)
    let precision = Money.precision(one.format.currency)
    self.products = products
    stockItems = products.filter { InvKind($0) == .stock }
    let sorted = one.records(.warehouses).sorted { InvInventory.warehouseOrder($0, $1) }
    warehouses = sorted
    defaultWarehouse = sorted.first { $0.flag("isDefault") && !$0.flag("archived") }
    self.movements = movements
    levels = InvStock.levels(movements, precision: precision)
    self.precision = precision
  }

  /// The default first, archived last, then by name in the language read.
  private static func warehouseOrder(_ a: JSONValue, _ b: JSONValue) -> Bool {
    let isDefault = (a.flag("isDefault") ? 1 : 0) - (b.flag("isDefault") ? 1 : 0)
    if isDefault != 0 { return isDefault > 0 }
    let archived = (a.flag("archived") ? 1 : 0) - (b.flag("archived") ? 1 : 0)
    if archived != 0 { return archived < 0 }
    return localName(a).localizedCompare(localName(b)) == .orderedAscending
  }

  /// A stock item's level (nil when it never moved).
  func level(_ id: String) -> InvStockLevel? {
    levels[id]
  }

  func warehouse(_ id: String?) -> JSONValue? {
    guard let id, !id.isEmpty else { return nil }
    return warehouses.first { $0.rid == id }
  }

  /// `localName(warehouse) || '—'`.
  func warehouseName(_ id: String?) -> String {
    guard let found = warehouse(id) else { return "—" }
    let name = localName(found)
    return name.isEmpty ? "—" : name
  }

  /// Main warehouses, each followed by its sub-warehouses.
  var ordered: [JSONValue] {
    let ids = Set(warehouses.map(\.rid))
    var list: [JSONValue] = []
    for main in warehouses where main.text("parentId") == nil || !ids.contains(main.str("parentId")) {
      list.append(main)
      list.append(contentsOf: warehouses.filter { $0.text("parentId") == main.rid })
    }
    return list
  }

  /// `warehousePath`: "Main store › Ahmed’s store", or "—".
  func path(_ warehouse: JSONValue?) -> String {
    guard let warehouse else { return "—" }
    if let parentId = warehouse.text("parentId"), let parent = self.warehouse(parentId) {
      return "\(localName(parent)) › \(localName(warehouse))"
    }
    return localName(warehouse)
  }

  /// Whether a warehouse has sub-warehouses under it.
  func hasSubs(_ warehouse: JSONValue) -> Bool {
    let id = warehouse.rid
    return warehouses.contains { $0.str("parentId") == id }
  }

  /// A stock item by id.
  func product(_ id: String) -> JSONValue? {
    products.first { $0.rid == id }
  }

  /// The value of everything in stock, in minor units.
  var totalValueMinor: Int64 {
    var sum: Int64 = 0
    for item in stockItems {
      sum += levels[item.rid]?.valueMinor ?? 0
    }
    return sum
  }
}

/// The inventory worked out once per change of the company's records (and
/// of the interface language, which orders the warehouses), not on every
/// redraw: the levels add up every movement.
@MainActor
enum InvInventoryCache {
  private struct Entry {
    let revision: Int
    let company: String
    let language: Language
    let inventory: InvInventory
  }

  private static var entry: Entry?

  static func inventory(_ one: OneData) -> InvInventory {
    let revision = one.revision
    let company = one.companyId ?? ""
    let language = LanguageStore.shared.language
    if let entry, entry.revision == revision, entry.company == company, entry.language == language {
      return entry.inventory
    }
    let made = InvInventory(one)
    entry = Entry(revision: revision, company: company, language: language, inventory: made)
    dated = nil
    return made
  }

  private struct Dated {
    let revision: Int
    let company: String
    let asAt: String
    let levels: [String: InvStockLevel]
  }

  private static var dated: Dated?

  /// The levels as at the end of a day (the stock count's date).
  static func levels(_ one: OneData, asAt: String) -> [String: InvStockLevel] {
    let inventory = self.inventory(one)
    let revision = one.revision
    let company = one.companyId ?? ""
    if let dated, dated.revision == revision, dated.company == company, dated.asAt == asAt {
      return dated.levels
    }
    let made = InvStock.levels(inventory.movements, precision: inventory.precision, asAt: asAt)
    dated = Dated(revision: revision, company: company, asAt: asAt, levels: made)
    return made
  }
}

/// How the interface writes stock: units, unit prices, names.
@MainActor
enum InvText {
  /// The interface is in Arabic.
  static var arabic: Bool { LanguageStore.shared.isArabic }

  /// `fmt.money`: the amount in the company's way, isolated so it reads the
  /// same in right-to-left text ("-12.500 د.ك").
  static func money(_ amount: Double, _ format: CompanyFormat) -> String {
    Format.isolateAmount(format.money(amount), locale: format.locale)
  }

  /// `formatUnitPrice` (`useUnitAmount`): an amount keeping up to 6 decimals, "KD 0.333333".
  static func unitAmount(_ amount: Double, _ format: CompanyFormat) -> String {
    Format.unitPrice(amount, currency: format.currency, locale: format.locale, display: format.display)
  }

  /// The web's list searches: the trimmed query, in lower case, somewhere in
  /// the fields joined by spaces.
  static func found(_ query: String, in fields: [String]) -> Bool {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if needle.isEmpty { return true }
    return fields.joined(separator: " ").lowercased().contains(needle)
  }

  /// Sorts by name in the language read (`localName(a).localeCompare(localName(b))`).
  static func byName(_ a: JSONValue, _ b: JSONValue) -> Bool {
    localName(a).localizedCompare(localName(b)) == .orderedAscending
  }

  /// The company's records are still coming to this iPhone.
  static func loading(_ one: OneData) -> Bool {
    if case .downloading = one.phase { return true }
    return !one.hasData
  }

  /// "12 pcs": a quantity and its unit, when there is one.
  static func quantity(_ value: Double, unit: String, _ format: CompanyFormat) -> String {
    let quantity = format.quantity(value)
    return unit.isEmpty ? quantity : "\(quantity) \(unit)"
  }

  /// `unitText(company, item, language)`: the Arabic name of a unit picked
  /// from the list in Arabic, else the unit as stored.
  static func unit(_ product: JSONValue, company: JSONValue?) -> String {
    Units.unitText(
      company, unit: product.str("unit"), unitId: product.text("unitId"), language: arabic ? "ar" : "en")
  }

  /// A record's name in the interface language, or "—".
  static func name(_ record: JSONValue?) -> String {
    guard let record else { return "—" }
    let name = localName(record)
    return name.isEmpty ? "—" : name
  }

  /// `t('{name} · {date}')`-style joins: the parts that aren't empty, with " · ".
  static func joined(_ parts: [String?]) -> String {
    parts.compactMap { part in
      guard let part, !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
      return part
    }
    .joined(separator: " · ")
  }
}
