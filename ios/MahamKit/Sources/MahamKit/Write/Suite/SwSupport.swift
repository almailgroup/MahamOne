import Foundation

// What the suite's ports share (compliance, vehicles, the company's
// settings, tax rates and files): the company's link to the cloud, how the
// web tidies text and compares names, the register's document types, and
// small JavaScript readings of a record's fields.

/// The company's link to the cloud as these ports need it: what its server
/// has (`linkHasFeature`). A company kept on this device only has none (nil).
public struct SwCloud: Sendable, Equatable {
  public var features: Set<String>

  public init(features: [String]) {
    self.features = Set(features)
  }

  /// `linkHasFeature(link, feature)` for a company kept in the cloud.
  public func has(_ feature: String) -> Bool { features.contains(feature) }

  /// `linkHasFeature(link, feature)`: always for a company kept on this device.
  static func allows(_ cloud: SwCloud?, _ feature: String) -> Bool {
    guard let cloud else { return true }
    return cloud.has(feature)
  }
}

// MARK: Reading a record

/// A record's fields as the web reads them.
enum SwField {
  /// The record's fields (none for a missing record).
  static func fields(_ value: JSONValue?) -> [String: JSONValue] {
    value?.object ?? [:]
  }

  /// A text field (`record.key`), "" when it isn't text.
  static func text(_ fields: [String: JSONValue], _ key: String) -> String {
    fields[key]?.string ?? ""
  }

  /// A text field that is set (`record.key || null`): nil when missing, null or empty.
  static func id(_ value: JSONValue?) -> String? {
    guard case .some(.string(let text)) = value, !text.isEmpty else { return nil }
    return text
  }

  /// `record.key === true`.
  static func isTrue(_ fields: [String: JSONValue], _ key: String) -> Bool {
    fields[key] == .bool(true)
  }

  /// `record.key` as JavaScript's truthiness reads it.
  static func truthy(_ fields: [String: JSONValue], _ key: String) -> Bool {
    WebJS.truthy(fields[key])
  }

  /// `value ?? null` as JSON: a missing value is null.
  static func orNull(_ value: JSONValue?) -> JSONValue {
    value ?? .null
  }

  /// A text, or null.
  static func string(_ text: String?) -> JSONValue {
    text.map { JSONValue.string($0) } ?? .null
  }
}

// MARK: Text

/// How the web tidies and compares what people type.
public enum SwText {
  /// `text.trim()`.
  public static func trim(_ text: String?) -> String {
    WebJS.trim(text ?? "")
  }

  /// `(text ?? '').trim().replace(/\s+/g, ' ')`: trimmed, with single spaces.
  public static func tidy(_ text: String?) -> String {
    let trimmed = WebJS.trim(text ?? "")
    var out = String.UnicodeScalarView()
    var inSpace = false
    for scalar in trimmed.unicodeScalars {
      if WebJS.isSpace(scalar) {
        if !inSpace { out.append(" ") }
        inSpace = true
      } else {
        out.append(scalar)
        inSpace = false
      }
    }
    return String(out)
  }

  private static let arabicLetters: [UInt32: UInt32] = [
    0x0623: 0x0627, 0x0625: 0x0627, 0x0622: 0x0627, 0x0671: 0x0627, 0x0649: 0x064A, 0x0626: 0x064A,
    0x0629: 0x0647, 0x0624: 0x0648, 0x06A9: 0x0643, 0x06CC: 0x064A,
  ]

  private static func isArabicMark(_ value: UInt32) -> Bool {
    (0x0610...0x061A).contains(value) || (0x064B...0x065F).contains(value) || value == 0x0670
      || (0x06D6...0x06ED).contains(value) || value == 0x0640
  }

  private static func isLetterOrNumber(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
      .decimalNumber, .letterNumber, .otherNumber:
      return true
    default:
      return false
    }
  }

  /// `normalizeSearch` (src/features/search/normalize.ts): lower case, no
  /// diacritics, one form of each Arabic letter, Western digits, single spaces.
  public static func normalizeSearch(_ text: String) -> String {
    var mapped = String.UnicodeScalarView()
    for scalar in text.decomposedStringWithCompatibilityMapping.unicodeScalars {
      let value = scalar.value
      if (0x0300...0x036F).contains(value) || isArabicMark(value) { continue }
      if let letter = arabicLetters[value], let replaced = Unicode.Scalar(letter) {
        mapped.append(replaced)
      } else if (0x0660...0x0669).contains(value), let digit = Unicode.Scalar(value - 0x0660 + 0x30) {
        mapped.append(digit)
      } else if (0x06F0...0x06F9).contains(value), let digit = Unicode.Scalar(value - 0x06F0 + 0x30) {
        mapped.append(digit)
      } else {
        mapped.append(scalar)
      }
    }
    let lowered = String(mapped).lowercased()
    var out = String.UnicodeScalarView()
    var inGap = false
    for scalar in lowered.unicodeScalars {
      let value = scalar.value
      if (0x200C...0x200F).contains(value) || (0x202A...0x202E).contains(value) || (0x2066...0x2069).contains(value) {
        continue
      }
      let kept = isLetterOrNumber(scalar) || value == 0x2E || value == 0x40 || value == 0x2B || value == 0x2D
      if kept {
        out.append(scalar)
        inGap = false
      } else if !inGap {
        out.append(" ")
        inGap = true
      }
    }
    return WebJS.trim(String(out))
  }

  /// `plateKey`: a plate as it is compared (Latin digits, one case, no spaces or separators).
  public static func plateKey(_ plate: String) -> String {
    WebJS.removing(normalizeSearch(plate)) { scalar in
      WebJS.isSpace(scalar) || scalar.value == 0x2E || scalar.value == 0x40 || scalar.value == 0x2B
        || scalar.value == 0x2D
    }
  }
}

// MARK: Amounts

enum SwMoney {
  /// `round(value, currencyPrecision(currency))` as a number.
  static func round(_ value: Double, currency: String) -> Double {
    Money.toNumber(Money.round(value, Money.precision(currency)))
  }

  /// `Math.round(x)` for the sizes of files.
  static func jsRound(_ value: Double) -> Double {
    (value + 0.5).rounded(.down)
  }
}

// MARK: The register's document types (src/lib/compliance.ts)

/// What the app knows of a type of document (`DOCUMENT_TYPES`).
public struct SwDocType: Sendable {
  /// The English name (a key of `t`).
  public let label: String
  /// Who it usually belongs to: company, employee, vehicle or other.
  public let owner: String
  /// The expense account its renewal fee goes to: government, licence, insurance or rent.
  public let fee: String
  /// Read from the employee record, never stored in the register.
  public let fromEmployee: Bool

  init(_ label: String, _ owner: String, _ fee: String, fromEmployee: Bool = false) {
    self.label = label
    self.owner = owner
    self.fee = fee
    self.fromEmployee = fromEmployee
  }
}

public enum SwDocTypes {
  /// The types, in the web's order.
  public static let order: [String] = [
    "commercial_licence", "commercial_registration", "pam_company_file", "authorised_signatories",
    "pam_salary_certificate", "mof_tax_card", "tax_clearance", "kcci_membership", "municipality_licence",
    "fire_licence", "lease_contract", "civil_id", "passport", "residency", "work_permit", "employment_contract",
    "central_agency_card", "health_insurance", "driving_licence", "vehicle_registration", "vehicle_insurance",
    "company_contract", "client_contract", "customer_cost", "other",
  ]

  private static let other = SwDocType("Other document", "other", "government")

  private static let table: [String: SwDocType] = [
    "commercial_licence": SwDocType("Commercial licence", "company", "licence"),
    "commercial_registration": SwDocType("Commercial registration (CR)", "company", "licence"),
    "pam_company_file": SwDocType("PAM company file", "company", "government"),
    "authorised_signatories": SwDocType("Authorised signatories", "company", "licence"),
    "pam_salary_certificate": SwDocType("PAM salary certificate", "company", "government"),
    "mof_tax_card": SwDocType("MOF tax card", "company", "government"),
    "tax_clearance": SwDocType("Tax clearance certificate", "company", "government"),
    "kcci_membership": SwDocType("KCCI membership", "company", "licence"),
    "municipality_licence": SwDocType("Municipality licence", "company", "licence"),
    "fire_licence": SwDocType("Fire department licence", "company", "licence"),
    "lease_contract": SwDocType("Lease contract", "company", "rent"),
    "civil_id": SwDocType("Civil ID", "employee", "government", fromEmployee: true),
    "passport": SwDocType("Passport", "employee", "government", fromEmployee: true),
    "residency": SwDocType("Residency", "employee", "government", fromEmployee: true),
    "work_permit": SwDocType("Work permit", "employee", "government", fromEmployee: true),
    "employment_contract": SwDocType("Employment contract", "employee", "government", fromEmployee: true),
    "central_agency_card": SwDocType("Central Agency review card", "employee", "government", fromEmployee: true),
    "health_insurance": SwDocType("Health insurance", "employee", "government"),
    "driving_licence": SwDocType("Driving licence", "employee", "government"),
    "vehicle_registration": SwDocType("Vehicle registration", "vehicle", "government"),
    "vehicle_insurance": SwDocType("Vehicle insurance", "vehicle", "insurance"),
    "company_contract": SwDocType("Company contract", "company", "government"),
    "client_contract": SwDocType("Customer contract", "other", "government"),
    "customer_cost": SwDocType("Customer cost sheet", "other", "government"),
    "other": other,
  ]

  /// `documentTypeInfo(type)`: a type a newer version saved is an other document.
  public static func info(_ type: String) -> SwDocType {
    table[type] ?? other
  }

  /// A type this version knows (`isKnown(DOCUMENT_TYPES, type)`).
  public static func isKnown(_ type: String) -> Bool { table[type] != nil }

  /// `EXTRA_DOCUMENT_TYPES`: offered only with the register's extras.
  public static let extraTypes: [String] = ["company_contract", "client_contract", "customer_cost"]

  /// `CUSTOMER_DOCUMENT_TYPES`: a customer's papers, kept under Other with the customer.
  public static let customerTypes: [String] = ["client_contract", "customer_cost"]

  /// `needsTitle`: contracts and cost sheets have no name of their own.
  public static func needsTitle(_ type: String) -> Bool { extraTypes.contains(type) }

  /// `registerTypesFor(owner, extras)`: the types that can be added for an owner.
  public static func registerTypes(for owner: String, extras: Bool) -> [String] {
    order.filter { type in
      let info = info(type)
      if info.fromEmployee { return false }
      if !extras && extraTypes.contains(type) { return false }
      if type == "other" { return true }
      if customerTypes.contains(type) { return owner == "other" }
      return owner == "other" || info.owner == owner
    }
  }

  /// `OWNER_LABELS`, by kind of owner.
  public static func ownerLabel(_ owner: String) -> String {
    switch owner {
    case "company": "Company"
    case "employee": "Employee"
    case "vehicle": "Vehicle"
    default: "Other"
    }
  }

  /// `EMPLOYEE_EXPIRY_FIELDS`: the employee field holding each paper's expiry.
  public static let employeeExpiryFields: [String: String] = [
    "civil_id": "civilIdExpiry", "passport": "passportExpiry", "residency": "residencyExpiry",
    "work_permit": "workPermitExpiry", "employment_contract": "contractEnd", "central_agency_card": "centralCardExpiry",
  ]

  /// `EMPLOYEE_NUMBER_FIELDS`: the employee field holding each paper's number.
  public static let employeeNumberFields: [String: String] = [
    "civil_id": "civilId", "passport": "passportNumber", "residency": "residencyNumber",
    "work_permit": "workPermitNumber", "central_agency_card": "centralCardNumber",
  ]

  /// `recordKey(id)`: a stored document's register key.
  public static func recordKey(_ id: String) -> String { "doc:\(id)" }

  /// `employeeDocumentKey(employeeId, type)`.
  public static func employeeKey(_ employeeId: String, _ type: String) -> String { "emp:\(employeeId):\(type)" }
}

/// The fee accounts of the Kuwait chart (`FEE_ACCOUNT_CODES`, `feeAccountSpec`).
struct SwFeeAccount {
  let code: String
  let name: String
  let nameAr: String
  let type: String

  static func spec(_ fee: String) -> SwFeeAccount {
    switch fee {
    case "licence":
      SwFeeAccount(
        code: "6100", name: "Commercial licence and chamber fees", nameAr: "رسوم الرخصة التجارية والغرفة",
        type: "expense")
    case "insurance": SwFeeAccount(code: "6160", name: "Insurance", nameAr: "التأمين", type: "expense")
    case "rent": SwFeeAccount(code: "6060", name: "Rent", nameAr: "الإيجار", type: "expense")
    default:
      SwFeeAccount(
        code: "6090", name: "Government fees, visas and residency", nameAr: "الرسوم الحكومية والتأشيرات والإقامات",
        type: "expense")
    }
  }
}

// MARK: Reminders and renewals

public enum SwReminders {
  /// `DEFAULT_REMINDER_DAYS`.
  public static let defaultDays: [Double] = [60, 30, 7]

  /// `cleanReminderDays`: whole positive numbers, no repeats, largest first; none stay none.
  public static func clean(_ value: JSONValue?) -> [Double] {
    guard case .some(.array(let items)) = value else { return [] }
    var seen: [Double] = []
    for item in items {
      let number = WebJS.toNumber(item)
      guard number.isFinite else { continue }
      let whole = number < 0 ? (-number).rounded(.down) * -1 : number.rounded(.down)
      if whole > 0 && !seen.contains(whole) { seen.append(whole) }
    }
    return seen.sorted(by: >)
  }

  /// `normalizeReminderDays`: cleaned, or the default days when none are left.
  public static func normalize(_ value: JSONValue?) -> [Double] {
    let days = clean(value)
    return days.isEmpty ? defaultDays : days
  }

  /// "60, 30, 7" as the form reads it (`parseDays`): nil leaves the company's setting.
  public static func parse(_ text: String) -> [Double]? {
    var days: [Double] = []
    var digits = ""
    for character in Money.normalizeDigits(text) + " " {
      if character.isASCII, character.isNumber {
        digits.append(character)
      } else if !digits.isEmpty {
        if let value = Double(digits), value > 0 { days.append(value) }
        digits = ""
      }
    }
    guard !days.isEmpty else { return nil }
    return normalize(.array(days.map { .number($0) }))
  }
}

enum SwRenewalRules {
  /// `latestRenewals`: each register entry's latest renewal, by its key.
  static func latest(_ renewals: [JSONValue]) -> [String: [String: JSONValue]] {
    var latest: [String: [String: JSONValue]] = [:]
    for value in renewals {
      let renewal = SwField.fields(value)
      guard case .some(.string(let key)) = renewal["documentKey"], case .some(.string(let expiry)) = renewal["newExpiry"]
      else { continue }
      if let before = latest[key] {
        let beforeExpiry = SwField.text(before, "newExpiry")
        let later = WebJS.less(beforeExpiry, expiry)
        let sameDay = beforeExpiry == expiry
        let created = WebJS.string(WebJS.present(renewal["createdAt"]) ?? .string(""))
        let createdBefore = WebJS.string(WebJS.present(before["createdAt"]) ?? .string(""))
        if later || (sameDay && WebJS.less(createdBefore, created)) { latest[key] = renewal }
      } else {
        latest[key] = renewal
      }
    }
    return latest
  }
}

// MARK: The books' lock date

enum SwBooks {
  /// `accountingSettings(company).template`.
  static func template(_ company: [String: JSONValue]) -> String {
    if let accounting = company["accounting"], !accounting.isNull {
      return accounting["template"]?.string ?? ""
    }
    let country = company["address"]?["country"]?.string ?? ""
    switch country {
    case "GB": return "uk"
    case "AE": return "ae"
    case "KW", "": return "kw"
    default: return "generic"
    }
  }

  /// `accountingSettings(company).lockDate`.
  static func lockDate(_ company: [String: JSONValue]) -> String? {
    guard let accounting = company["accounting"], !accounting.isNull else { return nil }
    return SwField.id(accounting["lockDate"])
  }

  /// `assertUnlocked(company, ...dates)`: refused when a date falls on or
  /// before the lock date (`LockedPeriodError`), the date written as the
  /// company writes dates.
  static func assertUnlocked(_ company: [String: JSONValue], _ dates: [String?], words: I18n.Translator) throws {
    guard let lock = lockDate(company) else { return }
    let locked = dates.contains { date in
      guard let date, !date.isEmpty else { return false }
      return !WebJS.less(lock, date)
    }
    guard locked else { return }
    let format = Format.DateFormat(rawValue: company["dateFormat"]?.string ?? "")
    let locale = FormatLocale.interface(words.language, companyLocale: company["locale"]?.string)
    let date = Format.date(lock, format: format, locale: locale)
    throw WriteFailure(
      "The books are locked up to {date}. Change the lock date in Settings → Accounting to edit earlier transactions.",
      ["date": date])
  }
}
