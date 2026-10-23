-- ---------------------------------------------------------------------------
-- The health check: answers without a session, names how far the
-- migrations have been run, and spots one that was skipped.
--
--   psql -f supabase/tests/shim.sql -f supabase/setup.sql -f this file
--
-- NEVER run this against the production project.
-- ---------------------------------------------------------------------------

begin;

create temporary table results (name text, ok boolean, detail text);
grant all on results to anon, authenticated;

create or replace function check_that(name text, ok boolean, detail text default '')
returns void language sql as $$
  insert into results values (name, ok, detail);
$$;

set local role anon;

select check_that('it answers without signing in, every migration run',
  (select h->>'database' = 'ok' and (h->>'schema')::int = 46 and h->'missing' = '[]'::jsonb
     from (select public.portal_health() as h) x),
  (select public.portal_health()::text));

select check_that('it says nothing about anybody',
  (select array(select jsonb_object_keys(public.portal_health()) order by 1))
    = array['database', 'missing', 'schema', 'time']);

reset role;

-- A migration skipped: the labels table never made.
drop table public.task_labels;
drop table public.labels cascade;

set local role anon;

select check_that('a skipped migration is named',
  (select h->'missing' = '[39]'::jsonb and (h->>'schema')::int = 46
     from (select public.portal_health() as h) x),
  (select public.portal_health()::text));

reset role;

select
  case when ok then 'PASS' else 'FAIL' end as result,
  name,
  detail
from results
order by ok, name;

do $$
declare failed integer;
begin
  select count(*) filter (where ok is not true) into failed from results;
  if failed > 0 then
    raise exception '% check(s) failed — see the table above', failed;
  end if;
end $$;

rollback;
