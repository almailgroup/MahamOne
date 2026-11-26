import MahamKit
import SwiftUI

/// `/inventory/landed-costs/:id` (`src/apps/books/pages/inventory/landed-cost-view.tsx`):
/// the bill with the charges and the bill with the goods, how they were
/// split, and each item's share and what was added to its stock.
struct InvLandedCostPage: View {
  let id: String
  @Environment(AppModel.self) private var model

  init(id: String) {
    self.id = id
  }

  var body: some View {
    let one = model.one
    let format = one.format
    let inventory = InvInventoryCache.inventory(one)
    let cost = one.record(.landedCosts, id)
    RecordDetailPage(
      record: cost, title: "\(t("Landed cost")) \(cost?.str("number") ?? "")", breadcrumb: t("Inventory")
    ) {
      Badge(status: InvLabels.postedBadge(cost?.str("status") ?? "", allocated: true))
    } content: {
      if let cost {
        InvLandedCostSummary(cost: cost, format: format)
        InvAllocationCard(cost: cost, inventory: inventory, format: format)
      }
    }
  }
}

/// The bills, the split and the date; the charges and the notes.
struct InvLandedCostSummary: View {
  let cost: JSONValue
  let format: CompanyFormat
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let costBill = model.one.record(.documents, cost.str("billId"))
    let targetBill = model.one.record(.documents, cost.str("targetBillId"))
    let charges = chargeNames(costBill)
    Card {
      InvFactRows(
        facts: [
          bill(t("Bill with the charges"), costBill),
          bill(t("Bill with the goods"), targetBill),
          InvFact(t("Split"), cost.str("method") == "value" ? t("By value") : t("By quantity")),
          InvFact(t("Date"), costBill.map { format.date($0.text("issueDate")) } ?? "—"),
        ], onOpen: { route in router.push(route) }
      )
      .padding(.vertical, 4)
      if !charges.isEmpty {
        InvCardNote(t("Charges: {items}", ["items": charges.joined(separator: ", ")]))
      }
      if let notes = cost.text("notes") {
        InvCardNote(notes)
      }
    }
  }

  /// A bill's number, opening it; "—" when it isn't here.
  private func bill(_ label: String, _ document: JSONValue?) -> InvFact {
    guard let document else { return InvFact(label, "—") }
    return InvFact(label, document.str("number"), route: .purchaseDocument(.bill, id: document.rid), tabular: true)
  }

  /// The lines and charges of the bill that are the landed costs.
  private func chargeNames(_ bill: JSONValue?) -> [String] {
    guard let bill else { return [] }
    let ids = Set(cost.list("sourceLineIds").compactMap(\.string))
    var names: [String] = []
    for line in bill.list("items") where ids.contains(line.rid) {
      names.append(line.str("name"))
    }
    for charge in bill.list("charges") where ids.contains(charge.rid) {
      names.append(charge.str("label"))
    }
    return names
  }
}

/// How the charges were shared: each item's quantity received, its share
/// and what was added to its stock, the totals, and what went to cost of
/// sales when part of the goods had been sold.
struct InvAllocationCard: View {
  let cost: JSONValue
  let inventory: InvInventory
  let format: CompanyFormat

  var body: some View {
    let movements = inventory.movements.filter { $0.str("sourceId") == cost.rid }.sorted {
      InvStock.plain($0.rid, $1.rid) < 0
    }
    let precision = inventory.precision
    let total = InvStock.minorSum(movements, key: "sourceValue", precision: precision)
    let kept = InvStock.minorSum(movements, precision: precision)
    Card {
      CardHeader(t("Allocation"), description: allocationNote(movements))
      if !movements.isEmpty {
        VStack(spacing: 0) {
          InvColumns(t("Item"), t("Share"))
          ForEach(movements.map(Rec.init)) { record in
            share(record.raw)
          }
          InvRow(
            title: t("Total"),
            detail: "\(t("Added to stock")) \(InvText.money(InvStock.amount(kept, precision: precision), format))",
            amount: InvText.money(InvStock.amount(total, precision: precision), format))
        }
        if total != kept {
          InvCardNote(
            t(
              "Part of the goods had been sold by then, so {amount} went to cost of sales.",
              ["amount": InvText.money(InvStock.amount(total - kept, precision: precision), format)]))
        }
      }
    }
  }

  /// Why nothing is allocated, when nothing is.
  private func allocationNote(_ movements: [JSONValue]) -> String? {
    if cost.str("status") == "void" { return t("This landed cost is void; nothing is allocated.") }
    if movements.isEmpty { return t("Nothing is allocated: one of the bills is no longer issued.") }
    return nil
  }

  private func share(_ movement: JSONValue) -> some View {
    InvRow(
      title: InvText.name(inventory.product(movement.str("productId"))),
      subtitle: "\(t("Quantity")) \(format.quantity(movement.num("basisQuantity")))",
      detail: "\(t("Added to stock")) \(InvText.money(movement.num("value"), format))",
      amount: InvText.money(movement.num("sourceValue"), format))
  }
}
