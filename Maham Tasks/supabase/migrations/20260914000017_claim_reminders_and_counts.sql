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
