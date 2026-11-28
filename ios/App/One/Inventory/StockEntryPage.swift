import MahamKit
import SwiftUI

/// `/inventory/entries/:id` (`src/apps/books/pages/inventory/entry-view.tsx`):
/// an opening stock entry, adjustment or transfer, Posted or Void; its date,
/// warehouses, reason and reference; what each line moved and was worth;
/// and what it posted.
struct InvStockEntryPage: View {
  let id: String
  @Environment(AppModel.self) private var model
  @State private var confirming = false

  init(id: String) {
    self.id = id
  }

  var body: some View {
    let one = model.one
    let format = one.format
    let inventory = InvInventoryCache.inventory(one)
    let entry = one.record(.stockEntries, id)
    let number = entry?.str("number") ?? ""
    RecordDetailPage(record: entry, title: title(entry), breadcrumb: t("Inventory")) {
      Badge(status: InvLabels.postedBadge(entry?.str("status") ?? ""))
    } actions: {
      if entry?.str("status") == "posted", IwGate.entries, IwGate.edits(model) {
        WebButton(t("Void entry"), icon: .ban, variant: .outline) { confirming = true }
      }
    } content: {
      if let entry {
        InvFactsCard(facts: facts(entry, inventory: inventory, format: format), note: entry.text("notes"))
        InvEntryLinesCard(entry: entry, inventory: inventory, format: format)
      }
    }
    .webDialog(
      isPresented: $confirming, title: t("Void {number}?", ["number": number]),
      description: t("The entry stays on record, and its stock movements leave the books.")
    ) {
      EmptyView()
    } footer: {
      IwConfirmFooter(label: t("Void entry"), onCancel: { confirming = false }, onConfirm: { voidNow(number) })
    }
  }

  /// `voidStockEntry(id)`, confirmed.
  private func voidNow(_ number: String) {
    confirming = false
    let id = self.id
    Task {
      await IwSave.run(model, done: { (_: Void) in t("{number} voided", ["number": number]) }) { ctx in
        try InventoryWrites.voidStockEntry(ctx, id: id)
      }
    }
  }

  /// "Stock adjustment ADJ-0004".
  private func title(_ entry: JSONValue?) -> String {
    guard let entry else { return t("Stock entry not found") }
    return "\(InvLabels.entryKind(entry.str("kind"))) \(entry.str("number"))"
  }

  private func facts(_ entry: JSONValue, inventory: InvInventory, format: CompanyFormat) -> [InvFact] {
    let transfer = entry.str("kind") == "transfer"
    var list = [
      InvFact(t("Date"), format.date(entry.text("date"))),
      InvFact(
        transfer ? t("From warehouse") : t("Warehouse"), inventory.warehouseName(entry.text("warehouseId"))),
    ]
    if transfer {
      list.append(InvFact(t("To warehouse"), inventory.warehouseName(entry.text("toWarehouseId"))))
    }
    list.append(InvFact(t("Reason"), InvLabels.reason(entry.text("reason")) ?? ""))
    list.append(InvFact(t("Reference"), entry.str("reference")))
    list.append(InvFact(t("Voided on"), format.dateTime(entry.text("voidedAt"))))
    return list
  }
}

/// The entry's stock items: each with its quantity (adjustments that add
/// stock with "+"), its unit cost and value; then what was posted.
struct InvEntryLinesCard: View {
  let entry: JSONValue
  let inventory: InvInventory
  let format: CompanyFormat
  @Environment(AppModel.self) private var model

  var body: some View {
    let lines = entry.list("lines")
    let counted = countedMovements
    Card {
      CardHeader(t("Stock items"))
      VStack(spacing: 0) {
        InvColumns(t("Item"), t("Value"))
        ForEach(Array(lines.indices), id: \.self) { index in
          lineRow(lines[index], counted: counted)
        }
      }
      if entry.str("status") == "posted" {
        InvCardNote(posting(counted))
      }
    }
  }

  /// The entry's movements, a transfer's counted once (the stock coming in).
  private var countedMovements: [JSONValue] {
    let id = entry.rid
    let transfer = entry.str("kind") == "transfer"
    return inventory.movements.filter { movement in
      movement.str("sourceId") == id && (!transfer || movement.num("quantity") > 0)
    }
  }

  private func lineRow(_ line: JSONValue, counted: [JSONValue]) -> some View {
    let product = model.one.record(.products, line.str("productId"))
    let void = entry.str("status") == "void"
    let quantity = line.num("quantity")
    let minor = InvStock.minorSum(counted.filter { $0.str("lineId") == line.rid }, precision: inventory.precision)
    let value = InvStock.amount(minor, precision: inventory.precision)
    let unitCost = quantity != 0 ? abs(value / quantity) : 0
    let sign = quantity > 0 && entry.str("kind") == "adjustment" ? "+" : ""
    return InvRow(
      title: product.map { localName($0) } ?? "—",
      subtitle: sign + InvText.quantity(quantity, unit: product?.str("unit") ?? "", format),
      detail: void ? nil : "\(t("Unit cost")) \(InvText.unitAmount(unitCost, format))",
      amount: void ? "—" : InvText.money(value, format))
  }

  /// What the entry posted (`posting`).
  private func posting(_ counted: [JSONValue]) -> String {
    let total = InvStock.minorSum(counted, precision: inventory.precision)
    let amount = { (minor: Int64) in InvText.money(InvStock.amount(minor, precision: inventory.precision), format) }
    switch entry.str("kind") {
    case "transfer":
      return t("Transfers stay in the inventory account, so nothing is posted.")
    case "opening":
      return t("Inventory against opening balance equity: {amount}", ["amount": amount(total)])
    default:
      if total < 0 {
        return t("Inventory adjustments against inventory: {amount}", ["amount": amount(-total)])
      }
      return t("Inventory against inventory adjustments: {amount}", ["amount": amount(total)])
    }
  }
}
