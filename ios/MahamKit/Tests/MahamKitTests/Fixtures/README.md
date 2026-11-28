# Write parity fixtures

Each `writes-<area>.json` is written by `ios/scripts/web-fixtures/writes-<area>.gen.ts`,
which runs the web app's own write functions (src/db/*.ts) on a fake IndexedDB with
fixed ids and a fixed clock, and records every table before and after each scenario.
The Swift ports (MahamKit/Write) run the same scenarios through `WriteContext` and must
produce the same records (`WriteParity` in WriteFixtureSupport.swift).

Regenerate from the repository root:

    npx vitest run --config ios/scripts/web-fixtures/writes.gen.config.mjs
