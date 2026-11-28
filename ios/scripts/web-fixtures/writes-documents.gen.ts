// The web's own outputs for the document ports (MahamKit/Write/Documents):
// sales and purchase documents of all nine types, their numbers, totals,
// statuses, conversions and orders, clients and vendors, items, credit holds
// and approval requests. (Items saved from the item form are the inventory's
// `saveItem`, in writes-inventory.) From the repository root:
//   npx vitest run --config ios/scripts/web-fixtures/writes.gen.config.mjs writes-documents
// writes ios/MahamKit/Tests/MahamKitTests/Fixtures/writes-documents.json.
//
// Each scenario's `input` says what the Swift side runs (`action` and its
// arguments, see WriteDocumentsTests.swift): `reserved` is the counter the
// cloud handed out (a fake reserver) and `request` what the web asked it
// for; `link` is the person's link to a company kept in the cloud.
// Fixed ids and no outbox come from writes-setup.ts (the config's setupFiles).
import { scenario, writeFixtures, type Scenario } from './writes-harness';
import { db } from '@/db/db';
import { createClient, createProduct } from '@/db/defaults';
import {
  convertDocument,
  deleteDocument,
  draftDocument,
  duplicateDocument,
  markSent,
  recalculateDocuments,
  reissueDocument,
  saveDocument,
  setDocumentStatus,
} from '@/db/documents';
import { createFromOrder, markDelivered } from '@/db/orders';
import { deleteClient, saveClient, saveProduct, setupCompany } from '@/db/records';
import { setCreditHold } from '@/db/credit';
import { requestApproval } from '@/db/approvals';
import { saveItem } from '@/db/inventory';
import { setCounterReserver } from '@/lib/numbering';

const NOW = '2026-11-28T09:00:00.000Z';
const USER = { userId: 'u-owner', userName: 'Sample Owner' };

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Any = any;

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

const KW = { line1: '', line2: '', city: 'Kuwait City', state: '', postalCode: '', country: 'KW' };

interface World {
  companyId: string;
  clientId: string;
  vendorId: string;
}

/** A Kuwaiti company (KWD, the Kuwait chart, no taxes), a client and a vendor. */
async function kuwait(edit?: (company: Any) => void, clientExtra: Any = {}): Promise<World> {
  const company = await setupCompany({ name: 'Al Waha Trading', currency: 'KWD', locale: 'en-KW', address: KW });
  if (edit) {
    const stored: Any = await db.companies.get(company.id);
    edit(stored);
    await db.companies.put(stored);
  }
  const client = await saveClient(
    createClient(company.id, { name: 'Al Rawda Trading', nameAr: 'الروضة التجارية', ...clientExtra }),
  );
  const vendor = await saveClient(
    createClient(company.id, { name: 'Gulf Paper', isCustomer: false, isVendor: true }),
  );
  return { companyId: company.id, clientId: client.id, vendorId: vendor.id };
}

/** A company in the Emirates (AED, 5% VAT on lines by default). */
async function emirates(edit?: (company: Any) => void): Promise<World> {
  const company = await setupCompany(
    {
      name: 'Desert Rose LLC',
      currency: 'AED',
      locale: 'en-AE',
      address: { line1: '', line2: '', city: 'Dubai', state: '', postalCode: '', country: 'AE' },
    },
    [{ name: 'VAT', rate: 5 }],
  );
  if (edit) {
    const stored: Any = await db.companies.get(company.id);
    edit(stored);
    await db.companies.put(stored);
  }
  const client = await saveClient(createClient(company.id, { name: 'Palm Contracting' }));
  const vendor = await saveClient(
    createClient(company.id, { name: 'Marina Supplies', isCustomer: false, isVendor: true }),
  );
  return { companyId: company.id, clientId: client.id, vendorId: vendor.id };
}

/** A company with the generic chart (no retention accounts yet), in US dollars. */
async function generic(): Promise<World> {
  const company = await setupCompany({
    name: 'Northwind Services',
    currency: 'USD',
    locale: 'en-US',
    address: { line1: '', line2: '', city: 'Austin', state: 'TX', postalCode: '', country: 'US' },
  });
  const client = await saveClient(
    createClient(company.id, { name: 'Contoso Builders', retentionPercent: 10, retentionKind: 'contract' }),
  );
  const vendor = await saveClient(
    createClient(company.id, { name: 'Fabrikam Steel', isCustomer: false, isVendor: true }),
  );
  return { companyId: company.id, clientId: client.id, vendorId: vendor.id };
}

async function company(id: string): Promise<Any> {
  return db.companies.get(id);
}

/** A draft of a type for the client (or vendor), saved with `patch` laid over it. */
async function saved(w: World, type: Any, patch: Any = {}, contact = w.clientId): Promise<Any> {
  const c = await company(w.companyId);
  const client = await db.clients.get(contact);
  const draft = await draftDocument(c, type, client ?? null);
  return saveDocument({ ...draft, ...patch });
}

/** A payment received against documents. */
async function payment(w: World, number: string, allocations: { documentId: string; amount: number }[], extra: Any = {}) {
  const amount = allocations.reduce((s, a) => s + a.amount, 0);
  const row = {
    id: `pay-${number}`,
    companyId: w.companyId,
    direction: 'in',
    clientId: w.clientId,
    number,
    date: '2026-11-20',
    amount,
    currency: 'KWD',
    method: 'bank_transfer',
    reference: '',
    notes: '',
    allocations,
    documentIds: allocations.map((a) => a.documentId),
    creditId: null,
    createdAt: NOW,
    updatedAt: NOW,
    ...extra,
  };
  await db.payments.put(row as Any);
  await recalculateDocuments([...row.documentIds, ...(row.creditId ? [row.creditId] : [])]);
  return row;
}

/** Links the company to the cloud for a person (`db.syncState`). */
async function link(w: World, role: string, approver = false) {
  await db.syncState.put({
    companyId: w.companyId,
    userId: USER.userId,
    role,
    status: 'ready',
    cursor: 1,
    name: 'Company',
    linkedAt: NOW,
    lastSyncAt: null,
    lastError: null,
    lastErrorAt: null,
    approver,
  } as Any);
  return { userId: USER.userId, role, approver };
}

/** Takes numbers from a fake cloud counter during the action, noting what was asked. */
function reserving(input: Any, counter: number, period = '') {
  input.reserved = { counter, period };
  setCounterReserver(async ({ kind, date, min }) => {
    input.request = { kind, date, min };
    return { counter, period };
  });
}

const out: Scenario[] = [];

/** Runs a scenario; the cloud's bookkeeping tables stay out of the fixtures. */
async function run(name: string, input: Any, seed: () => Promise<void>, action: () => Promise<unknown>, role?: string) {
  const s = await scenario(name, { now: NOW, ...USER, ...(role ? { role } : {}), input, seed }, async () => {
    try {
      await action();
    } finally {
      setCounterReserver(null);
    }
  });
  for (const tables of [s.before, s.after]) {
    for (const name of ['meta', 'syncState', 'outbox', 'syncRevs', 'fileQueue']) delete tables[name];
  }
  out.push(s);
}

it('documents', async () => {
  let w: World = { companyId: '', clientId: '', vendorId: '' };
  let doc: Any = null;
  let other: Any = null;

  // ------------------------------------------------------------------ drafts and totals

  {
    const input: Any = { action: 'draftAndSave', type: 'invoice' };
    await run('a new invoice, KWD rounded to 3 decimals', input, async () => {
      w = await kuwait();
      input.clientId = w.clientId;
      input.patch = {
        items: [
          line({ id: 'l1', name: 'Thermal paper', quantity: 3, unit: 'box', unitPrice: 1.2345 }),
          line({ id: 'l2', name: 'Delivery', quantity: 1, unitPrice: 2.5 }),
        ],
      };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(w.clientId);
      await saveDocument({ ...(await draftDocument(c, 'invoice', client ?? null)), ...input.patch });
    });
  }

  {
    const input: Any = { action: 'draftAndSave', type: 'invoice' };
    await run('line and document discounts, and a charge', input, async () => {
      w = await kuwait();
      input.clientId = w.clientId;
      input.patch = {
        poNumber: 'LPO-88',
        discount: 7.5,
        discountType: 'percent',
        charges: [{ id: 'ch1', label: 'Shipping', amount: 4.25, taxes: [] }],
        items: [
          line({ id: 'l1', name: 'Printer', quantity: 2, unitPrice: 125.25, discount: 10, discountType: 'percent' }),
          line({ id: 'l2', name: 'Cable', quantity: 7, unitPrice: 0.875, discount: 0.5, discountType: 'amount' }),
          line({ id: 'h1', kind: 'heading', name: 'Services', quantity: 0 }),
          line({ id: 'l3', name: 'Setup', quantity: 1.5, unitPrice: 12.333 }),
        ],
      };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(w.clientId);
      await saveDocument({ ...(await draftDocument(c, 'invoice', client ?? null)), ...input.patch });
    });
  }

  {
    const input: Any = { action: 'draftAndSave', type: 'invoice' };
    await run('5% VAT on lines, a fixed discount and a taxed charge (AED)', input, async () => {
      w = await emirates();
      input.clientId = w.clientId;
      const vat = { name: 'VAT', rate: 5 };
      input.patch = {
        discount: 15,
        discountType: 'amount',
        charges: [{ id: 'ch1', label: 'Shipping', amount: 20, taxes: [vat] }],
        items: [
          line({ id: 'l1', name: 'Tiles', quantity: 13, unitPrice: 17.99, taxes: [vat] }),
          line({ id: 'l2', name: 'Grout', quantity: 3, unitPrice: 9.33, taxes: [vat] }),
          line({ id: 'l3', name: 'Export pallet', quantity: 1, unitPrice: 50, taxes: [{ name: 'Zero rated', rate: 0, kind: 'zero' }] }),
        ],
      };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(w.clientId);
      await saveDocument({ ...(await draftDocument(c, 'invoice', client ?? null)), ...input.patch });
    });
  }

  {
    const input: Any = { action: 'draftAndSave', type: 'invoice' };
    await run('prices including VAT, with a reverse charge line', input, async () => {
      w = await emirates();
      input.clientId = w.clientId;
      const vat = { name: 'VAT', rate: 5 };
      input.patch = {
        pricesIncludeTax: true,
        discount: 3,
        discountType: 'percent',
        items: [
          line({ id: 'l1', name: 'Consulting', quantity: 3, unitPrice: 105, taxes: [vat] }),
          line({ id: 'l2', name: 'Licence', quantity: 1, unitPrice: 99.99, taxes: [vat] }),
          line({ id: 'l3', name: 'Imported service', quantity: 1, unitPrice: 200, taxes: [{ name: 'VAT', rate: 5, kind: 'reverse_charge' }] }),
        ],
      };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(w.clientId);
      await saveDocument({ ...(await draftDocument(c, 'invoice', client ?? null)), ...input.patch });
    });
  }

  {
    const input: Any = { action: 'draftAndSave', type: 'invoice' };
    await run('a dollar invoice of a Kuwaiti company, issued with its rate', input, async () => {
      w = await kuwait();
      input.clientId = w.clientId;
      input.patch = {
        status: 'sent',
        currency: 'USD',
        exchangeRate: 0.3051,
        items: [line({ id: 'l1', name: 'Software', quantity: 3, unitPrice: 333.335 })],
      };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(w.clientId);
      await saveDocument({ ...(await draftDocument(c, 'invoice', client ?? null)), ...input.patch });
    });
  }

  {
    const input: Any = { action: 'draftAndSave', type: 'invoice' };
    await run('the client’s tax retention, issued with a deposit asked', input, async () => {
      w = await kuwait(undefined, { retentionPercent: 5, retentionKind: 'tax' });
      input.clientId = w.clientId;
      input.patch = {
        status: 'sent',
        deposit: 100,
        depositDueDate: '2026-12-05',
        items: [line({ id: 'l1', name: 'Fit-out works', quantity: 1, unitPrice: 1234.567 })],
      };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(w.clientId);
      await saveDocument({ ...(await draftDocument(c, 'invoice', client ?? null)), ...input.patch });
    });
  }

  {
    const input: Any = { action: 'draftAndSave', type: 'invoice' };
    await run('a contract retention makes its account in a chart without one', input, async () => {
      w = await generic();
      input.clientId = w.clientId;
      input.patch = { status: 'sent', items: [line({ id: 'l1', name: 'Steel frame', quantity: 4, unitPrice: 999.99 })] };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(w.clientId);
      await saveDocument({ ...(await draftDocument(c, 'invoice', client ?? null)), ...input.patch });
    });
  }

  {
    const input: Any = { action: 'draftAndSave', type: 'bill' };
    await run('a bill with a retention held from the vendor', input, async () => {
      w = await generic();
      await db.clients.update(w.vendorId, { retentionPercent: 5, retentionKind: 'contract' } as Any);
      input.clientId = w.vendorId;
      input.patch = { status: 'sent', vendorReference: 'FS-1002', items: [line({ id: 'l1', name: 'Beams', quantity: 10, unitPrice: 45.5 })] };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(w.vendorId);
      await saveDocument({ ...(await draftDocument(c, 'bill', client ?? null)), ...input.patch });
    });
  }

  for (const type of ['quote', 'credit', 'proforma', 'sales_order', 'delivery_note', 'vendor_credit', 'purchase_order']) {
    const input: Any = { action: 'draftAndSave', type };
    await run(`a new ${type.replace('_', ' ')}`, input, async () => {
      w = await emirates((c) => {
        c.defaults.quoteIntro = 'Further to your request, we are pleased to quote:';
        c.defaults.creditNotes = 'Credited against your account.';
        c.defaults.footer = 'Thank you for your business.';
      });
      const purchase = type === 'vendor_credit' || type === 'purchase_order';
      input.clientId = purchase ? w.vendorId : w.clientId;
      input.patch = {
        items: [
          line({ id: 'l1', name: 'Marble slab', nameAr: 'لوح رخام', quantity: 2, unit: 'pcs', unitPrice: 410.5, taxes: type === 'delivery_note' ? [] : [{ name: 'VAT', rate: 5 }] }),
        ],
      };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(input.clientId);
      await saveDocument({ ...(await draftDocument(c, type as Any, client ?? null)), ...input.patch });
    });
  }

  {
    const input: Any = { action: 'draftAndSave', type: 'invoice' };
    await run('an invoice issued with an item: what it posts with is kept', input, async () => {
      w = await kuwait();
      const sales = (await db.accounts.where('companyId').equals(w.companyId).toArray()).find((a: Any) => a.role === 'sales');
      const product = await saveProduct(createProduct(w.companyId, { name: 'Annual support', unitPrice: 240, incomeAccountId: sales?.id }));
      input.clientId = w.clientId;
      input.patch = {
        status: 'sent',
        items: [line({ id: 'l1', productId: product.id, name: 'Annual support', quantity: 1, unitPrice: 240 }), line({ id: 'l2', name: 'Travel', unitPrice: 15 })],
      };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(w.clientId);
      await saveDocument({ ...(await draftDocument(c, 'invoice', client ?? null)), ...input.patch });
    });
  }

  // ------------------------------------------------------------------ numbers

  {
    const input: Any = { action: 'draftAndSave', type: 'invoice' };
    await run('a draft numbered when issued keeps no number', input, async () => {
      w = await kuwait((c) => {
        c.defaults.numberOnIssue = true;
      });
      input.clientId = w.clientId;
      input.patch = { items: [line({ id: 'l1', name: 'Rent', unitPrice: 500 })] };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(w.clientId);
      await saveDocument({ ...(await draftDocument(c, 'invoice', client ?? null)), ...input.patch });
    });
  }

  {
    const input: Any = { action: 'markSent' };
    await run('issuing a draft that waited for its number numbers it', input, async () => {
      w = await kuwait((c) => {
        c.defaults.numberOnIssue = true;
      });
      doc = await saved(w, 'invoice', { items: [line({ id: 'l1', name: 'Rent', unitPrice: 500 })] });
      input.id = doc.id;
    }, () => markSent(input.id));
  }

  {
    const input: Any = { action: 'markSent' };
    await run('issuing with a number taken in the cloud', input, async () => {
      w = await kuwait((c) => {
        c.defaults.numberOnIssue = true;
      });
      doc = await saved(w, 'invoice', { items: [line({ id: 'l1', name: 'Rent', unitPrice: 500 })] });
      input.id = doc.id;
    }, async () => {
      reserving(input, 12);
      await markSent(input.id);
    });
  }

  {
    const input: Any = { action: 'draftAndSave', type: 'invoice' };
    await run('a new invoice numbered from the cloud’s counter', input, async () => {
      w = await kuwait();
      input.clientId = w.clientId;
      input.patch = { items: [line({ id: 'l1', name: 'Rent', unitPrice: 500 })] };
    }, async () => {
      reserving(input, 7);
      const c = await company(w.companyId);
      const client = await db.clients.get(w.clientId);
      await saveDocument({ ...(await draftDocument(c, 'invoice', client ?? null)), ...input.patch });
    });
  }

  {
    const input: Any = { action: 'draftAndSave', type: 'invoice' };
    await run('the next number skips one typed by hand', input, async () => {
      w = await kuwait();
      await saved(w, 'invoice', { number: ' INV-2026-0001 ', items: [line({ id: 'l1', name: 'A', unitPrice: 1 })] });
      input.clientId = w.clientId;
      input.patch = { items: [line({ id: 'l1', name: 'B', unitPrice: 2 })] };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(w.clientId);
      await saveDocument({ ...(await draftDocument(c, 'invoice', client ?? null)), ...input.patch });
    });
  }

  {
    const input: Any = { action: 'draftAndSave', type: 'invoice' };
    await run('a number another document has is refused', input, async () => {
      w = await kuwait();
      await saved(w, 'invoice', { items: [line({ id: 'l1', name: 'A', unitPrice: 1 })] });
      input.clientId = w.clientId;
      input.patch = { number: 'inv-2026-0001', items: [line({ id: 'l1', name: 'B', unitPrice: 2 })] };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(w.clientId);
      await saveDocument({ ...(await draftDocument(c, 'invoice', client ?? null)), ...input.patch });
    });
  }

  {
    const input: Any = { action: 'draftAndSave', type: 'quote' };
    await run('a monthly counter with the client’s number', input, async () => {
      w = await kuwait((c) => {
        c.numbering.quote = { pattern: 'Q/{client}/{yy}{month}-{counter}', next: 9, padding: 3, reset: 'monthly', period: '2026-10' };
      });
      input.clientId = w.clientId;
      input.patch = { items: [line({ id: 'l1', name: 'Survey', unitPrice: 75 })] };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(w.clientId);
      await saveDocument({ ...(await draftDocument(c, 'quote', client ?? null)), ...input.patch });
    });
  }

  // ------------------------------------------------------------------ editing

  {
    const input: Any = { action: 'saveDocument' };
    await run('an issued invoice edited, with a part paid', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'invoice', { items: [line({ id: 'l1', name: 'Chairs', quantity: 10, unitPrice: 12.5 })] });
      await markSent(doc.id);
      await payment(w, 'PAY-0001', [{ documentId: doc.id, amount: 50 }]);
      const stored: Any = await db.documents.get(doc.id);
      input.document = { ...stored, items: [{ ...stored.items[0], quantity: 12 }], notes: 'Two more chairs.' };
    }, () => saveDocument(input.document));
  }

  {
    const input: Any = { action: 'saveDocument' };
    await run('an invoice paid in full when saved again', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', quantity: 1, unitPrice: 80 })] });
      await db.payments.put({
        id: 'pay-1', companyId: w.companyId, direction: 'in', clientId: w.clientId, number: 'PAY-0001', date: '2026-11-25', amount: 80,
        currency: 'KWD', method: 'knet', reference: '', notes: '', allocations: [{ documentId: doc.id, amount: 80 }], documentIds: [doc.id],
        creditId: null, createdAt: NOW, updatedAt: NOW,
      } as Any);
      input.document = await db.documents.get(doc.id);
    }, () => saveDocument(input.document));
  }

  {
    const input: Any = { action: 'saveDocument' };
    await run('the currency stays once a payment is recorded', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      await payment(w, 'PAY-0001', [{ documentId: doc.id, amount: 30 }]);
      input.document = { ...(await db.documents.get(doc.id)), currency: 'USD', exchangeRate: 0.305 };
    }, () => saveDocument(input.document));
  }

  {
    const input: Any = { action: 'saveDocument' };
    await run('the books are locked before the date', input, async () => {
      w = await kuwait((c) => {
        c.accounting.lockDate = '2026-06-30';
      });
      const c = await company(w.companyId);
      const draft = await draftDocument(c, 'invoice', (await db.clients.get(w.clientId)) ?? null);
      input.document = { ...draft, status: 'sent', issueDate: '2026-05-01', items: [line({ id: 'l1', name: 'Old sale', unitPrice: 10 })] };
    }, () => saveDocument(input.document));
  }

  {
    const input: Any = { action: 'saveDocument' };
    await run('more retention released than held is refused', input, async () => {
      w = await kuwait(undefined, { retentionPercent: 5 });
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Works', unitPrice: 1000 })] });
      const stored: Any = await db.documents.get(doc.id);
      await db.documents.put({ ...stored, retentionReleases: [{ id: 'r1', date: '2026-11-27', amount: 50, journalId: 'j1' }] });
      input.document = { ...stored, retentionPercent: 2 };
    }, () => saveDocument(input.document));
  }

  // ------------------------------------------------------------------ statuses

  {
    const input: Any = { action: 'markSent' };
    await run('an invoice marked as sent', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'invoice', { items: [line({ id: 'l1', name: 'Paper', quantity: 4, unitPrice: 2.125 })] });
      input.id = doc.id;
    }, () => markSent(input.id));
  }

  {
    const input: Any = { action: 'markSent' };
    await run('a bill marked as open', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'bill', { items: [line({ id: 'l1', name: 'Paper', quantity: 4, unitPrice: 2.125 })] }, w.vendorId);
      input.id = doc.id;
    }, () => markSent(input.id));
  }

  {
    const input: Any = { action: 'markSent' };
    await run('a sales order confirmed', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'sales_order', { items: [line({ id: 'l1', name: 'Printer', quantity: 5, unitPrice: 125.25 })] });
      input.id = doc.id;
    }, () => markSent(input.id));
  }

  {
    const input: Any = { action: 'markSent' };
    await run('a purchase order issued', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'purchase_order', { items: [line({ id: 'l1', name: 'Toner', quantity: 6, unitPrice: 18 })] }, w.vendorId);
      input.id = doc.id;
    }, () => markSent(input.id));
  }

  for (const status of ['accepted', 'declined']) {
    const input: Any = { action: 'setDocumentStatus', status };
    await run(`a quote marked as ${status}`, input, async () => {
      w = await kuwait();
      doc = await saved(w, 'quote', { items: [line({ id: 'l1', name: 'Survey', unitPrice: 75 })] });
      await markSent(doc.id);
      input.id = doc.id;
    }, () => setDocumentStatus(input.id, status as Any));
  }

  {
    const input: Any = { action: 'setDocumentStatus', status: 'void' };
    await run('an invoice voided as it always was', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      await payment(w, 'PAY-0001', [{ documentId: doc.id, amount: 30 }]);
      input.id = doc.id;
    }, () => setDocumentStatus(input.id, 'void'));
  }

  {
    const input: Any = { action: 'setDocumentStatus', status: 'void', patch: { voidReason: 'Wrong customer' }, freePaid: true };
    await run('voided with a reason, its payment left as credit (void and reissue)', input, async () => {
      w = await kuwait((c) => {
        c.defaults.numberOnIssue = true;
      });
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      await payment(w, 'PAY-0001', [{ documentId: doc.id, amount: 30 }]);
      input.link = await link(w, 'owner');
      input.id = doc.id;
    }, () => setDocumentStatus(input.id, 'void', undefined, input.patch, { freePaid: true }));
  }

  {
    const input: Any = { action: 'setDocumentStatus', status: 'sent' };
    await run('a void invoice restored', input, async () => {
      w = await kuwait((c) => {
        c.defaults.numberOnIssue = true;
      });
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      await setDocumentStatus(doc.id, 'void', undefined, { voidReason: 'By mistake' });
      input.id = doc.id;
    }, () => setDocumentStatus(input.id, 'sent'));
  }

  {
    const input: Any = { action: 'setDocumentStatus', status: 'void' };
    await run('voiding an invoice takes the credit note applied to it off', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      other = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Lamp', unitPrice: 40 })] });
      const credit = await saved(w, 'credit', { status: 'sent', sourceId: doc.id, items: [line({ id: 'l1', name: 'Desk return', unitPrice: 50 })] });
      await payment(w, 'APP-0001', [{ documentId: doc.id, amount: 20 }, { documentId: other.id, amount: 30 }], {
        method: 'credit_note', creditId: credit.id,
      });
      input.id = doc.id;
    }, () => setDocumentStatus(input.id, 'void'));
  }

  {
    const input: Any = { action: 'setDocumentStatus', status: 'void' };
    await run('voiding a credit note takes it off the invoices', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      const credit = await saved(w, 'credit', { status: 'sent', items: [line({ id: 'l1', name: 'Desk return', unitPrice: 50 })] });
      await payment(w, 'APP-0001', [{ documentId: doc.id, amount: 50 }], { method: 'credit_note', creditId: credit.id });
      input.id = credit.id;
    }, () => setDocumentStatus(input.id, 'void'));
  }

  {
    const input: Any = { action: 'setDocumentStatus', status: 'draft' };
    await run('an invoice moved back to draft', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      input.id = doc.id;
    }, () => setDocumentStatus(input.id, 'draft'));
  }

  {
    const input: Any = { action: 'setDocumentStatus', status: 'void' };
    await run('voiding in a locked period is refused', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'invoice', { status: 'sent', issueDate: '2026-03-10', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      const c: Any = await company(w.companyId);
      await db.companies.put({ ...c, accounting: { ...c.accounting, lockDate: '2026-03-31' } });
      input.id = doc.id;
    }, () => setDocumentStatus(input.id, 'void'));
  }

  {
    const input: Any = { action: 'setDocumentStatus', status: 'void' };
    await run('released retention keeps the invoice in the books', input, async () => {
      w = await kuwait(undefined, { retentionPercent: 5 });
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Works', unitPrice: 1000 })] });
      const stored: Any = await db.documents.get(doc.id);
      await db.documents.put({ ...stored, retentionReleases: [{ id: 'r1', date: '2026-11-27', amount: 50, journalId: 'j1' }] });
      input.id = doc.id;
    }, () => setDocumentStatus(input.id, 'void'));
  }

  {
    const input: Any = { action: 'saveDocument' };
    await run('an approver’s rules keep an issued invoice: an admin is asked to send it for approval', input, async () => {
      w = await kuwait((c) => {
        c.approvalRules = { documentTypes: ['invoice', 'credit'], voidInsteadOfDelete: true };
      });
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      input.link = await link(w, 'admin');
      const stored: Any = await db.documents.get(doc.id);
      input.document = { ...stored, items: [{ ...stored.items[0], unitPrice: 70 }] };
    }, () => saveDocument(input.document), 'admin');
  }

  {
    const input: Any = { action: 'setDocumentStatus', status: 'void', patch: { voidReason: 'Duplicate' } };
    await run('voided by an approver under the rules: its payment becomes credit', input, async () => {
      w = await kuwait((c) => {
        c.approvalRules = { documentTypes: ['invoice'] };
      });
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      await payment(w, 'PAY-0001', [{ documentId: doc.id, amount: 80 }]);
      input.link = await link(w, 'owner');
      input.id = doc.id;
    }, () => setDocumentStatus(input.id, 'void', undefined, input.patch));
  }

  {
    const input: Any = { action: 'setDocumentStatus', status: 'cancelled' };
    await run('a sales order cancelled', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'sales_order', { items: [line({ id: 'l1', name: 'Printer', quantity: 5, unitPrice: 125.25 })] });
      await markSent(doc.id);
      input.id = doc.id;
    }, () => setDocumentStatus(input.id, 'cancelled'));
  }

  {
    const input: Any = { action: 'setDocumentStatus', status: 'confirmed' };
    await run('a cancelled sales order reopened picks up its invoices', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'sales_order', { items: [line({ id: 'l1', name: 'Printer', quantity: 5, unitPrice: 125.25 })] });
      await markSent(doc.id);
      await createFromOrder(doc.id, 'invoice', { l1: 2 });
      await setDocumentStatus(doc.id, 'cancelled');
      input.id = doc.id;
    }, () => setDocumentStatus(input.id, 'confirmed'));
  }

  // ------------------------------------------------------------------ deleting

  {
    const input: Any = { action: 'deleteDocument' };
    await run('a draft invoice deleted', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'invoice', { items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      await db.attachments.put({ id: 'att-1', companyId: w.companyId, ownerId: doc.id, name: 'po.pdf', type: 'application/pdf', size: 10, createdAt: NOW } as Any);
      input.id = doc.id;
    }, () => deleteDocument(input.id));
  }

  {
    const input: Any = { action: 'deleteDocument' };
    await run('deleting a paid invoice keeps the money as credit and takes credits off', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      const credit = await saved(w, 'credit', { status: 'sent', sourceId: doc.id, items: [line({ id: 'l1', name: 'Discount', unitPrice: 10 })] });
      await payment(w, 'PAY-0001', [{ documentId: doc.id, amount: 30 }]);
      await payment(w, 'APP-0001', [{ documentId: doc.id, amount: 10 }], { method: 'credit_note', creditId: credit.id });
      input.id = doc.id;
    }, () => deleteDocument(input.id));
  }

  {
    const input: Any = { action: 'deleteDocument' };
    await run('deleting the invoice a quote became reopens the quote', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'quote', { items: [line({ id: 'l1', name: 'Survey', unitPrice: 75 })] });
      other = await convertDocument(doc.id, 'invoice');
      input.id = other.id;
    }, () => deleteDocument(input.id));
  }

  {
    const input: Any = { action: 'deleteDocument' };
    await run('deleting an invoice of an order puts its quantities back', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'sales_order', { items: [line({ id: 'l1', name: 'Printer', quantity: 5, unitPrice: 125.25 })] });
      await markSent(doc.id);
      other = await createFromOrder(doc.id, 'invoice', { l1: 5 });
      input.id = other.id;
    }, () => deleteDocument(input.id));
  }

  {
    const input: Any = { action: 'deleteDocument' };
    await run('deleting the copy issued in place of a void invoice', input, async () => {
      w = await kuwait((c) => {
        c.defaults.numberOnIssue = true;
      });
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      await setDocumentStatus(doc.id, 'void', undefined, { voidReason: 'Wrong price' });
      other = await reissueDocument(doc.id);
      input.id = other.id;
    }, () => deleteDocument(input.id));
  }

  {
    const input: Any = { action: 'deleteDocument' };
    await run('an issued invoice under “void instead of delete” is refused', input, async () => {
      w = await kuwait((c) => {
        c.approvalRules = { documentTypes: ['invoice'], voidInsteadOfDelete: true };
      });
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      input.link = await link(w, 'owner');
      input.id = doc.id;
    }, () => deleteDocument(input.id));
  }

  {
    const input: Any = { action: 'deleteDocument' };
    await run('anyone but an approver asks for a void instead of deleting', input, async () => {
      w = await kuwait((c) => {
        c.approvalRules = { documentTypes: ['invoice'] };
      });
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      input.link = await link(w, 'accountant');
      input.id = doc.id;
    }, () => deleteDocument(input.id), 'accountant');
  }

  {
    const input: Any = { action: 'deleteDocument' };
    await run('deleting an invoice its credit note points at', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'invoice', { items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      await saved(w, 'credit', { sourceId: doc.id, items: [line({ id: 'l1', name: 'Return', unitPrice: 80 })] });
      input.id = doc.id;
    }, () => deleteDocument(input.id));
  }

  // ------------------------------------------------------------------ copies and conversions

  {
    const input: Any = { action: 'duplicateDocument' };
    await run('an invoice duplicated', input, async () => {
      w = await emirates();
      doc = await saved(w, 'invoice', {
        status: 'sent',
        poNumber: 'PO-77',
        accentColor: '#0f766e',
        discount: 5,
        charges: [{ id: 'ch1', label: 'Shipping', amount: 12, taxes: [{ name: 'VAT', rate: 5 }] }],
        items: [line({ id: 'l1', name: 'Tiles', quantity: 13, unitPrice: 17.99, taxes: [{ name: 'VAT', rate: 5 }], sourceLineId: 'x' })],
      });
      input.id = doc.id;
    }, () => duplicateDocument(input.id));
  }

  {
    const input: Any = { action: 'duplicateDocument', asType: 'credit' };
    await run('a credit note made from an invoice', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'invoice', { status: 'sent', currency: 'USD', exchangeRate: 0.306, items: [line({ id: 'l1', name: 'Licence', unitPrice: 1200 })] });
      input.id = doc.id;
      input.overrides = { sourceId: doc.id };
    }, () => duplicateDocument(input.id, 'credit', input.overrides));
  }

  for (const to of ['invoice', 'proforma', 'sales_order']) {
    const input: Any = { action: 'convertDocument', to };
    await run(`a quote converted to ${to.replace('_', ' ')}`, input, async () => {
      w = await kuwait((c) => {
        c.defaults.quoteNotes = 'Valid for 30 days.';
      });
      doc = await saved(w, 'quote', {
        notes: 'Prices include installation.',
        deposit: 50,
        depositDueDate: '2026-12-01',
        deliveryDate: '2026-12-15',
        items: [line({ id: 'l1', name: 'Survey', nameAr: 'مسح', unitPrice: 75 })],
      });
      await markSent(doc.id);
      input.id = doc.id;
    }, () => convertDocument(input.id, to as Any));
  }

  {
    const input: Any = { action: 'convertDocument', to: 'invoice' };
    await run('a proforma converted to a draft invoice numbered when issued', input, async () => {
      w = await kuwait((c) => {
        c.defaults.numberOnIssue = true;
      });
      doc = await saved(w, 'proforma', { deposit: 100, items: [line({ id: 'l1', name: 'Kitchen', unitPrice: 900 })] });
      input.id = doc.id;
    }, () => convertDocument(input.id, 'invoice'));
  }

  {
    const input: Any = { action: 'convertDocument', to: 'invoice' };
    await run('a quote converted with a number from the cloud', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'quote', { items: [line({ id: 'l1', name: 'Survey', unitPrice: 75 })] });
      input.id = doc.id;
    }, async () => {
      reserving(input, 31);
      await convertDocument(input.id, 'invoice');
    });
  }

  {
    const input: Any = { action: 'reissueDocument' };
    await run('a void invoice issued again in its place', input, async () => {
      w = await kuwait((c) => {
        c.defaults.numberOnIssue = true;
      });
      doc = await saved(w, 'invoice', { status: 'sent', sourceId: null, items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      await setDocumentStatus(doc.id, 'void', undefined, { voidReason: 'Wrong price' });
      input.id = doc.id;
    }, () => reissueDocument(input.id));
  }

  {
    const input: Any = { action: 'reissueDocument' };
    await run('only a void document is issued again', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      input.id = doc.id;
    }, () => reissueDocument(input.id));
  }

  // ------------------------------------------------------------------ orders

  {
    const input: Any = { action: 'createFromOrder', target: 'invoice', quantities: { l1: 2, l2: 40 } };
    await run('part of a sales order invoiced', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'sales_order', {
        poNumber: 'LPO-55120',
        notes: 'Deliver to the Shuwaikh warehouse.',
        deliveryPlace: 'Warehouse 4, Shuwaikh Industrial',
        discount: 20,
        discountType: 'amount',
        charges: [{ id: 'ch1', label: 'Shipping', amount: 15, taxes: [] }],
        items: [
          line({ id: 'h1', kind: 'heading', name: 'Hardware', quantity: 0 }),
          line({ id: 'l1', name: 'Thermal label printer', nameAr: 'طابعة ملصقات حرارية', quantity: 5, unit: 'pcs', unitPrice: 125.25 }),
          line({ id: 'l2', name: 'Label rolls', nameAr: 'لفات ملصقات', quantity: 40, unit: 'rolls', unitPrice: 3.125 }),
        ],
      });
      await markSent(doc.id);
      input.id = doc.id;
    }, () => createFromOrder(input.id, 'invoice', input.quantities));
  }

  {
    const input: Any = { action: 'createFromOrder', target: 'invoice' };
    await run('the rest of a sales order invoiced takes the rest of its discount', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'sales_order', {
        discount: 20,
        discountType: 'amount',
        charges: [{ id: 'ch1', label: 'Shipping', amount: 15, taxes: [] }],
        items: [
          line({ id: 'l1', name: 'Printer', quantity: 5, unitPrice: 125.25 }),
          line({ id: 'l2', name: 'Rolls', quantity: 40, unitPrice: 3.125 }),
        ],
      });
      await markSent(doc.id);
      await createFromOrder(doc.id, 'invoice', { l1: 2, l2: 40 });
      input.id = doc.id;
    }, () => createFromOrder(input.id, 'invoice'));
  }

  {
    const input: Any = { action: 'createFromOrder', target: 'invoice' };
    await run('invoicing a draft order confirms it first', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'sales_order', { items: [line({ id: 'l1', name: 'Printer', quantity: 5, unitPrice: 125.25 })] });
      input.id = doc.id;
    }, () => createFromOrder(input.id, 'invoice'));
  }

  {
    const input: Any = { action: 'createFromOrder', target: 'invoice' };
    await run('nothing left to invoice', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'sales_order', { items: [line({ id: 'l1', name: 'Printer', quantity: 5, unitPrice: 125.25 })] });
      await markSent(doc.id);
      await createFromOrder(doc.id, 'invoice');
      input.id = doc.id;
    }, () => createFromOrder(input.id, 'invoice'));
  }

  {
    const input: Any = { action: 'createFromOrder', target: 'delivery_note', quantities: { l1: 3 } };
    await run('a delivery note for part of a sales order', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'sales_order', {
        deliveryPlace: 'Site 9',
        items: [line({ id: 'l1', name: 'Printer', quantity: 5, unit: 'pcs', unitPrice: 125.25 }), line({ id: 'l2', name: 'Rolls', quantity: 40, unitPrice: 3.125 })],
      });
      await markSent(doc.id);
      input.id = doc.id;
    }, () => createFromOrder(input.id, 'delivery_note', input.quantities));
  }

  {
    const input: Any = { action: 'createFromOrder', target: 'delivery_note' };
    await run('a delivery note of an invoice of a sales order', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'sales_order', { items: [line({ id: 'l1', name: 'Printer', quantity: 5, unitPrice: 125.25 })] });
      await markSent(doc.id);
      const note = await createFromOrder(doc.id, 'delivery_note', { l1: 2 });
      await markDelivered(note.id, { date: '2026-11-27', receiverName: 'Ahmad' });
      other = await createFromOrder(doc.id, 'invoice', { l1: 4 });
      input.id = other.id;
    }, () => createFromOrder(input.id, 'delivery_note'));
  }

  {
    const input: Any = { action: 'markDelivered', date: '2026-11-28', receiverName: '  Fatima Al-Sabah ', receiverCivilId: '2850 1012 3456' };
    await run('a delivery note marked as delivered', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'sales_order', { items: [line({ id: 'l1', name: 'Printer', quantity: 5, unitPrice: 125.25 })] });
      await markSent(doc.id);
      other = await createFromOrder(doc.id, 'delivery_note', { l1: 5 });
      input.id = other.id;
    }, () => markDelivered(input.id, { date: input.date, receiverName: input.receiverName, receiverCivilId: input.receiverCivilId }));
  }

  {
    const input: Any = { action: 'createFromOrder', target: 'bill', quantities: { l1: 4 } };
    await run('part of a purchase order billed', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'purchase_order', {
        notes: 'Deliver before noon.',
        items: [line({ id: 'l1', name: 'Toner', quantity: 6, unitPrice: 18, accountId: null }), line({ id: 'l2', name: 'Drum', quantity: 2, unitPrice: 41 })],
      }, w.vendorId);
      await markSent(doc.id);
      input.id = doc.id;
    }, () => createFromOrder(input.id, 'bill', input.quantities));
  }

  {
    const input: Any = { action: 'setDocumentStatus', status: 'void' };
    await run('voiding an invoice of an order', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'sales_order', { items: [line({ id: 'l1', name: 'Printer', quantity: 5, unitPrice: 125.25 })] });
      await markSent(doc.id);
      other = await createFromOrder(doc.id, 'invoice');
      await markSent(other.id);
      input.id = other.id;
    }, () => setDocumentStatus(input.id, 'void'));
  }

  // ------------------------------------------------------------------ contacts and items

  {
    const input: Any = { action: 'saveClient' };
    await run('a new client numbered, its first contact primary', input, async () => {
      w = await kuwait();
      input.client = createClient(w.companyId, {
        id: 'client-new',
        name: '  Blue Harbour Cafe ',
        nameAr: 'مقهى الميناء الأزرق',
        contacts: [
          { id: 'c1', name: 'Sara', email: 'sara@blueharbour.example', phone: '', role: 'Owner', primary: false },
          { id: 'c2', name: 'Omar', email: '', phone: '', role: '', primary: false },
        ],
        creditLimit: 500,
      } as Any);
    }, () => saveClient(input.client));
  }

  {
    const input: Any = { action: 'saveClient' };
    await run('a new vendor', input, async () => {
      w = await kuwait();
      input.client = createClient(w.companyId, { id: 'vendor-new', name: 'Gulf Cables', isCustomer: false, isVendor: true, email: 'sales@gulfcables.example' } as Any);
    }, () => saveClient(input.client));
  }

  {
    const input: Any = { action: 'saveClient' };
    await run('a client made tax exempt keeps a closed period as posted', input, async () => {
      w = await emirates((c) => {
        c.accounting.lockDate = '2026-09-30';
      });
      const c = await company(w.companyId);
      const client: Any = await db.clients.get(w.clientId);
      const draft = await draftDocument(c, 'invoice', client);
      // Issued before snapshots were kept: no posting.
      await db.documents.put({ ...draft, id: 'old-inv', number: 'INV-2026-0001', status: 'sent', issueDate: '2026-08-01', items: [line({ id: 'l1', name: 'Tiles', unitPrice: 100, taxes: [{ name: 'VAT', rate: 5 }] })] });
      input.client = { ...client, taxExempt: true, phone: '+971 4 000 0000' };
    }, () => saveClient(input.client));
  }

  {
    const input: Any = { action: 'deleteClient' };
    await run('a client with documents is kept', input, async () => {
      w = await kuwait();
      await saved(w, 'invoice', { items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      input.id = w.clientId;
    }, () => deleteClient(input.id));
  }

  {
    const input: Any = { action: 'deleteClient' };
    await run('a vendor without records deleted', input, async () => {
      w = await kuwait();
      input.id = w.vendorId;
    }, () => deleteClient(input.id));
  }

  for (const hold of [true, false]) {
    const input: Any = { action: 'setCreditHold', hold };
    await run(hold ? 'a client put on credit hold' : 'a credit hold lifted', input, async () => {
      w = await kuwait(undefined, hold ? {} : { creditHold: true });
      input.id = w.clientId;
    }, () => setCreditHold(input.id, hold));
  }

  {
    const input: Any = { action: 'setCreditHold', hold: true };
    await run('a client already on hold stays as it is', input, async () => {
      w = await kuwait(undefined, { creditHold: true });
      input.id = w.clientId;
    }, () => setCreditHold(input.id, true));
  }

  {
    const input: Any = { action: 'saveProduct' };
    await run('a product saved', input, async () => {
      w = await kuwait();
      input.product = createProduct(w.companyId, { id: 'prod-new', name: ' Annual support ', unitPrice: 240, unit: 'year', taxRateIds: [] });
    }, () => saveProduct(input.product));
  }

  {
    const input: Any = { action: 'saveProduct' };
    await run('a product given another income account keeps closed sales as posted', input, async () => {
      w = await kuwait((c) => {
        c.accounting.lockDate = '2026-09-30';
      });
      const accounts: Any[] = await db.accounts.where('companyId').equals(w.companyId).toArray();
      const income = accounts.filter((a) => a.type === 'income');
      const product = await saveProduct(createProduct(w.companyId, { id: 'prod-1', name: 'Support', unitPrice: 240, incomeAccountId: income[0].id }));
      const c = await company(w.companyId);
      const draft = await draftDocument(c, 'invoice', (await db.clients.get(w.clientId)) ?? null);
      await db.documents.put({ ...draft, id: 'old-inv', number: 'INV-2026-0001', status: 'sent', issueDate: '2026-08-01', items: [line({ id: 'l1', productId: product.id, name: 'Support', unitPrice: 240 })] });
      input.product = { ...product, incomeAccountId: income[1].id };
    }, () => saveProduct(input.product));
  }

  // ------------------------------------------------------------------ more of the web's cases

  {
    const input: Any = { action: 'draftAndSave', type: 'invoice' };
    await run('a yen invoice of a Kuwaiti company: no decimals', input, async () => {
      w = await kuwait();
      input.clientId = w.clientId;
      input.patch = {
        status: 'sent',
        currency: 'JPY',
        exchangeRate: 0.00205,
        discount: 2.5,
        items: [line({ id: 'l1', name: 'Parts', quantity: 7, unitPrice: 1234.5 }), line({ id: 'l2', name: 'Box', quantity: 3, unitPrice: 99.5 })],
      };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(w.clientId);
      await saveDocument({ ...(await draftDocument(c, 'invoice', client ?? null)), ...input.patch });
    });
  }

  {
    const input: Any = { action: 'draftAndSave', type: 'invoice' };
    await run('a tax-exempt client: no tax, and so it posts', input, async () => {
      w = await emirates();
      await db.clients.update(w.clientId, { taxExempt: true } as Any);
      input.clientId = w.clientId;
      input.patch = { status: 'sent', items: [line({ id: 'l1', name: 'Tiles', quantity: 10, unitPrice: 17.99, taxes: [{ name: 'VAT', rate: 5 }] })] };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(w.clientId);
      await saveDocument({ ...(await draftDocument(c, 'invoice', client ?? null)), ...input.patch });
    });
  }

  {
    const input: Any = { action: 'draftAndSave', type: 'quote' };
    await run('tax on the total, from the company’s default rate', input, async () => {
      w = await emirates((c) => {
        c.defaults.documentTaxes = true;
        c.defaults.lineTaxes = false;
      });
      input.clientId = w.clientId;
      input.patch = {
        items: [line({ id: 'l1', name: 'Design', unitPrice: 1500 }), line({ id: 'l2', name: 'Printing', quantity: 250, unitPrice: 0.85 })],
        charges: [{ id: 'ch1', label: 'Delivery', amount: 35, taxes: [] }],
      };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(w.clientId);
      await saveDocument({ ...(await draftDocument(c, 'quote', client ?? null)), ...input.patch });
    });
  }

  {
    const input: Any = { action: 'saveDocument' };
    await run('an issued invoice edited keeps the account it was issued with', input, async () => {
      w = await kuwait();
      const income = (await db.accounts.where('companyId').equals(w.companyId).toArray()).filter((a: Any) => a.type === 'income');
      const product = await saveProduct(createProduct(w.companyId, { id: 'prod-1', name: 'Support', unitPrice: 240, incomeAccountId: income[0].id }));
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', productId: product.id, name: 'Support', unitPrice: 240 })] });
      await saveProduct({ ...product, incomeAccountId: income[1].id });
      const stored: Any = await db.documents.get(doc.id);
      input.document = {
        ...stored,
        items: [{ ...stored.items[0], quantity: 2 }, line({ id: 'l2', productId: product.id, name: 'Support (extra)', unitPrice: 120 })],
      };
    }, () => saveDocument(input.document));
  }

  for (const change of ['the asset line', 'another line']) {
    const input: Any = { action: 'saveDocument' };
    await run(`a bill an asset was made from: ${change} changed`, input, async () => {
      w = await kuwait();
      const equipment: Any = (await db.accounts.where('companyId').equals(w.companyId).toArray()).find((a: Any) => a.code === '1500');
      doc = await saved(w, 'bill', { status: 'sent', items: [line({ id: 'l1', name: 'Forklift', unitPrice: 4500, accountId: equipment.id }), line({ id: 'l2', name: 'Fuel', unitPrice: 20 })] }, w.vendorId);
      await db.assets.put({ id: 'asset-1', companyId: w.companyId, number: 'FA-0001', name: 'Forklift', status: 'active', billId: doc.id, billLineId: 'l1', cost: 4500, createdAt: NOW, updatedAt: NOW } as Any);
      const stored: Any = await db.documents.get(doc.id);
      input.document =
        change === 'the asset line'
          ? { ...stored, items: [{ ...stored.items[0], unitPrice: 4400 }, stored.items[1]] }
          : { ...stored, items: [stored.items[0], { ...stored.items[1], unitPrice: 25 }] };
    }, () => saveDocument(input.document));
  }

  {
    const input: Any = { action: 'setDocumentStatus', status: 'void' };
    await run('a bill an asset was made from is not voided', input, async () => {
      w = await kuwait();
      const equipment: Any = (await db.accounts.where('companyId').equals(w.companyId).toArray()).find((a: Any) => a.code === '1500');
      doc = await saved(w, 'bill', { status: 'sent', items: [line({ id: 'l1', name: 'Forklift', unitPrice: 4500, accountId: equipment.id })] }, w.vendorId);
      await db.assets.put({ id: 'asset-1', companyId: w.companyId, number: 'FA-0001', name: 'Forklift', status: 'active', billId: doc.id, billLineId: 'l1', cost: 4500, createdAt: NOW, updatedAt: NOW } as Any);
      input.id = doc.id;
    }, () => setDocumentStatus(input.id, 'void'));
  }

  {
    const input: Any = { action: 'setDocumentStatus', status: 'sent' };
    await run('a void bill restored', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'bill', { status: 'sent', items: [line({ id: 'l1', name: 'Paper', unitPrice: 12 })] }, w.vendorId);
      await setDocumentStatus(doc.id, 'void');
      input.id = doc.id;
    }, () => setDocumentStatus(input.id, 'sent'));
  }

  {
    const input: Any = { action: 'duplicateDocument', overrides: { vendorReference: '' } };
    await run('a bill duplicated without the vendor’s reference', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'bill', { status: 'sent', vendorReference: 'GP-77', items: [line({ id: 'l1', name: 'Paper', unitPrice: 12 })] }, w.vendorId);
      input.id = doc.id;
    }, () => duplicateDocument(input.id, undefined, input.overrides));
  }

  {
    const input: Any = { action: 'setDocumentStatus', status: 'draft' };
    await run('a delivery note marked as not delivered', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'sales_order', { items: [line({ id: 'l1', name: 'Printer', quantity: 5, unitPrice: 125.25 })] });
      await markSent(doc.id);
      other = await createFromOrder(doc.id, 'delivery_note', { l1: 5 });
      await markDelivered(other.id, { date: '2026-11-27', receiverName: 'Ahmad' });
      input.id = other.id;
    }, () => setDocumentStatus(input.id, 'draft'));
  }

  {
    const input: Any = { action: 'convertDocument', to: 'invoice' };
    await run('an accepted proforma converted to an invoice with its deposit', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'proforma', { deposit: 250, depositDueDate: '2026-12-03', items: [line({ id: 'l1', name: 'Kitchen', unitPrice: 900 })] });
      await markSent(doc.id);
      await setDocumentStatus(doc.id, 'accepted');
      input.id = doc.id;
    }, () => convertDocument(input.id, 'invoice'));
  }

  {
    const input: Any = { action: 'convertDocument', to: 'sales_order' };
    await run('a proforma is not converted to a sales order', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'proforma', { items: [line({ id: 'l1', name: 'Kitchen', unitPrice: 900 })] });
      input.id = doc.id;
    }, () => convertDocument(input.id, 'sales_order' as Any));
  }

  {
    const input: Any = { action: 'createFromOrder', target: 'bill' };
    await run('the rest of a purchase order billed', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'purchase_order', { items: [line({ id: 'l1', name: 'Toner', quantity: 6, unitPrice: 18 }), line({ id: 'l2', name: 'Drum', quantity: 2, unitPrice: 41 })] }, w.vendorId);
      await markSent(doc.id);
      await createFromOrder(doc.id, 'bill', { l1: 4 });
      input.id = doc.id;
    }, () => createFromOrder(input.id, 'bill'));
  }

  {
    const input: Any = { action: 'deleteDocument' };
    await run('released retention keeps the invoice from being deleted', input, async () => {
      w = await kuwait(undefined, { retentionPercent: 5 });
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Works', unitPrice: 1000 })] });
      const stored: Any = await db.documents.get(doc.id);
      await db.documents.put({ ...stored, retentionReleases: [{ id: 'r1', date: '2026-11-27', amount: 50, journalId: 'j1' }] });
      input.id = doc.id;
    }, () => deleteDocument(input.id));
  }

  {
    const input: Any = { action: 'markSent' };
    await run('a credit note marked as sent, applied in part', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      const credit = await saved(w, 'credit', { sourceId: doc.id, items: [line({ id: 'l1', name: 'Return', unitPrice: 30 })] });
      await db.payments.put({
        id: 'app-1', companyId: w.companyId, direction: 'in', clientId: w.clientId, number: 'APP-0001', date: '2026-11-25', amount: 10,
        currency: 'KWD', method: 'credit_note', reference: '', notes: '', allocations: [{ documentId: doc.id, amount: 10 }], documentIds: [doc.id],
        creditId: credit.id, createdAt: NOW, updatedAt: NOW,
      } as Any);
      input.id = credit.id;
    }, () => markSent(input.id));
  }

  {
    const input: Any = { action: 'requestApproval', kind: 'invoice_unvoid', reason: 'Voided by mistake' };
    await run('a restore asked for, and one already waiting', input, async () => {
      w = await kuwait((c) => {
        c.approvalRules = { documentTypes: ['invoice'] };
      });
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      await setDocumentStatus(doc.id, 'void');
      input.link = await link(w, 'admin');
      input.subject = await db.documents.get(doc.id);
      await requestApproval({ kind: 'invoice_unvoid', subject: input.subject, reason: 'First ask' });
    }, () => requestApproval({ kind: 'invoice_unvoid', subject: input.subject, reason: input.reason }), 'admin');
  }

  // ------------------------------------------------------------------ stock items (the inventory's syncDocumentStock)

  for (const type of ['invoice', 'bill']) {
    const input: Any = { action: 'draftAndSave', type, stock: true };
    await run(`an issued ${type} of a stock item moves stock`, input, async () => {
      w = await kuwait();
      const item = await saveItem(createProduct(w.companyId, { id: 'stock-1', name: 'Toner', kind: 'stock', unitPrice: 30, costPrice: 18 } as Any), {
        opening: { warehouseId: '', quantity: 10, unitCost: 18, date: '2026-11-01' },
      });
      input.clientId = type === 'bill' ? w.vendorId : w.clientId;
      input.patch = { status: 'sent', items: [line({ id: 'l1', productId: item.id, name: 'Toner', quantity: 3, unitPrice: type === 'bill' ? 18 : 30 })] };
    }, async () => {
      const c = await company(w.companyId);
      const client = await db.clients.get(input.clientId);
      await saveDocument({ ...(await draftDocument(c, type as Any, client ?? null)), ...input.patch });
    });
  }

  {
    const input: Any = { action: 'setDocumentStatus', status: 'void', stock: true };
    await run('voiding an invoice of a stock item puts the stock back', input, async () => {
      w = await kuwait();
      const item = await saveItem(createProduct(w.companyId, { id: 'stock-1', name: 'Toner', kind: 'stock', unitPrice: 30, costPrice: 18 } as Any), {
        opening: { warehouseId: '', quantity: 10, unitCost: 18, date: '2026-11-01' },
      });
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', productId: item.id, name: 'Toner', quantity: 3, unitPrice: 30 })] });
      input.id = doc.id;
    }, () => setDocumentStatus(input.id, 'void'));
  }

  // ------------------------------------------------------------------ approval requests

  {
    const input: Any = { action: 'requestApproval', kind: 'invoice_edit', reason: ' The client asked for 70. ', byName: 'Sample Admin' };
    await run('an edit of an issued invoice sent for approval', input, async () => {
      w = await kuwait((c) => {
        c.approvalRules = { documentTypes: ['invoice'] };
      });
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      input.link = await link(w, 'admin');
      const stored: Any = await db.documents.get(doc.id);
      input.subject = stored;
      input.proposal = { ...stored, items: [{ ...stored.items[0], unitPrice: 70 }] };
    }, () => requestApproval({ kind: 'invoice_edit', subject: input.subject, proposal: input.proposal, reason: input.reason, byName: input.byName }), 'admin');
  }

  {
    const input: Any = { action: 'requestApproval', kind: 'invoice_void', reason: 'Duplicate of INV-2026-0002' };
    await run('a void asked for', input, async () => {
      w = await kuwait((c) => {
        c.approvalRules = { documentTypes: ['invoice'] };
      });
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      input.link = await link(w, 'staff');
      input.subject = await db.documents.get(doc.id);
    }, () => requestApproval({ kind: 'invoice_void', subject: input.subject, reason: input.reason }), 'staff');
  }

  {
    const input: Any = { action: 'requestApproval', kind: 'invoice_void', reason: '   ' };
    await run('a request needs a reason', input, async () => {
      w = await kuwait();
      doc = await saved(w, 'invoice', { status: 'sent', items: [line({ id: 'l1', name: 'Desk', unitPrice: 80 })] });
      input.subject = await db.documents.get(doc.id);
    }, () => requestApproval({ kind: 'invoice_void', subject: input.subject, reason: input.reason }));
  }

  writeFixtures('documents', out);
  console.log(`${out.length} scenarios, ${out.filter((s) => s.error).length} refused`);
  for (const s of out) if (s.error) console.log(`  ${s.name}: ${s.error}`);
});
