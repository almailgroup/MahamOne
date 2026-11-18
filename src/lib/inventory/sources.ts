import type {
  Account,
  ChartTemplateId,
  ID,
  InvoiceDocument,
  LandedCost,
  LineItem,
  Product,
  StockEntry,
  StockIssue,
  StockMovement,
} from '@/db/types';
import { allocate, documentLineParts, isPosted } from '@/lib/accounting/ledger';
import type { StockLedgerContext } from '@/lib/accounting/ledger';
import { findSpecAccount } from '@/lib/accounting/charts';
import { dec, fromMinor, round } from '@/lib/money';

/**
 * Where stock movements come from: issued bills, vendor credits, invoices and
 * credit notes, stock entries (opening stock, adjustments, transfers) and
 * landed costs. Movements are planned here without their cost; costing.ts
 * values them.
 */

/** A movement before it is stored and costed. */
export type PlannedMovement = Omit<
  StockMovement,
  'id' | 'companyId' | 'unitCost' | 'value' | 'createdAt' | 'updatedAt'
>;

/** Document types that move stock; other types (quotes, orders…) never do. */
export const STOCK_DOCUMENT_TYPES: readonly InvoiceDocument['type'][] = [
  'bill',
  'vendor_credit',
  'invoice',
  'credit',
];

export interface StockSetup {
  companyCurrency: string;
  precision: number;
  /** Ids of the stock items. */
  products: Set<ID>;
  defaultWarehouseId: ID;
  /** Warehouses that exist; lines pointing elsewhere use the default one. */
  warehouses: Set<ID>;
  taxExempt: (clientId: ID) => boolean;
}

export function isStockItem(product: Pick<Product, 'kind'> | null | undefined): boolean {
  return product?.kind === 'stock';
}

export function movesStock(doc: Pick<InvoiceDocument, 'type' | 'status'>): boolean {
  return STOCK_DOCUMENT_TYPES.includes(doc.type) && isPosted(doc);
}

/** Lines of a document that carry a stock item. */
export function stockLines(
  doc: Pick<InvoiceDocument, 'items'>,
  products: Set<ID>,
): (LineItem & { productId: ID })[] {
  return doc.items.filter(
    (i): i is LineItem & { productId: ID } =>
      i.kind === 'item' && Boolean(i.productId) && products.has(i.productId!),
  );
}

function warehouseOf(id: ID | null | undefined, setup: StockSetup): ID {
  return id && setup.warehouses.has(id) ? id : setup.defaultWarehouseId;
}

const order = (stamp: string, index: number, part = 0) =>
  `${stamp}|${String(index).padStart(4, '0')}|${part}`;

/**
 * Movements of an issued document: bills bring stock in at the line's value
 * in the company currency (after discounts, without tax, at the bill's
 * exchange rate); vendor credits take it out at the value credited; invoices
 * take it out and credit notes bring it back, both costed later.
 */
export function documentMovements(
  doc: InvoiceDocument,
  setup: StockSetup,
  /** Warehouse each line moved stock in before, kept when the line names none. */
  previous: Map<ID, ID> = new Map(),
): PlannedMovement[] {
  if (!movesStock(doc)) return [];
  const lines = stockLines(doc, setup.products).filter((i) => i.quantity !== 0);
  if (lines.length === 0) return [];
  const purchase = doc.type === 'bill' || doc.type === 'vendor_credit';
  const parts = purchase ? documentLineParts(doc, setup) : null;
  const direction = doc.type === 'bill' || doc.type === 'credit' ? 1 : -1;
  return lines.map((item) => ({
    productId: item.productId,
    warehouseId: warehouseOf(item.warehouseId ?? previous.get(item.id), setup),
    date: doc.issueDate,
    quantity: direction * item.quantity,
    sourceType: doc.type as PlannedMovement['sourceType'],
    sourceId: doc.id,
    lineId: item.id,
    documentId: doc.id,
    number: doc.number,
    sourceValue: parts ? fromMinor(direction * (parts.get(item.id) ?? 0), setup.precision) : null,
    returnOf: doc.type === 'credit' ? doc.sourceId : null,
    basisQuantity: null,
    sequence: order(doc.createdAt, doc.items.indexOf(item)),
    notes: '',
  }));
}

/** Movements of an opening stock entry, an adjustment or a transfer. */
export function entryMovements(entry: StockEntry, setup: StockSetup): PlannedMovement[] {
  if (entry.status !== 'posted') return [];
  const base = {
    date: entry.date,
    sourceType: entry.kind,
    sourceId: entry.id,
    documentId: null,
    number: entry.number,
    returnOf: null,
    basisQuantity: null,
    notes: '',
  };
  const from = warehouseOf(entry.warehouseId, setup);
  return entry.lines.flatMap((line, index): PlannedMovement[] => {
    if (!setup.products.has(line.productId) || line.quantity === 0) return [];
    const common = { ...base, productId: line.productId, lineId: line.id };
    if (entry.kind === 'transfer') {
      const to = warehouseOf(entry.toWarehouseId, setup);
      return [
        {
          ...common,
          warehouseId: from,
          quantity: -line.quantity,
          sourceValue: null,
          sequence: order(entry.createdAt, index, 0),
        },
        {
          ...common,
          warehouseId: to,
          quantity: line.quantity,
          sourceValue: null,
          sequence: order(entry.createdAt, index, 1),
        },
      ];
    }
    return [
      {
        ...common,
        warehouseId: from,
        quantity: line.quantity,
        sourceValue:
          entry.kind === 'opening'
            ? round(dec(line.quantity).times(dec(line.unitCost ?? 0)), setup.precision)
            : null,
        sequence: order(entry.createdAt, index),
      },
    ];
  });
}

/**
 * Movements of items issued to an employee: they leave the warehouse at the
 * weighted average cost. Void issues move nothing.
 */
export function issueMovements(issue: StockIssue, setup: StockSetup): PlannedMovement[] {
  if (issue.status !== 'posted') return [];
  const from = warehouseOf(issue.warehouseId, setup);
  return issue.lines.flatMap((line, index): PlannedMovement[] =>
    !setup.products.has(line.productId) || line.quantity === 0
      ? []
      : [
          {
            productId: line.productId,
            warehouseId: from,
            date: issue.date,
            quantity: -line.quantity,
            sourceType: 'issue',
            sourceId: issue.id,
            lineId: line.id,
            documentId: null,
            number: issue.number,
            sourceValue: null,
            returnOf: null,
            basisQuantity: null,
            sequence: order(issue.createdAt, index),
            notes: '',
          },
        ],
  );
}

/** Lines of the bills a landed cost links, or null when it has no effect. */
export interface LandedCostLinks {
  /** Lines and charges of the bill with the charges that post to inventory. */
  sourceIds: ID[];
  /** Stock lines that receive a share. */
  targets: (LineItem & { productId: ID })[];
}

/**
 * A landed cost counts while it is active, both bills are issued, the
 * charges are lines or charges of the first bill (not stock lines), and the
 * second bill still has stock received on it.
 */
export function landedCostLinks(
  cost: LandedCost,
  costBill: InvoiceDocument | undefined,
  targetBill: InvoiceDocument | undefined,
  products: Set<ID>,
): LandedCostLinks | null {
  if (cost.status !== 'active' || !costBill || !targetBill) return null;
  if (costBill.type !== 'bill' || targetBill.type !== 'bill') return null;
  if (!isPosted(costBill) || !isPosted(targetBill)) return null;
  const stockIds = new Set(stockLines(costBill, products).map((l) => l.id));
  const available = new Set(
    [...costBill.items.filter((i) => i.kind === 'item'), ...costBill.charges].map((l) => l.id),
  );
  const sourceIds = cost.sourceLineIds.filter((id) => available.has(id) && !stockIds.has(id));
  const targets = stockLines(targetBill, products).filter(
    (l) => l.quantity > 0 && (cost.targetLineIds.length === 0 || cost.targetLineIds.includes(l.id)),
  );
  if (sourceIds.length === 0 || targets.length === 0) return null;
  return { sourceIds, targets };
}

/** One stock line's share of a landed cost, in minor units of the company currency. */
export interface LandedCostShare {
  lineId: ID;
  productId: ID;
  warehouseId: ID;
  quantity: number;
  /** Value of the line received (minor units), the basis of an allocation by value. */
  lineValue: number;
  share: number;
}

/**
 * Splits the charges over the stock lines by value or by quantity. The
 * shares add up to the charges exactly.
 */
export function allocateLandedCost(
  cost: Pick<LandedCost, 'method'>,
  costBill: InvoiceDocument,
  targetBill: InvoiceDocument,
  links: LandedCostLinks,
  setup: StockSetup,
): { total: number; shares: LandedCostShare[] } {
  const costParts = documentLineParts(costBill, setup);
  const targetParts =
    targetBill.id === costBill.id ? costParts : documentLineParts(targetBill, setup);
  const total = links.sourceIds.reduce((acc, id) => acc + (costParts.get(id) ?? 0), 0);
  const weights = links.targets.map((l) =>
    cost.method === 'quantity' ? dec(l.quantity) : dec(targetParts.get(l.id) ?? 0),
  );
  const shares = allocate(total, weights);
  return {
    total,
    shares: links.targets.map((l, i) => ({
      lineId: l.id,
      productId: l.productId,
      warehouseId: warehouseOf(l.warehouseId, setup),
      quantity: l.quantity,
      lineValue: targetParts.get(l.id) ?? 0,
      share: shares[i],
    })),
  };
}

/** Value-only movements of a landed cost, dated like the bill with the charges. */
export function landedCostMovements(
  cost: LandedCost,
  costBill: InvoiceDocument,
  shares: LandedCostShare[],
  precision: number,
): PlannedMovement[] {
  return shares.map((s, index) => ({
    productId: s.productId,
    warehouseId: s.warehouseId,
    date: costBill.issueDate,
    quantity: 0,
    sourceType: 'landed_cost',
    sourceId: cost.id,
    lineId: s.lineId,
    documentId: costBill.id,
    number: cost.number,
    sourceValue: fromMinor(s.share, precision),
    returnOf: null,
    basisQuantity: s.quantity,
    sequence: order(cost.createdAt, index),
    notes: '',
  }));
}

/** The accounts stock posts to; cost of sales is the account with that role when there is one. */
export function stockAccounts(
  accounts: Account[],
  template: ChartTemplateId,
): {
  inventory?: Account;
  costOfSales?: Account;
  adjustments?: Account;
  issuedItems?: Account;
} {
  const live = [...accounts].sort((a, b) => Number(a.archived) - Number(b.archived));
  return {
    inventory: findSpecAccount(accounts, 'inventory', template),
    costOfSales:
      live.find((a) => a.role === 'cost_of_sales') ??
      findSpecAccount(accounts, 'costOfSales', template),
    adjustments: findSpecAccount(accounts, 'inventoryAdjustments', template),
    issuedItems: findSpecAccount(accounts, 'issuedItems', template),
  };
}

/** What the ledger needs to post stock (see buildLedger). */
export function stockLedgerContext(data: {
  accounts: Account[];
  products: Pick<Product, 'id' | 'kind'>[];
  landedCosts: LandedCost[];
  documents: Map<ID, InvoiceDocument>;
  template: ChartTemplateId;
}): StockLedgerContext {
  const products = new Set(data.products.filter(isStockItem).map((p) => p.id));
  const accounts = stockAccounts(data.accounts, data.template);
  const landedCostLines = new Set<string>();
  for (const cost of data.landedCosts) {
    const links = landedCostLinks(
      cost,
      data.documents.get(cost.billId),
      data.documents.get(cost.targetBillId),
      products,
    );
    for (const id of links?.sourceIds ?? []) landedCostLines.add(`${cost.billId}:${id}`);
  }
  return {
    products,
    inventoryAccountId: accounts.inventory?.id ?? null,
    costOfSalesAccountId: accounts.costOfSales?.id ?? null,
    adjustmentAccountId: accounts.adjustments?.id ?? null,
    issuedItemsAccountId: accounts.issuedItems?.id ?? null,
    landedCostLines,
  };
}
