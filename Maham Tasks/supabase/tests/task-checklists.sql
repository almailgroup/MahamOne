-- ---------------------------------------------------------------------------
-- Who may read and change a task's steps.
--
-- The answer is "exactly whoever may read and change the task", and that is
-- the whole point: the steps carry no rules of their own. These checks exist
-- to keep it that way, because a checklist is the kind of thing that
-- quietly grows a policy of its own later.
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
  ('00000000-0000-4000-8000-0000000000f1', 'boss@example.test'),
  ('00000000-0000-4000-8000-0000000000f2', 'hand@example.test'),
  ('00000000-0000-4000-8000-0000000000f3', 'other@example.test');

alter table public.profiles disable trigger profiles_guard_role_change;
update public.profiles set role = 'admin'
 where id = '00000000-0000-4000-8000-0000000000f1';
alter table public.profiles enable trigger profiles_guard_role_change;

select check_that(
  'the fixture admin really is an admin',
  (select role = 'admin' from public.profiles
    where id = '00000000-0000-4000-8000-0000000000f1'));

insert into public.projects (id, name, created_by)
values ('11111111-1111-4111-8111-0000000000f1', 'Banking',
        '00000000-0000-4000-8000-0000000000f1');

insert into public.tasks (id, project_id, title, status, created_by)
values ('22222222-2222-4222-8222-0000000000f1',
        '11111111-1111-4111-8111-0000000000f1',
        'Meet with Kuwait banks', 'todo',
        '00000000-0000-4000-8000-0000000000f1');

insert into public.task_assignments (task_id, user_id)
values ('22222222-2222-4222-8222-0000000000f1', '00000000-0000-4000-8000-0000000000f2');

insert into public.task_checklist_items (id, task_id, content, position, created_by)
values
  ('33333333-3333-4333-8333-0000000000f1', '22222222-2222-4222-8222-0000000000f1',
   'Bring the signatory list', 0, '00000000-0000-4000-8000-0000000000f1'),
  ('33333333-3333-4333-8333-0000000000f2', '22222222-2222-4222-8222-0000000000f1',
   'Bring the trade licence', 1024, '00000000-0000-4000-8000-0000000000f1');

-- --- the member doing the work ----------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000f2', true);

do $$
declare
  seen integer;
  changed integer;
begin
  select count(*) into seen from public.task_checklist_items;
  perform check_that('somebody on the task sees its steps', seen = 2, seen::text);

  update public.task_checklist_items set done = true
   where id = '33333333-3333-4333-8333-0000000000f1';
  get diagnostics changed = row_count;
  perform check_that('and can tick one off', changed = 1, changed::text);

  -- Assigned means can_edit_task here as everywhere else in this schema:
  -- somebody doing the work may also change what the work is made of.
  update public.task_checklist_items set content = 'Bring the signatory list and the stamp'
   where id = '33333333-3333-4333-8333-0000000000f1';
  get diagnostics changed = row_count;
  perform check_that('and may plan them, as they may edit the task', changed = 1, changed::text);
end $$;

-- --- somebody with no part in it ---------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000f3', true);

do $$
declare
  seen integer;
  changed integer;
begin
  select count(*) into seen from public.task_checklist_items;
  perform check_that('somebody not on the task sees no steps', seen = 0, seen::text);

  update public.task_checklist_items set done = true
   where id = '33333333-3333-4333-8333-0000000000f2';
  get diagnostics changed = row_count;
  perform check_that('and can tick nothing', changed = 0, changed::text);

  begin
    insert into public.task_checklist_items (task_id, content, created_by)
    values ('22222222-2222-4222-8222-0000000000f1', 'Sneak this in',
            '00000000-0000-4000-8000-0000000000f3');
    perform check_that('and cannot add one', false, 'it was allowed');
  exception when insufficient_privilege then
    perform check_that('and cannot add one', true, 'refused');
  end;
end $$;

-- --- a manager in the project, on neither the task nor its authorship --------
-- Being a manager is not by itself a way into a project: can_view_project
-- admits an admin, a member of the project, or whoever created it. So this
-- one is put in the project as well, which is the real shape of somebody
-- who can see a task they are not on.
reset role;
alter table public.profiles disable trigger profiles_guard_role_change;
update public.profiles set role = 'manager'
 where id = '00000000-0000-4000-8000-0000000000f3';
alter table public.profiles enable trigger profiles_guard_role_change;

insert into public.project_members (project_id, user_id)
values ('11111111-1111-4111-8111-0000000000f1', '00000000-0000-4000-8000-0000000000f3');
set local role authenticated;

do $$
declare
  seen integer;
  changed integer;
begin
  select count(*) into seen from public.task_checklist_items;
  perform check_that('a manager sees the steps of any task', seen = 2, seen::text);

  update public.task_checklist_items set content = 'Bring the board resolution'
   where id = '33333333-3333-4333-8333-0000000000f2';
  get diagnostics changed = row_count;

  -- The same predicate the task's own update policy uses. An earlier draft
  -- of these policies said only can_edit_task, which would have let a
  -- manager edit a task and not its steps.
  perform check_that('and may change them, as they may change the task', changed = 1, changed::text);
end $$;

reset role;

-- --- and the steps go with the task ------------------------------------------
delete from public.tasks where id = '22222222-2222-4222-8222-0000000000f1';

select check_that(
  'deleting a task takes its steps with it',
  (select count(*) from public.task_checklist_items) = 0,
  (select count(*)::text from public.task_checklist_items));

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
