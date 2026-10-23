-- ---------------------------------------------------------------------------
-- Recurring tasks
--
-- The portal could describe work that happens once. Everything that happens
-- every month — the freight reconciliation, the licence renewal, the board
-- pack — was retyped each time, which is both a chore and a way to forget.
--
-- The model is deliberately the simplest one that is honest: a task carries
-- its own repeat rule, and closing it opens the next one. There is no series,
-- no parent row, no calendar of future instances. That means:
--
--   * exactly one open instance of a repeating task exists at any moment, so
--     the board never fills with copies of the same thing;
--   * the history is the closed instances themselves, each with its own
--     comments and activity;
--   * changing the rule changes it from the next occurrence on, which is what
--     somebody editing a task in front of them expects.
--
-- What it cannot express is "the first Monday of the month" or "weekdays
-- only". Those want a real calendar rule and a generator, and neither is
-- worth its weight until somebody asks.
-- ---------------------------------------------------------------------------

alter table public.tasks
  add column if not exists repeat_every text,
  add column if not exists repeat_interval integer not null default 1;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'tasks_repeat_every_check'
  ) then
    alter table public.tasks
      add constraint tasks_repeat_every_check
      check (repeat_every is null or repeat_every in ('day', 'week', 'month', 'year'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'tasks_repeat_interval_check'
  ) then
    alter table public.tasks
      add constraint tasks_repeat_interval_check
      check (repeat_interval between 1 and 365);
  end if;

  -- A repeat with no due date has nothing to advance, so it is not a repeat.
  if not exists (
    select 1 from pg_constraint where conname = 'tasks_repeat_needs_due_check'
  ) then
    alter table public.tasks
      add constraint tasks_repeat_needs_due_check
      check (repeat_every is null or due_at is not null);
  end if;
end $$;

comment on column public.tasks.repeat_every is
  'Unit of the repeat rule: day, week, month or year. Null means the task happens once.';
comment on column public.tasks.repeat_interval is
  'How many of those units between occurrences. 2 with repeat_every = week is fortnightly.';

-- ---------------------------------------------------------------------------
-- Closing one opens the next
--
-- `security definer` because the row is written on behalf of whoever closed
-- the task, and the next occurrence belongs to the same person who owned the
-- last one rather than to them. It writes one row, shaped from a row the
-- caller has just proved they can update, so it hands out nothing that was
-- not already theirs.
--
-- The due date is advanced until it is in the future: a monthly task closed
-- three months late should next be due next month, not produce something that
-- is already overdue.
-- ---------------------------------------------------------------------------

create or replace function public.spawn_next_occurrence()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  step     interval;
  next_due timestamptz;
  copy_id  uuid;
begin
  if new.repeat_every is null or new.due_at is null then
    return new;
  end if;

  -- Only the move into done, and only once: an update that leaves a closed
  -- task closed must not open a second copy.
  if new.status <> 'done' or old.status = 'done' then
    return new;
  end if;

  step := (new.repeat_interval || ' ' || new.repeat_every)::interval;
  next_due := new.due_at + step;

  -- Bounded: a daily task abandoned for years would otherwise loop here.
  for i in 1..500 loop
    exit when next_due > now();
    next_due := next_due + step;
  end loop;

  insert into public.tasks (
    project_id, title, description, status, priority,
    due_at, position, created_by, repeat_every, repeat_interval
  )
  values (
    new.project_id, new.title, new.description, 'todo', new.priority,
    next_due, new.position, new.created_by, new.repeat_every, new.repeat_interval
  )
  returning id into copy_id;

  -- The same people, on the same job.
  insert into public.task_assignments (task_id, user_id)
  select copy_id, user_id
    from public.task_assignments
   where task_id = new.id;

  -- The rule travels with the occurrence that is still open, so the closed
  -- one reads as what it is: a thing that was done on a date.
  update public.tasks
     set repeat_every = null
   where id = new.id;

  return new;
end;
$fn$;

comment on function public.spawn_next_occurrence() is
  'Opens the next occurrence of a repeating task when one is closed, and moves the rule onto it.';

drop trigger if exists tasks_spawn_next_occurrence on public.tasks;

create trigger tasks_spawn_next_occurrence
  after update of status on public.tasks
  for each row
  execute function public.spawn_next_occurrence();
