import Foundation

/// The kinds of record (the web's table names) this app may save. A kind
/// is listed here only once the ports of the web's write functions that
/// change it (MahamKit/Write) pass their parity tests against the web's own
/// outputs: a record saved on the iPhone must be what the web would have
/// saved, or the web's devices rewrite it. Until a kind is here, the pages
/// that would change it keep their New and Edit buttons hidden (each
/// action checks every table it writes).
enum OneWritable {
  static let kinds: Set<String> = [
    // Shared by every area's actions.
    "activities", "companies", "accounts",
    // Sales and purchases (Write/Documents): documents, contacts, credit
    // hold, approval requests for documents; voids and deletes free their
    // payments and files.
    "documents", "clients", "approvals", "payments", "attachments",
    // Items and inventory (Write/Inventory); documents with stock items
    // write stock movements too.
    "products", "warehouses", "stockMovements", "stockEntries", "landedCosts", "stockIssues",
    // Accounting (Write/Accounting).
    "journals", "assets", "depreciationRuns", "yearEnds", "bankTransactions", "vatReturns",
    // Compliance and settings (Write/Suite).
    "complianceDocuments", "renewals", "complianceMarks", "vehicles", "taxRates",
  ]
}
