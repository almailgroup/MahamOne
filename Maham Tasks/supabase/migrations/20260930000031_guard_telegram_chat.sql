-- ---------------------------------------------------------------------------
-- A Telegram chat is proven, not declared.
--
-- `telegram_chat_id` says in its own comment what it is for: the link code
-- exists so somebody can prove a chat is theirs by sending the bot a code
-- from inside it. The webhook then records the chat id Telegram reported,
-- which is the piece the app cannot discover on its own.
--
-- Nothing enforced that. The update policy on this table is
-- `user_id = auth.uid()`, which is right for the two dozen preference
-- columns beside it, and the app never writes this one — but PostgREST is
-- reachable from the browser with the anon key, so one hand-written PATCH
-- set the column to any chat at all and switched the channel on. The bot
-- then delivered that person's reminders, task titles included, to a chat
-- that never agreed to receive them.
--
-- The same shape as `guard_note_owner` and `guard_note_item_parent` in
-- migration 0019: the policy decides which row, and a trigger pins the
-- columns within it that the policy has no way to speak about.
--
-- Clearing it is still the owner's to do — that is what unlinking is — and
-- the webhook is unaffected: it runs with the service role, which carries no
-- `sub` claim, so `auth.uid()` is null for it and it passes straight
-- through. The same is true of a migration or a psql session.
--
-- No dictionary key for the message: the app has no path that reaches it, so
-- the only way to see it is to have gone around the app.
-- ---------------------------------------------------------------------------

create or replace function public.guard_telegram_chat()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- The webhook, a migration, the dispatcher: anything not acting as a
  -- signed-in person. They are the ones allowed to name a chat.
  if auth.uid() is null then
    return new;
  end if;

  -- Unchanged, or being cleared: both fine. Unlinking is the owner's.
  if new.telegram_chat_id is not distinct from old.telegram_chat_id
     or new.telegram_chat_id is null then
    return new;
  end if;

  raise exception
    'A Telegram chat is linked by sending the bot the code from your profile, not by setting it directly.'
    using errcode = 'insufficient_privilege';
end;
$$;

comment on function public.guard_telegram_chat() is
  'Pins notification_preferences.telegram_chat_id so only the verified webhook can name a chat.';

drop trigger if exists notification_preferences_guard_telegram on public.notification_preferences;
create trigger notification_preferences_guard_telegram
  before update on public.notification_preferences
  for each row execute function public.guard_telegram_chat();
