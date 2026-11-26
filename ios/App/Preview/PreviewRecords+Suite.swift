#if DEBUG
  // Preview mode's made-up records for CRM, Compliance and the suite's own
  // pages (files, approvals, updates). Every name, number and amount here
  // is invented; nothing is real.

  import Foundation
  import MahamKit

  extension PreviewRecords {
    static func suiteArea(company: Company) -> [String: [JSONValue]] {
      let c = company.id
      return [
        "clients": [
          contact("p-su-cl-1", c, "CL-004", "Palm Grove Studio", "استوديو بستان النخيل", customer: true),
          contact("p-su-cl-2", c, "CL-005", "Coral Bay Fitness", nil, customer: true),
        ],
        "documents": [
          doc("p-su-qt-1", c, "quote", "QT-0043", "sent", "p-su-cl-1", day(-12), day(-2), total: 1850, paid: 0),
          doc("p-su-qt-2", c, "quote", "QT-0040", "declined", "p-cl-1", day(-30), day(-10), total: 640, paid: 0),
          doc("p-su-qt-3", c, "quote", "QT-0044", "draft", "p-su-cl-2", day(-1), day(29), total: 2275, paid: 0),
        ],
        "complianceDocuments": [
          suPaper(
            "p-su-cd-1", c, type: "commercial_licence", title: "", number: "CL/2024/55821", issuer: "Licensing office",
            issued: day(-345), expires: day(20), cost: 150),
          suPaper(
            "p-su-cd-2", c, type: "lease_contract", title: "Office lease, Block 3", number: "LS-118",
            issuer: "Sunrise Properties", issued: day(-300), expires: day(65), cost: 4800),
          suPaper(
            "p-su-cd-3", c, type: "fire_licence", title: "", number: "FD-90417", issuer: "Fire safety office",
            issued: day(-372), expires: day(-7), cost: 35),
          suPaper(
            "p-su-cd-4", c, type: "vehicle_registration", title: "", number: "REG-551203", issuer: "Vehicle registry",
            issued: day(-330), expires: day(5), cost: 10, owner: "vehicle", ownerName: "18/62417",
            vehicleId: "p-su-vh-1"),
          suPaper(
            "p-su-cd-5", c, type: "vehicle_insurance", title: "", number: "INS-7783", issuer: "Gulf Shield Insurance",
            issued: day(-200), expires: day(165), cost: 220, owner: "vehicle", ownerName: "18/62417",
            vehicleId: "p-su-vh-1"),
          suPaper(
            "p-su-cd-6", c, type: "client_contract", title: "Cleaning services contract", number: "CC-2026-04",
            issuer: "", issued: day(-120), expires: day(245), cost: 0, owner: "other", ownerName: "Blue Harbour Cafe",
            clientId: "p-cl-1"),
        ],
        "vehicles": [
          PreviewRecords.rec([
            "id": "p-su-vh-1", "companyId": c, "plate": "18/62417", "make": "Toyota", "model": "Hilux", "year": 2022,
            "chassisNumber": "JTFAB00000000001", "assetId": NSNull(), "driverEmployeeId": NSNull(),
            "notes": "", "archived": false, "createdAt": day(-330), "updatedAt": day(-30),
          ])
        ],
        "approvals": [
          PreviewRecords.rec([
            "id": "p-su-ap-1", "companyId": c, "kind": "invoice_edit", "subjectTbl": "documents",
            "subjectId": "p-inv-1", "subjectNumber": "INV-0107",
            "before": ["dueDate": day(-5), "notes": "Thank you for your business."],
            "after": ["dueDate": day(10), "notes": "Thank you for your business. Second instalment agreed."],
            "reason": "The customer asked for two more weeks to pay.", "status": "pending",
            "requestedBy": "p-su-user-2", "requestedByName": "Mariam Haddad",
            "requestedAt": "\(day(-1))T08:15:00.000Z", "decidedBy": NSNull(), "decidedAt": NSNull(),
            "decisionNote": "", "createdAt": "\(day(-1))T08:15:00.000Z", "updatedAt": "\(day(-1))T08:15:00.000Z",
          ]),
          PreviewRecords.rec([
            "id": "p-su-ap-2", "companyId": c, "kind": "invoice_void", "subjectTbl": "documents",
            "subjectId": "p-inv-2", "subjectNumber": "INV-0108", "before": NSNull(), "after": ["status": "void"],
            "reason": "Issued twice by mistake.", "status": "rejected", "requestedBy": "p-su-user-3",
            "requestedByName": "Yousef Darwish", "requestedAt": "\(day(-6))T10:40:00.000Z",
            "decidedBy": "p-su-user-1", "decidedAt": "\(day(-5))T07:05:00.000Z",
            "decisionNote": "A payment is already recorded on it.", "createdAt": "\(day(-6))T10:40:00.000Z",
            "updatedAt": "\(day(-5))T07:05:00.000Z",
          ]),
        ],
        "activities": [
          suActivity(
            "p-su-ac-1", c, at: "\(day(0))T06:20:00.000Z", entity: "invoice", entityId: "p-inv-4", documentId: "p-inv-4",
            key: "Invoice {number} created", vars: ["number": "INV-0110"], by: "p-su-user-2", name: "Mariam Haddad"),
          suActivity(
            "p-su-ac-2", c, at: "\(day(0))T05:05:00.000Z", entity: "client", entityId: "p-su-cl-2", documentId: nil,
            key: "Client {name} added", vars: ["name": "Coral Bay Fitness"], by: "p-su-user-3", name: "Yousef Darwish"),
          suActivity(
            "p-su-ac-3", c, at: "\(day(-1))T08:15:00.000Z", entity: "approval", entityId: "p-su-ap-1",
            documentId: "p-inv-1", key: "Approval asked for on {number}", vars: ["number": "INV-0107"],
            by: "p-su-user-2", name: "Mariam Haddad"),
          suActivity(
            "p-su-ac-4", c, at: "\(day(-3))T11:30:00.000Z", entity: "compliance", entityId: "p-su-cd-2",
            documentId: nil, key: "Document {title} added", vars: ["title": "Office lease, Block 3"],
            by: "p-su-user-3", name: "Yousef Darwish"),
        ],
        "attachments": [
          suFile("p-su-at-1", c, owner: "p-inv-1", name: "INV-0107 signed.pdf", size: 184_320, at: day(-19)),
          suFile("p-su-at-2", c, owner: "p-bl-1", name: "Gulf Paper bill scan.jpg", size: 942_080, at: day(-17)),
          suFile("p-su-at-3", c, owner: "p-su-cd-1", name: "Commercial licence 2025.pdf", size: 1_548_288, at: day(-340)),
          suFile("p-su-at-4", c, owner: "p-su-cd-4", name: "Registration card.png", size: 402_432, at: day(-329)),
          suFile("p-su-at-5", c, owner: "p-pay-1", name: "Transfer receipt.pdf", size: 96_256, at: day(-8)),
        ],
      ]
    }

    /// A paper of the register.
    static func suPaper(
      _ id: String, _ company: String, type: String, title: String, number: String, issuer: String, issued: String,
      expires: String, cost: Double, owner: String = "company", ownerName: String = "", vehicleId: String? = nil,
      clientId: String? = nil
    ) -> JSONValue {
      rec([
        "id": id, "companyId": company, "type": type, "title": title, "number": number, "issuer": issuer,
        "issueDate": issued, "expiryDate": expires, "renewalCost": cost, "reminderDays": NSNull(),
        "ownerType": owner, "employeeId": NSNull(), "ownerName": ownerName, "notes": "", "archived": false,
        "vehicleId": vehicleId ?? NSNull(), "clientId": clientId ?? NSNull(), "purposeId": NSNull(),
        "createdAt": "\(issued)T09:00:00.000Z", "updatedAt": "\(issued)T09:00:00.000Z",
      ])
    }

    /// A line of the activity log, as a team member's device writes it.
    static func suActivity(
      _ id: String, _ company: String, at: String, entity: String, entityId: String, documentId: String?,
      key: String, vars: [String: String], by: String, name: String
    ) -> JSONValue {
      var message = key
      for (field, value) in vars { message = message.replacingOccurrences(of: "{\(field)}", with: value) }
      return rec([
        "id": id, "companyId": company, "at": at, "entity": entity, "entityId": entityId,
        "clientId": NSNull(), "documentId": documentId ?? NSNull(), "action": "change", "message": message,
        "messageKey": key, "messageVars": vars, "by": by, "byName": name,
      ])
    }

    /// A file kept with a record; its content is in the cloud.
    static func suFile(_ id: String, _ company: String, owner: String, name: String, size: Int, at: String) -> JSONValue {
      let type = name.hasSuffix(".pdf") ? "application/pdf" : name.hasSuffix(".png") ? "image/png" : "image/jpeg"
      return rec([
        "id": id, "companyId": company, "ownerId": owner, "name": name, "type": type, "size": size, "dataUrl": "",
        "storagePath": "\(company)/\(id)", "contentMissing": 1, "createdAt": "\(at)T09:00:00.000Z",
      ])
    }
  }
#endif
