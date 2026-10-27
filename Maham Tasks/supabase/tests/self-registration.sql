-- ---------------------------------------------------------------------------
-- Accounts are added by an admin; nobody can sign themselves up.
--
-- Supabase writes an account's app_metadata itself, and only the service key
-- can add to it. A self sign-up arrives with nothing but its provider there;
-- the Team page's "Add teammate" records which admin added the person. Only
-- the second kind may become a profile — except the very first account, which
-- sets up an empty database and becomes its admin.
--
--   psql -f supabase/tests/shim.sql -f supabase/setup.sql -f this file
--
-- NEVER run this against the production project.
-- ---------------------------------------------------------------------------

begin;

create temporary table results (name text, ok boolean, detail text);

create or replace function check_that(name text, ok boolean, detail text default '')
returns void language sql as $$
  insert into results values (name, ok, detail);
$$;

-- What GoTrue writes for somebody signing themselves up with email.
create or replace function pg_temp.self_signup() returns jsonb
language sql as $$ select '{"provider": "email", "providers": ["email"]}'::jsonb $$;

-- Tries to create an account; returns the SQLSTATE it was refused with, or
-- null if it went in. A refused insert is rolled back with its sub-block.
create or replace function pg_temp.try_account(
  account uuid, address text, app_meta jsonb, user_meta jsonb default '{}'::jsonb
) returns text
language plpgsql as $$
begin
  insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data)
  values (account, address, app_meta, user_meta);
  return null;
exception when others then
  return sqlstate;
end;
$$;

-- --- an empty database -------------------------------------------------------

select check_that(
  'the first account in an empty database is let in',
  pg_temp.try_account('00000000-0000-4000-8000-0000000034a1', 'first@example.test',
                      pg_temp.self_signup()) is null);

select check_that(
  '…and becomes its admin',
  (select role::text from public.profiles
    where id = '00000000-0000-4000-8000-0000000034a1') = 'admin');

-- --- signing yourself up -----------------------------------------------------

select check_that(
  'after that, signing yourself up is refused',
  pg_temp.try_account('00000000-0000-4000-8000-0000000034b1', 'stranger@example.test',
                      pg_temp.self_signup()) = '42501');

select check_that(
  '…and leaves no account behind',
  not exists (select 1 from auth.users where id = '00000000-0000-4000-8000-0000000034b1')
  and not exists (select 1 from public.profiles where id = '00000000-0000-4000-8000-0000000034b1'));

select check_that(
  'naming an admin in user_metadata, which anyone can write, is not enough',
  pg_temp.try_account('00000000-0000-4000-8000-0000000034b2', 'clever@example.test',
                      pg_temp.self_signup(),
                      '{"added_by": "00000000-0000-4000-8000-0000000034a1"}'::jsonb) = '42501');

select check_that(
  'an account with no app_metadata at all is refused',
  pg_temp.try_account('00000000-0000-4000-8000-0000000034b3', 'bare@example.test',
                      '{}'::jsonb) = '42501');

-- --- added by an admin -------------------------------------------------------

select check_that(
  'an account an admin added is let in',
  pg_temp.try_account('00000000-0000-4000-8000-0000000034c1', 'new.hire@example.test',
                      pg_temp.self_signup()
                        || '{"added_by": "00000000-0000-4000-8000-0000000034a1"}'::jsonb) is null);

select check_that(
  '…as a member',
  (select role::text from public.profiles
    where id = '00000000-0000-4000-8000-0000000034c1') = 'member');

select check_that(
  'naming a member as the one who added you is refused',
  pg_temp.try_account('00000000-0000-4000-8000-0000000034b4', 'friend@example.test',
                      pg_temp.self_signup()
                        || '{"added_by": "00000000-0000-4000-8000-0000000034c1"}'::jsonb) = '42501');

select check_that(
  'naming nobody in particular is refused',
  pg_temp.try_account('00000000-0000-4000-8000-0000000034b5', 'ghost@example.test',
                      pg_temp.self_signup()
                        || '{"added_by": "00000000-0000-4000-8000-0000000034ff"}'::jsonb) = '42501');

select check_that(
  'a malformed value is refused with the same answer, not a cast error',
  pg_temp.try_account('00000000-0000-4000-8000-0000000034b6', 'odd@example.test',
                      pg_temp.self_signup() || '{"added_by": "admin"}'::jsonb) = '42501');

select check_that(
  'only the admin and the person they added have profiles',
  (select count(*) from public.profiles) = 2);

-- --- results ---------------------------------------------------------------

select
  case when ok then 'PASS' else 'FAIL' end as result,
  name,
  detail
from results
order by ok, name;

select count(*) filter (where ok is not true) as failures from results;

-- A failing check has to fail the run, not just appear in the table above.
do $$
declare failed integer;
begin
  select count(*) filter (where ok is not true) into failed from results;
  if failed > 0 then
    raise exception '% check(s) failed — see the table above', failed;
  end if;
end $$;

rollback;
