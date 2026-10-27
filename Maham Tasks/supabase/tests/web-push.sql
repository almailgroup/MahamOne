-- ---------------------------------------------------------------------------
-- Web push, checked where the fan-out lives.
--
-- The thing worth testing here is not that a notification arrives — that is
-- the push service's job — but that one person with two devices is queued
-- twice, that a second sweep does not queue them again, and that the other
-- three channels are untouched by any of it.
--
--   psql -f supabase/tests/shim.sql -f <every migration> -f this file
--
-- NEVER run this against the production project.
-- ---------------------------------------------------------------------------

begin;

create temporary table results (name text, ok boolean, detail text);
-- Some checks below run as `authenticated` to see what a signed-in session
-- can reach; they still have to be able to record what they found.
grant all on results to authenticated;

create or replace function check_that(name text, ok boolean, detail text default '')
returns void language sql as $$
  insert into results values (name, ok, detail);
$$;

-- --- two people, one with two devices --------------------------------------
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000c1', 'two-devices@example.test'),
  ('00000000-0000-4000-8000-0000000000c2', 'no-push@example.test');

update public.notification_preferences
   set push_enabled = true
 where user_id = '00000000-0000-4000-8000-0000000000c1';

insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, user_agent)
values
  ('00000000-0000-4000-8000-0000000000c1', 'https://push.example/one', 'k1', 'a1', 'iPhone'),
  ('00000000-0000-4000-8000-0000000000c1', 'https://push.example/two', 'k2', 'a2', 'Mac'),
  -- Registered, but the channel is off: a device on its own is not consent.
  ('00000000-0000-4000-8000-0000000000c2', 'https://push.example/three', 'k3', 'a3', 'iPad');

insert into public.projects (id, name, created_by)
values ('11111111-1111-4111-8111-0000000000c1', 'Ops',
        '00000000-0000-4000-8000-0000000000c1');

-- Due inside the default lead time, so the sweep picks it up.
insert into public.tasks (id, project_id, title, status, due_at, created_by)
values ('22222222-2222-4222-8222-0000000000c1',
        '11111111-1111-4111-8111-0000000000c1',
        'Sign the bank mandate', 'todo', now() + interval '2 hours',
        '00000000-0000-4000-8000-0000000000c1');

insert into public.task_assignments (task_id, user_id) values
  ('22222222-2222-4222-8222-0000000000c1', '00000000-0000-4000-8000-0000000000c1'),
  ('22222222-2222-4222-8222-0000000000c1', '00000000-0000-4000-8000-0000000000c2');

select public.enqueue_task_reminders();

-- --- one row per device ----------------------------------------------------
select check_that(
  'a person with two devices is queued twice, per reminder',
  (select count(*) from public.reminder_queue
    where channel = 'push' and kind = 'due_soon'
      and user_id = '00000000-0000-4000-8000-0000000000c1') = 2,
  (select count(*)::text from public.reminder_queue where channel = 'push'));

select check_that(
  'each row is addressed to its own device',
  (select array_agg(recipient order by recipient) from public.reminder_queue
    where channel = 'push' and kind = 'due_soon'
      and user_id = '00000000-0000-4000-8000-0000000000c1')
  = array['https://push.example/one', 'https://push.example/two'],
  (select string_agg(recipient, ', ') from public.reminder_queue where channel = 'push'));

select check_that(
  'a registered device with the channel off is not queued',
  (select count(*) from public.reminder_queue
    where channel = 'push'
      and user_id = '00000000-0000-4000-8000-0000000000c2') = 0);

-- Two people, two kinds each: being handed the work, and it falling due.
select check_that(
  'email is queued exactly as before',
  (select count(*) from public.reminder_queue where channel = 'email') = 4,
  (select string_agg(kind || '/' || channel, ', ' order by kind || channel)
     from public.reminder_queue where channel = 'email'));

select check_that(
  'being handed the work reaches the devices too',
  (select count(*) from public.reminder_queue
    where channel = 'push' and kind = 'assigned') = 2,
  (select count(*)::text from public.reminder_queue
    where channel = 'push' and kind = 'assigned'));

-- --- the second sweep ------------------------------------------------------
select public.enqueue_task_reminders();

select check_that(
  'a second sweep queues nothing twice',
  (select count(*) from public.reminder_queue) = 8,
  (select count(*)::text from public.reminder_queue));

-- --- the key that stops a queued reminder being re-sent --------------------
select check_that(
  'the dedupe key of an email is unchanged by any of this',
  (select dedupe_key from public.reminder_queue
    where channel = 'email' and kind = 'due_soon'
      and user_id = '00000000-0000-4000-8000-0000000000c1')
  = 'due_soon:22222222-2222-4222-8222-0000000000c1:00000000-0000-4000-8000-0000000000c1:email:'
    || extract(epoch from (select due_at from public.tasks
                            where id = '22222222-2222-4222-8222-0000000000c1'))::bigint,
  (select dedupe_key from public.reminder_queue
    where channel = 'email' and kind = 'due_soon'
      and user_id = '00000000-0000-4000-8000-0000000000c1'));

select check_that(
  'a push key carries the device, or two devices would collide',
  (select count(distinct dedupe_key) from public.reminder_queue
    where channel = 'push') = 4,
  (select count(distinct dedupe_key)::text from public.reminder_queue
    where channel = 'push'));

-- --- the keys nothing with a session may read ------------------------------
insert into public.web_push_keys (public_key, private_key) values ('pub', 'priv');

do $$
begin
  begin
    insert into public.web_push_keys (public_key, private_key) values ('pub2', 'priv2');
    perform check_that('there can only ever be one key pair', false, 'a second was accepted');
  exception when unique_violation then
    perform check_that('there can only ever be one key pair', true);
  end;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000c1', true);

do $$
declare
  seen integer;
begin
  begin
    select count(*) into seen from public.web_push_keys;
    perform check_that('a signed-in user cannot read the signing keys', seen = 0, seen::text);
  exception when insufficient_privilege then
    perform check_that('a signed-in user cannot read the signing keys', true, 'refused outright');
  end;
end $$;

-- A device belongs to whoever registered it.
do $$
declare
  seen integer;
begin
  select count(*) into seen from public.push_subscriptions;
  perform check_that('somebody sees only their own devices', seen = 2, seen::text);
end $$;

reset role;

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
