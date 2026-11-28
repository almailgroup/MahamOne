import Foundation

// The document maths the stock needs, ported from the web's
// `calculate` (src/lib/calc.ts), `computeDocument` (src/lib/document-calc.ts)
// and `weighDocument` / `documentLineParts` / `allocate`
// (src/lib/accounting/ledger.ts), in decimal.js-light's arithmetic
// (`IwDecimal`): a bill's stock lines come in at exactly the part of the
// document's net amount the ledger posts to inventory.

enum IwCalc {
  /// What `calculate` gives that the stock uses.
  struct Result {
    /// Each line's net amount (0 for headings), in `items` order.
    var lineNets: [Double]
    var subtotal: Double
    var discount: Double
    /// Each tax group's amount, and whether it is a reverse charge.
    var taxes: [(amount: Double, reverseCharge: Bool)]
    var total: Double
  }

  /// `isReverseCharge(tax)`.
  static func isReverseCharge(_ tax: JSONValue) -> Bool {
    tax["kind"]?.string == "reverse_charge"
  }

  /// `(type ?? 'percent') === 'percent'`.
  private static func isPercent(_ type: JSONValue?) -> Bool {
    guard let type = WebJS.present(type) else { return true }
    return type == .string("percent")
  }

  /// `validTaxes`: taxes with a name (or none at all) and a finite rate.
  private static func validTaxes(_ taxes: [JSONValue]) -> [JSONValue] {
    taxes.filter { tax in
      guard tax.object != nil else { return false }
      if let name = tax["name"]?.string, WebJS.trim(name).isEmpty { return false }
      guard let rate = tax["rate"]?.double else { return false }
      return rate.isFinite
    }
  }

  /// `taxKey(tax)`.
  private static func taxKey(_ tax: JSONValue) -> String {
    let name = WebJS.trim(WebJS.string(tax["name"])).lowercased()
    let key = name + "|" + IwDecimal(tax["rate"]).description
    return isReverseCharge(tax) ? key + "|rc" : key
  }

  private struct Bucket {
    var reverseCharge: Bool
    var amount: IwDecimal
  }

  /// `computeDocument(doc, { taxExempt })`, the parts the stock reads.
  static func compute(_ doc: JSONValue, taxExempt exempt: Bool) -> Result {
    let currency = doc["currency"]?.string ?? ""
    let p = max(0, min(6, Money.precision(currency.isEmpty ? "KWD" : currency)))
    let inclusive = doc.iwTruthy("pricesIncludeTax")
    let docTaxes = exempt ? [] : validTaxes(doc.iwList("taxes"))
    var keys: [String] = []
    var buckets: [String: Bucket] = [:]

    func addTax(_ tax: JSONValue, _ amount: IwDecimal) {
      let key = taxKey(tax)
      if var bucket = buckets[key] {
        bucket.amount = bucket.amount.plus(amount)
        buckets[key] = bucket
      } else {
        keys.append(key)
        buckets[key] = Bucket(reverseCharge: isReverseCharge(tax), amount: amount)
      }
    }

    func applyTaxes(_ amount: IwDecimal, _ taxes: [JSONValue]) {
      if taxes.isEmpty { return }
      var rateSum = IwDecimal.zero
      for tax in taxes where !isReverseCharge(tax) { rateSum = rateSum.plus(IwDecimal(tax["rate"])) }
      let hundred = IwDecimal(100)
      let base = inclusive ? amount.dividedBy(rateSum.dividedBy(hundred).plus(.one)) : amount
      for tax in taxes {
        addTax(tax, base.times(IwDecimal(tax["rate"])).dividedBy(hundred))
      }
    }

    // 1. Line amounts.
    let items = doc.iwList("items")
    var lineNets: [Double] = []
    var lineNet: [IwDecimal] = []
    for item in items {
      if item["kind"]?.string == "heading" {
        lineNets.append(0)
        lineNet.append(.zero)
        continue
      }
      let gross = IwDecimal(item["quantity"]).times(IwDecimal(item["unitPrice"]))
      // `dec(item.discount ?? 0)`, `(item.discountType ?? 'percent') === 'percent'`.
      let discountValue = IwDecimal(item["discount"])
      let percent = isPercent(item["discountType"])
      let discountRaw = percent ? gross.times(discountValue).dividedBy(IwDecimal(100)) : discountValue
      let net = IwMoney.round(gross.minus(discountRaw), p)
      lineNets.append(net)
      lineNet.append(IwDecimal(net))
    }
    var subtotal = IwDecimal.zero
    for net in lineNet { subtotal = subtotal.plus(net) }

    // 2. Document discount.
    let docDiscount = IwDecimal(doc["discount"])
    let docPercent = isPercent(doc["discountType"])
    let discount = IwDecimal(
      IwMoney.round(docPercent ? subtotal.times(docDiscount).dividedBy(IwDecimal(100)) : docDiscount, p))
    let ratio = subtotal.isZero ? IwDecimal.one : subtotal.minus(discount).dividedBy(subtotal)

    // 3. Taxes on lines (line taxes plus document taxes).
    for (index, item) in items.enumerated() where item["kind"]?.string != "heading" {
      let own = exempt ? [] : validTaxes(item.iwList("taxes"))
      applyTaxes(lineNet[index].times(ratio), own + docTaxes)
    }

    // 4. Charges.
    var chargesTotal = IwDecimal.zero
    for charge in doc.iwList("charges") {
      let amount = IwDecimal(IwMoney.round(IwDecimal(charge["amount"]), p))
      chargesTotal = chargesTotal.plus(amount)
      applyTaxes(amount, exempt ? [] : validTaxes(charge.iwList("taxes")))
    }

    // 5. Round once per tax group, then total.
    var taxes: [(amount: Double, reverseCharge: Bool)] = []
    var taxTotal = IwDecimal.zero
    for key in keys {
      guard let bucket = buckets[key] else { continue }
      let amount = IwMoney.round(bucket.amount, p)
      taxes.append((amount, bucket.reverseCharge))
      if !bucket.reverseCharge { taxTotal = taxTotal.plus(IwDecimal(amount)) }
    }
    let afterDiscount = subtotal.minus(discount).plus(chargesTotal)
    let total = inclusive ? afterDiscount : afterDiscount.plus(taxTotal)
    return Result(
      lineNets: lineNets, subtotal: IwMoney.round(subtotal, p), discount: IwMoney.round(discount, p), taxes: taxes,
      total: IwMoney.round(total, p))
  }

  /// `postingTaxExempt(doc, taxExempt)`: as fixed when issued, else as the contact is now.
  static func postingTaxExempt(_ doc: JSONValue, exemptClients: Set<String>) -> Bool {
    if WebJS.truthy(doc["posting"]) { return WebJS.truthy(doc["posting"]?["taxExempt"]) }
    guard WebJS.truthy(doc["clientId"]) else { return false }
    return exemptClients.contains(WebJS.string(doc["clientId"]))
  }

  /// `rateOf(doc, ctx)`: company-currency value of one unit of the document's currency.
  static func rateOf(_ doc: JSONValue, companyCurrency: String) -> Double {
    if doc["currency"]?.string == companyCurrency { return 1 }
    if let rate = doc["exchangeRate"]?.double, rate.isFinite, rate > 0 { return rate }
    return 1
  }

  /// `allocate(total, weights)`: `total` minor units over the weights, the
  /// remainder to the largest, so the parts add up exactly.
  static func allocate(_ total: Int, _ weights: [IwDecimal]) -> [Int] {
    if weights.isEmpty { return [] }
    var sum = IwDecimal.zero
    for weight in weights { sum = sum.plus(weight) }
    if sum.isZero { return weights.indices.map { $0 == 0 ? total : 0 } }
    var parts = weights.map { IwMoney.toMinor(IwDecimal(total).times($0).dividedBy(sum), 0) }
    let diff = total - parts.reduce(0, +)
    if diff != 0 {
      var largest = 0
      for (index, weight) in weights.enumerated() where weight.abs().gt(weights[largest].abs()) {
        largest = index
      }
      parts[largest] += diff
    }
    return parts
  }

  /// `documentLineParts(doc, ctx)`: each line's and charge's net amount in
  /// minor units of the company currency (after the document discount,
  /// without tax); the parts add up to the document's net amount.
  static func documentLineParts(_ doc: JSONValue, companyCurrency: String, precision p: Int, exemptClients: Set<String>)
    -> [String: Int]
  {
    let exempt = postingTaxExempt(doc, exemptClients: exemptClients)
    let result = compute(doc, taxExempt: exempt)
    let rate = IwDecimal(rateOf(doc, companyCurrency: companyCurrency))
    let total = IwMoney.toMinor(IwDecimal(result.total).times(rate), p)
    var charged = 0
    for tax in result.taxes where !tax.reverseCharge {
      charged += IwMoney.toMinor(IwDecimal(tax.amount).times(rate), p)
    }
    let income = total - charged
    let ratio =
      result.subtotal == 0
      ? IwDecimal.one
      : IwDecimal(result.subtotal).minus(IwDecimal(result.discount)).dividedBy(IwDecimal(result.subtotal))
    func rateSum(_ list: [JSONValue]) -> IwDecimal {
      var sum = IwDecimal.zero
      for tax in list { sum = sum.plus(IwDecimal(tax["rate"])) }
      return sum.dividedBy(IwDecimal(100)).plus(.one)
    }
    let inclusive = doc.iwTruthy("pricesIncludeTax")
    let docTaxes = exempt ? [] : doc.iwList("taxes")
    var ids: [String] = []
    var weights: [IwDecimal] = []
    for (index, item) in doc.iwList("items").enumerated() where item["kind"]?.string != "heading" {
      let taxes = exempt ? [] : item.iwList("taxes") + docTaxes
      let net = index < result.lineNets.count ? result.lineNets[index] : 0
      var weight = IwDecimal(net).times(ratio)
      let chargedTaxes = taxes.filter { !isReverseCharge($0) }
      if inclusive, !chargedTaxes.isEmpty { weight = weight.dividedBy(rateSum(chargedTaxes)) }
      ids.append(WebJS.string(item["id"]))
      weights.append(weight)
    }
    for charge in doc.iwList("charges") {
      let taxes = exempt ? [] : charge.iwList("taxes")
      var weight = IwDecimal(charge["amount"])
      let chargedTaxes = taxes.filter { !isReverseCharge($0) }
      if inclusive, !chargedTaxes.isEmpty { weight = weight.dividedBy(rateSum(chargedTaxes)) }
      ids.append(WebJS.string(charge["id"]))
      weights.append(weight)
    }
    let parts = allocate(income, weights)
    var out: [String: Int] = [:]
    for (index, id) in ids.enumerated() { out[id] = parts[index] }
    return out
  }
}
