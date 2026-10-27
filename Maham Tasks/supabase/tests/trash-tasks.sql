-- ---------------------------------------------------------------------------
-- Deleting a task puts it in the bin, and the bin behaves.
--
-- Trashing hides a task from every read at once, restoring brings it back
-- with everything on it, only the people who could delete may do either, and
-- the purge removes only what has sat there long enough. All of it is policy
-- and function, so it is tested against the real ones.
-- ---------------------------------------------------------------------------

\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaa0000-0000-4000-8000-000000000001', 'boss@test.local',   '{"full_name":"Boss"}'),
  ('bbbb0000-0000-4000-8000-000000000002', 'worker@test.local', '{"full_name":"Worker"}');

do $$
declare
  boss   constant uuid := 'aaaa0000-0000-4000-8000-000000000001';
  worker constant uuid := 'bbbb0000-0000-4000-8000-000000000002';
  job    constant uuid := 'cccc0000-0000-4000-8000-000000000003';
  seen   bigint;
  did    boolean;
begin
  execute 'set local role authenticated';

  -- The first account is the admin; the second joins as a member.
  perform set_config('request.jwt.claim.sub', boss::text, true);
  insert into tasks (id, title, status, priority, created_by)
    values (job, 'Book the van', 'todo', 'high', boss);
  insert into task_assignments (task_id, user_id) values (job, worker);
  insert into comments (task_id, user_id, content) values (job, boss, 'Before noon please');

  -- ---- A member cannot bin a task --------------------------------------
  perform set_config('request.jwt.claim.sub', worker::text, true);
  select count(*) into seen from tasks where id = job;
  assert seen = 1, 'the assignee could not see the task to begin with';
  select public.trash_task(job) into did;
  assert not did, 'a member was able to delete a task';
  select count(*) into seen from tasks where id = job;
  assert seen = 1, 'a refused delete still hid the task';

  -- ---- A manager or admin can, and it vanishes for everyone -------------
  perform set_config('request.jwt.claim.sub', boss::text, true);
  select public.trash_task(job) into did;
  assert did, 'an admin could not delete a task';
  select count(*) into seen from tasks where id = job;
  assert seen = 0, 'a trashed task was still readable by the person who trashed it';
  select count(*) into seen from task_counts();
  -- task_counts returns one row of figures; the task must not be in them.
  perform set_config('request.jwt.claim.sub', worker::text, true);
  select count(*) into seen from tasks;
  assert seen = 0, 'a trashed task was still readable by its assignee';

  -- The bin is recorded in the history.
  perform set_config('request.jwt.claim.sub', boss::text, true);
  select count(*) into seen from task_activity where task_id = job and action = 'deleted';
  assert seen = 1, 'trashing was not written to the history';

  -- ---- Restore brings it back with everything on it ---------------------
  perform set_config('request.jwt.claim.sub', worker::text, true);
  select public.restore_task(job) into did;
  assert not did, 'a member was able to restore a task';

  perform set_config('request.jwt.claim.sub', boss::text, true);
  select public.restore_task(job) into did;
  assert did, 'an admin could not restore a task';
  select count(*) into seen from tasks where id = job;
  assert seen = 1, 'a restored task did not come back';
  select count(*) into seen from comments where task_id = job;
  assert seen = 1, 'a restored task lost its comments';
  select count(*) into seen from task_assignments where task_id = job;
  assert seen = 1, 'a restored task lost its assignee';
  select count(*) into seen from task_activity where task_id = job and action = 'restored';
  assert seen = 1, 'restoring was not written to the history';

  -- ---- The purge takes only what has sat there long enough --------------
  perform public.trash_task(job);
  execute 'reset role';
  -- Backdate the bin timestamp as the owner, which the app never does.
  update public.tasks set deleted_at = now() - interval '10 days' where id = job;
  assert (select public.purge_trashed_tasks('30 days')) = 0, 'a ten-day-old task was purged early';
  update public.tasks set deleted_at = now() - interval '31 days' where id = job;
  assert (select public.purge_trashed_tasks('30 days')) = 1, 'a month-old task was not purged';
  select count(*) into seen from public.tasks where id = job;
  assert seen = 0, 'the purge did not actually remove the row';

  raise notice 'trash-tasks: every expectation held';
end $$;

rollback;
