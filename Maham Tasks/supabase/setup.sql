-- ---------------------------------------------------------------------------
-- Almailgroup Task Management Portal — complete database setup
--
-- GENERATED FILE. Do not edit by hand: run `npm run db:bundle` instead.
-- Source of truth is supabase/migrations/, concatenated here in filename order.
--
-- First-time setup: paste this whole file into the Supabase SQL editor and
-- run it. It is safe to re-run; every statement is idempotent.
--
-- Bundled migrations:
--   20260913000001_initial_schema.sql
--   20260913000002_functions_and_triggers.sql
--   20260913000003_row_level_security.sql
--   20260913000004_realtime.sql
--   20260913000005_protect_last_admin.sql
--   20260913000006_general_tasks_and_review_gate.sql
--   20260913000007_attachments.sql
--   20260913000008_notifications.sql
--   20260913000009_member_view_only_details.sql
--   20260913000010_fix_delete_task_audit.sql
--   20260913000011_due_time_and_positions.sql
--   20260913000012_project_membership.sql
--   20260913000013_follow_ups.sql
--   20260913000014_reminders.sql
--   20260913000015_members_see_only_assigned.sql
--   20260914000016_personal_notes.sql
--   20260914000017_claim_reminders_and_counts.sql
--   20260914000018_task_counts_timezone.sql
--   20260914000019_shared_notes.sql
--   20260914000020_trash_tasks.sql
--   20260916000021_notify_missing_recipient.sql
--   20260916000022_claim_task_reminders.sql
--   20260916000023_team_chat.sql
--   20260919000024_direct_messages.sql
--   20260921000025_recurring_tasks.sql
--   20260921000026_web_push.sql
--   20260927000027_reminder_failures.sql
--   20260927000028_error_log.sql
--   20260927000029_task_checklists.sql
--   20260927000030_archive_projects.sql
--   20260930000031_guard_telegram_chat.sql
--   20261002000032_project_status_updates.sql
--   20261002000033_comment_reactions.sql
--   20261013000034_close_self_registration.sql
--   20261013000035_attachment_files_follow_task.sql
--   20261017000036_company_holidays.sql
--   20261017000037_office_reminders.sql
--   20261017000038_two_step_sign_in.sql
--   20261017000039_labels.sql
--   20261017000040_task_dependencies.sql
--   20261017000041_task_templates.sql
--   20261017000042_telegram_quick_add.sql
--   20261017000043_work_report.sql
--   20261017000044_project_milestones.sql
--   20261017000045_admin_alerts.sql
--   20261017000046_portal_health.sql
-- ---------------------------------------------------------------------------

-- =========================================================================
-- 20260913000001_initial_schema.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Almailgroup Task Management Portal — core schema
--
-- Creates the enums, tables and indexes backing projects, tasks, assignments,
-- comments and the task audit trail.
-- ---------------------------------------------------------------------------

create extension if not exists "pgcrypto";

-- --------------------------------------------------------------------------
-- Enums
-- --------------------------------------------------------------------------

-- Created only if absent, so the script stays re-runnable. If a type of the
-- same name already exists with different values, this database belongs to a
-- different application — stop with an explanation rather than failing later
-- with a confusing "invalid input value for enum" on the first table.
create or replace function public.assert_enum(
  type_name text,
  required text[]
)
returns void
language plpgsql
as $fn$
declare
  existing text[];
begin
  if not exists (
    select 1 from pg_type
    where typname = type_name and typnamespace = 'public'::regnamespace
  ) then
    execute format(
      'create type public.%I as enum (%s)',
      type_name,
      (select string_agg(quote_literal(v), ', ') from unnest(required) v)
    );
    return;
  end if;

  select array_agg(e.enumlabel::text order by e.enumsortorder)
    into existing
  from pg_enum e
  join pg_type t on t.oid = e.enumtypid
  where t.typname = type_name and t.typnamespace = 'public'::regnamespace;

  if not (required <@ existing) then
    raise exception
      'public.% already exists here with different values (%), so this database belongs to another application.',
      type_name, array_to_string(existing, ', ')
      using hint =
        'Run this script against a Supabase project created for the task portal, not one already in use. Check the project selector at the top of the SQL editor.';
  end if;
end;
$fn$;

select public.assert_enum('user_role', array['admin', 'manager', 'member']);
select public.assert_enum('task_status', array['todo', 'in_progress', 'in_review', 'done']);
select public.assert_enum('task_priority', array['low', 'medium', 'high', 'urgent']);

-- --------------------------------------------------------------------------
-- profiles — one row per auth user, created automatically on signup.
-- --------------------------------------------------------------------------

create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text        not null,
  full_name   text,
  avatar_url  text,
  role        public.user_role not null default 'member',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint profiles_email_not_blank check (length(btrim(email)) > 0),
  constraint profiles_full_name_length check (full_name is null or length(full_name) <= 120)
);

create unique index if not exists profiles_email_key
  on public.profiles (lower(email));

comment on table public.profiles is
  'Application profile for each auth.users row. Role drives authorisation.';

-- --------------------------------------------------------------------------
-- projects
--
-- created_by is nullable with ON DELETE SET NULL so that offboarding a user
-- never cascades away the projects they happened to create.
-- --------------------------------------------------------------------------

create table if not exists public.projects (
  id          uuid primary key default gen_random_uuid(),
  name        text        not null,
  description text,
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint projects_name_length check (length(btrim(name)) between 1 and 120),
  constraint projects_description_length check (description is null or length(description) <= 2000)
);

create index if not exists projects_created_by_idx on public.projects (created_by);
create index if not exists projects_created_at_idx on public.projects (created_at desc);

-- --------------------------------------------------------------------------
-- tasks
--
-- `position` gives the Kanban board a stable, persistable order within each
-- status column. Cards are inserted using the midpoint between neighbours so a
-- single drag updates exactly one row.
-- --------------------------------------------------------------------------

create table if not exists public.tasks (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid        not null references public.projects (id) on delete cascade,
  title       text        not null,
  description text,
  status      public.task_status   not null default 'todo',
  priority    public.task_priority not null default 'medium',
  due_date    date,
  position    double precision not null default 0,
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint tasks_title_length check (length(btrim(title)) between 1 and 200),
  constraint tasks_description_length check (description is null or length(description) <= 20000)
);

create index if not exists tasks_project_status_position_idx
  on public.tasks (project_id, status, position);
create index if not exists tasks_project_created_idx
  on public.tasks (project_id, created_at desc);
-- Overdue lookups only ever consider unfinished work.
--
-- Guarded on the column still being called due_date: migration 0011 renames it
-- to due_at, and this file is also shipped inside the re-runnable setup.sql
-- bundle, where it is replayed against an already-migrated database.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'tasks'
      and column_name = 'due_date'
  ) then
    execute 'create index if not exists tasks_open_due_date_idx
      on public.tasks (due_date)
      where status <> ''done'' and due_date is not null';
  end if;
end $$;

-- --------------------------------------------------------------------------
-- task_assignments — many-to-many between tasks and profiles.
-- --------------------------------------------------------------------------

create table if not exists public.task_assignments (
  task_id     uuid not null references public.tasks (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  assigned_at timestamptz not null default now(),

  primary key (task_id, user_id)
);

create index if not exists task_assignments_user_idx
  on public.task_assignments (user_id);

-- --------------------------------------------------------------------------
-- comments — contextual discussion on a task, streamed over Realtime.
-- --------------------------------------------------------------------------

create table if not exists public.comments (
  id         uuid primary key default gen_random_uuid(),
  task_id    uuid not null references public.tasks (id) on delete cascade,
  user_id    uuid references public.profiles (id) on delete set null,
  content    text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint comments_content_length check (length(btrim(content)) between 1 and 5000)
);

create index if not exists comments_task_created_idx
  on public.comments (task_id, created_at);

-- --------------------------------------------------------------------------
-- task_activity — append-only audit trail, written by triggers.
--
-- `action` is text with a check rather than an enum so new activity kinds can
-- ship without an enum migration.
-- --------------------------------------------------------------------------

create table if not exists public.task_activity (
  id         uuid primary key default gen_random_uuid(),
  task_id    uuid not null references public.tasks (id) on delete cascade,
  actor_id   uuid references public.profiles (id) on delete set null,
  action     text not null,
  field      text,
  old_value  text,
  new_value  text,
  created_at timestamptz not null default now(),

  constraint task_activity_action_known check (
    action in (
      'created',
      'updated',
      'status_changed',
      'priority_changed',
      'due_date_changed',
      'assignee_added',
      'assignee_removed',
      'commented'
    )
  )
);

create index if not exists task_activity_task_created_idx
  on public.task_activity (task_id, created_at desc);

comment on table public.task_activity is
  'Append-only audit log. Written by triggers; never updated or deleted by the app.';

-- =========================================================================
-- 20260913000002_functions_and_triggers.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Functions and triggers
--
-- Every helper is SECURITY DEFINER with a pinned search_path. That combination
-- is what lets the RLS policies in the next migration read `profiles.role`
-- without recursing into the policy that guards `profiles` itself.
-- ---------------------------------------------------------------------------

-- --------------------------------------------------------------------------
-- Authorisation helpers
-- --------------------------------------------------------------------------

create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select role from public.profiles where id = auth.uid();
$$;

comment on function public.current_user_role() is
  'Role of the calling user. SECURITY DEFINER so RLS on profiles does not recurse.';

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.current_user_role() = 'admin', false);
$$;

create or replace function public.is_manager_or_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.current_user_role() in ('admin', 'manager'), false);
$$;

-- True when the caller created the task or is assigned to it.
create or replace function public.can_edit_task(task uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.tasks t
    where t.id = task
      and (
        t.created_by = auth.uid()
        or exists (
          select 1 from public.task_assignments a
          where a.task_id = t.id and a.user_id = auth.uid()
        )
      )
  );
$$;

-- --------------------------------------------------------------------------
-- Signup — mirror every new auth user into public.profiles.
--
-- The first account to register becomes the admin, so a fresh deployment is
-- not locked out of project creation.
-- --------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  assigned_role public.user_role;
begin
  select case when count(*) = 0 then 'admin'::public.user_role
              else 'member'::public.user_role end
    into assigned_role
  from public.profiles;

  insert into public.profiles (id, email, full_name, avatar_url, role)
  values (
    new.id,
    new.email,
    nullif(btrim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), ''),
    nullif(btrim(coalesce(new.raw_user_meta_data ->> 'avatar_url', '')), ''),
    assigned_role
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- --------------------------------------------------------------------------
-- updated_at maintenance
-- --------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

drop trigger if exists projects_set_updated_at on public.projects;
create trigger projects_set_updated_at
  before update on public.projects
  for each row execute function public.set_updated_at();

drop trigger if exists tasks_set_updated_at on public.tasks;
create trigger tasks_set_updated_at
  before update on public.tasks
  for each row execute function public.set_updated_at();

drop trigger if exists comments_set_updated_at on public.comments;
create trigger comments_set_updated_at
  before update on public.comments
  for each row execute function public.set_updated_at();

-- --------------------------------------------------------------------------
-- Role escalation guard
--
-- `profiles` is writable by its owner so people can edit their own name and
-- avatar. This trigger makes sure that same policy cannot be used to hand
-- yourself the admin role — only an existing admin may change `role`.
-- --------------------------------------------------------------------------

create or replace function public.guard_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.role is distinct from old.role and not public.is_admin() then
    raise exception 'Only an admin can change a profile role'
      using errcode = 'insufficient_privilege';
  end if;

  -- id and email track auth.users and are not user-editable.
  new.id := old.id;
  new.email := old.email;

  return new;
end;
$$;

drop trigger if exists profiles_guard_role_change on public.profiles;
create trigger profiles_guard_role_change
  before update on public.profiles
  for each row execute function public.guard_profile_role_change();

-- --------------------------------------------------------------------------
-- Task audit trail
-- --------------------------------------------------------------------------

create or replace function public.log_task_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.task_activity (task_id, actor_id, action, new_value)
  values (new.id, auth.uid(), 'created', new.title);
  return null;
end;
$$;

drop trigger if exists tasks_log_insert on public.tasks;
create trigger tasks_log_insert
  after insert on public.tasks
  for each row execute function public.log_task_insert();

create or replace function public.log_task_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor uuid := auth.uid();
begin
  if new.status is distinct from old.status then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'status_changed', 'status', old.status::text, new.status::text);
  end if;

  if new.priority is distinct from old.priority then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'priority_changed', 'priority', old.priority::text, new.priority::text);
  end if;

  if new.due_date is distinct from old.due_date then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'due_date_changed', 'due_date', old.due_date::text, new.due_date::text);
  end if;

  if new.title is distinct from old.title then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'updated', 'title', old.title, new.title);
  end if;

  -- Body text is logged as a change marker only; the diff itself would bloat
  -- the audit table.
  if new.description is distinct from old.description then
    insert into public.task_activity (task_id, actor_id, action, field)
    values (new.id, actor, 'updated', 'description');
  end if;

  return null;
end;
$$;

drop trigger if exists tasks_log_update on public.tasks;
create trigger tasks_log_update
  after update on public.tasks
  for each row execute function public.log_task_update();

create or replace function public.log_assignment_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target uuid;
  label  text;
begin
  target := case when tg_op = 'INSERT' then new.user_id else old.user_id end;

  select coalesce(p.full_name, p.email) into label
  from public.profiles p where p.id = target;

  if tg_op = 'INSERT' then
    insert into public.task_activity (task_id, actor_id, action, field, new_value)
    values (new.task_id, auth.uid(), 'assignee_added', 'assignees', label);
  else
    insert into public.task_activity (task_id, actor_id, action, field, old_value)
    values (old.task_id, auth.uid(), 'assignee_removed', 'assignees', label);
  end if;

  return null;
end;
$$;

drop trigger if exists task_assignments_log_insert on public.task_assignments;
create trigger task_assignments_log_insert
  after insert on public.task_assignments
  for each row execute function public.log_assignment_change();

drop trigger if exists task_assignments_log_delete on public.task_assignments;
create trigger task_assignments_log_delete
  after delete on public.task_assignments
  for each row execute function public.log_assignment_change();

create or replace function public.log_comment_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.task_activity (task_id, actor_id, action)
  values (new.task_id, new.user_id, 'commented');
  return null;
end;
$$;

drop trigger if exists comments_log_insert on public.comments;
create trigger comments_log_insert
  after insert on public.comments
  for each row execute function public.log_comment_insert();

-- =========================================================================
-- 20260913000003_row_level_security.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Row Level Security
--
-- Authorisation model: this is a single-tenant internal portal, so every
-- signed-in employee can READ the whole workspace (that is what makes project
-- switching, assignee pickers and @mentions work). WRITES are what the roles
-- gate:
--
--   admin   — everything, including roles and deletions
--   manager — create/edit/delete projects and any task
--   member  — create tasks; edit tasks they created or are assigned to
--
-- Nothing is readable while signed out: read policies target `authenticated`
-- AND require a JWT subject, so a role without an identity reads nothing.
-- ---------------------------------------------------------------------------

alter table public.profiles        enable row level security;
alter table public.projects        enable row level security;
alter table public.tasks           enable row level security;
alter table public.task_assignments enable row level security;
alter table public.comments        enable row level security;
alter table public.task_activity   enable row level security;

-- Force RLS to apply to table owners too, so a mistake in a SECURITY DEFINER
-- function cannot quietly hand out unrestricted access.
alter table public.profiles        force row level security;
alter table public.projects        force row level security;
alter table public.tasks           force row level security;
alter table public.task_assignments force row level security;
alter table public.comments        force row level security;
alter table public.task_activity   force row level security;

-- --------------------------------------------------------------------------
-- profiles
-- --------------------------------------------------------------------------

drop policy if exists "profiles are readable by authenticated users" on public.profiles;
create policy "profiles are readable by authenticated users"
  on public.profiles for select
  to authenticated
  using (auth.uid() is not null);

-- Own row only. The guard_profile_role_change trigger blocks self-promotion.
drop policy if exists "users update their own profile" on public.profiles;
create policy "users update their own profile"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists "admins update any profile" on public.profiles;
create policy "admins update any profile"
  on public.profiles for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- No INSERT policy: rows are created exclusively by the handle_new_user
-- trigger on auth.users. No DELETE policy: profiles die with their auth user.

-- --------------------------------------------------------------------------
-- projects
-- --------------------------------------------------------------------------

drop policy if exists "projects are readable by authenticated users" on public.projects;
create policy "projects are readable by authenticated users"
  on public.projects for select
  to authenticated
  using (auth.uid() is not null);

drop policy if exists "managers and admins create projects" on public.projects;
create policy "managers and admins create projects"
  on public.projects for insert
  to authenticated
  with check (public.is_manager_or_admin() and created_by = auth.uid());

drop policy if exists "managers and admins update projects" on public.projects;
create policy "managers and admins update projects"
  on public.projects for update
  to authenticated
  using (public.is_manager_or_admin())
  with check (public.is_manager_or_admin());

-- Deleting a project cascades to its tasks, so it stays with admins and the
-- manager who created it.
drop policy if exists "admins and owning managers delete projects" on public.projects;
create policy "admins and owning managers delete projects"
  on public.projects for delete
  to authenticated
  using (
    public.is_admin()
    or (public.is_manager_or_admin() and created_by = auth.uid())
  );

-- --------------------------------------------------------------------------
-- tasks
-- --------------------------------------------------------------------------

drop policy if exists "tasks are readable by authenticated users" on public.tasks;
create policy "tasks are readable by authenticated users"
  on public.tasks for select
  to authenticated
  using (auth.uid() is not null);

drop policy if exists "authenticated users create tasks" on public.tasks;
create policy "authenticated users create tasks"
  on public.tasks for insert
  to authenticated
  with check (created_by = auth.uid());

-- Managers and admins may edit anything; members only their own or assigned
-- tasks. can_edit_task() is SECURITY DEFINER to avoid recursing through the
-- task_assignments policies.
drop policy if exists "task editors update tasks" on public.tasks;
create policy "task editors update tasks"
  on public.tasks for update
  to authenticated
  using (public.is_manager_or_admin() or public.can_edit_task(id))
  with check (public.is_manager_or_admin() or public.can_edit_task(id));

drop policy if exists "managers admins and creators delete tasks" on public.tasks;
create policy "managers admins and creators delete tasks"
  on public.tasks for delete
  to authenticated
  using (public.is_manager_or_admin() or created_by = auth.uid());

-- --------------------------------------------------------------------------
-- task_assignments
-- --------------------------------------------------------------------------

drop policy if exists "assignments are readable by authenticated users" on public.task_assignments;
create policy "assignments are readable by authenticated users"
  on public.task_assignments for select
  to authenticated
  using (auth.uid() is not null);

-- Whoever may edit the task may change who works on it. Members can also pick
-- up unassigned work themselves.
drop policy if exists "task editors add assignees" on public.task_assignments;
create policy "task editors add assignees"
  on public.task_assignments for insert
  to authenticated
  with check (
    public.is_manager_or_admin()
    or public.can_edit_task(task_id)
    or user_id = auth.uid()
  );

drop policy if exists "task editors remove assignees" on public.task_assignments;
create policy "task editors remove assignees"
  on public.task_assignments for delete
  to authenticated
  using (
    public.is_manager_or_admin()
    or public.can_edit_task(task_id)
    or user_id = auth.uid()
  );

-- --------------------------------------------------------------------------
-- comments
-- --------------------------------------------------------------------------

drop policy if exists "comments are readable by authenticated users" on public.comments;
create policy "comments are readable by authenticated users"
  on public.comments for select
  to authenticated
  using (auth.uid() is not null);

drop policy if exists "users write their own comments" on public.comments;
create policy "users write their own comments"
  on public.comments for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "users edit their own comments" on public.comments;
create policy "users edit their own comments"
  on public.comments for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "authors and admins delete comments" on public.comments;
create policy "authors and admins delete comments"
  on public.comments for delete
  to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- --------------------------------------------------------------------------
-- task_activity
--
-- Readable by everyone signed in, writable by nobody: rows come only from the
-- SECURITY DEFINER audit triggers, which bypass RLS. Leaving out INSERT,
-- UPDATE and DELETE policies is what makes the log genuinely append-only.
-- --------------------------------------------------------------------------

drop policy if exists "activity is readable by authenticated users" on public.task_activity;
create policy "activity is readable by authenticated users"
  on public.task_activity for select
  to authenticated
  using (auth.uid() is not null);

-- --------------------------------------------------------------------------
-- Table privileges
--
-- RLS narrows access but never grants it. Supabase's default privileges
-- usually cover new public tables already; spelling them out here means the
-- schema also works on a project where those defaults were changed.
--
-- `anon` is deliberately granted nothing — there is no public read surface.
-- --------------------------------------------------------------------------

grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.projects to authenticated;
grant select, insert, update, delete on public.tasks to authenticated;
grant select, insert, delete on public.task_assignments to authenticated;
grant select, insert, update, delete on public.comments to authenticated;
-- Select only: the audit trail is written exclusively by triggers.
grant select on public.task_activity to authenticated;

grant execute on function public.current_user_role() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_manager_or_admin() to authenticated;
grant execute on function public.can_edit_task(uuid) to authenticated;

-- =========================================================================
-- 20260913000004_realtime.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Realtime
--
-- Publishes the tables the UI subscribes to. Realtime still enforces RLS on
-- every change it forwards, so publishing a table does not widen access.
--
-- Guarded with a lookup on pg_publication so the migration is idempotent and
-- also applies on a plain Postgres instance (CI, local validation) where the
-- Supabase publication does not exist.
-- ---------------------------------------------------------------------------

do $$
declare
  target text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'publication supabase_realtime not found — skipping';
    return;
  end if;

  foreach target in array array['tasks', 'comments', 'task_assignments', 'task_activity']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = target
    ) then
      execute format('alter publication supabase_realtime add table public.%I', target);
    end if;
  end loop;
end $$;

-- Realtime UPDATE payloads only carry the columns needed to identify a row
-- unless the replica identity is full. The board diffs old vs new status, so
-- tasks needs the complete old row.
alter table public.tasks replica identity full;
alter table public.comments replica identity full;

-- =========================================================================
-- 20260913000005_protect_last_admin.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Guard against locking the workspace out of its own admin role.
--
-- An admin may legitimately demote another admin, but if the last one demotes
-- themselves nobody can create projects or manage roles again, and there is no
-- in-app way to recover. This makes that specific transition fail.
-- ---------------------------------------------------------------------------

create or replace function public.prevent_last_admin_demotion()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  remaining integer;
begin
  if old.role = 'admin' and new.role is distinct from old.role then
    select count(*) into remaining
    from public.profiles
    where role = 'admin' and id <> old.id;

    if remaining = 0 then
      raise exception 'Cannot remove the last admin. Promote another member first.'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

-- Runs after guard_profile_role_change (alphabetical order among BEFORE
-- triggers on the same event), so permission is checked before this.
drop trigger if exists profiles_protect_last_admin on public.profiles;
create trigger profiles_protect_last_admin
  before update on public.profiles
  for each row execute function public.prevent_last_admin_demotion();

-- =========================================================================
-- 20260913000006_general_tasks_and_review_gate.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- General tasks and the review gate
--
-- 1. Tasks may now exist outside any project ("general tasks"). Creating one
--    is restricted to managers and admins.
-- 2. Only a manager or admin may mark a task done. Everyone else tops out at
--    'in_review', so finished work is reviewed before it is closed.
-- ---------------------------------------------------------------------------

-- --------------------------------------------------------------------------
-- General tasks: project_id becomes optional.
-- --------------------------------------------------------------------------

alter table public.tasks alter column project_id drop not null;

comment on column public.tasks.project_id is
  'NULL marks a general task: assigned work that belongs to no project.';

-- Board ordering for the general list, mirroring the per-project index.
create index if not exists tasks_general_status_position_idx
  on public.tasks (status, position)
  where project_id is null;

-- Only managers and admins may open general tasks; anyone may still create a
-- task inside a project.
drop policy if exists "authenticated users create tasks" on public.tasks;
create policy "authenticated users create tasks"
  on public.tasks for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and (project_id is not null or public.is_manager_or_admin())
  );

-- --------------------------------------------------------------------------
-- Review gate
--
-- Enforced as a trigger rather than in the RLS policy because the rule is
-- about a transition: a WITH CHECK expression cannot see the previous row, so
-- it could not tell "a member is closing this task" from "a member edited the
-- title of a task that was already closed".
--
-- Moving out of 'done' is restricted to the same roles. Letting an assignee
-- reopen a task would undo the reviewer's decision, which is the very thing
-- the gate exists to protect.
-- --------------------------------------------------------------------------

create or replace function public.enforce_review_gate()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status is distinct from old.status
     and 'done' in (new.status::text, old.status::text)
     and not public.is_manager_or_admin()
  then
    if new.status = 'done' then
      raise exception 'Only a manager or admin can mark a task done. Move it to In Review instead.'
        using errcode = 'insufficient_privilege';
    else
      raise exception 'Only a manager or admin can reopen a completed task.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists tasks_enforce_review_gate on public.tasks;
create trigger tasks_enforce_review_gate
  before update on public.tasks
  for each row execute function public.enforce_review_gate();

-- Exposed so the UI can disable the Done option up front rather than letting
-- the user discover the rule by hitting an error.
create or replace function public.can_complete_tasks()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_manager_or_admin();
$$;

grant execute on function public.can_complete_tasks() to authenticated;

-- =========================================================================
-- 20260913000007_attachments.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Task attachments — uploaded files and external links.
--
-- Both kinds live in one table so the task detail view renders a single list.
-- A row is either a file (storage_path set) or a link (url set), never both.
-- ---------------------------------------------------------------------------

create table if not exists public.task_attachments (
  id           uuid primary key default gen_random_uuid(),
  task_id      uuid not null references public.tasks (id) on delete cascade,
  uploaded_by  uuid references public.profiles (id) on delete set null,
  kind         text not null check (kind in ('file', 'link')),
  name         text not null,
  storage_path text,
  url          text,
  mime_type    text,
  size_bytes   bigint,
  created_at   timestamptz not null default now(),

  constraint task_attachments_name_length check (length(btrim(name)) between 1 and 255),

  -- Exactly one of storage_path / url, matching `kind`.
  constraint task_attachments_shape check (
    (kind = 'file' and storage_path is not null and url is null)
    or (kind = 'link' and url is not null and storage_path is null)
  ),

  -- Only http(s) links. Blocks javascript: and data: URLs, which would
  -- otherwise become a stored-XSS vector the moment one is rendered as a link.
  constraint task_attachments_url_scheme check (
    url is null or url ~* '^https?://'
  ),

  constraint task_attachments_size check (
    size_bytes is null or (size_bytes >= 0 and size_bytes <= 26214400)
  )
);

create index if not exists task_attachments_task_idx
  on public.task_attachments (task_id, created_at desc);

create unique index if not exists task_attachments_storage_path_key
  on public.task_attachments (storage_path)
  where storage_path is not null;

comment on table public.task_attachments is
  'Files and links attached to a task. Files live in the task-attachments bucket.';

-- --------------------------------------------------------------------------
-- Row Level Security
-- --------------------------------------------------------------------------

alter table public.task_attachments enable row level security;
alter table public.task_attachments force row level security;

drop policy if exists "attachments are readable by authenticated users" on public.task_attachments;
create policy "attachments are readable by authenticated users"
  on public.task_attachments for select
  to authenticated
  using (auth.uid() is not null);

-- Anyone who may edit the task may attach to it.
drop policy if exists "task editors add attachments" on public.task_attachments;
create policy "task editors add attachments"
  on public.task_attachments for insert
  to authenticated
  with check (
    uploaded_by = auth.uid()
    and (public.is_manager_or_admin() or public.can_edit_task(task_id))
  );

drop policy if exists "uploaders and managers remove attachments" on public.task_attachments;
create policy "uploaders and managers remove attachments"
  on public.task_attachments for delete
  to authenticated
  using (uploaded_by = auth.uid() or public.is_manager_or_admin());

grant select, insert, delete on public.task_attachments to authenticated;

-- --------------------------------------------------------------------------
-- Storage bucket
--
-- Private: objects are reached through short-lived signed URLs, so an
-- attachment cannot be read by guessing its path.
--
-- Guarded on the storage schema existing, so this migration also applies to a
-- plain Postgres instance (CI, local validation) that has no Supabase Storage.
-- Object keys are "<task_id>/<uuid>-<filename>", so the first path segment
-- identifies the task an object belongs to.
-- --------------------------------------------------------------------------

do $$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'storage schema not found - skipping bucket and object policies';
    return;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit)
  values ('task-attachments', 'task-attachments', false, 26214400)
  on conflict (id) do update
    set public = false,
        file_size_limit = excluded.file_size_limit;

  execute $p$drop policy if exists "attachment objects readable by authenticated" on storage.objects$p$;
  execute $p$create policy "attachment objects readable by authenticated"
    on storage.objects for select
    to authenticated
    using (bucket_id = 'task-attachments' and auth.uid() is not null)$p$;

  execute $p$drop policy if exists "attachment objects writable by task editors" on storage.objects$p$;
  execute $p$create policy "attachment objects writable by task editors"
    on storage.objects for insert
    to authenticated
    with check (
      bucket_id = 'task-attachments'
      and owner = auth.uid()
      and (
        public.is_manager_or_admin()
        or public.can_edit_task(nullif(split_part(name, '/', 1), '')::uuid)
      )
    )$p$;

  execute $p$drop policy if exists "attachment objects removable by owner or manager" on storage.objects$p$;
  execute $p$create policy "attachment objects removable by owner or manager"
    on storage.objects for delete
    to authenticated
    using (
      bucket_id = 'task-attachments'
      and (owner = auth.uid() or public.is_manager_or_admin())
    )$p$;
end $$;

-- =========================================================================
-- 20260913000008_notifications.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Notifications
--
-- Written by database triggers rather than application code, so an event
-- cannot be missed because some path forgot to raise it. Each row is private
-- to its recipient.
-- ---------------------------------------------------------------------------

create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  actor_id   uuid references public.profiles (id) on delete set null,
  type       text not null,
  title      text not null,
  body       text,
  task_id    uuid references public.tasks (id) on delete cascade,
  project_id uuid references public.projects (id) on delete cascade,
  read_at    timestamptz,
  created_at timestamptz not null default now(),

  constraint notifications_type_known check (
    type in (
      'task_assigned',
      'task_unassigned',
      'task_commented',
      'task_mentioned',
      'task_review_requested',
      'task_completed'
    )
  )
);

-- Drives the unread badge and the newest-first list.
create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);
create index if not exists notifications_user_unread_idx
  on public.notifications (user_id)
  where read_at is null;

alter table public.notifications enable row level security;
alter table public.notifications force row level security;

-- Strictly private: unlike the rest of this schema, a notification is visible
-- only to its recipient.
drop policy if exists "users read their own notifications" on public.notifications;
create policy "users read their own notifications"
  on public.notifications for select
  to authenticated
  using (user_id = auth.uid());

-- Recipients may only mark as read; the content is written by triggers.
drop policy if exists "users update their own notifications" on public.notifications;
create policy "users update their own notifications"
  on public.notifications for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "users delete their own notifications" on public.notifications;
create policy "users delete their own notifications"
  on public.notifications for delete
  to authenticated
  using (user_id = auth.uid());

-- No INSERT policy or grant: rows come only from the SECURITY DEFINER triggers
-- below, so nobody can forge a notification to another user.
grant select, update, delete on public.notifications to authenticated;

-- --------------------------------------------------------------------------
-- Helper
-- --------------------------------------------------------------------------

create or replace function public.push_notification(
  recipient uuid,
  actor uuid,
  kind text,
  heading text,
  detail text,
  task uuid,
  project uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Never notify someone about their own action, and never about a missing user.
  if recipient is null or recipient = coalesce(actor, '00000000-0000-0000-0000-000000000000'::uuid) then
    return;
  end if;

  insert into public.notifications (user_id, actor_id, type, title, body, task_id, project_id)
  values (recipient, actor, kind, heading, detail, task, project);
end;
$$;

-- --------------------------------------------------------------------------
-- Assignment
-- --------------------------------------------------------------------------

create or replace function public.notify_assignment()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t public.tasks%rowtype;
begin
  if tg_op = 'INSERT' then
    select * into t from public.tasks where id = new.task_id;
    perform public.push_notification(
      new.user_id, auth.uid(), 'task_assigned',
      'You were assigned a task', t.title, t.id, t.project_id
    );
  else
    select * into t from public.tasks where id = old.task_id;
    -- The task may already be gone when the assignment cascades away.
    if found then
      perform public.push_notification(
        old.user_id, auth.uid(), 'task_unassigned',
        'You were removed from a task', t.title, t.id, t.project_id
      );
    end if;
  end if;

  return null;
end;
$$;

drop trigger if exists task_assignments_notify_insert on public.task_assignments;
create trigger task_assignments_notify_insert
  after insert on public.task_assignments
  for each row execute function public.notify_assignment();

drop trigger if exists task_assignments_notify_delete on public.task_assignments;
create trigger task_assignments_notify_delete
  after delete on public.task_assignments
  for each row execute function public.notify_assignment();

-- --------------------------------------------------------------------------
-- Status changes
--
-- Reaching 'in_review' tells whoever has to review it. Reaching 'done' tells
-- the people who worked on it.
-- --------------------------------------------------------------------------

create or replace function public.notify_status_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor uuid := auth.uid();
  recipient uuid;
begin
  if new.status is not distinct from old.status then
    return null;
  end if;

  if new.status = 'in_review' then
    -- The task's creator reviews it; for general tasks with no creator left,
    -- fall back to every manager and admin.
    if new.created_by is not null then
      perform public.push_notification(
        new.created_by, actor, 'task_review_requested',
        'A task is ready for review', new.title, new.id, new.project_id
      );
    else
      for recipient in
        select id from public.profiles where role in ('admin', 'manager')
      loop
        perform public.push_notification(
          recipient, actor, 'task_review_requested',
          'A task is ready for review', new.title, new.id, new.project_id
        );
      end loop;
    end if;

  elsif new.status = 'done' then
    for recipient in
      select user_id from public.task_assignments where task_id = new.id
      union
      select new.created_by where new.created_by is not null
    loop
      perform public.push_notification(
        recipient, actor, 'task_completed',
        'A task was marked done', new.title, new.id, new.project_id
      );
    end loop;
  end if;

  return null;
end;
$$;

drop trigger if exists tasks_notify_status_change on public.tasks;
create trigger tasks_notify_status_change
  after update on public.tasks
  for each row execute function public.notify_status_change();

-- --------------------------------------------------------------------------
-- Comments and @mentions
--
-- Mentions are matched against profile names here so that a comment written
-- from anywhere — the app, the SQL editor, a future integration — still
-- notifies the people it names.
-- --------------------------------------------------------------------------

create or replace function public.notify_comment()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t public.tasks%rowtype;
  recipient uuid;
  mentioned uuid[];
begin
  select * into t from public.tasks where id = new.task_id;
  if not found then
    return null;
  end if;

  -- Anyone named with @Full Name, or @local-part of their email.
  select coalesce(array_agg(p.id), '{}')
    into mentioned
  from public.profiles p
  where p.id <> coalesce(new.user_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and (
      (p.full_name is not null and new.content ilike '%@' || p.full_name || '%')
      or new.content ilike '%@' || split_part(p.email, '@', 1) || '%'
    );

  foreach recipient in array mentioned loop
    perform public.push_notification(
      recipient, new.user_id, 'task_mentioned',
      'You were mentioned in a comment', left(new.content, 140), t.id, t.project_id
    );
  end loop;

  -- Everyone else with a stake in the task: its assignees and its creator.
  for recipient in
    select a.user_id from public.task_assignments a where a.task_id = t.id
    union
    select t.created_by where t.created_by is not null
  loop
    if not (recipient = any(mentioned)) then
      perform public.push_notification(
        recipient, new.user_id, 'task_commented',
        'New comment on a task', left(new.content, 140), t.id, t.project_id
      );
    end if;
  end loop;

  return null;
end;
$$;

drop trigger if exists comments_notify on public.comments;
create trigger comments_notify
  after insert on public.comments
  for each row execute function public.notify_comment();

-- --------------------------------------------------------------------------
-- Realtime — the bell updates without a refresh.
-- --------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'publication supabase_realtime not found - skipping';
    return;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;

-- =========================================================================
-- 20260913000009_member_view_only_details.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Team members are view-only on task details.
--
-- Planning is a manager's job. A member receives a task, works on it and
-- reports progress; they do not get to rewrite what they were asked to do.
--
-- Members may still:
--   * move a task's status (up to In Review — see the review gate)
--   * reorder cards on the board
--   * post comments
--   * attach files and links, which is how finished work is handed over
--
-- Members may no longer:
--   * change title, description, priority, due date, or which project a task
--     belongs to
--   * add or remove assignees, including themselves
--   * edit or delete comments, their own included
-- ---------------------------------------------------------------------------

-- --------------------------------------------------------------------------
-- Task fields
--
-- A trigger rather than a policy, for the same reason as the review gate: the
-- rule is about which columns changed, and a WITH CHECK expression cannot see
-- the previous row.
-- --------------------------------------------------------------------------

create or replace function public.enforce_task_field_permissions()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if public.is_manager_or_admin() then
    return new;
  end if;

  if new.title is distinct from old.title
     or new.description is distinct from old.description
     or new.priority is distinct from old.priority
     or new.due_date is distinct from old.due_date
     or new.project_id is distinct from old.project_id
  then
    raise exception 'Only a manager or admin can change task details. You can update the status and add comments or files.'
      using errcode = 'insufficient_privilege';
  end if;

  -- status and position are left alone: progress and board order are exactly
  -- what an assignee is expected to maintain.
  return new;
end;
$$;

drop trigger if exists tasks_enforce_field_permissions on public.tasks;
create trigger tasks_enforce_field_permissions
  before update on public.tasks
  for each row execute function public.enforce_task_field_permissions();

-- --------------------------------------------------------------------------
-- Assignments — managers and admins decide who works on what.
-- --------------------------------------------------------------------------

drop policy if exists "task editors add assignees" on public.task_assignments;
drop policy if exists "managers and admins add assignees" on public.task_assignments;
create policy "managers and admins add assignees"
  on public.task_assignments for insert
  to authenticated
  with check (public.is_manager_or_admin());

drop policy if exists "task editors remove assignees" on public.task_assignments;
drop policy if exists "managers and admins remove assignees" on public.task_assignments;
create policy "managers and admins remove assignees"
  on public.task_assignments for delete
  to authenticated
  using (public.is_manager_or_admin());

-- --------------------------------------------------------------------------
-- Comments — append-only for members.
--
-- The UPDATE policy is tightened alongside DELETE: leaving it open would let a
-- member blank a comment, which is a deletion by another name.
-- --------------------------------------------------------------------------

drop policy if exists "users edit their own comments" on public.comments;
drop policy if exists "managers and admins edit comments" on public.comments;
create policy "managers and admins edit comments"
  on public.comments for update
  to authenticated
  using (public.is_manager_or_admin())
  with check (public.is_manager_or_admin());

drop policy if exists "authors and admins delete comments" on public.comments;
drop policy if exists "managers and admins delete comments" on public.comments;
create policy "managers and admins delete comments"
  on public.comments for delete
  to authenticated
  using (public.is_manager_or_admin());

-- --------------------------------------------------------------------------
-- Deleting a task is a planning action too.
-- --------------------------------------------------------------------------

drop policy if exists "managers admins and creators delete tasks" on public.tasks;
drop policy if exists "managers and admins delete tasks" on public.tasks;
create policy "managers and admins delete tasks"
  on public.tasks for delete
  to authenticated
  using (public.is_manager_or_admin());

-- --------------------------------------------------------------------------
-- Exposed so the UI can render details read-only rather than letting someone
-- type into a field whose save is going to be refused.
-- --------------------------------------------------------------------------

create or replace function public.can_manage_task_details()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_manager_or_admin();
$$;

grant execute on function public.can_manage_task_details() to authenticated;

-- =========================================================================
-- 20260913000010_fix_delete_task_audit.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Fix: deleting a task failed when it had assignees.
--
-- Deleting a task cascades to task_assignments, which fires the audit trigger,
-- which tried to append an 'assignee_removed' row to task_activity. By then
-- the parent task is already gone, so that insert violated
-- task_activity_task_id_fkey and the whole DELETE was rolled back:
--
--   insert or update on table "task_activity" violates foreign key constraint
--   "task_activity_task_id_fkey"
--
-- The fix is to skip logging when the task no longer exists. Nothing is lost:
-- task_activity rows cascade away with the task, so those entries would have
-- been deleted in the same statement.
--
-- notify_assignment already guarded this case; log_assignment_change did not.
-- ---------------------------------------------------------------------------

create or replace function public.log_assignment_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target    uuid;
  label     text;
  parent_id uuid;
begin
  parent_id := case when tg_op = 'INSERT' then new.task_id else old.task_id end;

  -- The assignment is cascading away with its task; there is nothing to log.
  if not exists (select 1 from public.tasks where id = parent_id) then
    return null;
  end if;

  target := case when tg_op = 'INSERT' then new.user_id else old.user_id end;

  select coalesce(p.full_name, p.email) into label
  from public.profiles p where p.id = target;

  if tg_op = 'INSERT' then
    insert into public.task_activity (task_id, actor_id, action, field, new_value)
    values (new.task_id, auth.uid(), 'assignee_added', 'assignees', label);
  else
    insert into public.task_activity (task_id, actor_id, action, field, old_value)
    values (old.task_id, auth.uid(), 'assignee_removed', 'assignees', label);
  end if;

  return null;
end;
$$;

-- =========================================================================
-- 20260913000011_due_time_and_positions.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Due dates gain a time of day, and profiles gain a job position.
-- ---------------------------------------------------------------------------

-- --------------------------------------------------------------------------
-- tasks.due_date (date) -> tasks.due_at (timestamptz)
--
-- Renamed rather than reused: a column called due_date holding a time of day
-- would mislead every future reader. Existing dates are interpreted as the end
-- of that day, so nothing that was not yet overdue silently becomes overdue.
-- --------------------------------------------------------------------------

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'tasks' and column_name = 'due_date'
  ) then
    alter table public.tasks
      alter column due_date type timestamptz
      using (due_date::timestamp + interval '23 hours 59 minutes');

    alter table public.tasks rename column due_date to due_at;
  end if;
end $$;

comment on column public.tasks.due_at is
  'When the task is due, including time of day. Stored as an absolute instant.';

drop index if exists public.tasks_open_due_date_idx;
create index if not exists tasks_open_due_at_idx
  on public.tasks (due_at)
  where status <> 'done' and due_at is not null;

-- The audit trigger references the old column name.
create or replace function public.log_task_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor uuid := auth.uid();
begin
  if new.status is distinct from old.status then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'status_changed', 'status', old.status::text, new.status::text);
  end if;

  if new.priority is distinct from old.priority then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'priority_changed', 'priority', old.priority::text, new.priority::text);
  end if;

  if new.due_at is distinct from old.due_at then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'due_date_changed', 'due_at', old.due_at::text, new.due_at::text);
  end if;

  if new.title is distinct from old.title then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'updated', 'title', old.title, new.title);
  end if;

  if new.description is distinct from old.description then
    insert into public.task_activity (task_id, actor_id, action, field)
    values (new.id, actor, 'updated', 'description');
  end if;

  return null;
end;
$$;

-- The member field guard references it too.
create or replace function public.enforce_task_field_permissions()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if public.is_manager_or_admin() then
    return new;
  end if;

  if new.title is distinct from old.title
     or new.description is distinct from old.description
     or new.priority is distinct from old.priority
     or new.due_at is distinct from old.due_at
     or new.project_id is distinct from old.project_id
  then
    raise exception 'Only a manager or admin can change task details. You can update the status and add comments or files.'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

-- --------------------------------------------------------------------------
-- profiles.job_title
--
-- Named job_title, not "position": tasks.position already means sort order in
-- this schema, and reusing the word for something unrelated invites mistakes.
-- The UI labels it "Position".
-- --------------------------------------------------------------------------

alter table public.profiles
  add column if not exists job_title text;

alter table public.profiles
  drop constraint if exists profiles_job_title_length;
alter table public.profiles
  add constraint profiles_job_title_length
  check (job_title is null or length(btrim(job_title)) between 1 and 60);

-- Positions are assigned, not self-declared: the same guard that blocks
-- self-promotion now also pins job_title for anyone who is not an admin.
create or replace function public.guard_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.role is distinct from old.role and not public.is_admin() then
    raise exception 'Only an admin can change a profile role'
      using errcode = 'insufficient_privilege';
  end if;

  if new.job_title is distinct from old.job_title and not public.is_admin() then
    raise exception 'Only an admin can change a job position'
      using errcode = 'insufficient_privilege';
  end if;

  -- id and email track auth.users and are not user-editable.
  new.id := old.id;
  new.email := old.email;

  return new;
end;
$$;

-- --------------------------------------------------------------------------
-- Avatars bucket
--
-- Public, unlike task attachments: avatars are rendered in lists all over the
-- app, and signing every one of them per request would be pure overhead for
-- images that carry nothing sensitive. Writes stay locked to the owner.
--
-- Object keys are "<user_id>/<file>", so the first path segment is the owner.
-- --------------------------------------------------------------------------

do $$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'storage schema not found - skipping avatar bucket';
    return;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit)
  values ('avatars', 'avatars', true, 2097152)
  on conflict (id) do update
    set public = true,
        file_size_limit = excluded.file_size_limit;

  execute $p$drop policy if exists "avatars are publicly readable" on storage.objects$p$;
  execute $p$create policy "avatars are publicly readable"
    on storage.objects for select
    using (bucket_id = 'avatars')$p$;

  execute $p$drop policy if exists "users upload their own avatar" on storage.objects$p$;
  execute $p$create policy "users upload their own avatar"
    on storage.objects for insert
    to authenticated
    with check (
      bucket_id = 'avatars'
      and nullif(split_part(name, '/', 1), '') = auth.uid()::text
    )$p$;

  execute $p$drop policy if exists "users replace their own avatar" on storage.objects$p$;
  execute $p$create policy "users replace their own avatar"
    on storage.objects for update
    to authenticated
    using (
      bucket_id = 'avatars'
      and nullif(split_part(name, '/', 1), '') = auth.uid()::text
    )$p$;

  execute $p$drop policy if exists "users remove their own avatar" on storage.objects$p$;
  execute $p$create policy "users remove their own avatar"
    on storage.objects for delete
    to authenticated
    using (
      bucket_id = 'avatars'
      and (
        nullif(split_part(name, '/', 1), '') = auth.uid()::text
        or public.is_admin()
      )
    )$p$;
end $$;

-- =========================================================================
-- 20260913000012_project_membership.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Project membership
--
-- Until now every signed-in employee could read the whole workspace. Projects
-- are now private to the people on them: if you are not a member you do not
-- see the project, its tasks, its comments, its files or its history.
--
-- Who sees a project
--   * admins           — everything, so the workspace stays administrable
--   * project members   — the people explicitly added to it
--   * the creator       — added as a member automatically
--
-- Membership is granted two ways, so assigning work can never produce a task
-- its assignee cannot open:
--   1. explicitly, by an admin or manager
--   2. automatically, when someone is assigned a task in that project
--
-- General tasks (no project) follow the same principle: assignees and the
-- creator see them, and so do managers and admins.
-- ---------------------------------------------------------------------------

create table if not exists public.project_members (
  project_id uuid not null references public.projects (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  added_by   uuid references public.profiles (id) on delete set null,
  added_at   timestamptz not null default now(),

  primary key (project_id, user_id)
);

create index if not exists project_members_user_idx
  on public.project_members (user_id);

comment on table public.project_members is
  'Who can see a project. Membership is the unit of project visibility.';

-- --------------------------------------------------------------------------
-- Visibility helpers
--
-- SECURITY DEFINER so they can read project_members without going through the
-- policies that are themselves defined in terms of these functions.
-- --------------------------------------------------------------------------

create or replace function public.can_view_project(project uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    project is not null
    and (
      public.is_admin()
      or exists (
        select 1 from public.project_members m
        where m.project_id = project and m.user_id = auth.uid()
      )
      or exists (
        select 1 from public.projects p
        where p.id = project and p.created_by = auth.uid()
      )
    );
$$;

-- A task is visible when its project is, or — for a general task — when the
-- caller is its creator, an assignee, or a manager or admin.
create or replace function public.can_view_task(task uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.tasks t
    where t.id = task
      and (
        case
          when t.project_id is not null then public.can_view_project(t.project_id)
          else
            public.is_manager_or_admin()
            or t.created_by = auth.uid()
            or exists (
              select 1 from public.task_assignments a
              where a.task_id = t.id and a.user_id = auth.uid()
            )
        end
      )
  );
$$;

grant execute on function public.can_view_project(uuid) to authenticated;
grant execute on function public.can_view_task(uuid) to authenticated;

-- --------------------------------------------------------------------------
-- Keeping membership in step
-- --------------------------------------------------------------------------

-- Whoever creates a project is on it.
create or replace function public.add_project_creator_as_member()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.created_by is not null then
    insert into public.project_members (project_id, user_id, added_by)
    values (new.id, new.created_by, new.created_by)
    on conflict do nothing;
  end if;
  return null;
end;
$$;

drop trigger if exists projects_add_creator on public.projects;
create trigger projects_add_creator
  after insert on public.projects
  for each row execute function public.add_project_creator_as_member();

-- Being given a task in a project puts you on that project. Without this, a
-- manager could assign work that its assignee is not allowed to open.
create or replace function public.add_assignee_as_project_member()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target_project uuid;
begin
  select project_id into target_project from public.tasks where id = new.task_id;

  if target_project is not null then
    insert into public.project_members (project_id, user_id, added_by)
    values (target_project, new.user_id, auth.uid())
    on conflict do nothing;
  end if;

  return null;
end;
$$;

drop trigger if exists task_assignments_add_project_member on public.task_assignments;
create trigger task_assignments_add_project_member
  after insert on public.task_assignments
  for each row execute function public.add_assignee_as_project_member();

-- --------------------------------------------------------------------------
-- Backfill
--
-- Existing projects have no members yet. Without this every project would
-- vanish for everyone but admins the moment this migration lands.
-- --------------------------------------------------------------------------

insert into public.project_members (project_id, user_id, added_by)
select p.id, p.created_by, p.created_by
from public.projects p
where p.created_by is not null
on conflict do nothing;

insert into public.project_members (project_id, user_id)
select distinct t.project_id, a.user_id
from public.task_assignments a
join public.tasks t on t.id = a.task_id
where t.project_id is not null
on conflict do nothing;

-- --------------------------------------------------------------------------
-- RLS on project_members itself
-- --------------------------------------------------------------------------

alter table public.project_members enable row level security;
alter table public.project_members force row level security;

drop policy if exists "members readable within visible projects" on public.project_members;
create policy "members readable within visible projects"
  on public.project_members for select
  to authenticated
  using (public.can_view_project(project_id));

drop policy if exists "managers and admins add project members" on public.project_members;
create policy "managers and admins add project members"
  on public.project_members for insert
  to authenticated
  with check (public.is_manager_or_admin() and public.can_view_project(project_id));

drop policy if exists "managers and admins remove project members" on public.project_members;
create policy "managers and admins remove project members"
  on public.project_members for delete
  to authenticated
  using (public.is_manager_or_admin() and public.can_view_project(project_id));

grant select, insert, delete on public.project_members to authenticated;

-- --------------------------------------------------------------------------
-- Narrow every read policy to what the caller can actually see
-- --------------------------------------------------------------------------

drop policy if exists "projects are readable by authenticated users" on public.projects;
drop policy if exists "projects are readable by members" on public.projects;
create policy "projects are readable by members"
  on public.projects for select
  to authenticated
  using (public.can_view_project(id));

drop policy if exists "tasks are readable by authenticated users" on public.tasks;
drop policy if exists "tasks are readable within visible projects" on public.tasks;
create policy "tasks are readable within visible projects"
  on public.tasks for select
  to authenticated
  using (
    case
      when project_id is not null then public.can_view_project(project_id)
      else
        public.is_manager_or_admin()
        or created_by = auth.uid()
        or exists (
          select 1 from public.task_assignments a
          where a.task_id = tasks.id and a.user_id = auth.uid()
        )
    end
  );

drop policy if exists "assignments are readable by authenticated users" on public.task_assignments;
drop policy if exists "assignments readable within visible tasks" on public.task_assignments;
create policy "assignments readable within visible tasks"
  on public.task_assignments for select
  to authenticated
  using (public.can_view_task(task_id));

drop policy if exists "comments are readable by authenticated users" on public.comments;
drop policy if exists "comments readable within visible tasks" on public.comments;
create policy "comments readable within visible tasks"
  on public.comments for select
  to authenticated
  using (public.can_view_task(task_id));

drop policy if exists "activity is readable by authenticated users" on public.task_activity;
drop policy if exists "activity readable within visible tasks" on public.task_activity;
create policy "activity readable within visible tasks"
  on public.task_activity for select
  to authenticated
  using (public.can_view_task(task_id));

drop policy if exists "attachments are readable by authenticated users" on public.task_attachments;
drop policy if exists "attachments readable within visible tasks" on public.task_attachments;
create policy "attachments readable within visible tasks"
  on public.task_attachments for select
  to authenticated
  using (public.can_view_task(task_id));

-- Writing follows seeing: you cannot add a task, comment or file to something
-- you are not allowed to look at.
drop policy if exists "authenticated users create tasks" on public.tasks;
create policy "authenticated users create tasks"
  on public.tasks for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and (
      case
        when project_id is not null then public.can_view_project(project_id)
        else public.is_manager_or_admin()
      end
    )
  );

drop policy if exists "users write their own comments" on public.comments;
create policy "users write their own comments"
  on public.comments for insert
  to authenticated
  with check (user_id = auth.uid() and public.can_view_task(task_id));

-- profiles stay readable workspace-wide: the assignee picker, @mentions and
-- the team page all need the directory, and a name and role are not the
-- sensitive part of a project.

-- =========================================================================
-- 20260913000013_follow_ups.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Follow-ups
--
-- A task can carry a date to chase it on, plus a note saying what to chase
-- ("call the supplier Tuesday"). The follow-up list reads from these.
--
-- Stored as columns rather than a separate table: a task has one *next*
-- follow-up at a time, and the history of previous ones is already captured by
-- the audit trail below.
-- ---------------------------------------------------------------------------

alter table public.tasks
  add column if not exists follow_up_at timestamptz;

alter table public.tasks
  add column if not exists follow_up_note text;

alter table public.tasks
  drop constraint if exists tasks_follow_up_note_length;
alter table public.tasks
  add constraint tasks_follow_up_note_length
  check (follow_up_note is null or length(btrim(follow_up_note)) between 1 and 500);

-- A note without a date would never surface in the list.
alter table public.tasks
  drop constraint if exists tasks_follow_up_note_needs_date;
alter table public.tasks
  add constraint tasks_follow_up_note_needs_date
  check (follow_up_note is null or follow_up_at is not null);

comment on column public.tasks.follow_up_at is
  'When this task should next be chased. Drives the follow-up list.';

create index if not exists tasks_follow_up_idx
  on public.tasks (follow_up_at)
  where follow_up_at is not null and status <> 'done';

-- --------------------------------------------------------------------------
-- Follow-ups are planning, like the due date, so they follow the same rule:
-- managers and admins set them, members see them.
-- --------------------------------------------------------------------------

create or replace function public.enforce_task_field_permissions()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if public.is_manager_or_admin() then
    return new;
  end if;

  if new.title is distinct from old.title
     or new.description is distinct from old.description
     or new.priority is distinct from old.priority
     or new.due_at is distinct from old.due_at
     or new.project_id is distinct from old.project_id
     or new.follow_up_at is distinct from old.follow_up_at
     or new.follow_up_note is distinct from old.follow_up_note
  then
    raise exception 'Only a manager or admin can change task details. You can update the status and add comments or files.'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

-- --------------------------------------------------------------------------
-- Audit follow-up changes, so the history of what was chased and when survives
-- even though only the next one is stored.
-- --------------------------------------------------------------------------

alter table public.task_activity
  drop constraint if exists task_activity_action_known;
alter table public.task_activity
  add constraint task_activity_action_known check (
    action in (
      'created',
      'updated',
      'status_changed',
      'priority_changed',
      'due_date_changed',
      'follow_up_set',
      'follow_up_cleared',
      'assignee_added',
      'assignee_removed',
      'commented'
    )
  );

create or replace function public.log_task_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor uuid := auth.uid();
begin
  if new.status is distinct from old.status then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'status_changed', 'status', old.status::text, new.status::text);
  end if;

  if new.priority is distinct from old.priority then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'priority_changed', 'priority', old.priority::text, new.priority::text);
  end if;

  if new.due_at is distinct from old.due_at then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'due_date_changed', 'due_at', old.due_at::text, new.due_at::text);
  end if;

  if new.follow_up_at is distinct from old.follow_up_at
     or new.follow_up_note is distinct from old.follow_up_note then
    if new.follow_up_at is null then
      insert into public.task_activity (task_id, actor_id, action, field, old_value)
      values (new.id, actor, 'follow_up_cleared', 'follow_up_at', old.follow_up_at::text);
    else
      insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
      values (
        new.id, actor, 'follow_up_set', 'follow_up_at',
        old.follow_up_at::text,
        new.follow_up_at::text ||
          coalesce(' - ' || nullif(btrim(new.follow_up_note), ''), '')
      );
    end if;
  end if;

  if new.title is distinct from old.title then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'updated', 'title', old.title, new.title);
  end if;

  if new.description is distinct from old.description then
    insert into public.task_activity (task_id, actor_id, action, field)
    values (new.id, actor, 'updated', 'description');
  end if;

  return null;
end;
$$;

-- =========================================================================
-- 20260913000014_reminders.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Task reminders over email, Telegram and WhatsApp
--
-- Two tables:
--   notification_preferences — which channels a person wants, where to reach
--                              them, and which events are worth interrupting
--                              them for
--   reminder_queue           — one row per message to send, drained by a
--                              scheduled dispatcher in the app
--
-- Queuing rather than sending inline means a provider outage cannot lose a
-- reminder, retries are bounded and visible, and the same reminder can never
-- go out twice — see dedupe_key.
-- ---------------------------------------------------------------------------

-- --------------------------------------------------------------------------
-- Preferences
-- --------------------------------------------------------------------------

create table if not exists public.notification_preferences (
  user_id uuid primary key references public.profiles (id) on delete cascade,

  -- Channels. Email is on by default because the address is already known and
  -- verified by sign-up; the other two need details the user has to supply.
  email_enabled    boolean not null default true,
  telegram_enabled boolean not null default false,
  whatsapp_enabled boolean not null default false,

  -- Where to reach them.
  telegram_chat_id  text,
  whatsapp_number   text,

  -- A short-lived code the user sends to the bot to prove the chat is theirs.
  telegram_link_code text,

  -- Which events are worth a message.
  remind_assigned   boolean not null default true,
  remind_due_soon   boolean not null default true,
  remind_overdue    boolean not null default true,
  remind_follow_up  boolean not null default true,

  -- How far ahead of the due time to warn.
  due_soon_lead_hours integer not null default 24,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint notification_preferences_lead_range
    check (due_soon_lead_hours between 1 and 168),

  -- E.164, the format every WhatsApp provider expects.
  constraint notification_preferences_whatsapp_format
    check (whatsapp_number is null or whatsapp_number ~ '^\+[1-9]\d{6,14}$'),

  -- A channel cannot be switched on without somewhere to send to.
  constraint notification_preferences_telegram_needs_chat
    check (not telegram_enabled or telegram_chat_id is not null),
  constraint notification_preferences_whatsapp_needs_number
    check (not whatsapp_enabled or whatsapp_number is not null)
);

create unique index if not exists notification_preferences_link_code_key
  on public.notification_preferences (telegram_link_code)
  where telegram_link_code is not null;

drop trigger if exists notification_preferences_set_updated_at on public.notification_preferences;
create trigger notification_preferences_set_updated_at
  before update on public.notification_preferences
  for each row execute function public.set_updated_at();

-- Everyone gets a row, so the dispatcher never has to reason about its absence.
create or replace function public.ensure_notification_preferences()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return null;
end;
$$;

drop trigger if exists profiles_ensure_notification_preferences on public.profiles;
create trigger profiles_ensure_notification_preferences
  after insert on public.profiles
  for each row execute function public.ensure_notification_preferences();

insert into public.notification_preferences (user_id)
select id from public.profiles
on conflict (user_id) do nothing;

-- --------------------------------------------------------------------------
-- Outbound queue
-- --------------------------------------------------------------------------

create table if not exists public.reminder_queue (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  task_id    uuid references public.tasks (id) on delete cascade,

  channel    text not null check (channel in ('email', 'telegram', 'whatsapp')),
  kind       text not null check (kind in ('assigned', 'due_soon', 'overdue', 'follow_up')),

  recipient  text not null,
  subject    text,
  body       text not null,

  status     text not null default 'pending'
             check (status in ('pending', 'sent', 'failed', 'cancelled')),
  attempts   integer not null default 0,
  last_error text,

  -- Identifies the exact reminder, so re-running the scheduler cannot send the
  -- same thing twice. Changing a due date changes the key, which is what makes
  -- a rescheduled task legitimately remind again.
  dedupe_key text not null unique,

  scheduled_for timestamptz not null default now(),
  sent_at       timestamptz,
  created_at    timestamptz not null default now()
);

-- The dispatcher's query: what is pending and due, oldest first.
create index if not exists reminder_queue_pending_idx
  on public.reminder_queue (scheduled_for)
  where status = 'pending';

create index if not exists reminder_queue_user_idx
  on public.reminder_queue (user_id, created_at desc);

-- --------------------------------------------------------------------------
-- Row Level Security
--
-- Reminders are personal. A user may read their own to see what was sent, and
-- nothing else: the queue is written by the scheduler below and drained by the
-- dispatcher, both of which run outside RLS.
-- --------------------------------------------------------------------------

alter table public.notification_preferences enable row level security;
alter table public.notification_preferences force row level security;
alter table public.reminder_queue enable row level security;
alter table public.reminder_queue force row level security;

drop policy if exists "users read their own preferences" on public.notification_preferences;
create policy "users read their own preferences"
  on public.notification_preferences for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "users update their own preferences" on public.notification_preferences;
create policy "users update their own preferences"
  on public.notification_preferences for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "users read their own reminders" on public.reminder_queue;
create policy "users read their own reminders"
  on public.reminder_queue for select
  to authenticated
  using (user_id = auth.uid());

grant select, update on public.notification_preferences to authenticated;
grant select on public.reminder_queue to authenticated;

-- --------------------------------------------------------------------------
-- Scheduling
--
-- Builds the queue from the current state of the tasks table. Safe to call as
-- often as you like: every insert is keyed, so repeat runs are no-ops until
-- something actually changes.
-- --------------------------------------------------------------------------

create or replace function public.enqueue_task_reminders()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  inserted integer := 0;
begin
  -- Work that is due within the recipient's chosen lead time.
  with candidates as (
    select
      t.id as task_id, t.title, t.due_at,
      a.user_id,
      p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled,
      np.telegram_chat_id, np.whatsapp_number, np.due_soon_lead_hours
    from public.tasks t
    join public.task_assignments a on a.task_id = t.id
    join public.profiles p on p.id = a.user_id
    join public.notification_preferences np on np.user_id = a.user_id
    where t.status <> 'done'
      and t.due_at is not null
      and np.remind_due_soon
      and t.due_at > now()
      and t.due_at <= now() + make_interval(hours => np.due_soon_lead_hours)
  )
  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    c.user_id, c.task_id, ch.channel, 'due_soon',
    case ch.channel
      when 'email' then c.email
      when 'telegram' then c.telegram_chat_id
      else c.whatsapp_number
    end,
    'Due soon: ' || c.title,
    c.title || ' is due ' || to_char(c.due_at at time zone 'UTC', 'DD Mon HH24:MI') || ' UTC.',
    'due_soon:' || c.task_id || ':' || c.user_id || ':' || ch.channel || ':' || extract(epoch from c.due_at)::bigint
  from candidates c
  cross join lateral (
    select 'email'::text as channel where c.email_enabled
    union all select 'telegram' where c.telegram_enabled and c.telegram_chat_id is not null
    union all select 'whatsapp' where c.whatsapp_enabled and c.whatsapp_number is not null
  ) ch
  on conflict (dedupe_key) do nothing;

  get diagnostics inserted = row_count;

  -- Work that is already late. Keyed by the day so a task that stays overdue
  -- nags once a day rather than on every scheduler run.
  with candidates as (
    select
      t.id as task_id, t.title, t.due_at,
      a.user_id, p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled,
      np.telegram_chat_id, np.whatsapp_number, np.due_soon_lead_hours
    from public.tasks t
    join public.task_assignments a on a.task_id = t.id
    join public.profiles p on p.id = a.user_id
    join public.notification_preferences np on np.user_id = a.user_id
    where t.status <> 'done'
      and t.due_at is not null
      and t.due_at < now()
      and np.remind_overdue
  )
  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    c.user_id, c.task_id, ch.channel, 'overdue',
    case ch.channel
      when 'email' then c.email
      when 'telegram' then c.telegram_chat_id
      else c.whatsapp_number
    end,
    'Overdue: ' || c.title,
    c.title || ' was due ' || to_char(c.due_at at time zone 'UTC', 'DD Mon HH24:MI') || ' UTC and is still open.',
    'overdue:' || c.task_id || ':' || c.user_id || ':' || ch.channel || ':' || to_char(now(), 'YYYY-MM-DD')
  from candidates c
  cross join lateral (
    select 'email'::text as channel where c.email_enabled
    union all select 'telegram' where c.telegram_enabled and c.telegram_chat_id is not null
    union all select 'whatsapp' where c.whatsapp_enabled and c.whatsapp_number is not null
  ) ch
  on conflict (dedupe_key) do nothing;

  -- Follow-ups that have come due, to whoever has to chase them.
  with candidates as (
    select
      t.id as task_id, t.title, t.follow_up_at, t.follow_up_note,
      a.user_id, p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled,
      np.telegram_chat_id, np.whatsapp_number, np.due_soon_lead_hours
    from public.tasks t
    join public.task_assignments a on a.task_id = t.id
    join public.profiles p on p.id = a.user_id
    join public.notification_preferences np on np.user_id = a.user_id
    where t.status <> 'done'
      and t.follow_up_at is not null
      and t.follow_up_at <= now()
      and np.remind_follow_up
  )
  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    c.user_id, c.task_id, ch.channel, 'follow_up',
    case ch.channel
      when 'email' then c.email
      when 'telegram' then c.telegram_chat_id
      else c.whatsapp_number
    end,
    'Follow up: ' || c.title,
    coalesce(c.follow_up_note, 'Time to follow up on ' || c.title) || ' (' || c.title || ')',
    'follow_up:' || c.task_id || ':' || c.user_id || ':' || ch.channel || ':' || extract(epoch from c.follow_up_at)::bigint
  from candidates c
  cross join lateral (
    select 'email'::text as channel where c.email_enabled
    union all select 'telegram' where c.telegram_enabled and c.telegram_chat_id is not null
    union all select 'whatsapp' where c.whatsapp_enabled and c.whatsapp_number is not null
  ) ch
  on conflict (dedupe_key) do nothing;

  return inserted;
end;
$$;

-- Being handed work is worth telling someone about immediately rather than
-- waiting for the next scheduler run.
create or replace function public.enqueue_assignment_reminder()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t public.tasks%rowtype;
  prefs public.notification_preferences%rowtype;
begin
  select * into t from public.tasks where id = new.task_id;
  if not found then return null; end if;

  select * into prefs from public.notification_preferences where user_id = new.user_id;
  if not found or not prefs.remind_assigned then return null; end if;

  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    new.user_id, t.id, ch.channel, 'assigned',
    ch.recipient,
    'Assigned to you: ' || t.title,
    'You were assigned "' || t.title || '"'
      || coalesce(' - due ' || to_char(t.due_at at time zone 'UTC', 'DD Mon HH24:MI') || ' UTC', '') || '.',
    'assigned:' || t.id || ':' || new.user_id || ':' || ch.channel
  from (
    select 'email'::text as channel, (select email from public.profiles where id = new.user_id) as recipient
      where prefs.email_enabled
    union all
    select 'telegram', prefs.telegram_chat_id
      where prefs.telegram_enabled and prefs.telegram_chat_id is not null
    union all
    select 'whatsapp', prefs.whatsapp_number
      where prefs.whatsapp_enabled and prefs.whatsapp_number is not null
  ) ch
  where ch.recipient is not null
  on conflict (dedupe_key) do nothing;

  return null;
end;
$$;

drop trigger if exists task_assignments_enqueue_reminder on public.task_assignments;
create trigger task_assignments_enqueue_reminder
  after insert on public.task_assignments
  for each row execute function public.enqueue_assignment_reminder();

-- =========================================================================
-- 20260913000015_members_see_only_assigned.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Team members see only the work given to them.
--
-- Tightens two things at once:
--
--   1. Creating a task becomes a manager/admin action. Members never create,
--      and (since migration 0009) never delete.
--   2. A member sees only tasks assigned to them — including inside a project
--      they belong to. Their board is their own work, not the team's.
--
-- What a member can still do on a task they are assigned:
--   * read it
--   * move its status, up to In Review
--   * comment on it
--   * attach files and links
--
-- Managers and admins are unchanged: they see the projects they are on, and
-- admins see everything.
-- ---------------------------------------------------------------------------

-- --------------------------------------------------------------------------
-- Creating a task
-- --------------------------------------------------------------------------

drop policy if exists "authenticated users create tasks" on public.tasks;
drop policy if exists "managers and admins create tasks" on public.tasks;
create policy "managers and admins create tasks"
  on public.tasks for insert
  to authenticated
  with check (
    public.is_manager_or_admin()
    and created_by = auth.uid()
    -- A project task still has to go in a project the creator can see.
    and (project_id is null or public.can_view_project(project_id))
  );

-- --------------------------------------------------------------------------
-- Seeing a task
--
-- can_view_task is the single definition the comment, activity, attachment and
-- assignment policies all resolve through, so changing it here narrows every
-- one of them in step.
-- --------------------------------------------------------------------------

create or replace function public.can_view_task(task uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.tasks t
    where t.id = task
      and (
        -- Assigned to me: the only route a member has.
        exists (
          select 1 from public.task_assignments a
          where a.task_id = t.id and a.user_id = auth.uid()
        )
        -- Managers and admins see whole projects; admins see every project.
        or (
          public.is_manager_or_admin()
          and (t.project_id is null or public.can_view_project(t.project_id))
        )
      )
  );
$$;

drop policy if exists "tasks are readable within visible projects" on public.tasks;
drop policy if exists "tasks are readable when assigned or managed" on public.tasks;
create policy "tasks are readable when assigned or managed"
  on public.tasks for select
  to authenticated
  using (
    exists (
      select 1 from public.task_assignments a
      where a.task_id = tasks.id and a.user_id = auth.uid()
    )
    or (
      public.is_manager_or_admin()
      and (project_id is null or public.can_view_project(project_id))
    )
  );

-- --------------------------------------------------------------------------
-- Assignments
--
-- A member may only see who else is on a task they can see. Without narrowing
-- this, the assignee list would leak the existence of tasks they cannot open.
-- --------------------------------------------------------------------------

drop policy if exists "assignments readable within visible tasks" on public.task_assignments;
drop policy if exists "assignments readable for visible tasks" on public.task_assignments;
create policy "assignments readable for visible tasks"
  on public.task_assignments for select
  to authenticated
  using (public.can_view_task(task_id));

-- --------------------------------------------------------------------------
-- Projects
--
-- Membership still decides whether a project is visible at all — a member needs
-- the project to exist in order to reach the task inside it. They simply see
-- none of its other tasks.
-- --------------------------------------------------------------------------

comment on function public.can_view_task(uuid) is
  'A task is visible when it is assigned to the caller, or when the caller is a manager or admin who can see its project.';

-- =========================================================================
-- 20260914000016_personal_notes.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- My List — personal notes
--
-- A private scratchpad for what someone has to get through today, separate
-- from the assigned-task system. Unlike everything else in this schema these
-- rows are visible to exactly one person: there is no manager override and no
-- admin override, because a personal list nobody else can read is the whole
-- point of it.
--
-- A note owns its checklist items. They are separate rows rather than a JSON
-- blob so that ticking one box is a single narrow UPDATE — the interaction
-- that has to feel instant on a phone — instead of rewriting the note.
-- ---------------------------------------------------------------------------

create table if not exists public.personal_notes (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  title      text not null default '',
  body       text not null default '',
  pinned     boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint personal_notes_title_length check (char_length(title) <= 200),
  constraint personal_notes_body_length check (char_length(body) <= 20000)
);

-- The list is ordered pinned-first then most recently touched, which is also
-- the only way it is ever read.
create index if not exists personal_notes_user_idx
  on public.personal_notes (user_id, pinned desc, updated_at desc);

create table if not exists public.personal_note_items (
  id         uuid primary key default gen_random_uuid(),
  note_id    uuid not null references public.personal_notes (id) on delete cascade,
  -- Denormalised from the note so the RLS policy is a plain column check and
  -- never has to look at another table.
  user_id    uuid not null references public.profiles (id) on delete cascade,
  content    text not null default '',
  done       boolean not null default false,
  position   double precision not null default 1024,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint personal_note_items_content_length check (char_length(content) <= 1000)
);

create index if not exists personal_note_items_note_idx
  on public.personal_note_items (note_id, position);

-- ---------------------------------------------------------------------------
-- Keep updated_at honest, and bubble item edits up to the note so the list
-- re-sorts when you tick something off.
-- ---------------------------------------------------------------------------

drop trigger if exists personal_notes_set_updated_at on public.personal_notes;
create trigger personal_notes_set_updated_at
  before update on public.personal_notes
  for each row execute function public.set_updated_at();

drop trigger if exists personal_note_items_set_updated_at on public.personal_note_items;
create trigger personal_note_items_set_updated_at
  before update on public.personal_note_items
  for each row execute function public.set_updated_at();

create or replace function public.touch_personal_note()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.personal_notes
     set updated_at = now()
   where id = coalesce(new.note_id, old.note_id);
  return coalesce(new, old);
end;
$$;

drop trigger if exists personal_note_items_touch_note on public.personal_note_items;
create trigger personal_note_items_touch_note
  after insert or update or delete on public.personal_note_items
  for each row execute function public.touch_personal_note();

-- ---------------------------------------------------------------------------
-- Row Level Security: your own rows, and nothing else.
-- ---------------------------------------------------------------------------

alter table public.personal_notes enable row level security;
alter table public.personal_notes force row level security;
alter table public.personal_note_items enable row level security;
alter table public.personal_note_items force row level security;

drop policy if exists "own notes are readable" on public.personal_notes;
create policy "own notes are readable"
  on public.personal_notes for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "own notes are writable" on public.personal_notes;
create policy "own notes are writable"
  on public.personal_notes for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "own notes are updatable" on public.personal_notes;
create policy "own notes are updatable"
  on public.personal_notes for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "own notes are deletable" on public.personal_notes;
create policy "own notes are deletable"
  on public.personal_notes for delete
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "own note items are readable" on public.personal_note_items;
create policy "own note items are readable"
  on public.personal_note_items for select
  to authenticated
  using (user_id = auth.uid());

-- The note must also be yours, so an item cannot be parked on someone else's
-- note by forging note_id.
drop policy if exists "own note items are writable" on public.personal_note_items;
create policy "own note items are writable"
  on public.personal_note_items for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.personal_notes n
       where n.id = note_id and n.user_id = auth.uid()
    )
  );

drop policy if exists "own note items are updatable" on public.personal_note_items;
create policy "own note items are updatable"
  on public.personal_note_items for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "own note items are deletable" on public.personal_note_items;
create policy "own note items are deletable"
  on public.personal_note_items for delete
  to authenticated
  using (user_id = auth.uid());

grant select, insert, update, delete on public.personal_notes to authenticated;
grant select, insert, update, delete on public.personal_note_items to authenticated;

-- =========================================================================
-- 20260914000017_claim_reminders_and_counts.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- 1. Stop the reminder dispatcher sending the same message twice
--
-- The dispatcher read pending rows, delivered them, then marked them sent. If
-- the serverless function hit its timeout between the delivery and the update
-- — which a batch of forty slow provider calls can do — the row stayed pending
-- and the next run sent it again. A second WhatsApp at 7am is not a harmless
-- bug.
--
-- Rows are now claimed before any provider is called. `claim_reminders` moves
-- a batch to 'sending' and returns it, in one statement, with SKIP LOCKED so
-- two overlapping runs cannot claim the same row. A row that ends up stranded
-- in 'sending' (the function died mid-flight) is released by the next run
-- after a grace period, which is the one case where a duplicate is still
-- possible and is far better than the alternative of never retrying at all.
-- ---------------------------------------------------------------------------

alter table public.reminder_queue
  drop constraint if exists reminder_queue_status_check;

alter table public.reminder_queue
  add constraint reminder_queue_status_check
  check (status in ('pending', 'sending', 'sent', 'failed', 'cancelled'));

-- When the row was picked up, so a stranded claim can be spotted and released.
alter table public.reminder_queue
  add column if not exists claimed_at timestamptz;

create index if not exists reminder_queue_claimed_idx
  on public.reminder_queue (claimed_at)
  where status = 'sending';

/**
 * Claim a batch of due reminders.
 *
 * SECURITY DEFINER because only the service-role dispatcher calls it, and it
 * must see every user's queue. search_path is pinned so a caller cannot
 * shadow the tables it touches.
 */
create or replace function public.claim_reminders(batch_size integer default 40)
returns setof public.reminder_queue
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Release anything left 'sending' by a run that died. Ten minutes is far
  -- longer than any provider call and any function timeout.
  update public.reminder_queue
     set status = 'pending', claimed_at = null
   where status = 'sending'
     and claimed_at < now() - interval '10 minutes';

  return query
  with due as (
    select id
      from public.reminder_queue
     where status = 'pending'
       and scheduled_for <= now()
     order by scheduled_for
     limit greatest(1, least(batch_size, 200))
     -- Two dispatchers running at once take different rows instead of
     -- blocking on each other and then both sending.
     for update skip locked
  )
  update public.reminder_queue q
     set status = 'sending', claimed_at = now()
    from due
   where q.id = due.id
  returning q.*;
end;
$$;

revoke all on function public.claim_reminders(integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Count tasks in the database instead of in the browser
--
-- The dashboard read every task the viewer could see and counted them in
-- JavaScript. That is fine at fifty tasks and wasteful at five thousand: the
-- rows were fetched, serialised and shipped only to be reduced to six numbers.
--
-- SECURITY INVOKER (the default) on purpose — the counts must be filtered by
-- the caller's own RLS, exactly as the old query was.
-- ---------------------------------------------------------------------------

create or replace function public.task_counts()
returns table (
  total       bigint,
  done        bigint,
  todo        bigint,
  in_progress bigint,
  in_review   bigint,
  overdue     bigint,
  due_today   bigint
)
language sql
stable
set search_path = public, pg_temp
as $$
  select
    count(*)                                                        as total,
    count(*) filter (where status = 'done')                         as done,
    count(*) filter (where status = 'todo')                         as todo,
    count(*) filter (where status = 'in_progress')                  as in_progress,
    count(*) filter (where status = 'in_review')                    as in_review,
    count(*) filter (where status <> 'done' and due_at < now())     as overdue,
    count(*) filter (
      where status <> 'done'
        and due_at >= date_trunc('day', now())
        and due_at <  date_trunc('day', now()) + interval '1 day'
    )                                                               as due_today
  from public.tasks;
$$;

grant execute on function public.task_counts() to authenticated;

/**
 * Per-assignee workload, for the dashboard's "who is busy" panel.
 *
 * The other half of the same problem: this was computed by walking every task
 * and every assignment in JavaScript. SECURITY INVOKER again, so a member
 * sees only their own row and a manager sees their team.
 */
create or replace function public.workload_counts()
returns table (
  user_id uuid,
  open    bigint,
  done    bigint,
  overdue bigint
)
language sql
stable
set search_path = public, pg_temp
as $$
  select
    a.user_id,
    count(*) filter (where t.status <> 'done')                     as open,
    count(*) filter (where t.status = 'done')                      as done,
    count(*) filter (where t.status <> 'done' and t.due_at < now()) as overdue
  from public.task_assignments a
  join public.tasks t on t.id = a.task_id
  group by a.user_id;
$$;

grant execute on function public.workload_counts() to authenticated;

-- =========================================================================
-- 20260914000018_task_counts_timezone.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- "Due Today" means today where the viewer is
--
-- task_counts() decided what was due today with date_trunc('day', now()),
-- which is midnight in the *database's* timezone — UTC on Supabase. Every
-- other place in the app asks the browser, so it uses the viewer's calendar
-- day. Four hours east of UTC the two disagree for a quarter of every day: a
-- task due at 02:00 on Tuesday local time is 22:00 Monday in UTC, so the
-- dashboard tile counted it as due today while the list it opens showed
-- nothing. Overdue was never affected — an instant is an instant.
--
-- The caller now passes its IANA timezone, and the count is taken on that
-- calendar. An unknown or missing name falls back to UTC rather than raising,
-- so a stale or hand-edited cookie cannot break the dashboard.
-- ---------------------------------------------------------------------------

-- The old signature has to go first: with both defined, task_counts() with no
-- arguments is ambiguous and Postgres refuses to choose.
drop function if exists public.task_counts();

create or replace function public.task_counts(tz text default 'UTC')
returns table (
  total       bigint,
  done        bigint,
  todo        bigint,
  in_progress bigint,
  in_review   bigint,
  overdue     bigint,
  due_today   bigint
)
language sql
stable
set search_path = public, pg_temp
as $$
  with zone as (
    select coalesce(
      (select name from pg_timezone_names where name = tz),
      'UTC'
    ) as name
  )
  select
    count(*)                                                        as total,
    count(*) filter (where t.status = 'done')                       as done,
    count(*) filter (where t.status = 'todo')                       as todo,
    count(*) filter (where t.status = 'in_progress')                as in_progress,
    count(*) filter (where t.status = 'in_review')                  as in_review,
    count(*) filter (where t.status <> 'done' and t.due_at < now()) as overdue,
    count(*) filter (
      where t.status <> 'done'
        and t.due_at is not null
        -- Both sides converted to wall-clock time in the viewer's zone, then
        -- compared as dates: exactly what the browser does.
        and (t.due_at at time zone z.name)::date = (now() at time zone z.name)::date
    )                                                               as due_today
  from public.tasks t
  cross join zone z;
$$;

comment on function public.task_counts(text) is
  'Dashboard figures under the caller''s RLS. Pass an IANA timezone so "due today" means the viewer''s day; unknown names fall back to UTC.';

grant execute on function public.task_counts(text) to authenticated;

-- =========================================================================
-- 20260914000019_shared_notes.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Sharing a list
--
-- My List was built for exactly one reader — no manager override, no admin
-- override — and that stays true of every list nobody has been invited to.
-- What changes is that the owner can invite specific people, one list at a
-- time, and take the invitation back.
--
-- Who can do what on a shared list:
--
--   owner         everything, including deleting the list and managing who
--                 else is on it
--   collaborator  read it, write its text, and add, tick, edit or remove
--                 lines — a shared checklist that only one person may tick is
--                 not a shared checklist
--   collaborator  may also remove themselves, which is how you leave a list
--   anyone else   nothing, exactly as before
--
-- Ownership never moves: the guard below pins user_id through every update,
-- so a collaborator cannot make a list theirs.
-- ---------------------------------------------------------------------------

create table if not exists public.personal_note_shares (
  note_id  uuid not null references public.personal_notes (id) on delete cascade,
  user_id  uuid not null references public.profiles (id) on delete cascade,
  added_by uuid references public.profiles (id) on delete set null,
  added_at timestamptz not null default now(),

  primary key (note_id, user_id)
);

create index if not exists personal_note_shares_user_idx
  on public.personal_note_shares (user_id);

comment on table public.personal_note_shares is
  'Who a personal list has been shared with. Absence of a row is privacy.';

-- --------------------------------------------------------------------------
-- Visibility helpers
--
-- SECURITY DEFINER so they can read the notes and shares tables without going
-- through the policies that are themselves written in terms of them.
-- --------------------------------------------------------------------------

create or replace function public.owns_note(note uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.personal_notes n
     where n.id = note and n.user_id = auth.uid()
  );
$$;

create or replace function public.can_view_note(note uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    public.owns_note(note)
    or exists (
      select 1 from public.personal_note_shares s
       where s.note_id = note and s.user_id = auth.uid()
    );
$$;

grant execute on function public.owns_note(uuid) to authenticated;
grant execute on function public.can_view_note(uuid) to authenticated;

-- --------------------------------------------------------------------------
-- Ownership and parentage are not editable
--
-- Without this an update could rewrite user_id — handing a list to yourself,
-- or away to somebody else — or move a line onto a different note.
-- --------------------------------------------------------------------------

create or replace function public.guard_note_owner()
returns trigger
language plpgsql
as $$
begin
  new.user_id := old.user_id;
  return new;
end;
$$;

drop trigger if exists personal_notes_guard_owner on public.personal_notes;
create trigger personal_notes_guard_owner
  before update on public.personal_notes
  for each row execute function public.guard_note_owner();

create or replace function public.guard_note_item_parent()
returns trigger
language plpgsql
as $$
begin
  new.user_id := old.user_id;
  new.note_id := old.note_id;
  return new;
end;
$$;

drop trigger if exists personal_note_items_guard_parent on public.personal_note_items;
create trigger personal_note_items_guard_parent
  before update on public.personal_note_items
  for each row execute function public.guard_note_item_parent();

-- --------------------------------------------------------------------------
-- Notes: read and write for everyone on the list, delete for its owner
-- --------------------------------------------------------------------------

alter table public.personal_note_shares enable row level security;
alter table public.personal_note_shares force row level security;

drop policy if exists "own notes are readable" on public.personal_notes;
drop policy if exists "notes are readable by their people" on public.personal_notes;
create policy "notes are readable by their people"
  on public.personal_notes for select
  to authenticated
  using (public.can_view_note(id));

drop policy if exists "own notes are updatable" on public.personal_notes;
drop policy if exists "notes are writable by their people" on public.personal_notes;
create policy "notes are writable by their people"
  on public.personal_notes for update
  to authenticated
  using (public.can_view_note(id))
  with check (public.can_view_note(id));

-- Deleting somebody's list is not collaboration. A collaborator leaves by
-- removing their own share row instead.
drop policy if exists "own notes are deletable" on public.personal_notes;
drop policy if exists "notes are deletable by their owner" on public.personal_notes;
create policy "notes are deletable by their owner"
  on public.personal_notes for delete
  to authenticated
  using (user_id = auth.uid());

-- --------------------------------------------------------------------------
-- Lines: whoever can see the list can work it
--
-- The item policies used to be a plain user_id check, which is why the column
-- was denormalised onto the row in the first place. It stays — as a record of
-- who added a line — but visibility now resolves through the note, because on
-- a shared list the lines are not all the same person's.
-- --------------------------------------------------------------------------

drop policy if exists "own note items are readable" on public.personal_note_items;
drop policy if exists "note items are readable by their people" on public.personal_note_items;
create policy "note items are readable by their people"
  on public.personal_note_items for select
  to authenticated
  using (public.can_view_note(note_id));

drop policy if exists "own note items are writable" on public.personal_note_items;
drop policy if exists "note items are writable by their people" on public.personal_note_items;
create policy "note items are writable by their people"
  on public.personal_note_items for insert
  to authenticated
  with check (user_id = auth.uid() and public.can_view_note(note_id));

drop policy if exists "own note items are updatable" on public.personal_note_items;
drop policy if exists "note items are updatable by their people" on public.personal_note_items;
create policy "note items are updatable by their people"
  on public.personal_note_items for update
  to authenticated
  using (public.can_view_note(note_id))
  with check (public.can_view_note(note_id));

drop policy if exists "own note items are deletable" on public.personal_note_items;
drop policy if exists "note items are deletable by their people" on public.personal_note_items;
create policy "note items are deletable by their people"
  on public.personal_note_items for delete
  to authenticated
  using (public.can_view_note(note_id));

-- --------------------------------------------------------------------------
-- The share rows themselves
-- --------------------------------------------------------------------------

drop policy if exists "shares are readable by their people" on public.personal_note_shares;
create policy "shares are readable by their people"
  on public.personal_note_shares for select
  to authenticated
  using (public.can_view_note(note_id));

-- Only the owner invites, and never themselves — they are already on it.
drop policy if exists "owners share their notes" on public.personal_note_shares;
create policy "owners share their notes"
  on public.personal_note_shares for insert
  to authenticated
  with check (
    public.owns_note(note_id)
    and added_by = auth.uid()
    and user_id <> auth.uid()
  );

-- The owner removes anybody; everybody else may remove themselves, which is
-- what leaving a list means.
drop policy if exists "owners and leavers remove shares" on public.personal_note_shares;
create policy "owners and leavers remove shares"
  on public.personal_note_shares for delete
  to authenticated
  using (public.owns_note(note_id) or user_id = auth.uid());

grant select, insert, delete on public.personal_note_shares to authenticated;

-- --------------------------------------------------------------------------
-- Realtime
--
-- A shared list that only updates on reload is a worse shared list. Realtime
-- applies RLS to every change it forwards, so publishing these does not widen
-- who can see what.
-- --------------------------------------------------------------------------

do $$
declare
  target text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'publication supabase_realtime not found — skipping';
    return;
  end if;

  foreach target in array array['personal_notes', 'personal_note_items']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = target
    ) then
      execute format('alter publication supabase_realtime add table public.%I', target);
    end if;
  end loop;
end $$;

-- A deleted line has to say which note it belonged to, and the payload for a
-- delete carries only the identifying columns unless the whole row is kept.
alter table public.personal_note_items replica identity full;

-- =========================================================================
-- 20260914000020_trash_tasks.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Deleting a task puts it in the bin
--
-- Until now a delete was final, which is why every delete sat behind a
-- confirmation dialog: the only defence against "I deleted the wrong one"
-- was a question nobody reads. A deleted task is now hidden from every read
-- at once and kept for thirty days. Restoring it brings back everything that
-- was on it — comments, files, history, assignees — because none of that
-- went anywhere.
--
-- Hiding is done in the read policy, not in queries. Every list, count,
-- search and realtime event goes through that policy, so there is no query
-- to forget. The two things that read tasks without it — reminders and the
-- purge — are handled here by name.
--
-- Who may bin or restore is exactly who could delete: managers and admins.
-- ---------------------------------------------------------------------------

alter table public.tasks add column if not exists deleted_at timestamptz;

comment on column public.tasks.deleted_at is
  'Set when trashed; cleared on restore. The read policy hides the row while it is set.';

create index if not exists tasks_deleted_idx
  on public.tasks (deleted_at)
  where deleted_at is not null;

-- --------------------------------------------------------------------------
-- The read policy from migration 0015, with the bin excluded
-- --------------------------------------------------------------------------

drop policy if exists "tasks are readable when assigned or managed" on public.tasks;
create policy "tasks are readable when assigned or managed"
  on public.tasks for select
  to authenticated
  using (
    deleted_at is null
    and (
      exists (
        select 1 from public.task_assignments a
        where a.task_id = tasks.id and a.user_id = auth.uid()
      )
      or (
        public.is_manager_or_admin()
        and (project_id is null or public.can_view_project(project_id))
      )
    )
  );

-- --------------------------------------------------------------------------
-- Two more things the history can say
-- --------------------------------------------------------------------------

alter table public.task_activity
  drop constraint if exists task_activity_action_known;
alter table public.task_activity
  add constraint task_activity_action_known check (
    action in (
      'created',
      'updated',
      'status_changed',
      'priority_changed',
      'due_date_changed',
      'follow_up_set',
      'follow_up_cleared',
      'assignee_added',
      'assignee_removed',
      'commented',
      'deleted',
      'restored'
    )
  );

-- --------------------------------------------------------------------------
-- Bin, restore, purge
--
-- SECURITY DEFINER because the row being restored is, by definition, one the
-- caller cannot currently read. The permission check is the delete policy's,
-- written out: a manager or admin, on a task they could see if it were not
-- in the bin.
-- --------------------------------------------------------------------------

create or replace function public.trash_task(task uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target public.tasks%rowtype;
begin
  select * into target from public.tasks where id = task;
  if not found or target.deleted_at is not null then
    return false;
  end if;

  if not public.is_manager_or_admin() then
    return false;
  end if;
  if target.project_id is not null and not public.can_view_project(target.project_id) then
    return false;
  end if;

  update public.tasks set deleted_at = now() where id = task;

  -- Nothing should nag about a task that is in the bin.
  update public.reminder_queue
     set status = 'cancelled'
   where task_id = task and status = 'pending';

  insert into public.task_activity (task_id, actor_id, action)
  values (task, auth.uid(), 'deleted');

  return true;
end;
$$;

create or replace function public.restore_task(task uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target public.tasks%rowtype;
begin
  select * into target from public.tasks where id = task;
  if not found or target.deleted_at is null then
    return false;
  end if;

  if not public.is_manager_or_admin() then
    return false;
  end if;
  if target.project_id is not null and not public.can_view_project(target.project_id) then
    return false;
  end if;

  update public.tasks set deleted_at = null where id = task;

  insert into public.task_activity (task_id, actor_id, action)
  values (task, auth.uid(), 'restored');

  return true;
end;
$$;

-- Run by the daily dispatcher with the service key. Deliberately not granted
-- to authenticated: purging is housekeeping, not a user action.
create or replace function public.purge_trashed_tasks(older_than interval default '30 days')
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  removed integer;
begin
  delete from public.tasks
   where deleted_at is not null
     and deleted_at < now() - older_than;
  get diagnostics removed = row_count;
  return removed;
end;
$$;

grant execute on function public.trash_task(uuid) to authenticated;
grant execute on function public.restore_task(uuid) to authenticated;
revoke execute on function public.purge_trashed_tasks(interval) from authenticated, anon;

-- --------------------------------------------------------------------------
-- Reminders skip the bin
--
-- enqueue_task_reminders is SECURITY DEFINER and scans tasks directly, so the
-- read policy does not protect it. This is migration 0014's function with one
-- condition added to each of its three candidate sets, generated from that
-- file rather than retyped so the two cannot drift.
-- --------------------------------------------------------------------------

create or replace function public.enqueue_task_reminders()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  inserted integer := 0;
begin
  -- Work that is due within the recipient's chosen lead time.
  with candidates as (
    select
      t.id as task_id, t.title, t.due_at,
      a.user_id,
      p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled,
      np.telegram_chat_id, np.whatsapp_number, np.due_soon_lead_hours
    from public.tasks t
    join public.task_assignments a on a.task_id = t.id
    join public.profiles p on p.id = a.user_id
    join public.notification_preferences np on np.user_id = a.user_id
    where t.status <> 'done'
      and t.deleted_at is null
      and t.due_at is not null
      and np.remind_due_soon
      and t.due_at > now()
      and t.due_at <= now() + make_interval(hours => np.due_soon_lead_hours)
  )
  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    c.user_id, c.task_id, ch.channel, 'due_soon',
    case ch.channel
      when 'email' then c.email
      when 'telegram' then c.telegram_chat_id
      else c.whatsapp_number
    end,
    'Due soon: ' || c.title,
    c.title || ' is due ' || to_char(c.due_at at time zone 'UTC', 'DD Mon HH24:MI') || ' UTC.',
    'due_soon:' || c.task_id || ':' || c.user_id || ':' || ch.channel || ':' || extract(epoch from c.due_at)::bigint
  from candidates c
  cross join lateral (
    select 'email'::text as channel where c.email_enabled
    union all select 'telegram' where c.telegram_enabled and c.telegram_chat_id is not null
    union all select 'whatsapp' where c.whatsapp_enabled and c.whatsapp_number is not null
  ) ch
  on conflict (dedupe_key) do nothing;

  get diagnostics inserted = row_count;

  -- Work that is already late. Keyed by the day so a task that stays overdue
  -- nags once a day rather than on every scheduler run.
  with candidates as (
    select
      t.id as task_id, t.title, t.due_at,
      a.user_id, p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled,
      np.telegram_chat_id, np.whatsapp_number, np.due_soon_lead_hours
    from public.tasks t
    join public.task_assignments a on a.task_id = t.id
    join public.profiles p on p.id = a.user_id
    join public.notification_preferences np on np.user_id = a.user_id
    where t.status <> 'done'
      and t.deleted_at is null
      and t.due_at is not null
      and t.due_at < now()
      and np.remind_overdue
  )
  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    c.user_id, c.task_id, ch.channel, 'overdue',
    case ch.channel
      when 'email' then c.email
      when 'telegram' then c.telegram_chat_id
      else c.whatsapp_number
    end,
    'Overdue: ' || c.title,
    c.title || ' was due ' || to_char(c.due_at at time zone 'UTC', 'DD Mon HH24:MI') || ' UTC and is still open.',
    'overdue:' || c.task_id || ':' || c.user_id || ':' || ch.channel || ':' || to_char(now(), 'YYYY-MM-DD')
  from candidates c
  cross join lateral (
    select 'email'::text as channel where c.email_enabled
    union all select 'telegram' where c.telegram_enabled and c.telegram_chat_id is not null
    union all select 'whatsapp' where c.whatsapp_enabled and c.whatsapp_number is not null
  ) ch
  on conflict (dedupe_key) do nothing;

  -- Follow-ups that have come due, to whoever has to chase them.
  with candidates as (
    select
      t.id as task_id, t.title, t.follow_up_at, t.follow_up_note,
      a.user_id, p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled,
      np.telegram_chat_id, np.whatsapp_number, np.due_soon_lead_hours
    from public.tasks t
    join public.task_assignments a on a.task_id = t.id
    join public.profiles p on p.id = a.user_id
    join public.notification_preferences np on np.user_id = a.user_id
    where t.status <> 'done'
      and t.deleted_at is null
      and t.follow_up_at is not null
      and t.follow_up_at <= now()
      and np.remind_follow_up
  )
  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    c.user_id, c.task_id, ch.channel, 'follow_up',
    case ch.channel
      when 'email' then c.email
      when 'telegram' then c.telegram_chat_id
      else c.whatsapp_number
    end,
    'Follow up: ' || c.title,
    coalesce(c.follow_up_note, 'Time to follow up on ' || c.title) || ' (' || c.title || ')',
    'follow_up:' || c.task_id || ':' || c.user_id || ':' || ch.channel || ':' || extract(epoch from c.follow_up_at)::bigint
  from candidates c
  cross join lateral (
    select 'email'::text as channel where c.email_enabled
    union all select 'telegram' where c.telegram_enabled and c.telegram_chat_id is not null
    union all select 'whatsapp' where c.whatsapp_enabled and c.whatsapp_number is not null
  ) ch
  on conflict (dedupe_key) do nothing;

  return inserted;
end;
$$;

-- =========================================================================
-- 20260916000021_notify_missing_recipient.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Deleting a person could not be done.
--
-- Removing an account from Supabase's Authentication page returned 500, and
-- the database log underneath it said:
--
--   insert or update on table "notifications"
--   violates foreign key constraint "notifications_user_id_fkey"
--
-- The cascade is the whole story. Deleting the auth user deletes their
-- profile; deleting the profile deletes their task assignments; and every
-- assignment that goes fires `task_assignments_notify_delete`, which tries to
-- tell that person they have been removed from a task. The profile it would
-- address is the one that has just been deleted, so the insert has nobody to
-- point at and the whole delete rolls back. The more work somebody had been
-- given, the more certainly they could never be removed.
--
-- `push_notification` already meant to guard this — "never about a missing
-- user" is its own comment — but it only checked that the recipient id was not
-- null, and an id for a row that no longer exists is not null. It checks for
-- the row now.
--
-- This is the right place for the fix rather than the assignment trigger:
-- every notification in the app goes through this one function, so a comment,
-- a mention, a status change and a reassignment are all covered by it, and any
-- future one is covered without being remembered.
-- ---------------------------------------------------------------------------

create or replace function public.push_notification(
  recipient uuid,
  actor uuid,
  kind text,
  heading text,
  detail text,
  task uuid,
  project uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Never notify someone about their own action.
  if recipient is null or recipient = coalesce(actor, '00000000-0000-0000-0000-000000000000'::uuid) then
    return;
  end if;

  -- Never notify someone who is not there any more. During a cascading delete
  -- the profile is already gone by the time the triggers on its children run,
  -- and a message to a deleted account is not worth failing the delete for.
  if not exists (select 1 from public.profiles where id = recipient) then
    return;
  end if;

  insert into public.notifications (user_id, actor_id, type, title, body, task_id, project_id)
  values (recipient, actor, kind, heading, detail, task, project);
end;
$$;

-- =========================================================================
-- 20260916000022_claim_task_reminders.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Send "you were assigned this" at the moment it happens.
--
-- Every reminder went out on the daily sweep, which is right for the three
-- kinds that are questions about the clock — due soon, overdue, follow up.
-- They can only be found by looking at the board against the time, so a
-- scheduled run is the only thing that could find them.
--
-- Being handed a task is not that. It is an event that has already happened,
-- with a known recipient and a message sitting ready in the queue within
-- milliseconds. It waited up to a day anyway, because it shared the one
-- conveyor belt with the others — so somebody assigned work at 2pm heard
-- about it the next morning.
--
-- This claims the rows for a single task, so the assignment path can drain
-- just those and leave the rest of the queue to the scheduler. Same rules as
-- `claim_reminders`: the row is moved out of 'pending' in one statement before
-- any provider is called, SKIP LOCKED so the sweep and an assignment happening
-- at the same moment take different rows rather than both sending, and a claim
-- stranded by a dead function is released after ten minutes.
-- ---------------------------------------------------------------------------

create or replace function public.claim_task_reminders(task uuid)
returns setof public.reminder_queue
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if task is null then
    return;
  end if;

  -- Release anything this task left 'sending' in a run that died.
  update public.reminder_queue
     set status = 'pending', claimed_at = null
   where task_id = task
     and status = 'sending'
     and claimed_at < now() - interval '10 minutes';

  return query
  with due as (
    select id
      from public.reminder_queue
     where task_id = task
       and status = 'pending'
       and scheduled_for <= now()
     -- A task has one row per assignee per channel. The cap is here so a
     -- pathological task cannot turn one assignment into an unbounded send.
     limit 40
     for update skip locked
  )
  update public.reminder_queue q
     set status = 'sending', claimed_at = now()
    from due
   where q.id = due.id
  returning q.*;
end;
$$;

-- Only the service-role dispatcher calls this; it reads every user's queue.
revoke all on function public.claim_task_reminders(uuid) from public, anon, authenticated;

-- =========================================================================
-- 20260916000023_team_chat.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Team chat
--
-- One room for the workspace. Not a channel list and not direct messages:
-- everyone here already works together, and a single room that everybody can
-- see is the thing a small team actually uses. It is modelled so a `room`
-- column could be added later without moving the messages.
--
-- Deliberately separate from `comments`, which belong to a task and are part
-- of its record. A message here is conversation, and is allowed to be deleted
-- by the person who wrote it.
-- ---------------------------------------------------------------------------

create table if not exists public.team_messages (
  id        uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  body      text not null,

  created_at timestamptz not null default now(),
  edited_at  timestamptz,

  -- Long enough for a paragraph, short enough that the room stays a
  -- conversation rather than a document.
  constraint team_messages_body_length check (
    char_length(btrim(body)) between 1 and 4000
  )
);

-- The room is read newest-last and paged from the end.
create index if not exists team_messages_created_idx
  on public.team_messages (created_at desc);

alter table public.team_messages enable row level security;

-- Everyone signed in is on the team, so everyone reads the room. There is no
-- narrower rule to write: a shared room whose messages some members cannot see
-- is not a shared room.
drop policy if exists "team messages are readable by the team" on public.team_messages;
create policy "team messages are readable by the team"
  on public.team_messages for select
  to authenticated
  using (true);

-- You may only speak as yourself. Without the `author_id` check a member could
-- post a message attributed to somebody else, which is the one thing a chat
-- must not allow.
drop policy if exists "members write their own messages" on public.team_messages;
create policy "members write their own messages"
  on public.team_messages for insert
  to authenticated
  with check (author_id = auth.uid());

drop policy if exists "authors edit their own messages" on public.team_messages;
create policy "authors edit their own messages"
  on public.team_messages for update
  to authenticated
  using (author_id = auth.uid())
  with check (author_id = auth.uid());

-- An author can delete what they said; an admin can delete anything, because
-- somebody has to be able to remove what should not have been posted.
drop policy if exists "authors and admins delete messages" on public.team_messages;
create policy "authors and admins delete messages"
  on public.team_messages for delete
  to authenticated
  using (author_id = auth.uid() or public.is_admin());

-- Row-level security decides *which* rows; the grant decides whether the role
-- may touch the table at all, and both are needed. Every other table in this
-- schema grants explicitly rather than leaning on the default privileges of
-- the `public` schema — this one was the exception, and the symptom was a
-- room that answered "permission denied for table team_messages".
grant select, insert, update, delete on public.team_messages to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime
--
-- RLS is still enforced on everything realtime forwards, so publishing the
-- table does not widen who can read it.
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'publication supabase_realtime not found — skipping';
    return;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'team_messages'
  ) then
    alter publication supabase_realtime add table public.team_messages;
  end if;
end $$;

-- A delete payload carries only the identifying columns unless the replica
-- identity is full, and the room needs to know which message went.
alter table public.team_messages replica identity full;

-- =========================================================================
-- 20260919000024_direct_messages.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Private messages
--
-- The team room is one room that everybody reads; its select policy is
-- literally `using (true)`. This is the opposite: a conversation is readable
-- only by the people in it, and there is no admin override anywhere in this
-- file. An admin can remove a message from the shared room because somebody
-- has to be able to take down what should not have been posted in public.
-- Nothing here is public, so that reason does not apply, and "private unless
-- an admin is curious" is not private.
--
-- Shaped for one-to-one today and small private groups later without moving
-- any messages: membership lives in `conversation_participants`, which has no
-- idea how many people it holds. The ordered pair on `conversations` exists
-- only to stop two people ending up with two threads, and is null for
-- anything that is not a pair.
-- ---------------------------------------------------------------------------

create table if not exists public.conversations (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),

  -- Ordering for the conversation list, kept by the trigger below so the list
  -- does not have to aggregate every message to sort itself.
  last_message_at timestamptz not null default now(),

  -- The two people, smaller id first, so (a,b) and (b,a) are the same row.
  member_low  uuid references public.profiles (id) on delete cascade,
  member_high uuid references public.profiles (id) on delete cascade,

  constraint conversations_pair_ordered check (
    (member_low is null and member_high is null) or member_low < member_high
  )
);

-- One thread per pair. Partial, so future group conversations — which leave
-- both columns null — are not forced into a single row between them.
create unique index if not exists conversations_pair_idx
  on public.conversations (member_low, member_high)
  where member_low is not null;

create index if not exists conversations_recent_idx
  on public.conversations (last_message_at desc);

create table if not exists public.conversation_participants (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id         uuid not null references public.profiles (id) on delete cascade,

  -- How far this person has read. The unread count is everything after it.
  last_read_at timestamptz not null default now(),

  primary key (conversation_id, user_id)
);

create index if not exists conversation_participants_user_idx
  on public.conversation_participants (user_id);

create table if not exists public.direct_messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  author_id       uuid not null references public.profiles (id) on delete cascade,
  body            text not null,

  created_at timestamptz not null default now(),
  edited_at  timestamptz,

  constraint direct_messages_body_length check (
    char_length(btrim(body)) between 1 and 4000
  )
);

create index if not exists direct_messages_thread_idx
  on public.direct_messages (conversation_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Membership, asked without recursion
--
-- A policy on `conversation_participants` that checks membership by selecting
-- from `conversation_participants` is a policy that calls itself. `security
-- definer` steps outside row-level security to answer the one question every
-- policy in this file is built on, which is what breaks the loop.
-- ---------------------------------------------------------------------------

create or replace function public.in_conversation(conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select conversation is not null and exists (
    select 1
      from public.conversation_participants p
     where p.conversation_id = conversation
       and p.user_id = auth.uid()
  );
$$;

-- ---------------------------------------------------------------------------
-- Starting a conversation
--
-- Find the thread with somebody, or open it. Done in one `security definer`
-- function rather than by letting the client insert, for two reasons: the
-- caller can only ever add themselves and one other person, and two people
-- messaging each other at the same moment get one thread rather than two —
-- the unique index decides it and the loser reads the winner's row.
-- ---------------------------------------------------------------------------

create or replace function public.start_direct_conversation(other uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me   uuid := auth.uid();
  low  uuid;
  high uuid;
  found uuid;
begin
  if me is null then
    raise exception 'not signed in';
  end if;
  if other is null or other = me then
    raise exception 'pick somebody else to message';
  end if;
  if not exists (select 1 from public.profiles where id = other) then
    raise exception 'that person is not on the team';
  end if;

  low  := least(me, other);
  high := greatest(me, other);

  select id into found
    from public.conversations
   where member_low = low and member_high = high;

  if found is not null then
    return found;
  end if;

  insert into public.conversations (member_low, member_high)
       values (low, high)
  on conflict (member_low, member_high) where member_low is not null
  do nothing
  returning id into found;

  -- Somebody else won the race; their row is the thread.
  if found is null then
    select id into found
      from public.conversations
     where member_low = low and member_high = high;
    return found;
  end if;

  insert into public.conversation_participants (conversation_id, user_id)
       values (found, me), (found, other);

  return found;
end;
$$;

-- ---------------------------------------------------------------------------
-- Keeping the list in order, and telling the other person
-- ---------------------------------------------------------------------------

create or replace function public.touch_conversation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  recipient uuid;
  sender    text;
begin
  update public.conversations
     set last_message_at = new.created_at
   where id = new.conversation_id;

  -- A message nobody is told about is a message nobody reads. Everyone in the
  -- conversation except whoever wrote it.
  select coalesce(p.full_name, p.email) into sender
    from public.profiles p where p.id = new.author_id;

  for recipient in
    select user_id
      from public.conversation_participants
     where conversation_id = new.conversation_id
       and user_id <> new.author_id
  loop
    perform public.push_direct_notification(
      recipient, new.author_id, sender, new.body, new.conversation_id
    );
  end loop;

  return new;
end;
$$;

-- `push_notification` writes a notification about a task; this one is about a
-- conversation, which has no task and no project to point at.
create or replace function public.push_direct_notification(
  recipient uuid,
  actor uuid,
  heading text,
  detail text,
  conversation uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if recipient is null or recipient = actor then
    return;
  end if;
  -- Same guard as `push_notification`: never address a profile that has been
  -- deleted, or a cascading delete cannot finish.
  if not exists (select 1 from public.profiles where id = recipient) then
    return;
  end if;

  insert into public.notifications
    (user_id, actor_id, type, title, body, conversation_id)
  values
    (recipient, actor, 'direct_message', heading, left(btrim(detail), 140), conversation);
end;
$$;

drop trigger if exists direct_messages_touch on public.direct_messages;
create trigger direct_messages_touch
  after insert on public.direct_messages
  for each row execute function public.touch_conversation();

-- ---------------------------------------------------------------------------
-- A notification can now be about a conversation
-- ---------------------------------------------------------------------------

alter table public.notifications
  add column if not exists conversation_id uuid
  references public.conversations (id) on delete cascade;

alter table public.notifications drop constraint if exists notifications_type_known;
alter table public.notifications add constraint notifications_type_known check (
  type in (
    'task_assigned',
    'task_unassigned',
    'task_commented',
    'task_mentioned',
    'task_review_requested',
    'task_completed',
    'direct_message'
  )
);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.conversations              enable row level security;
alter table public.conversation_participants  enable row level security;
alter table public.direct_messages            enable row level security;

-- `force` so the rule holds for the table's owner too. A private conversation
-- is the one place in this schema where that distinction is worth the cost.
alter table public.conversations              force row level security;
alter table public.conversation_participants  force row level security;
alter table public.direct_messages            force row level security;

drop policy if exists "participants read their conversations" on public.conversations;
create policy "participants read their conversations"
  on public.conversations for select
  to authenticated
  using (public.in_conversation(id));

-- No insert policy on purpose: conversations are opened through
-- `start_direct_conversation`, which decides who is in one.

drop policy if exists "participants see who is in the room" on public.conversation_participants;
create policy "participants see who is in the room"
  on public.conversation_participants for select
  to authenticated
  using (public.in_conversation(conversation_id));

-- Marking your own place, and nobody else's.
drop policy if exists "participants mark their own place" on public.conversation_participants;
create policy "participants mark their own place"
  on public.conversation_participants for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "participants read the thread" on public.direct_messages;
create policy "participants read the thread"
  on public.direct_messages for select
  to authenticated
  using (public.in_conversation(conversation_id));

-- You may only speak as yourself, and only where you are.
drop policy if exists "participants write as themselves" on public.direct_messages;
create policy "participants write as themselves"
  on public.direct_messages for insert
  to authenticated
  with check (
    author_id = auth.uid() and public.in_conversation(conversation_id)
  );

drop policy if exists "authors edit their own messages" on public.direct_messages;
create policy "authors edit their own messages"
  on public.direct_messages for update
  to authenticated
  using (author_id = auth.uid())
  with check (author_id = auth.uid());

-- Authors only. There is deliberately no admin clause here.
drop policy if exists "authors delete their own messages" on public.direct_messages;
create policy "authors delete their own messages"
  on public.direct_messages for delete
  to authenticated
  using (author_id = auth.uid());

-- Row-level security decides which rows; the grant decides whether the role
-- may touch the table at all, and this schema says so explicitly everywhere.
grant select                       on public.conversations             to authenticated;
grant select, update               on public.conversation_participants to authenticated;
grant select, insert, update, delete on public.direct_messages         to authenticated;
grant execute on function public.in_conversation(uuid)            to authenticated;
grant execute on function public.start_direct_conversation(uuid)  to authenticated;

-- ---------------------------------------------------------------------------
-- The list, in one question
--
-- Built naively this is a query for the conversations and then two more for
-- each of them — the last thing said, and how much of it is unread. Twenty
-- conversations is forty-one round trips, and the unread total is wanted by
-- the app shell on *every* page, not just this one. One statement instead,
-- with a lateral join per thread, which Postgres answers from the indexes
-- already here.
--
-- `security invoker`, not definer: row-level security still applies, so this
-- cannot return a conversation the caller could not have read anyway. The
-- explicit `user_id = auth.uid()` join is the belt to that pair of braces.
-- ---------------------------------------------------------------------------

create or replace function public.my_conversations()
returns table (
  id              uuid,
  last_message_at timestamptz,
  other_id        uuid,
  other_name      text,
  other_email     text,
  other_avatar    text,
  other_title     text,
  last_message    text,
  last_author_id  uuid,
  unread          bigint
)
language sql
stable
set search_path = public, pg_temp
as $$
  with mine as (
    select c.id, c.last_message_at, p.last_read_at
      from public.conversations c
      join public.conversation_participants p
        on p.conversation_id = c.id
       and p.user_id = auth.uid()
  )
  select
    m.id,
    m.last_message_at,
    other.id,
    other.full_name,
    other.email,
    other.avatar_url,
    other.job_title,
    recent.body,
    recent.author_id,
    coalesce(counted.n, 0)
  from mine m
  left join lateral (
    select pr.id, pr.full_name, pr.email, pr.avatar_url, pr.job_title
      from public.conversation_participants p
      join public.profiles pr on pr.id = p.user_id
     where p.conversation_id = m.id
       and p.user_id <> auth.uid()
     limit 1
  ) other on true
  left join lateral (
    select d.body, d.author_id
      from public.direct_messages d
     where d.conversation_id = m.id
     order by d.created_at desc
     limit 1
  ) recent on true
  left join lateral (
    select count(*) as n
      from public.direct_messages d
     where d.conversation_id = m.id
       and d.author_id <> auth.uid()
       and d.created_at > m.last_read_at
  ) counted on true
  order by m.last_message_at desc;
$$;

-- Just the number, for the badge the shell draws on every page. Counting it
-- here rather than summing the list above is one small query instead of one
-- large one, on pages that will never show a conversation.
create or replace function public.unread_direct_count()
returns bigint
language sql
stable
set search_path = public, pg_temp
as $$
  select coalesce(count(d.*), 0)
    from public.conversation_participants p
    join public.direct_messages d
      on d.conversation_id = p.conversation_id
     and d.author_id <> p.user_id
     and d.created_at > p.last_read_at
   where p.user_id = auth.uid();
$$;

grant execute on function public.my_conversations()      to authenticated;
grant execute on function public.unread_direct_count()   to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime
--
-- RLS is enforced on everything realtime forwards, so publishing these does
-- not widen who can read them.
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'publication supabase_realtime not found — skipping';
    return;
  end if;

  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public'
       and tablename = 'direct_messages'
  ) then
    alter publication supabase_realtime add table public.direct_messages;
  end if;
end $$;

-- A delete payload carries only the identifying columns unless the replica
-- identity is full, and the thread needs to know which message went.
alter table public.direct_messages replica identity full;

-- =========================================================================
-- 20260921000025_recurring_tasks.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Recurring tasks
--
-- The portal could describe work that happens once. Everything that happens
-- every month — the freight reconciliation, the licence renewal, the board
-- pack — was retyped each time, which is both a chore and a way to forget.
--
-- The model is deliberately the simplest one that is honest: a task carries
-- its own repeat rule, and closing it opens the next one. There is no series,
-- no parent row, no calendar of future instances. That means:
--
--   * exactly one open instance of a repeating task exists at any moment, so
--     the board never fills with copies of the same thing;
--   * the history is the closed instances themselves, each with its own
--     comments and activity;
--   * changing the rule changes it from the next occurrence on, which is what
--     somebody editing a task in front of them expects.
--
-- What it cannot express is "the first Monday of the month" or "weekdays
-- only". Those want a real calendar rule and a generator, and neither is
-- worth its weight until somebody asks.
-- ---------------------------------------------------------------------------

alter table public.tasks
  add column if not exists repeat_every text,
  add column if not exists repeat_interval integer not null default 1;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'tasks_repeat_every_check'
  ) then
    alter table public.tasks
      add constraint tasks_repeat_every_check
      check (repeat_every is null or repeat_every in ('day', 'week', 'month', 'year'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'tasks_repeat_interval_check'
  ) then
    alter table public.tasks
      add constraint tasks_repeat_interval_check
      check (repeat_interval between 1 and 365);
  end if;

  -- A repeat with no due date has nothing to advance, so it is not a repeat.
  if not exists (
    select 1 from pg_constraint where conname = 'tasks_repeat_needs_due_check'
  ) then
    alter table public.tasks
      add constraint tasks_repeat_needs_due_check
      check (repeat_every is null or due_at is not null);
  end if;
end $$;

comment on column public.tasks.repeat_every is
  'Unit of the repeat rule: day, week, month or year. Null means the task happens once.';
comment on column public.tasks.repeat_interval is
  'How many of those units between occurrences. 2 with repeat_every = week is fortnightly.';

-- ---------------------------------------------------------------------------
-- Closing one opens the next
--
-- `security definer` because the row is written on behalf of whoever closed
-- the task, and the next occurrence belongs to the same person who owned the
-- last one rather than to them. It writes one row, shaped from a row the
-- caller has just proved they can update, so it hands out nothing that was
-- not already theirs.
--
-- The due date is advanced until it is in the future: a monthly task closed
-- three months late should next be due next month, not produce something that
-- is already overdue.
-- ---------------------------------------------------------------------------

create or replace function public.spawn_next_occurrence()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  step     interval;
  next_due timestamptz;
  copy_id  uuid;
begin
  if new.repeat_every is null or new.due_at is null then
    return new;
  end if;

  -- Only the move into done, and only once: an update that leaves a closed
  -- task closed must not open a second copy.
  if new.status <> 'done' or old.status = 'done' then
    return new;
  end if;

  step := (new.repeat_interval || ' ' || new.repeat_every)::interval;
  next_due := new.due_at + step;

  -- Bounded: a daily task abandoned for years would otherwise loop here.
  for i in 1..500 loop
    exit when next_due > now();
    next_due := next_due + step;
  end loop;

  insert into public.tasks (
    project_id, title, description, status, priority,
    due_at, position, created_by, repeat_every, repeat_interval
  )
  values (
    new.project_id, new.title, new.description, 'todo', new.priority,
    next_due, new.position, new.created_by, new.repeat_every, new.repeat_interval
  )
  returning id into copy_id;

  -- The same people, on the same job.
  insert into public.task_assignments (task_id, user_id)
  select copy_id, user_id
    from public.task_assignments
   where task_id = new.id;

  -- The rule travels with the occurrence that is still open, so the closed
  -- one reads as what it is: a thing that was done on a date.
  update public.tasks
     set repeat_every = null
   where id = new.id;

  return new;
end;
$fn$;

comment on function public.spawn_next_occurrence() is
  'Opens the next occurrence of a repeating task when one is closed, and moves the rule onto it.';

drop trigger if exists tasks_spawn_next_occurrence on public.tasks;

create trigger tasks_spawn_next_occurrence
  after update of status on public.tasks
  for each row
  execute function public.spawn_next_occurrence();

-- =========================================================================
-- 20260921000026_web_push.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Web push
--
-- The portal could reach somebody by email, Telegram or WhatsApp — every one
-- of them a different app, and none of them the one the work is in. Installed
-- to a home screen, the portal can now buzz the phone itself. iOS has allowed
-- this since 16.4, for installed web apps only, which is exactly how this one
-- is used.
--
-- Three things here:
--   * push_subscriptions — one row per device that said yes, not per person;
--   * push_enabled on the preferences, beside the other channels;
--   * 'push' as a channel on the queue, fanned out per device.
--
-- The keys that sign a push (VAPID) live in web_push_keys, which has row-level
-- security on and no policies at all: nothing reachable with a user's session
-- can read it, only the service role the dispatcher runs as. They are
-- generated on first use rather than pasted into an environment variable, so
-- the secret is never written down anywhere a person could paste it.
-- ---------------------------------------------------------------------------

create table if not exists public.push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  -- The browser's own address for this device. Unique across everybody: it is
  -- issued by the push service and two people cannot hold the same one.
  endpoint    text not null unique,
  -- The keys the payload is encrypted to. Useless without the endpoint.
  p256dh      text not null,
  auth        text not null,
  -- For the person deciding which of their devices to turn off.
  user_agent  text,
  created_at  timestamptz not null default now(),
  last_used_at timestamptz
);

create index if not exists push_subscriptions_user_idx
  on public.push_subscriptions (user_id);

alter table public.push_subscriptions enable row level security;
alter table public.push_subscriptions force row level security;

drop policy if exists "people see their own devices" on public.push_subscriptions;
create policy "people see their own devices"
  on public.push_subscriptions for select
  using (user_id = auth.uid());

drop policy if exists "people register their own devices" on public.push_subscriptions;
create policy "people register their own devices"
  on public.push_subscriptions for insert
  with check (user_id = auth.uid());

drop policy if exists "people update their own devices" on public.push_subscriptions;
create policy "people update their own devices"
  on public.push_subscriptions for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- No admin clause, deliberately: which devices somebody carries is theirs.
drop policy if exists "people remove their own devices" on public.push_subscriptions;
create policy "people remove their own devices"
  on public.push_subscriptions for delete
  using (user_id = auth.uid());

grant select, insert, update, delete on public.push_subscriptions to authenticated;

comment on table public.push_subscriptions is
  'One row per device that has agreed to notifications. The dispatcher sends to these with the service role.';

-- ---------------------------------------------------------------------------
-- The signing keys
--
-- One row, ever: `id` is a boolean fixed at true, so a second insert collides
-- with the primary key rather than quietly creating a second pair that half
-- the devices are subscribed to.
-- ---------------------------------------------------------------------------

create table if not exists public.web_push_keys (
  id          boolean primary key default true check (id),
  public_key  text not null,
  private_key text not null,
  created_at  timestamptz not null default now()
);

alter table public.web_push_keys enable row level security;
alter table public.web_push_keys force row level security;
-- No policies and no grants: the service role bypasses both, everybody else
-- is refused. The public half is handed to the browser by the app, which
-- reads this row on the server.

comment on table public.web_push_keys is
  'The VAPID key pair, generated on first use. Unreadable with a user session by design.';

-- ---------------------------------------------------------------------------
-- The channel
-- ---------------------------------------------------------------------------

alter table public.notification_preferences
  add column if not exists push_enabled boolean not null default false;

comment on column public.notification_preferences.push_enabled is
  'Whether reminders are also pushed to this person''s registered devices.';

alter table public.reminder_queue
  drop constraint if exists reminder_queue_channel_check;

alter table public.reminder_queue
  add constraint reminder_queue_channel_check
  check (channel in ('email', 'telegram', 'whatsapp', 'push'));

-- ---------------------------------------------------------------------------
-- Queueing to devices
--
-- The same function as before with one branch added. It is repeated whole
-- rather than patched because a plpgsql body cannot be edited in place, and a
-- half-replaced one is worse than a long migration.
--
-- Two things worth noticing. The lateral now carries its own recipient: the
-- other three channels have exactly one address each, a device does not, and
-- somebody with a phone and a laptop should be told on both. And the dedupe
-- key gains the endpoint for push only, so every key already in the queue
-- keeps its exact spelling and nothing that has been sent is sent again.
-- ---------------------------------------------------------------------------

create or replace function public.enqueue_task_reminders()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  inserted integer := 0;
begin
  -- Work that is due within the recipient's chosen lead time.
  with candidates as (
    select
      t.id as task_id, t.title, t.due_at,
      a.user_id,
      p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled, np.push_enabled,
      np.telegram_chat_id, np.whatsapp_number, np.due_soon_lead_hours
    from public.tasks t
    join public.task_assignments a on a.task_id = t.id
    join public.profiles p on p.id = a.user_id
    join public.notification_preferences np on np.user_id = a.user_id
    where t.status <> 'done'
      and t.deleted_at is null
      and t.due_at is not null
      and np.remind_due_soon
      and t.due_at > now()
      and t.due_at <= now() + make_interval(hours => np.due_soon_lead_hours)
  )
  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    c.user_id, c.task_id, ch.channel, 'due_soon',
    ch.recipient,
    'Due soon: ' || c.title,
    c.title || ' is due ' || to_char(c.due_at at time zone 'UTC', 'DD Mon HH24:MI') || ' UTC.',
    'due_soon:' || c.task_id || ':' || c.user_id || ':' || ch.channel || case when ch.channel = 'push' then ':' || ch.recipient else '' end || ':' || extract(epoch from c.due_at)::bigint
  from candidates c
  cross join lateral (
    select 'email'::text as channel, c.email as recipient
     where c.email_enabled
    union all
    select 'telegram', c.telegram_chat_id
     where c.telegram_enabled and c.telegram_chat_id is not null
    union all
    select 'whatsapp', c.whatsapp_number
     where c.whatsapp_enabled and c.whatsapp_number is not null
    union all
    -- One row per device, so somebody with a phone and a laptop is told on
    -- both. The others have exactly one address each, which is why they were
    -- a plain case expression until now.
    select 'push', s.endpoint
      from public.push_subscriptions s
     where c.push_enabled and s.user_id = c.user_id
  ) ch
  on conflict (dedupe_key) do nothing;

  get diagnostics inserted = row_count;

  -- Work that is already late. Keyed by the day so a task that stays overdue
  -- nags once a day rather than on every scheduler run.
  with candidates as (
    select
      t.id as task_id, t.title, t.due_at,
      a.user_id, p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled, np.push_enabled,
      np.telegram_chat_id, np.whatsapp_number, np.due_soon_lead_hours
    from public.tasks t
    join public.task_assignments a on a.task_id = t.id
    join public.profiles p on p.id = a.user_id
    join public.notification_preferences np on np.user_id = a.user_id
    where t.status <> 'done'
      and t.deleted_at is null
      and t.due_at is not null
      and t.due_at < now()
      and np.remind_overdue
  )
  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    c.user_id, c.task_id, ch.channel, 'overdue',
    ch.recipient,
    'Overdue: ' || c.title,
    c.title || ' was due ' || to_char(c.due_at at time zone 'UTC', 'DD Mon HH24:MI') || ' UTC and is still open.',
    'overdue:' || c.task_id || ':' || c.user_id || ':' || ch.channel || case when ch.channel = 'push' then ':' || ch.recipient else '' end || ':' || to_char(now(), 'YYYY-MM-DD')
  from candidates c
  cross join lateral (
    select 'email'::text as channel, c.email as recipient
     where c.email_enabled
    union all
    select 'telegram', c.telegram_chat_id
     where c.telegram_enabled and c.telegram_chat_id is not null
    union all
    select 'whatsapp', c.whatsapp_number
     where c.whatsapp_enabled and c.whatsapp_number is not null
    union all
    -- One row per device, so somebody with a phone and a laptop is told on
    -- both. The others have exactly one address each, which is why they were
    -- a plain case expression until now.
    select 'push', s.endpoint
      from public.push_subscriptions s
     where c.push_enabled and s.user_id = c.user_id
  ) ch
  on conflict (dedupe_key) do nothing;

  -- Follow-ups that have come due, to whoever has to chase them.
  with candidates as (
    select
      t.id as task_id, t.title, t.follow_up_at, t.follow_up_note,
      a.user_id, p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled, np.push_enabled,
      np.telegram_chat_id, np.whatsapp_number, np.due_soon_lead_hours
    from public.tasks t
    join public.task_assignments a on a.task_id = t.id
    join public.profiles p on p.id = a.user_id
    join public.notification_preferences np on np.user_id = a.user_id
    where t.status <> 'done'
      and t.deleted_at is null
      and t.follow_up_at is not null
      and t.follow_up_at <= now()
      and np.remind_follow_up
  )
  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    c.user_id, c.task_id, ch.channel, 'follow_up',
    ch.recipient,
    'Follow up: ' || c.title,
    coalesce(c.follow_up_note, 'Time to follow up on ' || c.title) || ' (' || c.title || ')',
    'follow_up:' || c.task_id || ':' || c.user_id || ':' || ch.channel || case when ch.channel = 'push' then ':' || ch.recipient else '' end || ':' || extract(epoch from c.follow_up_at)::bigint
  from candidates c
  cross join lateral (
    select 'email'::text as channel, c.email as recipient
     where c.email_enabled
    union all
    select 'telegram', c.telegram_chat_id
     where c.telegram_enabled and c.telegram_chat_id is not null
    union all
    select 'whatsapp', c.whatsapp_number
     where c.whatsapp_enabled and c.whatsapp_number is not null
    union all
    -- One row per device, so somebody with a phone and a laptop is told on
    -- both. The others have exactly one address each, which is why they were
    -- a plain case expression until now.
    select 'push', s.endpoint
      from public.push_subscriptions s
     where c.push_enabled and s.user_id = c.user_id
  ) ch
  on conflict (dedupe_key) do nothing;

  return inserted;
end;
$$;

-- ---------------------------------------------------------------------------
-- Being handed work, on the device in your pocket
--
-- The same trigger, with devices added to the same union it already used.
-- Assignment is the one reminder that should not wait for the next sweep, so
-- it is also the one where a push is worth most.
--
-- The dedupe key gains the endpoint for push only, as above.
-- ---------------------------------------------------------------------------

create or replace function public.enqueue_assignment_reminder()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  t public.tasks%rowtype;
  prefs public.notification_preferences%rowtype;
begin
  select * into t from public.tasks where id = new.task_id;
  if not found then return null; end if;

  select * into prefs from public.notification_preferences where user_id = new.user_id;
  if not found or not prefs.remind_assigned then return null; end if;

  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    new.user_id, t.id, ch.channel, 'assigned',
    ch.recipient,
    'Assigned to you: ' || t.title,
    'You were assigned "' || t.title || '"'
      || coalesce(' - due ' || to_char(t.due_at at time zone 'UTC', 'DD Mon HH24:MI') || ' UTC', '') || '.',
    'assigned:' || t.id || ':' || new.user_id || ':' || ch.channel
      || case when ch.channel = 'push' then ':' || ch.recipient else '' end
  from (
    select 'email'::text as channel, (select email from public.profiles where id = new.user_id) as recipient
      where prefs.email_enabled
    union all
    select 'telegram', prefs.telegram_chat_id
      where prefs.telegram_enabled and prefs.telegram_chat_id is not null
    union all
    select 'whatsapp', prefs.whatsapp_number
      where prefs.whatsapp_enabled and prefs.whatsapp_number is not null
    union all
    select 'push', s.endpoint
      from public.push_subscriptions s
     where prefs.push_enabled and s.user_id = new.user_id
  ) ch
  where ch.recipient is not null
  on conflict (dedupe_key) do nothing;

  return null;
end;
$fn$;

-- =========================================================================
-- 20260927000027_reminder_failures.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- When a reminder cannot be delivered
--
-- A reminder that exhausted its four attempts was marked `failed` and that
-- was the end of it. Nobody was told — not the person waiting for it, not an
-- admin. The only symptom was somebody quietly not hearing about their work,
-- which reads as the portal not bothering rather than as a wrong phone
-- number or a revoked notification permission.
--
-- Two things here. The person gets a notification, in the same bell as
-- everything else, saying which channel failed. And an admin can see the
-- failures across the team without being handed the messages themselves.
-- ---------------------------------------------------------------------------

-- When it gave up, which the row never recorded. `created_at` is when it was
-- queued: for a reminder that spent an hour being retried those are an hour
-- apart, and "why did nobody hear about this" is a question about the second
-- one. Old rows keep their queued time as the best available answer.
alter table public.reminder_queue
  add column if not exists failed_at timestamptz;

comment on column public.reminder_queue.failed_at is
  'When delivery was given up on. Null while the row is still pending or was sent.';

alter table public.notifications drop constraint if exists notifications_type_known;
alter table public.notifications add constraint notifications_type_known check (
  type in (
    'task_assigned',
    'task_unassigned',
    'task_commented',
    'task_mentioned',
    'task_review_requested',
    'task_completed',
    'direct_message',
    'reminder_failed'
  )
);

-- ---------------------------------------------------------------------------
-- The team's delivery failures, for somebody who can act on them
--
-- `security definer` because an admin has no business reading the queue
-- itself: a row carries the message, and a message carries the work. This
-- hands back who, which channel, when and why — and never the body.
--
-- The admin check is inside the function rather than in a policy, so calling
-- it as anybody else is refused rather than quietly returning nothing.
-- ---------------------------------------------------------------------------

create or replace function public.reminder_failures(since_hours integer default 168)
returns table (
  user_id     uuid,
  person      text,
  channel     text,
  kind        text,
  attempts    integer,
  last_error  text,
  failed_at   timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
begin
  if not public.is_admin() then
    raise exception 'Only an admin can read delivery failures.'
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select
      q.user_id,
      coalesce(p.full_name, p.email) as person,
      q.channel,
      q.kind,
      q.attempts,
      q.last_error,
      coalesce(q.failed_at, q.created_at) as failed_at
    from public.reminder_queue q
    join public.profiles p on p.id = q.user_id
   where q.status = 'failed'
     and coalesce(q.failed_at, q.created_at) > now() - make_interval(hours => greatest(1, since_hours))
   order by coalesce(q.failed_at, q.created_at) desc
   limit 100;
end;
$fn$;

comment on function public.reminder_failures(integer) is
  'Recent undeliverable reminders, for an admin. Who, which channel and why — never the message.';

grant execute on function public.reminder_failures(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- And the same question about yourself, which anybody may ask
--
-- The existing policy already lets somebody read their own queue rows, so
-- this is only a convenience: the shape the profile page wants, without the
-- body, and without every caller having to remember the status filter.
-- ---------------------------------------------------------------------------

create or replace function public.my_reminder_failures(since_hours integer default 168)
returns table (
  channel    text,
  kind       text,
  attempts   integer,
  last_error text,
  failed_at  timestamptz
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $fn$
  select
    q.channel,
    q.kind,
    q.attempts,
    q.last_error,
    coalesce(q.failed_at, q.created_at)
  from public.reminder_queue q
   where q.user_id = auth.uid()
     and q.status = 'failed'
     and coalesce(q.failed_at, q.created_at) > now() - make_interval(hours => greatest(1, since_hours))
   order by coalesce(q.failed_at, q.created_at) desc
   limit 20;
$fn$;

comment on function public.my_reminder_failures(integer) is
  'Reminders that could not be delivered to you. Security invoker: RLS decides, as it does for the table.';

grant execute on function public.my_reminder_failures(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Telling the person
--
-- Written here rather than by the dispatcher because every other
-- notification in this schema is written by the database, and the table's
-- grants say so: nothing holding a user's session may insert one. The
-- dispatcher calls this with the row it has just given up on.
--
-- The message names the channel, because the fix is almost always a wrong
-- number or a permission somebody revoked, and neither is guessable from
-- "a reminder failed".
-- ---------------------------------------------------------------------------

create or replace function public.notify_reminder_failed(reminder uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  q public.reminder_queue%rowtype;
  heading text;
begin
  select * into q from public.reminder_queue where id = reminder;
  if not found or q.status <> 'failed' then
    return;
  end if;

  heading := case q.channel
    when 'email'    then 'A reminder could not be emailed to you'
    when 'telegram' then 'A reminder could not be sent to you on Telegram'
    when 'whatsapp' then 'A reminder could not be sent to you on WhatsApp'
    when 'push'     then 'A reminder could not reach one of your devices'
    else 'A reminder could not be delivered to you'
  end;

  insert into public.notifications (user_id, actor_id, type, title, body, task_id)
  values (
    q.user_id,
    null,
    'reminder_failed',
    heading,
    coalesce(q.subject, left(q.body, 140)),
    q.task_id
  );
end;
$fn$;

comment on function public.notify_reminder_failed(uuid) is
  'Tells somebody a reminder could not be delivered, naming the channel. Called by the dispatcher.';

-- =========================================================================
-- 20260927000028_error_log.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Errors, somewhere a person looks
--
-- Nothing captured what went wrong in the deployed app. A page that threw on
-- somebody's phone left a line in a Vercel log nobody reads, and the way a
-- fault was discovered was that somebody mentioned it — or did not, and
-- worked around it for a month.
--
-- This is deliberately not a third-party service. It would mean an account,
-- a key pasted into a dashboard, and somebody's task titles leaving the
-- country; the portal already has a database with row-level security and an
-- admin who signs in every day. Errors go there, and the admin sees them
-- where they already look.
--
-- What is kept is what identifies a fault, never a payload: the message, the
-- route, whether it came from the browser or the server. Two weeks of them,
-- swept by the same cron that drains the reminder queue.
-- ---------------------------------------------------------------------------

create table if not exists public.app_errors (
  id           uuid primary key default gen_random_uuid(),
  occurred_at  timestamptz not null default now(),
  -- Null for somebody who was not signed in: a sign-in page that throws is
  -- exactly the kind of fault worth knowing about.
  user_id      uuid references public.profiles (id) on delete set null,
  source       text not null check (source in ('browser', 'server')),
  -- Next's own reference for a server error. Printed on the error page, so
  -- somebody can quote it and an admin can find this row.
  digest       text,
  message      text not null check (char_length(message) between 1 and 2000),
  route        text check (char_length(route) <= 500),
  user_agent   text check (char_length(user_agent) <= 400)
);

create index if not exists app_errors_when_idx
  on public.app_errors (occurred_at desc);

alter table public.app_errors enable row level security;
alter table public.app_errors force row level security;

-- Anybody signed in may report what went wrong in front of them, and only
-- as themselves. Reading is another matter.
drop policy if exists "report what went wrong" on public.app_errors;
create policy "report what went wrong"
  on public.app_errors for insert
  with check (user_id is null or user_id = auth.uid());

-- No select policy at all: a message can carry a fragment of whatever it
-- failed on. Admins read through the function below, which the service role
-- and an admin check stand behind.
grant insert on public.app_errors to authenticated;

comment on table public.app_errors is
  'Faults from the deployed app, kept for two weeks. Write-only for everybody; read through recent_errors().';

-- ---------------------------------------------------------------------------
-- What has been going wrong
-- ---------------------------------------------------------------------------

create or replace function public.recent_errors(since_hours integer default 72)
returns table (
  occurred_at timestamptz,
  person      text,
  source      text,
  digest      text,
  message     text,
  route       text,
  seen        bigint
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
begin
  if not public.is_admin() then
    raise exception 'Only an admin can read the error log.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Grouped: one fault hit forty times is one line with a count, not forty
  -- lines burying everything else that happened that day.
  return query
    select
      max(e.occurred_at) as occurred_at,
      max(coalesce(p.full_name, p.email)) as person,
      e.source,
      max(e.digest) as digest,
      e.message,
      e.route,
      count(*) as seen
    from public.app_errors e
    left join public.profiles p on p.id = e.user_id
   where e.occurred_at > now() - make_interval(hours => greatest(1, since_hours))
   group by e.source, e.message, e.route
   order by max(e.occurred_at) desc
   limit 50;
end;
$fn$;

comment on function public.recent_errors(integer) is
  'Recent faults, grouped by message and route. Admins only; raises for anybody else.';

grant execute on function public.recent_errors(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Two weeks is plenty
--
-- Called by the same scheduled route that drains the reminder queue, so
-- there is nothing new to set up and nothing to remember.
-- ---------------------------------------------------------------------------

create or replace function public.purge_old_errors(older_than interval default interval '14 days')
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  removed integer;
begin
  delete from public.app_errors where occurred_at < now() - older_than;
  get diagnostics removed = row_count;
  return removed;
end;
$fn$;

comment on function public.purge_old_errors(interval) is
  'Drops error rows older than the given age. Called by the scheduled dispatcher.';

-- =========================================================================
-- 20260927000029_task_checklists.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- The small steps inside a task
--
-- "Meet with Kuwait banks" has five documents to bring, and there was
-- nowhere to put them. They went into the description as prose, where
-- nothing can be ticked off and nobody can see how far along it is — or they
-- went nowhere, and somebody arrived without the signatory list.
--
-- My List has had items since the beginning; a task has not. Same idea, with
-- one difference that matters: a personal note belongs to one person, and a
-- task belongs to whoever can see it.
--
-- Who may do what is exactly what the task itself allows, and deliberately
-- not a rule of its own: reading follows can_view_task, writing follows the
-- same predicate as an update to the task — `is_manager_or_admin() or
-- can_edit_task(...)`.
--
-- The first draft of this had a third rule, a `security definer` function so
-- that somebody could tick a step off without being able to rewrite it. The
-- test for it could not find anybody in that position: on a project, anyone
-- who can *see* a task is a manager, its author or assigned to it, and all
-- three may edit it. A special case that protects nobody is worse than none,
-- so the rules are the task's own.
-- ---------------------------------------------------------------------------

create table if not exists public.task_checklist_items (
  id         uuid primary key default gen_random_uuid(),
  task_id    uuid not null references public.tasks (id) on delete cascade,
  content    text not null check (char_length(btrim(content)) between 1 and 500),
  done       boolean not null default false,
  -- Gaps, so an item can be dropped between two without renumbering.
  position   integer not null default 0,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists task_checklist_items_task_idx
  on public.task_checklist_items (task_id, position);

alter table public.task_checklist_items enable row level security;
alter table public.task_checklist_items force row level security;

drop policy if exists "see the steps of a task you can see" on public.task_checklist_items;
create policy "see the steps of a task you can see"
  on public.task_checklist_items for select
  using (public.can_view_task(task_id));

drop policy if exists "plan the steps of a task you can edit" on public.task_checklist_items;
create policy "plan the steps of a task you can edit"
  on public.task_checklist_items for insert
  with check (public.is_manager_or_admin() or public.can_edit_task(task_id));

drop policy if exists "change the steps of a task you can edit" on public.task_checklist_items;
create policy "change the steps of a task you can edit"
  on public.task_checklist_items for update
  using (public.is_manager_or_admin() or public.can_edit_task(task_id))
  with check (public.is_manager_or_admin() or public.can_edit_task(task_id));

drop policy if exists "remove the steps of a task you can edit" on public.task_checklist_items;
create policy "remove the steps of a task you can edit"
  on public.task_checklist_items for delete
  using (public.is_manager_or_admin() or public.can_edit_task(task_id));

grant select, insert, update, delete on public.task_checklist_items to authenticated;

drop trigger if exists task_checklist_items_set_updated_at on public.task_checklist_items;
create trigger task_checklist_items_set_updated_at
  before update on public.task_checklist_items
  for each row execute function public.set_updated_at();

comment on table public.task_checklist_items is
  'The steps inside a task. Read and written under exactly the rules the task itself has.';

-- =========================================================================
-- 20260927000030_archive_projects.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Finishing with a project
--
-- Projects accumulated. A job delivered in 2026 sat in the sidebar next to
-- live work for as long as the portal ran, and in every project picker, and
-- in the dashboard's counts — and the only way to be rid of it was to delete
-- it, which takes its tasks, its comments and its history with it.
--
-- Archiving is the other answer: out of the way, still readable, and
-- reversible. Nothing is destroyed and nothing is hidden from somebody who
-- goes looking.
--
-- A column rather than a status enum, because there are exactly two states
-- and one of them is "not archived". `archived_at` also records when, which
-- a boolean would not.
-- ---------------------------------------------------------------------------

alter table public.projects
  add column if not exists archived_at timestamptz;

create index if not exists projects_live_idx
  on public.projects (archived_at)
  where archived_at is null;

comment on column public.projects.archived_at is
  'When the project was archived, or null while it is live. Archiving hides it from the sidebar and the pickers; nothing is deleted.';

-- ---------------------------------------------------------------------------
-- Archiving one
--
-- The update policy on projects already says managers and admins, so this
-- needs no rule of its own — it exists to be one statement that can be
-- called by name, and to refuse the thing a plain update would happily do:
-- archiving a project that still has work open in it.
--
-- `security invoker`, so the policy decides, exactly as it would for an
-- ordinary update.
-- ---------------------------------------------------------------------------

create or replace function public.set_project_archived(project uuid, archived boolean)
returns void
language plpgsql
security invoker
set search_path = public, pg_temp
as $fn$
declare
  still_open integer;
  touched integer;
begin
  if archived then
    select count(*) into still_open
      from public.tasks t
     where t.project_id = project
       and t.deleted_at is null
       and t.status <> 'done';

    if still_open > 0 then
      -- Left as the default raise code on purpose. The app maps
      -- check_violation to a generic "not allowed", which would throw away
      -- the one useful thing here: how many are left.
      raise exception 'That project still has % task(s) open.', still_open;
    end if;
  end if;

  update public.projects
     set archived_at = case when archived then now() else null end
   where id = project;

  get diagnostics touched = row_count;
  if touched = 0 then
    -- Row-level security filtered it: not a manager, or no such project.
    raise exception 'That project is not yours to archive.'
      using errcode = 'insufficient_privilege';
  end if;
end;
$fn$;

comment on function public.set_project_archived(uuid, boolean) is
  'Archives a project, or brings it back. Refuses while any task in it is still open.';

grant execute on function public.set_project_archived(uuid, boolean) to authenticated;

-- =========================================================================
-- 20260930000031_guard_telegram_chat.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- A Telegram chat is proven, not declared.
--
-- `telegram_chat_id` says in its own comment what it is for: the link code
-- exists so somebody can prove a chat is theirs by sending the bot a code
-- from inside it. The webhook then records the chat id Telegram reported,
-- which is the piece the app cannot discover on its own.
--
-- Nothing enforced that. The update policy on this table is
-- `user_id = auth.uid()`, which is right for the two dozen preference
-- columns beside it, and the app never writes this one — but PostgREST is
-- reachable from the browser with the anon key, so one hand-written PATCH
-- set the column to any chat at all and switched the channel on. The bot
-- then delivered that person's reminders, task titles included, to a chat
-- that never agreed to receive them.
--
-- The same shape as `guard_note_owner` and `guard_note_item_parent` in
-- migration 0019: the policy decides which row, and a trigger pins the
-- columns within it that the policy has no way to speak about.
--
-- Clearing it is still the owner's to do — that is what unlinking is — and
-- the webhook is unaffected: it runs with the service role, which carries no
-- `sub` claim, so `auth.uid()` is null for it and it passes straight
-- through. The same is true of a migration or a psql session.
--
-- No dictionary key for the message: the app has no path that reaches it, so
-- the only way to see it is to have gone around the app.
-- ---------------------------------------------------------------------------

create or replace function public.guard_telegram_chat()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- The webhook, a migration, the dispatcher: anything not acting as a
  -- signed-in person. They are the ones allowed to name a chat.
  if auth.uid() is null then
    return new;
  end if;

  -- Unchanged, or being cleared: both fine. Unlinking is the owner's.
  if new.telegram_chat_id is not distinct from old.telegram_chat_id
     or new.telegram_chat_id is null then
    return new;
  end if;

  raise exception
    'A Telegram chat is linked by sending the bot the code from your profile, not by setting it directly.'
    using errcode = 'insufficient_privilege';
end;
$$;

comment on function public.guard_telegram_chat() is
  'Pins notification_preferences.telegram_chat_id so only the verified webhook can name a chat.';

drop trigger if exists notification_preferences_guard_telegram on public.notification_preferences;
create trigger notification_preferences_guard_telegram
  before update on public.notification_preferences
  for each row execute function public.guard_telegram_chat();

-- =========================================================================
-- 20261002000032_project_status_updates.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- How a project is going, in the words of the person running it
--
-- The board says what state every task is in. It cannot say whether the
-- project is going to land: twelve cards in progress might be a week from
-- done or a month behind, and the difference lives in somebody's head. A
-- status update is that person writing it down — on track, at risk or off
-- track, and a paragraph on why — so the director reads it rather than asks.
--
-- Rows are appended, never edited. An update is a record of what somebody
-- said on a given day, and the history is the point: "at risk" three weeks
-- running reads differently from "at risk" once. A mistake is deleted and
-- written again.
--
-- Who may do what:
--
--   read    anyone who can see the project — the people doing the work
--           should see the same picture the people reporting on it do
--   post    managers and admins on that project, as themselves
--   delete  whoever wrote it, or an admin
-- ---------------------------------------------------------------------------

create table if not exists public.project_status_updates (
  id         uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  -- Kept when the author leaves, so the history does not lose its entries.
  author_id  uuid references public.profiles (id) on delete set null,
  status     text not null,
  body       text not null,
  created_at timestamptz not null default now(),

  constraint project_status_updates_status_known
    check (status in ('on_track', 'at_risk', 'off_track')),
  constraint project_status_updates_body_length
    check (char_length(btrim(body)) between 1 and 2000)
);

create index if not exists project_status_updates_recent_idx
  on public.project_status_updates (project_id, created_at desc);

comment on table public.project_status_updates is
  'What the person running a project says about how it is going. Append-only.';

alter table public.project_status_updates enable row level security;
alter table public.project_status_updates force row level security;

drop policy if exists "status is readable with the project" on public.project_status_updates;
create policy "status is readable with the project"
  on public.project_status_updates for select
  to authenticated
  using (public.can_view_project(project_id));

drop policy if exists "managers report on their projects" on public.project_status_updates;
create policy "managers report on their projects"
  on public.project_status_updates for insert
  to authenticated
  with check (
    author_id = auth.uid()
    and public.is_manager_or_admin()
    and public.can_view_project(project_id)
  );

-- No update policy, on purpose: see the header.

drop policy if exists "authors and admins withdraw an update" on public.project_status_updates;
create policy "authors and admins withdraw an update"
  on public.project_status_updates for delete
  to authenticated
  using (author_id = auth.uid() or public.is_admin());

grant select, insert, delete on public.project_status_updates to authenticated;

-- ---------------------------------------------------------------------------
-- Every live project's health, in one question
--
-- The dashboard needs, per project: the latest thing somebody said about it,
-- and how much of its work is open and late. Asked the obvious way that is
-- three queries per project. This is one statement with two lateral joins.
--
-- `security invoker`, so the counts are the caller's own view: an admin sees
-- every project, a manager the ones they are on. Deciding which of these
-- need attention is left to the app, where the rule can be read, tested and
-- changed without a migration.
-- ---------------------------------------------------------------------------

create or replace function public.project_health()
returns table (
  project_id     uuid,
  name           text,
  latest_status  text,
  latest_body    text,
  latest_at      timestamptz,
  latest_author  text,
  open_tasks     bigint,
  overdue_tasks  bigint
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select
    p.id,
    p.name,
    latest.status,
    latest.body,
    latest.created_at,
    coalesce(author.full_name, author.email),
    coalesce(work.open_tasks, 0),
    coalesce(work.overdue_tasks, 0)
  from public.projects p
  left join lateral (
    select u.status, u.body, u.created_at, u.author_id
      from public.project_status_updates u
     where u.project_id = p.id
     order by u.created_at desc
     limit 1
  ) latest on true
  left join public.profiles author on author.id = latest.author_id
  left join lateral (
    select
      count(*) filter (where t.status <> 'done') as open_tasks,
      count(*) filter (where t.status <> 'done' and t.due_at < now()) as overdue_tasks
      from public.tasks t
     where t.project_id = p.id
       and t.deleted_at is null
  ) work on true
  -- A finished project has nothing left to go wrong.
  where p.archived_at is null
  order by p.name;
$$;

comment on function public.project_health() is
  'Per live project: the latest status update, and open and overdue task counts, as the caller can see them.';

grant execute on function public.project_health() to authenticated;

-- =========================================================================
-- 20261002000033_comment_reactions.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Reacting to a comment
--
-- A good half of the replies on a task are "ok", "thanks", "on it" — a whole
-- comment, and a notification to everybody on the task, to say what a
-- thumb would. A reaction says it without either.
--
-- A short fixed set rather than any emoji: five that mean something at work
-- (agreed, done, thanks, looking, well done), stored as the character itself
-- so nothing has to translate them. The check is the list; widening it is a
-- one-line migration.
--
-- Who may do what:
--
--   see     anyone who can see the comment — which is anyone who can see its
--           task, the rule every other thing on a task already follows
--   react   the same people, as themselves
--   remove  only your own
--
-- No notification. Telling somebody that a colleague put a thumb on their
-- comment is the noise this exists to remove.
-- ---------------------------------------------------------------------------

create table if not exists public.comment_reactions (
  comment_id uuid not null references public.comments (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  emoji      text not null,
  created_at timestamptz not null default now(),

  -- One of each per person: tapping 👍 twice takes it back rather than
  -- counting two.
  primary key (comment_id, user_id, emoji),

  constraint comment_reactions_emoji_known
    check (emoji in ('👍', '✅', '🙏', '👀', '🎉'))
);

comment on table public.comment_reactions is
  'Who reacted to which comment, with which of the five allowed emoji.';

-- ---------------------------------------------------------------------------
-- Visibility, through the comment's own task
--
-- SECURITY DEFINER so the question can be asked without going through the
-- comments policy, which is itself asking can_view_task. One definition, the
-- same one the comment, the file and the history already resolve through.
-- ---------------------------------------------------------------------------

create or replace function public.can_view_comment(comment uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.comments c
     where c.id = comment
       and public.can_view_task(c.task_id)
  );
$$;

grant execute on function public.can_view_comment(uuid) to authenticated;

alter table public.comment_reactions enable row level security;
alter table public.comment_reactions force row level security;

drop policy if exists "reactions are visible with their comment" on public.comment_reactions;
create policy "reactions are visible with their comment"
  on public.comment_reactions for select
  to authenticated
  using (public.can_view_comment(comment_id));

drop policy if exists "people react as themselves" on public.comment_reactions;
create policy "people react as themselves"
  on public.comment_reactions for insert
  to authenticated
  with check (user_id = auth.uid() and public.can_view_comment(comment_id));

drop policy if exists "people take back their own reactions" on public.comment_reactions;
create policy "people take back their own reactions"
  on public.comment_reactions for delete
  to authenticated
  using (user_id = auth.uid());

grant select, insert, delete on public.comment_reactions to authenticated;

-- =========================================================================
-- 20261013000034_close_self_registration.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Accounts are added, not taken.
--
-- This portal is for one company's staff. Until now anybody who found its
-- address could register: the sign-in page offered "Create one", and the
-- Supabase project accepts sign-ups unless they are switched off in its
-- settings. A stranger who did that could see nothing of the work — tasks and
-- projects are guarded — but could read the team chat, see every colleague's
-- name, email and role, and message any of them.
--
-- The app no longer offers registration. This closes it underneath as well,
-- so it holds even if the project's sign-up setting is left on, and even for
-- somebody who calls Supabase's sign-up endpoint directly with the public key.
--
-- An account is accepted only when an admin added it. The Team page's "Add
-- teammate" does that through the server's service key and records which
-- admin asked in the account's app_metadata — which only the service key can
-- write; somebody signing themselves up can set user_metadata, not this. The
-- trigger checks that the id recorded there belongs to an admin.
--
-- The first account in an empty database is still let in and made admin, as
-- before, so a fresh deployment can bootstrap itself.
--
-- One consequence: adding a user from the Supabase dashboard is refused too,
-- because the dashboard cannot set app_metadata on creation. Add people from
-- the Team page.
--
-- Run in the Supabase SQL editor. Safe to run more than once.
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  assigned_role public.user_role;
  added_by_text text := new.raw_app_meta_data ->> 'added_by';
  added_by uuid;
begin
  if not exists (select 1 from public.profiles) then
    -- An empty database: this is the person setting it up.
    assigned_role := 'admin';
  else
    -- Checked before casting, so a malformed value is refused with the
    -- message below rather than with a cast error.
    if added_by_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      added_by := added_by_text::uuid;
    end if;

    if added_by is null or not exists (
      select 1 from public.profiles p
      where p.id = added_by and p.role = 'admin'
    ) then
      raise exception 'Accounts are added by an admin from the Team page.'
        using errcode = '42501';
    end if;

    assigned_role := 'member';
  end if;

  insert into public.profiles (id, email, full_name, avatar_url, role)
  values (
    new.id,
    new.email,
    nullif(btrim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), ''),
    nullif(btrim(coalesce(new.raw_user_meta_data ->> 'avatar_url', '')), ''),
    assigned_role
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

-- The trigger itself is unchanged; it is restated so this file stands alone.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =========================================================================
-- 20261013000035_attachment_files_follow_task.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- A task's files are as private as the task.
--
-- Attachments live in two places: a row in task_attachments, which says what
-- the file is called and which task it belongs to, and the file itself in the
-- task-attachments storage bucket. The row has followed the task since
-- project membership arrived — you only see the attachments of tasks you can
-- see. The file never did: the bucket's read rule let any signed-in account
-- read any file in it, and reading includes listing. So a member who may only
-- see the tasks assigned to them could list the bucket and download the files
-- of every other task, in every project.
--
-- Every file is stored under its task's id — "<task id>/<file>" — which is
-- also what the upload rule checks. Reading now asks the same question the
-- rest of the app asks about the task itself: can_view_task.
--
-- Run in the Supabase SQL editor. Safe to run more than once.
-- ---------------------------------------------------------------------------

-- The task a stored file belongs to, from the first segment of its path, or
-- null when that is not a task id. Checked before casting, so a stray object
-- with an odd name is simply unreadable rather than an error for everybody
-- listing the bucket.
create or replace function public.attachment_task_id(object_name text)
returns uuid
language sql
immutable
set search_path = public, pg_temp
as $$
  select case
    when split_part(object_name, '/', 1)
      ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then split_part(object_name, '/', 1)::uuid
  end
$$;

do $$
begin
  if to_regclass('storage.objects') is null then
    raise notice 'storage schema not found - skipping the attachment read policy';
    return;
  end if;

  execute $p$drop policy if exists "attachment objects readable by authenticated" on storage.objects$p$;
  execute $p$drop policy if exists "attachment objects readable with their task" on storage.objects$p$;
  execute $p$create policy "attachment objects readable with their task"
    on storage.objects for select
    to authenticated
    using (
      bucket_id = 'task-attachments'
      and public.can_view_task(public.attachment_task_id(name))
    )$p$;
end $$;

-- =========================================================================
-- 20261017000036_company_holidays.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Company holidays.
--
-- The working week is Sunday to Thursday (src/lib/work-week.ts); these are the
-- other days off — National Day, Liberation Day, the Eids. Date shortcuts step
-- over them, the calendar marks them, and reminders and the morning summary
-- are not sent on them.
--
-- One row per day. A holiday that runs several days, as the Eids do, is
-- several rows with the same name; the settings page groups them back.
--
-- Everybody signed in can read them — the calendar needs them — and only an
-- admin can change them.
--
-- Run in the Supabase SQL editor. Safe to run more than once.
-- ---------------------------------------------------------------------------

create table if not exists public.company_holidays (
  day        date primary key,
  name       text not null,
  created_by uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),

  constraint company_holidays_name_length
    check (length(btrim(name)) between 1 and 80)
);

comment on table public.company_holidays is
  'Days the company is closed besides the Friday–Saturday weekend.';

alter table public.company_holidays enable row level security;

grant select on public.company_holidays to authenticated;
grant insert, update, delete on public.company_holidays to authenticated;
grant all on public.company_holidays to service_role;

drop policy if exists "holidays are readable by the team" on public.company_holidays;
create policy "holidays are readable by the team"
  on public.company_holidays for select
  to authenticated
  using (true);

drop policy if exists "admins add holidays" on public.company_holidays;
create policy "admins add holidays"
  on public.company_holidays for insert
  to authenticated
  with check (public.is_admin());

drop policy if exists "admins change holidays" on public.company_holidays;
create policy "admins change holidays"
  on public.company_holidays for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "admins remove holidays" on public.company_holidays;
create policy "admins remove holidays"
  on public.company_holidays for delete
  to authenticated
  using (public.is_admin());

-- =========================================================================
-- 20261017000037_office_reminders.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Reminders on office time, and a morning summary.
--
-- Three things.
--
-- 1. Times in reminders are Kuwait's, not UTC's. "Due 17 Oct 09:00 UTC" was
--    noon in the office and nobody's arithmetic should be needed to read a
--    reminder. company_time_zone() names the zone once; Kuwait keeps no
--    summer time, so the same hour all year. An overdue task still nags once
--    a day — the office's day now, not Greenwich's.
--
-- 2. A morning summary, for whoever turns it on in Profile: one message
--    with what is overdue, due today and to follow up, instead of (or as well
--    as) one message per task. Sent once a day on the channels the person
--    already uses; people with nothing to do that day are not messaged.
--
-- 3. The functions that fill the queue are for the dispatcher, which runs
--    with the service key — not for anybody signed in. They were callable
--    by any session; harmless, as they only queue what is due anyway, but
--    nothing in the app needs it, so it is closed.
--
-- When the dispatcher runs at all — 08:00 Kuwait, working days only, never on
-- a Friday, Saturday or company holiday — is decided in the app
-- (src/lib/work-week.ts), so the rule lives in one place.
--
-- Run in the Supabase SQL editor after 36. Safe to run more than once.
-- ---------------------------------------------------------------------------

create or replace function public.company_time_zone()
returns text
language sql
immutable
as $$ select 'Asia/Kuwait' $$;

comment on function public.company_time_zone() is
  'The office''s time zone, for anything written in words: reminder times, which day it is.';

-- ---------------------------------------------------------------------------
-- 1. Office time in the messages
--
-- Repeated whole from 26, with only the time formats and the overdue day
-- changed: a plpgsql body cannot be patched in place.
-- ---------------------------------------------------------------------------

create or replace function public.enqueue_task_reminders()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  inserted integer := 0;
begin
  -- Work that is due within the recipient's chosen lead time.
  with candidates as (
    select
      t.id as task_id, t.title, t.due_at,
      a.user_id,
      p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled, np.push_enabled,
      np.telegram_chat_id, np.whatsapp_number, np.due_soon_lead_hours
    from public.tasks t
    join public.task_assignments a on a.task_id = t.id
    join public.profiles p on p.id = a.user_id
    join public.notification_preferences np on np.user_id = a.user_id
    where t.status <> 'done'
      and t.deleted_at is null
      and t.due_at is not null
      and np.remind_due_soon
      and t.due_at > now()
      and t.due_at <= now() + make_interval(hours => np.due_soon_lead_hours)
  )
  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    c.user_id, c.task_id, ch.channel, 'due_soon',
    ch.recipient,
    'Due soon: ' || c.title,
    c.title || ' is due ' || to_char(c.due_at at time zone public.company_time_zone(), 'Dy DD Mon, HH24:MI') || '.',
    'due_soon:' || c.task_id || ':' || c.user_id || ':' || ch.channel || case when ch.channel = 'push' then ':' || ch.recipient else '' end || ':' || extract(epoch from c.due_at)::bigint
  from candidates c
  cross join lateral (
    select 'email'::text as channel, c.email as recipient
     where c.email_enabled
    union all
    select 'telegram', c.telegram_chat_id
     where c.telegram_enabled and c.telegram_chat_id is not null
    union all
    select 'whatsapp', c.whatsapp_number
     where c.whatsapp_enabled and c.whatsapp_number is not null
    union all
    -- One row per device, so somebody with a phone and a laptop is told on
    -- both. The others have exactly one address each, which is why they were
    -- a plain case expression until now.
    select 'push', s.endpoint
      from public.push_subscriptions s
     where c.push_enabled and s.user_id = c.user_id
  ) ch
  on conflict (dedupe_key) do nothing;

  get diagnostics inserted = row_count;

  -- Work that is already late. Keyed by the day so a task that stays overdue
  -- nags once a day rather than on every scheduler run.
  with candidates as (
    select
      t.id as task_id, t.title, t.due_at,
      a.user_id, p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled, np.push_enabled,
      np.telegram_chat_id, np.whatsapp_number, np.due_soon_lead_hours
    from public.tasks t
    join public.task_assignments a on a.task_id = t.id
    join public.profiles p on p.id = a.user_id
    join public.notification_preferences np on np.user_id = a.user_id
    where t.status <> 'done'
      and t.deleted_at is null
      and t.due_at is not null
      and t.due_at < now()
      and np.remind_overdue
  )
  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    c.user_id, c.task_id, ch.channel, 'overdue',
    ch.recipient,
    'Overdue: ' || c.title,
    c.title || ' was due ' || to_char(c.due_at at time zone public.company_time_zone(), 'Dy DD Mon, HH24:MI') || ' and is still open.',
    'overdue:' || c.task_id || ':' || c.user_id || ':' || ch.channel || case when ch.channel = 'push' then ':' || ch.recipient else '' end || ':' || to_char(now() at time zone public.company_time_zone(), 'YYYY-MM-DD')
  from candidates c
  cross join lateral (
    select 'email'::text as channel, c.email as recipient
     where c.email_enabled
    union all
    select 'telegram', c.telegram_chat_id
     where c.telegram_enabled and c.telegram_chat_id is not null
    union all
    select 'whatsapp', c.whatsapp_number
     where c.whatsapp_enabled and c.whatsapp_number is not null
    union all
    -- One row per device, so somebody with a phone and a laptop is told on
    -- both. The others have exactly one address each, which is why they were
    -- a plain case expression until now.
    select 'push', s.endpoint
      from public.push_subscriptions s
     where c.push_enabled and s.user_id = c.user_id
  ) ch
  on conflict (dedupe_key) do nothing;

  -- Follow-ups that have come due, to whoever has to chase them.
  with candidates as (
    select
      t.id as task_id, t.title, t.follow_up_at, t.follow_up_note,
      a.user_id, p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled, np.push_enabled,
      np.telegram_chat_id, np.whatsapp_number, np.due_soon_lead_hours
    from public.tasks t
    join public.task_assignments a on a.task_id = t.id
    join public.profiles p on p.id = a.user_id
    join public.notification_preferences np on np.user_id = a.user_id
    where t.status <> 'done'
      and t.deleted_at is null
      and t.follow_up_at is not null
      and t.follow_up_at <= now()
      and np.remind_follow_up
  )
  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    c.user_id, c.task_id, ch.channel, 'follow_up',
    ch.recipient,
    'Follow up: ' || c.title,
    coalesce(c.follow_up_note, 'Time to follow up on ' || c.title) || ' (' || c.title || ')',
    'follow_up:' || c.task_id || ':' || c.user_id || ':' || ch.channel || case when ch.channel = 'push' then ':' || ch.recipient else '' end || ':' || extract(epoch from c.follow_up_at)::bigint
  from candidates c
  cross join lateral (
    select 'email'::text as channel, c.email as recipient
     where c.email_enabled
    union all
    select 'telegram', c.telegram_chat_id
     where c.telegram_enabled and c.telegram_chat_id is not null
    union all
    select 'whatsapp', c.whatsapp_number
     where c.whatsapp_enabled and c.whatsapp_number is not null
    union all
    -- One row per device, so somebody with a phone and a laptop is told on
    -- both. The others have exactly one address each, which is why they were
    -- a plain case expression until now.
    select 'push', s.endpoint
      from public.push_subscriptions s
     where c.push_enabled and s.user_id = c.user_id
  ) ch
  on conflict (dedupe_key) do nothing;

  return inserted;
end;
$$;

-- Being assigned something, likewise.
create or replace function public.enqueue_assignment_reminder()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  t public.tasks%rowtype;
  prefs public.notification_preferences%rowtype;
begin
  select * into t from public.tasks where id = new.task_id;
  if not found then return null; end if;

  select * into prefs from public.notification_preferences where user_id = new.user_id;
  if not found or not prefs.remind_assigned then return null; end if;

  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    new.user_id, t.id, ch.channel, 'assigned',
    ch.recipient,
    'Assigned to you: ' || t.title,
    'You were assigned "' || t.title || '"'
      || coalesce(' - due ' || to_char(t.due_at at time zone public.company_time_zone(), 'Dy DD Mon, HH24:MI'), '') || '.',
    'assigned:' || t.id || ':' || new.user_id || ':' || ch.channel
      || case when ch.channel = 'push' then ':' || ch.recipient else '' end
  from (
    select 'email'::text as channel, (select email from public.profiles where id = new.user_id) as recipient
      where prefs.email_enabled
    union all
    select 'telegram', prefs.telegram_chat_id
      where prefs.telegram_enabled and prefs.telegram_chat_id is not null
    union all
    select 'whatsapp', prefs.whatsapp_number
      where prefs.whatsapp_enabled and prefs.whatsapp_number is not null
    union all
    select 'push', s.endpoint
      from public.push_subscriptions s
     where prefs.push_enabled and s.user_id = new.user_id
  ) ch
  where ch.recipient is not null
  on conflict (dedupe_key) do nothing;

  return null;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- 2. The morning summary
-- ---------------------------------------------------------------------------

alter table public.notification_preferences
  add column if not exists morning_summary boolean not null default false;

comment on column public.notification_preferences.morning_summary is
  'Whether this person gets one message each working morning listing their day.';

alter table public.reminder_queue
  drop constraint if exists reminder_queue_kind_check;

alter table public.reminder_queue
  add constraint reminder_queue_kind_check
  check (kind in ('assigned', 'due_soon', 'overdue', 'follow_up', 'summary'));

/**
 * One summary per person and channel for the office day `as_of` falls on.
 *
 * `as_of` is now() except in tests, which need a fixed working morning. Each
 * task is listed once, under the most pressing of: overdue, due today, follow
 * up today. Eight lines at most, then a count of the rest — a summary that
 * scrolls is not a summary.
 *
 * WhatsApp gets one line: its templates refuse a variable with a line break.
 */
create or replace function public.enqueue_morning_summaries(as_of timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  zone      constant text := public.company_time_zone();
  today     constant date := (as_of at time zone zone)::date;
  day_end   constant timestamptz := (today + 1)::timestamp at time zone zone;
  inserted  integer := 0;
begin
  with items as (
    select
      a.user_id,
      t.title,
      case
        when t.due_at < as_of   then 1   -- overdue
        when t.due_at < day_end then 2   -- due today
        else                         3   -- follow up today
      end as rank,
      case
        when t.due_at < day_end then t.due_at
        else t.follow_up_at
      end as moment
    from public.tasks t
    join public.task_assignments a on a.task_id = t.id
    where t.status <> 'done'
      and t.deleted_at is null
      and (t.due_at < day_end or t.follow_up_at < day_end)
  ),
  lines as (
    select
      i.user_id, i.rank,
      row_number() over (partition by i.user_id order by i.rank, i.moment, i.title) as n,
      i.title || case i.rank
        when 1 then ' — overdue since ' || to_char(i.moment at time zone zone, 'Dy DD Mon')
        when 2 then ' — due ' || to_char(i.moment at time zone zone, 'HH24:MI')
        else        ' — follow up'
      end as line
    from items i
  ),
  people as (
    select
      l.user_id,
      count(*) filter (where l.rank = 1) as overdue,
      count(*) filter (where l.rank = 2) as due_today,
      count(*) filter (where l.rank = 3) as follow_ups,
      count(*) as total,
      array_agg(l.line order by l.n) filter (where l.n <= 8) as shown
    from lines l
    group by l.user_id
  ),
  summaries as (
    select
      pe.*, p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled, np.push_enabled,
      np.telegram_chat_id, np.whatsapp_number,
      'Your day: ' || concat_ws(', ',
        case when pe.due_today  > 0 then pe.due_today  || ' due today' end,
        case when pe.overdue    > 0 then pe.overdue    || ' overdue' end,
        case when pe.follow_ups > 0 then pe.follow_ups || ' to follow up' end
      ) as subject,
      case when pe.total > 8 then 'and ' || (pe.total - 8) || ' more.' end as rest
    from people pe
    join public.profiles p on p.id = pe.user_id
    join public.notification_preferences np on np.user_id = pe.user_id
    where np.morning_summary
  )
  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    s.user_id, null, ch.channel, 'summary',
    ch.recipient,
    s.subject,
    case
      when ch.channel = 'whatsapp'
        then concat_ws('; ', array_to_string(s.shown, '; '), s.rest)
      else concat_ws(E'\n', '• ' || array_to_string(s.shown, E'\n• '), s.rest)
    end,
    'summary:' || s.user_id || ':' || ch.channel
      || case when ch.channel = 'push' then ':' || ch.recipient else '' end
      || ':' || to_char(today, 'YYYY-MM-DD')
  from summaries s
  cross join lateral (
    select 'email'::text as channel, s.email as recipient
     where s.email_enabled
    union all
    select 'telegram', s.telegram_chat_id
     where s.telegram_enabled and s.telegram_chat_id is not null
    union all
    select 'whatsapp', s.whatsapp_number
     where s.whatsapp_enabled and s.whatsapp_number is not null
    union all
    select 'push', d.endpoint
      from public.push_subscriptions d
     where s.push_enabled and d.user_id = s.user_id
  ) ch
  where ch.recipient is not null
  on conflict (dedupe_key) do nothing;

  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. For the dispatcher only
-- ---------------------------------------------------------------------------

revoke all on function public.enqueue_task_reminders() from public, anon, authenticated;
revoke all on function public.enqueue_morning_summaries(timestamptz) from public, anon, authenticated;
grant execute on function public.enqueue_task_reminders() to service_role;
grant execute on function public.enqueue_morning_summaries(timestamptz) to service_role;

-- =========================================================================
-- 20261017000038_two_step_sign_in.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Two-step sign-in.
--
-- Anybody can add an authenticator app in Profile; admins must, before they
-- can add people or change roles. Once someone has, their password alone is
-- not enough: a session that has the password but not yet the code counts
-- here as a member — whatever their role — until the code is entered.
--
-- The app sends such a session to the code page anyway. This is what makes
-- that hold for somebody who skips the app and talks to the database
-- directly with a stolen password: every role check in the schema goes
-- through current_user_role(), so changing it here covers all of them —
-- is_admin(), is_manager_or_admin(), the guard on role changes.
--
-- Nobody who has not set it up is affected, so this cannot lock anybody out.
--
-- Run in the Supabase SQL editor after 37. Safe to run more than once.
-- ---------------------------------------------------------------------------

/**
 * True when the caller has an authenticator app but this session was opened
 * with the password alone. Supabase records which in the token's `aal`
 * claim: aal1 after a password, aal2 after the code.
 */
create or replace function public.second_step_pending()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2'
     and exists (
       select 1 from auth.mfa_factors f
        where f.user_id = auth.uid()
          and f.status = 'verified'
     );
$$;

comment on function public.second_step_pending() is
  'Whether the caller has two-step sign-in but has not entered the code this session.';

create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
           when public.second_step_pending() then 'member'::public.user_role
           else role
         end
    from public.profiles
   where id = auth.uid();
$$;

comment on function public.current_user_role() is
  'Role of the calling user — member until the second step, for those who have one. SECURITY DEFINER so RLS on profiles does not recurse.';

grant execute on function public.second_step_pending() to authenticated;

-- =========================================================================
-- 20261017000039_labels.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Labels.
--
-- A word or two on a task that cuts across projects — "Bank", "Ministry",
-- "Waiting for signature" — so a list can be narrowed to it. One set for the
-- whole company, kept by admins and managers in Settings; they put them on
-- tasks as they plan them. Everybody sees them.
--
-- Colours are a small fixed set, shown as a dot beside the name. Amber is
-- not among them: in this app it means late, and nothing else.
--
-- Run in the Supabase SQL editor after 38. Safe to run more than once.
-- ---------------------------------------------------------------------------

create table if not exists public.labels (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  colour     text not null default 'slate',
  created_by uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),

  constraint labels_name_length check (length(btrim(name)) between 1 and 30),
  constraint labels_colour check (colour in ('slate', 'blue', 'green', 'violet', 'pink', 'teal'))
);

-- "Bank" and "bank " are the same label.
create unique index if not exists labels_name_unique on public.labels (lower(btrim(name)));

create table if not exists public.task_labels (
  task_id    uuid not null references public.tasks (id) on delete cascade,
  label_id   uuid not null references public.labels (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (task_id, label_id)
);

create index if not exists task_labels_label_idx on public.task_labels (label_id);

comment on table public.labels is
  'Words that cut across projects, put on tasks to narrow a list to them.';
comment on table public.task_labels is
  'Which labels are on which task. Seen with the task; set by whoever plans it.';

alter table public.labels enable row level security;
alter table public.labels force row level security;
alter table public.task_labels enable row level security;
alter table public.task_labels force row level security;

-- The labels themselves --------------------------------------------------------

drop policy if exists "labels are readable by the team" on public.labels;
create policy "labels are readable by the team"
  on public.labels for select to authenticated
  using (true);

drop policy if exists "planners add labels" on public.labels;
create policy "planners add labels"
  on public.labels for insert to authenticated
  with check (public.is_manager_or_admin());

drop policy if exists "planners change labels" on public.labels;
create policy "planners change labels"
  on public.labels for update to authenticated
  using (public.is_manager_or_admin())
  with check (public.is_manager_or_admin());

drop policy if exists "planners remove labels" on public.labels;
create policy "planners remove labels"
  on public.labels for delete to authenticated
  using (public.is_manager_or_admin());

-- Labels on tasks ---------------------------------------------------------------

drop policy if exists "see the labels on a task you can see" on public.task_labels;
create policy "see the labels on a task you can see"
  on public.task_labels for select to authenticated
  using (public.can_view_task(task_id));

drop policy if exists "planners label tasks" on public.task_labels;
create policy "planners label tasks"
  on public.task_labels for insert to authenticated
  with check (public.is_manager_or_admin() and public.can_view_task(task_id));

drop policy if exists "planners unlabel tasks" on public.task_labels;
create policy "planners unlabel tasks"
  on public.task_labels for delete to authenticated
  using (public.is_manager_or_admin() and public.can_view_task(task_id));

grant select, insert, update, delete on public.labels to authenticated;
grant select, insert, delete on public.task_labels to authenticated;
grant all on public.labels, public.task_labels to service_role;

-- =========================================================================
-- 20261017000040_task_dependencies.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Waiting on.
--
-- "Pay the deposit" cannot start until "Get the quote approved" is done. A
-- task can say which others it waits on; lists then show it as waiting
-- while any of them is open, and when the last one is finished, whoever is
-- on the waiting task is told it can go ahead.
--
-- Planners — admins and managers — link tasks, as they plan the rest. A link
-- is seen with the task that waits, and only made between tasks the planner
-- can see. A task cannot end up waiting on itself, however far round.
--
-- Run in the Supabase SQL editor after 39. Safe to run more than once.
-- ---------------------------------------------------------------------------

create table if not exists public.task_dependencies (
  task_id    uuid not null references public.tasks (id) on delete cascade,
  blocked_by uuid not null references public.tasks (id) on delete cascade,
  created_by uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (task_id, blocked_by),
  constraint task_dependencies_not_itself check (task_id <> blocked_by)
);

create index if not exists task_dependencies_blocked_by_idx
  on public.task_dependencies (blocked_by);

comment on table public.task_dependencies is
  'Task task_id cannot start until task blocked_by is done.';

alter table public.task_dependencies enable row level security;
alter table public.task_dependencies force row level security;

drop policy if exists "see what a task you can see waits on" on public.task_dependencies;
create policy "see what a task you can see waits on"
  on public.task_dependencies for select to authenticated
  using (public.can_view_task(task_id));

drop policy if exists "planners link tasks they can see" on public.task_dependencies;
create policy "planners link tasks they can see"
  on public.task_dependencies for insert to authenticated
  with check (
    public.is_manager_or_admin()
    and public.can_view_task(task_id)
    and public.can_view_task(blocked_by)
  );

drop policy if exists "planners unlink tasks" on public.task_dependencies;
create policy "planners unlink tasks"
  on public.task_dependencies for delete to authenticated
  using (public.is_manager_or_admin() and public.can_view_task(task_id));

grant select, insert, delete on public.task_dependencies to authenticated;
grant all on public.task_dependencies to service_role;

-- ---------------------------------------------------------------------------
-- No circles: A waits on B waits on C waits on A would wait forever.
-- Definer, so the whole chain is followed, not only the part this caller sees.
-- ---------------------------------------------------------------------------

create or replace function public.guard_task_dependency_cycle()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if exists (
    with recursive chain (id) as (
      select d.blocked_by from public.task_dependencies d where d.task_id = new.blocked_by
      union
      select d.blocked_by from public.task_dependencies d join chain c on d.task_id = c.id
    )
    select 1 from chain where id = new.task_id
  ) then
    raise exception 'task.dependencyCycle' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists task_dependencies_no_cycle on public.task_dependencies;
create trigger task_dependencies_no_cycle
  before insert on public.task_dependencies
  for each row execute function public.guard_task_dependency_cycle();

-- ---------------------------------------------------------------------------
-- How many open tasks this one waits on, as a column every task list can ask
-- for (`select=*,waiting_on`). Invoker, so it counts only what the caller can
-- see; a binned task is not waited on.
-- ---------------------------------------------------------------------------

create or replace function public.waiting_on(t public.tasks)
returns integer
language sql
stable
set search_path = public, pg_temp
as $$
  select count(*)::integer
    from public.task_dependencies d
    join public.tasks b on b.id = d.blocked_by
   where d.task_id = t.id
     and b.status <> 'done'
     and b.deleted_at is null;
$$;

grant execute on function public.waiting_on(public.tasks) to authenticated;

-- ---------------------------------------------------------------------------
-- Ready to go: when a task is finished, the people on each task that was
-- waiting only on it are told.
-- ---------------------------------------------------------------------------

alter table public.notifications drop constraint if exists notifications_type_known;
alter table public.notifications add constraint notifications_type_known check (
  type in (
    'task_assigned',
    'task_unassigned',
    'task_commented',
    'task_mentioned',
    'task_review_requested',
    'task_completed',
    'direct_message',
    'reminder_failed',
    'task_unblocked'
  )
);

create or replace function public.notify_unblocked()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  waiting record;
  person uuid;
begin
  if new.status <> 'done' or old.status = 'done' then
    return new;
  end if;

  for waiting in
    select w.id, w.title, w.project_id
      from public.task_dependencies d
      join public.tasks w on w.id = d.task_id
     where d.blocked_by = new.id
       and w.status <> 'done'
       and w.deleted_at is null
       -- Nothing else it waits on is still open.
       and not exists (
         select 1
           from public.task_dependencies other
           join public.tasks b on b.id = other.blocked_by
          where other.task_id = w.id
            and other.blocked_by <> new.id
            and b.status <> 'done'
            and b.deleted_at is null
       )
  loop
    for person in
      select a.user_id from public.task_assignments a where a.task_id = waiting.id
    loop
      perform public.push_notification(
        person,
        auth.uid(),
        'task_unblocked',
        'Ready to go: ' || waiting.title,
        new.title || ' is done.',
        waiting.id,
        waiting.project_id
      );
    end loop;
  end loop;

  return new;
end;
$$;

drop trigger if exists tasks_notify_unblocked on public.tasks;
create trigger tasks_notify_unblocked
  after update of status on public.tasks
  for each row execute function public.notify_unblocked();

-- =========================================================================
-- 20261017000041_task_templates.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Task templates.
--
-- The same work comes round again — month-end payroll, a new starter, a
-- licence renewal — with the same steps each time. A template keeps the
-- title, description, priority, labels and steps of one such task, and how
-- many working days after today it is usually due. Anybody creating a task
-- can start from one; admins and managers keep them, by saving a task as a
-- template or from Settings.
--
-- Run in the Supabase SQL editor after 40. Safe to run more than once.
-- ---------------------------------------------------------------------------

create table if not exists public.task_templates (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null,
  title               text not null,
  description         text,
  priority            public.task_priority not null default 'medium',
  steps               text[] not null default '{}',
  label_ids           uuid[] not null default '{}',
  due_in_working_days integer,
  created_by          uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint task_templates_name_length check (length(btrim(name)) between 1 and 80),
  constraint task_templates_title_length check (length(btrim(title)) between 1 and 200),
  constraint task_templates_steps_count check (cardinality(steps) <= 50),
  constraint task_templates_due_range check (due_in_working_days between 0 and 365)
);

comment on table public.task_templates is
  'Work that comes round again: a task''s title, steps and labels, to start the next one from.';

alter table public.task_templates enable row level security;
alter table public.task_templates force row level security;

drop policy if exists "templates are readable by the team" on public.task_templates;
create policy "templates are readable by the team"
  on public.task_templates for select to authenticated
  using (true);

drop policy if exists "planners add templates" on public.task_templates;
create policy "planners add templates"
  on public.task_templates for insert to authenticated
  with check (public.is_manager_or_admin());

drop policy if exists "planners change templates" on public.task_templates;
create policy "planners change templates"
  on public.task_templates for update to authenticated
  using (public.is_manager_or_admin())
  with check (public.is_manager_or_admin());

drop policy if exists "planners remove templates" on public.task_templates;
create policy "planners remove templates"
  on public.task_templates for delete to authenticated
  using (public.is_manager_or_admin());

grant select, insert, update, delete on public.task_templates to authenticated;
grant all on public.task_templates to service_role;

drop trigger if exists task_templates_set_updated_at on public.task_templates;
create trigger task_templates_set_updated_at
  before update on public.task_templates
  for each row execute function public.set_updated_at();

-- =========================================================================
-- 20261017000042_telegram_quick_add.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Adding work from Telegram.
--
-- Once someone has linked Telegram for reminders, anything they send the
-- bot that is not a command is added as theirs. Admins and managers get a
-- general task, assigned to themselves; members, who do not create general
-- tasks or assign them, get an item on a "Telegram" list in My List — the
-- same rules the app has, from the chat.
--
-- add_from_chat() is called by the webhook with the service key, which
-- answers to nobody; so it does the work as the person whose chat it is.
-- Every trigger — the activity log, notifications — sees them as the actor.
--
-- And the assignment reminder is no longer sent to somebody who assigned
-- themselves.
--
-- Run in the Supabase SQL editor after 41. Safe to run more than once.
-- ---------------------------------------------------------------------------

create or replace function public.add_from_chat(
  chat          text,
  item_title    text,
  item_detail   text default null,
  item_priority public.task_priority default 'medium',
  due           timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  person      uuid;
  person_role public.user_role;
  created     uuid;
  inbox       uuid;
  title_text  text := left(btrim(coalesce(item_title, '')), 200);
  detail_text text := nullif(btrim(coalesce(item_detail, '')), '');
begin
  if title_text = '' or chat is null then
    return null;
  end if;

  select np.user_id, p.role into person, person_role
    from public.notification_preferences np
    join public.profiles p on p.id = np.user_id
   where np.telegram_chat_id = chat
   limit 1;
  if person is null then
    return null;
  end if;

  -- From here on, as them.
  perform set_config('request.jwt.claim.sub', person::text, true);

  if person_role in ('admin', 'manager') then
    insert into public.tasks (project_id, title, description, priority, due_at, created_by, position)
    values (
      null, title_text, detail_text, item_priority, due, person,
      coalesce((select max(position) from public.tasks where project_id is null and status = 'todo'), 0) + 1024
    )
    returning id into created;

    insert into public.task_assignments (task_id, user_id) values (created, person);
    return jsonb_build_object('kind', 'task', 'id', created);
  end if;

  select id into inbox
    from public.personal_notes
   where user_id = person and title = 'Telegram'
   order by created_at
   limit 1;
  if inbox is null then
    insert into public.personal_notes (user_id, title) values (person, 'Telegram')
    returning id into inbox;
  end if;

  insert into public.personal_note_items (note_id, user_id, content, position)
  values (
    inbox, person,
    left(concat_ws(' — ', title_text, detail_text), 1000),
    coalesce((select max(position) from public.personal_note_items where note_id = inbox), 0) + 1024
  )
  returning id into created;

  -- To the top of My List, where the newest thing belongs.
  update public.personal_notes set updated_at = now() where id = inbox;
  return jsonb_build_object('kind', 'note', 'id', created);
end;
$$;

revoke all on function public.add_from_chat(text, text, text, public.task_priority, timestamptz)
  from public, anon, authenticated;
grant execute on function public.add_from_chat(text, text, text, public.task_priority, timestamptz)
  to service_role;

-- ---------------------------------------------------------------------------
-- No "Assigned to you" for assigning yourself. Repeated whole from 37 with
-- that one check added.
-- ---------------------------------------------------------------------------

create or replace function public.enqueue_assignment_reminder()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  t public.tasks%rowtype;
  prefs public.notification_preferences%rowtype;
begin
  select * into t from public.tasks where id = new.task_id;
  if not found then return null; end if;

  -- Nobody needs telling that they assigned themselves: from the task form,
  -- or from Telegram, where the bot has just said so.
  if new.user_id = auth.uid() then return null; end if;

  select * into prefs from public.notification_preferences where user_id = new.user_id;
  if not found or not prefs.remind_assigned then return null; end if;

  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    new.user_id, t.id, ch.channel, 'assigned',
    ch.recipient,
    'Assigned to you: ' || t.title,
    'You were assigned "' || t.title || '"'
      || coalesce(' - due ' || to_char(t.due_at at time zone public.company_time_zone(), 'Dy DD Mon, HH24:MI'), '') || '.',
    'assigned:' || t.id || ':' || new.user_id || ':' || ch.channel
      || case when ch.channel = 'push' then ':' || ch.recipient else '' end
  from (
    select 'email'::text as channel, (select email from public.profiles where id = new.user_id) as recipient
      where prefs.email_enabled
    union all
    select 'telegram', prefs.telegram_chat_id
      where prefs.telegram_enabled and prefs.telegram_chat_id is not null
    union all
    select 'whatsapp', prefs.whatsapp_number
      where prefs.whatsapp_enabled and prefs.whatsapp_number is not null
    union all
    select 'push', s.endpoint
      from public.push_subscriptions s
     where prefs.push_enabled and s.user_id = new.user_id
  ) ch
  where ch.recipient is not null
  on conflict (dedupe_key) do nothing;

  return null;
end;
$fn$;

-- =========================================================================
-- 20261017000043_work_report.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- The work report.
--
-- What the Reports page shows, in one call: how much was finished and added
-- in a period and the one before it, how much was finished on time, what is
-- overdue now, the period week by week (or month by month), open work by
-- person, and each project's progress.
--
-- Invoker, so it counts only what the person asking can see — the same rows
-- the rest of the app shows them. Days are the office's (company_time_zone);
-- weeks start on Sunday, as the office's do.
--
-- A task's finishing time is the last time it was moved to done, from the
-- activity log; a task done before the log existed falls back to when it was
-- last touched.
--
-- Run in the Supabase SQL editor after 42. Safe to run more than once.
-- ---------------------------------------------------------------------------

create or replace function public.work_report(
  first_day date,
  last_day  date,
  grain     text default 'week'
)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  with
  settings as (
    select public.company_time_zone() as zone,
           (last_day - first_day + 1) as length
  ),
  periods as (
    select
      (first_day::timestamp at time zone s.zone) as starts,
      ((last_day + 1)::timestamp at time zone s.zone) as ends,
      ((first_day - s.length)::timestamp at time zone s.zone) as before_starts
    from settings s
  ),
  live as (
    select * from public.tasks where deleted_at is null
  ),
  finished as (
    select
      t.id, t.due_at,
      coalesce(
        (select max(a.created_at) from public.task_activity a
          where a.task_id = t.id and a.action = 'status_changed' and a.new_value = 'done'),
        t.updated_at
      ) as at
    from live t
    where t.status = 'done'
  ),
  buckets as (
    select
      b::date as starts,
      (case when grain = 'month' then b + interval '1 month' else b + interval '7 days' end)::date as ends
    from generate_series(
      case when grain = 'month'
        then date_trunc('month', first_day)::date
        else first_day - extract(dow from first_day)::integer
      end,
      last_day,
      case when grain = 'month' then interval '1 month' else interval '7 days' end
    ) b
  ),
  local as (
    select
      (select zone from settings) as zone
  )
  select jsonb_build_object(
    'finished', (select count(*) from finished f, periods p where f.at >= p.starts and f.at < p.ends),
    'finishedBefore', (select count(*) from finished f, periods p where f.at >= p.before_starts and f.at < p.starts),
    'added', (select count(*) from live t, periods p where t.created_at >= p.starts and t.created_at < p.ends),
    'addedBefore', (select count(*) from live t, periods p where t.created_at >= p.before_starts and t.created_at < p.starts),
    'onTime', (select count(*) from finished f, periods p
                where f.at >= p.starts and f.at < p.ends and f.due_at is not null and f.at <= f.due_at),
    'withDue', (select count(*) from finished f, periods p
                 where f.at >= p.starts and f.at < p.ends and f.due_at is not null),
    'onTimeBefore', (select count(*) from finished f, periods p
                      where f.at >= p.before_starts and f.at < p.starts and f.due_at is not null and f.at <= f.due_at),
    'withDueBefore', (select count(*) from finished f, periods p
                       where f.at >= p.before_starts and f.at < p.starts and f.due_at is not null),
    'overdueNow', (select count(*) from live t where t.status <> 'done' and t.due_at < now()),
    'buckets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'starts', b.starts,
        'added', (select count(*) from live t
                   where (t.created_at at time zone l.zone)::date >= b.starts
                     and (t.created_at at time zone l.zone)::date < b.ends),
        'finished', (select count(*) from finished f
                      where (f.at at time zone l.zone)::date >= b.starts
                        and (f.at at time zone l.zone)::date < b.ends)
      ) order by b.starts)
      from buckets b, local l
    ), '[]'::jsonb),
    'people', coalesce((
      select jsonb_agg(row_to_json(x)::jsonb order by x.open desc, x.name)
      from (
        select
          p.id,
          coalesce(nullif(p.full_name, ''), p.email) as name,
          count(*) as open,
          count(*) filter (where t.due_at < now()) as overdue
        from public.task_assignments a
        join live t on t.id = a.task_id
        join public.profiles p on p.id = a.user_id
        where t.status <> 'done'
        group by p.id, p.full_name, p.email
      ) x
    ), '[]'::jsonb),
    'projects', coalesce((
      select jsonb_agg(row_to_json(y)::jsonb order by y.name)
      from (
        select
          pr.id,
          pr.name,
          count(t.id) as total,
          count(t.id) filter (where t.status = 'done') as done,
          count(t.id) filter (where t.status <> 'done' and t.due_at < now()) as overdue
        from public.projects pr
        left join live t on t.project_id = pr.id
        where pr.archived_at is null
        group by pr.id, pr.name
      ) y
    ), '[]'::jsonb)
  );
$$;

grant execute on function public.work_report(date, date, text) to authenticated;

-- =========================================================================
-- 20261017000044_project_milestones.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Milestones.
--
-- A project is a run of dates somebody has promised — "contract signed by
-- the 4th", "fit-out finished by the end of the month" — with the work for
-- each gathered under it. A milestone is one of those dates; a task can sit
-- under one milestone of its own project. Whoever can see the project sees
-- its milestones. Admins and managers set them, mark them reached, and put
-- tasks under them, the same as they set due dates.
--
-- `done_at` is set by hand: some milestones are a single event with no task
-- under them, and "every task is done" is not always "we got there".
--
-- Run in the Supabase SQL editor after 43. Safe to run more than once.
-- ---------------------------------------------------------------------------

create table if not exists public.project_milestones (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects (id) on delete cascade,
  title       text not null,
  due_on      date not null,
  done_at     timestamptz,
  created_by  uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint project_milestones_title_length check (length(btrim(title)) between 1 and 120)
);

create index if not exists project_milestones_project_idx
  on public.project_milestones (project_id, due_on);

comment on table public.project_milestones is
  'A date a project has promised, with the tasks for it gathered under it.';

alter table public.project_milestones enable row level security;
alter table public.project_milestones force row level security;

drop policy if exists "milestones are readable with the project" on public.project_milestones;
create policy "milestones are readable with the project"
  on public.project_milestones for select to authenticated
  using (public.can_view_project(project_id));

drop policy if exists "planners add milestones" on public.project_milestones;
create policy "planners add milestones"
  on public.project_milestones for insert to authenticated
  with check (public.is_manager_or_admin() and public.can_view_project(project_id));

drop policy if exists "planners change milestones" on public.project_milestones;
create policy "planners change milestones"
  on public.project_milestones for update to authenticated
  using (public.is_manager_or_admin() and public.can_view_project(project_id))
  with check (public.is_manager_or_admin() and public.can_view_project(project_id));

drop policy if exists "planners remove milestones" on public.project_milestones;
create policy "planners remove milestones"
  on public.project_milestones for delete to authenticated
  using (public.is_manager_or_admin() and public.can_view_project(project_id));

grant select, insert, update, delete on public.project_milestones to authenticated;
grant all on public.project_milestones to service_role;

drop trigger if exists project_milestones_set_updated_at on public.project_milestones;
create trigger project_milestones_set_updated_at
  before update on public.project_milestones
  for each row execute function public.set_updated_at();

-- A milestone never moves to another project: its tasks would go with it in
-- name only.
create or replace function public.keep_milestone_in_project()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.project_id is distinct from old.project_id then
    raise exception 'A milestone stays in its project.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists project_milestones_keep_project on public.project_milestones;
create trigger project_milestones_keep_project
  before update on public.project_milestones
  for each row execute function public.keep_milestone_in_project();

-- ---------------------------------------------------------------------------
-- A task under a milestone
--
-- Deleting the milestone leaves its tasks where they are, under none.
-- ---------------------------------------------------------------------------

alter table public.tasks
  add column if not exists milestone_id uuid
    references public.project_milestones (id) on delete set null;

create index if not exists tasks_milestone_idx
  on public.tasks (milestone_id)
  where milestone_id is not null;

comment on column public.tasks.milestone_id is
  'The milestone of the task''s own project it counts towards, or null.';

-- Only a milestone of the task's own project. A task moved to another
-- project, or out of every project, leaves its old milestone behind rather
-- than refusing to move: the move is the thing being asked for.
create or replace function public.check_task_milestone()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.milestone_id is null then
    return new;
  end if;

  if exists (
    select 1 from public.project_milestones m
    where m.id = new.milestone_id and m.project_id = new.project_id
  ) then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and new.project_id is distinct from old.project_id
     and new.milestone_id is not distinct from old.milestone_id
  then
    new.milestone_id := null;
    return new;
  end if;

  raise exception 'That milestone belongs to another project.'
    using errcode = 'check_violation';
end;
$$;

drop trigger if exists tasks_check_milestone on public.tasks;
create trigger tasks_check_milestone
  before insert or update of milestone_id, project_id on public.tasks
  for each row execute function public.check_task_milestone();

-- Which milestone a task counts towards is planning, like its due date.
create or replace function public.enforce_task_field_permissions()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if public.is_manager_or_admin() then
    return new;
  end if;

  if new.title is distinct from old.title
     or new.description is distinct from old.description
     or new.priority is distinct from old.priority
     or new.due_at is distinct from old.due_at
     or new.project_id is distinct from old.project_id
     or new.follow_up_at is distinct from old.follow_up_at
     or new.follow_up_note is distinct from old.follow_up_note
     or new.milestone_id is distinct from old.milestone_id
  then
    raise exception 'Only a manager or admin can change task details. You can update the status and add comments or files.'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

notify pgrst, 'reload schema';

-- =========================================================================
-- 20261017000045_admin_alerts.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- Telling the admins when something goes wrong.
--
-- Faults were recorded (migration 28) and reminders that could not be
-- delivered were flagged (migration 27), but both waited for an admin to
-- open their profile and look. The scheduled run now sends each admin who
-- has linked Telegram a short note when there is something new: how many
-- faults, on which pages, and how many reminders could not be delivered —
-- with a link to the full list in the portal.
--
-- The note carries counts and page paths, never a fault's own text: that
-- can hold a fragment of whatever it failed on, and stays in the portal.
--
-- Everything here is for the service key only. Nobody signed in can read
-- the log, add to it, or ask for the digest; the run that sends the note is
-- the only caller.
--
-- Run in the Supabase SQL editor after 44. Safe to run more than once.
-- ---------------------------------------------------------------------------

create table if not exists public.admin_alerts (
  id        uuid primary key default gen_random_uuid(),
  sent_at   timestamptz not null default now(),
  faults    integer not null default 0 check (faults >= 0),
  failures  integer not null default 0 check (failures >= 0),
  -- How many admins it reached.
  reached   integer not null default 0 check (reached >= 0)
);

create index if not exists admin_alerts_sent_idx on public.admin_alerts (sent_at desc);

comment on table public.admin_alerts is
  'When the admins were last told about faults and failed reminders. Service key only.';

alter table public.admin_alerts enable row level security;
alter table public.admin_alerts force row level security;
-- No policies: nobody signed in reads or writes it.
revoke all on public.admin_alerts from anon, authenticated;
grant all on public.admin_alerts to service_role;

-- ---------------------------------------------------------------------------
-- What is new since the last note
--
-- Since the last note sent, or the last day for the first one, so a new
-- install does not open with a fortnight of history. Pages are grouped
-- without their query strings, busiest first, five at most.
-- ---------------------------------------------------------------------------

create or replace function public.admin_alert_digest(as_of timestamptz default now())
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with since as (
    select coalesce(
      (select max(sent_at) from public.admin_alerts where sent_at <= as_of),
      as_of - interval '24 hours'
    ) as at
  ),
  faults as (
    select e.source, coalesce(nullif(split_part(e.route, '?', 1), ''), '/') as page
      from public.app_errors e, since
     where e.occurred_at > since.at and e.occurred_at <= as_of
  ),
  pages as (
    select source, page, count(*)::int as n
      from faults
     group by source, page
     order by count(*) desc, page
     limit 5
  )
  select jsonb_build_object(
    'since', (select at from since),
    'faults', (select count(*)::int from faults),
    'pages', coalesce(
      (select jsonb_agg(jsonb_build_object('source', source, 'page', page, 'count', n)
                        order by n desc, page) from pages),
      '[]'::jsonb),
    'failedReminders', (
      select count(*)::int from public.reminder_queue q, since
       where q.status = 'failed' and q.failed_at > since.at and q.failed_at <= as_of
    ),
    'recipients', coalesce(
      (select jsonb_agg(np.telegram_chat_id order by p.created_at)
         from public.profiles p
         join public.notification_preferences np on np.user_id = p.id
        where p.role = 'admin'
          and np.telegram_enabled
          and np.telegram_chat_id is not null),
      '[]'::jsonb)
  );
$$;

revoke all on function public.admin_alert_digest(timestamptz) from public, anon, authenticated;
grant execute on function public.admin_alert_digest(timestamptz) to service_role;

comment on function public.admin_alert_digest(timestamptz) is
  'Faults and failed reminders since the admins were last told, and which Telegram chats to tell. Service key only.';

-- =========================================================================
-- 20261017000046_portal_health.sql
-- =========================================================================

-- ---------------------------------------------------------------------------
-- A health check the outside world may ask.
--
-- /api/health asks this, for an uptime monitor: is the database answering,
-- and how far have the migrations been run? The second matters here more
-- than most places — Vercel deploys the code the moment it is pushed, and
-- the migrations are pasted into the SQL editor by hand afterwards, so "the
-- database is behind the code" is the commonest way for this app to be half
-- broken.
--
-- `schema` is the newest migration whose objects exist, found by looking for
-- one thing each migration made, so it reads true even when migrations were
-- run out of order. It names table and function names and nothing else: no
-- rows, no counts, nothing about anybody. Callable without signing in.
--
-- Run in the Supabase SQL editor after 45. Safe to run more than once.
-- ---------------------------------------------------------------------------

create or replace function public.portal_health()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with markers (migration, present) as (
    values
      (35, to_regprocedure('public.attachment_task_id(text)') is not null),
      (36, to_regclass('public.company_holidays') is not null),
      (37, to_regprocedure('public.enqueue_morning_summaries(timestamptz)') is not null),
      (38, to_regprocedure('public.second_step_pending()') is not null),
      (39, to_regclass('public.labels') is not null),
      (40, to_regclass('public.task_dependencies') is not null),
      (41, to_regclass('public.task_templates') is not null),
      (42, to_regprocedure('public.add_from_chat(text, text, text, public.task_priority, timestamptz)') is not null),
      (43, to_regprocedure('public.work_report(date, date, text)') is not null),
      (44, to_regclass('public.project_milestones') is not null),
      (45, to_regclass('public.admin_alerts') is not null),
      (46, true)
  )
  select jsonb_build_object(
    'database', 'ok',
    'time', now(),
    'schema', (select max(migration) from markers where present),
    -- Anything older than the newest present is missing: run out of order.
    'missing', coalesce(
      (select jsonb_agg(migration order by migration) from markers
        where not present
          and migration < (select max(migration) from markers where present)),
      '[]'::jsonb)
  );
$$;

grant execute on function public.portal_health() to anon, authenticated, service_role;

comment on function public.portal_health() is
  'For /api/health: the database answers, and which migrations have been run. Names only, nothing about anybody.';
