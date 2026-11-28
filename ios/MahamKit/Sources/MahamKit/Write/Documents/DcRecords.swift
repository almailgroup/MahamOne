import Foundation

/// The port of the web's contact and item writes (src/db/records.ts and
/// src/db/credit.ts). The item form's `saveItem` (src/db/inventory.ts) is
/// the inventory's port (`InventoryWrites.saveItem`).
public enum DcRecords {
  // MARK: Clients and vendors

  /// `isCustomer`: a contact is a client unless it says otherwise.
  public static func isCustomer(_ contact: JSONValue) -> Bool { contact["isCustomer"] != .bool(false) }

  /// `saveClient(input)`: a number when it has none, the first contact
  /// primary when none is, the email from the primary contact. Returns it.
  @discardableResult
  public static func saveClient(_ ctx: WriteContext, _ input: JSONValue) throws -> JSONValue {
    let existing = ctx.get("clients", input.dcId)
    if let existing, WebJS.truthy(existing["taxExempt"]) != WebJS.truthy(input["taxExempt"]),
      let company = ctx.get("companies", existing.dcText("companyId"))
    {
      // Issued documents of a closed period keep the tax they were posted with.
      let id = existing.dcId
      DcBooks.freezeLockedPostings(ctx, company) { $0["clientId"] == .string(id) }
    }
    var client = WebJS.spread(input)
    client["name"] = .string(WebJS.trim(input.dcText("name")))
    client["updatedAt"] = .string(ctx.stamp)
    if WebJS.trim(input.dcText("number")).isEmpty, let company = ctx.get("companies", input.dcText("companyId")) {
      let companyId = company.dcId
      let taken = Set(ctx.all("clients") { $0["companyId"] == .string(companyId) }.map { $0.dcText("number").lowercased() })
      let rule = NumberingRule(company["numbering"]?["client"] ?? .null)
      let allocated = Numbering.allocateNumber(rule, WebJS.prefix(input.dcText("createdAt"), 10)) {
        taken.contains($0.lowercased())
      }
      client["number"] = .string(allocated.number)
      var numbering = WebJS.spread(company["numbering"])
      numbering["client"] = allocated.rule.raw
      ctx.put("companies", DcJS.merge(company, [("numbering", .object(numbering))]))
    }
    // Keep the contact flagged as primary first and make sure one exists.
    var contacts = client["contacts"]?.array ?? []
    if !contacts.isEmpty && !contacts.contains(where: { WebJS.truthy($0["primary"]) }) {
      contacts = contacts.enumerated().map { index, contact in
        DcJS.merge(contact, [("primary", .bool(index == 0))])
      }
      client["contacts"] = .array(contacts)
    }
    let primary = contacts.first { WebJS.truthy($0["primary"]) }
    if !WebJS.truthy(client["email"]), let email = primary?["email"], WebJS.truthy(email) { client["email"] = email }
    let saved = JSONValue.object(client)
    ctx.put("clients", saved)
    if existing == nil {
      ctx.logActivity(
        entity: "client", entityId: saved.dcId, action: "created",
        message: ActivityMessage(
          isCustomer(saved) ? "Client {name} added" : "Vendor {name} added", vars: ["name": saved.dcText("name")],
          arabic: ["name": saved["nameAr"]?.string]),
        refs: ActivityRefs(clientId: saved.dcId))
    }
    return saved
  }

  /// `clientHasRecords(id)`: documents, payments, recurring invoices or expenses.
  public static func clientHasRecords(_ ctx: WriteContext, _ id: String) -> Bool {
    let mine = JSONValue.string(id)
    return ctx.all("documents").contains { $0["clientId"] == mine }
      || ctx.all("payments").contains { $0["clientId"] == mine }
      || ctx.all("recurring").contains { $0["clientId"] == mine }
      || ctx.all("expenses").contains { $0["vendorId"] == mine }
  }

  /// `deleteClient(id)`: refused while anything refers to it (archive it instead).
  public static func deleteClient(_ ctx: WriteContext, id: String) throws {
    if clientHasRecords(ctx, id) {
      throw WriteFailure("This contact has documents, payments or expenses. Archive it instead.")
    }
    let client = ctx.get("clients", id)
    ctx.delete("clients", id)
    if let client {
      ctx.logActivity(
        entity: "client", entityId: id, action: "deleted",
        message: ActivityMessage(
          isCustomer(client) ? "Client {name} deleted" : "Vendor {name} deleted",
          vars: ["name": client.dcText("name")], arabic: ["name": client["nameAr"]?.string]))
    }
  }

  /// `setCreditHold(clientId, hold)`: no new invoices or sales orders without
  /// an override while it holds; logged.
  public static func setCreditHold(_ ctx: WriteContext, clientId: String, hold: Bool) {
    guard let client = ctx.get("clients", clientId), WebJS.truthy(client["creditHold"]) != hold else { return }
    ctx.put("clients", DcJS.merge(client, [("creditHold", .bool(hold)), ("updatedAt", .string(ctx.stamp))]))
    ctx.logActivity(
      entity: "client", entityId: client.dcId, action: hold ? "credit_hold" : "credit_hold_lifted",
      message: ActivityMessage(
        hold ? "{name} put on credit hold" : "Credit hold lifted for {name}", vars: ["name": client.dcText("name")],
        arabic: ["name": client["nameAr"]?.string]),
      refs: ActivityRefs(clientId: client.dcId))
  }

  // MARK: Items

  /// `sellsProduct(id)`: sales documents with a line of the product.
  static func sellsProduct(_ id: String) -> (JSONValue) -> Bool {
    { doc in
      let type = doc.dcText("type")
      return (type == "invoice" || type == "credit") && doc.dcList("items").contains { $0["productId"] == .string(id) }
    }
  }

  /// `saveProduct(product)`: the name trimmed; sales of a closed period keep
  /// the income account they were posted to.
  @discardableResult
  public static func saveProduct(_ ctx: WriteContext, _ product: JSONValue) -> JSONValue {
    if let existing = ctx.get("products", product.dcId),
      (WebJS.present(existing["incomeAccountId"]) ?? .null) != (WebJS.present(product["incomeAccountId"]) ?? .null),
      let company = ctx.get("companies", existing.dcText("companyId"))
    {
      DcBooks.freezeLockedPostings(ctx, company, affected: sellsProduct(existing.dcId))
    }
    let updated = DcJS.merge(
      product, [("name", .string(WebJS.trim(product.dcText("name")))), ("updatedAt", .string(ctx.stamp))])
    ctx.put("products", updated)
    return updated
  }
}
