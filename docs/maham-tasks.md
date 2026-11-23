# Maham Tasks

Maham Tasks is the task management portal, kept in this repository in the
folder [`Maham Tasks`](../Maham%20Tasks). It is its own app, with its own
design and features (a Next.js app; its
[README](../Maham%20Tasks/README.md) describes it in full), and it lives at
its own address, **tasks.mahamone.com**.

It is part of the Maham One platform:

- **Maham One's database.** Its tables live in Maham One's Supabase project,
  in their own schema, `tasks`, beside Maham One's data and changing none of
  it ([`supabase/migrations/20261212000000_maham_tasks.sql`](../supabase/migrations/20261212000000_maham_tasks.sql)).
- **One account.** Everyone signs in to both apps with the same Maham One
  email and password. Being in Maham Tasks is up to its admins: a Maham One
  account they haven't invited reaches nothing of it.
- **No master key.** Maham Tasks' server (reminders, Telegram, push) holds
  only its own secret, `TASKS_SERVER_SECRET`, which opens its own functions
  and none of Maham One's data. Maham One's secret key is never used.
- **Its own Vercel project**, built from this repository's `Maham Tasks`
  folder. A Vercel project runs one app, so Maham One and Maham Tasks are two
  projects in the same team, from the same code.
- **Its own AI Worker** in Cloudflare, which keeps running as it is.

## What runs automatically

- **Checks** (`.github/workflows/maham-tasks.yml`): types, lint, unit tests,
  the build, the database rules against a real PostgreSQL (built from the
  script above), and the end-to-end tests. They run when a push to `main`
  changes the `Maham Tasks` folder or the script. Maham One's own tests
  (`src/cloud/maham-tasks-sql.test.ts`) run the script after all of Maham
  One's and check that nothing of Maham One changes.
- **Weekly backup** (`.github/workflows/maham-tasks-backup.yml`): optional, a
  copy of the `tasks` schema only, every Sunday, encrypted, kept for 30 days.
  It does nothing until its two secrets are added (see "Backups" in the Maham
  Tasks README).
- A push that changes only Maham Tasks doesn't rebuild or redeploy Maham One,
  and Maham One's build skips the folder.

## Bringing it back: the owner's steps

Its old Supabase project and old Vercel project are gone, so Maham Tasks
starts again empty, on Maham One's database. Do these in order.

### 1. Supabase: the database script

In Maham One's project (the one at `gagdyhintrxdkiqhahzh.supabase.co`):
**SQL Editor → New query**, paste the whole of
[`supabase/migrations/20261212000000_maham_tasks.sql`](../supabase/migrations/20261212000000_maham_tasks.sql)
(on GitHub: **Copy raw file**), and **Run**. It worked when Results shows a
small table with one column, `assert_enum`, and an empty row (an error shows in
red instead). To be sure, run this in a new query: it should say 33 and 19.

```sql
select
  (select count(*) from pg_tables where schemaname = 'tasks') as tables,
  (select count(*) from pg_proc
    where pronamespace = 'tasks'::regnamespace and proname like 'srv\_%') as server_functions;
```

It is safe to run again, and it needs none of Maham One's other scripts. Run
`supabase/health-check.sql` after it if you like: it reads the same as before.

### 2. Supabase: let the API serve it

**Project Settings → Data API → Exposed schemas**: add `tasks`, then
**Save**. Leave `public` and the others as they are.

### 3. Supabase: you as the first admin, and the server's secret

**SQL Editor → New query**, with the email of your Maham One account:

```sql
select tasks.add_first_admin('you@example.com');
```

Then a new query:

```sql
select tasks.new_server_secret();
```

It shows a long code, once. Copy it for step 5 (`TASKS_SERVER_SECRET`). Don't
paste it into a chat or an email. If it is ever lost or seen, run the line
again and replace it in Vercel: the old one stops working at once.

### 4. Supabase: let sign-in emails come back to Maham Tasks

**Authentication → URL Configuration → Redirect URLs → Add URL**:
`https://tasks.mahamone.com/**`. **Don't change the Site URL**: it is Maham
One's, and every Maham One email uses it.

### 5. Vercel: a project for Maham Tasks

In the **Almail Group** team: **Add New → Project**, import
`almailgroup/MahamOne`, and set **Root Directory** to `Maham Tasks`. Before
**Deploy**, open **Environment Variables** and add:

| Name                            | Value                                                                                          |
| ------------------------------- | ---------------------------------------------------------------------------------------------- |
| `NEXT_PUBLIC_SUPABASE_URL`      | `https://gagdyhintrxdkiqhahzh.supabase.co`                                                     |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Maham One's **publishable** key (Supabase → Project Settings → API Keys), never the secret one |
| `NEXT_PUBLIC_SITE_URL`          | `https://tasks.mahamone.com`                                                                   |
| `TASKS_SERVER_SECRET`           | the code from step 3                                                                           |
| `CRON_SECRET`                   | a long random code you make up (it lets Vercel's daily reminder run in)                        |

Reminders by email, Telegram or WhatsApp need their providers' keys as well
(see "Reminders" in the Maham Tasks README); the app works without them.

Then **Deploy**, and under the project's **Settings → Domains** add
`tasks.mahamone.com`. Your DNS record for `tasks` can stay as it is; if Vercel
asks for a different one, change it at your domain provider as it says.

### 6. Try it, then invite the team

1. Open tasks.mahamone.com and sign in with your Maham One email and
   password: you are the admin.
2. **Profile → Two-step sign-in**: add an authenticator app (the iPhone's
   Passwords app, Google or Microsoft Authenticator). Maham Tasks asks for it
   before an admin can invite anybody. From then on, signing in to Maham Tasks
   asks for its six-digit code too.
3. **Team → Add teammate**, with each person's Maham One email. They join the
   first time they sign in to tasks.mahamone.com with that account (someone
   without one makes it at Maham One with that email first). An invite lasts
   30 days; the Team page lists the ones not used yet, with **Withdraw**.

Someone signed in to Maham One who wasn't invited sees "Your Maham One account
is not in Maham Tasks yet".

Reminders on Telegram need one more step once it is deployed: see "Setting up
each channel" in the Maham Tasks README.

### 7. Archive the old repository

If not done yet: on GitHub, open
`almailgroup/almailgroup-task-management-portal` → **Settings → Archive this
repository**. It stays readable, but nobody can change it by mistake.
