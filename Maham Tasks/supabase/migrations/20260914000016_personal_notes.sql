-- ---------------------------------------------------------------------------
-- My List — personal notes
--
-- A private scratchpad for what someone has to get through today, separate
-- from the assigned-task system. Unlike everything else in this schema these
-- rows are visible to exactly one person: there is no manager override and no
-- admin override, because a personal list nobody else can read is the whole
-- point of it.
--
-- A note owns its checklist items. They are separate rows rather than a JSON
-- blob so that ticking one box is a single narrow UPDATE — the interaction
-- that has to feel instant on a phone — instead of rewriting the note.
-- ---------------------------------------------------------------------------

create table if not exists public.personal_notes (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  title      text not null default '',
  body       text not null default '',
  pinned     boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint personal_notes_title_length check (char_length(title) <= 200),
  constraint personal_notes_body_length check (char_length(body) <= 20000)
);

-- The list is ordered pinned-first then most recently touched, which is also
-- the only way it is ever read.
create index if not exists personal_notes_user_idx
  on public.personal_notes (user_id, pinned desc, updated_at desc);

create table if not exists public.personal_note_items (
  id         uuid primary key default gen_random_uuid(),
  note_id    uuid not null references public.personal_notes (id) on delete cascade,
  -- Denormalised from the note so the RLS policy is a plain column check and
  -- never has to look at another table.
  user_id    uuid not null references public.profiles (id) on delete cascade,
  content    text not null default '',
  done       boolean not null default false,
  position   double precision not null default 1024,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint personal_note_items_content_length check (char_length(content) <= 1000)
);

create index if not exists personal_note_items_note_idx
  on public.personal_note_items (note_id, position);

-- ---------------------------------------------------------------------------
-- Keep updated_at honest, and bubble item edits up to the note so the list
-- re-sorts when you tick something off.
-- ---------------------------------------------------------------------------

drop trigger if exists personal_notes_set_updated_at on public.personal_notes;
create trigger personal_notes_set_updated_at
  before update on public.personal_notes
  for each row execute function public.set_updated_at();

drop trigger if exists personal_note_items_set_updated_at on public.personal_note_items;
create trigger personal_note_items_set_updated_at
  before update on public.personal_note_items
  for each row execute function public.set_updated_at();

create or replace function public.touch_personal_note()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.personal_notes
     set updated_at = now()
   where id = coalesce(new.note_id, old.note_id);
  return coalesce(new, old);
end;
$$;

drop trigger if exists personal_note_items_touch_note on public.personal_note_items;
create trigger personal_note_items_touch_note
  after insert or update or delete on public.personal_note_items
  for each row execute function public.touch_personal_note();

-- ---------------------------------------------------------------------------
-- Row Level Security: your own rows, and nothing else.
-- ---------------------------------------------------------------------------

alter table public.personal_notes enable row level security;
alter table public.personal_notes force row level security;
alter table public.personal_note_items enable row level security;
alter table public.personal_note_items force row level security;

drop policy if exists "own notes are readable" on public.personal_notes;
create policy "own notes are readable"
  on public.personal_notes for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "own notes are writable" on public.personal_notes;
create policy "own notes are writable"
  on public.personal_notes for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "own notes are updatable" on public.personal_notes;
create policy "own notes are updatable"
  on public.personal_notes for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "own notes are deletable" on public.personal_notes;
create policy "own notes are deletable"
  on public.personal_notes for delete
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "own note items are readable" on public.personal_note_items;
create policy "own note items are readable"
  on public.personal_note_items for select
  to authenticated
  using (user_id = auth.uid());

-- The note must also be yours, so an item cannot be parked on someone else's
-- note by forging note_id.
drop policy if exists "own note items are writable" on public.personal_note_items;
create policy "own note items are writable"
  on public.personal_note_items for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.personal_notes n
       where n.id = note_id and n.user_id = auth.uid()
    )
  );

drop policy if exists "own note items are updatable" on public.personal_note_items;
create policy "own note items are updatable"
  on public.personal_note_items for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "own note items are deletable" on public.personal_note_items;
create policy "own note items are deletable"
  on public.personal_note_items for delete
  to authenticated
  using (user_id = auth.uid());

grant select, insert, update, delete on public.personal_notes to authenticated;
grant select, insert, update, delete on public.personal_note_items to authenticated;
