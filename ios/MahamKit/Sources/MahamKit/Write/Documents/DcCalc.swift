import Foundation

/// One line's amounts (`CalcLineResult`).
public struct DcLineResult: Sendable, Equatable {
  /// Quantity × unit price.
  public var gross: Double
  public var discount: Double
  /// Gross less the line's discount: the line's "Amount".
  public var net: Double
  /// Tax on the line (for display; totals use the grouped taxes).
  public var tax: Double
}

/// One tax of a document, grouped by name and rate (`TaxSummary`).
public struct DcTaxSummary: Sendable, Equatable, Identifiable {
  public var key: String
  public var name: String
  public var rate: Double
  public var kind: String
  /// What the tax was worked out on (always without tax).
  public var base: Double
  public var amount: Double
  public var id: String { key }
}

/// What `calculate` gives (`CalcResult`), every amount rounded to the currency.
public struct DcCalcResult: Sendable, Equatable {
  public var lines: [DcLineResult]
  public var subtotal: Double
  public var lineDiscountTotal: Double
  public var discount: Double
  public var chargesTotal: Double
  /// Every tax, reverse charge included (shown, never added to the total).
  public var taxes: [DcTaxSummary]
  public var taxTotal: Double
  public var netTotal: Double
  public var total: Double
  public var paid: Double
  public var retention: Double
  public var retentionHeld: Double
  public var balance: Double
  public var depositDue: Double
}

/// The web's document maths (src/lib/calc.ts and src/lib/document-calc.ts),
/// in the same order and with the same rounding: each line's net rounded to
/// the currency, the document discount spread into every line's tax base,
/// each tax group rounded once, charges taxed but never discounted.
public enum DcCalc {
  // MARK: Taxes

  /// `taxKind`: the kind, guessed from rate and name for older records.
  public static func taxKind(_ tax: JSONValue) -> String {
    if WebJS.truthy(tax["kind"]), let kind = tax["kind"]?.string { return kind }
    if (tax["rate"]?.double ?? 0) > 0 { return "standard" }
    let name = tax["name"]?.string ?? ""
    return name.range(of: "exempt", options: .caseInsensitive) != nil ? "exempt" : "zero"
  }

  public static func isReverseCharge(_ tax: JSONValue) -> Bool {
    tax["kind"] == .string("reverse_charge")
  }

  /// `taxLineOf`: the copy of a configured rate a line keeps.
  public static func taxLineOf(_ rate: JSONValue) -> JSONValue {
    var fields: [String: JSONValue] = ["name": rate["name"] ?? .null, "rate": rate["rate"] ?? .null]
    if WebJS.truthy(rate["kind"]) { fields["kind"] = rate["kind"] }
    return .object(fields)
  }

  /// `taxKey`: a reverse charge never merges with an ordinary rate of the same name.
  public static func taxKey(_ tax: JSONValue) -> String {
    let rate = Money.dec(tax["rate"]?.double ?? 0)
    let key = WebJS.trim(tax["name"]?.string ?? "").lowercased() + "|" + Money.jsString(Money.toNumber(rate))
    return isReverseCharge(tax) ? key + "|rc" : key
  }

  /// `validTaxes`: a name and a finite rate.
  static func validTaxes(_ taxes: JSONValue?) -> [JSONValue] {
    (taxes?.array ?? []).filter { tax in
      guard let name = tax["name"]?.string, WebJS.trim(name) != "" else { return false }
      guard case .number(let rate)? = tax["rate"], rate.isFinite else { return false }
      return true
    }
  }

  // MARK: Retention

  /// `retentionOf`: `percent` of the total, rounded to the currency (5% of 1,234.567 = 61.728).
  public static func retentionOf(_ total: Double, _ percent: Double?, _ precision: Int) -> Double {
    let rate: Double
    if let percent, percent.isFinite { rate = min(max(percent, 0), 100) } else { rate = 0 }
    if rate == 0 { return 0 }
    let amount = DcJS.round(Money.dec(total) * Money.dec(rate) / 100, precision)
    return amount > 0 ? amount : 0
  }

  /// `takesRetention`: invoices and bills hold one back.
  public static func takesRetention(_ type: String?) -> Bool {
    type == "invoice" || type == "bill"
  }

  /// `releasedRetention`: releases not undone, in the document's currency.
  public static func releasedRetention(_ doc: JSONValue) -> Double {
    var released = Decimal(0)
    for release in doc.dcList("retentionReleases") where !WebJS.truthy(release["reversedOn"]) {
      released += DcJS.dec(release["amount"])
    }
    return DcJS.round(released, DcJS.precision(of: doc))
  }

  /// `documentTaxExempt`: as fixed when issued (`posting`), else as the contact is now.
  public static func documentTaxExempt(_ doc: JSONValue, contact: JSONValue?) -> Bool {
    if WebJS.truthy(doc["posting"]) { return WebJS.truthy(doc["posting"]?["taxExempt"]) }
    return WebJS.truthy(contact?["taxExempt"])
  }

  // MARK: Calculating

  /// A charge to calculate: its amount and taxes.
  public struct Charge: Sendable {
    public var amount: JSONValue?
    public var taxes: [JSONValue]

    public init(amount: JSONValue?, taxes: [JSONValue]) {
      self.amount = amount
      self.taxes = taxes
    }
  }

  private struct Bucket {
    var name: String
    var rate: Double
    var kind: String
    var base: Decimal
    var amount: Decimal
  }

  /// `(type ?? 'percent') === 'percent'`.
  private static func isPercent(_ type: JSONValue?) -> Bool {
    guard let type = WebJS.present(type) else { return true }
    return type == .string("percent")
  }

  /// `calculate(input)`. `items` are document lines (headings carry nothing);
  /// `taxed` false leaves every line's own taxes out (a tax-exempt contact).
  public static func calculate(
    items: [JSONValue], itemsTaxed: Bool = true, discount: JSONValue?, discountType: JSONValue?, taxes: [JSONValue],
    charges: [Charge], pricesIncludeTax: Bool, precision: Int, paid: Double = 0, deposit: JSONValue? = nil,
    retentionPercent: Double? = 0, retentionReleased: Double = 0
  ) -> DcCalcResult {
    let p = max(0, min(6, precision))
    let inclusive = pricesIncludeTax
    let docTaxes = validTaxes(.array(taxes))
    var keys: [String] = []
    var buckets: [String: Bucket] = [:]

    func addTax(_ tax: JSONValue, _ base: Decimal, _ amount: Decimal) {
      let key = taxKey(tax)
      if var bucket = buckets[key] {
        bucket.base += base
        bucket.amount += amount
        buckets[key] = bucket
      } else {
        keys.append(key)
        buckets[key] = Bucket(
          name: WebJS.trim(tax["name"]?.string ?? ""), rate: tax["rate"]?.double ?? 0, kind: taxKind(tax), base: base,
          amount: amount)
      }
    }

    func applyTaxes(_ amount: Decimal, _ list: [JSONValue]) -> Decimal {
      if list.isEmpty { return 0 }
      var rateSum = Decimal(0)
      for tax in list where !isReverseCharge(tax) { rateSum += Money.dec(tax["rate"]?.double ?? 0) }
      let base = inclusive ? amount / (rateSum / 100 + 1) : amount
      var total = Decimal(0)
      for tax in list {
        let taxAmount = base * Money.dec(tax["rate"]?.double ?? 0) / 100
        addTax(tax, base, taxAmount)
        if !isReverseCharge(tax) { total += taxAmount }
      }
      return total
    }

    // 1. Line amounts.
    var lineNet: [Decimal] = []
    var lineDiscountTotal = Decimal(0)
    var lines: [DcLineResult] = []
    for item in items {
      if item["kind"] == .string("heading") {
        lineNet.append(0)
        lines.append(DcLineResult(gross: 0, discount: 0, net: 0, tax: 0))
        continue
      }
      let grossRaw = DcJS.dec(item["quantity"]) * DcJS.dec(item["unitPrice"])
      let discountValue = DcJS.dec(item["discount"])
      let discountRaw = isPercent(item["discountType"]) ? grossRaw * discountValue / 100 : discountValue
      let net = DcJS.round(grossRaw - discountRaw, p)
      let gross = DcJS.round(grossRaw, p)
      let lineDiscount = DcJS.round(Money.dec(gross) - Money.dec(net), p)
      lineDiscountTotal += Money.dec(lineDiscount)
      lineNet.append(Money.dec(net))
      lines.append(DcLineResult(gross: gross, discount: lineDiscount, net: net, tax: 0))
    }
    var subtotal = Decimal(0)
    for net in lineNet { subtotal += net }

    // 2. Document discount.
    let docDiscountValue = DcJS.dec(discount)
    let discountAmount = Money.dec(
      DcJS.round(isPercent(discountType) ? subtotal * docDiscountValue / 100 : docDiscountValue, p))
    // Each line carries its share of the document discount into its tax base.
    let ratio = subtotal.isZero ? Decimal(1) : (subtotal - discountAmount) / subtotal

    // 3. Taxes on lines (line taxes plus document taxes).
    for (index, item) in items.enumerated() where item["kind"] != .string("heading") {
      let own = itemsTaxed ? validTaxes(item["taxes"]) : []
      let lineTax = applyTaxes(lineNet[index] * ratio, own + docTaxes)
      lines[index].tax = DcJS.round(lineTax, p)
    }

    // 4. Charges.
    var chargesTotal = Decimal(0)
    for charge in charges {
      let amount = Money.dec(DcJS.round(DcJS.dec(charge.amount), p))
      chargesTotal += amount
      _ = applyTaxes(amount, validTaxes(.array(charge.taxes)))
    }

    // 5. Round once per tax group, then total.
    var summaries: [DcTaxSummary] = []
    for key in keys {
      guard let bucket = buckets[key] else { continue }
      summaries.append(
        DcTaxSummary(
          key: key, name: bucket.name, rate: bucket.rate, kind: bucket.kind, base: DcJS.round(bucket.base, p),
          amount: DcJS.round(bucket.amount, p)))
    }
    var taxTotal = Decimal(0)
    for summary in summaries where summary.kind != "reverse_charge" { taxTotal += Money.dec(summary.amount) }

    let afterDiscount = subtotal - discountAmount + chargesTotal
    let total = inclusive ? afterDiscount : afterDiscount + taxTotal
    let netTotal = total - taxTotal

    let paidAmount = Money.dec(DcJS.round(paid, p))
    let retention = Money.dec(retentionOf(DcJS.round(total, p), retentionPercent, p))
    var released = Money.dec(DcJS.round(retentionReleased, p))
    if released < 0 { released = 0 }
    if released > retention { released = retention }
    let retentionHeld = retention - released
    let balance = total - retentionHeld - paidAmount

    let depositValue = DcJS.dec(deposit)
    var depositDue = Decimal(0)
    if depositValue > 0 {
      // The retention is never part of the amount asked for up front.
      let payable = total - retention
      let capped = depositValue > payable ? payable : depositValue
      depositDue = capped - paidAmount
      if depositDue < 0 { depositDue = 0 }
    }

    return DcCalcResult(
      lines: lines, subtotal: DcJS.round(subtotal, p), lineDiscountTotal: DcJS.round(lineDiscountTotal, p),
      discount: DcJS.round(discountAmount, p), chargesTotal: DcJS.round(chargesTotal, p), taxes: summaries,
      taxTotal: DcJS.round(taxTotal, p), netTotal: DcJS.round(netTotal, p), total: DcJS.round(total, p),
      paid: DcJS.round(paidAmount, p), retention: DcJS.round(retention, p),
      retentionHeld: DcJS.round(retentionHeld, p), balance: DcJS.round(balance, p),
      depositDue: DcJS.round(depositDue, p))
  }

  /// `computeDocument(doc, { paid, taxExempt })`: a document's totals as its
  /// page and its saved `totals` show them.
  public static func computeDocument(_ doc: JSONValue, paid: Double = 0, taxExempt: Bool = false) -> DcCalcResult {
    let exempt = taxExempt
    let type = doc["type"]?.string
    let retains = takesRetention(type)
    let percent: Double? = retains ? (WebJS.present(doc["retentionPercent"]).map { $0.double ?? .nan } ?? 0) : 0
    return calculate(
      items: doc.dcList("items"), itemsTaxed: !exempt, discount: doc["discount"], discountType: doc["discountType"],
      taxes: exempt ? [] : doc.dcList("taxes"),
      charges: doc.dcList("charges").map { Charge(amount: $0["amount"], taxes: exempt ? [] : $0.dcList("taxes")) },
      pricesIncludeTax: WebJS.truthy(doc["pricesIncludeTax"]), precision: DcJS.precision(of: doc), paid: paid,
      deposit: doc["deposit"], retentionPercent: percent, retentionReleased: retains ? releasedRetention(doc) : 0)
  }
}
