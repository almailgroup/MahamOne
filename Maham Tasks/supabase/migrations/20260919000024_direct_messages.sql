-- ---------------------------------------------------------------------------
-- Private messages
--
-- The team room is one room that everybody reads; its select policy is
-- literally `using (true)`. This is the opposite: a conversation is readable
-- only by the people in it, and there is no admin override anywhere in this
-- file. An admin can remove a message from the shared room because somebody
-- has to be able to take down what should not have been posted in public.
-- Nothing here is public, so that reason does not apply, and "private unless
-- an admin is curious" is not private.
--
-- Shaped for one-to-one today and small private groups later without moving
-- any messages: membership lives in `conversation_participants`, which has no
-- idea how many people it holds. The ordered pair on `conversations` exists
-- only to stop two people ending up with two threads, and is null for
-- anything that is not a pair.
-- ---------------------------------------------------------------------------

create table if not exists public.conversations (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),

  -- Ordering for the conversation list, kept by the trigger below so the list
  -- does not have to aggregate every message to sort itself.
  last_message_at timestamptz not null default now(),

  -- The two people, smaller id first, so (a,b) and (b,a) are the same row.
  member_low  uuid references public.profiles (id) on delete cascade,
  member_high uuid references public.profiles (id) on delete cascade,

  constraint conversations_pair_ordered check (
    (member_low is null and member_high is null) or member_low < member_high
  )
);

-- One thread per pair. Partial, so future group conversations — which leave
-- both columns null — are not forced into a single row between them.
create unique index if not exists conversations_pair_idx
  on public.conversations (member_low, member_high)
  where member_low is not null;

create index if not exists conversations_recent_idx
  on public.conversations (last_message_at desc);

create table if not exists public.conversation_participants (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id         uuid not null references public.profiles (id) on delete cascade,

  -- How far this person has read. The unread count is everything after it.
  last_read_at timestamptz not null default now(),

  primary key (conversation_id, user_id)
);

create index if not exists conversation_participants_user_idx
  on public.conversation_participants (user_id);

create table if not exists public.direct_messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  author_id       uuid not null references public.profiles (id) on delete cascade,
  body            text not null,

  created_at timestamptz not null default now(),
  edited_at  timestamptz,

  constraint direct_messages_body_length check (
    char_length(btrim(body)) between 1 and 4000
  )
);

create index if not exists direct_messages_thread_idx
  on public.direct_messages (conversation_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Membership, asked without recursion
--
-- A policy on `conversation_participants` that checks membership by selecting
-- from `conversation_participants` is a policy that calls itself. `security
-- definer` steps outside row-level security to answer the one question every
-- policy in this file is built on, which is what breaks the loop.
-- ---------------------------------------------------------------------------

create or replace function public.in_conversation(conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select conversation is not null and exists (
    select 1
      from public.conversation_participants p
     where p.conversation_id = conversation
       and p.user_id = auth.uid()
  );
$$;

-- ---------------------------------------------------------------------------
-- Starting a conversation
--
-- Find the thread with somebody, or open it. Done in one `security definer`
-- function rather than by letting the client insert, for two reasons: the
-- caller can only ever add themselves and one other person, and two people
-- messaging each other at the same moment get one thread rather than two —
-- the unique index decides it and the loser reads the winner's row.
-- ---------------------------------------------------------------------------

create or replace function public.start_direct_conversation(other uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me   uuid := auth.uid();
  low  uuid;
  high uuid;
  found uuid;
begin
  if me is null then
    raise exception 'not signed in';
  end if;
  if other is null or other = me then
    raise exception 'pick somebody else to message';
  end if;
  if not exists (select 1 from public.profiles where id = other) then
    raise exception 'that person is not on the team';
  end if;

  low  := least(me, other);
  high := greatest(me, other);

  select id into found
    from public.conversations
   where member_low = low and member_high = high;

  if found is not null then
    return found;
  end if;

  insert into public.conversations (member_low, member_high)
       values (low, high)
  on conflict (member_low, member_high) where member_low is not null
  do nothing
  returning id into found;

  -- Somebody else won the race; their row is the thread.
  if found is null then
    select id into found
      from public.conversations
     where member_low = low and member_high = high;
    return found;
  end if;

  insert into public.conversation_participants (conversation_id, user_id)
       values (found, me), (found, other);

  return found;
end;
$$;

-- ---------------------------------------------------------------------------
-- Keeping the list in order, and telling the other person
-- ---------------------------------------------------------------------------

create or replace function public.touch_conversation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  recipient uuid;
  sender    text;
begin
  update public.conversations
     set last_message_at = new.created_at
   where id = new.conversation_id;

  -- A message nobody is told about is a message nobody reads. Everyone in the
  -- conversation except whoever wrote it.
  select coalesce(p.full_name, p.email) into sender
    from public.profiles p where p.id = new.author_id;

  for recipient in
    select user_id
      from public.conversation_participants
     where conversation_id = new.conversation_id
       and user_id <> new.author_id
  loop
    perform public.push_direct_notification(
      recipient, new.author_id, sender, new.body, new.conversation_id
    );
  end loop;

  return new;
end;
$$;

-- `push_notification` writes a notification about a task; this one is about a
-- conversation, which has no task and no project to point at.
create or replace function public.push_direct_notification(
  recipient uuid,
  actor uuid,
  heading text,
  detail text,
  conversation uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if recipient is null or recipient = actor then
    return;
  end if;
  -- Same guard as `push_notification`: never address a profile that has been
  -- deleted, or a cascading delete cannot finish.
  if not exists (select 1 from public.profiles where id = recipient) then
    return;
  end if;

  insert into public.notifications
    (user_id, actor_id, type, title, body, conversation_id)
  values
    (recipient, actor, 'direct_message', heading, left(btrim(detail), 140), conversation);
end;
$$;

drop trigger if exists direct_messages_touch on public.direct_messages;
create trigger direct_messages_touch
  after insert on public.direct_messages
  for each row execute function public.touch_conversation();

-- ---------------------------------------------------------------------------
-- A notification can now be about a conversation
-- ---------------------------------------------------------------------------

alter table public.notifications
  add column if not exists conversation_id uuid
  references public.conversations (id) on delete cascade;

alter table public.notifications drop constraint if exists notifications_type_known;
alter table public.notifications add constraint notifications_type_known check (
  type in (
    'task_assigned',
    'task_unassigned',
    'task_commented',
    'task_mentioned',
    'task_review_requested',
    'task_completed',
    'direct_message'
  )
);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.conversations              enable row level security;
alter table public.conversation_participants  enable row level security;
alter table public.direct_messages            enable row level security;

-- `force` so the rule holds for the table's owner too. A private conversation
-- is the one place in this schema where that distinction is worth the cost.
alter table public.conversations              force row level security;
alter table public.conversation_participants  force row level security;
alter table public.direct_messages            force row level security;

drop policy if exists "participants read their conversations" on public.conversations;
create policy "participants read their conversations"
  on public.conversations for select
  to authenticated
  using (public.in_conversation(id));

-- No insert policy on purpose: conversations are opened through
-- `start_direct_conversation`, which decides who is in one.

drop policy if exists "participants see who is in the room" on public.conversation_participants;
create policy "participants see who is in the room"
  on public.conversation_participants for select
  to authenticated
  using (public.in_conversation(conversation_id));

-- Marking your own place, and nobody else's.
drop policy if exists "participants mark their own place" on public.conversation_participants;
create policy "participants mark their own place"
  on public.conversation_participants for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "participants read the thread" on public.direct_messages;
create policy "participants read the thread"
  on public.direct_messages for select
  to authenticated
  using (public.in_conversation(conversation_id));

-- You may only speak as yourself, and only where you are.
drop policy if exists "participants write as themselves" on public.direct_messages;
create policy "participants write as themselves"
  on public.direct_messages for insert
  to authenticated
  with check (
    author_id = auth.uid() and public.in_conversation(conversation_id)
  );

drop policy if exists "authors edit their own messages" on public.direct_messages;
create policy "authors edit their own messages"
  on public.direct_messages for update
  to authenticated
  using (author_id = auth.uid())
  with check (author_id = auth.uid());

-- Authors only. There is deliberately no admin clause here.
drop policy if exists "authors delete their own messages" on public.direct_messages;
create policy "authors delete their own messages"
  on public.direct_messages for delete
  to authenticated
  using (author_id = auth.uid());

-- Row-level security decides which rows; the grant decides whether the role
-- may touch the table at all, and this schema says so explicitly everywhere.
grant select                       on public.conversations             to authenticated;
grant select, update               on public.conversation_participants to authenticated;
grant select, insert, update, delete on public.direct_messages         to authenticated;
grant execute on function public.in_conversation(uuid)            to authenticated;
grant execute on function public.start_direct_conversation(uuid)  to authenticated;

-- ---------------------------------------------------------------------------
-- The list, in one question
--
-- Built naively this is a query for the conversations and then two more for
-- each of them — the last thing said, and how much of it is unread. Twenty
-- conversations is forty-one round trips, and the unread total is wanted by
-- the app shell on *every* page, not just this one. One statement instead,
-- with a lateral join per thread, which Postgres answers from the indexes
-- already here.
--
-- `security invoker`, not definer: row-level security still applies, so this
-- cannot return a conversation the caller could not have read anyway. The
-- explicit `user_id = auth.uid()` join is the belt to that pair of braces.
-- ---------------------------------------------------------------------------

create or replace function public.my_conversations()
returns table (
  id              uuid,
  last_message_at timestamptz,
  other_id        uuid,
  other_name      text,
  other_email     text,
  other_avatar    text,
  other_title     text,
  last_message    text,
  last_author_id  uuid,
  unread          bigint
)
language sql
stable
set search_path = public, pg_temp
as $$
  with mine as (
    select c.id, c.last_message_at, p.last_read_at
      from public.conversations c
      join public.conversation_participants p
        on p.conversation_id = c.id
       and p.user_id = auth.uid()
  )
  select
    m.id,
    m.last_message_at,
    other.id,
    other.full_name,
    other.email,
    other.avatar_url,
    other.job_title,
    recent.body,
    recent.author_id,
    coalesce(counted.n, 0)
  from mine m
  left join lateral (
    select pr.id, pr.full_name, pr.email, pr.avatar_url, pr.job_title
      from public.conversation_participants p
      join public.profiles pr on pr.id = p.user_id
     where p.conversation_id = m.id
       and p.user_id <> auth.uid()
     limit 1
  ) other on true
  left join lateral (
    select d.body, d.author_id
      from public.direct_messages d
     where d.conversation_id = m.id
     order by d.created_at desc
     limit 1
  ) recent on true
  left join lateral (
    select count(*) as n
      from public.direct_messages d
     where d.conversation_id = m.id
       and d.author_id <> auth.uid()
       and d.created_at > m.last_read_at
  ) counted on true
  order by m.last_message_at desc;
$$;

-- Just the number, for the badge the shell draws on every page. Counting it
-- here rather than summing the list above is one small query instead of one
-- large one, on pages that will never show a conversation.
create or replace function public.unread_direct_count()
returns bigint
language sql
stable
set search_path = public, pg_temp
as $$
  select coalesce(count(d.*), 0)
    from public.conversation_participants p
    join public.direct_messages d
      on d.conversation_id = p.conversation_id
     and d.author_id <> p.user_id
     and d.created_at > p.last_read_at
   where p.user_id = auth.uid();
$$;

grant execute on function public.my_conversations()      to authenticated;
grant execute on function public.unread_direct_count()   to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime
--
-- RLS is enforced on everything realtime forwards, so publishing these does
-- not widen who can read them.
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'publication supabase_realtime not found — skipping';
    return;
  end if;

  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public'
       and tablename = 'direct_messages'
  ) then
    alter publication supabase_realtime add table public.direct_messages;
  end if;
end $$;

-- A delete payload carries only the identifying columns unless the replica
-- identity is full, and the thread needs to know which message went.
alter table public.direct_messages replica identity full;
