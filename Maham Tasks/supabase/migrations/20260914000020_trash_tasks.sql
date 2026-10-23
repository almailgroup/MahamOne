-- ---------------------------------------------------------------------------
-- Deleting a task puts it in the bin
--
-- Until now a delete was final, which is why every delete sat behind a
-- confirmation dialog: the only defence against "I deleted the wrong one"
-- was a question nobody reads. A deleted task is now hidden from every read
-- at once and kept for thirty days. Restoring it brings back everything that
-- was on it — comments, files, history, assignees — because none of that
-- went anywhere.
--
-- Hiding is done in the read policy, not in queries. Every list, count,
-- search and realtime event goes through that policy, so there is no query
-- to forget. The two things that read tasks without it — reminders and the
-- purge — are handled here by name.
--
-- Who may bin or restore is exactly who could delete: managers and admins.
-- ---------------------------------------------------------------------------

alter table public.tasks add column if not exists deleted_at timestamptz;

comment on column public.tasks.deleted_at is
  'Set when trashed; cleared on restore. The read policy hides the row while it is set.';

create index if not exists tasks_deleted_idx
  on public.tasks (deleted_at)
  where deleted_at is not null;

-- --------------------------------------------------------------------------
-- The read policy from migration 0015, with the bin excluded
-- --------------------------------------------------------------------------

drop policy if exists "tasks are readable when assigned or managed" on public.tasks;
create policy "tasks are readable when assigned or managed"
  on public.tasks for select
  to authenticated
  using (
    deleted_at is null
    and (
      exists (
        select 1 from public.task_assignments a
        where a.task_id = tasks.id and a.user_id = auth.uid()
      )
      or (
        public.is_manager_or_admin()
        and (project_id is null or public.can_view_project(project_id))
      )
    )
  );

-- --------------------------------------------------------------------------
-- Two more things the history can say
-- --------------------------------------------------------------------------

alter table public.task_activity
  drop constraint if exists task_activity_action_known;
alter table public.task_activity
  add constraint task_activity_action_known check (
    action in (
      'created',
      'updated',
      'status_changed',
      'priority_changed',
      'due_date_changed',
      'follow_up_set',
      'follow_up_cleared',
      'assignee_added',
      'assignee_removed',
      'commented',
      'deleted',
      'restored'
    )
  );

-- --------------------------------------------------------------------------
-- Bin, restore, purge
--
-- SECURITY DEFINER because the row being restored is, by definition, one the
-- caller cannot currently read. The permission check is the delete policy's,
-- written out: a manager or admin, on a task they could see if it were not
-- in the bin.
-- --------------------------------------------------------------------------

create or replace function public.trash_task(task uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target public.tasks%rowtype;
begin
  select * into target from public.tasks where id = task;
  if not found or target.deleted_at is not null then
    return false;
  end if;

  if not public.is_manager_or_admin() then
    return false;
  end if;
  if target.project_id is not null and not public.can_view_project(target.project_id) then
    return false;
  end if;

  update public.tasks set deleted_at = now() where id = task;

  -- Nothing should nag about a task that is in the bin.
  update public.reminder_queue
     set status = 'cancelled'
   where task_id = task and status = 'pending';

  insert into public.task_activity (task_id, actor_id, action)
  values (task, auth.uid(), 'deleted');

  return true;
end;
$$;

create or replace function public.restore_task(task uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target public.tasks%rowtype;
begin
  select * into target from public.tasks where id = task;
  if not found or target.deleted_at is null then
    return false;
  end if;

  if not public.is_manager_or_admin() then
    return false;
  end if;
  if target.project_id is not null and not public.can_view_project(target.project_id) then
    return false;
  end if;

  update public.tasks set deleted_at = null where id = task;

  insert into public.task_activity (task_id, actor_id, action)
  values (task, auth.uid(), 'restored');

  return true;
end;
$$;

-- Run by the daily dispatcher with the service key. Deliberately not granted
-- to authenticated: purging is housekeeping, not a user action.
create or replace function public.purge_trashed_tasks(older_than interval default '30 days')
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  removed integer;
begin
  delete from public.tasks
   where deleted_at is not null
     and deleted_at < now() - older_than;
  get diagnostics removed = row_count;
  return removed;
end;
$$;

grant execute on function public.trash_task(uuid) to authenticated;
grant execute on function public.restore_task(uuid) to authenticated;
revoke execute on function public.purge_trashed_tasks(interval) from authenticated, anon;

-- --------------------------------------------------------------------------
-- Reminders skip the bin
--
-- enqueue_task_reminders is SECURITY DEFINER and scans tasks directly, so the
-- read policy does not protect it. This is migration 0014's function with one
-- condition added to each of its three candidate sets, generated from that
-- file rather than retyped so the two cannot drift.
-- --------------------------------------------------------------------------

create or replace function public.enqueue_task_reminders()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  inserted integer := 0;
begin
  -- Work that is due within the recipient's chosen lead time.
  with candidates as (
    select
      t.id as task_id, t.title, t.due_at,
      a.user_id,
      p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled,
      np.telegram_chat_id, np.whatsapp_number, np.due_soon_lead_hours
    from public.tasks t
    join public.task_assignments a on a.task_id = t.id
    join public.profiles p on p.id = a.user_id
    join public.notification_preferences np on np.user_id = a.user_id
    where t.status <> 'done'
      and t.deleted_at is null
      and t.due_at is not null
      and np.remind_due_soon
      and t.due_at > now()
      and t.due_at <= now() + make_interval(hours => np.due_soon_lead_hours)
  )
  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    c.user_id, c.task_id, ch.channel, 'due_soon',
    case ch.channel
      when 'email' then c.email
      when 'telegram' then c.telegram_chat_id
      else c.whatsapp_number
    end,
    'Due soon: ' || c.title,
    c.title || ' is due ' || to_char(c.due_at at time zone 'UTC', 'DD Mon HH24:MI') || ' UTC.',
    'due_soon:' || c.task_id || ':' || c.user_id || ':' || ch.channel || ':' || extract(epoch from c.due_at)::bigint
  from candidates c
  cross join lateral (
    select 'email'::text as channel where c.email_enabled
    union all select 'telegram' where c.telegram_enabled and c.telegram_chat_id is not null
    union all select 'whatsapp' where c.whatsapp_enabled and c.whatsapp_number is not null
  ) ch
  on conflict (dedupe_key) do nothing;

  get diagnostics inserted = row_count;

  -- Work that is already late. Keyed by the day so a task that stays overdue
  -- nags once a day rather than on every scheduler run.
  with candidates as (
    select
      t.id as task_id, t.title, t.due_at,
      a.user_id, p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled,
      np.telegram_chat_id, np.whatsapp_number, np.due_soon_lead_hours
    from public.tasks t
    join public.task_assignments a on a.task_id = t.id
    join public.profiles p on p.id = a.user_id
    join public.notification_preferences np on np.user_id = a.user_id
    where t.status <> 'done'
      and t.deleted_at is null
      and t.due_at is not null
      and t.due_at < now()
      and np.remind_overdue
  )
  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    c.user_id, c.task_id, ch.channel, 'overdue',
    case ch.channel
      when 'email' then c.email
      when 'telegram' then c.telegram_chat_id
      else c.whatsapp_number
    end,
    'Overdue: ' || c.title,
    c.title || ' was due ' || to_char(c.due_at at time zone 'UTC', 'DD Mon HH24:MI') || ' UTC and is still open.',
    'overdue:' || c.task_id || ':' || c.user_id || ':' || ch.channel || ':' || to_char(now(), 'YYYY-MM-DD')
  from candidates c
  cross join lateral (
    select 'email'::text as channel where c.email_enabled
    union all select 'telegram' where c.telegram_enabled and c.telegram_chat_id is not null
    union all select 'whatsapp' where c.whatsapp_enabled and c.whatsapp_number is not null
  ) ch
  on conflict (dedupe_key) do nothing;

  -- Follow-ups that have come due, to whoever has to chase them.
  with candidates as (
    select
      t.id as task_id, t.title, t.follow_up_at, t.follow_up_note,
      a.user_id, p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled,
      np.telegram_chat_id, np.whatsapp_number, np.due_soon_lead_hours
    from public.tasks t
    join public.task_assignments a on a.task_id = t.id
    join public.profiles p on p.id = a.user_id
    join public.notification_preferences np on np.user_id = a.user_id
    where t.status <> 'done'
      and t.deleted_at is null
      and t.follow_up_at is not null
      and t.follow_up_at <= now()
      and np.remind_follow_up
  )
  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    c.user_id, c.task_id, ch.channel, 'follow_up',
    case ch.channel
      when 'email' then c.email
      when 'telegram' then c.telegram_chat_id
      else c.whatsapp_number
    end,
    'Follow up: ' || c.title,
    coalesce(c.follow_up_note, 'Time to follow up on ' || c.title) || ' (' || c.title || ')',
    'follow_up:' || c.task_id || ':' || c.user_id || ':' || ch.channel || ':' || extract(epoch from c.follow_up_at)::bigint
  from candidates c
  cross join lateral (
    select 'email'::text as channel where c.email_enabled
    union all select 'telegram' where c.telegram_enabled and c.telegram_chat_id is not null
    union all select 'whatsapp' where c.whatsapp_enabled and c.whatsapp_number is not null
  ) ch
  on conflict (dedupe_key) do nothing;

  return inserted;
end;
$$;
