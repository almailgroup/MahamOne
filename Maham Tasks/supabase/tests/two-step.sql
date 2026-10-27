-- ---------------------------------------------------------------------------
-- Two-step sign-in: a password alone is a member's session for anybody who
-- has an authenticator app, and changes nothing for anybody who has not.
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
  ('00000000-0000-4000-8000-0000000038a1', 'careful-admin@example.test');
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000038a2', 'other-admin@example.test'),
  ('00000000-0000-4000-8000-0000000038b1', 'lead@example.test');

alter table public.profiles disable trigger profiles_guard_role_change;
update public.profiles set role = 'admin'
 where id = '00000000-0000-4000-8000-0000000038a2';
update public.profiles set role = 'manager'
 where id = '00000000-0000-4000-8000-0000000038b1';
alter table public.profiles enable trigger profiles_guard_role_change;

-- The careful admin has an authenticator app; the manager started adding
-- one and never finished.
insert into auth.mfa_factors (user_id, status) values
  ('00000000-0000-4000-8000-0000000038a1', 'verified'),
  ('00000000-0000-4000-8000-0000000038b1', 'unverified');

set local role authenticated;

-- --- the admin with an app, password only ------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000038a1', true);
select set_config('request.jwt.claims', '{"aal": "aal1"}', true);

select check_that('with the password alone, the second step is pending',
  public.second_step_pending());
select check_that('…and the admin counts as a member',
  public.current_user_role() = 'member', public.current_user_role()::text);
select check_that('…so is_admin() says no',
  not public.is_admin());
select check_that('…and so does is_manager_or_admin()',
  not public.is_manager_or_admin());

do $$
begin
  insert into public.company_holidays (day, name) values ('2027-04-01', 'Test');
  perform check_that('an admin-only write is refused', false, 'it was accepted');
exception when insufficient_privilege then
  perform check_that('an admin-only write is refused', true, sqlerrm);
end $$;

update public.profiles set role = 'admin'
 where id = '00000000-0000-4000-8000-0000000038b1';
select check_that('nor can they promote anybody',
  (select role from public.profiles where id = '00000000-0000-4000-8000-0000000038b1') = 'manager');

-- No claim at all is a password session too.
select set_config('request.jwt.claims', '', true);
select check_that('a token without an aal claim is not taken for the second step',
  public.current_user_role() = 'member');

-- --- the same admin, after the code ------------------------------------------

select set_config('request.jwt.claims', '{"aal": "aal2"}', true);

select check_that('after the code, they are an admin again',
  public.current_user_role() = 'admin' and public.is_admin());

do $$
begin
  insert into public.company_holidays (day, name) values ('2027-04-01', 'Test');
  perform check_that('…and an admin-only write goes through', true);
exception when others then
  perform check_that('…and an admin-only write goes through', false, sqlerrm);
end $$;

-- --- people without an app are untouched -------------------------------------

select set_config('request.jwt.claims', '{"aal": "aal1"}', true);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000038a2', true);
select check_that('an admin with no app is still an admin on a password',
  public.is_admin() and not public.second_step_pending());

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000038b1', true);
select check_that('an app that was never confirmed does not count',
  public.current_user_role() = 'manager' and not public.second_step_pending());

reset role;

-- --- the server itself ---------------------------------------------------------

select set_config('request.jwt.claim.sub', '', true);
select check_that('with no caller there is no role and nothing pending',
  public.current_user_role() is null and not public.second_step_pending());

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
