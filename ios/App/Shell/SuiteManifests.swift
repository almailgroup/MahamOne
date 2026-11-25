// The apps' manifests, as the web's `src/apps/*/manifest.ts`, and what can
// be created (`src/features/shell/create.ts`). Keep them the same as the web.

/// Everything that can be created, by id; apps list them in their groups.
enum CreateActions {
  static let invoice = CreateAction(id: "invoice", label: "Invoice", command: "New invoice", to: "/invoices/new", icon: .fileText)
  static let quote = CreateAction(
    id: "quote", label: "Quote", command: "New quote", to: "/quotes/new", icon: .scrollText, keywords: "estimate")
  static let proforma = CreateAction(
    id: "proforma", label: "Proforma invoice", command: "New proforma invoice", to: "/proformas/new", icon: .fileClock)
  static let salesOrder = CreateAction(
    id: "sales_order", label: "Sales order", command: "New sales order", to: "/sales-orders/new", icon: .clipboardList)
  static let deliveryNote = CreateAction(
    id: "delivery_note", label: "Delivery note", command: "New delivery note", to: "/delivery-notes/new",
    icon: .packageCheck)
  static let credit = CreateAction(
    id: "credit", label: "Credit note", command: "New credit note", to: "/credits/new", icon: .fileMinus)
  static let recurring = CreateAction(
    id: "recurring", label: "Recurring invoice", command: "New recurring invoice", to: "/recurring/new", icon: .repeat)
  static let paymentIn = CreateAction(
    id: "payment_in", label: "Payment received", command: "Record payment received", to: "/payments/new",
    icon: .arrowDownLeft, keywords: "receipt cheque knet")
  static let bill = CreateAction(id: "bill", label: "Bill", command: "New bill", to: "/bills/new", icon: .receipt)
  static let expense = CreateAction(
    id: "expense", label: "Expense", command: "Record expense", to: "/expenses?new=1", icon: .wallet)
  static let purchaseOrder = CreateAction(
    id: "purchase_order", label: "Purchase order", command: "New purchase order", to: "/purchase-orders/new",
    icon: .shoppingCart, keywords: "lpo")
  static let paymentOut = CreateAction(
    id: "payment_out", label: "Payment made", command: "Record payment made", to: "/payments-made/new",
    icon: .arrowUpRight)
  static let vendorCredit = CreateAction(
    id: "vendor_credit", label: "Vendor credit", command: "New vendor credit", to: "/vendor-credits/new",
    icon: .receiptText)
  static let client = CreateAction(
    id: "client", label: "Client", command: "New client", to: "/clients/new", icon: .users, keywords: "customer")
  static let vendor = CreateAction(
    id: "vendor", label: "Vendor", command: "New vendor", to: "/vendors/new", icon: .truck, keywords: "supplier")
  static let product = CreateAction(
    id: "product", label: "Product or service", command: "New product or service", to: "/products?new=1",
    icon: .package, keywords: "item")
  static let employee = CreateAction(
    id: "employee", label: "Employee", command: "New employee", to: "/employees/new", icon: .idCard)
  static let letter = CreateAction(
    id: "letter", label: "Employee letter", command: "New employee letter", to: "/people/letters?new=1",
    icon: .mailPlus, keywords: "salary certificate experience employment warning noc")
  static let costing = CreateAction(
    id: "costing", label: "Manpower costing", command: "New manpower costing", to: "/people/costing?new=1",
    icon: .calculator, keywords: "quotation pricing guards cleaners rate card manpower", costingOnly: true)
  static let journal = CreateAction(
    id: "journal", label: "Manual journal", command: "New manual journal", to: "/journals/new", icon: .notebookPen)
  static let asset = CreateAction(
    id: "asset", label: "Fixed asset", command: "New fixed asset", to: "/assets/new", icon: .armchair)
  static let stockAdjustment = CreateAction(
    id: "stock_adjustment", label: "Stock adjustment", command: "New stock adjustment",
    to: "/inventory/adjustments/new", icon: .packagePlus)
  static let stockIssue = CreateAction(
    id: "stock_issue", label: "Items to an employee", command: "Issue items to an employee",
    to: "/inventory/issues/new", icon: .shirt, keywords: "uniform custody guard")

  static let all: [CreateAction] = [
    invoice, quote, proforma, salesOrder, deliveryNote, credit, recurring, paymentIn, bill, expense,
    purchaseOrder, paymentOut, vendorCredit, client, vendor, product, employee, letter, costing, journal, asset,
    stockAdjustment, stockIssue,
  ]

  static func byId(_ id: String) -> CreateAction? { all.first { $0.id == id } }
}

private let managedAccess: [AccessKey: SuiteAccess] = [
  .device: .manage, .owner: .manage, .admin: .manage, .accountant: .manage, .staff: .edit, .viewer: .view,
]

enum SuiteManifests {
  private typealias A = CreateActions

  // MARK: Maham Books

  private static let booksSales = NavGroup(
    id: "sales", label: "Sales", icon: .shoppingBag,
    children: [
      NavLink("/clients", "Clients", keywords: "customers"),
      NavLink("/quotes", "Quotes", keywords: "estimates"),
      NavLink("/proformas", "Proforma invoices"),
      NavLink("/sales-orders", "Sales orders"),
      NavLink("/invoices", "Invoices"),
      NavLink("/delivery-notes", "Delivery notes"),
      NavLink("/payments", "Payments received", keywords: "receipts"),
      NavLink("/credits", "Credit notes"),
      NavLink("/recurring", "Recurring invoices"),
    ])

  private static let booksPurchases = NavGroup(
    id: "purchases", label: "Purchases", icon: .shoppingCart,
    children: [
      NavLink("/vendors", "Vendors", keywords: "suppliers"),
      NavLink("/purchase-orders", "Purchase orders", keywords: "lpo"),
      NavLink("/bills", "Bills"),
      NavLink("/expenses", "Expenses"),
      NavLink("/payments-made", "Payments made"),
      NavLink("/vendor-credits", "Vendor credits"),
    ])

  private static let booksInventory = NavGroup(
    id: "inventory", label: "Inventory", icon: .boxes,
    children: [
      NavLink("/products", "Products & services", keywords: "items"),
      NavLink("/inventory", "Stock and warehouses", keywords: "stock"),
      NavLink("/inventory/issues", "Issued items", keywords: "uniforms custody"),
    ])

  private static let booksAccounting = NavGroup(
    id: "accounting", label: "Accounting", icon: .bookOpen,
    children: [
      NavLink("/accounts", "Chart of accounts"),
      NavLink("/journals", "Manual journals"),
      NavLink("/assets", "Fixed assets", keywords: "depreciation"),
      NavLink("/year-end", "Year-end close"),
      NavLink("/vat", "VAT returns", only: .taxes),
    ])

  private static let home = NavTopLink("/", "Home", icon: .house, end: true)
  private static let dashboard = NavTopLink(
    "/books", "Dashboard", icon: .layoutDashboard, end: true, keywords: "books overview")
  private static let cheques = NavTopLink("/cheques", "Cheques", icon: .walletCards, keywords: "pdc")
  private static let banking = NavTopLink("/banking", "Banking", icon: .banknote)
  private static let reports = NavTopLink("/reports", "Reports", icon: .chartColumn)
  private static let approvals = NavTopLink(
    "/approvals", "Approvals", icon: .clipboardCheck, keywords: "approval requests void", only: .approvals)
  private static let templates = NavTopLink("/templates", "Templates", icon: .palette)
  private static let settings = NavTopLink("/settings", "Settings", icon: .settings)

  static let books = SuiteApp(
    id: .books, name: "Maham Books", nameAr: "مهام بوكس",
    description: "Invoices, purchases, cheques, banking, accounting and reports.", icon: .bookOpenText,
    tone: .indigo, home: "/books",
    owns: [
      "books", "invoices", "quotes", "credits", "proformas", "sales-orders", "delivery-notes", "recurring",
      "payments", "payments-made", "cheques", "clients", "vendors", "bills", "vendor-credits", "purchase-orders",
      "expenses", "products", "inventory", "reports", "accounts", "journals", "assets", "year-end", "banking",
      "vat", "templates",
    ],
    nav: [
      .link(home), .link(dashboard), .group(booksSales), .group(booksPurchases), .link(cheques),
      .group(booksInventory), .link(banking), .group(booksAccounting), .link(reports), .link(approvals),
    ],
    footer: [templates, settings],
    create: [
      CreateGroup(
        label: "Sales",
        actions: [A.invoice, A.quote, A.proforma, A.salesOrder, A.deliveryNote, A.credit, A.recurring, A.paymentIn]),
      CreateGroup(label: "Purchases", actions: [A.bill, A.expense, A.purchaseOrder, A.paymentOut, A.vendorCredit]),
      CreateGroup(label: "Contacts and items", actions: [A.client, A.vendor, A.product]),
      CreateGroup(label: "Accounting", actions: [A.journal, A.asset, A.stockAdjustment, A.stockIssue]),
    ],
    tools: [
      SuiteTool("/invoices", "Invoices", icon: .fileText, keywords: "sales bill customer"),
      SuiteTool("/quotes", "Quotes", icon: .scrollText, keywords: "estimates"),
      SuiteTool("/clients", "Clients", icon: .users, keywords: "customers"),
      SuiteTool("/payments", "Payments received", icon: .handCoins, keywords: "receipts"),
      SuiteTool("/vendors", "Vendors", icon: .truck, keywords: "suppliers"),
      SuiteTool("/bills", "Bills", icon: .receipt, keywords: "purchases"),
      SuiteTool("/expenses", "Expenses", icon: .wallet),
      SuiteTool("/cheques", "Cheques", icon: .walletCards, keywords: "pdc"),
      SuiteTool("/products", "Products & services", icon: .package, keywords: "items stock"),
      SuiteTool("/banking", "Banking", icon: .landmark, keywords: "bank statement"),
      SuiteTool("/accounts", "Chart of accounts", icon: .bookOpen, keywords: "ledger"),
      SuiteTool("/reports", "Reports", icon: .chartColumn),
    ],
    tabs: [
      home,
      NavTopLink("/invoices", "Invoices", icon: .fileText),
      NavTopLink("/expenses", "Expenses", icon: .wallet),
    ],
    access: managedAccess)

  /// Maham Books in the split layout: the finance app, still called Maham Books.
  static let finance = SuiteApp(
    id: .books, name: books.name, nameAr: books.nameAr,
    description: "Purchases, cheques, banking, accounting and reports.", icon: books.icon, tone: books.tone,
    home: books.home,
    owns: books.owns.filter {
      ![
        "quotes", "proformas", "sales-orders", "invoices", "delivery-notes", "credits", "recurring", "payments",
        "clients", "products", "inventory",
      ].contains($0)
    },
    shares: ["clients", "invoices", "payments", "credits", "products", "inventory"],
    nav: [
      .link(home), .link(dashboard),
      .group(
        NavGroup(
          id: "receivables", label: "Receivables", icon: .handCoins,
          children: [
            NavLink("/clients", "Clients", keywords: "customers"),
            NavLink("/invoices", "Invoices"),
            NavLink("/payments", "Payments received", keywords: "receipts"),
            NavLink("/credits", "Credit notes"),
          ])),
      .group(booksPurchases), .link(cheques), .group(booksInventory), .link(banking), .group(booksAccounting),
      .link(reports), .link(approvals),
    ],
    footer: [templates, settings],
    create: [
      CreateGroup(
        label: "Purchases", actions: [A.bill, A.expense, A.purchaseOrder, A.paymentOut, A.vendorCredit, A.vendor]),
      CreateGroup(label: "Accounting", actions: [A.journal, A.asset]),
    ],
    tools: [
      SuiteTool("/bills", "Bills", icon: .receipt, keywords: "purchases"),
      SuiteTool("/expenses", "Expenses", icon: .wallet),
      SuiteTool("/vendors", "Vendors", icon: .truck, keywords: "suppliers"),
      SuiteTool("/cheques", "Cheques", icon: .walletCards, keywords: "pdc"),
      SuiteTool("/banking", "Banking", icon: .landmark, keywords: "bank statement"),
      SuiteTool("/reports/aging", "Receivables aging", icon: .handCoins, keywords: "who owes receivables"),
      SuiteTool("/accounts", "Chart of accounts", icon: .bookOpen, keywords: "ledger"),
      SuiteTool("/reports", "Reports", icon: .chartColumn),
    ],
    tabs: [
      home,
      NavTopLink("/bills", "Bills", icon: .receipt),
      NavTopLink("/expenses", "Expenses", icon: .wallet),
    ],
    access: managedAccess)

  // MARK: Maham People

  static let people = SuiteApp(
    id: .people, name: "Maham People", nameAr: "مهام بيبول", description: "Employees, payroll, leave and staff loans.",
    icon: .usersRound, tone: .emerald, home: "/people", owns: ["people", "employees", "payroll"],
    nav: [
      .link(home),
      .link(NavTopLink("/people", "Overview", icon: .layoutDashboard, end: true, keywords: "hr team today")),
      .link(NavTopLink("/people/directory", "Directory", icon: .contact, keywords: "phone email contacts staff")),
      .link(NavTopLink("/employees", "Employees", icon: .idCard, keywords: "staff")),
      .link(NavTopLink("/payroll", "Payroll", icon: .walletCards, keywords: "pay runs salaries pifss")),
      .link(NavTopLink("/payroll/leave", "Leave", icon: .calendarDays, keywords: "vacation annual sick")),
      .link(
        NavTopLink(
          "/payroll/leave-reasons", "Leave reasons", icon: .tags, keywords: "emergency compensatory unpaid half pay")),
      .link(NavTopLink("/payroll/loans", "Staff loans", icon: .handCoins, keywords: "advance")),
      .link(
        NavTopLink(
          "/people/letters", "Letters", icon: .mails,
          keywords: "salary certificate experience employment warning noc letter templates")),
      .link(
        NavTopLink(
          "/people/costing", "Manpower costing", icon: .calculator,
          keywords: "quotation quote pricing guards cleaners rate card manpower cost sheet", only: .costing)),
      .link(NavTopLink("/payroll/settings", "Payroll settings", icon: .slidersHorizontal)),
      .link(
        NavTopLink(
          "/approvals", "Approvals", icon: .clipboardCheck, keywords: "salary approval pay run requests",
          only: .payrollApprovals)),
    ],
    footer: [settings],
    create: [CreateGroup(label: "People", actions: [A.employee, A.letter, A.costing])],
    tools: [
      SuiteTool("/people/directory", "Directory", icon: .contact, keywords: "phone email"),
      SuiteTool("/employees", "Employees", icon: .idCard, keywords: "staff"),
      SuiteTool("/payroll", "Payroll", icon: .coins, keywords: "salaries pifss"),
      SuiteTool("/payroll/leave", "Leave", icon: .calendarDays, keywords: "vacation"),
      SuiteTool("/payroll/loans", "Staff loans", icon: .piggyBank, keywords: "advance"),
    ],
    tabs: [
      home,
      NavTopLink("/employees", "Employees", icon: .idCard),
      NavTopLink("/payroll", "Payroll", icon: .walletCards),
    ],
    access: [.device: .manage, .owner: .manage, .admin: .manage, .accountant: .manage, .staff: .hidden, .viewer: .hidden])

  // MARK: Maham CRM

  static let crm = SuiteApp(
    id: .crm, name: "Maham CRM", nameAr: "مهام CRM", description: "Quotes pipeline, follow-ups and prospects.",
    icon: .handshake, tone: .sky, home: "/crm", owns: ["crm"], shares: ["clients", "quotes", "sales-orders", "templates"],
    nav: [
      .link(home),
      .link(NavTopLink("/crm", "Pipeline", icon: .kanbanSquare, end: true, keywords: "deals sales follow up")),
      .link(NavTopLink("/crm/prospects", "Prospects", icon: .userSearch, keywords: "leads potential customers")),
      .link(NavTopLink("/clients", "Customers", icon: .users, keywords: "clients")),
      .link(NavTopLink("/quotes", "Quotes", icon: .scrollText, keywords: "estimates")),
      .link(NavTopLink("/sales-orders", "Sales orders", icon: .clipboardList, keywords: "orders")),
    ],
    footer: [settings],
    create: [CreateGroup(label: "Sales", actions: [A.quote, A.client, A.salesOrder])],
    tools: [
      SuiteTool("/crm", "Pipeline", icon: .kanbanSquare, keywords: "deals follow up"),
      SuiteTool("/crm/prospects", "Prospects", icon: .userSearch, keywords: "leads"),
      SuiteTool("/clients", "Customers", icon: .users, keywords: "clients"),
      SuiteTool("/quotes", "Quotes", icon: .scrollText, keywords: "estimates"),
      SuiteTool("/sales-orders", "Sales orders", icon: .clipboardList),
    ],
    tabs: [
      home,
      NavTopLink("/crm", "Pipeline", icon: .kanbanSquare, end: true),
      NavTopLink("/quotes", "Quotes", icon: .scrollText),
    ],
    access: [.device: .manage, .owner: .manage, .admin: .manage, .accountant: .edit, .staff: .edit, .viewer: .view],
    preview: true)

  // MARK: Maham Compliance

  static let compliance = SuiteApp(
    id: .compliance, name: "Maham Compliance", nameAr: "مهام الامتثال",
    description: "Licences, staff papers and statutory deadlines.", icon: .shieldCheck, tone: .amber,
    home: "/compliance", owns: ["compliance", "files"],
    nav: [
      .link(home),
      .link(
        NavTopLink(
          "/compliance", "Calendar", icon: .calendarClock, end: true, keywords: "deadlines pifss moci renewals")),
      .link(
        NavTopLink(
          "/compliance/documents", "Documents", icon: .folderCheck, keywords: "licence residency passport expiring")),
      .link(
        NavTopLink(
          "/compliance/vehicles", "Vehicles", icon: .car, keywords: "cars plates registration insurance drivers",
          only: .registerExtras)),
      .link(
        NavTopLink(
          "/files", "Files", icon: .fileSearch, keywords: "find attachments receipts scans pdf papers personnel",
          only: .fileFinder)),
    ],
    footer: [settings],
    create: [],
    tools: [
      SuiteTool("/compliance", "Calendar", icon: .calendarClock, keywords: "deadlines pifss"),
      SuiteTool("/compliance/documents", "Documents", icon: .folderCheck, keywords: "licences residency passport"),
    ],
    tabs: [
      home,
      NavTopLink("/compliance", "Calendar", icon: .calendarClock, end: true),
      NavTopLink("/compliance/documents", "Documents", icon: .folderCheck),
    ],
    access: [.device: .manage, .owner: .manage, .admin: .manage, .accountant: .manage, .staff: .view, .viewer: .view])

  // MARK: Maham Sales and Maham Inventory (the split layout)

  static let sales = SuiteApp(
    id: .sales, name: "Maham Sales", nameAr: "مهام سيلز",
    description: "Quotes, orders, invoices, payments received and customers.", icon: .shoppingBag, tone: .violet,
    home: "/invoices",
    owns: [
      "quotes", "proformas", "sales-orders", "invoices", "delivery-notes", "credits", "recurring", "payments", "clients",
    ],
    shares: ["products", "templates"],
    nav: [
      .link(home),
      .link(NavTopLink("/clients", "Clients", icon: .users, keywords: "customers")),
      .link(NavTopLink("/quotes", "Quotes", icon: .scrollText, keywords: "estimates")),
      .link(NavTopLink("/proformas", "Proforma invoices", icon: .fileClock)),
      .link(NavTopLink("/sales-orders", "Sales orders", icon: .clipboardList, keywords: "orders")),
      .link(NavTopLink("/invoices", "Invoices", icon: .fileText)),
      .link(NavTopLink("/delivery-notes", "Delivery notes", icon: .truck)),
      .link(NavTopLink("/payments", "Payments received", icon: .arrowDownLeft, keywords: "receipts")),
      .link(NavTopLink("/credits", "Credit notes", icon: .fileMinus)),
      .link(NavTopLink("/recurring", "Recurring invoices", icon: .repeat)),
      .link(NavTopLink("/products", "Products & services", icon: .package, keywords: "items prices")),
      .link(approvals),
    ],
    footer: [templates, settings],
    create: [
      CreateGroup(
        label: "Sales",
        actions: [
          A.invoice, A.quote, A.proforma, A.salesOrder, A.deliveryNote, A.credit, A.recurring, A.paymentIn, A.client,
        ])
    ],
    tools: [
      SuiteTool("/invoices", "Invoices", icon: .fileText, keywords: "sales bill customer"),
      SuiteTool("/quotes", "Quotes", icon: .scrollText, keywords: "estimates"),
      SuiteTool("/clients", "Clients", icon: .users, keywords: "customers"),
      SuiteTool("/payments", "Payments received", icon: .arrowDownLeft, keywords: "receipts"),
      SuiteTool("/sales-orders", "Sales orders", icon: .clipboardList, keywords: "orders"),
      SuiteTool("/delivery-notes", "Delivery notes", icon: .truck),
      SuiteTool("/credits", "Credit notes", icon: .fileMinus),
    ],
    tabs: [
      home,
      NavTopLink("/invoices", "Invoices", icon: .fileText),
      NavTopLink("/quotes", "Quotes", icon: .scrollText),
    ],
    access: managedAccess)

  static let inventory = SuiteApp(
    id: .inventory, name: "Maham Inventory", nameAr: "مهام إنفنتوري",
    description: "Items, stock, warehouses and stock counts.", icon: .boxes, tone: .teal, home: "/inventory",
    owns: ["products", "inventory"], shares: ["purchase-orders", "bills", "vendors", "delivery-notes"],
    nav: [
      .link(home),
      .link(
        NavTopLink(
          "/inventory", "Stock and warehouses", icon: .warehouse, keywords: "stock on hand adjustments landed costs")),
      .link(
        NavTopLink(
          "/inventory/issues", "Issued items", icon: .shirt, keywords: "uniforms custody employees guards sub-warehouse")),
      .link(NavTopLink("/products", "Products & services", icon: .package, keywords: "items sku labels")),
      .link(NavTopLink("/inventory/count", "Stock count", icon: .clipboardCheck, keywords: "stocktake")),
      .link(NavTopLink("/purchase-orders", "Purchase orders", icon: .shoppingCart, keywords: "lpo")),
      .link(NavTopLink("/bills", "Bills", icon: .receipt)),
      .link(NavTopLink("/vendors", "Vendors", icon: .truck, keywords: "suppliers")),
      .link(NavTopLink("/delivery-notes", "Delivery notes", icon: .clipboardList)),
    ],
    footer: [settings],
    create: [CreateGroup(label: "Inventory", actions: [A.product, A.stockAdjustment, A.stockIssue])],
    tools: [
      SuiteTool("/inventory", "Stock and warehouses", icon: .warehouse, keywords: "stock"),
      SuiteTool("/inventory/issues", "Issued items", icon: .shirt, keywords: "uniforms"),
      SuiteTool("/products", "Products & services", icon: .package, keywords: "items"),
      SuiteTool("/inventory/count", "Stock count", icon: .clipboardCheck),
      SuiteTool("/purchase-orders", "Purchase orders", icon: .shoppingCart, keywords: "lpo"),
    ],
    tabs: [
      home,
      NavTopLink("/inventory", "Stock", icon: .warehouse),
      NavTopLink("/products", "Products", icon: .package),
    ],
    access: managedAccess)

  // MARK: Layouts

  /// The classic layout's apps, in the switcher's and the home's order.
  static let classic: [SuiteApp] = [books, people, crm, compliance]
  /// The split layout's: Sales, Books (finance), Inventory, then the others.
  static let split: [SuiteApp] = [sales, finance, inventory, people, crm, compliance]

  static func apps(_ layout: SuiteLayout) -> [SuiteApp] {
    layout == .split ? split : classic
  }
}
