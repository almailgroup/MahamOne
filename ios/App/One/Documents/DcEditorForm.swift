import MahamKit
import SwiftUI
import UIKit

// The editor's fields, lines, totals and notes. The document stays the raw
// record the web stores; every field reads and writes it in place.

extension Binding where Value == JSONValue {
  /// A text field of the record.
  func dcString(_ key: String) -> Binding<String> {
    Binding<String>(
      get: { wrappedValue.str(key) },
      set: { text in
        var record = wrappedValue
        record.set(key, .string(text))
        wrappedValue = record
      })
  }

  /// A number field of the record (0 when missing).
  func dcDouble(_ key: String) -> Binding<Double> {
    Binding<Double>(
      get: { wrappedValue.num(key) },
      set: { number in
        var record = wrappedValue
        record.set(key, .number(number))
        wrappedValue = record
      })
  }

  /// A date field of the record: "" is null (no date).
  func dcDate(_ key: String) -> Binding<String> {
    Binding<String>(
      get: { wrappedValue.str(key) },
      set: { date in
        var record = wrappedValue
        record.set(key, date.isEmpty ? JSONValue.null : JSONValue.string(date))
        wrappedValue = record
      })
  }

  /// A yes/no field of the record.
  func dcBool(_ key: String) -> Binding<Bool> {
    Binding<Bool>(
      get: { wrappedValue.flag(key) },
      set: { on in
        var record = wrappedValue
        record.set(key, .bool(on))
        wrappedValue = record
      })
  }

  /// A line of the document, by its id.
  func dcLine(_ id: String) -> Binding<JSONValue> {
    Binding<JSONValue>(
      get: { wrappedValue.list("items").first { $0.rid == id } ?? .null },
      set: { line in
        var record = wrappedValue
        record.set("items", .array(record.list("items").map { $0.rid == id ? line : $0 }))
        wrappedValue = record
      })
  }
}

/// A row of a list with its place, for `ForEach`.
struct DcIndexed: Identifiable {
  let index: Int
  let record: JSONValue
  var id: String { record.rid.isEmpty ? "#\(index)" : record.rid }

  static func list(_ records: [JSONValue]) -> [DcIndexed] {
    records.enumerated().map { DcIndexed(index: $0.offset, record: $0.element) }
  }
}

/// The picker options the editor shows.
@MainActor
enum DcOptions {
  private static var currencyCache: [String: [SelectOption<String>]] = [:]

  /// Every currency, the common ones first (`CurrencySelect`).
  static func currencies() -> [SelectOption<String>] {
    let language = LanguageStore.shared.isArabic ? "ar" : "en"
    if let cached = currencyCache[language] { return cached }
    let options = Geo.currencyOptions(locale: language).map { SelectOption($0.value, $0.label) }
    currencyCache[language] = options
    return options
  }

  /// `contactOption`: the name in the reader's language, the other name, email and city under it.
  static func contact(_ contact: JSONValue) -> ComboOption {
    let name = localName(contact)
    let other = name == contact.str("name") ? contact.str("nameAr") : contact.str("name")
    let primary = contact.list("contacts").first { $0.flag("primary") }?.text("email")
    let email = primary ?? contact.str("email")
    let city = contact.obj("address")?.str("city") ?? ""
    return ComboOption(
      value: contact.rid, label: name,
      detail: [other, email, city].filter { !$0.isEmpty }.joined(separator: " · "),
      keywords: [contact.str("number"), contact.str("name"), contact.str("nameAr")].filter { !$0.isEmpty }
        .joined(separator: " "))
  }

  /// The clients (or vendors) to pick from: active ones of the kind, and the one chosen.
  static func contacts(_ one: OneData, purchase: Bool, chosen: String) -> [ComboOption] {
    one.records(.clients)
      .filter { contact in
        let kind = purchase ? contact.flag("isVendor") : contact["isCustomer"]?.bool != false
        return (kind && !contact.flag("archived")) || contact.rid == chosen
      }
      .map { contact($0) }
      .sorted { $0.label.localizedCompare($1.label) == .orderedAscending }
  }

  /// The items to pick a line from: active ones, with their code and price.
  static func products(_ one: OneData, format: CompanyFormat, purchase: Bool) -> [ComboOption] {
    one.records(.products)
      .filter { !$0.flag("archived") }
      .map { product in
        let price = purchase ? product.num("costPrice") : product.num("unitPrice")
        let detail = [product.str("sku"), format.money(price)].filter { !$0.isEmpty }.joined(separator: " · ")
        return ComboOption(
          value: product.rid, label: localName(product), detail: detail,
          keywords: [product.str("name"), product.str("nameAr"), product.str("sku")].joined(separator: " "))
      }
      .sorted { $0.label.localizedCompare($1.label) == .orderedAscending }
  }

  /// The company's tax rates, not archived.
  static func taxRates(_ one: OneData) -> [JSONValue] {
    let companyId = one.companyId ?? ""
    return one.records(.taxRates).filter { $0.str("companyId") == companyId && !$0.flag("archived") }
  }

  /// The accounts a purchase line can go to (`categoryOptions`): expenses, costs and assets.
  static func categories(_ one: OneData, keep: [String]) -> [ComboOption] {
    let wanted: Set<String> = [
      "expense", "cost_of_sales", "asset_current", "asset_fixed", "asset_non_current", "expense_other",
    ]
    return one.records(.accounts)
      .filter { account in
        (wanted.contains(account.str("type")) && !account.flag("archived")) || keep.contains(account.rid)
      }
      .sorted { $0.str("code").localizedStandardCompare($1.str("code")) == .orderedAscending }
      .map { ComboOption(value: $0.rid, label: "\($0.str("code")) \(localName($0))", keywords: $0.str("code")) }
  }
}

struct DcEditorForm: View {
  let type: DocType
  let isNew: Bool
  @Binding var doc: JSONValue
  @Binding var errors: [String: String]
  let numberHint: String
  let defaultTaxes: [JSONValue]
  let saving: String?
  let sendsForApproval: Bool
  let onContact: (String) -> Void
  let onNewContact: (String) -> Void
  let onCancel: () -> Void
  let onSave: (String) -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    let one = model.one
    let contact = one.record(.clients, doc.str("clientId"))
    let exempt = DcCalc.documentTaxExempt(doc, contact: contact)
    let result = DcCalc.computeDocument(doc, paid: doc.obj("totals")?.num("paid") ?? 0, taxExempt: exempt)
    WebPage(spacing: 16) {
      PageHeader(title, breadcrumb: t(type.plural), onBreadcrumb: onCancel)
      DcHeaderCard(
        type: type, isNew: isNew, doc: $doc, errors: $errors, numberHint: numberHint, onContact: onContact,
        onNewContact: onNewContact)
      DcLinesCard(type: type, doc: $doc, errors: $errors, result: result, defaultTaxes: defaultTaxes)
      if type.priced {
        DcTotalsCard(type: type, doc: $doc, result: result, defaultTaxes: defaultTaxes, contact: contact, exempt: exempt)
      }
      DcNotesCard(type: type, doc: $doc)
    }
    .stickyActions { actions }
  }

  private var title: String {
    isNew
      ? t(type.newLabel)
      : t("Edit {document} {number}", ["document": DcWrite.noun(type), "number": doc.str("number")])
  }

  /// Sales orders are confirmed rather than sent; delivery notes are marked as delivered from their page.
  private var sendLabel: String? {
    switch type {
    case .salesOrder: t("Save and confirm")
    case .deliveryNote: nil
    default: t("Save and mark as sent")
    }
  }

  @ViewBuilder
  private var actions: some View {
    WebButton(t("Cancel"), variant: .ghost) { onCancel() }
    if sendsForApproval {
      WebButton(t("Send for approval"), icon: .send, loading: saving == "save") { onSave("save") }
    } else if type.isPurchase {
      if doc.str("status") == "draft" {
        WebButton(t("Save as draft"), variant: .outline, loading: saving == "draft") { onSave("draft") }
      }
      WebButton(t("Save"), loading: saving == "open") { onSave("open") }
    } else {
      if doc.str("status") == "draft", let label = sendLabel {
        WebButton(label, variant: .outline, loading: saving == "sent") { onSave("sent") }
      }
      WebButton(t("Save"), icon: .save, loading: saving == "save") { onSave("save") }
    }
  }
}

// MARK: The header

private let paymentTerms = [0, 7, 14, 15, 30, 45, 60, 90]
private let quoteValidity = [7, 14, 30, 45, 60, 90]

struct DcHeaderCard: View {
  let type: DocType
  let isNew: Bool
  @Binding var doc: JSONValue
  @Binding var errors: [String: String]
  let numberHint: String
  let onContact: (String) -> Void
  let onNewContact: (String) -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    let one = model.one
    let company = one.company
    let unnumbered = DcRules.waitsForNumber(company: company, doc)
    let companyCurrency = company?.str("currency") ?? "KWD"
    let paid = doc.obj("totals")?.num("paid") ?? 0
    Card {
      CardBody {
        Field(t(type.contactLabel), error: errors["client"]) {
          Combobox(
            selection: contactBinding,
            options: DcOptions.contacts(one, purchase: type.isPurchase, chosen: doc.str("clientId")),
            placeholder: type.isPurchase ? t("Choose a vendor…") : t("Choose a client…"),
            searchPlaceholder: type.isPurchase ? t("Search vendors…") : t("Search clients…"),
            createLabel: type.isPurchase ? t("New vendor") : t("New client"), onCreate: onNewContact)
        }
        if type.isPurchase {
          Field(referenceLabel, optional: true) {
            DcTextField(text: $doc.dcString("vendorReference"), placeholder: t("As printed on their document"))
          }
        }
        Field(t(type.numberLabel), hint: numberFieldHint(unnumbered), error: errors["number"]) {
          TextInput(text: numberBinding, placeholder: unnumbered ? "" : numberHint)
        }
        if type != .purchaseOrder {
          Field(t("PO / reference"), optional: true) {
            DcTextField(text: $doc.dcString("poNumber"))
          }
        }
        Field(dateLabel) {
          DateField(value: issueDateBinding, required: true)
        }
        if type.dated {
          dueField
        }
        if type == .purchaseOrder || (!type.isPurchase && type != .credit) {
          Field(t("Delivery date"), optional: type != .deliveryNote) {
            DateField(value: $doc.dcDate("deliveryDate"))
          }
          Field(type == .deliveryNote || type == .purchaseOrder ? t("Deliver to") : t("Delivery place"), optional: true) {
            DcTextField(text: $doc.dcString("deliveryPlace"), placeholder: t("Site, warehouse or address"))
          }
        }
        if type == .deliveryNote && doc.str("status") == "delivered" {
          Field(t("Received by")) {
            DcTextField(text: $doc.dcString("receiverName"))
          }
          Field(t("Civil ID number"), optional: true) {
            DcTextField(text: $doc.dcString("receiverCivilId"), keyboard: .numberPad, leftToRight: true)
          }
        }
        if type.priced {
          Field(
            t("Currency"),
            hint: paid != 0 ? t("Payments or credits are recorded on it, so its currency stays.") : nil
          ) {
            Select(selection: $doc.dcString("currency"), options: DcOptions.currencies())
              .disabled(paid != 0)
          }
        }
        if doc.str("currency") != companyCurrency && showsRate {
          Field(t("Exchange rate"), hint: rateHint(companyCurrency)) {
            DcAmountField(value: $doc.dcDouble("exchangeRate"))
          }
        }
      }
    }
  }

  private var showsRate: Bool {
    type.isPurchase ? type != .purchaseOrder : DcRules.postsToLedger(type.rawValue)
  }

  private func rateHint(_ base: String) -> String {
    let rate = doc.number("exchangeRate").flatMap { $0 == 0 ? nil : Money.jsString($0) } ?? "?"
    return t(
      "1 {currency} = {rate} {base}, used for your books",
      ["currency": doc.str("currency"), "rate": rate, "base": base])
  }

  /// The vendor's own number for this document.
  private var referenceLabel: String {
    switch type {
    case .bill: t("Vendor's invoice number")
    case .vendorCredit: t("Vendor's credit note number")
    default: t("Vendor's quote number")
    }
  }

  private var dateLabel: String {
    switch type {
    case .bill: t("Bill date")
    case .purchaseOrder: t("Order date")
    case .vendorCredit: t("Date")
    default: t("Issue date")
    }
  }

  private func numberFieldHint(_ unnumbered: Bool) -> String? {
    guard doc.str("number").isEmpty else { return nil }
    if unnumbered { return t("Given when it is issued, so a draft that is deleted uses up no number.") }
    if isNew { return type.isPurchase ? t("Your own number, assigned when saved.") : t("Assigned automatically when saved.") }
    return nil
  }

  private var contactBinding: Binding<String?> {
    Binding<String?>(
      get: { doc.str("clientId").isEmpty ? nil : doc.str("clientId") },
      set: { picked in
        if let picked { onContact(picked) }
      })
  }

  private var numberBinding: Binding<String> {
    Binding<String>(
      get: { doc.str("number") },
      set: { number in
        doc.set("number", .string(number))
        errors["number"] = nil
      })
  }

  /// Days from the issue date to the due date, when there is one.
  private var termsDays: Int? {
    guard let due = doc.text("dueDate") else { return nil }
    return ISODates.daysBetween(doc.str("issueDate"), due)
  }

  private var issueDateBinding: Binding<String> {
    Binding<String>(
      get: { doc.str("issueDate") },
      set: { date in
        guard !date.isEmpty else { return }
        let days = termsDays
        doc.set("issueDate", .string(date))
        if let days, doc.text("dueDate") != nil { doc.set("dueDate", .string(ISODates.addDays(date, days))) }
      })
  }

  private var termsOptions: [SelectOption<String>] {
    let days = type.validity ? quoteValidity : paymentTerms
    var options = [SelectOption("none", type.validity ? t("No end date") : t("No due date"))]
    for day in days {
      let label: String
      if type.validity {
        label = tp(day, "{count} day", "{count} days")
      } else {
        label = day == 0 ? t("Due on receipt") : t("Net {days}", ["days": String(day)])
      }
      options.append(SelectOption(String(day), label))
    }
    options.append(SelectOption("custom", t("Custom")))
    return options
  }

  private var termsBinding: Binding<String> {
    Binding<String>(
      get: {
        guard let days = termsDays else { return "none" }
        let known = type.validity ? quoteValidity : paymentTerms
        return known.contains(days) ? String(days) : "custom"
      },
      set: { value in
        if value == "none" {
          doc.set("dueDate", .null)
        } else if let days = Int(value) {
          doc.set("dueDate", .string(ISODates.addDays(doc.str("issueDate"), days)))
        }
      })
  }

  private var dueField: some View {
    Field(type.validity ? t("Valid until") : t("Due date")) {
      VStack(spacing: 8) {
        Select(selection: termsBinding, options: termsOptions)
        DateField(value: $doc.dcDate("dueDate"))
      }
    }
  }
}

// MARK: The notes

struct DcNotesCard: View {
  let type: DocType
  @Binding var doc: JSONValue

  var body: some View {
    Card {
      CardHeader(type == .bill || type == .vendorCredit ? t("Notes") : t("Notes & terms"))
      CardBody {
        if type == .bill || type == .vendorCredit {
          Field(t("Notes"), hint: t("Only visible to you.")) {
            DcTextArea(text: $doc.dcString("privateNotes"), lines: 2)
          }
        } else {
          if type == .quote {
            Field(t("Introduction"), hint: t("Printed above the items.")) {
              DcTextArea(text: $doc.dcString("intro"), lines: 2)
            }
          }
          Field(t("Notes"), hint: t("Shown on the document.")) {
            DcTextArea(text: $doc.dcString("notes"), lines: 3)
          }
          Field(t("Terms & conditions")) {
            DcTextArea(text: $doc.dcString("terms"), lines: 3)
          }
          if type != .purchaseOrder {
            Field(t("Footer")) {
              DcTextField(text: $doc.dcString("footer"))
            }
          }
          Field(t("Private notes"), hint: t("Only visible to you, never printed.")) {
            DcTextArea(text: $doc.dcString("privateNotes"), lines: 2)
          }
        }
      }
    }
  }
}
