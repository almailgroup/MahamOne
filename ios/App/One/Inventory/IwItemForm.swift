import MahamKit
import SwiftUI

// An item created or edited natively (`src/apps/books/pages/products/item-dialog.tsx`):
// a service, a non-stock item or a stock item, its code, names, prices,
// unit, accounts and taxes, and a new stock item's opening stock; saved
// through the port of the web's `saveItem` (MahamKit/Write/Inventory).

/// An item being added or edited (`ItemDialog`'s state).
struct IwItemDraft {
  var product: JSONValue
  /// The item as it was opened.
  let original: JSONValue
  let isNew: Bool
  var opening: InventoryWrites.OpeningStock
  var error: String?

  /// `createProduct(company.id, { taxRateIds: company.defaults.defaultTaxRateIds, kind })`.
  @MainActor
  static func new(_ one: OneData, kind: String) -> IwItemDraft {
    let company = one.company
    let taxes = company?["defaults"]?["defaultTaxRateIds"] ?? .array([])
    let product = Defaults.createProduct(
      companyId: one.companyId ?? "", ["taxRateIds": taxes, "kind": .string(kind)])
    return IwItemDraft(product, one: one, isNew: true)
  }

  @MainActor
  static func edit(_ product: JSONValue, one: OneData) -> IwItemDraft {
    IwItemDraft(product, one: one, isNew: false)
  }

  @MainActor
  private init(_ product: JSONValue, one: OneData, isNew: Bool) {
    let company = one.company
    var start = product
    // An item saved before units came from the list: its unit picked when it is one of the list's.
    if SyncJSON.truthy(company?["items"]?["units"]),
      Units.listedUnit(company, unit: product.str("unit"), unitId: product.text("unitId")) == nil
    {
      start.set("unitId", Units.matchUnit(product.str("unit"), company).map(JSONValue.string))
    }
    self.product = start
    original = product
    self.isNew = isNew
    let inventory = InvInventoryCache.inventory(one)
    opening = InventoryWrites.OpeningStock(
      warehouseId: inventory.defaultWarehouse?.rid ?? "", quantity: 0, unitCost: product.num("costPrice"),
      date: ISODates.today())
  }

  /// `draft.kind ?? 'service'`.
  var kind: String { InventoryWrites.productKind(product) }
  /// The kind the item was opened with.
  var wasKind: String { InventoryWrites.productKind(original) }
}

/// Bindings into the draft's item.
@MainActor
enum IwItemBind {
  static func text(_ draft: Binding<IwItemDraft>, _ key: String) -> Binding<String> {
    Binding(
      get: { draft.wrappedValue.product[key]?.string ?? "" },
      set: { draft.wrappedValue.product.set(key, .string($0)) })
  }

  static func number(_ draft: Binding<IwItemDraft>, _ key: String) -> Binding<Double> {
    Binding(
      get: { draft.wrappedValue.product[key]?.double ?? 0 },
      set: { draft.wrappedValue.product.set(key, .number($0)) })
  }

  /// A choice that is null when empty (`value || null`).
  static func choice(_ draft: Binding<IwItemDraft>, _ key: String) -> Binding<String?> {
    Binding(
      get: { draft.wrappedValue.product[key]?.string },
      set: { value in
        let text = value ?? ""
        draft.wrappedValue.product.set(key, text.isEmpty ? .null : .string(text))
      })
  }
}

/// Saving an item (`ItemDialog.save`).
@MainActor
enum IwItemSaving {
  /// Saves the draft; false when it was refused (the reason is on the draft or in a toast).
  static func save(_ draft: Binding<IwItemDraft>, model: AppModel) async -> Bool {
    let current = draft.wrappedValue
    let name = current.product.str("name").trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty {
      draft.wrappedValue.error = t("Enter a name for the item.")
      return false
    }
    let kind = current.kind
    var input = current.product
    input.set("kind", .string(kind))
    var opening: InventoryWrites.OpeningStock?
    if current.isNew && kind == "stock" && current.opening.quantity > 0 {
      var start = current.opening
      start.unitCost = current.product.num("costPrice")
      opening = start
    }
    let start = opening
    // A new item without an SKU takes its code from the cloud's counter when it can.
    let request = try? await model.one.write { ctx in InventoryWrites.itemCounterRequest(ctx, input, opening: start) }
    var reserved: ReservedCounter?
    if let request {
      reserved = await model.one.reserveNumber(DcCounterRequest(kind: request.kind, date: request.date, min: request.min))
    }
    let counter = reserved
    let saved = await IwSave.run(model, done: { (_: JSONValue) in t("{name} saved", ["name": name]) }) { ctx in
      try InventoryWrites.saveItem(ctx, input, opening: start, reserved: counter)
    }
    return saved != nil
  }
}

/// The item form's fields (`ItemDialog`'s body).
struct IwItemFields: View {
  @Binding var draft: IwItemDraft
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let inventory = InvInventoryCache.inventory(one)
    VStack(alignment: .leading, spacing: 16) {
      kindPicker(inventory)
      nameAndCode(one)
      Field(t("Arabic name"), hint: t("Printed on Arabic and bilingual documents."), optional: true) {
        TextInput(text: IwItemBind.text($draft, "nameAr"))
          .environment(\.layoutDirection, .rightToLeft)
      }
      Field(t("Description"), hint: t("Copied onto invoice lines."), optional: true) {
        IwTextArea(text: IwItemBind.text($draft, "description"))
      }
      Field(t("Arabic description"), hint: t("Used instead of the description on Arabic documents."), optional: true) {
        IwTextArea(text: IwItemBind.text($draft, "descriptionAr"))
          .environment(\.layoutDirection, .rightToLeft)
      }
      prices(one)
      if draft.kind == "stock" {
        stockSection(one, inventory: inventory)
      }
      incomeAccount(one)
      taxes(one)
    }
  }

  // MARK: Type

  private func kindPicker(_ inventory: InvInventory) -> some View {
    let id = draft.original.rid
    // A stock item with movements stays one (see saveItem).
    let locked =
      !draft.isNew && draft.wasKind == "stock" && inventory.movements.contains { $0.str("productId") == id }
    let starts = !draft.isNew && draft.wasKind != "stock" && draft.kind == "stock"
    return VStack(alignment: .leading, spacing: 8) {
      Text(t("Type")).font(.web(14, .medium)).foregroundStyle(palette.slate(700))
      ForEach(IwItemKind.all, id: \.value) { option in
        kindOption(option, disabled: locked && option.value != "stock")
      }
      if locked {
        IwNote(text: t("This item has stock history, so it stays a stock item."))
      }
      if starts {
        IwNote(text: t("Bills and invoices already issued with this item will move stock from their dates."), warning: true)
      }
    }
  }

  private func kindOption(_ option: IwItemKind, disabled: Bool) -> some View {
    let on = draft.kind == option.value
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    return Button {
      Haptics.play(.selection)
      draft.product.set("kind", .string(option.value))
    } label: {
      HStack(alignment: .top, spacing: 10) {
        IconView(option.icon, size: 16).foregroundStyle(on ? palette.primary(600) : palette.slate(400))
          .padding(.top, 2)
        VStack(alignment: .leading, spacing: 2) {
          Text(t(option.label)).font(.web(14, .medium)).foregroundStyle(palette.slate(900))
          Text(t(option.hint)).font(.web(12)).foregroundStyle(palette.slate(500))
            .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(12)
      .background(on ? palette.primary(50).opacity(0.6) : palette.surface, in: shape)
      .border(on ? palette.primary(500) : palette.slate(200), in: shape)
      .contentShape(shape)
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .opacity(disabled ? 0.5 : 1)
    .accessibilityAddTraits(on ? .isSelected : [])
  }

  // MARK: Name and code

  @ViewBuilder
  private func nameAndCode(_ one: OneData) -> some View {
    let company = one.company ?? .null
    let autoCode = draft.isNew && SyncJSON.truthy(company["items"]?["autoSku"])
    let sku = draft.product.str("sku").trimmingCharacters(in: .whitespacesAndNewlines)
    let before = draft.original.str("sku").trimmingCharacters(in: .whitespacesAndNewlines)
    let next = autoCode
      ? InventoryWrites.suggestItemCode(company, products: one.records(.products), today: ISODates.today()) : ""
    Field(t("Name"), error: draft.error) {
      TextInput(text: nameBinding)
    }
    Field(
      t("SKU / code"), hint: autoCode && sku.isEmpty ? t("Left blank, the item gets the next code.") : nil,
      optional: true
    ) {
      TextInput(text: IwItemBind.text($draft, "sku"), placeholder: next)
        .environment(\.layoutDirection, .leftToRight)
    }
    if !draft.isNew && !before.isEmpty && sku != before {
      IwNote(
        text: t(
          "Labels printed with {sku} will no longer find this item. Print new ones after saving.", ["sku": before]),
        warning: true)
    }
  }

  private var nameBinding: Binding<String> {
    Binding(
      get: { draft.product.str("name") },
      set: { value in
        draft.product.set("name", .string(value))
        draft.error = nil
      })
  }

  // MARK: Prices and unit

  @ViewBuilder
  private func prices(_ one: OneData) -> some View {
    let kind = draft.kind
    Field(t("Selling price"), hint: t("Up to 6 decimals, e.g. 0.537 per piece.")) {
      IwNumberField(value: IwItemBind.number($draft, "unitPrice"))
    }
    if kind != "service" {
      Field(
        t("Cost price"),
        hint: kind == "stock" ? t("Rate on new bills and the cost of the opening stock.") : t("Rate on new bills.")
      ) {
        IwNumberField(value: IwItemBind.number($draft, "costPrice"), allowNegative: false)
      }
    }
    Field(t("Unit"), optional: true) {
      if SyncJSON.truthy(one.company?["items"]?["units"]) {
        IwUnitPicker(draft: $draft, company: one.company)
      } else {
        TextInput(text: typedUnit, placeholder: t("pcs, box, kg, hrs…"))
      }
    }
  }

  /// A unit typed by hand: no longer the list's unit.
  private var typedUnit: Binding<String> {
    Binding(
      get: { draft.product.str("unit") },
      set: { value in
        draft.product.set("unit", .string(value))
        draft.product.set("unitId", nil)
      })
  }

  // MARK: Stock

  @ViewBuilder
  private func stockSection(_ one: OneData, inventory: InvInventory) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Field(t("Reorder level"), hint: t("Shown as low stock at or below this quantity."), optional: true) {
        IwNumberField(value: reorderLevel, blankZero: true, allowNegative: false)
      }
      Field(t("Preferred vendor"), optional: true) {
        Combobox(
          selection: IwItemBind.choice($draft, "preferredVendorId"), options: vendorOptions(one),
          placeholder: t("Choose a vendor…"), searchPlaceholder: t("Search vendors…"))
      }
      Field(t("Barcode"), optional: true) {
        TextInput(text: IwItemBind.text($draft, "barcode"), keyboard: .numberPad)
          .environment(\.layoutDirection, .leftToRight)
      }
      Field(t("HS code"), hint: t("Customs tariff code."), optional: true) {
        TextInput(text: IwItemBind.text($draft, "hsCode"))
          .environment(\.layoutDirection, .leftToRight)
      }
      if draft.isNew {
        openingStock(inventory)
      }
    }
    .padding(16)
    .background(palette.slate(50).opacity(0.6), in: RoundedRectangle(cornerRadius: WebRadius.lg))
    .border(palette.slate(200), in: RoundedRectangle(cornerRadius: WebRadius.lg))
  }

  /// `v > 0 ? v : null`.
  private var reorderLevel: Binding<Double> {
    Binding(
      get: { draft.product["reorderLevel"]?.double ?? 0 },
      set: { value in draft.product.set("reorderLevel", value > 0 ? .number(value) : .null) })
  }

  private func vendorOptions(_ one: OneData) -> [ComboOption] {
    let chosen = draft.product.text("preferredVendorId")
    let vendors = one.records(.clients)
      .filter { ($0["isVendor"]?.bool == true && !$0.flag("archived")) || $0.rid == chosen }
      .sorted { InvText.byName($0, $1) }
    return [ComboOption(value: "", label: t("None"))] + vendors.map { ComboOption(value: $0.rid, label: localName($0)) }
  }

  @ViewBuilder
  private func openingStock(_ inventory: InvInventory) -> some View {
    let warehouses = inventory.warehouses.filter { !$0.flag("archived") }
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(t("Opening stock")).font(.web(14, .medium)).foregroundStyle(palette.slate(700))
        Text(t("What you have now, valued at the cost price. You can add it later."))
          .font(.web(12)).foregroundStyle(palette.slate(500))
      }
      Field(t("Quantity")) {
        IwNumberField(value: $draft.opening.quantity, blankZero: true, allowNegative: false)
      }
      Field(t("As of")) {
        DateField(value: $draft.opening.date, required: true)
      }
      if warehouses.count > 1 {
        Field(t("Warehouse")) {
          Select(
            selection: $draft.opening.warehouseId,
            options: warehouses.map { SelectOption($0.rid, localName($0)) })
        }
      }
    }
  }

  // MARK: Accounts and taxes

  private func incomeAccount(_ one: OneData) -> some View {
    let current = draft.original.text("incomeAccountId")
    let accounts = one.records(.accounts)
      .filter { account in
        let type = account.str("type")
        return (type == "income" || type == "income_other") && (!account.flag("archived") || account.rid == current)
      }
      .sorted { $0.str("code").localizedStandardCompare($1.str("code")) == .orderedAscending }
    let sales = accounts.first { $0.str("role") == "sales" }
    var options = [SelectOption("", t("{account} (default)", ["account": sales.map { localName($0) } ?? t("Sales")]))]
    for account in accounts where account.str("role") != "sales" {
      options.append(SelectOption(account.rid, "\(account.str("code")) \(localName(account))"))
    }
    return Field(t("Income account"), hint: t("Where sales of this item are recorded in your books.")) {
      Select(selection: incomeBinding, options: options)
    }
  }

  private var incomeBinding: Binding<String> {
    Binding(
      get: { draft.product["incomeAccountId"]?.string ?? "" },
      set: { value in draft.product.set("incomeAccountId", value.isEmpty ? .null : .string(value)) })
  }

  @ViewBuilder
  private func taxes(_ one: OneData) -> some View {
    let rates = one.records(.taxRates)
    if !rates.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text(t("Default taxes")).font(.web(14, .medium)).foregroundStyle(palette.slate(700))
        FlowLayout(spacing: 8, lineSpacing: 8) {
          ForEach(rates.map(Rec.init)) { record in
            taxChip(record.raw)
          }
        }
      }
    }
  }

  private func taxChip(_ rate: JSONValue) -> some View {
    let id = rate.rid
    let chosen = draft.product.list("taxRateIds").compactMap(\.string)
    let on = chosen.contains(id)
    return Button {
      Haptics.play(.selection)
      let next = on ? chosen.filter { $0 != id } : chosen + [id]
      draft.product.set("taxRateIds", .array(next.map(JSONValue.string)))
    } label: {
      Text("\(rate.str("name")) \(Money.jsString(rate.num("rate")))%")
        .font(.web(14))
        .foregroundStyle(on ? Color.white : palette.slate(700))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(on ? palette.primarySolid : palette.surface, in: Capsule())
        .border(on ? palette.primarySolid : palette.slate(300), in: Capsule())
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(on ? .isSelected : [])
  }
}

/// The three kinds of item (`PRODUCT_KINDS`, `KIND_LABELS`), English keys.
struct IwItemKind {
  let value: String
  let label: String
  let hint: String
  let icon: Icon

  static let all: [IwItemKind] = [
    IwItemKind(
      value: "service", label: "Service", hint: "Work you do, such as delivery, printing or installation.",
      icon: .wrench),
    IwItemKind(
      value: "non_stock", label: "Non-stock item", hint: "Goods you buy or sell without counting them in stock.",
      icon: .package),
    IwItemKind(
      value: "stock", label: "Stock item",
      hint: "Goods you keep in stock: quantity on hand, average cost and cost of sales.", icon: .boxes),
  ]
}

/// `UnitPicker`: the unit from the list (built in and the company's own),
/// in the app's language with the other name beside it; a unit typed by
/// hand can still be used, and one an older item had stays until changed.
struct IwUnitPicker: View {
  @Binding var draft: IwItemDraft
  let company: JSONValue?

  /// The value of a unit typed by hand, which is in no list.
  private static let typed = "\u{0}typed"

  var body: some View {
    Combobox(
      selection: selection, options: options, placeholder: t("Choose a unit…"), searchPlaceholder: t("Search units…"),
      createLabel: t("Use"), onCreate: { text in use(text) })
  }

  private var unitId: String? { draft.product.text("unitId") }
  private var unit: String { draft.product.str("unit").trimmingCharacters(in: .whitespacesAndNewlines) }

  private var options: [ComboOption] {
    var list = Units.unitChoices(company)
    // An archived unit the item still has.
    let current = Units.findUnit(company, unitId)
    if let current, !list.contains(where: { $0.id == current.id }) { list.append(current) }
    var choices = [ComboOption(value: "", label: t("None"))]
    let arabic = LanguageStore.shared.isArabic
    for item in list {
      let label = arabic && !item.nameAr.isEmpty ? item.nameAr : item.name
      let other = label == item.name ? item.nameAr : item.name
      choices.append(
        ComboOption(
          value: item.id, label: label, detail: !other.isEmpty && other != label ? other : nil,
          keywords: "\(item.name) \(item.nameAr)"))
    }
    if !unit.isEmpty && current == nil {
      choices.append(ComboOption(value: Self.typed, label: unit, detail: t("Typed by hand")))
    }
    return choices
  }

  private var selection: Binding<String?> {
    Binding(
      get: {
        if Units.findUnit(company, unitId) != nil { return unitId }
        return unit.isEmpty ? nil : Self.typed
      },
      set: { next in
        guard next != Self.typed else { return }
        if let found = Units.findUnit(company, next) {
          draft.product.set("unit", .string(found.name))
          draft.product.set("unitId", .string(found.id))
        } else {
          draft.product.set("unit", "")
          draft.product.set("unitId", nil)
        }
      })
  }

  private func use(_ text: String) {
    let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if typed.isEmpty { return }
    // Typed as one of the list's units: that unit.
    if let found = Units.findUnit(company, Units.matchUnit(typed, company)) {
      draft.product.set("unit", .string(found.name))
      draft.product.set("unitId", .string(found.id))
    } else {
      draft.product.set("unit", .string(typed))
      draft.product.set("unitId", nil)
    }
  }
}

/// `/products?new=1` on a phone: a new item, its form as a page with Cancel
/// and Save in the bar at the bottom.
struct IwItemFormPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @State private var draft: IwItemDraft?
  @State private var saving = false
  private let kind: String

  init() {
    kind = IwIntent.takeItemKind()
  }

  var body: some View {
    WebPage {
      PageHeader(t("New item"), breadcrumb: t("Products & services"), onBreadcrumb: { router.back() })
      if let binding = Binding($draft) {
        Card {
          CardBody {
            IwItemFields(draft: binding)
          }
        }
      } else {
        Card { DataLoadingRow() }
      }
    }
    .onAppear {
      if draft == nil, model.one.hasData { draft = IwItemDraft.new(model.one, kind: kind) }
    }
    .onChange(of: model.one.revision) { _, _ in
      if draft == nil, model.one.hasData { draft = IwItemDraft.new(model.one, kind: kind) }
    }
    .stickyActions {
      WebButton(t("Cancel"), variant: .outline) { router.back() }
      if IwGate.items && IwGate.edits(model) {
        WebButton(t("Save"), loading: saving) { save() }
      }
    }
  }

  private func save() {
    guard let current = draft else { return }
    let binding = Binding(get: { draft ?? current }, set: { draft = $0 })
    saving = true
    Task {
      let ok = await IwItemSaving.save(binding, model: model)
      saving = false
      if ok { router.back() }
    }
  }
}
