# Maham One's business rules: what the Swift port must reproduce

Paths are relative to `src/`. Counts are from November 2026.

The rules span about **31,000 lines** of pure TypeScript, plus about **8,000–10,000** lines
of rules inside the `db/` layer: roughly 40,000 lines for full parity.

There are 2,307 tests:

- 591 test pure `lib/` code and port to Swift Testing almost one to one.
- 585 test the `db/` layer against a fake IndexedDB and need an in-memory store in Swift.
- Good cross-platform fixtures: the golden suites (`lib/hr/leave-golden`, `db/leave-golden`,
  `db/payroll-approval-golden`) and `db/demo.test`, a 5,069-line demo company.

## How it's built

- **Pure rules** live in `lib/**`.
- **`db/*.ts`** mixes IndexedDB transactions with real rules: issuing, voiding, numbering,
  posting snapshots, approvals, stock sync. Swift needs this as a service layer.
- **Records** are JSON in `public.records`. Their shape is `db/types.ts` (3,062 lines).
  **Swift models must round-trip unknown fields and unknown enum values** (`lib/known.ts`
  `lookup`).
- **The ledger is computed on read** (`lib/accounting/ledger.ts`), never stored. Some stored
  values are caches: document `totals`, `status`, `paidAt` and `sentAt`; order
  `status`/`deliveryStatus`; `stockMovements`.
- **Web devices reconcile.** After each pull they recompute those caches and push any
  difference (see data-layer.md).
- **Money:** decimal.js-light, precision 40, rounding half away from zero. `dec(n)` goes
  through `String(n)`, so Swift must build `Decimal` from strings, never from `Double`. The
  ledger works in integer minor units (fils). Precision comes from `Intl`: KWD, BHD, OMR
  and JOD use 3 decimals.

## The modules, by area

### Foundations

- `lib/money.ts` (99): `dec`, `round`, `sum`, `currencyPrecision`, `normalizeDigits`,
  `parseAmount`, `toMinor`/`fromMinor`.
- `lib/dates.ts` (73): `occurrenceDate`, computed from the start date each time with no
  month-end drift.
- `lib/numbering.ts` (168, 7 tests): `periodKey`, `currentCounter`, `formatNumber`
  (placeholders `{counter}{year}{yy}{month}{day}{client}`), `allocateNumber`,
  `allocateFrom`.
- `lib/format.ts` (216, 17 tests): money, amount, quantity, percent, date; `isolateAmount`
  keeps amounts right-to-left safe.
- `lib/words.ts` (327, 6 tests): amount in words in English and Arabic, with gender
  agreement.
- `lib/kuwait.ts` (432, 10 tests): areas, banks, IBAN, civil ID check digit, phones,
  weekend, Hijri holidays.
- `lib/kuwait-rules.ts`: legal forms, cash limits.
- `lib/known.ts`, `ids.ts`, `geo.ts`, `units.ts`, `regions.ts`.
- `db/types.ts`, `db/defaults.ts`.
- `i18n/` (about 10,200 lines): `t`, `tp`, `msg`, `interpolate`, and the Arabic
  dictionaries.

Generated text is stored as an English key plus variables, and translated when shown.

### Sales documents

There are nine document types in one `InvoiceDocument` record.

**`lib/calc.ts`** (302, 22 tests): `calculate`. **Port its rounding order exactly:**

1. Each line's net is rounded.
2. The document discount is spread pro rata into each line's tax base.
3. Tax is grouped by name and rate (reverse charge kept apart) and rounded once per group.
4. Tax-inclusive prices are backed out to a net base.
5. Charges are taxed but not discounted.
6. Reverse charge is shown but kept out of the total.
7. Retention, then deposit, then balance.

**The other modules:**

- `lib/document-calc.ts`: `computeDocument`, tax exemption, retention on invoices and bills
  only.
- `lib/document-types.ts`.
- `lib/status.ts`: `STATUSES_BY_TYPE`, `issuedStatus`, `displayStatus` (overdue, expired,
  open), `settledStatus`.
- `lib/orders.ts` (16 tests): `lineProgress` (via `sourceLineId`), `orderStatus`,
  `deliveryStatusOf`, `copyLines`, `partDiscount`.
- `lib/retention.ts`.
- `lib/statements.ts`: `buildStatement`, aging, `creditCheck`, `exposureIncrease`.
- `lib/placeholders.ts`, `whatsapp.ts`, `email.ts`.
- `db/documents.ts` (1,186):
  - `draftDocument`, `paidAmount`, `applyTotals`;
  - `saveDocument`: checks the lock date, duplicates, number-on-issue and approvals, then
    syncs stock and refreshes orders;
  - `setDocumentStatus`: void and unvoid;
  - `deleteDocument`: voids instead when the document is issued;
  - `markSent`, `duplicateDocument`, `reissueDocument`;
  - `CONVERSIONS` and `convertDocument`.
- `db/orders.ts`, `db/posting.ts` (freezes the posting snapshot when a document is issued),
  `db/recurring.ts`, `db/retention.ts`, `db/credit.ts`.

### Payments and cheques

- `lib/payment-methods.ts`: methods, fees, providers, money accounts, cash limits.
- `lib/cheques.ts`.
- `lib/cheque-print.ts` + `cheque-layouts.ts` (31 tests).
- `db/payments.ts` (807):
  - allocations, unapplied amounts, validation, `savePayment`, `deletePayment`;
  - refuses over-allocation;
  - credit notes are applied as the method `credit_note`;
  - stamps `postingRules` = 2.
- `db/cheques.ts` (831): deposit, clear, return, cancel, replace; security cheques.
- `db/cheque-rules.ts`, `cheque-approvals.ts`, `cheque-print.ts`.
- `pdf/voucher/model.ts`.
- "Apply oldest first" (`autoApply`) is buried in `apps/books/pages/payments/form.tsx:273`.

### Purchases

- Bills, vendor credits and purchase orders reuse the sales modules.
- `db/purchases.ts`: expenses.
- `db/assets.ts` `billAssetLines`.
- Expense tax helpers `includedTax` and `reverseChargeTax` are in
  `features/purchases/expense-dialog.tsx`.

### Inventory

Inventory uses **weighted average costing (IAS 2), not FIFO**: one average per item across
all warehouses, replayed in date order.

- `lib/inventory/costing.ts` (13 tests): `costMovements`, `stockLevels`. `SOURCE_RANK`
  orders movements on the same day.
- `lib/inventory/sources.ts`: the movements a document makes, landed cost allocation.
- `lib/inventory/count.ts`.
- `db/inventory.ts` (1,188, 25 tests):
  - warehouses, `ensureStockAccounts` (1200, 5000, 5300);
  - `recost`, `syncDocumentStock`, `rebuildStock`;
  - stock entries, landed costs.
- `db/stock-issues.ts`, `db/product-images.ts`.

Stock movement ids are deterministic: `sm-` + `stableId(...)`, from `lib/ids.ts`.

### Accounting and reports

**`lib/accounting/ledger.ts`** (1,286, about 43 tests) is the posting engine:

- `buildLedger`, `postDocument`, `postPayment` (fees, cheque reversal dates, exchange
  differences), `postExpense`, `postJournal`;
- `allocate`: the remainder goes to the largest weight;
- `documentClearing`;
- `PAYMENT_POSTING_RULES`.

**The other modules:**

- `charts.ts` (the Kuwait IFRS chart, in Arabic and English), `account-types.ts`,
  `journal-kinds.ts`.
- `statements.ts`: P&L, balance sheet, trial balance, general ledger, IFRS statements,
  comparatives.
- `cash-flow.ts`, `asset-schedule.ts`.
- `vat.ts`: formats, periods, return boxes.
- `depreciation.ts`.
- `year-end.ts`: levies (statutory reserve 10% up to 50%, KFAS 1%, Zakat 1%, NLST 2.5%,
  15% income tax on the foreign share).
- `lib/reports.ts`: aging, tax, sales by client, payments.
- `lib/banking/*`: CSV and OFX import, matching, reconciliation.
- `db/accounting.ts`: lock date, accounts, journals, close year.
- `db/vat.ts`, `db/assets.ts`, `db/banking.ts`.
- `apps/books/features/dashboard/model.ts` (25 tests).
- `apps/books/features/reports/model.ts`.

### People and payroll

These follow Kuwait Labour Law 6/2010, as versioned rules.

**`lib/hr/payroll.ts`** (947, 41 tests):

- Rates: day rate = monthly ÷ 26; 8-hour day; overtime ×1.25 on a working day, ×1.5 on a
  rest day, ×2 on a holiday.
- Deductions: loans are capped at 10% of the wage, and all deductions together at 25%.
- PIFSS: employer 11.5%, employee 10.5%, capped at KD 2,750.
- Functions: `calculatePayLine`, `payRunTotals`, `payRunPostings`, provisions (2700 end of
  service, 2320 leave), `computeSettlement`.

**`lib/hr/eosi.ts`**, end-of-service indemnity:

- Article 51, monthly-paid: 15 days a year for 5 years, then one month a year, capped at 18
  months.
- Article 53, resignation: nothing before 3 years, ½ from 3 years, ⅔ from 5, all from 10.
- The PIFSS offset applies to Kuwaitis.

**`lib/hr/leave.ts`** (1,010, 47 tests): 30 days a year, accrual, sick-pay tiers (article
69), day counting with Friday and Saturday off plus Umm al-Qura holidays, balances.

**The other modules:**

- `lib/hr/employees.ts`, `salary-file.ts` (bank transfer files), `costing.ts` (manpower
  costing, 27 tests), `letters.ts`, `letter-templates.ts`, departments, job titles,
  nationalities.
- `db/payroll.ts` (2,297), `db/payroll-approvals.ts`, `db/people.ts`, `db/leave-openings.ts`,
  `db/costings.ts`, `db/letters.ts`.

### Compliance, CRM, approvals, alerts, AI, files, search, PDF

- `lib/compliance.ts` (1,110, 42 tests): papers, reminders, statutory deadlines, calendar.
- `db/renewals.ts`, `db/vehicles.ts`.
- `apps/crm/lib/pipeline.ts`.
- Approvals:
  - `db/approvals.ts` (744, 28 tests): `rulesInEffect`, `requestApproval`,
    `decideApproval`, `carryOutDecided`;
  - `features/approvals/*`.
- `cloud/roles.ts` (1,404): mirrors the SQL permissions.
- `alerts/collect.ts`, `topics.ts`, `changes.ts`; `suite/home/attention.ts`.
- `features/ai/*`: `scrub.ts` hides private details before anything leaves the device.
- `features/files/file-index.ts`.
- `features/search/*`: Arabic letter and digit folding, ranking.
- PDF:
  - models: `pdf/model.ts`, `labels.ts`, `template-resolve.ts`, `bidi.ts`;
    `pdf/statement/model.ts`; `pdf/costing-model.ts`;
  - the `pdf/templates/*.tsx` files (about 4,000 lines of react-pdf) must be re-rendered
    natively.

## Logic hidden in screen files (extract before porting)

| File | What to extract |
|---|---|
| `apps/books/pages/payments/form.tsx` | `autoApply` |
| `features/purchases/expense-dialog.tsx` | `includedTax`, `reverseChargeTax` |
| `features/clients/client-form.tsx` | `validateClient` |
| `features/people/employee-form.tsx` | `validateEmployee` |
| `features/company/bank-fields.tsx` | `ibanProblem` |
| `features/payroll/shared.tsx` | `runStatus`, `leaveDetailPay` |
| `apps/books/pages/assets/shared.tsx` | suggested accounts |
| `apps/books/features/documents/send-dialog.tsx` | payment link, email values |
| `features/renewals/expiry-reminders.tsx` | reminder rows |

Also `features/company/holidays.ts` and `taxes.ts`.

## Porting order

1. **Layer 0:** money, dates, known, ids, i18n (with the Arabic dictionaries), format, words,
   kuwait, the types (round-tripping), defaults, and the role checks (`roles.ts`).
2. **Reading invoices and quotes:** document-types, calc, document-calc, status, format.
   For PDFs: `pdf/labels`, `pdf/model`, a native renderer.
3. **Writing documents:**
   - numbering (with `reserve_number`), retention, orders, `creditCheck`, the posting
     snapshot, `db/documents` and `db/orders`.
   - For companies that keep stock: inventory sources, costing and `syncDocumentStock`.
     Otherwise the web's reconcile rewrites the stock.
   - Recurring.
4. **Payments and cheques:** payment-methods, `db/payments`, cheques, cheque rules, voucher.
5. **Books:** charts, ledger, statements, reports, dashboard, then VAT, assets, year-end,
   banking.
6. **Inventory screens.**
7. **People:** employees, holidays (Umm al-Qura), leave, end of service, payroll, salary
   file, letters, costing.
8. **Compliance and Today.**
9. **CRM.**
10. **Cross-cutting:** approvals (handling parked refusals), search, files, AI.

## Exactness traps

- **Money:** `NSDecimalNumber` with `.plain` rounding (half away from zero), built from
  strings. Keep the order of rounding in `calculate`, normalize -0, and keep the ledger in
  Int64 fils.
- **Dates:**
  - ISO date strings compare lexicographically.
  - `addMonths` clamps to the month end.
  - `daysBetween` counts calendar days.
  - Hijri holidays come from `Calendar(identifier: .islamicUmmAlQura)`.
- **Versioned behaviour:** keep `payment.postingRules`, the `doc.posting` snapshot, and the
  `lookup()` fallbacks for enum values from newer versions.
- **Generated text:** store an English key plus variables, never translated text.
