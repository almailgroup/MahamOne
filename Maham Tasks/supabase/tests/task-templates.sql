-- ---------------------------------------------------------------------------
-- Task templates: everybody can start from one, planners keep them.
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
  ('00000000-0000-4000-8000-0000000041a1', 'admin@example.test');
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000041b1', 'lead@example.test'),
  ('00000000-0000-4000-8000-0000000041c1', 'doer@example.test');

alter table public.profiles disable trigger profiles_guard_role_change;
update public.profiles set role = 'manager'
 where id = '00000000-0000-4000-8000-0000000041b1';
alter table public.profiles enable trigger profiles_guard_role_change;

set local role authenticated;

-- --- a manager keeps one ---------------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000041b1', true);

do $$
begin
  insert into public.task_templates (id, name, title, priority, steps, due_in_working_days) values
    ('44444444-4444-4444-8444-0000000041a1', 'Month-end payroll', 'Run payroll', 'high',
     array['Collect timesheets', 'Check overtime', 'Send to the bank'], 3);
  perform check_that('a manager saves a template', true);
exception when others then
  perform check_that('a manager saves a template', false, sqlerrm);
end $$;

select check_that('…recorded as theirs',
  (select created_by from public.task_templates where id = '44444444-4444-4444-8444-0000000041a1')
    = '00000000-0000-4000-8000-0000000041b1');

do $$
begin
  insert into public.task_templates (name, title, steps)
  values ('Too long', 'Fifty-one steps', array_fill('step'::text, array[51]));
  perform check_that('fifty steps at most', false, 'it was accepted');
exception when check_violation then
  perform check_that('fifty steps at most', true, sqlerrm);
end $$;

do $$
begin
  insert into public.task_templates (name, title) values ('  ', 'Nameless');
  perform check_that('a template needs a name', false, 'it was accepted');
exception when check_violation then
  perform check_that('a template needs a name', true, sqlerrm);
end $$;

-- --- a member uses it, and cannot change it ----------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000041c1', true);

select check_that('a member reads the templates',
  (select steps from public.task_templates where id = '44444444-4444-4444-8444-0000000041a1')
    = array['Collect timesheets', 'Check overtime', 'Send to the bank']);

do $$
begin
  insert into public.task_templates (name, title) values ('Mine', 'Mine');
  perform check_that('a member cannot add one', false, 'it was accepted');
exception when insufficient_privilege then
  perform check_that('a member cannot add one', true, sqlerrm);
end $$;

update public.task_templates set name = 'Changed';
delete from public.task_templates;
select check_that('nor change or remove one',
  (select name from public.task_templates where id = '44444444-4444-4444-8444-0000000041a1')
    = 'Month-end payroll');

-- --- an admin removes it ---------------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000041a1', true);
delete from public.task_templates where id = '44444444-4444-4444-8444-0000000041a1';
select check_that('an admin removes one',
  (select count(*) from public.task_templates) = 0);

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
