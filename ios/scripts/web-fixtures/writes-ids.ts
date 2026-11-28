// The ids a write scenario hands out, counted: kept apart from the harness
// (which imports the database, which imports @/lib/ids) so that mocking
// @/lib/ids with these doesn't import the database first:
//
//   vi.mock('@/lib/ids', async (load) => ({
//     ...(await load<typeof import('@/lib/ids')>()),
//     ...(await import('./writes-ids')).fixedIds(),
//   }));
let counter = 0;

/** Id number `n`: "00000001-0000-4000-8000-000000000000", … */
export function fixedId(n: number): string {
  return `${n.toString(16).padStart(8, '0')}-0000-4000-8000-000000000000`;
}

/** newId and shortId from the counter. */
export function fixedIds() {
  return {
    newId: () => fixedId(++counter),
    shortId: () => fixedId(++counter).replace(/-/g, '').slice(0, 12),
  };
}

/** Starts counting again from `start` (the next id is fixedId(start + 1)). */
export function resetIds(start = 0): void {
  counter = start;
}

/** How many ids have been handed out. */
export function idsUsed(): number {
  return counter;
}
