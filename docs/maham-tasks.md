# Maham Tasks

Maham Tasks is the task management portal, kept in this repository in the
folder [`Maham Tasks`](../Maham%20Tasks). It is its own app, with its own
design and features (a Next.js app; its
[README](../Maham%20Tasks/README.md) describes it in full), and it lives at
its own address, **tasks.mahamone.com**.

For now it keeps everything it had before it moved here:

- **its own Supabase project** (database, accounts and files). Merging it into
  Maham One's Supabase project is a later step;
- **its own Vercel site**, which now builds from this repository's
  `Maham Tasks` folder;
- **its own AI Worker** in Cloudflare, which keeps running as it is.

## What runs automatically

- **Checks** (`.github/workflows/maham-tasks.yml`): types, lint, unit tests,
  the build, the database rules against a real PostgreSQL, and the
  end-to-end tests. They run when a push to `main` changes the `Maham Tasks`
  folder. These are the same checks it had in its old repository: the copies
  inside the folder (`Maham Tasks/.github/workflows/`) don't run here,
  because GitHub only runs the workflows at the root of a repository.
- **Weekly backup** (`.github/workflows/maham-tasks-backup.yml`): a copy of the
  Maham Tasks database every Sunday, encrypted, kept for 30 days. It does
  nothing until its two secrets are added (step 4 below).
- A push that changes only Maham Tasks doesn't rebuild or redeploy Maham One,
  and Maham One's build skips the folder.

## Moving it here: the owner's steps

Do them in this order. Nothing changes for the people using Maham Tasks: the
same accounts, the same data, and the old address keeps working too.

### 1. Vercel: build the existing site from this repository

1. Sign in at [vercel.com](https://vercel.com) and open the project of the
   task portal (not Maham One's).
2. **Settings → Git**: disconnect `almailgroup-task-management-portal`, then
   connect **`almailgroup/MahamOne`**. If it isn't in the list, choose the
   option to adjust the GitHub app's permissions and give Vercel access to
   that repository.
3. **Settings → Build and Deployment → Root Directory**: type
   `Maham Tasks` (exactly, with the space) and save.
4. Leave the environment variables as they are.
5. **Deployments**: redeploy the latest one, or wait for the next push. Check
   the new deployment shows commits from `MahamOne` and finishes as Ready.

Optional: under **Settings → Git → Ignored Build Step**, you can make Vercel
build Maham Tasks only when its folder changes. Without it, every push to the
repository also rebuilds Maham Tasks, which is harmless.

### 2. The address tasks.mahamone.com

1. In the same Vercel project: **Settings → Domains → Add**, type
   `tasks.mahamone.com`.
2. Vercel shows the DNS record to add (usually a `CNAME` named `tasks`). Add
   it wherever mahamone.com's DNS is managed. If that is Vercel itself, it is
   added for you.
3. Wait until Vercel shows the domain as valid, then open
   https://tasks.mahamone.com and sign in.
4. **Settings → Environment Variables**: change `NEXT_PUBLIC_SITE_URL` to
   `https://tasks.mahamone.com` (Production and Preview), then redeploy.
   Password reset emails link to this address.

### 3. Supabase: let sign-in emails return to the new address

In the **Maham Tasks** Supabase project (not Maham One's):
**Authentication → URL Configuration**.

- **Site URL**: `https://tasks.mahamone.com`
- **Redirect URLs**: add `https://tasks.mahamone.com/auth/callback`. Keep the
  old address there until nobody uses it.

The old `vercel.app` address keeps working, so the daily reminders and the
Telegram bot keep working without changes. Moving them to the new address is
optional; the [Reminders](../Maham%20Tasks/README.md#reminders) section of the
Maham Tasks README shows where each one is set.

### 4. GitHub: the weekly backup

In this repository: **Settings → Secrets and variables → Actions → New
repository secret**, two secrets:

- `TASKS_SUPABASE_DB_URL`: the Maham Tasks project's **Session pooler**
  connection string (Supabase → **Connect**), with its database password in
  it. If the old repository had backups, it is the value it had as
  `SUPABASE_DB_URL`.
- `TASKS_BACKUP_PASSPHRASE`: a long passphrase kept in your password manager.
  If the old repository had backups, use the same one, so old and new backups
  open the same way.

Then **Actions → Maham Tasks weekly backup → Run workflow**, and check it
finishes green with a file attached. How to open a backup and try a restore:
[Backups](../Maham%20Tasks/README.md#backups) in the Maham Tasks README.

### 5. Archive the old repository

Once step 1 is done (Vercel no longer builds from it): on GitHub, open
`almailgroup/almailgroup-task-management-portal` → **Settings → Archive this
repository**. It stays readable, but nobody can change it by mistake. Its own
weekly backup stops then, which is why step 4 comes first.

### 6. Tell Claude

Once tasks.mahamone.com works, the next step is a **Maham Tasks** tile on the
Maham One home that opens it.
