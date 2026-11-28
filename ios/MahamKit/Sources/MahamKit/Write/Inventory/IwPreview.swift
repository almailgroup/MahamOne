import Foundation

/// What the stock forms show before saving, worked out as the web's forms
/// do with the same rules the writes use: a bill's charges and stock lines
/// with their values, and how a landed cost would be split.
public enum IwPreview {
  /// One stock line's share of a landed cost, in minor units of the company currency.
  public struct Share: Sendable, Equatable {
    public var lineId: String
    public var productId: String
    public var quantity: Double
    /// The value received on the line, the basis of a split by value.
    public var lineValue: Int
    public var share: Int
  }

  /// A landed cost as it would be allocated (`allocateLandedCost`): the
  /// charges' total and each stock line's share; nil when it has no effect.
  public struct Allocation: Sendable, Equatable {
    public var total: Int
    public var shares: [Share]
  }

  private static func makeSetup(company: JSONValue, products: [JSONValue], clients: [JSONValue]) -> IwSources.Setup {
    IwSources.Setup(
      companyCurrency: company.iwText("currency"), precision: Money.precision(company.iwText("currency")),
      products: Set(products.filter(IwSources.isStockItem).map(\.iwId)), defaultWarehouseId: "", warehouses: [],
      exemptClients: Set(clients.filter { $0.iwTruthy("taxExempt") }.map(\.iwId)))
  }

  /// `movesStock(doc)`: an issued bill, vendor credit, invoice or credit note.
  public static func movesStock(_ doc: JSONValue) -> Bool { IwSources.movesStock(doc) }

  /// `stockLines(doc, products)`: the ids of the document's lines that carry a stock item.
  public static func stockLineIds(_ doc: JSONValue, products: [JSONValue]) -> [String] {
    let stock = Set(products.filter(IwSources.isStockItem).map(\.iwId))
    return IwSources.stockLines(doc, stock).map { WebJS.string($0["id"]) }
  }

  /// `documentLineParts(doc, setup)`: each line's and charge's net amount
  /// in minor units of the company currency.
  public static func lineParts(_ doc: JSONValue, company: JSONValue, clients: [JSONValue]) -> [String: Int] {
    let currency = company.iwText("currency")
    return IwCalc.documentLineParts(
      doc, companyCurrency: currency, precision: Money.precision(currency),
      exemptClients: Set(clients.filter { $0.iwTruthy("taxExempt") }.map(\.iwId)))
  }

  /// `landedCostLinks` and `allocateLandedCost` for a landed cost being chosen.
  public static func landedCost(
    company: JSONValue, products: [JSONValue], clients: [JSONValue], costBill: JSONValue, targetBill: JSONValue,
    sourceLineIds: [String], targetLineIds: [String], method: String
  ) -> Allocation? {
    let setup = makeSetup(company: company, products: products, clients: clients)
    let draft: JSONValue = .object([
      "status": "active",
      "billId": costBill["id"] ?? .null,
      "targetBillId": targetBill["id"] ?? .null,
      "sourceLineIds": .array(sourceLineIds.map(JSONValue.string)),
      "targetLineIds": .array(targetLineIds.map(JSONValue.string)),
      "method": .string(method),
    ])
    guard let links = IwSources.landedCostLinks(draft, costBill, targetBill, setup.products) else { return nil }
    let result = IwSources.allocateLandedCost(draft, costBill, targetBill, links, setup)
    return Allocation(
      total: result.total,
      shares: result.shares.map { share in
        Share(
          lineId: WebJS.string(share.lineId), productId: WebJS.string(share.productId),
          quantity: share.quantity?.double ?? 0, lineValue: share.lineValue, share: share.share)
      })
  }

  /// `toMinor(dec(quantity).times(dec(unitCost)), precision)`: a quantity's value in minor units.
  public static func valueMinor(quantity: Double, unitCost: Double, precision: Int) -> Int {
    IwMoney.toMinor(IwDecimal(quantity).times(IwDecimal(unitCost)), precision)
  }

  /// `dec(a).plus(dec(b)).toNumber()`, as the forms add quantities.
  public static func add(_ a: Double, _ b: Double) -> Double {
    IwDecimal(a).plus(IwDecimal(b)).toNumber()
  }

  /// `dec(a).minus(dec(b)).toNumber()`.
  public static func subtract(_ a: Double, _ b: Double) -> Double {
    IwDecimal(a).minus(IwDecimal(b)).toNumber()
  }

  /// `dec(minor).dividedBy(dec(quantity)).dividedBy(10 ** p).toDecimalPlaces(6)`:
  /// the unit cost of a line once its share is added.
  public static func unitCost(minor: Int, quantity: Double, precision: Int) -> Double {
    guard quantity != 0 else { return 0 }
    return IwDecimal(minor).dividedBy(IwDecimal(quantity)).dividedBy(IwDecimal.power(precision)).toDecimalPlaces(6)
      .toNumber()
  }
}
