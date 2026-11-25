import Foundation
import Testing

@testable import MahamKit

/// The record kinds (`DATA_TABLES` in src/db/db.ts) and their push order
/// (`PUSH_ORDER` in src/cloud/sync.ts).
@Suite("Record kinds")
struct RecordKindsTests {
  @Test("are the server's 39 tables, named and ordered as on the web")
  func tables() {
    let web = [
      "companies", "clients", "products", "taxRates", "documents", "payments", "recurring", "activities", "accounts",
      "journals", "expenses", "attachments", "vatReturns", "bankTransactions", "employees", "complianceDocuments",
      "renewals", "complianceMarks", "peopleSettings", "securityCheques", "assets", "depreciationRuns", "yearEnds",
      "payRuns", "payrollSettings", "leaveRecords", "staffLoans", "finalSettlements", "warehouses", "stockMovements",
      "stockEntries", "landedCosts", "chequeLayouts", "vehicles", "approvals", "letterTemplates", "employeeLetters",
      "staffingCostings", "stockIssues",
    ]
    #expect(RecordKind.allCases.map(\.rawValue) == web)
    #expect(RecordKind.allCases.count == 39)
  }

  @Test("push owners before what refers to them")
  func pushOrder() {
    #expect(RecordKind.companies.pushOrder == 0)
    #expect(RecordKind.employees.pushOrder == 1)
    #expect(RecordKind.complianceDocuments.pushOrder == 2)
    #expect(RecordKind.renewals.pushOrder == 2)
    #expect(RecordKind.stockIssues.pushOrder == 4)
    #expect(RecordKind.documents.pushOrder == 5)
    #expect(RecordKind.stockMovements.pushOrder == 5)
    #expect(RecordKind.attachments.pushOrder == 8)
    #expect(RecordKind.activities.pushOrder == 9)
    #expect(RecordKind.pushOrder(of: "later") == 5)
    #expect(RecordKind.pushOrder(of: "companies") == 0)
  }
}
