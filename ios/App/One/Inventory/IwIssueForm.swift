import MahamKit
import SwiftUI

/// `/inventory/issues/new` (`src/apps/books/pages/inventory/issue-form.tsx`)
/// on a phone: uniforms and other items handed from a warehouse to an
/// employee. Whoever looks after a sub-warehouse sends them for approval;
/// an approver issues them at once. Saved through the port of the web's
/// `issueStock` (MahamKit/Write/Inventory).
struct IwIssueFormPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var warehouseId: String
  @State private var date = ISODates.today()
  @State private var employeeId: String?
  @State private var notes = ""
  @State private var rows: [IwIssueRow] = [IwIssueRow()]
  @State private var saving = false
  @State private var error: String?

  init() {
    _warehouseId = State(initialValue: IwIntent.takeIssueWarehouse() ?? "")
  }

  var body: some View {
    let one = model.one
    let format = one.format
    let inventory = InvInventoryCache.inventory(one)
    let link = IwSave.link(model)
    let approver = IwStockIssues.isApprover(link)
    let sources = issueSources(inventory, link: link)
    let from = sources.contains { $0.rid == warehouseId } ? warehouseId : (sources.first?.rid ?? "")
    let waiting = IwIssueForm.waiting(one)
    WebPage {
      PageHeader(
        t("Issue items"),
        description: approver
          ? t("Hand uniforms and other items to an employee. The stock leaves the warehouse at once.")
          : t(
            "Hand uniforms and other items to an employee. An approver confirms it, then the stock leaves your warehouse."
          ),
        breadcrumb: t("Issued items"), onBreadcrumb: { router.back() })
      if sources.isEmpty {
        Card {
          WebEmptyState(
            icon: .shirt, title: t("There is no warehouse you can issue items from"),
            description: t("The owner, an admin or an accountant sets up sub-warehouses and who issues items from them."))
        }
      } else {
        VStack(alignment: .leading, spacing: 24) {
          headCard(sources, inventory: inventory, from: from)
          linesCard(inventory, from: from, waiting: waiting, format: format)
          Card {
            CardBody {
              Field(t("Notes"), optional: true) {
                IwTextArea(text: $notes)
              }
            }
          }
        }
      }
    }
    .stickyActions {
      WebButton(t("Cancel"), variant: .outline) { router.back() }
      if IwGate.issues && !sources.isEmpty {
        WebButton(approver ? t("Issue items") : t("Send for approval"), icon: approver ? Icon.shirt : Icon.send, loading: saving) {
          save(from: from, inventory: inventory, link: link)
        }
      }
    }
  }

  /// Warehouses the person may issue from; a sub-warehouse they look after first.
  private func issueSources(_ inventory: InvInventory, link: IwStockIssues.Link?) -> [JSONValue] {
    let allowed = inventory.warehouses.filter { IwStockIssues.issuesFrom($0, link) }
    return allowed.filter { $0.text("parentId") != nil } + allowed.filter { $0.text("parentId") == nil }
  }

  // MARK: Who and where

  private func headCard(_ sources: [JSONValue], inventory: InvInventory, from: String) -> some View {
    let people = IwIssueForm.recipients(model.one)
    let canSee = Roles.canSeePeople(model.one.writeLink?.role)
    let unknown = people.isEmpty && !canSee
    let noEmployee = error != nil && (employeeId ?? "").isEmpty
    let fieldError: String? =
      unknown ? t("Connect to the internet to see who items can be issued to.") : (noEmployee ? error : nil)
    return Card {
      CardBody {
        VStack(alignment: .leading, spacing: 16) {
          Field(t("From warehouse")) {
            Select(
              selection: Binding(get: { from }, set: { warehouseId = $0 }),
              options: sources.map { SelectOption($0.rid, inventory.path($0)) })
          }
          Field(t("Date")) {
            DateField(value: $date, required: true)
          }
          Field(t("Issued to"), error: fieldError) {
            Combobox(
              selection: Binding(
                get: { employeeId },
                set: { value in
                  employeeId = value
                  error = nil
                }),
              options: people.map { person in
                ComboOption(
                  value: person.str("employeeId"), label: InvIssues.recipientLabel(person, arabic: InvText.arabic),
                  detail: person.str("number"),
                  keywords: "\(person.str("name")) \(person.str("nameAr")) \(person.str("jobTitle")) \(person.str("number"))")
              }, placeholder: t("Choose an employee…"), searchPlaceholder: t("Search employees…"),
              emptyText: t("No matches"))
          }
        }
      }
    }
  }

  // MARK: The items

  private func linesCard(
    _ inventory: InvInventory, from: String, waiting: [String: Double], format: CompanyFormat
  ) -> some View {
    let warehouse = inventory.warehouse(from)
    let items = inventory.stockItems.filter { !$0.flag("archived") }
    let options = items.map { item in
      ComboOption(
        value: item.rid, label: localName(item),
        detail: t("{quantity} left", ["quantity": format.quantity(max(0, left(item.rid, inventory, from, waiting)))]),
        keywords: "\(item.str("name")) \(item.str("nameAr")) \(item.str("sku")) \(item.str("barcode"))")
    }
    .sorted { $0.label.localizedCompare($1.label) == .orderedAscending }
    let lineError = error != nil && !(employeeId ?? "").isEmpty ? error : nil
    return Card {
      CardHeader(t("Items"), description: lineError)
      VStack(spacing: 0) {
        ForEach($rows) { $row in
          IwIssueLine(
            row: $row, number: (rows.firstIndex { $0.id == row.id } ?? 0) + 1, options: options,
            left: row.productId.isEmpty ? 0 : left(row.productId, inventory, from, waiting),
            asked: asked(row.productId), item: inventory.product(row.productId),
            warehouseName: warehouse.map { localName($0) } ?? "", format: format, canRemove: rows.count > 1,
            onRemove: { rows.removeAll { $0.id == row.id } })
        }
      }
      WebButton(t("Add an item"), icon: .plus, variant: .outline, size: .sm) { rows.append(IwIssueRow()) }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
    }
  }

  /// In the warehouse now, less what waits to be issued from it.
  private func left(_ productId: String, _ inventory: InvInventory, _ from: String, _ waiting: [String: Double])
    -> Double
  {
    let here = inventory.level(productId)?.byWarehouse[from] ?? 0
    return IwPreview.subtract(here, waiting[IwStockIssues.stockKey(from, productId)] ?? 0)
  }

  /// Lines of the same item count together.
  private func asked(_ productId: String) -> Double {
    var sum = 0.0
    for row in rows where row.productId == productId { sum = IwPreview.add(sum, row.quantity) }
    return sum
  }

  // MARK: Saving

  /// Who the issue names as having issued it: whoever looks after the
  /// sub-warehouse, with their job title, when it is them; else the account.
  private func issuerName(_ warehouse: JSONValue?, link: IwStockIssues.Link?) -> String {
    if let keeper = warehouse?.obj("keeper"), let name = keeper.text("name"),
      link == nil || keeper.str("userId") == link?.userId
    {
      let title = keeper.str("jobTitle")
      return title.isEmpty ? name : "\(name) (\(title))"
    }
    return model.session?.user.authorName ?? ""
  }

  private func save(from: String, inventory: InvInventory, link: IwStockIssues.Link?) {
    let people = IwIssueForm.recipients(model.one)
    guard let recipient = people.first(where: { $0.str("employeeId") == (employeeId ?? "") }) else {
      error = t("Choose the employee who receives the items.")
      return
    }
    let lines = rows.filter { !$0.productId.isEmpty && $0.quantity > 0 }
    if lines.isEmpty {
      error = t("Add at least one item with a quantity.")
      return
    }
    let input = IwStockIssues.Input(
      date: date, warehouseId: from, recipient: recipient,
      lines: lines.map { IwStockIssues.Input.Line(productId: $0.productId, quantity: $0.quantity) }, notes: notes)
    let issuer = IwStockIssues.Issuer(userId: link?.userId, name: issuerName(inventory.warehouse(from), link: link))
    saving = true
    Task {
      let made = await IwSave.run(model) { ctx in try IwStockIssues.issueStock(ctx, input, issuer: issuer, link: link) }
      saving = false
      guard let made else { return }
      if let issue = made.issue {
        model.confirm(t("{number} issued", ["number": issue.str("number")]))
        router.back()
        router.push(.stockIssue(id: issue.rid))
      } else if let request = made.request {
        model.confirm(t("Sent for approval. The stock leaves the warehouse once it is confirmed."))
        router.back()
        router.push(.stockIssue(id: request.str("subjectId")))
      }
    }
  }
}

/// The issue form's rules.
@MainActor
enum IwIssueForm {
  /// Who items can be issued to: the current employees, as an issue names
  /// them (`recipientOf`), by name.
  static func recipients(_ one: OneData) -> [JSONValue] {
    one.records(.employees)
      .filter { $0.str("status") != "left" }
      .sorted { InvText.byName($0, $1) }
      .map { employee in
        .object([
          "employeeId": .string(employee.rid),
          "number": .string(employee.str("number")),
          "name": .string(employee.str("name")),
          "nameAr": .string(employee.str("nameAr")),
          "jobTitle": .string(employee.str("jobTitle")),
          "jobTitleAr": .string(employee.str("jobTitleAr")),
        ])
      }
  }

  /// `waitingQuantities(waitingIssueRequests(companyId))`: asked for and not issued yet.
  static func waiting(_ one: OneData) -> [String: Double] {
    let kept = Set(one.records(.stockIssues).map(\.rid))
    let requests = one.records(.approvals).filter { request in
      let status = request.str("status")
      return (status == "pending" || status == "approved") && IwStockIssues.isStockIssueRequest(request)
        && (status != "approved" || !kept.contains(request.str("subjectId")))
    }
    return IwStockIssues.waitingQuantities(requests)
  }
}

/// One line of items being issued.
struct IwIssueRow: Identifiable {
  let id = UUID().uuidString
  var productId = ""
  var quantity: Double = 1
}

/// A line: the item, what is left in the warehouse, the quantity.
struct IwIssueLine: View {
  @Binding var row: IwIssueRow
  let number: Int
  let options: [ComboOption]
  let left: Double
  let asked: Double
  let item: JSONValue?
  let warehouseName: String
  let format: CompanyFormat
  let canRemove: Bool
  let onRemove: () -> Void
  @Environment(\.palette) private var palette

  var body: some View {
    let short = !row.productId.isEmpty && asked > left
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .bottom, spacing: 8) {
        Field(t("Item")) {
          Combobox(
            selection: Binding(
              get: { row.productId.isEmpty ? nil : row.productId }, set: { row.productId = $0 ?? "" }),
            options: options, placeholder: t("Choose an item…"), searchPlaceholder: t("Search items…"))
        }
        WebButton(icon: .trash2, label: t("Remove item {number}", ["number": String(number)])) { onRemove() }
          .disabled(!canRemove)
      }
      if let item {
        Text(
          t(
            "{quantity} left in {warehouse}",
            ["quantity": InvText.quantity(max(0, left), unit: item.str("unit"), format), "warehouse": warehouseName])
        )
        .font(.web(12))
        .foregroundStyle(palette.slate(500))
      }
      Field(t("Quantity")) {
        IwNumberField(value: $row.quantity)
      }
      if short {
        Text(t("Only {quantity} left to issue.", ["quantity": format.quantity(max(0, left))]))
          .font(.web(12))
          .foregroundStyle(palette[.amber(700)])
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }
}
