import { beforeEach, describe, expect, it } from 'vitest';
import { db } from './db';
import { createProduct } from './defaults';
import { setupCompany } from './records';
import { loadLedger } from './accounting';
import {
  createWarehouse,
  ensureDefaultWarehouse,
  InventoryError,
  rebuildStock,
  recordStockEntry,
  saveItem,
  saveWarehouse,
} from './inventory';
import {
  applyStockIssueRequest,
  issueRequestProblem,
  issueShortfall,
  issueStock,
  StockIssueError,
  voidStockIssue,
  waitingIssueRequests,
  waitingQuantities,
  warehouseStock,
  type IssueInput,
} from './stock-issues';
import { carryOutDecided, decideApproval } from './approvals';
import type { Company, ID, IssueRecipient, Product, Warehouse } from './types';
import type { MemberRole } from '@/cloud/roles';

/**
 * Items issued to employees from a sub-warehouse (uniforms to security
 * guards), confirmed by an approver. Made-up names and amounts only.
 */

beforeEach(async () => {
  await db.delete();
  await db.open();
});

const GUARD: IssueRecipient = {
  employeeId: 'emp-guard',
  number: 'E-0007',
  name: 'Mohammed Ahmed',
  nameAr: 'محمد أحمد',
  jobTitle: 'Security Guard',
  jobTitleAr: 'حارس أمن',
};

const KEEPER = 'user-keeper';

interface Setup {
  company: Company;
  main: Warehouse;
  store: Warehouse;
  trouser: Product;
  shirt: Product;
}

/** A main warehouse with uniforms, and Ahmed's store with some of them. */
async function setup(): Promise<Setup> {
  const company = await setupCompany({ name: 'Gulf Pearl Security', currency: 'KWD' });
  const main = await ensureDefaultWarehouse(company.id);
  const store = await saveWarehouse(
    createWarehouse(company.id, {
      name: '  Ahmed’s store ',
      parentId: main.id,
      keeper: {
        employeeId: 'emp-ahmed',
        name: ' Ahmed Saleh ',
        jobTitle: 'Warehouse Supervisor',
        userId: KEEPER,
      },
    }),
  );
  const trouser = await saveItem(
    createProduct(company.id, { name: 'Trouser', nameAr: 'بنطلون', kind: 'stock', unit: 'pcs' }),
  );
  const shirt = await saveItem(
    createProduct(company.id, { name: 'T-shirt', nameAr: 'قميص', kind: 'stock', unit: 'pcs' }),
  );
  await recordStockEntry(company.id, {
    kind: 'opening',
    date: '2026-11-01',
    warehouseId: main.id,
    reference: '',
    notes: '',
    lines: [
      { productId: trouser.id, quantity: 20, unitCost: 4 },
      { productId: shirt.id, quantity: 30, unitCost: 2 },
    ],
  });
  await recordStockEntry(company.id, {
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
  return { company, main, store, trouser, shirt };
}

/** This device's person in the company, kept in the cloud. */
async function signedInAs(
  company: Company,
  role: MemberRole,
  options: { userId?: string; approver?: boolean; features?: string[] } = {},
) {
  await db.syncState.put({
    companyId: company.id,
    userId: options.userId ?? `user-${role}`,
    role,
    status: 'ready',
    cursor: 0,
    name: company.name,
    linkedAt: '2026-11-01T08:00:00.000Z',
    lastSyncAt: null,
    lastError: null,
    lastErrorAt: null,
    features: options.features ?? ['tables_v16', 'approvals', 'stock_issues'],
    ...(options.approver ? { approver: true } : {}),
  });
}

function uniforms(s: Setup, trousers = 1, shirts = 1): IssueInput {
  return {
    date: '2026-11-03',
    warehouseId: s.store.id,
    recipient: GUARD,
    lines: [
      { productId: s.trouser.id, quantity: trousers },
      { productId: s.shirt.id, quantity: shirts },
    ],
    notes: 'New joiner',
  };
}

async function stockOf(s: Setup, warehouse: Warehouse, item: Product) {
  return (await warehouseStock(s.company.id, warehouse.id)).get(item.id) ?? 0;
}

async function balanceOf(company: Company, code: string) {
  const { accounts, lines } = await loadLedger((await db.companies.get(company.id))!);
  const account = accounts.find((a) => a.code === code);
  return lines.filter((l) => l.accountId === account?.id).reduce((sum, l) => sum + l.amount, 0);
}

/** An approver's decision, as it goes in a company kept in the cloud. */
async function decided(id: ID, decision: 'approved' | 'rejected') {
  expect(await decideApproval(id, decision)).toBe(false);
  await db.outbox.where('[table+id]').equals(['approvals', id]).delete();
  const request = (await db.approvals.get(id))!;
  await carryOutDecided(request.companyId, [id], async () => false);
}

describe('main warehouse and sub-warehouses', () => {
  it('keeps a sub-warehouse under the main one, with whoever looks after it', async () => {
    const s = await setup();
    expect(s.main.isDefault).toBe(true);
    expect(s.store).toMatchObject({
      name: 'Ahmed’s store',
      parentId: s.main.id,
      isDefault: false,
      keeper: {
        employeeId: 'emp-ahmed',
        name: 'Ahmed Saleh',
        jobTitle: 'Warehouse Supervisor',
        userId: KEEPER,
      },
    });
  });

  it('never makes a sub-warehouse the default, nor a sub-warehouse of a sub-warehouse', async () => {
    const s = await setup();
    await expect(saveWarehouse({ ...s.store, isDefault: true })).rejects.toThrow(InventoryError);
    await expect(
      saveWarehouse(createWarehouse(s.company.id, { name: 'Shelf', parentId: s.store.id })),
    ).rejects.toThrow('can’t have sub-warehouses');
    await expect(saveWarehouse({ ...s.main, parentId: s.store.id })).rejects.toThrow(
      InventoryError,
    );
  });

  it('archives a main warehouse only once its sub-warehouses are archived', async () => {
    const s = await setup();
    const other = await saveWarehouse(createWarehouse(s.company.id, { name: 'Al-Rai store' }));
    const sub = await saveWarehouse(
      createWarehouse(s.company.id, { name: 'Night shift store', parentId: other.id }),
    );
    await expect(saveWarehouse({ ...other, archived: true })).rejects.toThrow(
      'Archive its sub-warehouses',
    );
    await saveWarehouse({ ...sub, archived: true });
    expect((await saveWarehouse({ ...other, archived: true })).archived).toBe(true);
  });

  it('moves stock from the main warehouse to a sub-warehouse with a transfer', async () => {
    const s = await setup();
    expect(await stockOf(s, s.main, s.trouser)).toBe(15);
    expect(await stockOf(s, s.store, s.trouser)).toBe(5);
    expect(await stockOf(s, s.store, s.shirt)).toBe(10);
  });
});

describe('issuing items to an employee', () => {
  it('an approver issues at once: the stock leaves the sub-warehouse and its cost is booked', async () => {
    const s = await setup();
    const { issue, request } = await issueStock(s.company.id, uniforms(s), {
      userId: null,
      name: 'Owner',
    });
    expect(request).toBeNull();
    expect(issue).toMatchObject({
      number: 'ISS-0001',
      status: 'posted',
      warehouseId: s.store.id,
      recipient: GUARD,
      lines: [
        { productId: s.trouser.id, name: 'Trouser', nameAr: 'بنطلون', quantity: 1 },
        { productId: s.shirt.id, name: 'T-shirt', quantity: 1 },
      ],
    });
    expect(await stockOf(s, s.store, s.trouser)).toBe(4);
    expect(await stockOf(s, s.store, s.shirt)).toBe(9);
    expect(await stockOf(s, s.main, s.trouser)).toBe(15);
    // One trouser at 4.000 and one T-shirt at 2.000, as an expense.
    expect(await balanceOf(s.company, '6240')).toBe(6000);
    expect(await balanceOf(s.company, '1200')).toBe(20 * 4000 + 30 * 2000 - 6000);
    const second = await issueStock(s.company.id, uniforms(s, 2, 0), {
      userId: null,
      name: 'Owner',
    });
    expect(second.issue?.number).toBe('ISS-0002');
  });

  it('issues no more than the warehouse holds', async () => {
    const s = await setup();
    await expect(
      issueStock(s.company.id, uniforms(s, 6), { userId: null, name: 'Owner' }),
    ).rejects.toThrow(StockIssueError);
    expect(await stockOf(s, s.store, s.trouser)).toBe(5);
    expect(await db.stockIssues.count()).toBe(0);
  });

  it('asks for an employee and at least one item', async () => {
    const s = await setup();
    const owner = { userId: null, name: 'Owner' };
    await expect(
      issueStock(s.company.id, { ...uniforms(s), recipient: { ...GUARD, employeeId: '' } }, owner),
    ).rejects.toThrow('Choose the employee');
    await expect(issueStock(s.company.id, { ...uniforms(s), lines: [] }, owner)).rejects.toThrow(
      'at least one item',
    );
  });

  it('voiding an issue brings its stock back and takes its cost out of the books', async () => {
    const s = await setup();
    const { issue } = await issueStock(s.company.id, uniforms(s), { userId: null, name: 'Owner' });
    await voidStockIssue(issue!.id);
    expect((await db.stockIssues.get(issue!.id))?.status).toBe('void');
    expect(await stockOf(s, s.store, s.trouser)).toBe(5);
    expect(await balanceOf(s.company, '6240')).toBe(0);
  });

  it('rebuilding the stock keeps what was issued', async () => {
    const s = await setup();
    await issueStock(s.company.id, uniforms(s, 2), { userId: null, name: 'Owner' });
    await rebuildStock(s.company.id);
    expect(await stockOf(s, s.store, s.trouser)).toBe(3);
  });
});

describe('the keeper of a sub-warehouse, and the approver', () => {
  it('sends an issue for approval: nothing leaves the store until it is confirmed', async () => {
    const s = await setup();
    await signedInAs(s.company, 'staff', { userId: KEEPER });
    const { issue, request } = await issueStock(s.company.id, uniforms(s), {
      userId: KEEPER,
      name: 'Ahmed Saleh (Warehouse Supervisor)',
    });
    expect(issue).toBeNull();
    expect(request).toMatchObject({
      kind: 'stock_issue',
      subjectTbl: 'stockIssues',
      subjectNumber: '',
      status: 'pending',
      requestedBy: KEEPER,
      requestedByName: 'Ahmed Saleh (Warehouse Supervisor)',
      after: { warehouseId: s.store.id, recipient: GUARD, issuedBy: KEEPER },
    });
    expect(await stockOf(s, s.store, s.trouser)).toBe(5);
    expect(await db.stockIssues.count()).toBe(0);

    // What waits can't be issued twice.
    const waiting = waitingQuantities(await waitingIssueRequests(s.company.id));
    expect(waiting.get(`${s.store.id}|${s.trouser.id}`)).toBe(1);
    await expect(
      issueStock(s.company.id, uniforms(s, 5, 0), { userId: KEEPER, name: 'Ahmed' }),
    ).rejects.toThrow('Only 4 of Trouser left');

    // The owner confirms it on their device.
    await signedInAs(s.company, 'owner');
    expect(await issueShortfall(request!)).toBeNull();
    await decided(request!.id, 'approved');
    const kept = await db.stockIssues.get(request!.subjectId);
    expect(kept).toMatchObject({
      number: 'ISS-0001',
      status: 'posted',
      issuedBy: KEEPER,
      issuedByName: 'Ahmed Saleh (Warehouse Supervisor)',
      requestId: request!.id,
      approvedBy: 'user-owner',
    });
    expect(await db.approvals.get(request!.id)).toMatchObject({
      status: 'applied',
      resultId: request!.subjectId,
    });
    expect(await stockOf(s, s.store, s.trouser)).toBe(4);
    expect(await stockOf(s, s.store, s.shirt)).toBe(9);

    // Carried out again (another device of an approver): still one issue.
    await applyStockIssueRequest((await db.approvals.get(request!.id))!);
    expect(await db.stockIssues.count()).toBe(1);
    expect(await stockOf(s, s.store, s.trouser)).toBe(4);
  });

  it('holds back what is confirmed and not recorded yet, and checks a request before it is kept', async () => {
    const s = await setup();
    await signedInAs(s.company, 'staff', { userId: KEEPER });
    const { request } = await issueStock(s.company.id, uniforms(s, 4), {
      userId: KEEPER,
      name: 'A',
    });
    // Confirmed, not carried out yet (the approver's device hasn't synced).
    await signedInAs(s.company, 'owner');
    await db.approvals.update(request!.id, { status: 'approved', decidedBy: 'user-owner' });
    await signedInAs(s.company, 'staff', { userId: KEEPER });
    const waiting = waitingQuantities(await waitingIssueRequests(s.company.id));
    expect(waiting.get(`${s.store.id}|${s.trouser.id}`)).toBe(4);
    await expect(
      issueStock(s.company.id, uniforms(s, 2, 0), { userId: KEEPER, name: 'A' }),
    ).rejects.toThrow('Only 1 of Trouser left');

    // A request whose lines don't hold up is not kept.
    await signedInAs(s.company, 'owner');
    const bad = (lines: unknown[]) =>
      ({
        ...request!,
        id: `bad-${lines.length}-${JSON.stringify(lines).length}`,
        subjectId: `issue-${JSON.stringify(lines).length}`,
        status: 'approved',
        after: { ...request!.after, lines },
      }) as typeof request & object;
    const negative = bad([
      { id: 'a', productId: s.trouser.id, name: 'Trouser', unit: 'pcs', quantity: -40 },
    ]);
    expect(await issueRequestProblem(negative)).toBe('Quantities must be positive.');
    await expect(applyStockIssueRequest(negative)).rejects.toThrow(StockIssueError);
    const service = await saveItem(createProduct(s.company.id, { name: 'Delivery' }));
    expect(
      await issueRequestProblem(
        bad([{ id: 'a', productId: service.id, name: 'Jacket', unit: '', quantity: 1 }]),
      ),
    ).toBe('Only stock items can be issued.');
    // Nor one naming items already issued under another request.
    const direct = await issueStock(s.company.id, uniforms(s, 1, 0), {
      userId: 'user-owner',
      name: 'Owner',
    });
    expect(
      await issueRequestProblem({ ...request!, status: 'approved', subjectId: direct.issue!.id }),
    ).toContain('already on record under another request');
    // Each line is named as the item is, not as the request says.
    const renamed = {
      ...request!,
      status: 'approved' as const,
      after: {
        ...request!.after,
        lines: [{ id: 'a', productId: s.trouser.id, name: 'Jacket', unit: 'box', quantity: 1 }],
      },
    };
    await applyStockIssueRequest(renamed);
    expect((await db.stockIssues.get(request!.subjectId))?.lines).toEqual([
      {
        id: 'a',
        productId: s.trouser.id,
        name: 'Trouser',
        nameAr: 'بنطلون',
        unit: 'pcs',
        quantity: 1,
      },
    ]);
    // Recorded, it no longer holds anything back.
    expect(
      waitingQuantities(await waitingIssueRequests(s.company.id)).get(
        `${s.store.id}|${s.trouser.id}`,
      ),
    ).toBeUndefined();
  });

  it('a rejected issue moves nothing', async () => {
    const s = await setup();
    await signedInAs(s.company, 'staff', { userId: KEEPER });
    const { request } = await issueStock(s.company.id, uniforms(s), { userId: KEEPER, name: 'A' });
    await signedInAs(s.company, 'owner');
    await decided(request!.id, 'rejected');
    expect((await db.approvals.get(request!.id))?.status).toBe('rejected');
    expect(await db.stockIssues.count()).toBe(0);
    expect(await stockOf(s, s.store, s.trouser)).toBe(5);
  });

  it('the approver is told when the store no longer holds what was asked', async () => {
    const s = await setup();
    await signedInAs(s.company, 'staff', { userId: KEEPER });
    const { request } = await issueStock(s.company.id, uniforms(s, 5), {
      userId: KEEPER,
      name: 'A',
    });
    await signedInAs(s.company, 'owner');
    // Two trousers go back to the main warehouse meanwhile.
    await recordStockEntry(s.company.id, {
      kind: 'transfer',
      date: '2026-11-03',
      warehouseId: s.store.id,
      toWarehouseId: s.main.id,
      reference: '',
      notes: '',
      lines: [{ productId: s.trouser.id, quantity: 2 }],
    });
    expect(await issueShortfall(request!)).toContain('only 3 of Trouser');
  });

  it('a member issues only from the sub-warehouse they look after', async () => {
    const s = await setup();
    await signedInAs(s.company, 'staff', { userId: 'user-other' });
    await expect(
      issueStock(s.company.id, uniforms(s), { userId: 'user-other', name: 'B' }),
    ).rejects.toThrow('only issue items from the sub-warehouse you look after');
    await signedInAs(s.company, 'staff', { userId: KEEPER });
    await expect(
      issueStock(
        s.company.id,
        { ...uniforms(s), warehouseId: s.main.id },
        {
          userId: KEEPER,
          name: 'A',
        },
      ),
    ).rejects.toThrow('only issue items from the sub-warehouse you look after');
    await signedInAs(s.company, 'viewer', { userId: KEEPER });
    await expect(
      issueStock(s.company.id, uniforms(s), { userId: KEEPER, name: 'A' }),
    ).rejects.toThrow(StockIssueError);
  });

  it('leaves sub-warehouses and their stock to the owner, admins and accountants on this device', async () => {
    const s = await setup();
    await signedInAs(s.company, 'staff', { userId: KEEPER });
    // The keeper renames, moves or re-keeps nothing of the store.
    await expect(saveWarehouse({ ...s.store, name: 'Mine now' })).rejects.toThrow(
      'Only the owner, an admin or an accountant sets up sub-warehouses',
    );
    await expect(
      saveWarehouse(createWarehouse(s.company.id, { name: 'Side store', parentId: s.main.id })),
    ).rejects.toThrow('Only the owner, an admin or an accountant sets up sub-warehouses');
    // Nor moves its stock but by issuing items.
    await expect(
      recordStockEntry(s.company.id, {
        kind: 'adjustment',
        date: '2026-11-04',
        warehouseId: s.store.id,
        reason: 'damaged',
        reference: '',
        notes: '',
        lines: [{ productId: s.trouser.id, quantity: -1 }],
      }),
    ).rejects.toThrow('changes their stock directly');
    expect(await stockOf(s, s.store, s.trouser)).toBe(5);
    // They still keep other warehouses, as staff always have.
    await saveWarehouse(createWarehouse(s.company.id, { name: 'Showroom' }));
    // Items issued are written by approvers only, and never deleted.
    await signedInAs(s.company, 'owner');
    const { issue } = await issueStock(s.company.id, uniforms(s), {
      userId: 'user-owner',
      name: 'Owner',
    });
    await expect(db.stockIssues.delete(issue!.id)).rejects.toThrow(
      'Items issued are voided, never deleted.',
    );
    await signedInAs(s.company, 'accountant');
    await expect(db.stockIssues.put({ ...issue!, notes: 'Changed' })).rejects.toThrow(
      'Only an approver records items issued',
    );
    await saveWarehouse({ ...s.store, name: 'Ahmed’s store (east)' });
  });

  it('waits for the server to have issuing', async () => {
    const s = await setup();
    await signedInAs(s.company, 'owner', { features: ['tables_v16', 'approvals'] });
    await expect(
      issueStock(s.company.id, uniforms(s), { userId: 'user-owner', name: 'Owner' }),
    ).rejects.toThrow('latest database update');
  });
});
