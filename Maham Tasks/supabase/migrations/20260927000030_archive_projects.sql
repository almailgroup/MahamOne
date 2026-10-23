-- ---------------------------------------------------------------------------
-- Finishing with a project
--
-- Projects accumulated. A job delivered in 2026 sat in the sidebar next to
-- live work for as long as the portal ran, and in every project picker, and
-- in the dashboard's counts — and the only way to be rid of it was to delete
-- it, which takes its tasks, its comments and its history with it.
--
-- Archiving is the other answer: out of the way, still readable, and
-- reversible. Nothing is destroyed and nothing is hidden from somebody who
-- goes looking.
--
-- A column rather than a status enum, because there are exactly two states
-- and one of them is "not archived". `archived_at` also records when, which
-- a boolean would not.
-- ---------------------------------------------------------------------------

alter table public.projects
  add column if not exists archived_at timestamptz;

create index if not exists projects_live_idx
  on public.projects (archived_at)
  where archived_at is null;

comment on column public.projects.archived_at is
  'When the project was archived, or null while it is live. Archiving hides it from the sidebar and the pickers; nothing is deleted.';

-- ---------------------------------------------------------------------------
-- Archiving one
--
-- The update policy on projects already says managers and admins, so this
-- needs no rule of its own — it exists to be one statement that can be
-- called by name, and to refuse the thing a plain update would happily do:
-- archiving a project that still has work open in it.
--
-- `security invoker`, so the policy decides, exactly as it would for an
-- ordinary update.
-- ---------------------------------------------------------------------------

create or replace function public.set_project_archived(project uuid, archived boolean)
returns void
language plpgsql
security invoker
set search_path = public, pg_temp
as $fn$
declare
  still_open integer;
  touched integer;
begin
  if archived then
    select count(*) into still_open
      from public.tasks t
     where t.project_id = project
       and t.deleted_at is null
       and t.status <> 'done';

    if still_open > 0 then
      -- Left as the default raise code on purpose. The app maps
      -- check_violation to a generic "not allowed", which would throw away
      -- the one useful thing here: how many are left.
      raise exception 'That project still has % task(s) open.', still_open;
    end if;
  end if;

  update public.projects
     set archived_at = case when archived then now() else null end
   where id = project;

  get diagnostics touched = row_count;
  if touched = 0 then
    -- Row-level security filtered it: not a manager, or no such project.
    raise exception 'That project is not yours to archive.'
      using errcode = 'insufficient_privilege';
  end if;
end;
$fn$;

comment on function public.set_project_archived(uuid, boolean) is
  'Archives a project, or brings it back. Refuses while any task in it is still open.';

grant execute on function public.set_project_archived(uuid, boolean) to authenticated;
