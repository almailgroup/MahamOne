-- ---------------------------------------------------------------------------
-- Accounts are Maham One's; being in Maham Tasks is accepting an invite.
--
-- On Maham One's database Maham Tasks puts nothing on auth.users: every
-- sign-up is a Maham One account and none is refused or touched here. A
-- Maham Tasks admin, signed in with two-step sign-in, invites people by
-- email (tasks.add_teammate), which never says whether a Maham One account
-- has that email. The invited person accepts by signing in to Maham Tasks
-- with a confirmed account that has it (tasks.join), within 30 days. Nobody
-- becomes admin by being first: the owner names the first admin with
-- tasks.add_first_admin().
--
--   psql -f supabase/tests/shim.sql -f ../supabase/migrations/20261212000000_maham_tasks.sql -f this file
--
-- NEVER run this against the production project.
-- ---------------------------------------------------------------------------

begin;

-- The shim makes profiles for the suites' accounts; here the rules
-- themselves are what is checked.
alter table auth.users disable trigger shim_profile;

create temporary table results (name text, ok boolean, detail text);

create or replace function check_that(name text, ok boolean, detail text default '')
returns void language sql as $$
  insert into results values (name, ok, detail);
$$;

-- What GoTrue writes for somebody signing themselves up with email.
create or replace function pg_temp.self_signup() returns jsonb
language sql as $$ select '{"provider": "email", "providers": ["email"]}'::jsonb $$;

-- Tries to create an account; returns the SQLSTATE it was refused with, or
-- null if it went in.
create or replace function pg_temp.try_account(
  account uuid, address text, app_meta jsonb, user_meta jsonb default '{}'::jsonb,
  confirmed boolean default true
) returns text
language plpgsql as $$
begin
  insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at)
  values (account, address, app_meta, user_meta, case when confirmed then now() end);
  return null;
exception when others then
  return sqlstate;
end;
$$;

create or replace function pg_temp.member(account uuid) returns text
language sql as $$ select role::text from tasks.profiles where id = account $$;

-- Signs in as somebody, with or without the second step.
create or replace function pg_temp.as_user(account uuid, second_step boolean default true)
returns void language sql as $$
  select set_config('request.jwt.claim.sub', account::text, true),
         set_config('request.jwt.claims',
                    case when second_step then '{"aal": "aal2"}' else '{"aal": "aal1"}' end, true);
$$;

-- Runs one admin call, returning the SQLSTATE it was refused with or its status.
create or replace function pg_temp.invite(address text, who text default null, as_role tasks.user_role default 'member')
returns text language plpgsql as $$
begin
  return tasks.add_teammate(address, who, as_role) ->> 'status';
exception when others then
  return sqlstate;
end;
$$;

-- --- an empty Maham Tasks ----------------------------------------------------

select check_that(
  'the first account is let in, as every Maham One account is',
  pg_temp.try_account('00000000-0000-4000-8000-0000000034a1', 'first@example.test',
                      pg_temp.self_signup()) is null);

select check_that(
  '…and is not made admin, nor anything, for being first',
  pg_temp.member('00000000-0000-4000-8000-0000000034a1') is null);

select tasks.add_first_admin('FIRST@example.test');

select check_that(
  'the owner names the first admin',
  pg_temp.member('00000000-0000-4000-8000-0000000034a1') = 'admin');

-- --- signing yourself up -----------------------------------------------------

select check_that(
  'signing yourself up makes a Maham One account, never refused',
  pg_temp.try_account('00000000-0000-4000-8000-0000000034b1', 'stranger@example.test',
                      pg_temp.self_signup()) is null);

select check_that(
  '…which is there',
  exists (select 1 from auth.users where id = '00000000-0000-4000-8000-0000000034b1'));

select check_that(
  '…and nothing in Maham Tasks',
  pg_temp.member('00000000-0000-4000-8000-0000000034b1') is null);

select check_that(
  'naming an admin in app_metadata gets you nothing either',
  pg_temp.try_account('00000000-0000-4000-8000-0000000034b2', 'clever@example.test',
                      pg_temp.self_signup()
                        || '{"added_by": "00000000-0000-4000-8000-0000000034a1"}'::jsonb) is null
  and pg_temp.member('00000000-0000-4000-8000-0000000034b2') is null);

select pg_temp.as_user('00000000-0000-4000-8000-0000000034b2');

select check_that(
  'joining without an invite gets you nothing',
  not tasks.join() and pg_temp.member('00000000-0000-4000-8000-0000000034b2') is null);

-- --- invited by an admin -----------------------------------------------------

select pg_temp.as_user('00000000-0000-4000-8000-0000000034a1', false);

select check_that(
  'an admin without the second step invites nobody',
  pg_temp.invite('stranger@example.test') = '42501');

select pg_temp.as_user('00000000-0000-4000-8000-0000000034a1');

select check_that(
  'an admin invites somebody who has an account, saying only "invited"',
  pg_temp.invite('Stranger@example.test', 'Made-up Stranger') = 'invited');

select check_that(
  '…as for an address nobody has, so nobody learns who has an account',
  pg_temp.invite('later@example.test', 'Made-up Later', 'manager') = 'invited');

select check_that(
  '…and the invite alone makes nobody a member',
  pg_temp.member('00000000-0000-4000-8000-0000000034b1') is null);

select pg_temp.as_user('00000000-0000-4000-8000-0000000034b1');

select check_that(
  'the invited person joins by signing in',
  tasks.join());

select check_that(
  '…as a member, with the name the admin gave, the invite used up',
  pg_temp.member('00000000-0000-4000-8000-0000000034b1') = 'member'
  and (select full_name from tasks.profiles where id = '00000000-0000-4000-8000-0000000034b1') = 'Made-up Stranger'
  and not exists (select 1 from tasks.invites where email = 'stranger@example.test'));

select pg_temp.as_user('00000000-0000-4000-8000-0000000034a1');

select check_that(
  'inviting somebody already in says so',
  pg_temp.invite('STRANGER@example.test') = 'already');

-- Made later, and not confirmed yet.
select check_that(
  'an invited address signed up later is let in',
  pg_temp.try_account('00000000-0000-4000-8000-0000000034d1', 'later@example.test',
                      pg_temp.self_signup(), '{}'::jsonb, false) is null);

select pg_temp.as_user('00000000-0000-4000-8000-0000000034d1');

select check_that(
  '…but joins only once its email is confirmed',
  not tasks.join() and pg_temp.member('00000000-0000-4000-8000-0000000034d1') is null);

update auth.users set email_confirmed_at = now() where id = '00000000-0000-4000-8000-0000000034d1';

select check_that(
  '…and then as invited',
  tasks.join() and pg_temp.member('00000000-0000-4000-8000-0000000034d1') = 'manager');

-- An invite that lapsed.
insert into tasks.invites (email, expires_at) values ('late@example.test', now() - interval '1 day');
select pg_temp.try_account('00000000-0000-4000-8000-0000000034e1', 'late@example.test', pg_temp.self_signup());
select pg_temp.as_user('00000000-0000-4000-8000-0000000034e1');

select check_that(
  'an invite past its 30 days lets nobody in',
  not tasks.join() and pg_temp.member('00000000-0000-4000-8000-0000000034e1') is null);

select pg_temp.as_user('00000000-0000-4000-8000-0000000034b1');

select check_that(
  'a member invites nobody',
  pg_temp.invite('ghost@example.test') = '42501');

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '', true);

select check_that(
  'only the admin and the people who accepted have profiles',
  (select count(*) from tasks.profiles) = 3);

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
