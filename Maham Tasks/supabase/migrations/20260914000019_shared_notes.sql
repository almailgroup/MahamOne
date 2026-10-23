-- ---------------------------------------------------------------------------
-- Sharing a list
--
-- My List was built for exactly one reader — no manager override, no admin
-- override — and that stays true of every list nobody has been invited to.
-- What changes is that the owner can invite specific people, one list at a
-- time, and take the invitation back.
--
-- Who can do what on a shared list:
--
--   owner         everything, including deleting the list and managing who
--                 else is on it
--   collaborator  read it, write its text, and add, tick, edit or remove
--                 lines — a shared checklist that only one person may tick is
--                 not a shared checklist
--   collaborator  may also remove themselves, which is how you leave a list
--   anyone else   nothing, exactly as before
--
-- Ownership never moves: the guard below pins user_id through every update,
-- so a collaborator cannot make a list theirs.
-- ---------------------------------------------------------------------------

create table if not exists public.personal_note_shares (
  note_id  uuid not null references public.personal_notes (id) on delete cascade,
  user_id  uuid not null references public.profiles (id) on delete cascade,
  added_by uuid references public.profiles (id) on delete set null,
  added_at timestamptz not null default now(),

  primary key (note_id, user_id)
);

create index if not exists personal_note_shares_user_idx
  on public.personal_note_shares (user_id);

comment on table public.personal_note_shares is
  'Who a personal list has been shared with. Absence of a row is privacy.';

-- --------------------------------------------------------------------------
-- Visibility helpers
--
-- SECURITY DEFINER so they can read the notes and shares tables without going
-- through the policies that are themselves written in terms of them.
-- --------------------------------------------------------------------------

create or replace function public.owns_note(note uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.personal_notes n
     where n.id = note and n.user_id = auth.uid()
  );
$$;

create or replace function public.can_view_note(note uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    public.owns_note(note)
    or exists (
      select 1 from public.personal_note_shares s
       where s.note_id = note and s.user_id = auth.uid()
    );
$$;

grant execute on function public.owns_note(uuid) to authenticated;
grant execute on function public.can_view_note(uuid) to authenticated;

-- --------------------------------------------------------------------------
-- Ownership and parentage are not editable
--
-- Without this an update could rewrite user_id — handing a list to yourself,
-- or away to somebody else — or move a line onto a different note.
-- --------------------------------------------------------------------------

create or replace function public.guard_note_owner()
returns trigger
language plpgsql
as $$
begin
  new.user_id := old.user_id;
  return new;
end;
$$;

drop trigger if exists personal_notes_guard_owner on public.personal_notes;
create trigger personal_notes_guard_owner
  before update on public.personal_notes
  for each row execute function public.guard_note_owner();

create or replace function public.guard_note_item_parent()
returns trigger
language plpgsql
as $$
begin
  new.user_id := old.user_id;
  new.note_id := old.note_id;
  return new;
end;
$$;

drop trigger if exists personal_note_items_guard_parent on public.personal_note_items;
create trigger personal_note_items_guard_parent
  before update on public.personal_note_items
  for each row execute function public.guard_note_item_parent();

-- --------------------------------------------------------------------------
-- Notes: read and write for everyone on the list, delete for its owner
-- --------------------------------------------------------------------------

alter table public.personal_note_shares enable row level security;
alter table public.personal_note_shares force row level security;

drop policy if exists "own notes are readable" on public.personal_notes;
drop policy if exists "notes are readable by their people" on public.personal_notes;
create policy "notes are readable by their people"
  on public.personal_notes for select
  to authenticated
  using (public.can_view_note(id));

drop policy if exists "own notes are updatable" on public.personal_notes;
drop policy if exists "notes are writable by their people" on public.personal_notes;
create policy "notes are writable by their people"
  on public.personal_notes for update
  to authenticated
  using (public.can_view_note(id))
  with check (public.can_view_note(id));

-- Deleting somebody's list is not collaboration. A collaborator leaves by
-- removing their own share row instead.
drop policy if exists "own notes are deletable" on public.personal_notes;
drop policy if exists "notes are deletable by their owner" on public.personal_notes;
create policy "notes are deletable by their owner"
  on public.personal_notes for delete
  to authenticated
  using (user_id = auth.uid());

-- --------------------------------------------------------------------------
-- Lines: whoever can see the list can work it
--
-- The item policies used to be a plain user_id check, which is why the column
-- was denormalised onto the row in the first place. It stays — as a record of
-- who added a line — but visibility now resolves through the note, because on
-- a shared list the lines are not all the same person's.
-- --------------------------------------------------------------------------

drop policy if exists "own note items are readable" on public.personal_note_items;
drop policy if exists "note items are readable by their people" on public.personal_note_items;
create policy "note items are readable by their people"
  on public.personal_note_items for select
  to authenticated
  using (public.can_view_note(note_id));

drop policy if exists "own note items are writable" on public.personal_note_items;
drop policy if exists "note items are writable by their people" on public.personal_note_items;
create policy "note items are writable by their people"
  on public.personal_note_items for insert
  to authenticated
  with check (user_id = auth.uid() and public.can_view_note(note_id));

drop policy if exists "own note items are updatable" on public.personal_note_items;
drop policy if exists "note items are updatable by their people" on public.personal_note_items;
create policy "note items are updatable by their people"
  on public.personal_note_items for update
  to authenticated
  using (public.can_view_note(note_id))
  with check (public.can_view_note(note_id));

drop policy if exists "own note items are deletable" on public.personal_note_items;
drop policy if exists "note items are deletable by their people" on public.personal_note_items;
create policy "note items are deletable by their people"
  on public.personal_note_items for delete
  to authenticated
  using (public.can_view_note(note_id));

-- --------------------------------------------------------------------------
-- The share rows themselves
-- --------------------------------------------------------------------------

drop policy if exists "shares are readable by their people" on public.personal_note_shares;
create policy "shares are readable by their people"
  on public.personal_note_shares for select
  to authenticated
  using (public.can_view_note(note_id));

-- Only the owner invites, and never themselves — they are already on it.
drop policy if exists "owners share their notes" on public.personal_note_shares;
create policy "owners share their notes"
  on public.personal_note_shares for insert
  to authenticated
  with check (
    public.owns_note(note_id)
    and added_by = auth.uid()
    and user_id <> auth.uid()
  );

-- The owner removes anybody; everybody else may remove themselves, which is
-- what leaving a list means.
drop policy if exists "owners and leavers remove shares" on public.personal_note_shares;
create policy "owners and leavers remove shares"
  on public.personal_note_shares for delete
  to authenticated
  using (public.owns_note(note_id) or user_id = auth.uid());

grant select, insert, delete on public.personal_note_shares to authenticated;

-- --------------------------------------------------------------------------
-- Realtime
--
-- A shared list that only updates on reload is a worse shared list. Realtime
-- applies RLS to every change it forwards, so publishing these does not widen
-- who can see what.
-- --------------------------------------------------------------------------

do $$
declare
  target text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'publication supabase_realtime not found — skipping';
    return;
  end if;

  foreach target in array array['personal_notes', 'personal_note_items']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = target
    ) then
      execute format('alter publication supabase_realtime add table public.%I', target);
    end if;
  end loop;
end $$;

-- A deleted line has to say which note it belonged to, and the payload for a
-- delete carries only the identifying columns unless the whole row is kept.
alter table public.personal_note_items replica identity full;
