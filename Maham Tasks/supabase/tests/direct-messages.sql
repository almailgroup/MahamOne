-- ---------------------------------------------------------------------------
-- A private conversation is private.
--
-- The migration that creates these tables says so in its own first
-- paragraph: readable only by the people in it, and no admin override
-- anywhere in the file. These checks hold the policies to that claim, and
-- they exist because the thing that holds it is not obvious from reading
-- them.
--
-- Both UPDATE policies here pin only *who*: `user_id = auth.uid()` on a
-- participant row, `author_id = auth.uid()` on a message. Neither names the
-- conversation. Read on their own they would let somebody update their own
-- row into a conversation they are not in — joining a private thread, or
-- posting into one.
--
-- What stops it is the SELECT policy. Postgres requires an updated row to
-- still be visible to the caller afterwards, and every SELECT policy on
-- these tables is scoped by exactly the column such an update would have to
-- change: `in_conversation(conversation_id)`. So the new row fails the read
-- check and the update is refused.
--
-- That is a real guarantee and it is also an indirect one: it lives in the
-- SELECT policies rather than in the UPDATE policies that appear to be doing
-- the work. Widen a SELECT policy here for any reason and these two holes
-- open without a line of the UPDATE policies changing. That is what these
-- checks are watching for.
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

-- alice and bob talk to each other. eve is on the team and is not in it.
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000a11ce', 'alice@example.test'),
  ('00000000-0000-4000-8000-00000000b0b0', 'bob@example.test'),
  ('00000000-0000-4000-8000-0000000000ee', 'eve@example.test'),
  ('00000000-0000-4000-8000-0000000000dd', 'dave@example.test');

-- --- alice opens a thread with bob and says something ----------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000a11ce', true);

select set_config(
  'test.theirs',
  public.start_direct_conversation('00000000-0000-4000-8000-00000000b0b0')::text,
  true);

insert into public.direct_messages (conversation_id, author_id, body)
values (current_setting('test.theirs')::uuid,
        '00000000-0000-4000-8000-0000000a11ce',
        'The Kuwait account numbers are 4471 and 4472.');

select check_that(
  'alice can read her own thread',
  (select count(*) from public.direct_messages
    where conversation_id = current_setting('test.theirs')::uuid) = 1);

-- --- eve has a thread of her own, with dave --------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000ee', true);

select set_config(
  'test.hers',
  public.start_direct_conversation('00000000-0000-4000-8000-0000000000dd')::text,
  true);

-- --- baseline: eve cannot see alice and bob's thread ----------------------
select check_that(
  'eve cannot read a conversation she is not in',
  (select count(*) from public.direct_messages
    where conversation_id = current_setting('test.theirs')::uuid) = 0,
  (select count(*)::text from public.direct_messages
    where conversation_id = current_setting('test.theirs')::uuid));

select check_that(
  'eve cannot see the conversation row either',
  (select count(*) from public.conversations
    where id = current_setting('test.theirs')::uuid) = 0);

-- --- eve moves her own participant row into their thread ------------------
--
-- Her row by `user_id = auth.uid()`, both before the update and after. Only
-- the conversation changes, and nothing says which conversation that may be.
do $$
declare moved integer;
begin
  update public.conversation_participants
     set conversation_id = current_setting('test.theirs')::uuid
   where user_id = '00000000-0000-4000-8000-0000000000ee';
  get diagnostics moved = row_count;
  perform check_that(
    'eve cannot move her participant row into their conversation',
    moved = 0, 'rows moved: ' || moved::text);
exception when others then
  perform check_that(
    'eve cannot move her participant row into their conversation',
    true, 'refused: ' || sqlerrm);
end $$;

select check_that(
  'and so eve still cannot read what alice wrote to bob',
  (select count(*) from public.direct_messages
    where conversation_id = current_setting('test.theirs')::uuid) = 0,
  (select coalesce(string_agg(body, ' | '), '(nothing)')
     from public.direct_messages
    where conversation_id = current_setting('test.theirs')::uuid));

-- --- eve moves a message she wrote into their thread ----------------------
do $$
declare
  mine  uuid;
  moved integer;
begin
  insert into public.direct_messages (conversation_id, author_id, body)
  values (current_setting('test.hers')::uuid,
          '00000000-0000-4000-8000-0000000000ee',
          'Ignore those account numbers, use 9999 instead.')
  returning id into mine;

  update public.direct_messages
     set conversation_id = current_setting('test.theirs')::uuid
   where id = mine;
  get diagnostics moved = row_count;

  perform check_that(
    'eve cannot move a message she wrote into their conversation',
    moved = 0, 'rows moved: ' || moved::text);
exception when others then
  perform check_that(
    'eve cannot move a message she wrote into their conversation',
    true, 'refused: ' || sqlerrm);
end $$;

reset role;

-- Checked with row-level security out of the way, so this is what is really
-- in their conversation rather than what eve is allowed to see of it.
select check_that(
  'and nothing of eve''s reached their conversation',
  (select count(*) from public.direct_messages
     where conversation_id = current_setting('test.theirs')::uuid
       and author_id = '00000000-0000-4000-8000-0000000000ee') = 0,
  (select coalesce(string_agg(body, ' | '), '(nothing)')
     from public.direct_messages
    where conversation_id = current_setting('test.theirs')::uuid));

select check_that(
  'and eve is still only in her own',
  (select count(*) from public.conversation_participants
     where user_id = '00000000-0000-4000-8000-0000000000ee'
       and conversation_id = current_setting('test.hers')::uuid) = 1);

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
