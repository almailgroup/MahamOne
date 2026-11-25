import Foundation

/// Maham One's data, read as the signed-in person (`public.records` and its
/// functions). Read-only in this version of the app: Maham One's records
/// carry the books, and changing them is the website's job, with all of its
/// accounting. The database's rules decide what each role sees, so staff and
/// viewers simply get no employees.
public struct OneRepository: Sendable {
  public let db: DatabaseClient

  public init(db: DatabaseClient) {
    self.db = db
  }

  public func companies() async throws -> [Company] {
    try await db.rpc("my_companies", schema: .maham, NoParams())
  }

  /// Every record of one kind in a company, newest version of each.
  public func records<Value: Decodable & Sendable>(
    _ table: String, company: String, _ filters: [Query] = []
  ) async throws -> [Value] {
    let rows: [RecordRow<Value>] = try await db.selectAll(
      "records", schema: .maham,
      [.select("id,rev,data"), .eq("company_id", company), .eq("tbl", table)] + filters)
    return rows.map(\.data)
  }

  public func profile(company: String) async throws -> CompanyProfile? {
    let rows: [RecordRow<CompanyProfile>] = try await db.select(
      "records", schema: .maham,
      [.select("id,rev,data"), .eq("company_id", company), .eq("tbl", "companies"), .eq("id", company)])
    return rows.first?.data
  }

  /// Invoices, newest first.
  public func invoices(company: String) async throws -> [SalesDocument] {
    let all: [SalesDocument] = try await records(
      "documents", company: company, [Query("data->>type", "eq.invoice")])
    return all.sorted { ($0.issueDate ?? LocalDate(year: 1970, month: 1, day: 1)) > ($1.issueDate ?? LocalDate(year: 1970, month: 1, day: 1)) }
  }

  public func clients(company: String) async throws -> [Client] {
    let all: [Client] = try await records("clients", company: company)
    return all.filter { !$0.archived }.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  /// Employees, for the roles that may see them; an empty list otherwise.
  public func employees(company: String) async throws -> [Employee] {
    let all: [Employee] = try await records("employees", company: company)
    return all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  public func complianceDocuments(company: String) async throws -> [ComplianceDocument] {
    let all: [ComplianceDocument] = try await records("complianceDocuments", company: company)
    return all.filter { !$0.archived }
  }

  /// The team's changes, for the owner and approvers; nothing for others.
  public func updates(company: String, limit: Int = 50) async throws -> [ChangeEvent] {
    struct Params: Encodable {
      let p_company: String
      let p_after: Int
      let p_limit: Int
    }
    do {
      return try await db.rpc(
        "notification_feed", schema: .maham, Params(p_company: company, p_after: 0, p_limit: limit))
    } catch MahamError.permission {
      return []
    }
  }
}

/// What the Maham One department's home shows, worked out from the records.
public struct BusinessSummary: Sendable, Equatable {
  public var currency: String
  public var openInvoices: Int
  public var receivable: Double
  public var overdueInvoices: Int
  public var overdueAmount: Double
  public var invoicedThisMonth: Double
  public var expiringSoon: [Expiry]

  public init(
    invoices: [SalesDocument], expiries: [Expiry], currency: String, today: LocalDate,
    window: Int = 30
  ) {
    self.currency = currency
    let open = invoices.filter(\.isOpen)
    openInvoices = open.count
    receivable = open.reduce(0) { $0 + $1.totals.balance }
    let overdue = open.filter { $0.isOverdue(today: today) }
    overdueInvoices = overdue.count
    overdueAmount = overdue.reduce(0) { $0 + $1.totals.balance }
    invoicedThisMonth = invoices
      .filter { doc in
        guard let issued = doc.issueDate, doc.status != .draft, doc.status != .void else { return false }
        return issued.year == today.year && issued.month == today.month
      }
      .reduce(0) { $0 + $1.totals.total }
    expiringSoon = expiries
      .filter { $0.daysLeft(today: today) <= window }
      .sorted { $0.date < $1.date }
  }
}

/// Every expiry the role may see: the register's documents and, for those who
/// see people, employees' papers.
public func expiries(documents: [ComplianceDocument], employees: [Employee]) -> [Expiry] {
  let register = documents.compactMap { doc -> Expiry? in
    guard let date = doc.expiryDate else { return nil }
    return Expiry(id: doc.id, title: doc.title.isEmpty ? doc.type : doc.title, owner: doc.ownerName, date: date)
  }
  let papers = employees.filter(\.isActive).flatMap(\.expiries)
  return (register + papers).sorted { $0.date < $1.date }
}

// `Money`, with the `fractionDigits` and `format` these screens use, is in
// Foundation/Money.swift, the port of the web's money.ts.
