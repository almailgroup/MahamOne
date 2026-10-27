# Maham Tasks

Projects, tasks and real-time collaboration for your teams, part of Maham One. Built with
Next.js (App Router), TypeScript, Tailwind CSS, Supabase and a deliberately
monochrome interface.

**All five phases are complete.** The app is ready to deploy — see
[Deploying to Vercel](#deploying-to-vercel).

## Stack

| Layer      | Choice                                                     |
| ---------- | ---------------------------------------------------------- |
| Framework  | Next.js 15.5 (App Router, React 19, TypeScript)             |
| Styling    | Tailwind CSS v4 (CSS-first `@theme` configuration)          |
| Components | shadcn-style primitives on Radix UI, `lucide-react` icons   |
| Typography | Geist Sans / Geist Mono via `next/font`                     |
| Backend    | Supabase — Postgres, Auth, Row Level Security, Realtime     |
| Drag/drop  | `@dnd-kit` (pointer + keyboard sensors)                     |
| Deployment | Vercel                                                      |

## Features

- **Auth** — email/password sign-in, password reset, profile management.
  There is no self sign-up: admins add everyone from Team → Add teammate,
  which needs no email, and the database refuses any account an admin did not
  add. The very first account in an empty database becomes the admin.
- **Roles** — Admin, Manager, Team Member, enforced in the database.
- **Projects** — multi-project workspace with a switcher; create, edit, delete.
- **Tasks** — title, description, priority (Low/Medium/High/Urgent), status
  (To Do/In Progress/In Review/Done), due date, multiple assignees.
- **Kanban board** — drag and drop between and within columns, keyboard
  accessible, with order persisted.
- **List view** — filter by search, status, priority and assignee.
- **Audit history** — every task change recorded by database triggers,
  including trips to and from the bin.
- **Undo on delete** — a deleted task is hidden, not gone: Undo on the toast,
  and thirty days in the bin.
- **Realtime** — live comment threads and live task updates.
- **@mentions** — autocomplete in the comment box.
- **Attachments** — files (up to 25 MB, private storage, signed-URL download)
  and external links on any task.
- **Due dates with time of day**, stored as absolute instants and rendered in
  each viewer's own timezone.
- **Profile pictures** uploaded by each user, and **job positions** assigned by
  an admin from a preset list or free text.
- **Review gate** — assignees move work to In Review; only a manager or admin
  marks it Done.
- **General tasks** — assigned work belonging to no project, created by
  managers and admins.
- **Notifications** — live in-app bell for assignment, comments, @mentions,
  review requests and completions.
- **Reminders by email, Telegram or WhatsApp** — each person chooses their own
  channels and which events are worth interrupting them for.
- **Today** — the daily review: overdue, due today, in progress, awaiting
  review, follow-ups to chase now, and a per-person view of where the day is
  concentrated. Every row reschedules inline.
- **Quick reschedule** — move a due date from any task row without opening the
  form: later today, tomorrow, in 3 days, next Monday, in a week, or a picker.
- **Follow-ups** — give a task a date to chase it on and a note saying what to
  chase. The General tasks page has a follow-up tab split into due and coming
  up.
- **Dashboard** — six clickable tiles (To Do, Pending, In Review, Completed,
  Due Today, Overdue), each opening the matching task list at `/tasks`,
  overall progress,
  your assigned work, items needing attention, and per-user workload.
- **Project status** — whoever runs a project says how it is going: on track,
  at risk or off track, and a paragraph on why. Updates are kept, never
  edited, so "at risk three weeks running" is visible as such. On track is
  grey; the other two are amber, because amber means late or urgent work.
- **Projects needing attention** — top of the dashboard for managers and
  admins: projects called off track or at risk, projects with late work
  (even ones whose owner says they are on track), and projects with open
  work and no update in two weeks. Each is listed once with every reason that
  applies. When nothing qualifies the card is not drawn at all.
- **Reactions on comments** — 👍 ✅ 🙏 👀 🎉 instead of a reply that says
  "ok". No notification: telling somebody a colleague put a thumb on their
  comment is the noise this exists to remove.

The last three were taken from [Leantime](https://github.com/Leantime/leantime)
as ideas, not code — it is AGPL-3.0, and none of its source is in this
repository.

## Getting started

```bash
npm install
cp .env.example .env.local   # then fill in your Supabase credentials
npm run dev
```

Open http://localhost:3000. Until credentials are present the app serves the
landing page with a setup checklist, and authenticated routes redirect there
rather than erroring.

### 1. Create the Supabase project

Create a project at [supabase.com](https://supabase.com), then copy the values
from **Project Settings → API** into `.env.local`:

| Variable                        | Purpose                                     |
| ------------------------------- | ------------------------------------------- |
| `NEXT_PUBLIC_SUPABASE_URL`      | Project URL                                  |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Publishable anon key (safe for the browser)  |
| `NEXT_PUBLIC_SITE_URL`          | Base URL, used for auth email redirect links |

The `service_role` key is **never** used by this app. Every table is guarded by
Row Level Security instead, so the browser only ever holds a powerless key.

### 2. Apply the migrations

> **Use a Supabase project created for this app.** Running the script against a
> database that already belongs to another application will stop with an
> explanation — the schema lives in `public` and would collide. Check the
> project selector at the top of the SQL editor before running.

**Quickest — one paste.** Open the Supabase **SQL Editor**, paste the whole of
[`supabase/setup.sql`](supabase/setup.sql) and run it. That file is every
migration concatenated in order; it is safe to re-run.

**Or use the CLI**, which applies the migrations individually:

```bash
npx supabase link --project-ref <your-project-ref>
npx supabase db push
```

`setup.sql` is generated — the migrations are the source of truth. After adding
or editing one, regenerate with `npm run db:bundle` so the bundle cannot drift.

| Migration                         | Contents                                     |
| --------------------------------- | -------------------------------------------- |
| `…0001_initial_schema.sql`        | Enums, tables, constraints, indexes           |
| `…0002_functions_and_triggers.sql`| Auth helpers, signup hook, audit triggers     |
| `…0003_row_level_security.sql`    | RLS policies and table grants                 |
| `…0004_realtime.sql`              | Realtime publication, replica identity        |
| `…0005_protect_last_admin.sql`    | Prevents locking out the last admin           |
| `…0006_general_tasks_and_review_gate.sql` | Nullable project_id, review gate      |
| `…0007_attachments.sql`           | Attachments table, storage bucket and policies |
| `…0008_notifications.sql`         | Notifications table and trigger fan-out       |
| `…0009_member_view_only_details.sql` | Members are view-only on task details      |
| `…0010_fix_delete_task_audit.sql` | Lets a task with assignees be deleted         |
| `…0011_due_time_and_positions.sql`| due_at with time, job_title, avatars bucket   |
| `…0012_project_membership.sql`    | Projects become private to their members      |
| `…0013_follow_ups.sql`            | Follow-up dates and notes, audited            |
| `…0014_reminders.sql`             | Reminder preferences and outbound queue       |
| `…0015_members_see_only_assigned.sql` | Members see only their own tasks          |

### 3. Create the first user

In the Supabase dashboard, **Authentication → Users → Add user → Create new
user**, with *Auto Confirm User* ticked. **The first account in an empty
database becomes the admin**, so a fresh deployment is never locked out. That
is the only account the dashboard can make: from then on the database accepts
only accounts an admin added from the Team page.

### 4. Adding everyone else

**Team → Add teammate.** An admin fills in a name, an email and a role, and the
account exists immediately with a one-time password to hand over. Nothing is
emailed. This is the intended route for a workspace: access is granted by
whoever is responsible for it, rather than claimed.

A password somebody else chose and wrote down is only as private as wherever it
was written, so **the first sign-in lands on "Choose your password"** and the
app stays there until they have. The prompt is a flag on the account, cleared
the moment a password is set. Afterwards — and for anyone who simply wants a
new one — **Profile → Password → Change password** asks for the current
password and then the new one, without going anywhere near an email.

**Locked out?** An admin can issue a new password from Team → ⋯ → Reset
password, which works the same way: a one-time password to hand over, and the
account flagged so the next sign-in asks them to choose their own. An admin can
do this for anyone but themselves — their own password needs the current one,
on the profile page — and never learns the password anybody ends up using. It
is the one route that does not depend on email at all, which matters when the
alternative is a reset link and a mail quota.

**There is no self sign-up.** This is a company portal: people are added by
whoever is responsible for access. The app offers no way to register — an old
link to `/register` lands on sign-in — and the database enforces it underneath
(`…0034_close_self_registration.sql`): an account is accepted only if its
`app_metadata` names the admin who added it, which only the server's service
key can write. Somebody calling Supabase's sign-up endpoint directly with the
public key is refused, whatever the project's sign-up setting. As a second
lock, turn that setting off too: **Authentication → Sign In / Providers →
Allow new users to sign up**. Team → Add teammate keeps working either way.

Adding a user from the Supabase dashboard is refused once the first admin
exists, because the dashboard cannot set `app_metadata` on creation. Add people
from the Team page.

**Two-step sign-in.** Anybody can add an authenticator app — the iPhone's
Passwords app, Google or Microsoft Authenticator — from Profile → Two-step
sign-in. After that, signing in asks for the six-digit code as well as the
password, on every device.

Admins need it before they can add people, reset passwords or change roles;
the Team page says so until it is on. It cannot lock anybody out by being
switched on in the database: people who have not set it up are unaffected.

A password on its own is worth little once someone has an app. The app sends
such a session to the code page, and the database treats it as a member's
whatever the role (`…0038_two_step_sign_in.sql`), so a stolen admin password
used straight against Supabase gets a member's access and no more.

*Lost phone?* In Supabase → Authentication → Users, open the person, and
delete their factor under **Multi-Factor Authentication**; they can sign in
with the password again and set up a new app. TOTP is on by default in every
Supabase project (Authentication → Multi-Factor).

#### "email rate limit exceeded"

A Supabase project starts with a **shared, development-only mail service that
sends a handful of messages an hour**. Adding people sends nothing, so it never
gets in the way of onboarding — Team → Add teammate needs only
`SUPABASE_SERVICE_ROLE_KEY` in the server environment, the same key the
reminder dispatcher already uses.

Password resets do go through it, so until you **connect your own mail
service** in Supabase → Project Settings → Auth → SMTP Settings, "Forgot
password" stops working once the hour's handful is spent. (An admin's Team → ⋯
→ Reset password needs no email and always works.) If you are already sending
reminders through Resend, the same account works as SMTP: host
`smtp.resend.com`, port `465`, username `resend`, password your Resend API key,
and a sender on a domain you have verified.

## Authorisation model

**Projects are private to their members.** If you are not on a project you do
not see it, its tasks, its comments, its files or its history — it is simply
absent from your sidebar. Files are held to the same rule as the task they are
attached to, in storage as well as in the list
(`…0035_attachment_files_follow_task.sql`): a file can be downloaded only by
somebody who can see its task. Admins see every project so the workspace stays
administrable.

Membership is granted two ways, so assigning work can never produce a task its
assignee cannot open:

1. explicitly, by an admin or manager, from the **members** button on a project
2. automatically, when someone is assigned a task in that project

General tasks (belonging to no project) follow the same principle: assignees
and the creator see them, and so do managers and admins.

The **profile directory** stays readable workspace-wide — the assignee picker,
@mentions and the team page all need it, and a name and role are not the
sensitive part of a project.

On top of visibility, **writes** are gated by role:

| Action                                        | Admin | Manager      | Team Member             |
| --------------------------------------------- | :---: | :----------: | :---------------------: |
| Create / edit projects                        |  yes  | yes          | no                      |
| Delete a project                              |  yes  | own projects | no                      |
| Create tasks in a project                     |  yes  | yes          | **no**                  |
| Create **general** tasks                      |  yes  | yes          | no                      |
| See a task                                    |  all  | whole project | **only tasks assigned to them** |
| Edit title, description, priority, due date   |  yes  | yes          | **no — view only**      |
| Add or remove assignees                       |  yes  | yes          | **no**                  |
| Change a task's status                        |  yes  | yes          | assigned or created only |
| Move a task to **Done**                       |  yes  | yes          | **no — In Review only** |
| Reopen a completed task                       |  yes  | yes          | no                      |
| Reorder cards on the board                    |  yes  | yes          | yes                     |
| Delete a task                                 |  yes  | yes          | no                      |
| Attach files and links                        |  yes  | yes          | on tasks they work on   |
| Post comments                                 |  yes  | yes          | yes                     |
| Edit or delete comments (incl. their own)     |  yes  | yes          | **no**                  |
| See a project                                 |  all  | if a member  | if a member             |
| Add or remove project members                 |  yes  | yes          | no                      |
| Change roles                                  |  yes  | no           | no                      |
| Set job positions                             |  yes  | no           | no                      |
| Reschedule a due date                         |  yes  | yes          | no                      |
| Set a follow-up date and note                 |  yes  | yes          | no                      |
| Upload their own profile picture              |  yes  | yes          | yes                     |

**The member's lane.** Planning belongs to managers; members execute. A member
sees **only the tasks assigned to them** — a project they belong to appears in
their sidebar so they can reach their own work, but none of the team's other
tasks in it are visible, and neither are the comments or files on them. On a
task they have been given they can read it, move its status up to In Review,
comment, and attach files. They do not create tasks, delete them, rewrite what
they were asked to do, reassign it, remove themselves from it, or delete the
discussion around it.

Notes on how this is enforced:

- RLS is **enabled and forced** on all six tables, so a mistake in a
  `SECURITY DEFINER` function cannot quietly grant unrestricted access.
- Reads require both the `authenticated` role **and** a JWT subject. The `anon`
  role is granted nothing — there is no public read surface.
- Server Actions do **not** re-check roles. They let the database reject the
  write and translate the error, so there is exactly one source of truth.
- `task_activity` has a SELECT policy and no write policies or write grants,
  which is what makes the audit log genuinely append-only.
- Users can edit their own name and avatar but not their role: a trigger blocks
  self-promotion, and another prevents removing the last admin.
- **Task details are guarded by a trigger**, like the review gate, and for the
  same reason: the rule is about *which columns changed*, which a `WITH CHECK`
  expression cannot see. Status and board position are deliberately left
  writable — reporting progress is exactly what an assignee is for.
- The **review gate** is a trigger, not a policy. The rule is about a
  *transition* — a `WITH CHECK` expression cannot see the previous row, so it
  could not tell "a member is closing this task" from "a member edited the
  title of a task that was already closed".
- **Notifications are private**, the one exception to the read-wide model: a
  row is visible only to its recipient. They have no INSERT policy or grant,
  so nobody can forge one — rows come only from triggers.
- Attachment links are constrained to `http(s)` in the database, so a
  `javascript:` URL cannot be stored and later rendered as a link.

## Design system

The palette is a near-neutral cool grey, anchored on `#f3f3f4` in light mode
and `#2c2d32` in dark. Softer than pure black and white, which is easier to
read against for a full working day, and it buys the thing a white page cannot:
**panels can lift off the background**.


- **Surfaces** — three tones, always in the same order: chrome (sidebar and
  header) sits behind the page, the page behind its cards. In dark mode the
  page is the darkest tone and panels step *up* towards the light, so depth
  reads from the ramp with almost no shadow at all.
- **Separation** — 1px micro-borders, plus the tonal step between surfaces.
- **Status** — differentiated by badge fill weight, not colour.
- **Priority** — a four-bar greyscale severity ramp.
- **Overdue** — weight plus a dotted underline rather than red.
- **Themes** — light/dark via `next-themes`; all tokens redefined under `.dark`.
- **Elevation** — four restrained shadows, tinted with the palette's own ink
  rather than pure black, and all but removed in dark mode where tone already
  does the work.
- **Contrast** — every text/surface pair is checked against WCAG AA. The
  tightest is muted text on a card in dark mode at 4.92:1.
- **Motion** — one easing curve for the whole interface, and everything is
  disabled under `prefers-reduced-motion`.

Shared UI primitives keep pages consistent: `PageShell` and `PageHeader` give
every page one container and one title rhythm, `EmptyState` replaced four
hand-rolled variants, and each route has a `loading.tsx` skeleton shaped like
the page it precedes.

Press <kbd>⌘K</kbd> (or <kbd>Ctrl</kbd>+<kbd>K</kbd>) anywhere for the command
palette — every page, saved filter and project, one search away.

**The sidebar is resizable.** Drag its right edge, or focus the separator and
use the arrow keys (<kbd>Shift</kbd> for larger steps, <kbd>Home</kbd> and
<kbd>End</kbd> for the limits). Double-click or press <kbd>Enter</kbd> to
reset. The width is remembered per browser between 208px and 440px, and is
applied before first paint so it never snaps into place on load.

## Languages

The portal reads in English or Arabic. The selector sits in the header —
of the app, and of the sign-in screens — and the choice is kept in a `lang`
cookie, so it holds across sessions and devices that share a browser.

Choosing Arabic mirrors the whole interface rather than only swapping the
words: `<html dir="rtl">`, the sidebar on the right, the drawer sliding in
from the right, chevrons and arrows flipped, tables and forms reading
right-to-left. Every layout utility names its logical side (`ps-`, `me-`,
`text-start`, `border-e`) rather than a physical one, which is what lets one
set of components serve both directions. Arabic text is set in Noto Sans
Arabic, with Latin words inside a sentence — a container number, an email
address — still falling through to Geist. Dates are formatted for `ar-AE`
with Western digits, since that is how the company's own documents read.

Both languages name their locale — `en-AE` and `ar-AE-u-nu-latn` — and every
date is formatted in the timezone the `tz` cookie reports, never in whichever
one the machine doing the formatting happens to be in. That is not a
preference: a page is rendered twice, once on the server and once in the
browser, and if the two spell a date differently React throws the server's
HTML away and re-renders the whole tree (hydration error #418). Vercel runs
in UTC and answers `en-US`; a browser here is four hours ahead and answers
`en-GB`. `tests/unit/hydration-safe-dates.test.ts` pins the helpers that could
drift back.

The dictionaries live in `src/lib/i18n/`: flat, namespaced keys
(`"nav.dashboard"`, `"task.saveChanges"`) with English as the source of truth
and Arabic typed against it, so a key missing from either fails the build.
Server Components call `getI18n()`; client components call `useI18n()`.
Both hand back:

- `t(key, vars)` for a phrase, with `{name}` placeholders;
- `tn(key, count)` for anything counted — Arabic has six plural categories
  to English's two, and the dictionary carries each form it needs;
- `tm(message)` for a message that may be a key. Server Actions, validation
  and the database helpers return their messages as keys, so one action
  serves every language and the client shows it in the reader's.

Maham AI answers in the language it is asked in, and understands the
tracking questions in both.

To add a language: add its code to `LOCALES`, a dictionary file typed as
`Dictionary`, its label to `LOCALE_LABELS`, and — if it reads right-to-left
— its direction in `directionFor`. The unit test in `tests/unit/i18n.test.ts`
checks every key, placeholder and plural form is present.

## Project structure

```
src/
├── app/
│   ├── (app)/                  # authenticated shell
│   │   ├── dashboard/          # metrics
│   │   ├── projects/[id]/      # board + list workspace
│   │   ├── profile/
│   │   └── team/               # roster, admin role management
│   ├── (auth)/                 # login, password reset (no sign-up)
│   ├── auth/callback/          # email confirmation exchange
│   ├── error.tsx, not-found.tsx
│   ├── globals.css             # monochrome design tokens
│   └── layout.tsx              # fonts, theme provider, toaster
├── components/
│   ├── auth/  dashboard/  layout/  profile/  projects/
│   ├── tasks/                  # board, table, dialog, comments, mentions
│   ├── theme/                  # provider + toggle
│   └── ui/                     # Radix-based primitives
├── lib/
│   ├── action-result.ts        # typed Server Action results
│   ├── constants.ts            # status, priority, role vocabulary
│   ├── i18n/                   # English and Arabic dictionaries, translator
│   ├── mentions.tsx            # @mention parsing and rendering
│   ├── metrics.ts              # dashboard aggregation
│   ├── validation.ts           # zod schemas
│   ├── data/                   # queries + Server Actions
│   ├── realtime/               # live task subscription
│   └── supabase/               # clients, types, session middleware
└── middleware.ts

worker/                         # the Cloudflare Worker fronting Gemini
├── src/index.ts                # auth, the board as a prompt, the model call
├── wrangler.toml               # name, model; secrets never live here
└── README.md                   # deploy it in six steps
```

### How a request flows

1. `src/middleware.ts` runs on every non-static request and calls
   `updateSession()`, which refreshes the Supabase session cookie.
2. Unauthenticated visitors to a private route are redirected to `/login` with
   the intended destination preserved in `?next=`. Only relative single-slash
   paths are accepted back, so this cannot become an open redirect.
3. The `(app)` layout calls `requireProfile()`, a second gate behind the
   middleware.
4. Page queries run as the signed-in user, so RLS — not application code —
   decides what comes back.

## Scripts

```bash
npm run dev     # development server
npm run build   # production build
npm run start   # serve the production build
npm run lint    # eslint
```

Regenerate database types after changing the schema:

```bash
npx supabase gen types typescript --project-id <ref> --schema public \
  > src/lib/supabase/database.types.ts
```

## Database schema

- `profiles` — id, email, full_name, avatar_url, role, job_title, created_at,
  updated_at
- `projects` — id, name, description, created_by, created_at, updated_at
- `project_members` — project_id, user_id, added_by, added_at
- `tasks` — id, project_id, title, description, status, priority, due_at,
  follow_up_at, follow_up_note, position, created_by, created_at, updated_at
- `task_assignments` — task_id, user_id, assigned_at
- `comments` — id, task_id, user_id, content, created_at, updated_at
- `task_activity` — id, task_id, actor_id, action, field, old_value, new_value,
  created_at
- `task_attachments` — id, task_id, uploaded_by, kind (file|link), name,
  storage_path, url, mime_type, size_bytes, created_at
- `notifications` — id, user_id, actor_id, type, title, body, task_id,
  project_id, read_at, created_at
- `notification_preferences` — user_id, per-channel toggles and destinations,
  per-event toggles, due_soon_lead_hours
- `reminder_queue` — id, user_id, task_id, channel, kind, recipient, subject,
  body, status, attempts, last_error, dedupe_key, scheduled_for, sent_at

`tasks.project_id` is nullable: NULL marks a **general task**. Files live in
the private `task-attachments` storage bucket, reached only through short-lived
signed URLs.

Enums: `user_role` (admin, manager, member), `task_status` (todo, in_progress,
in_review, done), `task_priority` (low, medium, high, urgent).

Three additions beyond the original blueprint, each required by a requested
feature:

- **`task_activity`** — the task audit history has to be stored somewhere, and
  triggers writing it are what make the log tamper-resistant.
- **`tasks.position`** — Kanban drag-and-drop needs a persistable order. Cards
  are placed at the midpoint between their neighbours, so one drag rewrites
  exactly one row.
- **`updated_at`** — maintained by trigger, used for ordering and staleness.

`created_by` and `comments.user_id` are nullable with `ON DELETE SET NULL`, so
offboarding a user never cascades away their projects, tasks or comment threads.

## Removing somebody

Delete the account from **Supabase → Authentication → Users**. Everything they
owned follows: the profile, their assignments, their notifications and their
notes all cascade, and the things other people can still see — who created a
project, who uploaded a file — keep the record with the name dropped to null.

This used to fail with a 500, and the database log underneath it said
`insert or update on table "notifications" violates foreign key constraint
"notifications_user_id_fkey"`. The cascade was the whole story: deleting the
account deletes the profile, which deletes their task assignments, and every
assignment that goes fires the trigger that tells that person they have been
removed from a task — addressed to the profile that has just been deleted. The
more work somebody had been given, the more certainly they could not be
removed. `push_notification` now checks the recipient still exists, which is
what its own comment always claimed it did.

`20260916000021_notify_missing_recipient.sql` carries the fix, and it has to be
applied to the project before a delete will go through.

## On a phone

The app is used as a home-screen app on an iPhone, so the phone is a first
target rather than a reflow of the desktop. Two things were wrong with treating
it as a reflow.

**The chrome was sized for a 1440px screen.** The same page padding, the same
prose description under every title, the same wrapping filter bars — at 390px
that is a screenful of controls before the page shows you any work. Page
padding is tighter below `sm`, a page description is clamped to two lines
(they are read once and are noise every time after), a dashboard tile drops
the caption that restates its own label, an empty section on Today says so on
its own heading instead of opening a card to say it, and a row of filters
scrolls sideways rather than wrapping to three lines. Measured at 390px, the
page heights: Today 3062px → 1931, Tasks 7449 → 4632, General 6688 → 5625,
Team 1397 → 1034. The first block of content starts 14–35px higher on every
page.

**Controls were 40px.** Apple's floor is 44, and 40 is close enough to look
right in a screenshot and still be the wrong button often enough to notice.
Every control now reaches 44 on a coarse pointer. The checkbox is the
exception worth explaining: its box stays 18px, because inflating it would
look like a different control, and the *target* around it grows to 44 through
a pseudo-element. What a thumb has to hit and what the eye has to read are not
the same rectangle. Without it, a tap 10px off-centre opened the task instead
of selecting it — which is exactly the failure the rule exists to prevent.

Rows follow the same rule as the target: a task row, a task card and a Today
row are tappable end to end, not only on their title. The navigation inside
the phone drawer was the last thing under the floor, at 36px.

**The task dialog opened three hundred pixels down.** You tapped a task and
its title was above the top of the screen. Two things were doing it, and both
are worth not doing: the dialog focused the title field on open, which on a
phone raises the keyboard over half the screen for a field nobody opening a
task to read it wants; and the comment thread brought its newest comment into
view when it first loaded, and the nearest scrollable ancestor of a comment
thread is the dialog around it. Focus goes to the dialog itself now, and the
thread scrolls only when it *grows* — a first load is not growth. A comment
arriving while you read still pulls itself into view, which is checked.

iOS Safari zooms the page when you focus a field smaller than 16px and never
zooms back out; every input is 16px on a coarse pointer for that reason alone.
`viewport-fit=cover` plus `env(safe-area-inset-*)` keeps the navigation bar off
the home indicator, and any page that fills the screen subtracts the shell's
own header and navigation bar rather than guessing at a number.

## Team chat

One room for the workspace, under **Team chat** in the sidebar. Not a channel
list and not direct messages: everybody here already works together, and a
single room everyone can see is the thing a small team actually uses. The
table is modelled so a `room` column could be added later without moving the
messages.

Deliberately separate from a task's comments, which belong to that task and are
part of its record. A message here is conversation, and its author is allowed
to delete it.

Row-level security is the whole of the access rule and none of it is repeated
in TypeScript. Everyone signed in reads the room — a shared room whose messages
some members cannot see is not a shared room. The insert policy requires
`author_id = auth.uid()`, which is what stops a message being posted under
somebody else's name. Deleting is the author or an admin.

All of that was checked against a real Postgres before any of the UI was
written: a second member can read the room, cannot post as somebody else,
cannot edit or delete their messages, can delete their own, and an admin can
remove anything. An empty or whitespace-only message is refused by the table.

Worth knowing about the delete: RLS *filters* rather than refuses, so deleting
somebody else's message removes nothing and reports no error. The action counts
the rows, because without that a refusal is indistinguishable from success.

The room is server-rendered with the last hundred messages, so it reads before
any JavaScript runs, then stays live on the same realtime channel the board
uses. Realtime enforces RLS on everything it forwards, so subscribing cannot
show what a page load would have hidden.

Your own message appears the moment the server accepts it — the insert reads
the saved row back and the room shows that, rather than waiting for the
broadcast to come round. When the broadcast does arrive it is dropped as a
duplicate, matched on the row's id.

### Who is here, and who is typing

Both come from the channel's **presence**, not from a table. Neither is worth a
row: they are true for a few seconds and then they are not, and a table of them
would be a table of things that are already wrong. Presence is keyed by the
profile id, so somebody with the room open in two tabs is here once, and is
typing if either tab is.

Stopping typing has no event of its own — it is only ever the absence of one —
so it is a timer: two and a half seconds after the last keystroke, or the
moment the box is emptied, blurred, or sent from.

The member list sits on the trailing edge of the room: the right in English,
the left in Arabic, which is the same side of the reading order rather than the
same side of the screen. Online first, then alphabetical, because the point of
the column is to answer "who could see this now". Below `lg` there is no room
for two columns, so the same list opens over the conversation instead of
squeezing it. The presence dot is greyscale like everything else here — in this
palette the one colour means late work, and being online is not an alarm.

The room is exactly as tall as the screen leaves it, so the composer stays put
and the messages are the only thing that scrolls. What is subtracted is what
the app shell itself puts around a page — the header, and on a phone the
navigation bar and the home indicator — and everything inside is flexbox's
arithmetic rather than a guess at how tall a wrapped heading turns out to be.

New messages carry you along only if you were already at the bottom. Nothing is
more irritating in a chat than being dragged away from what you were reading
because somebody else said hello.

## The assistant in Arabic

It answers in the language of the question, not the language of the interface.
Somebody running the portal in English who types in Arabic is speaking Arabic,
and answering them in English is the assistant not listening.

Which language that is gets decided by the script the question *starts* in
rather than by counting letters. The board here is bilingual — Arabic
questions about tasks titled in English, English questions about projects
named in Arabic — and those two are mirror images, around a third of one
script and two thirds of the other. No ratio separates them. Which script
somebody opened their sentence in does, because that is the language they are
speaking; the other one is a name they are quoting. A question with no letters
at all falls back to the interface language.

For Arabic the model is asked for **Kuwaiti**, not Modern Standard — شنو rather
than ماذا, وايد rather than كثير, باجر for tomorrow — with two rules that
matter more than the vocabulary: do not caricature it, and never translate a
name. A task called "Ship the catalogue" is called that wherever the reader
looks for it.

The board the model reads from is written in the answer's language too, which
is the part that is easy to miss. A model reaches for the words it was shown,
so `in_review`, `high priority` and `Sep 17, 2026, 5:00 p.m.` left in the
table come back out in the middle of an Arabic sentence — none of it data,
all of it the Worker describing the board. It is Arabic when the answer is,
in the portal's own wording, with dates as month names rather than 17/09
because digits alone invite the model to do arithmetic on them. Names are the
exception and stay as written: a translated title is on no card.

That instruction lives in the Cloudflare Worker, so it takes a Worker deploy,
not just a portal one. The two can go in either order: a Worker that gets no
`replyIn` falls back to the interface language.

The offline brain — what answers when the Worker cannot be reached — now
recognises Kuwaiti as well as standard Arabic, because "شنو المتأخر" and
"ما هي المهام المتأخرة" are the same question and only one of them was
understood. Its sentences still come from the dictionary, so they are standard
Arabic; it is the floor, not the feature.

## Clicking on a person

A name and a face read as something you can act on. Almost none of them were:
the team list, the room's roster, a message's author, the workload card and
the header of a conversation were all text you could click at without result.

One menu now sits behind all of them — view their profile, message them
privately, copy their address, send them an email — so the answer is the same
wherever you found the person, and the caller decides what the target is
rather than having a button bolted on beside it. Messaging yourself is not
offered, because it is not a conversation and the database refuses it anyway.
Somebody whose account has been deleted leaves their messages in the room;
those stay text, because there is no longer a person behind them.

The profile it opens is a better view of what was already on screen, not a new
disclosure: the team page lists every field it shows.

The same principle for cards. A card that summarises a list opens that list —
overall progress goes to every task, "needs attention" to the overdue ones,
and each heading on Today to its own filter, which the task browser already
understood. Six rows of what may be forty should not make the way to the rest
somewhere else on the page.

Checked by walking the app and asking which blocks a reasonable person would
try clicking and nothing was listening to. The team page went from six to
none, the room from ten to three, and the three left are the page heading and
two continuation lines that have no name or face on them to click.

## Private messages

Separate from the team room, and the opposite of it. The room's read policy is
`using (true)` — everybody signed in sees everything. A conversation is
readable only by the people in it.

**There is no admin override anywhere in that migration, on purpose.** An
admin can delete a message from the shared room because somebody has to be
able to take down what should not have been posted in public. Nothing here is
public, so that reason does not apply, and "private unless an admin is
curious" is not private. An admin sees zero conversations, zero messages and
zero participants, and that is checked against a real Postgres rather than
asserted here.

Membership lives in `conversation_participants`, which has no idea how many
people it holds, so private groups can be added later without moving a
message. The ordered pair on `conversations` exists only to stop two people
ending up with two threads, and is null for anything that is not a pair.

A conversation is opened through `start_direct_conversation`, never by
inserting a row: the function decides who is in one, so a client cannot put
itself somewhere it was not invited, and two people starting a thread with
each other at the same moment get a single thread — the unique index decides
it and the loser reads the winner's row.

One trap worth naming. A policy on `conversation_participants` that checks
membership by selecting from `conversation_participants` is a policy that
calls itself. `in_conversation()` is `security definer` for that reason
alone: it steps outside row-level security to answer the one question every
policy in the file is built on.

Asking for a conversation you are not in returns nothing rather than an
error, and the page turns that into a 404. A conversation that does not exist
and one that is not yours look the same from outside — never "it exists, but
not for you".

The thread is bubbles rather than the room's flat list: a room needs a name on
every message because anybody might have written it, and two people do not —
which side it is on says who spoke. Unread counts are per conversation and add
up to a badge on the sidebar item, so a message that arrives while you are on
another page is visible without opening anything. A new message also writes a
notification, which is the only kind in this schema that points at a
conversation instead of a task.

The list is one round trip. Asked the obvious way it is a query for the
threads and then two more for each of them — the last thing said and the
unread count — which is forty-one round trips at twenty conversations, and the
unread total is wanted by the app shell on *every* page, not just this one.
`my_conversations()` answers all of it in one statement with a lateral join
per thread, and `unread_direct_count()` answers the badge with a single
number. Measured against the mock: ten round trips per page view became two,
and the two do not grow with the number of conversations.

Both functions are `security invoker`, not definer, so row-level security
still decides what comes back and neither can return a conversation the caller
could not have read anyway.

Not built: email or Telegram delivery for a private message. The in-app badge
and the notification bell are the whole of it.

## Reminders

Each person picks their own channels on **Profile → Task reminders**, and which
events are worth a message: assigned to me, due soon (with their own lead time),
overdue, or a follow-up coming due.

**The app works without any of this.** Unconfigured channels appear disabled in
the profile page with the reason, rather than silently doing nothing.

### How it works

Reminders are queued, not sent inline. `enqueue_task_reminders()` builds rows
from the current state of the tasks table; a scheduled call to
`/api/reminders/dispatch` drains the queue and calls the providers. That means a
provider outage cannot lose a reminder, retries are bounded and visible in
`reminder_queue.last_error`, and nothing is ever sent twice — every row carries
a `dedupe_key`. Changing a due date changes that key, which is exactly why a
rescheduled task legitimately reminds again, while re-running the scheduler ten
times does not.

Permanent failures (a blocked bot, a bad number) are not retried; transient ones
back off and are retried up to four times.

### Being assigned something arrives at once

Three of the four kinds are questions about the clock — due soon, overdue,
follow up — and can only be found by looking at the board against the time, so
a scheduled sweep is the only thing that could find them. Being handed a task
is not that: it is an event that has already happened, with a known recipient
and a message in the queue within milliseconds. It waited for the next sweep
anyway, because it shared the one conveyor belt, so work assigned at 2pm was
heard about the following morning.

The assignment path now drains that task's rows itself, through
`claim_task_reminders`, and leaves the rest of the queue to the scheduler. The
claiming is the only thing that differs between the two: `sendClaimed` does the
sending and the bookkeeping for both, so there is one implementation of what
happens to a claimed row rather than two that drift.

It cannot cost the assignment anything. The trigger has already written the
rows, so the work is safe before any provider is called; the send runs in
`after()`, once the response has gone, so nobody waits on Telegram to see the
board update; and `dispatchForTask` swallows its own failures and leaves the
rows for the daily sweep, because a provider outage must not turn a saved
assignment into a failed one.

### Server environment

All of these are **server secrets** — never prefix them `NEXT_PUBLIC_`, which
would compile them into the browser bundle. See `.env.example` for the full list.

| Variable | For |
| --- | --- |
| `SUPABASE_SERVICE_ROLE_KEY` | Required for any delivery. The dispatcher reads every user's queue, so it cannot run as any one of them. |
| `CRON_SECRET` | Authenticates the dispatcher. `openssl rand -hex 32`. |
| `RESEND_API_KEY`, `REMINDER_EMAIL_FROM` | Email |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_BOT_USERNAME`, `TELEGRAM_WEBHOOK_SECRET` | Telegram |
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_WHATSAPP_FROM` | WhatsApp |

### Scheduling

`vercel.json` registers a daily cron at 05:00 UTC — 08:00 in Kuwait, which
keeps no summer time, so the same hour all year.

The run keeps office hours (`src/lib/work-week.ts`, `src/lib/reminders/sweep.ts`):

- **Nothing goes out on a day off** — Friday, Saturday, or a company holiday
  from Settings. The next working morning's run looks at the board as it is
  then, so a task that went from "due soon" to overdue over the weekend is
  reported once, as overdue.
- **Nothing goes out before 07:00 or from 19:00**, Kuwait time, however often
  the dispatcher is called.
- **The morning summary** — one message per person listing what is overdue,
  due today and to follow up — goes out with the first run of a working
  morning, for whoever switched it on in Profile, and not after noon.
- **Being assigned something** is not held back: it is sent the moment it
  happens, because somebody at work just did it.
- Times in messages are Kuwait's (`public.company_time_zone()`).

Housekeeping (emptying the bin, trimming the error log) runs every time,
including days off.

**Vercel's Hobby plan only allows one run per day**, and only promises it
somewhere within the hour — enough for the morning, but "due in 2 hours" will
not be accurate. For finer granularity either upgrade to Pro, or drive it from
Supabase instead, which has no such limit; the office-hours rule above still
applies, so a run every 15 minutes is quiet at night and at weekends:

```sql
-- In the Supabase SQL editor, once.
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'dispatch-task-reminders',
  '*/15 * * * *',
  $$
  select net.http_post(
    url    := 'https://YOUR-APP.vercel.app/api/reminders/dispatch',
    headers:= jsonb_build_object('x-cron-secret', 'YOUR_CRON_SECRET')
  );
  $$
);
```

### Setting up each channel

**Email (Resend).** Create an account, verify the domain you will send from,
create an API key. The free tier covers a small team.

**Telegram.** Message `@BotFather`, `/newbot`, keep the token. Then register the
webhook once:

```bash
curl "https://api.telegram.org/bot<TOKEN>/setWebhook" \
  -d "url=https://YOUR-APP.vercel.app/api/telegram/webhook" \
  -d "secret_token=<TELEGRAM_WEBHOOK_SECRET>"
```

Each user then opens Profile → Task reminders → Connect Telegram, and sends the
one-time code to the bot. The bot replies to confirm. The chat id can only come
from Telegram itself, which is why this handshake exists.

Once linked, the bot also takes work. Anything sent to it that is not a
command is added as the sender's: a general task assigned to themselves for an
admin or manager, an item on a "Telegram" list in My List for a member — the
same rules as the app (`add_from_chat`, migration 42). The first line is the
title and the rest the detail; `!` in front makes it high priority; ending the
first line with *today* or *tomorrow* (or اليوم / باچر) sets it due at 17:00
Kuwait time, tomorrow meaning the next working day. `/help` in the chat says
the same.

The database holds that line rather than trusting the app to: a trigger pins
`telegram_chat_id` so only the webhook — which reaches Postgres with the
service role, carrying no user identity — may name a chat. Clearing it is
still yours, because that is what unlinking is. Without the trigger the update
policy on that table said only "your own row", which was true of the two dozen
preference columns beside it and let a hand-written request point the bot at
any chat at all. See `supabase/tests/telegram-link.sql`.

**WhatsApp (Twilio).** This one is not just an API key. For testing, join the
Twilio WhatsApp sandbox from the console and use the sandbox number. For real
use you need a WhatsApp Business account, a verified sender number, and — this
is the part that surprises people — **message templates approved by Meta**,
which takes days. Outside a 24-hour window since the user last messaged you,
only approved templates are delivered; free-text messages are rejected. Set
`TWILIO_WHATSAPP_TEMPLATE_SID` once you have one approved.

## Deleting a task

A deleted task goes to a bin, not out of existence. It disappears from every
list, count, search and board at once — that is done by the read policy, so
there is no query that can forget to exclude it — and the toast offers **Undo**
for ten seconds. The database keeps it for thirty days, with its comments,
files, history and assignees untouched, and the daily reminder run purges
whatever has sat there longer. Who may bin or restore is exactly who could
delete before: managers and admins.

There is no confirmation dialog any more. A question nobody reads protects
nothing; a bin does. `supabase/tests/trash-tasks.sql` checks the rules in a
real PostgreSQL — a member cannot bin a task, an admin's bin hides it from its
assignee, restore brings the comments back, and a ten-day-old task survives a
thirty-day purge while a month-old one does not.

## Calendar

**Calendar** in the sidebar shows every task you can see on the day it is due,
a month at a time. Placement happens in the browser, because only the browser
knows which local day an instant falls on — a task due at 01:00 on Tuesday
belongs on Tuesday whatever the offset. Overdue tasks are marked, done ones
struck through, and anything with no date is counted at the top rather than
silently left out.

Every square answers a click — empty ones included, where the answer is
"nothing due that day". It opens the day in a dialog listing what is due, on
every screen size. A square is too small to be the answer on its own: on a
phone it fits a count and nothing else, on a desktop three titles out of
however many there are. Those titles stay their own buttons and open the task
directly, which is the shorter path when the one you want is already visible.

The month is part of the address (`/calendar?month=2026-10`), so it survives a
reload and can be sent.

## Finishing with a project

Projects accumulated. A job delivered in 2026 sat in the sidebar next to live
work for as long as the portal ran, in every project picker, in the counts —
and the only way to be rid of it was to delete it, which takes its tasks, its
comments and its history with it.

Archiving is the other answer. **Manage → Archive project** takes it out of
the sidebar and the pickers and leaves everything else exactly where it was:
the project still opens, still reads, still has its work in it, and says at
the top that it is archived. Bringing it back is the same menu item.

**It is refused while anything in it is still open**, and the refusal says
how many — which is the difference between finishing with a project and
losing track of one. That check is in the database, not in the button, so it
holds however the project is archived.

Two queries where there was one: `getProjects` is what the sidebar, the
pickers and the dashboard ask, and leaves archived ones out; `getAllProjects`
is for the places that are about the projects themselves.

`supabase/tests/archive-projects.sql` checks the refusal and its count, that
archiving destroys nothing and the project still reads, that it is
reversible, and that a member cannot archive one at all.

## The steps inside a task

"Meet with Kuwait banks" has five documents to bring, and there was nowhere
to put them. They went into the description as prose, where nothing can be
ticked off and nobody can see how far along it is — or they went nowhere, and
somebody arrived without the signatory list.

A task now carries steps: add them in the dialog, tick them anywhere, and the
count rides along wherever the task is listed — "3/5" beside the due date,
which says more about whether something is nearly done than its status does.

**The steps carry no rules of their own.** Reading follows `can_view_task`,
writing follows exactly what an update to the task follows:
`is_manager_or_admin() or can_edit_task(...)`. That is deliberate, and it is
the second version of this: the first draft had a third rule and a
`security definer` function, so that somebody could tick a step off without
being able to rewrite it. The test for it could not find anybody in that
position — on a project, whoever can *see* a task is a manager, its author,
or assigned to it, and all three may edit it. A special case that protects
nobody is worse than none.

Only the flags are fetched with a task, never the text: a board of forty
tasks costs forty booleans rather than forty lists. The words are loaded when
the dialog opens.

Ticking is optimistic — a box that waits half a second to darken feels
broken. A refusal puts it back and says why.

`supabase/tests/task-checklists.sql` checks that somebody on the task sees
and ticks and plans, somebody with no part in it sees nothing and is refused
an insert outright, a manager in the project may change steps on a task they
are not on, and deleting a task takes its steps with it.

## Work that comes back

A task can repeat: daily, weekly, monthly or yearly, and every *n* of those —
fortnightly is "every 2 weeks". The control sits under the due date in the
task dialog, and the interval only appears once something is chosen, because
"every 1" beside "Does not repeat" is a question nobody asked.

The model is the simplest one that is honest: **a task carries its own rule,
and closing it opens the next one.** There is no series, no parent row and no
calendar of instances waiting to happen. What follows from that:

- exactly one open copy exists at a time, so the board never fills with the
  same job four times;
- the history is the closed instances themselves, each with its own comments
  and activity;
- editing the rule changes it from the next occurrence on, which is what
  somebody editing the task in front of them expects.

The next due date is advanced from the last one, not from today, and then
advanced again until it is in the future. A monthly task closed three months
late is next due next month rather than arriving already overdue. A task
abandoned for a year is bounded at 500 steps so nothing can spin.

The rule travels to the occurrence that is still open, so a closed task never
carries one. That is also what stops a second copy appearing if somebody
edits a task that is already done.

What it cannot say is "the first Monday of the month" or "weekdays only".
Those want a real calendar rule and a generator, and neither is worth its
weight until somebody asks for it.

All of that is one trigger in the database — `spawn_next_occurrence()` — so it
holds however the task is closed: the dialog, the board, a future API. It is
tested where it lives, in `supabase/tests/recurring-tasks.sql`, against a real
Postgres with the whole schema applied. Eleven checks; seven of them go red if
the trigger is dropped.

A repeat with no due date is refused twice over: by a check constraint,
because there would be nothing to advance, and by the form, so it reads as a
sentence under the field rather than as a constraint violation.

## My List

A private daily list, reached from **My List** in the sidebar. It is shaped
like the Notes app on a phone: a list of notes on one side, the note on the
other, one screen at a time below `lg` with a back button.

Each note holds a checklist and a free-text area. Ticking a line writes
immediately and optimistically; the title and text save themselves on a
700ms debounce rather than behind a Save button. Enter adds the next line,
Backspace on an empty line removes it.

### Sharing a list

A list is private until its owner invites somebody, one list and one person at
a time, from the **people icon** in the note's header. A shared list shows up
in the other person's My List with the owner's name under the title.

| | owner | collaborator | anyone else |
|---|---|---|---|
| read it | yes | yes | no |
| write its text, add, tick and remove lines | yes | yes | no |
| invite and remove people | yes | no | no |
| leave it | — | yes | — |
| delete it | yes | no | no |

Lines keep the name of whoever added them, and stay on the list when that
person leaves it.

A shared list updates live. Lines are separate rows, so two people ticking
different things never collide; the free-text area is one column saved on a
debounce, so a remote edit to it is applied only when the reader has nothing
unsaved — somebody mid-sentence keeps what they are writing.

### It is still genuinely private

`personal_notes` and `personal_note_items` remain the only tables in this
schema with no manager or admin override: there is no role that can read a
list it was not invited to, and an admin is nobody special here. Sharing did
not loosen that — it added one table of explicit invitations, and every policy
now resolves through it.

Because the whole thing rests on policies, it is tested where it lives:
`supabase/tests/shared-notes.sql` applies the entire schema to a plain
PostgreSQL and plays three people through it — the owner, somebody invited,
and somebody not. It asserts that an uninvited account sees zero rows, that a
collaborator can tick and write but cannot delete the list, take it over, or
invite anybody, that inviting yourself is refused, and that leaving takes
access away while leaving the lines you added behind. CI runs it on every
push; loosening a policy fails the build with the rule that moved.

Ticking an item bumps the parent note's `updated_at` through a trigger, so a
list you are working through floats to the top of the sidebar.

## Maham AI

The in-app assistant, reached from the button above the clock at the foot of
the sidebar. It answers questions about where work stands: what is overdue,
what is due today, what to pick up next, what is waiting in review, and how
the board is split by status. With an account that may change things, it can
also **propose** one: creating a task, moving one to another status, changing a
due date.

It opens **in the rail itself** rather than over the board — the sidebar
widens to make room and hands its column to the conversation, so you can read
a task while you ask about it. Closing returns the rail to navigation at its
previous width. While the assistant holds it, the rail can be dragged wider
than navigation allows (320–640px against 208–440px); that width is never
saved as the navigation width.

### What it can see

Nothing you could not already open yourself. `buildSnapshot` in
`src/lib/assistant/snapshot.ts` reads through the ordinary RLS-scoped queries, so
a member's snapshot holds only the tasks assigned to them and a manager's
holds their projects. The assistant has no permission logic of its own and no
service-role access; it cannot widen what you see.

The snapshot is built server-side on every question. The browser never holds
it, and never learns the Worker's address or its secret.

### What it can change

Nothing, on its own. The model returns a **proposal** — a tool name and some
arguments — and that is all it can do; the Worker has no database access of
any kind. The portal resolves the ids in it to names, shows a card with what
would happen, and waits.

Confirm runs it through `runAssistantAction` in
`src/lib/data/assistant-run.ts`, which parses every argument against a zod
schema and then hands off to `createTask`, `changeTaskStatus` or
`rescheduleTask` — the same Server Actions the ordinary buttons call. So the
review gate still stops a member short of Done, RLS still decides which rows
are visible, and the assistant cannot do anything the person asking could not
do by hand. That the proposal arrived through our own Worker buys it nothing:
this is a Server Action, so anyone signed in can call it with anything, and a
language model is only the likeliest source of a strange payload.

Someone who may not manage tasks is never offered the tools in the first
place, and their snapshot carries no project or teammate ids.

The card stays in the thread after a decision, showing what was agreed or that
it was left alone. A thread that silently rewrote itself would leave no way to
see what you had said yes to.

### Talking to it

The microphone beside the send button dictates into the box. It uses
`SpeechRecognition`, which is already in the browser: no key, no server, and
no audio passing through this app's code — what arrives is text. In Chrome the
recognition itself happens on Google's servers, which is worth knowing and is
not something this app arranges or can switch off.

It needs a secure context, so it works on the deployed site and on localhost,
and not over plain HTTP.

It also needs the microphone to be permitted by `Permissions-Policy`, which is
set in `next.config.ts`. That header shipped as `microphone=()` — an empty
allowlist, meaning nobody including this site — which was right until the
assistant grew a dictation button. A page denied by policy is not prompted and
then refused: it is never prompted at all, and `getUserMedia` fails with
`NotAllowedError`, which is the same error a person pressing Block produces.
So the button reported a blocked microphone, correctly, about a permission
nobody had ever been offered. It is `microphone=(self)` now; camera and
geolocation stay shut.

Where the browser has no recogniser the button is still there, disabled, and
says so when pressed. It used to be hidden, which meant the feature was simply
absent on some machines and present on others with nothing on screen to
explain the difference — a worse answer than a button that explains itself.
The rail and the mobile drawer render the same panel, so it is the browser
that decides this and never the screen size.

The language is asked for explicitly — `ar-AE` in Arabic, `en-US` in English —
and is deliberately not `localeTag()`. That one is `ar-AE-u-nu-latn`, a
formatting tag whose Unicode extension picks Latin digits; a recogniser will
not take it. Dictating Arabic into an engine left on English produces a
transcript nobody said.

While it listens, a voice-note meter sits above the box: a recording dot, a
waveform that scrolls with what you are saying, the elapsed time, and the
transcript updating under it. The point of the waveform is to answer the
question "is this thing on" without anybody having to say a test word — so it
is a real measurement, not an animation. The microphone is opened a second
time, purely to measure it: root mean square over the waveform, sixty times a
second, curved because speech into a laptop microphone is a small fraction of
full scale and a meter that reads 4% while somebody talks has not done its job.

It renders once. Everything after that is written to the bars' `transform`
inside an animation frame, and the level lives in a ref — sixty React renders
a second, of a panel holding the whole conversation, to move some bars is not
a trade worth making.

Four things about the behaviour:

- **It appends, and it never sends.** You can type half a question, speak the
  rest, and correct it before pressing enter. A transcript is a guess, and it
  goes in front of you like anything else the assistant proposes.
- **Settled phrases go in the box; the guess sits above it.** Interim results
  rewrite themselves word by word, and putting those in the textarea moves the
  caret under anyone trying to fix what has already landed.
- **Sound keeps it alive, not words.** The six-second deadline is pushed back
  by anything above the noise floor, because the recogniser only reports once
  it has settled a phrase — so a long or quietly-spoken sentence used to be cut
  off mid-breath at six seconds. The meter knows there is a voice in the room a
  great deal sooner. Driven against a stub, nine seconds of continuous talking
  now stays open and stops six seconds after the talking does.
- **The microphone closes itself.** On that deadline, on the stop button, when
  the panel closes, and on unmount — the capture stream's tracks stopped one by
  one and the audio context closed, because a `MediaStream` merely dropped
  leaves the browser's recording indicator lit.
- **The microphone is asked for, once, by `getUserMedia`.** That is the call
  which raises the permission prompt; on iOS the recogniser never does — it
  goes through the system speech service and fails at once when it has no
  permission. The two used to be independent, and the recogniser's failure
  tore the session down, which cancelled the request that was about to ask. So
  on an iPhone the prompt never appeared and the panel reported a blocked
  microphone that nobody had been offered. Now a failure while the prompt is
  still on screen waits for the answer, and if permission was the only thing
  missing the recogniser is started again — once, so a refusal cannot loop.
  Both halves share the one stream rather than asking twice.
- **A recogniser that stops at the first pause is reopened.** iOS ignores
  `continuous` and ends the session after one phrase, which is what made
  dictation there catch a sentence and then go deaf. While the person still
  wants to be listened to, a **new** recogniser is built after a short pause.
  Restarting the one that just ended, in the tick it ended in, is the obvious
  thing to write and does not work: the instance is spent and the microphone is
  still being let go of, so `start()` throws and the session closes on the first
  pause exactly as though none of this were here.

  The reopening is bounded, but not by counting reopens — somebody thinking for
  five seconds between sentences produces a run of perfectly ordinary short
  sessions, and a budget would end their dictation for them. What is counted is
  recognisers that end *sooner than they could have run*, five in a row, which
  is the shape of an engine that is broken rather than a person who is
  thinking.
- **Nothing waits to be told the session ended.** Teardown used to live only in
  the recogniser's `onend`, and Safari does not fire it reliably after a
  refused microphone: the panel sat on "Listening…" with the clock counting and
  a stop button that had nothing left to stop, and the only way out was a
  reload. An error now ends the session itself, `stop()` clears the state
  whether or not there is an engine left to stop, and a stop request that goes
  unanswered for 600ms is taken by force.

The meter is verified twice over. Once against a stub at the Web Audio
boundary, which pins the numbers: silence reads 0.12, quiet speech 0.52, loud
speech 1.00, and the microphone and audio context both come back to zero
however the session ends. And once end to end, with Chromium's fake capture
device fed a WAV of alternating loud and quiet passages, which drives the real
`getUserMedia`, the real audio graph and the real bars.

That second one was impossible until the header above was fixed, and the
failure was misread at the time as the container having no audio hardware. It
was this app refusing its own microphone.

`tests/unit/speech.test.ts` covers the language tags and the error mapping —
including that "no speech" and a deliberate stop both arrive as errors and
neither deserves a line of red text.

### Connecting Gemini

The assistant is named "AI assistant" everywhere it is read. Its code still
lives under `src/lib/assistant/` and its two environment variables are still
`ALMAIL_AI_WORKER_URL` and `ALMAIL_AI_WORKER_SECRET` — renaming those would mean
re-entering them on Vercel and in Cloudflare for no gain.

Until `ALMAIL_AI_WORKER_URL` is set, answers come from the local brain in
`src/lib/assistant/local-brain.ts` — deterministic, counted straight off the
board, and honest about the questions it cannot take. That brain stays on
afterwards as the fallback when the Worker call fails, so the panel is never
simply dead.

**The Worker is in [`worker/`](worker/), and its README is the step-by-step:**
get a key, deploy, set two variables on Vercel, redeploy. It fronts Gemini so
the API key lives on Cloudflare as a secret and never touches Vercel — where
anything this app holds is one `NEXT_PUBLIC_` typo away from the browser, and
the Worker exists precisely so the key never travels.

One thing worth knowing before pointing it at real work: on Gemini's **free**
tier Google uses what you send to improve its products, and human reviewers
may read it. Adding billing to the same key moves it to the paid tier, where
prompts are not used for training. See `worker/README.md`.

The Worker receives:

```jsonc
POST <ALMAIL_AI_WORKER_URL>
Authorization: Bearer <ALMAIL_AI_WORKER_SECRET>   // only if the secret is set

{
  "messages": [{ "id": "…", "role": "user", "text": "What is overdue?", "at": "…" }],
  "snapshot": {
    "viewer":   { "name": "…", "role": "manager", "canManage": true },
    "projects": [{ "id": "…", "name": "Gemellry" }],   // only when canManage
    "team":     [{ "id": "…", "name": "Sara Khan" }],  // only when canManage
    "locale":   "ar",                      // the language to answer in
    "timeZone": "Asia/Dubai",              // whose day "today" means
    "takenAt":  "2026-09-13T19:00:00.000Z",
    "tasks":    [{ "id": "…", "title": "…", "status": "todo", "priority": "high",
                   "project": "Gemellry", "dueAt": "…", "followUpAt": null,
                   "assignees": ["…"], "createdAt": "…" }],
    "counts":   { "total": 12, "todo": 4, "inProgress": 3, "inReview": 2, "done": 3,
                  "overdue": 1, "dueToday": 2, "unassigned": 1, "noDueDate": 4 }
  }
}
```

and must reply with `{ "text": "…", "action": … }`, where `action` is either
`null` or `{ "name": "create_task", "arguments": { … } }`. Anything else — a
non-2xx status, an empty reply carrying no proposal either, or no answer within
20 seconds — falls back to the local brain rather than surfacing an error.

`projects` and `team` are sent only to someone who may already pick from both
in the New Task form, and only because a tool call has to name them by id.

`locale` and `timeZone` are sent because neither can be inferred safely: a
model left to guess answers an English word typed into an Arabic panel in
English, and "what is due today" cannot be read off a list of instants without
knowing whose midnight to measure from.

The shapes above are `src/lib/assistant/types.ts`, which is deliberately free of
React and Supabase imports — the Worker imports that file directly rather than
keeping a copy, so the two ends cannot drift apart.

## How fast a page change is

Switching pages used to take three sequential round trips to Supabase before
anything could render, and each one is a network hop from the serverless
function: verify the session in the middleware, verify it *again* inside the
render, and only then fetch the page's data. The second and third waves were
both avoidable.

The middleware already verifies the session on every request, so it now writes
what it learned onto the request — `x-almail-user` and
`x-almail-password-change` — and `getAuthUser` reads those instead of asking
the auth server the same question a second time. Those headers are stripped
from the incoming request on every path through the middleware before it
writes its own, and the matcher covers every route, so a header a browser sent
can never be mistaken for one the middleware wrote. `tests/unit/middleware-identity.test.ts`
is the test of that, and of the refreshed session cookie surviving the rebuilt
response — a mistake there is a silent sign-out rather than a slow page.

The authenticated layout then asks for all five of its things at once. Only
the profile depends on knowing who is asking; the other four are scoped by RLS
and had been waiting on a question that was nothing to do with them.

Measured against a stubbed Supabase at 120ms a call, which is the shape of the
problem rather than the shape of any one network: **389ms → 269ms** median to
render a page on the server, and the dashboard 466ms → 309ms. Three waves down
to two. The remaining two are the middleware's own verification and then every
query at once, which is the floor without giving up server-side verification.

The sidebar and the bottom bar also now pass `prefetch` explicitly. Left alone,
Next fetches a dynamic route only as far as its `loading.tsx`, which is exactly
why the rail answered a click instantly with a skeleton and then sat on it: the
data had not been asked for until the click. `staleTimes.dynamic` in
`next.config.ts` keeps a prefetched page usable for twenty seconds so the work
is not thrown away the moment it is wanted — a page you have already visited
comes back in under 100ms with no network at all. What that costs is set out in
the comment there.

While a page genuinely is on its way, the nav item you clicked shows a spinner
in place of its own icon — `useLinkStatus` reports only for the link it is
rendered inside, so it can never appear on an item nobody clicked.

**Re-measured since, against the same stubbed Supabase at 120ms a call.** An
earlier attempt at this produced a number worth nothing: it waited for text
the page being *left* already showed, so every navigation looked instant. The
fix is to wait for something only the destination has.

Warm, a click costs **66–139ms** and one round trip — the page is already
sitting in the router cache. The one outlier is the first click after landing,
at 879ms, which is the hop competing with the rail's own prefetch burst rather
than the hop being slow. Arriving cold, content is on screen in **604–698ms**.

The burst is around 70 Supabase queries per page view, and that is the trade
the comment in `sidebar-nav.tsx` describes: server-side queries bought to keep
clicks instant. It is worth knowing where that lands. In the browser it is 2
requests and 35KB — the RSC payloads — against 1.26MB of JavaScript for the
same load, so it is not the phone's bandwidth being spent. It is Vercel
compute and Supabase queries, and it buys 1340ms → 66ms on a click.

Nothing here needed changing. The numbers are written down so the next person
to wonder does not have to set the harness up again: `tests/mock/supabase.mjs`
with `LATENCY_MS=120` is the whole of it.

## Installed on a phone

Added to the home screen, the app runs without Safari's chrome, which means the
notch and the home indicator are its problem rather than the browser's.

The viewport is `viewport-fit=cover`, and that is the part that was missing:
without it every `env(safe-area-inset-*)` reports `0px`. The navigation bar had
been padded away from the home indicator since the day it was written, and the
padding had always been zero — so the labels sat on the indicator and tapping
one was as likely to swipe the app away as to open the page.

Two custom properties in `globals.css` hold the standoff, so nothing has to
repeat the expression: `--safe-bottom`, which is the inset or a small gap,
whichever is larger, because a bar flush against the edge is unpleasant to tap
on any phone; and `--safe-top`, the notch or nothing. Everything that reaches
an edge pads itself back: the page header and the drawer's header carry the
notch, and the bar, the page and the drawer carry the indicator. Backgrounds
still run to the edge — it is only the content that stands off.

Measured at 393x852 with an iPhone's insets injected: the last tap target ends
34px above the bottom of the screen, the first header control starts 72px below
the top, and both come back to 6px and 13px on a device with no insets at all.
Each item in the bar is 79x56pt, above the 44pt Apple asks for.

Three more things a standalone app needs that a page in a browser does not:

- **No rubber band.** There is no browser chrome to bounce against, so dragging
  past the top swung the whole app down and showed a band of empty ground above
  the header, which reads as a broken layout rather than as a gesture.
  `overscroll-behavior-y: none` on the document.
- **The page holds still under the drawer.** `overflow: hidden` on the body is
  the usual answer and does nothing on iOS — opening "More" and dragging moved
  the board behind it, and closing left you somewhere you had not chosen to be.
  `useScrollLock` fixes the body at its offset and puts the position back.
  Except when the drawer closes *because a destination was tapped*: the
  position belongs to the page being left, and restoring it landed the new one
  part-scrolled. Tapping Calendar arrived 59px down a page that had never been
  scrolled, which is why `leaving` exists.
- **Chrome is not text.** A tap held a fraction too long on a navigation label
  selected the word, or raised the copy-and-share sheet over a link. The
  `chrome-touch` utility turns off selection, the callout and the wait for a
  second tap.

## When something goes wrong

Nothing captured it. A page that threw on somebody's phone left a line in a
Vercel log nobody reads, and the way a fault was discovered was that somebody
mentioned it — or did not, and worked around it for a month.

Faults now go into `app_errors`, and an admin sees them on their own profile:
what the message was, which route, browser or server, when, and how many
times. Grouped by message and route, because one fault hit forty times is one
line with a count rather than forty lines burying everything else.

Both halves are covered. `src/instrumentation.ts` exports `onRequestError`,
which Next calls for every error thrown while rendering or handling a
request — including the ones the boundary shows a generic page for, which is
exactly the set nobody was finding out about. The route-level boundary
reports what happened in the browser, alongside the console line it already
wrote, because the console is on the phone that hit the fault and that is the
one place nobody reads.

**Deliberately not a third-party service.** Sentry would mean an account, a
key pasted into a dashboard, and somebody's task titles leaving the country.
The portal already has a database with row-level security and an admin who
signs in every day.

The table is write-only for everybody: anybody signed in may report a fault,
and only as themselves, but there is no select policy at all — a message can
carry a fragment of whatever it failed on. Reading is through
`recent_errors()`, which raises for anybody but an admin. Rows are kept for
two weeks, swept by the same scheduled run that drains the reminder queue,
so there is nothing new to schedule.

`supabase/tests/error-log.sql` covers it: a fault cannot be reported as
somebody else, the table cannot be read with a session at all, a member is
refused the log outright, an admin gets it grouped with a count, and an old
row is swept while a recent one is not.

### Told on Telegram

Admins who have linked Telegram are also sent a short note when there is
something new — how many faults, on which pages, and how many reminders could
not be delivered, since the last note — with a link to the details on their
profile (migration 45, `src/lib/reminders/admin-alerts.ts`). It is sent by the
scheduled reminder run, with the service key it already holds, so it keeps
the same office hours as everything else that reaches a person: a fault at
midnight is in the first note of the working morning.

The note carries **counts and page paths, never a fault's own text**, which
stays in the portal for the same reason the table has no select policy.
Nothing new, no note; a note that reached nobody is not recorded, so the next
run tries again. `supabase/tests/admin-alerts.sql` checks the digest and that
nobody signed in — admins included — can read the log, write to it or ask
for the digest.

How soon a note arrives is how often the run is called: once a day on
Vercel's Hobby plan, every fifteen minutes with the `pg_cron` schedule under
[Scheduling](#scheduling).

## When a reminder cannot be delivered

A reminder gets four attempts. After that it was marked `failed` in a table
nobody reads — and that was the end of it. The person waiting to hear about
their work simply never heard, and the symptom was the portal seeming not to
bother rather than a wrong number or a permission somebody revoked.

Now the row records *when* it gave up (`failed_at` — `created_at` is when it
was queued, and an hour of retries can sit between the two), and two people
find out:

- **The person**, as a notification in the bell they already watch, naming
  the channel: "A reminder could not be sent to you on WhatsApp". The channel
  is named because that is where the fix is.
- **An admin**, on their own profile beside the channel settings, as a list
  of who, which channel, when and why — across the whole team.

An admin never sees the message. A queue row carries the reminder's subject
and body, and a body carries somebody's work; `reminder_failures()` returns
seven columns and none of them is it. The function raises for a non-admin
rather than returning an empty list, so "not allowed" can never be mistaken
for "nothing wrong".

The notification is written by the database, like every other notification
here — the table takes no inserts from anything holding a session, and the
wording lives beside the rest of them.

`supabase/tests/reminder-failures.sql` holds nine checks: a member sees
their own failure and not the one still being retried, a member is refused
the team's outright, an admin sees everybody's, the returned columns carry
no body, the person is told once, and a reminder still being retried tells
nobody. Adding a `body` column to what an admin gets turns the fourth of
those red.

## How much a page asks for

Every task view used to call one query: every task the viewer could see, no
limit, ordered by when it was created. That works until there are more tasks
than a response carries — and PostgREST caps a response whether or not the
query asks it to, Supabase's default being 1000 rows.

Past that cap the pages showed a slice, chosen by *creation* date while the
calendar places by *due* date, and said nothing at all. A task created last
year and due next month would simply not be on the calendar. No error, no
empty state, just a month that looked quieter than it was — and an assistant
answering from a board with holes in it.

So each page now asks for what it actually needs:

- **Calendar** fetches the six weeks its grid covers, and only that month.
  Turning the page fetches the next one and keeps it, so going back is free.
  The month stays in the address, so a reload or a shared link lands on it.
- **Today** asks for work that is not done, which is what its four sections
  are made of. Open work is bounded by how much is in flight rather than by
  how long the portal has been running.
- **The task browser** filters in the database rather than in the browser,
  and its chips are counted by the same function the dashboard tiles use — so
  a chip is right however many tasks there are, even when the list beneath it
  is one page of them.
- **The assistant** reads the open work and the database's own counts. It
  could previously state a total that was a row cap, with complete
  confidence, which is the worst way for a number to be wrong.

Where a bound is still reached, the page says so: "**first 500 — narrow the
filter to see the rest**" on the browser, "**showing part of this month**" on
the calendar. That is the point of the change. The cap was always there; what
it lacked was the honesty to mention it.

`TASK_PAGE_SIZE` exists so the end-to-end specs can drive the truncated case
with a dozen tasks instead of five hundred. The config starts a second copy
of the app with it set to five, because a small page size across the whole
suite would starve every other spec of the rows it looks for.

## When the connection drops

Installed to a home screen there is no address bar to explain a failure, so a
dropped connection used to look like the app being broken: a page that never
arrived, a save that quietly did nothing.

A service worker (`public/sw.js`) fixes the first half. A page is always
fetched from the network; when there is no network it serves `/offline`,
which is cached at install and says what has happened. Build assets are
cached too — they are content-hashed, so if one is in the cache it is still
correct.

**It deliberately caches no pages.** Every page here is somebody's private
workspace and a cache is shared by everyone who uses the device: cache
`/today` and the next person to open the app on a shared phone reads it,
signed in or not. Two things are kept — the offline page and the immutable
assets — and nothing else.

The second half is a line across the top of the app whenever the browser says
it is offline, because an interface that looks fine and silently stops saving
is worse than one that says so. It is monochrome: amber in this app means
late work, not "something is wrong".

### Work done with no signal is kept

Moving a task along (a swipe, the board, a member's status), putting it off
to the next working day, ticking a step and commenting are kept on the phone
when there is no connection, rather than failing (`src/lib/outbox.ts`,
`src/components/offline/outbox-provider.tsx`). They show as done at once — a
card says "Waiting to send", a comment sits in its thread marked the same —
and the offline bar counts them. They are sent in the order they were made
when the connection comes back, when the app returns to the front, or when it
is next opened; one the server refuses is reported by name, with the reason.

Each kept change records who made it, and is only ever sent for that person:
a phone handed to somebody else does not send one person's change as
another's. Several moves of the same task go as one, where it ended up. Other
edits — the task form, new tasks — still need the connection, and say so.

A request that fails for want of a connection is trusted over
`navigator.onLine`, which can say "online" when it is not.

Two rules in the routing exist only for this. `/offline` is public —
otherwise the one page meant to work without the network would need the
network to check a session. And `sw.js` is excluded from the middleware
matcher: a browser fetches a worker on its own schedule, sometimes with no
cookie, and a 307 to `/login` cannot be registered as a service worker. The
app would have had no worker and no offline page, and the browser would not
have tried again for a day.

## Notifications on the device itself

Reminders could reach somebody by email, Telegram or WhatsApp — three
different apps, none of them the one the work is in. The portal can now buzz
the phone it is installed on. iOS has allowed this since 16.4, for installed
web apps only, which is exactly how this one is used; on iPhone the control
says so rather than failing silently if the app has not been added to the
home screen.

Push is **per device, not per person**. Saying yes on the phone does not make
the laptop buzz, and turning the phone off leaves the laptop alone. The
profile page lists the devices that have agreed, names the one you are
holding, and lets any of them be removed.

It is a fourth channel on the existing queue rather than a parallel system,
so everything the other three already have — deduplication, retries with a
backoff, giving up after four attempts — applies unchanged. The lateral join
that fans a reminder out to channels now carries its own recipient: the other
three have exactly one address each, a person may have three devices.

The dedupe key gains the endpoint **for push only**, so every key already in
the queue keeps its exact spelling and nothing that has been sent is sent
again by the deploy that adds this.

A push service answering 404 or 410 means the device is gone — app deleted,
browser data cleared, permission revoked. That is not a transient failure to
retry for hours; the row is removed, which is the only thing that stops every
future reminder queueing a message to nowhere.

### The keys, and why they are not in an environment variable

A push has to be signed with the same key pair the browser subscribed with,
so it has to outlive a deployment. The usual answer is an environment
variable, which means somebody generates a secret, copies it out of a
terminal and pastes it into a dashboard — handling that ends with the private
half in a chat log.

Instead the pair is generated on first use and kept in `web_push_keys`: one
row, forever, in a table with row-level security on and **no policies at
all**. Nothing holding a user's session can read it; only the service role
the dispatcher runs as. The public half is handed to the browser by the app.
Nobody ever has to see the private one, which is the point.

`supabase/tests/web-push.sql` checks the parts that are easy to get wrong:
one person with two devices is queued twice, a second sweep queues nothing
again, a registered device whose owner has the channel off is not queued at
all, the email keys are byte-identical to what they were, and a signed-in
session reading the key table gets nothing.

## Signing in

### Forgotten passwords

**Sign in → Forgot password? → email → set a new one.** The link lands on
`/auth/callback`, which exchanges it for a session and forwards to
`/reset-password`. That page is therefore behind the middleware like any other
signed-in route: arriving without a valid link means no session, and the
middleware sends it to sign in, which is the correct answer.

The confirmation screen says the same thing whether or not the address has an
account — "if an account exists for …". Saying otherwise would hand anyone a
way to test which company addresses are registered, which is the same reason
sign-in refuses to say which half of the credentials was wrong.

**One thing to set in Supabase:** Authentication → URL Configuration →
Redirect URLs must include `https://your-domain/auth/callback`. Without it
Supabase refuses the redirect and the link dead-ends. Set `NEXT_PUBLIC_SITE_URL`
too — though the actions now fall back to the request's own origin rather than
to `localhost:3000`, so a missing variable no longer sends production links to
a machine the recipient does not have.

### The password field

Passwords can be shown. Typing one you cannot see is the main reason people
fail to sign in on a phone, where a long password and a soft keyboard make a
typo likely and invisible. The toggle sits outside the tab order, so Tab still
runs from the password straight to the submit button, and Caps Lock is called
out when it is on — the other half of the same problem, since a masked field
gives no way to notice.

The strength meter where a password is chosen rates length above cleverness. It is not a
percentage and not a score: those imply a precision nobody has, and they
reward `P@ssw0rd!` for containing a symbol. It never blocks anything; the
eight-character minimum is enforced by the schema on the server.

## Tests

```bash
npm test          # unit — vitest, ~2s
npm run test:e2e  # end-to-end — Playwright against a production build
```

CI runs both on every push and pull request, along with types, lint, the
build, a check that `supabase/setup.sql` still matches the migrations, and
every policy suite in `supabase/tests/` against a real PostgreSQL.

Those last two are worth a note, because both were broken for a while and in
the same way — a check that only looks where it is told. `setup.sql` had not
been regenerated in ten migrations, so the one file the section above tells a
fresh deployment to run would have built a database the app could not read a
task list out of. And the policy job named its suites one at a time, so eight
of the ten arrived with their migrations and were never added to it; they had
also been written to print a table of failures rather than to exit non-zero,
so running them would not have failed the build either. The suites are now
found by glob and a failed check raises.

### What is covered, and why those things

The unit tests are deliberately weighted towards bugs this codebase has
actually had, not towards a coverage number:

- **`dates` / `validation`** — the due-date timezone bug. The server now
  refuses the raw `2026-09-15T17:30` an `<input type="datetime-local">`
  produces, so the mistake cannot come back quietly.
- **`client-boundary`** — the `/team` crash. Every export of a `"use client"`
  module becomes a client reference when a Server Component imports it, and
  calling one on the server throws. TypeScript and ESLint both pass on that
  code, so it gets its own static check. It was verified by reintroducing the
  original bug and watching it go red.
- **`reminders`** — which failures are worth retrying, and that an
  unconfigured channel or a thrown request never wedges the dispatcher.
- **`attachments`** — that a filename cannot climb out of its task's folder
  and that a `javascript:` URL cannot be stored as a link.
- **`metrics` / `task-filters` / `sidebar`** — the arithmetic behind the
  dashboard, the filters and the resizable rail.
- **`i18n` / `server-messages`** — that the Arabic dictionary has every key,
  placeholder and plural form the English one has, and that no Server Action
  returns an English sentence where the client expects a key.
- **`hydration-safe-dates`** — that a date reads the same on the server as in
  the browser. Both the locale and the timezone are named rather than left to
  the runtime, because a task due at 22:00 UTC was "Sep 15, 10:00 PM" on
  Vercel and "16 Sept, 2:00" in Dubai, which cost the whole page its
  server render.

The end-to-end tests cover the pages reachable without a session, plus two
rules that apply everywhere and keep getting broken by accident: no page may
scroll sideways, and no control on a touch device may be smaller than a thumb.

The signed-in ones run against `tests/mock/supabase.mjs`, a stand-in that
answers like PostgREST and GoTrue and keeps what it is told, so a spec can
create a task and then find it. It is started by the Playwright config
alongside the app — including the build, because `NEXT_PUBLIC_SUPABASE_URL`
is inlined into the browser bundle and a build made against a real project
would keep talking to it however it is started.

Sign-in hands back a token for whichever address is typed, so a spec signs in
as a member and *is* one; that is what makes checking a role-shaped rule
possible. The workspace it serves is `tests/mock/seed.mjs`: six people, three
projects and a month of tasks around a fixed day, so "three are overdue" is
still true next year.

**The mock is not an authority.** It enforces nothing — every request is
answered as the signed-in user. Row-level security is verified where it
lives, against a real Postgres (`supabase/tests/`), and never against the
production project. A spec passing here proves the interface works, not that
the rules hold. Where a spec touches something RLS decides — the review gate,
a conversation that is not yours — it says so in a comment and checks only
that the interface states the rule rather than letting the database refuse a
button press.

What they cover: creating a task and finding it after a reload, an admin
closing one, a member being offered In Review but not Done, a manager being
offered Done, a repeat rule surviving a save, a repeat with no date being
refused in words, opening and adding to a private thread, a thread that is
not yours reading as missing, a calendar day opening whether or not anything
is due, the command palette knowing every destination the sidebar has, and
the service worker registering, caching the offline page and serving it when
the network is cut.

Point `BASE_URL` at a staging deployment to run the same specs against real
data instead; nothing in them depends on the mock being the thing answering.

### What is not covered

Two paths have never been exercised end to end, here or anywhere:

- **File and avatar uploads.** The bytes go straight from the browser to
  Supabase Storage, which needs a live bucket. The path-building and
  validation around them are tested; the upload itself is not.
- **Reminder delivery.** There are no provider credentials in CI and there
  should not be. Everything around the network call is tested with a stubbed
  `fetch`; no real email, Telegram message or WhatsApp has ever been sent by
  a test.

Both are worth one deliberate manual pass after deploying: attach a real file
to a task and download it again, set a profile picture, and set a due date a
few minutes out with each reminder channel switched on.

## Keeping it running

### Is it up?

`/api/health` answers without signing in, for an uptime monitor:

```json
{ "status": "ok", "database": "ok", "schema": 46, "expected": 46, "missing": [], "latencyMs": 38, "commit": "7676a87" }
```

- **ok** — the database answers and every migration this code needs has been
  run.
- **degraded** (still HTTP 200) — the database answers but is behind the code:
  `schema` is the newest migration run, `expected` what this code wants, and
  `missing` any older one that was skipped. Vercel deploys the moment a commit
  lands and the migrations are run by hand afterwards, so this is the commonest
  way for the portal to be half working. After running migrations, open
  `/api/health` and check it says `ok`.
- **down** (HTTP 503) — the database cannot be reached.

It is asked with the public key alone and says nothing about anybody: table
and function names, a time, the deployed commit (`portal_health()`, migration
46, checked by `supabase/tests/portal-health.sql`).

Point a free uptime monitor at it — UptimeRobot, Better Stack and the like all
have a free tier — every five minutes, with a **keyword** check for
`"status":"ok"` rather than a plain status check, so a database left behind
the code alerts too. Have it alert by email, or by Telegram where the monitor
offers it.

Faults inside the app are reported separately, to the admins on Telegram (see
[Told on Telegram](#told-on-telegram)).

### Backups

**On Supabase's Pro plan** backups are automatic: daily, kept seven days,
under Database → Backups (point-in-time recovery is an add-on). That is the
simplest answer, and it covers files too.

**On the free plan there are no backups you can download**, so the repository
has a weekly one: `.github/workflows/backup.yml`, Sunday 04:30 Kuwait time. It
dumps the roles, schema and data with Supabase's own CLI, encrypts them with
a passphrase only you hold, and keeps the result as a workflow artifact for 30
days. It does nothing until it is set up:

1. In Supabase, open **Connect** and copy the **Session pooler** connection
   string (GitHub's runners need the pooler; the direct address is IPv6 only).
   Put your database password into it.
2. In GitHub, **Settings → Secrets and variables → Actions → New repository
   secret**: `SUPABASE_DB_URL`, that string.
3. Make up a long passphrase, save it in your password manager, and add it as
   a second secret, `BACKUP_PASSPHRASE`. Without it a backup cannot be opened
   — by anyone, including you — so keep it somewhere that is not this
   repository, a chat or an email.
4. **Actions → Weekly backup → Run workflow**, and check it finishes green with
   an artifact attached.

To open one, download the artifact, then:

```bash
gpg --decrypt almail-2026-10-18.tar.gz.gpg | tar -xzf -
# backup/roles.sql, backup/schema.sql, backup/data.sql
```

**Try a restore once a quarter** — a backup nobody has restored is a hope.
Create a scratch Supabase project, and with its Session pooler string:

```bash
psql "$SCRATCH_DB_URL" \
  --single-transaction --variable ON_ERROR_STOP=1 \
  --file backup/roles.sql --file backup/schema.sql \
  --command 'SET session_replication_role = replica' \
  --file backup/data.sql
```

Then point a local copy of the app at the scratch project and sign in. Delete
the scratch project when done.

**Files attached to tasks are not in the database**, so not in these backups;
they live in Supabase Storage. Download the `task-attachments` and `avatars`
buckets from the dashboard now and then, or move to Pro.

## Deploying to Vercel

1. **Apply the migrations** to your Supabase project (see above) — do this
   first, or the deployed app will have nothing to talk to.
2. **Import the repository** at [vercel.com/new](https://vercel.com/new).
   Next.js is detected automatically; `vercel.json` pins the framework, build
   and install commands, and region.
3. **Add environment variables** under **Settings → Environment Variables**, for
   Production *and* Preview:
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
   - `NEXT_PUBLIC_SITE_URL` — your deployment URL, e.g.
     `https://almailgroup-tasks.vercel.app`
   - Optionally the reminder secrets above — see [Reminders](#reminders)
4. **Configure Supabase auth URLs** under **Authentication → URL
   Configuration**:
   - *Site URL*: your production URL
   - *Redirect URLs*: add `https://<your-domain>/auth/callback`, and
     `https://*-<your-team>.vercel.app/auth/callback` if you want preview
     deployments to handle email confirmation
5. **Deploy**, then create the admin account in the Supabase dashboard — see
   [Create the first user](#3-create-the-first-user).

Set `NEXT_PUBLIC_SITE_URL` to the deployment's own URL. It is what password
reset emails link back to, so a stale value sends people to the wrong host.

### Deployment protection and the manifest

Vercel's **Deployment Protection** puts every deployment-specific URL — the
long ones with a build hash, `…-5rjqd1vk8-…vercel.app` — behind its own SSO,
even when the same build is live on the production domain. Anything requested
without Vercel's cookie is redirected to `vercel.com/sso-api`.

A web app manifest is normally fetched with cookies *omitted*, so it was being
redirected off-origin and refused by CORS:

```
Access to manifest at 'https://vercel.com/sso-api?url=…'
(redirected from '…/manifest.webmanifest') has been blocked by CORS policy
```

The link in `src/app/layout.tsx` therefore carries
`crossOrigin="use-credentials"`, which sends the cookie and stops the redirect.
That is also why the manifest is a static file in `public/` rather than an
`app/manifest.ts` route: the Metadata API renders the link itself and gives no
way to set the attribute.

### Regions

**Not pinned.** `vercel.json` deliberately carries no `regions` key: on the
Hobby plan that property stops deployments from being created at all — silently,
with nothing appearing in the deployments list to explain why.

The Supabase project is in `eu-central-2` (Zurich), so the ideal placement is
`zrh1`. Reaching it needs a Pro plan, where the region can be set under
**Settings → Functions → Function Region**. Until then functions run in
Vercel's default region and each query crosses to it and back — noticeable,
but not worth breaking deployments over.

