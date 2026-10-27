-- ---------------------------------------------------------------------------
-- Adding work from Telegram: a planner's message becomes a task, a member's
-- an item in My List, and only the server may call it.
--
--   psql -f supabase/tests/shim.sql -f supabase/setup.sql -f this file
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
  ('00000000-0000-4000-8000-0000000042a1', 'admin@example.test');
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000042c1', 'doer@example.test');

update public.notification_preferences set telegram_chat_id = '1001', telegram_enabled = true
 where user_id = '00000000-0000-4000-8000-0000000042a1';
update public.notification_preferences set telegram_chat_id = '2002', telegram_enabled = true
 where user_id = '00000000-0000-4000-8000-0000000042c1';

-- --- an admin's message --------------------------------------------------------------

create temporary table added as
  select public.add_from_chat('1001', '  Call the bank  ', 'Ask about the mandate', 'high',
                              timestamptz '2026-10-20 17:00 Asia/Kuwait') as result;

select check_that('an admin''s message becomes a task',
  (select result ->> 'kind' from added) = 'task', (select result::text from added));

select check_that('…with what they wrote, tidied',
  exists (select 1 from public.tasks
           where id = ((select result ->> 'id' from added))::uuid
             and title = 'Call the bank' and description = 'Ask about the mandate'
             and priority = 'high' and project_id is null
             and due_at = timestamptz '2026-10-20 17:00 Asia/Kuwait'
             and created_by = '00000000-0000-4000-8000-0000000042a1'));

select check_that('…assigned to them',
  exists (select 1 from public.task_assignments
           where task_id = ((select result ->> 'id' from added))::uuid
             and user_id = '00000000-0000-4000-8000-0000000042a1'));

select check_that('…recorded as done by them',
  exists (select 1 from public.task_activity
           where task_id = ((select result ->> 'id' from added))::uuid
             and actor_id = '00000000-0000-4000-8000-0000000042a1'),
  (select string_agg(coalesce(actor_id::text, 'null') || ':' || action, ', ') from public.task_activity
    where task_id = ((select result ->> 'id' from added))::uuid));

select check_that('…and they are not sent "assigned to you" for it',
  not exists (select 1 from public.reminder_queue
               where kind = 'assigned'
                 and user_id = '00000000-0000-4000-8000-0000000042a1'));

-- --- a member's ---------------------------------------------------------------

select set_config('request.jwt.claim.sub', '', true);
select public.add_from_chat('2002', 'Buy stamps', 'for the contracts');
select set_config('request.jwt.claim.sub', '', true);
select public.add_from_chat('2002', 'Book the meeting room');

select check_that('a member''s messages go to one Telegram list in My List',
  (select count(*) from public.personal_notes
    where user_id = '00000000-0000-4000-8000-0000000042c1' and title = 'Telegram') = 1);

select check_that('…one item each, in order',
  (select array_agg(i.content order by i.position)
     from public.personal_note_items i
     join public.personal_notes n on n.id = i.note_id
    where n.user_id = '00000000-0000-4000-8000-0000000042c1')
  = array['Buy stamps — for the contracts', 'Book the meeting room']);

select check_that('…and no task, which a member does not create here',
  not exists (select 1 from public.tasks where created_by = '00000000-0000-4000-8000-0000000042c1'));

-- --- nothing from nowhere ---------------------------------------------------------

select check_that('a chat nobody linked adds nothing',
  public.add_from_chat('9999', 'Anything') is null);
select check_that('nor does an empty message',
  public.add_from_chat('1001', '   ') is null);

-- --- only the server ----------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000042c1', true);
do $$
begin
  perform public.add_from_chat('1001', 'Pretend to be the admin');
  perform check_that('a signed-in session cannot add as somebody else', false, 'it ran');
exception when insufficient_privilege then
  perform check_that('a signed-in session cannot add as somebody else', true, sqlerrm);
end $$;
reset role;

-- --- results ---------------------------------------------------------------

select
  case when ok then 'PASS' else 'FAIL' end as result,
  name,
  detail
from results
order by ok, name;

select count(*) filter (where ok is not true) as failures from results;

do $$
declare failed integer;
begin
  select count(*) filter (where ok is not true) into failed from results;
  if failed > 0 then
    raise exception '% check(s) failed — see the table above', failed;
  end if;
end $$;

rollback;
