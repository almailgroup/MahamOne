# Maham One's data layer: what a native peer must do

This is the protocol the web app (`src/cloud`, `src/db`, `supabase/migrations`) follows. The
iPhone app must follow it exactly before it writes anything. Line numbers are as of
November 2026 and may drift; the function names are stable.

## The shape of it

The web app is **local-first**. Each device:

- keeps a full mirror of the company in IndexedDB (Dexie);
- writes there, and records each write in an outbox in the same transaction;
- pushes **whole records**.

The server enforces permissions and a few rules, then stamps `rev`, `updated_at` and
`updated_by`. Business logic runs on the client:

- totals and document status;
- stock movements and costing;
- numbering;
- cascades;
- carrying out approvals.

The ledger is never stored: `buildLedger` (`src/lib/accounting/ledger.ts`) derives it from
the records.

**Web devices reconcile.** After a pull, every non-viewer web device recomputes stock
(`rebuildStock`) and the totals of the documents it touched, and pushes any difference. A
native client that derives data differently will be "corrected", and may flip back and
forth. **Native writes must reproduce the web's derivations exactly, or not write those
records.**

## Storage

### `public.records`

Key: `(company_id, tbl, id)`. Columns: `data jsonb`, `rev bigint`, `updated_at`,
`updated_by`.

Limits:
- `id` is 1–128 characters.
- `data` is an object of at most 1 MiB (3 MiB for the company record, which carries the
  logo, stamp and signature).

Identity rules:
- `data.id == id`.
- `data.companyId == company_id`.
- For the company record, `id == data.id == company_id`.

`rev` comes from one global sequence, under a per-company advisory lock until commit.
Gaps are normal.

### Tables

There are 39 `tbl` values (`DATA_TABLES` in `src/db/db.ts`; the types are in
`src/db/types.ts`):

companies, clients, products, taxRates, documents (every document type), payments,
recurring, activities, accounts, journals, expenses, attachments, vatReturns,
bankTransactions, employees, complianceDocuments, renewals, complianceMarks,
peopleSettings, securityCheques, assets, depreciationRuns, yearEnds, payRuns,
payrollSettings, leaveRecords, staffLoans, finalSettlements, warehouses, stockMovements,
stockEntries, landedCosts, chequeLayouts, vehicles, approvals, letterTemplates,
employeeLetters, staffingCostings, stockIssues.

### Other server tables

- `deleted_records`: deletion markers, purged after 30 days.
- `sync_signals`: the only table in Realtime.
- `companies`.
- `company_members`: carries the role, `permissions jsonb` and `can_approve`.
- `company_invites`.
- `profiles`: a client may write only `full_name` and `language`.
- Notification tables: `change_events`, `notification_settings`, `notification_reads`,
  `email_alerts`.
- The Storage bucket `company-files`.

## Reading

### Pulling

`pull_records(p_company, p_since, p_limit 500)` returns `(tbl, id, data, rev, deleted)`:

- records and deletion markers with `rev > since`, in `rev` order;
- at most 1000 per page;
- filtered by RLS.

If `since` is below `purged_until_rev`, it raises `almail:resync`.

The client (`pullAll`, `applyRows` in `src/cloud/sync.ts`) applies each page in one local
transaction:

1. **The cursor becomes the page's maximum rev, counting unknown tables too.**
2. It skips:
   - rows of another company;
   - rows this role may not hold;
   - **rows with pending outbox entries** (the local change wins). The company record is
     the exception: it is rebased instead.
3. A deletion removes the local row and its rev. The company record is never deleted
   by a pull.
4. A push never advances the cursor. Your own writes come back on the next pull, together
   with what the server changed in them (merged counters, kept keys, approval stamps).

### First download

1. Pull from 0.
2. Store the company record last.
3. Set the cursor to the larger of itself and `purged_until_rev`.

### Resync

1. List the ids with `company_record_ids(company, tbl?, after_tbl, after_id, limit≤1000)`.
2. Delete local rows the cloud no longer has, except those with outbox entries.
3. Set the cursor to 0 and pull everything again.

### When to sync

- Subscribe to Realtime `postgres_changes` on `public.sync_signals` with
  `company_id=eq.<id>`.
- Sync 1 s after a local change, on start, on going online, on focus, every 60 s, and
  500 ms after a signal.
- Back off from 2 s, doubling up to 5 min, ±20%.
- Run `my_companies()` every 5 min, `my_permissions()` every 5 min, `server_features()`
  every 10 min.

### Privacy

Owners, admins and accountants only see private records. The rules are the server's
`record_is_private`, mirrored on the client by `isPrivateRecord` in `src/cloud/roles.ts`.

What is private:

- All of the People tables: employees, payRuns, payrollSettings, peopleSettings,
  leaveRecords, staffLoans, finalSettlements, letterTemplates, employeeLetters,
  staffingCostings.
- Any record with `_private:true`.
- `complianceDocuments` with `employeeId`, or `confidential:true`, and their renewals.
- `journals` with `kind='payroll'`.
- `approvals` about private tables.
- `activities` about employees, payroll, costings, or confidential records.
- `attachments` owned by private records.

On a role downgrade, purge private rows. On an upgrade, reset the cursor to 0 and increment
`epoch`.

## Writing

### Capturing a write

Each user action is **one local transaction** with one outbox `group` id. In that
transaction:

1. Apply the same refusals as the server first (`refuse*` in `src/cloud/outbox.ts`).
2. Write the record.
3. Add an outbox entry `{table, id, op: put|delete, group}`.

Add no entry when the record is unchanged. That is `sameData`: deep equality where null and
missing count as equal.

### Pushing

`push_records(p_company, [{tbl,id,data,base_rev} | {tbl,id,deleted:true,base_rev}] ≤500)`
returns `(tbl, id, rev, conflict)`.

- An upsert replaces the whole `data`.
- **The push always wins.** `conflict` is only a note, which the web logs as an activity
  `sync_conflict`.
- A delete is real.

The client (`buildBatch`, `confirm`, `sendBatch` in `src/cloud/sync.ts`):

- Batches at most 200 records and 512 KB.
- Coalesces each record to its current local copy. Never send a patch.
- Sends `base_rev` = the stored rev.
- Orders a batch with `PUSH_ORDER`: companies 0, employees 1, complianceDocuments and
  renewals 2, stockIssues 4, others 5, attachments 8, activities 9.
- Keeps a transaction's group in one batch, unless the group has more than 20 records.
- Before sending, strips `_private` and `contentMissing`, and sets `_private:true` on
  attachments and activities about private owners.
- Parks records of kinds the server lacks (from `server_features()`) as `server_outdated`.
- On success, in one transaction: removes the outbox entries and stores the returned revs.
- On a refusal: retries `offline`, `server` and `auth` errors (also `not_member` and
  `resync`) with backoff. Otherwise it bisects by group and parks the refused group with
  its error, so the user can retry or discard it.

### The company record

The company record is the only one sent as a **field diff**: `patch_company` with ops
`{path[], value | remove:true, base}`.

- At most 500 ops; each path has 1–8 segments.
- Arrays and `companyType` are sent whole.
- A numbering counter always travels as the pair `numbering.<kind>.next` + `.period`.
- After the push, `base` becomes **the copy as sent**.
- If the function is missing or returns no row: fetch the record, rebase, and push it
  whole.

### Server triggers

**`records_before_write`:**
- Checks shape, size and identity.
- Staff may change only the company record's counters and `updatedAt`.
- Merges numbering: a later `period` wins; within a period the higher `next` wins.
- Sets `rev`, `updated_at` and `updated_by`.

**`records_guard`:**
- Warehouses and sub-warehouses: managers only.
- `stockIssues`: approvers only.
- People letters: owners and admins only.
- Issued letters are frozen.
- On the company record:
  - `ai`: kept unless the writer is owner or admin.
  - `approvalRules`: owner only.
  - Books settings: not changeable by a member whose Books access is limited.
- `numberOnIssue`: an issued invoice or credit note must have a number.
- With approval rules: covered cheques and covered changes to issued documents are for
  approvers only (`almail:approval_required`). `paymentLink` is kept for non-approvers.
- `approvals`:
  - Inserts are forced to pending, with server-set requester and time.
  - Only approvers decide; the requester may only cancel.
  - What was requested is immutable.
  - A decision is final.

**Delete, insert and change triggers:**
- `records_after_delete` writes a marker.
- `records_after_insert` clears the marker.
- `records_change_event` builds the feed.

### Multi-record writes

The server does **no cascades**. The client writes all related records in one transaction.

**`saveDocument`** (`src/db/documents.ts`) writes:
- the document, with totals from `applyTotals` and a posting snapshot (`src/db/posting.ts`);
- the company record, if it assigned a number;
- stock movements (`syncDocumentStock`), with deterministic ids `sm-` + `stableId(...)`
  (`src/lib/ids.ts`);
- recosted movements;
- an activity;
- related orders.

**`savePayment`** (`src/db/payments.ts`) writes the payment and recalculates each document
it pays: status partial or paid, and `paidAt`. It may also write the company's numbering,
accounts and activities.

**`deleteDocument`** deletes the attachments, frees payments, takes credits off, unlinks
related documents, and deletes the document.

## Numbering

Each rule is `company.numbering[kind] = {pattern, next, padding, reset:
never|yearly|monthly, period}`. Defaults are in `src/db/defaults.ts`; the format is in
`src/lib/numbering.ts`.

**Documents, letters and SKUs** (kinds: the document type, `letter`, `product`):

1. Compute the local allocation, skipping numbers already used. Compare case-insensitively.
2. Call `reserve_number(company, kind, date, min = local next − 1)` with a 3 s timeout.
   Skip the call when offline or for a viewer.
3. Use the larger of the reserved and local numbers when the periods match.
4. Write the counter back to the company record as a patch.

**Payments, payments made, clients, journals, expenses and employees** are numbered on the
device only.

**Duplicates** are flagged, never refused. With `numberOnIssue`, invoice and credit drafts
stay unnumbered until they are issued.

## Permissions

| | owner | admin | accountant | staff | viewer |
|---|---|---|---|---|---|
| Read | all | all | all | non-private | non-private |
| Write | all | all | all | `STAFF_TABLES` (`roles.ts`); limited journal kinds; company counters only | nothing |
| Team | ✓ | ✓ (not the owner) | ✗ | ✗ | ✗ |
| Approve | ✓ | if `can_approve` | if `can_approve` | ✗ | ✗ |

The owner can also limit each member per app: `permissions.apps.{books,people,crm,compliance}`
∈ `none|view|edit|manage`.

`can_delete_record` never allows deleting:
- companies, approvals or stockIssues;
- issued letters;
- covered issued documents, unless the writer is an approver and `voidInsteadOfDelete` is
  off;
- covered cheques, except by approvers;
- movements of a posted issue.

## Files

**The bucket:** `company-files` is private, accepts `image/*` and PDF up to 10 MiB, and
stores each file at `{companyId}/{attachmentId}`.

**Uploading:**
1. Upload with upsert **before** pushing the attachment record.
2. Store `contentHash` (SHA-256 hex) and `storagePath`, and set `dataUrl: ''`.

**Downloading:** download eagerly after a sync if 1.5 MB or less; otherwise when the file
is opened.

**Deleting:**
1. After the delete is confirmed, remove the file.
2. Confirm with `stored_files`.
3. On failure, retry from a queue.

PDFs are rendered on the client (`@react-pdf/renderer`, `src/pdf/templates`) and never
stored.

## Other rules

- **Ids:** lowercase UUID v4 for records; 12 hex characters (`shortId`) for nested rows.
  `stableId` must be ported bit for bit (stock movements, cheque payments, automatic
  letters).
- **Times:** `toISOString()` (UTC with milliseconds). Dates are local `YYYY-MM-DD`.
- **Money:** JSON numbers, rounded half away from zero to the currency's precision (KWD has
  3 decimals), with decimal arithmetic (`src/lib/money.ts`).
- **Activities:** written by the client in the web format (`logActivity`), with `by` and
  `byName`.
- **Approvals:** carried out on the approver's device only after the cloud accepted the
  decision (`settleDecisions`, then `carryOutDecided`).
- **Client-run jobs:** leave these to the web devices at first. Recurring-invoice
  generation and approval expiry can duplicate if two clients run them.
- **Unknown fields:** **round-trip every unknown field.** Pushes replace whole records, so
  a dropped field is deleted for everyone.
- **Testing:** test against the real migrations: `src/cloud/sql-harness.ts` (PGlite) and
  `src/cloud/testing/fake-cloud.ts`.
