-- ---------------------------------------------------------------------------
-- Notifications
--
-- Written by database triggers rather than application code, so an event
-- cannot be missed because some path forgot to raise it. Each row is private
-- to its recipient.
-- ---------------------------------------------------------------------------

create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  actor_id   uuid references public.profiles (id) on delete set null,
  type       text not null,
  title      text not null,
  body       text,
  task_id    uuid references public.tasks (id) on delete cascade,
  project_id uuid references public.projects (id) on delete cascade,
  read_at    timestamptz,
  created_at timestamptz not null default now(),

  constraint notifications_type_known check (
    type in (
      'task_assigned',
      'task_unassigned',
      'task_commented',
      'task_mentioned',
      'task_review_requested',
      'task_completed'
    )
  )
);

-- Drives the unread badge and the newest-first list.
create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);
create index if not exists notifications_user_unread_idx
  on public.notifications (user_id)
  where read_at is null;

alter table public.notifications enable row level security;
alter table public.notifications force row level security;

-- Strictly private: unlike the rest of this schema, a notification is visible
-- only to its recipient.
drop policy if exists "users read their own notifications" on public.notifications;
create policy "users read their own notifications"
  on public.notifications for select
  to authenticated
  using (user_id = auth.uid());

-- Recipients may only mark as read; the content is written by triggers.
drop policy if exists "users update their own notifications" on public.notifications;
create policy "users update their own notifications"
  on public.notifications for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "users delete their own notifications" on public.notifications;
create policy "users delete their own notifications"
  on public.notifications for delete
  to authenticated
  using (user_id = auth.uid());

-- No INSERT policy or grant: rows come only from the SECURITY DEFINER triggers
-- below, so nobody can forge a notification to another user.
grant select, update, delete on public.notifications to authenticated;

-- --------------------------------------------------------------------------
-- Helper
-- --------------------------------------------------------------------------

create or replace function public.push_notification(
  recipient uuid,
  actor uuid,
  kind text,
  heading text,
  detail text,
  task uuid,
  project uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Never notify someone about their own action, and never about a missing user.
  if recipient is null or recipient = coalesce(actor, '00000000-0000-0000-0000-000000000000'::uuid) then
    return;
  end if;

  insert into public.notifications (user_id, actor_id, type, title, body, task_id, project_id)
  values (recipient, actor, kind, heading, detail, task, project);
end;
$$;

-- --------------------------------------------------------------------------
-- Assignment
-- --------------------------------------------------------------------------

create or replace function public.notify_assignment()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t public.tasks%rowtype;
begin
  if tg_op = 'INSERT' then
    select * into t from public.tasks where id = new.task_id;
    perform public.push_notification(
      new.user_id, auth.uid(), 'task_assigned',
      'You were assigned a task', t.title, t.id, t.project_id
    );
  else
    select * into t from public.tasks where id = old.task_id;
    -- The task may already be gone when the assignment cascades away.
    if found then
      perform public.push_notification(
        old.user_id, auth.uid(), 'task_unassigned',
        'You were removed from a task', t.title, t.id, t.project_id
      );
    end if;
  end if;

  return null;
end;
$$;

drop trigger if exists task_assignments_notify_insert on public.task_assignments;
create trigger task_assignments_notify_insert
  after insert on public.task_assignments
  for each row execute function public.notify_assignment();

drop trigger if exists task_assignments_notify_delete on public.task_assignments;
create trigger task_assignments_notify_delete
  after delete on public.task_assignments
  for each row execute function public.notify_assignment();

-- --------------------------------------------------------------------------
-- Status changes
--
-- Reaching 'in_review' tells whoever has to review it. Reaching 'done' tells
-- the people who worked on it.
-- --------------------------------------------------------------------------

create or replace function public.notify_status_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor uuid := auth.uid();
  recipient uuid;
begin
  if new.status is not distinct from old.status then
    return null;
  end if;

  if new.status = 'in_review' then
    -- The task's creator reviews it; for general tasks with no creator left,
    -- fall back to every manager and admin.
    if new.created_by is not null then
      perform public.push_notification(
        new.created_by, actor, 'task_review_requested',
        'A task is ready for review', new.title, new.id, new.project_id
      );
    else
      for recipient in
        select id from public.profiles where role in ('admin', 'manager')
      loop
        perform public.push_notification(
          recipient, actor, 'task_review_requested',
          'A task is ready for review', new.title, new.id, new.project_id
        );
      end loop;
    end if;

  elsif new.status = 'done' then
    for recipient in
      select user_id from public.task_assignments where task_id = new.id
      union
      select new.created_by where new.created_by is not null
    loop
      perform public.push_notification(
        recipient, actor, 'task_completed',
        'A task was marked done', new.title, new.id, new.project_id
      );
    end loop;
  end if;

  return null;
end;
$$;

drop trigger if exists tasks_notify_status_change on public.tasks;
create trigger tasks_notify_status_change
  after update on public.tasks
  for each row execute function public.notify_status_change();

-- --------------------------------------------------------------------------
-- Comments and @mentions
--
-- Mentions are matched against profile names here so that a comment written
-- from anywhere — the app, the SQL editor, a future integration — still
-- notifies the people it names.
-- --------------------------------------------------------------------------

create or replace function public.notify_comment()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t public.tasks%rowtype;
  recipient uuid;
  mentioned uuid[];
begin
  select * into t from public.tasks where id = new.task_id;
  if not found then
    return null;
  end if;

  -- Anyone named with @Full Name, or @local-part of their email.
  select coalesce(array_agg(p.id), '{}')
    into mentioned
  from public.profiles p
  where p.id <> coalesce(new.user_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and (
      (p.full_name is not null and new.content ilike '%@' || p.full_name || '%')
      or new.content ilike '%@' || split_part(p.email, '@', 1) || '%'
    );

  foreach recipient in array mentioned loop
    perform public.push_notification(
      recipient, new.user_id, 'task_mentioned',
      'You were mentioned in a comment', left(new.content, 140), t.id, t.project_id
    );
  end loop;

  -- Everyone else with a stake in the task: its assignees and its creator.
  for recipient in
    select a.user_id from public.task_assignments a where a.task_id = t.id
    union
    select t.created_by where t.created_by is not null
  loop
    if not (recipient = any(mentioned)) then
      perform public.push_notification(
        recipient, new.user_id, 'task_commented',
        'New comment on a task', left(new.content, 140), t.id, t.project_id
      );
    end if;
  end loop;

  return null;
end;
$$;

drop trigger if exists comments_notify on public.comments;
create trigger comments_notify
  after insert on public.comments
  for each row execute function public.notify_comment();

-- --------------------------------------------------------------------------
-- Realtime — the bell updates without a refresh.
-- --------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'publication supabase_realtime not found - skipping';
    return;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
