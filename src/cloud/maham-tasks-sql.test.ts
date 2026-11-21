import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { beforeAll, describe, expect, it } from 'vitest';
import { startDatabase, TASKS_MIGRATION, type Harness } from './sql-harness';

/**
 * Maham Tasks on Maham One's database (20261212000000_maham_tasks.sql): in
 * its own schema, beside Maham One's files and changing nothing of them;
 * nothing on auth.users, so Maham One's sign-ups never go through it; one
 * account for both apps, in Maham Tasks only by accepting an admin's invite
 * (or as the owner's first admin); only its members reach its data; its
 * server works with its own secret, not a master key; and it runs again with
 * data in it. Made-up people only.
 */

const CHECK = readFileSync(join(__dirname, '../../supabase/health-check.sql'), 'utf8');

let h: Harness;
let without: Harness;

beforeAll(async () => {
  // Every Maham One file, then this one, each twice: running it again must be safe.
  h = await startDatabase(2, undefined, { tasks: true });
  without = await startDatabase();
}, 240_000);

let seq = 0;
const email = (who: string) => `${who}-${++seq}@example.com`;

type Query = <T>(sql: string, params?: unknown[]) => Promise<T[]>;

/** Runs `fn` as a signed-in account, with the second sign-in step or not. */
function signedIn<T>(
  db: Harness,
  userId: string,
  fn: (q: Query) => Promise<T>,
  secondStep = true,
): Promise<T> {
  return db.db.transaction(async (tx) => {
    await tx.query(`set local role authenticated`);
    await tx.query(`select set_config('request.jwt.claims', $1, true)`, [
      JSON.stringify({ sub: userId, role: 'authenticated', aal: secondStep ? 'aal2' : 'aal1' }),
    ]);
    return fn(
      async <R>(sql: string, params: unknown[] = []) =>
        (await tx.query<R>(sql, params)).rows as R[],
    );
  });
}

async function invite(
  db: Harness,
  by: string,
  address: string,
  role = 'member',
  secondStep = true,
) {
  const [row] = await signedIn(
    db,
    by,
    (q) =>
      q<{ status: { status: string } }>(
        `select tasks.add_teammate($1, 'Made-up Teammate', $2::tasks.user_role) as status`,
        [address, role],
      ),
    secondStep,
  );
  return row.status.status;
}

async function joins(db: Harness, userId: string) {
  const [row] = await signedIn(db, userId, (q) => q<{ ok: boolean }>(`select tasks.join() as ok`));
  return row.ok;
}

const roleOf = async (db: Harness, userId: string) =>
  (
    await db.admin<{ role: string }>(`select role::text from tasks.profiles where id = $1`, [
      userId,
    ])
  )[0]?.role;

/** The health check's rows, as status and check. */
async function healthCheck(db: Harness) {
  const results = await db.db.exec(CHECK);
  return (results.at(-1)!.rows as { step: string; check: string; status: string }[]).map(
    (r) => `${r.step} | ${r.check} | ${r.status}`,
  );
}

/** Maham One's functions, triggers and rules, as stored. */
async function mahamOne(db: Harness) {
  const functions = await db.admin<{ sig: string; body: string }>(
    `select p.oid::regprocedure::text as sig, md5(pg_get_functiondef(p.oid)) as body
       from pg_proc p
      where p.pronamespace in ('public'::regnamespace, 'almailbooks'::regnamespace)
        and p.prokind = 'f'
      order by 1`,
  );
  const policies = await db.admin<{ rel: string; name: string; qual: string }>(
    `select polrelid::regclass::text as rel, polname as name,
            coalesce(pg_get_expr(polqual, polrelid), '') || '|' ||
            coalesce(pg_get_expr(polwithcheck, polrelid), '') as qual
       from pg_policy
      where polrelid::regclass::text not like 'tasks.%'
        and polname not like 'Maham Tasks%'
        and polname not like 'attachment objects%'
        and polname not like '%avatar%'
      order by 1, 2`,
  );
  const triggers = await db.admin<{ rel: string; name: string; fn: string }>(
    `select tgrelid::regclass::text as rel, tgname as name, tgfoid::regproc::text as fn
       from pg_trigger
      where not tgisinternal and tgrelid::regclass::text not like 'tasks.%'
      order by 1, 2`,
  );
  return { functions, policies, triggers };
}

/** An admin of Maham Tasks: the first by the owner's line, the rest invited by an admin. */
async function admin() {
  const address = email('admin');
  const id = await h.user(address, { name: 'Made-up Admin' });
  const [first] = await h.admin<{ id: string }>(
    `select id from tasks.profiles where role = 'admin' order by created_at limit 1`,
  );
  if (first) {
    await invite(h, first.id, address, 'admin');
    expect(await joins(h, id)).toBe(true);
  } else {
    await h.admin(`select tasks.add_first_admin($1)`, [address]);
  }
  return id;
}

/** Somebody invited by `boss` who has accepted. */
async function member(boss: string, who = 'member') {
  const address = email(who);
  const id = await h.user(address);
  await invite(h, boss, address);
  expect(await joins(h, id)).toBe(true);
  return id;
}

describe('beside Maham One', () => {
  it('changes none of its functions, triggers or rules, and puts nothing on auth.users', async () => {
    const before = await mahamOne(without);
    const after = await mahamOne(h);
    expect(after.functions).toEqual(before.functions);
    expect(after.policies).toEqual(before.policies);
    expect(after.triggers).toEqual(before.triggers);
  });

  it('leaves the health check as it was', async () => {
    expect(await healthCheck(h)).toEqual(await healthCheck(without));
  }, 60_000);

  it('makes no Maham One sign-up a Maham Tasks member, not even the first', async () => {
    const id = await h.user(email('signup'));
    expect(await h.admin(`select id from public.profiles where id = $1`, [id])).toHaveLength(1);
    expect(await roleOf(h, id)).toBeUndefined();
    const fresh = await startDatabase(1, undefined, { tasks: true });
    const first = await fresh.user(email('first'));
    expect(await roleOf(fresh, first)).toBeUndefined();
  }, 120_000);

  it('runs again with data in it, the newest kinds of row included', async () => {
    const db = await startDatabase(1, undefined, { tasks: true });
    const owner = await db.user('owner@example.com');
    await db.admin(`select tasks.add_first_admin('owner@example.com')`);
    const [{ id: project }] = await db.admin<{ id: string }>(
      `insert into tasks.projects (name, created_by) values ('Made-up Project', $1) returning id`,
      [owner],
    );
    const [{ id: task }] = await db.admin<{ id: string }>(
      `insert into tasks.tasks (project_id, title, created_by) values ($1, 'Made-up Task', $2) returning id`,
      [project, owner],
    );
    await db.admin(
      `insert into tasks.task_activity (task_id, actor_id, action) values ($1, $2, 'restored')`,
      [task, owner],
    );
    await db.admin(
      `insert into tasks.notifications (user_id, type, title)
       values ($1, 'task_unblocked', 'x'), ($1, 'reminder_failed', 'y')`,
      [owner],
    );
    await db.admin(
      `insert into tasks.reminder_queue (user_id, channel, kind, recipient, body, status, dedupe_key)
       values ($1, 'push', 'summary', 'device', 'z', 'sending', 'made-up-key')`,
      [owner],
    );
    await db.db.exec(readFileSync(TASKS_MIGRATION, 'utf8'));
    expect(
      await db.admin(
        `select conname from pg_constraint
          where connamespace = 'tasks'::regnamespace and contype = 'c' and not convalidated`,
      ),
    ).toEqual([]);
    expect(await roleOf(db, owner)).toBe('admin');
  }, 120_000);
});

describe('one account, in Maham Tasks by invite', () => {
  it('makes the owner the first admin, once, from the SQL editor only', async () => {
    const fresh = await startDatabase(1, undefined, { tasks: true });
    const owner = await fresh.user('owner@example.com', { name: 'Made-up Owner' });
    await expect(
      fresh.rpc(owner, 'tasks.add_first_admin', { p_email: 'owner@example.com' }),
    ).rejects.toThrow();
    await expect(fresh.admin(`select tasks.add_first_admin('nobody@example.com')`)).rejects.toThrow(
      /No Maham One account uses/,
    );
    await fresh.admin(`select tasks.add_first_admin('OWNER@example.com')`);
    expect(
      await fresh.admin(`select role::text, full_name from tasks.profiles where id = $1`, [owner]),
    ).toEqual([{ role: 'admin', full_name: 'Made-up Owner' }]);
    const other = await fresh.user('other@example.com');
    await expect(fresh.admin(`select tasks.add_first_admin('other@example.com')`)).rejects.toThrow(
      /has an admin already/,
    );
    expect(await roleOf(fresh, other)).toBeUndefined();
  }, 120_000);

  it('invites by email, saying nothing of Maham One accounts, and the person accepts by signing in', async () => {
    const boss = await admin();
    const existing = email('existing');
    const id = await h.user(existing);
    // The same answer whether or not a Maham One account has the email.
    expect(await invite(h, boss, existing)).toBe('invited');
    expect(await invite(h, boss, email('nobody'))).toBe('invited');
    // Not in until they accept.
    expect(await roleOf(h, id)).toBeUndefined();
    expect(await joins(h, id)).toBe(true);
    expect(await roleOf(h, id)).toBe('member');
    expect(await invite(h, boss, existing.toUpperCase())).toBe('already');

    // Made later, unconfirmed: in only once the email is confirmed.
    const later = email('later');
    expect(await invite(h, boss, later, 'manager')).toBe('invited');
    const joined = await h.user(later, { confirmed: false });
    expect(await joins(h, joined)).toBe(false);
    await h.admin(`update auth.users set email_confirmed_at = now() where id = $1`, [joined]);
    expect(await joins(h, joined)).toBe(true);
    expect(await roleOf(h, joined)).toBe('manager');
    expect(await h.admin(`select email from tasks.invites where email = $1`, [later])).toEqual([]);

    // Without an invite, signing in gets nobody in.
    const stranger = await h.user(email('stranger'));
    expect(await joins(h, stranger)).toBe(false);
  });

  it('needs an admin with the second sign-in step, in the database itself', async () => {
    const boss = await admin();
    await expect(invite(h, boss, email('x'), 'member', false)).rejects.toThrow(/two-step/);
    const someone = await member(boss);
    await expect(invite(h, someone, email('y'))).rejects.toThrow(/Only an admin/);
  });

  it('lets an admin remove a teammate’s authenticator app, and nothing else', async () => {
    const boss = await admin();
    const id = await member(boss, 'lostphone');
    await h.admin(
      `insert into auth.mfa_factors (user_id, factor_type) values ($1, 'totp'), ($1, 'phone')`,
      [id],
    );
    const remove = (by: string, user: string, secondStep = true) =>
      signedIn(
        h,
        by,
        (q) => q<{ n: number }>(`select tasks.remove_two_step($1) as n`, [user]),
        secondStep,
      );
    await expect(remove(id, boss)).rejects.toThrow();
    await expect(remove(boss, id, false)).rejects.toThrow(/two-step/);
    expect(await remove(boss, id)).toEqual([{ n: 1 }]);
    expect(
      await h.admin(`select factor_type from auth.mfa_factors where user_id = $1`, [id]),
    ).toEqual([{ factor_type: 'phone' }]);
    // Not for an account outside Maham Tasks.
    const outsider = await h.user(email('outsider'));
    await expect(remove(boss, outsider)).rejects.toThrow(/not in Maham Tasks/);
  });
});

describe('only its members', () => {
  it('reach its data, whatever a table’s own rules allow', async () => {
    const boss = await admin();
    const someone = await member(boss);
    const outsider = await h.user(email('maham-one-only'));
    const day = `2027-0${(seq % 9) + 1}-1${seq % 10}`;
    await signedIn(h, boss, (q) =>
      q(`insert into tasks.company_holidays (day, name) values ($1, 'Made-up Day')`, [day]),
    );
    const count = (who: string, table: string) =>
      h.as(who, async (q) => {
        const [row] = await q<{ n: number }>(`select count(*)::int as n from tasks.${table}`);
        return row.n;
      });
    expect(await count(someone, 'company_holidays')).toBeGreaterThan(0);
    expect(await count(someone, 'profiles')).toBeGreaterThan(1);
    for (const table of ['company_holidays', 'profiles', 'labels', 'team_messages', 'invites']) {
      expect(await count(outsider, table)).toBe(0);
    }
    // Nor do they write to it.
    await expect(
      h.as(outsider, (q) =>
        q(`insert into tasks.team_messages (author_id, body) values ($1, 'hello')`, [outsider]),
      ),
    ).rejects.toThrow();
    // Its files neither.
    await h.admin(
      `insert into storage.objects (bucket_id, name, owner) values ('tasks-avatars', $1, $2)`,
      [`${someone}/me.png`, someone],
    );
    const files = (who: string) =>
      h.as(who, async (q) => {
        const [row] = await q<{ n: number }>(
          `select count(*)::int as n from storage.objects where bucket_id = 'tasks-avatars'`,
        );
        return row.n;
      });
    expect(await files(someone)).toBeGreaterThan(0);
    expect(await files(outsider)).toBe(0);
  });

  it('call its functions; nobody signed out does, but the server and the health check', async () => {
    const outsider = await h.user(email('caller'));
    for (const who of [null, outsider]) {
      await expect(h.rpc(who, 'tasks.purge_trashed_tasks', {})).rejects.toThrow();
      await expect(
        h.rpc(who, 'tasks.push_notification', {
          recipient: outsider,
          actor: outsider,
          kind: 'assigned',
          heading: 'x',
          detail: 'x',
          task: null,
          project: null,
        }),
      ).rejects.toThrow();
    }
    await expect(h.rpc(null, 'tasks.task_counts', {})).rejects.toThrow();
    await expect(h.rpc(null, 'tasks.join', {})).rejects.toThrow();
    expect(await h.rpc(null, 'tasks.portal_health', {})).toHaveLength(1);
  });
});

describe('its server, without a master key', () => {
  it('works with its own secret only, and reaches only Maham Tasks', async () => {
    await expect(h.rpc(null, 'tasks.new_server_secret', {})).rejects.toThrow();
    const [{ secret }] = await h.admin<{ secret: string }>(
      `select tasks.new_server_secret() as secret`,
    );
    expect(secret).toMatch(/^[0-9a-f]{64}$/);
    for (const wrong of [null, '', 'x'.repeat(64)]) {
      await expect(
        h.rpc(null, 'tasks.srv_holidays', {
          p_secret: wrong,
          p_from: '2027-01-01',
          p_to: '2027-12-31',
        }),
      ).rejects.toThrow(/Only Maham Tasks' server/);
    }
    const holidays = await h.rpc<{ day: string }>(null, 'tasks.srv_holidays', {
      p_secret: secret,
      p_from: '2027-01-01',
      p_to: '2027-12-31',
    });
    expect(holidays.length).toBeGreaterThan(0);
    const keys = await h.rpc(null, 'tasks.srv_web_push_keys', {
      p_secret: secret,
      p_public: 'public-key',
      p_private: 'private-key',
    });
    expect(keys).toEqual([{ public_key: 'public-key', private_key: 'private-key' }]);
    // A new secret replaces the old one.
    const [{ again }] = await h.admin<{ again: string }>(
      `select tasks.new_server_secret() as again`,
    );
    await expect(h.rpc(null, 'tasks.srv_purge_old_errors', { p_secret: secret })).rejects.toThrow();
    expect(await h.rpc(null, 'tasks.srv_purge_old_errors', { p_secret: again })).toHaveLength(1);
  });

  it('has nothing of Maham One among the functions it opens', async () => {
    const opened = await h.admin<{ body: string }>(
      `select p.prosrc as body from pg_proc p
        where p.pronamespace = 'tasks'::regnamespace and p.proname like 'srv\\_%'`,
    );
    expect(opened.length).toBeGreaterThan(15);
    for (const { body } of opened) {
      expect(body).toContain('tasks.assert_server(p_secret)');
      expect(body).not.toMatch(/public\.|almailbooks\./);
    }
  });
});
