#if DEBUG
  // Preview mode's made-up records for the contact, payment, recurring,
  // cheque and expense pages (App/One/Contacts). They add to the sales
  // records (`PreviewRecords.sales`: clients p-cl-1…3, vendors p-vn-1…2, their
  // documents and three payments). Every name, number and amount here is
  // invented; nothing is real.

  import Foundation
  import MahamKit

  extension PreviewRecords {
    static func contactsArea(company: Company) -> [String: [JSONValue]] {
      let c = company.id
      return [
        "clients": [contactsAreaContact(c)],
        "documents": contactsAreaDocuments(c),
        "payments": contactsAreaPayments(c),
        "recurring": contactsAreaRecurring(c),
        "securityCheques": contactsAreaSecurityCheques(c),
        "expenses": contactsAreaExpenses(c),
        "accounts": contactsAreaAccounts(c),
        "attachments": contactsAreaAttachments(c),
        "chequeLayouts": contactsAreaChequeLayouts(c),
      ]
    }

    /// A timestamp on day `offset`, as the web stores them.
    private static func ctStamp(_ offset: Int, _ time: String = "09:00:00") -> String {
      "\(day(offset))T\(time).000Z"
    }

    // MARK: Contacts

    /// A contractor that is both a client and a vendor, with a credit limit,
    /// a tax retention, an expired clearance certificate and two people.
    private static func contactsAreaContact(_ c: String) -> JSONValue {
      rec([
        "id": "p-ct-cl-4", "companyId": c, "number": "CL-004", "name": "Coral Bay Contracting",
        "nameAr": "شركة خليج المرجان للمقاولات",
        "contacts": [
          [
            "id": "p-ct-person-1", "name": "Huda Saleh", "email": "huda@example.com", "phone": "+965 5000 0101",
            "primary": true,
          ],
          ["id": "p-ct-person-2", "name": "Omar Fares", "email": "omar@example.com", "phone": "", "primary": false],
        ],
        "email": "accounts@example.com", "phone": "+965 2200 0101", "website": "", "taxId": "TC-448812",
        "civilId": "",
        "address": [
          "line1": "", "line2": "", "city": "Salmiya", "state": "Hawalli", "postalCode": "22001", "country": "KW",
          "block": "4", "street": "18", "building": "7", "floor": "2",
        ],
        "shippingAddress": NSNull(), "currency": NSNull(), "paymentTermsDays": 45, "language": NSNull(),
        "taxExempt": false, "isCustomer": true, "isVendor": true, "notes": "Prefers cheques dated at month end.",
        "creditLimit": 5000, "creditHold": false, "retentionPercent": 5, "retentionKind": "tax",
        "clearanceCertificates": [
          ["id": "p-ct-cert-1", "number": "CC-2026-118", "issueDate": day(-200), "expiryDate": day(-20), "notes": ""]
        ],
        "archived": false, "createdAt": ctStamp(-120), "updatedAt": ctStamp(-3),
      ])
    }

    // MARK: Documents

    private static func contactsAreaDocuments(_ c: String) -> [JSONValue] {
      // An invoice with 5% held back, part paid; a bill from the same contact.
      var retained = doc(
        "p-ct-inv-1", c, "invoice", "INV-0104", "partial", "p-ct-cl-4", day(-40), day(-10), total: 1250, paid: 500)
      retained.set(
        "totals",
        rec([
          "subtotal": 1250, "discount": 0, "taxTotal": 0, "total": 1250, "paid": 500, "retention": 62.5,
          "balance": 687.5,
        ]))
      retained.set("retentionPercent", .number(5))
      retained.set("retentionKind", .string("tax"))
      let bill = doc("p-ct-bl-1", c, "bill", "BL-0036", "sent", "p-ct-cl-4", day(-5), day(25), total: 300, paid: 0)
      // Invoices made from the monthly retainer.
      var first = doc(
        "p-ct-inv-2", c, "invoice", "INV-0099", "paid", "p-cl-1", day(-56), day(-26), total: 350, paid: 350)
      first.set("recurringId", .string("p-ct-rec-1"))
      var second = doc(
        "p-ct-inv-3", c, "invoice", "INV-0103", "paid", "p-cl-1", day(-26), day(4), total: 350, paid: 350)
      second.set("recurringId", .string("p-ct-rec-1"))
      return [retained, bill, first, second]
    }

    // MARK: Payments

    private static func contactsAreaPayments(_ c: String) -> [JSONValue] {
      [
        // A post-dated cheque in hand.
        ctPayment(
          "p-ct-pay-1", c, "in", "p-cl-2", "PAY-0053", day(-2), 460.5, method: "cheque",
          cheque: [
            "number": "204417", "bank": "NBOK", "date": day(9), "drawer": "Sandline Interiors", "status": "held",
          ]),
        // A replacement cheque, deposited.
        ctPayment(
          "p-ct-pay-2", c, "in", "p-cl-1", "PAY-0055", day(-1), 600, method: "cheque",
          cheque: [
            "number": "551203", "bank": "KFHO", "date": day(-1), "drawer": "Blue Harbour Cafe",
            "status": "deposited", "depositedOn": day(0), "replacesId": "p-ct-pay-3",
          ]),
        // The cheque it replaced, returned unpaid.
        ctPayment(
          "p-ct-pay-3", c, "in", "p-cl-1", "PAY-0054", day(-12), 600, method: "cheque",
          cheque: [
            "number": "551188", "bank": "KFHO", "date": day(-8), "drawer": "Blue Harbour Cafe",
            "status": "returned", "depositedOn": day(-7), "returnedOn": day(-4), "returnReason": "Insufficient funds",
            "replacedById": "p-ct-pay-2",
          ],
          extra: ["voided": true, "voidReason": "Cheque returned: insufficient funds", "voidedOn": day(-4)]),
        // Cash kept as client credit.
        ctPayment("p-ct-pay-4", c, "in", "p-cl-3", "PAY-0056", day(-3), 150, method: "cash", reference: "Front desk"),
        // KNET with the provider's fee, part of the retained invoice.
        ctPayment(
          "p-ct-pay-5", c, "in", "p-ct-cl-4", "PAY-0050", day(-15), 500, method: "knet", reference: "KN-77120",
          allocations: [["documentId": "p-ct-inv-1", "amount": 500]], extra: ["fee": 2.5]),
        // Retainer invoices paid by transfer.
        ctPayment(
          "p-ct-pay-6", c, "in", "p-cl-1", "PAY-0047", day(-50), 350, method: "bank_transfer", reference: "TRX-4410",
          allocations: [["documentId": "p-ct-inv-2", "amount": 350]]),
        ctPayment(
          "p-ct-pay-7", c, "in", "p-cl-1", "PAY-0052", day(-20), 350, method: "bank_transfer", reference: "TRX-4502",
          allocations: [["documentId": "p-ct-inv-3", "amount": 350]]),
        // Paid out: a transfer, and an advance by a cheque that is past its date.
        ctPayment(
          "p-ct-pay-8", c, "out", "p-vn-1", "PM-0021", day(-4), 120, method: "bank_transfer", reference: "OUT-2231"),
        ctPayment(
          "p-ct-pay-9", c, "out", "p-vn-1", "PM-0022", day(-9), 250, method: "cheque",
          cheque: [
            "number": "000318", "bank": "BRGN", "date": day(-3), "drawer": "Gulf Paper Supplies", "status": "held",
          ]),
      ]
    }

    private static func ctPayment(
      _ id: String, _ company: String, _ direction: String, _ client: String, _ number: String, _ date: String,
      _ amount: Double, method: String, reference: String = "", cheque: [String: Any]? = nil,
      allocations: [[String: Any]] = [], extra: [String: Any] = [:]
    ) -> JSONValue {
      var fields: [String: Any] = [
        "id": id, "companyId": company, "direction": direction, "clientId": client, "number": number, "date": date,
        "amount": amount, "currency": "KWD", "method": method, "reference": reference, "notes": "",
        "allocations": allocations, "documentIds": allocations.compactMap { $0["documentId"] },
        "creditId": NSNull(), "voided": false, "createdAt": "\(date)T10:00:00.000Z",
        "updatedAt": "\(date)T10:00:00.000Z",
      ]
      if var cheque {
        for key in ["depositedOn", "clearedOn", "returnedOn", "replacedById", "replacesId"] where cheque[key] == nil {
          cheque[key] = NSNull()
        }
        fields["cheque"] = cheque
      } else {
        fields["cheque"] = NSNull()
      }
      for (key, value) in extra { fields[key] = value }
      return rec(fields)
    }

    // MARK: Recurring invoices

    private static func contactsAreaRecurring(_ c: String) -> [JSONValue] {
      [
        ctRecurring(
          "p-ct-rec-1", c, "Monthly support retainer", "p-cl-1", "monthly", start: day(-56), next: day(4),
          remaining: nil, status: "active", issued: 2, item: "Monthly support", price: 350),
        ctRecurring(
          "p-ct-rec-2", c, "Clinic equipment maintenance", "p-cl-3", "quarterly", start: day(-100), next: day(-10),
          remaining: 3, status: "paused", issued: 1, item: "Quarterly maintenance visit", price: 820),
        ctRecurring(
          "p-ct-rec-3", c, "", "p-cl-2", "monthly", start: day(-150), next: nil, remaining: 0, status: "completed",
          issued: 4, item: "Showroom catalogue printing", price: 210),
      ]
    }

    private static func ctRecurring(
      _ id: String, _ company: String, _ name: String, _ client: String, _ frequency: String, start: String,
      next: String?, remaining: Int?, status: String, issued: Int, item: String, price: Double
    ) -> JSONValue {
      let template: [String: Any] = [
        "currency": "KWD",
        "items": [
          [
            "id": "\(id)-l1", "kind": "item", "productId": NSNull(), "name": item,
            "description": "For the month of {month} {year}", "quantity": 1, "unit": "month", "unitPrice": price,
            "discount": 0, "discountType": "percent", "taxes": [],
          ]
        ],
        "discount": 0, "discountType": "percent", "taxes": [], "charges": [], "pricesIncludeTax": false,
        "poNumber": "", "notes": "Thank you for your business.", "terms": "Payment within 30 days.", "footer": "",
        "privateNotes": "", "templateId": NSNull(),
      ]
      return rec([
        "id": id, "companyId": company, "clientId": client, "name": name, "frequency": frequency, "startDate": start,
        "nextIssueDate": next ?? NSNull(), "remainingCycles": remaining.map { $0 as Any } ?? NSNull(), "dueDays": 30,
        "markSent": true, "status": status, "template": template, "issuedCount": issued,
        "lastIssuedAt": issued > 0 ? ctStamp(-26) : NSNull(), "archived": false, "createdAt": ctStamp(-160),
        "updatedAt": ctStamp(-26),
      ])
    }

    // MARK: Security cheques

    private static func contactsAreaSecurityCheques(_ c: String) -> [JSONValue] {
      [
        ctSecurity(
          "p-ct-sec-1", c, "in", "p-cl-2", "880142", "GULB", day(-60), 1200, "Sandline Interiors",
          purpose: "Showroom rent deposit", status: "held"),
        ctSecurity(
          "p-ct-sec-2", c, "out", "p-vn-2", "000301", "BRGN", nil, 2500, "Desert Logistics",
          purpose: "Performance guarantee", status: "held"),
        ctSecurity(
          "p-ct-sec-3", c, "in", "p-cl-3", "771930", "BBYN", day(-140), 800, "Northwind Clinic",
          purpose: "Equipment loan", status: "returned", returnedOn: day(-30)),
      ]
    }

    private static func ctSecurity(
      _ id: String, _ company: String, _ direction: String, _ client: String, _ number: String, _ bank: String,
      _ date: String?, _ amount: Double, _ drawer: String, purpose: String, status: String, returnedOn: String? = nil
    ) -> JSONValue {
      rec([
        "id": id, "companyId": company, "direction": direction, "clientId": client, "number": number, "bank": bank,
        "date": date ?? NSNull(), "amount": amount, "currency": "KWD", "drawer": drawer, "purpose": purpose,
        "notes": "", "status": status, "returnedOn": returnedOn ?? NSNull(), "cashedOn": NSNull(),
        "paymentId": NSNull(), "createdAt": ctStamp(-60), "updatedAt": ctStamp(-30),
      ])
    }

    // MARK: Expenses and accounts

    private static func contactsAreaExpenses(_ c: String) -> [JSONValue] {
      [
        ctExpense(
          "p-ct-exp-1", c, "EXP-0031", day(-2), "p-ct-acc-fuel", 18.75, "Fuel for the delivery van",
          payee: "City Fuel Station", reference: "R-55120"),
        ctExpense(
          "p-ct-exp-2", c, "EXP-0030", day(-6), "p-ct-acc-office", 42.5, "Printer paper and toner",
          vendor: "p-vn-1", reference: "GP-9931"),
        ctExpense(
          "p-ct-exp-3", c, "EXP-0029", day(-11), "p-ct-acc-soft", 49, "Design software, monthly plan",
          payee: "Online subscription", currency: "USD", rate: 0.307),
        ctExpense(
          "p-ct-exp-4", c, "EXP-0028", day(-18), "p-ct-acc-fuel", 6.5, "Taxi to a client meeting",
          paidFrom: "p-ct-acc-cash"),
        ctExpense(
          "p-ct-exp-5", c, "EXP-0027", day(-25), "p-ct-acc-office", 120, "Same-day courier, showroom samples",
          vendor: "p-vn-2"),
      ]
    }

    private static func ctExpense(
      _ id: String, _ company: String, _ number: String, _ date: String, _ category: String, _ amount: Double,
      _ description: String, vendor: String? = nil, payee: String = "", reference: String = "",
      currency: String = "KWD", rate: Double? = nil, paidFrom: String? = nil
    ) -> JSONValue {
      var fields: [String: Any] = [
        "id": id, "companyId": company, "number": number, "date": date, "vendorId": vendor ?? NSNull(),
        "payee": payee, "accountId": category, "description": description, "amount": amount, "taxes": [],
        "currency": currency, "paidFromAccountId": paidFrom ?? NSNull(), "reference": reference, "notes": "",
        "createdAt": "\(date)T12:00:00.000Z", "updatedAt": "\(date)T12:00:00.000Z",
      ]
      if let rate { fields["exchangeRate"] = rate }
      return rec(fields)
    }

    private static func contactsAreaAccounts(_ c: String) -> [JSONValue] {
      [
        ctAccount("p-ct-acc-cash", c, "1000", "Cash", "النقد", type: "asset_cash", role: "cash"),
        ctAccount("p-ct-acc-bank", c, "1010", "Bank", "البنك", type: "asset_cash", role: "bank"),
        ctAccount("p-ct-acc-fuel", c, "6110", "Fuel and transport", "الوقود والمواصلات", type: "expense", role: nil),
        ctAccount("p-ct-acc-office", c, "6120", "Office supplies", "اللوازم المكتبية", type: "expense", role: nil),
        ctAccount("p-ct-acc-soft", c, "6130", "Software subscriptions", "اشتراكات البرامج", type: "expense", role: nil),
      ]
    }

    private static func ctAccount(
      _ id: String, _ company: String, _ code: String, _ name: String, _ nameAr: String, type: String, role: String?
    ) -> JSONValue {
      rec([
        "id": id, "companyId": company, "code": code, "name": name, "nameAr": nameAr, "type": type,
        "description": "", "role": role ?? NSNull(), "bank": NSNull(), "archived": false, "createdAt": ctStamp(-300),
        "updatedAt": ctStamp(-300),
      ])
    }

    private static func contactsAreaAttachments(_ c: String) -> [JSONValue] {
      [
        rec([
          "id": "p-ct-att-1", "companyId": c, "ownerId": "p-ct-exp-1", "name": "fuel-receipt.jpg",
          "type": "image/jpeg", "size": 182_000, "dataUrl": "", "createdAt": ctStamp(-2),
        ]),
        rec([
          "id": "p-ct-att-2", "companyId": c, "ownerId": "p-ct-pay-1", "name": "cheque-204417.pdf",
          "type": "application/pdf", "size": 96_000, "dataUrl": "", "createdAt": ctStamp(-2),
        ]),
      ]
    }

    // MARK: Cheque layouts

    /// The company's own layout for a third bank, beside the built-in ones.
    private static func contactsAreaChequeLayouts(_ c: String) -> [JSONValue] {
      func box(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [String: Any] {
        ["x": x, "y": y, "width": width, "height": height]
      }
      return [
        rec([
          "id": "p-ct-lay-1", "companyId": c, "bank": "NBOK", "name": "National Bank of Kuwait",
          "nameAr": "بنك الكويت الوطني", "version": 2, "size": ["width": 176, "height": 81],
          "offset": ["x": 0.5, "y": -1],
          "fields": [
            "date": box(126, 9, 42, 7), "payee": box(22, 22, 114, 7), "wordsLine1": box(30, 31, 104, 7),
            "wordsLine2": box(8, 39, 128, 7), "figures": box(138, 31, 32, 8), "crossing": box(6, 4, 40, 9),
          ],
          "dateStyle": "slashes", "wordsLanguage": "ar", "figures": ["prefix": "KD", "guard": "**"],
          "calibrated": true, "archived": false, "createdAt": ctStamp(-40), "updatedAt": ctStamp(-12),
        ])
      ]
    }
  }
#endif
