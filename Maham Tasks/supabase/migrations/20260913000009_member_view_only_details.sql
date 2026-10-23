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
