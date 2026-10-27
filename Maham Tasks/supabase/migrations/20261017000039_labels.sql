-- ---------------------------------------------------------------------------
-- Labels.
--
-- A word or two on a task that cuts across projects — "Bank", "Ministry",
-- "Waiting for signature" — so a list can be narrowed to it. One set for the
-- whole company, kept by admins and managers in Settings; they put them on
-- tasks as they plan them. Everybody sees them.
--
-- Colours are a small fixed set, shown as a dot beside the name. Amber is
-- not among them: in this app it means late, and nothing else.
--
-- Run in the Supabase SQL editor after 38. Safe to run more than once.
-- ---------------------------------------------------------------------------

create table if not exists public.labels (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  colour     text not null default 'slate',
  created_by uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),

  constraint labels_name_length check (length(btrim(name)) between 1 and 30),
  constraint labels_colour check (colour in ('slate', 'blue', 'green', 'violet', 'pink', 'teal'))
);

-- "Bank" and "bank " are the same label.
create unique index if not exists labels_name_unique on public.labels (lower(btrim(name)));

create table if not exists public.task_labels (
  task_id    uuid not null references public.tasks (id) on delete cascade,
  label_id   uuid not null references public.labels (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (task_id, label_id)
);

create index if not exists task_labels_label_idx on public.task_labels (label_id);

comment on table public.labels is
  'Words that cut across projects, put on tasks to narrow a list to them.';
comment on table public.task_labels is
  'Which labels are on which task. Seen with the task; set by whoever plans it.';

alter table public.labels enable row level security;
alter table public.labels force row level security;
alter table public.task_labels enable row level security;
alter table public.task_labels force row level security;

-- The labels themselves --------------------------------------------------------

drop policy if exists "labels are readable by the team" on public.labels;
create policy "labels are readable by the team"
  on public.labels for select to authenticated
  using (true);

drop policy if exists "planners add labels" on public.labels;
create policy "planners add labels"
  on public.labels for insert to authenticated
  with check (public.is_manager_or_admin());

drop policy if exists "planners change labels" on public.labels;
create policy "planners change labels"
  on public.labels for update to authenticated
  using (public.is_manager_or_admin())
  with check (public.is_manager_or_admin());

drop policy if exists "planners remove labels" on public.labels;
create policy "planners remove labels"
  on public.labels for delete to authenticated
  using (public.is_manager_or_admin());

-- Labels on tasks ---------------------------------------------------------------

drop policy if exists "see the labels on a task you can see" on public.task_labels;
create policy "see the labels on a task you can see"
  on public.task_labels for select to authenticated
  using (public.can_view_task(task_id));

drop policy if exists "planners label tasks" on public.task_labels;
create policy "planners label tasks"
  on public.task_labels for insert to authenticated
  with check (public.is_manager_or_admin() and public.can_view_task(task_id));

drop policy if exists "planners unlabel tasks" on public.task_labels;
create policy "planners unlabel tasks"
  on public.task_labels for delete to authenticated
  using (public.is_manager_or_admin() and public.can_view_task(task_id));

grant select, insert, update, delete on public.labels to authenticated;
grant select, insert, delete on public.task_labels to authenticated;
grant all on public.labels, public.task_labels to service_role;
