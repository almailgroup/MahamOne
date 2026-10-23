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
