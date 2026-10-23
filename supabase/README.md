# Maham Books cloud (Supabase)

`migrations/20261004000000_almailbooks_cloud.sql` is the server: tables,
row-level security, the functions the app calls, the Storage bucket and its
policies, and the Realtime publication. `migrations/20261006000000_sync_fixes.sql`
comes after it: company settings merged by field, document numbers taken in
the cloud, deleting a company safely, and the file checks below. Until the
second runs, the app notices its functions are missing and works as before.
`migrations/20261007000000_email_alerts.sql` comes next and adds email alerts
(see "Email alerts" below). `migrations/20261102000000_tables_v16.sql` comes
next: the records of the app's database version 16 and their privacy (see
"Records of database version 16" below).
`migrations/20261116000000_super_admin_approvals.sql` comes next: the Super
Admin's controls, approvals and cheque confirmation (see "The Super Admin",
"Approvals" and "Cheque confirmation" below).
`migrations/20261123000000_change_feed.sql` comes next: the changes of the
team for the owner and approvers (see "The change feed" below).
`migrations/20261130000000_people_alerts.sql` comes next: salary approval,
expiry alerts and employee letters (see "Salary approval", "Expiry alerts"
and "Employee letters" below).
`migrations/20261207000000_staffing_costings.sql` comes next: manpower
costings of Maham People (see "Manpower costings" below).
`migrations/20261208000000_ai_assistant.sql` comes last: the AI assistant's
switch is the owner's and the admins' (see "The AI assistant's switch"
below). Each file is
run once, in this order; a release that needs more from the server adds a
file, and only that one is run. The files after the first are safe to run again, except the
fourth once there are manpower costings; the first is not, once there are records of version
16 (see below). The owner's
step-by-step guides are [`docs/supabase-setup.md`](../docs/supabase-setup.md)
and [`docs/email-alerts.md`](../docs/email-alerts.md). `health-check.sql`
tells whether every file has run, each as its latest version, and whether
everything works (see "Health check" below).

The app stays local-first: every screen reads IndexedDB on the device, and the
cloud keeps a copy of each company that is synced in the background. A company
that is never put in the cloud never leaves the device.

## What is stored

| Table                    | What                                                                                            |
| ------------------------ | ----------------------------------------------------------------------------------------------- |
| `public.profiles`        | One row per account: name, language, email (copied from `auth.users` by a trigger).             |
| `public.companies`       | Companies kept in the cloud: id, name, creator, `purged_until_rev`.                             |
| `public.company_members` | Who belongs to which company, with a role. One owner per company (unique index).                |
| `public.company_invites` | Invitation links: address, role, random token, 7-day expiry, used/cancelled.                    |
| `public.records`         | Every record of every company as JSON: `(company_id, tbl, id)`, `data`, `rev`, `updated_at/by`. |
| `public.deleted_records` | A marker per deleted record: `(company_id, tbl, id)`, `rev`, `deleted_at`, `private`. No data.  |
| `public.sync_signals`    | One row per company with the latest rev; the only table published to Realtime.                  |
| `storage.objects`        | Receipts and scans in the private bucket `company-files`, at `{companyId}/{attachmentId}`.      |
| `public.email_alerts`    | Who gets the morning email of which company, what it covers, and what was last emailed.         |
| `public.change_events`   | The change feed: who changed what, when; folded per sync, important changes one row each.       |
| `public.notification_*`  | Each recipient's choice of the changes emailed (`_settings`) and how far they read (`_reads`).  |

`tbl` is one of the app's 37 synced tables (a check constraint lists them).
Every write gets `rev` from one global sequence, the time and the author from
the server (`records_before_write`); what the app sends for them is ignored.
A per-company advisory lock, held until commit, makes revs reach readers in
commit order, so a pull "after rev N" never skips a change that committed late.

## Roles

|                                                          | Owner |        Admin        | Accountant |         Staff          | Viewer |
| -------------------------------------------------------- | :---: | :-----------------: | :--------: | :--------------------: | :----: |
| Read sales, purchases, cheques, stock, accounts, reports |  yes  |         yes         |    yes     |          yes           |  yes   |
| Change sales, purchases, cheques, stock, files, activity |  yes  |         yes         |    yes     |          yes           |   no   |
| Make transfers, cheque clearings/returns, releases       |  yes  |         yes         |    yes     |          yes           |   no   |
| Change accounts, tax rates, journals, assets, year-end   |  yes  |         yes         |    yes     |       read only        |   no   |
| Change company settings                                  |  yes  |         yes         |    yes     | document counters only |   no   |
| See payroll and people data                              |  yes  |         yes         |    yes     |         **no**         | **no** |
| Invite, change roles, remove members                     |  yes  | yes (not the owner) |     no     |           no           |   no   |
| Transfer ownership, delete the company                   |  yes  |         no          |     no     |           no           |   no   |
| Limit members, choose approvers, keep senior roles       |  yes  |         no          |     no     |           no           |   no   |
| Leave the company                                        |  no   |         yes         |    yes     |          yes           |  yes   |

**Payroll and people data** (invisible to staff and viewers, not even
readable): `employees`, `payRuns`, `payrollSettings`, `peopleSettings`,
`leaveRecords`, `staffLoans`, `finalSettlements`; `complianceDocuments` and
`renewals` that belong to an employee; files (`attachments`) of an employee or
of an employee's document or renewal; payroll journals (`kind = 'payroll'`,
which show salaries); activity entries about employees and payroll; letter
templates and employee letters (`letterTemplates`, `employeeLetters`);
approval requests about any of these (`approvals` whose `subjectTbl` is one of
the tables above); register documents marked `confidential` with their
renewals, files and activity. The rule is `almailbooks.record_is_private`. The
app also marks files and activity about employees, letters and confidential
documents with `_private: true`, which can only make a record more private.

With the owner's switch on (see "The Super Admin" below), admins invite,
change and remove only staff and viewers.

## Functions

The app calls these (all `revoke`d from `anon` and `public`, granted to
`authenticated`, `set search_path = ''`, every name schema-qualified):

| Function                                                                   | Runs as | Why                                                                                       |
| -------------------------------------------------------------------------- | ------- | ----------------------------------------------------------------------------------------- |
| `push_records(company, changes)`                                           | invoker | Saves a batch in one transaction under the caller's RLS. Returns `{tbl,id,rev,conflict}`. |
| `pull_records(company, since, limit)`                                      | invoker | Records and deletion markers after a rev, under RLS; `almail:resync` when too old.        |
| `company_record_ids`, `company_sync_info`                                  | invoker | For a full resync, progress and the file clean-up; RLS applies.                           |
| `create_company(id, name)`                                                 | definer | Creates the company and the owner's membership (members can't insert themselves).         |
| `my_companies()`                                                           | definer | Only rows where `user_id = auth.uid()`.                                                   |
| `company_team(company)`                                                    | definer | Members' names and emails, for members of that company only (profiles are private).       |
| `create_invite`, `list_invites`, `revoke_invite`                           | definer | Owners and admins only; never as owner.                                                   |
| `invite_details(token)`, `accept_invite(token)`                            | definer | See "Invitations".                                                                        |
| `set_member_role`, `remove_member`, `transfer_ownership`, `delete_company` | definer | Role checks inside; the owner can't be demoted or removed.                                |
| `patch_company(company, ops)`                                              | invoker | The fields a device changed, laid over the cloud's company record; conflicts reported.    |
| `reserve_number(company, kind, date, min)`                                 | invoker | The next number of a kind of document, taken from the company's counter at once.          |
| `begin_delete_company(company)`                                            | definer | Owners only, before the app removes any file; uploads are refused for an hour.            |
| `stored_files(company, names)`                                             | definer | Which of these files are still stored, for members: a removal that removed nothing.       |
| `server_features()`                                                        | invoker | What the server has beyond the first files (`tables_v16`…), so the app can hide the rest. |
| `set_member_permissions`, `set_team_rules`                                 | definer | Owner only: a member's limits and approver mark; who makes admins and accountants.        |
| `team_permissions`, `my_permissions`, `owned_companies_overview`           | definer | Limits and approver marks (everyone's for owners and admins), and the companies owned.    |
| `notification_status`, `notification_feed`, `mark_notifications_read`      | definer | The changes of the team, for the owner and approvers only; never their own changes.       |
| `change_notification_settings`, `set_change_notifications`                 | definer | The caller's own choice for the changes emailed (owner and approvers only).               |

`create_company` refuses a company that is already in the cloud with records
(`almail:company_exists`): the app offers to download it instead, so an older
copy (a restored backup) never replaces the team's newer work.

Helpers used by the policies live in the schema `almailbooks`, which the Data
API does not expose, so nobody can call them through the API.

### Why each security definer function is safe

- They all start from `auth.uid()` (the JWT's subject), never from a user id
  the caller passes, and check the caller's role in the company first:
  `almailbooks.member_role(company)` reads the caller's own membership row.
- `set search_path = ''` and fully qualified names: no object can be swapped
  in through the search path.
- They never return records' data. `company_team` returns names, emails and
  roles of the caller's own team; `invite_details` returns what the invitation
  link already says; `my_companies` returns the caller's own memberships.
- Policy helpers (`can_read_record`, `can_write_record`, `record_is_private`,
  `can_use_file`…) are definer so that a policy on `records` can look at
  other rows (an attachment's owner) without recursion; they only answer yes
  or no for the calling user.
- Triggers are definer so that clients need no privilege on the rev sequence
  and the deletion markers; they validate what is written (company of the
  record, size, staff limits) and only write bookkeeping columns and markers.

## Files

A file at `{companyId}/{attachmentId}` follows its attachment record: whoever
may read or change the record may read or change the file
(`almailbooks.can_use_file`). Storage reads back every row it saves or
removes, so the read rule also applies to uploads and removals. While a file
has no record (the app uploads the file just before it sends the record, and
removes it just after the record is deleted):

- owners, admins and accountants may use it;
- staff may use only their own upload on its way (`storage.objects.owner_id`,
  which Storage sets from the signed-in account), and the file of a deleted
  attachment that was not private, to remove it;
- viewers may not.

So staff never see a file another member is still uploading (it may be an
employee's passport) nor the file of a deleted private attachment.

## Invitations can't be hijacked

- The token is 64 hex characters from two `gen_random_uuid()` (244 random bits
  from the server's strong random source): it can't be guessed.
- `accept_invite` only works for a signed-in account whose **confirmed**
  email (`auth.users.email_confirmed_at`, read on the server) equals the
  invited address (case-insensitive). Holding the link is not enough.
- Single use (`accepted_at`), expires after 7 days, can be cancelled; a new
  invitation for the same address cancels the pending one.
- Nobody can be invited as owner; only owners and admins invite.
- The description shown before signing in (company, who invited) is taken
  from the link and only shown; joining checks everything in the database.
- This relies on two Supabase settings that are on by default and must stay
  on: **Confirm email** (otherwise anyone could sign up with the invited
  address) and **Secure email change** (otherwise an account could switch to
  the invited address without confirming it).

## Deletes

- Deleting in the app deletes in the cloud: `push_records` deletes the row
  from `public.records` (members need write permission on that kind of
  record; the company record itself is never deleted this way).
- A trigger writes a marker to `public.deleted_records` with the next rev, so
  other devices delete their copy. The marker holds no data, only which record
  and when; markers of payroll data are hidden from staff and viewers.
- Markers are removed after **30 days**: on every push and pull for that
  company, and daily by `pg_cron` when the extension is on. A device that was
  away longer gets `almail:resync`: it fetches the ids that exist, deletes
  what the cloud no longer has (never changes still waiting to be sent) and
  pulls everything again.
- **Files**: deleting an attachment removes its Storage object in the same
  sync step; removals that fail are retried until they succeed. A new version
  of a file replaces the old object (same path). Owners can run **Clean up
  files** (Settings → Cloud and sync), which removes objects no attachment
  uses (older than an hour, so uploads on their way are left alone); it also
  runs after a full resync.
- **Deleting a company** (owner only) first removes every object under
  `{companyId}/` through the Storage API, then `delete_company` deletes the
  company row, which cascades to its records, markers, members, invitations
  and signal.
- **Deleting an employee** without payroll history removes them, their
  documents and renewals, every file kept with them or with those, and the
  activity about them; one entry with their number only records the deletion.
  With payroll history (pay runs, leave, loans, a settlement) they are marked
  as left, because the accounts depend on it.
- Supabase's daily backups (Pro plan) keep deleted data for up to **7 days**;
  after that it is gone.

## Sync rules

- The device sends its outbox with `base_rev` = the version it last had. The
  push always wins (last write wins); `conflict` is true when the server had a
  newer version that this push replaced (or a newer delete), and the app notes
  it in the activity log.
- **Document numbers never go back.** For the `companies` record the trigger
  merges `numbering`: for each kind of document the counter of the later
  `period` wins (same period: the higher `next`); pattern, padding and reset
  are taken as sent (a change of reset takes the rule as sent).
- Each record must belong to the company it is stored under (`data.companyId`
  and `data.id` are checked), and is at most about 1 MB (3 MB for the company
  record, which carries the logo, stamp and signature).

## Realtime

`public.records` is **not** published. With real deletes, Realtime would send
the primary key of every deleted row to anyone subscribed (Postgres can't check
row-level security on a row that no longer exists). Instead `push_records`
bumps one row per company in `public.sync_signals`, which is published and
protected by RLS (members only); the app pulls when it hears about it.

## Keys

The app only ever uses the **publishable key** (`sb_publishable_…`), which is
public by design: it identifies the project, and every request runs as the
signed-in person under RLS. The app refuses to start the cloud with a secret
key (`sb_secret_…`) or a service-role JWT (`src/cloud/config.ts`). The secret
key must never be put in the app, in Vercel's environment variables for the
app, or anywhere public.

## Security review checklist

- [x] RLS is enabled on every table; no table is readable by `anon`;
      `TRUNCATE`, `REFERENCES` and `TRIGGER` are revoked from clients.
- [x] A member of one company can neither read nor write another company's
      records, members, invitations, markers, signals or files (tested).
- [x] Staff and viewers never receive payroll or people data, through pulls,
      plain selects, id listings, markers or Storage, including files on their
      way up and files of deleted records (tested with the statements Storage
      runs).
- [x] Viewers can't write anything; staff can't change accounting setup or
      company settings (only document counters) (tested).
- [x] Records can't be moved between companies or stored under the wrong
      company id (tested).
- [x] Every `security definer` function sets `search_path = ''`, checks the
      caller's role from `auth.uid()`, and is not callable by `anon`.
- [x] Invitations: unguessable, single use, 7 days, confirmed matching email
      only, never as owner (tested).
- [x] The owner can't be removed or demoted; exactly one owner (unique index;
      an admin takes over if the owner's account is deleted) (tested).
- [x] Deletes leave no data behind; markers expire after 30 days (tested).
- [x] Realtime publishes no record data and no keys of deleted rows.
- [x] The app uses the publishable key only.
- [ ] Don't add other policies on `storage.objects` or on these tables in the
      dashboard: policies add up, so a broad one (for example "authenticated
      users can read every bucket") would open what these rules close.

## Testing

`src/cloud/sql.test.ts` runs this exact file in an in-process Postgres
(PGlite) after a small stand-in for Supabase's `auth` and `storage` schemas and
roles (`src/cloud/sql-harness.ts`), then checks the matrix above as real
signed-in users, with row-level security on. Run it with
`npx vitest run src/cloud/sql.test.ts`.

## Scripts by phase

| #   | File                                                  | Phase        | Notes                                                                   |
| --- | ----------------------------------------------------- | ------------ | ----------------------------------------------------------------------- |
| 1   | `migrations/20261004000000_almailbooks_cloud.sql`     | First setup  | Run once at set-up. Never again (see "Records of database version 16"). |
| 2   | `migrations/20261006000000_sync_fixes.sql`            | Set-up       | Run once at set-up.                                                     |
| 3   | `migrations/20261007000000_email_alerts.sql`          | Set-up       | Run once at set-up; optional (email alerts).                            |
| 4   | `migrations/20261102000000_tables_v16.sql`            | Phases 0-2   | Can't run again once there are manpower costings.                       |
| 5   | `migrations/20261116000000_super_admin_approvals.sql` | Phase 3      | Needs 4.                                                                |
| 6   | `migrations/20261123000000_change_feed.sql`           | Phase 3      | Needs 5.                                                                |
| 7   | `migrations/20261130000000_people_alerts.sql`         | Phase 4      | Needs 6.                                                                |
| 8   | `migrations/20261207000000_staffing_costings.sql`     | Phase 5      | Needs 7.                                                                |
| 9   | `migrations/20261208000000_ai_assistant.sql`          | AI assistant | Needs 8.                                                                |

A file run again puts back its own version of every function, rule and
constraint it defines. What a later file replaced must then be put back by
running again the latest file that defines it, and so on: after 3, run 7,
8 and 9; after 4, 8 and 9; after 5 or 6, 7, 8 and 9; after 7, 8 and 9;
after 8, 9 (after the first file, which only succeeds before there are
records of version 16: 2, 5, 7, 8 and 9).
`maham_closure` in `health-check.sql` is this table. The fourth file only
succeeds before there are manpower costings: once there are, the check
never asks for it, and what only it makes needs a fix from the developer.

## Health check

`health-check.sql` is pasted into the SQL editor whole; the owner's guide is
"Health check" in [`docs/supabase-setup.md`](../docs/supabase-setup.md). It
ends with one result set (the SQL editor shows only the last statement's),
one row per check in the order of the files: `step`, `check`, `status` and
`detail`, and a summary row last.

- **Read-only.** It creates five functions in `pg_temp` (gone with the
  connection), and the check's first statement sets
  `transaction_read_only`, so nothing after it can write: not the dynamic
  calls, not a function they reach. It reads the catalog (`pg_proc`,
  `pg_policy`, `pg_trigger`, `pg_constraint`, `pg_class`, the
  `has_*_privilege` functions), counts rows, calls
  `public.server_features()` and `almailbooks.record_is_private` (with no
  record, so it reads nothing), and reads `cron.job`,
  `cron.job_run_details` (status only) and `net._http_response` (status
  codes only). It never calls anything that writes, sends or schedules.
- **Private.** It shows counts, yes or no, versions, object names and
  statuses only: no record content, names, emails, salaries, the
  schedule's secret or the function's address. Kinds of record it names are
  the `tbl` values; error messages are reduced to their SQL state.
- **Which files ran.** Each file has objects no other file makes or
  removes (`push_records`, `patch_company`, `email_alerts_config`,
  `can_read_v16_file`, `set_member_permissions`, `change_events`,
  `people_shut`, the rule "Manpower costings: kept from staff and
  viewers", `switches_ai`). A file that hasn't run is one MISSING row (one WARN row for the
  email alerts, which are optional), with that file and every later one that
  hasn't run (but the email alerts, which only their own row names), each
  with the files that put back what it replaces.
- **Latest versions.** Every function, trigger, rule, table, column and
  constraint of each file, and its grants (what the app calls: signed-in
  members only; what the rules call: signed-in members; jobs and triggers:
  not the members; anonymous visitors: nothing). A function a later file
  replaces is checked at each later version by text only that version (and
  the ones after it) has; `server_features()` by what it answers, against
  the names in `src/cloud/features.ts`; `records_tbl_check` against every
  kind the app syncs; `record_is_private` by asking it about each payroll
  and people kind. Every function's body is also compared with the body
  each file that defines it has (`bd`: an md5 of `prosrc` with `--`
  comments and spacing left out, so a paste that changed them still
  matches): a body none of them has comes from an older copy of a file, or
  was changed by hand. Something wrong after its file ran is a FAIL that
  names the latest file setting it that has run (for grants, the files that
  grant or revoke the function, which `fg` lists where they aren't all the
  files that define it), and the files that put back what that one replaces
  (the table above). What only the first file sets up can't be fixed by a
  script, nor, once there are manpower costings, what only the fourth sets
  up: the row says to ask the developer. A public `company-files` bucket is
  put right in Storage: the row says how.
- **Schedules and email alerts.** With pg_cron, each job the files schedule
  (`almailbooks-purge-deleted-records`, `maham-books-email-alerts`,
  `maham-change-notifications`, `maham-change-feed-purge`): there, running
  the files' command, on, and how its last run ended. Without pg_cron, one
  WARN with what stops. With the email alerts: the settings row and its
  secret (length only), whether the function has registered its address,
  recent errors of each kind of email (counts), pay-run approval emails
  given up, and recent pg_net answers. The function's own secrets (Resend
  key, sender) are Edge Function secrets the database can't see; no file
  uses Vault.
- **Data and privacy.** Companies, one owner each, members by role,
  approvers, records by kind (none of a kind the app doesn't sync),
  approval requests waiting, deletion markers and changes past their
  clean-up, and that staff and viewers can't read payroll and people data:
  row-level security on, the restrictive rules there, `record_is_private`
  knows every private kind, no rule added by hand that opens records, and
  the API roles neither bypass row-level security nor own the tables.
  Nobody is impersonated.

`src/cloud/health-check-sql.test.ts` runs it on PGlite: OK after every file
(WARN only for pg_cron and the unpublished function, which PGlite can't
have; "All good" with stand-ins for both), MISSING for exactly the later
files after each prefix, FAIL with the right files after each earlier file is
run again (and OK once they have run), advice that leads to no FAIL or
MISSING when set-up files were skipped, an older copy of a function found
(and a body pasted with other spacing not), the fourth file never advised
once there is a manpower costing, nothing changed in the catalog, grants,
schedules or any table after running it twice, and none of a set of seeded
secrets, emails and salaries in its output. It also checks its lists against
the files: every function with the files that define it and those that set
its grants (and that each of those sets all of them), each marker present in
its version and the later ones only, each body's fingerprint in each file,
every trigger, rule and table, the kinds, the private kinds and the
features. A new file adds its objects to the lists in `health-check.sql`
(the fingerprints of its functions to `bd`, which the test prints when they
differ, and a line to `maham_closure`), or that test fails.

## Known limits

- Two devices editing the same record at the same time: the later save wins
  (with a note in the activity log), except document counters, which merge.
- Numbers are given out on each device; two devices offline at once can give
  out the same invoice number, which the app shows as a duplicate to fix.
- A team member could fill the company's storage (each record up to about
  1 MB); Supabase's plan limits apply.
- A company whose owner deletes their account goes to the longest-standing
  admin (or accountant); without either it has no owner.

## Records of database version 16

`20261102000000_tables_v16.sql` lets `public.records` take five more tables:
`chequeLayouts`, `vehicles`, `approvals`, `letterTemplates` and
`employeeLetters`. None of them can be changed by staff (`staff_can_write` is
unchanged). It replaces `record_is_private` with the rules above, and adds a
second, restrictive read rule on `records`, on `deleted_records` for letters,
and on the files in Storage, that keeps letters, approval requests about
people data, confidential documents, their renewals, and the files and
activity of any of these from staff and viewers even if the first file is run
again and puts back its older `record_is_private`. Activity entries carry a
mark of their own (`employeeId`, or `confidential: true`), so those about an
employee's papers or a confidential document stay private once it is deleted.

Once the new tables have records, the first file can't be run again: it stops
where it lists the kinds of record (`records_tbl_check`) and changes nothing.
Releases after this one add files of their own instead, and only those are
run. Had the first file been run again before there were any, run the later
files again after it, in order. The v16 file also schedules the daily clean-up
of deletion markers when `pg_cron` is on, as the first file does, so turning
`pg_cron` on and running it again is enough, until there are manpower
costings: then it can't run again either, and
`20261207000000_staffing_costings.sql`, which schedules the clean-up the same
way, is the one to run again.

`server_features()` answers `{tables_v16}`. The app asks it as it syncs and
keeps the answer on the device, so a feature that keeps these records stays
hidden until the owner has run the file. A device whose earlier version
skipped the new tables' records fetches just those tables once
(`company_record_ids` and the records), instead of syncing everything again.
`src/cloud/tables-v16-sql.test.ts` checks the rules, and
`src/cloud/table-parity.test.ts` that the table lists here and in the app agree.

## The Super Admin

`20261116000000_super_admin_approvals.sql`. It stops before changing
anything without `20261102000000_tables_v16.sql` (it answers `tables_v16` in
`server_features()`, and the devices then send what they kept back for that
file). The Super Admin is each company's owner (`company_members_one_owner`);
someone becomes Super Admin through `transfer_ownership`, and nothing names a
person.

- `company_members.permissions` (jsonb, `'{}'` by default) holds the owner's
  limits on a member: `{"apps": {"books" | "people" | "crm" | "compliance":
"none" | "view" | "edit" | "manage"}}`. `can_write_record` reads the
  member's row once (as `member_role` did) and refuses a write when the
  record's app (`almailbooks.record_app`: People tables, payroll journals and
  employees' papers are People; the register and vehicles Compliance; the
  books Books; the company record, activity and approval requests no app; a
  file the app of the record it is kept with, `almailbooks.attachment_app`,
  looked up only for a member with limits) is limited to `none` or `view`.
  `records_guard` also refuses (`almail:permission`) a member whose Books is
  `none` or `view` a change of the books' settings on the company record
  (`almailbooks.company_books_changed`: accounting with the lock date,
  payment, `bankAccount`, `emailTemplates`, `kuwait.wamdPhone` (empty and
  none alike), defaults, taxes, opening balances, vouchers, items, cheque
  printing and numbering rules; counters, employees' numbering and the rest
  of `kuwait` stay open), by a push or `patch_company`. Owners are never
  limited. `'{}'`, every member's value until the owner sets one, gives the
  first file's answers (the regular tests run with it). Reading is
  unchanged.
- `company_members.can_approve` (false by default): admins and accountants
  only, two at most; `almailbooks.is_approver(company)` is the owner or one of
  them. A trigger clears it when the role changes to anything else, and
  clears an owner's limits.
- `companies.senior_roles_owner_only` (false by default) is the owner's
  switch (`set_team_rules`): with it on, `create_invite`, `revoke_invite`,
  `set_member_role` and `remove_member` (same signatures) leave admins and
  accountants to the owner; admins still invite and remove staff and
  viewers, and anyone may leave. Turning it on cancels invitations as admin
  or accountant someone else made, and an admin's new invitation for an
  address the owner invited as admin or accountant is refused instead of
  replacing it. Refusals are `almail:permission` with SQLSTATE 42501.
- `company_members_audit` sends every team change (joined, role, limits,
  left, ownership, succession when the owner's account is deleted) to
  `public.change_events` as kind `member`, with ids and roles only. It does
  nothing until `20261123000000_change_feed.sql` creates that table, and
  ignores any error writing to it, so it never stops a team change. Once it
  exists, these show in the feed (see "The change feed").
- `server_features()` also answers `super_admin`.
- `src/cloud/super-admin-sql.test.ts` checks all of it, and that the app's
  test cloud (`src/cloud/testing/fake-cloud.ts`) refuses the same changes.

## Approvals

The same file. The company's rules are `approvalRules` on its own record
(`{"documentTypes": ["invoice", "credit"], "voidInsteadOfDelete": true,
"expireDays": 14}`), set by the owner in Settings → Approvals;
`almailbooks.approval_rules(company)` is null until then, and every rule below
does nothing while it is null, except those on approval requests themselves
(nothing wrote them before this file) and invoices numbered when issued.

- `staff_can_write` adds `approvals`: staff ask for approval (never of payroll
  or people data: `record_is_private` of the fourth file still applies).
- `records_guard`, BEFORE INSERT OR UPDATE on `public.records`, runs after
  `records_before_write` (same kind, by name). It looks at the company record,
  documents and approval requests only, and returns at once for the SQL editor
  and the server's own jobs (no `auth.uid()`). An upsert of a record that is
  there is checked as the update it becomes.
  - `companies`: only the owner changes `approvalRules` (by a push or
    `patch_company`).
  - `documents` of a type the rules cover, not a draft: anyone but an approver
    is refused when `almailbooks.invoice_content` changes (what is printed:
    party, dates, currency, lines, discounts, taxes, charges, deposit,
    retention terms, wording, design, number, `replacesNumber`) or the stage
    changes (draft, issued, void). Totals, status within issued, paid and sent
    times, retention releases, the posting snapshot and internal notes are
    written by payments and sync, and stay open. The payment link
    (`almailbooks.payment_link_changed`): once there is one, a write by
    anyone but an approver that changes or removes it keeps the stored link
    (`almailbooks.kept_key`) and goes through, since documents travel whole
    and such a copy is most often from a device that hadn't received the
    link, sent with a payment (the app refuses a change made on purpose);
    adding one where there was none stays open. Refusal:
    `almail:approval_required`, SQLSTATE 42501, which older versions of the app
    park as a permission problem.
  - `approvals`, whether or not the rules are on: a new request waits
    (`pending`), stamped with the server's `requestedBy` and `requestedAt`
    (`expired` and `resultId` dropped); what was asked never changes; only an
    approver decides (`approved`, `rejected`, `applied`, stamped
    `decidedBy`/`decidedAt`); whoever asked may cancel while it waits and
    change nothing else; `expired` is kept only when an approver cancels a
    waiting request and `resultId` only when one is carried out; a decision
    made stays made whatever an older copy says. A decided request sent up
    new is kept as it is from the owner (their company sent up again) and
    stamped as asked and decided by the deputy who sends it otherwise.
  - `documents`, with `defaults.numberOnIssue` on the company record (Settings
    → Numbering): an invoice or credit note leaving draft (or new) issued
    without a number is refused `almail:invalid`, SQLSTATE 42501, whoever
    sends it: older versions of the app don't number a draft they issue.
- `can_delete_record` (now plpgsql): approval requests are never deleted
  (the SQL editor still can); issued documents of the covered types are
  deleted by approvers only, and with `voidInsteadOfDelete` by nobody, so a
  delete followed by a new copy never gets round the rules. Counters are
  unchanged (numbers only move forward).
- `server_features()` also answers `approvals`.
- `src/cloud/approvals-sql.test.ts` checks rules off = as before, every role,
  an older app's batch, upserts, deletes, that `invoice_content` matches the
  app's `invoiceContent` (src/cloud/roles.ts) field by field, and that the
  test clouds refuse the same changes.

## Cheque confirmation

The same file (#9 of docs/requirements-plan.md). The rules' `cheques`
(`{"issued": true, "securityOut": true, "received": false}`, set by the owner
in Settings → Approvals → Cheques; absent or all false: nothing changes). An
unconfirmed cheque is an approval request, never a payment (D13): the
approver's device records the payment when they confirm it.

- `almailbooks.rules_cover_cheque(rules, payment)`: `method = 'cheque'` in a
  covered direction (`out`: issued; anything else: received).
  `almailbooks.rules_cover_security_cheque(rules, cheque)`: a security cheque
  with `direction = 'out'` while `securityOut` is on.
- `almailbooks.cheque_content(payment)`: what is confirmed (method, direction,
  client, payment date, amount, currency, rate with 1 for none, the account
  it is booked to, cheque number, bank, cheque date, drawer or payee, drawer
  civil ID). A cheque saved before it had an account may be given one.
  `almailbooks.security_cheque_content(cheque)`: direction, number, bank,
  date, amount, currency, drawer, drawer civil ID. Their life (status,
  deposited, cleared, returned, journals, replacements, voiding), prints,
  notes, allocations and the posting rules stay open. Kept the
  same as `chequeContent` / `securityChequeContent` in `src/cloud/roles.ts`.
- `almailbooks.cheque_change_needs_approver(rules, tbl, old, new)`: a new
  covered cheque, a change of its content (before or after covered), or a
  deletion (`new` null). A number change is open when the old number is among
  the new row's `cheque.spoiledLeaves` (printed onto the next leaf).
- `records_guard` also looks at `payments` and `securityCheques` (returning at
  once for payments that are not cheques and security cheques received):
  anyone but an approver who may write the record is refused
  `almail:approval_required`, SQLSTATE 42501.
- `can_delete_record`: only an approver deletes a covered cheque.
- A security cheque received (or given, with `securityOut` off) is not
  covered itself, though the payment it is cashed as may be: the approver's
  device carries out a request to cash it only while the security cheque is
  still what the request copied (`applyChequeRequest` in
  `src/db/cheque-approvals.ts`), and devices keep it unchanged while the
  request waits.
- `server_features()` also answers `cheque_approvals`: the app shows the
  cheque switches only then.
- `src/cloud/cheque-approvals-sql.test.ts` checks rules off = as before, every
  role, an older app's batch, upserts, deletes, the spoiled-leaf case, that
  the content functions match the app's, and that the test cloud
  (`src/cloud/testing/fake-cloud.ts`) answers the same; the e2e fake
  (`e2e/cloud-fake.ts`) mirrors it too.

## The change feed

`20261123000000_change_feed.sql` (#7 of docs/requirements-plan.md, D7 and D8).
It stops before changing anything without the Super Admin file.

- `public.change_events`: `id`, `company_id`, `at`, `actor`, `op`, `tbl`,
  `record_id`, `kind`, `important`, `private`, `count`, `fold_key` and
  `summary`, unique `(company_id, fold_key)`; row-level security on, no grants. A BEFORE INSERT
  trigger takes the company's write lock (`lock_company`, as records take
  their rev) before it numbers the row, so a company's changes are numbered
  in the order they commit and "up to id N" never skips one stored late.
- `records_change_event`, AFTER INSERT OR UPDATE OR DELETE on
  `public.records`, its whole body inside `exception when others`: a problem
  in it is ignored and the push goes on (tested with a feed that refuses
  every row). It returns at once without a signed-in caller (the SQL editor,
  the server's jobs), for `activities`, for a copy sent again unchanged
  (`old.data = new.data`), during `delete_company`, and **while nobody of the
  company has turned the feed on** (`notification_settings.enabled`), so
  until then it records nothing. Ordinary changes of one push fold into one
  row per person, table (documents also per type), kind and privacy
  (`fold_key` = transaction id and those); important ones get a row each
  (`almailbooks.change_details`: an issued invoice or credit note edited,
  voided, restored or deleted; cheque payments recorded, changed, voided,
  returned, cancelled or deleted; security cheques recorded, changed, cashed
  or deleted; approval requests, approvals and rejections; numbering rules,
  the lock date and the approval rules; pay runs added, deleted or moved on).
  A company record whose counters only moved on is left out. `private` is
  `record_is_private` of the old or new record; private summaries keep only
  what happened (and a pay run's stage and month): no names, numbers or
  amounts. The app's copy of these rules is `src/cloud/change-feed.ts`.
- `public.notification_settings` (one row per member who saved a choice,
  removed with the membership; `enabled`, `immediate_kinds`, `digest`
  `daily`/`off`, `app_url`, and what the function keeps: `emailed_upto`,
  `digest_on`, `sent_on`/`sent_count`, `last_sent_at`, `last_error`,
  `claimed_until`, `send_key`/`send_upto`), and `public.notification_reads`
  (`read_upto`). A trigger on `company_members` turns a person's off when
  they stop being the owner or an approver.
- `notification_status(company)`: for the owner and approvers whether they
  turned it on, unread (up to 100) and the newest id; everyone else gets
  "off". `notification_feed(company, after, before, limit)`: owner and
  approvers only (42501 otherwise), newest first, the caller's own changes
  left out, private ones only to owners, admins and accountants, with the
  author's (and for team changes the member's) name.
  `mark_notifications_read(company, upto)` never goes back.
  `set_change_notifications(company, enabled, kinds, digest, app_url)`: owner
  and approvers; turned on, it starts from now (earlier
  changes are not emailed and read as read).
- `almailbooks.run_change_notifications()`, scheduled every 5 minutes
  (`maham-change-notifications`), posts `{"action":"notify"}` to the
  email-alerts function with the email alerts secret, only when someone who
  turned it on has changes newer than what they were emailed (not their
  own). `almailbooks.purge_change_events()` (daily,
  `maham-change-feed-purge`) removes changes older than 180 days.
- The function claims each due person (`claimed_until`), reads their changes
  after `emailed_upto`, and sends important changes of the chosen kinds at
  once and the rest in the 8:00 summary, at most one email every 15 minutes
  and 20 a day (`notifyDecision` in `src/alerts/changes.ts`). The Resend
  `Idempotency-Key` and the last change covered are saved first, so an
  email whose answer was lost goes again as it was, once.
- `server_features()` also answers `change_feed`.
- Tests: `src/cloud/change-feed-sql.test.ts` (nobody asking = as before, an
  older app's batch, every role, folds of a 500-change push, upserts,
  deletes, important changes, privacy, a feed that refuses everything,
  delete_company, the schedule, the purge, the app's copy of the rules and
  the test cloud), `src/alerts/server.test.ts` ("notify") and
  `src/alerts/changes.test.ts`.

## Salary approval

`20261130000000_people_alerts.sql` (#10 of docs/requirements-plan.md, Phase 4's
file: later Phase 4 requirements add to it). It stops before changing anything
without the change feed file. Off until the owner sets `approvalRules.payroll`
to `true` on the company record (Settings → Approvals → Pay runs, the owner's
alone as every approval rule); until then nothing below looks at a record.

- `records_guard` is replaced with the Super Admin file's definition and every
  rule it had, plus, for an `approvals` row of kind `payroll` about `payRuns`
  with the switch on (`almailbooks.payroll_approval_on`): approving it
  (pending to approved, or to applied by anyone but the owner) is refused
  (`almail:invalid`, 42501) unless the pay run stored now has the `updatedAt`
  the request was made for (`after.runUpdatedAt`); a member allowed to
  approve who sent it is refused (`almail:permission`, 42501), the owner may
  approve their own; a member the owner gave no access to People
  (`almailbooks.people_shut`: `permissions.apps.people = 'none'`) decides
  none (`almail:permission`, 42501), though they may take back their own
  waiting request; a request sent up already approved or applied by anyone
  but the owner is stored as a new waiting one; and whoever may post the pay
  run (`can_write_record(company, 'payRuns', '{}')`: owner, admin or
  accountant whose People isn't limited) may move an approved request to
  applied, the decision kept. The owner who posts a pay run moves a waiting
  request to applied without the check (posting is their approval). Every
  other record passes as before. Posting a pay run is **not** refused by the
  server: its journal entries are separate records an older version would
  still send; the app refuses it, and the feed reports every posted run.
- `almailbooks.approval_emails` (`company_id`, `approval_id`, `user_id`,
  `sent_at`, `finished_at`, `attempts`, `claimed_until`, `last_error`),
  row-level security on, no grants: the email-alerts function (the database's
  own connection) only.
- `records_payroll_approval_email`, AFTER INSERT on `public.records` (`when`
  the row is a payroll approval): with the switch on and the request waiting,
  notes one row per approver (the owner and `can_approve` admins or
  accountants, not the requester, not one the owner gave no access to
  People), then `net.http_post` `{"action":"payroll_approval", companyId,
approvalId}` with the email alerts secret. Each part inside its own
  `exception when others`: without pg_net, the config or anything else it
  needs, the push goes on and the rows wait for the schedule. An upsert of a
  request already stored is an update, so it never emails twice.
- `almailbooks.run_change_notifications()` is replaced with the change feed
  file's definition plus: it also calls the function when an approval email
  hasn't gone (not finished, fewer than 5 tries, under 3 days old). The
  `notify` action then sends those too.
- The function (`sendPayrollApprovalEmails` in `src/alerts/server.ts`)
  claims the rows, sends only while the request waits, the switch is on and
  the stored pay run is the one sent, to approvers with a confirmed address
  in their language, with `Idempotency-Key: payroll-approval/<approval>/<user>`.
  The totals come from the stored pay run (`payrollBreakdown`, groups of one
  merged); no names, Civil IDs, IBANs, anyone's own pay or the note. Links
  come from the `MAHAM_APP_URL` secret or the person's saved app address,
  never from the call.
- `server_features()` answers every earlier name and `payroll_approvals`.
- Approval rows about pay runs were already private (`record_is_private` by
  `subjectTbl`, 20261102000000_tables_v16.sql), and so are their changes in
  the feed.
- Tests: `src/cloud/people-alerts-sql.test.ts` (off = as before, every role
  and a deputy, stale runs, the owner's own, done by whoever posts, older
  copies, upserts, deletes, privacy, no pg_net, the schedule, the files run
  twice, and the app's stand-ins), `src/alerts/payroll-approval.test.ts` and
  `src/db/payroll-approvals.test.ts`.

## Expiry alerts

`20261130000000_people_alerts.sql` also carries #18 of
docs/requirements-plan.md (lead times by type, reminders after expiry and the
new copy are the company's People settings, kept in its private
`peopleSettings` record: no rule of the server looks at them).

- `public.email_alerts.document_kinds text[]` (null: every kind, what every
  row has until someone chooses), checked against `company`, `vehicle`,
  `staff` and `client`. Added only when the email alerts table is there
  (without `20261007000000_email_alerts.sql` the file says so and goes on).
- `set_email_alerts` (the same four arguments) and
  `almailbooks.email_alerts_member_changed` are replaced with the email
  alerts file's definitions, with accountants: they may turn their own email
  on, and only someone who stops being an owner, admin or accountant loses
  their row. Saving there leaves `document_kinds` as it is, so older
  versions of the app keep someone's choice.
- `email_alert_scope(company) → table(document_kinds)` (members; the
  caller's own row) and `set_email_alert_scope(company, kinds) → void`
  (owners, admins and accountants; their own row, created off if there is
  none): an unknown kind is refused with 42501, an empty list with 22023;
  all four, or null, is kept as null. No new topic: older versions drop
  topics they don't know when they save (`src/cloud/supabase-api.ts`).
- `almailbooks.run_email_alerts()` is replaced with the email alerts file's
  definition plus: it also calls the function when a company wants its
  expiry reminders in Updates (`peopleSettings.expiryUpdates`) and someone
  there has the changes of the team on. `run_change_notifications` (above)
  leaves the reminders (`change_events.kind = 'document_expiry'`) out.
- The function (`src/alerts/server.ts`) emails owners, admins and
  accountants; per person it keeps the kinds chosen, drops employees' papers
  for whoever the owner gave no access to People, the other papers and
  deadlines for no access to Compliance, and invoices, bills and cheques for
  no access to Maham Books, and lists papers by kind. It reads
  the column as `to_jsonb(a) -> 'document_kinds'`: on a database without it
  (this file not run), every email is exactly as before.
  It reads renewals and the files marked as copies (`docKey`, `validUntil`,
  never content). `runExpiryUpdates` writes one `change_events` row per new
  reminder (no actor; private for employees' and confidential papers, then
  without names; `fold_key` `expiry:<key>` with `on conflict do nothing`).
- `server_features()` answers every earlier name, `payroll_approvals` and
  `document_alerts`. Nothing here touches `public.records`' triggers.
- Tests: `src/cloud/email-alerts-sql.test.ts` (before and after the file,
  accountants, every role, kinds, older saves, the file run twice, member
  changes, the hourly and 5-minute schedules), `src/alerts/server.test.ts`,
  `src/alerts/collect.test.ts`, `src/lib/expiry-reminders.test.ts` and
  `src/db/expiry-reminders.test.ts`.

## Employee letters

`20261130000000_people_alerts.sql` also carries #19 of
docs/requirements-plan.md. Templates and letters are the private
`letterTemplates` and `employeeLetters` records of `20261102000000_tables_v16.sql`
(staff and viewers read and write neither; `staff_can_write` is unchanged).
The company's switch is `"letters": true` on its `peopleSettings` record;
absent, as every company has it before, nothing here looks at a letter.

- `almailbooks.letters_on(company)`, `almailbooks.issues_letters(company)`
  (the owner, an admin, or an approver of `is_approver`),
  `almailbooks.letter_content(jsonb)` (a letter without `printedAt` and
  `updatedAt`, nulls stripped) and `almailbooks.issued_letter_kept` (what
  is stored over an issued or void letter): helpers, run by nobody but the
  functions below.
- `records_guard` (replaced with every rule it had) also looks at
  `peopleSettings` and `employeeLetters`. `peopleSettings`: only the owner or
  an admin changes `letters`; anyone else's copy keeps it as stored (a copy
  that has never heard of it never turns it off), and nothing is refused.
  `employeeLetters`, with letters on: a letter issued or void never goes back
  to a draft (42501, `almail:invalid`); once issued it stays as it was issued
  (number, date, text, signatory, stamp) and a void one stays void, with why
  and when: a copy sent again, an older one from another device too, only
  adds when it was last printed (the later of the two), and an issued one
  may be voided. Only someone who issues letters inserts one that isn't a
  draft, or voids an issued one (42501, `almail:permission`). Drafts are
  anyone's who may write them, and marking a letter printed changes nothing
  it says. Accountants ask through an approval request of kind `letter`
  (private, as its letter); the approver's device issues it.
- `can_delete_record` (replaced with every rule it had) never deletes a
  letter that is issued or void while letters are on: it is voided instead,
  so its number stays used. Drafts may go. While the letters are on, the
  `peopleSettings` record that holds the switch is deleted by the owner or
  an admin only (anyone else's delete would turn the letters off).
- Turning letters on gives a company made before letters its `letter`
  numbering rule on the company record, so even its first letter's number
  comes from `reserve_number`.
- Numbers come from `reserve_number(company, 'letter', date, min)` with the
  company's `letter` rule (`HR-{year}-{counter}`, yearly). Letters are never
  emailed.
- `server_features()` answers every earlier name and `employee_letters`.
- Tests: `src/cloud/employee-letters-sql.test.ts` (off exactly as before the
  file, owner, admin, deputy, accountant, staff and viewer, upserts, deletes,
  an older copy of the settings, the request of kind `letter`, the file run
  twice after the Phase 3 files, and the app's fakes against the server),
  `src/cloud/letter-roles.test.ts`, `src/cloud/letters-sync.test.ts`,
  `src/db/letters.test.ts` and `src/lib/hr/letters.test.ts`.

## Manpower costings

`20261207000000_staffing_costings.sql` (#3 part b of
docs/requirements-plan.md, Phase 5) adds one kind of record, `staffingCostings`
(the app's database version 17): a manpower costing that prices posts of
guards, cleaners and other staff from staff cost, with overhead and a margin.
The quote it makes is an ordinary `documents` record with sell prices only and
the costing's id as `costingId`; nothing else of the costing is on it. It
stops with "Run 20261130000000_people_alerts.sql first, then this file." and
changes nothing when that file hasn't run.

- `records_tbl_check` takes the full list of version 16 plus
  `staffingCostings`. Before the file the cloud refuses a costing (the app
  holds costings and their activity back until `server_features()` names
  `staffing_costings`). Once there are costings, the first file and
  `20261102000000_tables_v16.sql` stop with an error about `records_tbl_check`
  and change nothing.
- `record_is_private` (as in `20261102000000_tables_v16.sql`, with every rule
  it had) makes costings private, and activity of entity `costing` (even
  once the costing is gone). `can_read_v16_record` (as in that file) counts
  approval requests about costings as private too. `staff_can_write` is
  unchanged: it never named them, so staff and viewers never store them.
- A restrictive select policy, "Manpower costings: kept from staff and
  viewers", on `public.records` (costings and their activity) and on
  `public.deleted_records` (their deletion markers) keeps them from staff and
  viewers whatever `record_is_private` says, if an earlier file puts back one
  that doesn't know them. Every other record passes without a call.
- `record_app` (as in `20261116000000_super_admin_approvals.sql`) puts
  costings in Maham People, so a member the owner gave view only or no
  access to People doesn't store them. The four apps of the limits are
  unchanged.
- `change_kind` (as in `20261123000000_change_feed.sql`) counts a costing
  changed as a change to payroll and people data (private: it says only
  what happened).
- `server_features()` answers every earlier name and `staffing_costings`.
- The daily clean-up of deletion markers
  (`almailbooks-purge-deleted-records`) is scheduled when `pg_cron` is on,
  as in the v16 file, since that file can't run again once there are
  costings: turning `pg_cron` on and running this file is enough.
- Tests: `src/cloud/staffing-costings-sql.test.ts` (the guard, the file run
  twice after every earlier one, owner, admin, accountant, staff and viewer,
  deletion markers, People limits, an earlier `record_is_private` put back,
  every push an older version makes answered as before the file, and the
  app's fakes against the server), `src/cloud/costings-sync.test.ts`,
  `src/db/costings.test.ts` and `src/lib/hr/costing.test.ts`.

## The AI assistant's switch

`20261208000000_ai_assistant.sql` keeps the company's AI assistant switch
(`ai` on the company record, Settings → AI assistant; see
[`docs/ai-assistant.md`](../docs/ai-assistant.md)) for the owner and the
admins. It stops with "Run 20261207000000_staffing_costings.sql first, then
this file." and changes nothing when that file hasn't run. Until it runs,
only the app keeps the switch for them (its Settings page, and the device's
own check before it syncs), so the app works the same either way.

- `records_guard` is the one of `20261130000000_people_alerts.sql`, with
  every rule it has, and one more for the company record: anyone but the
  owner or an admin (`switches_ai`, kept the same as `switchesAi` in
  `src/cloud/roles.ts`) keeps `ai` as it is stored (`kept_key`, as the
  letters switch), by a push or `patch_company` alike, so an accountant
  neither turns it on nor off, and a copy from an older version, which has
  never heard of it, never turns it off. The rest of their change is stored
  as before.
- An admin the owner made Maham Books or Maham People view only for still
  changes it: it is not one of the books' settings
  (`company_books_changed`). Staff and viewers are refused as before (staff
  change only document numbers on the company record; viewers nothing).
- `server_features()` answers every earlier name and `ai_assistant`. The
  app waits for nothing on it: the device keeps the switch for the same
  people either way. The fakes (`src/cloud/testing/fake-cloud.ts`) keep it
  only once their server has `ai_assistant`, as the real one.
- The file replaces `records_guard` and `server_features()`, so it is run
  again after any earlier file that defines them is (the table in "Scripts
  by phase"); the health check names it then.
- The AI service (the Cloudflare Worker, `workers/ai-proxy`) doesn't read
  the switch: it answers everyone signed in, or, when its `COMPANY_ID` is
  set, only the members of the companies it names, and the app shows the
  assistant only with the switch on.
- Tests: `src/cloud/ai-assistant-sql.test.ts` (the guard, the file run twice
  after every earlier one, `records_guard` as the latest earlier one with
  only the rule added, `server_features()`, the owner, admins limited or
  not, an accountant by push and `patch_company`, an older version's copy,
  staff and viewers, and the app's fake against the server before and after
  the file), every other `*-sql.test.ts` (their rules, now through this
  file's `records_guard`), `src/cloud/health-check-sql.test.ts` (MISSING
  before it, OK after it) and `src/cloud/outbox.test.ts` (the device's own
  check).
