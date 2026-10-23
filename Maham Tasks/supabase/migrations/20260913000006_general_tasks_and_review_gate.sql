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
