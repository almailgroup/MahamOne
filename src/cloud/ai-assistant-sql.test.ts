// @vitest-environment node
import { readFileSync } from 'node:fs';
import { beforeAll, describe, expect, it } from 'vitest';
import { MIGRATIONS, startDatabase, type Harness } from './sql-harness';
import type { MemberRole } from './roles';
import { FakeCloud } from './testing/fake-cloud';

/**
 * 20261208000000_ai_assistant.sql: the company's AI assistant switch ("ai"
 * on the company record) is changed by the owner or an admin only, whatever
 * apps the owner limited the admin to. Anyone else's copy, by a push or
 * patch_company, keeps it as it is stored, so an older version's copy never
 * turns it off; staff and viewers are refused as before. The rule is one
 * more in records_guard, which keeps every rule it had (the other *-sql
 * tests run against this file's records_guard too), and server_features()
 * also answers 'ai_assistant'. Made-up data only.
 */

const FILE = MIGRATIONS.find((file) => file.endsWith('_ai_assistant.sql'))!;

let h: Harness;
let seq = 0;

beforeAll(async () => {
  // Each file twice, this one after every earlier one: running it again must be safe.
  h = await startDatabase(2);
}, 120_000);

const json = (value: unknown) => JSON.stringify(value);
type Change = { tbl: string; id: string; data?: unknown; deleted?: boolean };

/** A company with an owner, an admin, an admin limited to viewing both apps, an accountant, staff and a viewer. */
async function team(db: Harness = h) {
  seq += 1;
  const company = `ai-co-${String(seq).padStart(4, '0')}`;
  const tag = `ai-${seq}-${Math.random().toString(36).slice(2, 8)}`;
  const owner = await db.user(`owner-${tag}@example.com`);
  await db.rpc(owner, 'create_company', { p_id: company, p_name: `Company ${seq}` });
  const members: Record<string, string> = {};
  for (const [key, role] of [
    ['admin', 'admin'],
    ['limited', 'admin'],
    ['accountant', 'accountant'],
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
  await push(owner, company, [{ tbl: 'companies', id: company, data: record(company) }], db);
  await db.rpc(owner, 'set_member_permissions', {
    p_company: company,
    p_user: members.limited,
    p_permissions: json({ apps: { books: 'view', people: 'view' } }),
    p_can_approve: false,
  });
  const { admin, limited, accountant, staff, viewer } = members;
  return { company, owner, admin, limited, accountant, staff, viewer };
}

function push(user: string, company: string, changes: Change[], db: Harness = h) {
  return db.rpc<{ tbl: string; id: string; rev: number }>(user, 'push_records', {
    p_company: company,
    p_changes: json(changes),
  });
}

function patch(user: string, company: string, ops: unknown[], db: Harness = h) {
  return db.rpc(user, 'patch_company', { p_company: company, p_ops: json(ops) });
}

async function stored(company: string, db: Harness = h) {
  const [row] = await db.admin<{ data: Record<string, unknown> }>(
    `select data from public.records where company_id = $1 and tbl = 'companies' and id = $1`,
    [company],
  );
  return row?.data;
}

const record = (c: string, extra: Record<string, unknown> = {}) => ({
  id: c,
  name: 'Made-up Trading',
  currency: 'KWD',
  phone: '',
  createdAt: '2026-10-20T08:00:00.000Z',
  updatedAt: '2026-10-20T08:00:00.000Z',
  ...extra,
});

const ON = [{ path: ['ai'], value: { on: true } }];
const OFF = [{ path: ['ai'], remove: true }];

const EARLIER = [
  'tables_v16',
  'super_admin',
  'approvals',
  'cheque_approvals',
  'change_feed',
  'payroll_approvals',
  'document_alerts',
  'employee_letters',
  'staffing_costings',
];

async function features(db: Harness): Promise<string[]> {
  const someone = await db.user(`f-${Math.random().toString(36).slice(2)}@example.com`);
  const [row] = await db.rpc<{ server_features: string[] }>(someone, 'server_features');
  return row.server_features;
}

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

describe('the file', () => {
  it('stops at once, changing nothing, without the staffing costings file', async () => {
    const early = await startDatabase(1, MIGRATIONS.indexOf(FILE) - 1);
    await expect(early.db.exec(readFileSync(FILE, 'utf8'))).rejects.toThrow(
      /Run 20261207000000_staffing_costings\.sql first, then this file\./,
    );
    const [row] = await early.admin<{ missing: boolean }>(
      `select to_regprocedure('almailbooks.switches_ai(text)') is null as missing`,
    );
    expect(row.missing).toBe(true);
    expect(await features(early)).not.toContain('ai_assistant');
  }, 60_000);

  it('names ai_assistant with everything the earlier files name', async () => {
    const through = await startDatabase(1, MIGRATIONS.indexOf(FILE) + 1);
    expect(await features(through)).toEqual([...EARLIER, 'ai_assistant']);
    expect(await features(h)).toContain('ai_assistant');
    const before = await startDatabase(1, MIGRATIONS.indexOf(FILE));
    expect(await features(before)).toEqual(EARLIER);
  }, 60_000);

  it('keeps every rule records_guard had: the latest earlier one, with only the switch added', () => {
    const earlier = MIGRATIONS.slice(0, MIGRATIONS.indexOf(FILE)).filter((file) =>
      readFileSync(file, 'utf8').includes('create or replace function almailbooks.records_guard()'),
    );
    const latest = definition(earlier.at(-1)!, 'almailbooks.records_guard');
    const mine = definition(FILE, 'almailbooks.records_guard');
    const rule = /\n {4}-- The AI assistant's switch[\s\S]*?\n {4}end if;/.exec(mine)![0];
    expect(rule).toContain('almailbooks.kept_key(');
    expect(mine.replace(rule, '')).toBe(latest);
    // server_features as the latest earlier file has it, with one more name.
    const names = (body: string) => [...body.matchAll(/'([a-z0-9_]+)'/g)].map((m) => m[1]);
    expect(names(definition(FILE, 'public.server_features'))).toEqual([...EARLIER, 'ai_assistant']);
  });
});

describe('the AI assistant’s switch', () => {
  it('is turned on and off by the owner or an admin, an admin limited to viewing included', async () => {
    const t = await team();
    const c = t.company;
    for (const user of [t.owner, t.admin, t.limited]) {
      await patch(user, c, ON);
      expect((await stored(c))?.ai).toEqual({ on: true });
      await patch(user, c, OFF);
      expect(await stored(c)).not.toHaveProperty('ai');
      // By a push of the whole record too.
      await push(user, c, [{ tbl: 'companies', id: c, data: record(c, { ai: { on: true } }) }]);
      expect((await stored(c))?.ai).toEqual({ on: true });
      await push(user, c, [{ tbl: 'companies', id: c, data: record(c) }]);
      expect(await stored(c)).not.toHaveProperty('ai');
    }
  });

  it('is kept as stored for an accountant, whose other changes go through', async () => {
    const t = await team();
    const c = t.company;
    // Not turned on.
    await patch(t.accountant, c, ON);
    expect(await stored(c)).not.toHaveProperty('ai');
    await push(t.accountant, c, [
      { tbl: 'companies', id: c, data: record(c, { ai: { on: true } }) },
    ]);
    expect(await stored(c)).not.toHaveProperty('ai');
    // Nor off, nor changed, once the owner turned it on.
    await patch(t.owner, c, ON);
    await patch(t.accountant, c, OFF);
    expect((await stored(c))?.ai).toEqual({ on: true });
    await patch(t.accountant, c, [{ path: ['ai', 'on'], value: false }]);
    expect((await stored(c))?.ai).toEqual({ on: true });
    // An older version's copy, which has never heard of the switch.
    await push(t.accountant, c, [{ tbl: 'companies', id: c, data: record(c, { phone: '1' }) }]);
    expect(await stored(c)).toMatchObject({ ai: { on: true }, phone: '1' });
    await patch(t.accountant, c, [{ path: ['phone'], value: '+965 0000 0000' }]);
    expect(await stored(c)).toMatchObject({ ai: { on: true }, phone: '+965 0000 0000' });
  });

  it('is refused to staff and viewers, as any company setting', async () => {
    const t = await team();
    const c = t.company;
    await expect(patch(t.staff, c, ON)).rejects.toMatchObject({ code: '42501' });
    await expect(patch(t.viewer, c, ON)).rejects.toThrow();
    await expect(
      push(t.viewer, c, [{ tbl: 'companies', id: c, data: record(c, { ai: { on: true } }) }]),
    ).rejects.toThrow(/row-level security/);
    expect(await stored(c)).not.toHaveProperty('ai');
  });
});

describe('the app’s stand-in for the cloud', () => {
  it('keeps the switch as the server does, before the file and after it', async () => {
    const before = await startDatabase(1, MIGRATIONS.indexOf(FILE));
    for (const db of [before, h]) {
      const t = await team(db);
      const c = t.company;
      const fake = new FakeCloud();
      fake.features = await features(db);
      expect(fake.features.includes('ai_assistant')).toBe(db === h);
      fake.companies.set(c, { id: c, name: 'Company', purgedUntilRev: 0, createdAt: '' });
      const users: [string, MemberRole][] = [
        [t.owner, 'owner'],
        [t.admin, 'admin'],
        [t.accountant, 'accountant'],
      ];
      for (const [user, role] of users) fake.addMember(c, user, role);
      await fake
        .client(t.owner)
        .pushRecords(c, [{ tbl: 'companies', id: c, data: record(c) }] as never);
      const ai = async () => [
        fake.record(c, 'companies', c)?.ai ?? null,
        (await stored(c, db))?.ai ?? null,
      ];
      const seen: unknown[] = [];
      for (const [user] of users) {
        for (const ops of [ON, OFF, ON]) {
          await patch(user, c, ops, db);
          await fake.client(user).patchCompany(c, ops as never);
          const [inFake, inSql] = await ai();
          expect(inFake).toEqual(inSql);
          seen.push(inSql);
        }
        const whole = { tbl: 'companies', id: c, data: record(c) };
        await push(user, c, [whole], db);
        await fake.client(user).pushRecords(c, [whole] as never);
        const [inFake, inSql] = await ai();
        expect(inFake).toEqual(inSql);
        seen.push(inSql);
      }
      // The accountant's turn last: kept as stored once the file has run
      // (the admin turned it off with the whole record), theirs before it.
      expect(seen.slice(-4)).toEqual(
        db === h ? [null, null, null, null] : [{ on: true }, null, { on: true }, null],
      );
    }
  }, 120_000);
});
