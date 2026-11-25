import Foundation

/// The sales documents that share one list, editor and page.
enum SalesDocumentKind: String, CaseIterable, Sendable {
  case invoice = "invoices"
  case quote = "quotes"
  case credit = "credits"
  case proforma = "proformas"
  case salesOrder = "sales-orders"
  case deliveryNote = "delivery-notes"

  var plural: String {
    switch self {
    case .invoice: "Invoices"
    case .quote: "Quotes"
    case .credit: "Credit notes"
    case .proforma: "Proforma invoices"
    case .salesOrder: "Sales orders"
    case .deliveryNote: "Delivery notes"
    }
  }

  var singular: String {
    switch self {
    case .invoice: "Invoice"
    case .quote: "Quote"
    case .credit: "Credit note"
    case .proforma: "Proforma invoice"
    case .salesOrder: "Sales order"
    case .deliveryNote: "Delivery note"
    }
  }

  var createAction: CreateAction {
    switch self {
    case .invoice: CreateActions.invoice
    case .quote: CreateActions.quote
    case .credit: CreateActions.credit
    case .proforma: CreateActions.proforma
    case .salesOrder: CreateActions.salesOrder
    case .deliveryNote: CreateActions.deliveryNote
    }
  }
}

/// Bills, vendor credits and purchase orders.
enum PurchaseDocumentKind: String, CaseIterable, Sendable {
  case bill = "bills"
  case vendorCredit = "vendor-credits"
  case purchaseOrder = "purchase-orders"

  var plural: String {
    switch self {
    case .bill: "Bills"
    case .vendorCredit: "Vendor credits"
    case .purchaseOrder: "Purchase orders"
    }
  }

  var singular: String {
    switch self {
    case .bill: "Bill"
    case .vendorCredit: "Vendor credit"
    case .purchaseOrder: "Purchase order"
    }
  }

  var createAction: CreateAction {
    switch self {
    case .bill: CreateActions.bill
    case .vendorCredit: CreateActions.vendorCredit
    case .purchaseOrder: CreateActions.purchaseOrder
    }
  }
}

/// Clients and vendors.
enum ContactKind: String, CaseIterable, Sendable {
  case customer = "clients"
  case vendor = "vendors"
}

/// Payments received and payments made.
enum PaymentDirection: String, CaseIterable, Sendable {
  case received = "payments"
  case made = "payments-made"
}

/// A page of Maham One, by its web address (`src/app/routes.tsx` and the
/// apps' `routes.tsx`). `Route(path:)` reads an address, `path` writes it.
enum Route: Hashable, Sendable {
  // The suite
  /// `/`
  case home
  /// `/files`
  case files
  /// `/approvals`
  case approvals
  /// `/notifications`
  case notifications
  /// `/settings`, `/settings/:section`
  case settings(section: String?)
  /// `/setup`
  case setup

  // Maham Books
  /// `/books`
  case booksDashboard
  /// `/invoices`, `/quotes`, `/credits`, `/proformas`, `/sales-orders`, `/delivery-notes`
  case salesDocuments(SalesDocumentKind)
  /// `/invoices/new` …
  case newSalesDocument(SalesDocumentKind)
  /// `/invoices/:id` …
  case salesDocument(SalesDocumentKind, id: String)
  /// `/invoices/:id/edit` …
  case editSalesDocument(SalesDocumentKind, id: String)
  /// `/bills`, `/vendor-credits`, `/purchase-orders`
  case purchaseDocuments(PurchaseDocumentKind)
  case newPurchaseDocument(PurchaseDocumentKind)
  case purchaseDocument(PurchaseDocumentKind, id: String)
  case editPurchaseDocument(PurchaseDocumentKind, id: String)
  /// `/clients`, `/vendors`
  case contacts(ContactKind)
  case newContact(ContactKind)
  case contact(ContactKind, id: String)
  case editContact(ContactKind, id: String)
  /// `/payments`, `/payments-made`
  case payments(PaymentDirection)
  case newPayment(PaymentDirection)
  case payment(PaymentDirection, id: String)
  case editPayment(PaymentDirection, id: String)
  /// `/recurring`, `/recurring/new`, `/recurring/:id`
  case recurring
  case newRecurring
  case recurringInvoice(id: String)
  /// `/cheques`, `/cheques/layouts`
  case cheques
  case chequeLayouts
  /// `/expenses`; `/expenses?new=1` opens a new expense
  case expenses
  case newExpense
  /// `/products`; `/products?new=1`
  case products
  case newProduct
  /// `/inventory` and its pages
  case inventory
  case newStockAdjustment
  case stockEntry(id: String)
  case stockIssues
  case newStockIssue
  case stockIssue(id: String)
  case stockCount
  case newLandedCost
  case landedCost(id: String)
  /// `/reports`, `/reports/:report`
  case reports
  case report(String)
  /// `/accounts`
  case accounts
  /// `/journals`, `/journals/new`, `/journals/:id`
  case journals
  case newJournal
  case journal(id: String)
  /// `/assets` …
  case assets
  case newAsset
  case asset(id: String)
  case editAsset(id: String)
  /// `/year-end`
  case yearEnd
  /// `/banking`, `/banking/:accountId`
  case banking
  case bankAccount(id: String)
  /// `/vat`, `/vat/:start`
  case vat
  case vatReturn(start: String)
  /// `/templates`
  case templates

  // Maham People
  /// `/people`
  case peopleOverview
  /// `/people/directory`
  case directory
  /// `/people/all`
  case allCompanies
  /// `/employees` …
  case employees
  case newEmployee
  case employee(id: String)
  case editEmployee(id: String)
  /// `/employees/:id/settlement`
  case settlement(employeeId: String)
  /// `/payroll`, `/payroll/runs/:id`
  case payroll
  case payRun(id: String)
  /// `/payroll/leave`, `/payroll/leave-reasons`, `/payroll/loans`, `/payroll/settings`
  case leave
  case leaveReasons
  case loans
  case payrollSettings
  /// `/people/letters`; `?new=1`; `/people/letters/templates`, `/people/letters/templates/:id`
  case letters
  case newLetter
  case letterTemplates
  case letterTemplate(id: String)
  /// `/people/costing`; `?new=1`; `/people/costing/:id`
  case costings
  case newCosting
  case costing(id: String)

  // Maham CRM
  /// `/crm`, `/crm/prospects`
  case pipeline
  case prospects

  // Maham Compliance
  /// `/compliance`, `/compliance/documents`, `/compliance/vehicles`
  case complianceCalendar
  case complianceDocuments
  case vehicles

  /// Anything else: the web's "Page not found".
  case notFound(String)
}

extension Route {
  /// Reads a web address: "/invoices/abc", "/expenses?new=1".
  init(path raw: String) {
    let bare = PathMatch.pathOnly(raw)
    let isNew = raw.contains("new=1")
    let s = bare.split(separator: "/").map(String.init)
    let first = s.first ?? ""
    let second = s.count > 1 ? s[1] : nil
    let third = s.count > 2 ? s[2] : nil

    if s.isEmpty {
      self = .home
      return
    }
    if let kind = SalesDocumentKind(rawValue: first) {
      self = Route.documentRoute(
        s, list: .salesDocuments(kind), new: .newSalesDocument(kind), view: { .salesDocument(kind, id: $0) },
        edit: { .editSalesDocument(kind, id: $0) }) ?? .notFound(bare)
      return
    }
    if let kind = PurchaseDocumentKind(rawValue: first) {
      self = Route.documentRoute(
        s, list: .purchaseDocuments(kind), new: .newPurchaseDocument(kind),
        view: { .purchaseDocument(kind, id: $0) }, edit: { .editPurchaseDocument(kind, id: $0) }) ?? .notFound(bare)
      return
    }
    if let kind = ContactKind(rawValue: first) {
      self = Route.documentRoute(
        s, list: .contacts(kind), new: .newContact(kind), view: { .contact(kind, id: $0) },
        edit: { .editContact(kind, id: $0) }) ?? .notFound(bare)
      return
    }
    if let direction = PaymentDirection(rawValue: first) {
      self = Route.documentRoute(
        s, list: .payments(direction), new: .newPayment(direction), view: { .payment(direction, id: $0) },
        edit: { .editPayment(direction, id: $0) }) ?? .notFound(bare)
      return
    }

    if first == "people", second == "letters", third == "templates", s.count == 4 {
      self = .letterTemplate(id: s[3])
      return
    }
    self =
      switch (first, second, third, s.count) {
      case ("files", nil, _, 1): .files
      case ("approvals", nil, _, 1): .approvals
      case ("notifications", nil, _, 1): .notifications
      case ("settings", nil, _, 1): .settings(section: nil)
      case ("settings", let section?, _, _): .settings(section: section)
      case ("setup", nil, _, 1): .setup
      case ("books", nil, _, 1): .booksDashboard
      case ("recurring", nil, _, 1): .recurring
      case ("recurring", "new"?, _, 2): .newRecurring
      case ("recurring", let id?, _, 2): .recurringInvoice(id: id)
      case ("cheques", nil, _, 1): .cheques
      case ("cheques", "layouts"?, _, 2): .chequeLayouts
      case ("expenses", nil, _, 1): isNew ? .newExpense : .expenses
      case ("products", nil, _, 1): isNew ? .newProduct : .products
      case ("inventory", nil, _, 1): .inventory
      case ("inventory", "adjustments"?, "new"?, 3): .newStockAdjustment
      case ("inventory", "entries"?, let id?, 3): .stockEntry(id: id)
      case ("inventory", "issues"?, nil, 2): .stockIssues
      case ("inventory", "issues"?, "new"?, 3): .newStockIssue
      case ("inventory", "issues"?, let id?, 3): .stockIssue(id: id)
      case ("inventory", "count"?, _, 2): .stockCount
      case ("inventory", "landed-costs"?, "new"?, 3): .newLandedCost
      case ("inventory", "landed-costs"?, let id?, 3): .landedCost(id: id)
      case ("reports", nil, _, 1): .reports
      case ("reports", let report?, _, 2): .report(report)
      case ("accounts", nil, _, 1): .accounts
      case ("journals", nil, _, 1): .journals
      case ("journals", "new"?, _, 2): .newJournal
      case ("journals", let id?, _, 2): .journal(id: id)
      case ("assets", nil, _, 1): .assets
      case ("assets", "new"?, _, 2): .newAsset
      case ("assets", let id?, nil, 2): .asset(id: id)
      case ("assets", let id?, "edit"?, 3): .editAsset(id: id)
      case ("year-end", nil, _, 1): .yearEnd
      case ("banking", nil, _, 1): .banking
      case ("banking", let id?, _, 2): .bankAccount(id: id)
      case ("vat", nil, _, 1): .vat
      case ("vat", let start?, _, 2): .vatReturn(start: start)
      case ("templates", nil, _, 1): .templates
      case ("people", nil, _, 1): .peopleOverview
      case ("people", "directory"?, _, 2): .directory
      case ("people", "all"?, _, 2): .allCompanies
      case ("people", "letters"?, nil, 2): isNew ? .newLetter : .letters
      case ("people", "letters"?, "templates"?, 3): .letterTemplates
      case ("people", "costing"?, nil, 2): isNew ? .newCosting : .costings
      case ("people", "costing"?, let id?, 3): .costing(id: id)
      case ("employees", nil, _, 1): .employees
      case ("employees", "new"?, _, 2): .newEmployee
      case ("employees", let id?, nil, 2): .employee(id: id)
      case ("employees", let id?, "edit"?, 3): .editEmployee(id: id)
      case ("employees", let id?, "settlement"?, 3): .settlement(employeeId: id)
      case ("payroll", nil, _, 1): .payroll
      case ("payroll", "runs"?, let id?, 3): .payRun(id: id)
      case ("payroll", "leave"?, _, 2): .leave
      case ("payroll", "leave-reasons"?, _, 2): .leaveReasons
      case ("payroll", "loans"?, _, 2): .loans
      case ("payroll", "settings"?, _, 2): .payrollSettings
      case ("crm", nil, _, 1): .pipeline
      case ("crm", "prospects"?, _, 2): .prospects
      case ("compliance", nil, _, 1): .complianceCalendar
      case ("compliance", "documents"?, _, 2): .complianceDocuments
      case ("compliance", "vehicles"?, _, 2): .vehicles
      default: .notFound(bare)
      }
  }

  /// `list`, `list/new`, `list/:id`, `list/:id/edit`.
  private static func documentRoute(
    _ s: [String], list: Route, new: Route, view: (String) -> Route, edit: (String) -> Route
  ) -> Route? {
    switch s.count {
    case 1: return list
    case 2: return s[1] == "new" ? new : view(s[1])
    case 3 where s[2] == "edit": return edit(s[1])
    default: return nil
    }
  }

  /// The web address.
  var path: String {
    switch self {
    case .home: "/"
    case .files: "/files"
    case .approvals: "/approvals"
    case .notifications: "/notifications"
    case .settings(let section): section.map { "/settings/\($0)" } ?? "/settings"
    case .setup: "/setup"
    case .booksDashboard: "/books"
    case .salesDocuments(let kind): "/\(kind.rawValue)"
    case .newSalesDocument(let kind): "/\(kind.rawValue)/new"
    case .salesDocument(let kind, let id): "/\(kind.rawValue)/\(id)"
    case .editSalesDocument(let kind, let id): "/\(kind.rawValue)/\(id)/edit"
    case .purchaseDocuments(let kind): "/\(kind.rawValue)"
    case .newPurchaseDocument(let kind): "/\(kind.rawValue)/new"
    case .purchaseDocument(let kind, let id): "/\(kind.rawValue)/\(id)"
    case .editPurchaseDocument(let kind, let id): "/\(kind.rawValue)/\(id)/edit"
    case .contacts(let kind): "/\(kind.rawValue)"
    case .newContact(let kind): "/\(kind.rawValue)/new"
    case .contact(let kind, let id): "/\(kind.rawValue)/\(id)"
    case .editContact(let kind, let id): "/\(kind.rawValue)/\(id)/edit"
    case .payments(let direction): "/\(direction.rawValue)"
    case .newPayment(let direction): "/\(direction.rawValue)/new"
    case .payment(let direction, let id): "/\(direction.rawValue)/\(id)"
    case .editPayment(let direction, let id): "/\(direction.rawValue)/\(id)/edit"
    case .recurring: "/recurring"
    case .newRecurring: "/recurring/new"
    case .recurringInvoice(let id): "/recurring/\(id)"
    case .cheques: "/cheques"
    case .chequeLayouts: "/cheques/layouts"
    case .expenses, .newExpense: "/expenses"
    case .products, .newProduct: "/products"
    case .inventory: "/inventory"
    case .newStockAdjustment: "/inventory/adjustments/new"
    case .stockEntry(let id): "/inventory/entries/\(id)"
    case .stockIssues: "/inventory/issues"
    case .newStockIssue: "/inventory/issues/new"
    case .stockIssue(let id): "/inventory/issues/\(id)"
    case .stockCount: "/inventory/count"
    case .newLandedCost: "/inventory/landed-costs/new"
    case .landedCost(let id): "/inventory/landed-costs/\(id)"
    case .reports: "/reports"
    case .report(let report): "/reports/\(report)"
    case .accounts: "/accounts"
    case .journals: "/journals"
    case .newJournal: "/journals/new"
    case .journal(let id): "/journals/\(id)"
    case .assets: "/assets"
    case .newAsset: "/assets/new"
    case .asset(let id): "/assets/\(id)"
    case .editAsset(let id): "/assets/\(id)/edit"
    case .yearEnd: "/year-end"
    case .banking: "/banking"
    case .bankAccount(let id): "/banking/\(id)"
    case .vat: "/vat"
    case .vatReturn(let start): "/vat/\(start)"
    case .templates: "/templates"
    case .peopleOverview: "/people"
    case .directory: "/people/directory"
    case .allCompanies: "/people/all"
    case .employees: "/employees"
    case .newEmployee: "/employees/new"
    case .employee(let id): "/employees/\(id)"
    case .editEmployee(let id): "/employees/\(id)/edit"
    case .settlement(let id): "/employees/\(id)/settlement"
    case .payroll: "/payroll"
    case .payRun(let id): "/payroll/runs/\(id)"
    case .leave: "/payroll/leave"
    case .leaveReasons: "/payroll/leave-reasons"
    case .loans: "/payroll/loans"
    case .payrollSettings: "/payroll/settings"
    case .letters, .newLetter: "/people/letters"
    case .letterTemplates: "/people/letters/templates"
    case .letterTemplate(let id): "/people/letters/templates/\(id)"
    case .costings, .newCosting: "/people/costing"
    case .costing(let id): "/people/costing/\(id)"
    case .pipeline: "/crm"
    case .prospects: "/crm/prospects"
    case .complianceCalendar: "/compliance"
    case .complianceDocuments: "/compliance/documents"
    case .vehicles: "/compliance/vehicles"
    case .notFound(let path): path
    }
  }

  /// The page's title, an English key of the web's.
  var titleKey: String {
    switch self {
    case .home: "Home"
    case .files: "Files"
    case .approvals: "Approvals"
    case .notifications: "Notifications"
    case .settings: "Settings"
    case .setup: "Add company"
    case .booksDashboard: "Dashboard"
    case .salesDocuments(let kind): kind.plural
    case .newSalesDocument(let kind): kind.createAction.command
    case .salesDocument(let kind, _), .editSalesDocument(let kind, _): kind.singular
    case .purchaseDocuments(let kind): kind.plural
    case .newPurchaseDocument(let kind): kind.createAction.command
    case .purchaseDocument(let kind, _), .editPurchaseDocument(let kind, _): kind.singular
    case .contacts(let kind): kind == .customer ? "Clients" : "Vendors"
    case .newContact(let kind): kind == .customer ? "New client" : "New vendor"
    case .contact(let kind, _), .editContact(let kind, _): kind == .customer ? "Client" : "Vendor"
    case .payments(let direction): direction == .received ? "Payments received" : "Payments made"
    case .newPayment(let direction): direction == .received ? "Record payment received" : "Record payment made"
    case .payment(let direction, _), .editPayment(let direction, _):
      direction == .received ? "Payment received" : "Payment made"
    case .recurring: "Recurring invoices"
    case .newRecurring: "New recurring invoice"
    case .recurringInvoice: "Recurring invoice"
    case .cheques: "Cheques"
    case .chequeLayouts: "Cheques"
    case .expenses: "Expenses"
    case .newExpense: "Record expense"
    case .products: "Products & services"
    case .newProduct: "New product or service"
    case .inventory: "Stock and warehouses"
    case .newStockAdjustment: "New stock adjustment"
    case .stockEntry: "Stock and warehouses"
    case .stockIssues, .stockIssue: "Issued items"
    case .newStockIssue: "Issue items to an employee"
    case .stockCount: "Stock count"
    case .newLandedCost, .landedCost: "Stock and warehouses"
    case .reports, .report: "Reports"
    case .accounts: "Chart of accounts"
    case .journals: "Manual journals"
    case .newJournal: "New manual journal"
    case .journal: "Manual journals"
    case .assets: "Fixed assets"
    case .newAsset: "New fixed asset"
    case .asset, .editAsset: "Fixed assets"
    case .yearEnd: "Year-end close"
    case .banking, .bankAccount: "Banking"
    case .vat, .vatReturn: "VAT returns"
    case .templates: "Templates"
    case .peopleOverview: "Overview"
    case .directory: "Directory"
    case .allCompanies: "Directory"
    case .employees: "Employees"
    case .newEmployee: "New employee"
    case .employee, .editEmployee, .settlement: "Employee"
    case .payroll, .payRun: "Payroll"
    case .leave: "Leave"
    case .leaveReasons: "Leave reasons"
    case .loans: "Staff loans"
    case .payrollSettings: "Payroll settings"
    case .letters, .letterTemplates, .letterTemplate: "Letters"
    case .newLetter: "New employee letter"
    case .costings, .costing: "Manpower costing"
    case .newCosting: "New manpower costing"
    case .pipeline: "Pipeline"
    case .prospects: "Prospects"
    case .complianceCalendar: "Calendar"
    case .complianceDocuments: "Documents"
    case .vehicles: "Vehicles"
    case .notFound: "Page not found"
    }
  }
}
