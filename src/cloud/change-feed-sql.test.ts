// @vitest-environment node
import { beforeAll, describe, expect, it } from 'vitest';
import { MIGRATIONS, startDatabase, type Harness } from './sql-harness';
import { changeDetails, changeKind } from './change-feed';
import type { MemberRole } from './roles';
import { FakeCloud } from './testing/fake-cloud';

/**
 * 20261123000000_change_feed.sql: the server records who changed what for
 * the owner (the Super Admin) and the members allowed to approve, once one
 * of them asks for it. It must never stop a sync, and nobody else sees it.
 * pg_net is a stand-in here that records the requests it would send.
 */

const FILE = MIGRATIONS.find((file) => file.endsWith('_change_feed.sql'))!;

let h: Harness;
let seq = 0;

const NET_STUB = `
  create schema if not exists net;
  create table if not exists net.sent (url text, body jsonb, headers jsonb, timeout_ms integer);
  create or replace function net.http_post(
    url text,
    body jsonb default '{}'::jsonb,
    params jsonb default '{}'::jsonb,
    headers jsonb default '{}'::jsonb,
    timeout_milliseconds integer default 5000
  ) returns bigint language sql as $$
    insert into net.sent values (url, body, headers, timeout_milliseconds) returning 1::bigint
  $$;
`;

beforeAll(async () => {
  // Each file twice: running a script again must be safe.
  h = await startDatabase(2);
  await h.db.exec(NET_STUB);
}, 60_000);

const json = (value: unknown) => JSON.stringify(value);

/** A fresh company with an owner, and members in every other role. */
async function team(db: Harness = h) {
  seq += 1;
  const company = `feed-co-${String(seq).padStart(4, '0')}`;
  const tag = `feed-${seq}-${Math.random().toString(36).slice(2, 8)}`;
  const owner = await db.user(`owner-${tag}@example.com`, { name: 'Made-up Owner' });
  const outsider = await db.user(`outsider-${tag}@example.com`);
  await db.rpc(owner, 'create_company', { p_id: company, p_name: `Company ${seq}` });
  const members: Record<string, string> = {};
  for (const role of ['admin', 'accountant', 'staff', 'viewer']) {
    const email = `${role}-${tag}@example.com`;
    members[role] = await db.user(email, { name: `Made-up ${role}` });
    const [invite] = await db.rpc<{ token: string }>(owner, 'create_invite', {
      p_company: company,
      p_email: email,
      p_role: role,
    });
    await db.rpc(members[role], 'accept_invite', { p_token: invite.token });
  }
  const { admin, accountant, staff, viewer } = members;
  return { company, owner, admin, accountant, staff, viewer, outsider };
}

type Team = Awaited<ReturnType<typeof team>>;
type Change = { tbl: string; id: string; data?: unknown; deleted?: boolean };

function push(user: string, company: string, changes: Change[], db: Harness = h) {
  return db.rpc<{ tbl: string; id: string; rev: number; conflict: boolean }>(user, 'push_records', {
    p_company: company,
    p_changes: json(changes),
  });
}

const rec = (company: string, id: string, extra: Record<string, unknown> = {}) => ({
  id,
  companyId: company,
  ...extra,
});

const put = (tbl: string, data: { id: string } & Record<string, unknown>): Change => ({
  tbl,
  id: data.id,
  data,
});

const invoice = (company: string, id: string, extra: Record<string, unknown> = {}) =>
  rec(company, id, {
    type: 'invoice',
    number: id.toUpperCase(),
    status: 'sent',
    clientId: 'client-1',
    issueDate: '2026-10-01',
    currency: 'KWD',
    items: [{ description: 'Made-up service', quantity: 1, price: 100 }],
    totals: { total: 100, balance: 100 },
    ...extra,
  });

const cheque = (company: string, id: string, extra: Record<string, unknown> = {}) =>
  rec(company, id, {
    direction: 'out',
    clientId: 'client-1',
    number: id.toUpperCase(),
    method: 'cheque',
    amount: 250,
    currency: 'KWD',
    date: '2026-10-05',
    cheque: { number: '100200', bank: 'NBOK', date: '2026-10-20', status: 'held' },
    ...extra,
  });

function turnOn(
  user: string,
  company: string,
  options: { enabled?: boolean; kinds?: string[]; digest?: string; url?: string } = {},
  db: Harness = h,
) {
  return db.rpc<{ enabled: boolean; immediate_kinds: string[]; digest: string }>(
    user,
    'set_change_notifications',
    {
      p_company: company,
      p_enabled: options.enabled ?? true,
      p_immediate_kinds: options.kinds ?? [
        'document',
        'cheque',
        'approval',
        'member',
        'settings',
        'people',
      ],
      p_digest: options.digest ?? 'daily',
      p_app_url: options.url ?? 'https://app.example.com/',
    },
  );
}

interface Event {
  id: number;
  actor: string | null;
  op: string;
  tbl: string;
  record_id: string;
  kind: string;
  important: boolean;
  private: boolean;
  count: number;
  summary: Record<string, unknown>;
}

/** The company's changes as stored (not the team changes unless asked). */
async function events(company: string, members = false, db: Harness = h): Promise<Event[]> {
  return db.admin<Event>(
    `select id, actor, op, tbl, record_id, kind, important, private, count, summary
       from public.change_events
      where company_id = $1 and ($2 or kind <> 'member')
      order by id`,
    [company, members],
  );
}

interface FeedRow extends Event {
  actor_name: string;
  subject_name: string;
  unread: boolean;
}

/** The changes of the records only, without the team's (every test team has joins). */
async function feed(
  user: string,
  company: string,
  options: { after?: number; before?: number; limit?: number; members?: boolean } = {},
) {
  const rows = await h.rpc<FeedRow>(user, 'notification_feed', {
    p_company: company,
    p_after: options.after ?? 0,
    p_before: options.before ?? null,
    p_limit: options.limit ?? 50,
  });
  return options.members ? rows : rows.filter((r) => r.kind !== 'member');
}

function approve(t: Team, user: string, canApprove = true) {
  return h.rpc(t.owner, 'set_member_permissions', {
    p_company: t.company,
    p_user: user,
    p_permissions: json({}),
    p_can_approve: canApprove,
  });
}

/* -------------------------------------------------------------------------- */

describe('with nobody asking for the changes', () => {
  it('records nothing about the records and answers every push as before', async () => {
    const before = await startDatabase(1, MIGRATIONS.indexOf(FILE));
    const results: unknown[][] = [];
    const stored: unknown[][] = [];
    for (const db of [before, h]) {
      const t = await team(db);
      const c = t.company;
      const batches: [string, Change[]][] = [
        [
          t.staff,
          [
            put('clients', rec(c, 'client-1', { name: 'Made-up Client' })),
            put('documents', invoice(c, 'inv-1')),
            put('payments', cheque(c, 'pay-1')),
            put('activities', rec(c, 'act-1', { entity: 'invoice', message: 'Invoice sent' })),
          ],
        ],
        // An older app sends the same again, and changes one.
        [
          t.staff,
          [
            put('documents', invoice(c, 'inv-1', { notes: 'Changed on an older version' })),
            put('payments', cheque(c, 'pay-1')),
          ],
        ],
        [t.admin, [put('employees', rec(c, 'emp-1', { name: 'Made-up Person', salary: 900 }))]],
        [t.owner, [{ tbl: 'payments', id: 'pay-1', deleted: true }]],
      ];
      const answers: unknown[] = [];
      for (const [user, changes] of batches) {
        const rows = await push(user, c, changes, db);
        answers.push(rows.map((r) => [r.tbl, r.id, r.conflict]));
      }
      results.push(answers);
      stored.push(
        await db.admin(
          `select tbl, id, data from public.records where company_id = $1 order by tbl, id`,
          [c],
        ),
      );
      if (db === h) expect(await events(c)).toEqual([]);
    }
    expect(results[1]).toEqual(results[0]);
    expect(stored[1].map((r) => ({ ...(r as object), data: undefined }))).toEqual(
      stored[0].map((r) => ({ ...(r as object), data: undefined })),
    );
  }, 60_000);

  it('keeps the bell off for everyone', async () => {
    const t = await team();
    for (const user of [t.owner, t.admin, t.accountant, t.staff, t.viewer]) {
      const [status] = await h.rpc<{ enabled: boolean; unread: number }>(
        user,
        'notification_status',
        { p_company: t.company },
      );
      expect(status).toMatchObject({ enabled: false });
    }
    await expect(
      h.rpc(t.outsider, 'notification_status', { p_company: t.company }),
    ).rejects.toThrow(/almail:not_member/);
  });
});

describe('who may ask for the changes', () => {
  it('is the owner and the members the owner allowed to approve', async () => {
    const t = await team();
    const c = t.company;
    for (const user of [t.admin, t.accountant, t.staff, t.viewer, t.outsider]) {
      await expect(turnOn(user, c)).rejects.toMatchObject({ code: '42501' });
      await expect(
        h.rpc(user, 'change_notification_settings', { p_company: c }),
      ).rejects.toMatchObject({ code: '42501' });
      await expect(feed(user, c)).rejects.toMatchObject({ code: '42501' });
      await expect(
        h.rpc(user, 'mark_notifications_read', { p_company: c, p_upto: 1 }),
      ).rejects.toMatchObject({ code: '42501' });
    }
    const [saved] = await turnOn(t.owner, c, { kinds: ['cheque', 'document', 'cheque'] });
    expect(saved).toMatchObject({ enabled: true, immediate_kinds: ['document', 'cheque'] });
    await approve(t, t.accountant);
    const [deputy] = await turnOn(t.accountant, c, { digest: 'off' });
    expect(deputy).toMatchObject({ enabled: true, digest: 'off' });
  });

  it('starts with the defaults, and checks what is saved', async () => {
    const t = await team();
    const c = t.company;
    const [first] = await h.rpc(t.owner, 'change_notification_settings', { p_company: c });
    expect(first).toMatchObject({
      enabled: false,
      immediate_kinds: ['document', 'cheque', 'approval', 'member', 'settings', 'people'],
      digest: 'daily',
      last_error: '',
    });
    await expect(turnOn(t.owner, c, { kinds: ['salaries'] })).rejects.toThrow(/almail:invalid/);
    await expect(turnOn(t.owner, c, { digest: 'hourly' })).rejects.toThrow(/almail:invalid/);
    await turnOn(t.owner, c, { url: 'javascript:alert(1)' });
    const [row] = await h.admin<{ app_url: string }>(
      'select app_url from public.notification_settings where company_id = $1',
      [c],
    );
    expect(row.app_url).toBe('');
    // Nobody reaches the tables but through the functions.
    for (const table of ['change_events', 'notification_settings', 'notification_reads']) {
      await expect(h.as(t.owner, (q) => q(`select * from public.${table}`))).rejects.toThrow(
        /permission denied/,
      );
    }
  });

  it('stops for whoever is no longer an approver, and goes with whoever leaves', async () => {
    const t = await team();
    const c = t.company;
    await approve(t, t.admin);
    await turnOn(t.admin, c);
    await approve(t, t.admin, false);
    const [off] = await h.admin<{ enabled: boolean }>(
      'select enabled from public.notification_settings where company_id = $1 and user_id = $2',
      [c, t.admin],
    );
    expect(off.enabled).toBe(false);
    await approve(t, t.accountant);
    await turnOn(t.accountant, c);
    await h.rpc(t.accountant, 'mark_notifications_read', { p_company: c, p_upto: 0 });
    await h.rpc(t.owner, 'remove_member', { p_company: c, p_user: t.accountant });
    const left = await h.admin(
      `select 1 from public.notification_settings where company_id = $1 and user_id = $2
       union all
       select 1 from public.notification_reads where company_id = $1 and user_id = $2`,
      [c, t.accountant],
    );
    expect(left).toEqual([]);
  });
});

describe('what is recorded once someone asks', () => {
  it('names who made each change, and leaves out what changed nothing', async () => {
    const t = await team();
    const c = t.company;
    await turnOn(t.owner, c);
    await push(t.staff, c, [
      put('clients', rec(c, 'client-1', { name: 'Made-up Client', nameAr: 'عميل' })),
    ]);
    await push(t.admin, c, [put('documents', invoice(c, 'inv-1'))]);
    // The same again (a device that lost the answer), and the activity log.
    await push(t.admin, c, [put('documents', invoice(c, 'inv-1'))]);
    await push(t.staff, c, [put('activities', rec(c, 'act-1', { entity: 'invoice' }))]);
    const found = await events(c);
    expect(found.map((e) => [e.actor, e.tbl, e.op, e.kind, e.count])).toEqual([
      [t.staff, 'clients', 'insert', 'contact', 1],
      [t.admin, 'documents', 'insert', 'document', 1],
    ]);
    expect(found[0].summary).toEqual({ what: 'added', name: 'Made-up Client', nameAr: 'عميل' });
    expect(found[1].summary).toMatchObject({
      what: 'added',
      type: 'invoice',
      number: 'INV-1',
      total: 100,
      client: 'Made-up Client',
    });
    // The SQL editor and the server's own jobs are nobody.
    await h.admin(
      `update public.records set data = data || '{"notes": "By the server"}'
        where company_id = $1 and tbl = 'documents'`,
      [c],
    );
    expect(await events(c)).toHaveLength(2);
  });

  it('folds a sync of ordinary changes into one row per kind of record and person', async () => {
    const t = await team();
    const c = t.company;
    await turnOn(t.owner, c);
    const clients = Array.from({ length: 200 }, (_, i) =>
      put('clients', rec(c, `client-${i}`, { name: `Made-up Client ${i}` })),
    );
    await push(t.staff, c, clients);
    let found = await events(c);
    expect(found).toHaveLength(1);
    expect(found[0]).toMatchObject({ tbl: 'clients', op: 'insert', count: 200, important: false });

    // The most a push may carry: 500 changes of three kinds, upserts and deletes.
    const big: Change[] = [
      ...clients.slice(0, 150).map((change) => ({
        ...change,
        data: { ...(change.data as object), phone: '+000 0000 0000' },
      })),
      ...clients
        .slice(150, 200)
        .map((change) => ({ tbl: change.tbl, id: change.id, deleted: true })),
      ...Array.from({ length: 200 }, (_, i) =>
        put('products', rec(c, `item-${i}`, { name: `Made-up Item ${i}` })),
      ),
      ...Array.from({ length: 100 }, (_, i) =>
        put('documents', rec(c, `q-${i}`, { type: 'quote', number: `Q-${i}`, status: 'draft' })),
      ),
    ];
    expect(big).toHaveLength(500);
    await push(t.staff, c, big);
    found = (await events(c)).slice(1);
    expect(found.map((e) => [e.tbl, e.op, e.count])).toEqual([
      ['clients', 'mixed', 200],
      ['products', 'insert', 200],
      ['documents', 'insert', 100],
    ]);
    // Another person's changes in the same table are theirs.
    await push(t.admin, c, [put('clients', rec(c, 'client-0', { name: 'Renamed' }))]);
    expect((await events(c)).at(-1)).toMatchObject({ actor: t.admin, count: 1, op: 'update' });
  }, 60_000);

  it('keeps each important change on its own', async () => {
    const t = await team();
    const c = t.company;
    await turnOn(t.owner, c);
    const returned = { number: '100200', bank: 'NBOK', date: '2026-10-20', status: 'returned' };
    await push(t.owner, c, [
      put('clients', rec(c, 'client-1', { name: 'Made-up Vendor' })),
      put('documents', invoice(c, 'inv-1')),
      put('documents', invoice(c, 'inv-2')),
      put('documents', invoice(c, 'draft-1', { status: 'draft' })),
      put('payments', cheque(c, 'pay-1')),
      put('payRuns', rec(c, 'run-1', { period: '2026-10', status: 'draft', lines: [] })),
    ]);
    const more = [{ description: 'More', quantity: 1, price: 200 }];
    await push(t.staff, c, [
      // Edited after it was issued, voided, a draft deleted, a payment against it.
      put('documents', invoice(c, 'inv-1', { items: more })),
      put('documents', invoice(c, 'inv-2', { status: 'void' })),
      { tbl: 'documents', id: 'draft-1', deleted: true },
      put('documents', invoice(c, 'inv-1', { items: more, status: 'partial' })),
      // A cheque returned, a cash payment.
      put('payments', cheque(c, 'pay-1', { cheque: returned, voided: true })),
      put('payments', rec(c, 'pay-2', { method: 'cash', amount: 5, clientId: 'client-1' })),
      put(
        'approvals',
        rec(c, 'apr-1', {
          kind: 'invoice_edit',
          subjectTbl: 'documents',
          subjectId: 'inv-1',
          subjectNumber: 'INV-1',
          status: 'pending',
        }),
      ),
    ]);
    await push(t.admin, c, [
      put('payRuns', rec(c, 'run-1', { period: '2026-10', status: 'approved', lines: [] })),
    ]);
    const found = (await events(c)).filter((e) => e.actor !== t.owner);
    expect(
      found.map((e) => [e.tbl, e.op, String(e.summary.what), e.important, e.count, e.private]),
    ).toEqual([
      ['documents', 'update', 'edited', true, 1, false],
      ['documents', 'update', 'voided', true, 1, false],
      // The draft went and a payment changed the invoice's status: ordinary.
      ['documents', 'mixed', 'updated', false, 2, false],
      ['payments', 'update', 'returned', true, 1, false],
      ['payments', 'insert', 'added', false, 1, false],
      ['approvals', 'insert', 'requested', true, 1, false],
      ['payRuns', 'update', 'approved', true, 1, true],
    ]);
    expect(found[1].summary).toMatchObject({ type: 'invoice', number: 'INV-2', was: 'sent' });
    expect(found[3].summary).toMatchObject({
      cheque: '100200',
      amount: 250,
      status: 'returned',
      was: 'held',
      client: 'Made-up Vendor',
    });
    expect(found[3].kind).toBe('cheque');
    expect(found[4].kind).toBe('payment');
    // A pay run says its month and stage, nothing more.
    expect(found[6].summary).toEqual({
      what: 'approved',
      status: 'approved',
      was: 'draft',
      period: '2026-10',
    });
  });

  it('keeps payroll and people data private, without names or amounts', async () => {
    const t = await team();
    const c = t.company;
    await turnOn(t.owner, c);
    await push(t.admin, c, [
      put(
        'employees',
        rec(c, 'emp-1', { name: 'Made-up Person', civilId: '000000000000', salary: 900 }),
      ),
      put(
        'complianceDocuments',
        rec(c, 'doc-1', { title: 'Made-up Passport', employeeId: 'emp-1' }),
      ),
      put('complianceDocuments', rec(c, 'doc-2', { title: 'Commercial licence', type: 'licence' })),
      put('attachments', rec(c, 'file-1', { ownerId: 'emp-1', name: 'civil-id.pdf', dataUrl: '' })),
      put(
        'approvals',
        rec(c, 'apr-pay', {
          kind: 'payroll',
          subjectTbl: 'payRuns',
          subjectId: 'run-1',
          subjectNumber: '2026-10',
          status: 'pending',
        }),
      ),
    ]);
    const found = await events(c);
    expect(found.map((e) => [e.tbl, e.private, e.kind])).toEqual([
      ['employees', true, 'people'],
      ['complianceDocuments', true, 'compliance'],
      ['complianceDocuments', false, 'compliance'],
      ['attachments', true, 'file'],
      ['approvals', true, 'approval'],
    ]);
    const text = JSON.stringify(found.filter((e) => e.private));
    for (const secret of [
      'Made-up Person',
      '000000000000',
      '900',
      'Passport',
      'civil-id',
      '2026-10',
    ]) {
      expect(text).not.toContain(secret);
    }
    expect(found[2].summary).toMatchObject({ name: 'Commercial licence' });
    expect(found[4]).toMatchObject({
      important: true,
      summary: { what: 'requested', request: 'payroll', status: 'pending' },
    });
  });

  it('tells the owner’s settings that matter, and not a document counter moving on', async () => {
    const t = await team();
    const c = t.company;
    const company = (extra: Record<string, unknown> = {}) =>
      put('companies', {
        id: c,
        name: 'Made-up Company',
        numbering: { invoice: { pattern: 'INV-{n}', next: 1, period: '' } },
        accounting: { template: 'kw', lockDate: null },
        ...extra,
      });
    await push(t.owner, c, [company()]);
    await turnOn(t.owner, c);
    // A new invoice moves the counter on: nothing to tell.
    await push(t.staff, c, [
      company({ numbering: { invoice: { pattern: 'INV-{n}', next: 2, period: '' } } }),
    ]);
    expect(await events(c)).toEqual([]);
    await push(t.admin, c, [
      company({
        numbering: { invoice: { pattern: 'INV-{n}', next: 2, period: '' } },
        accounting: { template: 'kw', lockDate: '2026-09-30' },
      }),
    ]);
    await push(t.admin, c, [
      company({
        numbering: { invoice: { pattern: 'S-{n}', next: 2, period: '' } },
        accounting: { template: 'kw', lockDate: '2026-09-30' },
      }),
    ]);
    await push(t.admin, c, [
      company({
        name: 'Made-up Company Renamed',
        numbering: { invoice: { pattern: 'S-{n}', next: 2, period: '' } },
        accounting: { template: 'kw', lockDate: '2026-09-30' },
      }),
    ]);
    const found = await events(c);
    expect(found.map((e) => [e.important, e.summary])).toEqual([
      [true, { what: 'settings', changes: ['lockDate'], lockDate: '2026-09-30' }],
      [true, { what: 'settings', changes: ['numbering'] }],
      [false, { what: 'settings', changes: [] }],
    ]);
  });

  it('tells each decision on an approval request', async () => {
    const t = await team();
    const c = t.company;
    await turnOn(t.owner, c);
    const request = (status: string) =>
      put(
        'approvals',
        rec(c, 'apr-1', {
          kind: 'cheque_create',
          subjectTbl: 'payments',
          subjectId: 'pay-9',
          subjectNumber: '100300',
          status,
        }),
      );
    await push(t.staff, c, [request('pending')]);
    await approve(t, t.accountant);
    await push(t.accountant, c, [request('approved')]);
    await push(t.accountant, c, [request('applied')]);
    const found = await events(c);
    expect(found.map((e) => [e.actor, e.summary.what, e.important])).toEqual([
      [t.staff, 'requested', true],
      [t.accountant, 'approved', true],
      [t.accountant, 'applied', false],
    ]);
    expect(found[0].summary).toEqual({
      what: 'requested',
      request: 'cheque_create',
      subject: 'payments',
      number: '100300',
      status: 'pending',
    });
  });
});

describe('the feed never stops a sync', () => {
  it('stores every change even when the feed refuses them all', async () => {
    const t = await team();
    const c = t.company;
    await turnOn(t.owner, c);
    await h.admin(
      `alter table public.change_events add constraint never_${t.company.replace(/-/g, '_')}
         check (company_id <> '${c}') not valid`,
    );
    try {
      const rows = await push(t.staff, c, [
        put('clients', rec(c, 'client-1', { name: 'Made-up Client' })),
        put('documents', invoice(c, 'inv-1')),
      ]);
      expect(rows).toHaveLength(2);
      await push(t.staff, c, [put('documents', invoice(c, 'inv-1', { status: 'void' }))]);
      await push(t.owner, c, [{ tbl: 'documents', id: 'inv-1', deleted: true }]);
      const stored = await h.admin('select id from public.records where company_id = $1', [c]);
      expect(stored).toEqual([{ id: 'client-1' }]);
      expect(await events(c)).toEqual([]);
    } finally {
      await h.admin(
        `alter table public.change_events drop constraint never_${t.company.replace(/-/g, '_')}`,
      );
    }
  });

  it('lets a company be deleted with its changes', async () => {
    const t = await team();
    const c = t.company;
    await turnOn(t.owner, c);
    await push(t.staff, c, [put('clients', rec(c, 'client-1', { name: 'Made-up Client' }))]);
    await h.rpc(t.owner, 'delete_company', { p_company: c });
    const left = await h.admin(
      `select 1 from public.change_events where company_id = $1
       union all select 1 from public.notification_settings where company_id = $1`,
      [c],
    );
    expect(left).toEqual([]);
  });
});

describe('the feed in the app', () => {
  it('shows the owner the others’ changes, never their own', async () => {
    const t = await team();
    const c = t.company;
    await turnOn(t.owner, c);
    await push(t.owner, c, [put('clients', rec(c, 'client-1', { name: 'By the owner' }))]);
    await push(t.staff, c, [put('clients', rec(c, 'client-2', { name: 'By staff' }))]);
    await push(t.admin, c, [put('documents', invoice(c, 'inv-1', { status: 'void' }))]);
    const rows = await feed(t.owner, c);
    expect(rows.map((r) => [r.actor_name, r.tbl, r.unread])).toEqual([
      ['Made-up admin', 'documents', true],
      ['Made-up staff', 'clients', true],
    ]);
    // A deputy sees the owner's changes too.
    await approve(t, t.admin);
    const deputy = await feed(t.admin, c);
    expect(deputy.map((r) => r.actor_name)).toEqual(['Made-up staff', 'Made-up Owner']);
    // Paging.
    const [newest] = rows;
    expect((await feed(t.owner, c, { before: newest.id })).map((r) => r.tbl)).toEqual(['clients']);
    expect((await feed(t.owner, c, { after: rows[1].id })).map((r) => r.tbl)).toEqual([
      'documents',
    ]);
    expect(await feed(t.owner, c, { limit: 1 })).toHaveLength(1);
  });

  it('counts what is unread and marks it read, never back', async () => {
    const t = await team();
    const c = t.company;
    await turnOn(t.owner, c);
    await push(t.staff, c, [put('clients', rec(c, 'client-1', { name: 'Made-up Client' }))]);
    await push(t.staff, c, [put('documents', invoice(c, 'inv-1'))]);
    const status = async () =>
      (
        await h.rpc<{ enabled: boolean; unread: number; latest: number }>(
          t.owner,
          'notification_status',
          { p_company: c },
        )
      )[0];
    const first = await status();
    expect(first).toMatchObject({ enabled: true, unread: 2 });
    const [newest, older] = await feed(t.owner, c);
    expect(Number(first.latest)).toBe(Number(newest.id));
    await h.rpc(t.owner, 'mark_notifications_read', { p_company: c, p_upto: older.id });
    expect(await status()).toMatchObject({ unread: 1 });
    expect((await feed(t.owner, c)).map((r) => r.unread)).toEqual([true, false]);
    await h.rpc(t.owner, 'mark_notifications_read', { p_company: c, p_upto: 0 });
    expect(await status()).toMatchObject({ unread: 1 });
    // Far ahead is as far as there is.
    await h.rpc(t.owner, 'mark_notifications_read', { p_company: c, p_upto: 9_999_999_999 });
    expect(await status()).toMatchObject({ unread: 0 });
    await push(t.staff, c, [put('documents', invoice(c, 'inv-2'))]);
    expect(await status()).toMatchObject({ unread: 1 });
  });

  it('includes the team changes, naming who was changed', async () => {
    const t = await team();
    const c = t.company;
    await turnOn(t.owner, c);
    await h.rpc(t.admin, 'set_member_role', { p_company: c, p_user: t.staff, p_role: 'viewer' });
    const [change] = await feed(t.owner, c, { limit: 1, members: true });
    expect(change).toMatchObject({
      kind: 'member',
      important: true,
      actor_name: 'Made-up admin',
      subject_name: 'Made-up staff',
      summary: { reason: 'role', role: 'viewer', before: 'staff' },
    });
    expect(JSON.stringify(change)).not.toMatch(/@example\.com/);
  });

  it('shows private changes to approvers only, who are owners, admins or accountants', async () => {
    const t = await team();
    const c = t.company;
    await turnOn(t.owner, c);
    await push(t.admin, c, [put('employees', rec(c, 'emp-1', { name: 'Made-up Person' }))]);
    expect((await feed(t.owner, c)).map((r) => [r.tbl, r.private])).toEqual([['employees', true]]);
    await approve(t, t.accountant);
    expect(await feed(t.accountant, c)).toHaveLength(1);
    for (const user of [t.staff, t.viewer]) {
      await expect(feed(user, c)).rejects.toMatchObject({ code: '42501' });
      const [status] = await h.rpc<{ unread: number }>(user, 'notification_status', {
        p_company: c,
      });
      expect(Number(status.unread)).toBe(0);
    }
  });
});

describe('the 5-minute schedule', () => {
  async function configure(url: string) {
    await h.admin(`update almailbooks.email_alerts_config set function_url = $1 where id`, [url]);
    await h.admin('delete from net.sent');
  }
  const run = async () =>
    (
      await h.admin<{ id: string | null }>(
        'select almailbooks.run_change_notifications()::text as id',
      )
    )[0].id;

  it('calls the function with the secret only when someone has new changes', async () => {
    await h.admin('update public.notification_settings set enabled = false');
    await configure('');
    const t = await team();
    const c = t.company;
    await turnOn(t.owner, c);
    await push(t.staff, c, [put('clients', rec(c, 'client-1', { name: 'Made-up Client' }))]);
    // The function hasn't run yet: its address isn't known.
    expect(await run()).toBeNull();
    await configure('https://project.supabase.co/functions/v1/email-alerts');
    expect(await run()).toBe('1');
    const [sent] = await h.admin<{ url: string; body: unknown; headers: Record<string, string> }>(
      'select * from net.sent',
    );
    const [{ secret }] = await h.admin<{ secret: string }>(
      'select secret from almailbooks.email_alerts_config',
    );
    expect(sent).toMatchObject({
      url: 'https://project.supabase.co/functions/v1/email-alerts',
      body: { action: 'notify' },
      headers: { 'x-alerts-secret': secret },
    });
    // Emailed: nothing new.
    await h.admin(
      `update public.notification_settings
          set emailed_upto = (select max(id) from public.change_events where company_id = $1)
        where company_id = $1`,
      [c],
    );
    expect(await run()).toBeNull();
    // Their own changes are not news to them.
    await push(t.owner, c, [put('clients', rec(c, 'client-2', { name: 'By the owner' }))]);
    expect(await run()).toBeNull();
    // Nobody calls it but the schedule.
    await expect(
      h.as(t.owner, (q) => q('select almailbooks.run_change_notifications()')),
    ).rejects.toThrow(/permission denied/);
  });

  it('forgets changes after 180 days', async () => {
    const t = await team();
    const c = t.company;
    await turnOn(t.owner, c);
    await push(t.staff, c, [put('clients', rec(c, 'client-1', { name: 'Made-up Client' }))]);
    await push(t.staff, c, [put('clients', rec(c, 'client-2', { name: 'Made-up Client 2' }))]);
    const [oldest] = await events(c);
    await h.admin(
      `update public.change_events set at = now() - interval '181 days' where id = $1`,
      [oldest.id],
    );
    await h.admin('select almailbooks.purge_change_events()');
    expect((await events(c)).map((e) => e.record_id)).toEqual(['client-2']);
  });
});

describe('server_features', () => {
  it('names change_feed once this file has run, and the app finds nothing before', async () => {
    const user = await h.user(`features-${Math.random().toString(36).slice(2)}@example.com`);
    const [row] = await h.rpc<{ server_features: string[] }>(user, 'server_features');
    // Later files name theirs too (20261130000000_people_alerts.sql).
    expect(row.server_features).toEqual(
      expect.arrayContaining([
        'tables_v16',
        'super_admin',
        'approvals',
        'cheque_approvals',
        'change_feed',
      ]),
    );
    // This file's own answer, before any later file.
    const upto = await startDatabase(1, MIGRATIONS.indexOf(FILE) + 1);
    const [own] = await upto.rpc<{ server_features: string[] }>(
      await upto.user('feed-own@example.com'),
      'server_features',
    );
    expect(own.server_features).toEqual([
      'tables_v16',
      'super_admin',
      'approvals',
      'cheque_approvals',
      'change_feed',
    ]);
    const early = await startDatabase(1, MIGRATIONS.indexOf(FILE));
    const someone = await early.user('feed-early@example.com');
    const [before] = await early.rpc<{ server_features: string[] }>(someone, 'server_features');
    expect(before.server_features).not.toContain('change_feed');
    await expect(early.rpc(someone, 'notification_status', { p_company: 'x' })).rejects.toThrow(
      /does not exist/,
    );
  }, 60_000);

  it('stops at once, changing nothing, without the Super Admin file', async () => {
    const early = await startDatabase(1, MIGRATIONS.indexOf(FILE) - 1);
    const { readFileSync } = await import('node:fs');
    await expect(early.db.exec(readFileSync(FILE, 'utf8'))).rejects.toThrow(
      /20261116000000_super_admin_approvals\.sql first/,
    );
    const [found] = await early.admin<{ table: string | null }>(
      `select to_regclass('public.change_events')::text as table`,
    );
    expect(found.table).toBeNull();
  }, 60_000);
});

describe('the app’s copy of the rules (src/cloud/change-feed.ts)', () => {
  it('finds the same kind, importance and summary as the server', async () => {
    const c = 'parity-co';
    const client = { name: 'Made-up Client', nameAr: 'عميل' };
    const doc = (extra: Record<string, unknown> = {}) => invoice(c, 'inv-1', extra);
    const pay = (extra: Record<string, unknown> = {}) => cheque(c, 'pay-1', extra);
    const company = (extra: Record<string, unknown> = {}) => ({
      id: c,
      name: 'Made-up',
      numbering: { invoice: { pattern: 'INV-{n}', next: 1 } },
      accounting: { lockDate: null },
      ...extra,
    });
    const cases: [
      string,
      Record<string, unknown> | null,
      Record<string, unknown> | null,
      boolean,
    ][] = [
      ['documents', null, doc(), false],
      ['documents', doc(), null, false],
      ['documents', doc({ status: 'draft' }), null, false],
      ['documents', doc({ status: 'draft' }), doc(), false],
      ['documents', doc(), doc({ status: 'void' }), false],
      ['documents', doc({ status: 'void' }), doc(), false],
      ['documents', doc(), doc({ notes: 'Changed' }), false],
      ['documents', doc(), doc({ status: 'paid', totals: { total: 100, balance: 0 } }), false],
      ['documents', doc({ type: 'quote' }), doc({ type: 'quote', notes: 'Changed' }), false],
      ['payments', null, pay(), false],
      ['payments', pay(), pay({ amount: 300 }), false],
      [
        'payments',
        pay(),
        pay({
          cheque: { number: '100200', bank: 'NBOK', date: '2026-10-20', status: 'deposited' },
        }),
        false,
      ],
      ['payments', pay(), pay({ notes: 'A note' }), false],
      ['payments', pay({ method: 'cash' }), pay({ method: 'cash', amount: 1 }), false],
      ['payments', pay({ method: 'cash' }), pay({ method: 'cash', voided: true }), false],
      [
        'securityCheques',
        null,
        rec(c, 'sc-1', { direction: 'out', number: '7', amount: 1, status: 'held' }),
        false,
      ],
      [
        'securityCheques',
        rec(c, 'sc-1', { direction: 'out', number: '7', amount: 1, status: 'held' }),
        rec(c, 'sc-1', { direction: 'out', number: '7', amount: 1, status: 'cashed' }),
        false,
      ],
      [
        'approvals',
        null,
        rec(c, 'a', {
          kind: 'invoice_void',
          subjectTbl: 'documents',
          subjectNumber: 'INV-1',
          status: 'pending',
        }),
        false,
      ],
      [
        'approvals',
        rec(c, 'a', { kind: 'invoice_void', status: 'pending' }),
        rec(c, 'a', { kind: 'invoice_void', status: 'rejected' }),
        false,
      ],
      [
        'approvals',
        null,
        rec(c, 'a', { kind: 'payroll', subjectTbl: 'payRuns', subjectNumber: '2026-10' }),
        true,
      ],
      [
        'companies',
        company(),
        company({ numbering: { invoice: { pattern: 'INV-{n}', next: 5 } } }),
        false,
      ],
      ['companies', company(), company({ accounting: { lockDate: '2026-06-30' } }), false],
      ['companies', company(), company({ approvalRules: { documentTypes: ['invoice'] } }), false],
      ['companies', company(), company({ name: 'Other' }), false],
      ['payRuns', null, rec(c, 'r', { period: '2026-10', status: 'draft' }), true],
      ['payRuns', rec(c, 'r', { status: 'approved' }), rec(c, 'r', { status: 'paid' }), true],
      ['employees', null, rec(c, 'e', { name: 'Made-up' }), true],
      ['staffingCostings', null, rec(c, 'sc', { name: 'Made-up site', status: 'draft' }), true],
      ['clients', null, rec(c, 'cl', { name: 'Made-up', isVendor: true }), false],
      ['products', null, rec(c, 'p', { name: 'Made-up', sku: 'SKU-1' }), false],
      ['expenses', null, rec(c, 'x', { number: 'EXP-1', amount: 3, currency: 'KWD' }), false],
      ['journals', null, rec(c, 'j', { number: 'JV-1' }), false],
      ['vehicles', null, rec(c, 'v', { plate: '12/34567' }), false],
      ['complianceDocuments', null, rec(c, 'cd', { title: 'Licence', type: 'licence' }), false],
      ['attachments', null, rec(c, 'f', { name: 'scan.pdf' }), false],
      ['accounts', null, rec(c, 'acc', { name: 'Cash' }), false],
      // Items issued to employees (20261210000000_warehouse_issues.sql).
      [
        'approvals',
        null,
        rec(c, 'a', {
          kind: 'stock_issue',
          subjectTbl: 'stockIssues',
          subjectNumber: '',
          status: 'pending',
          after: {
            warehouseId: 'store',
            recipient: { name: 'Made-up Guard', nameAr: '', jobTitle: 'Security Guard' },
            lines: [
              { productId: 'p1', name: 'Trouser', nameAr: 'بنطلون', quantity: 1 },
              { productId: 'p2', name: 'T-shirt', quantity: 2 },
            ],
          },
        }),
        false,
      ],
      [
        'approvals',
        rec(c, 'a', { kind: 'stock_issue', status: 'pending', after: { recipient: {} } }),
        rec(c, 'a', { kind: 'stock_issue', status: 'approved', after: { recipient: {} } }),
        false,
      ],
      [
        'stockIssues',
        null,
        rec(c, 'si', {
          number: 'ISS-0001',
          recipient: { name: 'Made-up Guard', jobTitle: 'Security Guard' },
          lines: [{ productId: 'p1', name: 'Shoes', quantity: 1.5 }],
        }),
        false,
      ],
      ['stockIssues', rec(c, 'si', { number: 'ISS-0001', lines: [] }), null, false],
    ];
    for (const [tbl, before, after, isPrivate] of cases) {
      const data = after ?? before;
      const [server] = await h.admin<{ kind: string; details: unknown }>(
        `select almailbooks.change_kind($1, $2::jsonb) as kind,
                almailbooks.change_details('no-such-company', $1, $3::jsonb, $4::jsonb, $5) as details`,
        [tbl, json(data), before ? json(before) : null, after ? json(after) : null, isPrivate],
      );
      expect([tbl, changeKind(tbl, data)]).toEqual([tbl, server.kind]);
      // The server reads the contact's names from the records; given here.
      const app = changeDetails(tbl, before, after, isPrivate, null);
      expect([tbl, before, after, app]).toEqual([tbl, before, after, server.details]);
    }
    void client;
  });
});

describe('the fake cloud of the app’s tests', () => {
  it('keeps the same feed as the server, and shows it to the same people', async () => {
    const t = await team();
    const c = t.company;
    const fake = new FakeCloud();
    fake.features = ['tables_v16', 'super_admin', 'approvals', 'cheque_approvals', 'change_feed'];
    fake.companies.set(c, { id: c, name: 'Same', purgedUntilRev: 0, createdAt: '' });
    const users: Record<MemberRole, string> = {
      owner: t.owner,
      admin: t.admin,
      accountant: t.accountant,
      staff: t.staff,
      viewer: t.viewer,
    };
    for (const [role, user] of Object.entries(users)) fake.addMember(c, user, role as MemberRole);
    await approve(t, t.accountant);
    fake.setAccess(c, t.accountant, {}, true);
    for (const user of [t.owner, t.accountant]) {
      await turnOn(user, c);
      await fake.client(user).setChangeNotifications(c, {
        enabled: true,
        immediateKinds: ['document', 'cheque', 'approval', 'member', 'settings', 'people'],
        digest: 'daily',
        appUrl: '',
      });
    }
    const batches: [string, Change[]][] = [
      [
        t.staff,
        [
          put('clients', rec(c, 'client-1', { name: 'Made-up Client' })),
          put('clients', rec(c, 'client-2', { name: 'Made-up Client 2' })),
          put('documents', invoice(c, 'inv-1')),
          put('payments', cheque(c, 'pay-1')),
          put('activities', rec(c, 'act-1', { entity: 'invoice' })),
        ],
      ],
      [t.staff, [put('documents', invoice(c, 'inv-1', { status: 'void' }))]],
      [t.staff, [put('documents', invoice(c, 'inv-1', { status: 'void' }))]],
      [t.admin, [put('employees', rec(c, 'emp-1', { name: 'Made-up Person' }))]],
      [t.owner, [{ tbl: 'clients', id: 'client-2', deleted: true }]],
      [
        t.accountant,
        [
          put(
            'approvals',
            rec(c, 'apr-1', {
              kind: 'invoice_void',
              subjectTbl: 'documents',
              subjectId: 'inv-1',
              subjectNumber: 'INV-1',
              status: 'pending',
            }),
          ),
        ],
      ],
    ];
    for (const [user, changes] of batches) {
      await push(user, c, changes);
      await fake.client(user).pushRecords(c, changes as never);
    }
    const shape = (
      rows: {
        tbl: string;
        op: string;
        kind: string;
        important: boolean;
        private: boolean;
        count: number;
        summary: Record<string, unknown>;
      }[],
    ) =>
      rows
        .filter((r) => r.kind !== 'member')
        .map((r) => [r.tbl, r.op, r.kind, r.important, r.private, r.count, r.summary.what]);
    for (const user of [t.owner, t.accountant]) {
      const server = shape(await feed(user, c));
      const app = shape((await fake.client(user).changeFeed(c))!);
      expect(app).toEqual(server);
      expect(server.length).toBeGreaterThan(3);
    }
    // Everyone else is refused by both.
    for (const user of [t.admin, t.staff, t.viewer]) {
      await expect(feed(user, c)).rejects.toMatchObject({ code: '42501' });
      await expect(fake.client(user).changeFeed(c)).rejects.toMatchObject({ code: 'permission' });
    }
  }, 60_000);
});
