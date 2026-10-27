-- ---------------------------------------------------------------------------
-- Recurring tasks, checked where the rule lives.
--
-- The whole of recurrence is one trigger in the database, so this is where it
-- is tested: apply the schema to a plain Postgres and drive it.
--
--   psql -f supabase/tests/shim.sql -f <every migration> -f this file
--
-- NEVER run this against the production project. It writes and deletes rows.
-- ---------------------------------------------------------------------------

begin;

create temporary table results (name text, ok boolean, detail text);

create or replace function check_that(name text, ok boolean, detail text default '')
returns void language sql as $$
  insert into results values (name, ok, detail);
$$;

-- --- a workspace ----------------------------------------------------------
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'boss@example.test'),
  ('00000000-0000-4000-8000-00000000000b', 'hand@example.test');

-- profiles_guard_role_change exists to stop exactly this, so it is turned off
-- for the one statement that sets up the fixture. Leaving it on made an
-- earlier test pass for the wrong reason: the role never changed, so the
-- "admin" in it was a member and the gate below was never really tested.
alter table public.profiles disable trigger profiles_guard_role_change;
update public.profiles set role = 'admin'
 where id = '00000000-0000-4000-8000-00000000000a';
alter table public.profiles enable trigger profiles_guard_role_change;

-- Proof the fixture is what it claims to be, before anything relies on it.
select check_that(
  'the fixture admin really is an admin',
  (select role = 'admin' from public.profiles
    where id = '00000000-0000-4000-8000-00000000000a'),
  (select role::text from public.profiles
    where id = '00000000-0000-4000-8000-00000000000a'));

insert into public.projects (id, name, created_by)
values ('11111111-1111-4111-8111-00000000000a', 'Accounts',
        '00000000-0000-4000-8000-00000000000a');

-- A monthly task, due a fortnight ago, assigned to somebody.
insert into public.tasks (id, project_id, title, status, due_at, created_by,
                          repeat_every, repeat_interval)
values ('22222222-2222-4222-8222-00000000000a',
        '11111111-1111-4111-8111-00000000000a',
        'Reconcile the freight account', 'todo',
        now() - interval '14 days',
        '00000000-0000-4000-8000-00000000000a', 'month', 1);

insert into public.task_assignments (task_id, user_id)
values ('22222222-2222-4222-8222-00000000000a',
        '00000000-0000-4000-8000-00000000000b');

-- --- closing it opens the next --------------------------------------------
-- As the admin: only a manager or admin may close a task, and the trigger
-- that enforces that reads auth.uid(), which here is whatever a test says.
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000000a', true);

update public.tasks set status = 'done'
 where id = '22222222-2222-4222-8222-00000000000a';

select check_that(
  'closing a repeating task opens exactly one more',
  (select count(*) from public.tasks
    where title = 'Reconcile the freight account' and status = 'todo') = 1,
  (select count(*)::text from public.tasks
    where title = 'Reconcile the freight account'));

select check_that(
  'the next one is due in the future, not already late',
  (select due_at > now() from public.tasks
    where title = 'Reconcile the freight account' and status = 'todo'),
  (select due_at::text from public.tasks
    where title = 'Reconcile the freight account' and status = 'todo'));

select check_that(
  'the next one is a month on from the last, not from today',
  (select date_trunc('day', due_at) = date_trunc('day', now() - interval '14 days' + interval '1 month')
     from public.tasks
    where title = 'Reconcile the freight account' and status = 'todo'),
  (select due_at::text from public.tasks
    where title = 'Reconcile the freight account' and status = 'todo'));

select check_that(
  'the same people are on it',
  (select count(*) from public.task_assignments a
     join public.tasks t on t.id = a.task_id
    where t.title = 'Reconcile the freight account' and t.status = 'todo'
      and a.user_id = '00000000-0000-4000-8000-00000000000b') = 1);

select check_that(
  'the rule moves to the open one and leaves the closed one alone',
  (select repeat_every is null from public.tasks
    where id = '22222222-2222-4222-8222-00000000000a')
  and
  (select repeat_every = 'month' from public.tasks
    where title = 'Reconcile the freight account' and status = 'todo'));

-- --- closing it again must not open a third -------------------------------
update public.tasks set status = 'done', priority = 'high'
 where id = '22222222-2222-4222-8222-00000000000a';

select check_that(
  'touching a closed task again opens nothing',
  (select count(*) from public.tasks
    where title = 'Reconcile the freight account') = 2);

-- --- a task that does not repeat ------------------------------------------
insert into public.tasks (id, project_id, title, status, due_at, created_by)
values ('22222222-2222-4222-8222-00000000000b',
        '11111111-1111-4111-8111-00000000000a',
        'One-off signature', 'todo', now() + interval '1 day',
        '00000000-0000-4000-8000-00000000000a');

update public.tasks set status = 'done'
 where id = '22222222-2222-4222-8222-00000000000b';

select check_that(
  'a task with no rule stays closed and alone',
  (select count(*) from public.tasks where title = 'One-off signature') = 1);

-- --- a long-abandoned daily task ------------------------------------------
insert into public.tasks (id, project_id, title, status, due_at, created_by,
                          repeat_every, repeat_interval)
values ('22222222-2222-4222-8222-00000000000c',
        '11111111-1111-4111-8111-00000000000a',
        'Daily cash count', 'todo', now() - interval '400 days',
        '00000000-0000-4000-8000-00000000000a', 'day', 1);

update public.tasks set status = 'done'
 where id = '22222222-2222-4222-8222-00000000000c';

select check_that(
  'a rule abandoned for a year still lands in the future',
  (select due_at > now() from public.tasks
    where title = 'Daily cash count' and status = 'todo'),
  (select due_at::text from public.tasks
    where title = 'Daily cash count' and status = 'todo'));

-- --- the constraints ------------------------------------------------------
do $$
begin
  begin
    insert into public.tasks (project_id, title, created_by, repeat_every)
    values ('11111111-1111-4111-8111-00000000000a', 'No date', 
            '00000000-0000-4000-8000-00000000000a', 'week');
    perform check_that('a repeat with no due date is refused', false, 'it was accepted');
  exception when check_violation then
    perform check_that('a repeat with no due date is refused', true);
  end;

  begin
    insert into public.tasks (project_id, title, created_by, due_at, repeat_every)
    values ('11111111-1111-4111-8111-00000000000a', 'Nonsense unit',
            '00000000-0000-4000-8000-00000000000a', now(), 'fortnight');
    perform check_that('an unknown unit is refused', false, 'it was accepted');
  exception when check_violation then
    perform check_that('an unknown unit is refused', true);
  end;
end $$;

-- --- results --------------------------------------------------------------
select
  case when ok then 'PASS' else 'FAIL' end as result,
  name,
  detail
from results
order by ok, name;

-- `is not true` rather than `not ok`: a check whose subquery found no row at
-- all is NULL, and counting only false would report a silent nothing as a
-- pass.
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
