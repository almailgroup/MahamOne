import MahamKit
import SwiftUI

/// `/products` (`src/apps/books/pages/products/index.tsx`) on a phone: the
/// figures (stock value, stock items, low stock), then Active / Archived,
/// the type filter and the search; each item with its code, other name,
/// description and taxes, its price per unit and what is on hand. A tap
/// opens the item, read only.
struct InvProductsPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @State private var scope = "active"
  @State private var kindFilter = "all"
  @State private var query = ""
  @State private var shown = 50
  @State private var opened: String?
  @State private var showing = false

  var body: some View {
    let one = model.one
    let format = one.format
    let inventory = InvInventoryCache.inventory(one)
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(
        t("Products & services"),
        description: t("What you sell and buy, with prices, and stock for the goods you keep.")
      ) {
        WebButton(t("New item"), icon: .plus, haptic: .press) { router.push(.newProduct) }
      }
      InvProductFigures(inventory: inventory, format: format)
      if inventory.products.isEmpty {
        emptyCard(one)
      } else {
        listCard(inventory, format: format)
      }
    }
    .modifier(
      InvItemDialog(
        sheet: itemSheet(inventory, format: format), isPresented: $showing,
        onOpen: { route in follow(route) }))
    .onChange(of: scope) { _, _ in shown = 50 }
    .onChange(of: kindFilter) { _, _ in shown = 50 }
    .onChange(of: query) { _, _ in shown = 50 }
  }

  // MARK: Parts

  @ViewBuilder
  private func emptyCard(_ one: OneData) -> some View {
    Card {
      if InvText.loading(one) {
        DataLoadingRow()
      } else {
        WebEmptyState(
          icon: .package, title: t("No products or services yet"),
          description: t(
            "Add what you sell, such as delivery or printing, and the goods you keep in stock, with their prices.")
        ) {
          FlowLayout(spacing: 8, lineSpacing: 8) {
            WebButton(t("New item"), icon: .plus) { router.push(.newProduct) }
            WebButton(t("New stock item"), icon: .boxes, variant: .outline) { router.push(.newProduct) }
          }
        }
      }
    }
  }

  private func listCard(_ inventory: InvInventory, format: CompanyFormat) -> some View {
    let visible = filtered(inventory)
    let shared = InvProducts.sharedSkus(model.one.company, inventory.products)
    return ListCard {
      Segmented(selection: $scope, options: viewOptions(inventory))
      Select(selection: $kindFilter, options: kindOptions(inventory, format: format))
      TextInput(text: $query, placeholder: t("Search…"), leadingIcon: .search)
    } rows: {
      if visible.isEmpty {
        InvNothingMatches()
      } else {
        ForEach(visible.prefix(shown).map(Rec.init)) { record in
          InvProductRow(
            product: record.raw, inventory: inventory, format: format, sameSku: shared.contains(record.id)
          ) {
            opened = record.id
            showing = true
          }
        }
        if visible.count > shown {
          ListShowMore(remaining: visible.count - shown) { shown += 50 }
        }
      }
    }
  }

  // MARK: Filters

  private func viewOptions(_ inventory: InvInventory) -> [SegmentOption<String>] {
    let archived = inventory.products.filter { $0.flag("archived") }.count
    return [
      SegmentOption("active", t("Active"), count: inventory.products.count - archived),
      SegmentOption("archived", t("Archived"), count: archived),
    ]
  }

  /// "All types", each type with how many there are, and "Low stock".
  private func kindOptions(_ inventory: InvInventory, format: CompanyFormat) -> [SelectOption<String>] {
    let live = inventory.products.filter { !$0.flag("archived") }
    var options = [SelectOption("all", t("All types"))]
    for kind in InvKind.allCases {
      let count = live.filter { InvKind($0) == kind }.count
      options.append(SelectOption(kind.rawValue, "\(kind.plural) (\(format.quantity(Double(count))))"))
    }
    let low = InvProducts.lowStock(live, inventory: inventory).count
    options.append(SelectOption("low", "\(t("Low stock")) (\(format.quantity(Double(low))))"))
    return options
  }

  /// The items shown: active or archived, of the type chosen, matching the
  /// search, by name.
  private func filtered(_ inventory: InvInventory) -> [JSONValue] {
    let archived = scope == "archived"
    let chosen = kindFilter
    let text = query
    return inventory.products
      .filter { $0.flag("archived") == archived }
      .filter { product in
        switch chosen {
        case "all": true
        case "low": InvKind(product) == .stock && InvStock.isLow(product, inventory.level(product.rid))
        default: InvKind(product).rawValue == chosen
        }
      }
      .filter { product in
        InvText.found(
          text,
          in: [
            product.str("name"), product.str("nameAr"), product.str("sku"), product.str("barcode"),
            product.str("description"),
          ])
      }
      .sorted { InvText.byName($0, $1) }
  }

  // MARK: The dialog

  private func itemSheet(_ inventory: InvInventory, format: CompanyFormat) -> InvItemSheet? {
    guard let opened, let product = inventory.product(opened) else { return nil }
    return InvItemSheets.make(product, inventory: inventory, one: model.one, format: format)
  }

  private func follow(_ route: Route) {
    showing = false
    router.push(route)
  }
}

/// The figures above the items, once there are stock items: their value at
/// the weighted average cost, how many, and how many are low.
struct InvProductFigures: View {
  let inventory: InvInventory
  let format: CompanyFormat
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let live = inventory.products.filter { !$0.flag("archived") }
    let stock = live.filter { InvKind($0) == .stock }
    let low = InvProducts.lowStock(live, inventory: inventory).count
    if !stock.isEmpty {
      InvStats {
        InvStat(
          label: t("Stock value"),
          value: InvText.money(InvStock.amount(valueMinor(stock), precision: inventory.precision), format),
          hint: t("At weighted average cost"))
        InvStat(label: t("Stock items"), value: format.quantity(Double(stock.count)))
        if low > 0 {
          InvStat(
            label: t("Low stock"), value: format.quantity(Double(low)), hint: t("See what to reorder"), danger: true,
            onHint: { router.push(.report("low-stock")) })
        } else {
          InvStat(label: t("Low stock"), value: format.quantity(0), hint: t("Nothing to reorder"))
        }
      }
    }
  }

  private func valueMinor(_ items: [JSONValue]) -> Int64 {
    var sum: Int64 = 0
    for item in items {
      sum += inventory.level(item.rid)?.valueMinor ?? 0
    }
    return sum
  }
}

/// An item in the list: its name (and "Same SKU as another item"), its
/// code, other name, description and taxes, or its type; its price per
/// unit and what is on hand; "Low stock" when it is.
struct InvProductRow: View {
  let product: JSONValue
  let inventory: InvInventory
  let format: CompanyFormat
  let sameSku: Bool
  let action: () -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    let kind = InvKind(product)
    let low = kind == .stock && InvStock.isLow(product, inventory.level(product.rid))
    InvRow(title: InvText.name(product), subtitle: subtitle(kind), detail: detail(kind)) {
      if sameSku { Badge(t("Same SKU as another item"), tone: .amber) }
      if low { Badge(t("Low stock"), tone: .red) }
    } action: {
      action()
    }
  }

  /// `[sku, the other name, description, taxes].join(' · ')`, or the type.
  private func subtitle(_ kind: InvKind) -> String {
    let name = localName(product)
    let other = name == product.str("name") ? product.str("nameAr") : product.str("name")
    let line = InvText.joined([
      product.str("sku"), other, product.str("description"), InvItemSheets.taxLabel(product, one: model.one),
    ])
    return line.isEmpty ? kind.label : line
  }

  /// "KD 1.500 / pcs · 12 pcs on hand".
  private func detail(_ kind: InvKind) -> String {
    let unit = InvText.unit(product, company: model.one.company)
    let price = InvText.unitAmount(product.num("unitPrice"), format)
    var parts = [unit.isEmpty ? price : "\(price) / \(unit)"]
    if kind == .stock {
      let quantity = InvText.quantity(inventory.level(product.rid)?.quantity ?? 0, unit: unit, format)
      parts.append(t("{quantity} on hand", ["quantity": quantity]))
    }
    return parts.joined(separator: " · ")
  }
}

/// The products page's rules.
@MainActor
enum InvProducts {
  /// Stock items at or below their reorder level.
  static func lowStock(_ items: [JSONValue], inventory: InvInventory) -> [JSONValue] {
    items.filter { InvKind($0) == .stock && InvStock.isLow($0, inventory.level($0.rid)) }
  }

  /// `sharedItemCodes`: items sharing a code the company gives (another
  /// device gave the same code offline), once codes are given; groups of
  /// archived items only are left out. The ids of every item in a group.
  static func sharedSkus(_ company: JSONValue?, _ products: [JSONValue]) -> Set<String> {
    guard SyncJSON.truthy(company?["items"]?["autoSku"]) else { return [] }
    let stored = company?["numbering"]?["product"]
    let fallback = Numbering.defaultRules()["product"] ?? NumberingRule(pattern: "SKU-{counter}", padding: 5)
    let rule = stored.flatMap { $0.isNull ? nil : NumberingRule($0) } ?? fallback
    var groups: [String: [JSONValue]] = [:]
    for product in products {
      let key = product.str("sku").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if key.isEmpty || !Numbering.writtenBy(rule, key) { continue }
      groups[key, default: []].append(product)
    }
    var ids = Set<String>()
    for group in groups.values where group.count > 1 && group.contains(where: { !$0.flag("archived") }) {
      ids.formUnion(group.map(\.rid))
    }
    return ids
  }
}
