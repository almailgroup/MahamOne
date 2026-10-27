-- ---------------------------------------------------------------------------
-- Who may write a fault, and who may read one.
--
-- Anybody signed in reports what went wrong in front of them; nobody but an
-- admin reads them back, because a message can carry a fragment of whatever
-- it failed on.
--
--   psql -f supabase/tests/shim.sql -f <every migration> -f this file
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
  ('00000000-0000-4000-8000-0000000000e1', 'boss@example.test'),
  ('00000000-0000-4000-8000-0000000000e2', 'hand@example.test');

alter table public.profiles disable trigger profiles_guard_role_change;
update public.profiles set role = 'admin'
 where id = '00000000-0000-4000-8000-0000000000e1';
alter table public.profiles enable trigger profiles_guard_role_change;

select check_that(
  'the fixture admin really is an admin',
  (select role = 'admin' from public.profiles
    where id = '00000000-0000-4000-8000-0000000000e1'));

-- --- reporting, as somebody signed in --------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e2', true);

insert into public.app_errors (user_id, source, message, route)
values ('00000000-0000-4000-8000-0000000000e2', 'browser', 'TypeError: x is not a function', '/today');

-- The insert above either worked or aborted this transaction, so reaching
-- here is the result. It cannot be read back from this role, by design; the
-- row count after `reset role` below is what confirms it landed.
select check_that('somebody signed in can report a fault', true, 'insert accepted');

-- --- but not as somebody else ---------------------------------------------
do $$
begin
  begin
    insert into public.app_errors (user_id, source, message, route)
    values ('00000000-0000-4000-8000-0000000000e1', 'browser', 'Not mine', '/today');
    perform check_that('a fault cannot be reported as somebody else', false, 'it was allowed');
  exception when insufficient_privilege then
    perform check_that('a fault cannot be reported as somebody else', true, 'refused');
  end;
end $$;

-- --- and cannot read any of them ------------------------------------------
do $$
declare
  seen integer;
begin
  begin
    select count(*) into seen from public.app_errors;
    perform check_that('the table itself is unreadable with a session', seen = 0, seen::text);
  exception when insufficient_privilege then
    perform check_that('the table itself is unreadable with a session', true, 'refused outright');
  end;
end $$;

do $$
begin
  begin
    perform * from public.recent_errors();
    perform check_that('a member cannot read the error log', false, 'it was allowed');
  exception when insufficient_privilege then
    perform check_that('a member cannot read the error log', true, 'refused');
  end;
end $$;

-- --- the admin can, and sees them grouped ---------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000e1', true);

-- The same fault twice more: it should read as one line seen three times.
insert into public.app_errors (user_id, source, message, route)
values
  ('00000000-0000-4000-8000-0000000000e1', 'browser', 'TypeError: x is not a function', '/today'),
  ('00000000-0000-4000-8000-0000000000e1', 'browser', 'TypeError: x is not a function', '/today');

do $$
declare
  lines integer;
  hits bigint;
begin
  select count(*), max(seen) into lines, hits from public.recent_errors();
  perform check_that('an admin reads the log', lines = 1, lines::text);
  perform check_that('and one fault hit three times is one line', hits = 3, hits::text);
end $$;

reset role;

-- --- and old ones are swept ------------------------------------------------
insert into public.app_errors (user_id, source, message, route, occurred_at)
values (null, 'server', 'Ancient failure', '/old', now() - interval '30 days');

do $$
declare
  removed integer;
  left_behind integer;
begin
  select public.purge_old_errors() into removed;
  select count(*) into left_behind from public.app_errors;

  perform check_that('an old fault is swept', removed = 1, removed::text);
  perform check_that('and a recent one is not', left_behind = 3, left_behind::text);
end $$;

-- --- results ---------------------------------------------------------------
select
  case when ok then 'PASS' else 'FAIL' end as result,
  name,
  detail
from results
order by ok, name;

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
