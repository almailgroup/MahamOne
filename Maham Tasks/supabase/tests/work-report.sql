-- ---------------------------------------------------------------------------
-- The work report counts the right things, in the office's days, and only
-- what the person asking can see.
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

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000043a1', 'admin@example.test');
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000043b1', 'lead@example.test'),
  ('00000000-0000-4000-8000-0000000043c1', 'doer@example.test');

update public.profiles set full_name = 'Doer' where id = '00000000-0000-4000-8000-0000000043c1';

alter table public.profiles disable trigger profiles_guard_role_change;
update public.profiles set role = 'manager' where id = '00000000-0000-4000-8000-0000000043b1';
alter table public.profiles enable trigger profiles_guard_role_change;

-- A project only the admin is on, and one the manager is on too.
insert into public.projects (id, name, created_by) values
  ('11111111-1111-4111-8111-0000000043a1', 'Seen', '00000000-0000-4000-8000-0000000043b1'),
  ('11111111-1111-4111-8111-0000000043a2', 'Unseen', '00000000-0000-4000-8000-0000000043a1');

-- Period: Sunday 4 to Saturday 17 October 2026 (two office weeks).
-- In it: three added in "Seen", two finished (one on time, one late), one
-- overdue and open, assigned to the doer. Plus one in "Unseen", and one binned.
insert into public.tasks (id, project_id, title, status, due_at, created_by, created_at, updated_at, deleted_at) values
  ('22222222-2222-4222-8222-0000000043a1', '11111111-1111-4111-8111-0000000043a1', 'On time', 'done',
   '2026-10-08 17:00+03', '00000000-0000-4000-8000-0000000043b1', '2026-10-05 09:00+03', '2026-10-07 12:00+03', null),
  ('22222222-2222-4222-8222-0000000043a2', '11111111-1111-4111-8111-0000000043a1', 'Late', 'done',
   '2026-10-06 17:00+03', '00000000-0000-4000-8000-0000000043b1', '2026-10-05 09:00+03', '2026-10-13 12:00+03', null),
  ('22222222-2222-4222-8222-0000000043a3', '11111111-1111-4111-8111-0000000043a1', 'Overdue', 'todo',
   '2026-10-10 17:00+03', '00000000-0000-4000-8000-0000000043b1', '2026-10-12 09:00+03', '2026-10-12 09:00+03', null),
  ('22222222-2222-4222-8222-0000000043a4', '11111111-1111-4111-8111-0000000043a2', 'Hidden', 'done',
   null, '00000000-0000-4000-8000-0000000043a1', '2026-10-05 09:00+03', '2026-10-06 09:00+03', null),
  ('22222222-2222-4222-8222-0000000043a5', '11111111-1111-4111-8111-0000000043a1', 'Binned', 'todo',
   null, '00000000-0000-4000-8000-0000000043b1', '2026-10-05 09:00+03', '2026-10-05 09:00+03', '2026-10-06 09:00+03'),
  -- The period before: one finished.
  ('22222222-2222-4222-8222-0000000043a6', '11111111-1111-4111-8111-0000000043a1', 'Earlier', 'done',
   null, '00000000-0000-4000-8000-0000000043b1', '2026-09-22 09:00+03', '2026-09-23 09:00+03', null);

insert into public.task_assignments (task_id, user_id) values
  ('22222222-2222-4222-8222-0000000043a3', '00000000-0000-4000-8000-0000000043c1');

-- The log says when the late one was finished — after its due date.
insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value, created_at) values
  ('22222222-2222-4222-8222-0000000043a2', '00000000-0000-4000-8000-0000000043b1', 'status_changed', 'status', 'in_review', 'done', '2026-10-13 11:00+03');

-- The rows above set their own timestamps; triggers may have written others.
delete from public.task_activity where action = 'created';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000043b1', true);

create temporary table report as
  select public.work_report('2026-10-04', '2026-10-17') as r;
grant select on report to authenticated;

select check_that('finished in the period, of what the manager can see',
  (select (r ->> 'finished')::int from report) = 2, (select r::text from report));
select check_that('…and in the period before',
  (select (r ->> 'finishedBefore')::int from report) = 1);
select check_that('added in the period, binned work left out',
  (select (r ->> 'added')::int from report) = 3);
select check_that('one of two finished by its due date',
  (select (r ->> 'onTime')::int from report) = 1 and (select (r ->> 'withDue')::int from report) = 2);
select check_that('overdue now',
  (select (r ->> 'overdueNow')::int from report) = 1);
select check_that('two office weeks, starting on Sundays',
  (select jsonb_agg(b -> 'starts') from report, jsonb_array_elements(r -> 'buckets') b)
    = '["2026-10-04", "2026-10-11"]'::jsonb,
  (select (r -> 'buckets')::text from report));
select check_that('…with the work in the week it happened',
  (select jsonb_agg(jsonb_build_array(b -> 'added', b -> 'finished')) from report, jsonb_array_elements(r -> 'buckets') b)
    = '[[2, 1], [1, 1]]'::jsonb);
select check_that('open work by person, with what is overdue',
  (select r -> 'people' from report)
    = '[{"id": "00000000-0000-4000-8000-0000000043c1", "name": "Doer", "open": 1, "overdue": 1}]'::jsonb,
  (select (r -> 'people')::text from report));
select check_that('projects the manager can see, and not the other',
  (select jsonb_agg(p -> 'name') from report, jsonb_array_elements(r -> 'projects') p) = '["Seen"]'::jsonb,
  (select (r -> 'projects')::text from report));
select check_that('…with their progress',
  (select (r -> 'projects' -> 0 ->> 'done')::int from report) = 3
  and (select (r -> 'projects' -> 0 ->> 'total')::int from report) = 4);

select check_that('by month, a month is one bar',
  jsonb_array_length(public.work_report('2026-10-04', '2026-10-17', 'month') -> 'buckets') = 1);

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
