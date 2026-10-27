-- ---------------------------------------------------------------------------
-- Waiting on.
--
-- "Pay the deposit" cannot start until "Get the quote approved" is done. A
-- task can say which others it waits on; lists then show it as waiting
-- while any of them is open, and when the last one is finished, whoever is
-- on the waiting task is told it can go ahead.
--
-- Planners — admins and managers — link tasks, as they plan the rest. A link
-- is seen with the task that waits, and only made between tasks the planner
-- can see. A task cannot end up waiting on itself, however far round.
--
-- Run in the Supabase SQL editor after 39. Safe to run more than once.
-- ---------------------------------------------------------------------------

create table if not exists public.task_dependencies (
  task_id    uuid not null references public.tasks (id) on delete cascade,
  blocked_by uuid not null references public.tasks (id) on delete cascade,
  created_by uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (task_id, blocked_by),
  constraint task_dependencies_not_itself check (task_id <> blocked_by)
);

create index if not exists task_dependencies_blocked_by_idx
  on public.task_dependencies (blocked_by);

comment on table public.task_dependencies is
  'Task task_id cannot start until task blocked_by is done.';

alter table public.task_dependencies enable row level security;
alter table public.task_dependencies force row level security;

drop policy if exists "see what a task you can see waits on" on public.task_dependencies;
create policy "see what a task you can see waits on"
  on public.task_dependencies for select to authenticated
  using (public.can_view_task(task_id));

drop policy if exists "planners link tasks they can see" on public.task_dependencies;
create policy "planners link tasks they can see"
  on public.task_dependencies for insert to authenticated
  with check (
    public.is_manager_or_admin()
    and public.can_view_task(task_id)
    and public.can_view_task(blocked_by)
  );

drop policy if exists "planners unlink tasks" on public.task_dependencies;
create policy "planners unlink tasks"
  on public.task_dependencies for delete to authenticated
  using (public.is_manager_or_admin() and public.can_view_task(task_id));

grant select, insert, delete on public.task_dependencies to authenticated;
grant all on public.task_dependencies to service_role;

-- ---------------------------------------------------------------------------
-- No circles: A waits on B waits on C waits on A would wait forever.
-- Definer, so the whole chain is followed, not only the part this caller sees.
-- ---------------------------------------------------------------------------

create or replace function public.guard_task_dependency_cycle()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if exists (
    with recursive chain (id) as (
      select d.blocked_by from public.task_dependencies d where d.task_id = new.blocked_by
      union
      select d.blocked_by from public.task_dependencies d join chain c on d.task_id = c.id
    )
    select 1 from chain where id = new.task_id
  ) then
    raise exception 'task.dependencyCycle' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists task_dependencies_no_cycle on public.task_dependencies;
create trigger task_dependencies_no_cycle
  before insert on public.task_dependencies
  for each row execute function public.guard_task_dependency_cycle();

-- ---------------------------------------------------------------------------
-- How many open tasks this one waits on, as a column every task list can ask
-- for (`select=*,waiting_on`). Invoker, so it counts only what the caller can
-- see; a binned task is not waited on.
-- ---------------------------------------------------------------------------

create or replace function public.waiting_on(t public.tasks)
returns integer
language sql
stable
set search_path = public, pg_temp
as $$
  select count(*)::integer
    from public.task_dependencies d
    join public.tasks b on b.id = d.blocked_by
   where d.task_id = t.id
     and b.status <> 'done'
     and b.deleted_at is null;
$$;

grant execute on function public.waiting_on(public.tasks) to authenticated;

-- ---------------------------------------------------------------------------
-- Ready to go: when a task is finished, the people on each task that was
-- waiting only on it are told.
-- ---------------------------------------------------------------------------

alter table public.notifications drop constraint if exists notifications_type_known;
alter table public.notifications add constraint notifications_type_known check (
  type in (
    'task_assigned',
    'task_unassigned',
    'task_commented',
    'task_mentioned',
    'task_review_requested',
    'task_completed',
    'direct_message',
    'reminder_failed',
    'task_unblocked'
  )
);

create or replace function public.notify_unblocked()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  waiting record;
  person uuid;
begin
  if new.status <> 'done' or old.status = 'done' then
    return new;
  end if;

  for waiting in
    select w.id, w.title, w.project_id
      from public.task_dependencies d
      join public.tasks w on w.id = d.task_id
     where d.blocked_by = new.id
       and w.status <> 'done'
       and w.deleted_at is null
       -- Nothing else it waits on is still open.
       and not exists (
         select 1
           from public.task_dependencies other
           join public.tasks b on b.id = other.blocked_by
          where other.task_id = w.id
            and other.blocked_by <> new.id
            and b.status <> 'done'
            and b.deleted_at is null
       )
  loop
    for person in
      select a.user_id from public.task_assignments a where a.task_id = waiting.id
    loop
      perform public.push_notification(
        person,
        auth.uid(),
        'task_unblocked',
        'Ready to go: ' || waiting.title,
        new.title || ' is done.',
        waiting.id,
        waiting.project_id
      );
    end loop;
  end loop;

  return new;
end;
$$;

drop trigger if exists tasks_notify_unblocked on public.tasks;
create trigger tasks_notify_unblocked
  after update of status on public.tasks
  for each row execute function public.notify_unblocked();
