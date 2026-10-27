-- ---------------------------------------------------------------------------
-- A minimal stand-in for the parts of Supabase the schema leans on, so the
-- migrations — and the policy tests beside this file — can be applied to a
-- plain PostgreSQL instance in CI.
--
-- It provides only what the schema references: the auth schema, its users and
-- mfa_factors tables, auth.uid() and auth.jwt() (which here read settings the
-- tests set to say who they are and how they signed in), the Supabase roles, the realtime publication, and the two
-- storage tables. It is not a Supabase emulator and is not used anywhere but
-- in tests.
-- ---------------------------------------------------------------------------

create extension if not exists pgcrypto;

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'supabase_admin') then
    create role supabase_admin nologin;
  end if;
end $$;

create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key,
  email text unique,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  -- What only the service key can write. Supabase fills it in for every
  -- account; here it is null unless a test says otherwise.
  raw_app_meta_data jsonb,
  created_at timestamptz not null default now()
);

-- Accounts the suites create stand for accounts an admin added, which since
-- close_self_registration is the only way in once the first admin exists.
-- So an account inserted without app_metadata is recorded as added by the
-- admin, as the Team page would record it. self-registration.sql sets
-- app_metadata itself, to create the other kind.
--
-- Supabase creates accounts one at a time; the suites create several in one
-- statement, the admin first. Every row's BEFORE trigger runs before any
-- row's profile exists, so while there is no admin yet the first account of
-- the batch — the one that will become admin — is remembered and used.
create or replace function auth.shim_added_by_admin()
returns trigger
language plpgsql
as $$
declare
  admin_id uuid;
begin
  if new.raw_app_meta_data is null then
    select p.id into admin_id
      from public.profiles p
     where p.role = 'admin'
     order by p.created_at
     limit 1;
    if admin_id is null then
      admin_id := nullif(current_setting('shim.first_account', true), '')::uuid;
      if admin_id is null then
        perform set_config('shim.first_account', new.id::text, true);
      end if;
    end if;
    new.raw_app_meta_data := jsonb_build_object('added_by', admin_id);
  end if;
  return new;
end;
$$;

drop trigger if exists shim_added_by_admin on auth.users;
create trigger shim_added_by_admin
  before insert on auth.users
  for each row execute function auth.shim_added_by_admin();

-- auth.uid() reads whoever the test has declared itself to be.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create or replace function auth.role() returns text
language sql stable as $$ select 'authenticated'::text $$;

-- The token's claims, as Supabase exposes them. Tests set request.jwt.claims
-- to say how the caller signed in: {"aal": "aal2"} after a second step.
create or replace function auth.jwt() returns jsonb
language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;

-- Second sign-in steps (authenticator apps). Supabase's status is an enum;
-- text compares the same way.
create table if not exists auth.mfa_factors (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  friendly_name text,
  factor_type   text not null default 'totp',
  status        text not null default 'unverified',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Realtime publication the migrations add tables to.
do $$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

grant usage on schema public to authenticated, anon, service_role;
grant usage on schema auth to authenticated, anon, service_role;

-- Storage: just the two tables the bucket migrations write rules for, with
-- row level security on as it is in Supabase. Without them those migrations
-- skip their storage half, and the file rules went untested.
create schema if not exists storage;

create table if not exists storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false,
  file_size_limit bigint
);

create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text not null,
  owner uuid,
  created_at timestamptz not null default now()
);

alter table storage.objects enable row level security;

grant usage on schema storage to authenticated, anon, service_role;
grant select on storage.buckets to authenticated, anon;
grant select, insert, update, delete on storage.objects to authenticated;
