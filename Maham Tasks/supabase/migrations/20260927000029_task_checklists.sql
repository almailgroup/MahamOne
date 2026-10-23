-- ---------------------------------------------------------------------------
-- The small steps inside a task
--
-- "Meet with Kuwait banks" has five documents to bring, and there was
-- nowhere to put them. They went into the description as prose, where
-- nothing can be ticked off and nobody can see how far along it is — or they
-- went nowhere, and somebody arrived without the signatory list.
--
-- My List has had items since the beginning; a task has not. Same idea, with
-- one difference that matters: a personal note belongs to one person, and a
-- task belongs to whoever can see it.
--
-- Who may do what is exactly what the task itself allows, and deliberately
-- not a rule of its own: reading follows can_view_task, writing follows the
-- same predicate as an update to the task — `is_manager_or_admin() or
-- can_edit_task(...)`.
--
-- The first draft of this had a third rule, a `security definer` function so
-- that somebody could tick a step off without being able to rewrite it. The
-- test for it could not find anybody in that position: on a project, anyone
-- who can *see* a task is a manager, its author or assigned to it, and all
-- three may edit it. A special case that protects nobody is worse than none,
-- so the rules are the task's own.
-- ---------------------------------------------------------------------------

create table if not exists public.task_checklist_items (
  id         uuid primary key default gen_random_uuid(),
  task_id    uuid not null references public.tasks (id) on delete cascade,
  content    text not null check (char_length(btrim(content)) between 1 and 500),
  done       boolean not null default false,
  -- Gaps, so an item can be dropped between two without renumbering.
  position   integer not null default 0,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists task_checklist_items_task_idx
  on public.task_checklist_items (task_id, position);

alter table public.task_checklist_items enable row level security;
alter table public.task_checklist_items force row level security;

drop policy if exists "see the steps of a task you can see" on public.task_checklist_items;
create policy "see the steps of a task you can see"
  on public.task_checklist_items for select
  using (public.can_view_task(task_id));

drop policy if exists "plan the steps of a task you can edit" on public.task_checklist_items;
create policy "plan the steps of a task you can edit"
  on public.task_checklist_items for insert
  with check (public.is_manager_or_admin() or public.can_edit_task(task_id));

drop policy if exists "change the steps of a task you can edit" on public.task_checklist_items;
create policy "change the steps of a task you can edit"
  on public.task_checklist_items for update
  using (public.is_manager_or_admin() or public.can_edit_task(task_id))
  with check (public.is_manager_or_admin() or public.can_edit_task(task_id));

drop policy if exists "remove the steps of a task you can edit" on public.task_checklist_items;
create policy "remove the steps of a task you can edit"
  on public.task_checklist_items for delete
  using (public.is_manager_or_admin() or public.can_edit_task(task_id));

grant select, insert, update, delete on public.task_checklist_items to authenticated;

drop trigger if exists task_checklist_items_set_updated_at on public.task_checklist_items;
create trigger task_checklist_items_set_updated_at
  before update on public.task_checklist_items
  for each row execute function public.set_updated_at();

comment on table public.task_checklist_items is
  'The steps inside a task. Read and written under exactly the rules the task itself has.';
