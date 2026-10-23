-- ---------------------------------------------------------------------------
-- When a reminder cannot be delivered
--
-- A reminder that exhausted its four attempts was marked `failed` and that
-- was the end of it. Nobody was told — not the person waiting for it, not an
-- admin. The only symptom was somebody quietly not hearing about their work,
-- which reads as the portal not bothering rather than as a wrong phone
-- number or a revoked notification permission.
--
-- Two things here. The person gets a notification, in the same bell as
-- everything else, saying which channel failed. And an admin can see the
-- failures across the team without being handed the messages themselves.
-- ---------------------------------------------------------------------------

-- When it gave up, which the row never recorded. `created_at` is when it was
-- queued: for a reminder that spent an hour being retried those are an hour
-- apart, and "why did nobody hear about this" is a question about the second
-- one. Old rows keep their queued time as the best available answer.
alter table public.reminder_queue
  add column if not exists failed_at timestamptz;

comment on column public.reminder_queue.failed_at is
  'When delivery was given up on. Null while the row is still pending or was sent.';

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
    'reminder_failed'
  )
);

-- ---------------------------------------------------------------------------
-- The team's delivery failures, for somebody who can act on them
--
-- `security definer` because an admin has no business reading the queue
-- itself: a row carries the message, and a message carries the work. This
-- hands back who, which channel, when and why — and never the body.
--
-- The admin check is inside the function rather than in a policy, so calling
-- it as anybody else is refused rather than quietly returning nothing.
-- ---------------------------------------------------------------------------

create or replace function public.reminder_failures(since_hours integer default 168)
returns table (
  user_id     uuid,
  person      text,
  channel     text,
  kind        text,
  attempts    integer,
  last_error  text,
  failed_at   timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
begin
  if not public.is_admin() then
    raise exception 'Only an admin can read delivery failures.'
      using errcode = 'insufficient_privilege';
  end if;

  return query
    select
      q.user_id,
      coalesce(p.full_name, p.email) as person,
      q.channel,
      q.kind,
      q.attempts,
      q.last_error,
      coalesce(q.failed_at, q.created_at) as failed_at
    from public.reminder_queue q
    join public.profiles p on p.id = q.user_id
   where q.status = 'failed'
     and coalesce(q.failed_at, q.created_at) > now() - make_interval(hours => greatest(1, since_hours))
   order by coalesce(q.failed_at, q.created_at) desc
   limit 100;
end;
$fn$;

comment on function public.reminder_failures(integer) is
  'Recent undeliverable reminders, for an admin. Who, which channel and why — never the message.';

grant execute on function public.reminder_failures(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- And the same question about yourself, which anybody may ask
--
-- The existing policy already lets somebody read their own queue rows, so
-- this is only a convenience: the shape the profile page wants, without the
-- body, and without every caller having to remember the status filter.
-- ---------------------------------------------------------------------------

create or replace function public.my_reminder_failures(since_hours integer default 168)
returns table (
  channel    text,
  kind       text,
  attempts   integer,
  last_error text,
  failed_at  timestamptz
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $fn$
  select
    q.channel,
    q.kind,
    q.attempts,
    q.last_error,
    coalesce(q.failed_at, q.created_at)
  from public.reminder_queue q
   where q.user_id = auth.uid()
     and q.status = 'failed'
     and coalesce(q.failed_at, q.created_at) > now() - make_interval(hours => greatest(1, since_hours))
   order by coalesce(q.failed_at, q.created_at) desc
   limit 20;
$fn$;

comment on function public.my_reminder_failures(integer) is
  'Reminders that could not be delivered to you. Security invoker: RLS decides, as it does for the table.';

grant execute on function public.my_reminder_failures(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Telling the person
--
-- Written here rather than by the dispatcher because every other
-- notification in this schema is written by the database, and the table's
-- grants say so: nothing holding a user's session may insert one. The
-- dispatcher calls this with the row it has just given up on.
--
-- The message names the channel, because the fix is almost always a wrong
-- number or a permission somebody revoked, and neither is guessable from
-- "a reminder failed".
-- ---------------------------------------------------------------------------

create or replace function public.notify_reminder_failed(reminder uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  q public.reminder_queue%rowtype;
  heading text;
begin
  select * into q from public.reminder_queue where id = reminder;
  if not found or q.status <> 'failed' then
    return;
  end if;

  heading := case q.channel
    when 'email'    then 'A reminder could not be emailed to you'
    when 'telegram' then 'A reminder could not be sent to you on Telegram'
    when 'whatsapp' then 'A reminder could not be sent to you on WhatsApp'
    when 'push'     then 'A reminder could not reach one of your devices'
    else 'A reminder could not be delivered to you'
  end;

  insert into public.notifications (user_id, actor_id, type, title, body, task_id)
  values (
    q.user_id,
    null,
    'reminder_failed',
    heading,
    coalesce(q.subject, left(q.body, 140)),
    q.task_id
  );
end;
$fn$;

comment on function public.notify_reminder_failed(uuid) is
  'Tells somebody a reminder could not be delivered, naming the channel. Called by the dispatcher.';
