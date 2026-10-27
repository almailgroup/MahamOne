-- ---------------------------------------------------------------------------
-- Guard against locking the workspace out of its own admin role.
--
-- An admin may legitimately demote another admin, but if the last one demotes
-- themselves nobody can create projects or manage roles again, and there is no
-- in-app way to recover. This makes that specific transition fail.
-- ---------------------------------------------------------------------------

create or replace function public.prevent_last_admin_demotion()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  remaining integer;
begin
  if old.role = 'admin' and new.role is distinct from old.role then
    select count(*) into remaining
    from public.profiles
    where role = 'admin' and id <> old.id;

    if remaining = 0 then
      raise exception 'Cannot remove the last admin. Promote another member first.'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

-- Runs after guard_profile_role_change (alphabetical order among BEFORE
-- triggers on the same event), so permission is checked before this.
drop trigger if exists profiles_protect_last_admin on public.profiles;
create trigger profiles_protect_last_admin
  before update on public.profiles
  for each row execute function public.prevent_last_admin_demotion();
