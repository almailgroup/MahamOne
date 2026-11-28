import Foundation

/// A renewal's fee (`RenewalFee`).
public struct SwRenewalFee: Sendable, Equatable {
  public var amount: Double
  /// The expense category; nil uses the document type's fee account.
  public var accountId: String?
  /// The bank, cash or card it was paid from; nil uses the bank.
  public var paidFromAccountId: String?
  public var reference: String?

  public init(amount: Double, accountId: String? = nil, paidFromAccountId: String? = nil, reference: String? = nil) {
    self.amount = amount
    self.accountId = accountId
    self.paidFromAccountId = paidFromAccountId
    self.reference = reference
  }
}

/// A file as the web's forms hand it over (`{ name, type, dataUrl }`).
public struct SwFile: Sendable, Equatable {
  public var name: String
  public var type: String
  public var dataUrl: String

  public init(name: String, type: String, dataUrl: String) {
    self.name = name
    self.type = type
    self.dataUrl = dataUrl
  }
}

/// What a file is a copy of (`CopyTag`): a register entry's key, and until when the paper in it is valid.
public struct SwCopyTag: Sendable, Equatable {
  public var docKey: String
  public var validUntil: String?

  public init(docKey: String, validUntil: String?) {
    self.docKey = docKey
    self.validUntil = validUntil
  }
}

/// What `renewDocument` is asked (`RenewInput`).
public struct SwRenewInput: Sendable, Equatable {
  /// The register key ("doc:<id>" or "emp:<employeeId>:<type>").
  public var key: String
  public var newExpiry: String
  /// The day of the renewal (and of the fee's expense).
  public var renewedOn: String
  /// The new document number, when the renewal changes it.
  public var number: String?
  public var note: String?
  public var fee: SwRenewalFee?
  /// The renewed paper's new copy.
  public var copy: SwFile?

  public init(
    key: String, newExpiry: String, renewedOn: String, number: String? = nil, note: String? = nil,
    fee: SwRenewalFee? = nil, copy: SwFile? = nil
  ) {
    self.key = key
    self.newExpiry = newExpiry
    self.renewedOn = renewedOn
    self.number = number
    self.note = note
    self.fee = fee
    self.copy = copy
  }
}

/// The port of the web's renewals (src/db/renewals.ts `renewDocument`, the
/// fee account, the new copies) and of the writes they make on the way:
/// the fee's expense (src/db/purchases.ts `saveExpense`), the fee account
/// (src/db/accounting.ts `saveAccount`) and files (`addAttachment`,
/// `removeAttachment`).
public enum SwRenewals {
  // MARK: Renewing

  /// `renewDocument(input)`: moves a document's expiry date, keeps a record
  /// of the renewal and, with a fee, records it as an expense paid from the
  /// bank or cash. Returns the renewal and the expense.
  @discardableResult
  public static func renew(
    _ ctx: WriteContext, _ input: SwRenewInput, words: I18n.Translator = .english
  ) throws -> (renewal: JSONValue, expense: JSONValue?) {
    guard let company = ctx.get("companies", ctx.companyId)?.object else { throw WriteFailure("Company not found") }
    let companyId = SwField.text(company, "id")
    let number = input.number.map { SwText.trim($0) }
    let typed = number.flatMap { $0.isEmpty ? nil : $0 }

    let type: String
    let previousExpiry: JSONValue
    let currentNumber: String
    var numberField: String?
    var employee: [String: JSONValue]?
    var record: [String: JSONValue]?
    let parts = input.key.components(separatedBy: ":")
    let source = parts.first ?? ""
    let id = parts.count > 1 ? parts[1] : ""
    let field = parts.count > 2 ? parts[2] : ""
    if source == "doc" {
      guard let found = ctx.get("complianceDocuments", id)?.object, found["companyId"] == .string(companyId) else {
        throw WriteFailure("Document not found")
      }
      record = found
      type = SwField.text(found, "type")
      previousExpiry = found["expiryDate"] ?? .null
      currentNumber = SwField.text(found, "number")
      if found["ownerType"] == .string("employee"), let employeeId = SwField.id(found["employeeId"]) {
        employee = ctx.get("employees", employeeId)?.object
      }
    } else if source == "emp", let expiryField = SwDocTypes.employeeExpiryFields[field] {
      guard let found = ctx.get("employees", id)?.object, found["companyId"] == .string(companyId) else {
        throw WriteFailure("Employee not found")
      }
      employee = found
      type = field
      previousExpiry = WebJS.present(found[expiryField]) ?? .null
      numberField = SwDocTypes.employeeNumberFields[field]
      currentNumber = numberField.map { WebJS.string(WebJS.present(found[$0]) ?? .string("")) } ?? ""
    } else {
      throw WriteFailure("Document not found")
    }

    let since = previousExpiry.string ?? input.renewedOn
    if input.newExpiry.isEmpty || !WebJS.less(since, input.newExpiry) {
      throw WriteFailure("The new expiry date must be after the current one.")
    }
    if input.renewedOn.isEmpty { throw WriteFailure("Enter the renewal date.") }

    let currency = SwField.text(company, "currency")
    let feeAmount = SwMoney.round(max(0, input.fee?.amount ?? 0), currency: currency)
    let label = SwDocTypes.info(type).label
    let ownTitle = record.map { SwField.text($0, "title") } ?? ""
    let title = ownTitle.isEmpty ? words.t(label) : ownTitle
    let owner = employee.map { SwField.text($0, "name") } ?? record.map { SwField.text($0, "ownerName") } ?? ""

    var expense: JSONValue?
    if let fee = input.fee, feeAmount > 0 {
      let account: [String: JSONValue]?
      if let accountId = SwField.id(fee.accountId.map { JSONValue.string($0) }) {
        account = ctx.get("accounts", accountId)?.object
      } else {
        account = try ensureFeeAccount(ctx, company: company, type: type)
      }
      guard let account, account["companyId"] == .string(companyId) else { throw WriteFailure("Choose a category.") }
      // Staff and viewers see expenses: an employee's document, or a
      // confidential one, leaves no name, number or note there.
      let unnamed = employee != nil || record.map { SwField.isTrue($0, "confidential") } == true
      let description: String
      if unnamed {
        description = words.t("Document renewal fee")
      } else if !owner.isEmpty {
        description = words.t("{document} renewal – {owner}", ["document": title, "owner": owner])
      } else {
        description = words.t("{document} renewal", ["document": title])
      }
      let reference: String
      if unnamed {
        reference = SwText.trim(fee.reference)
      } else {
        let given = SwText.trim(fee.reference)
        reference = !given.isEmpty ? given : (typed ?? currentNumber)
      }
      let draft = newExpense(
        ctx,
        [
          "date": .string(input.renewedOn), "accountId": account["id"] ?? .null, "amount": .number(feeAmount),
          "currency": .string(currency), "paidFromAccountId": SwField.string(fee.paidFromAccountId),
          "description": .string(description), "reference": .string(reference),
          "notes": .string(unnamed ? "" : SwText.trim(input.note)),
        ])
      expense = try saveExpense(ctx, draft, words: words)
    }

    if var updated = record {
      updated["expiryDate"] = .string(input.newExpiry)
      updated["issueDate"] = .string(input.renewedOn)
      updated["number"] = typed.map { JSONValue.string($0) } ?? (updated["number"] ?? .null)
      if feeAmount > 0 { updated["renewalCost"] = .number(feeAmount) }
      updated["updatedAt"] = .string(ctx.stamp)
      ctx.put("complianceDocuments", .object(updated))
    } else if var updated = employee, let expiryField = SwDocTypes.employeeExpiryFields[type] {
      updated[expiryField] = .string(input.newExpiry)
      if let numberField, let typed { updated[numberField] = .string(typed) }
      updated["updatedAt"] = .string(ctx.stamp)
      ctx.put("employees", .object(updated))
    }

    // The new copy: the file given, or one already marked as this paper's
    // copy valid until the new expiry (filed before the renewal).
    var newCopyId: String?
    if let copy = input.copy {
      guard let ownerId = record.flatMap({ $0["id"]?.string }) ?? employee.flatMap({ $0["id"]?.string }) else {
        throw WriteFailure("Document not found")
      }
      let file = addAttachment(ctx, ownerId: ownerId, file: copy, tag: SwCopyTag(docKey: input.key, validUntil: input.newExpiry))
      newCopyId = file["id"]?.string
    } else {
      let tagged = ctx.all("attachments").filter { $0["docKey"] == .string(input.key) }
      let found = tagged.first { file in
        guard file["companyId"] == .string(companyId), let until = SwField.id(file["validUntil"]) else { return false }
        return !WebJS.less(until, input.newExpiry)
      }
      newCopyId = found?["id"]?.string
    }

    var renewal: [String: JSONValue] = [
      "id": .string(ctx.newId()), "companyId": .string(companyId), "documentKey": .string(input.key),
      "documentId": record?["id"] ?? .null, "employeeId": employee?["id"] ?? .null, "type": .string(type),
      "renewedOn": .string(input.renewedOn), "previousExpiry": previousExpiry, "newExpiry": .string(input.newExpiry),
      "fee": .number(feeAmount), "expenseId": expense?["id"] ?? .null, "note": .string(SwText.trim(input.note)),
      "number": .string(typed ?? currentNumber), "createdAt": .string(ctx.stamp),
    ]
    if let newCopyId, !newCopyId.isEmpty { renewal["newCopyId"] = .string(newCopyId) }
    ctx.put("renewals", .object(renewal))
    ctx.logActivity(
      entity: "compliance", entityId: renewal["id"]?.string ?? "", action: "renewed",
      message: ActivityMessage(
        owner.isEmpty ? "{document} renewed until {date}" : "{document} of {owner} renewed until {date}",
        vars: ["document": title, "owner": owner, "date": input.newExpiry]),
      refs: ActivityRefs(
        employeeId: employee.flatMap { SwField.id($0["id"]) },
        confidential: record.map { SwField.isTrue($0, "confidential") } ?? false))
    return (.object(renewal), expense)
  }

  // MARK: The fee account

  /// `findFeeAccount(accounts, company, type)`: by name, or by code in a
  /// company on the Kuwait chart.
  public static func findFeeAccount(_ accounts: [JSONValue], company: JSONValue, type: String) -> JSONValue? {
    let spec = SwFeeAccount.spec(SwDocTypes.info(type).fee)
    let fields = SwField.fields(company)
    // Active accounts first, in their order otherwise (a stable sort).
    let ordered =
      accounts.filter { WebJS.toNumber($0["archived"]) == 0 || WebJS.toNumber($0["archived"]).isNaN }
      + accounts.filter { WebJS.toNumber($0["archived"]) != 0 && !WebJS.toNumber($0["archived"]).isNaN }
    let sameName = { (account: JSONValue) -> Bool in
      let name = SwText.trim(account["name"]?.string).lowercased()
      if name == spec.name.lowercased() { return true }
      guard let nameAr = account["nameAr"]?.string else { return false }
      return SwText.trim(nameAr) == spec.nameAr
    }
    if let found = ordered.first(where: sameName) { return found }
    guard SwBooks.template(fields) == "kw" else { return nil }
    return ordered.first { $0["code"] == .string(spec.code) && $0["type"] == .string(spec.type) }
  }

  /// The fee account of a type of document as the Kuwait chart names it (`feeAccountSpec`).
  public static func feeAccountName(type: String) -> (name: String, nameAr: String) {
    let spec = SwFeeAccount.spec(SwDocTypes.info(type).fee)
    return (spec.name, spec.nameAr)
  }

  /// `ensureFeeAccount(company, type)`: the fee account, created from the
  /// Kuwait chart when the company doesn't have it.
  static func ensureFeeAccount(_ ctx: WriteContext, company: [String: JSONValue], type: String) throws -> [String: JSONValue] {
    let companyId = company["id"] ?? .null
    let accounts = ctx.all("accounts").filter { $0["companyId"] == companyId }
    if let found = findFeeAccount(accounts, company: .object(company), type: type)?.object { return found }
    let spec = SwFeeAccount.spec(SwDocTypes.info(type).fee)
    let codes = Set(accounts.map { WebJS.string($0["code"]) })
    var code = spec.code
    var next = (Int(spec.code) ?? 0) + 1
    while codes.contains(code) {
      code = String(next)
      next += 1
    }
    let stamp = ctx.stamp
    let account: [String: JSONValue] = [
      "id": .string(ctx.newId()), "companyId": companyId, "code": .string(code), "name": .string(spec.name),
      "type": .string(spec.type), "description": "", "role": .null, "bank": .null, "archived": false,
      "createdAt": .string(stamp), "updatedAt": .string(stamp), "nameAr": .string(spec.nameAr),
    ]
    return try saveNewAccount(ctx, account)
  }

  /// `saveAccount` for an account made here (a chart's account: no bank
  /// details, no role): code and name trimmed, the code free, logged.
  static func saveNewAccount(_ ctx: WriteContext, _ input: [String: JSONValue]) throws -> [String: JSONValue] {
    var account = input
    let nameAr = input["nameAr"]?.string.map { SwText.trim($0) }
    account.removeValue(forKey: "nameAr")
    account["code"] = .string(SwText.trim(input["code"]?.string))
    account["name"] = .string(SwText.trim(input["name"]?.string))
    if let nameAr, !nameAr.isEmpty { account["nameAr"] = .string(nameAr) }
    account["bank"] = .null
    let code = SwField.text(account, "code")
    let name = SwField.text(account, "name")
    if name.isEmpty { throw WriteFailure("Enter a name for the account.") }
    if code.isEmpty { throw WriteFailure("Enter a code for the account.") }
    let id = account["id"]
    let sameCode = ctx.all("accounts").contains {
      $0["companyId"] == account["companyId"] && $0["code"] == .string(code) && $0["id"] != id
    }
    if sameCode { throw WriteFailure("Code {code} is already used by another account.", ["code": code]) }
    let existing = ctx.get("accounts", SwField.text(account, "id"))?.object
    account["updatedAt"] = .string(ctx.stamp)
    ctx.put("accounts", .object(account))
    let vars = ["code": code, "name": name]
    ctx.logActivity(
      entity: "account", entityId: SwField.text(account, "id"), action: existing != nil ? "updated" : "created",
      message: ActivityMessage(
        existing != nil ? "Account {code} {name} updated" : "Account {code} {name} created", vars: vars,
        arabic: ["name": account["nameAr"]?.string]))
    return account
  }

  // MARK: The fee's expense

  /// `createExpense(companyId, overrides)`.
  static func newExpense(_ ctx: WriteContext, _ overrides: [String: JSONValue]) -> [String: JSONValue] {
    let stamp = ctx.stamp
    var fields: [String: JSONValue] = [
      "id": .string(ctx.newId()), "companyId": .string(ctx.companyId), "number": "", "date": .string(ctx.today),
      "vendorId": .null, "accountId": "", "description": "", "amount": 0, "taxes": [], "currency": "",
      "paidFromAccountId": .null, "reference": "", "notes": "", "createdAt": .string(stamp), "updatedAt": .string(stamp),
    ]
    for (key, value) in overrides { fields[key] = value }
    return fields
  }

  /// `saveExpense(input)` for a new expense made here (the renewal's fee):
  /// the books' lock, the amount and its category checked, numbered when it
  /// has no number, logged.
  static func saveExpense(_ ctx: WriteContext, _ input: [String: JSONValue], words: I18n.Translator) throws -> JSONValue {
    guard var company = ctx.get("companies", SwField.text(input, "companyId"))?.object else {
      throw WriteFailure("Company not found")
    }
    let existing = ctx.get("expenses", SwField.text(input, "id"))?.object
    try SwBooks.assertUnlocked(company, [input["date"]?.string, existing?["date"]?.string], words: words)
    let given = SwField.text(input, "currency")
    let currency = given.isEmpty ? SwField.text(company, "currency") : given
    let amount = SwMoney.round(WebJS.toNumber(input["amount"]), currency: currency)
    if !(amount > 0) { throw WriteFailure("Enter the amount paid.") }
    let account = SwField.id(input["accountId"]).flatMap { ctx.get("accounts", $0)?.object }
    if account == nil || account?["companyId"] != company["id"] { throw WriteFailure("Choose a category.") }

    var expense = input
    expense["currency"] = .string(currency)
    expense["amount"] = .number(amount)
    expense["number"] = .string(SwText.trim(input["number"]?.string))
    expense["updatedAt"] = .string(ctx.stamp)
    let payee = input["payee"]?.string.map { SwText.trim($0) } ?? ""
    if !payee.isEmpty && !WebJS.truthy(input["vendorId"]) {
      expense["payee"] = .string(payee)
    } else {
      expense.removeValue(forKey: "payee")
    }
    if SwField.text(expense, "number").isEmpty {
      let stored = WebJS.present(company["numbering"]?["expense"])
      let rule = NumberingRule(stored ?? (Defaults.defaultNumbering()["expense"] ?? .null))
      let expenseId = expense["id"]
      let taken = Set(
        ctx.all("expenses")
          .filter { $0["companyId"] == company["id"] && $0["id"] != expenseId }
          .map { ($0["number"]?.string ?? "").lowercased() })
      let date = SwField.text(expense, "date")
      let allocated = Numbering.allocateNumber(rule, date) { taken.contains($0.lowercased()) }
      expense["number"] = .string(allocated.number)
      var numbering = WebJS.spread(company["numbering"])
      numbering["expense"] = allocated.rule.raw
      company["numbering"] = .object(numbering)
      ctx.put("companies", .object(company))
    }
    if existing == nil { expense["createdAt"] = expense["updatedAt"] }
    ctx.put("expenses", .object(expense))
    let number = SwField.text(expense, "number")
    let shown = Format.money(amount, currency: currency, locale: FormatLocale(SwField.text(company, "locale")))
    ctx.logActivity(
      entity: "expense", entityId: SwField.text(expense, "id"), action: existing != nil ? "updated" : "created",
      message: ActivityMessage(
        existing != nil ? "Expense {number} of {amount} updated" : "Expense {number} of {amount} recorded",
        vars: ["number": number, "amount": shown], money: ["amount": (amount: amount, currency: currency)]))
    return .object(expense)
  }

  // MARK: Files

  /// `addAttachment(companyId, ownerId, file, tag)`: a file kept with a
  /// record, marked as the copy of a paper when `tag` is given.
  @discardableResult
  public static func addAttachment(_ ctx: WriteContext, ownerId: String, file: SwFile, tag: SwCopyTag? = nil) -> JSONValue {
    var attachment: [String: JSONValue] = [
      "id": .string(ctx.newId()), "companyId": .string(ctx.companyId), "ownerId": .string(ownerId),
      "name": .string(file.name), "type": .string(file.type),
      // Data URL length is a good-enough size estimate for display.
      "size": .number(SwMoney.jsRound(Double(file.dataUrl.utf16.count) * 3 / 4)),
      "dataUrl": .string(file.dataUrl),
    ]
    if let tag {
      attachment["docKey"] = .string(tag.docKey)
      attachment["validUntil"] = SwField.string(tag.validUntil)
    }
    attachment["createdAt"] = .string(ctx.stamp)
    ctx.put("attachments", .object(attachment))
    return .object(attachment)
  }

  /// `removeAttachment(id)`: removes a file; an employee's photo and an
  /// item's pictures go with it, so nothing points at a file that's gone.
  public static func removeAttachment(_ ctx: WriteContext, id: String) {
    let attachment = ctx.get("attachments", id)?.object
    ctx.delete("attachments", id)
    guard let attachment else { return }
    let ownerId = SwField.text(attachment, "ownerId")
    if var employee = ctx.get("employees", ownerId)?.object, employee["photoId"] == .string(id) {
      employee["photoId"] = .null
      employee["updatedAt"] = .string(ctx.stamp)
      ctx.put("employees", .object(employee))
    }
    if var product = ctx.get("products", ownerId)?.object,
      let images = product["imageIds"]?.array, images.contains(.string(id))
    {
      // `withoutImage`: the rest of its pictures, five at most; none leaves the field out.
      let rest = Array(images.filter { $0 != .string(id) }.prefix(5))
      product.removeValue(forKey: "imageIds")
      if !rest.isEmpty { product["imageIds"] = .array(rest) }
      product["updatedAt"] = .string(ctx.stamp)
      ctx.put("products", .object(product))
    }
  }

  // MARK: New copies

  /// `linkNewCopy`: the latest renewal of a paper points at its new copy
  /// once a file is marked as that paper's copy valid until the new expiry;
  /// a file that no longer is one stops being any renewal's.
  static func linkNewCopy(_ ctx: WriteContext, file: [String: JSONValue], tag: SwCopyTag?, added: Bool = false) {
    let fileId = file["id"] ?? .null
    let companyId = file["companyId"] ?? .null
    let linked =
      added
      ? []
      : ctx.all("renewals").compactMap(\.object).filter { $0["companyId"] == companyId && $0["newCopyId"] == fileId }
    for renewal in linked {
      if let tag, renewal["documentKey"] == .string(tag.docKey),
        !WebJS.less(tag.validUntil ?? "", SwField.text(renewal, "newExpiry"))
      {
        continue
      }
      var cleared = renewal
      cleared["newCopyId"] = .null
      ctx.put("renewals", .object(cleared))
    }
    guard let tag, let validUntil = tag.validUntil, !validUntil.isEmpty else { return }
    let renewals = ctx.all("renewals").filter { $0["documentKey"] == .string(tag.docKey) && $0["companyId"] == companyId }
    guard let latest = SwRenewalRules.latest(renewals)[tag.docKey] else { return }
    if latest["newCopyId"] == fileId || WebJS.less(validUntil, SwField.text(latest, "newExpiry")) { return }
    let kept = SwField.id(latest["newCopyId"]).map { ctx.get("attachments", $0) != nil } ?? false
    if !kept {
      var linkedNow = latest
      linkedNow["newCopyId"] = fileId
      ctx.put("renewals", .object(linkedNow))
    }
  }

  /// `addNewCopy(companyId, ownerId, file, tag)`: a file added to a record as the copy of one of the company's papers.
  @discardableResult
  public static func addNewCopy(_ ctx: WriteContext, ownerId: String, file: SwFile, tag: SwCopyTag) -> JSONValue {
    let added = addAttachment(ctx, ownerId: ownerId, file: file, tag: tag)
    linkNewCopy(ctx, file: SwField.fields(added), tag: tag, added: true)
    return added
  }

  /// `markNewCopy(fileId, tag)`: a file kept with a record marked as the
  /// copy of one of the company's papers, valid until a date, or (`tag`
  /// nil) as nothing in particular.
  public static func markNewCopy(_ ctx: WriteContext, fileId: String, tag: SwCopyTag?) throws {
    guard let file = ctx.get("attachments", fileId)?.object else { throw WriteFailure("File not found") }
    let sameKey = (WebJS.present(file["docKey"]) ?? .null) == SwField.string(tag?.docKey)
    let sameDate = (WebJS.present(file["validUntil"]) ?? .null) == SwField.string(tag?.validUntil)
    if sameKey && sameDate { return }
    var next = file
    next.removeValue(forKey: "docKey")
    next.removeValue(forKey: "validUntil")
    if let tag {
      next["docKey"] = .string(tag.docKey)
      next["validUntil"] = SwField.string(tag.validUntil)
    }
    ctx.put("attachments", .object(next))
    linkNewCopy(ctx, file: next, tag: tag)
  }
}
