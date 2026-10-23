-- ---------------------------------------------------------------------------
-- Milestones: planners set them, everybody on the project sees them, a task
-- sits only under one of its own project's, and members cannot move work
-- between them.
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
  ('00000000-0000-4000-8000-0000000044a1', 'admin@example.test');
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000044b1', 'lead@example.test'),
  ('00000000-0000-4000-8000-0000000044c1', 'doer@example.test'),
  ('00000000-0000-4000-8000-0000000044d1', 'outsider@example.test');

alter table public.profiles disable trigger profiles_guard_role_change;
update public.profiles set role = 'manager'
 where id = '00000000-0000-4000-8000-0000000044b1';
alter table public.profiles enable trigger profiles_guard_role_change;

insert into public.projects (id, name, created_by) values
  ('11111111-1111-4111-8111-0000000044a1', 'Office move', '00000000-0000-4000-8000-0000000044b1'),
  ('11111111-1111-4111-8111-0000000044b1', 'Website', '00000000-0000-4000-8000-0000000044b1');

insert into public.tasks (id, project_id, title, status, created_by) values
  ('22222222-2222-4222-8222-0000000044a1', '11111111-1111-4111-8111-0000000044a1', 'Sign the lease', 'todo', '00000000-0000-4000-8000-0000000044b1'),
  ('22222222-2222-4222-8222-0000000044a2', '11111111-1111-4111-8111-0000000044a1', 'Book the movers', 'todo', '00000000-0000-4000-8000-0000000044b1'),
  ('22222222-2222-4222-8222-0000000044b1', '11111111-1111-4111-8111-0000000044b1', 'Write the home page', 'todo', '00000000-0000-4000-8000-0000000044b1');
insert into public.task_assignments (task_id, user_id) values
  ('22222222-2222-4222-8222-0000000044a1', '00000000-0000-4000-8000-0000000044c1');

set local role authenticated;

-- --- the manager sets the dates ---------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000044b1', true);

do $$
begin
  insert into public.project_milestones (id, project_id, title, due_on) values
    ('33333333-3333-4333-8333-0000000044a1', '11111111-1111-4111-8111-0000000044a1', 'Lease signed', '2026-11-05'),
    ('33333333-3333-4333-8333-0000000044a2', '11111111-1111-4111-8111-0000000044a1', 'Moved in', '2026-12-03'),
    ('33333333-3333-4333-8333-0000000044b1', '11111111-1111-4111-8111-0000000044b1', 'Site live', '2026-11-20');
  perform check_that('a manager on the project adds milestones', true);
exception when others then
  perform check_that('a manager on the project adds milestones', false, sqlerrm);
end $$;

select check_that('…and is recorded as having made them',
  (select bool_and(created_by = '00000000-0000-4000-8000-0000000044b1') from public.project_milestones));

do $$
begin
  insert into public.project_milestones (project_id, title, due_on) values
    ('11111111-1111-4111-8111-0000000044a1', '   ', '2026-11-05');
  perform check_that('a milestone needs a name', false, 'it was accepted');
exception when check_violation then
  perform check_that('a milestone needs a name', true, sqlerrm);
end $$;

update public.tasks set milestone_id = '33333333-3333-4333-8333-0000000044a1'
 where id in ('22222222-2222-4222-8222-0000000044a1', '22222222-2222-4222-8222-0000000044a2');
select check_that('a manager puts tasks under a milestone',
  (select count(*) from public.tasks where milestone_id = '33333333-3333-4333-8333-0000000044a1') = 2);

do $$
begin
  update public.tasks set milestone_id = '33333333-3333-4333-8333-0000000044a1'
   where id = '22222222-2222-4222-8222-0000000044b1';
  perform check_that('not under another project''s milestone', false, 'it was accepted');
exception when check_violation then
  perform check_that('not under another project''s milestone', true, sqlerrm);
end $$;

do $$
begin
  insert into public.tasks (project_id, title, created_by, milestone_id) values
    ('11111111-1111-4111-8111-0000000044b1', 'Smuggled', '00000000-0000-4000-8000-0000000044b1',
     '33333333-3333-4333-8333-0000000044a1');
  perform check_that('nor created under one', false, 'it was accepted');
exception when check_violation then
  perform check_that('nor created under one', true, sqlerrm);
end $$;

do $$
begin
  update public.project_milestones set project_id = '11111111-1111-4111-8111-0000000044b1'
   where id = '33333333-3333-4333-8333-0000000044a1';
  perform check_that('a milestone stays in its project', false, 'it was moved');
exception when check_violation then
  perform check_that('a milestone stays in its project', true, sqlerrm);
end $$;

update public.project_milestones set done_at = now()
 where id = '33333333-3333-4333-8333-0000000044a1';
select check_that('a manager marks a milestone reached',
  (select done_at is not null from public.project_milestones where id = '33333333-3333-4333-8333-0000000044a1'));

-- --- the member on the lease ------------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000044c1', true);

select check_that('a member sees their project''s milestones, and no others',
  (select count(*) from public.project_milestones) = 2,
  (select string_agg(title, ', ') from public.project_milestones));

do $$
begin
  insert into public.project_milestones (project_id, title, due_on) values
    ('11111111-1111-4111-8111-0000000044a1', 'Party', '2026-12-10');
  perform check_that('a member cannot add a milestone', false, 'it was accepted');
exception when insufficient_privilege then
  perform check_that('a member cannot add a milestone', true, sqlerrm);
end $$;

update public.project_milestones set title = 'Renamed' where id = '33333333-3333-4333-8333-0000000044a2';
delete from public.project_milestones where id = '33333333-3333-4333-8333-0000000044a2';
select check_that('nor rename or remove one',
  (select title from public.project_milestones where id = '33333333-3333-4333-8333-0000000044a2') = 'Moved in');

do $$
begin
  update public.tasks set milestone_id = '33333333-3333-4333-8333-0000000044a2'
   where id = '22222222-2222-4222-8222-0000000044a1';
  perform check_that('a member cannot move their task to another milestone', false, 'it was accepted');
exception when insufficient_privilege then
  perform check_that('a member cannot move their task to another milestone', true, sqlerrm);
end $$;

do $$
begin
  update public.tasks set status = 'in_progress'
   where id = '22222222-2222-4222-8222-0000000044a1';
  perform check_that('…but still works the task under it', true);
exception when others then
  perform check_that('…but still works the task under it', false, sqlerrm);
end $$;

-- --- somebody on neither project --------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000044d1', true);

select check_that('somebody on neither project sees none of it',
  (select count(*) from public.project_milestones) = 0);

-- --- moving and removing ----------------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000044b1', true);

update public.tasks set project_id = '11111111-1111-4111-8111-0000000044b1'
 where id = '22222222-2222-4222-8222-0000000044a2';
select check_that('a task moved to another project leaves its milestone behind',
  (select milestone_id is null and project_id = '11111111-1111-4111-8111-0000000044b1'
     from public.tasks where id = '22222222-2222-4222-8222-0000000044a2'));

delete from public.project_milestones where id = '33333333-3333-4333-8333-0000000044a1';
select check_that('removing a milestone keeps its tasks, under none',
  (select milestone_id is null from public.tasks where id = '22222222-2222-4222-8222-0000000044a1'));

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000044a1', true);

select check_that('an admin sees every project''s milestones',
  (select count(*) from public.project_milestones) = 2);

-- --- results ---------------------------------------------------------------

reset role;

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
