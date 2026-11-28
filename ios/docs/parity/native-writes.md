# Saving natively: how every area ports the web's writes

The owner's rule: nothing in the app opens the web. Every action of Maham One works
natively, and a record saved on the iPhone is exactly what the web would have saved (the
web's devices recompute totals, statuses, stock and postings and rewrite whatever differs,
so a different record means conflicts and churn in the company's books).

## The pieces

- **`WriteContext`** (`MahamKit/Sources/MahamKit/Write/WriteContext.swift`): one user
  action's view of the company, as a Dexie transaction is on the web. `get(table, id)` and
  `all(table)` read the records with the action's own changes laid over them (Dexie order:
  by id); `put(table, record)` and `delete(table, id)` write; `newId()`, `shortId()`,
  `stamp` (`new Date().toISOString()`), `today`, `companyId`, `userId`, `role`.
  `logActivity(...)` is the port of `src/db/activity.ts` `logActivity`.
- **Ports** live in `MahamKit/Sources/MahamKit/Write/<Area>/`: each web write function
  (`src/db/*.ts`, and the `src/lib` rules they use) becomes a Swift function taking a
  `WriteContext` (and plain inputs), doing the same reads and writes in the same order,
  throwing the web's errors with the web's English messages (`WriteFailure`).
- **The app saves** with `model.one.write { ctx in try Port.saveX(ctx, …) }`
  (`App/Model/OneData.swift`). The sync engine applies the changes to the mirror and queues
  them for the cloud, all or nothing; its rules refuse what the web's outbox refuses
  (roles, approval rules, warehouses, letters) with the web's words.
- **`OneWritable.kinds`** (`App/Model/OneWritable.swift`) lists the tables the app may save.
  A table goes in only when every port that writes it passes its parity tests. Until then,
  the buttons that would change it stay hidden.

## Parity tests: the web's own outputs

1. A generator `ios/scripts/web-fixtures/writes-<area>.gen.ts` runs the web's real write
   functions on a fake IndexedDB (`writes-harness.ts`: `scenario(...)` with fixed ids from
   `fixedIds()` and a fixed clock, then `writeFixtures(area, scenarios)`). Run it from the
   repository root: `npx vitest run --config ios/scripts/web-fixtures/writes.gen.config.mjs writes-<area>`.
   It writes `ios/MahamKit/Tests/MahamKitTests/Fixtures/writes-<area>.json` (commit it).
2. A Swift test (`Tests/MahamKitTests/Write<Area>Tests.swift`) loads the scenarios
   (`WriteParity.scenarios("<area>")`), starts `scenario.context()` (same ids, same clock,
   on `before`), runs the port with `scenario.input`, and checks
   `WriteParity.assertMatches(scenario.applying(context.changes), scenario.after, scenario: scenario.name)`.
   A scenario where the web threw (`scenario.error`) must throw the same message and write nothing.
3. Cover what the web's own tests cover (`src/db/<area>.test.ts`): every action, the
   rounding edge cases, multi-currency, statuses, refusals.

The Swift tests run on Linux in CI (`swift test` in ios/MahamKit); there is no Swift
toolchain on the development machine, so write code that compiles first time.
