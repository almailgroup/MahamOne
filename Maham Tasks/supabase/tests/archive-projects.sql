-- ---------------------------------------------------------------------------
-- Archiving a project.
--
-- The two things worth pinning: it is refused while work is still open in
-- there, and it destroys nothing. Archiving is the answer to "we have
-- finished with this" that deleting is not.
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
  ('00000000-0000-4000-8000-0000000000a1', 'boss@example.test'),
  ('00000000-0000-4000-8000-0000000000a2', 'hand@example.test');

alter table public.profiles disable trigger profiles_guard_role_change;
update public.profiles set role = 'admin'
 where id = '00000000-0000-4000-8000-0000000000a1';
alter table public.profiles enable trigger profiles_guard_role_change;

insert into public.projects (id, name, created_by)
values ('11111111-1111-4111-8111-0000000000a1', 'Warehouse Move',
        '00000000-0000-4000-8000-0000000000a1');

insert into public.tasks (id, project_id, title, status, created_by)
values
  ('22222222-2222-4222-8222-0000000000a1', '11111111-1111-4111-8111-0000000000a1',
   'Move the racking', 'done', '00000000-0000-4000-8000-0000000000a1'),
  ('22222222-2222-4222-8222-0000000000a2', '11111111-1111-4111-8111-0000000000a1',
   'Return the keys', 'in_progress', '00000000-0000-4000-8000-0000000000a1');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);

-- --- not while there is work in it ------------------------------------------
do $$
declare
  complaint text;
begin
  begin
    perform public.set_project_archived('11111111-1111-4111-8111-0000000000a1', true);
  exception when others then
    complaint := sqlerrm;
  end;

  perform check_that(
    'a project with open work cannot be archived',
    complaint like '%1 task(s) open%',
    coalesce(complaint, 'it was allowed'));
end $$;

select check_that(
  'and it is still live',
  (select archived_at is null from public.projects
    where id = '11111111-1111-4111-8111-0000000000a1'));

-- --- once the work is finished ----------------------------------------------
update public.tasks set status = 'done'
 where id = '22222222-2222-4222-8222-0000000000a2';

select public.set_project_archived('11111111-1111-4111-8111-0000000000a1', true);

select check_that(
  'a finished project can be archived',
  (select archived_at is not null from public.projects
    where id = '11111111-1111-4111-8111-0000000000a1'));

select check_that(
  'and nothing of it is destroyed',
  (select count(*) from public.tasks
    where project_id = '11111111-1111-4111-8111-0000000000a1') = 2,
  (select count(*)::text from public.tasks
    where project_id = '11111111-1111-4111-8111-0000000000a1'));

select check_that(
  'and it can still be read',
  (select name from public.projects
    where id = '11111111-1111-4111-8111-0000000000a1') = 'Warehouse Move');

-- --- and brought back --------------------------------------------------------
select public.set_project_archived('11111111-1111-4111-8111-0000000000a1', false);

select check_that(
  'archiving is reversible',
  (select archived_at is null from public.projects
    where id = '11111111-1111-4111-8111-0000000000a1'));

-- --- who may do it ------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a2', true);

do $$
declare
  complaint text;
begin
  begin
    perform public.set_project_archived('11111111-1111-4111-8111-0000000000a1', true);
  exception when others then
    complaint := sqlerrm;
  end;

  perform check_that(
    'a member cannot archive a project',
    complaint is not null,
    coalesce(complaint, 'it was allowed'));
end $$;

reset role;

select check_that(
  'and it really is still live',
  (select archived_at is null from public.projects
    where id = '11111111-1111-4111-8111-0000000000a1'));

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
