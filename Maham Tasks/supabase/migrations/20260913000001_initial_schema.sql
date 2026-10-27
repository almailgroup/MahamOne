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
