import MahamKit
import SwiftUI

/// `/inventory` (`src/apps/books/pages/inventory/index.tsx`) on a phone:
/// the actions, the sub-warehouses the person looks after, the figures,
/// then the tabs (a select on a phone, as the web's is): the stock on hand,
/// the adjustments, the warehouses and the landed costs.
struct InvInventoryPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var tab = "stock"
  @State private var warehouseId = ""
  @State private var query = ""
  @State private var shown = 50
  @State private var opened: String?
  @State private var showing = false
  @State private var warehouseDraft: IwWarehouseDraft?
  @State private var rebuilding = false

  var body: some View {
    let one = model.one
    let format = one.format
    let inventory = InvInventoryCache.inventory(one)
    let items = stockItems(inventory)
    WebPage(refresh: { [model] in await model.one.sync() }) {
      header(inventory)
      InvKeeperCard(warehouses: keptByMe(inventory))
      InvInventoryFigures(inventory: inventory, format: format)
      ListCard {
        tabHeader(inventory, items: items, format: format)
      } rows: {
        tabRows(inventory, items: items, format: format)
      }
    }
    .modifier(
      InvItemDialog(
        sheet: itemSheet(inventory, format: format), isPresented: $showing,
        onOpen: { route in follow(route) }))
    .iwWarehouseDialog($warehouseDraft)
    .onChange(of: tab) { _, _ in shown = 50 }
    .onChange(of: query) { _, _ in shown = 50 }
    .onChange(of: warehouseId) { _, _ in shown = 50 }
  }

  // MARK: Header

  private func header(_ inventory: InvInventory) -> some View {
    let active = inventory.warehouses.filter { !$0.flag("archived") }.count
    let edits = IwGate.edits(model)
    let entries = edits && IwGate.entries
    let landed = edits && IwGate.landedCosts
    let rebuild = edits && IwGate.rebuild
    return PageHeader(t("Inventory"), description: t("Stock on hand, its value and every movement, by warehouse.")) {
      if entries {
        WebButton(t("Adjust stock"), icon: .slidersHorizontal, variant: .outline) { newEntry("adjustment") }
      }
      WebButton(t("Stock count"), icon: .clipboardList) { router.push(.stockCount) }
      if entries || landed || rebuild {
        DropdownMenu(alignment: .end, name: t("More actions")) {
          IconView(.moreHorizontal).foregroundStyle(palette.slate(600))
        } items: {
          if entries {
            DropdownItem(t("Transfer stock"), icon: .arrowLeftRight) { newEntry("transfer") }
              .disabled(active < 2)
            DropdownItem(t("Record opening stock"), icon: .packagePlus) { newEntry("opening") }
          }
          if landed {
            DropdownItem(t("Allocate landed costs"), icon: .shipWheel) { router.push(.newLandedCost) }
          }
          if rebuild {
            DropdownSeparator()
            DropdownItem(t("Recalculate stock"), icon: .refreshCw) { recalculate() }
              .disabled(rebuilding)
          }
        }
      }
    }
  }

  /// `/inventory/adjustments/new?kind=…`.
  private func newEntry(_ kind: String) {
    IwIntent.entry(kind: kind)
    router.push(.newStockAdjustment)
  }

  /// `rebuildStock(companyId)`: every movement planned and costed again.
  private func recalculate() {
    rebuilding = true
    Task {
      await IwSave.run(model, done: { (_: Void) in t("Stock recalculated") }) { ctx in
        try InventoryWrites.rebuildStock(ctx)
      }
      rebuilding = false
    }
  }

  /// The sub-warehouses the person looks after (and may issue from).
  private func keptByMe(_ inventory: InvInventory) -> [JSONValue] {
    guard let userId = model.session?.user.id, !userId.isEmpty else { return [] }
    return inventory.warehouses.filter { warehouse in
      warehouse.text("parentId") != nil && !warehouse.flag("archived")
        && warehouse.obj("keeper")?.text("userId") == userId
    }
  }

  // MARK: Tabs

  @ViewBuilder
  private func tabHeader(_ inventory: InvInventory, items: [JSONValue], format: CompanyFormat) -> some View {
    Select(selection: $tab, options: tabOptions(inventory, items: items, format: format))
    if tab == "stock", !inventory.stockItems.isEmpty {
      if inventory.warehouses.filter({ !$0.flag("archived") }).count > 1 {
        Select(selection: $warehouseId, options: warehouseOptions(inventory))
      }
      TextInput(text: $query, placeholder: t("Search items…"), leadingIcon: .search)
    }
    if tab == "warehouses", IwGate.warehouses, IwGate.edits(model) {
      FlowLayout(spacing: 8, lineSpacing: 8) {
        if IwWarehouseAccess(model).subsOffered, let main = inventory.defaultWarehouse {
          WebButton(t("New sub-warehouse"), icon: .cornerDownRight, variant: .outline, size: .sm) {
            warehouseDraft = IwWarehouseDraft.new(companyId: model.one.companyId ?? "", parentId: main.rid)
          }
        }
        WebButton(t("New warehouse"), icon: .plus, variant: .outline, size: .sm) {
          warehouseDraft = IwWarehouseDraft.new(companyId: model.one.companyId ?? "")
        }
      }
    }
    if tab == "landed-costs", IwGate.landedCosts, IwGate.edits(model) {
      WebButton(t("Allocate landed costs"), icon: .plus, variant: .outline, size: .sm) {
        router.push(.newLandedCost)
      }
    }
  }

  /// "Stock (12)", "Adjustments (3)", …
  private func tabOptions(_ inventory: InvInventory, items: [JSONValue], format: CompanyFormat) -> [SelectOption<String>] {
    let one = model.one
    let warehouses = inventory.warehouses.filter { !$0.flag("archived") }.count
    let counted = { (label: String, count: Int) in "\(label) (\(format.quantity(Double(count))))" }
    return [
      SelectOption("stock", counted(t("Stock"), items.count)),
      SelectOption("history", counted(t("Adjustments"), one.records(.stockEntries).count)),
      SelectOption("warehouses", counted(t("Warehouses"), warehouses)),
      SelectOption("landed-costs", counted(t("Landed costs"), one.records(.landedCosts).count)),
    ]
  }

  private func warehouseOptions(_ inventory: InvInventory) -> [SelectOption<String>] {
    var options = [SelectOption("", t("All warehouses"))]
    for warehouse in inventory.ordered {
      options.append(SelectOption(warehouse.rid, inventory.path(warehouse)))
    }
    return options
  }

  @ViewBuilder
  private func tabRows(_ inventory: InvInventory, items: [JSONValue], format: CompanyFormat) -> some View {
    if InvText.loading(model.one), inventory.products.isEmpty, inventory.warehouses.isEmpty {
      DataLoadingRow()
    } else {
      switch tab {
      case "history":
        InvEntriesTab(entries: InvEntries.newestFirst(model.one.records(.stockEntries)), inventory: inventory, format: format)
      case "warehouses":
        InvWarehousesTab(inventory: inventory, format: format, onEdit: { draft in warehouseDraft = draft })
      case "landed-costs":
        InvLandedCostsTab(inventory: inventory, format: format)
      default:
        stockRows(inventory, items: items, format: format)
      }
    }
  }

  // MARK: Stock

  /// Stock items in use (or still holding some), matching the search, by name.
  private func stockItems(_ inventory: InvInventory) -> [JSONValue] {
    let text = query
    return inventory.stockItems
      .filter { item in !item.flag("archived") || (inventory.level(item.rid)?.quantity ?? 0) != 0 }
      .filter { item in
        InvText.found(text, in: [item.str("name"), item.str("nameAr"), item.str("sku"), item.str("barcode")])
      }
      .sorted { InvText.byName($0, $1) }
  }

  @ViewBuilder
  private func stockRows(_ inventory: InvInventory, items: [JSONValue], format: CompanyFormat) -> some View {
    if inventory.stockItems.isEmpty {
      WebEmptyState(
        icon: .boxes, title: t("No stock items yet"),
        description: t(
          "Mark the goods you keep as stock items. Bills bring them in, invoices take them out, and the cost of sales follows."
        )
      ) {
        if IwGate.items && IwGate.edits(model) {
          WebButton(t("New stock item"), icon: .plus) {
            IwIntent.newItem(kind: "stock")
            router.push(.newProduct)
          }
        }
      }
    } else if items.isEmpty {
      InvNothingMatches()
    } else {
      ForEach(items.prefix(shown).map(Rec.init)) { record in
        InvStockRow(
          item: record.raw, level: inventory.level(record.id), warehouseId: warehouseId,
          precision: inventory.precision, format: format
        ) {
          opened = record.id
          showing = true
        }
      }
      if items.count > shown {
        ListShowMore(remaining: items.count - shown) { shown += 50 }
      }
    }
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

// MARK: The parts

/// "You look after {warehouse}": the sub-warehouses the person keeps, each
/// with Issue items.
struct InvKeeperCard: View {
  let warehouses: [JSONValue]
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    if !warehouses.isEmpty {
      Card {
        VStack(spacing: 0) {
          ForEach(Array(warehouses.indices), id: \.self) { index in
            row(warehouses[index], first: index == 0)
          }
        }
      }
      .padding(.bottom, 24)
    }
  }

  private func row(_ warehouse: JSONValue, first: Bool) -> some View {
    HStack(alignment: .top, spacing: 12) {
      IconView(.shirt, size: 20).foregroundStyle(palette.slate(400))
      VStack(alignment: .leading, spacing: 2) {
        Text(t("You look after {warehouse}", ["warehouse": localName(warehouse)]))
          .font(.web(14, .medium))
          .foregroundStyle(palette.slate(900))
        Text(t("Issue uniforms and other items from it to employees. Each issue waits for an approver."))
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
        if IwGate.issues {
          WebButton(t("Issue items"), icon: .shirt, size: .sm) {
            IwIntent.issue(warehouse: warehouse.rid)
            router.push(.newStockIssue)
          }
          .padding(.top, 8)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .overlay(alignment: .top) {
      if !first { Rectangle().fill(palette.slate(100)).frame(height: 1) }
    }
  }
}

/// The inventory's figures: the stock value, the items in stock and how
/// many are low.
struct InvInventoryFigures: View {
  let inventory: InvInventory
  let format: CompanyFormat
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let inStock = inventory.stockItems.filter { (inventory.level($0.rid)?.quantity ?? 0) > 0 }.count
    let low = inventory.stockItems.filter { !$0.flag("archived") && InvStock.isLow($0, inventory.level($0.rid)) }
      .count
    InvStats {
      InvStat(
        label: t("Stock value"),
        value: InvText.money(InvStock.amount(inventory.totalValueMinor, precision: inventory.precision), format),
        hint: t("At weighted average cost"))
      InvStat(
        label: t("Items in stock"), value: format.quantity(Double(inStock)),
        hint: tp(inventory.stockItems.count, "{count} stock item", "{count} stock items"))
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

/// A stock item on hand: its name, its code (or unit), "Low stock" and
/// "Below zero"; the quantity (in the warehouse chosen) and its value.
struct InvStockRow: View {
  let item: JSONValue
  let level: InvStockLevel?
  let warehouseId: String
  let precision: Int
  let format: CompanyFormat
  let action: () -> Void

  var body: some View {
    let quantity = InvStock.onHand(level, warehouse: warehouseId)
    let low = !item.flag("archived") && InvStock.isLow(item, level)
    InvRow(
      title: InvText.name(item), subtitle: code, detail: "\(t("Value")) \(InvText.money(value(quantity), format))",
      amount: InvText.quantity(quantity, unit: item.str("unit"), format), amountTone: quantity < 0 ? .red(600) : nil
    ) {
      if low { Badge(t("Low stock"), tone: .red) }
      if quantity < 0 { Badge(t("Below zero"), tone: .amber) }
    } action: {
      action()
    }
  }

  /// `item.sku || item.unit || '—'`.
  private var code: String {
    let sku = item.str("sku")
    if !sku.isEmpty { return sku }
    let unit = item.str("unit")
    return unit.isEmpty ? "—" : unit
  }

  /// In one warehouse, the quantity at the average cost; in all, the item's value.
  private func value(_ quantity: Double) -> Double {
    guard !warehouseId.isEmpty else { return level?.value ?? 0 }
    return InvStock.valueAt(quantity, unitCost: level?.unitCost ?? 0, precision: precision)
  }
}

/// The stock entries' order and words.
enum InvEntries {
  /// By date, then number, newest first (`localeCompare`).
  static func newestFirst(_ entries: [JSONValue]) -> [JSONValue] {
    entries.sorted { a, b in
      let date = b.str("date").localizedCompare(a.str("date"))
      if date != .orderedSame { return date == .orderedAscending }
      return b.str("number").localizedCompare(a.str("number")) == .orderedAscending
    }
  }
}

/// The adjustments tab: opening stock, adjustments and transfers, each with
/// its number, type and date, Posted or Void.
struct InvEntriesTab: View {
  let entries: [JSONValue]
  let inventory: InvInventory
  let format: CompanyFormat
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @State private var shown = 50

  init(entries: [JSONValue], inventory: InvInventory, format: CompanyFormat) {
    self.entries = entries
    self.inventory = inventory
    self.format = format
  }

  var body: some View {
    if entries.isEmpty {
      WebEmptyState(
        icon: .slidersHorizontal, title: t("No adjustments yet"),
        description: t("Opening stock, write-offs, count differences and transfers between warehouses show here.")
      ) {
        if IwGate.entries && IwGate.edits(model) {
          WebButton(t("Adjust stock"), icon: .slidersHorizontal, variant: .outline) {
            IwIntent.entry(kind: "adjustment")
            router.push(.newStockAdjustment)
          }
        }
      }
    } else {
      ForEach(entries.prefix(shown).map(Rec.init)) { record in
        InvRow(
          title: record.raw.str("number"), subtitle: subtitle(record.raw), detail: warehouses(record.raw)
        ) {
          Badge(status: InvLabels.postedBadge(record.raw.str("status")))
        } action: {
          router.push(.stockEntry(id: record.id))
        }
      }
      if entries.count > shown {
        ListShowMore(remaining: entries.count - shown) { shown += 50 }
      }
    }
  }

  /// "Stock adjustment · Damaged · 25/11/2026".
  private func subtitle(_ entry: JSONValue) -> String {
    InvText.joined([
      InvLabels.entryKind(entry.str("kind")), InvLabels.reason(entry.text("reason")), format.date(entry.text("date")),
    ])
  }

  /// The warehouse, or "From → To" for a transfer.
  private func warehouses(_ entry: JSONValue) -> String {
    let from = inventory.warehouseName(entry.text("warehouseId"))
    guard entry.str("kind") == "transfer" else { return from }
    return "\(from) → \(inventory.warehouseName(entry.text("toWarehouseId")))"
  }
}

/// The warehouses tab: each main warehouse followed by its sub-warehouses,
/// with who looks after it, its address and the units on hand.
struct InvWarehousesTab: View {
  let inventory: InvInventory
  let format: CompanyFormat
  /// Opens the warehouse form (where warehouses can be saved from this iPhone).
  var onEdit: ((IwWarehouseDraft) -> Void)?

  var body: some View {
    ForEach(inventory.ordered.map(Rec.init)) { record in
      row(record.raw)
    }
  }

  private func row(_ warehouse: JSONValue) -> some View {
    let sub = warehouse.text("parentId") != nil
    let icon: Icon = sub ? .cornerDownRight : .warehouse
    return HStack(spacing: 0) {
      InvRow(
        title: InvText.name(warehouse), subtitle: subtitle(warehouse), icon: icon, indent: sub ? 24 : 0
      ) {
        if warehouse.flag("isDefault") {
          Badge(inventory.hasSubs(warehouse) ? t("Main warehouse") : t("Default"), tone: .blue)
        }
        if sub { Badge(t("Sub-warehouse"), tone: .gray) }
        if warehouse.flag("archived") { Badge(t("Archived"), tone: .gray) }
      }
      if let onEdit {
        IwWarehouseMenu(warehouse: warehouse, inventory: inventory, onEdit: onEdit)
          .padding(.trailing, 8)
      }
    }
  }

  /// "Looked after by … · the address · 120 units on hand".
  private func subtitle(_ warehouse: JSONValue) -> String {
    var units: Double = 0
    for item in inventory.stockItems {
      units += InvStock.onHand(inventory.level(item.rid), warehouse: warehouse.rid)
    }
    let keeper = keeperLabel(warehouse.obj("keeper"))
    return InvText.joined([
      keeper.isEmpty ? nil : t("Looked after by {name}", ["name": keeper]), warehouse.str("address"),
      t("{quantity} units on hand", ["quantity": format.quantity(units)]),
    ])
  }

  /// The keeper's name, with the job title.
  private func keeperLabel(_ keeper: JSONValue?) -> String {
    guard let name = keeper?.text("name") else { return "" }
    guard let title = keeper?.text("jobTitle") else { return name }
    return "\(name) (\(title))"
  }
}

/// The landed costs tab: each with the bill of the charges and of the goods,
/// the amount allocated, Allocated or Void.
struct InvLandedCostsTab: View {
  let inventory: InvInventory
  let format: CompanyFormat
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let costs = model.one.records(.landedCosts).sorted {
      $1.str("number").localizedCompare($0.str("number")) == .orderedAscending
    }
    let totals = InvLandedCosts.totals(inventory)
    if costs.isEmpty {
      WebEmptyState(
        icon: .shipWheel, title: t("No landed costs yet"),
        description: t(
          "Add customs duty, freight, clearing and insurance from a bill to the cost of the goods they brought in.")
      ) {
        if IwGate.landedCosts && IwGate.edits(model) {
          WebButton(t("Allocate landed costs"), icon: .plus, variant: .outline) { router.push(.newLandedCost) }
        }
      }
    } else {
      ForEach(costs.map(Rec.init)) { record in
        InvRow(
          title: record.raw.str("number"), subtitle: "\(t("Charges")): \(billNumber(record.raw.str("billId")))",
          detail: "\(t("Goods")): \(billNumber(record.raw.str("targetBillId")))",
          amount: amount(totals[record.id])
        ) {
          Badge(status: InvLabels.postedBadge(record.raw.str("status"), allocated: true))
        } action: {
          router.push(.landedCost(id: record.id))
        }
      }
    }
  }

  /// A bill's number, or "—" when it isn't a bill here.
  private func billNumber(_ id: String) -> String {
    guard let bill = model.one.record(.documents, id), bill.str("type") == "bill" else { return "—" }
    return bill.str("number")
  }

  private func amount(_ minor: Int64?) -> String {
    guard let minor else { return "—" }
    return InvText.money(InvStock.amount(minor, precision: inventory.precision), format)
  }
}

/// What landed costs added up to.
@MainActor
enum InvLandedCosts {
  /// Each landed cost's charges, from its movements (`sourceValue`), in minor units.
  static func totals(_ inventory: InvInventory) -> [String: Int64] {
    var totals: [String: Int64] = [:]
    for movement in inventory.movements where movement.str("sourceType") == "landed_cost" {
      totals[movement.str("sourceId"), default: 0] += Money.toMinor(
        movement.num("sourceValue"), inventory.precision)
    }
    return totals
  }
}
