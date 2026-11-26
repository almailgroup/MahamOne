import Foundation
import MahamKit

// The general ledger, as the web derives it (`src/lib/accounting/ledger.ts`
// and the document maths of `src/lib/calc.ts` / `document-calc.ts`): every
// issued invoice, credit note, bill, vendor credit, payment, expense, stock
// entry, stock issue and posted journal turns into balanced debit/credit
// lines in integer minor units (fils) of the company currency. Nothing here
// touches the interface; it reads raw records and is deterministic.

// MARK: What the ledger is made of

/// Where a ledger line comes from (`LedgerSource`).
enum AcSource: String, Sendable, CaseIterable {
  case invoice, credit, bill
  case vendorCredit = "vendor_credit"
  case payment, expense, journal, stock, issue

  /// `SOURCE_LABELS`: an English key, shown with `t(_:)`.
  var label: String {
    switch self {
    case .invoice: "Invoice"
    case .credit: "Credit note"
    case .bill: "Bill"
    case .vendorCredit: "Vendor credit"
    case .payment: "Payment"
    case .expense: "Expense"
    case .journal: "Journal"
    case .stock: "Stock entry"
    case .issue: "Items issued"
    }
  }
}

/// What a line means for VAT returns (`VatTag`): the value of a sale or
/// purchase, or the tax on it, and how that tax is reported.
struct AcVatTag: Sendable, Hashable {
  /// "sale" or "purchase".
  let flow: String
  /// "base" or "tax".
  let part: String
  /// A tax kind, or "none" when no tax was chosen.
  let kind: String
  let rate: Double
}

/// Wording the ledger made up (`LedgerLabel`): an English key and its values;
/// `terms` names values that are English keys themselves.
struct AcLabel: Sendable {
  let text: String
  var vars: [String: String] = [:]
  var terms: [String] = []

  /// In the interface language (`labelText`).
  func translated() -> String {
    var shown = vars
    for term in terms {
      if let value = shown[term], !value.isEmpty { shown[term] = t(value) }
    }
    return t(text, shown)
  }
}

/// A line's description and the label it was made from.
struct AcText: Sendable {
  let description: String
  let label: AcLabel?

  /// `described`: generated wording, kept as a key and its values.
  static func described(_ text: String, _ vars: [String: String]) -> AcText {
    AcText(description: interpolate(text, vars), label: AcLabel(text: text, vars: vars))
  }

  /// What people typed, kept as it is.
  static func plain(_ text: String) -> AcText {
    AcText(description: text, label: nil)
  }
}

/// One line of the general ledger (`LedgerLine`). `amount` is in minor
/// units of the company currency; positive is a debit, negative a credit.
struct AcLine: Sendable {
  var date: String
  var accountId: String
  var amount: Int
  var source: AcSource
  var sourceId: String
  /// Document number shown in reports, e.g. "INV-2026-0001".
  var number: String
  var contactId: String?
  /// In English; show `text`.
  var description: String
  var label: AcLabel?
  var vat: AcVatTag?
  /// Part of the entry that closes a VAT return.
  var settlement = false

  /// `lineDescription`: generated wording in the interface language.
  var text: String { label?.translated() ?? description }
}

/// Something that could not be posted (`LedgerProblem`).
struct AcProblem: Sendable {
  let source: AcSource
  let sourceId: String
  let number: String
  let message: String
  let label: AcLabel?

  /// `problemText`.
  var text: String { label?.translated() ?? message }
}

/// An entry that cannot be posted (`LedgerError`).
struct AcLedgerError: Error {
  let message: String
  let label: AcLabel

  static func unbalanced(_ message: String) -> AcLedgerError {
    AcLedgerError(message: message, label: AcLabel(text: "This entry does not balance."))
  }
}

/// What the ledger needs to know about the company (`LedgerContext`).
struct AcLedgerContext: Sendable {
  var companyCurrency: String
  /// Minor-unit digits of the company currency.
  var precision: Int
  /// Account used for each automatic posting.
  var roles: [String: String]
  /// Accounts that exist.
  var accountIds: Set<String>
  /// Each product's income account (`incomeAccountId`).
  var productAccounts: [String: String]
  /// Clients marked tax exempt.
  var exemptClients: Set<String>
  /// Every document by id.
  var documents: [String: JSONValue]
  var stock: AcStockContext?
  var retentionReceivable: String?
  var retentionPayable: String?
  /// What each payment clears from a foreign-currency document (`documentClearing`).
  var clearing: [String: Int]?
}

/// The accounts and items the stock postings need (`StockLedgerContext`).
struct AcStockContext: Sendable {
  var products: Set<String>
  var inventoryAccountId: String?
  var costOfSalesAccountId: String?
  var adjustmentAccountId: String?
  var issuedItemsAccountId: String?
  /// Bill lines and charges allocated as landed costs, as "billId:lineId".
  var landedCostLines: Set<String>
}

// MARK: Taxes

/// A tax on a line, a document or a charge (`TaxLine`).
struct AcTax: Sendable {
  let name: String
  let rate: Double?
  let kind: String?

  init(_ value: JSONValue) {
    name = value.str("name")
    rate = value.number("rate")
    kind = value.text("kind")
  }

  var rateValue: Double { rate ?? 0 }
  var isReverseCharge: Bool { kind == "reverse_charge" }

  /// `taxKind`: the tax's kind, guessed from rate and name for older records.
  var reportedKind: String {
    if let kind { return kind }
    if rateValue > 0 { return "standard" }
    return name.range(of: "exempt", options: .caseInsensitive) != nil ? "exempt" : "zero"
  }

  /// `validTaxes`: a name and a finite rate.
  var isValid: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (rate?.isFinite ?? false)
  }

  /// `taxKey`: a reverse charge never merges with an ordinary rate of the same name.
  var key: String {
    let base = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + "|" + Money.jsString(rateValue)
    return isReverseCharge ? base + "|rc" : base
  }

  static func list(_ values: [JSONValue]) -> [AcTax] { values.map(AcTax.init) }
}

// MARK: Document maths (calc.ts)

/// The results of `calculate` the ledger and reports use; amounts are
/// rounded to the currency as the web rounds them.
struct AcCalcResult: Sendable {
  /// Each line's net amount (0 for headings), in `items` order.
  var lineNets: [Decimal]
  var subtotal: Decimal
  var discount: Decimal
  var chargesTotal: Decimal
  var taxes: [AcTaxSummary]
  var taxTotal: Decimal
  var netTotal: Decimal
  var total: Decimal
  var retention: Decimal
}

/// One tax of a document, grouped by name and rate (`TaxSummary`).
struct AcTaxSummary: Sendable {
  let key: String
  let name: String
  let rate: Double
  let kind: String
  let base: Decimal
  let amount: Decimal
}

enum AcCalc {
  /// `computeDocument(doc, { taxExempt })`.
  static func compute(_ doc: JSONValue, taxExempt: Bool) -> AcCalcResult {
    let type = doc.str("type")
    let currency = doc.text("currency") ?? "KWD"
    let takesRetention = type == "invoice" || type == "bill"
    return calculate(
      items: doc.list("items"), discount: doc.num("discount"),
      discountType: doc["discountType"]?.string ?? "percent",
      taxes: taxExempt ? [] : AcTax.list(doc.list("taxes")),
      charges: doc.list("charges"), chargesTaxed: !taxExempt, itemsTaxed: !taxExempt,
      inclusive: doc.flag("pricesIncludeTax"), precision: Money.precision(currency),
      retentionPercent: takesRetention ? (doc.number("retentionPercent") ?? 0) : 0)
  }

  /// `releasedRetention`: releases that were not undone, in the document currency.
  static func releasedRetention(_ doc: JSONValue) -> Decimal {
    let p = Money.precision(doc.text("currency") ?? "KWD")
    var sum = Decimal(0)
    for release in doc.list("retentionReleases") where release.text("reversedOn") == nil {
      sum += Money.dec(release.num("amount"))
    }
    return Money.round(sum, p)
  }

  /// `retentionOf`: `percent` of the total, rounded to the currency.
  static func retentionOf(_ total: Decimal, _ percent: Double, _ p: Int) -> Decimal {
    let rate = percent.isFinite ? min(max(percent, 0), 100) : 0
    if rate == 0 { return 0 }
    let amount = Money.round(total * Money.dec(rate) / 100, p)
    return amount > 0 ? amount : 0
  }

  private struct Bucket {
    let name: String
    let rate: Double
    let kind: String
    var base: Decimal
    var amount: Decimal
  }

  /// `calculate`, keeping its rounding order: each line's net is rounded, the
  /// document discount is spread into each line's tax base, taxes are rounded
  /// once per group, charges are taxed but not discounted.
  static func calculate(
    items: [JSONValue], discount discountInput: Double, discountType: String, taxes docTaxesInput: [AcTax],
    charges: [JSONValue], chargesTaxed: Bool, itemsTaxed: Bool, inclusive: Bool, precision: Int,
    retentionPercent: Double
  ) -> AcCalcResult {
    let p = max(0, min(6, precision))
    let docTaxes = docTaxesInput.filter(\.isValid)
    var keys: [String] = []
    var buckets: [String: Bucket] = [:]

    func addTax(_ tax: AcTax, _ base: Decimal, _ amount: Decimal) {
      let key = tax.key
      if var bucket = buckets[key] {
        bucket.base += base
        bucket.amount += amount
        buckets[key] = bucket
      } else {
        keys.append(key)
        buckets[key] = Bucket(
          name: tax.name.trimmingCharacters(in: .whitespacesAndNewlines), rate: tax.rateValue,
          kind: tax.reportedKind, base: base, amount: amount)
      }
    }

    func applyTaxes(_ amount: Decimal, _ taxes: [AcTax]) {
      if taxes.isEmpty { return }
      var rateSum = Decimal(0)
      for tax in taxes where !tax.isReverseCharge { rateSum += Money.dec(tax.rateValue) }
      let base = inclusive ? amount / (rateSum / 100 + 1) : amount
      for tax in taxes {
        addTax(tax, base, base * Money.dec(tax.rateValue) / 100)
      }
    }

    // 1. Line amounts.
    var lineNets: [Decimal] = []
    for item in items {
      if item.str("kind") == "heading" {
        lineNets.append(0)
        continue
      }
      let grossRaw = Money.dec(item.num("quantity")) * Money.dec(item.num("unitPrice"))
      let discountValue = Money.dec(item.num("discount"))
      let percent = (item["discountType"]?.string ?? "percent") == "percent"
      let discountRaw = percent ? grossRaw * discountValue / 100 : discountValue
      lineNets.append(Money.round(grossRaw - discountRaw, p))
    }
    var subtotal = Decimal(0)
    for net in lineNets { subtotal += net }

    // 2. Document discount.
    let discountValue = Money.dec(discountInput)
    let discount = Money.round(discountType == "percent" ? subtotal * discountValue / 100 : discountValue, p)
    let ratio = subtotal.isZero ? Decimal(1) : (subtotal - discount) / subtotal

    // 3. Taxes on lines (line taxes plus document taxes).
    for (index, item) in items.enumerated() where item.str("kind") != "heading" {
      let own = itemsTaxed ? AcTax.list(item.list("taxes")).filter(\.isValid) : []
      applyTaxes(lineNets[index] * ratio, own + docTaxes)
    }

    // 4. Charges.
    var chargesTotal = Decimal(0)
    for charge in charges {
      let amount = Money.round(charge.num("amount"), p)
      chargesTotal += amount
      applyTaxes(amount, chargesTaxed ? AcTax.list(charge.list("taxes")).filter(\.isValid) : [])
    }

    // 5. Round once per tax group, then total.
    var summaries: [AcTaxSummary] = []
    var taxTotal = Decimal(0)
    for key in keys {
      guard let bucket = buckets[key] else { continue }
      let amount = Money.round(bucket.amount, p)
      summaries.append(
        AcTaxSummary(
          key: key, name: bucket.name, rate: bucket.rate, kind: bucket.kind, base: Money.round(bucket.base, p),
          amount: amount))
      if bucket.kind != "reverse_charge" { taxTotal += amount }
    }
    let afterDiscount = subtotal - discount + chargesTotal
    let total = inclusive ? afterDiscount : afterDiscount + taxTotal
    let netTotal = total - taxTotal
    let retention = retentionOf(Money.round(total, p), retentionPercent, p)
    return AcCalcResult(
      lineNets: lineNets, subtotal: Money.round(subtotal, p), discount: Money.round(discount, p),
      chargesTotal: Money.round(chargesTotal, p), taxes: summaries, taxTotal: Money.round(taxTotal, p),
      netTotal: Money.round(netTotal, p), total: Money.round(total, p), retention: Money.round(retention, p))
  }
}

// MARK: Posting

enum AcLedger {
  /// `PAYMENT_POSTING_RULES`.
  static let paymentPostingRules = 2.0

  /// What the accounts of each role hold, for "no account is set up" problems.
  static func roleName(_ role: String) -> String {
    switch role {
    case "receivable": "Money owed by clients"
    case "payable": "Money owed to vendors"
    case "bank": "Bank"
    case "cash": "Cash payments"
    case "credit_card": "Company card"
    case "sales": "Sales"
    case "charges": "Delivery and other charges"
    case "output_tax": "Tax charged on sales"
    case "input_tax": "Tax paid on purchases"
    case "tax_settlement": "VAT owed to (or due from) the tax office"
    case "fx": "Exchange gains and losses"
    case "capital": "Owner or share capital"
    case "drawings": "Drawings"
    case "retained_earnings": "Retained earnings"
    case "opening_balance": "Opening balances"
    case "cost_of_sales": "Cost of sales"
    case "expense": "Expenses"
    case "bank_fees": "Bank charges"
    default: role
    }
  }

  /// Minor units, half away from zero.
  static func minor(_ value: Decimal, _ places: Int = 0) -> Int {
    Int(Money.toMinor(value, places))
  }

  static func minor(_ value: Double, _ places: Int) -> Int {
    Int(Money.toMinor(value, places))
  }

  /// Company-currency value of one unit of the record's currency (`rateOf`).
  static func rateOf(_ item: JSONValue, _ companyCurrency: String) -> Double {
    if item.str("currency") == companyCurrency { return 1 }
    if let rate = item.number("exchangeRate"), rate.isFinite, rate > 0 { return rate }
    return 1
  }

  static func needsRate(_ item: JSONValue, _ companyCurrency: String) -> Bool {
    if item.str("currency") == companyCurrency { return false }
    if let rate = item.number("exchangeRate"), rate.isFinite, rate > 0 { return false }
    return true
  }

  /// Invoices, credit notes, bills and vendor credits post to the ledger.
  static func postsToLedger(_ type: String) -> Bool {
    type == "invoice" || type == "credit" || type == "bill" || type == "vendor_credit"
  }

  /// Issued and not void (`isPosted`).
  static func isPosted(_ doc: JSONValue) -> Bool {
    guard postsToLedger(doc.str("type")) else { return false }
    let status = doc.str("status")
    return status != "draft" && status != "void"
  }

  /// `postingTaxExempt`: as fixed when issued, else as the contact is now.
  static func postingTaxExempt(_ doc: JSONValue, _ ctx: AcLedgerContext) -> Bool {
    if let posting = doc.obj("posting") { return posting.flag("taxExempt") }
    guard let client = doc.text("clientId") else { return false }
    return ctx.exemptClients.contains(client)
  }

  static func role(_ ctx: AcLedgerContext, _ name: String, _ fallback: String? = nil) throws -> String {
    if let id = ctx.roles[name] { return id }
    if let fallback, let id = ctx.roles[fallback] { return id }
    throw AcLedgerError(
      message: "No account is set up for \"\(name)\".",
      label: AcLabel(
        text: "No account is set up for “{account}”. Choose one in the accounting settings.",
        vars: ["account": roleName(name)], terms: ["account"]))
  }

  static func usable(_ ctx: AcLedgerContext, _ id: String?) -> String? {
    guard let id, !id.isEmpty, ctx.accountIds.contains(id) else { return nil }
    return id
  }

  /// `allocate`: splits `total` minor units over weights; the remainder goes
  /// to the largest weight, so the parts always add up exactly.
  static func allocate(_ total: Int, _ weights: [Decimal]) -> [Int] {
    if weights.isEmpty { return [] }
    var sum = Decimal(0)
    for weight in weights { sum += weight }
    if sum.isZero { return weights.indices.map { $0 == 0 ? total : 0 } }
    var parts = weights.map { minor(Decimal(total) * $0 / sum) }
    let diff = total - parts.reduce(0, +)
    if diff != 0 {
      var largest = 0
      for (index, weight) in weights.enumerated() where abs(weight) > abs(weights[largest]) { largest = index }
      parts[largest] += diff
    }
    return parts
  }

  static func balanced(_ lines: [AcLine]) -> Bool {
    lines.reduce(0) { $0 + $1.amount } == 0
  }

  /// "VAT 5% reverse charge".
  static func reverseChargeText(_ name: String, _ rate: Double) -> AcText {
    .described("{tax} {rate}% reverse charge", ["tax": name, "rate": Money.jsString(rate)])
  }

  static func rateProblem(_ source: AcSource, _ id: String, _ number: String, _ currency: String) -> AcProblem {
    AcProblem(
      source: source, sourceId: id, number: number, message: "No exchange rate for \(currency); 1:1 was used.",
      label: AcLabel(text: "No exchange rate for {currency}; 1:1 was used.", vars: ["currency": currency]))
  }

  // MARK: Documents

  /// How a document type posts (`POSTING`).
  struct Rule {
    let partner: String
    let tax: String
    let line: String
    let charges: String
    let sign: Int
    let numbered: String

    static func of(_ type: String) -> Rule? {
      switch type {
      case "invoice":
        Rule(
          partner: "receivable", tax: "output_tax", line: "sales", charges: "charges", sign: 1,
          numbered: "Invoice {number}")
      case "credit":
        Rule(
          partner: "receivable", tax: "output_tax", line: "sales", charges: "charges", sign: -1,
          numbered: "Credit note {number}")
      case "bill":
        Rule(
          partner: "payable", tax: "input_tax", line: "expense", charges: "expense", sign: -1,
          numbered: "Bill {number}")
      case "vendor_credit":
        Rule(
          partner: "payable", tax: "input_tax", line: "expense", charges: "expense", sign: 1,
          numbered: "Vendor credit {number}")
      default: nil
      }
    }
  }

  /// A line or charge with its share of the net amount (`WeighedEntry`).
  struct Weighed {
    let id: String
    let isCharge: Bool
    let index: Int
    let weight: Decimal
    let taxes: [AcTax]
    let label: String
    let productId: String?
    let accountId: String?
  }

  /// A charged tax in minor units.
  struct MinorTax {
    let name: String
    let rate: Double
    let kind: String
    let minor: Int
  }

  struct Weighing {
    let exempt: Bool
    let total: Int
    let retention: Int
    let chargedTaxes: [MinorTax]
    let reverseTaxes: [MinorTax]
    let income: Int
    let entries: [Weighed]
  }

  /// `weighDocument`.
  static func weigh(_ doc: JSONValue, _ ctx: AcLedgerContext) -> Weighing {
    let exempt = postingTaxExempt(doc, ctx)
    let result = AcCalc.compute(doc, taxExempt: exempt)
    let rate = Money.dec(rateOf(doc, ctx.companyCurrency))
    let p = ctx.precision
    let total = minor(result.total * rate, p)
    let retention = minor(result.retention * rate, p)
    var charged: [MinorTax] = []
    var reverse: [MinorTax] = []
    for tax in result.taxes {
      let value = MinorTax(name: tax.name, rate: tax.rate, kind: tax.kind, minor: minor(tax.amount * rate, p))
      if tax.kind == "reverse_charge" { reverse.append(value) } else { charged.append(value) }
    }
    let income = total - charged.reduce(0) { $0 + $1.minor }
    let ratio = result.subtotal.isZero ? Decimal(1) : (result.subtotal - result.discount) / result.subtotal
    func rateSum(_ list: [AcTax]) -> Decimal {
      var sum = Decimal(0)
      for tax in list { sum += Money.dec(tax.rateValue) }
      return sum / 100 + 1
    }
    let docTaxes = exempt ? [] : AcTax.list(doc.list("taxes"))
    let inclusive = doc.flag("pricesIncludeTax")
    var entries: [Weighed] = []
    for (index, item) in doc.list("items").enumerated() where item.str("kind") != "heading" {
      let taxes = exempt ? [] : AcTax.list(item.list("taxes")) + docTaxes
      let net = index < result.lineNets.count ? result.lineNets[index] : 0
      var weight = net * ratio
      let chargedTaxes = taxes.filter { !$0.isReverseCharge }
      if inclusive, !chargedTaxes.isEmpty { weight = weight / rateSum(chargedTaxes) }
      entries.append(
        Weighed(
          id: item.str("id"), isCharge: false, index: index, weight: weight, taxes: taxes, label: item.str("name"),
          productId: item.text("productId"), accountId: item.text("accountId")))
    }
    for (index, charge) in doc.list("charges").enumerated() {
      let taxes = exempt ? [] : AcTax.list(charge.list("taxes"))
      var weight = Money.dec(charge.num("amount"))
      let chargedTaxes = taxes.filter { !$0.isReverseCharge }
      if inclusive, !chargedTaxes.isEmpty { weight = weight / rateSum(chargedTaxes) }
      entries.append(
        Weighed(
          id: charge.str("id"), isCharge: true, index: index, weight: weight, taxes: taxes,
          label: charge.str("label"), productId: nil, accountId: nil))
    }
    return Weighing(
      exempt: exempt, total: total, retention: retention, chargedTaxes: charged, reverseTaxes: reverse,
      income: income, entries: entries)
  }

  /// `documentLineParts`: each line's and charge's net amount in minor units.
  static func documentLineParts(_ doc: JSONValue, _ ctx: AcLedgerContext) -> [String: Int] {
    let weighing = weigh(doc, ctx)
    let parts = allocate(weighing.income, weighing.entries.map(\.weight))
    var out: [String: Int] = [:]
    for (index, entry) in weighing.entries.enumerated() { out[entry.id] = parts[index] }
    return out
  }

  /// Lines of a bill or vendor credit that post to inventory (`stockEntryIds`).
  static func stockEntryIds(_ doc: JSONValue, _ entries: [Weighed], _ ctx: AcLedgerContext) -> Set<String> {
    let type = doc.str("type")
    guard let stock = ctx.stock, type == "bill" || type == "vendor_credit" else { return [] }
    var ids = Set<String>()
    for entry in entries {
      let product = entry.isCharge ? nil : entry.productId
      if let product, stock.products.contains(product) {
        ids.insert(entry.id)
      } else if stock.landedCostLines.contains(doc.str("id") + ":" + entry.id) {
        ids.insert(entry.id)
      }
    }
    return ids
  }

  static func inventoryAccount(_ ctx: AcLedgerContext) throws -> String {
    guard let id = usable(ctx, ctx.stock?.inventoryAccountId) else {
      throw AcLedgerError(
        message: "No inventory account is set up.", label: AcLabel(text: "No inventory account is set up."))
    }
    return id
  }

  static func costOfSalesAccount(_ ctx: AcLedgerContext) throws -> String {
    if let id = usable(ctx, ctx.stock?.costOfSalesAccountId) { return id }
    return try role(ctx, "cost_of_sales")
  }

  /// A base line of an entry.
  struct Base {
    let date: String
    let source: AcSource
    let sourceId: String
    let number: String
    let contactId: String?

    func line(_ accountId: String, _ amount: Int, _ text: AcText, vat: AcVatTag? = nil) -> AcLine {
      AcLine(
        date: date, accountId: accountId, amount: amount, source: source, sourceId: sourceId, number: number,
        contactId: contactId, description: text.description, label: text.label, vat: vat)
    }
  }

  private struct Group {
    let accountId: String
    var weight: Decimal
    var minor: Int
    let label: String
    let vat: AcVatTag
  }

  /// `postDocument`: ledger lines of an invoice, credit note, bill or vendor credit.
  static func postDocument(_ doc: JSONValue, _ ctx: AcLedgerContext) throws -> [AcLine] {
    let type = doc.str("type")
    guard isPosted(doc), let rule = Rule.of(type), let source = AcSource(rawValue: type) else { return [] }
    let sales = rule.partner == "receivable"
    let sign = rule.sign
    let weighing = weigh(doc, ctx)
    let exempt = weighing.exempt
    let flow = sales ? "sale" : "purchase"

    func tagOf(_ taxes: [AcTax]) -> AcVatTag {
      if let first = taxes.first(where: { !$0.isReverseCharge }) ?? taxes.first {
        return AcVatTag(flow: flow, part: "base", kind: first.reportedKind, rate: first.rateValue)
      }
      // Sales to tax-exempt clients (exports, charities) are reported as zero-rated.
      return AcVatTag(flow: flow, part: "base", kind: exempt && sales ? "zero" : "none", rate: 0)
    }

    var groupKeys: [String] = []
    var groups: [String: Group] = [:]
    func add(_ accountId: String, _ weight: Decimal, _ minor: Int, _ label: String, _ taxes: [AcTax]) {
      let vat = tagOf(taxes)
      let key = accountId + "|" + vat.kind + "|" + Money.jsString(vat.rate)
      if var group = groups[key] {
        group.weight += weight
        group.minor += minor
        groups[key] = group
      } else {
        groupKeys.append(key)
        groups[key] = Group(accountId: accountId, weight: weight, minor: minor, label: label, vat: vat)
      }
    }

    // With stock lines, every line takes its own exact part.
    let stockIds = stockEntryIds(doc, weighing.entries, ctx)
    let parts: [Int]? = stockIds.isEmpty ? nil : allocate(weighing.income, weighing.entries.map(\.weight))
    let posting = doc.obj("posting")
    for (index, entry) in weighing.entries.enumerated() {
      let account: String
      if stockIds.contains(entry.id) {
        account = try inventoryAccount(ctx)
      } else if entry.isCharge {
        account = try role(ctx, rule.charges, rule.line)
      } else {
        // The product's income account as it was when the document was issued.
        let productAccount: String?
        if let posting {
          productAccount = posting.obj("accounts")?.text(entry.id)
        } else if let product = entry.productId {
          productAccount = ctx.productAccounts[product]
        } else {
          productAccount = nil
        }
        if let own = usable(ctx, entry.accountId) {
          account = own
        } else if sales, let product = usable(ctx, productAccount) {
          account = product
        } else {
          account = try role(ctx, rule.line)
        }
      }
      add(account, entry.weight, parts?[index] ?? 0, entry.label, entry.taxes)
    }
    if groupKeys.isEmpty { add(try role(ctx, rule.line), Decimal(1), weighing.income, "", []) }

    let base = Base(
      date: doc.str("issueDate"), source: source, sourceId: doc.str("id"), number: doc.str("number"),
      contactId: doc.text("clientId"))
    let named = AcText.described(rule.numbered, ["number": doc.str("number")])
    // A retention held back waits in retentions receivable (payable) until released.
    let retentionAccount = usable(ctx, sales ? ctx.retentionReceivable : ctx.retentionPayable)
    let retained =
      retentionAccount != nil && weighing.retention > 0 ? min(weighing.retention, max(weighing.total, 0)) : 0
    var lines = [base.line(try role(ctx, rule.partner), sign * (weighing.total - retained), named)]
    if retained > 0, let retentionAccount {
      lines.append(
        base.line(retentionAccount, sign * retained, .described("Retention {number}", ["number": doc.str("number")])))
    }
    let entries = groupKeys.compactMap { groups[$0] }
    let amounts = parts != nil ? entries.map(\.minor) : allocate(weighing.income, entries.map(\.weight))
    for (index, minor) in amounts.enumerated() {
      let group = entries[index]
      let text = entries.count > 1 && !group.label.isEmpty ? AcText.plain(group.label) : named
      lines.append(base.line(group.accountId, -sign * minor, text, vat: group.vat))
    }
    for tax in weighing.chargedTaxes {
      lines.append(
        base.line(
          try role(ctx, rule.tax), -sign * tax.minor, .plain("\(tax.name) \(Money.jsString(tax.rate))%"),
          vat: AcVatTag(flow: flow, part: "tax", kind: tax.kind, rate: tax.rate)))
    }
    // Reverse charge on a purchase: the buyer owes the VAT and reclaims it at once.
    if !sales {
      for tax in weighing.reverseTaxes {
        let vat = AcVatTag(flow: flow, part: "tax", kind: "reverse_charge", rate: tax.rate)
        let text = reverseChargeText(tax.name, tax.rate)
        lines.append(base.line(try role(ctx, "input_tax"), -sign * tax.minor, text, vat: vat))
        lines.append(base.line(try role(ctx, "output_tax"), sign * tax.minor, text, vat: vat))
      }
    }
    let kept = lines.filter { $0.amount != 0 }
    if !balanced(kept) { throw AcLedgerError.unbalanced("\(named.description) does not balance") }
    return kept
  }

  /// `touchesStock`: lines that move stock or post to inventory.
  static func touchesStock(_ doc: JSONValue, _ ctx: AcLedgerContext) -> Bool {
    guard let stock = ctx.stock else { return false }
    let items = doc.list("items")
    if items.contains(where: { $0.str("kind") == "item" && stock.products.contains($0.text("productId") ?? "") }) {
      return true
    }
    let id = doc.str("id")
    return (items + doc.list("charges")).contains { stock.landedCostLines.contains(id + ":" + $0.str("id")) }
  }

  /// `postDocumentStock`: cost of sales against inventory at the value of the
  /// movements; on bills the difference between the stock moved and posted.
  static func postDocumentStock(_ doc: JSONValue, _ movements: [JSONValue], _ ctx: AcLedgerContext) throws -> [AcLine] {
    let type = doc.str("type")
    guard isPosted(doc), let rule = Rule.of(type), let source = AcSource(rawValue: type), ctx.stock != nil else {
      return []
    }
    let p = ctx.precision
    let moved = movements.reduce(0) { $0 + minor($1.num("value"), p) }
    var expected = 0
    if type == "bill" || type == "vendor_credit" {
      let weighing = weigh(doc, ctx)
      let ids = stockEntryIds(doc, weighing.entries, ctx)
      if !ids.isEmpty {
        let parts = allocate(weighing.income, weighing.entries.map(\.weight))
        var posted = 0
        for (index, entry) in weighing.entries.enumerated() where ids.contains(entry.id) { posted += parts[index] }
        expected = -rule.sign * posted
      }
    }
    let difference = moved - expected
    if difference == 0 { return [] }
    let base = Base(
      date: doc.str("issueDate"), source: source, sourceId: doc.str("id"), number: doc.str("number"),
      contactId: doc.text("clientId"))
    let key = type == "invoice" || type == "credit" ? "Cost of sales {number}" : "Stock cost difference {number}"
    let text = AcText.described(key, ["number": doc.str("number")])
    return [
      base.line(try inventoryAccount(ctx), difference, text),
      base.line(try costOfSalesAccount(ctx), -difference, text),
    ]
  }

  /// `postStockEntry`: opening stock and stock adjustments; transfers post nothing.
  static func postStockEntry(_ entry: JSONValue, _ movements: [JSONValue], _ ctx: AcLedgerContext) throws -> [AcLine] {
    if entry.str("status") != "posted" || entry.str("kind") == "transfer" { return [] }
    let p = ctx.precision
    let moved = movements.reduce(0) { $0 + minor($1.num("value"), p) }
    let number = entry.str("number")
    let base = Base(date: entry.str("date"), source: .stock, sourceId: entry.str("id"), number: number, contactId: nil)
    let inventory = try inventoryAccount(ctx)
    var lines: [AcLine]
    if entry.str("kind") == "opening" {
      let nominal = movements.reduce(0) { $0 + minor($1.number("sourceValue") ?? $1.num("value"), p) }
      let text = AcText.described("Opening stock {number}", ["number": number])
      lines = [
        base.line(inventory, moved, text),
        base.line(try role(ctx, "opening_balance"), -nominal, text),
        base.line(try costOfSalesAccount(ctx), nominal - moved, text),
      ]
    } else {
      guard let adjustments = usable(ctx, ctx.stock?.adjustmentAccountId) else {
        throw AcLedgerError(
          message: "No inventory adjustments account is set up.",
          label: AcLabel(text: "No inventory adjustments account is set up."))
      }
      let text = AcText.described("Stock adjustment {number}", ["number": number])
      lines = [base.line(inventory, moved, text), base.line(adjustments, -moved, text)]
    }
    let kept = lines.filter { $0.amount != 0 }
    if !balanced(kept) { throw AcLedgerError.unbalanced("Stock entry \(number) does not balance") }
    return kept
  }

  /// `postStockIssue`: items issued to an employee leave inventory as an expense.
  static func postStockIssue(_ issue: JSONValue, _ movements: [JSONValue], _ ctx: AcLedgerContext) throws -> [AcLine] {
    if issue.str("status") != "posted" { return [] }
    let moved = movements.reduce(0) { $0 + minor($1.num("value"), ctx.precision) }
    if moved == 0 { return [] }
    guard let expense = usable(ctx, ctx.stock?.issuedItemsAccountId) else {
      throw AcLedgerError(
        message: "No account is set up for items issued to employees.",
        label: AcLabel(text: "No account is set up for items issued to employees."))
    }
    let number = issue.str("number")
    let base = Base(date: issue.str("date"), source: .issue, sourceId: issue.str("id"), number: number, contactId: nil)
    let text = AcText.described(
      "Items issued {number} to {name}", ["number": number, "name": issue.obj("recipient")?.str("name") ?? ""])
    return [base.line(try inventoryAccount(ctx), moved, text), base.line(expense, -moved, text)]
  }

  // MARK: Payments

  /// `chequeReversalDate`: the day a returned or cancelled cheque is reversed.
  static func chequeReversalDate(_ payment: JSONValue) -> String? {
    let status = payment.obj("cheque")?.str("status") ?? ""
    guard payment.flag("voided"), status == "returned" || status == "cancelled" else { return nil }
    return payment.text("voidedOn")
  }

  static func postsUnderCurrentRules(_ payment: JSONValue) -> Bool {
    (payment.number("postingRules") ?? 1) >= paymentPostingRules
  }

  static func clearingKey(_ paymentId: String, _ documentId: String, credit: Bool = false) -> String {
    credit ? "\(paymentId)|\(documentId)|credit" : "\(paymentId)|\(documentId)"
  }

  /// `postPayment`.
  static func postPayment(_ payment: JSONValue, _ ctx: AcLedgerContext) throws -> [AcLine] {
    let method = payment.str("method")
    if method == "credit_note" {
      if !postsUnderCurrentRules(payment) { return [] }
      return try postCreditApplication(payment, ctx)
    }
    let reversedOn = chequeReversalDate(payment)
    if payment.flag("voided"), reversedOn == nil { return [] }
    let out = payment.str("direction") == "out"
    let p = ctx.precision
    let rate = Money.dec(rateOf(payment, ctx.companyCurrency))
    let amount = Money.dec(payment.num("amount"))
    let received = minor(amount * rate, p)
    if received == 0 { return [] }

    // Receivable (or payable) is cleared at each document's own rate.
    var cleared = 0
    var allocated = Decimal(0)
    let id = payment.str("id")
    for allocation in payment.list("allocations") {
      let documentId = allocation.str("documentId")
      let value = Money.dec(allocation.num("amount"))
      if let known = ctx.clearing?[clearingKey(id, documentId)] {
        cleared += known
      } else {
        let docRate = ctx.documents[documentId].map { Money.dec(rateOf($0, ctx.companyCurrency)) } ?? rate
        cleared += minor(value * docRate, p)
      }
      allocated += value
    }
    let unapplied = amount - allocated
    if unapplied > 0 { cleared += minor(unapplied * rate, p) }

    let cashLike = method == "cash" || method == "cod"
    let bank = try usable(ctx, payment.text("accountId")) ?? role(ctx, cashLike ? "cash" : "bank", "bank")
    let base = Base(
      date: payment.str("date"), source: .payment, sourceId: id, number: payment.str("number"),
      contactId: payment.text("clientId"))
    let named = AcText.described("Payment {number}", ["number": payment.str("number")])
    let flow = out ? -1 : 1
    var lines = [
      base.line(bank, flow * received, named),
      base.line(try role(ctx, out ? "payable" : "receivable"), -flow * cleared, named),
    ]
    let fx = received - cleared
    if fx != 0 {
      lines.append(
        base.line(
          try role(ctx, "fx"), -flow * fx, .described("Exchange difference {number}", ["number": payment.str("number")])
        ))
    }
    let feeValue = payment.num("fee")
    let fee = !out && feeValue != 0 ? minor(Money.dec(feeValue) * rate, p) : 0
    if fee > 0 {
      let text = AcText.described("Fee {number}", ["number": payment.str("number")])
      let feeAccount = try usable(ctx, payment.text("feeAccountId")) ?? role(ctx, "bank_fees", "expense")
      lines.append(base.line(feeAccount, fee, text))
      lines.append(base.line(bank, -fee, text))
    }
    let kept = lines.filter { $0.amount != 0 }
    if !balanced(kept) { throw AcLedgerError.unbalanced("Payment \(payment.str("number")) does not balance") }
    guard let reversedOn else { return kept }
    let cancelled = payment.obj("cheque")?.str("status") == "cancelled"
    let reversal = AcText.described(
      cancelled ? "Cheque {cheque} cancelled ({number})" : "Cheque {cheque} returned ({number})",
      ["cheque": payment.obj("cheque")?.str("number") ?? "", "number": payment.str("number")])
    var all = kept
    for line in kept {
      var back = line
      back.date = reversedOn
      back.amount = -line.amount
      back.description = reversal.description
      back.label = reversal.label
      all.append(back)
    }
    return all
  }

  /// `postCreditApplication`: a credit applied at another rate than its
  /// invoice posts the exchange difference.
  static func postCreditApplication(_ payment: JSONValue, _ ctx: AcLedgerContext) throws -> [AcLine] {
    guard let creditId = payment.text("creditId"), let credit = ctx.documents[creditId], !payment.flag("voided") else {
      return []
    }
    let out = payment.str("direction") == "out"
    let p = ctx.precision
    let id = payment.str("id")
    var difference = 0
    for allocation in payment.list("allocations") {
      let documentId = allocation.str("documentId")
      guard let doc = ctx.documents[documentId] else { continue }
      let value = Money.dec(allocation.num("amount"))
      let creditSide =
        ctx.clearing?[clearingKey(id, documentId, credit: true)]
        ?? minor(value * Money.dec(rateOf(credit, ctx.companyCurrency)), p)
      let documentSide =
        ctx.clearing?[clearingKey(id, documentId)] ?? minor(value * Money.dec(rateOf(doc, ctx.companyCurrency)), p)
      difference += out ? documentSide - creditSide : creditSide - documentSide
    }
    if difference == 0 { return [] }
    let base = Base(
      date: payment.str("date"), source: .payment, sourceId: id, number: payment.str("number"),
      contactId: payment.text("clientId"))
    let text = AcText.described("Exchange difference {number}", ["number": payment.str("number")])
    return [
      base.line(try role(ctx, out ? "payable" : "receivable"), difference, text),
      base.line(try role(ctx, "fx"), -difference, text),
    ]
  }

  private struct ClearingPart {
    let date: String
    let rank: Int
    let order: String
    let key: String
    let amount: Decimal
    let own: Int?
    let reverses: String?
  }

  /// `documentClearing`: what each payment and credit application clears from
  /// a document in another currency, converted cumulatively in date order.
  static func documentClearing(_ payments: [JSONValue], _ ctx: AcLedgerContext) -> [String: Int] {
    var byDocument: [String: [ClearingPart]] = [:]
    var documentOrder: [String] = []
    func foreign(_ id: String) -> JSONValue? {
      guard let doc = ctx.documents[id], doc.str("currency") != ctx.companyCurrency else { return nil }
      return doc
    }
    func add(_ documentId: String, _ part: ClearingPart) {
      if byDocument[documentId] == nil { documentOrder.append(documentId) }
      byDocument[documentId, default: []].append(part)
    }
    func alone(_ amount: Double, _ doc: JSONValue) -> Int {
      minor(Money.dec(amount) * Money.dec(rateOf(doc, ctx.companyCurrency)), ctx.precision)
    }
    for payment in payments {
      let reversedOn = chequeReversalDate(payment)
      if payment.flag("voided"), reversedOn == nil { continue }
      let current = postsUnderCurrentRules(payment)
      let id = payment.str("id")
      let order = payment.str("createdAt") + "|" + id
      let credit: JSONValue? =
        payment.str("method") == "credit_note" ? payment.text("creditId").flatMap { foreign($0) } : nil
      for allocation in payment.list("allocations") {
        let documentId = allocation.str("documentId")
        let key = clearingKey(id, documentId)
        let value = allocation.num("amount")
        if let doc = foreign(documentId) {
          add(
            doc.str("id"),
            ClearingPart(
              date: payment.str("date"), rank: 1, order: order, key: key, amount: Money.dec(value),
              own: current ? nil : alone(value, doc), reverses: nil))
          if let reversedOn {
            add(
              doc.str("id"),
              ClearingPart(
                date: reversedOn, rank: reversedOn == payment.str("date") ? 1 : 0, order: order,
                key: key + "|reversal", amount: -Money.dec(value), own: nil, reverses: key))
          }
        }
        if let credit {
          add(
            credit.str("id"),
            ClearingPart(
              date: payment.str("date"), rank: 1, order: order, key: clearingKey(id, documentId, credit: true),
              amount: Money.dec(value), own: current ? nil : alone(value, credit), reverses: nil))
        }
      }
    }
    var out: [String: Int] = [:]
    for documentId in documentOrder {
      guard let doc = ctx.documents[documentId], let parts = byDocument[documentId] else { continue }
      let rate = Money.dec(rateOf(doc, ctx.companyCurrency))
      let sorted = parts.sorted { a, b in
        if a.date != b.date { return a.date < b.date }
        if a.rank != b.rank { return a.rank < b.rank }
        if a.order != b.order { return a.order < b.order }
        let ra = a.reverses != nil ? 1 : 0
        let rb = b.reverses != nil ? 1 : 0
        if ra != rb { return ra < rb }
        return a.key < b.key
      }
      var total = Decimal(0)
      var cleared = 0
      for part in sorted {
        total += part.amount
        let value: Int
        if let reverses = part.reverses {
          value = -(out[reverses] ?? 0)
        } else {
          value = part.own ?? (minor(total * rate, ctx.precision) - cleared)
        }
        cleared += value
        out[part.key] = value
      }
    }
    return out
  }

  // MARK: Expenses and journals

  /// `postExpense`: the category and input tax, paid from a money account.
  static func postExpense(_ expense: JSONValue, _ ctx: AcLedgerContext) throws -> [AcLine] {
    let p = ctx.precision
    let rate = Money.dec(rateOf(expense, ctx.companyCurrency))
    let total = minor(Money.dec(expense.num("amount")) * rate, p)
    if total == 0 { return [] }
    let valid = AcTax.list(expense.list("taxes")).filter {
      !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ($0.rate?.isFinite ?? false)
    }
    let charged = valid.filter { !$0.isReverseCharge }
    let reverse = valid.filter(\.isReverseCharge)
    var rateSum = Decimal(0)
    for tax in charged { rateSum += Money.dec(tax.rateValue) }
    let net = rateSum.isZero ? Decimal(total) : Decimal(total) / (rateSum / 100 + 1)
    let taxTotal = total - minor(net)
    let perTax = allocate(taxTotal, charged.map { Money.dec($0.rateValue) })
    let first = charged.first ?? reverse.first
    let base = Base(
      date: expense.str("date"), source: .expense, sourceId: expense.str("id"), number: expense.str("number"),
      contactId: expense.text("vendorId"))
    let named: AcText =
      expense.str("description").isEmpty
      ? .described("Expense {number}", ["number": expense.str("number")]) : .plain(expense.str("description"))
    var lines = [
      base.line(
        try usable(ctx, expense.text("accountId")) ?? role(ctx, "expense"), total - taxTotal, named,
        vat: AcVatTag(flow: "purchase", part: "base", kind: first?.reportedKind ?? "none", rate: first?.rateValue ?? 0))
    ]
    for (index, tax) in charged.enumerated() {
      lines.append(
        base.line(
          try role(ctx, "input_tax"), perTax[index], .plain("\(tax.name) \(Money.jsString(tax.rateValue))%"),
          vat: AcVatTag(flow: "purchase", part: "tax", kind: tax.reportedKind, rate: tax.rateValue)))
    }
    lines.append(base.line(try usable(ctx, expense.text("paidFromAccountId")) ?? role(ctx, "bank"), -total, named))
    for tax in reverse {
      let value = minor(Decimal(total - taxTotal) * Money.dec(tax.rateValue) / 100)
      let vat = AcVatTag(flow: "purchase", part: "tax", kind: "reverse_charge", rate: tax.rateValue)
      let text = reverseChargeText(tax.name, tax.rateValue)
      lines.append(base.line(try role(ctx, "input_tax"), value, text, vat: vat))
      lines.append(base.line(try role(ctx, "output_tax"), -value, text, vat: vat))
    }
    return lines.filter { $0.amount != 0 }
  }

  /// `postJournal`: the lines of a posted manual journal.
  static func postJournal(_ journal: JSONValue, _ ctx: AcLedgerContext) throws -> [AcLine] {
    if journal.str("status") != "posted" { return [] }
    let number = journal.str("number")
    let reference = journal.str("reference")
    let settles = journal.text("vatReturnId") != nil
    var lines: [AcLine] = []
    for line in journal.list("lines") {
      let amount = minor(line.num("debit"), ctx.precision) - minor(line.num("credit"), ctx.precision)
      if amount == 0 { continue }
      let typed = line.str("description").isEmpty ? reference : line.str("description")
      let text: AcText = typed.isEmpty ? .described("Journal {number}", ["number": number]) : .plain(typed)
      var posted = AcLine(
        date: journal.str("date"), accountId: line.str("accountId"), amount: amount, source: .journal,
        sourceId: journal.str("id"), number: number, contactId: line.text("contactId"), description: text.description,
        label: text.label, vat: nil)
      posted.settlement = settles
      lines.append(posted)
    }
    if !balanced(lines) { throw AcLedgerError.unbalanced("Journal \(number) does not balance") }
    return lines
  }

  // MARK: The whole ledger

  /// The records the ledger is built from.
  struct Sources {
    var documents: [JSONValue]
    var payments: [JSONValue]
    var journals: [JSONValue]
    var expenses: [JSONValue]
    var movements: [JSONValue]
    var entries: [JSONValue]
    var issues: [JSONValue]
  }

  /// `buildLedger`: documents that can't be posted are reported as problems.
  static func build(_ data: Sources, _ ctx: AcLedgerContext) -> (lines: [AcLine], problems: [AcProblem]) {
    var lines: [AcLine] = []
    var problems: [AcProblem] = []
    func attempt(_ source: AcSource, _ id: String, _ number: String, _ post: () throws -> [AcLine]) {
      do {
        lines.append(contentsOf: try post())
      } catch let error as AcLedgerError {
        problems.append(AcProblem(source: source, sourceId: id, number: number, message: error.message, label: error.label))
      } catch {
        problems.append(
          AcProblem(source: source, sourceId: id, number: number, message: String(describing: error), label: nil))
      }
    }
    for doc in data.documents {
      guard isPosted(doc), let source = AcSource(rawValue: doc.str("type")) else { continue }
      if needsRate(doc, ctx.companyCurrency) {
        problems.append(rateProblem(source, doc.str("id"), doc.str("number"), doc.str("currency")))
      }
      attempt(source, doc.str("id"), doc.str("number")) { try postDocument(doc, ctx) }
    }
    if ctx.stock != nil {
      var byDocument: [String: [JSONValue]] = [:]
      var byEntry: [String: [JSONValue]] = [:]
      var byIssue: [String: [JSONValue]] = [:]
      for movement in data.movements {
        let type = movement.str("sourceType")
        if type == "opening" || type == "adjustment" {
          byEntry[movement.str("sourceId"), default: []].append(movement)
        } else if type == "issue" {
          byIssue[movement.str("sourceId"), default: []].append(movement)
        } else if let documentId = movement.text("documentId") {
          byDocument[documentId, default: []].append(movement)
        }
      }
      for doc in data.documents {
        guard isPosted(doc), let source = AcSource(rawValue: doc.str("type")) else { continue }
        let moved = byDocument[doc.str("id")]
        if moved == nil, !touchesStock(doc, ctx) { continue }
        attempt(source, doc.str("id"), doc.str("number")) { try postDocumentStock(doc, moved ?? [], ctx) }
      }
      for entry in data.entries {
        attempt(.stock, entry.str("id"), entry.str("number")) {
          try postStockEntry(entry, byEntry[entry.str("id")] ?? [], ctx)
        }
      }
      for issue in data.issues {
        attempt(.issue, issue.str("id"), issue.str("number")) {
          try postStockIssue(issue, byIssue[issue.str("id")] ?? [], ctx)
        }
      }
    }
    // Documents in other currencies are cleared cumulatively, to the last fils.
    var payContext = ctx
    if payContext.clearing == nil { payContext.clearing = documentClearing(data.payments, ctx) }
    for payment in data.payments {
      let posted = !payment.flag("voided") || chequeReversalDate(payment) != nil
      if payment.str("method") != "credit_note", posted, needsRate(payment, ctx.companyCurrency) {
        problems.append(rateProblem(.payment, payment.str("id"), payment.str("number"), payment.str("currency")))
      }
      attempt(.payment, payment.str("id"), payment.str("number")) { try postPayment(payment, payContext) }
    }
    for expense in data.expenses {
      if needsRate(expense, ctx.companyCurrency) {
        problems.append(rateProblem(.expense, expense.str("id"), expense.str("number"), expense.str("currency")))
      }
      attempt(.expense, expense.str("id"), expense.str("number")) { try postExpense(expense, ctx) }
    }
    for journal in data.journals {
      attempt(.journal, journal.str("id"), journal.str("number")) { try postJournal(journal, ctx) }
    }
    // By date, then number (as `localeCompare`); the sort keeps the order of equals.
    let sorted = lines.enumerated().sorted { a, b in
      if a.element.date != b.element.date { return a.element.date < b.element.date }
      let order = AcText.compare(a.element.number, b.element.number)
      if order != .orderedSame { return order == .orderedAscending }
      return a.offset < b.offset
    }
    return (sorted.map { $0.element }, problems)
  }
}

extension AcText {
  /// `a.localeCompare(b)`: the locale-aware order the web sorts text in.
  static func compare(_ a: String, _ b: String) -> ComparisonResult {
    a.compare(b, options: [], range: nil, locale: acCollationLocale)
  }

  /// `a.localeCompare(b, undefined, { numeric: true })`: codes in number order.
  static func compareNumeric(_ a: String, _ b: String) -> ComparisonResult {
    a.compare(b, options: [.numeric], range: nil, locale: acCollationLocale)
  }
}

/// The collation the web's `localeCompare` uses (the root order).
let acCollationLocale = Locale(identifier: "en")
