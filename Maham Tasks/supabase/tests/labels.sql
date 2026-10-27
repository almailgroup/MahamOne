-- ---------------------------------------------------------------------------
-- Labels: everybody reads them, planners keep them and put them on tasks, and
-- a label on a task is only as visible as the task.
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
  ('00000000-0000-4000-8000-0000000039a1', 'admin@example.test');
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000039b1', 'lead@example.test'),
  ('00000000-0000-4000-8000-0000000039c1', 'on-it@example.test'),
  ('00000000-0000-4000-8000-0000000039d1', 'elsewhere@example.test');

alter table public.profiles disable trigger profiles_guard_role_change;
update public.profiles set role = 'manager'
 where id = '00000000-0000-4000-8000-0000000039b1';
alter table public.profiles enable trigger profiles_guard_role_change;

-- A project only the manager and one member are on, with a task in it. The
-- manager is a member by creating it, the other by being assigned the task.
insert into public.projects (id, name, created_by) values
  ('11111111-1111-4111-8111-0000000039a1', 'Bank rollout', '00000000-0000-4000-8000-0000000039b1');
insert into public.tasks (id, project_id, title, created_by) values
  ('22222222-2222-4222-8222-0000000039a1', '11111111-1111-4111-8111-0000000039a1',
   'Sign the mandate', '00000000-0000-4000-8000-0000000039b1');
insert into public.task_assignments (task_id, user_id) values
  ('22222222-2222-4222-8222-0000000039a1', '00000000-0000-4000-8000-0000000039c1');

set local role authenticated;

-- --- a manager keeps the labels, and puts one on the task -----------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000039b1', true);

do $$
begin
  insert into public.labels (id, name, colour) values
    ('33333333-3333-4333-8333-0000000039a1', 'Bank', 'blue');
  perform check_that('a manager adds a label', true);
exception when others then
  perform check_that('a manager adds a label', false, sqlerrm);
end $$;

do $$
begin
  insert into public.labels (name) values ('  bank ');
  perform check_that('the same word twice is refused', false, 'it was accepted');
exception when unique_violation then
  perform check_that('the same word twice is refused', true, sqlerrm);
end $$;

do $$
begin
  insert into public.labels (name, colour) values ('Late', 'amber');
  perform check_that('amber is not a label colour', false, 'it was accepted');
exception when check_violation then
  perform check_that('amber is not a label colour', true, sqlerrm);
end $$;

do $$
begin
  insert into public.task_labels (task_id, label_id) values
    ('22222222-2222-4222-8222-0000000039a1', '33333333-3333-4333-8333-0000000039a1');
  perform check_that('a manager labels a task', true);
exception when others then
  perform check_that('a manager labels a task', false, sqlerrm);
end $$;

-- --- the member on the task ---------------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000039c1', true);

select check_that('a member on the task sees its label',
  (select count(*) from public.task_labels) = 1);

do $$
begin
  insert into public.labels (name) values ('Mine');
  perform check_that('a member cannot add a label', false, 'it was accepted');
exception when insufficient_privilege then
  perform check_that('a member cannot add a label', true, sqlerrm);
end $$;

delete from public.task_labels;
select check_that('nor take one off a task',
  (select count(*) from public.task_labels) = 1);

update public.labels set name = 'Renamed';
select check_that('nor rename one',
  (select name from public.labels where id = '33333333-3333-4333-8333-0000000039a1') = 'Bank');

-- --- a member not on the project -----------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000039d1', true);

select check_that('someone off the project sees the label itself',
  (select count(*) from public.labels) = 1);
select check_that('…but not that it is on a task they cannot see',
  (select count(*) from public.task_labels) = 0);

-- --- removing a label takes it off every task ------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000039a1', true);
delete from public.labels where id = '33333333-3333-4333-8333-0000000039a1';
select check_that('an admin removes a label, and it leaves every task',
  (select count(*) from public.task_labels) = 0);

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
