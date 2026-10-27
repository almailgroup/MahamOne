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
