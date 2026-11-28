import MahamKit
import SwiftUI

/// `/inventory/adjustments/new` (`src/apps/books/pages/inventory/entry-form.tsx`)
/// on a phone: opening stock, an adjustment (with a reason) or a transfer
/// between warehouses, saved through the port of the web's
/// `recordStockEntry` (MahamKit/Write/Inventory).
struct IwEntryFormPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var kind: String
  @State private var date = ISODates.today()
  @State private var warehouseId: String
  @State private var toWarehouseId: String
  @State private var reason = "damaged"
  @State private var reference = ""
  @State private var notes = ""
  @State private var rows: [IwEntryRow]
  @State private var saving = false
  @State private var error: String?

  init() {
    let intent = IwIntent.takeEntry()
    _kind = State(initialValue: intent.kind)
    _warehouseId = State(initialValue: intent.from ?? "")
    _toWarehouseId = State(initialValue: intent.to ?? "")
    _rows = State(initialValue: [IwEntryRow(productId: intent.item ?? "")])
  }

  static let kinds = ["adjustment", "transfer", "opening"]

  var body: some View {
    let one = model.one
    let format = one.format
    let inventory = InvInventoryCache.inventory(one)
    let levels = InvInventoryCache.levels(one, asAt: date)
    let active = activeWarehouses(inventory)
    let from = chosenFrom(inventory, active: active)
    let to = chosenTo(active, from: from)
    WebPage {
      PageHeader(t(title), description: t(description), breadcrumb: t("Inventory"), onBreadcrumb: { router.back() })
      VStack(alignment: .leading, spacing: 24) {
        headCard(active, from: from, to: to)
        linesCard(inventory, levels: levels, from: from, format: format)
        Card {
          CardBody {
            Field(t("Notes"), optional: true) {
              TextInput(text: $notes)
            }
          }
        }
      }
    }
    .stickyActions {
      WebButton(t("Cancel"), variant: .outline) { router.back() }
      if IwGate.entries && IwGate.edits(model) {
        WebButton(t(saveLabel), loading: saving) { save(from: from, to: to) }
          .disabled(kind == "transfer" && active.count < 2)
      }
    }
  }

  // MARK: Words

  private var title: String {
    switch kind {
    case "transfer": "Transfer stock"
    case "opening": "Record opening stock"
    default: "Adjust stock"
    }
  }

  private var saveLabel: String {
    switch kind {
    case "transfer": "Post transfer"
    case "opening": "Record opening stock"
    default: "Post adjustment"
    }
  }

  private var description: String {
    switch kind {
    case "transfer": "Move stock from one warehouse to another. Its value stays the same."
    case "opening": "Stock you had before you started using Maham Books, valued at its cost."
    default: "Write off damaged or expired goods, or correct the quantity after a count."
    }
  }

  private var quantityLabel: String {
    switch kind {
    case "adjustment": t("Quantity change")
    case "transfer": t("Quantity to move")
    default: t("Quantity")
    }
  }

  // MARK: Warehouses

  /// A sub-warehouse's stock is changed directly by the owner, an admin or an accountant only.
  private func activeWarehouses(_ inventory: InvInventory) -> [JSONValue] {
    let manages = IwStockIssues.managesWarehouses(IwSave.link(model))
    return inventory.warehouses.filter { !$0.flag("archived") && (manages || $0.text("parentId") == nil) }
  }

  private func chosenFrom(_ inventory: InvInventory, active: [JSONValue]) -> String {
    if active.contains(where: { $0.rid == warehouseId }) { return warehouseId }
    if let fallback = inventory.defaultWarehouse?.rid, !fallback.isEmpty { return fallback }
    return active.first?.rid ?? ""
  }

  private func chosenTo(_ active: [JSONValue], from: String) -> String {
    if active.contains(where: { $0.rid == toWarehouseId && $0.rid != from }) { return toWarehouseId }
    return active.first { $0.rid != from }?.rid ?? ""
  }

  // MARK: The entry

  private func headCard(_ active: [JSONValue], from: String, to: String) -> some View {
    let options = active.map { SelectOption($0.rid, localName($0)) }
    return Card {
      CardBody {
        VStack(alignment: .leading, spacing: 16) {
          Select(
            selection: $kind,
            options: Self.kinds.map { SelectOption($0, InvLabels.entryKind($0)) })
          Field(t("Date")) {
            DateField(value: $date, required: true)
          }
          Field(kind == "transfer" ? t("From warehouse") : t("Warehouse")) {
            Select(selection: Binding(get: { from }, set: { warehouseId = $0 }), options: options)
          }
          if kind == "transfer" {
            Field(t("To warehouse")) {
              Select(
                selection: Binding(get: { to }, set: { toWarehouseId = $0 }),
                options: options.filter { $0.value != from })
            }
          }
          if kind == "adjustment" {
            Field(t("Reason")) {
              Select(
                selection: $reason,
                options: ["damaged", "expired", "count", "other"].map { SelectOption($0, InvLabels.reason($0) ?? $0) })
            }
          }
          Field(t("Reference"), optional: true) {
            TextInput(text: $reference)
          }
          if kind == "transfer" && active.count < 2 {
            IwNote(text: t("Add a second warehouse to move stock between them."), warning: true)
          }
        }
      }
    }
  }

  // MARK: The lines

  private func linesCard(
    _ inventory: InvInventory, levels: [String: InvStockLevel], from: String, format: CompanyFormat
  ) -> some View {
    let items = inventory.stockItems.filter { !$0.flag("archived") }
    let options = items.map { item in
      ComboOption(
        value: item.rid, label: localName(item), detail: InvText.joined([item.str("sku"), item.str("unit")]),
        keywords: "\(item.str("name")) \(item.str("nameAr")) \(item.str("barcode"))")
    }
    .sorted { $0.label.localizedCompare($1.label) == .orderedAscending }
    let hint: String? = kind == "adjustment" ? t("Enter the change, or the quantity there should be.") : nil
    return Card {
      CardHeader(t("Stock items"), description: error ?? hint)
      if items.isEmpty {
        Text(t("No stock items yet."))
          .font(.web(14))
          .foregroundStyle(palette.slate(500))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 32)
      } else {
        VStack(spacing: 0) {
          ForEach($rows) { $row in
            IwEntryLine(
              row: $row, number: number(of: row), kind: kind, options: options, quantityLabel: quantityLabel,
              here: available(row.productId, levels, from), inventory: inventory, format: format,
              canRemove: rows.count > 1, onPick: { id in pick(row.id, id, inventory) },
              onRemove: { remove(row.id) })
          }
        }
      }
      footer(inventory, levels: levels, format: format)
    }
  }

  private func number(of row: IwEntryRow) -> Int {
    (rows.firstIndex { $0.id == row.id } ?? 0) + 1
  }

  private func available(_ productId: String, _ levels: [String: InvStockLevel], _ warehouse: String) -> Double {
    guard !productId.isEmpty else { return 0 }
    return levels[productId]?.byWarehouse[warehouse] ?? 0
  }

  /// The average cost on the entry's date, or the cost price before there is any stock.
  private func average(_ productId: String, _ levels: [String: InvStockLevel], _ inventory: InvInventory) -> Double {
    if let level = levels[productId], level.quantity > 0 { return level.unitCost }
    return inventory.product(productId)?.num("costPrice") ?? 0
  }

  private func pick(_ row: String, _ productId: String, _ inventory: InvInventory) {
    guard let index = rows.firstIndex(where: { $0.id == row }) else { return }
    rows[index].productId = productId
    rows[index].unitCost = inventory.product(productId)?.num("costPrice") ?? 0
    error = nil
  }

  private func remove(_ row: String) {
    rows.removeAll { $0.id == row }
  }

  private func footer(_ inventory: InvInventory, levels: [String: InvStockLevel], format: CompanyFormat) -> some View {
    let p = inventory.precision
    var minor = 0
    for row in rows where !row.productId.isEmpty && row.quantity != 0 {
      let unit = kind == "opening" ? row.unitCost : average(row.productId, levels, inventory)
      minor += IwPreview.valueMinor(quantity: row.quantity, unitCost: unit, precision: p)
    }
    let amount = InvText.money(InvStock.amount(Int64(minor), precision: p), format)
    return VStack(alignment: .leading, spacing: 12) {
      WebButton(t("Add stock item"), icon: .plus, variant: .outline, size: .sm) {
        rows.append(IwEntryRow(productId: ""))
      }
      if kind != "transfer" {
        Text(
          kind == "opening"
            ? t("Value of the opening stock: {amount}", ["amount": amount])
            : t("Value of the change, at average cost: {amount}", ["amount": amount])
        )
        .font(.web(14))
        .foregroundStyle(palette.slate(600))
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }

  // MARK: Saving

  private func save(from: String, to: String) {
    let lines = rows.filter { !$0.productId.isEmpty && $0.quantity != 0 }
    if lines.isEmpty {
      error = t("Add at least one item with a quantity.")
      return
    }
    let input = InventoryWrites.StockEntryInput(
      kind: kind, date: date, warehouseId: from, toWarehouseId: kind == "transfer" ? to : nil,
      reason: kind == "adjustment" ? reason : nil, reference: reference, notes: notes,
      lines: lines.map { row in
        InventoryWrites.StockEntryInput.Line(
          productId: row.productId, quantity: row.quantity, unitCost: kind == "opening" ? row.unitCost : nil)
      })
    saving = true
    Task {
      let entry = await IwSave.run(model, done: { (entry: JSONValue) in
        t("{number} saved", ["number": entry.str("number")])
      }) { ctx in
        try InventoryWrites.recordStockEntry(ctx, input)
      }
      saving = false
      if let entry {
        router.back()
        router.push(.stockEntry(id: entry.rid))
      }
    }
  }
}

/// One line of a stock entry being written.
struct IwEntryRow: Identifiable {
  let id = UUID().uuidString
  var productId: String
  /// Adjustments: the change (+/−). Opening stock and transfers: the quantity.
  var quantity: Double = 0
  var unitCost: Double = 0
}

/// A line: the item, what is on hand, the quantity, then the new quantity
/// (an adjustment) or the unit cost (opening stock).
struct IwEntryLine: View {
  @Binding var row: IwEntryRow
  let number: Int
  let kind: String
  let options: [ComboOption]
  let quantityLabel: String
  /// On hand in the warehouse on the entry's date.
  let here: Double
  let inventory: InvInventory
  let format: CompanyFormat
  let canRemove: Bool
  let onPick: (String) -> Void
  let onRemove: () -> Void
  @Environment(\.palette) private var palette

  var body: some View {
    let item = row.productId.isEmpty ? nil : inventory.product(row.productId)
    let short = kind == "transfer" && row.quantity > here
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .bottom, spacing: 8) {
        Field(t("Item")) {
          Combobox(
            selection: Binding(get: { row.productId.isEmpty ? nil : row.productId }, set: { onPick($0 ?? "") }),
            options: options, placeholder: t("Choose an item…"), searchPlaceholder: t("Search items…"))
        }
        WebButton(icon: .trash2, label: t("Remove item {number}", ["number": String(number)])) { onRemove() }
          .disabled(!canRemove)
      }
      if let item {
        Text(t("{quantity} on hand", ["quantity": InvText.quantity(here, unit: item.str("unit"), format)]))
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
      }
      HStack(alignment: .top, spacing: 12) {
        Field(quantityLabel) {
          IwNumberField(value: $row.quantity, allowNegative: kind == "adjustment")
        }
        if kind == "adjustment" {
          Field(t("New quantity")) {
            IwNumberField(value: newQuantity)
              .disabled(row.productId.isEmpty)
          }
        } else if kind == "opening" {
          Field(t("Unit cost")) {
            IwNumberField(value: $row.unitCost, allowNegative: false)
          }
        }
      }
      if short {
        Text(t("Only {quantity} in this warehouse.", ["quantity": format.quantity(here)]))
          .font(.web(12))
          .foregroundStyle(palette[.amber(700)])
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }

  /// `dec(here).plus(quantity)`; typing it sets the change.
  private var newQuantity: Binding<Double> {
    Binding(
      get: { IwPreview.add(here, row.quantity) },
      set: { counted in row.quantity = IwPreview.subtract(counted, here) })
  }
}
