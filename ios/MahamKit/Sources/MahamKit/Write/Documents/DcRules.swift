import Foundation

/// The web's rules of document types and statuses (src/lib/document-types.ts,
/// src/lib/status.ts, src/lib/retention.ts and the numbering rules of
/// src/db/documents.ts).
public enum DcRules {
  // MARK: Types

  /// Every document type, in the web's order.
  public static let types = [
    "invoice", "quote", "credit", "proforma", "sales_order", "delivery_note", "bill", "vendor_credit", "purchase_order",
  ]

  /// `isPurchaseType`: bills, vendor credits and purchase orders, against a vendor.
  public static func isPurchaseType(_ type: String) -> Bool {
    type == "bill" || type == "vendor_credit" || type == "purchase_order"
  }

  /// `isOrderType`: proformas, orders and delivery notes never post.
  public static func isOrderType(_ type: String) -> Bool {
    type == "proforma" || type == "sales_order" || type == "purchase_order" || type == "delivery_note"
  }

  /// `postsToLedger`: invoices, credit notes, bills and vendor credits.
  public static func postsToLedger(_ type: String) -> Bool {
    type == "invoice" || type == "credit" || type == "bill" || type == "vendor_credit"
  }

  /// `hasPrices`: delivery notes list goods only.
  public static func hasPrices(_ type: String) -> Bool { type != "delivery_note" }

  /// `isPosted`: issued (not a draft) and not void, of a type that posts.
  public static func isPosted(type: String, status: String) -> Bool {
    guard postsToLedger(type) else { return false }
    return status != "draft" && status != "void"
  }

  public static func isPosted(_ doc: JSONValue) -> Bool {
    isPosted(type: doc.dcText("type"), status: doc.dcText("status"))
  }

  // MARK: Statuses

  /// `issuedStatus`: sent, confirmed (sales orders) or issued (purchase
  /// orders); delivery notes are marked as delivered instead.
  public static func issuedStatus(_ type: String) -> String? {
    switch type {
    case "sales_order": "confirmed"
    case "purchase_order": "issued"
    case "delivery_note": nil
    default: "sent"
    }
  }

  /// `settledStatus`: an invoice's or credit's status once its paid amount changed.
  public static func settledStatus(type: String, status: String, total: Double, paid: Double) -> String {
    if !postsToLedger(type) || status == "void" { return status }
    let settled = Money.dec(total) - Money.dec(paid) <= 0
    let done = type == "credit" || type == "vendor_credit" ? "applied" : "paid"
    if paid != 0 && settled { return done }
    if paid != 0 { return "partial" }
    return status == "draft" ? "draft" : "sent"
  }

  /// `displayStatus`: adds the time-based "overdue" and "expired", and "open" for bills.
  public static func displayStatus(_ doc: JSONValue, today: String) -> String {
    let type = doc.dcText("type")
    let status = doc.dcText("status")
    let due = doc["dueDate"]?.string ?? ""
    let balance = doc["totals"]?["balance"]?.double ?? 0
    if type == "invoice" || type == "bill", status == "sent" || status == "partial", !due.isEmpty, due < today,
      balance > 0
    {
      return "overdue"
    }
    if type == "quote" || type == "proforma", status == "sent", !due.isEmpty, due < today { return "expired" }
    if type == "bill" || type == "vendor_credit", status == "sent" { return "open" }
    return status
  }

  // MARK: Numbers

  /// `NUMBERED_ON_ISSUE`.
  public static let numberedOnIssue = ["invoice", "credit"]

  /// `waitsForNumber`: a draft invoice or credit note of a company that
  /// numbers them when they are issued.
  public static func waitsForNumber(company: JSONValue?, type: String, status: String) -> Bool {
    company?["defaults"]?["numberOnIssue"] == .bool(true) && numberedOnIssue.contains(type) && status == "draft"
  }

  public static func waitsForNumber(company: JSONValue?, _ doc: JSONValue) -> Bool {
    waitsForNumber(company: company, type: doc.dcText("type"), status: doc.dcText("status"))
  }

  /// The company's rule for a kind (`company.numbering[kind] ?? defaultNumbering()[kind]`).
  public static func rule(_ company: JSONValue, _ kind: String) -> NumberingRule {
    if let raw = WebJS.present(company["numbering"]?[kind]) { return NumberingRule(raw) }
    return Numbering.defaultRules()[kind] ?? NumberingRule(pattern: "{counter}")
  }

  // MARK: Retention (src/lib/retention.ts)

  /// `certificateValidOn`.
  public static func certificateValidOn(_ certificate: JSONValue, _ date: String) -> Bool {
    let issued = certificate["issueDate"]?.string ?? ""
    if issued.isEmpty || issued > date { return false }
    let expiry = certificate["expiryDate"]?.string ?? ""
    return expiry.isEmpty || expiry >= date
  }

  /// `validCertificate`: the contact's certificate valid on a date, the one valid the longest.
  public static func validCertificate(_ contact: JSONValue?, _ date: String) -> JSONValue? {
    let valid = (contact?["clearanceCertificates"]?.array ?? []).filter { certificateValidOn($0, date) }
    if valid.isEmpty { return nil }
    let end = { (c: JSONValue) in c["expiryDate"]?.string ?? "9999-12-31" }
    var best = valid[0]
    for certificate in valid.dropFirst() where end(certificate) > end(best) { best = certificate }
    return best
  }

  /// `contactRetention`: the contact's retention rate, 0 when none.
  public static func contactRetention(_ contact: JSONValue?) -> Double {
    guard let value = WebJS.present(contact?["retentionPercent"]) else { return 0 }
    guard case .number(let percent) = value, percent.isFinite, percent > 0 else { return 0 }
    return min(percent, 100)
  }

  /// `retentionDefaults`: the retention of a new invoice or bill of this contact.
  public static func retentionDefaults(_ contact: JSONValue?, type: String, issueDate: String) -> DcPatch {
    let percent = contactRetention(contact)
    guard DcCalc.takesRetention(type), let contact, percent != 0 else {
      return [("retentionPercent", .number(0)), ("retentionKind", nil)]
    }
    let kind = WebJS.present(contact["retentionKind"]) ?? .string("tax")
    if kind == .string("tax") && validCertificate(contact, issueDate) != nil {
      return [("retentionPercent", .number(0)), ("retentionKind", kind)]
    }
    return [("retentionPercent", .number(percent)), ("retentionKind", kind)]
  }

  /// Retention releases not undone (`hasActiveReleases`).
  public static func hasActiveReleases(_ doc: JSONValue) -> Bool {
    doc.dcList("retentionReleases").contains { !WebJS.truthy($0["reversedOn"]) }
  }
}
