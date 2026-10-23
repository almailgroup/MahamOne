-- ---------------------------------------------------------------------------
-- Due dates gain a time of day, and profiles gain a job position.
-- ---------------------------------------------------------------------------

-- --------------------------------------------------------------------------
-- tasks.due_date (date) -> tasks.due_at (timestamptz)
--
-- Renamed rather than reused: a column called due_date holding a time of day
-- would mislead every future reader. Existing dates are interpreted as the end
-- of that day, so nothing that was not yet overdue silently becomes overdue.
-- --------------------------------------------------------------------------

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'tasks' and column_name = 'due_date'
  ) then
    alter table public.tasks
      alter column due_date type timestamptz
      using (due_date::timestamp + interval '23 hours 59 minutes');

    alter table public.tasks rename column due_date to due_at;
  end if;
end $$;

comment on column public.tasks.due_at is
  'When the task is due, including time of day. Stored as an absolute instant.';

drop index if exists public.tasks_open_due_date_idx;
create index if not exists tasks_open_due_at_idx
  on public.tasks (due_at)
  where status <> 'done' and due_at is not null;

-- The audit trigger references the old column name.
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

-- The member field guard references it too.
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
  then
    raise exception 'Only a manager or admin can change task details. You can update the status and add comments or files.'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

-- --------------------------------------------------------------------------
-- profiles.job_title
--
-- Named job_title, not "position": tasks.position already means sort order in
-- this schema, and reusing the word for something unrelated invites mistakes.
-- The UI labels it "Position".
-- --------------------------------------------------------------------------

alter table public.profiles
  add column if not exists job_title text;

alter table public.profiles
  drop constraint if exists profiles_job_title_length;
alter table public.profiles
  add constraint profiles_job_title_length
  check (job_title is null or length(btrim(job_title)) between 1 and 60);

-- Positions are assigned, not self-declared: the same guard that blocks
-- self-promotion now also pins job_title for anyone who is not an admin.
create or replace function public.guard_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.role is distinct from old.role and not public.is_admin() then
    raise exception 'Only an admin can change a profile role'
      using errcode = 'insufficient_privilege';
  end if;

  if new.job_title is distinct from old.job_title and not public.is_admin() then
    raise exception 'Only an admin can change a job position'
      using errcode = 'insufficient_privilege';
  end if;

  -- id and email track auth.users and are not user-editable.
  new.id := old.id;
  new.email := old.email;

  return new;
end;
$$;

-- --------------------------------------------------------------------------
-- Avatars bucket
--
-- Public, unlike task attachments: avatars are rendered in lists all over the
-- app, and signing every one of them per request would be pure overhead for
-- images that carry nothing sensitive. Writes stay locked to the owner.
--
-- Object keys are "<user_id>/<file>", so the first path segment is the owner.
-- --------------------------------------------------------------------------

do $$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'storage schema not found - skipping avatar bucket';
    return;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit)
  values ('avatars', 'avatars', true, 2097152)
  on conflict (id) do update
    set public = true,
        file_size_limit = excluded.file_size_limit;

  execute $p$drop policy if exists "avatars are publicly readable" on storage.objects$p$;
  execute $p$create policy "avatars are publicly readable"
    on storage.objects for select
    using (bucket_id = 'avatars')$p$;

  execute $p$drop policy if exists "users upload their own avatar" on storage.objects$p$;
  execute $p$create policy "users upload their own avatar"
    on storage.objects for insert
    to authenticated
    with check (
      bucket_id = 'avatars'
      and nullif(split_part(name, '/', 1), '') = auth.uid()::text
    )$p$;

  execute $p$drop policy if exists "users replace their own avatar" on storage.objects$p$;
  execute $p$create policy "users replace their own avatar"
    on storage.objects for update
    to authenticated
    using (
      bucket_id = 'avatars'
      and nullif(split_part(name, '/', 1), '') = auth.uid()::text
    )$p$;

  execute $p$drop policy if exists "users remove their own avatar" on storage.objects$p$;
  execute $p$create policy "users remove their own avatar"
    on storage.objects for delete
    to authenticated
    using (
      bucket_id = 'avatars'
      and (
        nullif(split_part(name, '/', 1), '') = auth.uid()::text
        or public.is_admin()
      )
    )$p$;
end $$;
