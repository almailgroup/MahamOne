-- ---------------------------------------------------------------------------
-- Accounts are added, not taken.
--
-- This portal is for one company's staff. Until now anybody who found its
-- address could register: the sign-in page offered "Create one", and the
-- Supabase project accepts sign-ups unless they are switched off in its
-- settings. A stranger who did that could see nothing of the work — tasks and
-- projects are guarded — but could read the team chat, see every colleague's
-- name, email and role, and message any of them.
--
-- The app no longer offers registration. This closes it underneath as well,
-- so it holds even if the project's sign-up setting is left on, and even for
-- somebody who calls Supabase's sign-up endpoint directly with the public key.
--
-- An account is accepted only when an admin added it. The Team page's "Add
-- teammate" does that through the server's service key and records which
-- admin asked in the account's app_metadata — which only the service key can
-- write; somebody signing themselves up can set user_metadata, not this. The
-- trigger checks that the id recorded there belongs to an admin.
--
-- The first account in an empty database is still let in and made admin, as
-- before, so a fresh deployment can bootstrap itself.
--
-- One consequence: adding a user from the Supabase dashboard is refused too,
-- because the dashboard cannot set app_metadata on creation. Add people from
-- the Team page.
--
-- Run in the Supabase SQL editor. Safe to run more than once.
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  assigned_role public.user_role;
  added_by_text text := new.raw_app_meta_data ->> 'added_by';
  added_by uuid;
begin
  if not exists (select 1 from public.profiles) then
    -- An empty database: this is the person setting it up.
    assigned_role := 'admin';
  else
    -- Checked before casting, so a malformed value is refused with the
    -- message below rather than with a cast error.
    if added_by_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      added_by := added_by_text::uuid;
    end if;

    if added_by is null or not exists (
      select 1 from public.profiles p
      where p.id = added_by and p.role = 'admin'
    ) then
      raise exception 'Accounts are added by an admin from the Team page.'
        using errcode = '42501';
    end if;

    assigned_role := 'member';
  end if;

  insert into public.profiles (id, email, full_name, avatar_url, role)
  values (
    new.id,
    new.email,
    nullif(btrim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), ''),
    nullif(btrim(coalesce(new.raw_user_meta_data ->> 'avatar_url', '')), ''),
    assigned_role
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

-- The trigger itself is unchanged; it is restated so this file stands alone.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
