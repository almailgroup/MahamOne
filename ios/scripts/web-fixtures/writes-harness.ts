// What every write fixture generator shares: fixed ids and a fixed clock, a
// fresh fake IndexedDB per scenario seeded with the records it starts from,
// and a dump of every table after the web's write function has run.
//
// A generator (writes-<area>.gen.ts) looks like:
//
//   import { vi } from 'vitest';
//   vi.mock('@/lib/ids', async (load) => ({
//     ...(await load<typeof import('@/lib/ids')>()),
//     ...(await import('./writes-ids')).fixedIds(),   // not the harness: it imports the database
//   }));
//   import { scenario, writeFixtures } from './writes-harness';
//   import { saveDocument } from '@/db/documents';
//
//   const out = [];
//   it('documents', async () => {
//     out.push(await scenario('a sent invoice', { now: '2026-11-28T09:00:00.000Z', before }, async () => {
//       await saveDocument(...);
//     }));
//     writeFixtures('documents', out);
//   });
//
// The Swift side (Tests/MahamKitTests/WriteFixtureSupport.swift) starts a
// WriteContext on `before` with the same ids (`WriteParity.ids`) and clock,
// runs the port, and compares every table with `after`.
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { vi } from 'vitest';
import { db } from '@/db/db';
import { setActivityAuthor, setAuthorCompanies } from '@/db/author';

import { fixedId, fixedIds, idsUsed, resetIds } from './writes-ids';

export { fixedId, fixedIds };

export type Tables = Record<string, unknown[]>;

export interface Scenario {
  name: string;
  /** The moment of the action (`new Date()`), ISO. */
  now: string;
  /** Today on the device. */
  today: string;
  /** The signed-in person (activity `by`), when the company is in the cloud. */
  userId?: string;
  userName?: string;
  role?: string;
  /** What the action was asked, for the Swift side (free form, per area). */
  input: unknown;
  /** The action's first id is fixedId(idStart + 1) (ids before it went to the seed). */
  idStart: number;
  before: Tables;
  after: Tables;
  /** The error message when the web refused the action. */
  error?: string;
}

/** Every table of the database, each sorted by id. */
async function dump(): Promise<Tables> {
  const tables: Tables = {};
  for (const table of db.tables) {
    const rows = (await table.toArray()) as { id?: string }[];
    if (rows.length === 0) continue;
    tables[table.name] = rows.sort((a, b) => String(a.id ?? '').localeCompare(String(b.id ?? '')));
  }
  return tables;
}

/**
 * Runs one scenario: a fresh database holding `before`, ids counted from 1
 * and the clock stopped at `now`, then `action`; returns what every table
 * holds before and after (or the error the web raised).
 */
export async function scenario(
  name: string,
  setup: { now: string; today?: string; before?: Tables; input?: unknown; userId?: string; userName?: string; role?: string; seed?: () => Promise<void> },
  action: () => Promise<unknown>,
): Promise<Scenario> {
  await db.delete();
  await db.open();
  vi.useFakeTimers({ now: new Date(setup.now), toFake: ['Date'] });
  resetIds();
  for (const [table, rows] of Object.entries(setup.before ?? {})) {
    await db.table(table).bulkPut(rows);
  }
  if (setup.seed) await setup.seed();
  // The activity log names the signed-in person in a company kept in the cloud.
  if (setup.userId) {
    setActivityAuthor({ id: setup.userId, name: setup.userName ?? '' });
    setAuthorCompanies((await db.companies.toArray()).map((c) => c.id));
  } else {
    setActivityAuthor(null);
  }
  const before = await dump();
  const idStart = idsUsed();
  let error: string | undefined;
  try {
    await action();
  } catch (e) {
    error = e instanceof Error ? e.message : String(e);
  }
  const after = await dump();
  vi.useRealTimers();
  return {
    name,
    now: setup.now,
    today: setup.today ?? setup.now.slice(0, 10),
    ...(setup.userId ? { userId: setup.userId } : {}),
    ...(setup.userName ? { userName: setup.userName } : {}),
    ...(setup.role ? { role: setup.role } : {}),
    input: setup.input ?? null,
    idStart,
    before,
    after,
    ...(error ? { error } : {}),
  };
}

/** Writes Tests/MahamKitTests/Fixtures/writes-<area>.json. */
export function writeFixtures(area: string, scenarios: Scenario[]): void {
  const path = fileURLToPath(
    new URL(`../../MahamKit/Tests/MahamKitTests/Fixtures/writes-${area}.json`, import.meta.url),
  );
  writeFileSync(path, JSON.stringify({ area, scenarios }, null, 1) + '\n');
}
