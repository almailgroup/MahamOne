-- ---------------------------------------------------------------------------
-- Errors, somewhere a person looks
--
-- Nothing captured what went wrong in the deployed app. A page that threw on
-- somebody's phone left a line in a Vercel log nobody reads, and the way a
-- fault was discovered was that somebody mentioned it — or did not, and
-- worked around it for a month.
--
-- This is deliberately not a third-party service. It would mean an account,
-- a key pasted into a dashboard, and somebody's task titles leaving the
-- country; the portal already has a database with row-level security and an
-- admin who signs in every day. Errors go there, and the admin sees them
-- where they already look.
--
-- What is kept is what identifies a fault, never a payload: the message, the
-- route, whether it came from the browser or the server. Two weeks of them,
-- swept by the same cron that drains the reminder queue.
-- ---------------------------------------------------------------------------

create table if not exists public.app_errors (
  id           uuid primary key default gen_random_uuid(),
  occurred_at  timestamptz not null default now(),
  -- Null for somebody who was not signed in: a sign-in page that throws is
  -- exactly the kind of fault worth knowing about.
  user_id      uuid references public.profiles (id) on delete set null,
  source       text not null check (source in ('browser', 'server')),
  -- Next's own reference for a server error. Printed on the error page, so
  -- somebody can quote it and an admin can find this row.
  digest       text,
  message      text not null check (char_length(message) between 1 and 2000),
  route        text check (char_length(route) <= 500),
  user_agent   text check (char_length(user_agent) <= 400)
);

create index if not exists app_errors_when_idx
  on public.app_errors (occurred_at desc);

alter table public.app_errors enable row level security;
alter table public.app_errors force row level security;

-- Anybody signed in may report what went wrong in front of them, and only
-- as themselves. Reading is another matter.
drop policy if exists "report what went wrong" on public.app_errors;
create policy "report what went wrong"
  on public.app_errors for insert
  with check (user_id is null or user_id = auth.uid());

-- No select policy at all: a message can carry a fragment of whatever it
-- failed on. Admins read through the function below, which the service role
-- and an admin check stand behind.
grant insert on public.app_errors to authenticated;

comment on table public.app_errors is
  'Faults from the deployed app, kept for two weeks. Write-only for everybody; read through recent_errors().';

-- ---------------------------------------------------------------------------
-- What has been going wrong
-- ---------------------------------------------------------------------------

create or replace function public.recent_errors(since_hours integer default 72)
returns table (
  occurred_at timestamptz,
  person      text,
  source      text,
  digest      text,
  message     text,
  route       text,
  seen        bigint
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
begin
  if not public.is_admin() then
    raise exception 'Only an admin can read the error log.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Grouped: one fault hit forty times is one line with a count, not forty
  -- lines burying everything else that happened that day.
  return query
    select
      max(e.occurred_at) as occurred_at,
      max(coalesce(p.full_name, p.email)) as person,
      e.source,
      max(e.digest) as digest,
      e.message,
      e.route,
      count(*) as seen
    from public.app_errors e
    left join public.profiles p on p.id = e.user_id
   where e.occurred_at > now() - make_interval(hours => greatest(1, since_hours))
   group by e.source, e.message, e.route
   order by max(e.occurred_at) desc
   limit 50;
end;
$fn$;

comment on function public.recent_errors(integer) is
  'Recent faults, grouped by message and route. Admins only; raises for anybody else.';

grant execute on function public.recent_errors(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Two weeks is plenty
--
-- Called by the same scheduled route that drains the reminder queue, so
-- there is nothing new to set up and nothing to remember.
-- ---------------------------------------------------------------------------

create or replace function public.purge_old_errors(older_than interval default interval '14 days')
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  removed integer;
begin
  delete from public.app_errors where occurred_at < now() - older_than;
  get diagnostics removed = row_count;
  return removed;
end;
$fn$;

comment on function public.purge_old_errors(interval) is
  'Drops error rows older than the given age. Called by the scheduled dispatcher.';
