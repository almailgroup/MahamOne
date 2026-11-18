# Maham One: release notes for warehouses and items issued

This release adds sub-warehouses to Maham Books (and Maham Inventory, when it is its own app). There is one main warehouse, and under it a sub-warehouse for each employee who looks after stock. Stock goes from the main warehouse to a sub-warehouse. The employee who looks after it issues uniforms and other items from it to the security guards. The owner (the Super Admin) or an approver confirms each issue. Only then does the stock leave the sub-warehouse.

**Nothing changes until you add a sub-warehouse.** Warehouses, stock, invoices and bills work as before. No record changes and nobody's access changes.

"The script" means the database script `supabase/migrations/20261210000000_warehouse_issues.sql`. It comes after the AI assistant script, `20261208000000_ai_assistant.sql`. Only cloud companies need it. Until it runs, a cloud company keeps its warehouses as they are and doesn't offer sub-warehouses. A company kept on one device has them at once.

**Nothing moves.** Every page keeps its address. Bookmarks and links in emails work as before.

**Private.** A keeper who is staff sees the names, numbers and job titles of the current employees, so they can choose who receives items. They see nothing else of Maham People: no salaries, payroll, leave or documents. The cloud sends them only those fields, and stops once they no longer look after a sub-warehouse or are made a viewer. Like every other record of Maham Books, the list of items issued (who received what, with their employee number and job title) is open to everyone in the company who opens Maham Books, staff and viewers included.

---

## What you do, once

1. Run the script in the Supabase SQL editor (a new query, paste the whole file, **Run**). Then run `supabase/health-check.sql`. Its last row should say "All good". Step 14 of [`supabase-setup.md`](supabase-setup.md) has the details.
   - Before items are issued, have everyone open the app once so their device has this version (a device updates itself when the app is opened). A device still on an older version doesn't know items issued. The cloud keeps their stock as it is either way, but that device shows its stock without them until it updates.
2. Invite each employee who looks after a sub-warehouse to the team as **Staff** (Settings → Team, الإعدادات ← الفريق).
3. Set up the sub-warehouses: **Inventory → Warehouses → New sub-warehouse** (المخزون ← المستودعات ← مستودع فرعي جديد). See below.
4. To get the notifications under the bell and by email, turn on **Settings → Email alerts → Changes by your team** (الإعدادات ← تنبيهات البريد ← تغييرات الفريق). Requests to issue items always show under **Approvals (الاعتمادات)**, whether this is on or off.

---

## Main warehouse and sub-warehouses

- **Inventory → Warehouses** (المخزون ← المستودعات) shows the main warehouse (المستودع الرئيسي) with its sub-warehouses (مستودع فرعي) under it. Each sub-warehouse shows who looks after it and how much it holds.
- **New sub-warehouse** (مستودع فرعي جديد), or **Add a sub-warehouse** (إضافة مستودع فرعي) in a main warehouse's menu:
  - **Belongs to**: the main warehouse it gets its stock from.
  - **Looked after by** (المسؤول عنه): the employee responsible for it. The sub-warehouse takes their name, for example "Ahmed Saleh". You can change it.
  - **Issues items from it** (يصرف المواد منه): their Maham One account. Only that account issues items from it. With nobody chosen, only the owner, admins and accountants issue from it.
- A sub-warehouse is never the default warehouse, and a sub-warehouse has no sub-warehouses of its own. A main warehouse is archived only once its sub-warehouses are.
- Only the owner, an admin or an accountant sets up sub-warehouses and changes their stock directly: opening stock, adjustments and transfers. Invoices and bills move their stock only when one of them makes the line, and only they delete such an invoice or bill. The database itself refuses anyone else.

## Sending stock to a sub-warehouse

- **Send stock** (إرسال مخزون) on a sub-warehouse opens **Transfer stock** (تحويل المخزون), from its main warehouse to it. Choose the items and quantities and press **Post transfer** (ترحيل التحويل).
- The main warehouse goes down and the sub-warehouse goes up, by the same quantities, at the same cost. Inventory → **History** keeps every transfer.

## Issuing items to an employee

- The employee who looks after a sub-warehouse signs in. Under **Inventory** they see **You look after …** (أنت مسؤول عن …), with **Issue items** (صرف مواد).
- **Issue items**: choose the employee who receives them (**Issued to**), then each item and its quantity: uniforms, trousers, T-shirts, shoes, shoulder badges, jackets… Each line shows how many are left in the sub-warehouse. Add a note if you want, such as "New joiner". Press **Send for approval** (إرسال للاعتماد).
- Nothing leaves the sub-warehouse yet. The quantities waiting are held back, so the keeper can't issue them twice.
- The keeper can take the request back while it waits (**Take back**).
- The request names the keeper as the sub-warehouse has them: "Ahmed Saleh (Warehouse supervisor)". The cloud sets that name itself, so nobody can send a request in someone else's name.
- The owner, an admin or an accountant can also issue items from any warehouse. When they are an approver, the items are issued at once.

## The owner's notification and confirmation

- The owner (or an approver) gets the request under **Approvals** (الاعتمادات). With **Changes by your team** on, it is also under the bell, and in the email of team changes, for example:
  > Ahmed Saleh (Warehouse supervisor) issued to Mohammed Ahmed (Security guard): 1 Trouser, 1 T-shirt, 1 Jacket
- The request shows the sub-warehouse, the date, the employee number and who asked. It warns when the sub-warehouse no longer holds enough.
- **Confirm** (تأكيد): the issue is recorded, numbered ISS-0001, ISS-0002 and so on, and the quantities leave that sub-warehouse. Its cost leaves inventory and goes to **6240 Items issued to employees** (مواد مصروفة للموظفين), an expense, at the average cost.
- **Reject** (رفض): nothing leaves the sub-warehouse. The keeper sees the note you write.
- Each line is recorded as the item is named in the items list. A request with a quantity that isn't positive, or with something that isn't a stock item, can't be confirmed: the request says why, and you reject it.
- Until it is recorded (on your device, once it has synced), a confirmed request still holds its quantities back, so they can't be issued twice.

## What is on record

- **Inventory → Issued items** (المخزون ← المواد المصروفة) lists every issue and every request: the date and number, who received what, from which warehouse, and whether it is waiting, issued, rejected or void. Each one shows who issued it, who confirmed it and when.
- Each employee's page has an **Issued items** tab. It shows what they hold, item by item, and every issue to them.
- **Reports → Issued items** (التقارير ← المواد المصروفة) lists the items issued line by line, by employee, item and date, with a CSV download.
- Items issued are never deleted. An issue made by mistake is **voided** by the owner or an approver. It stays on record as void, its stock comes back to the warehouse and its cost leaves the books.
- **Inventory → Stock**, filtered by warehouse, shows what each sub-warehouse holds.

## The script and the health check

- After this script, the Phase 0-2 script (`20261102000000_tables_v16.sql`) and the Phase 5 script (`20261207000000_staffing_costings.sql`) can't run again once items have been issued. They would stop with an error about `records_tbl_check` and change nothing. The health check never asks for them then.
- If any earlier script from the third on is run again, run this one again after it. The health check names it.
- Turning **pg_cron** on later: run this script again to schedule the daily clean-up.
