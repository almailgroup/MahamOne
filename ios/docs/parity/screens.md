# Every screen of the web apps (the parity checklist)

Each screen here gets a native twin that shows and does the same things on an iPhone.

Path roots:
- **B/** = `src/apps/books/pages/`
- **P/** = `src/apps/people/pages/`
- **S/** = `src/pages/`
- **T/** = `maham-tasks/src/`

## Rules for every screen (Maham One)

**Roles** (`src/cloud/roles.ts`):

| App | Who can do what |
|---|---|
| Books, Sales, Inventory | Owner, admin and accountant manage; staff edit; viewers view only |
| People | Owner, admin and accountant only; everyone else sees a lock card |
| CRM | Accountant and staff edit; viewers view |
| Compliance | Staff and viewers view only |

- The owner can lower any member's access per app. A view-only app shows an amber banner and
  turns saving off (`src/suite/app-gate.tsx`).
- The server refuses staff writes to accounts, journals, assets, VAT and payroll. For staff,
  Templates, Invoice defaults, Items and Payment details are read-only.
- **Approvers** are the owner, plus up to 2 admins or accountants marked "Can approve".

**Lists** follow one pattern:
- A header with the title, description, Export CSV and New X.
- Status chips with counts, and a search box.
- On a phone, one card per row.
- "Show more (N remaining)" after 50 rows.

**Editors** have a sticky Cancel/Save bar on a phone, and warn before leaving with unsaved
changes.

## Home

### `/` — `src/suite/home/index.tsx`
1. **Greeting**, then the company and the date.
2. **Launcher:** "Find an app or tool", then sections:
   - Your apps, each with a status line;
   - Create (up to 6);
   - Tools;
   - Company tools;
   - Integrations.
3. **Needs attention:** topic chips, up to 8 red or amber lines, then "And N more".
4. **Approval requests** (approvers, or the person's own pending requests), linking to
   `/approvals`.
5. **At a glance** (Books access only):
   - Owed to you → `/reports/aging`
   - Bills to pay → `/bills?status=unpaid`
   - Cheques in hand

### `/books` — `B/dashboard.tsx`
- Classic/Overview switch (owner and admin only).
- "Finish setting up" checklist.
- Four figures, 2×2 on a phone: Cash and bank, Owed to you, You owe this week, Cheques due.
- **Classic cards:**
  - Who owes you (aging)
  - Needs attention
  - Cheques due
  - Deadlines and renewals
  - Payroll (hidden from staff and viewers)
  - Low stock
  - Invoiced vs collected (12 months)
  - Recent activity
- **Overview:** a period picker, and cards each person can hide:
  - Income and expense
  - Cash flow
  - Bank accounts
  - Top expenses
  - Watchlist
  - Receivables and payables aging

## Sales

Six document types share `B/documents/list.tsx`, `editor.tsx` and `view.tsx`:
`/invoices`, `/quotes`, `/credits`, `/proformas`, `/sales-orders`, `/delivery-notes`, each with
`/new`, `/:id` and `/:id/edit`.

### List

**Chips:**

| Type | Chips |
|---|---|
| Invoice | All / Draft / Unpaid / Overdue / Paid / Void |
| Quote | All / Draft / Sent / Accepted / Expired / Invoiced / Converted / Declined |
| Credit note | All / Draft / Open / Applied / Void |
| Proforma | All / Draft / Sent / Accepted / Expired / Converted |
| Sales order | All / Draft / Confirmed / Partially invoiced / Invoiced / Cancelled |
| Delivery note | All / Draft / Delivered / Cancelled |

Every type adds "Waiting for approval" when approval rules are on.

**Search** covers number, client and PO.

**Card:** the client; "number · date"; the total; badges. Totals per currency at the foot.

### Editor

**Header fields:**
- Client\*, with "New client".
- Number: automatic, unique.
- PO / reference.
- Issue date: today.
- Due date (terms) for invoices; Valid until for quotes and proformas.
- Delivery date and place.
- Received by and Civil ID, on delivery notes once delivered.
- Currency (locked once paid), and Exchange rate.

**Items:** product search, Arabic name, description, quantity, unit, price, discount (% or
amount), taxes, serial number, condition, section headings, move, duplicate, remove. Delivery
notes have no prices.

**Notes:** Introduction (quotes only), Notes, Terms, Footer, Private notes.

**Totals:** discount, tax on the total, charges, retention %, prices include tax, deposit.

**Template and colour:** in the Preview sheet.

**Saving:**
- Save ▾, with "Save and mark as sent" and "Save and download PDF".
- Under approval rules, an issued document gets "Send for approval" with a reason.
- A credit-hold or credit-limit confirmation can come up.

### View

**Title:** "Invoice INV-…", the status and the client.

**Buttons:** Download PDF, Print, Edit, WhatsApp (invoices and quotes).

**Main action, by state:**
- Record payment
- Convert to invoice
- Apply to invoice
- Confirm order
- Create invoice
- Create delivery note
- Mark as delivered
- Mark as sent
- Send

**More menu:**
- Send by email
- Send reminder
- Mark as sent
- Mark as accepted / declined
- Convert to proforma or sales order
- Create delivery note
- Create credit note
- Mark as not delivered
- Duplicate
- Void / Request void / Void and reissue
- Restore / Request restore / Issue again
- Reopen
- Cancel order / Cancel delivery note
- Delete, hidden when the rules void instead

**Body:**
- The PDF preview.
- Summary: dates, total, deposit, paid, balance, sent, voided, replaces, related documents.
- Approval card.
- Payment link card.
- Order progress.
- Payments / Applied to, with "+ Add".
- Activity.

**Dialogs:**
- **Email:** To, Subject, Message, Mark as sent; Share PDF, Open email app, Copy text.
- **Reminder.**
- **WhatsApp:** number, EN / AR / both.
- **Record payment.**
- **Apply credit.**
- **Part:** quantity per line.
- **Deliver:** date, received by, Civil ID.
- **Reason:** for voiding or for asking an approver.

### Recurring — `B/recurring/list.tsx`, `editor.tsx`
- **List:** name, client, next date, Active / Paused / Completed.
  - Row menu: Edit, Create next invoice now, Pause / Resume, Delete.
- **Editor:**
  - Name, Client\*.
  - Frequency: weekly, every 2 weeks, monthly, every 2 months, quarterly, every 6 months,
    yearly.
  - First date; Ends (never / after N); Payment due (days).
  - Currency, Exchange rate, Template, Mark new invoices as sent, Active.
  - Items, Totals, Notes / Terms / PO, and a placeholder preview.

### Payments received — `B/payments/list.tsx`, `form.tsx`, `detail.tsx`
These screens are shared with payments made.

**List:** Record payment, Export CSV, method filter, search. Columns: Number, Date, Client,
Method, Reference / Cheque no., Amount, Applied / Unapplied, Voided, files.

**Form:**
- Client\*, Amount\*, Currency, Date.
- Method: Bank transfer, KNET, Cash, WAMD, Cheque, Payment link, Credit card, Buy now pay
  later, Cash on delivery, Credit note, Other.
  - Cash is limited by the business activity, with an "I confirm this cash payment" tick.
- Provider (MyFatoorah / Tap / UPayments / Hesabe / Ottu / Bank) and Fee.
- Deposit to, Exchange rate.
- Cheque: number\*, bank, date, drawer, drawer's Civil ID.
- Reference, Notes, Attachments.
- "Apply to invoices", with "Apply oldest first". Whatever isn't applied stays as client
  credit.
- Save, or "Send for confirmation" under the cheque rules.

**Detail:** Cheque actions, Print voucher, Email receipt, Edit, Delete; details, the cheque,
Applied to, attachments, the cheque approval card.

### Clients — `B/clients/*`, `src/features/clients/client-form.tsx`

**List:** Active / Archived, search. Card: name, number, badges, balance.

**Detail:**
- **Badges:** archived, credit hold, returned cheques, retention, tax exempt, currency, also a
  vendor.
- **Buttons:** New quote, New invoice, Edit.
- **More menu:** New credit note, New sales order, Record payment, Credit hold on / off,
  Archive / Restore, Delete.
- **Summary strip:** balance, overdue, credit used vs limit, cheques in hand, last payment.
- **Tabs:**
  - Overview
  - Documents
  - Payments
  - Statement (period, language, PDF, Print, CSV, WhatsApp)
  - Retentions (release, certificates)

**Form:**
- Client and/or Vendor; Name\*; Arabic name.
- Contacts: name, email, phone, primary.
- Billing address: Kuwait style (Governorate, Area, Block, Street, Avenue, Building, Floor,
  Office, Landmark, PACI no., P.O. Box) or generic.
- Shipping address.
- Tax ID; Civil ID (12 digits); Phone; Website.
- Currency; Payment terms; Document language; Tax exempt.
- Credit limit and hold.
- Retention % and "held until".
- Notes.

## Purchases

### Vendors
The client pages with `kind=vendor`:
- **Buttons:** New bill, Edit.
- **More menu:** New vendor credit, Record payment, Record expense, Archive, Delete.
- Adds an Expenses tab.

### Bills, vendor credits, purchase orders
List: `B/documents/list.tsx`. Editor: `B/purchases/bill-editor.tsx`. View: `bill-view.tsx`.

**Chips:**

| Type | Chips |
|---|---|
| Bill | All / Draft / Unpaid / Overdue / Paid / Void |
| Vendor credit | All / Draft / Open / Applied / Void |
| Purchase order | All / Draft / Issued / Partially billed / Billed / Cancelled |

**Editor:**
- Vendor\*, Vendor reference, Number, dates, terms, delivery for POs, PO, Currency, Rate.
- Lines: Category\* (an expense or asset account), description, Arabic name, quantity, price,
  tax, amount.
- Attachments (with the camera), Totals, Notes, Terms, Private notes.
- Save as draft, Save.

**View:**
- **Buttons:** PDF / Print (POs only), Edit.
- **Main action, by state:** Mark as open / issued, Convert to bill, Record payment, Apply to
  bill.
- **More menu:** Create vendor credit, Allocate landed costs, Duplicate, Reopen / Cancel,
  Restore, Void, Delete.

### Expenses — `B/purchases/expenses.tsx`, `src/features/purchases/expense-dialog.tsx`
- **List:** category filter, search. Columns: Number, Date, Description, Category, Vendor, Paid
  from, Reference, Amount, receipt; and a total.
- **Dialog:**
  - Receipt, Amount\*, Category\*, Date, Paid from.
  - More details: Tax included, Currency, Rate, Vendor or "Paid to", Reference, Description,
    Notes.
  - Buttons: Print voucher, Delete, Save.

### Payments made
The payment pages, going out:
- Vendor, Amount paid, Paid from, and "Pay to" for cheques.
- Payments apply to bills; anything left over is an advance.

### Cheques — `B/cheques/index.tsx`
**Tabs:** Received / Issued / Security.

**Received and issued tabs:**
- **Tiles:** Overdue, Due today, Next 7 days, Next 30 days.
- **Filters:** open / week / overdue / returned / all, plus "Waiting for confirmation".
- **Columns:** Date, Number, Bank, Drawer or payee, Amount, Status, Days to maturity.
- **Row actions:** Deposit, Mark cleared, Mark returned (reason, bank charge), Replace, Cancel,
  Open payment, Print.

**Security tab:**
- "Add security cheque": received or given, contact, held by, number, bank, amount, currency,
  date, Civil ID, purpose, notes.
- Row actions: Mark cashed, Give back, Edit, Delete.

**Cheque layouts:** `/cheques/layouts?bank=`.

## Print pages
- **Vouchers** (`B/payments/voucher.tsx`; the model is in `src/pdf/voucher/`): a bilingual
  receipt or payment voucher, with the amount in words, signature lines, stamp, and a VOID
  mark.
- **Cheque print** (`B/cheques/cheque-print.tsx`): Burgan and KFH leaves, "A/C Payee Only".
  Afterwards it asks: printed / spoiled (reason, next leaf) / didn't print.
- **Test print** (`B/cheques/test-print.tsx`).
- **Cheque register** (`B/cheques/print.tsx`).
- **Stock count sheet** (`B/inventory/count-print.tsx`).
- **Item labels** (`B/products/item-labels-print.tsx`): SKU QR codes.
- **Payslips** (`P/payroll/payslips.tsx`).
- **Payroll register by department** (`P/payroll/summary.tsx`).
- **Final settlement** (`P/payroll/settlement-print.tsx`).
- **Letters** (`P/letters/print.tsx`).

## Items and inventory

### `/products` — `B/products/index.tsx`, `item-dialog.tsx`
- **Header:** Print ▾ (product list, price list, labels), Export CSV, Import, New item.
- **Figures:** stock value, stock items, low stock.
- **Filters:** Active / Archived; type (Service / Non-stock / Stock / Low stock); search.
  Rows can be multi-selected for labels.
- **Row menu:** Edit, Print label, Adjust stock, Movements, Archive, Delete.
- **Item dialog:**
  - Type, Name\*, SKU, Arabic name, descriptions.
  - Selling and cost price, Unit, Reorder level, Preferred vendor, Barcode, HS code.
  - Opening stock, Income account, Taxes, Pictures.

### `/inventory` — `B/inventory/index.tsx`
- **Tabs:** Stock / Adjustments / Warehouses / Landed costs.
- **Header:** Adjust stock, Stock count; More (Transfer, Opening stock, Landed costs,
  Recalculate); Issue items.
- **Figures:** Stock value, Items in stock, Low stock.
- **Warehouse dialog:** Name\*, Arabic name, Belongs to, Looked after by, Issues items,
  Address, Default.

### Stock entries — `B/inventory/entry-form.tsx`, `entry-view.tsx`
- Adjustment, transfer or opening stock: Date, Warehouse(s), Reason, Reference, lines, Notes.
  Button: Post.
- The view shows the entry with its accounting; Void.

### Issued items — `B/inventory/issues*.tsx`
- **Chips:** All / Waiting / Issued / Void.
- **Form:** From warehouse, Date, Employee\*, Items, Notes. Button: Issue, or send for approval.

### Stock count — `B/inventory/count.tsx`
- On record vs counted, and the difference.
- Print sheet, Export, Import counts, Clear, Post adjustment.

### Landed costs — `landed-cost-form.tsx`, `landed-cost-view.tsx`
- Charges bill, goods bill, split by value or quantity, allocation table. Button: Allocate.
- The view has Void.

## Accounting

### `/accounts` — `B/accounting/chart.tsx`
- Search, archived; Code, Name, Type, Balance.
- New account dialog: Code, Name, Arabic name, Type, Description, bank details.

### `/journals` — `journals.tsx`, `journal-editor.tsx`
- **List chips:** All / Manual / Made by the app.
- **Editor:** Date, Reference, Notes, Lines (Account, Description, Debit, Credit), Total and
  Difference.
  - Buttons: Save as draft, Save and post, Delete.
  - Journals the system made are read-only.

### `/assets` — `B/assets/*`
- **Figures:** cost, accumulated depreciation, book value.
- **Tabs:** Register / Depreciation runs.
- **Actions:** New asset, Add from a bill, Run depreciation, Undo a run.
- **Form:**
  - Asset details.
  - Purchase: paid now, from a bill, or owned before.
  - Depreciation: start, life, method, rate, salvage, already charged, accounts.
  - Notes and files.
  - A live preview.
- **Detail:** Dispose of (shows gain or loss), Edit, Void, Undo disposal; the schedule.

### `/year-end` — `B/accounting/year-end.tsx`
- Profit, statutory reserve, KFAS, Zakat, NLST, income tax.
- Close (optionally lock), Reopen; closed years.

### Reports — `B/reports/*`
On a phone the report is chosen from a select.

| Group | Reports |
|---|---|
| Statements | balance-sheet, profit-and-loss, changes-in-equity, cash-flow |
| Accounting | trial-balance, general-ledger, asset-schedule, auditor-pack |
| Sales | aging, tax, sales, payments, statements, exposure, retentions |
| Purchases | payables, purchases, payments-made |
| Inventory | stock-on-hand, stock-valuation, stock-movements, low-stock, issued-items |

**Toolbar:** language (EN / AR / both), Print, CSV, period presets, compare with last year.

### Banking — `B/banking/index.tsx`
- **Account cards.**
- **Account page:**
  - Figures: In your books, Statement balance, Difference.
  - Tabs: To match / Matched / Ignored.
  - Line actions: Match, or record as invoice payment, bill payment, expense, transfer or
    other; Ignore; Delete; Unmatch; Restore.
- **Transfer money.**
- **Import statement:** Excel, CSV or OFX, with column mapping.

### VAT — `B/accounting/vat.tsx`
Only for companies that charge tax.
- The next-return card; periods with their status.
- The return's boxes drill down to their transactions.
- Mark as filed (lock), Record payment / refund, Undo, CSV.

## People and payroll (owner, admin, accountant)

### Overview and directory
- **`/people`** — `P/overview/index.tsx`: Employees, Away today, Joined in 30 days, Papers to
  renew; Away today, Coming up, Departments.
- **`/people/directory`:** search, department; cards.
- **`/people/all`:** search across all companies, CSV.

### Employees
**`/employees`** — `P/people/list.tsx`:
- Header: search all companies, Departments, CSV, Import, bulk documents and photos, New.
- Figures: Headcount, Kuwaiti share against target, Papers to renew.
- Filters: Current / Left / All; category, department, expiring documents, drivers without a
  licence.
- Multi-select to set the department.

**`/employees/:id`** — `P/people/detail.tsx`:
- Tabs: Overview (masked bank account), Leave, Loans, End of service, Letters, Issued items.

**Form** (`src/features/people/employee-form.tsx`):
- **Personal:**
  - Name (EN)\*, Name (AR), number.
  - Nationality (KW), category (Kuwaiti / GCC / Expatriate / Domestic).
  - Gender, Date of birth, Mobile, Email.
- **Papers:** Civil ID and expiry, passport and expiry, PIFSS number.
- **Residency:** article (18), number, expiry; work permit.
- **Job:** title (EN / AR), department, drives for work, hire date, probation, contract,
  annual leave days.
- **Pay:** basis, basic salary, allowances (EN / AR, amount, counts toward end of service).
- **Bank:** IBAN, bank, account / salary card.
- **Status:** active / on leave / left, with date and reason. Notes; personnel file.

**`/employees/:id/settlement`** — `P/payroll/settlement.tsx`:
- Leaving date, reason, indemnity share (or entered by hand), notice months, unused leave days,
  last salary days, deductions, notes.
- Post, Record payment, Print, Experience certificate, Reverse, Undo payment.

### Payroll
**`/payroll`** — `P/payroll/index.tsx`:
- Tabs: Pay runs / Leave / Loans / Settings. New pay run (month).
- Figures: Net pay, Employees, PIFSS due. The runs list.

**`/payroll/runs/:id`** — `P/payroll/run.tsx`:
- Figures: Gross, Deductions, Net, Cost.
- "Check before paying" warnings.
- Line dialog: overtime, unpaid days, additions and deductions, loans, payslip.
- PIFSS card; "In the books".
- **Actions:**
  - Update from records.
  - Approve, or ask for / give / reject the Super Admin's approval.
  - Reopen, Record payment, Undo payment, Delete draft.
  - Payslips; Register by department.
  - Salary file.
  - Opening leave balances.

**`/payroll/leave`:** reasons, opening balances, Record leave (employee, type, days, notes);
balances.

**`/payroll/leave-reasons`:** name EN / AR, how it's paid, most days a year, categories, note
required; recommended set.

**`/payroll/loans`:** still to recover, active; new loan (employee, amount, instalment, date,
first month, paid from, notes).

**`/payroll/settings`:** pay day, salaries account, working days, overtime basis, minimum wage,
PAM file; leave policy; PIFSS rates; provisions; accounts.

### Letters and costing
**`/people/letters`:**
- An on/off switch (owner and admin).
- Templates, New letter.
- Chips: To print / Drafts / Issued / Void / Waiting.
- Letter dialog:
  - Employee, template, language, addressed to, purpose, wording.
  - Draft / Issue / Send for approval / Void / Print / Attach signed copy.
  - Approvers: Approve and issue / Reject.

**Letter templates:** name EN / AR, kind, language, subject and text per language, signer,
signature, stamp, automatic drafts, private details; a live preview.

**`/people/costing`:**
- Switch, overhead %, margin %.
- Rate card, with "Fill from salaries".
- Costings.
- The editor:
  - Posts: title, nationality, headcount, hours, days, salary parts, overtime.
  - It works out PIFSS, indemnity, leave, cost and sell price.
  - Make quote, Delete.

## Compliance and CRM

**`/compliance`:**
- Tabs: Calendar / Documents / Vehicles.
- Settings: reminder days, audited statements, PIFSS day, Kuwaiti target, purposes.
- Figures: Overdue, Due in 30 days, Not done yet, Tracked.
- Deadlines by month: Mark as done / Undo / Renew.

**`/compliance/documents`:**
- Chips: All / Expiring / Expired / Valid / Archived / Drivers without a licence / No file /
  New copy missing.
- Document dialog:
  - Belongs to: an employee, vehicle, customer or the company.
  - Type, title, purpose, number, class, issuer, dates, cost, reminders, notes, confidential,
    files.
- Renew dialog: new expiry and number, the fee as an expense, a new copy.

**`/compliance/vehicles`:** one card per vehicle with its papers. Vehicle dialog: plate, make,
model, year, chassis, driver, asset, notes.

**`/crm`:**
- Open quotes, Won, Win rate, To follow up.
- Stage columns Draft / Waiting / Won / Lost, with count and value.

**`/crm/prospects`:** All / Quoted / Quoted before / Not contacted.

## Files, approvals and updates

**`/files`:**
- Switched on in Compliance.
- Search, "Kept with"; files open (downloaded when opened).
- Employees' and confidential files are hidden from roles that can't see People.

**`/approvals`** (cloud companies):
- Tabs: Waiting / Asked by me / Decided.
- Each card shows "Now" vs "Asked for". Approve / Reject (with a note) / Take back.

**`/notifications`** (Updates, for the owner and approvers):
- All / Unread / Important, by kind; Mark all as read.
- Today / Yesterday.

## Settings — `S/settings/*`

On a phone the sections scroll sideways. Each section has Unsaved changes → Discard / Save.

**Business:**
- **company:** names, legal form, activity, registrations, contact, address, payment details,
  logo, colour, stamp, signature, regional settings.
- **companies.**
- **links.**
- **compliance switches.**

**Account and team:**
- **account:** name, language, password, sign out.
- **alerts.**
- **team:**
  - Members: role, Permissions dialog (per app; Can approve), Remove.
  - Invitations: email and role → share the link.
  - Owner switches; Transfer ownership; Leave or delete the company.
- **approvals** (owner).
- **ai.**
- **cloud:** sync status, unsent changes (Try again / Undo / Send for approval).

**Documents:**
- **documents** (invoice defaults).
- **numbering:** pattern, digits, next number, restart; number invoices when issued.
- **items.**
- **emails.**
- **labels** (wording).

**Money:**
- **payments.**
- **taxes:** rates, kinds, per line or on the total, prices include tax.
- **accounting:** year end, lock date, levies, VAT setup, chart.

**Data:**
- **import wizard.**
- **backup, restore, delete.**

**This device:**
- **appearance:** match my device, light and dark themes.

**Other pages:**
- **`/templates`:** invoice, quote and credit-note designs; options.
- **`/setup`:** a new company (name\*, Kuwait preset, tax, details, keep in the cloud).
- **Account screens:** sign in, sign up, forgot and reset password, the callback, invites,
  cloud companies.

## Maham Tasks — `T/app/(app)/`

**Roles:** admin, manager, member.
- Only admins and managers edit task details, mark Done or reopen, set labels and milestones,
  open Reports and Settings, create projects and general tasks, and delete.
- Members create tasks in projects, change status up to In Review, comment and attach files.

**Shell:**
- Sidebar: Dashboard, Today, Calendar, My List, General tasks, Team, Team chat, Messages,
  Reports and Settings (admins and managers), Projects, Maham AI.
- **Phone tab bar: Today / Tasks / Home / My List / More.**
- Always there: bell, search, AI panel, offline outbox.

**Pages:**
- **dashboard:**
  - "Welcome back"; a getting-started guide.
  - Projects needing attention.
  - Six tiles: To Do, Pending, In Review, Completed, Due Today, Overdue.
  - Overall progress; Assigned to you; Needs attention; Workload.
- **today:** Overdue, Due today, In Progress, Waiting on review, Follow up now; who is busy;
  completed today.
- **my-list:** private notes with to-dos, pin, share, delete.
- **tasks?filter=:**
  - Chips: todo, pending, in_progress, in_review, done, due_today, overdue, all.
  - Filters and sort; CSV; bulk Move / Delete with Undo.
  - **Phone swipe cards:** towards the end moves the task on; towards the start puts it off to
    the next working day.
- **general:** Board / List / Follow-ups.
- **projects/[id]:**
  - Members, New task, Edit / Archive / Delete.
  - Status updates (On track / At risk / Off track).
  - Progress.
  - Board with drag and drop; List; Timeline with milestones.
- **calendar:** month grid with holidays.
- **chat:** one team room, typing indicator, online members.
- **messages:** private threads with unread counts.
- **reports:** Finished, Added, On time, Overdue; week by week; by person; projects.
- **team:** members, profile, message, email.
  - Admins also: position, role, remove two-step sign-in, add a teammate, invitations.
- **profile:**
  - Picture, name, password, two-step sign-in.
  - Reminders: email, Telegram, WhatsApp, push; assigned, due soon, overdue, follow-up,
    morning summary.
- **settings:** company holidays, labels, task templates.
- **Task dialog:**
  - Template; Title\* (200); Description.
  - Status (Done disabled for members).
  - Priority; Due, with quick chips.
  - Repeats (every N, 1–365).
  - Assignees; Labels and Milestone (managers).
  - Steps; Save as template; Waiting on; Follow-up.
  - Comments (mentions, reactions), Files (upload, photo, link), Activity.
- **Auth:** login, two-step verify, forgot, reset, register, set password.
