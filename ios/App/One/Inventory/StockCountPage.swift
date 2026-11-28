import MahamKit
import SwiftUI

/// `/inventory/count` (`src/apps/books/pages/inventory/count.tsx`): each
/// stock item in use with the quantity on record in the warehouse chosen at
/// the end of the count date, what was counted, and the differences posted
/// as one adjustment (the port of the web's `recordStockEntry`). Counts
/// typed are kept on this iPhone until they are posted, as the web keeps
/// them in the browser.
struct InvStockCountPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var warehouseId = ""
  @State private var date = ISODates.today()
  @State private var query = ""
  @State private var shown = 50
  @State private var counts: [String: String] = [:]
  @State private var loadedKey = ""
  @State private var posting = false

  var body: some View {
    let one = model.one
    let format = one.format
    let inventory = InvInventoryCache.inventory(one)
    let items = inventory.stockItems.filter { !$0.flag("archived") }.sorted { InvText.byName($0, $1) }
    let warehouse = warehouseId.isEmpty ? (inventory.defaultWarehouse?.rid ?? "") : warehouseId
    let key = IwCountDraft.key(one.companyId ?? "", warehouse)
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(
        t("Stock count"), description: t("Count what is on the shelves, then post the differences as one adjustment."),
        breadcrumb: t("Inventory"), onBreadcrumb: { backToInventory() })
      if items.isEmpty {
        emptyCard(one)
      } else {
        sheetCard(items, inventory: inventory, warehouse: warehouse, format: format)
        if counting {
          Text(t("Counts typed here are kept in this browser until you post them."))
            .font(.web(12))
            .foregroundStyle(palette.slate(500))
            .padding(.top, 12)
        }
      }
    }
    .onChange(of: query) { _, _ in shown = 50 }
    .onChange(of: key, initial: true) { _, next in load(next) }
    .onChange(of: counts) { _, _ in IwCountDraft.store(counts, key: loadedKey) }
  }

  /// Counting and posting the differences, where adjustments can be saved from this iPhone.
  private var counting: Bool { IwGate.entries && IwGate.edits(model) }

  @ViewBuilder
  private func emptyCard(_ one: OneData) -> some View {
    Card {
      if InvText.loading(one) {
        DataLoadingRow()
      } else {
        WebEmptyState(
          icon: .clipboardCheck, title: t("No stock items yet"),
          description: t("Stock items you add show here to be counted.")
        ) {
          if IwGate.items && IwGate.edits(model) {
            WebButton(t("New stock item")) {
              IwIntent.newItem(kind: "stock")
              router.push(.newProduct)
            }
          }
        }
      }
    }
  }

  private func sheetCard(
    _ items: [JSONValue], inventory: InvInventory, warehouse: String, format: CompanyFormat
  ) -> some View {
    let levels = InvInventoryCache.levels(model.one, asAt: date)
    let text = query
    let visible = items.filter { item in
      InvText.found(text, in: [item.str("name"), item.str("nameAr"), item.str("sku"), item.str("barcode")])
    }
    return ListCard {
      Field(t("Warehouse")) {
        Select(selection: $warehouseId, options: warehouseOptions(inventory), placeholder: t("Warehouse"))
      }
      Field(t("Count date")) {
        DateField(value: $date, required: true)
      }
      Field(t("Search")) {
        TextInput(text: $query, placeholder: t("Search items…"), leadingIcon: .search)
      }
    } rows: {
      InvColumns(t("Item"), counting ? t("Counted") : t("On record"))
      if visible.isEmpty {
        InvNothingMatches()
      } else {
        ForEach(visible.prefix(shown).map(Rec.init)) { record in
          row(record.raw, onRecord: onRecord(levels[record.id], warehouse: warehouse), format: format)
        }
        if visible.count > shown {
          ListShowMore(remaining: visible.count - shown) { shown += 50 }
        }
      }
      if counting {
        summary(items, levels: levels, inventory: inventory, warehouse: warehouse, format: format)
      }
    }
  }

  @ViewBuilder
  private func row(_ item: JSONValue, onRecord: Double, format: CompanyFormat) -> some View {
    if counting {
      IwCountRow(
        item: item, code: code(item), onRecord: onRecord, format: format,
        text: Binding(get: { counts[item.rid] ?? "" }, set: { counts[item.rid] = $0 }))
    } else {
      InvRow(title: InvText.name(item), subtitle: code(item), amount: format.quantity(onRecord))
    }
  }

  /// "3 items counted · 2 differences · worth KD 4.500 at average cost", Clear counts and Post adjustment.
  private func summary(
    _ items: [JSONValue], levels: [String: InvStockLevel], inventory: InvInventory, warehouse: String,
    format: CompanyFormat
  ) -> some View {
    let counted = differences(items, levels: levels, warehouse: warehouse)
    let changed = counted.filter { $0.quantity != 0 }
    var minor = 0
    for line in changed {
      minor += IwPreview.valueMinor(
        quantity: line.quantity, unitCost: unitCost(line.productId, levels, inventory), precision: inventory.precision)
    }
    var parts = [
      tp(counted.count, "{count} item counted", "{count} items counted"),
      tp(changed.count, "{count} difference", "{count} differences"),
    ]
    if !changed.isEmpty {
      parts.append(
        t(
          "worth {amount} at average cost",
          ["amount": InvText.money(InvStock.amount(Int64(minor), precision: inventory.precision), format)]))
    }
    return VStack(alignment: .leading, spacing: 12) {
      Text(parts.joined(separator: " · "))
        .font(.web(14))
        .foregroundStyle(palette.slate(600))
      FlowLayout(spacing: 8, lineSpacing: 8) {
        if !counts.isEmpty {
          WebButton(t("Clear counts"), variant: .ghost) { counts = [:] }
        }
        WebButton(t("Post adjustment"), loading: posting) { post(changed, warehouse: warehouse) }
          .disabled(changed.isEmpty)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }

  /// Each item counted, with the difference from what is on record.
  private func differences(_ items: [JSONValue], levels: [String: InvStockLevel], warehouse: String)
    -> [InventoryWrites.StockEntryInput.Line]
  {
    items.compactMap { item in
      guard let counted = IwCountDraft.parse(counts[item.rid] ?? "") else { return nil }
      let quantity = IwPreview.subtract(counted, onRecord(levels[item.rid], warehouse: warehouse))
      return InventoryWrites.StockEntryInput.Line(productId: item.rid, quantity: quantity)
    }
  }

  /// The average cost on the count date, or the cost price before there is any stock.
  private func unitCost(_ id: String, _ levels: [String: InvStockLevel], _ inventory: InvInventory) -> Double {
    if let level = levels[id], level.quantity > 0 { return level.unitCost }
    return inventory.product(id)?.num("costPrice") ?? 0
  }

  private func post(_ changed: [InventoryWrites.StockEntryInput.Line], warehouse: String) {
    let input = InventoryWrites.StockEntryInput(
      kind: "adjustment", date: date, warehouseId: warehouse, reason: "count", reference: t("Stock count"), notes: "",
      lines: changed)
    posting = true
    Task {
      let entry = await IwSave.run(model, done: { (entry: JSONValue) in
        t("{number} saved", ["number": entry.str("number")])
      }) { ctx in
        try InventoryWrites.recordStockEntry(ctx, input)
      }
      posting = false
      if let entry {
        counts = [:]
        router.push(.stockEntry(id: entry.rid))
      }
    }
  }

  private func load(_ key: String) {
    guard key != loadedKey else { return }
    loadedKey = key
    counts = IwCountDraft.load(key)
  }

  /// The warehouses in use; the default one is chosen until another is.
  private func warehouseOptions(_ inventory: InvInventory) -> [SelectOption<String>] {
    let defaultId = inventory.defaultWarehouse?.rid ?? ""
    var options: [SelectOption<String>] = []
    for warehouse in inventory.warehouses where !warehouse.flag("archived") {
      // The default stands for "" (nothing chosen yet), as the web's select shows it.
      options.append(SelectOption(warehouse.rid == defaultId ? "" : warehouse.rid, localName(warehouse)))
    }
    return options
  }

  /// `levels.get(id)?.byWarehouse.get(warehouse) ?? 0`: on record in the
  /// warehouse (none when no warehouse is chosen and there is no default).
  private func onRecord(_ level: InvStockLevel?, warehouse: String) -> Double {
    level?.byWarehouse[warehouse] ?? 0
  }

  /// Back to the inventory, where the count is opened from.
  private func backToInventory() {
    if router.path.isEmpty {
      router.go(.inventory)
    } else {
      router.back()
    }
  }

  /// "SKU · unit", or "—".
  private func code(_ item: JSONValue) -> String {
    let line = InvText.joined([item.str("sku"), item.str("unit")])
    return line.isEmpty ? "—" : line
  }
}

/// A counted item: its name and code, on record, the count typed and the difference.
struct IwCountRow: View {
  let item: JSONValue
  let code: String
  let onRecord: Double
  let format: CompanyFormat
  @Binding var text: String
  @Environment(\.palette) private var palette

  var body: some View {
    let counted = IwCountDraft.parse(text)
    let invalid = !text.trimmingCharacters(in: .whitespaces).isEmpty && counted == nil
    let difference = counted.map { IwPreview.subtract($0, onRecord) }
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(InvText.name(item)).font(.web(16, .medium)).foregroundStyle(palette.slate(900)).lineLimit(2)
        Text(code).font(.web(12)).foregroundStyle(palette.slate(500)).lineLimit(1)
        Text("\(t("On record")) \(format.quantity(onRecord))")
          .font(.web(12, tabular: true))
          .foregroundStyle(palette.slate(600))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .trailing, spacing: 4) {
        TextInput(text: $text, keyboard: .decimalPad)
          .environment(\.fieldInvalid, invalid)
          .environment(\.layoutDirection, .leftToRight)
          .frame(width: 96)
          .accessibilityLabel(Text(t("Counted quantity of {name}", ["name": InvText.name(item)])))
        Text(differenceText(difference))
          .font(.web(12, .medium, tabular: true))
          .foregroundStyle(differenceColor(difference))
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }

  private func differenceText(_ difference: Double?) -> String {
    guard let difference else { return "—" }
    return (difference > 0 ? "+" : "") + format.quantity(difference)
  }

  private func differenceColor(_ difference: Double?) -> Color {
    guard let difference, difference != 0 else { return palette.slate(500) }
    return difference < 0 ? palette[.red(600)] : palette[.emerald(700)]
  }
}

/// Counts typed and not posted yet, kept on this iPhone per company and warehouse.
@MainActor
enum IwCountDraft {
  static func key(_ companyId: String, _ warehouseId: String) -> String {
    warehouseId.isEmpty ? "" : "stock-count:\(companyId):\(warehouseId)"
  }

  static func load(_ key: String) -> [String: String] {
    guard !key.isEmpty, let data = UserDefaults.standard.data(forKey: key),
      let stored = try? JSONDecoder().decode([String: String].self, from: data)
    else { return [:] }
    return stored
  }

  static func store(_ counts: [String: String], key: String) {
    guard !key.isEmpty else { return }
    if counts.isEmpty {
      UserDefaults.standard.removeObject(forKey: key)
    } else if let data = try? JSONEncoder().encode(counts) {
      UserDefaults.standard.set(data, forKey: key)
    }
  }

  /// `parseCount(text)`: a number of 0 or more (Arabic digits too), or nil.
  static func parse(_ text: String) -> Double? {
    var cleaned = String.UnicodeScalarView()
    for scalar in Money.normalizeDigits(text).unicodeScalars where scalar != "," && !scalar.properties.isWhitespace {
      cleaned.append(scalar)
    }
    let number = String(cleaned)
    if number.isEmpty { return nil }
    guard let value = Double(number), value.isFinite, value >= 0 else { return nil }
    return value
  }
}
