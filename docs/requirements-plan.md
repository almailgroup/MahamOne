# Maham One: plan for the 30 requested features

This plan covers the 30 requirements sent on 20 October 2026 for Maham Books, Maham People, Compliance and the Maham App. Each one was checked against the code as it is today (commit `874a2c9`). For each, it says what already exists, with file and line, and what is missing. It then lists the changes to the local and cloud database, the server endpoints, the screens and components, the steps, the tests, the risks, and the questions only the business can answer.

**Nothing in this plan is built yet.** It is the spec to build from, phase by phase.

Production has real data and is in daily use, so every change here is additive and ships switched off (D1). Old devices, backups, bookmarks and email links keep working.

## At a glance

**Update, 21 October 2026:** Phases 0, 1 and 2 are built, reviewed and released: 18 of the 30 requirements (#4 and #5 in part). How to switch each one on is in [the release notes](release-notes-phases-0-2.md).

Phase 3 is built and reviewed too: #6, #7, #8 and #9, so 22 of the 30 in all. It needs two new database scripts. How to switch each one on is in [the Phase 3 release notes](release-notes-phase-3.md).

Phase 4 is built and reviewed too: #10, #15, #18 and #19, so 26 of the 30 in all. It needs one new database script, `20261130000000_people_alerts.sql`. How to switch each one on, and what to ask the auditor first, is in [the Phase 4 release notes](release-notes-phase-4.md).

Phase 5 is built and reviewed too: #3, in two parts (Maham Sales, Maham Books and Maham Inventory as a switchable app layout, and the manpower costing in Maham People with its quote), so 27 of the 30 in all. It needs one new database script, `20261207000000_staffing_costings.sql`, for the manpower costing only. How to switch each part on, and what to ask counsel and the auditor first, is in [the Phase 5 release notes](release-notes-phase-5.md).

Beyond the 30, warehouses and items issued are built too: sub-warehouses under the main warehouse, each looked after by an employee, stock sent to them, and uniforms issued to employees once the Super Admin confirms. It needs one new database script, `20261210000000_warehouse_issues.sql`. How to switch it on is in [the release notes for warehouses](release-notes-warehouses.md).

When this plan was written, none of the 30 was fully built: 25 were partly built, 4 were not built, and 1 conflicted with how invoice numbering must work (#8).

Size: S is under a day, M is 1–3 days, L is 3–7 days and XL is over a week. The phases are described under [Phases](#phases).

| #   | Requirement                                                                                       | Status                                | Size | Phase                      |
| --- | ------------------------------------------------------------------------------------------------- | ------------------------------------- | ---- | -------------------------- |
| 1   | [Employee search across all companies](#1-employee-search-across-all-companies)                   | Built                                 | M    | 2                          |
| 2   | [Company Type field](#2-company-type-field)                                                       | Built                                 | S    | 2                          |
| 3   | [Separate Sales, HR, Finance and Inventory apps](#3-separate-sales-hr-finance-and-inventory-apps) | Built                                 | XL   | 5                          |
| 4   | [Document finder and AI assistant](#4-document-finder-and-ai-assistant)                           | Built (finder); AI in Phase 8         | XL   | 2 (finder), 8 (AI)         |
| 5   | [Deema, Taly and Tahseel in the sidebar](#5-integrations-in-the-sidebar-deema-taly-tahseel)       | Built (links); integration in Phase 6 | M    | 2 (links), 6 (integration) |
| 6   | [Super Admin](#6-super-admin-with-full-control-of-roles-and-permissions)                          | Built                                 | L    | 3                          |
| 7   | [Change notifications to the Super Admin](#7-change-notifications-to-the-super-admin)             | Built                                 | L    | 3                          |
| 8   | [Invoice approval and Void invoices](#8-invoice-approval-and-void-invoices)                       | Built                                 | XL   | 3                          |
| 9   | [Cheque confirmation](#9-cheque-confirmation-by-the-super-admin)                                  | Built                                 | L    | 3                          |
| 10  | [Salary approval](#10-salary-approval-by-the-super-admin)                                         | Built                                 | XL   | 4                          |
| 11  | [Leave requests from the Maham App](#11-leave-requests-from-the-maham-app)                        | Not built                             | XL   | 7                          |
| 12  | [Departments and a Stateless option](#12-departments-and-a-stateless-option)                      | Built                                 | L    | 2                          |
| 13  | [Driving licences for drivers](#13-driving-licences-for-drivers)                                  | Built                                 | M    | 2                          |
| 14  | [Default leave policy of 30 days](#14-default-leave-policy-of-30-days)                            | Built                                 | M    | 2                          |
| 15  | [Custom leave reasons](#15-custom-leave-reasons-with-automatic-pay-and-balance-effects)           | Built                                 | XL   | 4                          |
| 16  | [Messages to guards in the Maham App](#16-messages-to-guards-in-the-maham-app)                    | Not built                             | L    | 7                          |
| 17  | [Company documents, contracts and vehicles](#17-company-documents-contracts-and-vehicles)         | Built                                 | L    | 2                          |
| 18  | [Expiry alerts](#18-expiry-alerts-with-lead-times-and-re-upload-reminders)                        | Built                                 | L    | 4                          |
| 19  | [Employee letter templates](#19-employee-letter-templates)                                        | Built                                 | XL   | 4                          |
| 20  | [Zoho-style dashboard](#20-zoho-style-books-dashboard)                                            | Built                                 | L    | 1                          |
| 21  | [Scanned attachments on payments](#21-scanned-attachments-on-payments)                            | Built                                 | M    | 1                          |
| 22  | [Invoice QR, signature and stamp](#22-invoice-qr-signature-and-stamp-signature-in-blue)           | Built                                 | M    | 1                          |
| 23  | [Burgan Bank and KFH cheque printing](#23-burgan-bank-and-kfh-cheque-printing)                    | Built                                 | L    | 1                          |
| 24  | [Receipt and payment vouchers](#24-receipt-and-payment-vouchers-سند-قبض--سند-صرف)                 | Built                                 | M    | 1                          |
| 25  | [Import bank statements](#25-import-bank-statements)                                              | Built                                 | L    | 1                          |
| 26  | [Pay-by-link from the invoice QR](#26-pay-by-link-from-the-invoice-qr)                            | Partly built                          | XL   | 6                          |
| 27  | [Quote design](#27-quote-design-layout-colour-and-logo)                                           | Built                                 | M    | 1                          |
| 28  | [Units, SKU and QR codes, labels](#28-item-units-sku-and-qr-codes-labels-and-printing)            | Built                                 | L    | 1                          |
| 29  | [Product images](#29-product-images)                                                              | Built                                 | M    | 1                          |
| 30  | [Excel stock import](#30-bulk-import-of-stock-items-from-excel-or-csv)                            | Built                                 | M    | 1                          |

**Rough effort:** about 150 working days for one developer across the eight phases. Phase 0 adds about two weeks. That figure excludes waiting for decisions, merchant contracts and SMS or bank sign-ups, and testing with the real company.

## Decisions needed before building

Each section ends with its own questions and the default we will use if there is no answer. These are the ones that change the design:

1. **Invoice numbers are never reused (#8).** A deleted invoice becomes a void and keeps its number, under _Void invoices_. A corrected invoice gets a new number that says which invoice it replaces. Drafts get their number only when issued, so deleting a draft never uses up a number. Reusing a number would give two legal documents the same number and break the audit trail, and the number is already on PDFs and payment links that were sent. _Please confirm with the auditor._
2. **Mr. AbdulAziz Almail becomes the owner of each company (#6).** The cloud already has exactly one owner per company, so no new role is needed. Only the Super Admin grants admin or accountant; admins can still invite staff and viewers. Up to two deputies can be allowed to approve, off by default.
3. **An unconfirmed cheque is a request, not a payment (#9).** It reaches the books only when the Super Admin confirms it, dated the day it was written or received. Recommended scope: cheques the company writes and security cheques it hands over; received cheques are off.
4. **Salary approval emails carry totals only (#10).** The email shows totals by department and position, plus a link that opens the signed-in app, where the per-person breakdown is. Individual salaries are not sent by email.
5. **How quickly to notify about changes (#7).** Recommended: important changes (an invoice voided or edited after it was sent, a cheque, a role change) within 5 minutes; everything else in a daily 08:00 digest. The email service's free plan allows 100 emails a day, shared with the morning alerts, so a paid plan is advisable.
6. **The Maham App has to be built (#11, #16).** No repository for it exists. The plan builds it as a separate mobile app from this codebase. Guards sign in with an SMS code, which needs an SMS provider account (a running cost). Guards are not team members and see only their own leave, balance and messages.
7. **Stateless (Bedoon) employees (#12).** We need the legal treatment confirmed: no PIFSS (as today), optional work permit, and the Central Agency review card instead of an Iqama.
8. **Online payments (#26) and Tahseel (#5).** Which gateway does the company have a merchant account with? MyFatoorah is the default in the plan. We also need to confirm which service "Tahseel" means before it is added.
9. **AI assistant (#4).** Do you consent to sending document metadata (titles, numbers, dates; never IDs, salaries or IBANs) to Anthropic? What is the monthly budget, and whose account holds the key? A document finder that needs no AI ships first, in Phase 2.
10. **App structure (#3).** Recommended: Sales owns quotes, orders, invoices and customers; Finance (still "Maham Books") owns purchases, payments, cheques, banking and accounts; Inventory becomes its own app. "HR integrated with quotations" becomes manpower costing: guard and staff posts priced from a rate card that HR keeps, never from individual salaries.
11. **Cheque printing (#23)** needs a scan of one cancelled leaf from Burgan Bank and one from KFH, plus the printer model, to measure the layouts.
12. **Leave (#14, #15).** Are the 30 days working days (as today) or calendar days? Which custom leave reasons are needed, and how is each paid?

## Shared decisions every section follows

These are fixed for the whole plan. Sections refer to them by number (D1…D16) instead of repeating them.

**D1. Ship everything off.** Every new behaviour sits behind a company setting that is absent today, so production behaves exactly as now until the owner switches each feature on. New fields are optional; missing means today's behaviour.

**D2. Phase 0 compatibility release first.** Before any feature writes new kinds of data, one release with no visible change:

- tolerant lookups for every closed list an older build reads without a fallback (`LEAVE_TYPES[type]`, `CATEGORY_LABELS[category]`, `DOCUMENT_TYPES[type]` including the copy bundled into the email-alerts function, `RUN_STATUS[status]`, `STATUS_META`, alert topics);
- the sync fix for new tables: today `pull` moves its cursor past rows of a table it doesn't know (`src/cloud/sync.ts:994-996`), so an older build never receives them after it updates. `CloudLink.tables` records the tables a device has pulled with; when the list grows, the cursor resets to 0 and the epoch is bumped (the pattern `applyRole` uses, `sync.ts:1326-1336`);
- a parity test that the table lists agree: `DATA_TABLES` (`src/db/db.ts:176-209`), `backupSchema` (`src/db/backup.ts:47-85`), `records_tbl_check` in the migrations, `PEOPLE_TABLES` / `STAFF_TABLES` (`src/cloud/roles.ts:41-127`) and `record_is_private` / `staff_can_write`;
- the Edge Function build becomes multi-entry (`vite.functions.config.ts`, `supabase/config.toml`, `.github/workflows/deploy.yml`) with the email-alerts bundle unchanged.
  PWA updates wait for the user (`registerType: 'prompt'`, `vite.config.ts:19`), so this release must reach devices a week or two before Phase 1 writes anything new.

**D3. Local database versions.** The last Dexie version is 15 (`src/db/db.ts:168`; 11 and 12 were never used). Version **16** ships in Phase 0 and declares the new tables of Phases 1–4 at once (empty tables cost nothing):

| Table                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Indexes                                                               | Private (People)                | Staff may write | Used by       |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ------------------------------- | --------------- | ------------- |
| `chequeLayouts`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | `id, companyId, bank`                                                 | no                              | no              | #23           |
| `vehicles`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `id, companyId, plate`                                                | no                              | no              | #17, #13, #18 |
| `approvals`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | `id, companyId, [companyId+status], subjectId, kind`                  | when its subject is People data | yes (to ask)    | #8, #9, #10   |
| `letterTemplates`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | `id, companyId, kind`                                                 | yes                             | no              | #19           |
| `employeeLetters`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | `id, companyId, employeeId, [companyId+issuedOn], templateId, status` | yes                             | no              | #19           |
| Plus new indexes on existing tables in the same version: `complianceDocuments` + `clientId, vehicleId`; `products` + `[companyId+sku]`; `attachments` + `docKey`.                                                                                                                                                                                                                                                                                                                                                                            |
| Later phases take **17** (`staffingCostings`, #3), **18** (`gatewayPayments`, #26) and **19** (`leaveRequests`, `employeeMessages`, #11 #16). Never edit or reuse a shipped number. Every new synced table is also added to `DATA_TABLES`, `backupSchema` with `.default([])` (old backups still restore; `BACKUP_FORMAT` stays 1), `src/cloud/labels.ts`, and the role mirrors in `src/cloud/roles.ts`. Device-only data (printer calibration, dashboard preferences) stays out of `DATA_TABLES` and backups (`db.meta` or `localStorage`). |

**D4. Cloud migrations.** New files only, idempotent (`create or replace`, `if not exists`), pasted by the owner in the Supabase SQL editor, added to `MIGRATIONS` in `src/cloud/sql-harness.ts:18-22` and to `docs/supabase-setup.md`. Release order is always: run the migration, then ship the app. The app hides a feature until the server has it (the `optionalRpc` / PGRST202 pattern, `src/cloud/supabase-api.ts:82-108`). Server refusals use SQLSTATE `42501`, which old clients park as a permission problem instead of retrying. Planned files:

| File                                       | Phase | What                                                                                                                                                                                                                                                                                                                   |
| ------------------------------------------ | ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `20261102000000_tables_v16.sql`            | 0     | `records_tbl_check` + the five new tbls; `record_is_private` for the private ones, plus the `confidential` branch for company documents (#17) with its device mirror in the same release; `staff_can_write` + `approvals`; a RESTRICTIVE select policy for People tables that survives a re-run of the first migration |
| `20261116000000_super_admin_approvals.sql` | 3     | `company_members.permissions` / `can_approve`; `is_approver()`; owner-only team rules; the `records_guard` trigger; audit of member changes                                                                                                                                                                            |
| `20261123000000_change_feed.sql`           | 3     | `change_events`, `notification_settings`, `notification_reads`, the 5-minute cron                                                                                                                                                                                                                                      |
| `20261130000000_people_alerts.sql`         | 4     | targeted document alerts (`email_alerts.document_kinds`), accountants as recipients, payroll approval email trigger                                                                                                                                                                                                    |
| `20261207000000_staffing_costings.sql`     | 5     | tbl `staffingCostings` (private)                                                                                                                                                                                                                                                                                       |
| `20261210000000_warehouse_issues.sql`      | —     | Built (not one of the 30): tbl `stockIssues`; sub-warehouses and their keepers; requests of kind `stock_issue`; `stock_issue_recipients`; who receives what in the change feed                                                                                                                                         |
| `20261214000000_payment_gateway.sql`       | 6     | tbl `gatewayPayments`; `payment_links`, `gateway_accounts` (Vault), `gateway_events`; anonymous pay RPC                                                                                                                                                                                                                |
| `20261221000000_employee_app.sql`          | 7     | `employee_invites`, `employee_accounts`, `my_employee_id()`, tbls `leaveRequests` / `employeeMessages`, `message_receipts`, `push_subscriptions`, `message_dispatch`                                                                                                                                                   |
| `20261228000000_document_assistant.sql`    | 8     | `search_fold()`, `record_search_text()`, `record_summary()`, `assistant_settings`, `assistant_usage`                                                                                                                                                                                                                   |

**D5. Super Admin = the company owner.** The cloud already has exactly one owner per company (`company_members_one_owner`). Mr. AbdulAziz Almail is made the owner of each company with the existing _Transfer ownership_; the code never contains the Super Admin's name or email. Optional deputies get `can_approve`. "All companies" means every company where the signed-in account is owner. A company kept only on one device has no server, so approvals and notifications apply to cloud companies only.

**D6. One approvals service** for #8, #9, #10 (and later expense or letter approvals): a synced tbl `approvals` `{kind, subjectTbl, subjectId, subjectNumber, before?, after?, reason, status: pending|approved|rejected|cancelled|applied, requestedBy, requestedAt, decidedBy, decidedAt, decisionNote}`. The server stamps `requestedBy` and the decision fields and refuses anything else (a `records_guard` trigger after `records_before_write`), because `push_records` is last-writer-wins and an offline copy must not overwrite a decision. The device mirrors the rule in `src/cloud/outbox.ts:109-125` so the refusal is instant offline. Rules live in an owner-only `Company.approvalRules`. Code: `src/db/approvals.ts`, `src/features/approvals/` (shared, because Books and People both use it; the boundaries test forbids app-to-app imports). Inbox: a new _Approvals_ page plus a count on the suite home (`src/suite/home/attention.ts`).

**D7. One notification service** for #7, #10, #18 and later #16: a server-side feed `public.change_events` filled by a trigger on `public.records` and `public.company_members` (wrapped in `exception when others` so it can never block a push; skips replays where `old.data = new.data`, imports and `delete_company`), per-user `notification_settings` and `notification_reads`, and a 5-minute pg_cron job that calls the existing email-alerts function with `{"action":"notify"}`. Emails are digests (one email per recipient per window, daily cap); in-app it is a bell fed by `public.notification_feed(p_company, p_after)`. Events about People data reach only owners, admins and accountants. Resend's free plan (100 emails a day) is shared with the morning alerts, so a paid plan or strict caps are needed. Web push comes with the Maham App (Phase 7), because it needs the service worker moved from `generateSW` to `injectManifest`.

**D8. Who did what.** `Activity` has no author today and `pull_records` doesn't return `updated_by`. Phase 3 adds `Activity.by` / `byName` written by the device and the server-side `change_events.actor`, so the Super Admin sees who made each change.

**D9. Employees are not team members.** Guards and other staff who use the Maham App get a row in `public.employee_accounts (company_id, user_id, employee_id)`; `member_role()` stays null for them, so every existing rule refuses them unchanged. They read and write only through narrow security-definer RPCs that return their own non-salary data. Their requests land in `public.records` (tbls `leaveRequests`, `employeeMessages`), so HR devices get them offline-first through the normal sync.

**D10. The Maham App** does not exist in any repository today. It is built as a separate mobile web app (installable PWA) from this repository (`src/me/`, its own Vite config and service worker), deployed as a second Vercel project on its own address, so it can't disturb the main app's offline cache. It may reuse `src/cloud/{client,config,auth}`, `src/i18n`, `src/lib` and `src/components/ui`, never Dexie or `src/cloud/store.ts` (a new boundaries-test rule). Sign-in: an invite link sent by SMS or WhatsApp, then phone one-time codes (needs an SMS provider configured in Supabase Auth).

**D11. Company-defined lists are data, not new enum values.** Company types, departments, document purposes, leave reasons and units are lists of `{id, name, nameAr, archived?}`; anything older builds compute with maps onto an existing base value (a custom leave reason has a base `LeaveType`). People lists live in the existing private settings rows (`PeopleSettings`, `PayrollSettings`), so they need no migration.

**D12. Invoice numbers are never reused.** A voided invoice keeps its number and moves to _Void invoices_ (the existing `void` status and `?status=void` list); a corrected invoice gets a new number and a "Replaces INV-…" link. To meet the intent that numbers aren't wasted, drafts get their number only when issued (`DocumentDefaults.numberOnIssue`), so deleting a draft never burns a number. Reusing a number would give two legal documents one number, break the audit trail, and clash with numbers already printed on sent PDFs and payment links.

**D13. An unconfirmed cheque is a request, not a payment.** Until the Super Admin confirms, the cheque lives in `approvals.after`; confirming creates the Payment (dated when the cheque was received), so nothing reaches the ledger early and older builds, which post every Payment, are unaffected. No new `ChequeStatus`.

**D14. Salaries stay inside the app.** The payroll approval email carries totals by position and department and a link that opens the signed-in app; the per-person breakdown is only in the app. A one-click approve link without signing in would be a bearer token for salary decisions. Attaching the full breakdown to the email is possible only as an explicit owner choice (and `docs/email-alerts.md` must then stop promising that emails never contain salaries).

**D15. Signatures and stamps never print on drafts.** Drafts get a DRAFT watermark; the blue ink is produced once at upload (the original is kept so the colour can be changed). Images stay small: the company record is capped at 3 MB in the cloud.

**D16. Privacy.** Staff and viewers never receive payroll or employee data: every new People table goes into `record_is_private` and `PEOPLE_TABLES`; every new server function reads as the caller (RLS) or strips private fields per recipient; nothing sends Civil IDs, salaries or IBANs to a third party (AI or email) without an explicit owner decision. Examples, demo data and tests use invented names only.

## Phases

| Phase | Theme                                     | Requirements                                                               |
| ----- | ----------------------------------------- | -------------------------------------------------------------------------- |
| 0     | Groundwork, no visible change             | D2, D3, D4 (`tables_v16`)                                                  |
| 1     | Books quick wins (local, no server work)  | #21, #22, #24, #25, #28, #29, #30, #23, #27, #20                           |
| 2     | Company, People and Compliance quick wins | #2, #1, #5 (links), #12, #13, #14, #17, #4 part A (document finder, no AI) |
| 3     | Super Admin control                       | #6, approvals service (D6), #8, #9, #7 (D7, D8)                            |
| 4     | HR workflows and alerts                   | #15, #10, #18, #19                                                         |
| 5     | Suite structure                           | #3 (Sales / HR / Finance / Inventory apps; staffing quotes)                |
| 6     | Online payments                           | #26, #5 part B (Taly, Deema, Tahseel integrations)                         |
| 7     | Maham App                                 | D9, D10, #11, #16                                                          |
| 8     | AI assistant                              | #4 part B                                                                  |

## The 30 requirements

Each section has the same parts: what is there now, what is missing, the database changes (on the device and in the cloud), the server API, the screens and components, the steps, the tests, the risks and the questions for the owner. "(D6)" and similar refer to the [shared decisions](#shared-decisions-every-section-follows).

## 1. General and core

### 1. Employee search across all companies

**Status:** Partly built · **Size:** M · **Phase:** 2

An _All companies_ page in People and an _Employees in other companies_ palette section, reading only data already on the device. Privacy is decided per company from its own link, never from the open company's role; as owner of every company (D5), Mr. AbdulAziz Almail sees them all. This is wider than D5's 'all companies' (owned companies only): an admin or accountant also searches the companies where their role may see People. That is the same data they can already open one company at a time.

**There now**

- `src/app/company.tsx:37-48`: loads every company on the device and picks the open one; switching only writes a meta key (`src/db/records.ts:42-48`).
- `src/features/search/sources.ts:192-199,240-254`: the palette indexes employees of the open company only, hidden when People access is `none` (`src/features/search/command-palette.tsx:166`).
- `src/apps/people/pages/people/list.tsx:79-105`: filters over `useEmployees()` of the open company (`src/features/people/hooks.ts:8-14`).
- `src/features/cloud/role-gates.tsx:24-41,44-66`: `useRoleView` and `PeopleGate` know only the open company; People routes use `AppGate` (`src/apps/people/routes.tsx:25-27`).
- `src/cloud/sync.ts:986-998,1326-1336`: staff and viewer companies never hold employees locally; `CloudLink` keeps `userId`, `role`, `status` (`src/cloud/types.ts:11-45`).
- `src/apps/people/pages/people/detail.tsx:127`: an employee of another company shows "could not be found".

**Missing**

- Per-company eligibility, a cross-company query, the page, the palette section, and "switch company, then open".

**Database**

- Local: no Dexie change; `db.employees.where('companyId').anyOf(ids)` uses the existing index (`src/db/db.ts:124`). `PeopleSettings.groupSearch?: boolean` per company (D1: missing keeps the company out). Remembered filters in `localStorage` with try/catch. No backup change.
- Cloud: No change.

**Server API**

- None: runs on the device.

**Screens and components**

- `src/features/people/all-companies.ts` (shared layer; the palette may not import `src/apps`): `peopleCompanies(companies, links, userId)` keeps device-only companies and those whose link has the signed-in `userId`, is not `removed`, passes `canSeePeople(role)` and has `groupSearch` on; `findEmployees()` reuses `normalizeSearch` (`src/features/search/normalize.ts:48`).
- `useEmployeesEverywhere()` (`src/features/people/hooks.ts`, drops ineligible rows again), `openInCompany(companyId, to)` (`src/app/company.tsx`), `AnyCompanyPeopleGate` (`role-gates.tsx`).
- `src/apps/people/pages/overview/all-companies.tsx` at `people/all`, behind the new gate, opened from a _Search all companies_ link on Employees when 2+ companies qualify (no sidebar link, since `NavLink` has no such condition). Filters: company, Company Type (#2), department, category, current/left; per-company _Include_ switches; CSV without salary, IBAN or Civil ID.
- Palette: `otherCompanyEmployeeEntries()` in `sources.ts`, company name as subtitle; recent items saved under the target company (`src/features/search/recent.ts:25`).
- Arabic in `src/i18n/ar/people.ts`: كل الشركات, موظفون في شركات أخرى.

**Steps**

1. Eligibility helper and search, with unit tests.
2. Hook, `openInCompany`, gate.
3. Page, route, Employees link, switches, Arabic.
4. Palette section; `docs/maham-one.md`.

**Tests**

- Unit `src/features/people/all-companies.test.ts`: device-only, owner, admin, accountant in; staff, viewer, `removed`, another account's link and switch off out; Arabic names and phone digits match.
- `src/features/search/sources.test.ts`: never an ineligible company.
- e2e `e2e/people.spec.ts`: from company A, find and open an employee of B; with `e2e/cloud-fake.ts` a staff company adds nothing.

**Risks**

- Shared computer: another account's companies stay on the device; the `userId` check and the per-row filter keep them out.
- Unsaved forms and a "not found" flash: `openInCompany` asks before leaving a form with unsaved changes, switches, then navigates; a toast names the company now open.

**Decisions for the owner**

- Search companies not on this device through the cloud? _Recommended:_ not now; later a `security invoker` RPC over `public.records`, so each company's RLS applies with no new rule.
- Include employees who left? _Recommended:_ current only, with a Left toggle.

### 2. Company Type field

**Status:** Partly built · **Size:** S · **Phase:** 2

An optional _Company type_ (نوع الشركة) on the creation and edit forms for the line of business (security services, manpower supply, trading). Legal form stays a fixed list, because Zakat, KFAS, NLST, the statutory reserve and deadlines are computed from it.

**There now**

- `src/db/types.ts:379-388` `LegalForm`, `:403-426` `KuwaitProfile`, `:451-506` `Company`: no type field.
- `src/features/company/fields.tsx:17-36,38-56`: fixed Legal form and activity selects; `other` can't be described.
- `src/pages/setup.tsx:264-284` and `src/pages/settings/company.tsx:188-195`: Legal form on the creation and edit forms.
- `src/lib/accounting/year-end.ts:110-156`, `src/lib/compliance.ts:350-384`: money rules and deadlines read `legalForm`.
- `supabase/migrations/20261006000000_sync_fixes.sql:84-184`: `patch_company` merges any changed path. Staff can change only numbering, on the server (`20261004000000_almailbooks_cloud.sql:585-604`) and the device (`src/cloud/outbox.ts:115-121`).

**Missing**

- The field, a description for Legal form _Other_, the type in Settings → Companies and the switcher.

**Database**

- Local: `Company.companyType?: { id: ID; name: string; nameAr?: string }` (D11 shape). No stored list: the picker offers built-ins with fixed ids (`security`, `manpower`, `cleaning`, `trading`, `contracting`) plus types other companies on this device use, so #1 groups by `id` across devices. `KuwaitProfile.legalFormOther?: string`. No Dexie version; backup keeps whole company rows.
- Cloud: No change: the field travels in the company record, and only changed leaves are sent (`src/cloud/company-patch.ts`, `patch_company`).

**Server API**

- None: runs on the device.

**Screens and components**

- `src/features/company/company-types.ts`: pure `companyTypeOptions(companies)`. `src/features/company/fields.tsx`: `CompanyTypeField` (known types + _New type…_ with English and Arabic names).
- `src/pages/setup.tsx`, `src/pages/settings/company.tsx`: the field next to Legal form; _Describe the legal form_ (وصف الشكل القانوني) when Legal form is Other. Staff and viewers see it read-only (`src/pages/settings/shared.tsx:108`).
- `src/pages/settings/companies.tsx:94-99`, `src/features/shell/sidebar.tsx:75-123`: the type under the company name.
- Arabic in `src/i18n/ar/company.ts`.

**Steps**

1. Optional fields; `companyTypeOptions` with tests.
2. Field on both forms; Other description.
3. Companies list, switcher, Arabic, a type on the Kuwaiti demo.
4. Hand the type to #1's filter.

**Tests**

- Unit: options deduplicate by id, trim, keep Arabic; empty saves as missing.
- `src/db/review-company.test.ts`: `setupCompany` keeps `companyType`; `legalForm` unchanged.
- `src/cloud/company-patch.test.ts`: a type change travels alone and doesn't clash with numbering.
- `src/db/backup.test.ts`: round trip keeps both fields.
- e2e `e2e/kuwait-setup.spec.ts`: set at creation, change in Settings, see it in Companies, Arabic too.

**Risks**

- Mixing it up with Legal form: the hint says "Line of business; taxes don't change"; `legalForm` is untouched.
- Spelling drift across companies: fixed-id built-ins and reuse of existing types.
- D1: empty means today's behaviour; nothing prints or computes from it. Older builds ignore it, and since only changed fields travel, they don't erase it in the cloud.

**Decisions for the owner**

- Is "Company Type" the line of business or the legal form? _Recommended:_ line of business, as a new field.
- Print it on invoices? _Recommended:_ no. Required? _Recommended:_ optional.

### 3. Separate Sales, HR, Finance and Inventory apps

**Status:** Partly built · **Size:** XL · **Phase:** 5

Two parts. (a) A switchable app layout that splits Maham Books into Sales, Finance (Books) and Inventory by manifest ownership only: no URL or data change. (b) HR-to-quotation as a private _Manpower costing_ (تسعير العمالة) in People that prices guard and cleaner posts and creates a quote with sell prices only. Finance, Inventory and Purchases are already integrated and stay as they are.

**There now**

- `src/suite/apps.ts:11` `APPS` = Books, People, CRM, Compliance; `:29` owner map; `:41-45` `appForPath`; `:52-56` `appAccess`; `:79-99` `createGroups`.
- `src/suite/types.ts:14` `AppId` (4 ids), `:24` `AppTone` (4 colours), `:47-79` `SuiteApp`.
- `src/apps/books/manifest.ts:42-70`: Books owns every sales, purchase, inventory and accounting segment; New groups `:143-165`; access `:185-192`. `src/apps/crm/manifest.ts:30-31`: CRM owns `crm`, shares clients, quotes, sales orders.
- Routes are flat and owner-free (`src/app/routes.tsx:96-103`); `src/app/routes.test.ts:24` `LEGACY_PATHS`; `src/suite/apps.test.ts:21-30` expects four apps and one owner per segment.
- Already integrated: documents move stock (`src/db/documents.ts:659,737,813` → `src/db/inventory.ts:361`); orders become bills or invoices (`src/db/orders.ts:65`).
- HR blocks for costing: `src/lib/hr/payroll.ts:168-183` hourly rate and overtime, `src/lib/hr/eosi.ts`, `src/lib/hr/job-titles.ts:9-15` guard and cleaner titles.
- `docs/maham-one.md:130-147` plans an HR role with per-app access.

**Missing**

- Sales and Inventory apps and a switch for them; staff costing and its quote link; per-app roles.

**Database**

- Local: `Company.appLayout?: 'split'` (D1: missing = today's four apps). Dexie **17** (D3): `staffingCostings: 'id, companyId, clientId, quoteId, status'`. `StaffingCosting { name, clientId, quoteId, status: draft|quoted|won|lost, posts, overheadPercent, marginPercent, notes }`; `CostingPost { jobTitle, jobTitleAr?, headcount, hoursPerDay, daysPerMonth, basic, allowances, employerPifss, eosiMonthly, leaveMonthly, otherCosts, monthlyCost, sellPrice }`. `InvoiceDocument.costingId?: ID | null` (an id only). `PeopleSettings.costing?: { on, overheadPercent, marginPercent }`. The table joins `DATA_TABLES`, `backupSchema` (`.default([])`), `src/cloud/labels.ts` and `PEOPLE_TABLES`, never `STAFF_TABLES`.
- Cloud: `20261207000000_staffing_costings.sql` (D4): `records_tbl_check` re-created with the full v16 list plus `staffingCostings`; `record_is_private` adds it and activities of entity `costing` (mirrored in `isPrivateRecord`, `src/cloud/roles.ts:92-104`); `staff_can_write` unchanged; added to `MIGRATIONS` and `docs/supabase-setup.md`. The D2 parity test catches a missed list.

**Server API**

- None: runs on the device. Quote numbers keep using `public.reserve_number`.

**Screens and components**

- `src/suite/types.ts`: `AppId` + `'sales' | 'inventory'`; `AppTone` + `'violet' | 'teal'` (both theme palettes in `src/lib/themes.ts`); `APP_TONES` in `src/suite/switcher.tsx:16-21`.
- `src/apps/sales/manifest.ts` (Maham Sales): owns quotes, proformas, sales-orders, invoices, delivery-notes, credits, recurring, payments, clients; the Sales New group; Books' access.
- `src/apps/inventory/manifest.ts` (Maham Inventory): owns products, inventory; shares purchase-orders, bills, vendors, delivery-notes; creates product and stock adjustment.
- `src/apps/books/manifest.ts`: a `FINANCE` variant without those segments, sharing invoices, payments, credits, clients (Receivables) and products, inventory.
- `src/suite/apps.ts`: `appsFor(company)` and `useApps()`; `appForPath`, `accessMap`, `createGroups`, `isAppId` take the active list, as do `TOPIC_APPS` (`src/suite/home/attention.ts:20-26`), home stats (`src/suite/home/index.tsx`) and palette subtitles (`src/features/search/sources.ts:132-136`). CRM shares Sales-owned segments.
- The switch: Settings → Team, above `src/suite/access-grid.tsx`, owner and admin.
- People: `src/apps/people/pages/costing/{list,editor}.tsx` at `people/costing` and `people/costing/:id`, behind People's `AppGate`; nav link; action in `src/features/shell/create.ts`; calculator `src/lib/hr/costing.ts`; _Create quote_ through `src/db/documents.ts`; internal cost sheet `src/pdf/costing.tsx` (كشف التكلفة), never attached to the quote.
- Arabic in `src/i18n/ar/suite.ts`, `src/i18n/ar/people.ts`.

**Steps**

1. Owner answers the boundary questions; update `docs/maham-one.md`.
2. Ids, tones, Sales, Inventory and Finance manifests.
3. Layout-aware registry and its users; the switch; tests for both layouts.
4. Home, palette, Team grid, Arabic, `e2e/suite.spec.ts`.
5. `src/lib/hr/costing.ts` with tests.
6. Costing data, Dexie 17, mirrors, migration with SQL tests; the owner runs it, then the app ships (D4).
7. Costing pages, _Create quote_, `costingId`, cost sheet, demo with invented posts, e2e.

**Tests**

- `src/suite/apps.test.ts`: classic layout unchanged; split: six apps, unique tones, one owner per segment, `appForPath('/invoices/1')` → `sales`, `appForPath('/products')` → `inventory`, `appForPath('/invoices/1', 'books')` → `books`.
- `src/app/routes.test.ts`: `LEGACY_PATHS` green, `/people/costing` in `SUITE_PATHS`; `src/suite/boundaries.test.ts` with no new exception.
- `src/lib/hr/costing.test.ts`: employer PIFSS only for Kuwaiti/GCC posts; EOSI accrual; a 12-hour post priced as 8 normal hours plus 4 overtime hours at 1.25×, with a warning, because art. 66 of Labour Law 6/2010 limits overtime to two hours a day unless an exemption applies (the owner confirms with counsel); 3-decimal KWD; margin versus markup.
- `src/cloud/roles.test.ts` and `src/cloud/sql.test.ts`: private; staff and viewer can't read or push it. `src/db/db.test.ts`: upgrade 16 → 17. `src/db/backup.test.ts`: round trip.
- e2e `e2e/people.spec.ts`: costing → quote shows sell prices only; a staff member (cloud fake) never sees costing.

**Risks**

- Sidebars change for everyone at once: the split is off by default; the remembered app (`src/suite/current-app.ts:14`) falls back to Books when its id is not in the active list.
- Salaries leaking to staff through quotes: lines, notes and activity text carry sell prices only; a test checks the quote has no cost fields.
- An older build saving the quote may drop `costingId`; the costing's `quoteId` keeps the link.
- Before the migration, pushes of the tbl are refused and parked; the costing switch shows only once the server has it (D4). D2's cursor reset lets older builds receive the rows after they update.
- Moving document pages to a shared layer isn't needed (routes are flat); skip that large diff.
- Links chosen for apps (#5, `CompanyLink.apps`) keep the ids of the four apps: the integrations (Deema, Taly, Tahseel) are saved with `['books', 'crm']`, the owner's choice of "Finance (Books) and Sales". In the split layout `linkApps` (`src/lib/links.ts`) must read `books` as Finance _and_ Sales (and Inventory where it fits), or the stored lists be remapped when the split is switched on; otherwise every integration misses the Sales sidebar.

**Decisions for the owner**

- Invoices in Sales or Finance? _Recommended:_ Sales owns them; Finance lists them under Receivables.
- Inventory its own app? _Recommended:_ yes; purchases stay in Finance.
- Is "HR with Quotation" a manpower costing priced from staff cost? _Recommended:_ yes, 10% overhead and 15% margin, from a rate card pre-filled with current averages per job title.
- HR-only or Sales-only roles? _Recommended:_ not in this plan; they need per-app server rules.
- Names? _Recommended:_ Finance keeps "Maham Books"; مهام سيلز and مهام إنفنتوري, like مهام بوكس and مهام بيبول.

### 4. Document finder and AI assistant

**Status:** Partly built · **Size:** XL · **Phase:** 2 (part A, finder) and 8 (part B, AI)

Part A is a local Files page plus Ctrl K results over every stored file and paper. It works offline, folds Arabic, and serves every role. Part B is an assistant whose tools only call one read-only search RPC that runs as the signed-in person, so it sees exactly what that person's role allows.

**There now**

- `src/db/types.ts:1096-1119`: `Attachment` links to its record only by `ownerId`. It has no category and no text.
- `src/features/search/sources.ts:192-199`: the palette indexes clients, products, employees, documents and payments only. `normalize.ts:48` already folds Arabic.
- `src/features/people/bulk-documents-dialog.tsx:98-116`: reads `[ownerId+name]` index keys without loading file content.
- `src/apps/compliance/pages/compliance/documents.tsx:65-75`: register search is `toLowerCase()` only. Register rows and expenses have no URL of their own.
- `supabase/migrations/20261004000000_almailbooks_cloud.sql:193,279,991`: `record_is_private`, `can_read_record`, and `pull_records` (security invoker). `src/cloud/roles.ts:92` mirrors them.
- `src/alerts/server.ts:191-200`: reads `public.records` as the database owner, which bypasses RLS. There is no AI code.

**Missing**

- Search over register rows, derived papers (`src/lib/compliance.ts:232`), expenses, assets and cheques.
- Deep links `?doc=` and `?open=`.
- Server search and the assistant function.
- PDF text. pdf.js only renders pages (`src/components/pdf/pdf-preview.tsx:12`).

**Database**

- Local: part A adds only an optional company switch `fileFinder?` (D1). Phase 8 adds optional, unindexed fields `Attachment.text?` (20,000 characters at most), `textSource?: 'pdf' | 'ocr'`, `textHash?` and `textAt?`. They need no Dexie version, and backups carry them. No `fileIndex` table; if one is ever needed, it takes the next free version after 19 (D3). Chats stay in memory.
- Cloud: `20261228000000_document_assistant.sql` (D4).
  - `almailbooks.search_fold` matches `normalizeSearch`.
  - `record_search_text` lists the searchable fields. It matches ID numbers but never returns them.
  - `record_summary` returns title, number, dates, status, file name and owner. It never returns salary, IBAN, PIFSS, Civil ID, passport, phone, notes or `dataUrl` (D16).
  - Real tables `assistant_settings` (`enabled`, `include_people`, `ocr`, all false; limits) and `assistant_usage` (requests and tokens per user per day). RLS on, privileges revoked, cascade deletes.
  - No new tbl, no cron.

**Server API**

- `public.search_company_records(p_company text, p_query text, p_kinds text[], p_from date, p_to date, p_include_private boolean default false, p_limit int default 20) → table(tbl, id, summary jsonb, score real)`:
  - Security invoker. RLS applies, plus an explicit `can_read_record` check.
  - Queries up to 200 characters, at most 50 rows.
  - Non-members, Maham App users included (D9), get `almail:not_member` (42501).
- `public.assistant_settings(p_company)`: any member, through `optionalRpc`.
- `set_assistant_settings`: owner only (D5).
- `assistant_usage_report`: owner and admins.
- `document-assistant`, one more entry in the multi-entry build (D2). `verify_jwt = false`; it checks the session itself, as `server.ts:487-503` does.
  - `GET` → `{ok, database, model}`.
  - `POST {action:'ask', companyId, language, messages}` (10 turns at most) → `{ok, answer, refs, usage}` or an error (`auth`, `not_member`, `not_enabled`, `too_many`, `not_configured`, `declined`, `failed`).
  - Tools query with `set local role authenticated` and the caller's claims (as `src/cloud/sql-harness.ts:161-168`). `companyId` is never a tool argument.
  - `POST {action:'read', attachmentId}`: OCR after the owner opts in, downloaded with the caller's token.
- Model calls:
  - `@anthropic-ai/sdk`, with `ASSISTANT_MODEL` defaulting to `claude-opus-5-5` and `output_config: {effort: 'low'}` (its default is `medium`; thinking can't be turned off on this model).
  - `strict` tools with `tool_choice: auto`, because forced choice is refused.
  - `fallbacks: 'default'` with the beta header `server-side-fallback-2026-07-01` (Claude API only). A final `stop_reason: 'refusal'` becomes `declined`.
  - At most 4 tool rounds. The prompt is cached and `stop_reason` is checked.
  - Secret: `ANTHROPIC_API_KEY`.

**Screens and components**

- Part A:
  - `src/features/files/file-index.ts`: owner and route from index keys. People files are private through `isPrivateRecord`.
  - `src/features/search/`: `file` and `paper` kinds in `rank.ts`. `sources.ts` gets the new entries and `command-palette.tsx` opens files with `openAttachment`. In `recent.ts`, employee files stay under `/employees`.
  - `src/pages/files.tsx` at `/files`, with "Files" (الملفات) in `src/apps/compliance/manifest.ts`.
  - `?doc=` in `documents.tsx`, `?open=` in `expenses.tsx`.
  - `src/i18n/ar/files.ts`.
- Part B:
  - `src/assistant/{edge,server,tools,prompt,summary}.ts` and a shared `src/functions/sql-as.ts`.
  - `CloudApi` methods, with fakes in `src/cloud/testing/fake-cloud.ts` and `e2e/cloud-fake.ts`.
  - `src/features/assistant/assistant-panel.tsx`: plain-text answers and cards built only from refs. A missing ref shows "not synced yet" (لم تتم مزامنته بعد). Opened from the palette with "Ask the assistant" (اسأل المساعد).
  - `src/pages/settings/assistant.tsx`, titled "Document assistant" (مساعد المستندات) and registered like alerts (`src/pages/settings/index.tsx:42,57,171`).
  - `src/lib/pdf-text.ts`, `src/features/files/extract.ts` and `src/i18n/ar/assistant.ts`.

**Steps**

1. `file-index.ts` and its tests.
2. Palette kinds and sources. Arabic folding in the register.
3. `/files`, the deep links, Arabic strings and e2e. Ships in Phase 2.
4. Migration. Move the privacy fixture to `src/cloud/testing/sql-fixture.ts` and add the migration to `MIGRATIONS`.
5. Server code with injected dependencies. Tools receive only `sqlAs(userId)`.
6. Function entry, `config.toml`, deploy health check, `docs/document-assistant.md`, and a pinned SDK.
7. App API, Settings, the panel and e2e.
8. Release switched off (D1). Check production as the owner and as staff.
9. PDF text extraction: throttled, writer roles only, skipped when `textHash` equals `contentHash`. Then optional OCR.

**Tests**

- Unit:
  - `file-index.test.ts`: never reads content; hides People files.
  - `sources.test.ts`: Arabic variants and number formats.
  - `pdf-text.test.ts`.
  - `src/assistant/server.test.ts` (fake Auth and Claude): status codes, the 4-round stop, an invented `companyId` ignored, staff get no private rows, no questions in logs.
- SQL (`src/cloud/assistant-sql.test.ts`):
  - Staff and viewers get no PRIVATE ids.
  - Summaries have no salary, IBAN or IDs.
  - Limits hold under concurrency.
  - The migration runs twice.
  - `search_fold` equals `normalizeSearch`.
- e2e:
  - `e2e/files.spec.ts`: works offline; staff see no employee files.
  - `e2e/assistant.spec.ts`: owner asking in Arabic, staff, offline, missing RPC.

**Risks**

- Searching through the owner connection (the alerts pattern) would leak private rows. Mitigation: only `sqlAs`, and SQL tests run as staff.
- People data reaching Anthropic. Mitigation: `include_people` off, the whitelist, and no prompt logs.
- Prompt injection through file names. Mitigation: read-only tools limited to the caller's role, and links taken only from refs.
- Cost. Mitigation: off by default, limits, and an Anthropic spend limit.
- A text backfill flooding sync. Mitigation: the 20k cap (`PUSH_BYTES` is 512 KB, `src/cloud/sync.ts:47`), throttling and the hash check.
- Unsynced changes are invisible to the cloud. Mitigation: the panel says so when the outbox is not empty.

**Decisions for the owner**

- People data and OCR of scans? _Recommended:_ both off. If on, send metadata only (never IDs, salaries or IBANs), with a second opt-in for employee scans.
- Model and budget? _Recommended:_ `claude-opus-5-5` at low effort, about USD 0.05 a question. `claude-haiku-5-5` costs about a fortieth of that and is one setting away. Limits of 300 a day and 30 per person per hour, plus a spend limit.
- Whose Anthropic account holds the key? _Recommended:_ a company-owned workspace. The key is stored only as a Supabase secret.

### 5. Integrations in the sidebar: Deema, Taly, Tahseel

**Status:** Partly built · **Size:** M · **Phase:** 2 (part B: 6)

Phase 2 extends the existing company links: Deema, Taly and Tahseel presets, an _Integrations_ (التكاملات) sidebar heading and a choice of apps per link, opening in a new tab as today. API work (part B) is #26's payment gateway, Phase 6.

**There now**

- `src/db/types.ts:509-517`: `CompanyLink { id, label, labelAr?, url }` on `Company.links`; `src/lib/links.ts:4,11-36`: up to 8 http/https links, checked again when they arrive from other devices.
- `src/pages/settings/links.tsx`: Settings → Links with English and Arabic names.
- `src/features/shell/sidebar.tsx:150-175,237`: one flat list in every app's sidebar, `rel="noopener noreferrer"`; `src/suite/home/launcher.tsx:189-193`: "Company tools" tiles.
- `src/lib/payment-methods.ts:102-117`: Deema and Taly already exist as BNPL providers (clearing 1020, fees 6180); `providerLabel` falls back to the raw value (`:127-129`). Tahseel is unknown; تحصيل appears only as cheque collection (`src/lib/accounting/charts.ts:223`).

**Missing**

- Presets, a section, per-app placement, a Tahseel link provider, any API.

**Database**

- Local: `CompanyLink.section?: 'integrations'` (missing = today's list, D1), `preset?: 'deema' | 'taly' | 'tahseel'`, `apps?: string[]` (missing = every app); `PaymentLinkProvider` + `'tahseel'` once confirmed. No Dexie or backup change.
- Cloud: No change in Phase 2. Part B uses #26's `20261214000000_payment_gateway.sql` (`gateway_accounts` with keys in Vault, `gateway_events`, tbl `gatewayPayments`) rather than separate integration tables, so there is one gateway model.

**Server API**

- Phase 2: None: runs on the device. Part B: provider adapters in #26's `payment-links` Edge Function (member JWT to create a link; signed webhooks, idempotent on the provider reference); keys per company in Vault.

**Screens and components**

- `src/lib/links.ts`: `LINK_PRESETS` (ديما, تالي, Tahseel) and `sidebarLinks(links, appId)`.
- `src/pages/settings/links.tsx`: _Add Deema / Taly / Tahseel_ fill the names, the owner pastes the portal address; section and app choices; a warning for `token`, `key` or `secret` parameters.
- `src/features/shell/sidebar.tsx`: a collapsible _Integrations_ group like `SidebarGroup` (`:261`), filtered by `useCurrentApp`, neutral icons; matching home tiles (`src/suite/home/tiles.ts`).
- `src/lib/payment-methods.ts`: `{ value: 'tahseel', label: 'Tahseel', kind: 'link' }`.
- Arabic in `src/i18n/ar/links.ts`, `src/i18n/ar/payments.ts`.

**Steps**

1. Optional link fields and the app filter, with tests.
2. Presets and choices in Settings → Links.
3. Sidebar group and home tiles; e2e.
4. Tahseel provider once confirmed.

**Tests**

- `src/lib/links.test.ts`: presets valid; app filter; no section stays in Tools; unknown preset ignored.
- `src/lib/payment-methods.test.ts`: `providersFor('link')` includes `tahseel`; the BNPL list is unchanged.
- `e2e/links.spec.ts`: three presets under Integrations only in the chosen app; new tab; Arabic names.

**Risks**

- Links reach every member and backup, so keys never go in them. Only owner, admin and accountant save them (`src/cloud/outbox.ts:115-121`). Older builds ignore the new fields and show a flat list.
- تحصيل already means cheque collection here: label Tahseel by its brand name.
- Part B: net-of-fee money in 1020 must match bank deposits; automatic payments must be idempotent and numbered by `reserve_number`.

**Decisions for the owner**

- Is Tahseel the CBK-listed Tahseeel.Com collection service? _Recommended:_ confirm before adding it as a provider.
- Which apps show the links? _Recommended:_ Finance (Books) and Sales.
- API integration now? _Recommended:_ links now; Tahseel invoice links in Phase 6; BNPL checkout once merchant contracts exist.

## 2. Roles and Super Admin approvals

### 6. Super Admin with full control of roles and permissions

**Status:** Partly built · **Size:** L · **Phase:** 3

The Super Admin is the company owner (D5): Mr. AbdulAziz Almail takes ownership of each company with the existing _Transfer ownership_, and no code holds the Super Admin's name or email. The server then lets only the owner grant admin or accountant, and adds restrict-only app limits per member and a `can_approve` deputy flag.

**There now**

- `src/cloud/roles.ts:9-35`: five fixed roles; `canManageTeam` (`:139-141`) is owner or admin.
- `supabase/migrations/20261004000000_almailbooks_cloud.sql:92-93`: one owner per company. `:1141`, `:1354`, `:1403`: admins also invite, change roles and remove members; `transfer_ownership` (`:1412-1438`) is owner only.
- Same file `:736-762`: if the owner's account is deleted, the oldest admin, or else an accountant, becomes owner. No team change is recorded.
- `src/pages/settings/team.tsx:271`: owner and admins change anyone's role but the owner's and their own; `:381-430` transfers ownership.
- `src/suite/access-grid.tsx:38`: read-only role × app grid; access is fixed per role in each manifest (`src/apps/books/manifest.ts:185`).

**Missing**

- Owner-only senior roles, per-member limits, an approver flag, an audit of team changes, an overview of owned companies.

**Database**

- Local: no Dexie change. `CloudLink` (`src/cloud/types.ts:11`) gets optional `permissions?: {apps?: Partial<Record<AppId, AppAccess>>}` and `approver?: boolean`, filled on refresh (`src/cloud/manager.ts:182`); not synced or backed up. `src/cloud/roles.ts`: `isSuperAdmin`, `effectiveAccess` (lower of role default and limit).
- Cloud: `20261116000000_super_admin_approvals.sql` (D4). `company_members.permissions jsonb default '{}'` and `can_approve boolean default false` (admin or accountant rows only, so deputies see People data for #10). `almailbooks.is_approver(p_company)` = owner or `can_approve`. `can_write_record` applies app limits through a table→app map; a file follows the record it is kept with (`almailbooks.attachment_app`), and the books' settings on the company record (lock date, numbering rules, payment details with the bank account and WAMD number, email templates, document defaults) are Books' (`records_guard`, `almailbooks.company_books_changed`); `'{}'` gives today's result. `create_invite`, `set_member_role`, `remove_member` keep their signatures; only the owner touches admin or accountant. A `company_members` trigger records role, permission and succession changes as kind `member` in `change_events` (D7), doing nothing until `20261123000000_change_feed.sql` creates it. No `super_admin` enum value: checks read `role in ('owner','admin','accountant')` and would deny it. No platform admin: sign-up is open (`src/cloud/auth.ts:83`).

**Server API**

- `public.set_member_permissions(p_company text, p_user uuid, p_permissions jsonb, p_can_approve boolean) → void`: owner only; the owner's row is refused (42501).
- `public.team_permissions(p_company text) → table(user_id uuid, permissions jsonb, can_approve boolean)`: owner and admins all rows, others their own.
- `public.my_permissions(p_company text) → table(permissions jsonb, can_approve boolean, is_owner boolean)`: any member, through `optionalRpc` (`src/cloud/supabase-api.ts:82-108`).
- `public.owned_companies_overview() → table(company_id text, name text, members bigint, pending_approvals bigint)`: companies the caller owns.
- No Edge Function or secret.

**Screens and components**

- `src/pages/settings/team.tsx`: admins offered staff and viewer only; badge 'Owner (Super Admin)' / 'المالك (المشرف العام)' (`:519`); _Permissions_ opens new `src/pages/settings/member-permissions.tsx` (none/view/edit per app, capped at the role; _Can approve_ / 'صلاحية الاعتماد').
- `src/suite/access-grid.tsx`: editable mode. `appAccess` and `accessMap` (`src/suite/apps.ts:52-64`) and `useRoleView` (`src/features/cloud/role-gates.tsx:24`) read the limits.
- API in `src/cloud/api.ts`, `supabase-api.ts`, `testing/fake-cloud.ts`, `e2e/cloud-fake.ts`; _Companies you own_ in `src/pages/settings/companies.tsx`; Arabic in `src/i18n/ar/cloud.ts`.

**Steps**

1. No code: check who owns each production company; the current owner transfers it to Mr. AbdulAziz Almail's account.
2. Labels, badge, `isSuperAdmin`, Arabic.
3. Migration: owner-only team rules; update `supabase/README.md:39-52`. SQL tests.
4. Migration: columns, `is_approver`, RPCs, write limits; re-run the roles cases of `src/cloud/sql.test.ts` with `'{}'`.
5. Client: manager stores limits; `appAccess`, `useRoleView`, `refuse()` (`src/cloud/outbox.ts:109-125`) apply them.
6. Dialog, grid, overview, e2e; tell current admins before release.

**Tests**

- SQL `src/cloud/super-admin-sql.test.ts`: only the owner grants admin or accountant; a transfer moves the powers; `set_member_permissions` refused to everyone else; staff with `books: 'view'` can't push documents; `'{}'` matches today.
- Unit `src/cloud/roles.test.ts`, `src/suite/apps.test.ts`; one fixture checked by fake-cloud and SQL (pattern of `src/cloud/review-roles.test.ts`).
- e2e `e2e/cloud.spec.ts`: a limited member sees view-only and a forced write is parked.

**Risks**

- `can_write_record` is in every records and storage policy; a bug stops all sync. Default `'{}'`, full regression run.
- App 'none' hides the app and blocks writes, but data already on a device stays (D16).
- Admins lose powers they use today: tell them first. Old builds get 42501 and park the change.

**Decisions for the owner**

- May admins still invite and remove staff and viewers? _Recommended:_ yes; only the Super Admin grants admin or accountant.
- Deputies? _Recommended:_ up to two admins or accountants with _Can approve_, off by default.
- If Mr. AbdulAziz Almail's account is deleted, who becomes owner? _Recommended:_ today's rule (oldest admin), now recorded.

### 7. Change notifications to the Super Admin

**Status:** Partly built · **Size:** L · **Phase:** 3

A server-side change feed (D7) records who changed what. The Super Admin sees it in an in-app bell as soon as a device syncs, and by email digest within about five minutes; phone push waits for Phase 7.

**There now**

- `src/db/activity.ts:32-64`: `logActivity` writes a bilingual `Activity` on the device, with no author (`src/db/types.ts:1044-1068`).
- `supabase/migrations/20261004000000_almailbooks_cloud.sql:617`: the server stamps `updated_by`, but `pull_records` (`:991-1027`) never returns it and keeps no history. `push_records` (`:890-986`) is one transaction of up to 500 rows; devices hear it through `api.watch` (`src/cloud/api.ts:235`).
- `supabase/migrations/20261007000000_email_alerts.sql:113-140`: `run_email_alerts` posts `{"action":"run"}` through `pg_net`; hourly cron at `:274-278`. The function handles `run` and `send` (`src/alerts/server.ts:604-617`).
- `src/suite/home/attention.ts:1-40`: the suite home's "needs attention" list, filtered by app access.
- `docs/email-alerts.md:51-52`: Resend's free plan sends 100 emails a day.

**Missing**

- Change history, "by whom", a bell, unread state, a fast email path, flood control.

**Database**

- Local: optional `Activity.by?` / `byName?` set by `logActivity` (D8); `ActivityEntity` gains `'approval' | 'member'`. No Dexie version.
- Cloud: `20261123000000_change_feed.sql` (D4).
  - `public.change_events(id identity, company_id, at, actor, op, tbl, record_id, kind, important, private, count, fold_key, summary jsonb)`, unique `(company_id, fold_key)`; RLS on, no grants.
  - AFTER trigger `records_change_event` on `public.records`, inside `exception when others`. Skips `old.data = new.data`, a null actor and `delete_company`. Ordinary writes of one push fold into one row per table and actor (`fold_key` = transaction id + tbl + actor). A device sends at most 200 changes or 512 KB per push (`PUSH_BATCH`, `PUSH_BYTES`, `src/cloud/sync.ts:46-47`), so an import of N rows becomes about N/200 events per table, which the digest then groups by actor and table. The server can't tell an import from other writes, so this folding takes the place of D7's 'skips imports'. Important changes stay one row each: invoice voided or edited after issue, cheques, approvals, numbering, lock date, `approvalRules`, pay runs. Private summaries carry no names or amounts (D16).
  - `public.notification_settings` (per user: enabled, immediate kinds, digest, cursor, daily count, `claimed_until`) and `public.notification_reads(read_upto)`.
  - Cron `*/5 * * * *` calls `almailbooks.run_change_notifications()`, posting `{"action":"notify"}` only when a setting is on; daily purge after 180 days.

**Server API**

- `public.notification_feed(p_company text, p_after bigint) → table(id, at, actor_name, kind, tbl, record_id, count, important, summary, unread)`: owner and approvers; private rows only to owner, admins and accountants; the caller's own changes left out.
- `public.mark_notifications_read(p_company text, p_upto bigint) → void`.
- `public.change_notification_settings(p_company text)` and `public.set_change_notifications(p_company text, p_enabled boolean, p_immediate_kinds text[], p_digest text, p_app_url text)`: owner and approvers (named like `email_alert_settings`, not clashing with the table).
- Existing `email-alerts` function, `POST {action: 'notify'}` with the scheduler secret: groups new events by actor and kind, applies caps, renders en/ar, sends with a Resend `Idempotency-Key` → `{ok, sent, skipped}`. Secrets unchanged (`RESEND_API_KEY`, `ALERTS_FROM`).

**Screens and components**

- `src/features/notifications/bell.tsx` next to `AppSwitcher` (`src/features/shell/header.tsx:88`); refetches on `api.watch` and focus.
- `src/pages/notifications.tsx` at `/notifications` (`src/app/routes.tsx:101`): by day, filters, _Mark all as read_, links to records.
- _Changes by your team_ section in `src/pages/settings/alerts.tsx`; `src/alerts/changes.ts`, `renderChangesEmail` in `src/alerts/email.ts`.
- Arabic in `src/i18n/ar/alerts.ts`: 'تغييرات الفريق', 'تعليم الكل كمقروء'. Never 'الإشعارات' (credit notes) or 'تنبيهات' (morning alerts). The bell also shows #18's document reminders, so it needs one general name, for example 'المستجدات' (Updates), and #18 uses the same name.

**Steps**

1. Migration: table, trigger, feed RPCs, settings, cron, purge. SQL tests with a 500-row push.
2. Author stamp in `logActivity`; timelines show "by".
3. Client API, bell, page, Arabic, e2e.
4. `notify` action, server tests, `docs/email-alerts.md`.
5. Switch on for the owner only, watch volume for a week, tune.

**Tests**

- SQL `src/cloud/change-feed-sql.test.ts`: actor recorded; unchanged re-push → nothing; 200-row push → one row; a forced trigger error doesn't abort the push; private events never reach staff or viewers.
- Edge `src/alerts/server.test.ts`: caps, own changes left out, no double send (`claimed_until`, idempotency key), Arabic subject. Unit `src/alerts/changes.test.ts`, `src/alerts/email.test.ts`.
- e2e: a second member edits an invoice; the owner's bell shows it with their name.

**Risks**

- The trigger runs inside every push; a failure would stop all sync. Exception guard and tests.
- 100 emails a day shared with the morning alerts: per-person caps or a paid plan.
- Emails leave the system: People events carry no names or amounts; links open the signed-in app (D14).
- Old builds are unaffected: the feed is server-only.

**Decisions for the owner**

- Who receives? _Recommended:_ the Super Admin and deputies.
- What is emailed within 5 minutes? _Recommended:_ the important changes above; the rest in a daily 08:00 digest.
- Caps? _Recommended:_ one email per 15 minutes, 20 a day; the bell has everything.

### 8. Invoice approval and Void invoices

**Status:** Needs a decision · **Size:** XL · **Phase:** 3

Edits, voids and deletes of issued invoices by non-approvers become requests in the approvals service (D6), applied on the approver's device. Deleting an issued invoice becomes a void that keeps its number under _Void invoices_; numbers are not freed (D12): drafts are numbered only when issued, and a correction gets a new number linked to the original.

**There now**

- `src/db/types.ts:58`: `InvoiceStatus` has `'void'`. `setDocumentStatus` (`src/db/documents.ts:679-748`) keeps document and number; `src/pdf/model.ts:641` prints VOID; `isPosted` (`src/lib/accounting/ledger.ts:222`) leaves voids off the ledger.
- `src/apps/books/pages/documents/list.tsx:57,171`: a Void filter as `?status=void`, already a _Void invoices_ view.
- `src/apps/books/pages/documents/view.tsx:253-288,447-451,513`: delete, void, un-void and _Edit_ at any status for anyone who may write documents. `deleteDocument` (`documents.ts:764-826`) hard-deletes, leaving payments as unapplied credit.
- Drafts are numbered at first save (`documents.ts:616-633`); `takenNumbers` counts voids (`:326-333`); reuse throws `DuplicateNumberError` (`:429`); the cloud counter only moves forward (`20261006000000_sync_fixes.sql:193`).
- `20261004000000_almailbooks_cloud.sql:260-329`: rules by role and table only; staff may delete documents. The lock date is checked only on devices.
- Refused pushes are found by halves and parked (`src/cloud/sync.ts:729`); 42501 becomes `permission` (`src/cloud/api.ts:332`).

**Missing**

- Requests, a server guard, void reason/who/when, a "replaces" link, unnumbered drafts.
- Reusing numbers conflicts with accounting practice and with the code by design (D12).

**Database**

- Local: Dexie v16 `approvals` (D3) with D6 fields; kinds `invoice_edit`, `invoice_void`, `invoice_unvoid`; type `ApprovalRequest`. Optional on `InvoiceDocument`: `voidedAt`, `voidedBy`, `voidReason`, `approvalId`, `replacesId`, `replacedById`. `Company.approvalRules?: {documentTypes?, voidInsteadOfDelete?, expireDays?, cheques?, payroll?}` (`cheques` from #9, `payroll` from #10), absent = off (D1). `DocumentDefaults.numberOnIssue?` (`types.ts:117`). Catch-up after upgrade: D2.
- Cloud: tbl `approvals` comes with `20261102000000_tables_v16.sql`. `20261116000000_super_admin_approvals.sql` adds:
  - `almailbooks.approval_rules(p_company) → jsonb`; `almailbooks.invoice_content(p jsonb) → jsonb`, the printed fields (party, dates, currency, lines, discounts, taxes, charges, deposit, retention terms, wording, template). Totals, paid status, posting and retention releases stay out: payments and sync write them. The payment link (printed, and in the QR code) has its own rule, `almailbooks.payment_link_changed`: once an issued invoice has one, only an approver changes or removes it (the app refuses it; the server keeps the stored link from anyone else's copy, since documents travel whole and a device that hasn't received the link may send the invoice with a payment); adding one where there was none stays open, as links are often made after the invoice is issued.
  - `records_guard`, BEFORE INSERT OR UPDATE on `public.records`, firing after `records_before_write` by name. `approvals`: a new row is forced to `pending` with server `requestedBy`/`requestedAt`; a non-approver may only cancel their own pending request; an approver moves `pending` to `approved`, `rejected` or `applied` with server `decidedBy`/`decidedAt`, so an offline copy can't undo a decision. `documents` of a ruled type, not draft: a non-approver is refused when `invoice_content` changes or status moves in or out of `void`/`draft`. `companies`: only the owner changes `approvalRules` (covers `patch_company`). Refusal `almail:approval_required`, SQLSTATE 42501.
  - An upsert fires the INSERT trigger first (`20261004000000_almailbooks_cloud.sql:588-589`): an insert of an existing row is checked as an update.
  - `can_delete_record`: never `approvals`; no ruled issued invoice when `voidInsteadOfDelete` is on. Counters unchanged.

**Server API**

- None required: requests and decisions are records, pushed offline-first and guarded.
- Optional `public.approvals_overview() → table(company_id text, company_name text, pending bigint)`, approvers only, for the inbox across companies (D5).

**Screens and components**

- `src/db/approvals.ts` (D6): `needsApproval`, `requestApproval`, `cancelApproval`, `decideApproval`, `applyApproval` (merges the proposal into the current invoice, so totals follow today's payments), `expirePending`.
- `src/db/documents.ts`: `saveDocument`, `setDocumentStatus` and `deleteDocument` throw `ApprovalRequiredError` under the rules, covering every caller.
- `refuse()` (`src/cloud/outbox.ts:109-125`) and fake-cloud mirror the guard; `approval_required` joins `src/cloud/api.ts` codes and `PARKED_REASONS` (`src/cloud/labels.ts:42`).
- Editor: Save on an issued invoice becomes _Send for approval_ ('إرسال للاعتماد') with a reason. View: before/after banner (right-to-left safe), Approve/Reject, _Request void_, _Void and reissue_ (`duplicateDocument` with `replacesId`); PDF prints "Replaces INV-…".
- List: _Void invoices_ ('الفواتير الملغاة'), _Waiting for approval_ ('بانتظار الاعتماد').
- `src/features/approvals/` inbox; `src/pages/approvals.tsx` at `/approvals` ('طلبات الاعتماد'); Books sidebar link; count in `src/suite/home/attention.ts`.
- `src/pages/settings/approvals.tsx` (owner only); _Number invoices when they are issued_ in `src/pages/settings/numbering.tsx`; parked refusals (`src/pages/settings/cloud.tsx`) offer _Send for approval instead_. Arabic: new `src/i18n/ar/approvals.ts`.

**Steps**

1. Owner and auditor settle number reuse.
2. Types and `src/db/approvals.ts`; unit tests.
3. Guard and helpers; SQL tests.
4. TS mirror of `invoice_content`; a test runs every background write (`recalculateDocuments`, retention, `setPaymentLink`, posting freeze, conversion) and checks none is refused.
5. Guards in `documents.ts`, void stamps, paid-invoice handling.
6. Editor, view, list, inbox, settings, Arabic; two-user e2e.
7. `numberOnIssue`, _Void and reissue_.
8. Every device syncs before the owner turns rules on.

**Tests**

- SQL `src/cloud/approvals-sql.test.ts`: rules off = today. Rules on: content edits by staff, accountant or admin refused with 42501 while their payment pushes that recalculate the invoice pass; void and un-void refused to non-approvers; request stamps can't be forged; approvals can't be deleted; an admin's `approvalRules` change refused by push and `patch_company`.
- Unit `src/db/approvals.test.ts` (apply onto a changed invoice, expiry); numbering (voids keep numbers, counters never go back, `numberOnIssue`); `invoice_content` parity; `src/cloud/sync.test.ts` parks a refused edit as `approval_required`.
- e2e: staff edit → request; owner approves → both devices updated; void with reason → under Void invoices, VOID on the PDF.

**Risks**

- A reused number puts two legal documents under one number (sent PDFs, payment links, customers' books); hence D12.
- A protected list too broad parks routine writes; too narrow lets edits escape. Parity test.
- A guard bug blocks every document push: gated on `approvalRules`, small, tested.
- Voiding rewrites the original period; prefer credit notes in closed periods.
- `numberOnIssue`: lists, search and duplicate checks that expect a number need a "Draft" placeholder.
- Old builds park refused edits; device-only companies are not covered (D5).

**Decisions for the owner**

- Instead of reusing numbers: the void keeps its number, the reissue gets a new linked one, drafts are numbered on issue? _Recommended:_ yes; confirm with the auditor.
- Which documents? _Recommended:_ invoices and credit notes first.
- May the Super Admin hard-delete issued invoices? _Recommended:_ no; drafts only.
- Voiding a paid invoice? _Recommended:_ its payments become unapplied customer credit, as delete does, and the request says so.
- Expiry? _Recommended:_ pending requests cancelled after 14 days.

### 9. Cheque confirmation by the Super Admin

**Status:** Partly built · **Size:** L · **Phase:** 3

Under the rules, a cheque recorded by a non-approver is saved as an approvals request holding the proposed payment, not as a Payment (D13). Confirming runs the normal `savePayment` on the approver's device, so nothing reaches the ledger or invoice balances early and older builds have nothing to post.

**There now**

- `src/db/types.ts:848`: `ChequeStatus` is a closed union; cheques are `Payment` rows (`:884`).
- `src/db/payments.ts:324` `savePayment`: every cheque path ends here: the payment form (`src/apps/books/pages/payments/form.tsx:303`), invoice and bill dialogs (`src/apps/books/features/documents/payment-dialogs.tsx:110,324`), `replaceCheque` (`src/db/cheques.ts:467`) and `cashSecurityCheque` (`:656`). `checkCheque` (`payments.ts:191`) catches duplicates.
- `postPayment` (`src/lib/accounting/ledger.ts:775-781`) posts every non-voided payment on each device, so a pending flag on a Payment would still post in older builds.
- Register `src/apps/books/pages/cheques/index.tsx:214`; filters `src/apps/books/features/cheques/register.ts:8`, `src/lib/cheques.ts:30`.
- Staff may write payments (`20261004000000_almailbooks_cloud.sql:267`); the voucher's _Approved by_ box (`src/apps/books/pages/payments/voucher.tsx:52`) is paper only.

**Missing**

- A confirmation state, an approver, a server rule, a register view of waiting cheques, a notification.

**Database**

- Local: v16 `approvals` (D3); kinds `cheque_create`, `cheque_edit`, `cheque_delete`, `cheque_replace`, `security_cheque_cash`; `after` holds the proposed `Payment` with allocations, or `{action, sourceId, input}`. Optional `Payment.approvalId?`; `Company.approvalRules.cheques?: {issued?, received?, securityOut?}`. No new `ChequeStatus` (D13).
- Cloud: same `20261116000000_super_admin_approvals.sql`. With cheque rules on, `records_guard` refuses a non-approver on `payments`: a real INSERT with `method = 'cheque'` in a ruled direction; an UPDATE that makes a payment a cheque or changes `almailbooks.cheque_content(jsonb)` (amount, currency, rate, direction, client, account, number, bank, date, drawer, drawer civil ID). Lifecycle fields, void fields, notes and allocations stay open, so staff still deposit and clear. `can_delete_record`: non-approvers can't delete cheque payments. Optional: the same for `securityCheques` going out.

**Server API**

- None: requests are guarded records. Inbox and `approvals_overview` from #8; alert from #7.

**Screens and components**

- `src/db/payments.ts`: split `savePayment` into `validatePayment` and the write, unchanged in behaviour. A non-approver's new cheque becomes `requestApproval`: validated, no number, no posting. `checkCheque` also checks pending requests.
- `src/db/cheques.ts`: `replaceCheque` and `cashSecurityCheque` become requests; the approver's device runs them on confirming.
- `src/db/approvals.ts`: applying calls `savePayment` with the request's date (when the cheque was received or written), then marks the request `applied` with the payment id.
- Form and dialogs: _Send for confirmation_ ('إرسال للتأكيد'). Register: `pending` filter _Waiting for confirmation_ ('بانتظار التأكيد'); Approve/Reject for approvers, Cancel for the requester. Invoice and bill views note a waiting cheque, so nobody records it twice.
- Labels in `src/lib/status.ts`; Arabic in `src/i18n/ar/payments.ts`.

**Steps**

1. Split `savePayment`; existing payments and cheques tests pass unchanged.
2. Payments guard and delete rule; SQL tests.
3. Requests and apply for new cheques, replacements and cashing; db tests.
4. Register, form button, invoice note, Arabic, e2e.
5. Dry run on the demo company, then turn on `cheques.issued`.

**Tests**

- SQL (`src/cloud/approvals-sql.test.ts`): a staff or accountant cheque refused, an approver's accepted; staff deposit, clear and return pass; amount or number change refused; delete refused; other methods untouched; rules off = today.
- Unit `src/db/cheques.test.ts`, `src/db/payments.test.ts`: a pending request leaves `buildLedger`, invoice balances, register and alerts unchanged; applying numbers and posts it; applying fails clearly when an allocated invoice was paid meanwhile; duplicate cheque numbers across requests refused.
- e2e `e2e/cheques.spec.ts`: staff cheque → waiting, not Open; owner confirms → issued and posted; reject → gone, reason kept.

**Risks**

- Received cheques waiting make invoices look unpaid, so paying customers could get reminders: default is issued only.
- The paper cheque may leave before confirmation: a process rule, not code.
- Payment numbers follow confirmation order; a request dated in a period locked meanwhile can't be applied, and the UI says why.
- Old builds: a direct cheque is refused (42501) and parked.

**Decisions for the owner**

- Which cheques? _Recommended:_ issued and security cheques given out; received off.
- Edits and deletes? _Recommended:_ amount, payee, number, bank, date and delete need confirmation; deposit, clear, return and cancel don't.
- A threshold below which no confirmation is needed? _Recommended:_ none at first.

### 10. Salary approval by the Super Admin

**Status:** Partly built · **Size:** XL · **Phase:** 4

_Send for approval_ on a draft pay run creates a `payroll` request in the shared approvals service (D6). The server then emails the approvers totals by department and position, with a link into the signed-in app (D14). Posting (_Approve_) stays blocked until that request is approved for the unchanged run, so pay runs keep their three statuses.

**There now**

- `src/db/types.ts:1764`: `PayRunStatus` is `draft | approved | paid`, where `approved` means posted. A new status would break `RUN_STATUS[status]` (`src/features/payroll/shared.tsx:61-69`) and the `status !== 'draft'` checks (`src/db/payroll.ts:706`).
- `src/db/payroll.ts:1240`: `approvePayRun` recalculates and posts salaries, provisions and PIFSS loans. Any owner, admin or accountant can run it, with no sign-off.
- `src/apps/people/pages/payroll/run.tsx:198-216`: the Approve dialog. The button is at `:314`, Payslips at `:320`.
- `src/db/types.ts:1808-1809`: `PayLine` already has `jobTitle` / `jobTitleAr`, so the by-position breakdown needs no new field. Department comes from #12.
- `src/alerts/server.ts:320`: `sendEmail` (Resend, idempotency key). `:576`: `handleAlertsRequest` dispatches on `action`.
- `docs/email-alerts.md:30-31`: emails "never show … salaries".

**Missing**

- A record of who approved which numbers, and a rule that requires one.
- A breakdown by department and position.
- Any payroll email.

**Database**

- Local: no new table. A request is an `approvals` row (D3 v16) with:
  - `kind: 'payroll'`, `subjectTbl: 'payRuns'`, `subjectId`;
  - `subjectNumber`: the period;
  - `after: {runUpdatedAt, totals, groups}`, group totals only, no names.

  There is no separate `payRunApprovals` table, so D6's inbox, guard and notifications apply. The row is private (People subject, D3). The switch is the owner-only `Company.approvalRules.payroll` (D6), not `PayrollSettings`, which accountants can write.

- Cloud: `20261130000000_people_alerts.sql` (D4), added to `MIGRATIONS`, contains:
  - an `AFTER INSERT` trigger on `public.records` for pending `payroll` approvals. It calls email-alerts through `net.http_post` with the secret from `almailbooks.email_alerts_config`. It does nothing without `pg_net`, and `exception when others` means it never blocks a push.
  - `almailbooks.approval_emails (approval_id, user_id, sent_at, error)`, which tracks sends for retries.
  - a payroll rule in `records_guard` (D6): approving is refused (`42501`) when the run's stored `updatedAt` no longer equals `after.runUpdatedAt`.

**Server API**

- `email-alerts` `POST {action: 'payroll_approval', companyId, approvalId}` → `{sent}`, authenticated by `x-alerts-secret`. The trigger calls it. The D7 5-minute `notify` run retries any request that has not been sent.
  - Recipients: the owner and the `can_approve` members with confirmed emails (D5), each in their own language.
  - Content: headcount, gross, deductions, net, employer PIFSS, the change since last month, and totals by department and position. One-person groups merge into "Other positions".
  - Links are built from the new secret `MAHAM_APP_URL`, or else the recipient's `email_alerts.app_url`. They are never taken from the client.
  - Idempotency key: `payroll-approval/<approvalId>/<userId>`.
  - Secrets: `RESEND_API_KEY`, `ALERTS_FROM`, `MAHAM_APP_URL`.
- No token or one-click link (D14): the link opens the D6 Approvals page, and opening it decides nothing. The sender sees the outcome in the D7 feed.

**Screens and components**

- `src/lib/hr/payroll.ts`: `payrollBreakdown(lines, precision)`, grouped by department and then job title.
- `src/apps/people/pages/payroll/summary.tsx`: a printable register (كشف الرواتب حسب القسم والوظيفة). Its route `payroll/runs/:id/summary` goes in `peoplePrintRoutes` (`src/apps/people/routes.tsx:35`).
- `run.tsx`:
  - _Send for approval_ (إرسال للموافقة), with a note;
  - a status strip: awaiting (بانتظار الموافقة), approved by whom and when, rejected with the note, or changed since it was sent.

  _Approve_ keeps اعتماد (`src/i18n/ar/payroll.ts:32`) for posting. The Super Admin's decision uses موافقة.

- `src/features/payroll/approval-panel.tsx`: what the D6 Approvals page shows for `kind: 'payroll'`. It includes per-person lines, which appear in the app only.
- `src/db/payroll.ts`:
  - `requestPayrollApproval(runId, note)`.
  - `approvePayRun` posts only when an approved request matches `run.updatedAt`. It then marks that request `applied`.
- `src/alerts/payroll-approval-email.ts`: the email in English and Arabic, right to left in Arabic. Its strings go in `src/i18n/ar/alerts.ts`.

**Steps**

1. `payrollBreakdown` and the summary page (useful without approvals too).
2. The request helper and the posting gate, behind the switch (D1).
3. The migration, with PGlite tests.
4. The email renderer, the action and the `notify` retry.
5. The strip, the panel, and the owner's switch on the D6 rules screen.
6. Docs: totals in `docs/email-alerts.md`, `MAHAM_APP_URL` in `docs/supabase-setup.md`.
7. Release: migration, app, then the owner switches it on.

**Tests**

- Unit:
  - `src/lib/hr/payroll.test.ts`: the breakdown adds up to `payRunTotals` (`src/lib/hr/payroll.ts:425`).
  - `src/db/payroll.test.ts`: posting is refused when the request is missing, pending, rejected or stale. Nothing changes when the switch is off.
  - `src/alerts/server.test.ts`: a wrong secret returns 401. Emails go only to approvers. No names, IBAN or Civil ID appear. One-person groups are merged. Links ignore client input. A retry reuses the same key.
- SQL: `src/cloud/people-alerts-sql.test.ts`: one call is queued per request. A stale approval is refused. Staff and viewers never read the row.
- e2e: `e2e/payroll.spec.ts` with the fake cloud: send, approve, then post. An edit after sending asks for a new approval.

**Risks**

- Salary totals stay in mailboxes and in Resend's log. Mitigation: totals only, with one-person groups hidden (D14).
- An older tab ignores the switch and can post. Mitigation: the switch stays off until devices update, and the D7 feed reports every posted run. A server-side refusal was rejected because the run's journal entries would still sync.
- Any edit after sending voids the approval. The strip says why. Device-only companies don't get the feature (D5).

**Decisions for the owner**

- May the email show totals by department and position? _Recommended:_ yes, totals only.
- Is approval required or advisory? _Recommended:_ required once the switch is on.
- May a deputy approve a run they sent themselves? _Recommended:_ no. Only the owner may approve their own.

## 3. Employees and HR

### 11. Leave requests from the Maham App

**Status:** Not built · **Size:** XL · **Phase:** 7

A guard asks for leave in the Maham App (D10) through a narrow RPC that writes a private `leaveRequests` record (D9). HR devices pull it through the normal sync, and HR approves it in Maham People, which turns it into an ordinary approved `LeaveRecord`. Requests get their own table because `LeaveRecord.status` is a closed list (`'approved' | 'cancelled'`, `src/db/types.ts:1929`) that older builds show and filter on. The `LEAVE_TYPES[r.type]` lookups (`src/features/payroll/employee-tabs.tsx:228`) are tolerant from Phase 0 (D2, #15).

**There now**

- `src/db/types.ts:1918-1932`: `LeaveRecord.status` is `'approved' | 'cancelled'`. There is no requester, no approver and no pending state.
- `src/db/payroll.ts:670` `createLeaveRecord` defaults to approved. `:745` `saveLeaveRecord` counts days and calls `assertPayUnchanged` (`:699`) in one transaction. `:800` `cancelLeaveRecord` soft-cancels.
- `src/lib/hr/leave.ts:119` `countLeaveDays`, `:128` `isTaken` (approved only), `:385` `employeeLeaveBalance`, `:448` `leaveWarnings`: pure code the Maham App can reuse. Pending requests never touch balances.
- `supabase/migrations/20261004000000_almailbooks_cloud.sql:202`: `leaveRecords` is private. `:295`: any role other than owner, admin or accountant reads all non-private data, so employees must not be members (D9). `:1316-1326`: invites need a confirmed, matching email, which guards don't have.
- `src/cloud/auth.ts:83,109`: email and password sign-in only.
- `src/apps/people/manifest.ts:59-65` has the _Leave_ link; `src/apps/people/routes.tsx:69` has `payroll/leave`.

**Missing**

- Employee identity, phone sign-in and the Maham App itself.
- A request record linked to the `LeaveRecord` it creates, an HR queue, and app access (invite, revoke).

**Database**

- Local: in `src/db/types.ts`, a new `LeaveRequest {id, companyId, employeeId, type: LeaveType, reasonId?, start, end, days, note, status: pending|approved|rejected|withdrawn|cancelled, source: 'app'|'hr', submittedAt, decidedAt?, decidedBy?, decisionNote?, leaveRecordId?}` and an optional `LeaveRecord.requestId?`. `reasonId` points to a #15 reason that has a base `type` (D11). Dexie **19** (D3): `leaveRequests: 'id, companyId, employeeId, [companyId+status]'`. Add it to `DATA_TABLES`, `backupSchema` with `.default([])`, `src/cloud/labels.ts`, `PEOPLE_TABLES` and the fake cloud. Older devices catch up through the Phase 0 backfill (D2).
- Cloud: `20261221000000_employee_app.sql` (D4):
  - real tables `employee_invites` (long token, phone snapshot, 7-day expiry) and `employee_accounts (company_id, user_id, employee_id, revoked_at, last_seen_at)`;
  - `almailbooks.my_employee_id(p_company)`, which returns null once the employee is `left`;
  - tbl `leaveRequests` in `records_tbl_check`, `record_is_private` and the Phase 0 restrictive People policy;
  - `records_guard` (D6) stamps `decidedBy`/`decidedAt` and refuses a decision on a withdrawn request (`42501`).

  HR hears about new requests through the D7 bell and digest. It is a People event, so only owners, admins and accountants get it.

**Server API**

- HR (owner, admin, accountant):
  - `public.create_employee_invite(p_company text, p_employee text) → table(id, token, expires_at, phone)`
  - `public.employee_app_access(p_company text) → table(employee_id, state, activated_at, last_seen_at)`
  - `public.revoke_employee_access(p_company text, p_employee text) → void`
- Employee (signed in, not a member):
  - `public.accept_employee_invite(p_token text) → table(company_id, company_name, employee_id)`. The confirmed phone must match the snapshot.
  - `public.my_employee_links() → table(company_id, company_name, employee_id)`
  - `public.my_employee_profile(p_company text) → jsonb`. Never salary, IBAN or notes.
  - `public.my_leave(p_company text) → table(kind, data)`. Own leave only, without HR notes.
  - `public.submit_leave_request(p_company text, p_id text, p_type text, p_start date, p_end date, p_note text) → table(id, rev)`. The device-made id makes retries safe. At most 5 pending per employee. Calls `touch_sync_signal`.
  - `public.withdraw_leave_request(p_company text, p_id text) → void`. Own pending requests only.
- No Edge Function. The SMS provider for one-time codes is set in Supabase Auth, and its keys never go in the repo.

**Screens and components**

- `src/db/leave-requests.ts`: `approveLeaveRequest`, `rejectLeaveRequest`. Approval is one Dexie transaction that reuses the body of `saveLeaveRecord`, moved into an inner helper. `cancelLeaveRecord` also cancels a linked request.
- `src/apps/people/pages/payroll/requests.tsx` at `payroll/requests`, with a nav entry after _Leave_ (_Leave requests_ / طلبات الإجازة). Also:
  - `src/features/payroll/request-dialog.tsx`, reusing the warnings of `leave-dialog.tsx`;
  - `usePendingLeaveRequestCount` in `src/features/payroll/hooks.ts`;
  - a card on `src/apps/people/pages/overview/index.tsx`;
  - an item in `src/suite/home/attention.ts`.
- `src/features/people/app-access-card.tsx` on `src/apps/people/pages/people/detail.tsx`: access state, _Invite on WhatsApp_ (`src/lib/whatsapp.ts:46`), revoke, and bulk invite. The CloudApi methods use `optionalRpc`.
- Maham App (D10): `me.html`, `vite.me.config.ts`, and `src/me/` pages `join`, `signin`, `home` (balance), `leave` and `leave-new`. `sendPhoneCode`/`verifyPhoneCode` go in `src/cloud/auth.ts`. Because the app has its own address, it needs no `/me/` fallback rule and no second auth key.
- Arabic: `src/i18n/ar/payroll.ts` and a new `src/i18n/ar/me.ts`.

**Steps**

1. Migration and SQL tests. Add it to `MIGRATIONS`, and add `phone`/`phone_confirmed_at` to the `auth.users` stub (`src/cloud/sql-harness.ts:31-37`). The owner runs the migration.
2. Local schema: version 19, backup, roles, labels, fake cloud.
3. `src/db/leave-requests.ts` and the `saveLeaveRecord` refactor.
4. HR page, dialog, nav entry and card, hidden until `employee_app_access` answers.
5. App access card; Supabase phone provider; `docs/supabase-setup.md`.
6. Maham App shell, second Vercel project, boundaries rule.
7. Maham App leave pages.
8. Pilot with two or three guards, then bulk invite.

**Tests**

- SQL `src/cloud/employee-app-sql.test.ts`:
  - a linked employee gets nothing from `pull_records`, `company_team` or files;
  - invites are refused for staff, viewers and `left` employees, and when the invite is wrong, expired or reused;
  - the profile has no salary;
  - submitting twice with the same id is safe, and the request stays private;
  - re-running `20261004…` keeps requests hidden.
- Unit `src/db/leave-requests.test.ts`: approval creates a linked `LeaveRecord`. An approved or paid run refuses the approval and the request stays pending. Pending requests never change `employeeLeaveBalance`. Also upgrade, backup, roles, boundaries and i18n tests.
- E2E `e2e/people-requests.spec.ts` and `e2e/me.spec.ts` (fake cloud): join, submit, withdraw, approve and reject, in both languages.

**Risks**

- Privacy: a new `member_role` value would leak non-private data (`:295`); D9 avoids this. Re-running the first migration resets `record_is_private`, but the restrictive policy still holds.
- A device that pushes `leaveRequests` before the migration has run gets the change parked (23514). Follow the release order in D4.
- An offline HR approval could overwrite a withdrawal, because the last writer wins. `records_guard` refuses it, and HR sees the parked change.
- `assertPayUnchanged` refuses an approval inside an approved or paid pay run, so it is never half-applied.
- Phones change or are shared. HR can revoke access in one click, and access ends when the employee is marked as left. SMS sends phone numbers to a provider, so get the employees' consent.

**Decisions for the owner**

- How do guards sign in? _Recommended:_ an SMS one-time code, with long sessions.
- Who approves? _Recommended:_ the owner, admins and accountants.
- Which leave types may guards request? _Recommended:_ annual, sick, unpaid, bereavement, Hajj and any active custom reasons (#15). Maternity leave is entered by HR.
- May guards ask for more than their balance? _Recommended:_ yes, with a warning to the guard and to HR.
- App name? _Recommended:_ "Maham App / تطبيق مهام", in English and Arabic first.

### 12. Departments and a Stateless option

**Status:** Partly built · **Size:** L · **Phase:** 2

Departments become a managed list in `PeopleSettings`, with English and Arabic names (D11), bulk assignment, and a department on each pay line. _Stateless_ is an optional `Employee.stateless` flag on top of the `expat` category, not a new `EmployeeCategory`. That way older builds still show a label and compute the same pay.

**There now**

- `src/db/types.ts:1193`: `Employee.department` is free text. `src/features/people/employee-form.tsx:499-505` suggests names already in use, collected in `src/apps/people/pages/people/form.tsx:71-75`.
- `src/apps/people/pages/people/list.tsx:62-105` filters by department. `src/apps/people/pages/overview/index.tsx:204-217` links `?department=<name>`.
- `src/db/types.ts:1135`: `EmployeeCategory` has no stateless value. `src/lib/hr/employees.ts:28-40` derives residency, work permit and PIFSS from the category.
- `src/lib/hr/nationalities.ts:151`: `NO_COUNTRY` already recognises bedoon, stateless and بدون (tested at `src/db/import-employees.test.ts:247`). The import then keeps `expat` (`src/db/import-employees.ts:436-450`).

**Missing**

- A canonical department list. Typos create duplicates, and there are no Arabic names, renames, bulk assignment or pay-line department (#10 needs one).
- A stateless status (غير محدد الجنسية (بدون)). Today the form asks stateless staff for an Article 18 residency and a work permit.
- The Central Agency review card (بطاقة المراجعة), which stateless staff hold instead of a residency.

**Database**

- Local:
  - `PeopleSettings.departments?: {id, name, nameAr, archived?}[]` (D11). `Employee.department` keeps the English name, so links, imports and older builds keep working.
  - `Employee.stateless?: boolean`, `centralCardNumber?`, `centralCardExpiry?: ISODate | null`.
  - `ComplianceDocumentType` gains `central_agency_card`. This is safe once Phase 0's tolerant `DOCUMENT_TYPES` lookup has shipped (D2).
  - `PayLine.department?`, set in `buildLine` (`src/db/payroll.ts:928`).
  - No Dexie version or backup change.
  - Why a flag and not a new category: a new category would break older builds at `t(CATEGORY_LABELS[e.category])` (`list.tsx:147,429`, `detail.tsx:237`) and give NaN in `byCategory[e.category] += 1` (`employees.ts:168`). With `expat` underneath, their pay is unchanged.
- Cloud: No change.

**Server API**

- None: runs on the device. The email-alerts bundle gets the card type on its next deploy.

**Screens and components**

- `src/lib/hr/employees.ts`:
  - `needsResidency` and `needsWorkPermit` also read the flag. Stateless staff need no residency. The work permit depends on the owner's answer.
  - `categoryLabel(e)`.
  - `workforceSummary` gets a separate stateless count.
- `employee-form.tsx`:
  - a fifth choice, "Stateless (Bedoon)", which stores `category: 'expat'`, `stateless: true` and `nationality: ''`;
  - a Central Agency card section in place of Residency;
  - `setNationality` (`:173`) clears the flag when a country is chosen.
- `src/lib/compliance.ts`: `employeeDocuments` emits the card. `EMPLOYEE_EXPIRY_FIELDS` / `EMPLOYEE_NUMBER_FIELDS` (`:204`, `:215`) map it, so renewals work.
- `src/lib/hr/nationalities.ts`: `isStatelessText()` sets the flag on import. Add import columns for the card.
- New `src/features/people/departments-dialog.tsx`: add, rename (in one transaction), merge, Arabic name, archive.
- New `src/features/people/assign-department-dialog.tsx` for selected list rows. The form gets a Select with "Other…".
- `src/apps/people/lib/directory.ts` shows `nameAr` in Arabic but keeps the English value in the URL. Arabic strings go in `src/i18n/ar/people.ts` (القسم is at `:179`).

**Steps**

1. Get the owner's answers on PIFSS, work permits and identity documents.
2. The flag, helpers, labels and the card type, with tests.
3. The form, the detail page, the list chips and import detection.
4. The department dialogs, plus `renameDepartment` / `assignDepartment` in `src/db/people.ts`.
5. `PayLine.department` and a department column on the run page.

**Tests**

- Unit:
  - `src/lib/hr/employees.test.ts`: stateless staff need no residency, are not insured, and have their own count.
  - `src/lib/compliance.test.ts`: the card appears and no residency is asked.
  - `src/db/import-employees.test.ts`: Bedoon, بدون and غير محدد الجنسية set the flag.
  - `src/db/people.test.ts`: rename and assign each happen in one transaction.
- e2e: `e2e/people.spec.ts`: a stateless employee in both languages; bulk assign.

**Risks**

- Wrong PIFSS treatment changes net pay. Mitigation: keep the `expat` behaviour until the owner confirms.
- Older tabs show "Expatriate" until they reload. Pay is unchanged.
- A rename rewrites many employee rows, and the last write wins. Mitigation: one transaction, and a warning first.
- The bank file reads `civilId` (`src/lib/hr/salary-file.ts:21`). Use the card number when there is no Civil ID.

**Decisions for the owner**

- Are stateless staff insured with PIFSS? _Recommended:_ no, as today.
- Do they have PAM work permits? _Recommended:_ make the work permit fields optional, and never require a residency.
- Do they have a Civil ID, or only a review card? _Recommended:_ keep both fields and track the card's expiry.

### 13. Driving licences for drivers

**Status:** Partly built · **Size:** M · **Phase:** 2

Licences are already stored as `driving_licence` register documents, and their expiry is tracked. We add who must hold one: decided by job title, a per-employee override, or an assigned vehicle. Drivers without a valid licence are flagged in the app now, and in the morning email when #18 ships.

**There now**

- `src/lib/compliance.ts:99`: the `driving_licence` type. `registerTypesFor` (`:117-124`) offers it for employees.
- `src/features/renewals/document-dialog.tsx:68,307`: private scans. `src/alerts/collect.ts:98` `documentAlerts` already emails about expiring licences.
- `src/features/people/employee-documents.tsx:59`: _Add document_ defaults to `health_insurance`.
- `src/features/company/import-columns.ts:501-520` and `src/db/import-employees.ts:665` `saveDrivingLicence` import the licence number and expiry.
- `src/lib/hr/job-titles.ts:18-24`: driver titles (سائق, سائق حافلة, سائق مركبة ثقيلة). Valets map to عامل صف سيارات.
- `src/features/people/bulk-documents-dialog.tsx:172`: bulk scans go to the personnel file.

**Missing**

- Nothing knows who drives, so a missing licence is never flagged.
- A licence class, a driver default for _Add document_, and filing bulk scans as licences.

**Database**

- Local: `Employee.drivingLicenceRequired?: boolean | null` (null means "from the title") and `ComplianceDocument.licenceClass?: string`. No new table or version.
- Cloud: No change. Both are already private.

**Server API**

- None: runs on the device. The missing-licence email line comes with #18 under the `documents` topic.

**Screens and components**

- `src/lib/hr/job-titles.ts`: `isDriverTitle()` checks `jobTitle`, `jobTitleAr` and `pamJobTitle`.
- `src/lib/compliance.ts`:
  - `requiresDrivingLicence(employee, vehicles?)`: the override first, then the vehicle assignment once #17's `vehicles` (D3) records one, then the title.
  - `missingDocuments()`.
- `employee-documents.tsx`: a "Driving licence missing" row. _Add document_ defaults to the licence for drivers.
- `employee-form.tsx`: "Drives for work" (Automatic / Yes / No).
- `document-dialog.tsx`: licence class (فئة الرخصة).
- `src/apps/compliance/pages/compliance/documents.tsx` and `src/apps/people/pages/people/list.tsx`: a filter for drivers without a valid licence (السائقون بدون رخصة سارية).
- `bulk-documents-dialog.tsx`: a "File as driving licence" option.
- Arabic: `src/i18n/ar/people.ts`.

**Steps**

1. The three helpers, with tests.
2. The documents card, the default type and the override.
3. The filters.
4. Licence class and bulk filing.

**Tests**

- Unit:
  - new `src/lib/hr/job-titles.test.ts`: Driver, HEAVY DRIVER and سائق حافلة match. Security Guard does not.
  - `src/lib/compliance.test.ts`: missing, expired, archived and left; the override wins.
- e2e: `e2e/people.spec.ts`: the warning shows; a licence expiring in 20 days shows _Expiring_.

**Risks**

- Free-text titles in two languages will sometimes be misread. The override corrects each case.
- Scans are personal data. They stay on the employee's private document.

**Decisions for the owner**

- Which titles count as drivers, and do valets? _Recommended:_ the driver titles above, Valet Driver, and any title containing سائق.
- Should a missing licence block vehicle assignment? _Recommended:_ warn only.
- Should we track the licence class? _Recommended:_ yes, as an optional field.

### 14. Default leave policy of 30 days

**Status:** Partly built · **Size:** M · **Phase:** 2

The 30-day default already applies, but as constants. It becomes a visible, dated policy in `PayrollSettings`, with an optional entitlement per employee. Until a policy is saved, every balance stays exactly as it is today.

**There now**

- `src/lib/hr/leave.ts:41,58,60`: annual leave is 30 working days, `ANNUAL_LEAVE_DAYS = 30`, `FIRST_YEAR_MONTHS = 9` (art. 70).
- `src/lib/hr/leave.ts:315`: `annualLeaveBalance` adds 2.5 days per completed month and carries every day forward.
- Where the balance is used:
  - provisions, `src/db/payroll.ts:1194-1215`, posted as "target less held" (`:1326-1334`);
  - settlements, `:1573`;
  - fixed texts in `src/apps/people/pages/payroll/leave.tsx:156`, `src/features/payroll/employee-tabs.tsx:104,170` and `src/features/payroll/leave-dialog.tsx:33`.
- `src/db/types.ts:1725`: `PayrollSettings` has no leave fields. `normalizePayrollSettings` (`src/db/payroll.ts:283`) spreads `...input`, so older builds keep new fields.

**Missing**

- A visible, editable policy.
- Contract entitlements above 30 days.
- Start dates. Changing the constant would rewrite past balances, provisions and settlements.

**Database**

- Local:
  - `PayrollSettings.leavePolicy?: {annualDays: {from, days}[], firstYearMonths, carryForwardMax, counting}`. When it is absent, today's constants apply (D1, D11).
  - `Employee.annualLeaveDays?: number | null`.
  - No version change.
- Cloud: No change.

**Server API**

- None: runs on the device.

**Screens and components**

- `src/lib/hr/leave.ts`: `DEFAULT_LEAVE_POLICY`. `annualLeaveBalance`, `employeeLeaveBalance`, `leaveWarnings` and `countedDates` take the policy as an optional argument. Each dated period accrues at its own rate.
- `src/db/payroll.ts`: pass the policy to provisions, settlements and `saveLeaveRecord`.
- `src/apps/people/pages/payroll/settings.tsx`: an _Annual leave_ (الإجازة السنوية) card: days a year (at least 30), a start date, first-year months, and a cap. Counting locks once leave has been recorded.
- `employee-form.tsx`: an entitlement field, with the company default as placeholder.
- The fixed texts come from the policy. Arabic goes in `src/i18n/ar/payroll.ts`.

**Steps**

1. Pure refactor with the default policy, existing tests unchanged (#15 builds on it).
2. Golden test on the demo company.
3. Dated accrual, the entitlement and the cap.
4. Wiring, settings card, field and texts.

**Tests**

- Unit:
  - `src/lib/hr/leave.test.ts`: the default equals today; 45 days gives 3.75 a month; a mid-year change; the cap.
  - `src/db/payroll.test.ts`: provisions catch up only from the start date.
  - `src/db/payroll-regressions.test.ts`: settlements are unchanged.
- e2e: `e2e/payroll.spec.ts`: the Leave page footer follows the policy.

**Risks**

- A change that reaches back in time posts a one-off leave expense. The start date prevents it.
- Fewer than 30 days breaches art. 70. The form refuses it.
- Days are stored at save, so changing the counting would mix methods. Counting locks.

**Decisions for the owner**

- Are the 30 days working days or calendar days? _Recommended:_ working days, as today.
- Does anyone get more than 30 days? _Recommended:_ allow per-employee entitlements.
- Should carried-forward days be capped? _Recommended:_ no (art. 73 pays unused days).
- Should new staff wait nine months or six for their first leave? _Recommended:_ nine (art. 70).

### 15. Custom leave reasons with automatic pay and balance effects

**Status:** Partly built · **Size:** XL · **Phase:** 4

Companies define leave reasons in `PayrollSettings` (D11). Each reason sets:

- how it is paid: full, a percentage, or in tiers;
- whether it is taken from annual leave;
- whether it pauses annual accrual;
- whether it has its own balance.

Every reason maps onto a base `LeaveType`, so older builds can still read every record.

**There now**

- `src/db/types.ts:1911`: `LeaveType` is a fixed set of six. `LeaveRecord` (`:1918-1932`) has `type`, `days` stored at save, and free-text `notes` as the only reason.
- `src/lib/hr/leave.ts:40-47`: `LEAVE_TYPES`. `:63-69`: `SICK_TIERS`, 15/10/10/10/30 days at 100/75/50/25/0% (art. 69), applied by `sickDayRates` (`:131`).
- `src/lib/hr/leave.ts:209`: `leaveInPeriod` sets each day's share of pay. Overlapping leave takes the lower pay. `src/lib/hr/payroll.ts:237` `calculatePayLine` turns this into `absenceDeduction`.
- `src/lib/hr/leave.ts:315`: only annual leave accrues. `:448` `leaveWarnings` checks limits, Hajj once and overlaps.
- Lookups with no fallback, made tolerant in Phase 0 (D2): `LEAVE_TYPES[r.type]` in `src/features/payroll/employee-tabs.tsx:228`, `src/apps/people/pages/payroll/leave.tsx:129`, `src/apps/people/pages/overview/index.tsx:163` and `leave.ts:109`.

**Missing**

- Company-defined reasons with Arabic names.
- Pay rules other than unpaid and sick.
- Taking leave from the annual balance.
- Other balances, such as compensatory days.
- Pausing accrual during long unpaid leave.
- Payslip detail showing which leave caused a deduction.

**Database**

- Local:
  - `PayrollSettings.leaveReasons?: LeaveReason[]`, each `{id, name, nameAr, archived?, base: LeaveType, counting, pay: {mode: 'full'} | {mode: 'percent', percent} | {mode: 'tiers', tiers, per: 'calendar_year' | 'service_year'}, fromAnnual, pausesAccrual, grant?: {daysPerYear, carryMax}, maxDaysPerYear?, categories?, noteRequired?, usedAt?}`.
  - The six built-in types are seeded with `id` equal to their `LeaveType`. Their legal floors (the sick tiers, 70 days of maternity leave) cannot be lowered.
  - `LeaveRecord.reasonId?` and `payPercent?`. `type` holds the reason's `base`. The base is derived from the reason's rules, not chosen freely: `annual` for `fromAnnual`, `unpaid` for 0% or partial pay, `bereavement` for full pay. Older builds will then warn about full-pay reasons longer than 3 days (`LEAVE_TYPES.bereavement.days`, `src/lib/hr/leave.ts:45`), and the reasons page should say so.
  - `PayLine.leaveDetail?: {reasonId, name, nameAr, days, percent}[]`, display only.
  - No separate `leaveTypes` table, because of D11. No Dexie version.
- Cloud: No change.

**Server API**

- None: runs on the device.

**Screens and components**

- `src/lib/hr/leave.ts`, built on #14's refactor:
  - `reasonOf()`;
  - tier counters per reason that generalise `sickDayRates`, with built-in sick leave giving identical numbers;
  - in `annualLeaveBalance`, `fromAnnual` days count as taken and months paused by `pausesAccrual` don't accrue;
  - `reasonBalance()` for grants;
  - warnings driven by each reason's definition.
- `src/db/payroll.ts`:
  - reasons are passed into `buildLine` (`:928`, which fills `leaveDetail`), `assertPayUnchanged`, `saveLeaveRecord`, provisions and settlements.
  - `approvePayRun` refuses a line that lacks `leaveDetail` when the month has reason records, with the message "Update from records first".
- New `src/apps/people/pages/payroll/leave-reasons.tsx`, on route `payroll/leave-reasons` in `peopleRoutes`. It gets a _Leave reasons_ (أسباب الإجازة) entry after _Leave_ in `src/apps/people/manifest.ts:61`.
- New `src/features/payroll/leave-reason-dialog.tsx`: a tier editor with a preview such as "15 days full, 10 at 75%…".
- `leave-dialog.tsx`: reasons by their local name, the pay effect ("8 days at 50%"), and a required note where set.
- `employee-tabs.tsx`: balance cards for reasons with grants, and tier use for any tiered reason.
- `leaveLabel()` replaces the three label lookups listed above.
- `payslips.tsx` and `line-dialog.tsx` list deductions per reason.
- Arabic strings go in `src/i18n/ar/payroll.ts` (مدفوعة بنسبة {percent}٪, تُخصم من الإجازة السنوية). Custom reasons use their `nameAr`.

**Steps**

1. Turn the six built-in types into definitions. Golden tests must give identical pay and balances.
2. Add `reasonId`, seeding and normalisation, and wire them through `db/payroll.ts`.
3. Percentage and tiered pay, per calendar year or per service year.
4. `fromAnnual` and `pausesAccrual`.
5. Grants and their warnings.
6. The reasons page, dialogs, labels and payslip detail.
7. Lock a reason's rules once a posted run uses it (`usedAt`). To change them, archive the reason and add a new one.
8. Regression check on a copy of real data: balances and the next draft must not change.

**Tests**

- Unit:
  - `src/lib/hr/leave.test.ts`: sick leave as a definition equals `SICK_TIERS`; a 50% reason; custom tiers; service year; `fromAnnual`; 60 unpaid days pause accrual; a grant resets; overlaps take the lower pay.
  - `src/lib/hr/payroll.test.ts`: the `leaveDetail` amounts add up to `absenceDeduction`.
  - `src/db/payroll.test.ts` and `src/db/payroll-regressions.test.ts`: records without `reasonId` are unchanged; locked rules stay locked.
  - `src/lib/hr/pay-line-versions.test.ts`: the copy kept for old versions is still written.
- e2e: `e2e/payroll.spec.ts`: "Emergency leave (from annual)" and a 50% reason, in English and Arabic.

**Risks**

- This changes the core of leave pay. Mitigation: refactor first, behind golden tests, then a regression check on real data.
- A partly paid reason has no exact base, so an older tab refreshing a draft pays it as unpaid. Older tabs also label full-pay reasons as bereavement. Mitigation: the `leaveDetail` check blocks posting such a line, and the reasons page asks the owner to update every device first. The feature is off by default (D1).
- Editing a reason in use would change provisions and settlements after the fact. Mitigation: rules lock once used.

**Decisions for the owner**

- Which reasons do you need, and how is each paid? _Recommended:_ emergency leave taken from annual leave; compensatory days added by hand; everything else on full pay with a yearly maximum.
- Should sick tiers run per calendar year or per service year? _Recommended:_ calendar year, as today.
- Should long unpaid leave pause accrual? _Recommended:_ yes, for months with more than 15 unpaid days. Confirm with the auditor.
- Should domestic workers (Law 68/2015) have their own reasons? _Recommended:_ yes, through `categories`.

### 16. Messages to guards in the Maham App

**Status:** Not built · **Size:** L · **Phase:** 7

HR writes a message in Maham People to chosen employees, a job-title group or a department. It is saved as a private `employeeMessages` record (D9), with the recipient ids fixed when it is sent. Guards read it in the Maham App inbox, receipts live in a real table, and a new `employee-notify` Edge Function sends Web Push as the push channel of the notification service (D7).

**There now**

- No message, inbox or push code exists. `vite.config.ts:18-53` uses `generateSW`, with no `push` handler.
- `src/lib/hr/job-titles.ts:8-14` maps "Guard" and "Security Gaurd" to "Security Guard" (حارس أمن). It is used only to fill in Arabic titles.
- `src/db/types.ts:1191-1193`: `jobTitle` and `department` are free text. `src/apps/people/lib/directory.ts:62` has `departments()`.
- `src/lib/whatsapp.ts:46-49` `whatsappUrl`: a free, manual fallback.
- `supabase/migrations/20261007000000_email_alerts.sql:74,113,274`: a config table, a `pg_net` call with a secret, and `pg_cron`. This is the pattern to copy.

**Missing**

- A message record, an audience model and a canonical job-title key.
- Push keys, push subscriptions and a sender.
- Receipts, and all the screens.

**Database**

- Local: in `src/db/types.ts`, a new `EmployeeMessage {id, companyId, title, body, audience: {kind: employees|jobTitle|department|all, values}, recipientIds, status: draft|sent|cancelled, requireAck?, sentAt?, sentByName?}`. Dexie **19** (D3): `employeeMessages: 'id, companyId, [companyId+sentAt], status'`. Add it to `DATA_TABLES`, `backupSchema` with `.default([])`, `labels.ts` and `PEOPLE_TABLES` (D16).
- Cloud, in `20261221000000_employee_app.sql` (D4):
  - tbl `employeeMessages` in `records_tbl_check`, `record_is_private` and the restrictive policy;
  - `can_delete_record` refuses deleting a sent message (`42501`), mirrored in `src/cloud/outbox.ts:109-125`;
  - real tables `message_receipts`, `push_subscriptions` and `message_dispatch`, and the config table `almailbooks.employee_notify_config`;
  - a trigger on `records` queues a dispatch and calls the function via `pg_net` when a message's status becomes `sent`;
  - A 5-minute cron of its own (`almailbooks.run_employee_notify()`, the same pattern as D7's job, reading `almailbooks.employee_notify_config`) posts `{action:'run'}` to `employee-notify` to retry failed sends. D7's job only calls email-alerts.

**Server API**

- Employee:
  - `public.my_messages(p_company text, p_before timestamptz, p_limit int) → table(id, title, body, sent_at, sender_name, require_ack, read_at, acknowledged_at)`. Never returns `recipientIds`.
  - `public.mark_message_read(p_company text, p_id text) → void`
  - `public.acknowledge_message(p_company text, p_id text) → void`
  - `public.save_push_subscription(p_company text, p_endpoint text, p_p256dh text, p_auth text) → void`
- HR (owner, admin, accountant):
  - `public.message_receipt_counts(p_company text, p_ids text[]) → table(message_id, recipients, delivered, read, acknowledged)`
  - `public.message_receipts(p_company text, p_message text) → table(employee_id, pushed_at, read_at, acknowledged_at)`
- `employee-notify`, another entry of the D2 multi-entry build (after #26's `payment-links` in Phase 6):
  - `POST {action:'run'}` with `x-notify-secret` → `{pushed, failed}`;
  - `POST {action:'test'}` with an HR session;
  - `GET` for a health check.

  Secrets: `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`. A separate function keeps these keys out of email-alerts. The push shows only the company name and the message title.

**Screens and components**

- The compose screen lives in Maham People, because only roles that see employees may pick them (D16):
  - `src/apps/people/pages/messages/{index,compose,detail}.tsx`, with routes `people/messages[/new|/:id]`;
  - nav entry _Messages_ / الرسائل in `src/apps/people/manifest.ts`;
  - compose previews the recipients before sending. Offline it says _Will be sent when online_.
- `src/db/messages.ts` (skips `left` employees), `jobTitleKey()` in `src/lib/hr/job-titles.ts`, and _Send message_ on `src/apps/people/pages/people/detail.tsx`.
- Maham App: `src/me/pages/messages.tsx`, `message.tsx` (_I confirm_ / أؤكد الاطلاع), `src/me/push.ts` and `src/me/sw.ts` (`injectManifest`, `push` and `notificationclick`). The permission text uses تنبيهات, never الإشعارات, which means credit notes in this app.
- Arabic: `src/i18n/ar/people.ts` and `src/i18n/ar/me.ts`.

**Steps**

1. After #11 steps 1, 2 and 6: this part of the migration and its tests.
2. Local schema and `jobTitleKey`.
3. HR compose and history, hidden until `message_receipt_counts` answers.
4. The inbox, which polls for new messages. It ships before push.
5. `employee-notify`, `supabase/config.toml`, `.github/workflows/deploy.yml` and `docs/employee-notify.md`.
6. Push subscription, tested on a pilot guard's phones.

**Tests**

- SQL `src/cloud/employee-messages-sql.test.ts`: a guard sees only sent messages addressed to them, and nothing after access is revoked. Receipts are HR-only. A sent message can't be deleted. Each send creates one dispatch.
- Unit `src/notify/server.test.ts`: a wrong secret gets 401, a 410 answer disables the subscription, and failed sends are retried. Also `jobTitleKey`.
- E2E `e2e/messages.spec.ts`: HR messages all Security Guards, the inbox shows the message, and HR sees it marked as read.

**Risks**

- Recipient lists name employees and must never reach guards. Pushes show on lock screens, so messages carry no pay or personal data.
- On iOS, push works only when the app is added to the Home Screen (iOS 16.4+). The inbox is the source of truth.
- Receipts kept inside the message record would be lost, because the last writer wins. They stay in `message_receipts`.
- The function holds the VAPID key, so it checks the secret in constant time (`src/alerts/server.ts:115`).

**Decisions for the owner**

- Who may send messages? _Recommended:_ the owner, admins and accountants.
- Should messages target guards by site? _Recommended:_ by person, job title and department for now. Add a _Site_ field only if the owner asks for it.
- Is there a budget for SMS or WhatsApp? _Recommended:_ none at first; use manual WhatsApp links.
- Can guards reply? _Recommended:_ no replies in v1, with an optional "I confirm" button.

## 4. Documents, templates and expiry alerts

### 17. Company documents, contracts and vehicles

**Status:** Partly built · **Size:** L · **Phase:** 2

We extend the existing Maham Compliance register rather than build a second one. It gains Purpose, customer and vehicle links, contract and cost-sheet types, a vehicle list and a _Confidential_ flag. Customer papers keep the owner `other` and add `clientId`, so older builds never meet a new owner value.

**There now**

- `src/db/types.ts:1241-1295` holds the types, among them company licences, `lease_contract`, `vehicle_registration` (دفتر المركبة) and `other`. The title is optional (:1276), expiry and reminders exist, there is no purpose, and the vehicle is free text in `ownerName` (:1288).
- `src/features/renewals/document-dialog.tsx` takes the vehicle as free text (:174-185) and already attaches scans (:305-313).
- `src/db/renewals.ts:160-185` deletes a document for good, files included, but refuses once it has renewals.
- Staff and viewers can only view (`src/apps/compliance/manifest.ts:53-60`; `staff_can_write`, `20261004000000_almailbooks_cloud.sql:260-277`).
- A row is private only with an `employeeId` (`almailbooks_cloud.sql:216-217`, `src/cloud/roles.ts:93-127`). Storage takes images and PDFs up to 10 MB (:1515-1520).
- Customers already hold tax clearance certificates (`src/db/types.ts:576`, `src/db/retention.ts:47-95`), shown at `src/apps/books/pages/clients/detail.tsx:252-255`. Fixed assets can hold vehicles (`FixedAsset`, `src/db/types.ts:1397`; Vehicles accounts in `src/lib/accounting/charts.ts:236-237`) but are not linked to their papers.

**Missing**

- Purpose, a required Title, contract and cost types, a customer Documents card.
- Vehicle records, and a way to hide cost sheets (guard salaries) from staff.
- A file column, a _No file_ filter, and documents in search.

**Database**

- Local: `ComplianceDocument` gets optional `purposeId`, `clientId`, `vehicleId` and `confidential`, plus types `company_contract`, `client_contract` and `customer_cost`. `ownerName` keeps the plate or customer name for older builds. Purposes are a D11 list in `Company.documentPurposes`; `PeopleSettings` is not used because staff never receive it. New `Vehicle {id, companyId, plate, make, model, year?, chassisNumber?, assetId?, driverEmployeeId?, notes, archived, createdAt, updatedAt}`, with its table and indexes in Dexie 16 (D3). The switch is `Company.registerExtras` (D1).
- Cloud: nothing ships in Phase 2. `20261102000000_tables_v16.sql` (D4) adds `vehicles` (not private, no staff writes). That file also gives `record_is_private` a `confidential` branch, so the document, its files and its activity are private. The branch does nothing until a row is marked. `isPrivateRecord` and `privateOwnerIds` (`src/cloud/sync.ts:575-590`) get the same branch in the Phase 0 release, so D2's parity test passes.

**Server API**

- None: runs on the device.

**Screens and components**

- `document-dialog.tsx`: Purpose (الغرض) with _Add purpose_, Customer (العميل), a vehicle picker with _New vehicle_, and _Confidential_ (سري) for People roles only.
- `documents.tsx`: a purpose column, a paperclip column, and _No file_ and _Customer_ filters.
- New `src/apps/compliance/pages/compliance/vehicles.tsx`, added to `routes.tsx`, `manifest.ts` and `src/features/renewals/compliance-header.tsx:27-32`.
- New `src/features/renewals/client-documents.tsx` for the Books customer page. It is shared code, so the boundaries test holds.
- `src/db/vehicles.ts`, `text.ts` `entryOwner`, `src/features/search/sources.ts`. `src/suite/home/attention.ts:76-78` also leaves out confidential rows.
- Arabic in `src/i18n/ar/documents-register.ts` (عقد الشركة، عقد العميل، كشف تكاليف العميل، المركبات).

**Steps**

1. Types and save checks: customer and vehicle in the same company; a Title for the new types.
2. Dialog, list and filters.
3. Vehicles, with a _Link vehicles_ action that groups papers sharing an `ownerName` and asks before linking.
4. Confidential. Turning it on later re-creates the document, its files, its renewals (`documentKey: doc:<id>`) and its activity under new ids, then deletes the old ones in one transaction. `deleteComplianceDocument` refuses documents that have renewals (`src/db/renewals.ts:167-169`), so this needs its own helper.
5. New types, customer card, demo data with invented names.

**Tests**

- Unit: `src/db/renewals.test.ts` and `src/db/vehicles.test.ts`; `src/cloud/roles.test.ts`; `src/cloud/sync.test.ts` (re-creation sends a public deletion marker).
- SQL, `src/cloud/sql.test.ts`: staff and viewers can't read a confidential document, its file or its activity. Staff writes to `vehicles` get `42501`.
- e2e, new `e2e/compliance.spec.ts`: a contract with purpose, expiry and PDF; a vehicle page; Arabic RTL.

**Risks**

- A row that becomes private stays on staff devices (`pull_records` only filters what it sends). Step 4 uses new ids for that reason.
- Unknown types crash older builds, so D2 must reach devices first.
- A driver stored in `employeeId` would hide the paper from staff. The driver goes on `Vehicle` instead.

**Decisions for the owner**

- May staff upload company documents? _Recommended:_ no.
- What is "customer cost documentation"? _Recommended:_ a file linked to the customer, confidential by default.
- Should Word and Excel files be accepted? _Recommended:_ no; PDF and images up to 10 MB.

### 18. Expiry alerts with lead times and re-upload reminders

**Status:** Partly built · **Size:** L · **Phase:** 4

We extend the existing morning alerts (`email-alerts` `run`) rather than add a new job. They gain lead times per document type, repeat reminders after expiry, and a "new copy missing" reminder based on tagged scans. Owners, admins and accountants choose which kinds they receive. The bell shows the same items (D7). Every new setting starts empty, which keeps today's behaviour (D1).

**There now**

- `src/lib/compliance.ts:130` sets the default lead times (60/30/7 days). `expiryStatus` (:160-172) applies them, and a document can override them (:279-293).
- `PeopleSettings.reminderDays` (`src/db/types.ts:1340`; `src/features/renewals/settings-dialog.tsx:50-63`) is one list for every document type. Residency (الإقامة) and passport come from the employee record (`compliance.ts:232`).
- `src/alerts/collect.ts:98-123` keys each alert as `documents:<entry>:<expiry>:<stage>`. `src/alerts/server.ts:370-481` emails only new keys (:432-442), plus a Sunday summary. So an expired paper is emailed once, then only on Sundays.
- Only owners and admins get alerts (`server.ts:381`, `:518`; `20261007000000_email_alerts.sql:98`, `:208`). The suite home shows the same alerts from device data (`src/suite/home/attention.ts:45-89`).
- `loadAlertData` (`server.ts:191-244`) bypasses RLS and reads no renewals or files. Renewing (`src/db/renewals.ts:412`) asks for no new scan.

**Missing**

- Lead times per type, repeat reminders, and a check that the new copy is uploaded.
- Accountants as recipients, a choice of kinds, and bell items.

**Database**

- Local: `PeopleSettings` gets optional `reminderDaysByType`, `expiredRepeatDays` and `newCopyGraceDays`. `normalizePeopleSettings` (`src/db/people.ts:522-537`) must not pass an empty list to `normalizeReminderDays`, which would fill it with 60/30/7. `Attachment` gets optional `docKey` (the key of what the file is a copy of: a register entry key such as `doc:<id>`, or `letter:<id>` for #19) and `validUntil`. `docKey` is indexed in Dexie 16 (D3).
- Cloud: `20261130000000_people_alerts.sql` (D4) adds `email_alerts.document_kinds text[]` (null means all). It replaces `set_email_alerts` (same four arguments) and `email_alerts_member_changed` so they accept accountants. No new topic values, because older builds drop unknown topics when they save (`src/cloud/supabase-api.ts:40`).

**Server API**

- `public.email_alert_scope(p_company text) → table(document_kinds text[])`, members only.
- `public.set_email_alert_scope(p_company text, p_kinds text[]) → void`, for an owner, admin or accountant setting their own row. Kinds must be company, vehicle, staff or client; otherwise `42501`.
- `email-alerts` `POST {action:'run'}` (cron secret):
  - adds accountants and filters each person's kinds;
  - removes private items per person (D16);
  - reads renewals and file tags, and treats a missing column as all kinds;
  - writes one `change_events` row (`document_expiry`) per new key, which the 5-minute digest skips.
- `POST {action:'send'}` also admits accountants. Secrets are unchanged (`RESEND_API_KEY`, `ALERTS_FROM`).

**Screens and components**

- `settings-dialog.tsx`: _Reminders by document type_ (التذكير حسب نوع المستند), _Remind every N days after expiry_, _Ask for the new copy within N days_.
- `src/features/renewals/renew-dialog.tsx`: an optional _New copy_ file, tagged on save.
- `src/apps/people/pages/people/detail.tsx:309-330` and `src/features/people/bulk-documents-dialog.tsx`: an optional "This file is the…" tag.
- Documents page: _New copy missing_ (لم تُرفع النسخة الجديدة) badge and filter.
- `src/pages/settings/alerts.tsx`: accountants and kind checkboxes. `src/alerts/email.ts` groups by kind. Update `docs/email-alerts.md`.
- Arabic in `src/i18n/ar/alerts.ts`. The bell keeps the name chosen in #7: never الإشعارات (credit notes) and never تنبيهات, which the morning email alerts already use (تنبيهات البريد, src/i18n/ar/alerts.ts:78).

**Steps**

1. `reminderDaysFor(type, settings, override)`, called from `src/db/renewals.ts:205-207`, `collect.ts:98-104`, `attention.ts` and `people/detail.tsx:306`. Output must stay the same when nothing is set.
2. Settings fields and dialog.
3. Repeat stages. The first key stays `…:expired`; later keys are `…:expired+7`, `…:expired+14` and so on.
4. Tagged scans, and a `…:noscan` stage once the grace period passes with no tagged file valid until the new expiry.
5. Migration, `optionalRpc` calls (D4), alerts page.
6. Function changes. Release order: the migration runs first.

**Tests**

- Unit: `src/alerts/collect.test.ts` (keys unchanged when unset; repeats; a tag clears `noscan`); `src/alerts/server.test.ts` (accountants included; a missing column means all kinds; no employee papers for lower roles).
- SQL, `src/cloud/email-alerts-sql.test.ts`: accountants can subscribe; staff get `42501`; bad kinds are refused.
- e2e, `e2e/people.spec.ts`: an Iqama lead time of 90 days marks an Iqama expiring in 80 days.

**Risks**

- A new key format would re-send every open item, so existing keys stay.
- The function bypasses RLS, so the code must remove private items for each person.
- Resend's free plan allows 100 emails a day, shared with other alerts (D7). Each person still gets at most one email a day.

**Decisions for the owner**

- Who gets document alerts? _Recommended:_ owners, admins and accountants who opt in.
- What default lead times? _Recommended:_ Iqama 90/60/30/7, passport 180/90/30, vehicles 30/14/7.
- How often after expiry? _Recommended:_ every 7 days.
- WhatsApp or SMS? _Recommended:_ not now. Phone push arrives with the Maham App (D10).

### 19. Employee letter templates

**Status:** Not built · **Size:** XL · **Phase:** 4

HR letters come from editable Arabic and English templates kept in two private tables (D3). They cover salary, experience and employment certificates, warning letters, NOCs and salary transfer letters. A letter is filled with employee data, then numbered and frozen at issue. "Automatic" means drafts are created on joining, leaving or a salary change. A person checks, issues and prints each one.

**There now**

- No letter templates exist. The only near match is the `pam_salary_certificate` document type (`src/lib/compliance.ts:63-67`).
- `src/features/payroll/print.tsx:20-120` has the print parts (`Both`, `printMoney`, `PrintToolbar`, `PrintHeader`). Print routes sit inside `<Bare><People>` (`src/apps/people/routes.tsx:35-56`).
- The only template editor is for emails (`src/pages/settings/emails.tsx:17-99`). Its templates are stored on the company record (`src/db/types.ts:482`), which staff receive. `fillTemplate` (`src/lib/email.ts:2-7`) only fills `{word}` keys.
- Helpers already exist: `amountInWords` (`src/lib/words.ts:319`), `serviceYears` (`src/lib/hr/eosi.ts:205`), and stamp and signature images (`types.ts:143-158`).
- `saveEmployee` (`src/db/people.ts:91-217`) logs joining and leaving, except during imports (`log: false`). It saves its number rule on the company (:181-188).
- `reserve_number` takes any kind (`20261006000000_sync_fixes.sql:221`) but returns nothing without a rule (:238). `NumberedEntity` (`types.ts:82-83`) has no letter.

**Missing**

- Templates, the merge, an editor, and default wording.
- A register of issued letters; warning letters form discipline records.
- A print layout, automatic drafts, and a print queue.

**Database**

- Local:
  - `LetterKind`: `salary_certificate`, `experience_certificate`, `employment_certificate`, `warning`, `noc`, `salary_transfer`, `custom`.
  - `LetterTrigger`: `joining`, `leaving`, `salary_change`.
  - `LetterTemplate {id, companyId, kind, name, nameAr?, language: 'en'|'ar'|'ar-en', subjectEn, subjectAr, bodyEn, bodyAr, showStamp, showSignature, signatoryName, signatoryTitle, autoOn?, archived, createdAt, updatedAt}`.
  - `EmployeeLetter {id, companyId, employeeId, templateId, kind, number ('' while a draft), language, addressee, purpose, subject, body (frozen at issue), issuedOn, status: 'draft'|'issued'|'void', trigger, voidReason?, createdAt, updatedAt}`.
  - Both tables, with their sync, backup and `PEOPLE_TABLES` entries, ship in Phase 0 (D3).
  - `NumberedEntity` gets `letter`. `defaultNumbering()` (`src/db/defaults.ts:30-47`) gets `HR-{year}-{counter}`, reset every year. Reads fall back to it because older company records lack the rule.
  - Signed copies go to the private personnel file, tagged `docKey: 'letter:<id>'`. Activity is logged as `employee` and never shows salary.
  - The switch is `PeopleSettings.letters` (D1).
- Cloud: both tables are already private in `20261102000000_tables_v16.sql` (D4, D16), and `staff_can_write` does not change. `20261130000000_people_alerts.sql` adds the issue guard (step 5).

**Server API**

- None: runs on the device. Numbers come from `public.reserve_number(p_company, 'letter', p_date, p_min)`. When an accountant wants a letter issued, the request goes through approvals (D6, kind `letter`). Letters are never emailed (D14).

**Screens and components**

- `src/lib/hr/letters.ts`: fields with dotted keys (`{employee.name}`, `{employee.department}` from #12, `{service.years}`, `{salary.total}`, `{salary.totalWords}`, `{letter.number}`…), `letterValues()` and `fillLetter()`. Emails keep `fillTemplate`.
- `src/lib/hr/letter-templates.ts`: default wording, and an invented employee for previews.
- `src/db/letters.ts`: `saveTemplate`, `seedDefaultTemplates`, `createDraft`, `issueLetter`, `voidLetter`, `deleteDraft`, `autoDrafts`.
- `src/apps/people/pages/letters/`:
  - `index.tsx`: issued letters and the _Letters to print_ queue.
  - `templates.tsx` and `template-editor.tsx`: both languages, field chips, preview, _Restore default_.
  - `print.tsx`: A4 with `PrintHeader` and the letter number. Stamp and signature appear only once issued; drafts show an _مسودة_ watermark (D15).
- `src/features/people/letter-dialog.tsx`; a _Letters_ tab in `people/detail.tsx` (TABS :49-54); a link from `settlement.tsx`.
- Routes: `people/letters`, `people/letters/templates` and `people/letters/templates/:id`. The print routes `people/letters/:id/print` and `people/letters/print?ids=` sit inside `<Bare><People>`.
- _Letters_ (الخطابات) in `src/apps/people/manifest.ts`, _New letter_ in `src/features/shell/create.ts`, and a People overview card.
- Arabic in `src/i18n/ar/letters.ts` (شهادة راتب، شهادة خبرة، شهادة عمل، خطاب إنذار، شهادة عدم ممانعة). Template text is data, not translation keys.

**Steps**

1. Types, the letter number rule and `src/db/letters.ts`, with the privacy tests written first.
2. Merge and default templates.
3. Editor, routes and menus. Defaults are seeded on first open with ids `default:<companyId>:<kind>`.
4. Letter dialog, employee tab and print page.
5. Issuing. Owners and admins issue directly; accountants ask through D6, where an approver decides (the owner or a `can_approve` member, #6). The server already lets accountants write `employeeLetters` (`can_write_record`), so `20261130000000_people_alerts.sql` adds a `records_guard` rule: only an approver may set `status: 'issued'` (42501 otherwise). Numbers are given at issue only and never reused (D12).
6. Automatic drafts from `saveEmployee`, with ids `auto:<templateId>:<employeeId>:<trigger>:<date>` (within the 128-character `records_id_check`). Then the queue and bulk print.
7. Demo data with invented names, `docs/maham-one.md`, e2e.

**Tests**

- Unit:
  - `src/lib/hr/letters.test.ts`: every field in both languages, Western digits, and KWD to three decimals and in words.
  - `src/db/letters.test.ts`: issuing reserves `HR-2026-0001` and freezes the body. Voiding keeps the number. Issued letters can't be deleted, and deleting a draft uses no number. Imports create no drafts.
  - `src/cloud/sync.test.ts`: two devices end up with one automatic draft.
- SQL, `src/cloud/sql.test.ts`: staff and viewers read nothing from either table, deletion markers stay private, and staff writes get `42501`.
- e2e, `e2e/people.spec.ts`: edit a template, issue and print a letter, and check the Arabic RTL version. A draft shows the watermark and no signature. Staff (`e2e/cloud-fake.ts`) see the lock on `/people/letters`.

**Risks**

- Letters contain salaries. The tables stay private, printing stays inside the People gate, and activity never shows salary.
- Templates on the company record would reach staff, so they get their own tables.
- Bulk edits of hundreds of employees could flood the queue: imports are skipped and each save is capped.
- Offline devices could issue duplicate numbers. The first issue saves the rule on the company, and from then on `reserve_number` hands out numbers.
- Warning letters and NOCs have legal weight under Kuwaiti Labour Law. The owner or a lawyer reviews the default wording.
- A stamped letter is easy to misuse. Stamps print only on issued letters, and only owners and admins issue them.

**Decisions for the owner**

- Which letters first? _Recommended:_ salary, experience and employment certificates, warning letter, NOC.
- What should "automatic" mean? _Recommended:_ drafts only, never sent without a person.
- Who issues and signs? _Recommended:_ accountants draft; owners and admins issue.
- Which language? _Recommended:_ set per template, Arabic by default.
- Which number format? _Recommended:_ `HR-{year}-{counter}`, reset yearly.
- Should employees receive letters directly? _Recommended:_ print only for now; the Maham App can come later (D10).

## 5. Invoicing, payments and financial documents

### 20. Zoho-style Books dashboard

**Status:** Partly built · **Size:** L · **Phase:** 1

We will reorder the Books dashboard (`/books`) to follow Zoho. The order is: key figures, then receivables next to payables, cash flow, income and expense, top expenses, bank and card accounts, and a watchlist. Today's Kuwait cards stay underneath. All figures are computed from data already on the device. The new layout is a company setting that stays off until the owner turns it on (D1).

**There now**

- `src/apps/books/routes.tsx:116`: `/books` renders `pages/dashboard.tsx`.
- `dashboard.tsx:395-455`: four KPI tiles. The cash tile (`:293-304`) counts only `asset_cash` accounts, so credit cards are missing.
- `dashboard.tsx:659`: `ReceivablesCard`, with 30-day buckets from `agingReport` (`:192`). Needs attention is at `:839`. The cheques, compliance, payroll, low-stock and activity cards are at `:959-1255`.
- `dashboard.tsx:226-245`: an "Invoiced vs collected" chart that always covers 12 months, drawn by `src/components/charts/column-chart.tsx`. This is the only chart component; there is no chart library.
- Calculations that exist but aren't used here: `agingReport(..., 'bill')` (`src/lib/reports.ts:73-79`), `cashFlow()` (`src/lib/accounting/cash-flow.ts:106`), `profitAndLoss()` with the fiscal-year helpers (`src/lib/accounting/statements.ts:20-27, 92`), and `ledgerLink()` (`src/apps/books/pages/reports/financial.tsx:225`).
- `src/features/cloud/role-gates.tsx:73` `PayrollNotIncluded`: staff and viewers never receive payroll journals.

**Missing**

- A payables card, plus a Current/Overdue split on both receivables and payables.
- Cash flow, income and expense by month, and the top expense accounts.
- A list of bank and card accounts, and an account watchlist.
- A period selector, a way to hide cards, and line and bar charts.
- Projects: there is no projects module, so this card is left out.

**Database**

- Local: no Dexie change. One new optional field, `Company.dashboard?: { layout?: 'classic' | 'overview' }`; when it is missing, the classic layout is used. The chosen period, the watchlist and hidden cards go in `localStorage` under `dashboard:<companyId>`, inside try/catch as in `dashboard.tsx:80-99`. None of this goes into `DATA_TABLES` or backups (D3).
- Cloud: No change.

**Server API**

- None: runs on the device.

**Screens and components**

- `src/apps/books/features/dashboard/model.ts` (new, pure): `dashboardRange`, `payablesSummary`, `monthlyCashFlow`, `incomeExpenseByMonth`, `topExpenses` and `moneyAccountRows`. All conversions between minor and major currency units happen here.
- `features/dashboard/cards/`: `PayablesCard`, `CashFlowCard`, `IncomeExpenseCard`, `TopExpensesCard`, `BankAccountsCard` and `WatchlistCard`. The watchlist reuses the account picker in `features/accounting/account-pickers.tsx`.
- `src/components/charts/line-chart.tsx` and `bar-list.tsx`: same API as `ColumnChart`, with RTL support and a table view.
- `dashboard.tsx`: a period select that defaults to the last 12 months, plus a Classic / Overview switch for owners and admins.
- Arabic strings in `src/i18n/ar/shell2.ts`: الذمم الدائنة (payables), الإيرادات والمصروفات (income and expense), أعلى المصروفات (top expenses), قائمة المتابعة (watchlist).

**Steps**

1. Move the calculations in `dashboard.tsx:182-304` into `model.ts` unchanged, with tests that pin today's numbers.
2. Add the layout setting and the period selector.
3. Add the payables card and the Current/Overdue headlines.
4. Add the bank and card accounts card.
5. Add the line chart and the cash-flow card.
6. Add income and expense, labelled "accrual basis".
7. Add the bar chart and top expenses, linked to the ledger.
8. Add the watchlist (up to 8 accounts).
9. Hide cards by role, add the Arabic strings, and check RTL and dark themes.

**Tests**

- `model.test.ts`:
  - Each month's closing equals the next month's opening, and the last closing matches both the cash tile and `cashFlow()`.
  - Monthly income and expense match `profitAndLoss`, and payables match `agingReport('bill')`.
  - Also test a year end other than December and the credit-card sign.
- `line-chart.test.tsx`: the table toggle, RTL and negative values.
- With `peopleHidden`, salary accounts never appear.
- `e2e/dashboard.spec.ts` (new): English and Arabic, switching the period, and the watchlist after a reload. `e2e/suite.spec.ts:18` must still pass.

**Risks**

- Salaries entered as bills or journals would show up in top expenses or the watchlist (D16). Hide both cards when `peopleHidden` is true.
- People are used to today's numbers, so 30-day buckets and the 12-month period stay the defaults.
- `useLedger` rebuilds after every change, so memoise the results per period.

**Decisions for the owner**

- Should aging use Zoho's 15-day buckets? _Recommended:_ no. Keep 30-day buckets, which the aging report also uses.
- Should staff and viewers see the income, expense and watchlist cards? _Recommended:_ no. Only owners, admins and accountants see them.

### 21. Scanned attachments on payments

**Status:** Partly built · **Size:** M · **Phase:** 1

We will reuse the attachments component from bills on the payment form, the payment page and the Record payment dialog. `deletePayment` will also delete the payment's files. A scan is stored as an ordinary `attachments` row, with the payment as `ownerId`.

**There now**

- `src/features/purchases/attachments.tsx:88`: `useDraftAttachments` holds new files until `commit(companyId)` saves them. `AttachmentList` (`:120`) shows thumbnails, opens PDFs and offers "Take photo". Bills already use both (`bill-editor.tsx:102,216`).
- `src/lib/image.ts:56`: `receiptFromFile` refuses files over 10 MB and saves photos as JPEG, at most 1600 px.
- No payment screen takes files: not the form (`src/apps/books/pages/payments/form.tsx:275-314`), not the payment page (`detail.tsx:246-388`), and not `RecordPaymentDialog` (`src/apps/books/features/documents/payment-dialogs.tsx:34`).
- `src/db/payments.ts:502-506`: `deletePayment` leaves attachments behind, while `deleteDocument` deletes them (`src/db/documents.ts:783`). When sync sends a deletion, it also removes the stored file (`src/cloud/sync.ts:787`).
- Cloud: staff may write `payments` and `attachments` (`20261004000000_almailbooks_cloud.sql:260-277`). An attachment is private only when it belongs to employee data (`:236-250`).

**Missing**

- Attachments on the payment form, the payment page and the dialog.
- A paperclip icon on `payments/list.tsx`, like the expenses list has (`expenses.tsx:266`).
- Deleting a payment's files together with the payment.

**Database**

- Local: No change.
- Cloud: no change. Viewers can read payment scans and staff can add them, the same as bill scans. No D1 switch is needed: only `attachments` rows are written, and every build already syncs and backs those up.

**Server API**

- None: runs on the device.

**Screens and components**

- `form.tsx`:
  - Call `useDraftAttachments(payment?.id ?? '')` before the early returns.
  - Add an Attachments card after Cheque.
  - Include `attachments.dirty` in the unsaved-changes check.
  - Commit right after `savePayment`.
- `detail.tsx`: an Attachments card. Hide add and remove when `useRoleView().readOnly.readOnly` is true.
- `RecordPaymentDialog`: a compact attachments list, committed when the payment is saved.
- Arabic: المرفقات ("Attachments") already exists (`src/i18n/ar/orders.ts:390`). New hints, such as صورة الشيك أو إيصال التحويل ("cheque or transfer scan"), go in `src/i18n/ar/payments.ts`.

**Steps**

1. Make `deletePayment` delete the payment's attachments.
2. Add the card to the payment page.
3. Add files to the payment form.
4. Add files to the dialog.
5. Add the paperclip and the Arabic strings.

**Tests**

- `src/db/payments.test.ts`: deleting a payment deletes its files. A void or locked payment cannot be deleted, so its files stay.
- `src/cloud/roles.test.ts`: a payment's attachment is not private, and the outbox refuses a viewer's change.
- `src/cloud/sql.test.ts`: staff can upload the file (`can_use_file`); viewers cannot.
- e2e, following `e2e/purchases.spec.ts:31`: attach a scan, reload, delete the payment, and check the file is gone.

**Risks**

- If `commit` fails after `savePayment`, the payment is saved without its file. Bills behave the same way. Show a toast when it happens.
- Viewers may see bank account numbers on scans. They can already see them on the payments.
- An older build deletes a payment without its scans. The next device of this build (not a viewer's) that brings in the deletion deletes them, here and in the cloud. If no such device brings it in, the scans stay, with nothing left that shows them.

**Decisions for the owner**

- Should viewers see payment scans? _Recommended:_ yes, the same as bill scans.
- Should every cheque payment need a scan? _Recommended:_ no, keep it optional.

### 22. Invoice QR, signature and stamp (signature in blue)

**Status:** Partly built · **Size:** M · **Phase:** 1

The signature gets a "blue ink" option, and the stamp can have one too. The blue version is made once, at upload, and the original is kept (D15). Drafts will no longer print the signature or stamp; they get a DRAFT watermark instead (D15). A new setting chooses what the invoice QR encodes. The stable pay page option comes with #26.

**There now**

- `src/db/types.ts:143-158`: `Branding.stamp` and `Branding.signature` are data URLs on the company record. `src/lib/image.ts:28` stores them as PNGs up to 800 px and never recolours them.
- `src/pdf/model.ts:647-659`: the signature and stamp print on every document, drafts included. All 10 templates share `SignatureBlock` (`src/pdf/templates/shared.tsx:1098`).
- `src/components/pdf/use-pdf.ts:12-42`: the QR encodes a pasted link (`model.ts:283-291`). It prints only on unpaid invoices and proformas that aren't void (`model.ts:669-688`).
- The company record is capped at 3 MB (`20261004000000_almailbooks_cloud.sql:572`). Staff can change only its numbering (`:584-604`), so staff can't replace the signature.

**Missing**

- Ink conversion (dark strokes to blue, white to transparent) with a preview, and an optional pad to draw a signature.
- The draft rule, the DRAFT watermark and a QR content setting.

**Database**

- Local: optional `Branding.signatureInk?` and `stampInk?: 'original' | 'blue'`, plus `signatureOriginal?` and `stampOriginal?`. Optional `DocumentDefaults.qrContent?: 'payment_link' | 'pay_page'`. Turning the QR off stays with the existing `PaymentSettings.showQrCode` (Settings → Payments, `src/pages/settings/payments.tsx:99`; read at `src/components/pdf/use-pdf.ts:39` and `src/pdf/model.ts:687`). Missing fields keep today's behaviour. The blue image is stored in `signature` and `stamp`, so older builds print it as is. No Dexie change.
- Cloud: no change. To stay under the cap, originals are stored at 600 px or less, and a save is refused if the company record would pass 2.5 MB.

**Server API**

- None: runs on the device.

**Screens and components**

- `src/lib/image.ts`: a pure `inkPixels(data, ink, threshold)` and a canvas wrapper `inkImage(dataUrl, ink)`. `ImageField` (`src/features/company/fields.tsx:172`) runs them once, at upload.
- `src/pages/settings/company.tsx:420-431`: an Original / Blue ink (حبر أزرق) choice, with a preview.
- `model.ts`:
  - Drafts drop the signature and stamp images and set `watermark: 'draft'`.
  - A new `DraftWatermark` in `shared.tsx` draws it, using a new `draftStamp` label (مسودة, "Draft") in `src/pdf/labels.ts`.
  - `model.ts` also applies `qrContent`.
- `src/apps/books/pages/templates.tsx`: a QR content choice (payment link or pay page) with a link to the existing switch in Settings → Payments. Arabic strings go in `src/i18n/ar/company.ts` and `documents-pdf.ts`.

**Steps**

1. Build `inkPixels` and `inkImage`, with tests.
2. Add the Branding fields, keep the original at upload, and add the settings choice.
3. Add the draft rule and the watermark.
4. Add `qrContent` (#26 adds `pay_page`), then the Templates page and Arabic strings.

**Tests**

- `src/lib/image.test.ts` (new): black becomes blue, white becomes transparent, and soft edges stay partly transparent.
- `src/pdf/model.test.ts` (near `:316-344`):
  - A draft has no images and has the watermark.
  - A sent invoice keeps its images.
  - `showQrCode: false` prints no QR whatever `qrContent` says.
  - Missing fields give today's output.
- `src/pdf/templates.test.tsx`: every template draws the watermark.

**Risks**

- The draft rule changes today's draft PDFs, because D15 applies without a setting. Note it in the release notes.
- Photos with shadows can tint badly. Show a preview, tune the threshold and keep the original.
- A signature image is not a qualified electronic signature under Kuwait Law 20/2014, so the app calls it a printed signature.

**Decisions for the owner**

- Should the stamp be blue too? _Recommended:_ no, only the signature.
- Should each signatory have their own signature? _Recommended:_ not in v1, because the company record syncs to every member.

### 23. Burgan Bank and KFH cheque printing

**Status:** Partly built · **Size:** L · **Phase:** 1

We will print a recorded cheque issued straight onto a Burgan (`BRGN`) or KFH (`KFHO`) leaf from per-bank millimetre layouts in `chequeLayouts` (D3), and keep a record of every print on the cheque. Printing posts nothing to the ledger.

**There now**

- `src/db/types.ts:851-877`: `ChequeDetails` (`number`, `bank` as a `KUWAIT_BANKS` code, `date`, `drawer` = payee when issued, `status`) on `Payment.cheque`.
- `src/lib/kuwait.ts:206-213`: `KFHO` بيت التمويل الكويتي and `BRGN` بنك برقان.
- `src/lib/words.ts:319-327`: `amountInWords(amount, currency, 'en'|'ar')`.
- `src/apps/books/pages/cheques/print.tsx` prints only the register; `booksPrintRoutes` (`src/apps/books/routes.tsx:79-112`) wraps print views in `Bare`.
- `src/apps/books/pages/payments/detail.tsx:192-193`: _Print voucher_; `src/apps/books/features/payments/fields.tsx:302-310`: _Pay to_.
- `src/features/payroll/print.tsx:85`: existing `@page` injection.

**Missing**

- Leaf layouts in mm; auto-fill of date, payee, figures and words over two lines.
- Company and per-device offsets; test print.
- Print record, spoiled leaves, rules against printing a voided, cancelled, cleared or returned cheque, or twice.
- Optional crossing "يصرف للمستفيد الأول / A/C payee only".

**Database**

- Local: `chequeLayouts` (`id, companyId, bank`) ships in Dexie 16 in Phase 0 with `DATA_TABLES`, `backupSchema`, labels and roles; not private, not staff-writable (D3). Type `ChequeLayout {id, companyId, bank, name, nameAr?, version, size, offset, fields (date, payee, wordsLine1, wordsLine2, figures, crossing?: mm boxes), dateStyle, wordsLanguage, figures {prefix, guard}, calibrated, archived, …}`. Optional `ChequeDetails.printedAt?`, `printCount?`, `printedLayoutId?`, `printedText?`, `crossed?`, `spoiledLeaves?`. Printer offsets in `db.meta` (`cheque-offset:<layoutId>`), never synced or backed up. Switch `Company.chequePrinting?` (D1).
- Cloud: No change in Phase 1: `20261102000000_tables_v16.sql` already admits `chequeLayouts`. No separate migration is needed (D4).

**Server API**

- None: runs on the device.

**Screens and components**

- `src/lib/cheque-layouts.ts`: `BRGN`/`KFHO` presets (`calibrated: false`), `layoutFor(bank)`.
- `src/lib/cheque-print.ts` (pure): `chequeFace()`, `splitWords(text, widthsMm, measure)`, `canPrint(payment)`.
- `src/apps/books/pages/cheques/cheque-print.tsx`: `Bare` route `payments-made/:id/cheque` on the mm page helper from #28. After printing it asks "Did the cheque print correctly?" → record the print, or record a spoiled leaf and the next number.
- `cheques/layouts.tsx` (`/cheques/layouts`, shell) with a to-scale preview; `cheques/test-print.tsx` (`Bare`) with rulers and ±0.5 mm nudges.
- `src/db/cheque-print.ts`: `saveChequeLayout`, `recordChequePrinted`, `recordSpoiledLeaf`, logging `'cheque'` activity (`types.ts:1038`).
- _Print cheque_ on the payment and in the register row menu. Arabic in `src/i18n/ar/payments.ts` (طباعة الشيك, نماذج الشيكات, ورقة تالفة).

**Steps**

1. Measure a voided leaf per bank (300 dpi at 100%); write presets.
2. `cheque-print.ts` with tests.
3. Types and `src/db/cheque-print.ts`.
4. Print page and confirm dialog.
5. Layout editor, device offset, test print.
6. Entry points, setting, Arabic, e2e.
7. Calibrate on the office printer; set `calibrated: true`.

**Tests**

- Unit: `src/lib/cheque-print.test.ts` (KWD 0.500, 1.000, 1,250.750, 100,000.000 in ar/en; guards; split keeps every word; refuses voided, cleared, received, non-KWD); `src/db/cheque-print.test.ts` (count, snapshot, spoiled leaf).
- SQL: `src/cloud/sql.test.ts` accountant pushes `chequeLayouts`; staff and viewer refused.
- e2e: `e2e/cheques.spec.ts` record a cheque issued, print, check fields, confirm, see "Printed on".

**Risks**

- Printer scaling shifts fields: 100%, no margins, test print first; Chrome/Edge.
- Two prints are two negotiable cheques: every print is logged. Reprinting, or editing a printed cheque's amount, payee or number, first marks the leaf spoiled.
- Words must equal figures: one amount rounded to 3 decimals.
- With cheque confirmation (#9) on, an unconfirmed cheque is only a request (D13). _Print cheque_ exists only on a Payment, so nothing prints before Mr. AbdulAziz Almail confirms.

**Decisions for the owner**

- One voided leaf per bank, plus the printer model and feed? _Recommended:_ 300-dpi scans and a manual single-leaf test.
- Words in Arabic, English or both? _Recommended:_ Arabic; English optional per layout.
- Who prints, who edits layouts? _Recommended:_ staff and above print; owner, admin, accountant edit.
- Cross "A/C payee only" by default? _Recommended:_ off, per cheque.
- Chequebook tracking or salary cheques? _Recommended:_ not now; D3 has no table, and salary payees are People data (D16).

### 24. Receipt and payment vouchers (سند قبض / سند صرف)

**Status:** Partly built · **Size:** M · **Phase:** 1

Today's bilingual voucher becomes a PDF people can download and share, at the same URLs, and expenses get vouchers too. The stamp and the blue signature from #22 are optional. Vouchers keep the payment and expense numbers (PAY-, PM-, EXP-), so there is no new number sequence (D12).

**There now**

- `src/apps/books/pages/payments/voucher.tsx:33-56`: `WORDS` holds the bilingual labels (سند قبض, سند صرف, استلمنا من, وذلك عن).
- The voucher page (`:83`) prints the logo, CR number, Hijri date, amount in words and cheque details. It also prints a VOID mark (`:157-166`) and three fixed signature lines (`:306-317`). It is HTML only, printed with `window.print()`.
- `src/apps/books/routes.tsx:78-95`: `payments/:id/voucher` and `payments-made/:id/voucher`, both protected in `src/app/routes.test.ts:33-34`. They open from `payments/detail.tsx:192` and from the cheque menu (`src/apps/books/features/cheques/action-dialogs.tsx:144`).
- `src/pdf/statement/render.ts:8-20` is the pattern for rendering a PDF on the page.
- `e2e/cheques.spec.ts:97-110` checks for "Receipt voucher" and "سند قبض".

**Missing**

- Expenses (`src/db/types.ts:1071`, vendor optional) have no voucher.
- There is no PDF download, no stamp or signature image and no company address. The signature lines can't be changed.

**Database**

- Local: optional `Expense.payee?: string` names who was paid when there is no vendor. Optional `Company.vouchers?: { images?: boolean; lines?: { in: string[]; out: string[] } }`; when it is missing, vouchers keep today's lines and print no images (D1). No Dexie change.
- Cloud: No change.

**Server API**

- None: runs on the device.

**Screens and components**

- `src/pdf/voucher/model.ts` (new, pure): `buildVoucherModel({kind, source: Payment | Expense, company, party, documents})`. `WORDS` moves here and the HTML page shares it.
- `src/pdf/voucher/document.tsx` and `render.ts` (new): A5 or A4, with the brand colour and logo. The stamp and signature print only when switched on, and never on void vouchers.
- `voucher.tsx`: keep the HTML sheet so printing and e2e work as before, and add a Download PDF button (تنزيل PDF). The same page serves the new Bare route `expenses/:id/voucher` (`source="expense"`), which is added to `routes.test.ts`. `ExpenseDialog` (`src/features/purchases/expense-dialog.tsx:54`) gets a "Print voucher" button.
- `src/pages/settings/documents.tsx`: a Vouchers section with the image switch and the signature lines. Arabic strings go in `src/i18n/ar/payments.ts`.

**Steps**

1. Move `WORDS` and the voucher data into `model.ts`, with no visible change.
2. Build the PDF and the Download button.
3. Add images and company details behind `vouchers.images`.
4. Add expense vouchers, the settings section and the Arabic strings.

**Tests**

- `src/pdf/voucher/model.test.ts`:
  - wording for money in and money out;
  - cheque details;
  - expenses with and without a vendor;
  - VOID;
  - KWD amounts in words with fils, in both languages;
  - credit-note applications refused.
- `src/pdf/voucher/document.test.tsx`, built like the statement one.
- `routes.test.ts` covers the new path.
- `e2e/cheques.spec.ts` stays unchanged, plus a new expense-voucher test.

**Risks**

- Bookmarks and e2e tests rely on today's URLs and headings, so neither changes.
- Arabic text shaping in react-pdf: reuse `src/pdf/bidi.ts`.
- Any member can print a signed voucher, so images stay off until the owner turns them on.

**Decisions for the owner**

- Should vouchers get their own RV-/PV- numbers? _Recommended:_ no, keep the payment and expense numbers.
- Should vouchers print the stamp and signature? _Recommended:_ yes, with the signature in blue (#22).

### 25. Import bank statements

**Status:** Partly built · **Size:** L · **Phase:** 1

The app already imports CSV and OFX statements. We will add Excel files through the app's existing XLSX reader. The import will find the header row even when a bank puts account details above it, and will remember each account's column layout. We will also add presets for the company's Kuwaiti banks. PDF comes last, and only for a bank with no Excel export. Files that import today keep working as they do now (D1).

**There now**

- `src/lib/banking/statement.ts`:
  - `parseCsvRows` (`:30`) and date formats with Arabic month names (`:80-158`).
  - `parseAmount` (`:174`) reads KD and د.ك, Arabic digits, DR/CR and مدين/دائن.
  - `guessMapping` (`:258`) assumes the header is row 1.
  - OFX (`:374-379`) and `fingerprints` (`:426`).
- `src/apps/books/features/banking/import-dialog.tsx`: a 5 MB limit (`:29`), UTF-8 then windows-1256 decoding (`:32-39`), column mapping and a preview. `accept` covers only csv, txt, ofx and qfx (`:186`).
- `src/db/banking.ts:20`: `importStatement` stores amounts in the company currency and skips lines it already has, by fingerprint.
- `src/lib/xlsx.ts:426` `readXlsx`, `:42` `isOldExcel`, and `src/features/company/import-columns.ts:910` `decodeCsv` (which also reads UTF-16). The data import uses these, but the bank import does not.
- `src/lib/kuwait.ts:200-215`: `KUWAIT_BANKS` lists NBOK, KFHO, BBYN, GULB and BRGN with Arabic names, among others.
- `pdfjs-dist` is installed (`package.json:39`), and `src/test/workbook.ts` builds synthetic .xlsx files.

**Missing**

- XLSX import, a clear message for old binary .xls files, and support for HTML or SpreadsheetML tables saved as ".xls".
- Finding the header under rows such as account name, IBAN and period, and dropping the totals rows at the end.
- A saved layout per account, bank presets and the value date.
- PDF statements.

**Database**

- Local:
  - Optional `Account.statementFormat?: { kind: 'csv' | 'xlsx' | 'html' | 'pdf'; headerRow: number; mapping: CsvMapping; preset?: string }`. When it is missing, the app guesses the layout as it does today.
  - Optional `BankTransaction.valueDate?: ISODate`.
  - No new table and no new Dexie version.
- Cloud: no change. Staff can't write accounts or bank lines (`20261004000000_almailbooks_cloud.sql:260-277`), which matches who is allowed to import.

**Server API**

- None: runs on the device. Kuwaiti open-banking APIs are out of scope.

**Screens and components**

- `import-dialog.tsx`: read the raw bytes and pick a reader: OFX, XLSX (`readXlsx`), HTML or SpreadsheetML, PDF (loaded on demand), or text (`decodeCsv`). Add `.xlsx,.xls,.htm,.html,.pdf` to `accept`.
- Two new controls: "Table starts at row N", with the raw rows shown, and "Remember this layout for this account" (تذكّر هذا التنسيق لهذا الحساب).
- `statement.ts`: `findHeaderRow(rows)` and `trimFooter(rows)`.
- New files: `src/lib/banking/presets.ts` (keyed by `KUWAIT_BANKS` code), `src/lib/spreadsheet-html.ts`, and `src/lib/banking/pdf-statement.ts`, which groups pdfjs text into rows and columns.
- Arabic strings go in `src/i18n/ar/accounting.ts`.

**Steps**

1. The owner sends one redacted export per bank, and we build synthetic copies in `src/test/bank-statements/` (D16).
2. Add `findHeaderRow` and footer trimming.
3. Accept XLSX in the dialog, decoding text with `decodeCsv`.
4. Add the HTML and SpreadsheetML readers, and this message for binary .xls: "Save it as .xlsx or CSV".
5. Save each account's layout and reuse it on the next import.
6. Add the bank presets.
7. Add PDF import per bank, only where needed, then Arabic strings and e2e.

**Tests**

- `statement.test.ts`:
  - The header is found under 5 preamble rows, in English and Arabic.
  - Totals rows are dropped.
  - Separate debit and credit columns with 3 decimals.
  - Value dates.
- An XLSX built with `src/test/workbook.ts` gives the same lines and fingerprints as the same data in CSV, so importing both adds nothing new.
- HTML-as-.xls and SpreadsheetML fixtures, and `pdf-statement.test.ts` on synthetic text items.
- `e2e/banking.spec.ts`: import the same XLSX with preamble rows twice; the second import adds no duplicates.

**Risks**

- A wrong sign gives wrong reconciliations. Always preview, and compare the last line with the statement's running balance.
- Don't change `fingerprints`, or every existing line would import again.
- Real bank samples contain customer data and must never be committed.

**Decisions for the owner**

- Which banks and file formats does the company download? _Recommended:_ start with XLSX and CSV.
- Do you have bank accounts in other currencies? _Recommended:_ leave them out of v1. For now their lines would import as KWD.

### 26. Pay-by-link from the invoice QR

**Status:** Partly built · **Size:** XL · **Phase:** 6

Each issued invoice gets a stable pay token. Its QR opens `/#/pay/<token>`, which shows the amount due and hands the payer to the gateway's hosted page (KNET or card; MyFatoorah first). A verified webhook writes a `gatewayPayments` row, and an accountant's device turns it into an ordinary Payment. That way numbering, the ledger and lock dates stay on the device.

**There now**

- `src/db/types.ts:809-817`: `PaymentLinkProvider` (myfatoorah, tap, upayments, hesabe, ottu, bank, other) and `PaymentLink {provider, url, expiresAt}`. `InvoiceDocument.paymentLink` is at `:769`.
- `src/apps/books/features/payments/payment-link.tsx:29,127`: links are pasted by hand and the QR encodes them (`src/components/pdf/use-pdf.ts:12-42`), so printed QRs go stale when a link expires.
- There is one Edge Function (`supabase/config.toml:6-11`, `verify_jwt = false`). It takes `sql`, `env`, `fetch` and `now` as injected inputs so tests can fake them (`src/alerts/server.ts:53-60`).
- Nothing is open to anonymous visitors (`src/cloud/sql.test.ts:210`). `/invite/:token` (`src/app/routes.tsx:68-75`) is the pattern for a token page.
- `reserve_number` and `patch_company` refuse callers who are not signed in (`20261006000000_sync_fixes.sql:104,215`), so a webhook can't number a Payment.
- `src/cloud/sync.ts:1284-1301` `reconcile`: a payment that arrives by sync makes non-viewer devices recalculate invoice balances.

**Missing**

- A stable token and the pay page.
- Gateway checkout and a signed webhook.
- Merchant keys kept only on the server.
- Turning gateway payments into Payments.
- Cancelling links when an invoice is voided or deleted.

**Database**

- Local:
  - Dexie **18** (D3) adds `gatewayPayments: 'id, companyId, documentId, status'`, holding `{documentId, provider, transactionId, amount, currency, fee?, paidAt, status: 'new' | 'applied' | 'dismissed', paymentId?, error?}`.
  - The table goes into `DATA_TABLES`, `backupSchema` (`.default([])`), `src/cloud/labels.ts` and the role mirrors. It is not private, and staff can't write it.
  - New optional fields: `PaymentLink.token?`, `PaymentSettings.gateway?: {provider, mode, enabled}` (no secrets; missing means off, D1) and `Payment.gateway?: {provider, transactionId, eventId}`.
  - Older devices pick up the table through the D2 cursor reset.
- Cloud: `20261214000000_payment_gateway.sql` (D4) adds tbl `gatewayPayments` to `records_tbl_check`. `records_guard` (D6) refuses client inserts and lets clients change only `status`, `paymentId` and `error`. New real tables:
  - `public.payment_links (token pk, 128-bit random; company_id, document_id, status open|paid|cancelled, gateway_ref, last_checkout_at, created_by, created_at)`, which members can read.
  - `almailbooks.gateway_accounts`, which holds Vault secret ids and is not exposed.
  - `almailbooks.gateway_events (provider, event_id unique, payload, received_at)`.

**Server API**

- `public.create_pay_link(p_company text, p_document text) → text` and `public.cancel_pay_link(p_company text, p_document text) → void`. Both are security definer, for owner, admin, accountant or staff. The invoice must be synced and not void. If the invoice already has an open token, create returns it.
- `public.pay_link_details(p_token text) → table(company_name text, number text, issue_date date, balance numeric, currency text, status text)`, granted to `anon` (D4). It returns no client name and no lines.
- `public.set_gateway_account(p_company text, p_provider text, p_mode text, p_api_key text, p_webhook_secret text) → void`, owner only (D5). The keys go to Vault.
- `public.gateway_account_status(p_company text) → table(provider text, mode text, configured boolean, updated_at timestamptz)`, for owner and admin.
- Edge Function `payment-links`, a second entry in the multi-entry build (D2), with `verify_jwt = false` and its own deploy step:
  - `POST {action: 'checkout', token}`: anonymous, at most one new gateway session per token per minute. It returns `{url}` for the current balance.
  - `POST /webhook/<provider>`: checks the signature and asks the provider to confirm the status. It records the event in `gateway_events` only once and marks the link paid. It then inserts the `gatewayPayments` record with a deterministic id and calls `almailbooks.touch_sync_signal`.
  - Secrets: `SUPABASE_DB_URL` and `PAY_APP_URL`. Merchant keys stay in Vault.
- Alerts go through the change feed (D7).

**Screens and components**

- `src/pages/settings/payments.tsx`: an "Online payments" section (الدفع الإلكتروني) with the provider, test or live mode, a connect button, the status and the webhook URL.
- `src/pages/pay.tsx` (new, loaded on demand): a Bare route `/pay/:token` in `src/app/routes.tsx`, added to `routes.test.ts`. It shows the company, invoice number, amount due and status in both languages, with "Pay with KNET or card" (ادفع عبر كي نت أو البطاقة).
- `payment-link.tsx`: a "Create pay link" button. The QR (`qrContent: 'pay_page'`, #22) and `send-dialog.tsx` use the pay URL.
- `src/apps/books/features/payments/gateway-inbox.ts` (new) runs after sync on owner, admin and accountant devices:
  - Each `new` row becomes a Payment through `savePayment`, using the row's id and method `link`. The clearing account comes from `defaultDestination` (`src/lib/payment-methods.ts:138`).
  - The money is applied up to the invoice balance, any extra becomes credit, and the row is marked `applied`.
  - If saving fails (locked period, deleted invoice), the row gets an `error` and shows in Needs attention and in `src/suite/home/attention.ts`.
- `docs/payment-links.md`, plus Arabic strings in `src/i18n/ar/payments.ts`.

**Steps**

1. The owner picks a gateway and gets test keys.
2. Write the migration and SQL tests, and add the `MIGRATIONS` entry.
3. Add Dexie 18, the types and the table lists.
4. Write `src/payments/server.ts` and `edge.ts` with one provider adapter, tested with a fake fetch. Add the build entry, config and deploy step.
5. Build the settings section, link creation and the pay page.
6. Build the inbox and the attention item.
7. Run a test-mode pilot on one invoice, then go live.

**Tests**

- `src/payments/server.test.ts`:
  - checkout with open, paid, void and unknown tokens;
  - webhooks with valid, bad and replayed signatures;
  - the provider reporting a different status.
- `src/cloud/payment-gateway-sql.test.ts` (PGlite):
  - only the owner sets keys, and nobody can read them back;
  - clients can't insert `gatewayPayments` rows;
  - `pay_link_details` is the only anonymous function, and `sql.test.ts:210` is updated on purpose.
- `gateway-inbox.test.ts`: a row is applied once even with two devices, an overpayment becomes credit, and a locked period goes to review.
- e2e (`e2e/cloud-fake.ts`): the pay page in English and Arabic, and the invoice paid after a fake webhook and a sync.

**Risks**

- These are the first anonymous entry points. Use 128-bit tokens, show minimal fields, throttle checkout, re-check every webhook with the provider, and get a security review before going live.
- A customer may also pay by transfer. Money is applied only up to the balance, and the rest stays as credit.
- Two devices applying the same row write the same Payment id. One reserved number may be skipped, but it is never reused (D12).
- Keys never go into `public.records`, the company record or backups. Card details are entered only on the gateway's hosted page. The gateway gets only the invoice number, amount and client display name (D16).
- Voiding (D12) or deleting an invoice cancels its link. Companies kept on one device only can't use pay links (D5).

**Decisions for the owner**

- Which gateway does the company have a merchant account with? _Recommended:_ MyFatoorah.
- Should online payments be applied automatically? _Recommended:_ yes, through the inbox, with an alert.
- How should gateway fees be recorded? _Recommended:_ as a fee expense, through the clearing account.

## 6. Inventory and products

### 27. Quote design: layout, colour and logo

**Status:** Partly built · **Size:** M · **Phase:** 1

Quotes (and invoices and credit notes) get their own design, colour and a few layout switches over the company default. One helper resolves them (document → type → company), and Templates gets a quote preview. Missing settings keep today's look (D1).

**There now**

- `src/apps/books/pages/templates.tsx`: 10 designs, `ColorField` (`:130`); preview always an invoice (`:66`); _Use_ sets one `templateId` (`:112`).
- `src/db/types.ts:143-158`: `Branding` has one `accentColor`, `templateId`, `logo`, `stamp?`, `signature?`.
- `src/pdf/templates/shared.tsx:111`: `Logo` at a fixed size per template.
- `src/db/types.ts:752`: per-document `templateId`, resolved separately at `documents/editor.tsx:177`, `documents/view.tsx:157`, `purchases/bill-view.tsx:111`, `recurring/editor.tsx:119`, `src/components/pdf/use-pdf.ts:51`.
- `src/pdf/model.ts:793`: accent from a caller's `options.accent` (passed by `prepareModel`, `src/components/pdf/use-pdf.ts:33-41`), else `branding.accentColor`; documents store no colour of their own; `src/pdf/sample.ts:213` makes quote samples.
- Staff edits are refused on the device with a toast (`src/cloud/outbox.ts:115-121`, `src/pages/settings/shared.tsx:42`); controls stay enabled.

**Missing**

- Design, colour and layout per type; colour per document.
- Logo size and position, SKU column, item images (#29), acceptance box, quote introduction.
- Quote preview, _Quote design_ links, read-only page for staff.

**Database**

- Local: optional `Branding.byType?: Partial<Record<PrintableDocumentType, {templateId?, accentColor?, layout?}>>`, `Branding.layout?: DocumentLayout {logoSize?, logoPosition?, showSku?, showItemImages?, showAcceptance?}`, `InvoiceDocument.accentColor?`, `intro?`, `DocumentDefaults.quoteIntro?`, `LineItem.sku?` copied when an item is picked. No Dexie version; no per-type logos (D15).
- Cloud: No change.

**Server API**

- None: runs on the device.

**Screens and components**

- `src/pdf/template-resolve.ts` (new): `documentTemplate`, `documentAccent`, `documentLayout`, used at every site above.
- `shared.tsx`: `Logo` size/position; `ItemsTable` (`:378`) SKU and image columns; `SignatureBlock` (`:1098`) acceptance box (قبول العميل); stamps follow D15.
- `templates.tsx`: Invoices / Quotes / Credit notes switcher, "Same as invoices", `?type=quote`, read-only via `useRoleView` (`src/features/cloud/role-gates.tsx:24`).
- `editor.tsx:289-305`: colour beside the template select; intro on quotes.
- Links from Quotes and CRM (`src/apps/crm/manifest.ts:31`, add `templates` to `shares`). Arabic in `src/i18n/ar/documents-pdf.ts` (تصميم عرض السعر).

**Steps**

1. Types; `template-resolve.ts`; route call sites, output unchanged.
2. Layout in `RenderModel` and shared parts.
3. Templates page; editor; links; Arabic; e2e.

**Tests**

- Unit: `src/pdf/model.test.ts` resolution order and unchanged baseline; `src/pdf/templates.test.tsx` all templates × options × en/ar/ar-en.
- SQL: none (no server change).
- e2e: quotes get Classic and another colour; invoices keep theirs; staff sees read-only.

**Risks**

- A new type default re-renders older quotes downloaded later: say so on the page.
- Options × templates × languages can break RTL: few options, all render-tested.

**Decisions for the owner**

- Quotes follow invoices until changed? _Recommended:_ yes.
- Which options? _Recommended:_ the five above only.
- Quote introduction? _Recommended:_ a default in Settings > Documents, editable per quote.

### 28. Item units, SKU and QR codes, labels and printing

**Status:** Partly built · **Size:** L · **Phase:** 1

Items get a unit list (built-in plus company units, D11), automatic SKUs from a new `product` numbering series, a QR code drawn from the SKU (never stored), and printable labels and price lists. Units and auto-SKU sit behind `Company.items` switches (D1); print pages only read.

**There now**

- `src/db/types.ts:639-667`: `Product.sku` and `unit` are free text.
- `src/apps/books/pages/products/item-dialog.tsx:173-182` SKU typed by hand; `:256-265` unit is an `Input`; barcode only for stock (`:304`).
- `src/db/inventory.ts:504-514`: `saveItem` trims the SKU, never checks or assigns it.
- `src/db/types.ts:82`: no `product` in `NumberedEntity`. `reserveCounter` (`src/lib/numbering.ts:112`) and `public.reserve_number` take any key (`20261006000000_sync_fixes.sql:193-260`); `counters_only` lets staff add a missing key (`20261004000000_almailbooks_cloud.sql:466`).
- `src/components/pdf/use-pdf.ts:14-26`: `qrDataUrl`, used only for payment links.
- Units print as typed (`src/pdf/model.ts:493`); `src/db/import.ts:413-424` skips taken SKUs; the line picker ignores barcode (`src/apps/books/features/editor/item-name-input.tsx:46`).

**Missing**

- Unit list with Arabic names; auto SKU and uniqueness; item QR; labels; product and price list printing; barcode search in the picker and palette.

**Database**

- Local: optional `Product.unitId?`, `LineItem.unitId?` (`unit` stays the printed text). `NumberedEntity` gains `product`, read as `company.numbering.product ?? defaultNumbering().product` (`rule('SKU-{counter}', 5)`). `Company.items?: {units?, autoSku?, customUnits?: {id, name, nameAr, archived?}[]}`, owner/admin/accountant only. `[companyId+sku]` on `products` ships in Dexie 16 (D3).
- Cloud: No change.

**Server API**

- Existing `public.reserve_number(p_company text, p_kind text, p_date text, p_min bigint) → table(counter bigint, period text)`, any member, `p_kind = 'product'`. It returns nothing until the server copy has `numbering.product` (`sync_fixes.sql:238-240`), so switching auto-SKU on also writes that rule.

**Screens and components**

- `src/lib/units.ts`: fixed ids (pcs قطعة, box علبة, carton كرتون, kg كغ, l لتر, m متر, hour ساعة, day يوم, month شهر, trip رحلة, set طقم); `matchUnit()` pre-selects on old items.
- `item-dialog.tsx`: `Combobox` (`src/components/ui/combobox.tsx:20`, `onCreate`); next-code placeholder (`previewNumber`, `numbering.ts:139`); QR preview, _Print label_.
- `src/apps/books/features/editor/line-items.tsx:159` copies `unitId`. `model.ts:493` prints `nameAr` on Arabic documents only when a line has `unitId`, so old documents print as before.
- `saveItem`: blank SKU → next code (`reserveCounter`, local fallback skipping taken codes); refuse a new or changed duplicate.
- `src/pages/settings/numbering.tsx:9-24`: _Item codes (SKU)_ (رموز الأصناف); `src/lib/qr.ts` takes `qrDataUrl` out of the PDF module.
- `src/features/print/mm-page.tsx` (new, reused by #23): `@page` size, zero margins, mm boxes, test grid.
- `products/item-labels-print.tsx`: `Bare` route `products/labels` (A4 3×8, 50×25 mm thermal). Not named "labels", because `src/pdf/labels.ts` exists.
- `products/index.tsx`: _Print_ menu (product list, price list via `usePrint`, `report-toolbar.tsx:50`); selected rows → _Print labels_. `src/features/search/sources.ts:230-234` also matches barcode. Arabic in `src/i18n/ar/inventory.ts` (طباعة الملصقات, قائمة الأسعار).

**Steps**

1. `units.ts`, types, unit picker, Arabic units in the model.
2. `product` numbering, switches, `saveItem` auto-SKU and uniqueness.
3. `qr.ts`, QR preview.
4. `mm-page.tsx`, labels, list printing.
5. Barcode search; Arabic; e2e.

**Tests**

- Unit: `src/lib/units.test.ts` (pc, pcs, قطعة → one id); `src/db/inventory.test.ts` (SKU-00001 then -00002; manual kept; taken skipped; unchanged old duplicate saves; new duplicate refused; no `numbering.product`); `src/cloud/testing/fake-cloud.ts` two devices, distinct SKUs; `src/pdf/model.test.ts` Arabic unit.
- SQL: `src/cloud/sql.test.ts` `reserve_number` with `product`, staff advance it.
- e2e: `e2e/inventory.spec.ts` new item shows SKU and QR; labels page; box/علبة.

**Risks**

- Old free-text units stay as custom text.
- Checking old duplicates would block edits: only new or changed SKUs.
- Offline local fallback can repeat a SKU: show it as a sync problem, like duplicate document numbers.
- The QR holds the SKU: warn when a labelled SKU changes.

**Decisions for the owner**

- SKU pattern? _Recommended:_ `SKU-{counter}`, 5 digits, editable.
- Codes for existing items? _Recommended:_ a one-click _Give codes to items without one_.
- QR content? _Recommended:_ the SKU, which any scanner types into item search.
- Label sizes? _Recommended:_ A4 3×8 and 50×25 mm thermal; Code 128 later.

### 29. Product images

**Status:** Not built · **Size:** M · **Phase:** 1

Product images become attachments owned by the product (`Product.imageIds`, first is main), copying the employee-photo pattern. Files use the existing Storage bucket, so no table or migration is needed. Behind `Company.items.images` (D1).

**There now**

- `src/db/types.ts:639-667`: no image on `Product`.
- `src/db/people.ts:467-500`: `setEmployeePhoto`/`removeEmployeePhoto` store an attachment and delete the old one; `saveEmployee` keeps the stored `photoId` (`:147`).
- `src/features/people/employee-photo.tsx`: `useEmployeePhotos` (`:88`), `EmployeePhotoEditor` (`:103`); shared code Books may import.
- `src/db/purchases.ts:145-155`: `removeAttachment` clears `employee.photoId`.
- `src/db/inventory.ts:585-603`: `deleteItem`'s transaction has no `attachments`.
- `src/cloud/files.ts`: files ≤1.5 MB sync eagerly; bucket takes `image/*` up to 10 MB (`20261004000000_almailbooks_cloud.sql:1514-1515`). Product attachments aren't private, and staff may write them (`src/cloud/roles.ts:53-68`).

**Missing**

- Upload, preview, replace, rotate, remove, set main; thumbnails; clean-up on delete; `saveItem` spreads a possibly stale draft (`inventory.ts:504-514`).

**Database**

- Local: optional `Product.imageIds?: ID[]`, `Company.items.images?`. No Dexie version (attachments indexed by `ownerId`, `src/db/db.ts:168-170`); backups already carry attachments.
- Cloud: No change.

**Server API**

- None: runs on the device.

**Screens and components**

- `src/lib/image.ts`: `productImageFromFile(file, max = 1024)` (aspect kept, JPEG 0.85) beside `photoFromFile` (`:84`); `rotateImage`.
- `src/db/product-images.ts` (new): add, replace, remove, set main, rotate in a `products`+`attachments`+`activities` transaction. `saveItem` keeps `existing.imageIds`; `deleteItem` deletes the files; `removeAttachment` drops the id.
- `src/apps/books/features/inventory/product-image.tsx`: `ProductThumb`, `useProductImages`, `ProductImageEditor` (full size via `openAttachment`, `src/features/purchases/attachments.tsx:35`).
- Image section in `item-dialog.tsx`; thumbnails in `products/index.tsx` and `item-name-input.tsx`. PDF images come with #27's `showItemImages`, loaded in `prepareModel` (`use-pdf.ts:32-41`) only when it is on.
- Arabic in `src/i18n/ar/inventory.ts` (صورة الصنف, صورة رئيسية).

**Steps**

1. Image helpers; type; db functions and the `saveItem`/`deleteItem`/`removeAttachment` changes.
2. Editor, thumbnails, switch.
3. Arabic; e2e.

**Tests**

- Unit: `src/db/product-images.test.ts` like `employee-photos.test.ts` (replace removes the old file, a stale save keeps images, delete removes files); `src/db/backup.test.ts`; `src/cloud/sync.test.ts` staff upload, viewer reads.
- SQL: none (no server change).
- e2e: `e2e/inventory.spec.ts` upload, thumbnail, reload.

**Risks**

- Storage growth: 1024 px, about 200 KB, five per item.
- Older builds deleting an item leave its files: harmless until devices update.
- Files over 1.5 MB arrive when opened: placeholder, never block a PDF.

**Decisions for the owner**

- How many images? _Recommended:_ one main plus four.
- On invoices and quotes? _Recommended:_ off; per type via #27.
- Edit without crop? _Recommended:_ yes: replace, rotate, remove, set main.

### 30. Bulk import of stock items from Excel or CSV

**Status:** Partly built · **Size:** M · **Phase:** 1

The existing products import gains type, cost, quantity and warehouse columns. It posts opening stock through `addStockEntry` inside the same all-or-nothing transaction. Nothing posts unless a quantity column is mapped and the user confirms that import (D1).

**There now**

- `src/pages/settings/import.tsx`: products kind (`:68`), `.csv/.txt/.xlsx` (`:659`), 5 MB (`:57`); as-of date only for contacts and opening balances (`:561`).
- `src/features/company/import-columns.ts:200`: product columns name, sku, unit, price, descriptions; `readImportFile` (`:940`) uses `readXlsx` (`src/lib/xlsx.ts:426`).
- `src/db/import.ts:413-454` plan skips taken SKUs; commit `:896-906` in one transaction (`:790`); `ImportOptions` (`:79-95`) has `asOf`, `updateExisting`.
- `src/db/inventory.ts:632-698`: `addStockEntry` (not exported) checks lock date, stock items, warehouse; `src/lib/accounting/ledger.ts:701-745` posts Dr Inventory / Cr Opening balance equity.
- `src/apps/books/pages/inventory/count.tsx:200`: count sheets CSV only.

**Missing**

- Type (imports become services), cost, quantity, warehouse, reorder level and barcode columns.
- Opening stock; updating existing items; default taxes (`products/index.tsx:133`).
- Double-count guard; `.xlsx` count sheets.

**Database**

- Local: No change in tables. `ImportOptions.warehouseId?`; `StockEntry.reference` = file name.
- Cloud: No change.

**Server API**

- None: runs on the device.

**Screens and components**

- `import-columns.ts`: نوع الصنف (مخزون / خدمة / غير مخزني), سعر التكلفة, الكمية, المستودع, حد إعادة الطلب, الباركود, with English aliases; generic template rows.
- `import.ts` plan: validate (quantity needs a stock item; unknown warehouse or negative is an error), default taxes, #28 SKU and units when on.
- `import.ts` commit: adds `stockTables()` (`inventory.ts:51`), exports `addStockEntry`, one OPN per warehouse, a `count` adjustment for items with history; any stock error refuses the whole file.
- `import.tsx`: _Stock as at_, Warehouse, "opening stock worth KD X to Opening balance equity", a warning when `company.openingBalances` touch Inventory. Quantities only for owner, admin, accountant.
- `count.tsx`: `.xlsx` via `readImportFile`. _Import_ on `products/index.tsx`. Arabic in `src/i18n/ar/company.ts`.

**Steps**

1. Columns and validation.
2. Commit with opening stock; existing items as counts.
3. Import page; `.xlsx` count sheet; Arabic; e2e.

**Tests**

- Unit: `src/db/import.test.ts` stock items → one OPN per warehouse, Dr Inventory = Σ qty × cost; bad rows import nothing; locked date refused; Arabic headers; `.xlsx` equals CSV; 2,000 rows.
- SQL: none (no server change).
- e2e: `e2e/inventory.spec.ts` import an `.xlsx`, see stock and the OPN entry.

**Risks**

- Stock counted twice with the trial balance: warn, require confirmation.
- OPN numbers are taken on the device (`inventory.ts:626`): import on one device at a time.
- The staff limit is device-only; the server accepts staff stock entries.

**Decisions for the owner**

- Existing items' quantities as a count? _Recommended:_ yes.
- Default date and warehouse? _Recommended:_ last day of last month; main store.
- Does the trial balance already hold stock value? _Recommended:_ keep stock out of it; import it here.

## Appendix: server endpoints by phase

Everything new on the server, collected from the sections above. All RPCs are `security definer` or `security invoker` functions in `public`, callable by signed-in users only (`authenticated`), unless marked _anonymous_. Each section gives the exact arguments, results and who may call each one.

| Phase | Migration (D4)          | RPCs                                                                                                                                                                                                                                                                                                                                                              | Edge Functions                                                                          |
| ----- | ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| 0     | `tables_v16`            | none (table list and privacy rules only)                                                                                                                                                                                                                                                                                                                          | multi-entry build; `email-alerts` unchanged                                             |
| 3     | `super_admin_approvals` | `my_permissions`, `team_permissions`, `set_member_permissions`, `owned_companies_overview` (#6); `approvals_overview` (#8)                                                                                                                                                                                                                                        | none                                                                                    |
| 3     | `change_feed`           | `notification_feed`, `mark_notifications_read`, `change_notification_settings`, `set_change_notifications` (#7)                                                                                                                                                                                                                                                   | `email-alerts` gains `{action: 'notify'}`, run by a 5-minute cron (#7)                  |
| 4     | `people_alerts`         | Built (finder); AI in Phase 8                                                                                                                                                                                                                                                                                                                                     | `email-alerts` gains the payroll approval email (#10) and the new document stages (#18) |
| 6     | `payment_gateway`       | `create_pay_link`, `cancel_pay_link`, `set_gateway_account`, `gateway_account_status`; `pay_link_details` (_anonymous_, by unguessable token) (#26)                                                                                                                                                                                                               | `payment-links`: the pay page's API and the gateway webhooks (#26, #5 part B)           |
| 7     | `employee_app`          | `create_employee_invite`, `revoke_employee_access`, `employee_app_access` (HR); `accept_employee_invite`, `my_employee_links`, `my_employee_profile`, `my_leave`, `submit_leave_request`, `withdraw_leave_request` (#11); `my_messages`, `mark_message_read`, `acknowledge_message`, `save_push_subscription`, `message_receipts`, `message_receipt_counts` (#16) | `employee-notify`: web push to the Maham App (#16)                                      |
| 8     | `document_assistant`    | `search_company_records`, `assistant_settings`, `set_assistant_settings`, `assistant_usage_report` (#4)                                                                                                                                                                                                                                                           | `document-assistant`: `{action: 'ask'}` and `{action: 'read'}` (#4)                     |

Phases 1, 2 and 5 need no new endpoint: their features run on the device and travel through the existing sync. Phase 5's `staffingCostings` needs only its migration.

## Appendix: how each release goes out

1. The SQL tests run (PGlite, `src/cloud/*sql*.test.ts`) with the new migration added to `MIGRATIONS`.
2. The owner pastes the migration into the Supabase SQL editor (`docs/supabase-setup.md`). It is safe to run twice.
3. The app ships. CI runs format, lint, typecheck, unit tests, the build, the functions build and Playwright, then deploys to Vercel and the Edge Functions. Features whose server part is missing stay hidden (D4).
4. Devices pick up the update the next time someone accepts the "update available" prompt, so expect old versions to stay in use for a while (D2).
5. The owner switches the feature on in Settings (D1), first in a test company, then in production.
