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
