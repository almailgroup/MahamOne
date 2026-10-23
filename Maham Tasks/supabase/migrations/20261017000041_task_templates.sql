-- ---------------------------------------------------------------------------
-- Task templates.
--
-- The same work comes round again — month-end payroll, a new starter, a
-- licence renewal — with the same steps each time. A template keeps the
-- title, description, priority, labels and steps of one such task, and how
-- many working days after today it is usually due. Anybody creating a task
-- can start from one; admins and managers keep them, by saving a task as a
-- template or from Settings.
--
-- Run in the Supabase SQL editor after 40. Safe to run more than once.
-- ---------------------------------------------------------------------------

create table if not exists public.task_templates (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null,
  title               text not null,
  description         text,
  priority            public.task_priority not null default 'medium',
  steps               text[] not null default '{}',
  label_ids           uuid[] not null default '{}',
  due_in_working_days integer,
  created_by          uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint task_templates_name_length check (length(btrim(name)) between 1 and 80),
  constraint task_templates_title_length check (length(btrim(title)) between 1 and 200),
  constraint task_templates_steps_count check (cardinality(steps) <= 50),
  constraint task_templates_due_range check (due_in_working_days between 0 and 365)
);

comment on table public.task_templates is
  'Work that comes round again: a task''s title, steps and labels, to start the next one from.';

alter table public.task_templates enable row level security;
alter table public.task_templates force row level security;

drop policy if exists "templates are readable by the team" on public.task_templates;
create policy "templates are readable by the team"
  on public.task_templates for select to authenticated
  using (true);

drop policy if exists "planners add templates" on public.task_templates;
create policy "planners add templates"
  on public.task_templates for insert to authenticated
  with check (public.is_manager_or_admin());

drop policy if exists "planners change templates" on public.task_templates;
create policy "planners change templates"
  on public.task_templates for update to authenticated
  using (public.is_manager_or_admin())
  with check (public.is_manager_or_admin());

drop policy if exists "planners remove templates" on public.task_templates;
create policy "planners remove templates"
  on public.task_templates for delete to authenticated
  using (public.is_manager_or_admin());

grant select, insert, update, delete on public.task_templates to authenticated;
grant all on public.task_templates to service_role;

drop trigger if exists task_templates_set_updated_at on public.task_templates;
create trigger task_templates_set_updated_at
  before update on public.task_templates
  for each row execute function public.set_updated_at();
