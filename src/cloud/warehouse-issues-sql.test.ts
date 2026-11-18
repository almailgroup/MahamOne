// @vitest-environment node
import { readFileSync } from 'node:fs';
import { beforeAll, describe, expect, it } from 'vitest';
import { MIGRATIONS, startDatabase, type Harness } from './sql-harness';

/**
 * 20261210000000_warehouse_issues.sql: sub-warehouses and who looks after
 * them are set up by the owner, an admin or an accountant, who alone change
 * a sub-warehouse's stock directly; items issued to employees are written by
 * approvers only, and asked for by whoever may issue from the warehouse;
 * they are never deleted; whoever looks after a sub-warehouse reads the
 * current employees' names (nothing else of People); the changes of the
 * team say who receives what. records_guard and the other functions it
 * replaces keep every rule they had. Made-up data only.
 */

const FILE = MIGRATIONS.find((file) => file.endsWith('_warehouse_issues.sql'))!;

let h: Harness;
let seq = 0;

beforeAll(async () => {
  // Each file twice, this one after every earlier one: running it again must be safe.
  h = await startDatabase(2);
}, 120_000);

const json = (value: unknown) => JSON.stringify(value);
type Change = { tbl: string; id: string; data?: unknown; deleted?: boolean };

/** A company with an owner, an admin, an accountant allowed to approve, two staff and a viewer. */
async function team(db: Harness = h) {
  seq += 1;
  const company = `wh-co-${String(seq).padStart(4, '0')}`;
  const tag = `wh-${seq}-${Math.random().toString(36).slice(2, 8)}`;
  const owner = await db.user(`owner-${tag}@example.com`);
  await db.rpc(owner, 'create_company', { p_id: company, p_name: `Company ${seq}` });
  const members: Record<string, string> = {};
  for (const [key, role] of [
    ['admin', 'admin'],
    ['accountant', 'accountant'],
    ['keeper', 'staff'],
    ['staff', 'staff'],
    ['viewer', 'viewer'],
  ]) {
    const email = `${key}-${tag}@example.com`;
    members[key] = await db.user(email);
    const [invite] = await db.rpc<{ token: string }>(owner, 'create_invite', {
      p_company: company,
      p_email: email,
      p_role: role,
    });
    await db.rpc(members[key], 'accept_invite', { p_token: invite.token });
  }
  await db.rpc(owner, 'set_member_permissions', {
    p_company: company,
    p_user: members.accountant,
    p_permissions: json({}),
    p_can_approve: true,
  });
  const { admin, accountant, keeper, staff, viewer } = members;
  await push(
    owner,
    company,
    [
      {
        tbl: 'companies',
        id: company,
        data: { id: company, name: 'Made-up Security', currency: 'KWD' },
      },
      { tbl: 'warehouses', id: 'main', data: warehouse('main', { isDefault: true }) },
      {
        tbl: 'warehouses',
        id: 'store',
        data: warehouse('store', { parentId: 'main', keeper: keeperOf(keeper) }),
      },
      {
        tbl: 'employees',
        id: 'emp-1',
        data: {
          id: 'emp-1',
          number: 'E-0001',
          name: 'Mohammed Ahmed',
          nameAr: 'محمد أحمد',
          jobTitle: 'Security Guard',
          jobTitleAr: 'حارس أمن',
          department: 'Security',
          status: 'active',
          basicSalary: 250,
        },
      },
      {
        tbl: 'employees',
        id: 'emp-2',
        data: { id: 'emp-2', number: 'E-0002', name: 'Left Already', status: 'left' },
      },
    ],
    db,
  );
  return { company, owner, admin, accountant, keeper, staff, viewer };
}

function push(user: string, company: string, changes: Change[], db: Harness = h) {
  // Every record names its company.
  const owned = changes.map((c) =>
    c.data ? { ...c, data: { companyId: company, ...(c.data as object) } } : c,
  );
  return db.rpc<{ tbl: string; id: string; rev: number }>(user, 'push_records', {
    p_company: company,
    p_changes: json(owned),
  });
}

async function stored(company: string, tbl: string, id: string, db: Harness = h) {
  const [row] = await db.admin<{ data: Record<string, unknown> }>(
    `select data from public.records where company_id = $1 and tbl = $2 and id = $3`,
    [company, tbl, id],
  );
  return row?.data;
}

const keeperOf = (userId: string) => ({
  employeeId: 'emp-9',
  name: 'Ahmed Saleh',
  jobTitle: 'Warehouse Supervisor',
  userId,
});

const warehouse = (id: string, extra: Record<string, unknown> = {}) => ({
  id,
  name: `Warehouse ${id}`,
  address: '',
  isDefault: false,
  archived: false,
  ...extra,
});

const entry = (id: string, from: string, to: string | null, kind = 'transfer') => ({
  id,
  kind,
  number: 'TRF-0001',
  date: '2026-11-02',
  warehouseId: from,
  toWarehouseId: to,
  lines: [{ id: 'l1', productId: 'trouser', quantity: 2 }],
  status: 'posted',
});

const issue = (id: string, warehouseId = 'store') => ({
  id,
  number: '',
  date: '2026-11-03',
  warehouseId,
  recipient: {
    employeeId: 'emp-1',
    number: 'E-0001',
    name: 'Mohammed Ahmed',
    nameAr: 'محمد أحمد',
    jobTitle: 'Security Guard',
  },
  issuedBy: null,
  issuedByName: 'Ahmed Saleh (Warehouse Supervisor)',
  lines: [
    { id: 'a', productId: 'trouser', name: 'Trouser', nameAr: 'بنطلون', unit: 'pcs', quantity: 1 },
    { id: 'b', productId: 'shirt', name: 'T-shirt', unit: 'pcs', quantity: 2 },
  ],
  notes: '',
  status: 'posted',
});

const request = (id: string, warehouseId = 'store') => ({
  id,
  kind: 'stock_issue',
  subjectTbl: 'stockIssues',
  subjectId: `issue-${id}`,
  subjectNumber: '',
  before: null,
  after: issue(`issue-${id}`, warehouseId),
  reason: '',
  status: 'pending',
  requestedBy: 'someone-else',
  requestedByName: 'Ahmed Saleh (Warehouse Supervisor)',
  requestedAt: '2026-11-03T08:00:00.000Z',
  decidedBy: null,
  decidedAt: null,
  decisionNote: '',
});

const invoice = (id: string, warehouseId: string | null, status = 'sent') => ({
  id,
  type: 'invoice',
  number: `INV-${id}`,
  status,
  clientId: '',
  items: [{ id: 'i1', kind: 'item', productId: 'trouser', quantity: 1, unitPrice: 5, warehouseId }],
});

/** A function's definition in a migration file (the last one there). */
function definition(file: string, name: string): string {
  const source = readFileSync(file, 'utf8');
  const found = [
    ...source.matchAll(
      new RegExp(
        String.raw`create or replace function ${name.replace('.', String.raw`\.`)}\([\s\S]*?\$\$;`,
        'g',
      ),
    ),
  ];
  return found.at(-1)![0];
}

/** The latest definition of a function in the files before this one. */
function earlier(name: string): string {
  const files = MIGRATIONS.slice(0, MIGRATIONS.indexOf(FILE)).filter((file) =>
    readFileSync(file, 'utf8').includes(`create or replace function ${name}(`),
  );
  return definition(files.at(-1)!, name);
}

async function features(db: Harness): Promise<string[]> {
  const someone = await db.user(`f-${Math.random().toString(36).slice(2)}@example.com`);
  const [row] = await db.rpc<{ server_features: string[] }>(someone, 'server_features');
  return row.server_features;
}

describe('the file', () => {
  it('stops at once, changing nothing, without the AI assistant file', async () => {
    const early = await startDatabase(1, MIGRATIONS.indexOf(FILE) - 1);
    await expect(early.db.exec(readFileSync(FILE, 'utf8'))).rejects.toThrow(
      /Run 20261208000000_ai_assistant\.sql first, then this file\./,
    );
    const [row] = await early.admin<{ missing: boolean }>(
      `select to_regprocedure('almailbooks.issues_from(text,text)') is null as missing`,
    );
    expect(row.missing).toBe(true);
  }, 60_000);

  it('names stock_issues with everything the earlier files name', async () => {
    const before = await startDatabase(1, MIGRATIONS.indexOf(FILE));
    const names = await features(before);
    expect(names).not.toContain('stock_issues');
    expect(await features(h)).toEqual([...names, 'stock_issues']);
  }, 60_000);

  it('keeps every rule the functions it replaces had, adding only its own', () => {
    const mine = definition(FILE, 'almailbooks.records_guard');
    const added = [
      /\n {2}-- Sub-warehouses, and who looks after them,[\s\S]*?\n {2}-- Nor does anyone else move[\s\S]*?\n {2}end if;\n/,
      /\n {4}-- Items to issue to an employee are asked for[\s\S]*?\n {6}end if;\n {4}end if;/,
    ];
    let rest = mine;
    for (const block of added) {
      const found = block.exec(rest);
      expect(found).not.toBeNull();
      rest = rest.replace(found![0], '');
    }
    rest = rest.replace(", 'warehouses', 'stockEntries', 'stockIssues'\n", '\n');
    rest = rest.replace('\n  v_keeper jsonb;\n  v_name text;', '');
    expect(rest).toBe(earlier('almailbooks.records_guard'));

    const deletes = definition(FILE, 'almailbooks.can_delete_record')
      .replace("('companies', 'approvals', 'stockIssues')", "('companies', 'approvals')")
      .replace(/\n {2}-- A sub-warehouse and its stock entries[\s\S]*?\n {2}end if;/, '')
      .replace(/\n {2}-- The stock movements of items issued[\s\S]*?\n {2}end if;/, '')
      .replace(/\n {2}-- Nor does anyone else delete an invoice[\s\S]*?\n {2}end if;/, '');
    expect(deletes).toBe(earlier('almailbooks.can_delete_record'));

    const details = definition(FILE, 'almailbooks.change_details')
      .replace('\n  v_issue jsonb;', '')
      .replace(/\n {4}-- Items to issue: who receives them[\s\S]*?\n {4}end if;/, '')
      .replace(
        /\n {2}elsif p_tbl = 'stockIssues' then[\s\S]*?almailbooks\.issue_summary\(v_data\);/,
        '',
      );
    expect(details).toBe(earlier('almailbooks.change_details'));
  });
});

describe('sub-warehouses', () => {
  it('are set up by the owner, an admin or an accountant', async () => {
    const t = await team();
    for (const user of [t.owner, t.admin, t.accountant]) {
      const id = `sub-${user.slice(0, 6)}`;
      await push(user, t.company, [
        { tbl: 'warehouses', id, data: warehouse(id, { parentId: 'main' }) },
      ]);
      expect(await stored(t.company, 'warehouses', id)).toMatchObject({ parentId: 'main' });
    }
  });

  it('are not set up or changed by staff, who still manage other warehouses', async () => {
    const t = await team();
    for (const user of [t.keeper, t.staff]) {
      await expect(
        push(user, t.company, [
          { tbl: 'warehouses', id: 'x', data: warehouse('x', { parentId: 'main' }) },
        ]),
      ).rejects.toMatchObject({ code: '42501' });
      await expect(
        push(user, t.company, [
          {
            tbl: 'warehouses',
            id: 'store',
            data: warehouse('store', { parentId: 'main', name: 'Mine' }),
          },
        ]),
      ).rejects.toMatchObject({ code: '42501' });
      // Nor turns one into a plain warehouse, nor names themselves its keeper.
      await expect(
        push(user, t.company, [{ tbl: 'warehouses', id: 'store', data: warehouse('store') }]),
      ).rejects.toMatchObject({ code: '42501' });
      await expect(
        push(user, t.company, [
          {
            tbl: 'warehouses',
            id: 'main',
            data: warehouse('main', { isDefault: true, keeper: keeperOf(user) }),
          },
        ]),
      ).rejects.toMatchObject({ code: '42501' });
    }
    await push(t.staff, t.company, [{ tbl: 'warehouses', id: 'shop', data: warehouse('shop') }]);
    expect(await stored(t.company, 'warehouses', 'shop')).toMatchObject({ name: 'Warehouse shop' });
    await expect(
      push(t.staff, t.company, [{ tbl: 'warehouses', id: 'store', deleted: true }]),
    ).rejects.toThrow();
    expect(await stored(t.company, 'warehouses', 'store')).toBeDefined();
  });

  it('get stock from the main warehouse: staff move none of it directly', async () => {
    const t = await team();
    for (const [id, from, to, kind] of [
      ['e1', 'main', 'store', 'transfer'],
      ['e2', 'store', 'main', 'transfer'],
      ['e3', 'store', null, 'adjustment'],
    ] as const) {
      await expect(
        push(t.keeper, t.company, [{ tbl: 'stockEntries', id, data: entry(id, from, to, kind) }]),
      ).rejects.toMatchObject({ code: '42501' });
    }
    // An entry of other warehouses is theirs to record, as before.
    await push(t.staff, t.company, [{ tbl: 'warehouses', id: 'shop', data: warehouse('shop') }]);
    await push(t.staff, t.company, [
      { tbl: 'stockEntries', id: 'e4', data: entry('e4', 'main', 'shop') },
    ]);
    // The owner, an admin or an accountant moves it, and voids or deletes it.
    await push(t.accountant, t.company, [
      { tbl: 'stockEntries', id: 'e5', data: entry('e5', 'main', 'store') },
    ]);
    await expect(
      push(t.staff, t.company, [
        {
          tbl: 'stockEntries',
          id: 'e5',
          data: { ...entry('e5', 'main', 'store'), status: 'void' },
        },
      ]),
    ).rejects.toMatchObject({ code: '42501' });
    await expect(
      push(t.staff, t.company, [{ tbl: 'stockEntries', id: 'e5', deleted: true }]),
    ).rejects.toThrow();
    await push(t.admin, t.company, [{ tbl: 'stockEntries', id: 'e5', deleted: true }]);
    expect(await stored(t.company, 'stockEntries', 'e5')).toBeUndefined();
  });

  it('nor with an invoice or a bill line', async () => {
    const t = await team();
    await expect(
      push(t.staff, t.company, [{ tbl: 'documents', id: 'd1', data: invoice('d1', 'store') }]),
    ).rejects.toMatchObject({ code: '42501' });
    await push(t.staff, t.company, [{ tbl: 'documents', id: 'd2', data: invoice('d2', 'main') }]);
    await push(t.staff, t.company, [{ tbl: 'documents', id: 'd3', data: invoice('d3', null) }]);
    // A draft of the owner's from the sub-warehouse: staff don't issue it.
    await push(t.owner, t.company, [
      { tbl: 'documents', id: 'd4', data: invoice('d4', 'store', 'draft') },
    ]);
    await expect(
      push(t.staff, t.company, [{ tbl: 'documents', id: 'd4', data: invoice('d4', 'store') }]),
    ).rejects.toMatchObject({ code: '42501' });
    await push(t.accountant, t.company, [
      { tbl: 'documents', id: 'd4', data: invoice('d4', 'store') },
    ]);
    expect(await stored(t.company, 'documents', 'd4')).toMatchObject({ status: 'sent' });
    // Nor deleted by staff; one of the main warehouse is, as before.
    await expect(
      push(t.staff, t.company, [{ tbl: 'documents', id: 'd4', deleted: true }]),
    ).rejects.toThrow();
    expect(await stored(t.company, 'documents', 'd4')).toBeDefined();
    await push(t.staff, t.company, [{ tbl: 'documents', id: 'd2', deleted: true }]);
    expect(await stored(t.company, 'documents', 'd2')).toBeUndefined();
    await push(t.accountant, t.company, [{ tbl: 'documents', id: 'd4', deleted: true }]);
    expect(await stored(t.company, 'documents', 'd4')).toBeUndefined();
  });
});

describe('items issued to employees', () => {
  it('are written by approvers only, and never deleted', async () => {
    const t = await team();
    for (const user of [t.keeper, t.staff, t.admin, t.viewer]) {
      await expect(
        push(user, t.company, [{ tbl: 'stockIssues', id: 'i1', data: issue('i1') }]),
      ).rejects.toThrow();
    }
    await push(t.accountant, t.company, [{ tbl: 'stockIssues', id: 'i1', data: issue('i1') }]);
    await push(t.owner, t.company, [{ tbl: 'stockIssues', id: 'i2', data: issue('i2') }]);
    await push(t.owner, t.company, [
      { tbl: 'stockIssues', id: 'i2', data: { ...issue('i2'), status: 'void' } },
    ]);
    expect(await stored(t.company, 'stockIssues', 'i2')).toMatchObject({ status: 'void' });
    await expect(
      push(t.owner, t.company, [{ tbl: 'stockIssues', id: 'i1', deleted: true }]),
    ).rejects.toThrow();
    expect(await stored(t.company, 'stockIssues', 'i1')).toBeDefined();
  });

  it('are asked for by the keeper of the sub-warehouse, as themselves, and decided by an approver', async () => {
    const t = await team();
    await push(t.keeper, t.company, [{ tbl: 'approvals', id: 'r1', data: request('r1') }]);
    expect(await stored(t.company, 'approvals', 'r1')).toMatchObject({
      status: 'pending',
      requestedBy: t.keeper,
      after: { warehouseId: 'store', issuedBy: t.keeper, recipient: { name: 'Mohammed Ahmed' } },
    });
    // Named as the warehouse's keeper, whatever name the copy gives.
    await push(t.keeper, t.company, [
      {
        tbl: 'approvals',
        id: 'r8',
        data: {
          ...request('r8'),
          requestedByName: 'The Owner',
          after: { ...issue('issue-r8'), issuedByName: 'The Owner' },
        },
      },
    ]);
    expect(await stored(t.company, 'approvals', 'r8')).toMatchObject({
      requestedByName: 'Ahmed Saleh (Warehouse Supervisor)',
      after: { issuedByName: 'Ahmed Saleh (Warehouse Supervisor)' },
    });
    // Not by anyone else, nor from another warehouse.
    await expect(
      push(t.staff, t.company, [{ tbl: 'approvals', id: 'r2', data: request('r2') }]),
    ).rejects.toMatchObject({ code: '42501' });
    await expect(
      push(t.keeper, t.company, [{ tbl: 'approvals', id: 'r3', data: request('r3', 'main') }]),
    ).rejects.toMatchObject({ code: '42501' });
    // The keeper can't confirm their own; the owner does.
    await push(t.keeper, t.company, [
      { tbl: 'approvals', id: 'r1', data: { ...request('r1'), status: 'approved' } },
    ]).catch(() => undefined);
    expect(await stored(t.company, 'approvals', 'r1')).toMatchObject({ status: 'pending' });
    await push(t.owner, t.company, [
      { tbl: 'approvals', id: 'r1', data: { ...request('r1'), status: 'approved' } },
    ]);
    expect(await stored(t.company, 'approvals', 'r1')).toMatchObject({
      status: 'approved',
      decidedBy: t.owner,
      after: { issuedBy: t.keeper },
    });
    // The owner, an admin or an accountant may ask from any warehouse,
    // named by their account (the app's), not by what the copy says.
    await push(t.admin, t.company, [{ tbl: 'approvals', id: 'r4', data: request('r4', 'main') }]);
    const r4 = await stored(t.company, 'approvals', 'r4');
    expect(r4).toMatchObject({ status: 'pending', requestedBy: t.admin });
    expect(r4).not.toHaveProperty('requestedByName');
    expect(r4?.after).not.toHaveProperty('issuedByName');
  });

  it('keep their stock movements while they stand, whatever an older app deletes', async () => {
    const t = await team();
    const movement = (id: string, sourceId: string, sourceType = 'issue') => ({
      id,
      productId: 'trouser',
      warehouseId: 'store',
      date: '2026-11-03',
      quantity: -1,
      sourceType,
      sourceId,
      lineId: 'a',
    });
    await push(t.owner, t.company, [
      { tbl: 'stockIssues', id: 'i1', data: issue('i1') },
      { tbl: 'stockMovements', id: 'm1', data: movement('m1', 'i1') },
      { tbl: 'stockMovements', id: 'm2', data: movement('m2', 'e1', 'entry') },
    ]);
    for (const user of [t.owner, t.accountant, t.staff]) {
      await expect(
        push(user, t.company, [{ tbl: 'stockMovements', id: 'm1', deleted: true }]),
      ).rejects.toThrow();
    }
    expect(await stored(t.company, 'stockMovements', 'm1')).toBeDefined();
    // Another source's movement goes as before.
    await push(t.staff, t.company, [{ tbl: 'stockMovements', id: 'm2', deleted: true }]);
    expect(await stored(t.company, 'stockMovements', 'm2')).toBeUndefined();
    // Voided, its movements go with it.
    await push(t.owner, t.company, [
      { tbl: 'stockIssues', id: 'i1', data: { ...issue('i1'), status: 'void' } },
      { tbl: 'stockMovements', id: 'm1', deleted: true },
    ]);
    expect(await stored(t.company, 'stockMovements', 'm1')).toBeUndefined();
  });

  it('a keeper no longer asks once the sub-warehouse is archived or someone else keeps it', async () => {
    const t = await team();
    await push(t.owner, t.company, [
      {
        tbl: 'warehouses',
        id: 'store',
        data: warehouse('store', { parentId: 'main', keeper: keeperOf(t.staff) }),
      },
    ]);
    await expect(
      push(t.keeper, t.company, [{ tbl: 'approvals', id: 'r5', data: request('r5') }]),
    ).rejects.toMatchObject({ code: '42501' });
    await push(t.staff, t.company, [{ tbl: 'approvals', id: 'r6', data: request('r6') }]);
    await push(t.owner, t.company, [
      {
        tbl: 'warehouses',
        id: 'store',
        data: warehouse('store', { parentId: 'main', keeper: keeperOf(t.staff), archived: true }),
      },
    ]);
    await expect(
      push(t.staff, t.company, [{ tbl: 'approvals', id: 'r7', data: request('r7') }]),
    ).rejects.toMatchObject({ code: '42501' });
  });
});

describe('who items can be issued to', () => {
  it('the keeper reads current employees’ names and titles, nothing else', async () => {
    const t = await team();
    const rows = await h.rpc<Record<string, unknown>>(t.keeper, 'stock_issue_recipients', {
      p_company: t.company,
    });
    expect(rows).toEqual([
      {
        id: 'emp-1',
        number: 'E-0001',
        name: 'Mohammed Ahmed',
        name_ar: 'محمد أحمد',
        job_title: 'Security Guard',
        job_title_ar: 'حارس أمن',
        department: 'Security',
      },
    ]);
    // The owner, an admin and an accountant too.
    for (const user of [t.owner, t.admin, t.accountant]) {
      expect(await h.rpc(user, 'stock_issue_recipients', { p_company: t.company })).toHaveLength(1);
    }
  });

  it('nobody else', async () => {
    const t = await team();
    for (const user of [t.staff, t.viewer, await h.user(`out-${seq}@example.com`)]) {
      await expect(
        h.rpc(user, 'stock_issue_recipients', { p_company: t.company }),
      ).rejects.toMatchObject({ code: '42501' });
    }
    // Nor a keeper made a viewer since.
    await h.admin(
      `update public.company_members set role = 'viewer' where company_id = $1 and user_id = $2`,
      [t.company, t.keeper],
    );
    await expect(
      h.rpc(t.keeper, 'stock_issue_recipients', { p_company: t.company }),
    ).rejects.toMatchObject({ code: '42501' });
  });
});

describe('the changes of the team', () => {
  it('say who receives items asked for, and what', async () => {
    const [row] = await h.admin<{ details: Record<string, unknown> }>(
      `select almailbooks.change_details('c', 'approvals', null, $1::jsonb, false) as details`,
      [json(request('r1'))],
    );
    expect(row.details).toEqual({
      important: true,
      summary: {
        what: 'requested',
        request: 'stock_issue',
        subject: 'stockIssues',
        number: '',
        status: 'pending',
        name: 'Mohammed Ahmed',
        nameAr: 'محمد أحمد',
        jobTitle: 'Security Guard',
        items: [
          { quantity: 1, name: 'Trouser', nameAr: 'بنطلون' },
          { quantity: 2, name: 'T-shirt' },
        ],
      },
    });
    const [kept] = await h.admin<{ details: Record<string, unknown> }>(
      `select almailbooks.change_details('c', 'stockIssues', null, $1::jsonb, false) as details`,
      [json({ ...issue('i1'), number: 'ISS-0001' })],
    );
    expect(kept.details).toMatchObject({
      important: false,
      summary: { what: 'added', number: 'ISS-0001', name: 'Mohammed Ahmed' },
    });
  });
});
