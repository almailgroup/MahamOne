-- ---------------------------------------------------------------------------
-- A task's files are as private as the task.
--
-- Files are stored under their task's id, "<task id>/<file>". Reading one —
-- downloading it, or listing the bucket — is allowed only to somebody who can
-- see that task: the people assigned to it, managers on its project, admins.
-- Until attachment_files_follow_task, any signed-in account could read every
-- file in the bucket.
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

-- The attachment files the current person can list, by file name.
create or replace function public.attachment_files_seen()
returns text language sql stable as $$
  select coalesce(string_agg(split_part(name, '/', 2), ', ' order by name), '(none)')
  from storage.objects
  where bucket_id = 'task-attachments'
$$;
grant execute on function public.attachment_files_seen() to authenticated;

-- The first account in a fresh database becomes its admin.
-- b1 runs the project · b2 manages, but not this project
-- c1 is on the custody task · c2 on the freight task and the licence (general)
-- c3 is on nothing
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000035a1', 'admin@example.test');
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000035b1', 'lead@example.test'),
  ('00000000-0000-4000-8000-0000000035b2', 'other.lead@example.test'),
  ('00000000-0000-4000-8000-0000000035c1', 'hand@example.test'),
  ('00000000-0000-4000-8000-0000000035c2', 'second.hand@example.test'),
  ('00000000-0000-4000-8000-0000000035c3', 'outsider@example.test');

alter table public.profiles disable trigger profiles_guard_role_change;
update public.profiles set role = 'manager'
 where id in ('00000000-0000-4000-8000-0000000035b1',
              '00000000-0000-4000-8000-0000000035b2');
alter table public.profiles enable trigger profiles_guard_role_change;

insert into public.projects (id, name, created_by) values
  ('77777777-7777-4777-8777-000000000035', 'Kuwait Bank Portal',
   '00000000-0000-4000-8000-0000000035b1');

insert into public.tasks (id, project_id, title, created_by) values
  ('22222222-2222-4222-8222-000000000351', '77777777-7777-4777-8777-000000000035',
   'Sign the custody agreement', '00000000-0000-4000-8000-0000000035b1'),
  ('22222222-2222-4222-8222-000000000352', '77777777-7777-4777-8777-000000000035',
   'Reconcile August freight', '00000000-0000-4000-8000-0000000035b1'),
  ('22222222-2222-4222-8222-000000000353', null,
   'Renew the trade licence', '00000000-0000-4000-8000-0000000035a1');

insert into public.task_assignments (task_id, user_id) values
  ('22222222-2222-4222-8222-000000000351', '00000000-0000-4000-8000-0000000035c1'),
  ('22222222-2222-4222-8222-000000000352', '00000000-0000-4000-8000-0000000035c2'),
  ('22222222-2222-4222-8222-000000000353', '00000000-0000-4000-8000-0000000035c2');

insert into storage.objects (bucket_id, name, owner) values
  ('task-attachments', '22222222-2222-4222-8222-000000000351/custody-agreement.pdf',
   '00000000-0000-4000-8000-0000000035b1'),
  ('task-attachments', '22222222-2222-4222-8222-000000000352/freight-invoice.pdf',
   '00000000-0000-4000-8000-0000000035b1'),
  ('task-attachments', '22222222-2222-4222-8222-000000000353/licence-renewal.pdf',
   '00000000-0000-4000-8000-0000000035a1'),
  -- Not under a task id: nobody's to read, and must not break a listing.
  ('task-attachments', 'not-a-task/stray.txt', '00000000-0000-4000-8000-0000000035a1'),
  ('avatars', '00000000-0000-4000-8000-0000000035c1/face.png',
   '00000000-0000-4000-8000-0000000035c1');

set local role authenticated;

-- --- members -----------------------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000035c1', true);
select check_that(
  'a member gets the files of the task assigned to them, and no others',
  public.attachment_files_seen() = 'custody-agreement.pdf',
  public.attachment_files_seen());

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000035c2', true);
select check_that(
  'a member on two tasks gets both tasks'' files, project or general',
  public.attachment_files_seen() = 'freight-invoice.pdf, licence-renewal.pdf',
  public.attachment_files_seen());

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000035c3', true);
select check_that(
  'somebody on no task gets no files',
  public.attachment_files_seen() = '(none)',
  public.attachment_files_seen());

select check_that(
  '…not even by asking for one by its exact name',
  not exists (
    select 1 from storage.objects
    where bucket_id = 'task-attachments'
      and name = '22222222-2222-4222-8222-000000000351/custody-agreement.pdf'));

select check_that(
  'avatars are untouched: still readable by everybody',
  exists (select 1 from storage.objects where bucket_id = 'avatars'));

-- --- managers ------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000035b1', true);
select check_that(
  'a manager gets every file on their project, and the general tasks''',
  public.attachment_files_seen()
    = 'custody-agreement.pdf, freight-invoice.pdf, licence-renewal.pdf',
  public.attachment_files_seen());

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000035b2', true);
select check_that(
  'a manager outside the project gets only the general task''s file',
  public.attachment_files_seen() = 'licence-renewal.pdf',
  public.attachment_files_seen());

-- --- admins ------------------------------------------------------------------

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000035a1', true);
select check_that(
  'an admin gets every task''s files',
  public.attachment_files_seen()
    = 'custody-agreement.pdf, freight-invoice.pdf, licence-renewal.pdf',
  public.attachment_files_seen());

select check_that(
  'a file that is not under a task is nobody''s, and listing still works',
  not exists (select 1 from storage.objects where name = 'not-a-task/stray.txt'));

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
