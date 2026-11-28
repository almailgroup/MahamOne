// Set up for every write fixture generator (writes.gen.config.mjs), so each
// generator doesn't have to:
// - ids are handed out by writes-ids.ts (fixed, counted), not at random;
// - the outbox middleware is left out. It names each transaction's changes
//   with a short id (its group), which would take the next fixed id at the
//   first write of every transaction: the web's own bookkeeping, which the
//   iPhone's sync engine does its own way. Without it the ids count only the
//   records the web writes, so the Swift ports can hand out the same ones.
import { vi } from 'vitest';

vi.mock('@/lib/ids', async (load) => ({
  ...(await load<typeof import('@/lib/ids')>()),
  ...(await import('./writes-ids')).fixedIds(),
}));

vi.mock('@/cloud/outbox', async (load) => ({
  ...(await load<typeof import('@/cloud/outbox')>()),
  outboxMiddleware: () => ({ stack: 'dbcore', name: 'NoOutbox', create: () => ({}) }),
}));
