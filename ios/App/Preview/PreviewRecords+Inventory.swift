#if DEBUG
  // Preview mode's made-up items and stock (see PreviewRecords.swift): a few
  // services, a non-stock item and stock items in two warehouses and a
  // uniform store, with the movements the web would have costed for them
  // (opening stock, two bills, a landed cost, an invoice, transfers, items
  // issued, an adjustment). Every name, number and amount is invented.

  import Foundation
  import MahamKit

  extension PreviewRecords {
    /// The items and inventory area's records.
    static func inventoryArea(company: Company) -> [String: [JSONValue]] {
      let c = company.id
      return [
        "products": invProducts(c),
        "warehouses": invWarehouses(c),
        "stockMovements": invMovements(c),
        "stockEntries": invEntries(c),
        "stockIssues": [invIssue(c)],
        "landedCosts": [invLandedCost(c)],
        "documents": invDocuments(c),
        "approvals": [invIssueRequest(c)],
      ]
    }

    // MARK: Items

    private static func invProducts(_ c: String) -> [JSONValue] {
      [
        invProduct(
          c, "p-inv-x-pr-1", kind: "service", sku: "SRV-001", name: "Installation visit", nameAr: "زيارة تركيب",
          price: 25, unit: "hour", unitId: "hour"),
        // An item saved before inventory existed: no kind, so a service.
        invProduct(c, "p-inv-x-pr-2", kind: nil, sku: "", name: "Delivery within Kuwait", price: 5, unit: "trip"),
        invProduct(
          c, "p-inv-x-pr-3", kind: "non_stock", sku: "NS-010", name: "Printed flyers, 500", price: 18.5, cost: 11,
          unit: "box", unitId: "box"),
        invProduct(
          c, "p-inv-x-pr-4", kind: "stock", sku: "SKU-00001", name: "Mesh office chair", nameAr: "كرسي مكتب شبكي",
          price: 45, cost: 28, unit: "pcs", unitId: "pcs", reorder: 5, vendor: "p-vn-1", barcode: "6290000000017",
          hsCode: "9401.30"),
        invProduct(
          c, "p-inv-x-pr-5", kind: "stock", sku: "SKU-00002", name: "A4 copy paper", nameAr: "ورق تصوير A4",
          price: 1.75, cost: 1.2, unit: "box", unitId: "box", reorder: 40, vendor: "p-vn-1"),
        invProduct(
          c, "p-inv-x-pr-6", kind: "stock", sku: "SKU-00003", name: "Staff polo shirt", nameAr: "قميص بولو للموظفين",
          price: 0, cost: 3.5, unit: "pcs", unitId: "pcs"),
        invProduct(
          c, "p-inv-x-pr-7", kind: "stock", sku: "SKU-00004", name: "Desk lamp, old model", price: 9, cost: 6,
          unit: "pcs", unitId: "pcs", archived: true),
        invProduct(
          c, "p-inv-x-pr-8", kind: "stock", sku: "SKU-00005", name: "Whiteboard marker", price: 0.35, cost: 0.125,
          unit: "pcs", unitId: "pcs", reorder: 20),
      ]
    }

    private static func invProduct(
      _ c: String, _ id: String, kind: String?, sku: String, name: String, nameAr: String? = nil, price: Double,
      cost: Double? = nil, unit: String, unitId: String? = nil, reorder: Double? = nil, vendor: String? = nil,
      barcode: String = "", hsCode: String = "", archived: Bool = false
    ) -> JSONValue {
      var fields: [String: Any] = [
        "id": id, "companyId": c, "sku": sku, "name": name, "description": "", "unitPrice": price, "unit": unit,
        "taxRateIds": [String](), "incomeAccountId": NSNull(), "barcode": barcode, "hsCode": hsCode,
        "archived": archived, "createdAt": "\(day(-90))T08:00:00.000Z", "updatedAt": "\(day(-20))T08:00:00.000Z",
      ]
      if let kind { fields["kind"] = kind }
      if let nameAr { fields["nameAr"] = nameAr }
      if let cost { fields["costPrice"] = cost }
      if let unitId { fields["unitId"] = unitId }
      if let reorder {
        fields["reorderLevel"] = reorder
      } else if kind == "stock" {
        fields["reorderLevel"] = NSNull()
      }
      if let vendor {
        fields["preferredVendorId"] = vendor
      } else {
        fields["preferredVendorId"] = NSNull()
      }
      return rec(fields)
    }

    // MARK: Warehouses

    private static func invWarehouses(_ c: String) -> [JSONValue] {
      let keeper: [String: Any] = [
        "employeeId": "p-inv-x-emp-9", "name": "Sami Karim", "nameAr": "سامي كريم", "jobTitle": "Storekeeper",
        "jobTitleAr": "أمين مخزن", "userId": NSNull(),
      ]
      return [
        invWarehouse(
          c, "p-inv-x-wh-1", "Shuwaikh store", "مخزن الشويخ", address: "Shuwaikh Industrial, Block 2",
          isDefault: true),
        invWarehouse(c, "p-inv-x-wh-2", "Al-Rai showroom", "معرض الري", address: "Al-Rai, Street 30"),
        invWarehouse(
          c, "p-inv-x-wh-3", "Uniform store", "مخزن الزي", address: "", parent: "p-inv-x-wh-1", keeper: keeper),
      ]
    }

    private static func invWarehouse(
      _ c: String, _ id: String, _ name: String, _ nameAr: String, address: String, isDefault: Bool = false,
      parent: String? = nil, keeper: [String: Any]? = nil
    ) -> JSONValue {
      rec([
        "id": id, "companyId": c, "name": name, "nameAr": nameAr, "address": address, "isDefault": isDefault,
        "archived": false, "parentId": parent ?? NSNull(), "keeper": keeper ?? NSNull(),
        "createdAt": "\(day(-120))T08:00:00.000Z", "updatedAt": "\(day(-30))T08:00:00.000Z",
      ])
    }

    // MARK: Movements

    /// One movement as the web costs and stores it.
    private struct InvMove {
      let id: String
      let product: String
      let warehouse: String
      let date: String
      let quantity: Double
      let unitCost: Double
      let value: Double
      let source: String
      let sourceId: String
      let line: String
      let number: String
      var document: String?
      var sourceValue: Double?
      var basis: Double?
      var part = 0
      var index = 0
    }

    private static func invMovements(_ c: String) -> [JSONValue] {
      let chair = "p-inv-x-pr-4"
      let paper = "p-inv-x-pr-5"
      let polo = "p-inv-x-pr-6"
      let marker = "p-inv-x-pr-8"
      let (main, showroom, uniforms) = ("p-inv-x-wh-1", "p-inv-x-wh-2", "p-inv-x-wh-3")
      let moves: [InvMove] = [
        InvMove(
          id: "p-inv-x-mv-01", product: chair, warehouse: main, date: day(-60), quantity: 10, unitCost: 27,
          value: 270, source: "opening", sourceId: "p-inv-x-se-1", line: "p-inv-x-se-1-l1", number: "OPN-0001",
          sourceValue: 270),
        InvMove(
          id: "p-inv-x-mv-02", product: polo, warehouse: main, date: day(-60), quantity: 40, unitCost: 3.5,
          value: 140, source: "opening", sourceId: "p-inv-x-se-1", line: "p-inv-x-se-1-l2", number: "OPN-0001",
          sourceValue: 140, index: 1),
        InvMove(
          id: "p-inv-x-mv-03", product: chair, warehouse: main, date: day(-30), quantity: 12, unitCost: 28.5,
          value: 342, source: "bill", sourceId: "p-inv-x-bl-1", line: "p-inv-x-bl-1-l1", number: "BL-0101",
          document: "p-inv-x-bl-1", sourceValue: 342),
        InvMove(
          id: "p-inv-x-mv-04", product: paper, warehouse: main, date: day(-30), quantity: 50, unitCost: 1.15,
          value: 57.5, source: "bill", sourceId: "p-inv-x-bl-1", line: "p-inv-x-bl-1-l2", number: "BL-0101",
          document: "p-inv-x-bl-1", sourceValue: 57.5, index: 1),
        InvMove(
          id: "p-inv-x-mv-05", product: chair, warehouse: main, date: day(-28), quantity: 0, unitCost: 5.7,
          value: 68.4, source: "landed_cost", sourceId: "p-inv-x-lc-1", line: "p-inv-x-bl-1-l1", number: "LC-0001",
          document: "p-inv-x-bl-3", sourceValue: 68.4, basis: 12),
        InvMove(
          id: "p-inv-x-mv-06", product: paper, warehouse: main, date: day(-28), quantity: 0, unitCost: 0.23,
          value: 11.5, source: "landed_cost", sourceId: "p-inv-x-lc-1", line: "p-inv-x-bl-1-l2", number: "LC-0001",
          document: "p-inv-x-bl-3", sourceValue: 11.5, basis: 50, index: 1),
        InvMove(
          id: "p-inv-x-mv-07", product: chair, warehouse: main, date: day(-20), quantity: -4, unitCost: 30.927273,
          value: -123.709, source: "transfer", sourceId: "p-inv-x-se-3", line: "p-inv-x-se-3-l1", number: "TRF-0001"),
        InvMove(
          id: "p-inv-x-mv-08", product: chair, warehouse: showroom, date: day(-20), quantity: 4, unitCost: 30.927273,
          value: 123.709, source: "transfer", sourceId: "p-inv-x-se-3", line: "p-inv-x-se-3-l1", number: "TRF-0001",
          part: 1),
        InvMove(
          id: "p-inv-x-mv-09", product: polo, warehouse: main, date: day(-15), quantity: -25, unitCost: 3.5,
          value: -87.5, source: "transfer", sourceId: "p-inv-x-se-4", line: "p-inv-x-se-4-l1", number: "TRF-0002"),
        InvMove(
          id: "p-inv-x-mv-10", product: polo, warehouse: uniforms, date: day(-15), quantity: 25, unitCost: 3.5,
          value: 87.5, source: "transfer", sourceId: "p-inv-x-se-4", line: "p-inv-x-se-4-l1", number: "TRF-0002",
          part: 1),
        InvMove(
          id: "p-inv-x-mv-11", product: chair, warehouse: showroom, date: day(-10), quantity: -3, unitCost: 30.927333,
          value: -92.782, source: "invoice", sourceId: "p-inv-x-in-1", line: "p-inv-x-in-1-l1", number: "INV-0120",
          document: "p-inv-x-in-1"),
        InvMove(
          id: "p-inv-x-mv-12", product: paper, warehouse: main, date: day(-10), quantity: -20, unitCost: 1.38,
          value: -27.6, source: "invoice", sourceId: "p-inv-x-in-1", line: "p-inv-x-in-1-l2", number: "INV-0120",
          document: "p-inv-x-in-1", index: 1),
        // Sold before any was in stock: out at the cost price.
        InvMove(
          id: "p-inv-x-mv-13", product: marker, warehouse: main, date: day(-10), quantity: -12, unitCost: 0.125,
          value: -1.5, source: "invoice", sourceId: "p-inv-x-in-1", line: "p-inv-x-in-1-l3", number: "INV-0120",
          document: "p-inv-x-in-1", index: 2),
        InvMove(
          id: "p-inv-x-mv-14", product: polo, warehouse: uniforms, date: day(-7), quantity: -3, unitCost: 3.5,
          value: -10.5, source: "issue", sourceId: "p-inv-x-is-1", line: "p-inv-x-is-1-l1", number: "ISS-0001"),
        InvMove(
          id: "p-inv-x-mv-15", product: chair, warehouse: main, date: day(-5), quantity: -1, unitCost: 30.927,
          value: -30.927, source: "adjustment", sourceId: "p-inv-x-se-2", line: "p-inv-x-se-2-l1",
          number: "ADJ-0001"),
        // Brought in while below zero: the units sold short take the difference.
        InvMove(
          id: "p-inv-x-mv-16", product: marker, warehouse: main, date: day(-3), quantity: 10, unitCost: 0.12,
          value: 1.25, source: "bill", sourceId: "p-inv-x-bl-2", line: "p-inv-x-bl-2-l1", number: "BL-0102",
          document: "p-inv-x-bl-2", sourceValue: 1.2),
      ]
      return moves.map { invMovement(c, $0) }
    }

    private static func invMovement(_ c: String, _ m: InvMove) -> JSONValue {
      let stamp = "\(m.date)T08:00:00.000Z"
      let sequence = "\(stamp)|\(String(format: "%04d", m.index))|\(m.part)"
      return rec([
        "id": m.id, "companyId": c, "productId": m.product, "warehouseId": m.warehouse, "date": m.date,
        "quantity": m.quantity, "unitCost": m.unitCost, "value": m.value, "sourceType": m.source,
        "sourceId": m.sourceId, "lineId": m.line, "documentId": m.document ?? NSNull(), "number": m.number,
        "sourceValue": m.sourceValue ?? NSNull(), "returnOf": NSNull(), "basisQuantity": m.basis ?? NSNull(),
        "sequence": sequence, "notes": "", "createdAt": stamp, "updatedAt": stamp,
      ])
    }

    // MARK: Stock entries

    private static func invEntries(_ c: String) -> [JSONValue] {
      [
        invEntry(
          c, "p-inv-x-se-1", kind: "opening", number: "OPN-0001", date: day(-60), from: "p-inv-x-wh-1",
          lines: [
            invEntryLine("p-inv-x-se-1-l1", "p-inv-x-pr-4", 10, unitCost: 27),
            invEntryLine("p-inv-x-se-1-l2", "p-inv-x-pr-6", 40, unitCost: 3.5),
          ], notes: "Counted when the books moved to Maham One."),
        invEntry(
          c, "p-inv-x-se-3", kind: "transfer", number: "TRF-0001", date: day(-20), from: "p-inv-x-wh-1",
          to: "p-inv-x-wh-2", lines: [invEntryLine("p-inv-x-se-3-l1", "p-inv-x-pr-4", 4)]),
        invEntry(
          c, "p-inv-x-se-4", kind: "transfer", number: "TRF-0002", date: day(-15), from: "p-inv-x-wh-1",
          to: "p-inv-x-wh-3", lines: [invEntryLine("p-inv-x-se-4-l1", "p-inv-x-pr-6", 25)]),
        invEntry(
          c, "p-inv-x-se-2", kind: "adjustment", number: "ADJ-0001", date: day(-5), from: "p-inv-x-wh-1",
          reason: "damaged", reference: "Inspection 14", lines: [invEntryLine("p-inv-x-se-2-l1", "p-inv-x-pr-4", -1)]),
        invEntry(
          c, "p-inv-x-se-5", kind: "adjustment", number: "ADJ-0002", date: day(-2), from: "p-inv-x-wh-1",
          reason: "count", reference: "Stock count", lines: [invEntryLine("p-inv-x-se-5-l1", "p-inv-x-pr-5", 2)],
          voidedAt: "\(day(-1))T10:00:00.000Z"),
      ]
    }

    private static func invEntryLine(_ id: String, _ product: String, _ quantity: Double, unitCost: Double? = nil)
      -> [String: Any]
    {
      ["id": id, "productId": product, "quantity": quantity, "unitCost": unitCost ?? NSNull()]
    }

    private static func invEntry(
      _ c: String, _ id: String, kind: String, number: String, date: String, from: String, to: String? = nil,
      reason: String? = nil, reference: String = "", lines: [[String: Any]], notes: String = "",
      voidedAt: String? = nil
    ) -> JSONValue {
      rec([
        "id": id, "companyId": c, "kind": kind, "number": number, "date": date, "warehouseId": from,
        "toWarehouseId": to ?? NSNull(), "reason": reason ?? NSNull(), "reference": reference, "notes": notes,
        "lines": lines, "status": voidedAt == nil ? "posted" : "void", "voidedAt": voidedAt ?? NSNull(),
        "createdAt": "\(date)T08:00:00.000Z", "updatedAt": "\(voidedAt ?? date)",
      ])
    }

    // MARK: Items issued

    private static func invRecipient() -> [String: Any] {
      [
        "employeeId": "p-inv-x-emp-1", "number": "E-0107", "name": "Omar Saleh", "nameAr": "عمر صالح",
        "jobTitle": "Security guard", "jobTitleAr": "حارس أمن",
      ]
    }

    private static func invPoloLine(_ id: String, _ quantity: Double) -> [String: Any] {
      [
        "id": id, "productId": "p-inv-x-pr-6", "name": "Staff polo shirt", "nameAr": "قميص بولو للموظفين",
        "unit": "pcs", "quantity": quantity,
      ]
    }

    private static func invIssue(_ c: String) -> JSONValue {
      rec([
        "id": "p-inv-x-is-1", "companyId": c, "number": "ISS-0001", "date": day(-7), "warehouseId": "p-inv-x-wh-3",
        "recipient": invRecipient(), "issuedBy": NSNull(), "issuedByName": "Sami Karim (Storekeeper)",
        "requestId": "p-inv-x-ap-0", "approvedBy": NSNull(), "approvedByName": "Layla Nasser",
        "approvedAt": "\(day(-7))T11:20:00.000Z", "lines": [invPoloLine("p-inv-x-is-1-l1", 3)],
        "notes": "Two for the day shifts, one spare.", "status": "posted", "voidedAt": NSNull(),
        "createdAt": "\(day(-7))T09:05:00.000Z", "updatedAt": "\(day(-7))T11:20:00.000Z",
      ])
    }

    /// Items asked for, waiting for an approver.
    private static func invIssueRequest(_ c: String) -> JSONValue {
      let after: [String: Any] = [
        "number": "", "date": day(-1), "warehouseId": "p-inv-x-wh-3", "recipient": invRecipient(),
        "issuedBy": NSNull(), "issuedByName": "Sami Karim (Storekeeper)", "requestId": "p-inv-x-ap-1",
        "approvedBy": NSNull(), "approvedByName": "", "approvedAt": NSNull(),
        "lines": [invPoloLine("p-inv-x-is-2-l1", 2)], "notes": "", "status": "posted",
        "createdAt": "\(day(-1))T08:15:00.000Z", "updatedAt": "\(day(-1))T08:15:00.000Z",
      ]
      return rec([
        "id": "p-inv-x-ap-1", "companyId": c, "kind": "stock_issue", "subjectTbl": "stockIssues",
        "subjectId": "p-inv-x-is-2", "subjectNumber": "", "before": NSNull(), "after": after,
        "reason": "Replacement for a torn shirt.", "status": "pending", "requestedBy": "p-inv-x-user-1",
        "requestedByName": "Sami Karim (Storekeeper)", "requestedAt": "\(day(-1))T08:15:00.000Z",
        "decidedBy": NSNull(), "decidedAt": NSNull(), "decisionNote": "",
        "createdAt": "\(day(-1))T08:15:00.000Z", "updatedAt": "\(day(-1))T08:15:00.000Z",
      ])
    }

    // MARK: Landed cost and the documents behind the movements

    private static func invLandedCost(_ c: String) -> JSONValue {
      rec([
        "id": "p-inv-x-lc-1", "companyId": c, "number": "LC-0001", "billId": "p-inv-x-bl-3",
        "sourceLineIds": ["p-inv-x-bl-3-l1"], "targetBillId": "p-inv-x-bl-1", "targetLineIds": [String](),
        "method": "value", "notes": "Sea freight from Jebel Ali, shared by value.", "status": "active",
        "voidedAt": NSNull(), "createdAt": "\(day(-28))T12:00:00.000Z", "updatedAt": "\(day(-28))T12:00:00.000Z",
      ])
    }

    private static func invDocuments(_ c: String) -> [JSONValue] {
      [
        invDocument(
          c, "p-inv-x-bl-1", type: "bill", number: "BL-0101", status: "paid", contact: "p-vn-1", date: day(-30),
          lines: [
            invDocLine("p-inv-x-bl-1-l1", "p-inv-x-pr-4", "Mesh office chair", 12, "pcs", 28.5),
            invDocLine("p-inv-x-bl-1-l2", "p-inv-x-pr-5", "A4 copy paper", 50, "box", 1.15),
          ]),
        invDocument(
          c, "p-inv-x-bl-2", type: "bill", number: "BL-0102", status: "sent", contact: "p-vn-1", date: day(-3),
          lines: [invDocLine("p-inv-x-bl-2-l1", "p-inv-x-pr-8", "Whiteboard marker", 10, "pcs", 0.12)]),
        invDocument(
          c, "p-inv-x-bl-3", type: "bill", number: "BL-0103", status: "paid", contact: "p-vn-2", date: day(-28),
          lines: [invDocLine("p-inv-x-bl-3-l1", nil, "Sea freight and clearing", 1, "", 79.9)]),
        invDocument(
          c, "p-inv-x-in-1", type: "invoice", number: "INV-0120", status: "sent", contact: "p-cl-2", date: day(-10),
          lines: [
            invDocLine(
              "p-inv-x-in-1-l1", "p-inv-x-pr-4", "Mesh office chair", 3, "pcs", 45, warehouse: "p-inv-x-wh-2"),
            invDocLine("p-inv-x-in-1-l2", "p-inv-x-pr-5", "A4 copy paper", 20, "box", 1.75),
            invDocLine("p-inv-x-in-1-l3", "p-inv-x-pr-8", "Whiteboard marker", 12, "pcs", 0.35),
          ]),
      ]
    }

    private static func invDocLine(
      _ id: String, _ product: String?, _ name: String, _ quantity: Double, _ unit: String, _ price: Double,
      warehouse: String? = nil
    ) -> [String: Any] {
      [
        "id": id, "kind": "item", "productId": product ?? NSNull(), "name": name, "description": "",
        "quantity": quantity, "unit": unit, "unitPrice": price, "discount": 0, "discountType": "percent",
        "taxes": [Any](), "warehouseId": warehouse ?? NSNull(),
      ]
    }

    private static func invDocument(
      _ c: String, _ id: String, type: String, number: String, status: String, contact: String, date: String,
      lines: [[String: Any]]
    ) -> JSONValue {
      var total: Double = 0
      for line in lines {
        total += ((line["quantity"] as? Double) ?? 0) * ((line["unitPrice"] as? Double) ?? 0)
      }
      let rounded = (total * 1000).rounded() / 1000
      let paid = status == "paid" ? rounded : 0
      let totals: [String: Any] = [
        "subtotal": rounded, "discount": 0, "taxTotal": 0, "total": rounded, "paid": paid, "balance": rounded - paid,
      ]
      return rec([
        "id": id, "companyId": c, "type": type, "number": number, "status": status, "clientId": contact,
        "issueDate": date, "dueDate": ISODates.addDays(date, 30), "poNumber": "", "currency": "KWD", "items": lines,
        "discount": 0, "discountType": "percent", "taxes": [Any](), "charges": [Any](), "pricesIncludeTax": false,
        "deposit": 0, "depositDueDate": NSNull(), "notes": "", "terms": "", "footer": "", "privateNotes": "",
        "templateId": NSNull(), "totals": totals, "sentAt": "\(date)T09:30:00.000Z", "paidAt": NSNull(),
        "sourceId": NSNull(), "convertedToId": NSNull(), "recurringId": NSNull(), "archived": false,
        "createdAt": "\(date)T09:00:00.000Z", "updatedAt": "\(date)T09:00:00.000Z",
      ])
    }
  }
#endif
