# Setting up the cloud (Supabase)

This guide turns on accounts, teams and sync for Maham Books. It is written
for the owner of the Supabase project; no programming is needed. It takes about
15 minutes.

Project: `https://gagdyhintrxdkiqhahzh.supabase.co`. The app already contains
the project's **publishable key**, which is meant to be public. Nothing else
has to be added to the app or to Vercel.

> **Never share the secret key.** In **Project Settings → API Keys** there is
> also a _secret_ key (`sb_secret_…`). It bypasses every protection. Don't
> paste it into the app, into Vercel, into GitHub, into an email or a chat. If
> it was ever shared, create a new one there and delete the old one. The app
> refuses to work with a secret key.

## 1. Create the database (once)

1. Open the project at <https://supabase.com/dashboard> and choose
   **SQL Editor** in the left menu.
2. Click **New query** (the **+** button).
3. Open the file
   [`supabase/migrations/20261004000000_almailbooks_cloud.sql`](../supabase/migrations/20261004000000_almailbooks_cloud.sql),
   select everything and copy it. Paste it into the editor.
4. Click **Run** (or press Ctrl+Enter / ⌘+Enter). If Supabase warns that the
   query has "destructive operations", choose **Run this query**: the script
   only replaces its own rules and never deletes data.
5. It should finish with "Success. No rows returned".
6. Do the same with
   [`supabase/migrations/20261006000000_sync_fixes.sql`](../supabase/migrations/20261006000000_sync_fixes.sql)
   (a new query, paste, **Run**). It must come after the first file.
7. For email alerts, the third script,
   [`supabase/migrations/20261007000000_email_alerts.sql`](../supabase/migrations/20261007000000_email_alerts.sql),
   comes next. It is part of [`docs/email-alerts.md`](email-alerts.md).
8. Then the fourth script,
   [`supabase/migrations/20261102000000_tables_v16.sql`](../supabase/migrations/20261102000000_tables_v16.sql)
   (a new query, paste, **Run**), after the others. It makes room for cheque
   layouts, vehicles, approval requests and HR letters, and keeps letters and
   confidential documents from staff and viewers. Until it runs, the app keeps
   the features that need it hidden; everything else works as before.
9. Then the fifth script,
   [`supabase/migrations/20261116000000_super_admin_approvals.sql`](../supabase/migrations/20261116000000_super_admin_approvals.sql)
   (a new query, paste, **Run**), after the fourth. It adds the Super Admin's
   controls in **Settings → Team** and the approval rules in **Settings →
   Approvals**, cheque confirmation included (see "The Super Admin",
   "Approvals" and "Cheque confirmation" below). Running it changes nothing by
   itself: every member keeps their role's access, admins keep inviting and
   changing roles until the owner switches that off, and nothing waits for
   approval or confirmation until the owner turns it on. It stops with "Run
   20261102000000_tables_v16.sql first" if the fourth script hasn't run, and
   then changes nothing: run step 8 first. If you ran an earlier copy of this
   script, run it again: it is safe, and the cheque switches appear only once
   it has run.
10. Then the sixth script,
    [`supabase/migrations/20261123000000_change_feed.sql`](../supabase/migrations/20261123000000_change_feed.sql)
    (a new query, paste, **Run**), after the fifth. It adds **Changes by your
    team** in **Settings → Email alerts** and the bell (see "Changes by your
    team" below). It stops with "Run 20261116000000_super_admin_approvals.sql
    first" if the fifth script hasn't run, and then changes nothing. Running it
    changes nothing by itself either: nothing is recorded until the owner (or
    a member allowed to approve) turns it on. The emails also need the email
    alerts script (step 7) and the email-alerts function
    ([`docs/email-alerts.md`](email-alerts.md)). If the fifth script is ever
    run again, run this one again after it.
11. Then the seventh script,
    [`supabase/migrations/20261130000000_people_alerts.sql`](../supabase/migrations/20261130000000_people_alerts.sql)
    (a new query, paste, **Run**), after the sixth. It adds salary approval by
    the Super Admin, **Settings → Approvals → Pay runs** (see "Salary
    approval" below), and its emails. It stops with "Run
    20261123000000_change_feed.sql first" if the sixth script hasn't run, and
    then changes nothing. Running it changes nothing by itself either: pay
    runs are approved as before until the owner turns the switch on. It also
    lets accountants get the morning email alerts and everyone choose the
    kinds of paper they are told about (**Settings → Email alerts**), and
    lets the expiry reminders show under the bell (see "Expiry alerts"
    below), and adds employee letters (see "Employee letters" below); until
    someone uses them, everything is as before. If the fifth or
    sixth script, or the email alerts script (step 7), is ever run again, run
    this one again after them.
12. Then the eighth script,
    [`supabase/migrations/20261207000000_staffing_costings.sql`](../supabase/migrations/20261207000000_staffing_costings.sql)
    (a new query, paste, **Run**), after the seventh. It lets the cloud keep
    manpower costings of Maham People (see "Manpower costing" below), private
    like payroll. It stops with "Run 20261130000000_people_alerts.sql first,
    then this file." if the seventh script hasn't run, and then changes
    nothing. Running it changes nothing by itself either: the costing stays
    off until someone turns it on. If the fourth, fifth, sixth or seventh
    script is ever run again, run this one again after them. Once there are
    costings, the first and fourth scripts stop with an error about
    `records_tbl_check` and change nothing.
13. Then the ninth script,
    [`supabase/migrations/20261208000000_ai_assistant.sql`](../supabase/migrations/20261208000000_ai_assistant.sql)
    (a new query, paste, **Run**), after the eighth. It makes the database
    itself keep the AI assistant's switch (**Settings → AI assistant**) for
    the owner and the admins: anyone else's change to it is ignored. Until it
    runs, the app keeps it for them on each device, so the app works the
    same before and after. It stops with "Run
    20261207000000_staffing_costings.sql first, then this file." if the
    eighth script hasn't run, and then changes nothing. Running it changes
    nothing else. If any script from the third to the eighth is ever run
    again, run this one again after them.
14. Then the tenth script,
    [`supabase/migrations/20261210000000_warehouse_issues.sql`](../supabase/migrations/20261210000000_warehouse_issues.sql)
    (a new query, paste, **Run**), after the ninth. It lets the cloud keep
    sub-warehouses, who looks after each, and items issued to employees
    (uniforms, shoes, badges), confirmed by the owner or an approver (see
    "Warehouses and items issued" below). It stops with "Run
    20261208000000_ai_assistant.sql first, then this file." if the ninth
    script hasn't run, and then changes nothing. Running it changes nothing
    by itself either: warehouses stay as they are until you add a
    sub-warehouse. If any script from the third to the ninth is ever run
    again, run this one again after them. Once items have been issued, the
    fourth and eighth scripts stop with an error about `records_tbl_check`
    and change nothing.

Each script is run once. A new version of the app that needs more from the
database comes with a new script: run just that one, after the others. The
later scripts are safe to run again (they create what is missing and replace
their own rules with the same ones), but **don't run the first script again**:
once the app keeps cheque layouts, vehicles, approval requests or HR letters,
it stops with an error about `records_tbl_check` and changes nothing. The
fourth script stops the same way once there are manpower costings or items
issued, and the eighth once there are items issued. If the
first was run again and finished without an error, or any script was run
again after a later one, run the health check: it names the scripts to run
again, in order.

**Optional, recommended: the daily clean-up.** Deleted records leave a small
marker (no data) for 30 days. They are also cleaned up as the app syncs, but a
daily job does it for every company. The email alerts script (step 7) turns it
on; without email alerts, open **Database → Extensions**, search for
**pg_cron**, enable it, then run the tenth script (step 14) once more.
The fourth and eighth scripts schedule it too, but once there are manpower
costings or items issued they can't run again.

To check, run the health check (see "Health check" below): it says, step by
step, whether each script has run, each as its latest version, and whether
everything works, and which scripts to run, in which order, if not.

Don't add policies of your own to these tables or to Storage (for example a
template like "Give users access to all buckets"): policies add up, so a
broad one would open what the script keeps closed.

## 2. Sign-in settings

1. **Authentication → URL Configuration**
   - **Site URL**: `https://mahamone.com`
   - **Redirect URLs** → **Add URL** for each:
     - `https://mahamone.com/**`
     - `https://www.mahamone.com/**`
     - `http://localhost:5173/**` (for testing on a computer)
   - Save.
2. **Authentication → Sign In / Providers → Email**
   - **Enable email provider**: on.
   - **Confirm email**: **on**. This is essential: it is what stops someone
     from signing up with another person's address and taking their
     invitation.
   - **Secure email change**: on (the default).
   - Save.
3. **Authentication → Policies** (or **Password security**, depending on the
   dashboard version): set the minimum password length to **8**. The app asks
   for 8 as well.

The emails Supabase sends (confirmation, password reset) contain a link back
to the app; no change to the email templates is needed.

## 3. Try it

Supabase's built-in email service only sends to the people who are members of
your Supabase organisation, and only about **2 emails per hour**. Until you set
up your own email service (step 4), test with the email address of your
Supabase account.

1. Open <https://mahamone.com> (with this version deployed).
2. Click **Create an account**, enter your name, the email address of your
   Supabase account and a password of at least 8 characters.
3. The app says **Check your email**. Open the email from Supabase on the
   **same device and browser** and click the link. The app opens, signed in,
   on **Your companies**.
4. Choose **Keep in the cloud** next to your company (or set one up). The
   status goes from **Uploading…** to **Synced**. In Supabase, **Table
   Editor → records** now has its records.
5. On another computer or browser, open the app and choose **Sign in**. Under
   **In your account**, choose **Download to this device**.
6. Change something on one device: the other one shows it within seconds
   (or after its next sync, at most a minute).
7. **Team**: in **Settings → Team**, invite someone (an address that can
   receive Supabase's emails, see above), copy the link or send it by
   WhatsApp, open it in another browser, create the account with that address,
   confirm it and accept. Try the **Staff** role: Payroll and People are not
   there for them.

If something doesn't work, see "Problems" below.

## 4. Your own email service (before real customers)

The built-in service is only for testing. To send to anyone, connect an email
service in **Authentication → Emails → SMTP Settings** (turn on **Enable
custom SMTP**):

- **Resend** (simple, and the one email alerts use): steps 1 and 2 of
  [`docs/email-alerts.md`](email-alerts.md) set up the domain, the API key and
  these settings: host `smtp.resend.com`, port `465`, username `resend`,
  password = the API key, sender email for example `no-reply@almailgroup.com`,
  sender name `Maham Books`.
- **Google Workspace**: create an app password for a mailbox (or use the SMTP
  relay in the Workspace admin console). Host `smtp.gmail.com`, port `465`,
  username = the mailbox address, password = the app password. Google limits
  how many emails a mailbox may send each day.

Then raise the email limit in **Authentication → Rate Limits**, and send
yourself a test (create an account with another address).

## 5. Before real customers: Pro plan

On the free plan a project is paused after a week without use, and there are
no daily backups. Upgrade the organisation to **Pro** (**Organization →
Billing**) before customers rely on it: Pro keeps daily backups for 7 days and
doesn't pause.

## How deletes work

- **Deletes are immediate.** Deleting something in the app (an invoice, a
  client, a receipt, an employee) deletes it in the cloud at the next sync,
  for everyone.
- Other devices learn about it from a small **marker** that says only which
  record was deleted and when, with no names or amounts. Markers are kept for
  **30 days at most**; a device that was away longer simply downloads the
  company again.
- **Files are removed too**: the receipt or scan is deleted from Storage with
  its record. Owners can also use **Clean up files** in **Settings → Cloud
  and sync** to remove files nothing uses any more.
- **Deleting a company** (owner only, in **Settings → Team**) deletes its
  files, then the company with all its records, members and invitations, at
  once.
- **Deleting an employee** removes them with their documents, renewals, files
  and activity; only their employee number stays in the activity log.
  Employees with payroll history are marked as left instead, because the
  accounts depend on it.
- **Backups**: on the Pro plan, Supabase's daily backups keep deleted data for
  up to **7 days**; after that it is gone for good. Ask each member to keep a
  backup file (**Settings → Backup & data**) if they need a longer history.

## Who can do what

| Role       | Can                                                                             |
| ---------- | ------------------------------------------------------------------------------- |
| Owner      | Everything, including the team and deleting the company.                        |
| Admin      | Everything except deleting the company or changing the owner.                   |
| Accountant | All books and payroll. Not the team.                                            |
| Staff      | Sales, purchases, cheques, stock and receipts. No payroll, no accounting setup. |
| Viewer     | Look at everything except payroll; change nothing.                              |

The database itself enforces this (row-level security), not just the app.
Details and the security checklist: [`supabase/README.md`](../supabase/README.md).

## The Super Admin

The Super Admin of a company is its **owner**. The app names nobody: to make
someone the Super Admin, the current owner opens **Settings → Team → Transfer
ownership** (الإعدادات ← الفريق ← نقل الملكية) and chooses them; the previous
owner becomes an admin. Do this once in every company, after the fifth script
(step 1.9) has run. **Settings → Companies → Companies you own** then lists
every company the account owns.

In **Settings → Team**, the owner (badge **Owner (Super Admin)**, المالك
(المشرف العام)) has:

- **Only the owner makes admins and accountants** (المالك وحده يعيّن المديرين
  والمحاسبين). Off until the owner turns it on. On, only the owner invites,
  makes, changes or removes admins and accountants; admins still invite and
  remove staff and viewers. Turning it on cancels invitations as admin or
  accountant that someone else made. Tell the admins before turning it on.
- **Permissions** (الصلاحيات) next to each member: make an app view only or
  turn it off for them (Maham Books can only be made view only, because the
  other apps use its customers and items). Limits only take away from the
  role, and the cloud refuses what the member saves in that app, the files
  of its records included (a scan in an employee's personnel file is
  People's). Settings and activity follow the role, except the books'
  settings (the lock date, numbering, payment details with the bank account
  and WAMD number, email templates and document defaults), which follow the
  limit on Maham Books. What is already on their device stays there.
- **Can approve** (صلاحية الاعتماد), in the same dialog: up to two admins or
  accountants may approve requests besides the owner. Off for everyone at
  first.

If the owner's account is ever deleted, the longest-standing admin (or else
accountant) becomes the owner, as before; the change is recorded, and shows
under **Changes by your team** once the sixth script has run.

## Approvals

**Settings → Approvals** (الإعدادات ← الاعتمادات) holds the owner's rules. Only
the owner changes them; everyone else sees them. Nothing waits for approval
until the owner turns something on:

- **Issued invoices need an approver to change** (تعديل الفواتير الصادرة يحتاج
  إلى معتمِد) and the same for **credit notes**. With it on, a change to an
  issued invoice (its customer, dates, lines, prices, wording, its number),
  voiding it or bringing it back from void is made only by an approver: the
  owner, or an admin or accountant with **Can approve** (Settings → Team).
  Everyone else gets **Send for approval** (إرسال للاعتماد) instead of Save,
  and **Request void** instead of Void (or Delete), with a reason. Payments,
  credit notes applied to it and retention releases go on as before. A
  payment link can still be added to one that has none; once it has one,
  only an approver changes or removes it (it is where the customer pays). A
  device that hasn't received the link yet keeps it when it sends the
  invoice, with a payment for example.
  Drafts and new invoices are anyone's.
- **Void instead of delete** (الإبطال بدلاً من الحذف), on by default: issued
  invoices and credit notes are voided, never deleted, so their numbers stay
  used. With it off only approvers may delete them. They are under **Invoices → Void** (الفواتير الملغاة). Drafts can
  still be deleted. A voided invoice that was paid leaves the money on the
  payment as the customer's unapplied credit.
- **Cancel requests still waiting after (days)**: 14 by default; 0 keeps them
  waiting.

Requests are in **Approvals** (الاعتمادات) in the Books sidebar (طلبات
الاعتماد), and a count is on the home page for approvers. An approver opens a
request, sees what would change and approves or rejects it; approving makes
the change on their device once the cloud has the decision (offline, when the
device is back online), and it syncs to everyone. A request taken back or
decided on another device meanwhile stays as the cloud has it. Whoever asked
can take a request back while it waits. The cloud stamps who asked, who
decided and when, and a decision once made can't be undone by an older copy.
An approval that can't be carried out (the period was locked meanwhile, say)
stays approved, to be carried out again or rejected. Carrying it out again
asks the cloud first, so a device that is offline, or whose copy is behind
(another approver rejected it meanwhile), carries nothing out.

**Void and reissue** (إبطال وإعادة إصدار), on any issued invoice or credit
note once approvals or the numbering below are on, voids it and opens a new
draft in its place, which prints "Replaces INV-…" and gets a new number when
issued. Money paid on the void one becomes the customer's unapplied credit,
to apply to the new one. Numbers are never reused. To avoid using up numbers
on drafts, **Settings → Numbering → Number invoices and credit notes when they
are issued** gives drafts their number only when they are sent; the cloud then
refuses an invoice issued without its number (an older version issuing such a
draft), which waits in **Settings → Cloud and sync**. In a company kept in the
cloud the switch appears only once the fifth script (step 1.9) has run, since
until then nothing in the cloud refuses such an invoice; switched on before the
company moved to the cloud, it can still be turned off there, and should be
until the script has run.

Before turning approvals or that numbering on, update every device and let
each one sync. A change an older version makes to an issued invoice is refused
by the cloud and waits in **Settings → Cloud and sync**, with **Send for
approval instead**; what it changed with it (the payments a delete freed, say)
waits with it on a device with this version. On a device still on an older
version, undo such a change there (**Undo my change**): its payments were
already sent.
Companies kept on one device only have nobody to ask: the rules apply to cloud
companies.

## Cheque confirmation

**Settings → Approvals → Cheques** (الإعدادات ← الاعتمادات ← الشيكات), the
owner's switch **Cheques need confirmation** (الشيكات تحتاج إلى تأكيد). Turned
on, it covers what is recommended: **Cheques issued** (الشيكات الصادرة) and
**Security cheques given** (شيكات الضمان المسلَّمة) on, **Cheques received**
(الشيكات المستلمة) off. Each can be changed on its own.

- A cheque of a covered kind recorded by anyone but an approver is not a
  payment: the button says **Send for confirmation** (إرسال للتأكيد), and the
  cheque waits as a request. It is not in the books, not on the bill or
  invoice (which shows "waiting for confirmation" so nobody records it twice),
  not in the cheque register's totals or the morning alerts, and it can't be
  printed.
- The approver (the owner, or an admin or accountant with **Can approve**)
  finds it in **Approvals** and in **Cheques → Waiting for confirmation**
  (بانتظار التأكيد), and presses **Confirm** (تأكيد) or **Reject**. Confirming
  records the payment on the approver's device as it was asked, dated the day
  the cheque was written or received, numbered and posted then. Whoever asked
  can take a request back while it waits.
- Changing a confirmed cheque's amount, payee, number, bank or dates, deleting
  it, replacing it and cashing a security cheque given out wait the same way.
  Depositing, clearing, returning, cancelling, printing, notes and the
  documents it pays go on as before. A printed cheque moved to its next leaf
  (the spoiled leaf on record) needs nothing more.
- While cashing a security cheque waits, that security cheque can't be
  changed or deleted. Changed anyway (on an older version), the request
  can't be confirmed, since the payment would not be what was asked: it says
  so, and is rejected and asked again.
- If a bill was paid meanwhile, or the period was locked, confirming says why
  and the request stays confirmed but not recorded: carry it out again, or
  reject it.

Received cheques are off by default: while one waits, its invoice stays unpaid
and the customer may still get a reminder. Before turning cheque confirmation
on, update every device and let each one sync: a cheque an older version
records is refused by the cloud and waits in **Settings → Cloud and sync**,
with **Send for confirmation instead**. On a device still on an older version,
undo it there instead (**Undo my change**): until then that device counts the
cheque on its bill, and devices with this version leave the bill as the cloud
has it after a few tries. The paper cheque should not leave the office before
it is confirmed: the app can't see paper.

## Changes by your team

**Settings → Email alerts → Changes by your team** (الإعدادات ← تنبيهات البريد
← تغييرات الفريق), after the sixth script (step 1.10). It is there for the
owner (the Super Admin) and the admins or accountants with **Can approve**
(Settings → Team); nobody else sees it. Each of them turns their own on:

- **Tell me about changes by my team** (أبلغني بتغييرات فريقي). Off at first.
  Until someone of the company turns it on, the cloud records nothing.
- **Email at once** (بالبريد فوراً): important changes, within about 5
  minutes: an issued invoice or credit note changed, voided, restored or
  deleted; cheques recorded, changed, returned, cancelled or deleted, and
  security cheques; approval requests and each decision; someone joining or
  leaving, a role or permissions changing; the numbering, the lock date or
  the approval rules changing; pay runs added, approved, paid or deleted.
  Each kind can be turned off.
- **Everything else in a morning summary** (كل ما عدا ذلك في ملخص صباحي), at
  8:00 Kuwait time, on days the team changed something. Off, only the
  changes above are emailed.
- At most **one email every 15 minutes and 20 a day** per person and
  company; what comes meanwhile goes in the next email. The emails share
  Resend's daily allowance (100 a day on the free plan) with the morning
  alerts: with three recipients that is up to 60, so a paid plan is
  advisable once the team is busy.

The **bell** (المستجدات, Updates) at the top, next to the app grid, counts
the unread changes and lists the latest; **See all updates** opens the
Updates page (by day, filters, **Mark all as read**, a link to each record).
A change shows there as soon as the device that made it has synced. Nobody
sees their own changes. Changes to payroll and people data say only what
happened ("Approved the pay run for 2026-10"), never a name, a Civil ID or
an amount, and only owners, admins and accountants ever see them. Changes
are kept 180 days.

Each entry of a record's activity now also says who made it ("· by …"), in
companies kept in the cloud; entries from before, and from older versions of
the app, name nobody.

## Salary approval

**Settings → Approvals → Pay runs** (الإعدادات ← الاعتمادات ← مسيرات الرواتب),
after the seventh script (step 1.11). Only the owner (the Super Admin) turns
on **Pay runs need the Super Admin's approval** (مسيرات الرواتب تحتاج إلى
موافقة المشرف العام); it is off at first, and until then pay runs are
approved as before.

- With it on, whoever prepares a pay run (an admin or accountant) clicks
  **Ask for approval** (إرسال للموافقة) on the draft, with a note if needed.
  **Approve** (اعتماد), which posts the pay run to the books, stays greyed
  out until the owner, or an admin or accountant with **Can approve** who
  didn't send it, clicks **Give approval** (موافقة) in **Approvals** (in the
  People sidebar, and on the home page). The owner may approve a pay run
  they sent themselves, and may approve (post) any pay run at once.
- Any change to the pay run after it was sent (a line, the pay date, Update
  from records that changes something) asks for a new approval. The pay run
  says so. Only a pay run that could be approved (posted) as it is can be
  sent: one with net pay below zero, a loan recovered beyond what is left, a
  final settlement for the month, leave by reason not worked out or a pay
  date in the locked period is put right first.
- A member the owner gave no access to People (Settings → Team) doesn't see
  pay run or letter requests in Approvals, gets no email of them, and the
  cloud doesn't let them decide a pay run.
- The owner and the members allowed to approve get an email: the totals by
  department and position, the change since last month, and a link that
  opens the pay run in the signed-in app. Groups of one person are merged
  into "Other positions" or "Other departments", and a pay run of one person
  has no amounts at all. Nobody's own pay, name, Civil ID or IBAN is ever in
  it, nor the note: each employee's pay is in the app only. Opening the link
  decides nothing.
- The links use the function secret `MAHAM_APP_URL` (where the app is, for
  example `https://mahamone.com/`), or else the address each person saved
  with their email alerts or their changes by the team. Add it in Supabase:
  **Edge Functions → Secrets → Add new secret**, name `MAHAM_APP_URL`. Without
  it, someone who saved neither gets the email without a link.
- The emails go out through the email-alerts function, as soon as a pay run
  is sent (with pg_net), and the change feed's 5-minute schedule tries again
  for three days. They need the email alerts set up
  ([`docs/email-alerts.md`](email-alerts.md)) and count towards Resend's
  daily allowance.
- **Update every device first.** An older version of the app doesn't know
  the switch and can still approve a pay run without approval; Updates
  (المستجدات) report every pay run approved.
- **Ask the auditor to confirm** that the approved pay run and its register
  by department and position (the pay run → **Register by department**,
  الكشف حسب القسم) are kept with the month's records. Nothing in the pay is
  worked out differently.

## Expiry alerts

**Compliance → Settings → Expiry reminders** (الامتثال ← الإعدادات ← تذكيرات
الانتهاء), for the owner, admins and accountants. Each switch is off at first,
and until it is on the reminders work as before:

- **Reminders by document type** (التذكير حسب نوع المستند): it offers the
  lead times the owner chose, residency 90, 60, 30 and 7 days before,
  passport 180, 90 and 30, vehicles' papers 30, 14 and 7. They can be
  changed, and types added or removed.
- **Remind again after expiry** (التذكير مجدداً بعد الانتهاء): an expired
  paper is in the morning email again every 7 days until it is renewed.
- **Ask for the new copy after a renewal** (طلب النسخة الجديدة بعد التجديد): a
  paper renewed with **Renew** from that day on is marked **New copy missing**
  (لم تُرفع النسخة الجديدة) after 14 days unless its new scan was added, with
  Renew's **New copy** or the tag button of the personnel file (**This file
  is the…**, هذا الملف هو…).
- **Show the reminders in Updates** (إظهار التذكيرات في المستجدات), after the
  seventh script (step 1.11): the owner and the approvers who get the changes
  of the team find each new reminder under the bell each morning. They are
  not emailed again as changes.

After the seventh script, **Settings → Email alerts** lets accountants turn
the morning email on too, and each person chooses the kinds of paper under
**Papers and licences**: the company's, vehicles', employees' or customers'.
Someone the owner gave no access to People gets no employees' papers; no
access to Compliance, no other papers and no deadlines; no access to Maham
Books, no invoices, bills or cheques. Nothing needs to be
set up in Supabase beyond the script: the morning schedule of the email
alerts does the rest. WhatsApp and SMS are not part of this.

## Employee letters

**People → Letters** (الموظفون ← الخطابات): salary, experience and employment
certificates, warning letters and no objection certificates, filled from
each employee's record and printed on A4 with the company's letterhead. They
are off at first. In a company kept in the cloud the page offers them only
after the seventh script (step 1.11); until then it says the cloud needs the
latest database script. The owner or an admin turns on **Use employee
letters** (استخدام خطابات الموظفين) on that page.

- **Letter templates** (قوالب الخطابات): the five first letters are there
  with the app's wording, in Arabic and English, printed in Arabic unless a
  template says otherwise. Ask your lawyer to check the wording of the warning
  letter and the no objection certificate before they are issued.
- Accountants make drafts and click **Send for approval** (إرسال للاعتماد); the
  owner, admins and the members allowed to approve issue them (**Issue
  letter**, إصدار الخطاب) or approve the request (**Approve and issue**,
  اعتماد وإصدار), which issues it on their device. With letters on, the cloud
  refuses an issue by anyone else.
- A letter gets its number when it is issued: HR-2026-0001, from 1 again each
  year. Numbers are never used twice: an issued letter is voided, never
  deleted, and keeps its number. Once issued it stays as it was issued, and
  a void letter stays void, whatever an older copy on another device says.
  A warning letter or a no objection certificate is issued only once it
  says what happened, or what the company has no objection to.
- A template can make a draft by itself when an employee joins, leaves or has
  their salary changed. Drafts are never issued or printed without a person.
- Letters are printed, never emailed. The stamp and signature of Settings →
  Company print only on issued letters; drafts print with a watermark.
- Staff and viewers never see letters, templates or the requests about them.

## Manpower costing

**Maham People → Manpower costing** (مهام بيبول ← تسعير العمالة): posts of
guards, cleaners and other staff priced from what they cost (wage, overtime
at 1.25 past 8 hours a day, the employer's PIFSS share for Kuwaiti and GCC
posts, the end-of-service indemnity and leave earned in a month, and other
costs), with 10% overhead and a 15% margin of the sell price at first. It is
off at first. In a company kept in the cloud the page offers it only after
the eighth script (step 1.12); until then it says the cloud needs the latest
database script. The owner, an admin or an accountant turns on **Use
manpower costing** (استخدام تسعير العمالة) on that page.

- The **rate card** (جدول الأجور) starts from the current salaries: the
  average pay of each job title, worked out on the device of someone who
  sees payroll. Save it, or change it first.
- **Make quote** (إعداد عرض سعر) makes a draft quote for the costing's
  customer, numbered like any quote, with one line a post: the job title,
  hours, days, headcount and the sell price per person a month. Nothing else
  of the costing goes on the quote: no salary, PIFSS, indemnity, cost or
  margin. The quote and the costing point to each other.
- **Cost sheet** (كشف التكلفة) downloads the internal sheet of a costing. It
  is never attached to the quote or emailed.
- Article 66 of Labour Law 6/2010 limits overtime to 2 hours a day, 3 days
  a week and 180 hours a year unless an exemption applies. A post past any
  of these is flagged: more than 2 hours of overtime a day, or overtime on
  more than 3 days a week or for more than 180 hours a year. Staying within
  2 hours a day is not enough on its own: a 10-hour post worked 26 days a
  month is past the last two. Confirm with counsel before quoting such a
  post, or add people to it.
- Staff and viewers never see costings, their rate card or their activity;
  the cloud refuses them as it refuses payroll. A member the owner gave view
  only or no access to Maham People doesn't change them.

## Warehouses and items issued

**Maham Books → Inventory → Warehouses** (المستودعات): one main warehouse
and, under it, sub-warehouses (مستودع فرعي), each looked after by an
employee. In a company kept in the cloud this needs the tenth script (step
1.14); until then the page offers sub-warehouses only for companies kept on
a device.

1. **New sub-warehouse**: choose the employee who **looks after** it (it is
   named after them; you can change the name) and, under **Issues items
   from it**, their Maham One account. Invite that employee to the team as
   **Staff** first (**Settings → Team**).
2. **Send stock** on the sub-warehouse moves stock from the main warehouse
   to it, as a transfer: one warehouse goes down, the other up, at the same
   cost.
3. The employee signs in and, under **Inventory**, sees **You look after
   …** with **Issue items**: they choose the employee who receives the items
   (uniforms, trousers, T-shirts, shoes, shoulder badges, jackets…) and the
   quantities, and press **Send for approval**. Nothing leaves the
   sub-warehouse yet.
4. You (or an approver) get it in **Approvals**, and under the bell when
   **Changes by your team** is on (**Settings → Email alerts → Changes by
   your team**): "Ahmed
   (Warehouse supervisor) issued to Mohammed Ahmed (Security guard): 1
   Trouser, 1 T-shirt, 1 Jacket". **Confirm** records it as ISS-0001 and so
   on, and takes the quantities out of that sub-warehouse; **Reject** moves
   nothing and tells them why.
5. **Inventory → Issued items** lists every issue, who received what, from
   which warehouse, who issued and who confirmed it, and when. Each
   employee's page has an **Issued items** tab with what they hold, and
   **Reports → Issued items** has it line by line, with a CSV.
   An issue made by mistake is **voided** (never deleted): its stock comes
   back to the warehouse.

- The owner, admins and accountants set up sub-warehouses and change their
  stock directly (opening stock, adjustments, transfers); the employee who
  looks after one only issues items from it. The database itself refuses
  anything else.
- A keeper who is staff sees the names, numbers and job titles of current
  employees to choose who receives items, and nothing else of Maham People:
  no salaries, payroll or documents.
- The cost of the items issued is booked to **6240 Items issued to
  employees** (an expense), out of inventory, at the average cost.

## Scripts by phase

The database scripts are in
[`supabase/migrations/`](../supabase/migrations/). Each is run once, in this
order, in a new query of the SQL editor (paste the whole file, **Run**).

| #   | Script                                     | Phase                   | When                                                                            |
| --- | ------------------------------------------ | ----------------------- | ------------------------------------------------------------------------------- |
| 1   | `20261004000000_almailbooks_cloud.sql`     | First setup             | Run once at set-up (done). **Never run it again.**                              |
| 2   | `20261006000000_sync_fixes.sql`            | Set-up                  | Run once at set-up (done).                                                      |
| 3   | `20261007000000_email_alerts.sql`          | Set-up: email alerts    | Run once at set-up (done), with [`email-alerts.md`](email-alerts.md). Optional. |
| 4   | `20261102000000_tables_v16.sql`            | Phases 0-2              | Once, after 1 to 3. It can't run again once there are manpower costings.        |
| 5   | `20261116000000_super_admin_approvals.sql` | Phase 3 (first of two)  | Once, after 4.                                                                  |
| 6   | `20261123000000_change_feed.sql`           | Phase 3 (second of two) | Once, after 5.                                                                  |
| 7   | `20261130000000_people_alerts.sql`         | Phase 4                 | Once, after 6.                                                                  |
| 8   | `20261207000000_staffing_costings.sql`     | Phase 5                 | Once, after 7.                                                                  |
| 9   | `20261208000000_ai_assistant.sql`          | AI assistant            | Once, after 8.                                                                  |
| 10  | `20261210000000_warehouse_issues.sql`      | Warehouses              | Once, after 9. Then 4 and 8 can't run again once items are issued.              |

Scripts 2, 3, 5 to 7, 9 and 10 are safe to run again. Script 4 is too,
until there are manpower costings or items issued, and script 8 until there
are items issued: then they stop with an error about `records_tbl_check`
and change nothing. A script run again after a later one puts back its own,
older version of what the later one changed. The health check finds that and
says which scripts to run again, in order. As a rule: after script 3 run 7,
8, 9 and 10 again; after 4, run 8, 9 and 10 again; after 5 or 6, run 7, 8,
9 and 10 again; after 7, run 8, 9 and 10 again; after 8, run 9 and 10
again; after 9, run 10 again.

## Health check

[`supabase/health-check.sql`](../supabase/health-check.sql) checks the
database: that every script has run, each as its latest version, and that
what they set up works (tables, functions, triggers, row-level security,
grants, Storage, the schedules, email alerts, and that staff and viewers
can't read payroll and people data). It **changes nothing** and never shows
names, email addresses, phone numbers, Civil IDs, salaries, IBANs, keys or
what any record says: only counts, yes or no, versions, names of database
objects and statuses. Run it after running a script, or any time.

1. **SQL Editor** → **New query**.
2. Paste the whole of
   [`supabase/health-check.sql`](../supabase/health-check.sql) and click
   **Run**.
3. You get one table: **step** (the script, 1 to 10 as in the table above, or
   11 Schedules, 12 Email alerts, 13 Data and privacy), **check**, **status**
   and **detail**. The **last row** sums it up: "All good", or how many
   FAIL, MISSING and WARN there are, with the scripts to run, in order.

What each status means:

- **OK**: as it should be.
- **MISSING**: that step's script has not run yet. Run the scripts the
  detail names, in that order (the last row lists all of them).
- **WARN**: it works, but something optional is off or worth a look. The
  detail says what to do. Nothing in a WARN row stops the app.
- **FAIL**: something is broken, or an older version is in place. The
  detail says what to do.

What to do:

- **"This script has not run yet"** (MISSING): run it, then the ones the
  detail names after it, in order. The last row never adds the optional
  email alerts script: its own row says what to run for it.
- **"An older version"**, **"not as the script has it"**, **"not taken"**,
  **"not answered"** or **"not private"** (FAIL): an earlier script was run
  again after a later one, or an older copy of a script was run. Run again
  the scripts the detail names, in that order; the last row lists them all,
  for example "Run 20261130000000_people_alerts.sql again, then
  20261207000000_staffing_costings.sql again, then
  20261208000000_ai_assistant.sql again, then
  20261210000000_warehouse_issues.sql again (in this order)". Then run the
  health check again. The check never asks for the first script, nor for the
  fourth once there are manpower costings or items issued, nor for the
  eighth once there are items issued: if a row says something "can't be
  fixed by running a script" or "can't be put back by running it again", ask
  the developer.
- **"Email alerts were never set up"** (WARN): they are optional. To set
  them up, follow [`email-alerts.md`](email-alerts.md), then run the scripts
  the detail names (the email alerts script, then the Phase 4, Phase 5, AI
  assistant and warehouses scripts again).
- **"pg_cron is not on"** (WARN): nothing runs on a schedule (morning
  emails, emails of team changes, the daily clean-ups). Open **Database →
  Extensions**, enable **pg_cron** and **pg_net**, then run again the
  scripts the detail names.
- **"The email-alerts function hasn't run yet"** (WARN): publish it
  ([`email-alerts.md`](email-alerts.md), steps 4 and 5), then in the app open
  **Settings → Email alerts** and press **Send it now**.
- **A job "is switched off"** (WARN): turn it on in **Integrations → Cron →
  Jobs**. **"It is not scheduled"** (FAIL): run again the script the detail
  names. **"Its last run … ended "failed""** (FAIL): open the job there to
  see why, or ask the developer.
- **Emails that had a problem** or **calls to the email-alerts function that
  failed** (WARN): the people concerned see the message in **Settings →
  Email alerts**; see "If no email arrives" in
  [`email-alerts.md`](email-alerts.md).
- **"Rules added by hand to the app's tables"** (FAIL) or **"Other rules on
  Storage"** (WARN): someone added a policy in the dashboard. Policies add
  up, so one can open what the scripts keep closed: unless the developer
  added it, delete it in **Database → Policies** (or **Storage →
  Policies**).
- **The bucket company-files is "public"** (FAIL): in **Storage**, edit the
  `company-files` bucket and turn **Public bucket** off.
- **"Deletion markers"** or **"Old changes"** older than they should be
  (WARN): the daily clean-up isn't running; see the pg_cron rows.
- **A company with no owner**, **records of kinds the app doesn't sync**,
  or **a role that bypasses row-level security** (FAIL): ask the developer.

## Problems

- **"Check your email" but no email arrives**: the built-in service only sends
  to members of your Supabase organisation and about 2 per hour. Check spam,
  wait, or set up your own email service (step 4).
- **The link in the email says it has expired**: links work once, for a
  short time. Sign in, or ask for a new one from the sign-in screen.
- **The link opens on another device**: the address is confirmed anyway; sign
  in on the device you want to use.
- **"Redirect URL not allowed"** or the link opens the wrong site: check
  step 2.1.
- **Sync problem** in the app: open **Settings → Cloud and sync**. It shows
  what was not accepted (usually a change the person's role doesn't allow),
  with **Try again** and **Undo my change**.
- The app keeps working offline; changes sync when the connection is back.
