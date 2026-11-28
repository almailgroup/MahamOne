import MahamKit
import SwiftUI

// Warehouses saved natively (`src/apps/books/features/inventory/warehouse-dialog.tsx`
// and the warehouses tab of `inventory/index.tsx`): a showroom or a store,
// or a sub-warehouse of a main one looked after by an employee; made the
// default, archived or restored. Saved through the port of the web's
// `saveWarehouse` (MahamKit/Write/Inventory).

/// A warehouse being added or edited (`WarehouseDialog`'s state).
struct IwWarehouseDraft: Identifiable {
  var warehouse: JSONValue
  let original: JSONValue
  var error: String?
  var id: String { original.rid }
  var isNew: Bool { original.str("name").isEmpty }
  var isSub: Bool { warehouse.text("parentId") != nil }

  /// `createWarehouse(companyId, overrides)`.
  static func new(companyId: String, parentId: String? = nil) -> IwWarehouseDraft {
    let stamp = JSONValue.string(Defaults.nowStamp())
    var fields: [String: JSONValue] = [
      "id": .string(MahamKit.newId()), "companyId": .string(companyId), "name": "", "nameAr": "", "address": "",
      "isDefault": false, "archived": false, "createdAt": stamp, "updatedAt": stamp,
    ]
    if let parentId { fields["parentId"] = .string(parentId) }
    return IwWarehouseDraft(warehouse: .object(fields), original: .object(fields))
  }

  static func edit(_ warehouse: JSONValue) -> IwWarehouseDraft {
    IwWarehouseDraft(warehouse: warehouse, original: warehouse)
  }
}

/// Who may set up sub-warehouses and change their stock (`useWarehouseAccess`).
@MainActor
struct IwWarehouseAccess {
  let link: IwStockIssues.Link?

  init(_ model: AppModel) {
    link = IwSave.link(model)
  }

  var offered: Bool { IwStockIssues.issuesOffered(link) }
  var manages: Bool { IwStockIssues.managesWarehouses(link) }
  var subsOffered: Bool { offered && manages }
  func issuesFrom(_ warehouse: JSONValue) -> Bool { offered && IwStockIssues.issuesFrom(warehouse, link) }
}

extension View {
  /// The warehouse form, open while `draft` is set.
  func iwWarehouseDialog(_ draft: Binding<IwWarehouseDraft?>) -> some View {
    modifier(IwWarehouseDialog(draft: draft))
  }
}

private struct IwWarehouseDialog: ViewModifier {
  @Binding var draft: IwWarehouseDraft?
  @Environment(AppModel.self) private var model
  @State private var saving = false

  func body(content: Content) -> some View {
    content.webDialog(isPresented: open, title: title, description: description) {
      if let binding = Binding($draft) {
        IwWarehouseFields(draft: binding)
      }
    } footer: {
      WebButton(t("Cancel"), variant: .outline) { draft = nil }
      if IwGate.warehouses {
        WebButton(t("Save"), loading: saving) { save() }
      }
    }
  }

  private var open: Binding<Bool> {
    Binding(get: { draft != nil }, set: { if !$0 { draft = nil } })
  }

  private var title: String {
    guard let draft else { return "" }
    if draft.isNew { return draft.isSub ? t("New sub-warehouse") : t("New warehouse") }
    return t("Edit {name}", ["name": draft.original.str("name")])
  }

  private var description: String {
    draft?.isSub == true
      ? t("Stock reaches it from the main warehouse, and whoever looks after it issues items from it.")
      : t("A place you keep stock, such as a showroom or a store.")
  }

  private func save() {
    guard let current = draft else { return }
    let name = current.warehouse.str("name").trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty {
      draft?.error = t("Enter a name for the warehouse.")
      return
    }
    let input = current.warehouse
    saving = true
    Task {
      let saved = await IwSave.run(model, done: { (_: JSONValue) in t("{name} saved", ["name": name]) }) { ctx in
        try InventoryWrites.saveWarehouse(ctx, input)
      }
      saving = false
      if saved != nil { draft = nil }
    }
  }
}

/// The warehouse form's fields.
private struct IwWarehouseFields: View {
  @Binding var draft: IwWarehouseDraft
  @Environment(AppModel.self) private var model

  var body: some View {
    let one = model.one
    let access = IwWarehouseAccess(model)
    let all = one.records(.warehouses)
    let id = draft.original.rid
    let hasSubs = all.contains { $0.str("parentId") == id && !$0.flag("archived") }
    // Main warehouses it may belong to: in use, not itself, not a sub-warehouse.
    let mains = all.filter { $0.rid != id && !$0.flag("archived") && $0.text("parentId") == nil }
    VStack(alignment: .leading, spacing: 16) {
      if access.subsOffered && !draft.original.flag("isDefault") && !hasSubs && !mains.isEmpty {
        Field(t("Belongs to"), hint: t("A sub-warehouse gets its stock from its main warehouse.")) {
          Select(
            selection: parentBinding,
            options: [SelectOption("", t("Nothing: it is a main warehouse"))]
              + mains.map { SelectOption($0.rid, localName($0)) })
        }
      }
      if access.subsOffered && draft.isSub {
        Field(t("Looked after by"), hint: t("The employee responsible for the stock kept here."), optional: true) {
          Combobox(
            selection: keeperBinding, options: people(one), placeholder: t("Choose an employee…"),
            searchPlaceholder: t("Search employees…"), emptyText: t("No matches"))
        }
      }
      Field(t("Name"), error: draft.error) {
        TextInput(text: nameBinding, placeholder: draft.isSub ? t("e.g. Ahmed’s store") : t("e.g. Shuwaikh store"))
      }
      Field(t("Arabic name"), optional: true) {
        TextInput(text: text("nameAr"))
          .environment(\.layoutDirection, .rightToLeft)
      }
      Field(t("Address"), optional: true) {
        IwTextArea(text: text("address"))
      }
      if !draft.isSub {
        Switch(
          t("Default warehouse"), description: t("Bills and invoices move stock here unless a line says otherwise."),
          isOn: defaultBinding
        )
        .disabled(draft.original.flag("isDefault"))
      }
    }
  }

  private func text(_ key: String) -> Binding<String> {
    Binding(get: { draft.warehouse.str(key) }, set: { draft.warehouse.set(key, .string($0)) })
  }

  private var nameBinding: Binding<String> {
    Binding(
      get: { draft.warehouse.str("name") },
      set: { value in
        draft.warehouse.set("name", .string(value))
        draft.error = nil
      })
  }

  private var parentBinding: Binding<String> {
    Binding(
      get: { draft.warehouse["parentId"]?.string ?? "" },
      set: { value in
        draft.warehouse.set("parentId", value.isEmpty ? .null : .string(value))
        draft.warehouse.set("isDefault", false)
      })
  }

  private var defaultBinding: Binding<Bool> {
    Binding(get: { draft.warehouse.flag("isDefault") }, set: { draft.warehouse.set("isDefault", .bool($0)) })
  }

  private var keeperBinding: Binding<String?> {
    Binding(
      get: { draft.warehouse["keeper"]?["employeeId"]?.string ?? "" },
      set: { value in chooseKeeper(value ?? "") })
  }

  /// The current employees (and the one looking after it now), by name.
  private func people(_ one: OneData) -> [ComboOption] {
    let current = draft.warehouse["keeper"]?["employeeId"]?.string
    let employees = one.records(.employees)
      .filter { $0.str("status") != "left" || $0.rid == current }
      .sorted { InvText.byName($0, $1) }
    let options = employees.map { employee in
      ComboOption(
        value: employee.rid, label: localName(employee),
        detail: InvText.joined([employee.str("number"), employee.str("jobTitle")]),
        keywords: "\(employee.str("name")) \(employee.str("nameAr")) \(employee.str("jobTitle"))")
    }
    return [ComboOption(value: "", label: t("Nobody"))] + options
  }

  /// `chooseKeeper(employeeId)`: a new sub-warehouse is named after whoever looks after it.
  private func chooseKeeper(_ employeeId: String) {
    let keeper = draft.warehouse["keeper"]
    let userId = keeper?["userId"]?.string
    guard !employeeId.isEmpty, let employee = model.one.record(.employees, employeeId) else {
      if let userId, !userId.isEmpty {
        draft.warehouse.set(
          "keeper",
          .object([
            "employeeId": .null, "name": "", "nameAr": "", "jobTitle": "", "jobTitleAr": "", "userId": .string(userId),
          ]))
      } else {
        draft.warehouse.set("keeper", .null)
      }
      return
    }
    if draft.warehouse.str("name").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      draft.warehouse.set("name", .string(employee.str("name")))
      draft.warehouse.set("nameAr", .string(employee.str("nameAr")))
    }
    draft.warehouse.set(
      "keeper",
      .object([
        "employeeId": .string(employee.rid), "name": .string(employee.str("name")),
        "nameAr": .string(employee.str("nameAr")), "jobTitle": .string(employee.str("jobTitle")),
        "jobTitleAr": .string(employee.str("jobTitleAr")), "userId": userId.map(JSONValue.string) ?? .null,
      ]))
    draft.error = nil
  }
}

/// A warehouse's actions in the warehouses tab: Edit, Send stock (to a
/// sub-warehouse), Issue items, Add a sub-warehouse, Make default, Archive
/// or Restore.
struct IwWarehouseMenu: View {
  let warehouse: JSONValue
  let inventory: InvInventory
  let onEdit: (IwWarehouseDraft) -> Void
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let access = IwWarehouseAccess(model)
    let sub = warehouse.text("parentId") != nil
    let parent = inventory.warehouse(warehouse.text("parentId"))
    let archived = warehouse.flag("archived")
    // Stock is sent from the main warehouse; only those who manage warehouses
    // move a sub-warehouse's stock directly.
    let sendable =
      sub && parent != nil && parent?.flag("archived") == false && !archived && (access.manages || !access.offered)
      && IwGate.entries
    // Staff change no sub-warehouse once the server keeps them.
    let editable = !(sub && access.offered && !access.manages) && IwGate.warehouses
    let issues = sub && access.issuesFrom(warehouse) && IwGate.issues
    let adds = access.subsOffered && !sub && !archived && IwGate.warehouses
    let defaults = !warehouse.flag("isDefault") && !archived && !sub && IwGate.warehouses
    if IwGate.edits(model) && (editable || sendable || issues || adds || defaults) {
      DropdownMenu(alignment: .end, name: t("Actions for {name}", ["name": localName(warehouse)])) {
        IconView(.moreHorizontal).foregroundStyle(palette.slate(600))
      } items: {
        if editable {
          DropdownItem(t("Edit"), icon: .pencil) { onEdit(IwWarehouseDraft.edit(warehouse)) }
        }
        if sendable, let parent {
          DropdownItem(t("Send stock"), icon: .send) {
            IwIntent.entry(kind: "transfer", from: parent.rid, to: warehouse.rid)
            router.push(.newStockAdjustment)
          }
        }
        if issues {
          DropdownItem(t("Issue items"), icon: .shirt) {
            IwIntent.issue(warehouse: warehouse.rid)
            router.push(.newStockIssue)
          }
        }
        if adds {
          DropdownItem(t("Add a sub-warehouse"), icon: .cornerDownRight) {
            onEdit(IwWarehouseDraft.new(companyId: model.one.companyId ?? "", parentId: warehouse.rid))
          }
        }
        if defaults {
          DropdownItem(t("Make default"), icon: .star) { update(["isDefault": true]) }
        }
        if !warehouse.flag("isDefault") && editable {
          DropdownItem(archived ? t("Restore") : t("Archive"), icon: archived ? Icon.archiveRestore : Icon.archive) {
            update(["archived": .bool(!archived)])
          }
        }
      }
    }
  }

  /// `saveWarehouse({ ...w, ...patch })`.
  private func update(_ patch: [String: JSONValue]) {
    var input = warehouse
    for (key, value) in patch { input.set(key, value) }
    let changed = input
    Task {
      await IwSave.run(model) { ctx in try InventoryWrites.saveWarehouse(ctx, changed) }
    }
  }
}
