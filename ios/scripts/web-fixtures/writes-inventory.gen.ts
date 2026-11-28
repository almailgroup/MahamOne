// The web's own outputs for the inventory ports (MahamKit/Write/Inventory):
// warehouses, items and their codes, stock entries (opening stock,
// adjustments, transfers), landed costs, items issued to employees, the
// stock movements of documents and their costing at the weighted average.
// From the repository root:
//   npx vitest run --config ios/scripts/web-fixtures/writes.gen.config.mjs writes-inventory
// writes ios/MahamKit/Tests/MahamKitTests/Fixtures/writes-inventory.json.
//
// Each scenario's `input` says what the Swift side runs (`action` and its
// arguments, see WriteInventoryTests.swift). Documents are stored as they
// would be saved (db.documents.put) and their stock synced with
// syncDocumentStock, so these scenarios depend on no other area's port.
import { vi } from 'vitest';
vi.mock('@/lib/ids', async (load) => ({
  ...(await load<typeof import('@/lib/ids')>()),
  ...(await import('./writes-ids')).fixedIds(),
}));
import { scenario, writeFixtures, type Scenario } from './writes-harness';
import { db } from '@/db/db';
import { createClient, createDocument, createProduct } from '@/db/defaults';
import { saveClient, saveCompany, setupCompany } from '@/db/records';
import {
  assignItemCodes,
  createWarehouse,
  deleteItem,
  ensureDefaultWarehouse,
  rebuildStock,
  recordStockEntry,
  recost,
  saveItem,
  saveLandedCost,
  saveWarehouse,
  stockTables,
  syncDocumentStock,
  voidLandedCost,
  voidStockEntry,
} from '@/db/inventory';
import { applyStockIssueRequest, issueStock, voidStockIssue } from '@/db/stock-issues';
import { setCounterReserver } from '@/lib/numbering';

const NOW = '2026-11-28T09:00:00.000Z';
const USER = { userId: 'u-owner', userName: 'Sample Owner' };

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Any = any;

interface World {
  companyId: string;
  vendorId: string;
  customerId: string;
  paper: Any;
  mainId: string;
}

const empty = (): World => ({ companyId: '', vendorId: '', customerId: '', paper: null, mainId: '' });

const clone = <T>(value: T): T => JSON.parse(JSON.stringify(value));

async function company(id: string): Promise<Any> {
  return (await db.companies.get(id))!;
}

/** A company with a vendor, a customer and a stock item (printer paper). */
async function books(paper: Any = {}): Promise<World> {
  const c = await setupCompany({ name: 'Gulf Trading' });
  const vendor = await saveClient(
    createClient(c.id, { name: 'Shuwaikh Imports', isVendor: true, isCustomer: false } as Any),
  );
  const customer = await saveClient(createClient(c.id, { name: 'Al Noor' }));
  const item = await saveItem(
    createProduct(c.id, {
      name: 'Printer paper',
      nameAr: 'ورق طابعة',
      kind: 'stock',
      unit: 'box',
      unitPrice: 2.5,
      ...paper,
    } as Any),
  );
  const main = (await db.warehouses.where('companyId').equals(c.id).first())!;
  return { companyId: c.id, vendorId: vendor.id, customerId: customer.id, paper: item, mainId: main.id };
}

/** A stock item of the company, saved as the item form saves it. */
async function stockItem(w: World, name: string, extra: Any = {}): Promise<Any> {
  return saveItem(createProduct(w.companyId, { name, kind: 'stock', unit: 'pcs', ...extra } as Any));
}

/** A full line, as the editor makes one. */
function line(p: Any): Any {
  return {
    id: 'line',
    kind: 'item',
    productId: null,
    name: '',
    description: '',
    quantity: 1,
    unit: '',
    unitPrice: 0,
    discount: 0,
    discountType: 'percent',
    taxes: [],
    ...p,
  };
}

let docCount = 0;

/** A document stored as issued (not yet costed): its lines `items`. */
async function putDoc(w: World, type: string, date: string, items: Any[], extra: Any = {}): Promise<Any> {
  docCount += 1;
  const purchase = type === 'bill' || type === 'vendor_credit';
  const doc = createDocument(w.companyId, type as Any, {
    clientId: purchase ? w.vendorId : w.customerId,
    issueDate: date,
    status: 'sent',
    number: `${type.toUpperCase()}-${String(docCount).padStart(4, '0')}`,
    items: items.map((i, index) => line({ id: `l${index + 1}`, ...i })),
    ...extra,
  } as Any);
  await db.documents.put(doc);
  return doc;
}

/** A document stored and its stock synced, as saving it does. */
async function issued(w: World, type: string, date: string, items: Any[], extra: Any = {}): Promise<Any> {
  const doc = await putDoc(w, type, date, items, extra);
  await syncDocumentStock(w.companyId, doc.id);
  return doc;
}

const paperLine = (w: World, quantity: number, unitPrice: number, extra: Any = {}) => ({
  productId: w.paper.id,
  name: 'Printer paper',
  quantity,
  unitPrice,
  ...extra,
});

async function lockAt(w: World, date: string) {
  const c = await company(w.companyId);
  await saveCompany({ ...c, accounting: { ...c.accounting, lockDate: date } });
}

/** Links the company to the cloud for a person (`db.syncState`). */
async function link(w: World, role: string, userId = USER.userId, options: Any = {}) {
  const features = options.features ?? ['tables_v16', 'approvals', 'stock_issues'];
  await db.syncState.put({
    companyId: w.companyId,
    userId,
    role,
    status: 'ready',
    cursor: 1,
    name: 'Company',
    linkedAt: NOW,
    lastSyncAt: null,
    lastError: null,
    lastErrorAt: null,
    features,
    ...(options.approver ? { approver: true } : {}),
  } as Any);
  return { role, userId, approver: Boolean(options.approver), features };
}

let moveCount = 0;

/** A stock movement as stored before it is costed (costing.test.ts's `move`). */
function move(w: World, date: string, sourceType: string, quantity: number, extra: Any = {}): Any {
  moveCount += 1;
  const n = String(moveCount).padStart(3, '0');
  return {
    id: `m${n}`,
    companyId: w.companyId,
    productId: w.paper.id,
    warehouseId: w.mainId,
    date,
    quantity,
    unitCost: 0,
    value: 0,
    sourceType,
    sourceId: extra.sourceId ?? `s${n}`,
    lineId: null,
    documentId: null,
    number: '',
    sourceValue: null,
    returnOf: null,
    basisQuantity: null,
    sequence: String(moveCount).padStart(4, '0'),
    notes: '',
    createdAt: '',
    updatedAt: '',
    ...extra,
  };
}

const out: Scenario[] = [];

/**
 * Runs `body` in a transaction of the stock tables, as saving a document
 * does. fake-indexeddb can finish such a transaction a tick before the
 * function's last `await` has unwound once every write is done (Dexie then
 * reports "committed too early"); the writes are all there, so that alone
 * is not a refusal.
 */
async function inStock(body: () => Promise<unknown>): Promise<void> {
  try {
    await db.transaction('rw', stockTables(), body);
  } catch (e) {
    if ((e as Any)?.name !== 'PrematureCommitError') throw e;
  }
}

/** Runs a scenario; the cloud's bookkeeping tables stay out of the fixtures. */
async function run(name: string, input: Any, seed: () => Promise<void>, action: () => Promise<unknown>) {
  docCount = 0;
  moveCount = 0;
  const s = await scenario(name, { now: NOW, ...USER, input, seed }, action);
  for (const tables of [s.before, s.after]) {
    for (const table of ['meta', 'syncState', 'outbox', 'syncRevs', 'fileQueue']) delete tables[table];
  }
  out.push(s);
}

const GUARD = {
  employeeId: 'emp-guard',
  number: ' E-0007 ',
  name: ' Mohammed Ahmed ',
  nameAr: 'محمد أحمد',
  jobTitle: 'Security Guard',
  jobTitleAr: 'حارس أمن',
};
const KEEPER = 'user-keeper';

interface Uniforms extends World {
  storeId: string;
  trouser: Any;
  shirt: Any;
}

/** A main warehouse with uniforms, and Ahmed's store with some of them (stock-issues.test.ts). */
async function uniforms(): Promise<Uniforms> {
  const c = await setupCompany({ name: 'Gulf Pearl Security', currency: 'KWD' });
  const main = await ensureDefaultWarehouse(c.id);
  const store = await saveWarehouse(
    createWarehouse(c.id, {
      name: '  Ahmed’s store ',
      parentId: main.id,
      keeper: { employeeId: 'emp-ahmed', name: ' Ahmed Saleh ', jobTitle: 'Warehouse Supervisor', userId: KEEPER },
    } as Any),
  );
  const trouser = await saveItem(
    createProduct(c.id, { name: 'Trouser', nameAr: 'بنطلون', kind: 'stock', unit: 'pcs' } as Any),
  );
  const shirt = await saveItem(
    createProduct(c.id, { name: 'T-shirt', nameAr: 'قميص', kind: 'stock', unit: 'pcs' } as Any),
  );
  await recordStockEntry(c.id, {
    kind: 'opening',
    date: '2026-11-01',
    warehouseId: main.id,
    reference: '',
    notes: '',
    lines: [
      { productId: trouser.id, quantity: 20, unitCost: 4 },
      { productId: shirt.id, quantity: 30, unitCost: 2.125 },
    ],
  });
  await recordStockEntry(c.id, {
    kind: 'transfer',
    date: '2026-11-02',
    warehouseId: main.id,
    toWarehouseId: store.id,
    reference: '',
    notes: '',
    lines: [
      { productId: trouser.id, quantity: 5 },
      { productId: shirt.id, quantity: 10 },
    ],
  });
  return {
    companyId: c.id,
    vendorId: '',
    customerId: '',
    paper: trouser,
    mainId: main.id,
    storeId: store.id,
    trouser,
    shirt,
  };
}

function issueOf(u: Uniforms, trousers = 1, shirts = 1, extra: Any = {}): Any {
  return {
    date: '2026-11-03',
    warehouseId: u.storeId,
    recipient: GUARD,
    lines: [
      { productId: u.trouser.id, quantity: trousers },
      { productId: u.shirt.id, quantity: shirts },
    ],
    notes: ' New joiner ',
    ...extra,
  };
}

it('inventory', async () => {
  // The outbox's capture names each transaction's group with a shortId(),
  // which would take ids from the scenario's counter; on the iPhone the sync
  // engine groups the action's changes itself. (Its refusals are the
  // engine's WriteRules, tested apart.)
  db.close();
  db.unuse({ stack: 'dbcore', name: 'MahamBooksOutbox' } as Any);
  let w: World = empty();
  let doc: Any = null;

  // ------------------------------------------------------------ documents move stock

  // In a transaction, as saving a document runs it: a refusal leaves nothing behind.
  const sync = (input: Any) => async () =>
    inStock(() => syncDocumentStock(w.companyId, input.documentId));

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a bill brings stock in at its value', input, async () => {
      w = await books();
      doc = await putDoc(w, 'bill', '2026-10-01', [paperLine(w, 10, 1.25)]);
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('an invoice takes stock out at the weighted average', input, async () => {
      w = await books();
      await issued(w, 'bill', '2026-10-01', [paperLine(w, 10, 1.25)]);
      await issued(w, 'bill', '2026-10-02', [paperLine(w, 10, 1.5)]);
      doc = await putDoc(w, 'invoice', '2026-10-03', [paperLine(w, 5, 2.5)]);
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a bill entered back-dated re-costs a later sale', input, async () => {
      w = await books();
      await issued(w, 'bill', '2026-10-01', [paperLine(w, 10, 1)]);
      await issued(w, 'invoice', '2026-10-10', [paperLine(w, 5, 3)]);
      doc = await putDoc(w, 'bill', '2026-10-05', [paperLine(w, 10, 2)]);
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a credit note brings goods back at the cost they left with', input, async () => {
      w = await books();
      await issued(w, 'bill', '2026-10-01', [paperLine(w, 10, 1)]);
      const invoice = await issued(w, 'invoice', '2026-10-02', [paperLine(w, 4, 3)]);
      await issued(w, 'bill', '2026-10-03', [paperLine(w, 10, 2)]);
      doc = await putDoc(w, 'credit', '2026-10-04', [paperLine(w, 1, 3)], { sourceId: invoice.id });
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a credit note without its invoice comes back at the average', input, async () => {
      w = await books();
      await issued(w, 'bill', '2026-10-01', [paperLine(w, 3, 1.001)]);
      await issued(w, 'invoice', '2026-10-02', [paperLine(w, 1, 3)]);
      doc = await putDoc(w, 'credit', '2026-10-04', [paperLine(w, 0.5, 3)]);
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a bill edited: fewer goods at a new price', input, async () => {
      w = await books();
      doc = await issued(w, 'bill', '2026-10-01', [paperLine(w, 10, 1.25)]);
      await issued(w, 'invoice', '2026-10-05', [paperLine(w, 4, 3)]);
      await db.documents.put({ ...doc, items: [{ ...doc.items[0], quantity: 8, unitPrice: 1.5 }] });
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a bill voided: the sale is costed at the cost price', input, async () => {
      w = await books({ costPrice: 1.1 });
      doc = await issued(w, 'bill', '2026-10-01', [paperLine(w, 10, 1.25)]);
      await issued(w, 'invoice', '2026-10-05', [paperLine(w, 4, 3)]);
      await db.documents.put({ ...doc, status: 'void' });
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a bill deleted takes its stock with it', input, async () => {
      w = await books();
      doc = await issued(w, 'bill', '2026-10-01', [paperLine(w, 10, 1.25)]);
      await issued(w, 'bill', '2026-10-02', [paperLine(w, 2, 2)]);
      await issued(w, 'invoice', '2026-10-05', [paperLine(w, 4, 3)]);
      await db.documents.delete(doc.id);
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a bill with a service line, a delivery charge and a discount', input, async () => {
      w = await books();
      doc = await putDoc(
        w,
        'bill',
        '2026-10-01',
        [paperLine(w, 3, 1.111), { name: 'Installation', quantity: 1, unitPrice: 0.5 }],
        { discount: 5, discountType: 'percent', charges: [{ id: 'ch1', label: 'Delivery', amount: 0.75, taxes: [] }] },
      );
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a bill with tax on its lines: stock without the tax', input, async () => {
      w = await books();
      const vat = [{ name: 'VAT', rate: 5, kind: 'standard' }];
      doc = await putDoc(w, 'bill', '2026-10-01', [
        paperLine(w, 7, 1.237, { taxes: vat, discount: 2.5, discountType: 'percent' }),
        paperLine(w, 3, 0.333, { id: 'l9', taxes: vat, discount: 0.1, discountType: 'amount' }),
      ]);
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a bill with prices that include tax and a document discount', input, async () => {
      w = await books();
      const vat = [{ name: 'VAT', rate: 5, kind: 'standard' }];
      const toner = await stockItem(w, 'Toner');
      doc = await putDoc(
        w,
        'bill',
        '2026-10-01',
        [
          paperLine(w, 3, 1.1, { taxes: vat }),
          { productId: toner.id, name: 'Toner', quantity: 7, unitPrice: 2.345, taxes: vat },
          { name: 'Freight', quantity: 1, unitPrice: 1, taxes: [{ name: 'Import', rate: 15, kind: 'reverse_charge' }] },
        ],
        { pricesIncludeTax: true, discount: 1.234, discountType: 'amount' },
      );
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a foreign-currency bill at its exchange rate', input, async () => {
      w = await books();
      doc = await putDoc(w, 'bill', '2026-10-01', [paperLine(w, 4, 25)], { currency: 'USD', exchangeRate: 0.3075 });
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a vendor credit returns goods at the value credited', input, async () => {
      w = await books();
      await issued(w, 'bill', '2026-10-01', [paperLine(w, 10, 1)]);
      await issued(w, 'bill', '2026-10-02', [paperLine(w, 10, 2)]);
      await issued(w, 'invoice', '2026-10-04', [paperLine(w, 15, 3)]);
      doc = await putDoc(w, 'vendor_credit', '2026-10-03', [paperLine(w, 5, 2)]);
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('returning the last units to a vendor takes their whole value', input, async () => {
      w = await books();
      await issued(w, 'bill', '2026-10-01', [paperLine(w, 2, 1.5)]);
      doc = await putDoc(w, 'vendor_credit', '2026-10-02', [paperLine(w, 2, 2)]);
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('stock sold short takes the cost of the bill that brings it in', input, async () => {
      w = await books({ costPrice: 1 });
      await issued(w, 'invoice', '2026-10-01', [paperLine(w, 2, 3)]);
      await issued(w, 'invoice', '2026-10-03', [paperLine(w, 8, 3)]);
      doc = await putDoc(w, 'bill', '2026-10-02', [paperLine(w, 10, 1.5)]);
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a draft invoice moves no stock', input, async () => {
      w = await books();
      await issued(w, 'bill', '2026-10-01', [paperLine(w, 10, 1)]);
      doc = await putDoc(w, 'invoice', '2026-10-02', [paperLine(w, 2, 3)], { status: 'draft' });
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a delivery note moves no stock', input, async () => {
      w = await books();
      await issued(w, 'bill', '2026-10-01', [paperLine(w, 10, 1)]);
      doc = await putDoc(w, 'delivery_note', '2026-10-02', [paperLine(w, 2, 0)]);
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('an invoice that was issued goes back to draft', input, async () => {
      w = await books();
      await issued(w, 'bill', '2026-10-01', [paperLine(w, 10, 1)]);
      doc = await issued(w, 'invoice', '2026-10-02', [paperLine(w, 2, 3), { name: 'Courier', quantity: 1, unitPrice: 1 }]);
      await db.documents.put({ ...doc, status: 'draft' });
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('an invoice line from a sub-warehouse, and headings', input, async () => {
      w = await books();
      const sub = await saveWarehouse(createWarehouse(w.companyId, { name: 'Van 1', parentId: w.mainId } as Any));
      await issued(w, 'bill', '2026-10-01', [paperLine(w, 10, 1.2)]);
      await recordStockEntry(w.companyId, {
        kind: 'transfer',
        date: '2026-10-02',
        warehouseId: w.mainId,
        toWarehouseId: sub.id,
        reference: '',
        notes: '',
        lines: [{ productId: w.paper.id, quantity: 3 }],
      });
      doc = await putDoc(w, 'invoice', '2026-10-03', [
        { kind: 'heading', name: 'From the van', quantity: 0 },
        paperLine(w, 2, 3, { warehouseId: sub.id }),
        paperLine(w, 1, 3, { warehouseId: 'gone' }),
        paperLine(w, 0, 3),
      ]);
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a new default warehouse leaves where a bill moved stock', input, async () => {
      w = await books();
      doc = await issued(w, 'bill', '2026-10-01', [paperLine(w, 5, 1)]);
      await saveWarehouse(createWarehouse(w.companyId, { name: 'Salmiya showroom', isDefault: true } as Any));
      await db.documents.put({
        ...doc,
        items: [{ ...doc.items[0], unitPrice: 1.2 }, line(paperLine(w, 1, 1, { id: 'new' }))],
      });
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a change to a bill in a locked period is refused', input, async () => {
      w = await books();
      doc = await issued(w, 'bill', '2026-09-01', [paperLine(w, 10, 1)]);
      await issued(w, 'invoice', '2026-09-20', [paperLine(w, 5, 3)]);
      await lockAt(w, '2026-09-30');
      await db.documents.put({ ...doc, items: [{ ...doc.items[0], quantity: 12 }] });
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('October is costed from the locked September figures', input, async () => {
      w = await books();
      await issued(w, 'bill', '2026-09-01', [paperLine(w, 10, 1)]);
      await issued(w, 'invoice', '2026-09-20', [paperLine(w, 5, 3)]);
      await issued(w, 'invoice', '2026-10-05', [paperLine(w, 6, 3)]);
      await lockAt(w, '2026-09-30');
      doc = await putDoc(w, 'bill', '2026-10-01', [paperLine(w, 5, 2)]);
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a bill with landed costs edited re-allocates them', input, async () => {
      w = await books();
      const toner = await stockItem(w, 'Toner');
      doc = await issued(w, 'bill', '2026-10-01', [
        paperLine(w, 10, 3, { id: 'paper' }),
        { id: 'toner', productId: toner.id, name: 'Toner', quantity: 2, unitPrice: 10 },
      ]);
      const customs = await issued(w, 'bill', '2026-10-04', [
        { id: 'duty', name: 'Customs duty 5%', quantity: 1, unitPrice: 2.5 },
        { id: 'freight', name: 'Freight', quantity: 1, unitPrice: 1.5 },
      ]);
      await saveLandedCost(w.companyId, {
        billId: customs.id,
        sourceLineIds: ['duty', 'freight'],
        targetBillId: doc.id,
        targetLineIds: [],
        method: 'value',
        notes: '',
      });
      await issued(w, 'invoice', '2026-10-06', [paperLine(w, 3, 5)]);
      await db.documents.put({ ...doc, items: [{ ...doc.items[0], quantity: 12 }, doc.items[1]] });
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('voiding the bill with the charges takes its landed cost out', input, async () => {
      w = await books();
      const goods = await issued(w, 'bill', '2026-10-01', [paperLine(w, 10, 1, { id: 'paper' })]);
      doc = await issued(w, 'bill', '2026-10-03', [{ id: 'freight', name: 'Freight', quantity: 1, unitPrice: 2 }]);
      await saveLandedCost(w.companyId, {
        billId: doc.id,
        sourceLineIds: ['freight'],
        targetBillId: goods.id,
        targetLineIds: [],
        method: 'quantity',
        notes: '',
      });
      await db.documents.put({ ...doc, status: 'void' });
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('the first stock document makes the stock accounts and the main store', input, async () => {
      const c = await setupCompany({ name: 'Gulf Trading' });
      const vendor = await saveClient(createClient(c.id, { name: 'Shuwaikh Imports', isVendor: true } as Any));
      const accounts = await db.accounts.where('companyId').equals(c.id).toArray();
      await db.accounts.bulkDelete(accounts.filter((a) => a.code === '1200').map((a) => a.id));
      const fuel = accounts.find((a) => a.type === 'expense' && !a.role)!;
      await db.accounts.put({ ...fuel, id: 'fuel-account', code: '5300', name: 'Fuel' });
      const item = createProduct(c.id, { name: 'Cable', kind: 'stock' } as Any);
      await db.products.put(item);
      w = { companyId: c.id, vendorId: vendor.id, customerId: '', paper: item, mainId: '' };
      doc = await putDoc(w, 'bill', '2026-10-01', [paperLine(w, 4, 0.75, { name: 'Cable' })]);
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a company on the standard chart gets an inventory account next to its bank', input, async () => {
      const c = await setupCompany({
        name: 'Acme',
        currency: 'USD',
        address: { line1: '', line2: '', city: '', state: '', postalCode: '', country: 'US' },
      } as Any);
      const vendor = await saveClient(createClient(c.id, { name: 'Supplier', isVendor: true } as Any));
      const item = createProduct(c.id, { name: 'Widget', kind: 'stock' } as Any);
      await db.products.put(item);
      w = { companyId: c.id, vendorId: vendor.id, customerId: '', paper: item, mainId: '' };
      doc = await putDoc(w, 'bill', '2026-10-01', [paperLine(w, 3, 9.99, { name: 'Widget' })], { currency: 'USD' });
      input.documentId = doc.id;
    }, sync(input));
  }

  {
    const input: Any = { action: 'syncDocumentStock' };
    await run('a tax-exempt vendor: the whole line value is stock', input, async () => {
      w = await books();
      const vendor = await db.clients.get(w.vendorId);
      await db.clients.put({ ...vendor!, taxExempt: true });
      doc = await putDoc(w, 'bill', '2026-10-01', [paperLine(w, 3, 1.5, { taxes: [{ name: 'VAT', rate: 5 }] })]);
      input.documentId = doc.id;
    }, sync(input));
  }

  // ------------------------------------------------------------ costing (recost)

  const recostAll = (input: Any) => async () =>
    inStock(async () => recost(await company(w.companyId), input.productIds));
  const seedMoves = async (input: Any, extra: Any, moves: (w: World) => Any[]) => {
    w = await books(extra);
    await db.stockMovements.bulkPut(moves(w));
    input.productIds = [w.paper.id];
  };

  {
    const input: Any = { action: 'recost' };
    await run('recost: a sale at the average of two purchases', input, () =>
      seedMoves(input, {}, (w) => [
        move(w, '2026-10-01', 'bill', 10, { sourceValue: 12.5 }),
        move(w, '2026-10-02', 'bill', 10, { sourceValue: 15 }),
        move(w, '2026-10-03', 'invoice', -5),
      ]), recostAll(input));
  }

  {
    const input: Any = { action: 'recost' };
    await run('recost: the last units take what is left exactly', input, () =>
      seedMoves(input, {}, (w) => [
        move(w, '2026-10-01', 'bill', 3, { sourceValue: 1 }),
        move(w, '2026-10-02', 'invoice', -1),
        move(w, '2026-10-03', 'invoice', -1),
        move(w, '2026-10-04', 'invoice', -1),
      ]), recostAll(input));
  }

  {
    const input: Any = { action: 'recost' };
    await run('recost: same-day order, receipts before sales and counts last', input, () =>
      seedMoves(input, {}, (w) => [
        move(w, '2026-10-01', 'adjustment', -1, { sequence: '0001' }),
        move(w, '2026-10-01', 'issue', -1, { sequence: '0002' }),
        move(w, '2026-10-01', 'vendor_credit', -1, { sequence: '0003', sourceValue: -1.1 }),
        move(w, '2026-10-01', 'invoice', -2, { sequence: '0004', sourceId: 'inv-1' }),
        move(w, '2026-10-01', 'transfer', -2, { sequence: '0005|0', sourceId: 'trf' }),
        move(w, '2026-10-01', 'transfer', 2, { sequence: '0005|1', sourceId: 'trf', warehouseId: 'other' }),
        move(w, '2026-10-01', 'credit', 1, { sequence: '0006', returnOf: 'inv-1' }),
        move(w, '2026-10-01', 'landed_cost', 0, { sequence: '0007', sourceValue: 0.9, basisQuantity: 4 }),
        move(w, '2026-10-01', 'bill', 4, { sequence: '0008', sourceValue: 8 }),
        move(w, '2026-10-01', 'opening', 3, { sequence: '0009', sourceValue: 2.7 }),
      ]), recostAll(input));
  }

  {
    const input: Any = { action: 'recost' };
    await run('recost: a credit note at the cost its invoice took the goods out', input, () =>
      seedMoves(input, {}, (w) => [
        move(w, '2026-10-01', 'bill', 10, { sourceValue: 10 }),
        move(w, '2026-10-02', 'bill', 10, { sourceValue: 20 }),
        move(w, '2026-10-03', 'invoice', -4, { sourceId: 'inv-1' }),
        move(w, '2026-10-04', 'bill', 4, { sourceValue: 12 }),
        move(w, '2026-10-05', 'credit', 2, { returnOf: 'inv-1' }),
        move(w, '2026-10-06', 'credit', 1, { returnOf: 'unknown' }),
      ]), recostAll(input));
  }

  {
    const input: Any = { action: 'recost' };
    await run('recost: stock sold short is settled when it is received', input, () =>
      seedMoves(input, { costPrice: 1 }, (w) => [
        move(w, '2026-10-01', 'invoice', -2),
        move(w, '2026-10-02', 'bill', 10, { sourceValue: 15 }),
        move(w, '2026-10-03', 'invoice', -8),
        move(w, '2026-10-04', 'invoice', -3),
        move(w, '2026-10-05', 'bill', 1, { sourceValue: 2 }),
        move(w, '2026-10-06', 'adjustment', 1.5),
      ]), recostAll(input));
  }

  {
    const input: Any = { action: 'recost' };
    await run('recost: goods returned to a vendor at the value credited', input, () =>
      seedMoves(input, {}, (w) => [
        move(w, '2026-10-01', 'bill', 10, { sourceValue: 10 }),
        move(w, '2026-10-02', 'bill', 10, { sourceValue: 20 }),
        move(w, '2026-10-03', 'vendor_credit', -5, { sourceValue: -10 }),
        move(w, '2026-10-04', 'invoice', -13),
        move(w, '2026-10-05', 'vendor_credit', -2, { sourceValue: -9 }),
      ]), recostAll(input));
  }

  {
    const input: Any = { action: 'recost' };
    await run('recost: a landed cost spreads over what is still in stock', input, () =>
      seedMoves(input, {}, (w) => [
        move(w, '2026-10-01', 'bill', 10, { sourceValue: 10 }),
        move(w, '2026-10-02', 'invoice', -4),
        move(w, '2026-10-03', 'landed_cost', 0, { sourceValue: 2, basisQuantity: 10 }),
        move(w, '2026-10-04', 'invoice', -6),
        move(w, '2026-10-05', 'landed_cost', 0, { sourceValue: 1, basisQuantity: 3 }),
        move(w, '2026-10-06', 'landed_cost', 0, { sourceValue: -0.5, basisQuantity: null }),
      ]), recostAll(input));
  }

  {
    const input: Any = { action: 'recost' };
    await run('recost: half of three units worth 1.001 moved and counted', input, () =>
      seedMoves(input, {}, (w) => [
        move(w, '2026-10-01', 'bill', 3, { sourceValue: 1.001 }),
        move(w, '2026-10-02', 'transfer', -1.5, { sourceId: 'trf', sequence: '0002|0' }),
        move(w, '2026-10-02', 'transfer', 1.5, { sourceId: 'trf', sequence: '0002|1', warehouseId: 'van' }),
        move(w, '2026-10-03', 'adjustment', 1.5),
        move(w, '2026-10-04', 'invoice', -1.5),
      ]), recostAll(input));
  }

  {
    const input: Any = { action: 'recost' };
    await run('recost: sevenths of a fils, cut as decimal.js-light cuts them', input, () =>
      seedMoves(input, {}, (w) => [
        move(w, '2026-10-01', 'bill', 7, { sourceValue: 0.005 }),
        move(w, '2026-10-02', 'adjustment', 3.5),
        move(w, '2026-10-03', 'invoice', -10.5),
        move(w, '2026-10-04', 'invoice', -3.5),
        move(w, '2026-10-05', 'adjustment', 3.5),
        move(w, '2026-10-06', 'bill', 7, { sourceValue: 1.001 }),
        move(w, '2026-10-07', 'landed_cost', 0, { sourceValue: 0.007, basisQuantity: 14 }),
        move(w, '2026-10-08', 'invoice', -0.7),
      ]), recostAll(input));
  }

  {
    const input: Any = { action: 'recost' };
    await run('recost: a locked period keeps its values', input, async () => {
      w = await books();
      await db.stockMovements.bulkPut([
        move(w, '2026-09-01', 'bill', 10, { sourceValue: 10, value: 10, unitCost: 1 }),
        move(w, '2026-09-05', 'bill', 10, { sourceValue: 30, value: 30, unitCost: 3 }),
        move(w, '2026-09-10', 'invoice', -5, { value: -5, unitCost: 1 }),
        move(w, '2026-09-11', 'transfer', -1, { value: -7, unitCost: 7 }),
        move(w, '2026-10-02', 'invoice', -5),
        move(w, '2026-10-03', 'transfer', -1, { sourceId: 'trf' }),
      ]);
      await lockAt(w, '2026-09-30');
      input.productIds = [w.paper.id];
    }, recostAll(input));
  }

  {
    const input: Any = { action: 'recost' };
    await run('recost: movements already costed change nothing', input, async () => {
      w = await books();
      await db.stockMovements.bulkPut([
        move(w, '2026-10-01', 'bill', 10, { sourceValue: 12.5 }),
        move(w, '2026-10-02', 'invoice', -3),
      ]);
      await recost(await company(w.companyId), [w.paper.id]);
      input.productIds = [w.paper.id, w.paper.id, 'no-such-item'];
    }, recostAll(input));
  }

  {
    const input: Any = { action: 'recost' };
    await run('recost: many items at once', input, async () => {
      w = await books();
      const ids: string[] = [w.paper.id];
      const moves: Any[] = [];
      for (let i = 0; i < 22; i++) {
        const item = await stockItem(w, `Part ${i + 1}`, { costPrice: i / 8 });
        ids.push(item.id);
        moves.push(
          move(w, '2026-10-01', 'bill', 3 + i, { productId: item.id, sourceValue: 1.001 * (i + 1) }),
          move(w, '2026-10-02', 'invoice', -(i % 5) - 1, { productId: item.id }),
        );
      }
      await db.stockMovements.bulkPut(moves);
      input.productIds = ids;
    }, recostAll(input));
  }

  // ------------------------------------------------------------ rebuildStock

  {
    const input: Any = { action: 'rebuildStock' };
    await run('rebuilding the stock re-plans and re-costs everything', input, async () => {
      w = await books();
      await issued(w, 'bill', '2026-10-01', [paperLine(w, 10, 1.25)]);
      const invoice = await issued(w, 'invoice', '2026-10-02', [paperLine(w, 3, 3)]);
      await recordStockEntry(w.companyId, {
        kind: 'adjustment',
        date: '2026-10-03',
        warehouseId: w.mainId,
        reason: 'damaged',
        reference: '',
        notes: '',
        lines: [{ productId: w.paper.id, quantity: -1 }],
      });
      // A movement whose source is gone, one lost, and values gone stale.
      await db.stockMovements.put(move(w, '2026-10-04', 'invoice', -2, { id: 'orphan', sourceId: 'gone' }));
      const sale = (await db.stockMovements.where('sourceId').equals(invoice.id).toArray())[0];
      await db.stockMovements.put({ ...sale, value: -99 });
      await db.documents.put({ ...invoice, items: [{ ...invoice.items[0], quantity: 4 }] });
    }, async () => rebuildStock(w.companyId));
  }

  // ------------------------------------------------------------ warehouses

  const saveW = (input: Any) => async () => saveWarehouse(input.warehouse);

  {
    const input: Any = { action: 'saveWarehouse' };
    await run('a new warehouse, trimmed', input, async () => {
      w = await books();
      input.warehouse = clone(
        createWarehouse(w.companyId, { name: '  Salmiya showroom ', nameAr: ' معرض السالمية ', address: ' Block 10 ' } as Any),
      );
    }, saveW(input));
  }

  {
    const input: Any = { action: 'saveWarehouse' };
    await run('the first warehouse is the default one', input, async () => {
      const c = await setupCompany({ name: 'Gulf Trading' });
      input.warehouse = clone(createWarehouse(c.id, { name: 'Shuwaikh store' } as Any));
    }, saveW(input));
  }

  {
    const input: Any = { action: 'saveWarehouse' };
    await run('a new default warehouse takes over', input, async () => {
      w = await books();
      input.warehouse = clone(createWarehouse(w.companyId, { name: 'Salmiya showroom', isDefault: true } as Any));
    }, saveW(input));
  }

  {
    const input: Any = { action: 'saveWarehouse' };
    await run('a sub-warehouse with whoever looks after it', input, async () => {
      w = await books();
      input.warehouse = clone(
        createWarehouse(w.companyId, {
          name: '  Ahmed’s store ',
          parentId: w.mainId,
          keeper: {
            employeeId: '',
            name: ' Ahmed Saleh ',
            nameAr: ' أحمد صالح ',
            jobTitle: ' Warehouse Supervisor ',
            userId: ' user-keeper ',
          },
        } as Any),
      );
    }, saveW(input));
  }

  {
    const input: Any = { action: 'saveWarehouse' };
    await run('a keeper with neither a name nor an account is nobody', input, async () => {
      w = await books();
      const main = await db.warehouses.get(w.mainId);
      input.warehouse = clone({
        ...main,
        name: 'Main store',
        keeper: { employeeId: 'emp-1', name: '  ', jobTitle: 'Clerk', userId: ' ' },
      });
    }, saveW(input));
  }

  {
    const input: Any = { action: 'saveWarehouse' };
    await run('a sub-warehouse archived', input, async () => {
      w = await books();
      const sub = await saveWarehouse(createWarehouse(w.companyId, { name: 'Van 1', parentId: w.mainId } as Any));
      input.warehouse = clone({ ...sub, archived: true });
    }, saveW(input));
  }

  const refusedWarehouse = async (name: string, make: (w: World, sub: Any) => Any) => {
    const input: Any = { action: 'saveWarehouse' };
    await run(name, input, async () => {
      w = await books();
      const sub = await saveWarehouse(createWarehouse(w.companyId, { name: 'Van 1', parentId: w.mainId } as Any));
      await saveWarehouse(createWarehouse(w.companyId, { name: 'Old depot', archived: true } as Any));
      input.warehouse = clone(make(w, sub));
    }, saveW(input));
  };

  await refusedWarehouse('a warehouse needs a name', (w) => createWarehouse(w.companyId, { name: '   ' } as Any));
  await refusedWarehouse('another warehouse already has the name', (w) =>
    createWarehouse(w.companyId, { name: ' van 1 ' } as Any),
  );
  await refusedWarehouse('an archived name is taken too', (w) =>
    createWarehouse(w.companyId, { name: 'OLD DEPOT' } as Any),
  );
  await refusedWarehouse('the default warehouse can’t be archived', (w) =>
    createWarehouse(w.companyId, { name: 'New', isDefault: true, archived: true } as Any),
  );
  await refusedWarehouse('a sub-warehouse can’t be the default', (w, sub) => ({ ...sub, isDefault: true }));
  await refusedWarehouse('no sub-warehouse of a sub-warehouse', (w, sub) =>
    createWarehouse(w.companyId, { name: 'Shelf', parentId: sub.id } as Any),
  );
  await refusedWarehouse('the main warehouse must exist and be in use', (w) =>
    createWarehouse(w.companyId, { name: 'Shelf', parentId: 'no-such-warehouse' } as Any),
  );

  {
    const input: Any = { action: 'saveWarehouse' };
    await run('a warehouse with sub-warehouses is archived after them', input, async () => {
      w = await books();
      const other = await saveWarehouse(createWarehouse(w.companyId, { name: 'Al-Rai store' } as Any));
      await saveWarehouse(createWarehouse(w.companyId, { name: 'Night shift store', parentId: other.id } as Any));
      input.warehouse = clone({ ...other, archived: true });
    }, saveW(input));
  }

  {
    const input: Any = { action: 'saveWarehouse' };
    await run('a main warehouse with sub-warehouses becoming a sub-warehouse is refused', input, async () => {
      w = await books();
      const other = await saveWarehouse(createWarehouse(w.companyId, { name: 'Al-Rai store' } as Any));
      await saveWarehouse(createWarehouse(w.companyId, { name: 'Night shift store', parentId: other.id } as Any));
      input.warehouse = clone({ ...other, parentId: w.mainId });
    }, saveW(input));
  }

  {
    const input: Any = { action: 'saveWarehouse' };
    await run('an archived main warehouse can’t take sub-warehouses', input, async () => {
      w = await books();
      const old = await saveWarehouse(createWarehouse(w.companyId, { name: 'Old depot' } as Any));
      await saveWarehouse({ ...old, archived: true });
      input.warehouse = clone(createWarehouse(w.companyId, { name: 'Shelf', parentId: old.id } as Any));
    }, saveW(input));
  }

  {
    const input: Any = { action: 'ensureDefaultWarehouse' };
    await run('the main store, with the same id on every device', input, async () => {
      const c = await setupCompany({ name: 'Gulf Trading' });
      w = { ...empty(), companyId: c.id };
    }, async () => ensureDefaultWarehouse(w.companyId));
  }

  {
    const input: Any = { action: 'ensureDefaultWarehouse' };
    await run('a warehouse in use becomes the default one', input, async () => {
      w = await books();
      const main = (await db.warehouses.get(w.mainId))!;
      await db.warehouses.put({ ...main, isDefault: false, archived: true });
      await db.warehouses.put(createWarehouse(w.companyId, { id: 'w-second', name: 'Second' } as Any));
    }, async () => ensureDefaultWarehouse(w.companyId));
  }

  {
    const input: Any = { action: 'ensureDefaultWarehouse' };
    await run('only archived warehouses: a new main store', input, async () => {
      w = await books();
      const main = (await db.warehouses.get(w.mainId))!;
      await db.warehouses.put({ ...main, archived: true });
    }, async () => ensureDefaultWarehouse(w.companyId));
  }

  // ------------------------------------------------------------ items

  const save = (input: Any) => async () => saveItem(input.product, { opening: input.opening ?? null });

  {
    const input: Any = { action: 'saveItem' };
    await run('a new stock item makes the stock accounts and the main store', input, async () => {
      const c = await setupCompany({ name: 'Gulf Trading' });
      input.product = clone(
        createProduct(c.id, {
          name: '  Cable ',
          nameAr: 'كيبل',
          kind: 'stock',
          costPrice: 0.12345678,
          unit: 'pcs',
          unitId: '',
          barcode: ' 628100 ',
          hsCode: ' 8544 ',
          reorderLevel: 5,
        } as Any),
      );
    }, save(input));
  }

  {
    const input: Any = { action: 'saveItem' };
    await run('a new stock item with opening stock in the default warehouse', input, async () => {
      const c = await setupCompany({ name: 'Gulf Trading' });
      input.product = clone(createProduct(c.id, { name: 'Cable', kind: 'stock', costPrice: 0.75 } as Any));
      input.opening = { warehouseId: '', quantity: 8, unitCost: 0.75, date: '2026-10-01' };
    }, save(input));
  }

  {
    const input: Any = { action: 'saveItem' };
    await run('a new stock item with opening stock in another warehouse', input, async () => {
      w = await books();
      const showroom = await saveWarehouse(createWarehouse(w.companyId, { name: 'Showroom' } as Any));
      input.product = clone(createProduct(w.companyId, { name: 'Toner', kind: 'stock', costPrice: 1.3333337 } as Any));
      input.opening = { warehouseId: showroom.id, quantity: 3, unitCost: 1.3333337, date: '2026-10-01' };
    }, save(input));
  }

  {
    const input: Any = { action: 'saveItem' };
    await run('a service: no stock accounts, no warehouse', input, async () => {
      const c = await setupCompany({ name: 'Gulf Trading' });
      input.product = clone(
        createProduct(c.id, { name: 'Delivery', kind: null, unit: 'trip', unitId: 'trip', reorderLevel: 3 } as Any),
      );
      input.opening = { warehouseId: '', quantity: 2, unitCost: 1, date: '2026-10-01' };
    }, save(input));
  }

  {
    const input: Any = { action: 'saveItem' };
    await run('a new cost price re-costs sales made before stock had a cost', input, async () => {
      w = await books({ costPrice: 1 });
      await issued(w, 'invoice', '2026-10-01', [paperLine(w, 2, 3)]);
      const stored = await db.products.get(w.paper.id);
      input.product = clone({ ...stored, costPrice: 1.25, imageIds: [] });
    }, save(input));
  }

  {
    const input: Any = { action: 'saveItem' };
    await run('a service that becomes a stock item starts moving stock', input, async () => {
      w = await books();
      const toner = await saveItem(createProduct(w.companyId, { name: 'Toner' }));
      await issued(w, 'bill', '2026-10-01', [{ productId: toner.id, name: 'Toner', quantity: 2, unitPrice: 10 }]);
      await issued(w, 'invoice', '2026-10-02', [{ productId: toner.id, name: 'Toner', quantity: 1, unitPrice: 15 }]);
      await db.products.put({ ...toner, imageIds: ['img-1'] });
      input.product = clone({ ...toner, kind: 'stock' });
    }, save(input));
  }

  {
    const input: Any = { action: 'saveItem' };
    await run('a stock item without history can become a service', input, async () => {
      w = await books();
      const stored = await db.products.get(w.paper.id);
      input.product = clone({ ...stored, kind: 'service', reorderLevel: 4 });
    }, save(input));
  }

  {
    const input: Any = { action: 'saveItem' };
    await run('a stock item with history stays one', input, async () => {
      w = await books();
      await issued(w, 'bill', '2026-10-01', [paperLine(w, 2, 1)]);
      input.product = clone({ ...w.paper, kind: 'non_stock' });
    }, save(input));
  }

  {
    const input: Any = { action: 'saveItem' };
    await run('a service sold in a locked period can’t start moving stock', input, async () => {
      w = await books();
      const courier = await saveItem(createProduct(w.companyId, { name: 'Courier' }));
      await putDoc(w, 'invoice', '2026-09-02', [{ productId: courier.id, name: 'Courier', quantity: 1, unitPrice: 1 }]);
      await lockAt(w, '2026-09-30');
      input.product = clone({ ...courier, kind: 'stock' });
    }, save(input));
  }

  {
    const input: Any = { action: 'saveItem' };
    await run('a new income account: sales of the locked period keep theirs', input, async () => {
      w = await books();
      const courier = await saveItem(createProduct(w.companyId, { name: 'Courier' }));
      await putDoc(w, 'invoice', '2026-09-02', [
        { productId: courier.id, name: 'Courier', quantity: 1, unitPrice: 1 },
        { productId: w.paper.id, name: 'Paper', quantity: 1, unitPrice: 1 },
      ]);
      await putDoc(w, 'invoice', '2026-10-02', [{ productId: courier.id, name: 'Courier', quantity: 1, unitPrice: 1 }]);
      await putDoc(w, 'quote', '2026-09-03', [{ productId: courier.id, name: 'Courier', quantity: 1, unitPrice: 1 }]);
      await lockAt(w, '2026-09-30');
      const income = (await db.accounts.where('companyId').equals(w.companyId).toArray()).find(
        (a) => a.type === 'income' && a.role !== 'sales',
      )!;
      input.product = clone({ ...courier, incomeAccountId: income.id });
    }, save(input));
  }

  const refusedItem = async (name: string, product: (w: World) => Any) => {
    const input: Any = { action: 'saveItem' };
    await run(name, input, async () => {
      w = await books();
      input.product = clone(product(w));
    }, save(input));
  };
  await refusedItem('an item needs a name', (w) => createProduct(w.companyId, { name: '  ' }));
  await refusedItem('a negative cost is refused', (w) => createProduct(w.companyId, { name: 'X', costPrice: -1 } as Any));
  await refusedItem('a negative reorder level is refused', (w) =>
    createProduct(w.companyId, { name: 'X', kind: 'stock', reorderLevel: -2 } as Any),
  );
  await refusedItem('an item of no company', () => createProduct('no-such-company', { name: 'X' }));

  // Item codes (SKU).
  const coding = async (on = true, numbering?: (n: Any) => Any) => {
    const c = await setupCompany({ name: 'Gulf Trading' });
    const coded = await saveCompany({ ...c, items: on ? { autoSku: true } : undefined } as Any);
    if (numbering) await db.companies.put({ ...coded, numbering: numbering(coded.numbering) });
    return coded;
  };
  const code = async (name: string, setup: (c: Any) => Promise<Any>, on = true, numbering?: (n: Any) => Any) => {
    const input: Any = { action: 'saveItem' };
    await run(name, input, async () => {
      const c = await coding(on, numbering);
      w = { ...empty(), companyId: c.id };
      input.product = clone(await setup(c));
    }, save(input));
  };

  await code('a new item without an SKU gets the next code', async (c) => createProduct(c.id, { name: 'Gloves' }));
  await code('a code typed by hand is kept, trimmed', async (c) => createProduct(c.id, { name: 'Boots', sku: ' BT-44 ' }));
  await code('codes typed by hand are skipped', async (c) => {
    await saveItem(createProduct(c.id, { name: 'Vest', sku: 'sku-00001' }));
    return createProduct(c.id, { name: 'Gloves' });
  });
  await code(
    'a company made before item codes gets the rule',
    async (c) => createProduct(c.id, { name: 'Gloves' }),
    true,
    (n) => {
      const { product: _none, ...rest } = n;
      return rest;
    },
  );
  await code(
    'a yearly item code starts again in a new year',
    async (c) => createProduct(c.id, { name: 'Gloves' }),
    true,
    (n) => ({ ...n, product: { pattern: 'IT-{yy}-{counter}', next: 41, padding: 3, reset: 'yearly', period: '2025' } }),
  );
  await code('no code while codes are off', async (c) => createProduct(c.id, { name: 'Gloves' }), false);
  // The code from the cloud's counter, as a signed-in device takes it
  // (`input.reserved`; `input.request` is what the web asked for).
  for (const [name, counter, period] of [
    ['a new item takes its code from the cloud’s counter', 7, ''],
    ['a counter below this device’s own is not used', 1, ''],
    ['a counter of another period is not used', 9, '2025'],
  ] as const) {
    const input: Any = { action: 'saveItem' };
    await run(name, input, async () => {
      const c = await coding();
      w = { ...empty(), companyId: c.id };
      await saveItem(createProduct(c.id, { name: 'Vest', sku: 'SKU-00002' }));
      input.product = clone(createProduct(c.id, { name: 'Gloves' }));
      input.reserved = { counter, period };
      setCounterReserver(async ({ kind, date, min }) => {
        input.request = { kind, date, min };
        return { counter, period };
      });
    }, async () => {
      try {
        await saveItem(input.product);
      } finally {
        setCounterReserver(null);
      }
    });
  }
  await code('an older item without a code keeps none', async (c) => {
    const before = createProduct(c.id, { name: 'Rope' });
    await db.products.put(before);
    return { ...before, archived: true };
  });
  await code('an SKU another item has is refused', async (c) => {
    await saveItem(createProduct(c.id, { name: 'Gloves', sku: 'GL-01' }));
    return createProduct(c.id, { name: 'Gloves XL', sku: ' gl-01' });
  });
  await code('an SKU changed to one another item has is refused', async (c) => {
    await saveItem(createProduct(c.id, { name: 'Gloves', sku: 'GL-01' }));
    const helmet = await saveItem(createProduct(c.id, { name: 'Helmet', sku: 'HM-01' }));
    return { ...helmet, sku: 'GL-01' };
  });
  await code('an item saved again with an SKU it shares is kept', async (c) => {
    const gloves = await saveItem(createProduct(c.id, { name: 'Gloves', sku: 'GL-01' }));
    const helmet = await saveItem(createProduct(c.id, { name: 'Helmet', sku: 'HM-01' }));
    await db.products.put({ ...helmet, sku: 'GL-01' });
    return { ...gloves, unitPrice: 2 };
  });
  await code('the archived item that has the SKU is named', async (c) => {
    const old = await saveItem(createProduct(c.id, { name: 'Gloves (old supplier)', sku: 'OLD-1' }));
    await saveItem({ ...old, archived: true });
    return createProduct(c.id, { name: 'Gloves', sku: 'old-1' });
  });
  await code(
    'items share an SKU while the company gives no codes',
    async (c) => {
      await saveItem(createProduct(c.id, { name: 'Gloves', sku: 'OLD-1' }));
      return createProduct(c.id, { name: 'Gloves XL', sku: 'old-1' });
    },
    false,
  );

  // Delete and codes for every item.
  {
    const input: Any = { action: 'deleteItem' };
    await run('an item without history is deleted with its pictures', input, async () => {
      w = await books();
      const courier = await saveItem(createProduct(w.companyId, { name: 'Courier', nameAr: 'توصيل' }));
      await db.attachments.bulkPut([
        { id: 'att-1', companyId: w.companyId, ownerId: courier.id, name: 'a.png' },
        { id: 'att-2', companyId: w.companyId, ownerId: w.paper.id, name: 'b.png' },
      ] as Any);
      input.id = courier.id;
    }, async () => deleteItem(input.id));
  }

  {
    const input: Any = { action: 'deleteItem' };
    await run('an item with stock history is archived instead', input, async () => {
      w = await books();
      await recordStockEntry(w.companyId, {
        kind: 'opening',
        date: '2026-10-01',
        warehouseId: w.mainId,
        reference: '',
        notes: '',
        lines: [{ productId: w.paper.id, quantity: 1, unitCost: 1 }],
      });
      input.id = w.paper.id;
    }, async () => deleteItem(input.id));
  }

  {
    const input: Any = { action: 'deleteItem' };
    await run('an item that is gone: nothing to delete', input, async () => {
      w = await books();
      input.id = 'no-such-item';
    }, async () => deleteItem(input.id));
  }

  {
    const input: Any = { action: 'assignItemCodes' };
    await run('codes for the items without one, oldest first', input, async () => {
      const c = await coding();
      w = { ...empty(), companyId: c.id };
      const first = createProduct(c.id, { name: 'Rope', createdAt: '2026-01-01T00:00:00Z' });
      const second = createProduct(c.id, { name: 'Bag', createdAt: '2026-02-01T00:00:00Z' });
      const third = createProduct(c.id, { name: 'Axe', createdAt: '2026-02-01T00:00:00Z' });
      const archived = createProduct(c.id, { name: 'Old', archived: true });
      await db.products.bulkPut([second, first, third, archived]);
      await saveItem(createProduct(c.id, { name: 'Gloves', sku: 'SKU-00002' }));
    }, async () => assignItemCodes(w.companyId));
  }

  {
    const input: Any = { action: 'assignItemCodes' };
    await run('every item has a code: none given', input, async () => {
      const c = await coding();
      w = { ...empty(), companyId: c.id };
      await saveItem(createProduct(c.id, { name: 'Gloves' }));
    }, async () => assignItemCodes(w.companyId));
  }

  // ------------------------------------------------------------ stock entries

  const entry = (input: Any) => async () => recordStockEntry(w.companyId, input.entry);
  const withEntry = async (name: string, make: (w: World, extra: Any) => Any, seed?: (w: World) => Promise<Any>) => {
    const input: Any = { action: 'recordStockEntry' };
    await run(name, input, async () => {
      w = await books();
      const extra = seed ? await seed(w) : {};
      input.entry = clone(make(w, extra));
    }, entry(input));
  };
  const stocked = async (w: World) => {
    await issued(w, 'bill', '2026-10-01', [paperLine(w, 10, 1.375)]);
    const showroom = await saveWarehouse(createWarehouse(w.companyId, { name: 'Showroom' } as Any));
    const van = await saveWarehouse(createWarehouse(w.companyId, { name: 'Van', parentId: w.mainId } as Any));
    const old = await saveWarehouse(createWarehouse(w.companyId, { name: 'Old depot' } as Any));
    await saveWarehouse({ ...old, archived: true });
    const service = await saveItem(createProduct(w.companyId, { name: 'Courier' }));
    return { showroom: showroom.id, van: van.id, old: old.id, service: service.id };
  };

  await withEntry('opening stock, its cost to 6 decimals', (w) => ({
    kind: 'opening',
    date: '2026-09-30',
    warehouseId: w.mainId,
    reason: 'count',
    toWarehouseId: 'x',
    reference: ' OB-1 ',
    notes: ' Counted ',
    lines: [
      { productId: w.paper.id, quantity: 20, unitCost: 1.3755555555 },
      { productId: w.paper.id, quantity: 0, unitCost: 2 },
      { productId: '', quantity: 3, unitCost: 2 },
    ],
  }));
  await withEntry(
    'an adjustment writes off damaged goods at the average',
    (w) => ({
      kind: 'adjustment',
      date: '2026-10-02',
      warehouseId: w.mainId,
      reason: 'damaged',
      reference: '',
      notes: '',
      lines: [{ productId: w.paper.id, quantity: -3 }],
    }),
    stocked,
  );
  await withEntry(
    'an adjustment without a reason adds stock at the average',
    (w) => ({
      kind: 'adjustment',
      date: '2026-10-02',
      warehouseId: w.mainId,
      reference: '',
      notes: '',
      lines: [{ productId: w.paper.id, quantity: 1.5, unitCost: 9 }],
    }),
    stocked,
  );
  await withEntry(
    'a transfer between warehouses moves no value',
    (w, x) => ({
      kind: 'transfer',
      date: '2026-10-02',
      warehouseId: w.mainId,
      toWarehouseId: x.showroom,
      reason: 'damaged',
      reference: '',
      notes: '',
      lines: [{ productId: w.paper.id, quantity: 4 }],
    }),
    stocked,
  );
  await withEntry(
    'a transfer to a sub-warehouse',
    (w, x) => ({
      kind: 'transfer',
      date: '2026-10-02',
      warehouseId: w.mainId,
      toWarehouseId: x.van,
      reference: '',
      notes: '',
      lines: [{ productId: w.paper.id, quantity: 3.333 }],
    }),
    stocked,
  );
  await withEntry(
    'the numbers carry on from the highest',
    (w) => ({
      kind: 'adjustment',
      date: '2026-10-02',
      warehouseId: w.mainId,
      reason: 'count',
      reference: '',
      notes: '',
      lines: [{ productId: w.paper.id, quantity: -1 }],
    }),
    async (w) => {
      await db.stockEntries.bulkPut([
        { id: 'e1', companyId: w.companyId, kind: 'adjustment', number: 'ADJ-0007', lines: [], status: 'void' },
        { id: 'e2', companyId: w.companyId, kind: 'adjustment', number: 'ADJ-x', lines: [], status: 'void' },
        { id: 'e3', companyId: w.companyId, kind: 'opening', number: 'OPN-0099', lines: [], status: 'void' },
        { id: 'e4', companyId: 'other', kind: 'adjustment', number: 'ADJ-0050', lines: [], status: 'void' },
      ] as Any);
      return {};
    },
  );

  const refusedEntry = (name: string, make: (w: World, x: Any) => Any) => withEntry(name, make, stocked);
  const adjust = (w: World, lines: Any[], extra: Any = {}) => ({
    kind: 'adjustment',
    date: '2026-10-02',
    warehouseId: w.mainId,
    reason: 'damaged',
    reference: '',
    notes: '',
    lines,
    ...extra,
  });
  await refusedEntry('an entry needs an item with a quantity', (w) => adjust(w, [{ productId: w.paper.id, quantity: 0 }]));
  await refusedEntry('only stock items can be added', (w, x) => adjust(w, [{ productId: x.service, quantity: -1 }]));
  await refusedEntry('an item of no company can’t be added', (w) => adjust(w, [{ productId: 'nothing', quantity: -1 }]));
  await refusedEntry('opening stock in positive quantities', (w) =>
    adjust(w, [{ productId: w.paper.id, quantity: -1, unitCost: 1 }], { kind: 'opening' }),
  );
  await refusedEntry('opening stock at no negative cost', (w) =>
    adjust(w, [{ productId: w.paper.id, quantity: 1, unitCost: -1 }], { kind: 'opening' }),
  );
  await refusedEntry('an entry needs a warehouse in use', (w, x) =>
    adjust(w, [{ productId: w.paper.id, quantity: -1 }], { warehouseId: x.old }),
  );
  await refusedEntry('a transfer needs somewhere to go', (w, x) =>
    adjust(w, [{ productId: w.paper.id, quantity: 1 }], { kind: 'transfer', toWarehouseId: x.old }),
  );
  await refusedEntry('a transfer needs two warehouses', (w) =>
    adjust(w, [{ productId: w.paper.id, quantity: 1 }], { kind: 'transfer', toWarehouseId: w.mainId }),
  );
  await refusedEntry('a transfer in negative quantities is refused', (w, x) =>
    adjust(w, [{ productId: w.paper.id, quantity: -1 }], { kind: 'transfer', toWarehouseId: x.showroom }),
  );
  {
    const input: Any = { action: 'recordStockEntry' };
    await run('an entry in a locked period is refused', input, async () => {
      w = await books();
      await lockAt(w, '2026-09-30');
      input.entry = adjust(w, [{ productId: w.paper.id, quantity: -1 }], { date: '2026-09-15' });
    }, entry(input));
  }

  {
    const input: Any = { action: 'voidStockEntry' };
    await run('voiding an adjustment takes its movements out', input, async () => {
      w = await books();
      await issued(w, 'bill', '2026-10-01', [paperLine(w, 10, 1.375)]);
      const damaged = await recordStockEntry(w.companyId, adjust(w, [{ productId: w.paper.id, quantity: -3 }]) as Any);
      await issued(w, 'invoice', '2026-10-05', [paperLine(w, 2, 3)]);
      input.id = damaged.id;
    }, async () => voidStockEntry(input.id));
  }

  {
    const input: Any = { action: 'voidStockEntry' };
    await run('voiding a void entry does nothing', input, async () => {
      w = await books();
      const e = await recordStockEntry(w.companyId, adjust(w, [{ productId: w.paper.id, quantity: -3 }]) as Any);
      await voidStockEntry(e.id);
      input.id = e.id;
    }, async () => voidStockEntry(input.id));
  }

  {
    const input: Any = { action: 'voidStockEntry' };
    await run('an entry in a locked period can’t be voided', input, async () => {
      w = await books();
      const e = await recordStockEntry(w.companyId, adjust(w, [{ productId: w.paper.id, quantity: -3 }]) as Any);
      await lockAt(w, '2026-10-31');
      input.id = e.id;
    }, async () => voidStockEntry(input.id));
  }

  // ------------------------------------------------------------ landed costs

  const landed = (input: Any) => async () => saveLandedCost(w.companyId, input.cost);
  const goodsAndCharges = async (w: World) => {
    const toner = await stockItem(w, 'Toner');
    const goods = await issued(w, 'bill', '2026-10-01', [
      paperLine(w, 10, 3, { id: 'paper' }),
      { id: 'toner', productId: toner.id, name: 'Toner', quantity: 2, unitPrice: 10 },
    ]);
    await issued(w, 'invoice', '2026-10-02', [paperLine(w, 4, 5)]);
    const customs = await issued(
      w,
      'bill',
      '2026-10-04',
      [
        { id: 'duty', name: 'Customs duty 5%', quantity: 1, unitPrice: 2.5 },
        { id: 'freight', name: 'Freight', quantity: 1, unitPrice: 1.5 },
        paperLine(w, 1, 3, { id: 'more-paper' }),
      ],
      { charges: [{ id: 'clearing', label: 'Clearing', amount: 0.333, taxes: [] }] },
    );
    return { goods, customs, toner };
  };
  const withCost = async (name: string, make: (x: Any) => Any, seed?: (w: World, x: Any) => Promise<void>) => {
    const input: Any = { action: 'saveLandedCost' };
    await run(name, input, async () => {
      w = await books();
      const x = await goodsAndCharges(w);
      if (seed) await seed(w, x);
      input.cost = clone(make(x));
    }, landed(input));
  };

  await withCost('customs and freight added to the goods by value', (x) => ({
    billId: x.customs.id,
    sourceLineIds: ['duty', 'freight', 'duty'],
    targetBillId: x.goods.id,
    targetLineIds: [],
    method: 'value',
    notes: '  Shipment 7 ',
  }));
  await withCost('a charge allocated by quantity to some of the goods', (x) => ({
    billId: x.customs.id,
    sourceLineIds: ['clearing', 'more-paper'],
    targetBillId: x.goods.id,
    targetLineIds: ['toner', 'toner'],
    method: 'quantity',
    notes: '',
  }));
  await withCost('charges on the same bill as the goods', (x) => ({
    billId: x.customs.id,
    sourceLineIds: ['freight', 'clearing'],
    targetBillId: x.customs.id,
    targetLineIds: [],
    method: 'value',
    notes: '',
  }));
  await withCost(
    'the next landed cost number',
    (x) => ({
      billId: x.customs.id,
      sourceLineIds: ['freight'],
      targetBillId: x.goods.id,
      targetLineIds: [],
      method: 'value',
      notes: '',
    }),
    async (w, x) => {
      await saveLandedCost(w.companyId, {
        billId: x.customs.id,
        sourceLineIds: ['duty'],
        targetBillId: x.goods.id,
        targetLineIds: [],
        method: 'value',
        notes: '',
      });
    },
  );
  await withCost(
    'a charge already allocated is refused',
    (x) => ({
      billId: x.customs.id,
      sourceLineIds: ['freight', 'duty'],
      targetBillId: x.goods.id,
      targetLineIds: [],
      method: 'value',
      notes: '',
    }),
    async (w, x) => {
      await saveLandedCost(w.companyId, {
        billId: x.customs.id,
        sourceLineIds: ['duty'],
        targetBillId: x.goods.id,
        targetLineIds: [],
        method: 'value',
        notes: '',
      });
    },
  );
  await withCost(
    'a voided allocation frees its charges',
    (x) => ({
      billId: x.customs.id,
      sourceLineIds: ['duty'],
      targetBillId: x.goods.id,
      targetLineIds: [],
      method: 'quantity',
      notes: '',
    }),
    async (w, x) => {
      const first = await saveLandedCost(w.companyId, {
        billId: x.customs.id,
        sourceLineIds: ['duty'],
        targetBillId: x.goods.id,
        targetLineIds: [],
        method: 'value',
        notes: '',
      });
      await voidLandedCost(first.id);
    },
  );
  await withCost('charges dated before the goods are refused', (x) => ({
    billId: x.goods.id,
    sourceLineIds: ['paper'],
    targetBillId: x.customs.id,
    targetLineIds: [],
    method: 'value',
    notes: '',
  }));
  await withCost('only stock lines chosen as charges is refused', (x) => ({
    billId: x.customs.id,
    sourceLineIds: ['more-paper'],
    targetBillId: x.goods.id,
    targetLineIds: [],
    method: 'value',
    notes: '',
  }));
  await withCost(
    'a draft bill can’t take charges',
    (x) => ({
      billId: x.draft.id,
      sourceLineIds: ['freight'],
      targetBillId: x.goods.id,
      targetLineIds: [],
      method: 'value',
      notes: '',
    }),
    async (w, x) => {
      x.draft = await putDoc(w, 'bill', '2026-10-05', [{ id: 'freight', name: 'Freight', quantity: 1, unitPrice: 1 }], {
        status: 'draft',
      });
    },
  );
  await withCost(
    'a bill without stock to receive the charges is refused',
    (x) => ({
      billId: x.customs.id,
      sourceLineIds: ['duty'],
      targetBillId: x.services.id,
      targetLineIds: [],
      method: 'value',
      notes: '',
    }),
    async (w, x) => {
      x.services = await issued(w, 'bill', '2026-10-03', [{ id: 'svc', name: 'Cleaning', quantity: 1, unitPrice: 5 }]);
    },
  );
  await withCost(
    'charges in a locked period are refused',
    (x) => ({
      billId: x.customs.id,
      sourceLineIds: ['duty'],
      targetBillId: x.goods.id,
      targetLineIds: [],
      method: 'value',
      notes: '',
    }),
    async (w) => lockAt(w, '2026-10-04'),
  );

  {
    const input: Any = { action: 'voidLandedCost' };
    await run('a landed cost voided: the charges go back to expenses', input, async () => {
      w = await books();
      const x = await goodsAndCharges(w);
      const cost = await saveLandedCost(w.companyId, {
        billId: x.customs.id,
        sourceLineIds: ['duty', 'freight'],
        targetBillId: x.goods.id,
        targetLineIds: [],
        method: 'value',
        notes: '',
      });
      input.id = cost.id;
    }, async () => voidLandedCost(input.id));
  }

  {
    const input: Any = { action: 'voidLandedCost' };
    await run('a landed cost of a locked period can’t be voided', input, async () => {
      w = await books();
      const x = await goodsAndCharges(w);
      const cost = await saveLandedCost(w.companyId, {
        billId: x.customs.id,
        sourceLineIds: ['duty'],
        targetBillId: x.goods.id,
        targetLineIds: [],
        method: 'value',
        notes: '',
      });
      await lockAt(w, '2026-10-04');
      input.id = cost.id;
    }, async () => voidLandedCost(input.id));
  }

  // ------------------------------------------------------------ items issued to employees

  let u: Uniforms = null as Any;
  const issueAs = (input: Any) => async () => issueStock(u.companyId, input.issue, input.issuer);
  const withIssue = async (
    name: string,
    make: (u: Uniforms) => Any,
    options: { link?: (u: Uniforms) => Promise<Any>; seed?: (u: Uniforms) => Promise<void>; issuer?: Any } = {},
  ) => {
    const input: Any = { action: 'issueStock' };
    await run(name, input, async () => {
      u = await uniforms();
      w = u;
      if (options.seed) await options.seed(u);
      input.link = options.link ? await options.link(u) : null;
      input.issue = clone(make(u));
      input.issuer = options.issuer ?? { userId: input.link?.userId ?? null, name: ' Owner ' };
    }, issueAs(input));
  };
  const keeper = (u: Uniforms) => link(u, 'staff', KEEPER);

  await withIssue('an owner on this device issues at once', (u) => issueOf(u));
  await withIssue('an owner in the cloud issues at once', (u) => issueOf(u, 2, 3), { link: (u) => link(u, 'owner') });
  await withIssue('an admin who approves issues at once', (u) => issueOf(u), {
    link: (u) => link(u, 'admin', USER.userId, { approver: true }),
  });
  await withIssue('a keeper sends an issue for approval', (u) => issueOf(u), {
    link: keeper,
    issuer: { userId: KEEPER, name: 'Ahmed Saleh (Warehouse Supervisor)' },
  });
  await withIssue('an accountant sends an issue from the main warehouse for approval', (u) =>
    issueOf(u, 3, 0, { warehouseId: u.mainId }), { link: (u) => link(u, 'accountant') },
  );
  await withIssue('the same item twice is one line', (u) => ({
    ...issueOf(u),
    lines: [
      { productId: u.trouser.id, quantity: 1 },
      { productId: u.shirt.id, quantity: 0 },
      { productId: u.trouser.id, quantity: 1.5 },
      { productId: '', quantity: 3 },
    ],
  }));
  await withIssue('the second issue is ISS-0002', (u) => issueOf(u, 2, 0), {
    seed: async (u) => {
      await issueStock(u.companyId, issueOf(u), { userId: null, name: 'Owner' });
    },
  });
  await withIssue('no more than the warehouse holds', (u) => issueOf(u, 6));
  await withIssue('what waits for approval can’t be issued twice', (u) => issueOf(u, 5, 0), {
    link: keeper,
    issuer: { userId: KEEPER, name: 'Ahmed' },
    seed: async (u) => {
      await link(u, 'staff', KEEPER);
      await issueStock(u.companyId, issueOf(u), { userId: KEEPER, name: 'A' });
      const confirmed = await issueStock(u.companyId, issueOf(u, 1, 0), { userId: KEEPER, name: 'A' });
      await db.approvals.update(confirmed.request!.id, { status: 'approved', decidedBy: 'user-owner' });
      const rejected = await issueStock(u.companyId, issueOf(u, 3, 0), { userId: KEEPER, name: 'A' });
      await db.approvals.update(rejected.request!.id, { status: 'rejected' });
    },
  });
  await withIssue('the employee is needed', (u) => ({ ...issueOf(u), recipient: { ...GUARD, employeeId: '' } }));
  await withIssue('the employee’s name is needed', (u) => ({ ...issueOf(u), recipient: { ...GUARD, name: '  ' } }));
  await withIssue('at least one item is needed', (u) => ({ ...issueOf(u), lines: [] }));
  await withIssue('quantities must be positive', (u) => issueOf(u, -1));
  await withIssue('only stock items can be issued', (u) => ({
    ...issueOf(u),
    lines: [{ productId: u.service.id, quantity: 1 }],
  }), {
    seed: async (u) => {
      (u as Any).service = await saveItem(createProduct(u.companyId, { name: 'Delivery' }));
    },
  });
  await withIssue('an archived item can’t be issued', (u) => issueOf(u), {
    seed: async (u) => {
      await db.products.put({ ...u.shirt, archived: true });
    },
  });
  await withIssue('an archived warehouse issues nothing', (u) => issueOf(u), {
    seed: async (u) => {
      const store = await db.warehouses.get(u.storeId);
      await db.warehouses.put({ ...store!, archived: true });
    },
  });
  await withIssue('a member issues only from the store they look after', (u) => issueOf(u), {
    link: (u) => link(u, 'staff', 'user-other'),
  });
  await withIssue('a keeper doesn’t issue from the main warehouse', (u) => issueOf(u, 1, 1, { warehouseId: u.mainId }), {
    link: keeper,
  });
  await withIssue('a viewer issues nothing', (u) => issueOf(u), { link: (u) => link(u, 'viewer', KEEPER) });
  await withIssue('issuing waits for the server to have it', (u) => issueOf(u), {
    link: (u) => link(u, 'owner', USER.userId, { features: ['tables_v16', 'approvals'] }),
  });
  await withIssue('an issue in a locked period is refused', (u) => issueOf(u), {
    seed: async (u) => lockAt(u, '2026-11-05'),
  });

  {
    const input: Any = { action: 'voidStockIssue' };
    await run('voiding an issue brings its stock back', input, async () => {
      u = await uniforms();
      w = u;
      const { issue } = await issueStock(u.companyId, issueOf(u), { userId: null, name: 'Owner' });
      input.id = issue!.id;
      input.link = null;
    }, async () => voidStockIssue(input.id));
  }

  {
    const input: Any = { action: 'voidStockIssue' };
    await run('only an approver voids items issued', input, async () => {
      u = await uniforms();
      w = u;
      const { issue } = await issueStock(u.companyId, issueOf(u), { userId: null, name: 'Owner' });
      input.id = issue!.id;
      input.link = await link(u, 'accountant');
    }, async () => voidStockIssue(input.id));
  }

  {
    const input: Any = { action: 'applyStockIssueRequest' };
    await run('a confirmed request is kept as the issue it carries', input, async () => {
      u = await uniforms();
      w = u;
      await link(u, 'staff', KEEPER);
      const { request } = await issueStock(u.companyId, issueOf(u, 2, 1), {
        userId: KEEPER,
        name: 'Ahmed Saleh (Warehouse Supervisor)',
      });
      await db.syncState.delete(u.companyId);
      const decided = { ...request!, status: 'approved', decidedBy: 'user-owner', decidedAt: '2026-11-28T08:00:00.000Z' };
      await db.approvals.put(decided as Any);
      input.request = clone(decided);
    }, async () => applyStockIssueRequest(input.request));
  }

  {
    const input: Any = { action: 'applyStockIssueRequest' };
    await run('each line is named as the item is, not as the request says', input, async () => {
      u = await uniforms();
      w = u;
      await link(u, 'staff', KEEPER);
      const { request } = await issueStock(u.companyId, issueOf(u), { userId: KEEPER, name: 'A' });
      await db.syncState.delete(u.companyId);
      input.request = clone({
        ...request!,
        status: 'approved',
        requestedByName: '',
        after: {
          ...request!.after,
          lines: [
            { id: 'a', productId: u.trouser.id, name: 'Jacket', unit: 'box', quantity: 1 },
            { id: '', productId: u.shirt.id, name: 'Hat', unit: 'box', quantity: 2 },
          ],
        },
      });
    }, async () => applyStockIssueRequest(input.request));
  }

  {
    const input: Any = { action: 'applyStockIssueRequest' };
    await run('a request carried out again keeps one issue', input, async () => {
      u = await uniforms();
      w = u;
      await link(u, 'staff', KEEPER);
      const { request } = await issueStock(u.companyId, issueOf(u), { userId: KEEPER, name: 'A' });
      await db.syncState.delete(u.companyId);
      const decided = { ...request!, status: 'approved' };
      await applyStockIssueRequest(decided as Any);
      input.request = clone(decided);
    }, async () => applyStockIssueRequest(input.request));
  }

  const badRequest = async (name: string, change: (u: Uniforms, request: Any) => Promise<Any> | Any) => {
    const input: Any = { action: 'applyStockIssueRequest' };
    await run(name, input, async () => {
      u = await uniforms();
      w = u;
      await link(u, 'staff', KEEPER);
      const { request } = await issueStock(u.companyId, issueOf(u), { userId: KEEPER, name: 'A' });
      await db.syncState.delete(u.companyId);
      input.request = clone(await change(u, { ...request!, status: 'approved' }));
    }, async () => applyStockIssueRequest(input.request));
  };
  await badRequest('a request with negative quantities is not kept', (u, r) => ({
    ...r,
    after: { ...r.after, lines: [{ id: 'a', productId: u.trouser.id, name: 'Trouser', unit: 'pcs', quantity: -40 }] },
  }));
  await badRequest('a request for a service is not kept', async (u, r) => {
    const service = await saveItem(createProduct(u.companyId, { name: 'Delivery' }));
    return { ...r, after: { ...r.after, lines: [{ id: 'a', productId: service.id, name: 'X', unit: '', quantity: 1 }] } };
  });
  await badRequest('a request for items already on record under another is not kept', async (u, r) => {
    const direct = await issueStock(u.companyId, issueOf(u, 1, 0), { userId: null, name: 'Owner' });
    return { ...r, subjectId: direct.issue!.id };
  });
  await badRequest('a request this version can’t read is not kept', (u, r) => ({ ...r, after: { lines: [] } }));
  await badRequest('a request without its employee is not kept', (u, r) => ({
    ...r,
    after: { ...r.after, recipient: { ...r.after.recipient, employeeId: '' } },
  }));
  await badRequest('a request from another company’s warehouse is not kept', (u, r) => ({
    ...r,
    after: { ...r.after, warehouseId: 'no-such-warehouse' },
  }));

  writeFixtures('inventory', out);
});
