import MahamKit
import SwiftUI

/// `/inventory/landed-costs/new` (`src/apps/books/pages/inventory/landed-cost-form.tsx`)
/// on a phone: charges on a bill (customs duty, freight, clearing,
/// insurance) allocated to the stock received on that bill or an earlier
/// one, saved through the port of the web's `saveLandedCost`
/// (MahamKit/Write/Inventory).
struct IwLandedCostFormPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var billId: String
  @State private var targetId: String?
  @State private var sourceIds: [String]?
  @State private var targetIds: [String]?
  @State private var method = "value"
  @State private var notes = ""
  @State private var saving = false

  init() {
    _billId = State(initialValue: IwIntent.takeLandedBill() ?? "")
  }

  var body: some View {
    let plan = IwLandedPlan(
      model.one, billId: billId, targetId: targetId, sourceIds: sourceIds, targetIds: targetIds, method: method)
    let format = model.one.format
    WebPage {
      PageHeader(
        t("Allocate landed costs"),
        description: t(
          "Add customs duty, freight, clearing and insurance to the cost of the goods they brought in. The charges move from expenses to inventory."
        ),
        breadcrumb: t("Inventory"), onBreadcrumb: { router.back() })
      VStack(alignment: .leading, spacing: 24) {
        chargesCard(plan, format: format)
        if plan.costBill != nil {
          goodsCard(plan, format: format)
        }
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
      if IwGate.landedCosts && IwGate.edits(model) {
        WebButton(t("Allocate"), loading: saving) { save(plan) }
          .disabled(plan.allocation == nil)
      }
    }
  }

  // MARK: Charges

  private func chargesCard(_ plan: IwLandedPlan, format: CompanyFormat) -> some View {
    Card {
      CardHeader(t("Charges"), description: t("The bill from the customs broker, the shipper or the insurer."))
      CardBody {
        VStack(alignment: .leading, spacing: 16) {
          Field(t("Bill with the charges")) {
            Combobox(
              selection: Binding(
                get: { billId.isEmpty ? nil : billId },
                set: { value in
                  billId = value ?? ""
                  sourceIds = nil
                  targetId = nil
                  targetIds = nil
                }),
              options: plan.bills.map { plan.option($0, format: format) }, placeholder: t("Choose a bill…"),
              searchPlaceholder: t("Search bills…"))
          }
          if plan.costBill != nil {
            if plan.charges.isEmpty {
              Text(t("This bill has only stock items. Choose the bill with the charges."))
                .font(.web(14))
                .foregroundStyle(palette.slate(500))
            } else {
              chargeList(plan, format: format)
            }
          }
        }
      }
    }
  }

  private func chargeList(_ plan: IwLandedPlan, format: CompanyFormat) -> some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    return VStack(spacing: 0) {
      ForEach(plan.charges, id: \.id) { charge in
        IwCheckRow(
          label: charge.label.isEmpty ? t("Line") : charge.label,
          description: plan.taken.contains(charge.id) ? t("Already allocated") : nil,
          checked: plan.chosenSources.contains(charge.id),
          trailing: format.money(plan.amount(plan.parts[charge.id] ?? 0))
        ) {
          sourceIds = IwLandedPlan.toggle(plan.chosenSources, charge.id)
        }
        .disabled(plan.taken.contains(charge.id))
        .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
      }
    }
    .clipShape(shape)
    .border(palette.slate(200), in: shape)
  }

  // MARK: Goods

  private func goodsCard(_ plan: IwLandedPlan, format: CompanyFormat) -> some View {
    Card {
      CardHeader(t("Goods"), description: t("The bill the stock was received on, dated on or before the charges."))
      CardBody {
        VStack(alignment: .leading, spacing: 16) {
          Field(t("Bill with the goods")) {
            Combobox(
              selection: Binding(
                get: { plan.target?.rid },
                set: { value in
                  targetId = value ?? ""
                  targetIds = nil
                }),
              options: plan.goodsBills.map { plan.option($0, format: format) }, placeholder: t("Choose a bill…"),
              searchPlaceholder: t("Search bills…"), emptyText: t("No bills with stock items on or before this date."))
          }
          VStack(alignment: .leading, spacing: 6) {
            Text(t("Split")).font(.web(14, .medium)).foregroundStyle(palette.slate(700))
            Segmented(
              selection: $method,
              options: [SegmentOption("value", t("By value")), SegmentOption("quantity", t("By quantity"))])
          }
          if plan.target != nil {
            goodsList(plan, format: format)
          }
          if let allocation = plan.allocation, let bill = plan.costBill {
            Text(
              t(
                "{amount} added to the cost of the goods on {date}.",
                ["amount": format.money(plan.amount(allocation.total)), "date": format.date(bill.text("issueDate"))])
            )
            .font(.web(14))
            .foregroundStyle(palette.slate(600))
          }
        }
      }
    }
  }

  private func goodsList(_ plan: IwLandedPlan, format: CompanyFormat) -> some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    return VStack(spacing: 0) {
      ForEach(plan.goodsLines.map(Rec.init)) { record in
        goodsRow(record.raw, plan: plan, format: format)
      }
    }
    .clipShape(shape)
    .border(palette.slate(200), in: shape)
  }

  private func goodsRow(_ line: JSONValue, plan: IwLandedPlan, format: CompanyFormat) -> some View {
    let share = plan.allocation?.shares.first { $0.lineId == line.rid }
    let item = model.one.record(.products, line.str("productId"))
    let quantity = line.num("quantity")
    var parts = ["\(t("Quantity")) \(format.quantity(quantity))"]
    if let share {
      parts.append("\(t("Value")) \(format.money(plan.amount(share.lineValue)))")
      let unit = IwPreview.unitCost(minor: share.lineValue + share.share, quantity: quantity, precision: plan.precision)
      parts.append("\(t("New unit cost")) \(InvText.unitAmount(unit, format))")
    }
    let shareText = share.map { "\(t("Share")) \(format.money(plan.amount($0.share)))" }
    return VStack(alignment: .leading, spacing: 0) {
      IwCheckRow(
        label: item.map { localName($0) } ?? line.str("name"), description: parts.joined(separator: " · "),
        checked: plan.chosenTargets.contains(line.rid), trailing: shareText
      ) {
        targetIds = IwLandedPlan.toggle(plan.chosenTargets, line.rid)
      }
    }
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }

  // MARK: Saving

  private func save(_ plan: IwLandedPlan) {
    guard let bill = plan.costBill, let target = plan.target else { return }
    let input = InventoryWrites.LandedCostInput(
      billId: bill.rid, sourceLineIds: plan.chosenSources, targetBillId: target.rid,
      targetLineIds: plan.chosenTargets.count == plan.goodsLines.count ? [] : plan.chosenTargets, method: method,
      notes: notes)
    saving = true
    Task {
      let cost = await IwSave.run(model, done: { (cost: JSONValue) in
        t("{number} saved", ["number": cost.str("number")])
      }) { ctx in
        try InventoryWrites.saveLandedCost(ctx, input)
      }
      saving = false
      if let cost {
        router.back()
        router.push(.landedCost(id: cost.rid))
      }
    }
  }
}

/// What the landed cost form works out from what is chosen (the web form's
/// derived values): the issued bills, the charges and goods, and the split.
@MainActor
struct IwLandedPlan {
  struct Charge {
    let id: String
    let label: String
  }

  let company: JSONValue
  let precision: Int
  let products: [JSONValue]
  let clients: [JSONValue]
  /// Issued bills, newest first.
  let bills: [JSONValue]
  let costBill: JSONValue?
  let parts: [String: Int]
  /// Charges already allocated by another landed cost in use.
  let taken: Set<String>
  let charges: [Charge]
  let chosenSources: [String]
  /// Bills with stock items, dated on or before the bill with the charges.
  let goodsBills: [JSONValue]
  let target: JSONValue?
  let goodsLines: [JSONValue]
  let chosenTargets: [String]
  let allocation: IwPreview.Allocation?

  init(_ one: OneData, billId: String, targetId: String?, sourceIds: [String]?, targetIds: [String]?, method: String) {
    let company = one.company ?? .null
    self.company = company
    precision = Money.precision(company.str("currency"))
    products = one.records(.products)
    clients = one.records(.clients)
    // A local copy: closures below can't capture `self` before every property is set.
    let billList = one.records(.documents)
      .filter { $0.str("type") == "bill" && IwPreview.movesStock($0) }
      .sorted { a, b in
        let date = InvStock.plain(b.str("issueDate"), a.str("issueDate"))
        if date != 0 { return date < 0 }
        return b.str("number").localizedCompare(a.str("number")) == .orderedAscending
      }
    bills = billList
    let costBill = billList.first { $0.rid == billId }
    self.costBill = costBill
    parts = costBill.map { IwPreview.lineParts($0, company: company, clients: one.records(.clients)) } ?? [:]
    var taken = Set<String>()
    for cost in one.records(.landedCosts) where cost.str("status") == "active" && cost.str("billId") == billId {
      for id in cost.list("sourceLineIds").compactMap(\.string) { taken.insert(id) }
    }
    self.taken = taken
    var charges: [Charge] = []
    if let costBill {
      let stock = Set(IwPreview.stockLineIds(costBill, products: products))
      for item in costBill.list("items") where item.str("kind") == "item" && !stock.contains(item.rid) {
        charges.append(Charge(id: item.rid, label: item.str("name")))
      }
      for charge in costBill.list("charges") {
        charges.append(Charge(id: charge.rid, label: charge.str("label")))
      }
    }
    self.charges = charges
    chosenSources = sourceIds ?? charges.filter { !taken.contains($0.id) }.map(\.id)
    let productList = products
    let goodsBills: [JSONValue] =
      costBill.map { bill in
        billList.filter { candidate in
          InvStock.plain(candidate.str("issueDate"), bill.str("issueDate")) <= 0
            && !IwPreview.stockLineIds(candidate, products: productList).isEmpty
        }
      } ?? []
    self.goodsBills = goodsBills
    let target: JSONValue?
    if let targetId {
      target = goodsBills.first { $0.rid == targetId }
    } else {
      target = goodsBills.first { $0.rid == billId }
    }
    self.target = target
    var goodsLines: [JSONValue] = []
    if let target {
      let stock = Set(IwPreview.stockLineIds(target, products: productList))
      goodsLines = target.list("items").filter { stock.contains($0.rid) && $0.num("quantity") > 0 }
    }
    self.goodsLines = goodsLines
    chosenTargets = targetIds ?? goodsLines.map(\.rid)
    if let costBill, let target {
      allocation = IwPreview.landedCost(
        company: company, products: productList, clients: one.records(.clients), costBill: costBill,
        targetBill: target, sourceLineIds: chosenSources, targetLineIds: chosenTargets, method: method)
    } else {
      allocation = nil
    }
  }

  /// A bill in a list: its number, the vendor and the date.
  func option(_ bill: JSONValue, format: CompanyFormat) -> ComboOption {
    let vendor = clients.first { $0.rid == bill.str("clientId") }
    let name = vendor.map { localName($0) } ?? ""
    return ComboOption(
      value: bill.rid, label: bill.str("number"),
      detail: "\(name.isEmpty ? "—" : name) · \(format.date(bill.text("issueDate")))",
      keywords: "\(name) \(bill.str("vendorReference"))")
  }

  /// Minor units as an amount of the company currency.
  func amount(_ minor: Int) -> Double {
    InvStock.amount(Int64(minor), precision: precision)
  }

  static func toggle(_ list: [String], _ id: String) -> [String] {
    list.contains(id) ? list.filter { $0 != id } : list + [id]
  }
}
