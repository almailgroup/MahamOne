-- ---------------------------------------------------------------------------
-- Company holidays.
--
-- The working week is Sunday to Thursday (src/lib/work-week.ts); these are the
-- other days off — National Day, Liberation Day, the Eids. Date shortcuts step
-- over them, the calendar marks them, and reminders and the morning summary
-- are not sent on them.
--
-- One row per day. A holiday that runs several days, as the Eids do, is
-- several rows with the same name; the settings page groups them back.
--
-- Everybody signed in can read them — the calendar needs them — and only an
-- admin can change them.
--
-- Run in the Supabase SQL editor. Safe to run more than once.
-- ---------------------------------------------------------------------------

create table if not exists public.company_holidays (
  day        date primary key,
  name       text not null,
  created_by uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),

  constraint company_holidays_name_length
    check (length(btrim(name)) between 1 and 80)
);

comment on table public.company_holidays is
  'Days the company is closed besides the Friday–Saturday weekend.';

alter table public.company_holidays enable row level security;

grant select on public.company_holidays to authenticated;
grant insert, update, delete on public.company_holidays to authenticated;
grant all on public.company_holidays to service_role;

drop policy if exists "holidays are readable by the team" on public.company_holidays;
create policy "holidays are readable by the team"
  on public.company_holidays for select
  to authenticated
  using (true);

drop policy if exists "admins add holidays" on public.company_holidays;
create policy "admins add holidays"
  on public.company_holidays for insert
  to authenticated
  with check (public.is_admin());

drop policy if exists "admins change holidays" on public.company_holidays;
create policy "admins change holidays"
  on public.company_holidays for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "admins remove holidays" on public.company_holidays;
create policy "admins remove holidays"
  on public.company_holidays for delete
  to authenticated
  using (public.is_admin());
