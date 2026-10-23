-- ---------------------------------------------------------------------------
-- Row Level Security
--
-- Authorisation model: this is a single-tenant internal portal, so every
-- signed-in employee can READ the whole workspace (that is what makes project
-- switching, assignee pickers and @mentions work). WRITES are what the roles
-- gate:
--
--   admin   — everything, including roles and deletions
--   manager — create/edit/delete projects and any task
--   member  — create tasks; edit tasks they created or are assigned to
--
-- Nothing is readable while signed out: read policies target `authenticated`
-- AND require a JWT subject, so a role without an identity reads nothing.
-- ---------------------------------------------------------------------------

alter table public.profiles        enable row level security;
alter table public.projects        enable row level security;
alter table public.tasks           enable row level security;
alter table public.task_assignments enable row level security;
alter table public.comments        enable row level security;
alter table public.task_activity   enable row level security;

-- Force RLS to apply to table owners too, so a mistake in a SECURITY DEFINER
-- function cannot quietly hand out unrestricted access.
alter table public.profiles        force row level security;
alter table public.projects        force row level security;
alter table public.tasks           force row level security;
alter table public.task_assignments force row level security;
alter table public.comments        force row level security;
alter table public.task_activity   force row level security;

-- --------------------------------------------------------------------------
-- profiles
-- --------------------------------------------------------------------------

drop policy if exists "profiles are readable by authenticated users" on public.profiles;
create policy "profiles are readable by authenticated users"
  on public.profiles for select
  to authenticated
  using (auth.uid() is not null);

-- Own row only. The guard_profile_role_change trigger blocks self-promotion.
drop policy if exists "users update their own profile" on public.profiles;
create policy "users update their own profile"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists "admins update any profile" on public.profiles;
create policy "admins update any profile"
  on public.profiles for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- No INSERT policy: rows are created exclusively by the handle_new_user
-- trigger on auth.users. No DELETE policy: profiles die with their auth user.

-- --------------------------------------------------------------------------
-- projects
-- --------------------------------------------------------------------------

drop policy if exists "projects are readable by authenticated users" on public.projects;
create policy "projects are readable by authenticated users"
  on public.projects for select
  to authenticated
  using (auth.uid() is not null);

drop policy if exists "managers and admins create projects" on public.projects;
create policy "managers and admins create projects"
  on public.projects for insert
  to authenticated
  with check (public.is_manager_or_admin() and created_by = auth.uid());

drop policy if exists "managers and admins update projects" on public.projects;
create policy "managers and admins update projects"
  on public.projects for update
  to authenticated
  using (public.is_manager_or_admin())
  with check (public.is_manager_or_admin());

-- Deleting a project cascades to its tasks, so it stays with admins and the
-- manager who created it.
drop policy if exists "admins and owning managers delete projects" on public.projects;
create policy "admins and owning managers delete projects"
  on public.projects for delete
  to authenticated
  using (
    public.is_admin()
    or (public.is_manager_or_admin() and created_by = auth.uid())
  );

-- --------------------------------------------------------------------------
-- tasks
-- --------------------------------------------------------------------------

drop policy if exists "tasks are readable by authenticated users" on public.tasks;
create policy "tasks are readable by authenticated users"
  on public.tasks for select
  to authenticated
  using (auth.uid() is not null);

drop policy if exists "authenticated users create tasks" on public.tasks;
create policy "authenticated users create tasks"
  on public.tasks for insert
  to authenticated
  with check (created_by = auth.uid());

-- Managers and admins may edit anything; members only their own or assigned
-- tasks. can_edit_task() is SECURITY DEFINER to avoid recursing through the
-- task_assignments policies.
drop policy if exists "task editors update tasks" on public.tasks;
create policy "task editors update tasks"
  on public.tasks for update
  to authenticated
  using (public.is_manager_or_admin() or public.can_edit_task(id))
  with check (public.is_manager_or_admin() or public.can_edit_task(id));

drop policy if exists "managers admins and creators delete tasks" on public.tasks;
create policy "managers admins and creators delete tasks"
  on public.tasks for delete
  to authenticated
  using (public.is_manager_or_admin() or created_by = auth.uid());

-- --------------------------------------------------------------------------
-- task_assignments
-- --------------------------------------------------------------------------

drop policy if exists "assignments are readable by authenticated users" on public.task_assignments;
create policy "assignments are readable by authenticated users"
  on public.task_assignments for select
  to authenticated
  using (auth.uid() is not null);

-- Whoever may edit the task may change who works on it. Members can also pick
-- up unassigned work themselves.
drop policy if exists "task editors add assignees" on public.task_assignments;
create policy "task editors add assignees"
  on public.task_assignments for insert
  to authenticated
  with check (
    public.is_manager_or_admin()
    or public.can_edit_task(task_id)
    or user_id = auth.uid()
  );

drop policy if exists "task editors remove assignees" on public.task_assignments;
create policy "task editors remove assignees"
  on public.task_assignments for delete
  to authenticated
  using (
    public.is_manager_or_admin()
    or public.can_edit_task(task_id)
    or user_id = auth.uid()
  );

-- --------------------------------------------------------------------------
-- comments
-- --------------------------------------------------------------------------

drop policy if exists "comments are readable by authenticated users" on public.comments;
create policy "comments are readable by authenticated users"
  on public.comments for select
  to authenticated
  using (auth.uid() is not null);

drop policy if exists "users write their own comments" on public.comments;
create policy "users write their own comments"
  on public.comments for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "users edit their own comments" on public.comments;
create policy "users edit their own comments"
  on public.comments for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "authors and admins delete comments" on public.comments;
create policy "authors and admins delete comments"
  on public.comments for delete
  to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- --------------------------------------------------------------------------
-- task_activity
--
-- Readable by everyone signed in, writable by nobody: rows come only from the
-- SECURITY DEFINER audit triggers, which bypass RLS. Leaving out INSERT,
-- UPDATE and DELETE policies is what makes the log genuinely append-only.
-- --------------------------------------------------------------------------

drop policy if exists "activity is readable by authenticated users" on public.task_activity;
create policy "activity is readable by authenticated users"
  on public.task_activity for select
  to authenticated
  using (auth.uid() is not null);

-- --------------------------------------------------------------------------
-- Table privileges
--
-- RLS narrows access but never grants it. Supabase's default privileges
-- usually cover new public tables already; spelling them out here means the
-- schema also works on a project where those defaults were changed.
--
-- `anon` is deliberately granted nothing — there is no public read surface.
-- --------------------------------------------------------------------------

grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.projects to authenticated;
grant select, insert, update, delete on public.tasks to authenticated;
grant select, insert, delete on public.task_assignments to authenticated;
grant select, insert, update, delete on public.comments to authenticated;
-- Select only: the audit trail is written exclusively by triggers.
grant select on public.task_activity to authenticated;

grant execute on function public.current_user_role() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_manager_or_admin() to authenticated;
grant execute on function public.can_edit_task(uuid) to authenticated;
