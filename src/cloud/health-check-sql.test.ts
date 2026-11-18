// @vitest-environment node
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { DATA_TABLES } from '@/db/db';
import { PEOPLE_TABLES } from './roles';
import { MIGRATION, MIGRATIONS, startDatabase, type Harness } from './sql-harness';

/**
 * supabase/health-check.sql: the owner pastes it into the Supabase SQL editor
 * to see whether every script ran, each as its latest version, and whether
 * everything works. It must say exactly which scripts are missing or were
 * undone (and in which order to run them), never change anything, and never
 * show a secret or anyone's data. Made-up data only.
 */

const CHECK_FILE = join(__dirname, '../../supabase/health-check.sql');
const CHECK = readFileSync(CHECK_FILE, 'utf8');
const SOURCES = MIGRATIONS.map((file) => readFileSync(file, 'utf8'));
const FILE_NAMES = MIGRATIONS.map((file) => file.split('/').at(-1)!);

interface Row {
  step: string;
  check: string;
  status: 'OK' | 'MISSING' | 'WARN' | 'FAIL';
  detail: string;
}

async function runCheck(h: Harness): Promise<Row[]> {
  const results = await h.db.exec(CHECK);
  return results.at(-1)!.rows as unknown as Row[];
}

/** The script number a row is about (1 to 10), or the part after them (11 to 14). */
const stepNo = (row: Row) => Number(/^(\d+)\./.exec(row.step)![1]);
const notOk = (rows: Row[]) => rows.filter((row) => row.status !== 'OK');
const summary = (rows: Row[]) => rows.at(-1)!;

/** "Run a, then b again, then c (in this order)." as script numbers. */
function scriptsIn(detail: string): number[] {
  return [...detail.matchAll(/(\d{14}_[a-z0-9_]+\.sql)/g)].map((m) => FILE_NAMES.indexOf(m[1]) + 1);
}

/** What PGlite and its stand-in for Supabase can't have: pg_cron, pg_net, a published function. */
const STAND_IN_WARNINGS = [
  ['11. Schedules (pg_cron)', 'pg_cron and pg_net'],
  ['12. Email alerts set-up', 'The email-alerts function has run'],
];

function expectOnlyStandInWarnings(rows: Row[], extra: Row[] = []) {
  const left = notOk(rows).filter((row) => !extra.includes(row) && row !== summary(rows));
  expect(
    left.map((row) => [row.step, row.check]),
    JSON.stringify(left, null, 1),
  ).toEqual(STAND_IN_WARNINGS);
  for (const row of left) expect(row.status).toBe('WARN');
}

/** A database with the scripts run in this order (script numbers). */
async function databaseWith(scripts: number[]): Promise<Harness> {
  const h = await startDatabase(1, 0);
  for (const n of scripts) await h.db.exec(SOURCES[n - 1]);
  return h;
}

/* -------------------------------------------------------------------------- */
/* Stand-ins for pg_cron and pg_net, as Supabase has them                      */
/* -------------------------------------------------------------------------- */

/** The jobs the scripts schedule (when pg_cron is on): name, schedule, command. */
function scheduledJobs(): [string, string, string][] {
  const jobs = new Map<string, [string, string, string]>();
  for (const source of SOURCES) {
    for (const m of source.matchAll(
      /cron\.schedule\(\s*'([^']+)',\s*'([^']+)',\s*'([^']+)'\s*\)/g,
    )) {
      jobs.set(m[1], [m[1], m[2], m[3]]);
    }
  }
  return [...jobs.values()];
}

const CRON_STAND_IN = `
create schema cron;
create table cron.job (
  jobid bigserial primary key,
  schedule text not null,
  command text not null,
  nodename text not null default 'localhost',
  nodeport integer not null default 5432,
  database text not null default 'postgres',
  username text not null default 'postgres',
  active boolean not null default true,
  jobname text
);
create table cron.job_run_details (
  jobid bigint,
  runid bigserial primary key,
  job_pid integer,
  database text,
  username text,
  command text,
  status text,
  return_message text,
  start_time timestamptz,
  end_time timestamptz
);
create schema net;
create table net._http_response (
  id bigint,
  status_code integer,
  content_type text,
  headers jsonb,
  content text,
  timed_out boolean,
  error_msg text,
  created timestamptz not null default now()
);
`;

/** pg_cron with the scripts' jobs, each run once; pg_net with one answer; the function registered. */
async function withSchedules(h: Harness) {
  await h.db.exec(CRON_STAND_IN);
  for (const [name, schedule, command] of scheduledJobs()) {
    await h.admin(`insert into cron.job (jobname, schedule, command) values ($1, $2, $3)`, [
      name,
      schedule,
      command,
    ]);
    await h.admin(
      `insert into cron.job_run_details (jobid, command, status, return_message, start_time, end_time)
       select j.jobid, j.command, 'succeeded', '1 row', now() - interval '1 hour', now() - interval '59 minutes'
       from cron.job j where j.jobname = $1`,
      [name],
    );
  }
  await h.admin(
    `insert into net._http_response (id, status_code, content) values (1, 200, '{"ok":true}')`,
  );
  await h.admin(
    `update almailbooks.email_alerts_config
     set function_url = 'https://made-up-ref.supabase.co/functions/v1/email-alerts'`,
  );
}

/* -------------------------------------------------------------------------- */
/* The lists in the check, as the scripts have them                           */
/* -------------------------------------------------------------------------- */

const arrayIn = (name: string) =>
  [
    ...new RegExp(String.raw`${name} constant text\[\] := array\[([\s\S]*?)\];`)
      .exec(CHECK)![1]
      .matchAll(/'([^']+)'/g),
  ].map((m) => m[1]);

/** A function's signature as to_regprocedure reads it, from its definition in a script. */
function signature(name: string, args: string): string {
  const types = args
    .split(',')
    .map((arg) => arg.trim())
    .filter(Boolean)
    .map((arg) =>
      arg
        .replace(/\s+default\s+[\s\S]*$/i, '')
        .split(/\s+/)
        .slice(1)
        .join(' '),
    );
  return `${name}(${types.join(',')})`;
}

/** Every function the scripts define, with the scripts that define it. */
function scriptFunctions(): Map<string, number[]> {
  const found = new Map<string, number[]>();
  SOURCES.forEach((source, i) => {
    for (const m of source.matchAll(/create or replace function ([a-z0-9_.]+)\(([^)]*)\)/g)) {
      const sig = signature(m[1], m[2]);
      found.set(sig, [...(found.get(sig) ?? []), i + 1]);
    }
  });
  return found;
}

/** The body of a function in each script that defines it. */
function bodies(sig: string): Map<number, string> {
  const name = sig.split('(')[0].replace('.', String.raw`\.`);
  const found = new Map<number, string>();
  SOURCES.forEach((source, i) => {
    for (const m of source.matchAll(
      new RegExp(
        String.raw`create or replace function ${name}\(([^)]*)\)[\s\S]*?as \$\$([\s\S]*?)\$\$;`,
        'g',
      ),
    )) {
      if (signature(sig.split('(')[0], m[1]) === sig) found.set(i + 1, m[2]);
    }
  });
  return found;
}

const versionsOf = (list: string) => list.split(',').map(Number);

const checkFunctions = () =>
  [
    ...CHECK.matchAll(
      /\('((?:public|almailbooks)\.[a-z0-9_]+\([^)]*\))', (\d+), '(app|rls|internal|plain)', '\{([\d,]+)\}'/g,
    ),
  ].map((m) => ({ sig: m[1], step: Number(m[2]), access: m[3], versions: versionsOf(m[4]) }));

const checkMarkers = () =>
  [
    ...CHECK.matchAll(
      /\((\d+), '((?:public|almailbooks)\.[a-z0-9_]+\([^)]*\))', '((?:[^']|'')+)'\)/g,
    ),
  ].map((m) => ({ step: Number(m[1]), sig: m[2], marker: m[3].replace(/''/g, "'") }));

/** A function's body as the check takes it: comments and spacing left out. */
const FINGERPRINT =
  "md5(btrim(regexp_replace(regexp_replace(p.prosrc, '-{2}.*$', '', 'gn'), '[[:space:]]+', ' ', 'g')))";

const checkBodies = () =>
  [
    ...CHECK.matchAll(
      /\('((?:public|almailbooks)\.[a-z0-9_]+\([^)]*\))', (\d+), '([0-9a-f]{32})'\)/g,
    ),
  ].map((m) => `('${m[1]}', ${m[2]}, '${m[3]}')`);

/**
 * The scripts that grant or revoke each function, and what each does with it
 * ("grant authenticated", "revoke anon", ...). The first script's revoke on
 * every function of its schema counts for those it defines.
 */
function grantScripts(): Map<string, { scripts: number[]; by: Map<number, Set<string>> }> {
  const defined = scriptFunctions();
  const found = new Map<string, { scripts: number[]; by: Map<number, Set<string>> }>();
  const add = (sig: string, script: number, what: string[]) => {
    const known = found.get(sig) ?? { scripts: [], by: new Map<number, Set<string>>() };
    if (!known.scripts.includes(script)) known.scripts.push(script);
    known.by.set(script, new Set([...(known.by.get(script) ?? []), ...what]));
    found.set(sig, known);
  };
  SOURCES.forEach((source, i) => {
    const code = source.replace(/--.*$/gm, '');
    for (const m of code.matchAll(
      /\b(grant|revoke)\s[^;]*?\bon\s+(?:all\s+functions\s+in\s+schema\s+([a-z_]+)|function\s+([^;]*?))\s+(?:to|from)\s+([^;]*);/gi,
    )) {
      const what = m[4].split(',').map((role) => `${m[1].toLowerCase()} ${role.trim()}`);
      if (m[2]) {
        for (const [sig, versions] of defined) {
          if (sig.startsWith(`${m[2]}.`) && versions.includes(i + 1)) add(sig, i + 1, what);
        }
        continue;
      }
      for (const f of m[3].matchAll(/([a-z0-9_.]+)\(([^)]*)\)/g)) {
        const types = f[2]
          .split(',')
          .map((type) => type.trim())
          .filter(Boolean);
        add(`${f[1]}(${types.join(',')})`, i + 1, what);
      }
    }
  });
  return found;
}

const checkTriggers = () =>
  [
    ...CHECK.matchAll(
      /\((\d+), '([a-z_.]+)', '([a-z_]+)', '(almailbooks\.[a-z_]+)\(\)', '\{([\d,]+)\}'/g,
    ),
  ].map((m) => ({
    step: Number(m[1]),
    rel: m[2],
    name: m[3],
    fn: m[4],
    versions: versionsOf(m[5]),
  }));

const checkPolicies = () =>
  [
    ...CHECK.matchAll(
      /\((\d+), '(policies|storage)', '([a-z_.]+)', '([^']+)', '([rawd])', (true|false), (?:null(?:::text)?|'([^']*)'), '\{([\d,]+)\}'/g,
    ),
  ].map((m) => ({
    step: Number(m[1]),
    rel: m[3],
    name: m[4],
    cmd: m[5],
    permissive: m[6] === 'true',
    marker: m[7] ?? null,
    versions: versionsOf(m[8]),
  }));

describe('the health check’s lists are the scripts’', () => {
  it('names every function each script defines, with the scripts that define it', () => {
    const listed = checkFunctions();
    const fromScripts = scriptFunctions();
    expect(new Set(listed.map((f) => f.sig)).size).toBe(listed.length);
    expect(Object.fromEntries(listed.map((f) => [f.sig, f.versions]))).toEqual(
      Object.fromEntries(fromScripts),
    );
    for (const f of listed) expect(f.step, f.sig).toBe(f.versions[0]);
  });

  it('marks each replaced function with text only that version and the later ones have', () => {
    const markers = checkMarkers();
    const listed = new Map(checkFunctions().map((f) => [f.sig, f]));
    // Every function a later script replaces is checked at every later version.
    const expected = [...listed.values()].flatMap((f) =>
      f.sig === 'public.server_features()'
        ? []
        : f.versions.slice(1).map((step) => `${step} ${f.sig}`),
    );
    expect(markers.map((m) => `${m.step} ${m.sig}`).sort()).toEqual(expected.sort());
    for (const { step, sig, marker } of markers) {
      for (const [script, body] of bodies(sig)) {
        expect(body.includes(marker), `${sig} in script ${script} and ${marker}`).toBe(
          script >= step,
        );
      }
    }
  });

  it('names every trigger, on its table, with its function', () => {
    const fromScripts = new Map<string, { rel: string; fn: string; versions: number[] }>();
    SOURCES.forEach((source, i) => {
      for (const m of source.matchAll(
        /create trigger ([a-z_]+)\s+[\s\S]*?\son ([a-z_.]+)\s[\s\S]*?execute function ([a-z_.]+)\(\)/g,
      )) {
        const known = fromScripts.get(m[1]);
        fromScripts.set(m[1], {
          rel: m[2],
          fn: m[3],
          versions: [...(known?.versions ?? []), i + 1],
        });
      }
    });
    const listed = checkTriggers();
    expect(
      Object.fromEntries(
        listed.map((t) => [t.name, { rel: t.rel, fn: t.fn, versions: t.versions }]),
      ),
    ).toEqual(Object.fromEntries(fromScripts));
    for (const t of listed) expect(t.step).toBe(t.versions[0]);
  });

  it('names every row-level security rule, on its table and for its action', () => {
    const commands: Record<string, string> = { select: 'r', insert: 'a', update: 'w', delete: 'd' };
    const fromScripts = new Map<string, { cmd: string; permissive: boolean; versions: number[] }>();
    SOURCES.forEach((source, i) => {
      for (const m of source.matchAll(
        /create policy "([^"]+)" on ([a-z_.]+)\s+(as restrictive\s+)?for (select|insert|update|delete) to authenticated/g,
      )) {
        const key = `${m[2]} ${m[1]}`;
        const known = fromScripts.get(key);
        fromScripts.set(key, {
          cmd: commands[m[4]],
          permissive: !m[3],
          versions: [...(known?.versions ?? []), i + 1],
        });
      }
    });
    const listed = new Map<string, { cmd: string; permissive: boolean; versions: number[] }>();
    for (const p of checkPolicies()) {
      listed.set(`${p.rel} ${p.name}`, {
        cmd: p.cmd,
        permissive: p.permissive,
        versions: p.versions,
      });
    }
    expect(Object.fromEntries(listed)).toEqual(Object.fromEntries(fromScripts));
  });

  it('names every table the scripts make', () => {
    const fromScripts = SOURCES.flatMap((source, i) =>
      [...source.matchAll(/create table if not exists ([a-z_.]+)/g)].map((m) => `${i + 1} ${m[1]}`),
    );
    const listed = [
      ...CHECK.matchAll(/\((\d+), '((?:public|almailbooks)\.[a-z_]+)', (?:true|false)\)/g),
    ].map((m) => `${m[1]} ${m[2]}`);
    expect(listed.sort()).toEqual(fromScripts.sort());
  });

  it('knows the kinds of record, the private ones and the features the app has', () => {
    expect(arrayIn('v_kinds')).toEqual([...DATA_TABLES]);
    expect(arrayIn('v_private_kinds')).toEqual([...PEOPLE_TABLES]);
    const kindsOf = (source: string) =>
      [
        ...[...source.matchAll(/add constraint records_tbl_check check \(tbl in \(([^)]*)\)\)/g)]
          .at(-1)![1]
          .matchAll(/'([^']+)'/g),
      ].map((m) => m[1]);
    const v16 = SOURCES[3];
    expect(arrayIn('v_v16_kinds')).toEqual(
      kindsOf(v16).filter((kind) => !kindsOf(SOURCES[0]).includes(kind)),
    );
    const features = readFileSync(join(__dirname, 'features.ts'), 'utf8');
    const union = /export type ServerFeature =([\s\S]*?'[a-z0-9_]+');/.exec(features)![1];
    const appFeatures = [...union.matchAll(/\| '([a-z0-9_]+)'/g)].map((m) => m[1]);
    expect(arrayIn('v_app_features')).toEqual(appFeatures);
    // The latest server_features() answers the same names.
    const latest = SOURCES.flatMap((source) => [
      ...source.matchAll(/function public\.server_features\(\)[\s\S]*?\$\$([\s\S]*?)\$\$/g),
    ]).at(-1)![1];
    expect([...latest.matchAll(/'([a-z0-9_]+)'/g)].map((m) => m[1])).toEqual(appFeatures);
  });

  it('expects the jobs the scripts schedule', () => {
    for (const [name, schedule, command] of scheduledJobs()) {
      expect(CHECK).toContain(`'${name}', '${schedule}'`);
      expect(CHECK).toContain(`'${command}'`);
    }
  });

  it('names, for each function’s grants, the scripts that set them', () => {
    const fromScripts = grantScripts();
    const overrides = new Map(
      [
        ...CHECK.matchAll(
          /\('((?:public|almailbooks)\.[a-z0-9_]+\([^)]*\))', '\{([\d,]+)\}'(?:::integer\[\])?\)/g,
        ),
      ].map((m) => [m[1], versionsOf(m[2])]),
    );
    const listed = checkFunctions();
    for (const sig of overrides.keys()) expect(listed.map((f) => f.sig)).toContain(sig);
    expect(
      Object.fromEntries(listed.map((f) => [f.sig, overrides.get(f.sig) ?? f.versions])),
    ).toEqual(Object.fromEntries([...fromScripts].map(([sig, g]) => [sig, g.scripts])));
    // Each of those scripts sets all of them: run again, it puts them right.
    for (const f of listed) {
      for (const script of fromScripts.get(f.sig)!.scripts) {
        const done = fromScripts.get(f.sig)!.by.get(script)!;
        const what = `${f.sig} in script ${script}`;
        expect(done.has('revoke public') && done.has('revoke anon'), what).toBe(true);
        if (f.access === 'app' || f.access === 'rls') {
          expect(done.has('grant authenticated'), what).toBe(true);
        }
        if (f.access === 'internal') expect(done.has('revoke authenticated'), what).toBe(true);
      }
    }
  });

  it('knows the body of every function as each script that defines it has it', async () => {
    // The scripts have no unusual spaces, so "[[:space:]]" means the same on every server.
    for (const source of SOURCES) {
      expect(source).not.toMatch(
        /[\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]/,
      );
    }
    expect(CHECK.replace(/\s+/g, ' ')).toContain(`b.hash = ${FINGERPRINT}`);
    const listed = checkFunctions();
    const expected: string[] = [];
    const h = await startDatabase(1, 0);
    for (let n = 1; n <= SOURCES.length; n++) {
      await h.db.exec(SOURCES[n - 1]);
      for (const f of listed.filter((f) => f.versions.includes(n))) {
        const [row] = await h.admin<{ hash: string }>(
          `select ${FINGERPRINT} as hash from pg_proc p where p.oid = to_regprocedure($1)`,
          [f.sig],
        );
        expected.push(`('${f.sig}', ${n}, '${row.hash}')`);
      }
    }
    // On a change to a script, paste these lines into bd in health-check.sql.
    expect(checkBodies().join(',\n'), 'bd in health-check.sql').toBe(expected.join(',\n'));
  }, 60_000);
});

/* -------------------------------------------------------------------------- */
/* What it says                                                               */
/* -------------------------------------------------------------------------- */

describe('after every script', () => {
  it('says OK everywhere but for what PGlite can’t have', async () => {
    const h = await startDatabase();
    const rows = await runCheck(h);
    expectOnlyStandInWarnings(rows);
    expect(summary(rows)).toMatchObject({ step: '14. Summary', check: '2 WARN', status: 'WARN' });
    // One row per check, few enough for the SQL editor's first 100.
    expect(rows.length).toBeLessThan(100);
    expect(new Set(rows.map((row) => `${row.step} ${row.check}`)).size).toBe(rows.length);
    // Every script's step is there, in order, and the summary last.
    const steps = rows.map(stepNo);
    expect(steps).toEqual([...steps].sort((a, b) => a - b));
    expect([...new Set(steps)]).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]);
  }, 60_000);

  it('says "All good" when pg_cron, pg_net and the email function are there too', async () => {
    const h = await startDatabase();
    await withSchedules(h);
    const rows = await runCheck(h);
    expect(notOk(rows), JSON.stringify(notOk(rows), null, 1)).toEqual([]);
    expect(summary(rows)).toMatchObject({ check: 'All good', status: 'OK' });
    for (const [name] of scheduledJobs()) {
      expect(rows.find((row) => row.check.startsWith(`Job ${name} `))?.detail).toMatch(
        /^It is on; its last run, .* UTC, succeeded\.$/,
      );
    }
  }, 60_000);

  it('runs the same after each script was run twice', async () => {
    const h = await startDatabase(2);
    expectOnlyStandInWarnings(await runCheck(h));
  }, 60_000);
});

describe('before the later scripts', () => {
  for (const ran of [4, 5, 6, 7, 8, 9]) {
    it(`after ${ran} scripts, says exactly the later ones are missing, in order`, async () => {
      const h = await startDatabase(1, ran);
      const rows = await runCheck(h);
      const missing = rows.filter((row) => row.status === 'MISSING' && row !== summary(rows));
      const later = Array.from({ length: 10 - ran }, (_, i) => ran + 1 + i);
      expect(missing.map(stepNo)).toEqual(later);
      for (const row of missing) {
        expect(row.check).toBe('Script has run');
        expect(row.detail).toMatch(/^This script has not run yet\. Run \d{14}_/);
        // That one, then each later one; none "again".
        expect(scriptsIn(row.detail)).toEqual(later.filter((n) => n >= stepNo(row)));
        expect(row.detail).not.toContain(' again');
      }
      expectOnlyStandInWarnings(rows, missing);
      expect(rows.filter((row) => row.status === 'FAIL')).toEqual([]);
      expect(summary(rows)).toMatchObject({
        status: 'MISSING',
        check: `${10 - ran} MISSING, 2 WARN`,
      });
      expect(scriptsIn(summary(rows).detail)).toEqual(later);
    }, 60_000);
  }

  it('says email alerts were never set up as a warning, with the scripts that set them up', async () => {
    const h = await databaseWith([1, 2, 4, 5, 6, 7, 8, 9, 10]);
    const rows = await runCheck(h);
    const email = rows.find((row) => row.step.startsWith('3.'))!;
    expect(email).toMatchObject({ check: 'Email alerts', status: 'WARN' });
    expect(email.detail).toContain('docs/email-alerts.md');
    expect(scriptsIn(email.detail)).toEqual([3, 7, 8, 9, 10]);
    // No email rows without the email alerts; nothing else is wrong.
    expect(rows.filter((row) => row.step.startsWith('12.'))).toEqual([]);
    expect(notOk(rows).map((row) => [row.step, row.check, row.status])).toEqual([
      ['3. Set-up: email_alerts', 'Email alerts', 'WARN'],
      ['11. Schedules (pg_cron)', 'pg_cron and pg_net', 'WARN'],
      ['14. Summary', '2 WARN', 'WARN'],
    ]);
    expect(summary(rows).detail).toContain('Every script but the optional email alerts has run.');
  }, 60_000);

  it('says what to run when the database has not been set up at all', async () => {
    const h = await startDatabase(1, 0);
    const rows = await runCheck(h);
    expect(rows.map((row) => [stepNo(row), row.status])).toEqual([
      [1, 'MISSING'],
      [2, 'MISSING'],
      [3, 'WARN'],
      [4, 'MISSING'],
      [5, 'MISSING'],
      [6, 'MISSING'],
      [7, 'MISSING'],
      [8, 'MISSING'],
      [9, 'MISSING'],
      [10, 'MISSING'],
      [14, 'MISSING'],
    ]);
    // The optional email alerts only in their own row, with what they need after them.
    expect(scriptsIn(summary(rows).detail)).toEqual([1, 2, 4, 5, 6, 7, 8, 9, 10]);
    expect(scriptsIn(rows.find((row) => row.step.startsWith('3.'))!.detail)).toEqual([
      3, 4, 5, 6, 7, 8, 9, 10,
    ]);
  }, 60_000);

  // Set-up scripts skipped: what the last row says leads to no FAIL or MISSING,
  // and the email alerts' own row then to nothing but what PGlite can't have.
  const skipped: [number[], number[]][] = [
    [[1, 4, 5, 6, 7, 8, 9, 10], [2]],
    [
      [1, 4, 5, 6, 7],
      [2, 8, 9, 10],
    ],
    [
      [1, 2, 4, 5, 6, 7, 8],
      [9, 10],
    ],
    [[1, 2, 4, 5, 6, 7, 8, 9], [10]],
  ];
  for (const [ran, fix] of skipped) {
    it(`with scripts ${ran.join(', ')}, says to run ${fix.join(', ')}, and that is enough`, async () => {
      const h = await databaseWith(ran);
      let rows = await runCheck(h);
      expect(scriptsIn(summary(rows).detail)).toEqual(fix);
      for (const n of fix) await h.db.exec(SOURCES[n - 1]);
      rows = await runCheck(h);
      expect(rows.filter((row) => row.status === 'FAIL' || row.status === 'MISSING')).toEqual([]);
      const email = rows.find((row) => row.step.startsWith('3.'))!;
      expect(email.status).toBe('WARN');
      expect(scriptsIn(email.detail)).toEqual([3, 7, 8, 9, 10]);
      expect(email.detail).toContain(
        `Run ${FILE_NAMES[2]}, then ${FILE_NAMES[6]} again, then ${FILE_NAMES[7]} again, then ${FILE_NAMES[8]} again, then ${FILE_NAMES[9]} again`,
      );
      for (const n of scriptsIn(email.detail)) await h.db.exec(SOURCES[n - 1]);
      expectOnlyStandInWarnings(await runCheck(h));
    }, 60_000);
  }
});

describe('an earlier script run again after the later ones', () => {
  // The script run again, and the scripts the check says to run, in order.
  const cases: [number, number[]][] = [
    [1, [2, 5, 7, 8, 9, 10]],
    [3, [7, 8, 9, 10]],
    [4, [8, 9, 10]],
    // Script 10 has the latest records_guard, can_delete_record, record_app,
    // change_kind and server_features (and the kinds of record): it alone puts
    // back what 5, 7, 8 and 9 did.
    [5, [10]],
    [6, [7, 8, 9, 10]],
    [7, [10]],
    [8, [10]],
    [9, [10]],
  ];
  for (const [again, fix] of cases) {
    it(`script ${again} run again: FAIL, then run ${fix.join(', ')} again`, async () => {
      const h = await startDatabase();
      await h.db.exec(SOURCES[again - 1]);
      const rows = await runCheck(h);
      const failed = rows.filter((row) => row.status === 'FAIL' && row !== summary(rows));
      expect(failed.length).toBeGreaterThan(0);
      expect(rows.filter((row) => row.status === 'MISSING')).toEqual([]);
      for (const row of failed) {
        // Only rows of the scripts that ran after it, or the privacy row.
        expect(stepNo(row) > again || row.step.startsWith('13.'), row.step).toBe(true);
        for (const n of scriptsIn(row.detail)) expect(fix).toContain(n);
        expect(row.detail).toMatch(/ again[ ,.(]/);
      }
      expect(summary(rows).status).toBe('FAIL');
      expect(scriptsIn(summary(rows).detail)).toEqual(fix);
      expect(summary(rows).detail).not.toMatch(/needs? more than a script/);

      // And once those have run, all is well again.
      for (const n of fix) await h.db.exec(SOURCES[n - 1]);
      expectOnlyStandInWarnings(await runCheck(h));
    }, 60_000);
  }

  it('script 2 run again changes nothing', async () => {
    const h = await startDatabase();
    await h.db.exec(SOURCES[1]);
    expectOnlyStandInWarnings(await runCheck(h));
  }, 60_000);

  it('tells what an older version of one function is, and which script brings it back', async () => {
    const guardOf = (source: string) =>
      /create or replace function almailbooks\.records_guard\(\)[\s\S]*?\$\$;/.exec(source)![0];
    const failedOf = (rows: Row[]) =>
      rows
        .filter((row) => row.status === 'FAIL' && row !== summary(rows))
        .map((row) => [row.step, row.check]);
    // records_guard as the Super Admin script left it, before people_alerts,
    // ai_assistant and warehouse_issues: the latest script that has it puts
    // it right.
    const h = await startDatabase();
    await h.db.exec(guardOf(SOURCES[4]));
    let rows = await runCheck(h);
    const failed = rows.filter((row) => row.status === 'FAIL' && row !== summary(rows));
    expect(failed.map((row) => [row.step, row.check])).toEqual([
      ['7. Phase 4: people_alerts', 'Functions are its latest version'],
      ['9. AI assistant: ai_assistant', 'Functions are its latest version'],
      ['10. Warehouses: warehouse_issues', 'Functions are its latest version'],
    ]);
    for (const row of failed) {
      expect(row.detail).toContain('almailbooks.records_guard (an older version)');
    }
    expect(scriptsIn(summary(rows).detail)).toEqual([10]);
    await h.db.exec(SOURCES[9]);
    expectOnlyStandInWarnings(await runCheck(h));
    // As people_alerts left it: the AI assistant's and the warehouses' scripts
    // are behind, and the latest puts it right.
    await h.db.exec(guardOf(SOURCES[6]));
    rows = await runCheck(h);
    expect(failedOf(rows)).toEqual([
      ['9. AI assistant: ai_assistant', 'Functions are its latest version'],
      ['10. Warehouses: warehouse_issues', 'Functions are its latest version'],
    ]);
    expect(scriptsIn(summary(rows).detail)).toEqual([10]);
    // As ai_assistant left it: only the warehouses' script is behind.
    await h.db.exec(guardOf(SOURCES[8]));
    rows = await runCheck(h);
    expect(failedOf(rows)).toEqual([
      ['10. Warehouses: warehouse_issues', 'Functions are its latest version'],
    ]);
    expect(scriptsIn(summary(rows).detail)).toEqual([10]);
    await h.db.exec(SOURCES[9]);
    expectOnlyStandInWarnings(await runCheck(h));
  }, 60_000);

  const WAREHOUSES = '10. Warehouses: warehouse_issues';

  it('says the AI assistant’s script is missing before it runs, and OK after', async () => {
    const h = await databaseWith([1, 2, 3, 4, 5, 6, 7, 8]);
    let rows = await runCheck(h);
    const ai = (all: Row[]) => all.filter((row) => row.step === '9. AI assistant: ai_assistant');
    expect(ai(rows)).toEqual([
      {
        step: '9. AI assistant: ai_assistant',
        check: 'Script has run',
        status: 'MISSING',
        detail: `This script has not run yet. Run ${FILE_NAMES[8]}, then ${FILE_NAMES[9]} (in this order).`,
      },
    ]);
    expect(
      rows.find(
        (row) => row.step.startsWith('8.') && row.check === 'What server_features() answers',
      )?.detail,
    ).toBe('It answers staffing_costings.');
    expect(summary(rows)).toMatchObject({ check: '2 MISSING, 2 WARN', status: 'MISSING' });
    await h.db.exec(SOURCES[8]);
    rows = await runCheck(h);
    expect(ai(rows).map((row) => [row.check, row.status])).toEqual([
      ['Functions', 'OK'],
      ['Functions are its latest version', 'OK'],
      ['What server_features() answers', 'OK'],
      ['Who may use what (grants)', 'OK'],
    ]);
    expect(ai(rows).find((row) => row.check === 'What server_features() answers')?.detail).toBe(
      'It answers ai_assistant.',
    );
    // Only the warehouses' script is left, and nothing else is wrong.
    const left = rows.filter((row) => row.step === WAREHOUSES);
    expect(left.map((row) => [row.check, row.status])).toEqual([['Script has run', 'MISSING']]);
    expectOnlyStandInWarnings(rows, left);
    await h.db.exec(SOURCES[9]);
    expectOnlyStandInWarnings(await runCheck(h));
  }, 60_000);

  it('says the warehouses’ script is missing before it runs, OK after, and behind once the AI assistant’s runs again', async () => {
    const h = await databaseWith([1, 2, 3, 4, 5, 6, 7, 8, 9]);
    let rows = await runCheck(h);
    const warehouses = (all: Row[]) => all.filter((row) => row.step === WAREHOUSES);
    expect(warehouses(rows)).toEqual([
      {
        step: WAREHOUSES,
        check: 'Script has run',
        status: 'MISSING',
        detail: `This script has not run yet. Run ${FILE_NAMES[9]}.`,
      },
    ]);
    // Before it, the cloud takes every kind of record but items issued, and
    // that is no problem yet.
    expect(
      rows.find(
        (row) => row.step.startsWith('8.') && row.check === 'Kinds of record the cloud takes',
      ),
    ).toMatchObject({
      status: 'OK',
      detail: 'The cloud takes the kind of record this script adds: staffingCostings.',
    });
    expect(summary(rows)).toMatchObject({ check: '1 MISSING, 2 WARN', status: 'MISSING' });
    expect(summary(rows).detail).toBe(
      `Run ${FILE_NAMES[9]}. Then run this check again. ` +
        'The WARN rows say what is off and what to do; nothing in them stops the app.',
    );
    expectOnlyStandInWarnings(rows, warehouses(rows));

    await h.db.exec(SOURCES[9]);
    rows = await runCheck(h);
    expect(warehouses(rows).map((row) => [row.check, row.status])).toEqual([
      ['Functions', 'OK'],
      ['Functions are its latest version', 'OK'],
      ['Kinds of record the cloud takes', 'OK'],
      ['What server_features() answers', 'OK'],
      ['Who may use what (grants)', 'OK'],
    ]);
    const by = (check: string) => warehouses(rows).find((row) => row.check === check)?.detail;
    expect(by('Kinds of record the cloud takes')).toBe(
      `The cloud takes all ${DATA_TABLES.length} kinds of record the app syncs.`,
    );
    expect(by('What server_features() answers')).toBe(
      `It answers every name the app knows: ${[...arrayIn('v_app_features')].sort().join(', ')}.`,
    );
    expect(arrayIn('v_kinds')).toContain('stockIssues');
    expect(arrayIn('v_app_features')).toContain('stock_issues');
    expectOnlyStandInWarnings(rows);

    // The AI assistant's script run again puts back its records_guard and
    // server_features: run the warehouses' script again after it.
    await h.db.exec(SOURCES[8]);
    rows = await runCheck(h);
    const failed = rows.filter((row) => row.status === 'FAIL' && row !== summary(rows));
    expect(failed.map((row) => [row.step, row.check])).toEqual([
      [WAREHOUSES, 'Functions are its latest version'],
      [WAREHOUSES, 'What server_features() answers'],
    ]);
    expect(failed[0].detail).toContain('almailbooks.records_guard (an older version)');
    expect(failed[1].detail).toContain('stock_issues (not answered)');
    for (const row of failed) expect(row.detail).toContain(`Run ${FILE_NAMES[9]} again.`);
    expect(summary(rows)).toMatchObject({ check: '2 FAIL, 2 WARN', status: 'FAIL' });
    expect(summary(rows).detail).toBe(
      `Run ${FILE_NAMES[9]} again. Then run this check again. ` +
        'The WARN rows say what is off and what to do; nothing in them stops the app.',
    );
    expect(rows.filter((row) => row.status === 'MISSING')).toEqual([]);
    await h.db.exec(SOURCES[9]);
    expectOnlyStandInWarnings(await runCheck(h));
  }, 60_000);

  /** company_books_changed as the Super Admin script had it before its last fixes. */
  function olderBooksChanged(): string {
    const definition =
      /create or replace function almailbooks\.company_books_changed\([\s\S]*?\$\$;/.exec(
        SOURCES[4],
      )![0];
    const older = definition
      .replace(
        / or not almailbooks\.json_same\(\s*nullif\(p_old #> '\{kuwait,wamdPhone\}'[\s\S]*?\)\s*\) or exists/,
        ' or exists',
      )
      .replace(`'bankAccount', 'emailTemplates', `, '');
    expect(older).not.toContain('wamdPhone');
    return older;
  }

  it('finds a function an older copy of its script left, and which scripts put it right', async () => {
    const h = await startDatabase();
    await h.db.exec(olderBooksChanged());
    const rows = await runCheck(h);
    const failed = rows.filter((row) => row.status === 'FAIL' && row !== summary(rows));
    expect(failed.map((row) => [row.step, row.check])).toEqual([
      ['5. Phase 3: super_admin_approvals', 'Functions are its latest version'],
    ]);
    expect(failed[0].detail).toContain(
      'almailbooks.company_books_changed (not as the script has it)',
    );
    expect(failed[0].detail).toContain('an older copy of this script was run');
    expect(scriptsIn(summary(rows).detail)).toEqual([5, 7, 8, 9, 10]);
    for (const n of [5, 7, 8, 9, 10]) await h.db.exec(SOURCES[n - 1]);
    expectOnlyStandInWarnings(await runCheck(h));
  }, 60_000);

  it('takes a body pasted with other line ends, spacing or comments as the same', async () => {
    const h = await startDatabase();
    const definition =
      /create or replace function almailbooks\.company_books_changed\([\s\S]*?\$\$;/.exec(
        SOURCES[4],
      )![0];
    await h.db.exec(
      definition
        .replace('select exists (', 'select exists ( -- a note pasted along\n')
        .replace(/\n/g, '  \r\n\t'),
    );
    expectOnlyStandInWarnings(await runCheck(h));
  }, 60_000);
});

describe('what goes wrong besides the scripts', () => {
  /** A company with one manpower costing: the fourth script can't run again then. */
  async function withCosting(h: Harness) {
    const owner = await h.user('owner-costing@example.com');
    await h.rpc(owner, 'create_company', { p_id: 'costing-company', p_name: 'Costing' });
    await h.rpc(owner, 'push_records', {
      p_company: 'costing-company',
      p_changes: JSON.stringify([
        {
          tbl: 'companies',
          id: 'costing-company',
          data: { id: 'costing-company', companyId: 'costing-company' },
        },
        {
          tbl: 'staffingCostings',
          id: 'cost-1',
          data: { id: 'cost-1', companyId: 'costing-company', posts: [] },
        },
      ]),
    });
  }

  /** What only the fourth script makes, changed by hand: one of its rules and a grant. */
  async function breakTablesV16(h: Harness) {
    await h.admin(`drop policy "People data: kept from staff and viewers" on storage.objects`);
    await h.admin(`grant execute on function almailbooks.document_is_private(jsonb) to anon`);
  }

  it('never asks for tables_v16 again once there are manpower costings', async () => {
    const h = await startDatabase();
    await withCosting(h);
    await breakTablesV16(h);
    // It couldn't: it stops at the kinds of record, and changes nothing.
    await expect(h.db.exec(SOURCES[3])).rejects.toThrow(/records_tbl_check/);
    const rows = await runCheck(h);
    const failed = rows.filter((row) => row.status === 'FAIL' && row !== summary(rows));
    expect(failed.map((row) => [row.step, row.check])).toEqual([
      ['4. Phase 0-2: tables_v16', 'Row-level security rules'],
      ['4. Phase 0-2: tables_v16', 'Who may use what (grants)'],
      ['13. Data and privacy', "Staff and viewers can't read payroll and people data"],
    ]);
    for (const row of rows) expect(row.detail).not.toContain(FILE_NAMES[3]);
    for (const row of failed) {
      expect(scriptsIn(row.detail)).toEqual([]);
      expect(row.detail).toContain('ask the developer');
    }
    expect(failed[0].detail).toContain('now that there are manpower costings');
    expect(scriptsIn(summary(rows).detail)).toEqual([]);
    expect(summary(rows).detail).toContain('3 FAIL rows need more than a script');
  }, 60_000);

  /** A company with items issued: neither the fourth nor the eighth script can run again then. */
  async function withIssue(h: Harness) {
    const owner = await h.user('owner-issues@example.com');
    await h.rpc(owner, 'create_company', { p_id: 'issues-company', p_name: 'Issues' });
    await h.rpc(owner, 'push_records', {
      p_company: 'issues-company',
      p_changes: JSON.stringify([
        {
          tbl: 'companies',
          id: 'issues-company',
          data: { id: 'issues-company', companyId: 'issues-company' },
        },
        {
          tbl: 'stockIssues',
          id: 'issue-1',
          data: { id: 'issue-1', companyId: 'issues-company', number: 'SI-0001', lines: [] },
        },
      ]),
    });
    expect(await h.admin(`select r.id from public.records r where r.tbl = 'stockIssues'`)).toEqual([
      { id: 'issue-1' },
    ]);
  }

  /**
   * What only the eighth script makes, changed by hand: one of its rules
   * gone, and record_is_private as the fourth script had it.
   */
  async function breakStaffingCostings(h: Harness) {
    await h.admin(
      `drop policy "Manpower costings: kept from staff and viewers" on public.deleted_records`,
    );
    await h.db.exec(
      /create or replace function almailbooks\.record_is_private\([\s\S]*?\$\$;/.exec(
        SOURCES[3],
      )![0],
    );
  }

  const STUCK_8 =
    "What only the Phase 5 script (staffing_costings) sets up can't be put back by running it " +
    'again now that there are items issued (it would take them out of the kinds of record the ' +
    'cloud takes, so it stops with an error about records_tbl_check): ask the developer for a fix.';

  it('never asks for staffing_costings again once there are items issued', async () => {
    const h = await startDatabase();
    await withIssue(h);
    await breakStaffingCostings(h);
    // Neither could: each stops at the kinds of record, and changes nothing.
    for (const n of [4, 8]) {
      await expect(h.db.exec(SOURCES[n - 1])).rejects.toThrow(/records_tbl_check/);
    }
    const rows = await runCheck(h);
    const failed = rows.filter((row) => row.status === 'FAIL' && row !== summary(rows));
    expect(failed.map((row) => [row.step, row.check])).toEqual([
      ['8. Phase 5: staffing_costings', 'Functions are its latest version'],
      ['8. Phase 5: staffing_costings', 'Row-level security rules'],
      ['8. Phase 5: staffing_costings', 'Payroll and people data are private'],
      ['13. Data and privacy', "Staff and viewers can't read payroll and people data"],
    ]);
    expect(failed[0].detail).toContain('almailbooks.record_is_private (an older version)');
    expect(failed[1].detail).toContain(
      '"Manpower costings: kept from staff and viewers" on public.deleted_records (missing)',
    );
    expect(failed[2].detail).toContain('staffingCostings (not private)');
    // Neither script is asked for anywhere, not even to schedule the jobs.
    for (const row of rows) {
      expect(row.detail).not.toContain(FILE_NAMES[3]);
      expect(row.detail).not.toContain(FILE_NAMES[7]);
    }
    for (const row of failed) {
      expect(scriptsIn(row.detail)).toEqual([]);
      expect(row.detail).toContain(STUCK_8);
    }
    expect(scriptsIn(summary(rows).detail)).toEqual([]);
    expect(summary(rows).detail).toContain('4 FAIL rows need more than a script');
  }, 60_000);

  it('never asks for tables_v16 again once there are items issued, nor with costings too', async () => {
    const h = await startDatabase();
    await withIssue(h);
    await breakTablesV16(h);
    let rows = await runCheck(h);
    const failedOf = (all: Row[]) =>
      all.filter((row) => row.status === 'FAIL' && row !== summary(all));
    expect(failedOf(rows).map((row) => [row.step, row.check])).toEqual([
      ['4. Phase 0-2: tables_v16', 'Row-level security rules'],
      ['4. Phase 0-2: tables_v16', 'Who may use what (grants)'],
      ['13. Data and privacy', "Staff and viewers can't read payroll and people data"],
    ]);
    for (const row of rows) {
      expect(row.detail).not.toContain(FILE_NAMES[3]);
      expect(row.detail).not.toContain(FILE_NAMES[7]);
    }
    for (const row of failedOf(rows)) {
      expect(scriptsIn(row.detail)).toEqual([]);
      expect(row.detail).toContain(
        "What only the Phase 0-2 script (tables_v16) sets up can't be put back by running it " +
          'again now that there are items issued (it would take them out of the kinds of record ' +
          'the cloud takes, so it stops with an error about records_tbl_check): ask the ' +
          'developer for a fix.',
      );
    }
    expect(scriptsIn(summary(rows).detail)).toEqual([]);
    expect(summary(rows).detail).toContain('3 FAIL rows need more than a script');
    // With manpower costings as well, both reasons are said.
    await withCosting(h);
    rows = await runCheck(h);
    expect(failedOf(rows)).toHaveLength(3);
    for (const row of failedOf(rows)) {
      expect(row.detail).toContain('now that there are manpower costings and items issued (');
      expect(scriptsIn(row.detail)).toEqual([]);
    }
  }, 60_000);

  // With items issued, an earlier script run again is put right without
  // staffing_costings: the warehouses' script puts back all it replaced.
  const withIssues: [number, number[]][] = [
    [3, [7, 9, 10]],
    [6, [7, 9, 10]],
  ];
  for (const [again, fix] of withIssues) {
    it(`with items issued, script ${again} run again: run ${fix.join(', ')} again, and that is enough`, async () => {
      const h = await startDatabase();
      await withIssue(h);
      await h.db.exec(SOURCES[again - 1]);
      let rows = await runCheck(h);
      expect(summary(rows).status).toBe('FAIL');
      expect(scriptsIn(summary(rows).detail)).toEqual(fix);
      expect(summary(rows).detail).not.toMatch(/needs? more than a script/);
      for (const row of rows) expect(row.detail).not.toContain(FILE_NAMES[7]);
      for (const n of fix) await h.db.exec(SOURCES[n - 1]);
      rows = await runCheck(h);
      expectOnlyStandInWarnings(rows);
      // The scripts that schedule the jobs once pg_cron is on: without the eighth either.
      const cron = rows.find((row) => row.check === 'pg_cron and pg_net')!.detail;
      expect(scriptsIn(cron)).toEqual([3, 6, 7, 9, 10]);
      expect(cron).toContain(
        `, then ${FILE_NAMES[8]} again, then ${FILE_NAMES[9]} again (in this order).`,
      );
    }, 60_000);
  }

  it('asks the developer when the eighth script’s own objects are gone and there are items issued', async () => {
    const h = await startDatabase();
    await withIssue(h);
    // What says it ran: as if it never had.
    await h.admin(`drop policy "Manpower costings: kept from staff and viewers" on public.records`);
    const rows = await runCheck(h);
    expect(rows.filter((row) => row.step.startsWith('8.'))).toEqual([
      {
        step: '8. Phase 5: staffing_costings',
        check: 'Script has run',
        status: 'FAIL',
        detail: `This script's own objects are missing, as if it never ran. ${STUCK_8}`,
      },
    ]);
    for (const row of rows) expect(row.detail).not.toContain(FILE_NAMES[7]);
    expect(summary(rows)).toMatchObject({ check: '1 FAIL, 2 WARN', status: 'FAIL' });
    expect(scriptsIn(summary(rows).detail)).toEqual([]);
    expect(summary(rows).detail).toContain('1 FAIL row needs more than a script');
  }, 60_000);

  it('schedules the clean-up of deletion markers again with warehouse_issues once there are items issued', async () => {
    const job = (all: Row[], name: string) =>
      all.find((row) => row.check.startsWith(`Job ${name} `))!;
    // The warehouses' script schedules it too, and it can always run again.
    let h = await startDatabase();
    await withSchedules(h);
    await withIssue(h);
    await h.admin(`delete from cron.job where jobname = 'almailbooks-purge-deleted-records'`);
    let rows = await runCheck(h);
    expect(job(rows, 'almailbooks-purge-deleted-records').status).toBe('FAIL');
    expect(scriptsIn(job(rows, 'almailbooks-purge-deleted-records').detail)).toEqual([10]);
    // Without email alerts too, never the eighth script.
    h = await databaseWith([1, 2, 4, 5, 6, 7, 8, 9, 10]);
    await withIssue(h);
    await h.db.exec(CRON_STAND_IN);
    rows = await runCheck(h);
    const purge = job(rows, 'almailbooks-purge-deleted-records');
    expect(purge.status).toBe('FAIL');
    expect(purge.detail).toContain('It is not scheduled');
    expect(purge.detail).not.toContain(STUCK_8);
    expect(scriptsIn(purge.detail)).toEqual([10]);
    // The change feed's jobs: its script again, and those after it but the eighth.
    for (const name of ['maham-change-notifications', 'maham-change-feed-purge']) {
      expect(job(rows, name).status).toBe('FAIL');
      expect(scriptsIn(job(rows, name).detail)).toEqual([6, 7, 9, 10]);
    }
    expect(scriptsIn(summary(rows).detail)).toEqual([6, 7, 9, 10]);
    expect(summary(rows).detail).not.toContain('needs more than a script');
    // The script it names schedules it as the earlier ones do.
    expect(SOURCES[9]).toContain(
      "cron.schedule(\n      'almailbooks-purge-deleted-records',\n      '17 3 * * *',\n      'select almailbooks.purge_all_deleted_records()'\n    )",
    );
  }, 60_000);

  it('asks for tables_v16 again, then staffing_costings, while there are no costings', async () => {
    const h = await startDatabase();
    await breakTablesV16(h);
    const rows = await runCheck(h);
    expect(scriptsIn(summary(rows).detail)).toEqual([4, 8, 9, 10]);
    expect(summary(rows).detail).not.toMatch(/needs? more than a script/);
    for (const n of [4, 8, 9, 10]) await h.db.exec(SOURCES[n - 1]);
    expectOnlyStandInWarnings(await runCheck(h));
  }, 60_000);

  it('asks the developer for grants only the first script sets', async () => {
    const h = await startDatabase();
    await h.admin(
      `revoke execute on function almailbooks.can_write_record(text, text, jsonb) from authenticated`,
    );
    const rows = await runCheck(h);
    const failed = rows.filter((row) => row.status === 'FAIL' && row !== summary(rows));
    expect(failed.map((row) => [row.step, row.check])).toEqual([
      ['1. First setup: almailbooks_cloud', 'Who may use what (grants)'],
    ]);
    expect(failed[0].detail).toContain(
      "almailbooks.can_write_record (signed-in members can't run it)",
    );
    // The first script named only as the one never to run again.
    expect(failed[0].detail).toContain(`never run ${FILE_NAMES[0]} again): ask the developer`);
    expect(scriptsIn(failed[0].detail)).toEqual([1]);
    expect(scriptsIn(summary(rows).detail)).toEqual([]);
    expect(summary(rows).detail).toContain('1 FAIL row needs more than a script');
  }, 60_000);

  it('says how to make the bucket private again', async () => {
    const h = await startDatabase();
    await h.admin(`update storage.buckets set public = true where id = 'company-files'`);
    const rows = await runCheck(h);
    const failed = rows.filter((row) => row.status === 'FAIL' && row !== summary(rows));
    expect(failed).toEqual([
      expect.objectContaining({
        step: '1. First setup: almailbooks_cloud',
        check: 'Storage: bucket company-files and its rules',
      }),
    ]);
    expect(failed[0].detail).toBe(
      'Not right: bucket company-files (public: anyone with a link could download its files). ' +
        'In Storage, edit the bucket company-files and turn Public bucket off.',
    );
    expect(summary(rows).detail).toContain('1 FAIL row needs more than a script');
  }, 60_000);

  it('finds a rule added by hand, a public bucket and a role that bypasses the rules', async () => {
    const h = await startDatabase();
    await h.admin(
      `create policy "Everyone reads" on public.records for select to authenticated using (true)`,
    );
    await h.admin(`update storage.buckets set public = true where id = 'company-files'`);
    await h.admin(`alter role authenticated bypassrls`);
    const rows = await runCheck(h);
    const by = (check: string) => rows.find((row) => row.check === check)!;
    expect(by("Rules added by hand to the app's tables")).toMatchObject({
      status: 'FAIL',
      detail: expect.stringContaining('"Everyone reads" on public.records (adds access)'),
    });
    expect(by('Storage: bucket company-files and its rules')).toMatchObject({
      status: 'FAIL',
      detail: expect.stringContaining('bucket company-files (public'),
    });
    const privacy = by("Staff and viewers can't read payroll and people data");
    expect(privacy.status).toBe('FAIL');
    expect(privacy.detail).toContain('the role authenticated bypasses row-level security');
    expect(privacy.detail).toContain('"Everyone reads" on public.records was added by hand');
    expect(summary(rows).detail).toMatch(/FAIL rows need more than a script/);
  }, 60_000);

  it('finds grants changed by hand', async () => {
    const h = await startDatabase();
    await h.admin(`grant execute on function public.server_features() to anon`);
    await h.admin(`grant update on public.profiles to authenticated`);
    await h.admin(`revoke execute on function public.push_records(text, jsonb) from authenticated`);
    const rows = await runCheck(h);
    const grants = rows.filter(
      (row) => row.check === 'Who may use what (grants)' && row.status === 'FAIL',
    );
    expect(grants.map((row) => row.step)).toEqual([
      '1. First setup: almailbooks_cloud',
      '4. Phase 0-2: tables_v16',
    ]);
    expect(grants[0].detail).toContain("public.push_records (signed-in members can't run it)");
    expect(grants[0].detail).toContain('public.profiles for authenticated (may also update)');
    expect(grants[0].detail).toContain('public.profiles.email for authenticated (may change it)');
    expect(grants[1].detail).toContain('public.server_features (anonymous visitors can run it)');
    expect(scriptsIn(grants[1].detail)).toEqual([10]);
  }, 60_000);

  it('reports each schedule: missing, off, failing, never run, or moved', async () => {
    const h = await startDatabase();
    await withSchedules(h);
    await h.admin(`delete from cron.job where jobname = 'maham-change-feed-purge'`);
    await h.admin(`update cron.job set active = false where jobname = 'maham-books-email-alerts'`);
    await h.admin(
      `update cron.job_run_details set status = 'failed'
       where jobid = (select jobid from cron.job where jobname = 'maham-change-notifications')`,
    );
    await h.admin(
      `delete from cron.job_run_details
       where jobid = (select jobid from cron.job where jobname = 'almailbooks-purge-deleted-records')`,
    );
    await h.admin(`insert into net._http_response (id, status_code) values (2, 401), (3, 500)`);
    const rows = await runCheck(h);
    const job = (name: string) => rows.find((row) => row.check.startsWith(`Job ${name} `))!;
    expect(job('maham-change-feed-purge')).toMatchObject({ status: 'FAIL' });
    expect(scriptsIn(job('maham-change-feed-purge').detail)).toEqual([6, 7, 8, 9, 10]);
    expect(job('maham-books-email-alerts')).toMatchObject({
      status: 'WARN',
      detail: expect.stringContaining('switched off'),
    });
    expect(job('maham-change-notifications')).toMatchObject({
      status: 'FAIL',
      detail: expect.stringContaining('ended "failed"'),
    });
    expect(job('almailbooks-purge-deleted-records')).toMatchObject({
      status: 'WARN',
      detail: expect.stringContaining('no run is recorded yet'),
    });
    expect(
      rows.find((row) => row.check === 'Recent calls to the email-alerts function'),
    ).toMatchObject({
      status: 'WARN',
      detail: expect.stringMatching(/^2 of the 3 calls .* failed \(401, 500\)/),
    });

    await h.admin(
      `update cron.job set schedule = '0 4 * * *' where jobname = 'almailbooks-purge-deleted-records'`,
    );
    await h.admin(
      `insert into cron.job_run_details (jobid, status, start_time)
       select jobid, 'succeeded', now() from cron.job where jobname = 'almailbooks-purge-deleted-records'`,
    );
    const moved = (await runCheck(h)).find((row) =>
      row.check.startsWith('Job almailbooks-purge-deleted-records '),
    )!;
    expect(moved).toMatchObject({ status: 'WARN' });
    expect(moved.detail).toContain('Its schedule is 0 4 * * *; the script sets 17 3 * * *.');
  }, 60_000);

  it('counts companies, owners, members and records, and finds old markers', async () => {
    const h = await startDatabase();
    const owner = await h.user('owner-count@example.com');
    await h.rpc(owner, 'create_company', { p_id: 'count-company-1', p_name: 'Counted' });
    await h.rpc(owner, 'push_records', {
      p_company: 'count-company-1',
      p_changes: JSON.stringify([
        {
          tbl: 'companies',
          id: 'count-company-1',
          data: { id: 'count-company-1', companyId: 'count-company-1' },
        },
        { tbl: 'employees', id: 'e1', data: { id: 'e1', companyId: 'count-company-1' } },
        { tbl: 'clients', id: 'c1', data: { id: 'c1', companyId: 'count-company-1' } },
        { tbl: 'clients', id: 'c2', data: { id: 'c2', companyId: 'count-company-1' } },
      ]),
    });
    await h.rpc(owner, 'push_records', {
      p_company: 'count-company-1',
      p_changes: JSON.stringify([{ tbl: 'clients', id: 'c2', deleted: true }]),
    });
    await h.admin(`update public.deleted_records set deleted_at = now() - interval '40 days'`);
    // A company left without an owner.
    await h.admin(`insert into public.companies (id, name) values ('ownerless-1', 'Nobody''s')`);
    const rows = await runCheck(h);
    const by = (check: string) => rows.find((row) => row.check === check)!;
    expect(by('Companies in the cloud').detail).toBe('2 companies.');
    expect(by('Each company has exactly one owner')).toMatchObject({
      status: 'FAIL',
      detail: expect.stringMatching(/^1 company has no owner and 0 more than one\./),
    });
    expect(by('Members by role').detail).toBe(
      '1 member: owner 1, admin 0, accountant 0, staff 0, viewer 0. 0 may approve besides the owners.',
    );
    expect(by('Records by kind')).toMatchObject({
      status: 'OK',
      detail:
        "3 records of 3 kinds, 1 of them payroll and people data. None is of a kind the app doesn't sync.",
    });
    expect(by('Deletion markers cleaned up')).toMatchObject({
      status: 'WARN',
      detail: expect.stringMatching(/^1 of the 1 deletion markers are older than 30 days/),
    });
  }, 60_000);
});

describe('read-only and private', () => {
  /** Everything a script could change: the catalog, grants, schedules and every row count. */
  async function snapshot(h: Harness): Promise<string> {
    const [catalog] = await h.admin<{ s: unknown }>(`
      with own as (
        select n.oid from pg_namespace n
        where n.nspname not like 'pg_temp%' and n.nspname not like 'pg_toast_temp%'
      )
      select jsonb_build_object(
        'class', (select jsonb_agg(jsonb_build_array(c.oid, c.relname, c.relkind, c.relacl::text,
            c.relrowsecurity, c.relforcerowsecurity, c.relowner) order by c.oid)
          from pg_class c where c.relnamespace in (select oid from own)),
        'proc', (select jsonb_agg(jsonb_build_array(p.oid, p.proname, md5(p.prosrc), p.proacl::text,
            p.proconfig, p.prosecdef) order by p.oid)
          from pg_proc p where p.pronamespace in (select oid from own)),
        'policy', (select jsonb_agg(jsonb_build_array(x.oid, x.polname, x.polcmd, x.polpermissive,
            x.polroles::text, pg_get_expr(x.polqual, x.polrelid), pg_get_expr(x.polwithcheck, x.polrelid))
            order by x.oid) from pg_policy x),
        'trigger', (select jsonb_agg(jsonb_build_array(t.oid, t.tgname, t.tgenabled, t.tgfoid) order by t.oid)
          from pg_trigger t),
        'constraint', (select jsonb_agg(jsonb_build_array(c.oid, c.conname, pg_get_constraintdef(c.oid),
            c.convalidated) order by c.oid) from pg_constraint c where c.connamespace in (select oid from own)),
        'routine_grants', (select jsonb_agg(jsonb_build_array(g.grantee, g.specific_schema, g.specific_name,
            g.privilege_type) order by g.grantee, g.specific_schema, g.specific_name)
          from information_schema.role_routine_grants g
          -- The check's own helpers, gone with the connection.
          where g.specific_schema not like 'pg_temp%'),
        'table_grants', (select jsonb_agg(jsonb_build_array(g.grantee, g.table_schema, g.table_name,
            g.privilege_type) order by g.grantee, g.table_schema, g.table_name, g.privilege_type)
          from information_schema.table_privileges g),
        'extensions', (select jsonb_agg(e.extname order by e.extname) from pg_extension e),
        'settings', jsonb_build_array(current_setting('transaction_read_only'), current_setting('search_path')),
        'sequences', jsonb_build_array(
          (select last_value from public.records_rev_seq),
          (select last_value from public.change_events_id_seq)
        )
      ) as s`);
    const tables = await h.admin<{ name: string }>(`
      select format('%I.%I', n.nspname, c.relname) as name
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where c.relkind in ('r', 'p')
        and n.nspname in ('public', 'almailbooks', 'storage', 'auth', 'cron', 'net')
      order by 1`);
    const counts: Record<string, unknown> = {};
    for (const { name } of tables) {
      const [row] = await h.admin<{ n: number; h: string }>(
        `select count(*)::int as n, coalesce(md5(string_agg(t::text, ',' order by t::text)), '') as h from ${name} t`,
      );
      counts[name] = row;
    }
    return JSON.stringify({ catalog: catalog.s, counts });
  }

  it('changes nothing, run twice, with data, schedules and team in place', async () => {
    const h = await startDatabase();
    await withSchedules(h);
    const owner = await h.user('owner-ro@example.com');
    await h.rpc(owner, 'create_company', { p_id: 'readonly-company', p_name: 'Read only' });
    await h.rpc(owner, 'push_records', {
      p_company: 'readonly-company',
      p_changes: JSON.stringify([
        {
          tbl: 'companies',
          id: 'readonly-company',
          data: {
            id: 'readonly-company',
            companyId: 'readonly-company',
            numbering: { invoice: { next: 7, reset: 'never' } },
          },
        },
        {
          tbl: 'approvals',
          id: 'a1',
          data: { id: 'a1', companyId: 'readonly-company', status: 'pending' },
        },
      ]),
    });
    const before = await snapshot(h);
    await runCheck(h);
    await runCheck(h);
    expect(await snapshot(h)).toBe(before);
  }, 60_000);

  it('makes the transaction read-only before it checks anything', async () => {
    const h = await startDatabase();
    let setting = '';
    let refused = '';
    await h.db
      .transaction(async (tx) => {
        // As one run in the SQL editor: the helpers, the check, then (were it there) a write.
        await tx.exec(CHECK);
        setting = (
          await tx.query<{ ro: string }>(`select current_setting('transaction_read_only') as ro`)
        ).rows[0].ro;
        await tx
          .query(`insert into public.companies (id, name) values ('should-not-be', 'No')`)
          .catch((error: Error) => {
            refused = error.message;
          });
      })
      .catch(() => undefined);
    expect(setting).toBe('on');
    expect(refused).toMatch(/read-only transaction/);
    expect(await h.admin(`select 1 from public.companies where id = 'should-not-be'`)).toEqual([]);
  }, 60_000);

  it('only makes helper functions of its own connection, and writes nothing in them', () => {
    // Statements outside the functions' bodies: the helpers in pg_temp, then one select.
    const outside = CHECK.replace(/--.*$/gm, '').replace(/\$(\w*)\$[\s\S]*?\$\1\$/g, '$$body$$');
    const statements = outside
      .split(';')
      .map((statement) => statement.trim())
      .filter(Boolean);
    expect(statements.at(-1)).toMatch(/^select o_step as step, o_check as "check"/);
    for (const statement of statements.slice(0, -1)) {
      expect(statement).toMatch(/^create or replace function pg_temp\.maham_[a-z_]+\(/);
    }
    // Inside them, with the text of messages left out: no statement that writes, and
    // what is run by name only reads.
    const code = CHECK.replace(/--.*$/gm, '').replace(/'(?:[^']|'')*'/g, "''");
    expect(code).not.toMatch(
      /\b(insert\s+into|update\s+[a-z_.]+\s+set|delete\s+from|truncate|grant\s|revoke\s|alter\s|drop\s|notify\s|copy\s|vacuum|analyze|lock\s|nextval|setval|http_post|cron\.(un)?schedule|reserve_number|run_email_alerts|run_change_notifications|purge_)/i,
    );
    for (const m of CHECK.matchAll(/execute\s+'([^']*)/g)) {
      expect(m[1]).toMatch(/^select /);
    }
  });

  it('never shows a secret, an email address, a name or a salary', async () => {
    const h = await startDatabase();
    await withSchedules(h);
    const secrets = [
      'owner.secret-person@example.com',
      'accountant.hidden@example.com',
      'Fatima Al-Secretname',
      'Hidden Company Name',
      '287041512345',
      'KW81CBKU0000000000001234560101',
      '98765432',
      '4321.987',
      'made-up-ref',
      'S3cretValueOfTheScheduleThatMustNeverShow0123456789',
    ];
    const owner = await h.user('owner.secret-person@example.com', { name: 'Fatima Al-Secretname' });
    const accountant = await h.user('accountant.hidden@example.com');
    await h.rpc(owner, 'create_company', { p_id: 'secret-company', p_name: 'Hidden Company Name' });
    const [invite] = await h.rpc<{ token: string }>(owner, 'create_invite', {
      p_company: 'secret-company',
      p_email: 'accountant.hidden@example.com',
      p_role: 'accountant',
    });
    await h.rpc(accountant, 'accept_invite', { p_token: invite.token });
    const rec = (tbl: string, id: string, data: Record<string, unknown>) => ({
      tbl,
      id,
      data: { id, companyId: 'secret-company', ...data },
    });
    await h.rpc(owner, 'push_records', {
      p_company: 'secret-company',
      p_changes: JSON.stringify([
        rec('companies', 'secret-company', { name: 'Hidden Company Name' }),
        rec('employees', 'emp-1', {
          name: 'Fatima Al-Secretname',
          civilId: '287041512345',
          iban: 'KW81CBKU0000000000001234560101',
          phone: '98765432',
          salary: 4321.987,
        }),
        rec('payRuns', 'run-1', { lines: [{ employeeId: 'emp-1', net: 4321.987 }] }),
        rec('staffingCostings', 'cost-1', { posts: [{ salary: 4321.987 }] }),
        rec('approvals', 'ap-1', {
          status: 'pending',
          reason: 'Fatima Al-Secretname',
          subjectTbl: 'payRuns',
        }),
      ]),
    });
    await h.admin(
      `update almailbooks.email_alerts_config set secret = 'S3cretValueOfTheScheduleThatMustNeverShow0123456789'`,
    );
    await h.admin(
      `insert into public.email_alerts (company_id, user_id, enabled, last_error, last_error_at)
       values ('secret-company', $1, true, 'Resend refused owner.secret-person@example.com', now())`,
      [owner],
    );
    await h.admin(
      `insert into net._http_response (id, status_code, content, error_msg)
       values (9, 500, 'Fatima Al-Secretname 4321.987', 'owner.secret-person@example.com')`,
    );
    const rows = await runCheck(h);
    // The seeded problems are found, as counts.
    expect(rows.find((row) => row.check === 'Morning email alerts')).toMatchObject({
      status: 'WARN',
    });
    const text = JSON.stringify(rows);
    for (const secret of secrets) expect(text, secret).not.toContain(secret);
    expect(text).not.toMatch(/@example\.com/);
  }, 60_000);
});

it('the first script is never in its advice', async () => {
  // The first script can't run again once there are records of the later kinds.
  const h = await startDatabase();
  await h.db.exec(readFileSync(MIGRATION, 'utf8'));
  const rows = await runCheck(h);
  for (const row of rows) expect(scriptsIn(row.detail)).not.toContain(1);
}, 60_000);
