-- ---------------------------------------------------------------------------
-- Linking Telegram is a handshake, and the handshake is the point.
--
-- The link code exists so a chat can prove it wants the bot: you send the
-- code from inside the chat, Telegram tells the webhook which chat replied,
-- and the webhook records it. A person who can write the chat id straight
-- into their own preferences row has skipped all of that, and the bot will
-- deliver their reminders — task titles and all — to a chat that never
-- agreed to anything.
--
--   psql -f supabase/tests/shim.sql -f <every migration> -f this file
--
-- NEVER run this against the production project.
-- ---------------------------------------------------------------------------

begin;

create temporary table results (name text, ok boolean, detail text);
grant all on results to authenticated;

create or replace function check_that(name text, ok boolean, detail text default '')
returns void language sql as $$
  insert into results values (name, ok, detail);
$$;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000cc01', 'sara@example.test'),
  ('00000000-0000-4000-8000-00000000cc02', 'omar@example.test');

-- --- as a signed-in person ------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000cc01', true);

do $$
begin
  update public.notification_preferences
     set telegram_chat_id = '-1001999888777', telegram_enabled = true
   where user_id = '00000000-0000-4000-8000-00000000cc01';
  perform check_that(
    'a person cannot name their own Telegram chat directly',
    false, 'the update went through');
exception when insufficient_privilege then
  perform check_that(
    'a person cannot name their own Telegram chat directly', true, sqlerrm);
end $$;

select check_that(
  'so no chat is linked and the channel stays off',
  (select telegram_chat_id is null and not telegram_enabled
     from public.notification_preferences
    where user_id = '00000000-0000-4000-8000-00000000cc01'));

-- Everything else on the row is still theirs to change.
do $$
declare n integer;
begin
  update public.notification_preferences
     set remind_overdue = false, due_soon_lead_hours = 4
   where user_id = '00000000-0000-4000-8000-00000000cc01';
  get diagnostics n = row_count;
  perform check_that(
    'and the rest of their preferences are untouched by the guard',
    n = 1, 'rows: ' || n::text);
exception when others then
  perform check_that(
    'and the rest of their preferences are untouched by the guard',
    false, sqlerrm);
end $$;

-- A person still cannot see anybody else's row, link code included.
select check_that(
  'and nobody else''s preferences are readable',
  (select count(*) from public.notification_preferences
    where user_id = '00000000-0000-4000-8000-00000000cc02') = 0);

-- --- as the webhook -------------------------------------------------------
-- The service role carries no `sub`, so auth.uid() is null and the guard
-- stands aside. This is the only path that may name a chat.
reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$
declare n integer;
begin
  update public.notification_preferences
     set telegram_chat_id = '-1001999888777',
         telegram_enabled = true,
         telegram_link_code = null
   where user_id = '00000000-0000-4000-8000-00000000cc01';
  get diagnostics n = row_count;
  perform check_that('the webhook can link the chat it heard from', n = 1);
exception when others then
  perform check_that('the webhook can link the chat it heard from', false, sqlerrm);
end $$;

select check_that(
  'and the link is recorded',
  (select telegram_chat_id = '-1001999888777' and telegram_enabled
     from public.notification_preferences
    where user_id = '00000000-0000-4000-8000-00000000cc01'));

-- --- unlinking stays the owner's ------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000cc01', true);

do $$
declare n integer;
begin
  update public.notification_preferences
     set telegram_enabled = false, telegram_chat_id = null, telegram_link_code = null
   where user_id = '00000000-0000-4000-8000-00000000cc01';
  get diagnostics n = row_count;
  perform check_that('and they can still unlink it themselves', n = 1);
exception when others then
  perform check_that('and they can still unlink it themselves', false, sqlerrm);
end $$;

select check_that(
  'which leaves no chat linked',
  (select telegram_chat_id is null
     from public.notification_preferences
    where user_id = '00000000-0000-4000-8000-00000000cc01'));

reset role;

-- --- results ---------------------------------------------------------------
select
  case when ok then 'PASS' else 'FAIL' end as result,
  name,
  detail
from results
order by ok, name;

select count(*) filter (where ok is not true) as failures from results;

-- A failing check has to fail the run, not just appear in the table above.
-- Printing the rows and exiting 0 is how these files sat in the repo being
-- green by never being asked: psql stops on an *error*, and a FAIL row is
-- not one until something raises.
do $$
declare failed integer;
begin
  select count(*) filter (where ok is not true) into failed from results;
  if failed > 0 then
    raise exception '% check(s) failed — see the table above', failed;
  end if;
end $$;

rollback;
