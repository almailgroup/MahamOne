import Dexie, { type Table } from 'dexie';
import { db } from './db';
import { logActivity } from './activity';
import { accountingSettings } from './chart-setup';
import { defaultNumbering, nowStamp } from './defaults';
import { assertUnlocked, ensureSpecAccount, LockedPeriodError, roleMap } from './accounting';
import { freezeLockedPostings, sellsProduct } from './posting';
import type {
  AdjustmentReason,
  Company,
  ID,
  ISODate,
  LandedCost,
  LandedCostMethod,
  NumberingRule,
  Product,
  ProductKind,
  StockEntry,
  StockEntryKind,
  StockIssue,
  StockMovement,
  Warehouse,
  WarehouseKeeper,
} from './types';
import { costMovements } from '@/lib/inventory/costing';
import {
  allocateLandedCost,
  documentMovements,
  entryMovements,
  isStockItem,
  issueMovements,
  landedCostLinks,
  landedCostMovements,
  movesStock,
  STOCK_DOCUMENT_TYPES,
  stockAccounts,
  stockLines,
  type PlannedMovement,
  type StockSetup,
} from '@/lib/inventory/sources';
import { currencyPrecision, round } from '@/lib/money';
import { newId, shortId, stableId } from '@/lib/ids';
import { today } from '@/lib/dates';
import {
  allocateFrom,
  allocateNumber,
  canReserveCounters,
  reserveCounter,
  type ReservedCounter,
} from '@/lib/numbering';
import { msg, t } from '@/i18n';
import { localName } from '@/i18n/names';

/**
 * Inventory: warehouses, stock items, and the stock movements derived from
 * issued documents, stock entries and landed costs. Saving, voiding or
 * deleting a document re-plans its movements and re-costs the items it
 * touches in date order; periods on or before the lock date keep their values.
 */

export class InventoryError extends Error {}

/** Tables a stock update reads and writes. Transactions that save documents include them. */
export function stockTables(): Table[] {
  return [
    db.companies,
    db.documents,
    db.clients,
    db.products,
    db.accounts,
    db.activities,
    db.warehouses,
    db.stockMovements,
    db.stockEntries,
    db.landedCosts,
    db.stockIssues,
  ];
}

/** Whether the running transaction, if any, includes the stock tables. */
function stockReachable(): boolean {
  const outer = Dexie.currentTransaction;
  return !outer || stockTables().every((table) => outer.storeNames.includes(table.name));
}

/**
 * `tables` plus the stock tables, each once. Inside a transaction that
 * doesn't include them (seeding demo data) only `tables`: the stock follows
 * once that transaction is done (see syncDocumentStock).
 */
export function withStockTables(tables: Table[]): Table[] {
  if (!stockReachable()) return tables;
  const seen = new Set<string>();
  return [...tables, ...stockTables()].filter((table) => {
    if (seen.has(table.name)) return false;
    seen.add(table.name);
    return true;
  });
}

export function productKind(product: Pick<Product, 'kind'> | null | undefined): ProductKind {
  return product?.kind ?? 'service';
}

/* -------------------------------------------------------------------------- */
/* Warehouses                                                                 */
/* -------------------------------------------------------------------------- */

export function createWarehouse(companyId: ID, overrides: Partial<Warehouse> = {}): Warehouse {
  const stamp = nowStamp();
  return {
    id: newId(),
    companyId,
    name: '',
    nameAr: '',
    address: '',
    isDefault: false,
    archived: false,
    createdAt: stamp,
    updatedAt: stamp,
    ...overrides,
  };
}

/**
 * The warehouse documents use when a line names none. The first one,
 * "Main store", is created when the company has no warehouse yet.
 */
export async function ensureDefaultWarehouse(companyId: ID): Promise<Warehouse> {
  const all = await db.warehouses.where('companyId').equals(companyId).toArray();
  const found = all.find((w) => w.isDefault && !w.archived) ?? all.find((w) => !w.archived);
  if (found) {
    if (!found.isDefault) {
      const updated = { ...found, isDefault: true, updatedAt: nowStamp() };
      await db.warehouses.put(updated);
      return updated;
    }
    return found;
  }
  const warehouse = createWarehouse(companyId, {
    // The very first one has the same id on every device, so devices that
    // each need it at once (a company kept in the cloud) share one.
    ...(all.length === 0 ? { id: `${companyId}-main-store` } : {}),
    name: 'Main store',
    nameAr: 'المستودع الرئيسي',
    isDefault: true,
  });
  await db.warehouses.add(warehouse);
  return warehouse;
}

/** Creates the default warehouse when missing; safe to call from pages. */
export async function prepareInventory(companyId: ID): Promise<void> {
  const count = await db.warehouses.where('companyId').equals(companyId).count();
  if (count > 0) return;
  await db.transaction('rw', [db.warehouses], () => ensureDefaultWarehouse(companyId));
}

export async function saveWarehouse(input: Warehouse): Promise<Warehouse> {
  return db.transaction('rw', [db.warehouses, db.stockMovements, db.activities], async () => {
    const name = input.name.trim();
    if (!name) throw new InventoryError(t('Enter a name for the warehouse.'));
    const all = await db.warehouses.where('companyId').equals(input.companyId).toArray();
    const existing = all.find((w) => w.id === input.id);
    if (all.some((w) => w.id !== input.id && w.name.trim().toLowerCase() === name.toLowerCase())) {
      throw new InventoryError(t('Another warehouse already has this name.'));
    }
    if (input.archived && input.isDefault) {
      throw new InventoryError(t('Choose another default warehouse before archiving this one.'));
    }
    const parentId = input.parentId || null;
    if (parentId) {
      const parent = all.find((w) => w.id === parentId);
      if (!parent || parent.archived || parent.id === input.id) {
        throw new InventoryError(t('Choose the main warehouse this one belongs to.'));
      }
      if (parent.parentId) {
        throw new InventoryError(t('A sub-warehouse can’t have sub-warehouses of its own.'));
      }
      if (all.some((w) => w.parentId === input.id && !w.archived)) {
        throw new InventoryError(
          t('This warehouse has sub-warehouses, so it can’t become a sub-warehouse.'),
        );
      }
      if (input.isDefault) {
        throw new InventoryError(t('A sub-warehouse can’t be the default warehouse.'));
      }
    }
    if (input.archived && all.some((w) => w.parentId === input.id && !w.archived)) {
      throw new InventoryError(t('Archive its sub-warehouses before archiving this warehouse.'));
    }
    const warehouse: Warehouse = {
      ...input,
      name,
      nameAr: input.nameAr?.trim() ?? '',
      address: input.address.trim(),
      // The first warehouse is the default one; a sub-warehouse never is.
      isDefault:
        !parentId && (input.isDefault || !all.some((w) => w.id !== input.id && w.isDefault)),
      parentId,
      keeper: cleanKeeper(input.keeper),
      updatedAt: nowStamp(),
    };
    if (warehouse.isDefault) {
      for (const w of all) {
        if (w.id !== warehouse.id && w.isDefault) {
          await db.warehouses.put({ ...w, isDefault: false, updatedAt: warehouse.updatedAt });
        }
      }
    }
    await db.warehouses.put(warehouse);
    await logActivity(
      warehouse.companyId,
      'stock',
      warehouse.id,
      existing ? 'updated' : 'created',
      existing
        ? { text: msg('Warehouse {name} updated'), vars: { name } }
        : { text: msg('Warehouse {name} created'), vars: { name } },
    );
    return warehouse;
  });
}

/** The keeper as stored: trimmed, or null when it names nobody. */
function cleanKeeper(keeper: WarehouseKeeper | null | undefined): WarehouseKeeper | null {
  if (!keeper) return null;
  const name = keeper.name.trim();
  const userId = keeper.userId?.trim() || null;
  if (!name && !userId) return null;
  return {
    employeeId: keeper.employeeId || null,
    name,
    nameAr: keeper.nameAr?.trim() ?? '',
    jobTitle: keeper.jobTitle.trim(),
    jobTitleAr: keeper.jobTitleAr?.trim() ?? '',
    userId,
  };
}

/** Whether a warehouse is a sub-warehouse (it belongs to a main one). */
export function isSubWarehouse(warehouse: Pick<Warehouse, 'parentId'> | null | undefined): boolean {
  return Boolean(warehouse?.parentId);
}

/* -------------------------------------------------------------------------- */
/* Accounts                                                                   */
/* -------------------------------------------------------------------------- */

/**
 * Inventory (1200), cost of sales (5000) and inventory adjustments (5300),
 * created when the chart doesn't have them. Must run where the accounts and
 * activities tables are writable.
 */
export async function ensureStockAccounts(company: Company): Promise<void> {
  const accounts = await db.accounts.where('companyId').equals(company.id).toArray();
  const found = stockAccounts(accounts, accountingSettings(company).template);
  if (!found.inventory) await ensureSpecAccount(company, 'inventory');
  if (!found.costOfSales && !roleMap(accounts).cost_of_sales) {
    await ensureSpecAccount(company, 'costOfSales');
  }
  if (!found.adjustments) await ensureSpecAccount(company, 'inventoryAdjustments');
}

/**
 * The stock accounts and the expense account of items issued to employees
 * (6240), created when missing. Must run where the accounts and activities
 * tables are writable.
 */
export async function ensureIssueAccounts(company: Company): Promise<void> {
  await ensureStockAccounts(company);
  const accounts = await db.accounts.where('companyId').equals(company.id).toArray();
  if (!stockAccounts(accounts, accountingSettings(company).template).issuedItems) {
    await ensureSpecAccount(company, 'issuedItems');
  }
}

/* -------------------------------------------------------------------------- */
/* Movements                                                                  */
/* -------------------------------------------------------------------------- */

async function loadSetup(company: Company): Promise<StockSetup> {
  const [products, warehouses, clients] = await Promise.all([
    db.products.where('companyId').equals(company.id).toArray(),
    db.warehouses.where('companyId').equals(company.id).toArray(),
    db.clients.where('companyId').equals(company.id).toArray(),
  ]);
  const fallback = warehouses.find((w) => w.isDefault && !w.archived);
  const defaultWarehouse = fallback ?? (await ensureDefaultWarehouse(company.id));
  const exempt = new Set(clients.filter((c) => c.taxExempt).map((c) => c.id));
  return {
    companyCurrency: company.currency,
    precision: currencyPrecision(company.currency),
    products: new Set(products.filter(isStockItem).map((p) => p.id)),
    defaultWarehouseId: defaultWarehouse.id,
    warehouses: new Set([...warehouses.map((w) => w.id), defaultWarehouse.id]),
    taxExempt: (id) => exempt.has(id),
  };
}

const plannedKey = (m: PlannedMovement | StockMovement) =>
  JSON.stringify([
    m.productId,
    m.warehouseId,
    m.date,
    m.quantity,
    m.sourceValue,
    m.sourceType,
    m.lineId,
    m.documentId,
    m.number,
    m.returnOf ?? null,
    m.basisQuantity ?? null,
    m.sequence,
  ]);

const sameKeys = (a: string[], b: string[]) =>
  a.length === b.length && [...a].sort().join('\n') === [...b].sort().join('\n');

/**
 * Replaces a source's movements with the planned ones. Movements in a locked
 * period can't change: they stay as they are, and a change to them is
 * refused. Returns the items whose movements changed.
 */
async function replaceMovements(
  company: Company,
  existing: StockMovement[],
  planned: PlannedMovement[],
): Promise<ID[]> {
  const lock = accountingSettings(company).lockDate;
  const locked = (m: { date: ISODate }) => lock !== null && m.date <= lock;
  if (!sameKeys(existing.filter(locked).map(plannedKey), planned.filter(locked).map(plannedKey))) {
    throw new LockedPeriodError(lock!, company);
  }
  const before = existing.filter((m) => !locked(m));
  const after = planned.filter((m) => !locked(m));
  if (sameKeys(before.map(plannedKey), after.map(plannedKey))) return [];
  const stamp = nowStamp();
  const ids = movementIds(company.id, after);
  await db.stockMovements.bulkDelete(before.map((m) => m.id));
  await db.stockMovements.bulkAdd(
    after.map((m, i) => ({
      ...m,
      id: ids[i],
      companyId: company.id,
      unitCost: 0,
      value: 0,
      createdAt: stamp,
      updatedAt: stamp,
    })),
  );
  return [...new Set([...before, ...after].map((m) => m.productId))];
}

/**
 * Ids of planned movements follow from what they are, so two devices that
 * plan the same source (a company kept in the cloud) make the same movements
 * and their copies agree instead of adding up.
 */
function movementIds(companyId: ID, planned: PlannedMovement[]): string[] {
  const seen = new Map<string, number>();
  return planned.map((m) => {
    const key = `${companyId}|${m.sourceId}|${plannedKey(m)}`;
    const n = seen.get(key) ?? 0;
    seen.set(key, n + 1);
    return `sm-${stableId(`${key}|${n}`)}`;
  });
}

/**
 * Re-costs items at the weighted average, in date order, outside locked
 * periods, for example after an import changed their cost prices. Runs where
 * `stockTables()` are writable.
 */
export async function recost(company: Company, productIds: Iterable<ID>): Promise<void> {
  const ids = [...new Set(productIds)];
  if (ids.length === 0) return;
  const precision = currencyPrecision(company.currency);
  const lockDate = accountingSettings(company).lockDate;
  const stamp = nowStamp();
  const products = await db.products.bulkGet(ids);
  // Many items at once (an import): the company's movements are read in one go.
  let grouped: Map<ID, StockMovement[]> | null = null;
  if (ids.length > 20) {
    grouped = new Map();
    for (const m of await db.stockMovements.where('companyId').equals(company.id).toArray()) {
      const list = grouped.get(m.productId);
      if (list) list.push(m);
      else grouped.set(m.productId, [m]);
    }
  }
  const changed: StockMovement[] = [];
  for (const [index, productId] of ids.entries()) {
    const movements = grouped
      ? (grouped.get(productId) ?? [])
      : await db.stockMovements
          .where('[companyId+productId]')
          .equals([company.id, productId])
          .toArray();
    changed.push(
      ...costMovements(movements, {
        precision,
        lockDate,
        fallbackUnitCost: products[index]?.costPrice ?? 0,
      }),
    );
  }
  if (changed.length) {
    await db.stockMovements.bulkPut(changed.map((m) => ({ ...m, updatedAt: stamp })));
  }
}

async function activeLandedCosts(documentId: ID): Promise<LandedCost[]> {
  const [asCost, asTarget] = await Promise.all([
    db.landedCosts.where('billId').equals(documentId).toArray(),
    db.landedCosts.where('targetBillId').equals(documentId).toArray(),
  ]);
  const all = new Map([...asCost, ...asTarget].map((c) => [c.id, c]));
  return [...all.values()];
}

async function planLandedCost(cost: LandedCost, setup: StockSetup): Promise<PlannedMovement[]> {
  const [costBill, targetBill] = await Promise.all([
    db.documents.get(cost.billId),
    db.documents.get(cost.targetBillId),
  ]);
  const links = landedCostLinks(cost, costBill, targetBill, setup.products);
  if (!links || !costBill || !targetBill) return [];
  const { shares } = allocateLandedCost(cost, costBill, targetBill, links, setup);
  return landedCostMovements(cost, costBill, shares, setup.precision);
}

async function syncLandedCost(
  company: Company,
  cost: LandedCost,
  setup: StockSetup,
): Promise<ID[]> {
  const existing = await db.stockMovements.where('sourceId').equals(cost.id).toArray();
  return replaceMovements(company, existing, await planLandedCost(cost, setup));
}

/** Warehouse of each line's earlier movements, so a new default warehouse doesn't move history. */
function previousWarehouses(movements: StockMovement[]): Map<ID, ID> {
  return new Map(
    movements.filter((m) => m.lineId).map((m) => [m.lineId!, m.warehouseId] as [ID, ID]),
  );
}

/**
 * Brings a document's stock movements (and those of landed costs linked to
 * it) in line with the document as saved, voided or deleted, then re-costs
 * the items. Runs inside the transaction that changed the document, which
 * must include `stockTables()`. Documents without stock items cost nothing.
 */
export async function syncDocumentStock(companyId: ID, documentId: ID): Promise<void> {
  if (!stockReachable()) {
    Dexie.currentTransaction!.idbtrans.addEventListener('complete', () => {
      void db
        .transaction('rw', stockTables(), () => syncDocumentStock(companyId, documentId))
        .catch(() => undefined);
    });
    return;
  }
  const doc = await db.documents.get(documentId);
  const [existing, linked] = await Promise.all([
    db.stockMovements.where('sourceId').equals(documentId).toArray(),
    activeLandedCosts(documentId),
  ]);
  const productIds = [
    ...new Set((doc?.items ?? []).map((i) => i.productId).filter((id): id is ID => Boolean(id))),
  ];
  const products = productIds.length ? await db.products.bulkGet(productIds) : [];
  const hasStock = Boolean(
    doc && STOCK_DOCUMENT_TYPES.includes(doc.type) && products.some((p) => isStockItem(p)),
  );
  if (!hasStock && existing.length === 0 && linked.length === 0) return;
  const company = await db.companies.get(companyId);
  if (!company) return;
  if (hasStock && doc && movesStock(doc)) await ensureStockAccounts(company);
  const setup = await loadSetup(company);
  const planned = doc ? documentMovements(doc, setup, previousWarehouses(existing)) : [];
  const touched = await replaceMovements(company, existing, planned);
  for (const cost of linked) touched.push(...(await syncLandedCost(company, cost, setup)));
  await recost(company, touched);
}

/**
 * Re-plans and re-costs every movement of a company, for example after
 * restoring an old backup. Locked periods are left as they are.
 */
export async function rebuildStock(companyId: ID): Promise<void> {
  await db.transaction('rw', stockTables(), async () => {
    const company = await db.companies.get(companyId);
    if (!company) return;
    const lock = accountingSettings(company).lockDate;
    const setup = await loadSetup(company);
    const [documents, entries, costs, issues, movements] = await Promise.all([
      db.documents.where('companyId').equals(companyId).toArray(),
      db.stockEntries.where('companyId').equals(companyId).toArray(),
      db.landedCosts.where('companyId').equals(companyId).toArray(),
      db.stockIssues.where('companyId').equals(companyId).toArray(),
      db.stockMovements.where('companyId').equals(companyId).toArray(),
    ]);
    const bySource = new Map<ID, StockMovement[]>();
    for (const m of movements) {
      const list = bySource.get(m.sourceId);
      if (list) list.push(m);
      else bySource.set(m.sourceId, [m]);
    }
    const touched: ID[] = [];
    const sync = async (sourceId: ID, planned: PlannedMovement[]) => {
      try {
        touched.push(...(await replaceMovements(company, bySource.get(sourceId) ?? [], planned)));
      } catch (error) {
        // Movements of a locked period keep the values they were posted with.
        if (!(error instanceof LockedPeriodError)) throw error;
      }
      bySource.delete(sourceId);
    };
    for (const doc of documents) {
      if (!STOCK_DOCUMENT_TYPES.includes(doc.type)) continue;
      const before = bySource.get(doc.id) ?? [];
      await sync(doc.id, documentMovements(doc, setup, previousWarehouses(before)));
    }
    for (const entry of entries) await sync(entry.id, entryMovements(entry, setup));
    for (const cost of costs) await sync(cost.id, await planLandedCost(cost, setup));
    for (const issue of issues) await sync(issue.id, issueMovements(issue, setup));
    // Movements whose source is gone.
    for (const left of bySource.values()) {
      const open = left.filter((m) => lock === null || m.date > lock);
      await db.stockMovements.bulkDelete(open.map((m) => m.id));
      touched.push(...open.map((m) => m.productId));
    }
    await recost(company, [...touched, ...movements.map((m) => m.productId)]);
  });
}

/* -------------------------------------------------------------------------- */
/* Items                                                                      */
/* -------------------------------------------------------------------------- */

export interface OpeningStockInput {
  warehouseId: ID;
  quantity: number;
  unitCost: number;
  date: ISODate;
}

/** Whether an item has stock history (movements or stock entries). */
export async function hasStockHistory(product: Pick<Product, 'id' | 'companyId'>) {
  const [movements, entries] = await Promise.all([
    db.stockMovements
      .where('[companyId+productId]')
      .equals([product.companyId, product.id])
      .count(),
    db.stockEntries
      .where('companyId')
      .equals(product.companyId)
      .filter((e) => e.lines.some((l) => l.productId === product.id))
      .count(),
  ]);
  return movements + entries > 0;
}

/** SKUs compare without case or spaces at the ends. */
export const skuKey = (sku: string | null | undefined) => (sku ?? '').trim().toLowerCase();

/** The SKUs of the company's other items, as compared. */
async function takenSkus(companyId: ID, exceptId?: ID): Promise<Set<string>> {
  const products = await db.products.where('companyId').equals(companyId).toArray();
  return new Set(
    products
      .filter((p) => p.id !== exceptId)
      .map((p) => skuKey(p.sku))
      .filter(Boolean),
  );
}

/** The rule item codes are built with; companies made before it have none yet. */
export function itemCodeRule(company: Pick<Company, 'numbering'>) {
  return company.numbering.product ?? defaultNumbering().product;
}

/** The code a new item saved now without an SKU would get, for display before saving. */
export async function suggestItemCode(company: Company): Promise<string> {
  const taken = await takenSkus(company.id);
  return allocateNumber(itemCodeRule(company), today(), (n) => taken.has(skuKey(n))).number;
}

/**
 * For a new item without an SKU in a company that gives codes, kept in the
 * cloud: the next counter taken on the server while online, so two devices
 * never give the same code. Null to number on this device. A save that is
 * going to be refused takes none.
 */
async function reserveItemCounter(
  input: Product,
  opening: OpeningStockInput | null | undefined,
): Promise<ReservedCounter | null> {
  if (!canReserveCounters() || input.sku.trim() || Dexie.currentTransaction) return null;
  if (!input.name.trim() || (input.costPrice ?? 0) < 0 || (input.reorderLevel ?? 0) < 0) {
    return null;
  }
  if (await db.products.get(input.id)) return null;
  const company = await db.companies.get(input.companyId);
  if (!company?.items?.autoSku) return null;
  if (productKind(input) === 'stock' && opening && opening.quantity > 0) {
    try {
      assertUnlocked(company, opening.date);
    } catch {
      return null;
    }
  }
  const taken = await takenSkus(company.id, input.id);
  const local = allocateNumber(itemCodeRule(company), today(), (n) => taken.has(skuKey(n)));
  return reserveCounter({
    companyId: company.id,
    kind: 'product',
    date: today(),
    min: local.rule.next - 1,
  });
}

/**
 * Saves an item. A service or non-stock item that becomes a stock item
 * starts moving stock on its issued documents (none may be in a locked
 * period); a stock item with history stays one. A new stock item can get its
 * opening stock at the same time. A new item without an SKU gets the next
 * item code when the company gives codes (items.autoSku); such a company
 * also refuses an SKU another item has, archived ones included, when it is
 * new or changed. An item saved again with the SKU it had is never refused
 * (another device may have given it too).
 */
export async function saveItem(
  input: Product,
  options: { opening?: OpeningStockInput | null } = {},
): Promise<Product> {
  const reserved = await reserveItemCounter(input, options.opening);
  return db.transaction('rw', [...stockTables(), db.taxRates], async () => {
    const name = input.name.trim();
    if (!name) throw new InventoryError(t('Enter a name for the item.'));
    let company = await db.companies.get(input.companyId);
    if (!company) throw new InventoryError(t('Company not found'));
    const existing = await db.products.get(input.id);
    const kind = productKind(input);
    const wasStock = productKind(existing) === 'stock';
    const moved = existing
      ? await db.stockMovements
          .where('[companyId+productId]')
          .equals([existing.companyId, existing.id])
          .count()
      : 0;
    if (existing && wasStock && kind !== 'stock' && moved > 0) {
      throw new InventoryError(
        t(
          'This item has stock history, so it stays a stock item. Archive it if you no longer sell it.',
        ),
      );
    }
    if ((input.costPrice ?? 0) < 0) throw new InventoryError(t('The cost can’t be negative.'));
    if ((input.reorderLevel ?? 0) < 0) {
      throw new InventoryError(t('The reorder level can’t be negative.'));
    }
    let sku = input.sku.trim();
    const taken = await takenSkus(company.id, input.id);
    // Once the company gives codes (D1: items could always share an SKU before).
    if (
      company.items?.autoSku &&
      sku &&
      taken.has(skuKey(sku)) &&
      !(existing && skuKey(existing.sku) === skuKey(sku))
    ) {
      const other = await db.products
        .where('companyId')
        .equals(company.id)
        .filter((p) => p.id !== input.id && skuKey(p.sku) === skuKey(sku))
        .toArray();
      if (other.length > 0 && other.every((p) => p.archived)) {
        throw new InventoryError(
          t('The archived item {name} already has the SKU {sku}.', {
            name: localName(other[0]),
            sku,
          }),
        );
      }
      throw new InventoryError(t('Another item already has the SKU {sku}.', { sku }));
    }
    if (!sku && !existing && company.items?.autoSku) {
      const allocated = allocateFrom(
        itemCodeRule(company),
        today(),
        (n) => taken.has(skuKey(n)),
        '',
        reserved,
      );
      sku = allocated.number;
      company = { ...company, numbering: { ...company.numbering, product: allocated.rule } };
      await db.companies.put(company);
    }
    const product: Product = {
      ...input,
      name,
      sku,
      kind,
      costPrice: round(input.costPrice ?? 0, 6),
      barcode: input.barcode?.trim() ?? '',
      hsCode: input.hsCode?.trim() ?? '',
      reorderLevel: kind === 'stock' ? (input.reorderLevel ?? null) : null,
      updatedAt: nowStamp(),
    };
    // A unit typed by hand has no id.
    if (!product.unitId) delete product.unitId;
    // Changed only in db/product-images.ts: a form opened before a picture
    // was added doesn't take it away.
    const imageIds = existing ? existing.imageIds : input.imageIds;
    if (imageIds?.length) product.imageIds = imageIds;
    else delete product.imageIds;
    if (!existing) product.createdAt = product.updatedAt;
    if (existing && (existing.incomeAccountId ?? null) !== (product.incomeAccountId ?? null)) {
      // Sales of a closed period keep the income account they were posted to.
      await freezeLockedPostings(company, sellsProduct(existing.id));
    }
    await db.products.put(product);

    if (kind === 'stock') {
      await ensureStockAccounts(company);
      await ensureDefaultWarehouse(company.id);
    }
    if (existing && wasStock && kind === 'stock' && existing.costPrice !== product.costPrice) {
      // The cost price values sales made before any stock had a cost.
      await recost(company, [product.id]);
    }
    if (existing && wasStock !== (kind === 'stock')) {
      // Issued documents with the item start (or stop) moving stock.
      const documents = (await db.documents.where('companyId').equals(company.id).toArray()).filter(
        (d) => movesStock(d) && d.items.some((i) => i.productId === product.id),
      );
      const lock = accountingSettings(company).lockDate;
      if (lock && documents.some((d) => d.issueDate <= lock)) {
        throw new InventoryError(
          t(
            'This item is on documents in a locked period, so whether it is tracked in stock can’t change.',
          ),
        );
      }
      const setup = await loadSetup(company);
      const touched: ID[] = [];
      for (const doc of documents) {
        const movements = await db.stockMovements.where('sourceId').equals(doc.id).toArray();
        const planned = documentMovements(doc, setup, previousWarehouses(movements));
        touched.push(...(await replaceMovements(company, movements, planned)));
        for (const cost of await activeLandedCosts(doc.id)) {
          touched.push(...(await syncLandedCost(company, cost, setup)));
        }
      }
      await recost(company, touched);
    }
    if (kind === 'stock' && options.opening && options.opening.quantity > 0) {
      await addStockEntry(company, {
        kind: 'opening',
        date: options.opening.date,
        warehouseId: options.opening.warehouseId || (await ensureDefaultWarehouse(company.id)).id,
        reference: '',
        notes: '',
        lines: [
          {
            productId: product.id,
            quantity: options.opening.quantity,
            unitCost: options.opening.unitCost,
          },
        ],
      });
    }
    await logActivity(
      company.id,
      'product',
      product.id,
      existing ? 'updated' : 'created',
      existing
        ? { text: msg('Item {name} updated'), vars: { name } }
        : { text: msg('Item {name} created'), vars: { name } },
    );
    return product;
  });
}

/**
 * The next `count` item codes of the company, skipping codes in `taken` (as
 * compared, see skuKey; the codes given are added to it), and the rule after
 * them. The first comes from the cloud's counter when there is one; the rest
 * follow it.
 */
export function nextItemCodes(
  company: Pick<Company, 'numbering'>,
  taken: Set<string>,
  count: number,
  reserved: ReservedCounter | null,
): { codes: string[]; rule: NumberingRule } {
  const isTaken = (n: string) => taken.has(skuKey(n));
  let rule = itemCodeRule(company);
  const date = today();
  const codes: string[] = [];
  for (let index = 0; index < count; index++) {
    const allocated =
      index === 0
        ? allocateFrom(rule, date, isTaken, '', reserved)
        : allocateNumber(rule, date, isTaken);
    rule = allocated.rule;
    taken.add(skuKey(allocated.number));
    codes.push(allocated.number);
  }
  return { codes, rule };
}

/** The company's items that have no SKU and aren't archived, oldest first. */
function uncodedItems(products: Product[]): Product[] {
  return products
    .filter((p) => !p.archived && !p.sku.trim())
    .sort(
      (a, b) =>
        (a.createdAt ?? '').localeCompare(b.createdAt ?? '') || a.name.localeCompare(b.name),
    );
}

/** The first counter of a block of item codes taken on the server, and the last. */
export interface ReservedItemCodes extends ReservedCounter {
  last: number;
}

/**
 * For codes given to many items at once in a company kept in the cloud: the
 * first counter of the block, taken on the server, which then moves its
 * counter past the whole block so no other device gives one of them. The
 * block runs to the last code the items get, past the codes other items
 * already have. Null to number on this device. The block is the items
 * without a code, or `count` codes (new items of an import).
 */
export async function reserveItemCodes(
  companyId: ID,
  count?: number,
): Promise<ReservedItemCodes | null> {
  if (!canReserveCounters() || Dexie.currentTransaction) return null;
  const company = await db.companies.get(companyId);
  if (!company) return null;
  const products = await db.products.where('companyId').equals(companyId).toArray();
  count ??= uncodedItems(products).length;
  if (count === 0) return null;
  const taken = new Set(products.map((p) => skuKey(p.sku)).filter(Boolean));
  const date = today();
  const local = allocateNumber(itemCodeRule(company), date, (n) => taken.has(skuKey(n)));
  const first = await reserveCounter({
    companyId,
    kind: 'product',
    date,
    min: local.rule.next - 1,
  });
  if (!first) return null;
  const block = nextItemCodes(company, taken, count, first).rule;
  let last = block.period === first.period ? block.next - 1 : first.counter;
  if (last > first.counter) {
    last = (await reserveCounter({ companyId, kind: 'product', date, min: last }))?.counter ?? last;
  }
  return { ...first, last };
}

/**
 * After codes were given from a block taken on the server: when they went
 * past it (codes in a file took some of it), the server's counter is moved
 * past the last one too.
 */
export async function coverItemCodes(
  companyId: ID,
  reserved: ReservedItemCodes | null,
): Promise<void> {
  if (!reserved) return;
  const company = await db.companies.get(companyId);
  if (!company) return;
  const rule = itemCodeRule(company);
  if (rule.period !== reserved.period) return;
  const last = rule.next - 1;
  if (last > reserved.last) {
    await reserveCounter({ companyId, kind: 'product', date: today(), min: last });
  }
}

/**
 * Gives the next item codes to the company's items that have no SKU and
 * aren't archived, oldest first, in one go. Returns how many got one.
 */
export async function assignItemCodes(companyId: ID): Promise<number> {
  const reserved = await reserveItemCodes(companyId);
  const count = await db.transaction('rw', [db.companies, db.products, db.activities], async () => {
    const company = await db.companies.get(companyId);
    if (!company) throw new InventoryError(t('Company not found'));
    const products = await db.products.where('companyId').equals(companyId).toArray();
    const missing = uncodedItems(products);
    if (missing.length === 0) return 0;
    const taken = new Set(products.map((p) => skuKey(p.sku)).filter(Boolean));
    const { codes, rule } = nextItemCodes(company, taken, missing.length, reserved);
    const stamp = nowStamp();
    for (const [index, product] of missing.entries()) {
      await db.products.put({ ...product, sku: codes[index], updatedAt: stamp });
    }
    await db.companies.put({ ...company, numbering: { ...company.numbering, product: rule } });
    await logActivity(companyId, 'company', companyId, 'item_codes', {
      text: msg('Item codes given to {count} items'),
      vars: { count: missing.length },
    });
    return missing.length;
  });
  await coverItemCodes(companyId, reserved);
  return count;
}

/**
 * Deletes an item without stock history, with its pictures; documents keep
 * their copy of it.
 */
export async function deleteItem(id: ID): Promise<void> {
  await db.transaction(
    'rw',
    [db.products, db.stockMovements, db.stockEntries, db.attachments, db.activities],
    async () => {
      const product = await db.products.get(id);
      if (!product) return;
      if (await hasStockHistory(product)) {
        throw new InventoryError(t('This item has stock history. Archive it instead.'));
      }
      await db.attachments.bulkDelete(
        await db.attachments.where('ownerId').equals(id).primaryKeys(),
      );
      await db.products.delete(id);
      await logActivity(product.companyId, 'product', id, 'deleted', {
        text: msg('Item {name} deleted'),
        vars: { name: product.name },
        arabic: { name: product.nameAr },
      });
    },
  );
}

/* -------------------------------------------------------------------------- */
/* Stock entries: opening stock, adjustments, transfers                        */
/* -------------------------------------------------------------------------- */

export interface StockEntryInput {
  kind: StockEntryKind;
  date: ISODate;
  warehouseId: ID;
  toWarehouseId?: ID | null;
  reason?: AdjustmentReason | null;
  reference: string;
  notes: string;
  lines: { productId: ID; quantity: number; unitCost?: number | null }[];
}

const ENTRY_PREFIX: Record<StockEntryKind, string> = {
  opening: 'OPN',
  adjustment: 'ADJ',
  transfer: 'TRF',
};

function nextNumber(prefix: string, taken: string[]): string {
  const pattern = new RegExp(`^${prefix}-(\\d+)$`);
  const last = taken.reduce((max, n) => Math.max(max, Number(pattern.exec(n)?.[1] ?? 0)), 0);
  return `${prefix}-${String(last + 1).padStart(4, '0')}`;
}

/**
 * Records a stock entry inside a transaction that includes `stockTables()`
 * (recordStockEntry, saveItem and imports).
 */
export async function addStockEntry(company: Company, input: StockEntryInput): Promise<StockEntry> {
  assertUnlocked(company, input.date);
  const lines = input.lines.filter((l) => l.productId && l.quantity !== 0);
  if (lines.length === 0) throw new InventoryError(t('Add at least one item with a quantity.'));
  const products = await db.products.bulkGet(lines.map((l) => l.productId));
  if (products.some((p) => !p || p.companyId !== company.id || !isStockItem(p))) {
    throw new InventoryError(t('Only stock items can be added.'));
  }
  if (input.kind !== 'adjustment' && lines.some((l) => l.quantity < 0)) {
    throw new InventoryError(t('Quantities must be positive.'));
  }
  if (input.kind === 'opening' && lines.some((l) => !((l.unitCost ?? 0) >= 0))) {
    throw new InventoryError(t('The cost can’t be negative.'));
  }
  const warehouses = await db.warehouses.where('companyId').equals(company.id).toArray();
  const live = (id: ID | null | undefined) => warehouses.some((w) => w.id === id && !w.archived);
  if (!live(input.warehouseId)) throw new InventoryError(t('Choose a warehouse.'));
  if (input.kind === 'transfer') {
    if (!live(input.toWarehouseId)) throw new InventoryError(t('Choose where the stock goes.'));
    if (input.toWarehouseId === input.warehouseId) {
      throw new InventoryError(t('Choose two different warehouses.'));
    }
  }
  await ensureStockAccounts(company);
  const taken = (await db.stockEntries.where('companyId').equals(company.id).toArray()).map(
    (e) => e.number,
  );
  const stamp = nowStamp();
  const entry: StockEntry = {
    id: newId(),
    companyId: company.id,
    kind: input.kind,
    number: nextNumber(ENTRY_PREFIX[input.kind], taken),
    date: input.date,
    warehouseId: input.warehouseId,
    toWarehouseId: input.kind === 'transfer' ? (input.toWarehouseId ?? null) : null,
    reason: input.kind === 'adjustment' ? (input.reason ?? 'other') : null,
    reference: input.reference.trim(),
    notes: input.notes.trim(),
    lines: lines.map((l) => ({
      id: shortId(),
      productId: l.productId,
      quantity: l.quantity,
      unitCost: input.kind === 'opening' ? round(l.unitCost ?? 0, 6) : null,
    })),
    status: 'posted',
    voidedAt: null,
    createdAt: stamp,
    updatedAt: stamp,
  };
  await db.stockEntries.add(entry);
  const setup = await loadSetup(company);
  await recost(company, await replaceMovements(company, [], entryMovements(entry, setup)));
  const vars = { number: entry.number };
  await logActivity(
    company.id,
    'stock',
    entry.id,
    'posted',
    entry.kind === 'opening'
      ? { text: msg('Opening stock {number} recorded'), vars }
      : entry.kind === 'transfer'
        ? { text: msg('Stock transfer {number} recorded'), vars }
        : { text: msg('Stock adjustment {number} recorded'), vars },
  );
  return entry;
}

/** Records opening stock, an adjustment or a transfer. */
export async function recordStockEntry(companyId: ID, input: StockEntryInput): Promise<StockEntry> {
  return db.transaction('rw', stockTables(), async () => {
    const company = await db.companies.get(companyId);
    if (!company) throw new InventoryError(t('Company not found'));
    return addStockEntry(company, input);
  });
}

/** Voids a stock entry: it stays on record and its movements leave the books. */
export async function voidStockEntry(id: ID): Promise<void> {
  await db.transaction('rw', stockTables(), async () => {
    const entry = await db.stockEntries.get(id);
    if (!entry || entry.status === 'void') return;
    const company = await db.companies.get(entry.companyId);
    if (!company) return;
    assertUnlocked(company, entry.date);
    const stamp = nowStamp();
    await db.stockEntries.put({ ...entry, status: 'void', voidedAt: stamp, updatedAt: stamp });
    const existing = await db.stockMovements.where('sourceId').equals(id).toArray();
    await recost(company, await replaceMovements(company, existing, []));
    await logActivity(company.id, 'stock', id, 'void', {
      text: msg('Stock entry {number} voided'),
      vars: { number: entry.number },
    });
  });
}

/**
 * Brings the movements of items issued to an employee in line with the
 * issue as stored (posted or void), then re-costs the items. Runs inside a
 * transaction that includes `stockTables()`.
 */
export async function syncIssueStock(company: Company, issue: StockIssue): Promise<void> {
  const setup = await loadSetup(company);
  const existing = await db.stockMovements.where('sourceId').equals(issue.id).toArray();
  await recost(company, await replaceMovements(company, existing, issueMovements(issue, setup)));
}

/** The next free number of a kind of stock record, e.g. "ISS-0007". */
export function nextStockNumber(prefix: string, taken: string[]): string {
  return nextNumber(prefix, taken);
}

/* -------------------------------------------------------------------------- */
/* Landed costs                                                               */
/* -------------------------------------------------------------------------- */

export interface LandedCostInput {
  billId: ID;
  sourceLineIds: ID[];
  targetBillId: ID;
  targetLineIds: ID[];
  method: LandedCostMethod;
  notes: string;
}

/**
 * Allocates charges on a bill to the stock received on that bill or an
 * earlier one. The charges then post to inventory and raise the cost of the
 * items from the date of the bill with the charges.
 */
export async function saveLandedCost(companyId: ID, input: LandedCostInput): Promise<LandedCost> {
  return db.transaction('rw', stockTables(), async () => {
    const company = await db.companies.get(companyId);
    if (!company) throw new InventoryError(t('Company not found'));
    const [costBill, targetBill] = await Promise.all([
      db.documents.get(input.billId),
      db.documents.get(input.targetBillId),
    ]);
    const issuedBill = (d: typeof costBill) =>
      d && d.companyId === companyId && d.type === 'bill' && movesStock(d);
    if (!issuedBill(costBill) || !issuedBill(targetBill)) {
      throw new InventoryError(t('Both bills must be issued (not drafts or void).'));
    }
    if (targetBill!.issueDate > costBill!.issueDate) {
      throw new InventoryError(
        t('The bill with the charges must be dated on or after the bill with the goods.'),
      );
    }
    assertUnlocked(company, costBill!.issueDate);
    const setup = await loadSetup(company);
    const stockIds = new Set(stockLines(costBill!, setup.products).map((l) => l.id));
    const sourceLineIds = [...new Set(input.sourceLineIds)].filter((id) => !stockIds.has(id));
    if (sourceLineIds.length === 0) {
      throw new InventoryError(t('Choose the charges to add to the cost of the goods.'));
    }
    const others = (await db.landedCosts.where('billId').equals(costBill!.id).toArray()).filter(
      (c) => c.status === 'active',
    );
    if (others.some((c) => c.sourceLineIds.some((id) => sourceLineIds.includes(id)))) {
      throw new InventoryError(t('A charge on this bill is already allocated to stock.'));
    }
    const taken = (await db.landedCosts.where('companyId').equals(companyId).toArray()).map(
      (c) => c.number,
    );
    const stamp = nowStamp();
    const cost: LandedCost = {
      id: newId(),
      companyId,
      number: nextNumber('LC', taken),
      billId: costBill!.id,
      sourceLineIds,
      targetBillId: targetBill!.id,
      targetLineIds: [...new Set(input.targetLineIds)],
      method: input.method,
      notes: input.notes.trim(),
      status: 'active',
      voidedAt: null,
      createdAt: stamp,
      updatedAt: stamp,
    };
    if (!landedCostLinks(cost, costBill, targetBill, setup.products)) {
      throw new InventoryError(
        t('The bill with the goods has no stock items to receive the charges.'),
      );
    }
    await ensureStockAccounts(company);
    await db.landedCosts.add(cost);
    await recost(company, await syncLandedCost(company, cost, setup));
    await logActivity(company.id, 'stock', cost.id, 'created', {
      text: msg('Landed cost {number} allocated to {bill}'),
      vars: { number: cost.number, bill: targetBill!.number },
    });
    return cost;
  });
}

/** Voids a landed cost: the charges go back to their expense accounts. */
export async function voidLandedCost(id: ID): Promise<void> {
  await db.transaction('rw', stockTables(), async () => {
    const cost = await db.landedCosts.get(id);
    if (!cost || cost.status === 'void') return;
    const company = await db.companies.get(cost.companyId);
    if (!company) return;
    const costBill = await db.documents.get(cost.billId);
    assertUnlocked(company, costBill?.issueDate);
    const stamp = nowStamp();
    const voided: LandedCost = { ...cost, status: 'void', voidedAt: stamp, updatedAt: stamp };
    await db.landedCosts.put(voided);
    const existing = await db.stockMovements.where('sourceId').equals(id).toArray();
    await recost(company, await replaceMovements(company, existing, []));
    await logActivity(company.id, 'stock', id, 'void', {
      text: msg('Landed cost {number} voided'),
      vars: { number: cost.number },
    });
  });
}
