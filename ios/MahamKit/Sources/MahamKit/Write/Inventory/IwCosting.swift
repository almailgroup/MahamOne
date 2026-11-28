import Foundation

/// Weighted average costing (IAS 2), ported from the web's
/// `src/lib/inventory/costing.ts`: every stock item keeps one average cost
/// across its warehouses; movements are replayed in date order, so a bill
/// entered late re-costs everything sold after it; movements on or before
/// the lock date keep their values. Values are integer minor units of the
/// company currency; unit costs keep up to 6 decimals.
enum IwCosting {
  /// `SOURCE_RANK`: on the same day stock comes in before it goes out; counts come last.
  static func rank(_ sourceType: JSONValue?) -> Int? {
    switch sourceType?.string ?? "" {
    case "opening": 0
    case "bill": 1
    case "landed_cost": 2
    case "credit": 3
    case "transfer": 4
    case "invoice": 5
    case "vendor_credit": 6
    case "issue": 7
    case "adjustment": 8
    default: nil
    }
  }

  /// `compareMovements`: by date, source, the order recorded, then id.
  static func compare(_ a: JSONValue, _ b: JSONValue) -> Int {
    let date = IwRecords.textOrder(a["date"], b["date"])
    if date != 0 { return date }
    // An unknown source gives NaN on the web, which counts as equal.
    if let x = rank(a["sourceType"]), let y = rank(b["sourceType"]), x != y { return x < y ? -1 : 1 }
    let sequence = IwRecords.textOrder(a["sequence"], b["sequence"])
    if sequence != 0 { return sequence }
    return IwRecords.textOrder(a["id"], b["id"])
  }

  /// Running position of one item: quantity, value (minor units) and the last position with stock.
  private struct Position {
    var quantity = IwDecimal.zero
    var value = 0
    var last: (quantity: IwDecimal, value: Int)?
    /// Minor units per unit before the item had any cost (its cost price).
    var fallback: IwDecimal

    mutating func remember() {
      if !quantity.isZero { last = (quantity: quantity, value: value) }
    }

    /// The cost of one unit when nothing is in stock: the last one known.
    func lastUnit() -> IwDecimal {
      guard let last else { return fallback }
      return IwDecimal(last.value).dividedBy(last.quantity)
    }

    func averageUnit() -> IwDecimal {
      quantity.gt(.zero) ? IwDecimal(value).dividedBy(quantity) : lastUnit()
    }

    /// Stock coming in at `amount`; below zero, the units still in stock
    /// afterwards take the incoming cost.
    mutating func receive(_ incoming: IwDecimal, _ amount: Int) -> Int {
      var effect = amount
      if quantity.lt(.zero) {
        let after = quantity.plus(incoming)
        let valueAfter =
          after.gt(.zero)
          ? IwCosting.whole(IwDecimal(amount).times(after).dividedBy(incoming))
          : IwCosting.whole(IwDecimal(value).times(after).dividedBy(quantity))
        effect = valueAfter - value
      }
      quantity = quantity.plus(incoming)
      value += effect
      remember()
      return effect
    }

    /// Stock going out at the weighted average; the last units take what is left.
    mutating func issue(_ outgoing: IwDecimal) -> Int {
      let taken: Int
      if quantity.gt(.zero) {
        taken =
          outgoing.eq(quantity)
          ? value : IwCosting.whole(IwDecimal(value).times(outgoing).dividedBy(quantity))
      } else {
        taken = IwCosting.whole(outgoing.times(lastUnit()))
      }
      quantity = quantity.minus(outgoing)
      value -= taken
      remember()
      return -taken
    }

    /// Goods returned to a vendor leave at the value credited.
    mutating func returnToVendor(_ outgoing: IwDecimal, _ amount: Int) -> Int {
      if !quantity.gt(outgoing) { return issue(outgoing) }
      let taken = min(max(amount, 0), max(value, 0))
      quantity = quantity.minus(outgoing)
      value -= taken
      remember()
      return -taken
    }

    /// A landed cost raises the value of what is still in stock.
    mutating func addValue(_ amount: Int, _ basis: Double?) -> Int {
      if !quantity.gt(.zero) || amount == 0 { return 0 }
      var held = IwDecimal.one
      if let basis, basis != 0, basis > 0 { held = quantity.dividedBy(IwDecimal(basis)) }
      let share = held.gt(.one) ? IwDecimal.one : held
      let effect = max(IwCosting.whole(IwDecimal(amount).times(share)), -value)
      value += effect
      remember()
      return effect
    }
  }

  /// `toMinor(value, 0)`.
  static func whole(_ value: IwDecimal) -> Int {
    value.toDecimalPlaces(0).toInt()
  }

  /// `unitCostOf(minorPerUnit, scale)`: to 6 decimals, never -0.
  private static func unitCostOf(_ minorPerUnit: IwDecimal, _ scale: IwDecimal) -> Double {
    minorPerUnit.dividedBy(scale).toDecimalPlaces(6).toNumber()
  }

  /// `costMovements(movements, { precision, lockDate, fallbackUnitCost })`:
  /// the movements whose value or unit cost changed, with the new figures,
  /// in the order they were replayed.
  static func costMovements(
    _ movements: [JSONValue], precision p: Int, lockDate: String?, fallbackUnitCost: JSONValue?
  ) -> [JSONValue] {
    let scale = IwDecimal.power(p)
    // `10 ** p`, exact for the currencies' few decimals.
    var factor = 1.0
    for _ in 0..<max(0, p) { factor *= 10 }
    // Stored values have at most `p` decimals, so these are exact.
    func minorOf(_ amount: Double) -> Int {
      let scaled = IwMoney.jsRound(amount * factor)
      guard scaled.isFinite, Swift.abs(scaled) < 9.0e18 else { return 0 }
      return Int(scaled)
    }
    func amountOf(_ minor: Int) -> Double {
      // Number((minor / factor).toFixed(p)) || 0: the nearest number to the amount.
      let value = IwDecimal(minor).dividedBy(scale).toNumber()
      return value == 0 ? 0 : value
    }
    var position = Position(fallback: IwDecimal(WebJS.present(fallbackUnitCost) ?? .number(0)).times(scale))
    /// Quantity and value each invoice took out, for its credit notes.
    var sold: [String: (quantity: IwDecimal, value: Int)] = [:]
    var changed: [JSONValue] = []
    let sorted = movements.sorted { compare($0, $1) < 0 }

    for m in sorted {
      let quantity = IwDecimal(m["quantity"])
      let sourceType = m["sourceType"]?.string ?? ""
      let locked = lockDate.map { IwRecords.onOrBefore(m["date"], $0) } ?? false
      let storedValue = m["value"]?.double
      let sourceValue = WebJS.present(m["sourceValue"])?.double
      let basis = WebJS.present(m["basisQuantity"])?.double
      var value: Int
      var unit: IwDecimal

      if locked {
        value = minorOf(storedValue ?? 0)
        unit = IwDecimal(m["unitCost"]).times(scale)
        if sourceType != "transfer" {
          position.quantity = position.quantity.plus(quantity)
          position.value += value
          position.remember()
        }
      } else if sourceType == "transfer" {
        // Between warehouses neither the quantity nor the value changes.
        unit = position.averageUnit()
        value = whole(quantity.times(unit))
      } else if sourceType == "landed_cost" {
        let amount = minorOf(sourceValue ?? 0)
        value = position.addValue(amount, basis)
        if let basis, basis != 0 {
          unit = IwDecimal(amount).dividedBy(IwDecimal(basis))
        } else {
          unit = .zero
        }
      } else if quantity.gt(.zero) {
        let amount: Int
        if let sourceValue {
          amount = minorOf(sourceValue)
          unit = IwDecimal(amount).dividedBy(quantity)
        } else {
          let returnOf = m["returnOf"]
          let out: (quantity: IwDecimal, value: Int)? =
            sourceType == "credit" && WebJS.truthy(returnOf) ? sold[WebJS.string(returnOf)] : nil
          if let out, out.quantity.gt(.zero) {
            unit = IwDecimal(out.value).dividedBy(out.quantity)
          } else {
            unit = position.averageUnit()
          }
          amount = whole(quantity.times(unit))
        }
        value = position.receive(quantity, amount)
      } else if quantity.lt(.zero) {
        if let sourceValue {
          value = position.returnToVendor(quantity.negated(), -minorOf(sourceValue))
        } else {
          value = position.issue(quantity.negated())
        }
        unit = IwDecimal(-value).dividedBy(quantity.negated())
      } else {
        value = 0
        unit = position.averageUnit()
      }

      if sourceType == "invoice" && quantity.lt(.zero) {
        let key = WebJS.string(m["sourceId"])
        let out = sold[key] ?? (quantity: IwDecimal.zero, value: 0)
        sold[key] = (quantity: out.quantity.plus(quantity.negated()), value: out.value - value)
      }
      if locked { continue }
      let nextUnit = unitCostOf(unit, scale)
      let sameValue = storedValue.map { minorOf($0) == value } ?? false
      let sameUnit = m["unitCost"]?.double == nextUnit
      if !sameValue || !sameUnit {
        changed.append(m.iwWith(["value": .number(amountOf(value)), "unitCost": .number(nextUnit)]))
      }
    }
    return changed
  }
}
