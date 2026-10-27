-- ---------------------------------------------------------------------------
-- Follow-ups
--
-- A task can carry a date to chase it on, plus a note saying what to chase
-- ("call the supplier Tuesday"). The follow-up list reads from these.
--
-- Stored as columns rather than a separate table: a task has one *next*
-- follow-up at a time, and the history of previous ones is already captured by
-- the audit trail below.
-- ---------------------------------------------------------------------------

alter table public.tasks
  add column if not exists follow_up_at timestamptz;

alter table public.tasks
  add column if not exists follow_up_note text;

alter table public.tasks
  drop constraint if exists tasks_follow_up_note_length;
alter table public.tasks
  add constraint tasks_follow_up_note_length
  check (follow_up_note is null or length(btrim(follow_up_note)) between 1 and 500);

-- A note without a date would never surface in the list.
alter table public.tasks
  drop constraint if exists tasks_follow_up_note_needs_date;
alter table public.tasks
  add constraint tasks_follow_up_note_needs_date
  check (follow_up_note is null or follow_up_at is not null);

comment on column public.tasks.follow_up_at is
  'When this task should next be chased. Drives the follow-up list.';

create index if not exists tasks_follow_up_idx
  on public.tasks (follow_up_at)
  where follow_up_at is not null and status <> 'done';

-- --------------------------------------------------------------------------
-- Follow-ups are planning, like the due date, so they follow the same rule:
-- managers and admins set them, members see them.
-- --------------------------------------------------------------------------

create or replace function public.enforce_task_field_permissions()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if public.is_manager_or_admin() then
    return new;
  end if;

  if new.title is distinct from old.title
     or new.description is distinct from old.description
     or new.priority is distinct from old.priority
     or new.due_at is distinct from old.due_at
     or new.project_id is distinct from old.project_id
     or new.follow_up_at is distinct from old.follow_up_at
     or new.follow_up_note is distinct from old.follow_up_note
  then
    raise exception 'Only a manager or admin can change task details. You can update the status and add comments or files.'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

-- --------------------------------------------------------------------------
-- Audit follow-up changes, so the history of what was chased and when survives
-- even though only the next one is stored.
-- --------------------------------------------------------------------------

alter table public.task_activity
  drop constraint if exists task_activity_action_known;
alter table public.task_activity
  add constraint task_activity_action_known check (
    action in (
      'created',
      'updated',
      'status_changed',
      'priority_changed',
      'due_date_changed',
      'follow_up_set',
      'follow_up_cleared',
      'assignee_added',
      'assignee_removed',
      'commented'
    )
  );

create or replace function public.log_task_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor uuid := auth.uid();
begin
  if new.status is distinct from old.status then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'status_changed', 'status', old.status::text, new.status::text);
  end if;

  if new.priority is distinct from old.priority then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'priority_changed', 'priority', old.priority::text, new.priority::text);
  end if;

  if new.due_at is distinct from old.due_at then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'due_date_changed', 'due_at', old.due_at::text, new.due_at::text);
  end if;

  if new.follow_up_at is distinct from old.follow_up_at
     or new.follow_up_note is distinct from old.follow_up_note then
    if new.follow_up_at is null then
      insert into public.task_activity (task_id, actor_id, action, field, old_value)
      values (new.id, actor, 'follow_up_cleared', 'follow_up_at', old.follow_up_at::text);
    else
      insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
      values (
        new.id, actor, 'follow_up_set', 'follow_up_at',
        old.follow_up_at::text,
        new.follow_up_at::text ||
          coalesce(' - ' || nullif(btrim(new.follow_up_note), ''), '')
      );
    end if;
  end if;

  if new.title is distinct from old.title then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'updated', 'title', old.title, new.title);
  end if;

  if new.description is distinct from old.description then
    insert into public.task_activity (task_id, actor_id, action, field)
    values (new.id, actor, 'updated', 'description');
  end if;

  return null;
end;
$$;
