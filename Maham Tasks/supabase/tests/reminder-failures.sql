-- ---------------------------------------------------------------------------
-- Who may learn that a reminder failed.
--
-- The failure itself is operational, not private — but the queue row carries
-- the message, and the message carries the work. So an admin gets who, which
-- channel and why, and never the body; anybody else gets their own failures
-- and nobody else's.
--
--   psql -f supabase/tests/shim.sql -f <every migration> -f this file
--
-- NEVER run this against the production project.
-- ---------------------------------------------------------------------------

begin;

create temporary table results (name text, ok boolean, detail text);
grant all on results to authenticated;

create or replace function check_that(name text, ok boolean, detail text default '')
returns void language sql as $$
  insert into results values (name, ok, detail);
$$;

-- --- an admin, a member, and a failure each -------------------------------
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000d1', 'boss@example.test'),
  ('00000000-0000-4000-8000-0000000000d2', 'hand@example.test');

alter table public.profiles disable trigger profiles_guard_role_change;
update public.profiles set role = 'admin'
 where id = '00000000-0000-4000-8000-0000000000d1';
alter table public.profiles enable trigger profiles_guard_role_change;

select check_that(
  'the fixture admin really is an admin',
  (select role = 'admin' from public.profiles
    where id = '00000000-0000-4000-8000-0000000000d1'),
  (select role::text from public.profiles
    where id = '00000000-0000-4000-8000-0000000000d1'));

insert into public.reminder_queue
  (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key,
   status, attempts, last_error, failed_at)
values
  ('00000000-0000-4000-8000-0000000000d1', null, 'whatsapp', 'due_soon',
   '+96500000001', 'Due soon: the board pack', 'The board pack is due.',
   'test:boss:1', 'failed', 4, 'Twilio 400: not a WhatsApp number', now()),
  ('00000000-0000-4000-8000-0000000000d2', null, 'push', 'assigned',
   'https://push.example/gone', 'Assigned to you: the freight audit',
   'You were assigned the freight audit.', 'test:hand:1',
   'failed', 1, 'gone', now()),
  -- Still trying: not a failure yet, and must not be reported as one.
  ('00000000-0000-4000-8000-0000000000d2', null, 'email', 'overdue',
   'hand@example.test', 'Overdue', 'It is late.', 'test:hand:2',
   'pending', 1, 'Resend 500', null);

-- --- the person sees their own, and only their own ------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d2', true);

do $$
declare
  seen integer;
  channels text;
begin
  select count(*), string_agg(channel, ',' order by channel)
    into seen, channels
    from public.my_reminder_failures();

  perform check_that('somebody sees their own failure', seen = 1, coalesce(channels, '-'));
  perform check_that('and not the one still being retried', channels = 'push', coalesce(channels, '-'));
end $$;

-- --- and cannot read the team's ------------------------------------------
do $$
begin
  begin
    perform * from public.reminder_failures();
    perform check_that('a member cannot read the team''s failures', false, 'it was allowed');
  exception when insufficient_privilege then
    perform check_that('a member cannot read the team''s failures', true, 'refused');
  end;
end $$;

-- --- the admin sees everybody's, without the message ----------------------
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000d1', true);

do $$
declare
  seen integer;
  people text;
begin
  select count(*), string_agg(person, ', ' order by person)
    into seen, people
    from public.reminder_failures();

  perform check_that('an admin sees the team''s failures', seen = 2, coalesce(people, '-'));
end $$;

-- The columns the function returns are its OUT parameters, so this asks the
-- catalogue rather than trusting the definition to stay as it reads today.
select check_that(
  'what an admin gets back carries no message body',
  not exists (
    select 1
      from information_schema.routines r
      join information_schema.parameters p on p.specific_name = r.specific_name
     where r.routine_name = 'reminder_failures'
       and p.parameter_name in ('body', 'subject')
  ));

reset role;

-- --- the person is told ---------------------------------------------------
do $$
declare
  queued uuid;
  told integer;
begin
  select id into queued from public.reminder_queue
   where user_id = '00000000-0000-4000-8000-0000000000d2' and status = 'failed';

  perform public.notify_reminder_failed(queued);

  select count(*) into told from public.notifications
   where user_id = '00000000-0000-4000-8000-0000000000d2'
     and type = 'reminder_failed';

  perform check_that('the person is told, in the bell they already watch', told = 1, told::text);
end $$;

select check_that(
  'and the message names the channel, because that is the fix',
  (select title like '%devices%' from public.notifications
    where user_id = '00000000-0000-4000-8000-0000000000d2'
      and type = 'reminder_failed'),
  (select title from public.notifications
    where user_id = '00000000-0000-4000-8000-0000000000d2'
      and type = 'reminder_failed'));

-- A row that is not failed must never produce one of these.
do $$
declare
  pending_row uuid;
  told integer;
begin
  select id into pending_row from public.reminder_queue where status = 'pending';
  perform public.notify_reminder_failed(pending_row);

  select count(*) into told from public.notifications where type = 'reminder_failed';
  perform check_that('a reminder still being retried tells nobody', told = 1, told::text);
end $$;

-- --- results ---------------------------------------------------------------
select
  case when ok then 'PASS' else 'FAIL' end as result,
  name,
  detail
from results
order by ok, name;

select count(*) filter (where ok is not true) as failures from results;

-- A failing check has to fail the run, not just appear in the table above.
-- Printing the rows and exiting 0 is how these files sat in the repo being
-- green by never being asked: psql stops on an *error*, and a FAIL row is
-- not one until something raises.
do $$
declare failed integer;
begin
  select count(*) filter (where ok is not true) into failed from results;
  if failed > 0 then
    raise exception '% check(s) failed — see the table above', failed;
  end if;
end $$;

rollback;
