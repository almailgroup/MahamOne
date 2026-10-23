-- ---------------------------------------------------------------------------
-- Reacting to a comment
--
-- A good half of the replies on a task are "ok", "thanks", "on it" — a whole
-- comment, and a notification to everybody on the task, to say what a
-- thumb would. A reaction says it without either.
--
-- A short fixed set rather than any emoji: five that mean something at work
-- (agreed, done, thanks, looking, well done), stored as the character itself
-- so nothing has to translate them. The check is the list; widening it is a
-- one-line migration.
--
-- Who may do what:
--
--   see     anyone who can see the comment — which is anyone who can see its
--           task, the rule every other thing on a task already follows
--   react   the same people, as themselves
--   remove  only your own
--
-- No notification. Telling somebody that a colleague put a thumb on their
-- comment is the noise this exists to remove.
-- ---------------------------------------------------------------------------

create table if not exists public.comment_reactions (
  comment_id uuid not null references public.comments (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  emoji      text not null,
  created_at timestamptz not null default now(),

  -- One of each per person: tapping 👍 twice takes it back rather than
  -- counting two.
  primary key (comment_id, user_id, emoji),

  constraint comment_reactions_emoji_known
    check (emoji in ('👍', '✅', '🙏', '👀', '🎉'))
);

comment on table public.comment_reactions is
  'Who reacted to which comment, with which of the five allowed emoji.';

-- ---------------------------------------------------------------------------
-- Visibility, through the comment's own task
--
-- SECURITY DEFINER so the question can be asked without going through the
-- comments policy, which is itself asking can_view_task. One definition, the
-- same one the comment, the file and the history already resolve through.
-- ---------------------------------------------------------------------------

create or replace function public.can_view_comment(comment uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.comments c
     where c.id = comment
       and public.can_view_task(c.task_id)
  );
$$;

grant execute on function public.can_view_comment(uuid) to authenticated;

alter table public.comment_reactions enable row level security;
alter table public.comment_reactions force row level security;

drop policy if exists "reactions are visible with their comment" on public.comment_reactions;
create policy "reactions are visible with their comment"
  on public.comment_reactions for select
  to authenticated
  using (public.can_view_comment(comment_id));

drop policy if exists "people react as themselves" on public.comment_reactions;
create policy "people react as themselves"
  on public.comment_reactions for insert
  to authenticated
  with check (user_id = auth.uid() and public.can_view_comment(comment_id));

drop policy if exists "people take back their own reactions" on public.comment_reactions;
create policy "people take back their own reactions"
  on public.comment_reactions for delete
  to authenticated
  using (user_id = auth.uid());

grant select, insert, delete on public.comment_reactions to authenticated;
