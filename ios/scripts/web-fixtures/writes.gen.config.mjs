// Runs the write fixture generators (writes-*.gen.ts) with the web app's own
// modules on a fake IndexedDB. From the repository root:
//   npx vitest run --config ios/scripts/web-fixtures/writes.gen.config.mjs
// Each writes ios/MahamKit/Tests/MahamKitTests/Fixtures/writes-<area>.json.
import { fileURLToPath } from 'node:url';

const here = fileURLToPath(new URL('.', import.meta.url));
export default {
  resolve: { alias: { '@': fileURLToPath(new URL('../../../src', import.meta.url)) } },
  test: {
    environment: 'node',
    globals: true,
    include: ['writes-*.gen.ts'],
    root: here,
    setupFiles: ['fake-indexeddb/auto'],
    // Dates and "today" as in Kuwait, where the company is.
    env: { TZ: 'Asia/Kuwait' },
    testTimeout: 120_000,
  },
};
