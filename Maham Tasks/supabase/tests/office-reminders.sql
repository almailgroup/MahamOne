-- ---------------------------------------------------------------------------
-- Reminders on office time, and the morning summary.
--
-- The summary is built for a fixed Sunday morning, 08:00 in Kuwait, rather
-- than for whenever this happens to run: what counts as "today" and
-- "overdue" depends on the hour, and a test that passes on some mornings
-- only is no test.
--
--   psql -f supabase/tests/shim.sql -f supabase/setup.sql -f this file
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

-- Sunday 18 October 2026, 08:00 in Kuwait (05:00 UTC).
create temporary table morning as
  select timestamptz '2026-10-18 08:00 Asia/Kuwait' as at;

-- --- people ------------------------------------------------------------------
--   a1: wants the summary, by email and WhatsApp
--   b1: does not want it
--   c1: wants it, but has nothing on today
--   d1: wants it, and has a great deal on
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000037a1', 'busy@example.test');
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000037b1', 'quiet@example.test'),
  ('00000000-0000-4000-8000-0000000037c1', 'free@example.test'),
  ('00000000-0000-4000-8000-0000000037d1', 'swamped@example.test');

update public.notification_preferences
   set morning_summary = true, whatsapp_enabled = true, whatsapp_number = '+96550000037'
 where user_id = '00000000-0000-4000-8000-0000000037a1';
update public.notification_preferences
   set morning_summary = true
 where user_id in ('00000000-0000-4000-8000-0000000037c1',
                   '00000000-0000-4000-8000-0000000037d1');

insert into public.projects (id, name, created_by)
values ('11111111-1111-4111-8111-0000000037a1', 'Office',
        '00000000-0000-4000-8000-0000000037a1');

insert into public.tasks (id, project_id, title, status, due_at, follow_up_at, deleted_at, created_by)
select id::uuid, '11111111-1111-4111-8111-0000000037a1', title, status::public.task_status,
       due::timestamptz, follow::timestamptz, gone::timestamptz,
       '00000000-0000-4000-8000-0000000037a1'
from (values
  ('22222222-2222-4222-8222-0000000037a1', 'Renew the trade licence', 'todo',
     '2026-10-15 10:00 Asia/Kuwait', null, null),
  ('22222222-2222-4222-8222-0000000037a2', 'Sign the payroll', 'in_progress',
     '2026-10-18 13:30 Asia/Kuwait', null, null),
  ('22222222-2222-4222-8222-0000000037a3', 'Chase the bank', 'todo',
     '2026-10-25 12:00 Asia/Kuwait', '2026-10-18 11:00 Asia/Kuwait', null),
  ('22222222-2222-4222-8222-0000000037a4', 'Tomorrow''s visit', 'todo',
     '2026-10-19 09:00 Asia/Kuwait', null, null),
  ('22222222-2222-4222-8222-0000000037a5', 'Already filed', 'done',
     '2026-10-18 10:00 Asia/Kuwait', null, null),
  ('22222222-2222-4222-8222-0000000037a6', 'Thrown away', 'todo',
     '2026-10-18 10:00 Asia/Kuwait', null, '2026-10-17 12:00 Asia/Kuwait'),
  ('22222222-2222-4222-8222-0000000037b1', 'Someone else''s day', 'todo',
     '2026-10-18 10:00 Asia/Kuwait', null, null)
) as t(id, title, status, due, follow, gone);

insert into public.task_assignments (task_id, user_id)
select id, '00000000-0000-4000-8000-0000000037a1'
  from public.tasks where id::text like '22222222-2222-4222-8222-0000000037a_';
insert into public.task_assignments (task_id, user_id) values
  ('22222222-2222-4222-8222-0000000037b1', '00000000-0000-4000-8000-0000000037b1');

-- Ten things due today for d1.
insert into public.tasks (id, project_id, title, status, due_at, created_by)
select ('33333333-3333-4333-8333-0000000037' || lpad(n::text, 2, '0'))::uuid,
       '11111111-1111-4111-8111-0000000037a1', 'Pile item ' || n, 'todo',
       timestamptz '2026-10-18 09:00 Asia/Kuwait' + make_interval(mins => n),
       '00000000-0000-4000-8000-0000000037a1'
  from generate_series(1, 10) n;
insert into public.task_assignments (task_id, user_id)
select id, '00000000-0000-4000-8000-0000000037d1'
  from public.tasks where title like 'Pile item %';

-- The assignment trigger has queued "assigned" rows; only summaries matter here.
delete from public.reminder_queue;

select public.enqueue_morning_summaries((select at from morning));

-- --- who is summarised ---------------------------------------------------------

select check_that(
  'someone who asked gets one summary per channel',
  (select array_agg(channel order by channel) from public.reminder_queue
    where user_id = '00000000-0000-4000-8000-0000000037a1' and kind = 'summary')
  = array['email', 'whatsapp'],
  (select string_agg(channel || '/' || kind, ', ') from public.reminder_queue));

select check_that(
  'someone who did not ask gets nothing',
  not exists (select 1 from public.reminder_queue
               where user_id = '00000000-0000-4000-8000-0000000037b1'));

select check_that(
  'someone with nothing on today is not messaged to say so',
  not exists (select 1 from public.reminder_queue
               where user_id = '00000000-0000-4000-8000-0000000037c1'));

-- --- what it says --------------------------------------------------------------

select check_that(
  'the subject counts the day',
  (select subject from public.reminder_queue
    where user_id = '00000000-0000-4000-8000-0000000037a1' and channel = 'email')
  = 'Your day: 1 due today, 1 overdue, 1 to follow up',
  (select subject from public.reminder_queue
    where user_id = '00000000-0000-4000-8000-0000000037a1' and channel = 'email'));

select check_that(
  'overdue first, then today in office time, then follow-ups',
  (select body from public.reminder_queue
    where user_id = '00000000-0000-4000-8000-0000000037a1' and channel = 'email')
  = E'• Renew the trade licence — overdue since Thu 15 Oct\n'
    '• Sign the payroll — due 13:30\n'
    '• Chase the bank — follow up',
  (select body from public.reminder_queue
    where user_id = '00000000-0000-4000-8000-0000000037a1' and channel = 'email'));

select check_that(
  'tomorrow, finished and binned work is left out',
  (select body not like '%Tomorrow%' and body not like '%filed%' and body not like '%Thrown%'
     from public.reminder_queue
    where user_id = '00000000-0000-4000-8000-0000000037a1' and channel = 'email'));

select check_that(
  'WhatsApp gets it on one line',
  (select body from public.reminder_queue
    where user_id = '00000000-0000-4000-8000-0000000037a1' and channel = 'whatsapp')
  = 'Renew the trade licence — overdue since Thu 15 Oct; Sign the payroll — due 13:30; Chase the bank — follow up');

select check_that(
  'a long day is cut at eight lines, and says how many more',
  (select body from public.reminder_queue
    where user_id = '00000000-0000-4000-8000-0000000037d1')
  like '%Pile item 8 — due 09:08' || E'\n' || 'and 2 more.',
  (select body from public.reminder_queue
    where user_id = '00000000-0000-4000-8000-0000000037d1'));

-- --- once a day ----------------------------------------------------------------

select check_that(
  'a second run the same morning queues nothing',
  public.enqueue_morning_summaries((select at + interval '3 hours' from morning)) = 0);

select check_that(
  'the next working morning queues again',
  public.enqueue_morning_summaries((select at + interval '1 day' from morning)) > 0);

-- --- reminders read in office time ---------------------------------------------

delete from public.reminder_queue;
-- Rescheduled by the admin (the first account), as the task guard requires.
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000037a1', true);
update public.tasks set due_at = now() + interval '2 hours'
 where id = '22222222-2222-4222-8222-0000000037a2';
select public.enqueue_task_reminders();

select check_that(
  'a due-soon reminder gives the time in Kuwait, not UTC',
  (select body from public.reminder_queue
    where task_id = '22222222-2222-4222-8222-0000000037a2'
      and kind = 'due_soon' and channel = 'email')
  = 'Sign the payroll is due '
    || to_char((now() + interval '2 hours') at time zone 'Asia/Kuwait', 'Dy DD Mon, HH24:MI') || '.',
  (select body from public.reminder_queue
    where task_id = '22222222-2222-4222-8222-0000000037a2' and channel = 'email'));

select check_that(
  'an overdue reminder is keyed by the office''s day',
  exists (select 1 from public.reminder_queue
           where task_id = '22222222-2222-4222-8222-0000000037a1' and kind = 'overdue'
             and dedupe_key like '%:' || to_char(now() at time zone 'Asia/Kuwait', 'YYYY-MM-DD')));

-- --- for the dispatcher only ---------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000037a1', true);

do $$
begin
  perform public.enqueue_morning_summaries();
  perform check_that('a signed-in session cannot queue summaries', false, 'it ran');
exception when insufficient_privilege then
  perform check_that('a signed-in session cannot queue summaries', true, sqlerrm);
end $$;

do $$
begin
  perform public.enqueue_task_reminders();
  perform check_that('…or reminders', false, 'it ran');
exception when insufficient_privilege then
  perform check_that('…or reminders', true, sqlerrm);
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

do $$
declare failed integer;
begin
  select count(*) filter (where ok is not true) into failed from results;
  if failed > 0 then
    raise exception '% check(s) failed — see the table above', failed;
  end if;
end $$;

rollback;
