-- ---------------------------------------------------------------------------
-- Task reminders over email, Telegram and WhatsApp
--
-- Two tables:
--   notification_preferences — which channels a person wants, where to reach
--                              them, and which events are worth interrupting
--                              them for
--   reminder_queue           — one row per message to send, drained by a
--                              scheduled dispatcher in the app
--
-- Queuing rather than sending inline means a provider outage cannot lose a
-- reminder, retries are bounded and visible, and the same reminder can never
-- go out twice — see dedupe_key.
-- ---------------------------------------------------------------------------

-- --------------------------------------------------------------------------
-- Preferences
-- --------------------------------------------------------------------------

create table if not exists public.notification_preferences (
  user_id uuid primary key references public.profiles (id) on delete cascade,

  -- Channels. Email is on by default because the address is already known and
  -- verified by sign-up; the other two need details the user has to supply.
  email_enabled    boolean not null default true,
  telegram_enabled boolean not null default false,
  whatsapp_enabled boolean not null default false,

  -- Where to reach them.
  telegram_chat_id  text,
  whatsapp_number   text,

  -- A short-lived code the user sends to the bot to prove the chat is theirs.
  telegram_link_code text,

  -- Which events are worth a message.
  remind_assigned   boolean not null default true,
  remind_due_soon   boolean not null default true,
  remind_overdue    boolean not null default true,
  remind_follow_up  boolean not null default true,

  -- How far ahead of the due time to warn.
  due_soon_lead_hours integer not null default 24,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint notification_preferences_lead_range
    check (due_soon_lead_hours between 1 and 168),

  -- E.164, the format every WhatsApp provider expects.
  constraint notification_preferences_whatsapp_format
    check (whatsapp_number is null or whatsapp_number ~ '^\+[1-9]\d{6,14}$'),

  -- A channel cannot be switched on without somewhere to send to.
  constraint notification_preferences_telegram_needs_chat
    check (not telegram_enabled or telegram_chat_id is not null),
  constraint notification_preferences_whatsapp_needs_number
    check (not whatsapp_enabled or whatsapp_number is not null)
);

create unique index if not exists notification_preferences_link_code_key
  on public.notification_preferences (telegram_link_code)
  where telegram_link_code is not null;

drop trigger if exists notification_preferences_set_updated_at on public.notification_preferences;
create trigger notification_preferences_set_updated_at
  before update on public.notification_preferences
  for each row execute function public.set_updated_at();

-- Everyone gets a row, so the dispatcher never has to reason about its absence.
create or replace function public.ensure_notification_preferences()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return null;
end;
$$;

drop trigger if exists profiles_ensure_notification_preferences on public.profiles;
create trigger profiles_ensure_notification_preferences
  after insert on public.profiles
  for each row execute function public.ensure_notification_preferences();

insert into public.notification_preferences (user_id)
select id from public.profiles
on conflict (user_id) do nothing;

-- --------------------------------------------------------------------------
-- Outbound queue
-- --------------------------------------------------------------------------

create table if not exists public.reminder_queue (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  task_id    uuid references public.tasks (id) on delete cascade,

  channel    text not null check (channel in ('email', 'telegram', 'whatsapp')),
  kind       text not null check (kind in ('assigned', 'due_soon', 'overdue', 'follow_up')),

  recipient  text not null,
  subject    text,
  body       text not null,

  status     text not null default 'pending'
             check (status in ('pending', 'sent', 'failed', 'cancelled')),
  attempts   integer not null default 0,
  last_error text,

  -- Identifies the exact reminder, so re-running the scheduler cannot send the
  -- same thing twice. Changing a due date changes the key, which is what makes
  -- a rescheduled task legitimately remind again.
  dedupe_key text not null unique,

  scheduled_for timestamptz not null default now(),
  sent_at       timestamptz,
  created_at    timestamptz not null default now()
);

-- The dispatcher's query: what is pending and due, oldest first.
create index if not exists reminder_queue_pending_idx
  on public.reminder_queue (scheduled_for)
  where status = 'pending';

create index if not exists reminder_queue_user_idx
  on public.reminder_queue (user_id, created_at desc);

-- --------------------------------------------------------------------------
-- Row Level Security
--
-- Reminders are personal. A user may read their own to see what was sent, and
-- nothing else: the queue is written by the scheduler below and drained by the
-- dispatcher, both of which run outside RLS.
-- --------------------------------------------------------------------------

alter table public.notification_preferences enable row level security;
alter table public.notification_preferences force row level security;
alter table public.reminder_queue enable row level security;
alter table public.reminder_queue force row level security;

drop policy if exists "users read their own preferences" on public.notification_preferences;
create policy "users read their own preferences"
  on public.notification_preferences for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "users update their own preferences" on public.notification_preferences;
create policy "users update their own preferences"
  on public.notification_preferences for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "users read their own reminders" on public.reminder_queue;
create policy "users read their own reminders"
  on public.reminder_queue for select
  to authenticated
  using (user_id = auth.uid());

grant select, update on public.notification_preferences to authenticated;
grant select on public.reminder_queue to authenticated;

-- --------------------------------------------------------------------------
-- Scheduling
--
-- Builds the queue from the current state of the tasks table. Safe to call as
-- often as you like: every insert is keyed, so repeat runs are no-ops until
-- something actually changes.
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

-- Being handed work is worth telling someone about immediately rather than
-- waiting for the next scheduler run.
create or replace function public.enqueue_assignment_reminder()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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
      || coalesce(' - due ' || to_char(t.due_at at time zone 'UTC', 'DD Mon HH24:MI') || ' UTC', '') || '.',
    'assigned:' || t.id || ':' || new.user_id || ':' || ch.channel
  from (
    select 'email'::text as channel, (select email from public.profiles where id = new.user_id) as recipient
      where prefs.email_enabled
    union all
    select 'telegram', prefs.telegram_chat_id
      where prefs.telegram_enabled and prefs.telegram_chat_id is not null
    union all
    select 'whatsapp', prefs.whatsapp_number
      where prefs.whatsapp_enabled and prefs.whatsapp_number is not null
  ) ch
  where ch.recipient is not null
  on conflict (dedupe_key) do nothing;

  return null;
end;
$$;

drop trigger if exists task_assignments_enqueue_reminder on public.task_assignments;
create trigger task_assignments_enqueue_reminder
  after insert on public.task_assignments
  for each row execute function public.enqueue_assignment_reminder();
