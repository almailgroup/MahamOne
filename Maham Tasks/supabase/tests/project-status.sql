-- ---------------------------------------------------------------------------
-- Who may say how a project is going, and who gets to read it.
--
-- Readable by anyone who can see the project; written by managers and admins
-- on it, as themselves; never edited; withdrawn only by whoever wrote it or
-- an admin. And project_health() counts what the caller can see and nothing
-- more.
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

-- a1 admin · m1 manager on the project · m2 manager not on it
-- u1 member on the project · u2 member not on it
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000005a1', 'admin@example.test'),
  ('00000000-0000-4000-8000-0000000005b1', 'lead@example.test'),
  ('00000000-0000-4000-8000-0000000005b2', 'other-lead@example.test'),
  ('00000000-0000-4000-8000-0000000005c1', 'hand@example.test'),
  ('00000000-0000-4000-8000-0000000005c2', 'outsider@example.test');

alter table public.profiles disable trigger profiles_guard_role_change;
update public.profiles set role = 'admin'
 where id = '00000000-0000-4000-8000-0000000005a1';
update public.profiles set role = 'manager'
 where id in ('00000000-0000-4000-8000-0000000005b1',
              '00000000-0000-4000-8000-0000000005b2');
alter table public.profiles enable trigger profiles_guard_role_change;

-- m1 creates the project, which makes them a member of it.
insert into public.projects (id, name, created_by) values
  ('77777777-7777-4777-8777-000000000001', 'Warehouse Move',
   '00000000-0000-4000-8000-0000000005b1'),
  ('77777777-7777-4777-8777-000000000002', '2025 Audit',
   '00000000-0000-4000-8000-0000000005b1');

update public.projects set archived_at = now()
 where id = '77777777-7777-4777-8777-000000000002';

insert into public.project_members (project_id, user_id, added_by) values
  ('77777777-7777-4777-8777-000000000001', '00000000-0000-4000-8000-0000000005c1',
   '00000000-0000-4000-8000-0000000005b1');

-- Two open tasks, one of them late, and one done.
insert into public.tasks (project_id, title, status, due_at, created_by) values
  ('77777777-7777-4777-8777-000000000001', 'Book the trucks', 'todo',
   now() - interval '2 days', '00000000-0000-4000-8000-0000000005b1'),
  ('77777777-7777-4777-8777-000000000001', 'Label the racks', 'in_progress',
   now() + interval '5 days', '00000000-0000-4000-8000-0000000005b1'),
  ('77777777-7777-4777-8777-000000000001', 'Sign the lease', 'done',
   now() - interval '9 days', '00000000-0000-4000-8000-0000000005b1');

set local role authenticated;

-- --- posting ---------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000005b1', true);

do $$
begin
  insert into public.project_status_updates (project_id, author_id, status, body)
  values ('77777777-7777-4777-8777-000000000001', '00000000-0000-4000-8000-0000000005b1',
          'at_risk', 'Customs are holding two containers until the permits arrive.');
  perform check_that('the manager running it can post an update', true);
exception when others then
  perform check_that('the manager running it can post an update', false, sqlerrm);
end $$;

do $$
begin
  insert into public.project_status_updates (project_id, author_id, status, body)
  values ('77777777-7777-4777-8777-000000000001', '00000000-0000-4000-8000-0000000005c1',
          'on_track', 'All fine.');
  perform check_that('but not in somebody else''s name', false, 'it was accepted');
exception when insufficient_privilege then
  perform check_that('but not in somebody else''s name', true, sqlerrm);
end $$;

do $$
begin
  insert into public.project_status_updates (project_id, author_id, status, body)
  values ('77777777-7777-4777-8777-000000000001', '00000000-0000-4000-8000-0000000005b1',
          'great', 'Going well.');
  perform check_that('only the three statuses exist', false, 'it was accepted');
exception when check_violation then
  perform check_that('only the three statuses exist', true, sqlerrm);
end $$;

do $$
begin
  insert into public.project_status_updates (project_id, author_id, status, body)
  values ('77777777-7777-4777-8777-000000000001', '00000000-0000-4000-8000-0000000005b1',
          'on_track', '   ');
  perform check_that('an update has to say something', false, 'it was accepted');
exception when check_violation then
  perform check_that('an update has to say something', true, sqlerrm);
end $$;

-- A member on the project reads it, but does not report on it.
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000005c1', true);

select check_that(
  'somebody working on the project can read how it is going',
  (select count(*) from public.project_status_updates
    where project_id = '77777777-7777-4777-8777-000000000001') = 1);

do $$
begin
  insert into public.project_status_updates (project_id, author_id, status, body)
  values ('77777777-7777-4777-8777-000000000001', '00000000-0000-4000-8000-0000000005c1',
          'on_track', 'Looks fine from here.');
  perform check_that('but a member cannot post one', false, 'it was accepted');
exception when insufficient_privilege then
  perform check_that('but a member cannot post one', true, sqlerrm);
end $$;

-- A manager who is not on it neither reads nor posts.
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000005b2', true);

select check_that(
  'a manager not on the project cannot read its updates',
  (select count(*) from public.project_status_updates) = 0);

do $$
begin
  insert into public.project_status_updates (project_id, author_id, status, body)
  values ('77777777-7777-4777-8777-000000000001', '00000000-0000-4000-8000-0000000005b2',
          'off_track', 'This looks bad.');
  perform check_that('or post one', false, 'it was accepted');
exception when insufficient_privilege then
  perform check_that('or post one', true, sqlerrm);
end $$;

-- Nor does a member who is not on it.
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000005c2', true);
select check_that(
  'and nor can anybody else',
  (select count(*) from public.project_status_updates) = 0);

-- --- never edited -------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000005b1', true);

do $$
begin
  update public.project_status_updates set status = 'on_track';
  perform check_that('an update cannot be rewritten after the fact', false, 'it was accepted');
exception when insufficient_privilege then
  perform check_that('an update cannot be rewritten after the fact', true, sqlerrm);
end $$;

-- --- the health of every live project ---------------------------------------
select check_that(
  'project_health carries the latest status and the work counts',
  (select latest_status = 'at_risk' and open_tasks = 2 and overdue_tasks = 1
     from public.project_health()
    where project_id = '77777777-7777-4777-8777-000000000001'),
  (select latest_status || ' / open ' || open_tasks || ' / late ' || overdue_tasks
     from public.project_health()
    where project_id = '77777777-7777-4777-8777-000000000001'));

select check_that(
  'and names who said it',
  (select latest_author = 'lead@example.test' from public.project_health()
    where project_id = '77777777-7777-4777-8777-000000000001'));

select check_that(
  'an archived project is not reported on',
  not exists (select 1 from public.project_health()
               where project_id = '77777777-7777-4777-8777-000000000002'));

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000005b2', true);
select check_that(
  'and a manager is only told about projects they are on',
  not exists (select 1 from public.project_health()
               where project_id = '77777777-7777-4777-8777-000000000001'));

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000005a1', true);
select check_that(
  'while an admin is told about every one',
  exists (select 1 from public.project_health()
           where project_id = '77777777-7777-4777-8777-000000000001'));

-- --- withdrawing ------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000005c1', true);
do $$
declare n integer;
begin
  delete from public.project_status_updates;
  get diagnostics n = row_count;
  perform check_that('a member cannot withdraw somebody''s update', n = 0, 'rows: ' || n);
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000005a1', true);
do $$
declare n integer;
begin
  delete from public.project_status_updates;
  get diagnostics n = row_count;
  perform check_that('an admin can', n = 1, 'rows: ' || n);
end $$;

reset role;

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
