-- ---------------------------------------------------------------------------
-- A task's files are as private as the task.
--
-- Attachments live in two places: a row in task_attachments, which says what
-- the file is called and which task it belongs to, and the file itself in the
-- task-attachments storage bucket. The row has followed the task since
-- project membership arrived — you only see the attachments of tasks you can
-- see. The file never did: the bucket's read rule let any signed-in account
-- read any file in it, and reading includes listing. So a member who may only
-- see the tasks assigned to them could list the bucket and download the files
-- of every other task, in every project.
--
-- Every file is stored under its task's id — "<task id>/<file>" — which is
-- also what the upload rule checks. Reading now asks the same question the
-- rest of the app asks about the task itself: can_view_task.
--
-- Run in the Supabase SQL editor. Safe to run more than once.
-- ---------------------------------------------------------------------------

-- The task a stored file belongs to, from the first segment of its path, or
-- null when that is not a task id. Checked before casting, so a stray object
-- with an odd name is simply unreadable rather than an error for everybody
-- listing the bucket.
create or replace function public.attachment_task_id(object_name text)
returns uuid
language sql
immutable
set search_path = public, pg_temp
as $$
  select case
    when split_part(object_name, '/', 1)
      ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then split_part(object_name, '/', 1)::uuid
  end
$$;

do $$
begin
  if to_regclass('storage.objects') is null then
    raise notice 'storage schema not found - skipping the attachment read policy';
    return;
  end if;

  execute $p$drop policy if exists "attachment objects readable by authenticated" on storage.objects$p$;
  execute $p$drop policy if exists "attachment objects readable with their task" on storage.objects$p$;
  execute $p$create policy "attachment objects readable with their task"
    on storage.objects for select
    to authenticated
    using (
      bucket_id = 'task-attachments'
      and public.can_view_task(public.attachment_task_id(name))
    )$p$;
end $$;
