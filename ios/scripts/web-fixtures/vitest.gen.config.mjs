// Runs fixtures.gen.ts with the web app's own modules (Vite's import.meta.glob
// needs vitest, not plain tsx). From the repository root:
//   npx vitest run --config ios/scripts/web-fixtures/vitest.gen.config.mjs
//   python3 ios/scripts/web-fixtures/emit_swift.py ios/scripts/web-fixtures/fixtures.json \
//     ios/MahamKit/Tests/MahamKitTests/WebFixtures.swift
import { fileURLToPath } from 'node:url';

const here = fileURLToPath(new URL('.', import.meta.url));
export default {
  resolve: { alias: { '@': fileURLToPath(new URL('../../../src', import.meta.url)) } },
  test: { environment: 'node', globals: true, include: ['*.gen.ts'], root: here },
};
