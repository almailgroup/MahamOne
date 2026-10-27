-- ---------------------------------------------------------------------------
-- Functions and triggers
--
-- Every helper is SECURITY DEFINER with a pinned search_path. That combination
-- is what lets the RLS policies in the next migration read `profiles.role`
-- without recursing into the policy that guards `profiles` itself.
-- ---------------------------------------------------------------------------

-- --------------------------------------------------------------------------
-- Authorisation helpers
-- --------------------------------------------------------------------------

create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select role from public.profiles where id = auth.uid();
$$;

comment on function public.current_user_role() is
  'Role of the calling user. SECURITY DEFINER so RLS on profiles does not recurse.';

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.current_user_role() = 'admin', false);
$$;

create or replace function public.is_manager_or_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.current_user_role() in ('admin', 'manager'), false);
$$;

-- True when the caller created the task or is assigned to it.
create or replace function public.can_edit_task(task uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.tasks t
    where t.id = task
      and (
        t.created_by = auth.uid()
        or exists (
          select 1 from public.task_assignments a
          where a.task_id = t.id and a.user_id = auth.uid()
        )
      )
  );
$$;

-- --------------------------------------------------------------------------
-- Signup — mirror every new auth user into public.profiles.
--
-- The first account to register becomes the admin, so a fresh deployment is
-- not locked out of project creation.
-- --------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  assigned_role public.user_role;
begin
  select case when count(*) = 0 then 'admin'::public.user_role
              else 'member'::public.user_role end
    into assigned_role
  from public.profiles;

  insert into public.profiles (id, email, full_name, avatar_url, role)
  values (
    new.id,
    new.email,
    nullif(btrim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), ''),
    nullif(btrim(coalesce(new.raw_user_meta_data ->> 'avatar_url', '')), ''),
    assigned_role
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- --------------------------------------------------------------------------
-- updated_at maintenance
-- --------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

drop trigger if exists projects_set_updated_at on public.projects;
create trigger projects_set_updated_at
  before update on public.projects
  for each row execute function public.set_updated_at();

drop trigger if exists tasks_set_updated_at on public.tasks;
create trigger tasks_set_updated_at
  before update on public.tasks
  for each row execute function public.set_updated_at();

drop trigger if exists comments_set_updated_at on public.comments;
create trigger comments_set_updated_at
  before update on public.comments
  for each row execute function public.set_updated_at();

-- --------------------------------------------------------------------------
-- Role escalation guard
--
-- `profiles` is writable by its owner so people can edit their own name and
-- avatar. This trigger makes sure that same policy cannot be used to hand
-- yourself the admin role — only an existing admin may change `role`.
-- --------------------------------------------------------------------------

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

  -- id and email track auth.users and are not user-editable.
  new.id := old.id;
  new.email := old.email;

  return new;
end;
$$;

drop trigger if exists profiles_guard_role_change on public.profiles;
create trigger profiles_guard_role_change
  before update on public.profiles
  for each row execute function public.guard_profile_role_change();

-- --------------------------------------------------------------------------
-- Task audit trail
-- --------------------------------------------------------------------------

create or replace function public.log_task_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.task_activity (task_id, actor_id, action, new_value)
  values (new.id, auth.uid(), 'created', new.title);
  return null;
end;
$$;

drop trigger if exists tasks_log_insert on public.tasks;
create trigger tasks_log_insert
  after insert on public.tasks
  for each row execute function public.log_task_insert();

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

  if new.due_date is distinct from old.due_date then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'due_date_changed', 'due_date', old.due_date::text, new.due_date::text);
  end if;

  if new.title is distinct from old.title then
    insert into public.task_activity (task_id, actor_id, action, field, old_value, new_value)
    values (new.id, actor, 'updated', 'title', old.title, new.title);
  end if;

  -- Body text is logged as a change marker only; the diff itself would bloat
  -- the audit table.
  if new.description is distinct from old.description then
    insert into public.task_activity (task_id, actor_id, action, field)
    values (new.id, actor, 'updated', 'description');
  end if;

  return null;
end;
$$;

drop trigger if exists tasks_log_update on public.tasks;
create trigger tasks_log_update
  after update on public.tasks
  for each row execute function public.log_task_update();

create or replace function public.log_assignment_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target uuid;
  label  text;
begin
  target := case when tg_op = 'INSERT' then new.user_id else old.user_id end;

  select coalesce(p.full_name, p.email) into label
  from public.profiles p where p.id = target;

  if tg_op = 'INSERT' then
    insert into public.task_activity (task_id, actor_id, action, field, new_value)
    values (new.task_id, auth.uid(), 'assignee_added', 'assignees', label);
  else
    insert into public.task_activity (task_id, actor_id, action, field, old_value)
    values (old.task_id, auth.uid(), 'assignee_removed', 'assignees', label);
  end if;

  return null;
end;
$$;

drop trigger if exists task_assignments_log_insert on public.task_assignments;
create trigger task_assignments_log_insert
  after insert on public.task_assignments
  for each row execute function public.log_assignment_change();

drop trigger if exists task_assignments_log_delete on public.task_assignments;
create trigger task_assignments_log_delete
  after delete on public.task_assignments
  for each row execute function public.log_assignment_change();

create or replace function public.log_comment_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.task_activity (task_id, actor_id, action)
  values (new.task_id, new.user_id, 'commented');
  return null;
end;
$$;

drop trigger if exists comments_log_insert on public.comments;
create trigger comments_log_insert
  after insert on public.comments
  for each row execute function public.log_comment_insert();
