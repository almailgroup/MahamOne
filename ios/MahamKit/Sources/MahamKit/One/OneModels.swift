import Foundation

// Maham One's records, read from `public.records` (one JSON document per
// record: `src/db/types.ts` of the web app). Each model reads only what the
// iPhone shows and tolerates anything missing, since records written by
// older versions of the web app lack newer fields.

public enum MemberRole: String, Codable, Sendable, CaseIterable {
  case owner, admin, accountant, staff, viewer

  public var title: String {
    switch self {
    case .owner: "Owner"
    case .admin: "Admin"
    case .accountant: "Accountant"
    case .staff: "Staff"
    case .viewer: "Viewer"
    }
  }

  /// Payroll and people data: the database hides them from staff and viewers.
  public var seesPeople: Bool { self == .owner || self == .admin || self == .accountant }
}

/// A company you belong to (`my_companies()`).
public struct Company: Codable, Identifiable, Hashable, Sendable {
  public let id: String
  public var name: String
  public var role: MemberRole
  public var members: Int

  enum CodingKeys: String, CodingKey { case id, name, role, members }

  public init(id: String, name: String, role: MemberRole, members: Int = 1) {
    self.id = id
    self.name = name
    self.role = role
    self.members = members
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    name = try c.decode(String.self, forKey: .name)
    role = (try? c.decode(MemberRole.self, forKey: .role)) ?? .viewer
    members = (try? c.decode(Int.self, forKey: .members)) ?? 1
  }
}

/// A row of `public.records`: the record's JSON and its version.
public struct RecordRow<Value: Decodable & Sendable>: Decodable, Sendable {
  public let id: String
  public let rev: Int
  public let data: Value
}

/// The company record's details the app shows.
public struct CompanyProfile: Decodable, Hashable, Sendable {
  public var id: String
  public var name: String
  public var nameAr: String?
  public var currency: String
  public var email: String
  public var phone: String

  enum CodingKeys: String, CodingKey { case id, name, nameAr, currency, email, phone }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    name = (try? c.decode(String.self, forKey: .name)) ?? ""
    nameAr = try? c.decodeIfPresent(String.self, forKey: .nameAr)
    currency = (try? c.decode(String.self, forKey: .currency)) ?? "KWD"
    email = (try? c.decode(String.self, forKey: .email)) ?? ""
    phone = (try? c.decode(String.self, forKey: .phone)) ?? ""
  }
}

/// A name in the language being read: the Arabic one when there is one and
/// the app is in Arabic.
public func localName(_ name: String, _ nameAr: String?, arabic: Bool) -> String {
  if arabic, let nameAr, !nameAr.trimmingCharacters(in: .whitespaces).isEmpty { return nameAr }
  return name
}

public enum DocumentStatus: String, Codable, Sendable {
  case draft, sent, partial, paid, void, accepted, declined, invoiced, converted, applied
  case issued, delivered, cancelled, other

  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = DocumentStatus(rawValue: value) ?? .other
  }

  public var title: String {
    switch self {
    case .draft: "Draft"
    case .sent: "Sent"
    case .partial: "Partly paid"
    case .paid: "Paid"
    case .void: "Void"
    case .accepted: "Accepted"
    case .declined: "Declined"
    case .invoiced: "Invoiced"
    case .converted: "Converted"
    case .applied: "Applied"
    case .issued: "Issued"
    case .delivered: "Delivered"
    case .cancelled: "Cancelled"
    case .other: "Other"
    }
  }
}

public struct DocumentTotals: Codable, Hashable, Sendable {
  public var subtotal: Double
  public var taxTotal: Double
  public var total: Double
  public var paid: Double
  public var balance: Double

  enum CodingKeys: String, CodingKey { case subtotal, taxTotal, total, paid, balance }

  public init(subtotal: Double = 0, taxTotal: Double = 0, total: Double = 0, paid: Double = 0, balance: Double = 0) {
    self.subtotal = subtotal
    self.taxTotal = taxTotal
    self.total = total
    self.paid = paid
    self.balance = balance
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    subtotal = (try? c.decode(Double.self, forKey: .subtotal)) ?? 0
    taxTotal = (try? c.decode(Double.self, forKey: .taxTotal)) ?? 0
    total = (try? c.decode(Double.self, forKey: .total)) ?? 0
    paid = (try? c.decode(Double.self, forKey: .paid)) ?? 0
    balance = (try? c.decode(Double.self, forKey: .balance)) ?? 0
  }
}

public struct DocumentLine: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var kind: String
  public var name: String
  public var description: String
  public var quantity: Double
  public var unit: String
  public var unitPrice: Double

  enum CodingKeys: String, CodingKey { case id, kind, name, description, quantity, unit, unitPrice }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
    kind = (try? c.decode(String.self, forKey: .kind)) ?? "item"
    name = (try? c.decode(String.self, forKey: .name)) ?? ""
    description = (try? c.decode(String.self, forKey: .description)) ?? ""
    quantity = (try? c.decode(Double.self, forKey: .quantity)) ?? 0
    unit = (try? c.decode(String.self, forKey: .unit)) ?? ""
    unitPrice = (try? c.decode(Double.self, forKey: .unitPrice)) ?? 0
  }

  public var amount: Double { quantity * unitPrice }
}

/// An invoice, quote, credit note or any other sales or purchase document.
public struct SalesDocument: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var type: String
  public var number: String
  public var status: DocumentStatus
  public var clientId: String
  public var issueDate: LocalDate?
  public var dueDate: LocalDate?
  public var currency: String
  public var items: [DocumentLine]
  public var totals: DocumentTotals
  public var notes: String
  public var poNumber: String

  enum CodingKeys: String, CodingKey {
    case id, type, number, status, clientId, issueDate, dueDate, currency, items, totals, notes, poNumber
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    type = (try? c.decode(String.self, forKey: .type)) ?? "invoice"
    number = (try? c.decode(String.self, forKey: .number)) ?? ""
    status = (try? c.decode(DocumentStatus.self, forKey: .status)) ?? .other
    clientId = (try? c.decode(String.self, forKey: .clientId)) ?? ""
    issueDate = try? c.decodeIfPresent(LocalDate.self, forKey: .issueDate)
    dueDate = try? c.decodeIfPresent(LocalDate.self, forKey: .dueDate)
    currency = (try? c.decode(String.self, forKey: .currency)) ?? "KWD"
    items = (try? c.decode([DocumentLine].self, forKey: .items)) ?? []
    totals = (try? c.decode(DocumentTotals.self, forKey: .totals)) ?? DocumentTotals()
    notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
    poNumber = (try? c.decode(String.self, forKey: .poNumber)) ?? ""
  }

  /// Issued and not settled: what is still owed.
  public var isOpen: Bool {
    (status == .sent || status == .partial) && totals.balance > 0.0005
  }

  public func isOverdue(today: LocalDate) -> Bool {
    guard isOpen, let dueDate else { return false }
    return dueDate < today
  }

  public func daysOverdue(today: LocalDate) -> Int {
    guard isOverdue(today: today), let dueDate else { return 0 }
    return dueDate.days(to: today)
  }
}

public struct ClientContact: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var email: String
  public var phone: String
  public var primary: Bool

  enum CodingKeys: String, CodingKey { case id, name, email, phone, primary }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
    name = (try? c.decode(String.self, forKey: .name)) ?? ""
    email = (try? c.decode(String.self, forKey: .email)) ?? ""
    phone = (try? c.decode(String.self, forKey: .phone)) ?? ""
    primary = (try? c.decode(Bool.self, forKey: .primary)) ?? false
  }
}

public struct Client: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var number: String
  public var name: String
  public var nameAr: String?
  public var email: String
  public var phone: String
  public var website: String
  public var contacts: [ClientContact]
  public var city: String
  public var archived: Bool
  public var isCustomer: Bool
  public var isVendor: Bool

  enum CodingKeys: String, CodingKey {
    case id, number, name, nameAr, email, phone, website, contacts, address, archived, isCustomer, isVendor
  }

  private struct Address: Decodable {
    let city: String?
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    number = (try? c.decode(String.self, forKey: .number)) ?? ""
    name = (try? c.decode(String.self, forKey: .name)) ?? ""
    nameAr = try? c.decodeIfPresent(String.self, forKey: .nameAr)
    email = (try? c.decode(String.self, forKey: .email)) ?? ""
    phone = (try? c.decode(String.self, forKey: .phone)) ?? ""
    website = (try? c.decode(String.self, forKey: .website)) ?? ""
    contacts = (try? c.decode([ClientContact].self, forKey: .contacts)) ?? []
    city = ((try? c.decode(Address.self, forKey: .address))?.city) ?? ""
    archived = (try? c.decode(Bool.self, forKey: .archived)) ?? false
    isCustomer = (try? c.decode(Bool.self, forKey: .isCustomer)) ?? true
    isVendor = (try? c.decode(Bool.self, forKey: .isVendor)) ?? false
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(number, forKey: .number)
    try c.encode(name, forKey: .name)
    try c.encodeIfPresent(nameAr, forKey: .nameAr)
    try c.encode(email, forKey: .email)
    try c.encode(phone, forKey: .phone)
    try c.encode(website, forKey: .website)
    try c.encode(contacts, forKey: .contacts)
    try c.encode(archived, forKey: .archived)
    try c.encode(isCustomer, forKey: .isCustomer)
    try c.encode(isVendor, forKey: .isVendor)
  }

  /// The number to call: the client's own, or its main contact's.
  public var bestPhone: String? {
    let own = phone.trimmingCharacters(in: .whitespaces)
    if !own.isEmpty { return own }
    let contact = contacts.first(where: \.primary) ?? contacts.first
    let theirs = contact?.phone.trimmingCharacters(in: .whitespaces) ?? ""
    return theirs.isEmpty ? nil : theirs
  }

  public var bestEmail: String? {
    let own = email.trimmingCharacters(in: .whitespaces)
    if !own.isEmpty { return own }
    let contact = contacts.first(where: \.primary) ?? contacts.first
    let theirs = contact?.email.trimmingCharacters(in: .whitespaces) ?? ""
    return theirs.isEmpty ? nil : theirs
  }
}

/// An employee, as owners, admins and accountants may see them (the database
/// gives staff and viewers none).
public struct Employee: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var number: String
  public var name: String
  public var nameAr: String?
  public var jobTitle: String
  public var department: String
  public var nationality: String
  public var phone: String
  public var email: String
  public var status: String
  public var civilIdExpiry: LocalDate?
  public var passportExpiry: LocalDate?
  public var residencyExpiry: LocalDate?
  public var workPermitExpiry: LocalDate?

  enum CodingKeys: String, CodingKey {
    case id, number, name, nameAr, jobTitle, department, nationality, phone, email, status
    case civilIdExpiry, passportExpiry, residencyExpiry, workPermitExpiry
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    number = (try? c.decode(String.self, forKey: .number)) ?? ""
    name = (try? c.decode(String.self, forKey: .name)) ?? ""
    nameAr = try? c.decodeIfPresent(String.self, forKey: .nameAr)
    jobTitle = (try? c.decode(String.self, forKey: .jobTitle)) ?? ""
    department = (try? c.decode(String.self, forKey: .department)) ?? ""
    nationality = (try? c.decode(String.self, forKey: .nationality)) ?? ""
    phone = (try? c.decode(String.self, forKey: .phone)) ?? ""
    email = (try? c.decode(String.self, forKey: .email)) ?? ""
    status = (try? c.decode(String.self, forKey: .status)) ?? "active"
    civilIdExpiry = try? c.decodeIfPresent(LocalDate.self, forKey: .civilIdExpiry)
    passportExpiry = try? c.decodeIfPresent(LocalDate.self, forKey: .passportExpiry)
    residencyExpiry = try? c.decodeIfPresent(LocalDate.self, forKey: .residencyExpiry)
    workPermitExpiry = try? c.decodeIfPresent(LocalDate.self, forKey: .workPermitExpiry)
  }

  public var isActive: Bool { status != "left" && status != "terminated" }

  /// The employee's papers that expire, soonest first.
  public var expiries: [Expiry] {
    [
      civilIdExpiry.map { Expiry(id: "\(id)-civil", title: "Civil ID", owner: name, date: $0) },
      passportExpiry.map { Expiry(id: "\(id)-passport", title: "Passport", owner: name, date: $0) },
      residencyExpiry.map { Expiry(id: "\(id)-residency", title: "Residency", owner: name, date: $0) },
      workPermitExpiry.map { Expiry(id: "\(id)-permit", title: "Work permit", owner: name, date: $0) },
    ].compactMap { $0 }.sorted { $0.date < $1.date }
  }
}

/// A licence, permit or contract of the company register (Maham Compliance).
public struct ComplianceDocument: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var type: String
  public var title: String
  public var number: String
  public var issuer: String
  public var expiryDate: LocalDate?
  public var ownerName: String
  public var employeeId: String?
  public var archived: Bool

  enum CodingKeys: String, CodingKey {
    case id, type, title, number, issuer, expiryDate, ownerName, employeeId, archived
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    type = (try? c.decode(String.self, forKey: .type)) ?? ""
    title = (try? c.decode(String.self, forKey: .title)) ?? ""
    number = (try? c.decode(String.self, forKey: .number)) ?? ""
    issuer = (try? c.decode(String.self, forKey: .issuer)) ?? ""
    expiryDate = try? c.decodeIfPresent(LocalDate.self, forKey: .expiryDate)
    ownerName = (try? c.decode(String.self, forKey: .ownerName)) ?? ""
    employeeId = try? c.decodeIfPresent(String.self, forKey: .employeeId)
    archived = (try? c.decode(Bool.self, forKey: .archived)) ?? false
  }
}

/// Something with an expiry date: a document of the register or an
/// employee's paper.
public struct Expiry: Hashable, Sendable, Identifiable {
  public var id: String
  public var title: String
  public var owner: String
  public var date: LocalDate

  public init(id: String, title: String, owner: String, date: LocalDate) {
    self.id = id
    self.title = title
    self.owner = owner
    self.date = date
  }

  public func daysLeft(today: LocalDate) -> Int { today.days(to: date) }
}

/// A change of the team (`notification_feed`), for the owner and approvers.
public struct ChangeEvent: Codable, Hashable, Sendable, Identifiable {
  public var id: Int
  public var at: Date
  public var actorName: String?
  public var subjectName: String?
  public var kind: String
  public var op: String
  public var tbl: String
  public var count: Int
  public var important: Bool

  enum CodingKeys: String, CodingKey {
    case id, at, kind, op, tbl, count, important
    case actorName = "actor_name"
    case subjectName = "subject_name"
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(Int.self, forKey: .id)
    at = try c.decode(Date.self, forKey: .at)
    actorName = try? c.decodeIfPresent(String.self, forKey: .actorName)
    subjectName = try? c.decodeIfPresent(String.self, forKey: .subjectName)
    kind = (try? c.decode(String.self, forKey: .kind)) ?? ""
    op = (try? c.decode(String.self, forKey: .op)) ?? ""
    tbl = (try? c.decode(String.self, forKey: .tbl)) ?? ""
    count = (try? c.decode(Int.self, forKey: .count)) ?? 1
    important = (try? c.decode(Bool.self, forKey: .important)) ?? false
  }
}
