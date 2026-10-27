-- ---------------------------------------------------------------------------
-- Realtime
--
-- Publishes the tables the UI subscribes to. Realtime still enforces RLS on
-- every change it forwards, so publishing a table does not widen access.
--
-- Guarded with a lookup on pg_publication so the migration is idempotent and
-- also applies on a plain Postgres instance (CI, local validation) where the
-- Supabase publication does not exist.
-- ---------------------------------------------------------------------------

do $$
declare
  target text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'publication supabase_realtime not found — skipping';
    return;
  end if;

  foreach target in array array['tasks', 'comments', 'task_assignments', 'task_activity']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = target
    ) then
      execute format('alter publication supabase_realtime add table public.%I', target);
    end if;
  end loop;
end $$;

-- Realtime UPDATE payloads only carry the columns needed to identify a row
-- unless the replica identity is full. The board diffs old vs new status, so
-- tasks needs the complete old row.
alter table public.tasks replica identity full;
alter table public.comments replica identity full;
