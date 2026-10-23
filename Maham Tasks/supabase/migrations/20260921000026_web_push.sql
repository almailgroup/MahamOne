-- ---------------------------------------------------------------------------
-- Web push
--
-- The portal could reach somebody by email, Telegram or WhatsApp — every one
-- of them a different app, and none of them the one the work is in. Installed
-- to a home screen, the portal can now buzz the phone itself. iOS has allowed
-- this since 16.4, for installed web apps only, which is exactly how this one
-- is used.
--
-- Three things here:
--   * push_subscriptions — one row per device that said yes, not per person;
--   * push_enabled on the preferences, beside the other channels;
--   * 'push' as a channel on the queue, fanned out per device.
--
-- The keys that sign a push (VAPID) live in web_push_keys, which has row-level
-- security on and no policies at all: nothing reachable with a user's session
-- can read it, only the service role the dispatcher runs as. They are
-- generated on first use rather than pasted into an environment variable, so
-- the secret is never written down anywhere a person could paste it.
-- ---------------------------------------------------------------------------

create table if not exists public.push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  -- The browser's own address for this device. Unique across everybody: it is
  -- issued by the push service and two people cannot hold the same one.
  endpoint    text not null unique,
  -- The keys the payload is encrypted to. Useless without the endpoint.
  p256dh      text not null,
  auth        text not null,
  -- For the person deciding which of their devices to turn off.
  user_agent  text,
  created_at  timestamptz not null default now(),
  last_used_at timestamptz
);

create index if not exists push_subscriptions_user_idx
  on public.push_subscriptions (user_id);

alter table public.push_subscriptions enable row level security;
alter table public.push_subscriptions force row level security;

drop policy if exists "people see their own devices" on public.push_subscriptions;
create policy "people see their own devices"
  on public.push_subscriptions for select
  using (user_id = auth.uid());

drop policy if exists "people register their own devices" on public.push_subscriptions;
create policy "people register their own devices"
  on public.push_subscriptions for insert
  with check (user_id = auth.uid());

drop policy if exists "people update their own devices" on public.push_subscriptions;
create policy "people update their own devices"
  on public.push_subscriptions for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- No admin clause, deliberately: which devices somebody carries is theirs.
drop policy if exists "people remove their own devices" on public.push_subscriptions;
create policy "people remove their own devices"
  on public.push_subscriptions for delete
  using (user_id = auth.uid());

grant select, insert, update, delete on public.push_subscriptions to authenticated;

comment on table public.push_subscriptions is
  'One row per device that has agreed to notifications. The dispatcher sends to these with the service role.';

-- ---------------------------------------------------------------------------
-- The signing keys
--
-- One row, ever: `id` is a boolean fixed at true, so a second insert collides
-- with the primary key rather than quietly creating a second pair that half
-- the devices are subscribed to.
-- ---------------------------------------------------------------------------

create table if not exists public.web_push_keys (
  id          boolean primary key default true check (id),
  public_key  text not null,
  private_key text not null,
  created_at  timestamptz not null default now()
);

alter table public.web_push_keys enable row level security;
alter table public.web_push_keys force row level security;
-- No policies and no grants: the service role bypasses both, everybody else
-- is refused. The public half is handed to the browser by the app, which
-- reads this row on the server.

comment on table public.web_push_keys is
  'The VAPID key pair, generated on first use. Unreadable with a user session by design.';

-- ---------------------------------------------------------------------------
-- The channel
-- ---------------------------------------------------------------------------

alter table public.notification_preferences
  add column if not exists push_enabled boolean not null default false;

comment on column public.notification_preferences.push_enabled is
  'Whether reminders are also pushed to this person''s registered devices.';

alter table public.reminder_queue
  drop constraint if exists reminder_queue_channel_check;

alter table public.reminder_queue
  add constraint reminder_queue_channel_check
  check (channel in ('email', 'telegram', 'whatsapp', 'push'));

-- ---------------------------------------------------------------------------
-- Queueing to devices
--
-- The same function as before with one branch added. It is repeated whole
-- rather than patched because a plpgsql body cannot be edited in place, and a
-- half-replaced one is worse than a long migration.
--
-- Two things worth noticing. The lateral now carries its own recipient: the
-- other three channels have exactly one address each, a device does not, and
-- somebody with a phone and a laptop should be told on both. And the dedupe
-- key gains the endpoint for push only, so every key already in the queue
-- keeps its exact spelling and nothing that has been sent is sent again.
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
    c.title || ' is due ' || to_char(c.due_at at time zone 'UTC', 'DD Mon HH24:MI') || ' UTC.',
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
    c.title || ' was due ' || to_char(c.due_at at time zone 'UTC', 'DD Mon HH24:MI') || ' UTC and is still open.',
    'overdue:' || c.task_id || ':' || c.user_id || ':' || ch.channel || case when ch.channel = 'push' then ':' || ch.recipient else '' end || ':' || to_char(now(), 'YYYY-MM-DD')
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

-- ---------------------------------------------------------------------------
-- Being handed work, on the device in your pocket
--
-- The same trigger, with devices added to the same union it already used.
-- Assignment is the one reminder that should not wait for the next sweep, so
-- it is also the one where a push is worth most.
--
-- The dedupe key gains the endpoint for push only, as above.
-- ---------------------------------------------------------------------------

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
      || coalesce(' - due ' || to_char(t.due_at at time zone 'UTC', 'DD Mon HH24:MI') || ' UTC', '') || '.',
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
