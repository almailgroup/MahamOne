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
