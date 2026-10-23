-- ---------------------------------------------------------------------------
-- Waiting on: planners link tasks, nobody makes a circle, lists can count
-- what a task waits on, and finishing the last thing tells the people waiting.
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
  ('00000000-0000-4000-8000-0000000040a1', 'admin@example.test');
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000040b1', 'lead@example.test'),
  ('00000000-0000-4000-8000-0000000040c1', 'doer@example.test');

alter table public.profiles disable trigger profiles_guard_role_change;
update public.profiles set role = 'manager'
 where id = '00000000-0000-4000-8000-0000000040b1';
alter table public.profiles enable trigger profiles_guard_role_change;

insert into public.projects (id, name, created_by) values
  ('11111111-1111-4111-8111-0000000040a1', 'Office move', '00000000-0000-4000-8000-0000000040b1');

-- quote → deposit → keys: the deposit waits on the quote, the keys on both.
insert into public.tasks (id, project_id, title, status, created_by) values
  ('22222222-2222-4222-8222-0000000040a1', '11111111-1111-4111-8111-0000000040a1', 'Get the quote approved', 'todo', '00000000-0000-4000-8000-0000000040b1'),
  ('22222222-2222-4222-8222-0000000040a2', '11111111-1111-4111-8111-0000000040a1', 'Pay the deposit', 'todo', '00000000-0000-4000-8000-0000000040b1'),
  ('22222222-2222-4222-8222-0000000040a3', '11111111-1111-4111-8111-0000000040a1', 'Collect the keys', 'todo', '00000000-0000-4000-8000-0000000040b1');
insert into public.task_assignments (task_id, user_id) values
  ('22222222-2222-4222-8222-0000000040a2', '00000000-0000-4000-8000-0000000040c1');

set local role authenticated;

-- --- the manager links them ----------------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000040b1', true);

do $$
begin
  insert into public.task_dependencies (task_id, blocked_by) values
    ('22222222-2222-4222-8222-0000000040a2', '22222222-2222-4222-8222-0000000040a1'),
    ('22222222-2222-4222-8222-0000000040a3', '22222222-2222-4222-8222-0000000040a2');
  perform check_that('a manager links tasks', true);
exception when others then
  perform check_that('a manager links tasks', false, sqlerrm);
end $$;

do $$
begin
  insert into public.task_dependencies (task_id, blocked_by) values
    ('22222222-2222-4222-8222-0000000040a1', '22222222-2222-4222-8222-0000000040a3');
  perform check_that('a circle, however far round, is refused', false, 'it was accepted');
exception when check_violation then
  perform check_that('a circle, however far round, is refused', sqlerrm = 'task.dependencyCycle', sqlerrm);
end $$;

do $$
begin
  insert into public.task_dependencies (task_id, blocked_by) values
    ('22222222-2222-4222-8222-0000000040a1', '22222222-2222-4222-8222-0000000040a1');
  perform check_that('a task cannot wait on itself', false, 'it was accepted');
exception when check_violation then
  perform check_that('a task cannot wait on itself', true, sqlerrm);
end $$;

select check_that('a list can count what a task waits on',
  (select public.waiting_on(t) from public.tasks t where t.id = '22222222-2222-4222-8222-0000000040a2') = 1
  and (select public.waiting_on(t) from public.tasks t where t.id = '22222222-2222-4222-8222-0000000040a1') = 0);

-- --- the member on the deposit ---------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000040c1', true);

select check_that('a member sees what their task waits on',
  (select count(*) from public.task_dependencies
    where task_id = '22222222-2222-4222-8222-0000000040a2') = 1);

do $$
begin
  insert into public.task_dependencies (task_id, blocked_by) values
    ('22222222-2222-4222-8222-0000000040a3', '22222222-2222-4222-8222-0000000040a1');
  perform check_that('a member cannot link tasks', false, 'it was accepted');
exception when insufficient_privilege then
  perform check_that('a member cannot link tasks', true, sqlerrm);
end $$;

delete from public.task_dependencies;
select check_that('nor unlink them',
  (select count(*) from public.task_dependencies
    where task_id = '22222222-2222-4222-8222-0000000040a2') = 1);

-- --- finishing the quote ---------------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000040b1', true);
update public.tasks set status = 'done' where id = '22222222-2222-4222-8222-0000000040a1';

reset role;

select check_that('the person on the deposit is told it can go ahead',
  exists (select 1 from public.notifications
           where user_id = '00000000-0000-4000-8000-0000000040c1'
             and type = 'task_unblocked'
             and task_id = '22222222-2222-4222-8222-0000000040a2'
             and title = 'Ready to go: Pay the deposit'
             and body = 'Get the quote approved is done.'),
  (select string_agg(type || ':' || title, ', ') from public.notifications));

select check_that('…and the deposit no longer counts as waiting',
  (select public.waiting_on(t) from public.tasks t where t.id = '22222222-2222-4222-8222-0000000040a2') = 0);

select check_that('the keys still wait, on the deposit',
  (select public.waiting_on(t) from public.tasks t where t.id = '22222222-2222-4222-8222-0000000040a3') = 1);

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
