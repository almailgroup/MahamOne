#if DEBUG
  // Preview mode's made-up records (see PreviewMode.swift and OneData), the
  // company's data as the sync engine would bring it. Every name, number and
  // amount here is invented; nothing is real.

  import Foundation
  import MahamKit

  enum PreviewRecords {
    /// Every table's records, for `OneData.openPreview`.
    static func all(company: Company) -> [String: [JSONValue]] {
      var tables: [String: [JSONValue]] = [:]
      for part in [sales(company: company), extra(company: company)] {
        for (table, records) in part { tables[table, default: []] += records }
      }
      return tables
    }

    /// Records of more areas, added as their pages come (see `PreviewRecords+Areas`).
    static func extra(company: Company) -> [String: [JSONValue]] {
      var tables: [String: [JSONValue]] = [:]
      for maker in areaMakers {
        for (table, records) in maker(company) { tables[table, default: []] += records }
      }
      return tables
    }

    /// Day `offset` from today, as the web stores dates ("2026-11-26").
    static func day(_ offset: Int) -> String {
      ISODates.addDays(ISODates.today(), offset)
    }

    /// A record from a dictionary literal.
    static func rec(_ fields: [String: Any]) -> JSONValue {
      let data = (try? JSONSerialization.data(withJSONObject: fields)) ?? Data("{}".utf8)
      return (try? JSONValue.parse(data)) ?? .object([:])
    }

    // MARK: Sales

    static func sales(company: Company) -> [String: [JSONValue]] {
      let c = company.id
      let companyRecord = rec([
        "id": c, "name": company.name, "currency": "KWD", "locale": "en-KW", "dateFormat": "dd/MM/yyyy",
        "email": "hello@example.com", "phone": "+965 2200 0000", "registerExtras": true, "fileFinder": true,
        "accounting": ["vat": ["registered": true]],
        "createdAt": day(-400), "updatedAt": day(-2),
      ])
      let clients = [
        contact("p-cl-1", c, "CL-001", "Blue Harbour Cafe", "مقهى الميناء الأزرق", customer: true),
        contact("p-cl-2", c, "CL-002", "Sandline Interiors", nil, customer: true),
        contact("p-cl-3", c, "CL-003", "Northwind Clinic", nil, customer: true),
        contact("p-vn-1", c, "VN-001", "Gulf Paper Supplies", nil, vendor: true),
        contact("p-vn-2", c, "VN-002", "Desert Logistics", nil, vendor: true),
      ]
      let documents = [
        doc("p-inv-1", c, "invoice", "INV-0107", "sent", "p-cl-1", day(-20), day(-5), total: 1250, paid: 0),
        doc("p-inv-2", c, "invoice", "INV-0108", "partial", "p-cl-2", day(-12), day(18), total: 860.5, paid: 400),
        doc("p-inv-3", c, "invoice", "INV-0109", "paid", "p-cl-3", day(-9), day(21), total: 2400, paid: 2400),
        doc("p-inv-4", c, "invoice", "INV-0110", "draft", "p-cl-1", day(-1), day(29), total: 315.75, paid: 0),
        doc("p-qt-1", c, "quote", "QT-0042", "sent", "p-cl-2", day(-6), day(24), total: 4200, paid: 0),
        doc("p-qt-2", c, "quote", "QT-0041", "accepted", "p-cl-3", day(-15), day(15), total: 980, paid: 0),
        doc("p-cr-1", c, "credit", "CN-0007", "sent", "p-cl-1", day(-3), nil, total: 120, paid: 0),
        doc("p-so-1", c, "sales_order", "SO-0019", "confirmed", "p-cl-2", day(-4), nil, total: 1730, paid: 0),
        doc("p-bl-1", c, "bill", "BL-0033", "sent", "p-vn-1", day(-18), day(-2), total: 540, paid: 0),
        doc("p-bl-2", c, "bill", "BL-0034", "paid", "p-vn-2", day(-10), day(20), total: 1210, paid: 1210),
        doc("p-po-1", c, "purchase_order", "PO-0011", "issued", "p-vn-1", day(-7), nil, total: 760, paid: 0),
      ]
      let payments = [
        rec([
          "id": "p-pay-1", "companyId": c, "direction": "in", "clientId": "p-cl-2", "number": "PAY-0051",
          "date": day(-8), "amount": 400, "currency": "KWD", "method": "bank_transfer", "reference": "TRX-5521",
          "notes": "", "allocations": [["documentId": "p-inv-2", "amount": 400]], "documentIds": ["p-inv-2"],
          "creditId": NSNull(), "createdAt": day(-8), "updatedAt": day(-8),
        ]),
        rec([
          "id": "p-pay-2", "companyId": c, "direction": "in", "clientId": "p-cl-3", "number": "PAY-0052",
          "date": day(-5), "amount": 2400, "currency": "KWD", "method": "knet", "reference": "",
          "notes": "", "allocations": [["documentId": "p-inv-3", "amount": 2400]], "documentIds": ["p-inv-3"],
          "creditId": NSNull(), "createdAt": day(-5), "updatedAt": day(-5),
        ]),
        rec([
          "id": "p-pay-3", "companyId": c, "direction": "out", "clientId": "p-vn-2", "number": "PM-0020",
          "date": day(-6), "amount": 1210, "currency": "KWD", "method": "cheque", "reference": "CHQ 100482",
          "notes": "", "allocations": [["documentId": "p-bl-2", "amount": 1210]], "documentIds": ["p-bl-2"],
          "creditId": NSNull(), "createdAt": day(-6), "updatedAt": day(-6),
        ]),
      ]
      return ["companies": [companyRecord], "clients": clients, "documents": documents, "payments": payments]
    }

    static func contact(
      _ id: String, _ company: String, _ number: String, _ name: String, _ nameAr: String?,
      customer: Bool = false, vendor: Bool = false
    ) -> JSONValue {
      var fields: [String: Any] = [
        "id": id, "companyId": company, "number": number, "name": name, "contacts": [],
        "email": "\(number.lowercased())@example.com", "phone": "+965 5000 0000", "website": "", "taxId": "",
        "address": ["line1": "Block 3, Street 12", "city": "Kuwait City", "country": "KW"],
        "shippingAddress": NSNull(), "currency": NSNull(), "paymentTermsDays": 30, "language": NSNull(),
        "taxExempt": false, "isCustomer": customer, "isVendor": vendor, "notes": "", "archived": false,
        "createdAt": day(-90), "updatedAt": day(-10),
      ]
      if let nameAr { fields["nameAr"] = nameAr }
      return rec(fields)
    }

    static func doc(
      _ id: String, _ company: String, _ type: String, _ number: String, _ status: String, _ client: String,
      _ issued: String, _ due: String?, total: Double, paid: Double
    ) -> JSONValue {
      let subtotal = total
      let items: [[String: Any]] = [
        [
          "id": "\(id)-l1", "kind": "item", "productId": NSNull(), "name": "Consulting hours",
          "description": "Monthly support", "quantity": 4, "unit": "hr", "unitPrice": subtotal * 0.6 / 4,
          "discount": 0, "discountType": "percent", "taxes": [],
        ],
        [
          "id": "\(id)-l2", "kind": "item", "productId": NSNull(), "name": "Printed catalogues",
          "description": "", "quantity": 10, "unit": "pcs", "unitPrice": subtotal * 0.4 / 10,
          "discount": 0, "discountType": "percent", "taxes": [],
        ],
      ]
      var fields: [String: Any] = [
        "id": id, "companyId": company, "type": type, "number": number, "status": status, "clientId": client,
        "issueDate": issued, "dueDate": due ?? NSNull(), "poNumber": "", "currency": "KWD", "items": items,
        "discount": 0, "discountType": "percent", "taxes": [], "charges": [], "pricesIncludeTax": false,
        "deposit": 0, "depositDueDate": NSNull(), "notes": "Thank you for your business.", "terms": "",
        "footer": "", "privateNotes": "", "templateId": NSNull(),
        "totals": [
          "subtotal": subtotal, "discount": 0, "taxTotal": 0, "total": total, "paid": paid,
          "balance": total - paid,
        ],
        "sentAt": status == "draft" ? NSNull() : "\(issued)T09:30:00.000Z", "paidAt": NSNull(),
        "sourceId": NSNull(), "convertedToId": NSNull(), "recurringId": NSNull(), "archived": false,
        "createdAt": "\(issued)T09:00:00.000Z", "updatedAt": "\(issued)T09:00:00.000Z",
      ]
      if type == "sales_order" { fields["deliveryStatus"] = "not_delivered" }
      return rec(fields)
    }
  }
#endif
