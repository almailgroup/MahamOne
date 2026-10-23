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
