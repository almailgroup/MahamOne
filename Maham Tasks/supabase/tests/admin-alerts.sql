-- ---------------------------------------------------------------------------
-- Admin alerts: the digest counts what is new since the last note, groups
-- faults by page without the query string, finds the admins on Telegram —
-- and nobody signed in can read it, the log, or call it.
--
--   psql -f supabase/tests/shim.sql -f supabase/setup.sql -f this file
--
-- NEVER run this against the production project.
-- ---------------------------------------------------------------------------

begin;

create temporary table results (name text, ok boolean, detail text);
grant all on results to authenticated, service_role;

create or replace function check_that(name text, ok boolean, detail text default '')
returns void language sql as $$
  insert into results values (name, ok, detail);
$$;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000045a1', 'admin@example.test');
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000045a2', 'second-admin@example.test'),
  ('00000000-0000-4000-8000-0000000045b1', 'member@example.test');

alter table public.profiles disable trigger profiles_guard_role_change;
update public.profiles set role = 'admin'
 where id = '00000000-0000-4000-8000-0000000045a2';
alter table public.profiles enable trigger profiles_guard_role_change;

-- The first admin and the member are on Telegram; the second admin is not.
update public.notification_preferences
   set telegram_enabled = true, telegram_chat_id = '4501'
 where user_id = '00000000-0000-4000-8000-0000000045a1';
update public.notification_preferences
   set telegram_enabled = true, telegram_chat_id = '4502'
 where user_id = '00000000-0000-4000-8000-0000000045b1';

-- Faults: two on the tasks page (one with a query string), one on the
-- calendar, and one from three days ago that is old news.
insert into public.app_errors (occurred_at, source, message, route) values
  ('2026-10-18 06:00+00', 'browser', 'TypeError: secret task title', '/tasks?filter=all&task=1'),
  ('2026-10-18 06:10+00', 'browser', 'TypeError: secret task title', '/tasks'),
  ('2026-10-18 06:20+00', 'server', 'boom', '/calendar'),
  ('2026-10-15 06:00+00', 'browser', 'old', '/today');

insert into public.reminder_queue
  (user_id, channel, kind, recipient, body, dedupe_key, status, attempts, last_error, failed_at)
values
  ('00000000-0000-4000-8000-0000000045b1', 'whatsapp', 'overdue', '+96550000045', 'x',
   'alert-test-1', 'failed', 5, 'no', '2026-10-18 05:30+00'),
  ('00000000-0000-4000-8000-0000000045b1', 'whatsapp', 'overdue', '+96550000045', 'y',
   'alert-test-2', 'failed', 5, 'no', '2026-10-14 05:30+00');

-- --- the service key ----------------------------------------------------------

set local role service_role;

create temporary table digest as
  select public.admin_alert_digest('2026-10-18 07:00+00') as d;

select check_that('the first note looks back one day',
  (select (d->>'since')::timestamptz = '2026-10-17 07:00+00' from digest),
  (select d->>'since' from digest));

select check_that('it counts the faults since then, not the old ones',
  (select (d->>'faults')::int = 3 from digest),
  (select d::text from digest));

select check_that('pages are grouped without their query string, busiest first',
  (select d->'pages' = '[{"page": "/tasks", "count": 2, "source": "browser"},
                         {"page": "/calendar", "count": 1, "source": "server"}]'::jsonb from digest),
  (select (d->'pages')::text from digest));

select check_that('a fault''s own text is not in it',
  (select position('secret' in d::text) = 0 from digest));

select check_that('it counts reminders that could not be delivered since then',
  (select (d->>'failedReminders')::int = 1 from digest));

select check_that('it is told to the admins on Telegram, and only them',
  (select d->'recipients' = '["4501"]'::jsonb from digest),
  (select (d->'recipients')::text from digest));

insert into public.admin_alerts (sent_at, faults, failures, reached)
values ('2026-10-18 07:00+00', 3, 1, 1);

select check_that('after a note, the next one starts from it',
  (select (d->>'faults')::int = 0 and (d->>'failedReminders')::int = 0
     from (select public.admin_alert_digest('2026-10-18 08:00+00') as d) later));

reset role;

-- --- anybody signed in --------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000045a1', true);

do $$
begin
  perform public.admin_alert_digest();
  perform check_that('not even an admin can ask for the digest', false, 'it answered');
exception when insufficient_privilege then
  perform check_that('not even an admin can ask for the digest', true, sqlerrm);
end $$;

do $$
declare n integer;
begin
  select count(*) into n from public.admin_alerts;
  perform check_that('nor read the log', false, 'it read ' || n);
exception when insufficient_privilege then
  perform check_that('nor read the log', true, sqlerrm);
end $$;

do $$
begin
  insert into public.admin_alerts (faults) values (1);
  perform check_that('nor write to it', false, 'it was accepted');
exception when insufficient_privilege then
  perform check_that('nor write to it', true, sqlerrm);
end $$;

-- --- results ---------------------------------------------------------------

reset role;

select
  case when ok then 'PASS' else 'FAIL' end as result,
  name,
  detail
from results
order by ok, name;

select count(*) filter (where ok is not true) as failures from results;

do $$
declare failed integer;
begin
  select count(*) filter (where ok is not true) into failed from results;
  if failed > 0 then
    raise exception '% check(s) failed — see the table above', failed;
  end if;
end $$;

rollback;
