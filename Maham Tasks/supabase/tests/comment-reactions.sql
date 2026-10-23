-- ---------------------------------------------------------------------------
-- Reactions follow the comment, which follows the task.
--
-- Anyone who can read a comment can see and add reactions to it, as
-- themselves; only the person who reacted can take it back; and somebody who
-- cannot see the task learns nothing about it from here.
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

-- The first account in a fresh database becomes its admin, and the last
-- admin cannot be demoted, so somebody has to hold that role first.
-- m1 runs the project · u1 is assigned the task · u2 is not
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000006a1', 'admin@example.test');
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000006b1', 'lead@example.test'),
  ('00000000-0000-4000-8000-0000000006c1', 'hand@example.test'),
  ('00000000-0000-4000-8000-0000000006c2', 'outsider@example.test');

alter table public.profiles disable trigger profiles_guard_role_change;
update public.profiles set role = 'manager'
 where id = '00000000-0000-4000-8000-0000000006b1';
alter table public.profiles enable trigger profiles_guard_role_change;

insert into public.projects (id, name, created_by) values
  ('77777777-7777-4777-8777-000000000061', 'Warehouse Move',
   '00000000-0000-4000-8000-0000000006b1');

insert into public.tasks (id, project_id, title, created_by) values
  ('22222222-2222-4222-8222-000000000061', '77777777-7777-4777-8777-000000000061',
   'Book the trucks', '00000000-0000-4000-8000-0000000006b1');

insert into public.task_assignments (task_id, user_id) values
  ('22222222-2222-4222-8222-000000000061', '00000000-0000-4000-8000-0000000006c1');

insert into public.comments (id, task_id, user_id, content) values
  ('33333333-3333-4333-8333-000000000061', '22222222-2222-4222-8222-000000000061',
   '00000000-0000-4000-8000-0000000006b1', 'Trucks booked for Thursday.');

set local role authenticated;

-- --- the person on the task -------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000006c1', true);

do $$
begin
  insert into public.comment_reactions (comment_id, user_id, emoji)
  values ('33333333-3333-4333-8333-000000000061', '00000000-0000-4000-8000-0000000006c1', '👍');
  perform check_that('somebody who can read the comment can react to it', true);
exception when others then
  perform check_that('somebody who can read the comment can react to it', false, sqlerrm);
end $$;

select check_that(
  'and sees the reaction',
  (select count(*) from public.comment_reactions
    where comment_id = '33333333-3333-4333-8333-000000000061') = 1);

do $$
begin
  insert into public.comment_reactions (comment_id, user_id, emoji)
  values ('33333333-3333-4333-8333-000000000061', '00000000-0000-4000-8000-0000000006c1', '👍');
  perform check_that('the same reaction twice is one reaction', false, 'it was accepted');
exception when unique_violation then
  perform check_that('the same reaction twice is one reaction', true, sqlerrm);
end $$;

do $$
begin
  insert into public.comment_reactions (comment_id, user_id, emoji)
  values ('33333333-3333-4333-8333-000000000061', '00000000-0000-4000-8000-0000000006c1', '🔥');
  perform check_that('only the five allowed emoji', false, 'it was accepted');
exception when check_violation then
  perform check_that('only the five allowed emoji', true, sqlerrm);
end $$;

do $$
begin
  insert into public.comment_reactions (comment_id, user_id, emoji)
  values ('33333333-3333-4333-8333-000000000061', '00000000-0000-4000-8000-0000000006b1', '🎉');
  perform check_that('nobody reacts in somebody else''s name', false, 'it was accepted');
exception when insufficient_privilege then
  perform check_that('nobody reacts in somebody else''s name', true, sqlerrm);
end $$;

-- --- somebody who cannot see the task -----------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000006c2', true);

select check_that(
  'somebody not on the task cannot see its reactions',
  (select count(*) from public.comment_reactions) = 0);

do $$
begin
  insert into public.comment_reactions (comment_id, user_id, emoji)
  values ('33333333-3333-4333-8333-000000000061', '00000000-0000-4000-8000-0000000006c2', '👀');
  perform check_that('or add one', false, 'it was accepted');
exception when insufficient_privilege then
  perform check_that('or add one', true, sqlerrm);
end $$;

-- --- taking it back -------------------------------------------------------------
-- The manager can see the reaction, and cannot remove it.
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000006b1', true);

select check_that(
  'the manager sees it too',
  (select count(*) from public.comment_reactions) = 1);

do $$
declare n integer;
begin
  delete from public.comment_reactions;
  get diagnostics n = row_count;
  perform check_that('but cannot take back somebody else''s reaction', n = 0, 'rows: ' || n);
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000006c1', true);
do $$
declare n integer;
begin
  delete from public.comment_reactions;
  get diagnostics n = row_count;
  perform check_that('the person who reacted can', n = 1, 'rows: ' || n);
end $$;

-- --- and they go with the comment ---------------------------------------------
insert into public.comment_reactions (comment_id, user_id, emoji)
values ('33333333-3333-4333-8333-000000000061', '00000000-0000-4000-8000-0000000006c1', '✅');

reset role;
delete from public.comments where id = '33333333-3333-4333-8333-000000000061';

select check_that(
  'deleting a comment takes its reactions with it',
  (select count(*) from public.comment_reactions) = 0);

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
