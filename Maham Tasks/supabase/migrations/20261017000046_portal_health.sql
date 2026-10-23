-- ---------------------------------------------------------------------------
-- A health check the outside world may ask.
--
-- /api/health asks this, for an uptime monitor: is the database answering,
-- and how far have the migrations been run? The second matters here more
-- than most places — Vercel deploys the code the moment it is pushed, and
-- the migrations are pasted into the SQL editor by hand afterwards, so "the
-- database is behind the code" is the commonest way for this app to be half
-- broken.
--
-- `schema` is the newest migration whose objects exist, found by looking for
-- one thing each migration made, so it reads true even when migrations were
-- run out of order. It names table and function names and nothing else: no
-- rows, no counts, nothing about anybody. Callable without signing in.
--
-- Run in the Supabase SQL editor after 45. Safe to run more than once.
-- ---------------------------------------------------------------------------

create or replace function public.portal_health()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with markers (migration, present) as (
    values
      (35, to_regprocedure('public.attachment_task_id(text)') is not null),
      (36, to_regclass('public.company_holidays') is not null),
      (37, to_regprocedure('public.enqueue_morning_summaries(timestamptz)') is not null),
      (38, to_regprocedure('public.second_step_pending()') is not null),
      (39, to_regclass('public.labels') is not null),
      (40, to_regclass('public.task_dependencies') is not null),
      (41, to_regclass('public.task_templates') is not null),
      (42, to_regprocedure('public.add_from_chat(text, text, text, public.task_priority, timestamptz)') is not null),
      (43, to_regprocedure('public.work_report(date, date, text)') is not null),
      (44, to_regclass('public.project_milestones') is not null),
      (45, to_regclass('public.admin_alerts') is not null),
      (46, true)
  )
  select jsonb_build_object(
    'database', 'ok',
    'time', now(),
    'schema', (select max(migration) from markers where present),
    -- Anything older than the newest present is missing: run out of order.
    'missing', coalesce(
      (select jsonb_agg(migration order by migration) from markers
        where not present
          and migration < (select max(migration) from markers where present)),
      '[]'::jsonb)
  );
$$;

grant execute on function public.portal_health() to anon, authenticated, service_role;

comment on function public.portal_health() is
  'For /api/health: the database answers, and which migrations have been run. Names only, nothing about anybody.';
