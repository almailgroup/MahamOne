import MahamKit
import Observation
import SwiftUI

/// The Maham One department: the company you're looking at and what it holds
/// for your role. Read-only in this version (see OneRepository).
@MainActor
@Observable
final class BusinessStore {
  private(set) var companies: [Company] = []
  private(set) var profile: CompanyProfile?
  private(set) var invoices: [SalesDocument] = []
  private(set) var clients: [Client] = []
  private(set) var employees: [Employee] = []
  private(set) var documents: [ComplianceDocument] = []
  private(set) var updates: [ChangeEvent] = []
  private(set) var isLoading = false
  private(set) var loadedOnce = false

  var onError: (@MainActor (Error) -> Void)?

  /// The company on screen, remembered on this iPhone.
  var selectedCompanyId: String? {
    didSet {
      guard oldValue != selectedCompanyId else { return }
      UserDefaults.standard.set(selectedCompanyId, forKey: "selectedCompanyId")
      clearCompany()
      loadCache()
      Task { await refreshCompany() }
    }
  }

  private let services: AppServices?

  init(services: AppServices?) {
    self.services = services
    selectedCompanyId = UserDefaults.standard.string(forKey: "selectedCompanyId")
    if let companies = services?.cache.load([Company].self, as: "companies") {
      self.companies = companies
    }
    loadCache()
  }

  // MARK: What screens read

  var company: Company? {
    companies.first { $0.id == selectedCompanyId } ?? companies.first
  }

  var role: MemberRole { company?.role ?? .viewer }
  var currency: String { profile?.currency ?? "KWD" }
  var today: LocalDate { LocalDate(Date()) }

  /// Every expiry this role may see: employees' papers only for those who
  /// see people (the database hides them anyway; this is the second lock).
  var expiries: [Expiry] {
    if role.seesPeople { return MahamKit.expiries(documents: documents, employees: employees) }
    let register = documents.filter { ($0.employeeId ?? "").isEmpty }
    return MahamKit.expiries(documents: register, employees: [])
  }

  var summary: BusinessSummary {
    BusinessSummary(invoices: invoices, expiries: expiries, currency: currency, today: today)
  }

  func client(_ id: String?) -> Client? {
    guard let id else { return nil }
    return clients.first { $0.id == id }
  }

  func invoice(_ id: String) -> SalesDocument? {
    invoices.first { $0.id == id }
  }

  func invoices(for clientId: String) -> [SalesDocument] {
    invoices.filter { $0.clientId == clientId }
  }

  func format(_ amount: Double) -> String {
    Money.format(amount, currency: currency)
  }

  /// The same invoice in Maham One on the web.
  func webURL(invoice: SalesDocument) -> URL? {
    services.map { URL(string: "#/invoices/\(invoice.id)", relativeTo: $0.config.webURL)! }
  }

  func webURL(client: Client) -> URL? {
    services.map { URL(string: "#/clients/\(client.id)", relativeTo: $0.config.webURL)! }
  }

  // MARK: Loading

  func refresh() async {
    guard let one = services?.one else { return }
    do {
      companies = try await one.companies()
      services?.cache.save(companies, as: "companies")
      if companies.isEmpty {
        clearCompany()
        loadedOnce = true
        return
      }
      if company == nil || !companies.contains(where: { $0.id == selectedCompanyId }) {
        if let first = companies.first {
          selectedCompanyId = first.id
          return  // didSet loads it
        }
      }
      await refreshCompany()
    } catch MahamError.offline {
    } catch {
      onError?(error)
    }
  }

  func select(_ company: Company) {
    selectedCompanyId = company.id
  }

  func refreshCompany() async {
    guard let one = services?.one, let id = company?.id else { return }
    isLoading = true
    defer {
      isLoading = false
      loadedOnce = true
    }
    do {
      async let profile = one.profile(company: id)
      async let invoices = one.invoices(company: id)
      async let clients = one.clients(company: id)
      async let employees = one.employees(company: id)
      async let documents = one.complianceDocuments(company: id)
      async let updates = one.updates(company: id)
      (self.profile, self.invoices, self.clients, self.employees, self.documents, self.updates) =
        try await (profile, invoices, clients, employees, documents, updates)
      saveCache()
      SystemSync.businessChanged(clients: self.clients, invoices: self.invoices, expiries: expiries)
    } catch MahamError.offline {
    } catch {
      onError?(error)
    }
  }

  func reset() {
    companies = []
    clearCompany()
    loadedOnce = false
  }

  private func clearCompany() {
    profile = nil
    invoices = []
    clients = []
    employees = []
    documents = []
    updates = []
  }

  // MARK: Keeping the copy

  private struct Cached: Codable {
    var invoices: [SalesDocument]
    var clients: [Client]
    var employees: [Employee]
    var documents: [ComplianceDocument]
  }

  private var cacheKey: String? { company.map { "company-\($0.id)" } }

  private func saveCache() {
    guard let cacheKey else { return }
    services?.cache.save(
      Cached(invoices: invoices, clients: clients, employees: employees, documents: documents),
      as: cacheKey)
  }

  private func loadCache() {
    guard let cacheKey, let cached = services?.cache.load(Cached.self, as: cacheKey) else { return }
    invoices = cached.invoices
    clients = cached.clients
    employees = cached.employees
    documents = cached.documents
  }
}
