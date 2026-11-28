import MahamKit
import SwiftUI
import UIKit

// The client and vendor form (`src/features/clients/client-form.tsx`), as
// its own page (`/clients/new`, `/clients/:id/edit`, `/vendors/…`) and as the
// editors' quick "New client" / "New vendor" sheet. Saving goes through the
// port of the web's `saveClient`.

/// `CONTACT_COPY`: the words of each kind of contact.
struct DcContactCopy {
  let kind: ContactKind

  var title: String { kind == .vendor ? "Vendors" : "Clients" }
  var newLabel: String { kind == .vendor ? "New vendor" : "New client" }
  var saveLabel: String { kind == .vendor ? "Save vendor" : "Save client" }
  var added: String { kind == .vendor ? "Vendor {name} added" : "Client {name} added" }
  var notFound: String { kind == .vendor ? "This vendor could not be found." : "This client could not be found." }
  var quickHint: String {
    kind == .vendor
      ? "You can add more details later from the Vendors page." : "You can add more details later from the Clients page."
  }
}

@MainActor
enum DcContacts {
  /// A new contact of the kind (`createClient` with `contactRoles(kind)`), its first person primary.
  nonisolated static func blank(_ ctx: WriteContext, company: JSONValue, kind: ContactKind, name: String) -> JSONValue {
    let country = company.obj("address")?.str("country") ?? ""
    var overrides: [String: JSONValue] = [
      "id": .string(ctx.newId()), "name": .string(name), "contacts": .array([person(primary: true)]),
      "address": Geo.emptyAddress(country),
    ]
    if kind == .vendor {
      overrides["isCustomer"] = false
      overrides["isVendor"] = true
    } else {
      overrides["isCustomer"] = true
    }
    return Defaults.createClient(companyId: company.rid, overrides, now: ctx.now)
  }

  /// `newContact(primary)`: a person at the contact.
  nonisolated static func person(primary: Bool) -> JSONValue {
    .object([
      "id": .string(MahamKit.shortId()), "name": "", "email": "", "phone": "", "primary": .bool(primary),
    ])
  }

  /// The people kept when saving: those with a name, an email or a phone.
  nonisolated static func cleaned(_ contact: JSONValue) -> JSONValue {
    let people = contact.list("contacts").filter { person in
      !person.str("name").trimmingCharacters(in: .whitespaces).isEmpty
        || !person.str("email").trimmingCharacters(in: .whitespaces).isEmpty
        || !person.str("phone").trimmingCharacters(in: .whitespaces).isEmpty
    }
    return DcDocuments.applying(contact, [("contacts", .array(people))])
  }

  /// `taxIdLabel(company)`.
  static func taxIdLabel(_ company: JSONValue?) -> String {
    let label = (company?.str("taxIdLabel") ?? "").trimmingCharacters(in: .whitespaces)
    if label.isEmpty { return t("Tax ID") }
    return ["Tax card no.", "VAT No.", "Tax ID", "Tax No."].contains(label) ? t(label) : label
  }
}

/// `/clients/new`, `/clients/:id/edit`, `/vendors/new`, `/vendors/:id/edit`.
struct DcContactFormPage: View {
  let kind: ContactKind
  let id: String?
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @State private var contact: JSONValue?
  @State private var original: JSONValue?
  @State private var nameError: String?
  @State private var saving = false
  @State private var missing = false
  @State private var confirm: DcConfirm?

  init(kind: ContactKind, id: String?) {
    self.kind = kind
    self.id = id
  }

  var body: some View {
    let copy = DcContactCopy(kind: kind)
    content(copy)
      .task(id: model.one.revision) { await load() }
      .dcConfirm($confirm)
  }

  @ViewBuilder
  private func content(_ copy: DcContactCopy) -> some View {
    if let contact {
      WebPage(spacing: 16) {
        PageHeader(title(copy, contact), breadcrumb: t(copy.title), onBreadcrumb: { cancel() })
        Card {
          CardBody {
            DcContactFields(kind: kind, contact: binding(contact), nameError: nameError, compact: false)
          }
        }
      }
      .stickyActions {
        WebButton(t("Cancel"), variant: .ghost) { cancel() }
        WebButton(t(copy.saveLabel), loading: saving) { Task { await save(copy) } }
      }
    } else if missing {
      WebPage { Card { WebEmptyState(icon: .userRound, title: t(copy.notFound)) } }
    } else {
      WebPage { Card { DataLoadingRow() } }
    }
  }

  private func title(_ copy: DcContactCopy, _ contact: JSONValue) -> String {
    id != nil && !contact.str("name").isEmpty ? t("Edit {name}", ["name": contact.str("name")]) : t(copy.newLabel)
  }

  private func binding(_ fallback: JSONValue) -> Binding<JSONValue> {
    Binding(get: { contact ?? fallback }, set: { contact = $0 })
  }

  private func load() async {
    guard contact == nil, !missing else { return }
    let one = model.one
    if let id {
      guard let found = one.record(.clients, id) else {
        missing = one.hasData && one.phase == .ready
        return
      }
      contact = found
      original = found
    } else {
      guard let company = one.company else { return }
      let shown = kind
      let blank = try? await one.write { ctx in DcContacts.blank(ctx, company: company, kind: shown, name: "") }
      contact = blank
      original = blank
    }
  }

  private func cancel() {
    if contact != original {
      confirm = DcConfirm(
        title: t("Discard unsaved changes?"), description: t("You have changes that have not been saved yet."),
        confirmLabel: t("Discard changes"), cancelLabel: t("Keep editing"), danger: true
      ) { router.back() }
    } else {
      router.back()
    }
  }

  private func save(_ copy: DcContactCopy) async {
    guard let contact, !saving else { return }
    if contact.str("name").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      nameError = t("Please enter a name.")
      model.toast = Toast(kind: .error, message: t("Please fix the highlighted fields."))
      return
    }
    nameError = nil
    saving = true
    defer { saving = false }
    let input = DcContacts.cleaned(contact)
    do {
      let saved = try await model.one.write { ctx in try DcRecords.saveClient(ctx, input) }
      model.confirm(t("{name} saved", ["name": saved.str("name")]))
      original = self.contact
      let page = Route.contact(kind, id: saved.rid)
      router.back()
      if router.current != page { router.push(page) }
    } catch {
      DcWrite.fail(model, error)
    }
  }
}

/// The editors' quick "New client" (or vendor): the main fields, saved at once.
struct DcContactSheet: View {
  let kind: ContactKind
  let name: String
  let onSaved: (JSONValue) -> Void
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.palette) private var palette
  @State private var contact: JSONValue?
  @State private var nameError: String?
  @State private var saving = false

  init(kind: ContactKind, name: String, onSaved: @escaping (JSONValue) -> Void) {
    self.kind = kind
    self.name = name
    self.onSaved = onSaved
  }

  var body: some View {
    let copy = DcContactCopy(kind: kind)
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text(t(copy.quickHint)).font(.web(14)).foregroundStyle(palette.slate(500))
          if let contact {
            DcContactFields(kind: kind, contact: binding(contact), nameError: nameError, compact: true)
          } else {
            Spinner(t("Loading…"))
          }
        }
        .padding(16)
      }
      .background(palette.page.ignoresSafeArea())
      .navigationTitle(t(copy.newLabel))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(t(copy.saveLabel)) { Task { await save(copy) } }
            .disabled(saving || contact == nil)
        }
      }
    }
    .task { await load() }
  }

  private func binding(_ fallback: JSONValue) -> Binding<JSONValue> {
    Binding(get: { contact ?? fallback }, set: { contact = $0 })
  }

  private func load() async {
    guard contact == nil, let company = model.one.company else { return }
    let shown = kind
    let typed = name
    contact = try? await model.one.write { ctx in DcContacts.blank(ctx, company: company, kind: shown, name: typed) }
  }

  private func save(_ copy: DcContactCopy) async {
    guard let contact, !saving else { return }
    if contact.str("name").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      nameError = t("Please enter a name.")
      return
    }
    saving = true
    defer { saving = false }
    let input = DcContacts.cleaned(contact)
    do {
      let saved = try await model.one.write { ctx in try DcRecords.saveClient(ctx, input) }
      model.confirm(t(copy.added, ["name": saved.str("name")]))
      onSaved(saved)
      dismiss()
    } catch {
      DcWrite.fail(model, error)
    }
  }
}

/// `ClientForm`: names, people, address, tax and Civil ID, phone; with
/// `compact` off also the website, currency, terms, language, tax exemption,
/// roles, credit control, retention and notes.
struct DcContactFields: View {
  let kind: ContactKind
  @Binding var contact: JSONValue
  let nameError: String?
  let compact: Bool
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette

  var body: some View {
    let company = model.one.company
    let customer = contact["isCustomer"]?.bool != false
    let vendor = contact.flag("isVendor")
    VStack(alignment: .leading, spacing: 16) {
      Field(
        kind == .vendor ? t("Vendor name") : t("Client name"),
        hint: kind == .vendor ? t("Company or person you buy from.") : t("Company or person you are billing."),
        error: nameError
      ) {
        TextInput(text: $contact.dcString("name"))
      }
      Field(t("Arabic name"), hint: t("Printed on Arabic and bilingual documents."), optional: true) {
        TextInput(text: $contact.dcString("nameAr"))
          .environment(\.layoutDirection, .rightToLeft)
      }
      people
      DcAddressFields(title: customer ? t("Billing address") : t("Address"), address: $contact.dcObject("address"))
      if customer { shipping }
      Field(DcContacts.taxIdLabel(company), optional: true) {
        TextInput(text: $contact.dcString("taxId"))
      }
      Field(
        t("Civil ID"), hint: t("For individual customers and cheque drawers."), error: civilIdError, optional: true
      ) {
        DcTextField(text: $contact.dcString("civilId"), keyboard: .numberPad, leftToRight: true)
      }
      Field(t("Phone (main)"), optional: true) {
        DcTextField(text: $contact.dcString("phone"), keyboard: .phonePad, leftToRight: true)
      }
      if !compact {
        more(company: company, customer: customer, vendor: vendor)
      }
    }
  }

  private var civilIdError: String? {
    let civilId = contact.str("civilId").trimmingCharacters(in: .whitespaces)
    return !civilId.isEmpty && !Kuwait.isValidCivilId(civilId)
      ? t("This Civil ID does not look right. Check the 12 digits.") : nil
  }

  private var people: some View {
    let list = contact.list("contacts")
    return VStack(alignment: .leading, spacing: 12) {
      Text(t("Contacts")).font(.web(14, .semibold)).foregroundStyle(palette.slate(900))
      ForEach(DcIndexed.list(list)) { row in
        DcPersonRow(
          person: personBinding(row.record.rid), canRemove: list.count > 1,
          onPrimary: { makePrimary(row.record.rid) },
          onRemove: { contact.set("contacts", .array(contact.list("contacts").filter { $0.rid != row.record.rid })) })
      }
      WebButton(t("Add contact"), icon: .plus, variant: .ghost, size: .sm) {
        contact.set("contacts", .array(contact.list("contacts") + [DcContacts.person(primary: false)]))
      }
    }
  }

  private func personBinding(_ id: String) -> Binding<JSONValue> {
    Binding<JSONValue>(
      get: { contact.list("contacts").first { $0.rid == id } ?? .null },
      set: { person in
        contact.set("contacts", .array(contact.list("contacts").map { $0.rid == id ? person : $0 }))
      })
  }

  private func makePrimary(_ id: String) {
    let people = contact.list("contacts").map { DcDocuments.applying($0, [("primary", .bool($0.rid == id))]) }
    contact.set("contacts", .array(people))
  }

  @ViewBuilder
  private var shipping: some View {
    Switch(t("Different shipping address"), isOn: shippingBinding)
    if contact.obj("shippingAddress") != nil {
      DcAddressFields(title: nil, address: $contact.dcObject("shippingAddress"))
    }
  }

  private var shippingBinding: Binding<Bool> {
    Binding<Bool>(
      get: { contact.obj("shippingAddress") != nil },
      set: { on in
        let country = contact.obj("address")?.str("country") ?? ""
        contact.set("shippingAddress", on ? Geo.emptyAddress(country) : JSONValue.null)
      })
  }

  @ViewBuilder
  private func more(company: JSONValue?, customer: Bool, vendor: Bool) -> some View {
    let companyCurrency = company?.str("currency") ?? "KWD"
    let termsDefault = Int(company?.obj("defaults")?.num("paymentTermsDays") ?? 30)
    Field(t("Website"), optional: true) {
      DcTextField(text: $contact.dcString("website"), keyboard: .URL, leftToRight: true)
    }
    Field(t("Currency"), hint: t("Leave as default to use {currency}.", ["currency": companyCurrency])) {
      Select(selection: currencyBinding(companyCurrency), options: DcOptions.currencies())
    }
    Field(t("Payment terms (days)"), hint: tp(termsDefault, "Default: {count} day", "Default: {count} days")) {
      HStack(spacing: 8) {
        DcAmountField(value: termsBinding(Double(termsDefault)))
        if contact["paymentTermsDays"]?.double != nil {
          WebButton(t("Default"), variant: .ghost, size: .sm) { contact.set("paymentTermsDays", .null) }
        }
      }
    }
    if customer {
      Field(t("Document language")) {
        Select(selection: languageBinding, options: languageOptions)
      }
    }
    Switch(
      t("Tax exempt"),
      description: vendor && !customer
        ? t("Not registered for tax: their bills never include tax.") : t("Taxes are never applied to their documents."),
      isOn: $contact.dcBool("taxExempt"))
    Switch(t("Client"), description: t("You send them quotes and invoices."), isOn: roleBinding("isCustomer"))
      .disabled(customer && !vendor)
    Switch(t("Vendor"), description: t("You record their bills and pay them."), isOn: roleBinding("isVendor"))
      .disabled(vendor && !customer)
    if customer { creditControl(companyCurrency) }
    retention(customer: customer, vendor: vendor)
    Field(t("Internal notes"), hint: t("Only visible to you.")) {
      DcTextArea(text: $contact.dcString("notes"), lines: 3)
    }
  }

  private func currencyBinding(_ companyCurrency: String) -> Binding<String> {
    Binding<String>(
      get: { contact.text("currency") ?? companyCurrency },
      set: { currency in
        contact.set("currency", currency == companyCurrency ? JSONValue.null : JSONValue.string(currency))
      })
  }

  private func termsBinding(_ fallback: Double) -> Binding<Double> {
    Binding<Double>(
      get: { contact["paymentTermsDays"]?.double ?? fallback },
      set: { days in contact.set("paymentTermsDays", .number(max(0, days.rounded()))) })
  }

  private var languageOptions: [SelectOption<String>] {
    let languages: [(String, String)] = [
      ("ar-en", "Arabic and English"), ("ar", "Arabic"), ("en", "English"), ("fr", "French"), ("es", "Spanish"),
      ("de", "German"), ("pt", "Portuguese"), ("it", "Italian"), ("nl", "Dutch"),
    ]
    return [SelectOption("", t("Company default"))] + languages.map { SelectOption($0.0, t($0.1)) }
  }

  private var languageBinding: Binding<String> {
    Binding<String>(
      get: { contact.text("language") ?? "" },
      set: { language in contact.set("language", language.isEmpty ? JSONValue.null : JSONValue.string(language)) })
  }

  /// A contact always keeps at least one role.
  private func roleBinding(_ key: String) -> Binding<Bool> {
    Binding<Bool>(
      get: { key == "isCustomer" ? contact["isCustomer"]?.bool != false : contact.flag("isVendor") },
      set: { on in contact.set(key, .bool(on)) })
  }

  @ViewBuilder
  private func creditControl(_ companyCurrency: String) -> some View {
    let limited = contact["creditLimit"]?.double != nil
    VStack(alignment: .leading, spacing: 12) {
      Text(t("Credit control")).font(.web(14, .semibold)).foregroundStyle(palette.slate(900))
      Switch(
        t("Set a credit limit"), description: t("You are warned before an invoice or sales order takes them over it."),
        isOn: limitBinding)
      if limited {
        Field(
          t("Credit limit"),
          hint: t("Open balance plus cheques not yet cleared, in {currency}.", ["currency": companyCurrency])
        ) {
          DcAmountField(value: $contact.dcDouble("creditLimit"))
        }
      }
      Switch(
        t("Credit hold"), description: t("New invoices and sales orders need an override."),
        isOn: $contact.dcBool("creditHold"))
    }
  }

  private var limitBinding: Binding<Bool> {
    Binding<Bool>(
      get: { contact["creditLimit"]?.double != nil },
      set: { on in
        contact.set("creditLimit", on ? JSONValue.number(contact["creditLimit"]?.double ?? 0) : JSONValue.null)
      })
  }

  @ViewBuilder
  private func retention(customer: Bool, vendor: Bool) -> some View {
    let held = DcRules.contactRetention(contact) > 0
    let kindKey = contact.text("retentionKind") ?? "tax"
    VStack(alignment: .leading, spacing: 12) {
      Text(t("Retention")).font(.web(14, .semibold)).foregroundStyle(palette.slate(900))
      Switch(
        customer && !vendor
          ? t("This client holds back a retention")
          : vendor && !customer ? t("You hold back a retention from this vendor") : t("Hold back a retention"),
        description: t("A share of each invoice or bill is held until a clearance certificate or the handover."),
        isOn: retentionBinding)
      if held {
        Field(t("Retention (%)")) {
          DcAmountField(value: retentionPercent)
        }
        Field(
          t("Held until"),
          hint: kindKey == "contract"
            ? t("Held until handover of the work.") : t("Held until the Ministry of Finance clearance certificate is shown.")
        ) {
          Select(
            selection: $contact.dcString("retentionKind"),
            options: [SelectOption("tax", t("Tax retention")), SelectOption("contract", t("Contract retention"))])
        }
      }
    }
  }

  private var retentionBinding: Binding<Bool> {
    Binding<Bool>(
      get: { DcRules.contactRetention(contact) > 0 },
      set: { on in
        if on {
          contact.set("retentionPercent", .number(5))
          contact.set("retentionKind", .string(contact.text("retentionKind") ?? "tax"))
        } else {
          contact.set("retentionPercent", .null)
        }
      })
  }

  private var retentionPercent: Binding<Double> {
    Binding<Double>(
      get: { contact.num("retentionPercent") },
      set: { percent in contact.set("retentionPercent", .number(min(max(percent, 0), 100))) })
  }
}

/// A person at the contact: name, email, phone, the primary star and remove.
struct DcPersonRow: View {
  @Binding var person: JSONValue
  let canRemove: Bool
  let onPrimary: () -> Void
  let onRemove: () -> Void
  @Environment(\.palette) private var palette

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    VStack(alignment: .leading, spacing: 10) {
      Field(t("Name")) { TextInput(text: $person.dcString("name")) }
      Field(t("Email")) {
        DcTextField(text: $person.dcString("email"), keyboard: .emailAddress, leftToRight: true)
      }
      Field(t("Phone")) {
        DcTextField(text: $person.dcString("phone"), keyboard: .phonePad, leftToRight: true)
      }
      HStack(spacing: 4) {
        WebButton(
          icon: .star, label: person.flag("primary") ? t("Primary contact") : t("Make primary contact")
        ) { onPrimary() }
        .foregroundStyle(person.flag("primary") ? palette[.amber(500)] : palette.slate(500))
        if canRemove {
          WebButton(icon: .trash2, label: t("Remove contact")) { onRemove() }
        }
      }
    }
    .padding(12)
    .overlay { shape.stroke(palette.slate(200), lineWidth: 1) }
  }
}

/// `AddressFields`: two lines, city, state, postal code and country.
struct DcAddressFields: View {
  let title: String?
  @Binding var address: JSONValue
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let title {
        Text(title).font(.web(14, .semibold)).foregroundStyle(palette.slate(900))
      }
      Field(t("Address line 1")) { TextInput(text: $address.dcString("line1")) }
      Field(t("Address line 2"), optional: true) { TextInput(text: $address.dcString("line2")) }
      Field(t("City")) { TextInput(text: $address.dcString("city")) }
      Field(t("State / region"), optional: true) { TextInput(text: $address.dcString("state")) }
      Field(t("Postal code")) { DcTextField(text: $address.dcString("postalCode"), leftToRight: true) }
      Field(t("Country")) { Select(selection: $address.dcString("country"), options: DcAddressFields.countries()) }
    }
  }

  @MainActor private static var countryCache: [String: [SelectOption<String>]] = [:]

  @MainActor
  static func countries() -> [SelectOption<String>] {
    let language = LanguageStore.shared.isArabic ? "ar" : "en"
    if let cached = countryCache[language] { return cached }
    let options = [SelectOption("", "—")] + Geo.countryOptions(locale: language).map { SelectOption($0.value, $0.label) }
    countryCache[language] = options
    return options
  }
}

extension Binding where Value == JSONValue {
  /// A nested object of the record (an address); empty when missing.
  func dcObject(_ key: String) -> Binding<JSONValue> {
    Binding<JSONValue>(
      get: {
        if let value = wrappedValue[key], value.object != nil { return value }
        return .object([:])
      },
      set: { value in
        var record = wrappedValue
        record.set(key, value)
        wrappedValue = record
      })
  }
}
