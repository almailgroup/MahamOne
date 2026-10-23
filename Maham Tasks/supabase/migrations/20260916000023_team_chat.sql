-- ---------------------------------------------------------------------------
-- Team chat
--
-- One room for the workspace. Not a channel list and not direct messages:
-- everyone here already works together, and a single room that everybody can
-- see is the thing a small team actually uses. It is modelled so a `room`
-- column could be added later without moving the messages.
--
-- Deliberately separate from `comments`, which belong to a task and are part
-- of its record. A message here is conversation, and is allowed to be deleted
-- by the person who wrote it.
-- ---------------------------------------------------------------------------

create table if not exists public.team_messages (
  id        uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  body      text not null,

  created_at timestamptz not null default now(),
  edited_at  timestamptz,

  -- Long enough for a paragraph, short enough that the room stays a
  -- conversation rather than a document.
  constraint team_messages_body_length check (
    char_length(btrim(body)) between 1 and 4000
  )
);

-- The room is read newest-last and paged from the end.
create index if not exists team_messages_created_idx
  on public.team_messages (created_at desc);

alter table public.team_messages enable row level security;

-- Everyone signed in is on the team, so everyone reads the room. There is no
-- narrower rule to write: a shared room whose messages some members cannot see
-- is not a shared room.
drop policy if exists "team messages are readable by the team" on public.team_messages;
create policy "team messages are readable by the team"
  on public.team_messages for select
  to authenticated
  using (true);

-- You may only speak as yourself. Without the `author_id` check a member could
-- post a message attributed to somebody else, which is the one thing a chat
-- must not allow.
drop policy if exists "members write their own messages" on public.team_messages;
create policy "members write their own messages"
  on public.team_messages for insert
  to authenticated
  with check (author_id = auth.uid());

drop policy if exists "authors edit their own messages" on public.team_messages;
create policy "authors edit their own messages"
  on public.team_messages for update
  to authenticated
  using (author_id = auth.uid())
  with check (author_id = auth.uid());

-- An author can delete what they said; an admin can delete anything, because
-- somebody has to be able to remove what should not have been posted.
drop policy if exists "authors and admins delete messages" on public.team_messages;
create policy "authors and admins delete messages"
  on public.team_messages for delete
  to authenticated
  using (author_id = auth.uid() or public.is_admin());

-- Row-level security decides *which* rows; the grant decides whether the role
-- may touch the table at all, and both are needed. Every other table in this
-- schema grants explicitly rather than leaning on the default privileges of
-- the `public` schema — this one was the exception, and the symptom was a
-- room that answered "permission denied for table team_messages".
grant select, insert, update, delete on public.team_messages to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime
--
-- RLS is still enforced on everything realtime forwards, so publishing the
-- table does not widen who can read it.
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'publication supabase_realtime not found — skipping';
    return;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'team_messages'
  ) then
    alter publication supabase_realtime add table public.team_messages;
  end if;
end $$;

-- A delete payload carries only the identifying columns unless the replica
-- identity is full, and the room needs to know which message went.
alter table public.team_messages replica identity full;
