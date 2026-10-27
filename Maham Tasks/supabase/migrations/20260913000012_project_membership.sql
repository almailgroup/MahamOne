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
