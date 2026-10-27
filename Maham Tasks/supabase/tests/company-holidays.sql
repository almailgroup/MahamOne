-- ---------------------------------------------------------------------------
-- Company holidays: everybody reads them, only an admin changes them.
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

-- The first account in a fresh database becomes its admin.
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000036a1', 'admin@example.test');
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000036b1', 'lead@example.test'),
  ('00000000-0000-4000-8000-0000000036c1', 'hand@example.test');

alter table public.profiles disable trigger profiles_guard_role_change;
update public.profiles set role = 'manager'
 where id = '00000000-0000-4000-8000-0000000036b1';
alter table public.profiles enable trigger profiles_guard_role_change;

set local role authenticated;

-- --- an admin --------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000036a1', true);

do $$
begin
  insert into public.company_holidays (day, name) values
    ('2027-02-25', 'National Day'),
    ('2027-02-26', 'Liberation Day');
  perform check_that('an admin adds holidays', true);
exception when others then
  perform check_that('an admin adds holidays', false, sqlerrm);
end $$;

select check_that(
  '…recorded as theirs',
  (select count(*) from public.company_holidays
    where created_by = '00000000-0000-4000-8000-0000000036a1') = 2);

do $$
begin
  update public.company_holidays set name = 'Liberation Day (observed)'
   where day = '2027-02-26';
  perform check_that('an admin renames one', true);
exception when others then
  perform check_that('an admin renames one', false, sqlerrm);
end $$;

do $$
begin
  insert into public.company_holidays (day, name) values ('2027-03-01', '   ');
  perform check_that('a holiday needs a name', false, 'it was accepted');
exception when check_violation then
  perform check_that('a holiday needs a name', true, sqlerrm);
end $$;

-- --- a manager -------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000036b1', true);

select check_that(
  'a manager sees the holidays',
  (select count(*) from public.company_holidays) = 2);

do $$
begin
  insert into public.company_holidays (day, name) values ('2027-03-02', 'Long weekend');
  perform check_that('a manager cannot add one', false, 'it was accepted');
exception when insufficient_privilege then
  perform check_that('a manager cannot add one', true, sqlerrm);
end $$;

-- --- a member --------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000036c1', true);

select check_that(
  'a member sees the holidays too — the calendar needs them',
  (select count(*) from public.company_holidays) = 2);

update public.company_holidays set name = 'Day off' where day = '2027-02-25';
select check_that(
  'a member cannot rename one',
  (select name from public.company_holidays where day = '2027-02-25') = 'National Day');

delete from public.company_holidays where day = '2027-02-25';
select check_that(
  'or remove one',
  (select count(*) from public.company_holidays) = 2);

-- --- the admin again -------------------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000036a1', true);

delete from public.company_holidays where day between '2027-02-25' and '2027-02-26';
select check_that(
  'an admin removes a run of days at once',
  (select count(*) from public.company_holidays) = 0);

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
