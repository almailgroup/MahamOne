import MahamKit
import SwiftUI
import UIKit

// The editor's lines (`LineItemsEditor` for sales documents, the bill
// editor's lines for purchases), its totals (`TotalsPanel`) and the tax
// picker (`TaxSelect`).

/// What the lines need to know of the document and the company.
struct DcLineContext {
  let type: DocType
  let products: [ComboOption]
  let taxRates: [JSONValue]
  let showTaxes: Bool
  let showArabic: Bool
  let currency: String
  let categories: [ComboOption]
  let defaultAccount: String?
  let language: String
}

struct DcLinesCard: View {
  let type: DocType
  @Binding var doc: JSONValue
  @Binding var errors: [String: String]
  let result: DcCalcResult
  let defaultTaxes: [JSONValue]
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let context = lineContext
    let rows = DcIndexed.list(doc.list("items"))
    let itemCount = rows.filter { $0.record.str("kind") != "heading" }.count
    Card {
      CardHeader(type.isPurchase ? t("Lines") : t("Items"), description: description)
      if let error = errors["items"] {
        Text(error)
          .font(.web(14))
          .foregroundStyle(palette[.red(600)])
          .padding(.horizontal, 20)
          .padding(.top, 12)
      }
      VStack(spacing: 12) {
        ForEach(rows) { row in
          DcLineCard(
            context: context, line: $doc.dcLine(row.record.rid), index: row.index, count: rows.count,
            itemCount: itemCount, net: row.index < result.lines.count ? result.lines[row.index].net : 0,
            onChange: { errors["items"] = nil },
            onMove: { delta in move(row.index, delta) },
            onDuplicate: { duplicate(row.index) },
            onHeading: { insertHeading(row.index) },
            onRemove: { remove(row.index) })
        }
      }
      .padding(16)
      FlowLayout(spacing: 8, lineSpacing: 8) {
        if type.isPurchase {
          WebButton(t("Add line"), icon: .plus, variant: .outline, size: .sm) { addPurchaseLine(context) }
        } else {
          WebButton(t("Add item"), icon: .plus, variant: .outline, size: .sm) { addItem() }
          WebButton(t("Add section heading"), icon: .heading, variant: .ghost, size: .sm) {
            setItems(doc.list("items") + [DcDocuments.newHeading(id: MahamKit.shortId())])
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 16)
    }
  }

  private var description: String {
    switch type {
    case .purchaseOrder: t("What you are ordering. The categories carry over to the bill.")
    case .bill, .vendorCredit: t("Each line goes to an expense or asset account in your books.")
    default: t("Type to search your products & services.")
    }
  }

  private var lineContext: DcLineContext {
    let one = model.one
    let company = one.company
    let items = doc.list("items")
    let lineTaxes = company?.obj("defaults")?.flag("lineTaxes") ?? false
    let contact = one.record(.clients, doc.str("clientId"))
    let language = contact?.text("language") ?? company?.str("language") ?? ""
    let arabicDocument = language.isEmpty || language == "ar" || language == "ar-en"
    let anyArabic = items.contains { !($0.text("nameAr") ?? "").isEmpty }
    let companyId = company?.rid ?? ""
    let expense = one.records(.accounts)
      .filter { $0.str("companyId") == companyId && $0.str("role") == "expense" }
      .min { $0.rid < $1.rid }
    return DcLineContext(
      type: type, products: DcOptions.products(one, format: one.format, purchase: type.isPurchase),
      taxRates: one.records(.taxRates).filter { $0.str("companyId") == companyId },
      showTaxes: type.isPurchase || lineTaxes || items.contains { !$0.list("taxes").isEmpty },
      showArabic: type.isPurchase ? type == .purchaseOrder : (arabicDocument || anyArabic),
      currency: doc.text("currency") ?? company?.str("currency") ?? "KWD",
      categories: type.isPurchase ? DcOptions.categories(one, keep: items.map { $0.str("accountId") }) : [],
      defaultAccount: expense?.rid, language: language)
  }

  private func setItems(_ items: [JSONValue]) {
    doc.set("items", .array(items))
    errors["items"] = nil
  }

  private func addItem() {
    let lineTaxes = model.one.company?.obj("defaults")?.flag("lineTaxes") ?? false
    setItems(doc.list("items") + [DcDocuments.newLine(id: MahamKit.shortId(), taxes: lineTaxes ? defaultTaxes : [])])
  }

  /// A new line takes the taxes and the category of the one above it.
  private func addPurchaseLine(_ context: DcLineContext) {
    let lines = doc.list("items").filter { $0.str("kind") == "item" }
    let last = lines.last
    let taxes = last?.list("taxes") ?? defaultTaxes
    var line = DcDocuments.newLine(id: MahamKit.shortId(), taxes: taxes)
    let account = last?["accountId"] ?? context.defaultAccount.map { JSONValue.string($0) }
    if let account { line.set("accountId", account) }
    setItems(doc.list("items") + [line])
  }

  private func move(_ index: Int, _ delta: Int) {
    var items = doc.list("items")
    let target = index + delta
    guard items.indices.contains(index), items.indices.contains(target) else { return }
    items.swapAt(index, target)
    setItems(items)
  }

  private func duplicate(_ index: Int) {
    var items = doc.list("items")
    guard items.indices.contains(index) else { return }
    var copy = items[index]
    copy.set("id", .string(MahamKit.shortId()))
    items.insert(copy, at: index + 1)
    setItems(items)
  }

  private func insertHeading(_ index: Int) {
    var items = doc.list("items")
    items.insert(DcDocuments.newHeading(id: MahamKit.shortId()), at: min(index, items.count))
    setItems(items)
  }

  private func remove(_ index: Int) {
    var items = doc.list("items")
    guard items.indices.contains(index) else { return }
    items.remove(at: index)
    setItems(items)
  }
}

/// One line: a heading's name, or an item's name, product, quantity, unit,
/// price, discount, taxes and amount, with its menu.
struct DcLineCard: View {
  let context: DcLineContext
  @Binding var line: JSONValue
  let index: Int
  let count: Int
  let itemCount: Int
  let net: Double
  let onChange: () -> Void
  let onMove: (Int) -> Void
  let onDuplicate: () -> Void
  let onHeading: () -> Void
  let onRemove: () -> Void
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    VStack(alignment: .leading, spacing: 12) {
      if line.str("kind") == "heading" {
        headingFields
      } else if context.type.isPurchase {
        purchaseFields
      } else {
        itemFields
      }
    }
    .padding(12)
    .background(palette.surface, in: shape)
    .overlay { shape.stroke(palette.slate(200), lineWidth: 1) }
  }

  // MARK: Parts

  private var headingFields: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 8) {
        TextInput(text: $line.dcString("name"), placeholder: t("Section heading, e.g. “Print production”"))
        menu
      }
      if context.showArabic {
        DcTextField(text: $line.dcString("nameAr"), placeholder: t("Heading in Arabic"))
      }
      DcTextField(text: $line.dcString("description"), placeholder: t("Optional note"))
    }
  }

  private var itemFields: some View {
    let priced = context.type.priced
    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 8) {
        TextInput(text: nameBinding, placeholder: t("Item name or search products…"))
        menu
      }
      if !context.products.isEmpty {
        Combobox(
          selection: productBinding, options: context.products, placeholder: t("Products & services"),
          searchPlaceholder: t("Item name or search products…"))
      }
      if context.showArabic {
        DcTextField(text: $line.dcString("nameAr"), placeholder: t("Name in Arabic (optional)"))
      }
      DcTextArea(text: $line.dcString("description"), placeholder: t("Description (optional)"), lines: 1)
      HStack(alignment: .top, spacing: 8) {
        miniField(t("Qty")) { DcAmountField(value: quantityBinding) }
        miniField(t("Unit")) { DcTextField(text: $line.dcString("unit"), placeholder: t("pcs, hrs…")) }
      }
      if priced {
        HStack(alignment: .top, spacing: 8) {
          miniField(t("Price")) { DcAmountField(value: priceBinding) }
          miniField(t("Discount")) { discountField }
        }
        if context.showTaxes {
          miniField(t("Tax")) { DcTaxPicker(taxes: $line.dcTaxes, rates: context.taxRates) }
        }
        amountRow
      }
    }
  }

  private var purchaseFields: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 8) {
        miniField(t("Category")) {
          Combobox(
            selection: accountBinding, options: context.categories, placeholder: t("Choose a category…"),
            searchPlaceholder: t("Search accounts…"))
        }
        WebButton(icon: .trash2, label: t("Remove line {number}", ["number": String(index + 1)])) { onRemove() }
          .disabled(itemCount <= 1)
      }
      miniField(t("Description")) {
        TextInput(text: nameBinding, placeholder: t("Item name or search products…"))
      }
      if !context.products.isEmpty {
        Combobox(
          selection: productBinding, options: context.products, placeholder: t("Products & services"),
          searchPlaceholder: t("Item name or search products…"))
      }
      if context.showArabic {
        DcTextField(text: $line.dcString("nameAr"), placeholder: t("Name in Arabic (optional)"))
      }
      HStack(alignment: .top, spacing: 8) {
        miniField(t("Qty")) { DcAmountField(value: quantityBinding) }
        miniField(t("Price")) { DcAmountField(value: priceBinding) }
      }
      miniField(t("Tax")) { DcTaxPicker(taxes: $line.dcTaxes, rates: context.taxRates) }
      amountRow
    }
  }

  private var amountRow: some View {
    HStack {
      Text(t("Amount")).font(.web(12, .medium)).foregroundStyle(palette.slate(500))
      Spacer(minLength: 8)
      Text(model.one.format.money(net, context.currency))
        .font(.web(14, .semibold, tabular: true))
        .foregroundStyle(palette.slate(900))
        .environment(\.layoutDirection, .leftToRight)
    }
  }

  private func miniField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.web(12, .medium)).foregroundStyle(palette.slate(500))
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var discountField: some View {
    let percent = line.str("discountType") != "amount"
    let symbol = Format.currencySymbol(context.currency, locale: model.one.format.locale)
    return HStack(spacing: 4) {
      DcAmountField(value: $line.dcDouble("discount"))
      Button {
        Haptics.play(.selection)
        line.set("discountType", .string(percent ? "amount" : "percent"))
      } label: {
        Text(percent ? "%" : symbol)
          .font(.web(12, .semibold))
          .foregroundStyle(palette.slate(600))
          .frame(minWidth: 44, minHeight: 44)
          .background(palette.slate(50), in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(percent ? t("Switch to a fixed amount") : t("Switch to a percentage")))
    }
  }

  private var menu: some View {
    DropdownMenu(name: t("Line {number} actions", ["number": String(index + 1)])) {
      IconView(.moreHorizontal, size: 16).foregroundStyle(palette.slate(600))
    } items: {
      DropdownItem(t("Move up"), icon: .arrowUp) { onMove(-1) }
        .disabled(index == 0)
      DropdownItem(t("Move down"), icon: .arrowDown) { onMove(1) }
        .disabled(index >= count - 1)
      DropdownItem(t("Duplicate"), icon: .copy) { onDuplicate() }
      DropdownItem(t("Insert heading above"), icon: .heading) { onHeading() }
      DropdownSeparator()
      DropdownItem(t("Remove"), icon: .trash2, danger: true) { onRemove() }
    }
  }

  // MARK: Bindings

  /// Typed over a product: the line is a plain one again.
  private var nameBinding: Binding<String> {
    Binding<String>(
      get: { line.str("name") },
      set: { name in
        var next = line
        next.set("name", .string(name))
        if next.str("productId") != "" {
          next.set("productId", .null)
          next.set("sku", nil)
          if context.type.isPurchase, isStock(line.str("productId")), let account = context.defaultAccount {
            next.set("accountId", .string(account))
          }
        }
        line = next
        onChange()
      })
  }

  private var quantityBinding: Binding<Double> {
    Binding<Double>(get: { line.num("quantity") }, set: { line.set("quantity", .number($0)) })
  }

  private var priceBinding: Binding<Double> {
    Binding<Double>(
      get: { line.num("unitPrice") },
      set: { price in
        line.set("unitPrice", .number(price))
        onChange()
      })
  }

  private var accountBinding: Binding<String?> {
    Binding<String?>(
      get: { line.text("accountId") ?? context.defaultAccount },
      set: { account in
        if let account { line.set("accountId", .string(account)) }
      })
  }

  private var productBinding: Binding<String?> {
    Binding<String?>(
      get: { line.text("productId") },
      set: { productId in
        guard let productId, let product = model.one.record(.products, productId) else { return }
        line = context.type.isPurchase ? pickedForPurchase(product) : picked(product)
        onChange()
      })
  }

  private func isStock(_ productId: String) -> Bool {
    model.one.record(.products, productId)?.str("kind") == "stock"
  }

  /// `pickProduct`: the item's names, description, price, unit, code and taxes.
  private func picked(_ product: JSONValue) -> JSONValue {
    let rateIds = product.list("taxRateIds").compactMap(\.string)
    let taxes = rateIds.compactMap { id in context.taxRates.first { $0.rid == id } }.map { DcCalc.taxLineOf($0) }
    let arabic = context.language == "ar" && !(product.text("descriptionAr") ?? "").isEmpty
    let sku = product.str("sku").trimmingCharacters(in: .whitespacesAndNewlines)
    var lineTaxes = JSONValue.array([])
    if context.showTaxes { lineTaxes = rateIds.isEmpty ? (line["taxes"] ?? JSONValue.array([])) : JSONValue.array(taxes) }
    return DcDocuments.applying(
      line,
      [
        ("productId", .string(product.rid)),
        ("name", product["name"]),
        ("nameAr", .string(product.str("nameAr"))),
        ("description", arabic ? product["descriptionAr"] : product["description"]),
        ("unitPrice", product["unitPrice"]),
        ("unit", product["unit"]),
        ("unitId", product["unitId"]),
        ("sku", sku.isEmpty ? Optional<JSONValue>.none : JSONValue.string(sku)),
        ("taxes", lineTaxes),
      ])
  }

  /// The bill editor's pick: the cost price, and the inventory account for stock items.
  private func pickedForPurchase(_ product: JSONValue) -> JSONValue {
    let sku = product.str("sku").trimmingCharacters(in: .whitespacesAndNewlines)
    let cost = product.num("costPrice")
    return DcDocuments.applying(
      line,
      [
        ("productId", .string(product.rid)),
        ("name", product["name"]),
        ("nameAr", .string(product.str("nameAr"))),
        ("unit", product["unit"]),
        ("unitId", product["unitId"]),
        ("sku", sku.isEmpty ? Optional<JSONValue>.none : JSONValue.string(sku)),
        ("unitPrice", cost != 0 ? JSONValue.number(cost) : line["unitPrice"]),
      ])
  }
}

extension Binding where Value == JSONValue {
  /// A record's `taxes` list.
  var dcTaxes: Binding<[JSONValue]> {
    Binding<[JSONValue]>(
      get: { wrappedValue.list("taxes") },
      set: { taxes in
        var record = wrappedValue
        record.set("taxes", .array(taxes))
        wrappedValue = record
      })
  }
}

/// `TaxSelect`: the rates of a line, the document or a charge, several at once.
struct DcTaxPicker: View {
  @Binding var taxes: [JSONValue]
  let rates: [JSONValue]
  var placeholder: String?
  @State private var open = false
  @Environment(\.palette) private var palette

  init(taxes: Binding<[JSONValue]>, rates: [JSONValue], placeholder: String? = nil) {
    _taxes = taxes
    self.rates = rates
    self.placeholder = placeholder
  }

  var body: some View {
    Button {
      Haptics.play(.tap)
      open = true
    } label: {
      HStack(spacing: 8) {
        Text(summary)
          .foregroundStyle(taxes.isEmpty ? palette.slate(500) : palette.slate(900))
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        IconView(.chevronDown, size: 16).foregroundStyle(palette.slate(400))
      }
      .padding(.horizontal, 12)
      .modifier(InputChrome(focused: open))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .dropdownPanel(isPresented: $open, alignment: .end, width: 240) {
      if options.isEmpty {
        Text(t("No tax rates yet. Add them in Settings → Taxes."))
          .font(.web(14))
          .foregroundStyle(palette.slate(500))
          .padding(12)
      }
      ForEach(DcIndexed.list(options)) { row in
        DropdownItem(label(row.record), icon: chosen(row.record) ? Icon.check : nil, reservesIcon: true) {
          toggle(row.record)
        }
      }
      if !taxes.isEmpty {
        DropdownSeparator()
        DropdownItem(t("Clear")) { taxes = [] }
      }
    }
  }

  /// The configured rates, and those still on the record that are no longer configured.
  private var options: [JSONValue] {
    var list = rates.filter { !$0.flag("archived") }.map { DcCalc.taxLineOf($0) }
    for tax in taxes where !list.contains(where: { DcCalc.taxKey($0) == DcCalc.taxKey(tax) }) {
      list.append(tax)
    }
    return list
  }

  private func chosen(_ tax: JSONValue) -> Bool {
    taxes.contains { DcCalc.taxKey($0) == DcCalc.taxKey(tax) }
  }

  private func toggle(_ tax: JSONValue) {
    let key = DcCalc.taxKey(tax)
    taxes = chosen(tax) ? taxes.filter { DcCalc.taxKey($0) != key } : taxes + [tax]
  }

  private static func rateText(_ tax: JSONValue) -> String {
    let rate = (tax.num("rate") * 10_000).rounded() / 10_000
    return "\(Money.jsString(rate))%"
  }

  private func label(_ tax: JSONValue) -> String {
    let base = "\(tax.str("name")) \(DcTaxPicker.rateText(tax))"
    return tax.str("kind") == "reverse_charge" ? "\(base) (\(t("Reverse charge")))" : base
  }

  private var summary: String {
    if taxes.isEmpty { return placeholder ?? t("No tax") }
    return taxes.map { tax in
      let rate = DcTaxPicker.rateText(tax)
      return tax.str("kind") == "reverse_charge" ? t("{rate} RC", ["rate": rate]) : rate
    }.joined(separator: " + ")
  }
}

// MARK: Totals

struct DcTotalsCard: View {
  let type: DocType
  @Binding var doc: JSONValue
  let result: DcCalcResult
  let defaultTaxes: [JSONValue]
  let contact: JSONValue?
  let exempt: Bool
  @State private var addRetention = false
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  init(
    type: DocType, doc: Binding<JSONValue>, result: DcCalcResult, defaultTaxes: [JSONValue], contact: JSONValue?,
    exempt: Bool
  ) {
    self.type = type
    _doc = doc
    self.result = result
    self.defaultTaxes = defaultTaxes
    self.contact = contact
    self.exempt = exempt
  }

  var body: some View {
    let one = model.one
    let company = one.company
    let rates = DcOptions.taxRates(one)
    let showDocumentTaxes = !type.isPurchase && (company?.obj("defaults")?.flag("documentTaxes") ?? false)
    Card {
      CardHeader(t("Totals"))
      CardBody {
        row(t("Subtotal"), money(result.subtotal))
        HStack(spacing: 8) {
          Text(t("Discount")).font(.web(14)).foregroundStyle(palette.slate(600))
          Spacer(minLength: 8)
          discountField.frame(width: 150)
          Text(result.discount != 0 ? money(-result.discount) : "—")
            .font(.web(14, tabular: true))
            .foregroundStyle(palette.slate(600))
            .environment(\.layoutDirection, .leftToRight)
        }
        if showDocumentTaxes || !doc.list("taxes").isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text(t("Tax on total")).font(.web(14)).foregroundStyle(palette.slate(600))
            DcTaxPicker(taxes: $doc.dcTaxes, rates: rates, placeholder: t("None"))
          }
        }
        charges(rates)
        if DcCalc.takesRetention(type.rawValue) { retention }
        totals
        Switch(
          t("Prices include tax"), description: t("Tax is calculated backwards from the entered prices."),
          isOn: $doc.dcBool("pricesIncludeTax"))
        if type == .invoice || type == .proforma { deposit }
      }
    }
  }

  private func money(_ amount: Double) -> String {
    model.one.format.money(amount, doc.text("currency"))
  }

  private func row(_ label: String, _ value: String, strong: Bool = false) -> some View {
    HStack {
      Text(label)
      Spacer(minLength: 8)
      Text(value).environment(\.layoutDirection, .leftToRight)
    }
    .font(.web(strong ? 16 : 14, strong ? .semibold : .regular, tabular: true))
    .foregroundStyle(strong ? palette.slate(900) : palette.slate(600))
  }

  private var discountField: some View {
    let percent = doc.str("discountType") != "amount"
    let symbol = Format.currencySymbol(doc.text("currency") ?? "KWD", locale: model.one.format.locale)
    return HStack(spacing: 4) {
      DcAmountField(value: $doc.dcDouble("discount"))
      Button {
        Haptics.play(.selection)
        doc.set("discountType", .string(percent ? "amount" : "percent"))
      } label: {
        Text(percent ? "%" : symbol)
          .font(.web(12, .semibold))
          .foregroundStyle(palette.slate(600))
          .frame(minWidth: 44, minHeight: 44)
          .background(palette.slate(50), in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(percent ? t("Switch to a fixed amount") : t("Switch to a percentage")))
    }
  }

  @ViewBuilder
  private func charges(_ rates: [JSONValue]) -> some View {
    let lineTaxes = model.one.company?.obj("defaults")?.flag("lineTaxes") ?? false
    let hasLineTaxes = doc.list("items").contains { !$0.list("taxes").isEmpty }
    VStack(alignment: .leading, spacing: 8) {
      ForEach(DcIndexed.list(doc.list("charges"))) { row in
        DcChargeRow(charge: chargeBinding(row.record.rid), rates: rates) {
          doc.set("charges", .array(doc.list("charges").filter { $0.rid != row.record.rid }))
        }
      }
      WebButton(t("Add charge (shipping, handling…)"), icon: .plus, variant: .ghost, size: .sm) {
        let charge: JSONValue = .object([
          "id": .string(MahamKit.shortId()), "label": .string(t("Shipping")), "amount": 0,
          "taxes": .array(type.isPurchase || lineTaxes || hasLineTaxes ? defaultTaxes : doc.list("taxes")),
        ])
        doc.set("charges", .array(doc.list("charges") + [charge]))
      }
    }
  }

  private func chargeBinding(_ id: String) -> Binding<JSONValue> {
    Binding<JSONValue>(
      get: { doc.list("charges").first { $0.rid == id } ?? .null },
      set: { charge in doc.set("charges", .array(doc.list("charges").map { $0.rid == id ? charge : $0 })) })
  }

  @ViewBuilder
  private var retention: some View {
    let usual = DcRules.contactRetention(contact)
    let percent = doc.num("retentionPercent")
    let shown = addRetention || percent > 0 || usual > 0
    let format = model.one.format
    if shown {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(t("Retention")).font(.web(14)).foregroundStyle(palette.slate(600))
          Spacer(minLength: 8)
          HStack(spacing: 4) {
            DcAmountField(value: retentionBinding).frame(width: 90)
            Text("%").font(.web(14)).foregroundStyle(palette.slate(500))
          }
          Text(result.retention != 0 ? money(-result.retention) : "—")
            .font(.web(14, tabular: true))
            .foregroundStyle(palette.slate(600))
            .environment(\.layoutDirection, .leftToRight)
        }
        Text(retentionHint(usual: usual, percent: percent, format: format))
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
      }
    } else {
      WebButton(t("Add retention"), icon: .plus, variant: .ghost, size: .sm) { addRetention = true }
    }
  }

  private func retentionHint(usual: Double, percent: Double, format: CompanyFormat) -> String {
    let kind = contact?.text("retentionKind") ?? "tax"
    if usual > 0, kind == "tax", let certificate = DcRules.validCertificate(contact, doc.str("issueDate")) {
      return t(
        "Clearance certificate {number} is valid on this date: nothing needs to be held.",
        ["number": certificate.str("number")])
    }
    if usual > 0 && usual != percent {
      return t("Usually {percent} for this contact.", ["percent": format.percent(usual)])
    }
    return t("Held back until released; not part of the balance due.")
  }

  private var retentionBinding: Binding<Double> {
    Binding<Double>(
      get: { doc.num("retentionPercent") },
      set: { value in
        let kind = doc["retentionKind"]?.string ?? contact?.text("retentionKind") ?? "tax"
        doc.set("retentionPercent", .number(min(max(value, 0), 100)))
        doc.set("retentionKind", .string(kind))
      })
  }

  @ViewBuilder
  private var totals: some View {
    let format = model.one.format
    let inclusive = doc.flag("pricesIncludeTax")
    let charged = result.taxes.filter { $0.kind != "reverse_charge" }
    let reverse = result.taxes.filter { $0.kind == "reverse_charge" }
    let isCredit = type == .credit || type == .vendorCredit
    VStack(spacing: 2) {
      Rectangle().fill(palette.slate(100)).frame(height: 1).padding(.bottom, 8)
      if !inclusive {
        ForEach(charged) { tax in row("\(tax.name) \(format.percent(tax.rate))", money(tax.amount)) }
      }
      row(t("Total"), money(result.total), strong: true)
      if inclusive {
        ForEach(charged) { tax in
          row(t("Includes {tax}", ["tax": "\(tax.name) \(format.percent(tax.rate))"]), money(tax.amount))
        }
      }
      ForEach(reverse) { tax in
        row(reverseLabel("\(tax.name) \(format.percent(tax.rate))"), money(tax.amount))
      }
      if result.retentionHeld != 0 {
        row(t("Retention held"), money(-result.retentionHeld))
      }
      if DcRules.postsToLedger(type.rawValue) && (result.paid != 0 || result.retentionHeld != 0) {
        if result.paid != 0 { row(isCredit ? t("Applied") : t("Paid"), money(-result.paid)) }
        row(isCredit ? t("Remaining credit") : t("Balance due"), money(result.balance), strong: true)
      }
      if exempt {
        Text(
          type.isPurchase
            ? t("This vendor is not registered for tax — taxes are not applied.")
            : t("This client is tax exempt — taxes are not applied.")
        )
        .font(.web(12))
        .foregroundStyle(palette[.amber(800)])
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette[.amber(50)], in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
        .padding(.top, 8)
      }
    }
  }

  private func reverseLabel(_ tax: String) -> String {
    type.isPurchase
      ? t("Reverse charge {tax} · you account for it", ["tax": tax])
      : t("Reverse charge {tax} · the client accounts for it", ["tax": tax])
  }

  @ViewBuilder
  private var deposit: some View {
    let on = doc.num("deposit") > 0
    Switch(
      t("Request a deposit"), description: t("Shows a deposit amount due before the full balance."),
      isOn: depositBinding)
    if on {
      HStack(alignment: .top, spacing: 8) {
        Field(t("Deposit amount")) { DcAmountField(value: $doc.dcDouble("deposit")) }
        Field(t("Deposit due")) { DateField(value: $doc.dcDate("depositDueDate")) }
      }
    }
  }

  private var depositBinding: Binding<Bool> {
    Binding<Bool>(
      get: { doc.num("deposit") > 0 },
      set: { on in
        if on {
          let p = Money.precision(doc.text("currency") ?? "KWD")
          doc.set("deposit", .number(Money.toNumber(Money.round(result.total * 0.5, p))))
          doc.set("depositDueDate", .string(doc.str("issueDate")))
        } else {
          doc.set("deposit", .number(0))
          doc.set("depositDueDate", .null)
        }
      })
  }
}

/// A charge: its label, amount and taxes.
struct DcChargeRow: View {
  @Binding var charge: JSONValue
  let rates: [JSONValue]
  let onRemove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        TextInput(text: $charge.dcString("label"), placeholder: t("e.g. Shipping"))
        DcAmountField(value: $charge.dcDouble("amount")).frame(width: 110)
        WebButton(icon: .trash2, label: t("Remove charge")) { onRemove() }
      }
      DcTaxPicker(taxes: $charge.dcTaxes, rates: rates)
    }
  }
}
