-- ---------------------------------------------------------------------------
-- Telling the admins when something goes wrong.
--
-- Faults were recorded (migration 28) and reminders that could not be
-- delivered were flagged (migration 27), but both waited for an admin to
-- open their profile and look. The scheduled run now sends each admin who
-- has linked Telegram a short note when there is something new: how many
-- faults, on which pages, and how many reminders could not be delivered —
-- with a link to the full list in the portal.
--
-- The note carries counts and page paths, never a fault's own text: that
-- can hold a fragment of whatever it failed on, and stays in the portal.
--
-- Everything here is for the service key only. Nobody signed in can read
-- the log, add to it, or ask for the digest; the run that sends the note is
-- the only caller.
--
-- Run in the Supabase SQL editor after 44. Safe to run more than once.
-- ---------------------------------------------------------------------------

create table if not exists public.admin_alerts (
  id        uuid primary key default gen_random_uuid(),
  sent_at   timestamptz not null default now(),
  faults    integer not null default 0 check (faults >= 0),
  failures  integer not null default 0 check (failures >= 0),
  -- How many admins it reached.
  reached   integer not null default 0 check (reached >= 0)
);

create index if not exists admin_alerts_sent_idx on public.admin_alerts (sent_at desc);

comment on table public.admin_alerts is
  'When the admins were last told about faults and failed reminders. Service key only.';

alter table public.admin_alerts enable row level security;
alter table public.admin_alerts force row level security;
-- No policies: nobody signed in reads or writes it.
revoke all on public.admin_alerts from anon, authenticated;
grant all on public.admin_alerts to service_role;

-- ---------------------------------------------------------------------------
-- What is new since the last note
--
-- Since the last note sent, or the last day for the first one, so a new
-- install does not open with a fortnight of history. Pages are grouped
-- without their query strings, busiest first, five at most.
-- ---------------------------------------------------------------------------

create or replace function public.admin_alert_digest(as_of timestamptz default now())
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with since as (
    select coalesce(
      (select max(sent_at) from public.admin_alerts where sent_at <= as_of),
      as_of - interval '24 hours'
    ) as at
  ),
  faults as (
    select e.source, coalesce(nullif(split_part(e.route, '?', 1), ''), '/') as page
      from public.app_errors e, since
     where e.occurred_at > since.at and e.occurred_at <= as_of
  ),
  pages as (
    select source, page, count(*)::int as n
      from faults
     group by source, page
     order by count(*) desc, page
     limit 5
  )
  select jsonb_build_object(
    'since', (select at from since),
    'faults', (select count(*)::int from faults),
    'pages', coalesce(
      (select jsonb_agg(jsonb_build_object('source', source, 'page', page, 'count', n)
                        order by n desc, page) from pages),
      '[]'::jsonb),
    'failedReminders', (
      select count(*)::int from public.reminder_queue q, since
       where q.status = 'failed' and q.failed_at > since.at and q.failed_at <= as_of
    ),
    'recipients', coalesce(
      (select jsonb_agg(np.telegram_chat_id order by p.created_at)
         from public.profiles p
         join public.notification_preferences np on np.user_id = p.id
        where p.role = 'admin'
          and np.telegram_enabled
          and np.telegram_chat_id is not null),
      '[]'::jsonb)
  );
$$;

revoke all on function public.admin_alert_digest(timestamptz) from public, anon, authenticated;
grant execute on function public.admin_alert_digest(timestamptz) to service_role;

comment on function public.admin_alert_digest(timestamptz) is
  'Faults and failed reminders since the admins were last told, and which Telegram chats to tell. Service key only.';
