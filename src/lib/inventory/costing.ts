import type { ID, ISODate, StockMovement, StockSourceType } from '@/db/types';
import { Decimal, dec, toMinor } from '@/lib/money';

/**
 * Weighted average costing (IAS 2). Every stock item keeps one average cost
 * across all warehouses. Movements are replayed in date order, so a bill
 * entered late (back-dated) re-costs everything sold after it. Movements on
 * or before the lock date keep the values they were posted with.
 *
 * All values are worked out in integer minor units (fils) of the company
 * currency; unit costs keep up to 6 decimals.
 */

/** Order of movements on the same day: stock comes in before it goes out; counts come last. */
export const SOURCE_RANK: Record<StockSourceType, number> = {
  opening: 0,
  bill: 1,
  landed_cost: 2,
  credit: 3,
  transfer: 4,
  invoice: 5,
  vendor_credit: 6,
  issue: 7,
  adjustment: 8,
};

export type CostingMovement = Pick<
  StockMovement,
  | 'id'
  | 'date'
  | 'quantity'
  | 'unitCost'
  | 'value'
  | 'sourceType'
  | 'sourceId'
  | 'sourceValue'
  | 'returnOf'
  | 'basisQuantity'
  | 'sequence'
>;

export function compareMovements(
  a: Pick<StockMovement, 'date' | 'sourceType' | 'sequence' | 'id'>,
  b: Pick<StockMovement, 'date' | 'sourceType' | 'sequence' | 'id'>,
): number {
  // Dates, sequences and ids are plain ASCII: compare them without locale rules.
  const text = (x: string, y: string) => (x < y ? -1 : x > y ? 1 : 0);
  return (
    text(a.date, b.date) ||
    SOURCE_RANK[a.sourceType] - SOURCE_RANK[b.sourceType] ||
    text(a.sequence, b.sequence) ||
    text(a.id, b.id)
  );
}

export interface CostingOptions {
  /** Minor-unit digits of the company currency (3 for KWD). */
  precision: number;
  /** Movements dated on or before this keep their stored values. */
  lockDate: ISODate | null;
  /** Cost of one unit before the item has any (its cost price), company currency. */
  fallbackUnitCost?: number;
}

/** Running position of one item: quantity, value in minor units and the last known unit cost. */
interface Position {
  quantity: Decimal;
  value: number;
  /** The last position with stock (or stock sold short), for its unit cost. */
  last: { quantity: Decimal; value: number } | null;
  /** Minor units per unit before the item had any cost (its cost price). */
  fallback: Decimal;
}

const whole = (value: Decimal): number => toMinor(value, 0);

function remember(position: Position): void {
  if (!position.quantity.isZero()) {
    position.last = { quantity: position.quantity, value: position.value };
  }
}

/** Cost of one unit (minor units) when nothing is in stock: the last one known. */
function lastUnit(position: Position): Decimal {
  const last = position.last;
  return last ? dec(last.value).dividedBy(last.quantity) : position.fallback;
}

function averageUnit(position: Position): Decimal {
  return position.quantity.gt(0)
    ? dec(position.value).dividedBy(position.quantity)
    : lastUnit(position);
}

/**
 * Stock coming in at `amount` minor units. When the item had gone below zero,
 * the units still in stock afterwards take the incoming cost; what the units
 * sold short really cost is the difference (it goes to cost of sales).
 */
function receive(position: Position, quantity: Decimal, amount: number): number {
  let effect = amount;
  if (position.quantity.lt(0)) {
    const after = position.quantity.plus(quantity);
    const valueAfter = after.gt(0)
      ? whole(dec(amount).times(after).dividedBy(quantity))
      : whole(dec(position.value).times(after).dividedBy(position.quantity));
    effect = valueAfter - position.value;
  }
  position.quantity = position.quantity.plus(quantity);
  position.value += effect;
  remember(position);
  return effect;
}

/** Stock going out at the weighted average cost; the last units take what is left exactly. */
function issue(position: Position, quantity: Decimal): number {
  let taken: number;
  if (position.quantity.gt(0)) {
    taken = quantity.eq(position.quantity)
      ? position.value
      : whole(dec(position.value).times(quantity).dividedBy(position.quantity));
  } else {
    taken = whole(quantity.times(lastUnit(position)));
  }
  position.quantity = position.quantity.minus(quantity);
  position.value -= taken;
  remember(position);
  return -taken;
}

/**
 * Goods returned to a vendor leave at the value credited, so the units that
 * stay keep their own cost. The value can't go below zero, and returning the
 * last units takes the stock's whole value; the rest is cost of sales.
 */
function returnToVendor(position: Position, quantity: Decimal, amount: number): number {
  if (!position.quantity.gt(quantity)) return issue(position, quantity);
  const taken = Math.min(Math.max(amount, 0), Math.max(position.value, 0));
  position.quantity = position.quantity.minus(quantity);
  position.value -= taken;
  remember(position);
  return -taken;
}

/**
 * A landed cost raises the value of the stock. When part of the quantity it
 * was allocated to has been sold, that part's share is cost of sales.
 */
function addValue(position: Position, amount: number, basis: number | null | undefined): number {
  if (!position.quantity.gt(0) || amount === 0) return 0;
  const held = basis && basis > 0 ? position.quantity.dividedBy(basis) : new Decimal(1);
  const share = held.gt(1) ? new Decimal(1) : held;
  const effect = Math.max(whole(dec(amount).times(share)), -position.value);
  position.value += effect;
  remember(position);
  return effect;
}

function unitCostOf(minorPerUnit: Decimal, scale: Decimal): number {
  const n = minorPerUnit.dividedBy(scale).toDecimalPlaces(6, Decimal.ROUND_HALF_UP).toNumber();
  return Object.is(n, -0) ? 0 : n;
}

/**
 * Replays an item's movements and returns those whose value or unit cost
 * changed, with the new figures (company currency).
 */
export function costMovements<T extends CostingMovement>(
  movements: T[],
  options: CostingOptions,
): T[] {
  const p = options.precision;
  const scale = new Decimal(10).pow(p);
  const factor = 10 ** p;
  // Stored values have at most `p` decimals, so these conversions are exact.
  const minorOf = (amount: number) => Math.round(amount * factor);
  const amountOf = (minor: number) => Number((minor / factor).toFixed(p)) || 0;
  const position: Position = {
    quantity: new Decimal(0),
    value: 0,
    last: null,
    fallback: dec(options.fallbackUnitCost ?? 0).times(scale),
  };
  /** Quantity and value each invoice took out, so credit notes bring goods back at that cost. */
  const sold = new Map<ID, { quantity: Decimal; value: number }>();
  const changed: T[] = [];
  const sorted = [...movements].sort(compareMovements);

  for (const m of sorted) {
    const quantity = dec(m.quantity);
    const locked = options.lockDate !== null && m.date <= options.lockDate;
    let value: number;
    let unit: Decimal;

    if (locked) {
      value = minorOf(m.value);
      unit = dec(m.unitCost).times(scale);
      if (m.sourceType !== 'transfer') {
        position.quantity = position.quantity.plus(quantity);
        position.value += value;
        remember(position);
      }
    } else if (m.sourceType === 'transfer') {
      // Moving stock between warehouses changes neither the quantity nor the value.
      unit = averageUnit(position);
      value = whole(quantity.times(unit));
    } else if (m.sourceType === 'landed_cost') {
      const amount = minorOf(m.sourceValue ?? 0);
      value = addValue(position, amount, m.basisQuantity);
      unit = m.basisQuantity ? dec(amount).dividedBy(m.basisQuantity) : new Decimal(0);
    } else if (quantity.gt(0)) {
      let amount: number;
      if (m.sourceValue !== null && m.sourceValue !== undefined) {
        amount = minorOf(m.sourceValue);
        unit = dec(amount).dividedBy(quantity);
      } else {
        const out = m.sourceType === 'credit' && m.returnOf ? sold.get(m.returnOf) : undefined;
        unit =
          out && out.quantity.gt(0)
            ? dec(out.value).dividedBy(out.quantity)
            : averageUnit(position);
        amount = whole(quantity.times(unit));
      }
      value = receive(position, quantity, amount);
    } else if (quantity.lt(0)) {
      const amount =
        m.sourceValue !== null && m.sourceValue !== undefined ? -minorOf(m.sourceValue) : null;
      value =
        amount === null
          ? issue(position, quantity.negated())
          : returnToVendor(position, quantity.negated(), amount);
      unit = dec(-value).dividedBy(quantity.negated());
    } else {
      value = 0;
      unit = averageUnit(position);
    }

    if (m.sourceType === 'invoice' && quantity.lt(0)) {
      const out = sold.get(m.sourceId) ?? { quantity: new Decimal(0), value: 0 };
      sold.set(m.sourceId, {
        quantity: out.quantity.plus(quantity.negated()),
        value: out.value - value,
      });
    }
    if (locked) continue;
    const nextUnit = unitCostOf(unit, scale);
    if (minorOf(m.value) !== value || m.unitCost !== nextUnit) {
      changed.push({ ...m, value: amountOf(value), unitCost: nextUnit });
    }
  }
  return changed;
}

/** Quantity and value of one item, in total and per warehouse. */
export interface StockLevel {
  productId: ID;
  quantity: number;
  /** Company currency. */
  value: number;
  /** Weighted average cost of one unit (company currency); 0 when nothing is in stock. */
  unitCost: number;
  byWarehouse: Map<ID, number>;
}

const round6 = (d: Decimal) => Number(d.toDecimalPlaces(6, Decimal.ROUND_HALF_UP).toString());

/** Stock levels of every item from its movements, optionally as at the end of a day. */
export function stockLevels(
  movements: Pick<StockMovement, 'productId' | 'warehouseId' | 'date' | 'quantity' | 'value'>[],
  precision: number,
  asAt?: ISODate,
): Map<ID, StockLevel> {
  const acc = new Map<ID, { quantity: Decimal; value: number; byWarehouse: Map<ID, Decimal> }>();
  for (const m of movements) {
    if (asAt && m.date > asAt) continue;
    let level = acc.get(m.productId);
    if (!level) {
      level = { quantity: new Decimal(0), value: 0, byWarehouse: new Map() };
      acc.set(m.productId, level);
    }
    const quantity = dec(m.quantity);
    level.quantity = level.quantity.plus(quantity);
    level.value += toMinor(m.value, precision);
    level.byWarehouse.set(
      m.warehouseId,
      (level.byWarehouse.get(m.warehouseId) ?? new Decimal(0)).plus(quantity),
    );
  }
  const scale = new Decimal(10).pow(precision);
  const result = new Map<ID, StockLevel>();
  for (const [productId, level] of acc) {
    const value = Number(dec(level.value).dividedBy(scale).toFixed(precision));
    result.set(productId, {
      productId,
      quantity: round6(level.quantity),
      value,
      unitCost: level.quantity.gt(0)
        ? unitCostOf(dec(level.value).dividedBy(level.quantity), scale)
        : 0,
      byWarehouse: new Map([...level.byWarehouse].map(([id, q]) => [id, round6(q)])),
    });
  }
  return result;
}
