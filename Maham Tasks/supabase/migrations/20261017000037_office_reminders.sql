-- ---------------------------------------------------------------------------
-- Reminders on office time, and a morning summary.
--
-- Three things.
--
-- 1. Times in reminders are Kuwait's, not UTC's. "Due 17 Oct 09:00 UTC" was
--    noon in the office and nobody's arithmetic should be needed to read a
--    reminder. company_time_zone() names the zone once; Kuwait keeps no
--    summer time, so the same hour all year. An overdue task still nags once
--    a day — the office's day now, not Greenwich's.
--
-- 2. A morning summary, for whoever turns it on in Profile: one message
--    with what is overdue, due today and to follow up, instead of (or as well
--    as) one message per task. Sent once a day on the channels the person
--    already uses; people with nothing to do that day are not messaged.
--
-- 3. The functions that fill the queue are for the dispatcher, which runs
--    with the service key — not for anybody signed in. They were callable
--    by any session; harmless, as they only queue what is due anyway, but
--    nothing in the app needs it, so it is closed.
--
-- When the dispatcher runs at all — 08:00 Kuwait, working days only, never on
-- a Friday, Saturday or company holiday — is decided in the app
-- (src/lib/work-week.ts), so the rule lives in one place.
--
-- Run in the Supabase SQL editor after 36. Safe to run more than once.
-- ---------------------------------------------------------------------------

create or replace function public.company_time_zone()
returns text
language sql
immutable
as $$ select 'Asia/Kuwait' $$;

comment on function public.company_time_zone() is
  'The office''s time zone, for anything written in words: reminder times, which day it is.';

-- ---------------------------------------------------------------------------
-- 1. Office time in the messages
--
-- Repeated whole from 26, with only the time formats and the overdue day
-- changed: a plpgsql body cannot be patched in place.
-- ---------------------------------------------------------------------------

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
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled, np.push_enabled,
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
    ch.recipient,
    'Due soon: ' || c.title,
    c.title || ' is due ' || to_char(c.due_at at time zone public.company_time_zone(), 'Dy DD Mon, HH24:MI') || '.',
    'due_soon:' || c.task_id || ':' || c.user_id || ':' || ch.channel || case when ch.channel = 'push' then ':' || ch.recipient else '' end || ':' || extract(epoch from c.due_at)::bigint
  from candidates c
  cross join lateral (
    select 'email'::text as channel, c.email as recipient
     where c.email_enabled
    union all
    select 'telegram', c.telegram_chat_id
     where c.telegram_enabled and c.telegram_chat_id is not null
    union all
    select 'whatsapp', c.whatsapp_number
     where c.whatsapp_enabled and c.whatsapp_number is not null
    union all
    -- One row per device, so somebody with a phone and a laptop is told on
    -- both. The others have exactly one address each, which is why they were
    -- a plain case expression until now.
    select 'push', s.endpoint
      from public.push_subscriptions s
     where c.push_enabled and s.user_id = c.user_id
  ) ch
  on conflict (dedupe_key) do nothing;

  get diagnostics inserted = row_count;

  -- Work that is already late. Keyed by the day so a task that stays overdue
  -- nags once a day rather than on every scheduler run.
  with candidates as (
    select
      t.id as task_id, t.title, t.due_at,
      a.user_id, p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled, np.push_enabled,
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
    ch.recipient,
    'Overdue: ' || c.title,
    c.title || ' was due ' || to_char(c.due_at at time zone public.company_time_zone(), 'Dy DD Mon, HH24:MI') || ' and is still open.',
    'overdue:' || c.task_id || ':' || c.user_id || ':' || ch.channel || case when ch.channel = 'push' then ':' || ch.recipient else '' end || ':' || to_char(now() at time zone public.company_time_zone(), 'YYYY-MM-DD')
  from candidates c
  cross join lateral (
    select 'email'::text as channel, c.email as recipient
     where c.email_enabled
    union all
    select 'telegram', c.telegram_chat_id
     where c.telegram_enabled and c.telegram_chat_id is not null
    union all
    select 'whatsapp', c.whatsapp_number
     where c.whatsapp_enabled and c.whatsapp_number is not null
    union all
    -- One row per device, so somebody with a phone and a laptop is told on
    -- both. The others have exactly one address each, which is why they were
    -- a plain case expression until now.
    select 'push', s.endpoint
      from public.push_subscriptions s
     where c.push_enabled and s.user_id = c.user_id
  ) ch
  on conflict (dedupe_key) do nothing;

  -- Follow-ups that have come due, to whoever has to chase them.
  with candidates as (
    select
      t.id as task_id, t.title, t.follow_up_at, t.follow_up_note,
      a.user_id, p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled, np.push_enabled,
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
    ch.recipient,
    'Follow up: ' || c.title,
    coalesce(c.follow_up_note, 'Time to follow up on ' || c.title) || ' (' || c.title || ')',
    'follow_up:' || c.task_id || ':' || c.user_id || ':' || ch.channel || case when ch.channel = 'push' then ':' || ch.recipient else '' end || ':' || extract(epoch from c.follow_up_at)::bigint
  from candidates c
  cross join lateral (
    select 'email'::text as channel, c.email as recipient
     where c.email_enabled
    union all
    select 'telegram', c.telegram_chat_id
     where c.telegram_enabled and c.telegram_chat_id is not null
    union all
    select 'whatsapp', c.whatsapp_number
     where c.whatsapp_enabled and c.whatsapp_number is not null
    union all
    -- One row per device, so somebody with a phone and a laptop is told on
    -- both. The others have exactly one address each, which is why they were
    -- a plain case expression until now.
    select 'push', s.endpoint
      from public.push_subscriptions s
     where c.push_enabled and s.user_id = c.user_id
  ) ch
  on conflict (dedupe_key) do nothing;

  return inserted;
end;
$$;

-- Being assigned something, likewise.
create or replace function public.enqueue_assignment_reminder()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  t public.tasks%rowtype;
  prefs public.notification_preferences%rowtype;
begin
  select * into t from public.tasks where id = new.task_id;
  if not found then return null; end if;

  select * into prefs from public.notification_preferences where user_id = new.user_id;
  if not found or not prefs.remind_assigned then return null; end if;

  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    new.user_id, t.id, ch.channel, 'assigned',
    ch.recipient,
    'Assigned to you: ' || t.title,
    'You were assigned "' || t.title || '"'
      || coalesce(' - due ' || to_char(t.due_at at time zone public.company_time_zone(), 'Dy DD Mon, HH24:MI'), '') || '.',
    'assigned:' || t.id || ':' || new.user_id || ':' || ch.channel
      || case when ch.channel = 'push' then ':' || ch.recipient else '' end
  from (
    select 'email'::text as channel, (select email from public.profiles where id = new.user_id) as recipient
      where prefs.email_enabled
    union all
    select 'telegram', prefs.telegram_chat_id
      where prefs.telegram_enabled and prefs.telegram_chat_id is not null
    union all
    select 'whatsapp', prefs.whatsapp_number
      where prefs.whatsapp_enabled and prefs.whatsapp_number is not null
    union all
    select 'push', s.endpoint
      from public.push_subscriptions s
     where prefs.push_enabled and s.user_id = new.user_id
  ) ch
  where ch.recipient is not null
  on conflict (dedupe_key) do nothing;

  return null;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- 2. The morning summary
-- ---------------------------------------------------------------------------

alter table public.notification_preferences
  add column if not exists morning_summary boolean not null default false;

comment on column public.notification_preferences.morning_summary is
  'Whether this person gets one message each working morning listing their day.';

alter table public.reminder_queue
  drop constraint if exists reminder_queue_kind_check;

alter table public.reminder_queue
  add constraint reminder_queue_kind_check
  check (kind in ('assigned', 'due_soon', 'overdue', 'follow_up', 'summary'));

/**
 * One summary per person and channel for the office day `as_of` falls on.
 *
 * `as_of` is now() except in tests, which need a fixed working morning. Each
 * task is listed once, under the most pressing of: overdue, due today, follow
 * up today. Eight lines at most, then a count of the rest — a summary that
 * scrolls is not a summary.
 *
 * WhatsApp gets one line: its templates refuse a variable with a line break.
 */
create or replace function public.enqueue_morning_summaries(as_of timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  zone      constant text := public.company_time_zone();
  today     constant date := (as_of at time zone zone)::date;
  day_end   constant timestamptz := (today + 1)::timestamp at time zone zone;
  inserted  integer := 0;
begin
  with items as (
    select
      a.user_id,
      t.title,
      case
        when t.due_at < as_of   then 1   -- overdue
        when t.due_at < day_end then 2   -- due today
        else                         3   -- follow up today
      end as rank,
      case
        when t.due_at < day_end then t.due_at
        else t.follow_up_at
      end as moment
    from public.tasks t
    join public.task_assignments a on a.task_id = t.id
    where t.status <> 'done'
      and t.deleted_at is null
      and (t.due_at < day_end or t.follow_up_at < day_end)
  ),
  lines as (
    select
      i.user_id, i.rank,
      row_number() over (partition by i.user_id order by i.rank, i.moment, i.title) as n,
      i.title || case i.rank
        when 1 then ' — overdue since ' || to_char(i.moment at time zone zone, 'Dy DD Mon')
        when 2 then ' — due ' || to_char(i.moment at time zone zone, 'HH24:MI')
        else        ' — follow up'
      end as line
    from items i
  ),
  people as (
    select
      l.user_id,
      count(*) filter (where l.rank = 1) as overdue,
      count(*) filter (where l.rank = 2) as due_today,
      count(*) filter (where l.rank = 3) as follow_ups,
      count(*) as total,
      array_agg(l.line order by l.n) filter (where l.n <= 8) as shown
    from lines l
    group by l.user_id
  ),
  summaries as (
    select
      pe.*, p.email,
      np.email_enabled, np.telegram_enabled, np.whatsapp_enabled, np.push_enabled,
      np.telegram_chat_id, np.whatsapp_number,
      'Your day: ' || concat_ws(', ',
        case when pe.due_today  > 0 then pe.due_today  || ' due today' end,
        case when pe.overdue    > 0 then pe.overdue    || ' overdue' end,
        case when pe.follow_ups > 0 then pe.follow_ups || ' to follow up' end
      ) as subject,
      case when pe.total > 8 then 'and ' || (pe.total - 8) || ' more.' end as rest
    from people pe
    join public.profiles p on p.id = pe.user_id
    join public.notification_preferences np on np.user_id = pe.user_id
    where np.morning_summary
  )
  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    s.user_id, null, ch.channel, 'summary',
    ch.recipient,
    s.subject,
    case
      when ch.channel = 'whatsapp'
        then concat_ws('; ', array_to_string(s.shown, '; '), s.rest)
      else concat_ws(E'\n', '• ' || array_to_string(s.shown, E'\n• '), s.rest)
    end,
    'summary:' || s.user_id || ':' || ch.channel
      || case when ch.channel = 'push' then ':' || ch.recipient else '' end
      || ':' || to_char(today, 'YYYY-MM-DD')
  from summaries s
  cross join lateral (
    select 'email'::text as channel, s.email as recipient
     where s.email_enabled
    union all
    select 'telegram', s.telegram_chat_id
     where s.telegram_enabled and s.telegram_chat_id is not null
    union all
    select 'whatsapp', s.whatsapp_number
     where s.whatsapp_enabled and s.whatsapp_number is not null
    union all
    select 'push', d.endpoint
      from public.push_subscriptions d
     where s.push_enabled and d.user_id = s.user_id
  ) ch
  where ch.recipient is not null
  on conflict (dedupe_key) do nothing;

  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. For the dispatcher only
-- ---------------------------------------------------------------------------

revoke all on function public.enqueue_task_reminders() from public, anon, authenticated;
revoke all on function public.enqueue_morning_summaries(timestamptz) from public, anon, authenticated;
grant execute on function public.enqueue_task_reminders() to service_role;
grant execute on function public.enqueue_morning_summaries(timestamptz) to service_role;
