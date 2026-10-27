-- ---------------------------------------------------------------------------
-- The work report.
--
-- What the Reports page shows, in one call: how much was finished and added
-- in a period and the one before it, how much was finished on time, what is
-- overdue now, the period week by week (or month by month), open work by
-- person, and each project's progress.
--
-- Invoker, so it counts only what the person asking can see — the same rows
-- the rest of the app shows them. Days are the office's (company_time_zone);
-- weeks start on Sunday, as the office's do.
--
-- A task's finishing time is the last time it was moved to done, from the
-- activity log; a task done before the log existed falls back to when it was
-- last touched.
--
-- Run in the Supabase SQL editor after 42. Safe to run more than once.
-- ---------------------------------------------------------------------------

create or replace function public.work_report(
  first_day date,
  last_day  date,
  grain     text default 'week'
)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  with
  settings as (
    select public.company_time_zone() as zone,
           (last_day - first_day + 1) as length
  ),
  periods as (
    select
      (first_day::timestamp at time zone s.zone) as starts,
      ((last_day + 1)::timestamp at time zone s.zone) as ends,
      ((first_day - s.length)::timestamp at time zone s.zone) as before_starts
    from settings s
  ),
  live as (
    select * from public.tasks where deleted_at is null
  ),
  finished as (
    select
      t.id, t.due_at,
      coalesce(
        (select max(a.created_at) from public.task_activity a
          where a.task_id = t.id and a.action = 'status_changed' and a.new_value = 'done'),
        t.updated_at
      ) as at
    from live t
    where t.status = 'done'
  ),
  buckets as (
    select
      b::date as starts,
      (case when grain = 'month' then b + interval '1 month' else b + interval '7 days' end)::date as ends
    from generate_series(
      case when grain = 'month'
        then date_trunc('month', first_day)::date
        else first_day - extract(dow from first_day)::integer
      end,
      last_day,
      case when grain = 'month' then interval '1 month' else interval '7 days' end
    ) b
  ),
  local as (
    select
      (select zone from settings) as zone
  )
  select jsonb_build_object(
    'finished', (select count(*) from finished f, periods p where f.at >= p.starts and f.at < p.ends),
    'finishedBefore', (select count(*) from finished f, periods p where f.at >= p.before_starts and f.at < p.starts),
    'added', (select count(*) from live t, periods p where t.created_at >= p.starts and t.created_at < p.ends),
    'addedBefore', (select count(*) from live t, periods p where t.created_at >= p.before_starts and t.created_at < p.starts),
    'onTime', (select count(*) from finished f, periods p
                where f.at >= p.starts and f.at < p.ends and f.due_at is not null and f.at <= f.due_at),
    'withDue', (select count(*) from finished f, periods p
                 where f.at >= p.starts and f.at < p.ends and f.due_at is not null),
    'onTimeBefore', (select count(*) from finished f, periods p
                      where f.at >= p.before_starts and f.at < p.starts and f.due_at is not null and f.at <= f.due_at),
    'withDueBefore', (select count(*) from finished f, periods p
                       where f.at >= p.before_starts and f.at < p.starts and f.due_at is not null),
    'overdueNow', (select count(*) from live t where t.status <> 'done' and t.due_at < now()),
    'buckets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'starts', b.starts,
        'added', (select count(*) from live t
                   where (t.created_at at time zone l.zone)::date >= b.starts
                     and (t.created_at at time zone l.zone)::date < b.ends),
        'finished', (select count(*) from finished f
                      where (f.at at time zone l.zone)::date >= b.starts
                        and (f.at at time zone l.zone)::date < b.ends)
      ) order by b.starts)
      from buckets b, local l
    ), '[]'::jsonb),
    'people', coalesce((
      select jsonb_agg(row_to_json(x)::jsonb order by x.open desc, x.name)
      from (
        select
          p.id,
          coalesce(nullif(p.full_name, ''), p.email) as name,
          count(*) as open,
          count(*) filter (where t.due_at < now()) as overdue
        from public.task_assignments a
        join live t on t.id = a.task_id
        join public.profiles p on p.id = a.user_id
        where t.status <> 'done'
        group by p.id, p.full_name, p.email
      ) x
    ), '[]'::jsonb),
    'projects', coalesce((
      select jsonb_agg(row_to_json(y)::jsonb order by y.name)
      from (
        select
          pr.id,
          pr.name,
          count(t.id) as total,
          count(t.id) filter (where t.status = 'done') as done,
          count(t.id) filter (where t.status <> 'done' and t.due_at < now()) as overdue
        from public.projects pr
        left join live t on t.project_id = pr.id
        where pr.archived_at is null
        group by pr.id, pr.name
      ) y
    ), '[]'::jsonb)
  );
$$;

grant execute on function public.work_report(date, date, text) to authenticated;
