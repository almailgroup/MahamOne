import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { PGlite, type Transaction } from '@electric-sql/pglite';

/**
 * An in-process Postgres with a small stand-in for what Supabase provides
 * (the auth schema and auth.uid(), the anon and authenticated roles, the
 * storage schema and the Realtime publication), then the cloud migration.
 * Only for tests: the migration runs unchanged here and in Supabase.
 */

export const MIGRATION = join(
  __dirname,
  '../../supabase/migrations/20261004000000_almailbooks_cloud.sql',
);

/** Every migration, in the order the owner runs them. */
export const MIGRATIONS = [
  MIGRATION,
  join(__dirname, '../../supabase/migrations/20261006000000_sync_fixes.sql'),
  join(__dirname, '../../supabase/migrations/20261007000000_email_alerts.sql'),
  join(__dirname, '../../supabase/migrations/20261102000000_tables_v16.sql'),
  join(__dirname, '../../supabase/migrations/20261116000000_super_admin_approvals.sql'),
  join(__dirname, '../../supabase/migrations/20261123000000_change_feed.sql'),
  join(__dirname, '../../supabase/migrations/20261130000000_people_alerts.sql'),
  join(__dirname, '../../supabase/migrations/20261207000000_staffing_costings.sql'),
  join(__dirname, '../../supabase/migrations/20261208000000_ai_assistant.sql'),
  join(__dirname, '../../supabase/migrations/20261210000000_warehouse_issues.sql'),
];

/**
 * Maham Tasks, in its own schema (tasks): run after Maham One's files, and
 * needing none of them. Kept out of MIGRATIONS, which the health check
 * numbers; startDatabase runs it when asked.
 */
export const TASKS_MIGRATION = join(
  __dirname,
  '../../supabase/migrations/20261212000000_maham_tasks.sql',
);

const SUPABASE_STUB = `
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema auth;
grant usage on schema auth to anon, authenticated;
create table auth.users (
  id uuid primary key,
  email text,
  email_confirmed_at timestamptz,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  -- What only the service key writes (Maham Tasks reads it).
  raw_app_meta_data jsonb,
  created_at timestamptz not null default now()
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(
    coalesce(
      nullif(current_setting('request.jwt.claim.sub', true), ''),
      nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
    ),
    ''
  )::uuid
$$;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;
grant execute on function auth.uid(), auth.jwt() to anon, authenticated;

create schema storage;
grant usage on schema storage to anon, authenticated;
create table storage.buckets (
  id text primary key,
  name text not null,
  owner uuid,
  public boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[],
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text not null,
  owner uuid,
  owner_id text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  last_accessed_at timestamptz default now(),
  metadata jsonb,
  version text,
  user_metadata jsonb,
  unique (bucket_id, name)
);
alter table storage.objects enable row level security;
grant select, insert, update, delete on storage.objects to anon, authenticated;
create function storage.foldername(name text) returns text[] language plpgsql as $$
declare _parts text[];
begin
  select string_to_array(name, '/') into _parts;
  return _parts[1:array_length(_parts, 1) - 1];
end
$$;
create function storage.filename(name text) returns text language plpgsql as $$
declare _parts text[];
begin
  select string_to_array(name, '/') into _parts;
  return _parts[array_length(_parts, 1)];
end
$$;

create publication supabase_realtime;

-- Two-step sign-in factors (Maham Tasks).
create table auth.mfa_factors (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  factor_type text not null default 'totp',
  status text not null default 'verified',
  created_at timestamptz default now()
);

-- Supabase lets the API roles use whatever is created in the public schema
-- unless a script takes it back; the migrations must.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
`;

export type Query = <T = Record<string, unknown>>(sql: string, params?: unknown[]) => Promise<T[]>;

export interface Harness {
  db: PGlite;
  /** Runs SQL as the database owner (like the SQL editor). */
  admin: Query;
  /** Creates an account; its email is confirmed unless told otherwise. */
  user: (email: string, options?: { confirmed?: boolean; name?: string }) => Promise<string>;
  /** Runs `fn` in a transaction as the given account (or anonymously). */
  as: <T>(userId: string | null, fn: (q: Query) => Promise<T>) => Promise<T>;
  /** Calls a function of the app's API as the given account. */
  rpc: <T = Record<string, unknown>>(
    userId: string | null,
    name: string,
    args?: Record<string, unknown>,
  ) => Promise<T[]>;
}

function queryOn(tx: Pick<Transaction, 'query'>): Query {
  return async <T>(sql: string, params: unknown[] = []) =>
    (await tx.query<T>(sql, params)).rows as T[];
}

/**
 * A database with the migrations run in order, each `runs` times (running a
 * file again must be safe). `migrations` limits it to the first ones, to
 * check what an app finds before the owner runs the latest.
 */
export async function startDatabase(
  runs = 1,
  migrations: number = MIGRATIONS.length,
  options: { tasks?: boolean } = {},
): Promise<Harness> {
  const db = new PGlite();
  await db.exec(SUPABASE_STUB);
  const files = [...MIGRATIONS.slice(0, migrations), ...(options.tasks ? [TASKS_MIGRATION] : [])];
  for (const file of files) {
    const migration = readFileSync(file, 'utf8');
    for (let i = 0; i < runs; i++) await db.exec(migration);
  }
  const admin = queryOn(db);
  let counter = 0;

  const user: Harness['user'] = async (email, options = {}) => {
    counter += 1;
    const id = `00000000-0000-4000-8000-${String(counter).padStart(12, '0')}`;
    await admin(
      `insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data)
       values ($1, $2, $3, $4)`,
      [
        id,
        email,
        options.confirmed === false ? null : new Date().toISOString(),
        JSON.stringify({ full_name: options.name ?? email.split('@')[0], language: 'en' }),
      ],
    );
    return id;
  };

  const as: Harness['as'] = (userId, fn) =>
    db.transaction(async (tx) => {
      await tx.query(`set local role ${userId ? 'authenticated' : 'anon'}`);
      await tx.query(`select set_config('request.jwt.claims', $1, true)`, [
        JSON.stringify(userId ? { sub: userId, role: 'authenticated' } : { role: 'anon' }),
      ]);
      return fn(queryOn(tx));
    });

  const rpc: Harness['rpc'] = (userId, name, args = {}) =>
    as(userId, (q) => {
      const names = Object.keys(args);
      const list = names.map((n, i) => `${n} => $${i + 1}`).join(', ');
      return q(
        `select * from ${name.includes('.') ? name : `public.${name}`}(${list})`,
        names.map((n) => args[n]),
      );
    });

  return { db, admin, user, as, rpc };
}
