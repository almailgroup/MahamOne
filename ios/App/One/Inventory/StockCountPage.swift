import MahamKit
import SwiftUI

/// `/inventory/count` (`src/apps/books/pages/inventory/count.tsx`), read
/// only: the count sheet before counting, each stock item in use with the
/// quantity on record in the warehouse chosen at the end of the count date.
/// Counting and posting the differences stay on the web.
struct InvStockCountPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @State private var warehouseId = ""
  @State private var date = ISODates.today()
  @State private var query = ""
  @State private var shown = 50

  var body: some View {
    let one = model.one
    let format = one.format
    let inventory = InvInventoryCache.inventory(one)
    let items = inventory.stockItems.filter { !$0.flag("archived") }.sorted { InvText.byName($0, $1) }
    let warehouse = warehouseId.isEmpty ? (inventory.defaultWarehouse?.rid ?? "") : warehouseId
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(
        t("Stock count"), description: t("Count what is on the shelves, then post the differences as one adjustment."),
        breadcrumb: t("Inventory"), onBreadcrumb: { backToInventory() })
      if items.isEmpty {
        emptyCard(one)
      } else {
        sheetCard(items, inventory: inventory, warehouse: warehouse, format: format)
      }
    }
    .onChange(of: query) { _, _ in shown = 50 }
  }

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
          WebButton(t("New stock item")) { router.push(.newProduct) }
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
      InvColumns(t("Item"), t("On record"))
      if visible.isEmpty {
        InvNothingMatches()
      } else {
        ForEach(visible.prefix(shown).map(Rec.init)) { record in
          InvRow(
            title: InvText.name(record.raw), subtitle: code(record.raw),
            amount: format.quantity(onRecord(levels[record.id], warehouse: warehouse)))
        }
        if visible.count > shown {
          ListShowMore(remaining: visible.count - shown) { shown += 50 }
        }
      }
    }
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
