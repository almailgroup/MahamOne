import Foundation

/// New records, shaped exactly as the web makes them (src/db/defaults.ts):
/// the same fields with the same defaults, a new id, and `createdAt` and
/// `updatedAt` stamped as JavaScript's `toISOString()`. `overrides` replace
/// fields at the top level, as the web's `...overrides` does (a null in them
/// is stored as null).
public enum Defaults {
  /// A moment as JavaScript's `toISOString()` writes it: UTC, milliseconds
  /// (cut, not rounded), "2026-11-25T10:24:00.123Z".
  public static func nowStamp(_ date: Date = Date()) -> String {
    // Whole seconds, then the fraction to the microsecond: Date keeps its
    // time from 2001, so a whole millisecond can come back a hair below it.
    let seconds = date.timeIntervalSince1970
    let whole = seconds.rounded(.down)
    let micros = Int64(((seconds - whole) * 1_000_000).rounded())
    return isoString(milliseconds: Int64(whole) * 1000 + micros / 1000)
  }

  /// `new Date(milliseconds).toISOString()`.
  public static func isoString(milliseconds ms: Int64) -> String {
    let dayMs: Int64 = 86_400_000
    let days = ms >= 0 ? ms / dayMs : -((-ms + dayMs - 1) / dayMs)
    let rest = Int(ms - days * dayMs)
    let d = CivilDate.date(Int(days))
    let year =
      (0...9999).contains(d.year)
      ? WebJS.padStart(String(d.year), 4) : (d.year < 0 ? "-" : "+") + WebJS.padStart(String(abs(d.year)), 6)
    let two = { (n: Int) in WebJS.padStart(String(n), 2) }
    return "\(year)-\(two(d.month))-\(two(d.day))T\(two(rest / 3_600_000)):\(two(rest / 60_000 % 60))"
      + ":\(two(rest / 1000 % 60)).\(WebJS.padStart(String(rest % 1000), 3))Z"
  }

  /// The day it is on this device (`today()` of src/lib/dates.ts): the local
  /// calendar date, `yyyy-MM-dd`.
  public static func today(_ date: Date = Date(), in zone: TimeZone = .current) -> String {
    let seconds = (date.timeIntervalSince1970 + Double(zone.secondsFromGMT(for: date))).rounded(.down)
    let days = Int((seconds / 86_400).rounded(.down))
    return CivilDate.iso(days)
  }

  /// The numbering rules a new company starts with (`defaultNumbering`).
  public static func defaultNumbering() -> JSONValue {
    .object(Numbering.defaultRules().mapValues(\.raw))
  }

  public static let emailPlaceholders = [
    "{client}", "{contact}", "{number}", "{amount}", "{balance}", "{issueDate}", "{dueDate}", "{company}",
    "{paymentLink}",
  ]

  private static func template(_ subject: String, _ body: String) -> JSONValue {
    ["subject": .string(subject), "body": .string(body)]
  }

  public static func defaultEmailTemplates() -> JSONValue {
    [
      "invoice": template(
        "Invoice {number} from {company}",
        "Hello {contact},\n\nPlease find attached invoice {number} for {amount}, due on {dueDate}.\n\n"
          + "{paymentLink}\n\nThank you for your business.\n\nKind regards,\n{company}"),
      "quote": template(
        "Quote {number} from {company}",
        "Hello {contact},\n\nPlease find attached quote {number} for {amount}, valid until {dueDate}.\n\n"
          + "Let us know if you have any questions.\n\nKind regards,\n{company}"),
      "credit": template(
        "Credit note {number} from {company}",
        "Hello {contact},\n\nPlease find attached credit note {number} for {amount}.\n\n"
          + "Kind regards,\n{company}"),
      "reminder": template(
        "Reminder: invoice {number} is due",
        "Hello {contact},\n\nThis is a friendly reminder that invoice {number} has a balance of "
          + "{balance}, due on {dueDate}.\n\n{paymentLink}\n\nIf you have already paid, please ignore "
          + "this message.\n\nKind regards,\n{company}"),
      "payment": template(
        "Payment received — thank you",
        "Hello {contact},\n\nWe have received your payment of {amount}. Thank you.\n\n"
          + "Kind regards,\n{company}"),
    ]
  }

  /// The same messages in Arabic, for businesses that write to their clients in Arabic.
  public static func defaultEmailTemplatesAr() -> JSONValue {
    [
      "invoice": template(
        "فاتورة رقم {number} من {company}",
        "السادة {client} المحترمين،\n\nمرفق لكم الفاتورة رقم {number} بمبلغ {amount}، "
          + "وتاريخ استحقاقها {dueDate}.\n\n{paymentLink}\n\nشكراً لتعاملكم معنا.\n\nمع التحية،\n{company}"),
      "quote": template(
        "عرض سعر رقم {number} من {company}",
        "السادة {client} المحترمين،\n\nمرفق لكم عرض السعر رقم {number} بمبلغ {amount}، "
          + "وهو ساري حتى {dueDate}.\n\nيسعدنا الرد على أي استفسار.\n\nمع التحية،\n{company}"),
      "credit": template(
        "إشعار دائن رقم {number} من {company}",
        "السادة {client} المحترمين،\n\nمرفق لكم الإشعار الدائن رقم {number} بمبلغ {amount}.\n\n"
          + "مع التحية،\n{company}"),
      "reminder": template(
        "تذكير: استحقاق الفاتورة رقم {number}",
        "السادة {client} المحترمين،\n\nنود تذكيركم بأن الفاتورة رقم {number} عليها رصيد مستحق "
          + "قدره {balance}، وتاريخ استحقاقها {dueDate}.\n\n{paymentLink}\n\n"
          + "إذا كنتم قد سددتم المبلغ فنرجو تجاهل هذه الرسالة.\n\nمع التحية،\n{company}"),
      "payment": template(
        "تم استلام دفعتكم مع الشكر",
        "السادة {client} المحترمين،\n\nنفيدكم باستلام دفعتكم بمبلغ {amount}، ونشكركم على ذلك.\n\n"
          + "مع التحية،\n{company}"),
    ]
  }

  /// The notes new invoices and quotes start with, in the documents'
  /// language ("en", "ar" or "ar-en"): Arabic first, then English, on
  /// bilingual ones.
  public static func defaultNotes(_ language: String) -> (invoiceNotes: String, quoteNotes: String) {
    func write(_ en: String, _ ar: String) -> String {
      language == "ar" ? ar : language == "ar-en" ? "\(ar)\n\(en)" : en
    }
    return (
      write("Thank you for your business.", "شكراً لتعاملكم معنا."),
      write("We look forward to working with you.", "نتطلع إلى التعامل معكم.")
    )
  }

  private static func merged(_ base: [String: JSONValue], _ overrides: [String: JSONValue]) -> JSONValue {
    .object(base.merging(overrides) { _, override in override })
  }

  public static func createCompany(_ overrides: [String: JSONValue] = [:], now: Date = Date()) -> JSONValue {
    let stamp = JSONValue.string(nowStamp(now))
    // `overrides.locale ?? 'en-KW'`: null counts as not given here.
    let locale = WebJS.present(overrides["locale"]) ?? "en-KW"
    let localeText = WebJS.string(locale)
    let usLetter = localeText.hasSuffix("-US") || localeText.hasSuffix("-CA")
    // Kuwaiti invoices are in Arabic, with English next to it.
    let language = WebJS.present(overrides["language"]) ?? "ar-en"
    let notes = defaultNotes(language.string ?? WebJS.string(language))
    let base: [String: JSONValue] = [
      "id": .string(newId()),
      "name": "",
      "legalName": "",
      "email": "",
      "phone": "",
      "website": "",
      "taxIdLabel": "Tax card no.",
      "taxId": "",
      "registrationLabel": "CR No.",
      "registrationNumber": "",
      "address": Geo.emptyAddress("KW"),
      "currency": "KWD",
      "locale": locale,
      "dateFormat": "dd/MM/yyyy",
      "language": language,
      "branding": [
        "accentColor": "#4f46e5",
        "templateId": "modern",
        "logo": nil,
        "fontId": nil,
        "showStatusStamp": true,
      ],
      "defaults": [
        "paymentTermsDays": 30,
        "quoteValidDays": 30,
        "invoiceNotes": .string(notes.invoiceNotes),
        "quoteNotes": .string(notes.quoteNotes),
        "invoiceTerms": "",
        "quoteTerms": "",
        "creditNotes": "",
        "creditTerms": "",
        "footer": "",
        "pricesIncludeTax": false,
        "lineTaxes": true,
        "documentTaxes": false,
        "defaultTaxRateIds": [],
        "pageSize": usLetter ? "LETTER" : "A4",
      ],
      "numbering": defaultNumbering(),
      "payment": ["bankDetails": "", "instructions": "", "paymentLink": "", "showQrCode": true],
      "labels": [:],
      "emailTemplates": defaultEmailTemplates(),
      "createdAt": stamp,
      "updatedAt": stamp,
    ]
    return merged(base, overrides)
  }

  public static func createClient(companyId: String, _ overrides: [String: JSONValue] = [:], now: Date = Date())
    -> JSONValue
  {
    let stamp = JSONValue.string(nowStamp(now))
    let base: [String: JSONValue] = [
      "id": .string(newId()),
      "companyId": .string(companyId),
      "number": "",
      "name": "",
      "contacts": [],
      "email": "",
      "phone": "",
      "website": "",
      "taxId": "",
      "address": Geo.emptyAddress(),
      "shippingAddress": nil,
      "currency": nil,
      "paymentTermsDays": nil,
      "language": nil,
      "taxExempt": false,
      "notes": "",
      "archived": false,
      "createdAt": stamp,
      "updatedAt": stamp,
    ]
    return merged(base, overrides)
  }

  public static func createProduct(companyId: String, _ overrides: [String: JSONValue] = [:], now: Date = Date())
    -> JSONValue
  {
    let stamp = JSONValue.string(nowStamp(now))
    let base: [String: JSONValue] = [
      "id": .string(newId()),
      "companyId": .string(companyId),
      "sku": "",
      "name": "",
      "description": "",
      "unitPrice": 0,
      "unit": "",
      "taxRateIds": [],
      "archived": false,
      "createdAt": stamp,
      "updatedAt": stamp,
    ]
    return merged(base, overrides)
  }

  public static func createTaxRate(companyId: String, _ overrides: [String: JSONValue] = [:], now: Date = Date())
    -> JSONValue
  {
    let stamp = JSONValue.string(nowStamp(now))
    let base: [String: JSONValue] = [
      "id": .string(newId()),
      "companyId": .string(companyId),
      "name": "",
      "rate": 0,
      "archived": false,
      "createdAt": stamp,
      "updatedAt": stamp,
    ]
    return merged(base, overrides)
  }

  /// A document's totals before anything is on it.
  public static func emptyTotals() -> JSONValue {
    ["subtotal": 0, "discount": 0, "taxTotal": 0, "total": 0, "paid": 0, "balance": 0]
  }

  /// A new draft document of any type ("invoice", "quote", "bill", …), dated today.
  public static func createDocument(
    companyId: String, type: String, _ overrides: [String: JSONValue] = [:], now: Date = Date(),
    zone: TimeZone = .current
  ) -> JSONValue {
    let stamp = JSONValue.string(nowStamp(now))
    let base: [String: JSONValue] = [
      "id": .string(newId()),
      "companyId": .string(companyId),
      "type": .string(type),
      "number": "",
      "status": "draft",
      "clientId": "",
      "issueDate": .string(today(now, in: zone)),
      "dueDate": nil,
      "poNumber": "",
      "currency": "KWD",
      "items": [],
      "discount": 0,
      "discountType": "percent",
      "taxes": [],
      "charges": [],
      "pricesIncludeTax": false,
      "deposit": 0,
      "depositDueDate": nil,
      "notes": "",
      "terms": "",
      "footer": "",
      "privateNotes": "",
      "templateId": nil,
      "totals": emptyTotals(),
      "sentAt": nil,
      "paidAt": nil,
      "sourceId": nil,
      "convertedToId": nil,
      "recurringId": nil,
      "archived": false,
      "createdAt": stamp,
      "updatedAt": stamp,
    ]
    return merged(base, overrides)
  }

  /// A new recurring invoice profile, monthly from today.
  public static func createRecurring(
    companyId: String, _ overrides: [String: JSONValue] = [:], now: Date = Date(), zone: TimeZone = .current
  ) -> JSONValue {
    let stamp = JSONValue.string(nowStamp(now))
    let start = JSONValue.string(today(now, in: zone))
    let base: [String: JSONValue] = [
      "id": .string(newId()),
      "companyId": .string(companyId),
      "clientId": "",
      "name": "",
      "frequency": "monthly",
      "startDate": start,
      "nextIssueDate": start,
      "remainingCycles": nil,
      "dueDays": 30,
      "markSent": false,
      "status": "active",
      "template": [
        "currency": "KWD",
        "items": [],
        "discount": 0,
        "discountType": "percent",
        "taxes": [],
        "charges": [],
        "pricesIncludeTax": false,
        "poNumber": "",
        "notes": "",
        "terms": "",
        "footer": "",
        "privateNotes": "",
        "templateId": nil,
      ],
      "issuedCount": 0,
      "lastIssuedAt": nil,
      "archived": false,
      "createdAt": stamp,
      "updatedAt": stamp,
    ]
    return merged(base, overrides)
  }
}
