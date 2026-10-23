-- ---------------------------------------------------------------------------
-- "Due Today" means today where the viewer is
--
-- task_counts() decided what was due today with date_trunc('day', now()),
-- which is midnight in the *database's* timezone — UTC on Supabase. Every
-- other place in the app asks the browser, so it uses the viewer's calendar
-- day. Four hours east of UTC the two disagree for a quarter of every day: a
-- task due at 02:00 on Tuesday local time is 22:00 Monday in UTC, so the
-- dashboard tile counted it as due today while the list it opens showed
-- nothing. Overdue was never affected — an instant is an instant.
--
-- The caller now passes its IANA timezone, and the count is taken on that
-- calendar. An unknown or missing name falls back to UTC rather than raising,
-- so a stale or hand-edited cookie cannot break the dashboard.
-- ---------------------------------------------------------------------------

-- The old signature has to go first: with both defined, task_counts() with no
-- arguments is ambiguous and Postgres refuses to choose.
drop function if exists public.task_counts();

create or replace function public.task_counts(tz text default 'UTC')
returns table (
  total       bigint,
  done        bigint,
  todo        bigint,
  in_progress bigint,
  in_review   bigint,
  overdue     bigint,
  due_today   bigint
)
language sql
stable
set search_path = public, pg_temp
as $$
  with zone as (
    select coalesce(
      (select name from pg_timezone_names where name = tz),
      'UTC'
    ) as name
  )
  select
    count(*)                                                        as total,
    count(*) filter (where t.status = 'done')                       as done,
    count(*) filter (where t.status = 'todo')                       as todo,
    count(*) filter (where t.status = 'in_progress')                as in_progress,
    count(*) filter (where t.status = 'in_review')                  as in_review,
    count(*) filter (where t.status <> 'done' and t.due_at < now()) as overdue,
    count(*) filter (
      where t.status <> 'done'
        and t.due_at is not null
        -- Both sides converted to wall-clock time in the viewer's zone, then
        -- compared as dates: exactly what the browser does.
        and (t.due_at at time zone z.name)::date = (now() at time zone z.name)::date
    )                                                               as due_today
  from public.tasks t
  cross join zone z;
$$;

comment on function public.task_counts(text) is
  'Dashboard figures under the caller''s RLS. Pass an IANA timezone so "due today" means the viewer''s day; unknown names fall back to UTC.';

grant execute on function public.task_counts(text) to authenticated;
