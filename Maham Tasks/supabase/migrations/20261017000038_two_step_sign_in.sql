-- ---------------------------------------------------------------------------
-- Two-step sign-in.
--
-- Anybody can add an authenticator app in Profile; admins must, before they
-- can add people or change roles. Once someone has, their password alone is
-- not enough: a session that has the password but not yet the code counts
-- here as a member — whatever their role — until the code is entered.
--
-- The app sends such a session to the code page anyway. This is what makes
-- that hold for somebody who skips the app and talks to the database
-- directly with a stolen password: every role check in the schema goes
-- through current_user_role(), so changing it here covers all of them —
-- is_admin(), is_manager_or_admin(), the guard on role changes.
--
-- Nobody who has not set it up is affected, so this cannot lock anybody out.
--
-- Run in the Supabase SQL editor after 37. Safe to run more than once.
-- ---------------------------------------------------------------------------

/**
 * True when the caller has an authenticator app but this session was opened
 * with the password alone. Supabase records which in the token's `aal`
 * claim: aal1 after a password, aal2 after the code.
 */
create or replace function public.second_step_pending()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2'
     and exists (
       select 1 from auth.mfa_factors f
        where f.user_id = auth.uid()
          and f.status = 'verified'
     );
$$;

comment on function public.second_step_pending() is
  'Whether the caller has two-step sign-in but has not entered the code this session.';

create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
           when public.second_step_pending() then 'member'::public.user_role
           else role
         end
    from public.profiles
   where id = auth.uid();
$$;

comment on function public.current_user_role() is
  'Role of the calling user — member until the second step, for those who have one. SECURITY DEFINER so RLS on profiles does not recurse.';

grant execute on function public.second_step_pending() to authenticated;
