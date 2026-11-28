import MahamKit
import SwiftUI

// Settings → Compliance and files (`ComplianceSettingsDialog`) and
// Settings → Taxes (`TaxSettings`), saved natively.

// MARK: Compliance and files

/// The register's extras with the purposes of documents, and the file
/// finder, saved together as the web's dialog saves them: the purposes
/// first (a name given twice stops everything), then the extras, then the
/// finder. The reminders and drivers' licences are People's settings.
struct SwComplianceSettings: View {
  @Environment(AppModel.self) private var model
  @State private var extras = false
  @State private var finder = false
  @State private var purposes: [JSONValue] = []
  @State private var base: SwComplianceValues?
  @State private var saving = false

  var body: some View {
    let company = model.one.company
    let editable = SwAccess(model).edits && SwAccess.can(.companies, .activities)
    SwSettingsCard(
      t("Compliance and files"),
      description: t(
        "Reminders and deadlines, drivers’ licences, contracts, customers’ papers and vehicles in the register, and the Files page with files and papers in search, for Books too."
      )
    ) {
      Switch(
        t("Contracts, customers and vehicles"),
        description: t(
          "Company and customer contracts, cost sheets, what each document is for, the company’s vehicles with their papers, and confidential documents only owners, admins and accountants see."
        ), isOn: $extras)
      if extras { purposesList }
      Switch(
        t("Find files and papers"),
        description: t(
          "A Files page lists every file kept with the company’s records, and search also finds files, papers on employees’ records, expenses, fixed assets and security cheques. Staff and viewers never see employees’ files."
        ), isOn: $finder)
      if editable && dirty {
        HStack(spacing: 8) {
          Spacer(minLength: 0)
          WebButton(t("Reset"), variant: .outline) { reset(company) }
          WebButton(t("Save"), loading: saving) { save() }
        }
      }
    }
    .disabled(!editable)
    .onChange(of: company, initial: true) { _, latest in
      if !dirty || base == nil { reset(latest) }
    }
  }

  private var values: SwComplianceValues { SwComplianceValues(extras: extras, finder: finder, purposes: purposes) }
  private var dirty: Bool { base != values }

  private func reset(_ company: JSONValue?) {
    let start = SwComplianceValues(company)
    extras = start.extras
    finder = start.finder
    purposes = start.purposes
    base = start
  }

  @ViewBuilder
  private var purposesList: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(t("Purposes of documents")).font(.web(14, .medium))
      if purposes.isEmpty {
        Text(t("What documents are for, such as a tender, a site or a bank facility.")).font(.web(12))
      }
      ForEach(purposes.indices, id: \.self) { index in
        purposeRow(index)
      }
      WebButton(t("Add purpose"), icon: .plus, variant: .outline, size: .sm) {
        purposes.append(["id": .string(newId()), "name": "", "nameAr": ""])
      }
    }
  }

  private func purposeRow(_ index: Int) -> some View {
    let archived = purposes[index].flag("archived")
    return HStack(spacing: 8) {
      TextInput(text: field(index, "name"), placeholder: t("Name (English)")).disabled(archived)
      TextInput(text: field(index, "nameAr"), placeholder: t("Name (Arabic)")).disabled(archived)
      WebButton(
        icon: archived ? .archiveRestore : .archive,
        label: archived
          ? t("Restore {name}", ["name": purposes[index].str("name")])
          : t("Archive {name}", ["name": purposes[index].str("name")]), variant: .ghost, size: .iconSmall
      ) {
        purposes[index].set("archived", .bool(!archived))
      }
    }
  }

  private func field(_ index: Int, _ key: String) -> Binding<String> {
    Binding(
      get: { purposes.indices.contains(index) ? purposes[index].str(key) : "" },
      set: { value in
        guard purposes.indices.contains(index) else { return }
        purposes[index].set(key, .string(value))
      })
  }

  private func save() {
    let wanted = values
    saving = true
    Task {
      let ok = await SwSave.run(model, done: t("Settings saved")) { ctx in
        if wanted.extras { try SwCompliance.savePurposes(ctx, wanted.purposes) }
        SwCompliance.setRegisterExtras(ctx, on: wanted.extras)
        SwCompliance.setFileFinder(ctx, on: wanted.finder)
      }
      saving = false
      if ok { reset(model.one.company) }
    }
  }
}

/// What the compliance settings hold.
private struct SwComplianceValues: Equatable {
  var extras: Bool
  var finder: Bool
  var purposes: [JSONValue]

  init(extras: Bool, finder: Bool, purposes: [JSONValue]) {
    self.extras = extras
    self.finder = finder
    self.purposes = purposes
  }

  init(_ company: JSONValue?) {
    extras = company?["registerExtras"] == .bool(true)
    finder = company?["fileFinder"] == .bool(true)
    purposes = company?.list("documentPurposes") ?? []
  }
}

// MARK: Taxes

/// The kinds of tax rate, in the web's order (`TAX_KINDS`, `KIND_TEXT`).
private enum SwTaxKinds {
  static let all: [(value: String, label: String)] = [
    ("standard", "Standard"), ("reduced", "Reduced"), ("zero", "Zero-rated"), ("exempt", "Exempt"),
    ("reverse_charge", "Reverse charge"), ("out_of_scope", "Outside the scope"),
  ]

  /// `taxKind(rate)`: its own kind, else standard above 0%, exempt when named so, else zero-rated.
  static func of(_ rate: JSONValue) -> String {
    if let kind = rate.text("kind") { return kind }
    if rate.num("rate") > 0 { return "standard" }
    return rate.str("name").range(of: "exempt", options: .caseInsensitive) != nil ? "exempt" : "zero"
  }

  static func order(_ kind: String) -> Int {
    all.firstIndex { $0.value == kind } ?? -1
  }
}

/// Settings → Taxes: taxes on or off (at once), the rates (each saved as it
/// changes), and how taxes are applied with the default rates (saved with Save).
struct SwTaxSettings: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    SwCompanyEditor { draft in
      SwTaxFields(draft: draft)
    }
  }
}

private struct SwTaxFields: View {
  @Binding var draft: JSONValue
  @Environment(AppModel.self) private var model
  @State private var busy = false
  @State private var deleting: JSONValue?

  private var rates: [JSONValue] {
    model.one.records(.taxRates).filter { $0.str("companyId") == draft.rid }
  }

  private var editable: Bool { SwAccess(model).edits && SwAccess.can(.companies, .taxRates) }

  var body: some View {
    let enabled = SwCompany.taxesEnabled(draft, rates: rates.count)
    SwSettingsCard(t("Tax"), description: t("Kuwait has no VAT today, so most businesses leave this off.")) {
      Switch(
        t("This business charges tax"),
        description: enabled
          ? t("Invoices and bills can carry tax, and tax returns are available.")
          : t("Invoices and bills have no tax lines, and tax returns are hidden."),
        isOn: Binding(get: { enabled }, set: { switchTaxes($0) })
      )
      .disabled(!editable || busy)
    }
    if enabled {
      ratesCard
      SwSettingsCard(t("How taxes are applied")) {
        Switch(
          t("Tax per line item"), description: t("Choose taxes for each line, needed when items have different rates."),
          isOn: SwBind.flag($draft, ["defaults", "lineTaxes"]))
        Switch(
          t("Tax on the invoice total"), description: t("Apply one or more taxes to the whole invoice."),
          isOn: SwBind.flag($draft, ["defaults", "documentTaxes"]))
        Switch(
          t("Prices include tax"), description: t("Enter prices with tax included; the tax is shown as “includes”."),
          isOn: SwBind.flag($draft, ["defaults", "pricesIncludeTax"]))
      }
    }
  }

  private var sorted: [JSONValue] {
    rates.sorted { a, b in
      if a.str("createdAt") != b.str("createdAt") { return a.str("createdAt") < b.str("createdAt") }
      let (ka, kb) = (SwTaxKinds.order(SwTaxKinds.of(a)), SwTaxKinds.order(SwTaxKinds.of(b)))
      if ka != kb { return ka < kb }
      return a.num("rate") > b.num("rate")
    }
  }

  private var ratesCard: some View {
    Card {
      CardHeader(
        t("Tax rates"),
        description: t(
          "Rates you can pick on invoices and bills. Starred rates are applied to new items. The kind decides where each rate goes on your tax return."
        )
      ) {
        if editable {
          WebButton(t("Add rate"), icon: .plus, variant: .outline, size: .sm) { addRate() }
        }
      }
      CardBody {
        if rates.isEmpty {
          Text(t("No tax rates yet. Add the rates you charge.")).font(.web(14))
        }
        ForEach(sorted.map(Rec.init)) { rate in
          SwTaxRateRow(
            rate: rate.raw, isDefault: defaults.contains(.string(rate.id)), editable: editable,
            onToggleDefault: { toggleDefault(rate.id) }, onDelete: { deleting = rate.raw })
        }
      }
    }
    .webDialog(
      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      title: t(
        "Delete {name} {rate}%?",
        ["name": deleting?.str("name") ?? "", "rate": Money.jsString(deleting?.num("rate") ?? 0)]),
      description: t("Existing documents keep their taxes. It will no longer be offered on new items.")
    ) {
      EmptyView()
    } footer: {
      SwConfirmFooter(label: t("Delete"), danger: true, onCancel: { deleting = nil }) { deleteRate() }
    }
  }

  private var defaults: [JSONValue] { draft["defaults"]?["defaultTaxRateIds"]?.array ?? [] }

  private func toggleDefault(_ id: String) {
    let list = defaults
    let next = list.contains(.string(id)) ? list.filter { $0 != .string(id) } : list + [.string(id)]
    draft = SwBind.set(draft, ["defaults", "defaultTaxRateIds"], .array(next))
  }

  /// `saveWith((current) => withTaxes(current, on))`: the draft as it is, with taxes switched.
  private func switchTaxes(_ on: Bool) {
    let next = SwCompany.withTaxes(draft, enabled: on)
    busy = true
    Task {
      let ok = await SwSave.run(model, done: on ? t("Taxes turned on") : t("Taxes turned off")) { ctx in
        SwCompany.save(ctx, next)
      }
      busy = false
      if ok, let saved = model.one.company { draft = saved }
    }
  }

  private func addRate() {
    let name = t("Tax")
    Task {
      await SwSave.run(model) { ctx in SwCompany.addTaxRate(ctx, name: name) }
    }
  }

  private func deleteRate() {
    guard let rate = deleting else { return }
    deleting = nil
    let id = rate.rid
    Task {
      await SwSave.run(model, done: t("Tax rate deleted")) { ctx in SwCompany.deleteTaxRate(ctx, id: id) }
    }
  }
}

/// A tax rate: its name and rate (saved once changed, with the check), its
/// kind (saved at once), whether new items get it, and Delete.
private struct SwTaxRateRow: View {
  let rate: JSONValue
  let isDefault: Bool
  let editable: Bool
  let onToggleDefault: () -> Void
  let onDelete: () -> Void
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette
  @State private var name = ""
  @State private var value: Double = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        TextInput(text: $name, placeholder: t("Tax name"))
        SwNumberField(value: $value, blankZero: false).frame(width: 100)
        Text(verbatim: "%").font(.web(14)).foregroundStyle(palette.slate(500))
      }
      HStack(spacing: 8) {
        Select(selection: kindBinding, options: SwTaxKinds.all.map { SelectOption($0.value, t($0.label)) })
        WebButton(
          icon: .star, label: isDefault ? t("Remove as default") : t("Make default"),
          variant: isDefault ? .subtle : .ghost, size: .iconSmall
        ) { onToggleDefault() }
        WebButton(icon: .trash2, label: t("Delete {name}", ["name": rate.str("name")]), size: .iconSmall) {
          onDelete()
        }
        if changed {
          WebButton(icon: .check, label: t("Save"), variant: .primary, size: .iconSmall) { commit() }
        }
      }
    }
    .padding(.vertical, 6)
    .disabled(!editable)
    .onChange(of: rate, initial: true) { _, latest in
      name = latest.str("name")
      value = latest.num("rate")
    }
  }

  /// The name is saved only when it has one (`name.trim() && name !== rate.name`).
  private var changed: Bool {
    (!SwText.trim(name).isEmpty && name != rate.str("name")) || value != rate.num("rate")
  }

  private var kindBinding: Binding<String> {
    Binding(get: { SwTaxKinds.of(rate) }, set: { save(["kind": .string($0)]) })
  }

  private func commit() {
    var patch: [String: JSONValue] = [:]
    if !SwText.trim(name).isEmpty && name != rate.str("name") { patch["name"] = .string(name) }
    if value != rate.num("rate") { patch["rate"] = .number(value) }
    save(patch)
  }

  /// `saveTaxRate({ ...rate, ...patch })`.
  private func save(_ patch: [String: JSONValue]) {
    var fields = rate.object ?? [:]
    for (key, field) in patch { fields[key] = field }
    let next = JSONValue.object(fields)
    Task {
      await SwSave.run(model) { ctx in SwCompany.saveTaxRate(ctx, next) }
    }
  }
}
