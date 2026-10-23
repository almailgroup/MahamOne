-- ---------------------------------------------------------------------------
-- Deleting a person could not be done.
--
-- Removing an account from Supabase's Authentication page returned 500, and
-- the database log underneath it said:
--
--   insert or update on table "notifications"
--   violates foreign key constraint "notifications_user_id_fkey"
--
-- The cascade is the whole story. Deleting the auth user deletes their
-- profile; deleting the profile deletes their task assignments; and every
-- assignment that goes fires `task_assignments_notify_delete`, which tries to
-- tell that person they have been removed from a task. The profile it would
-- address is the one that has just been deleted, so the insert has nobody to
-- point at and the whole delete rolls back. The more work somebody had been
-- given, the more certainly they could never be removed.
--
-- `push_notification` already meant to guard this — "never about a missing
-- user" is its own comment — but it only checked that the recipient id was not
-- null, and an id for a row that no longer exists is not null. It checks for
-- the row now.
--
-- This is the right place for the fix rather than the assignment trigger:
-- every notification in the app goes through this one function, so a comment,
-- a mention, a status change and a reassignment are all covered by it, and any
-- future one is covered without being remembered.
-- ---------------------------------------------------------------------------

create or replace function public.push_notification(
  recipient uuid,
  actor uuid,
  kind text,
  heading text,
  detail text,
  task uuid,
  project uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Never notify someone about their own action.
  if recipient is null or recipient = coalesce(actor, '00000000-0000-0000-0000-000000000000'::uuid) then
    return;
  end if;

  -- Never notify someone who is not there any more. During a cascading delete
  -- the profile is already gone by the time the triggers on its children run,
  -- and a message to a deleted account is not worth failing the delete for.
  if not exists (select 1 from public.profiles where id = recipient) then
    return;
  end if;

  insert into public.notifications (user_id, actor_id, type, title, body, task_id, project_id)
  values (recipient, actor, kind, heading, detail, task, project);
end;
$$;
