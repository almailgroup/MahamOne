import Foundation

/// The kinds of record in `public.records`: its `tbl` values, named exactly
/// as on the server (`DATA_TABLES` in src/db/db.ts), in the web's order.
public enum RecordKind: String, CaseIterable, Codable, Hashable, Sendable {
  case companies
  case clients
  case products
  case taxRates
  case documents
  case payments
  case recurring
  case activities
  case accounts
  case journals
  case expenses
  case attachments
  case vatReturns
  case bankTransactions
  case employees
  case complianceDocuments
  case renewals
  case complianceMarks
  case peopleSettings
  case securityCheques
  case assets
  case depreciationRuns
  case yearEnds
  case payRuns
  case payrollSettings
  case leaveRecords
  case staffLoans
  case finalSettlements
  case warehouses
  case stockMovements
  case stockEntries
  case landedCosts
  case chequeLayouts
  case vehicles
  case approvals
  case letterTemplates
  case employeeLetters
  case staffingCostings
  case stockIssues

  /// Where records of this kind go in a push batch (`PUSH_ORDER` in
  /// src/cloud/sync.ts): owners before what refers to them, so the server
  /// can tell what is private. Lower goes first.
  public var pushOrder: Int {
    switch self {
    case .companies: 0
    case .employees: 1
    case .complianceDocuments, .renewals: 2
    // Before their stock movements: the cloud keeps those of an issue that
    // stands, so a void reaches it first.
    case .stockIssues: 4
    case .attachments: 8
    case .activities: 9
    default: 5
    }
  }

  /// The push order of a `tbl` value, known or not (5 for one this version
  /// doesn't know, as on the web).
  public static func pushOrder(of table: String) -> Int {
    RecordKind(rawValue: table)?.pushOrder ?? 5
  }
}
