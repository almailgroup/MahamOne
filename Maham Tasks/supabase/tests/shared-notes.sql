-- ---------------------------------------------------------------------------
-- The privacy rules for My List, checked against the real policies.
--
-- These are the most private rows in the schema: a personal list has no
-- manager override and no admin override, and sharing one is per person and
-- per list. That is enforced entirely by Row Level Security, which no amount
-- of testing the UI can verify — so it is tested here, as three different
-- people, against a database with every migration applied.
--
-- Run with:  psql -f supabase/setup.sql && psql -f supabase/tests/shared-notes.sql
-- Any failed expectation raises, so a non-zero exit means a rule has moved.
-- ---------------------------------------------------------------------------

\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaa0000-0000-4000-8000-000000000001', 'ali@test.local',  '{"full_name":"Ali"}'),
  ('bbbb0000-0000-4000-8000-000000000002', 'sara@test.local', '{"full_name":"Sara"}'),
  ('cccc0000-0000-4000-8000-000000000003', 'omar@test.local', '{"full_name":"Omar"}');

do $$
declare
  ali   constant uuid := 'aaaa0000-0000-4000-8000-000000000001';
  sara  constant uuid := 'bbbb0000-0000-4000-8000-000000000002';
  omar  constant uuid := 'cccc0000-0000-4000-8000-000000000003';
  list  constant uuid := 'dddd0000-0000-4000-8000-000000000004';
  refused boolean;
  seen  bigint;
  owner uuid;

begin
  -- Become somebody. RLS reads auth.uid() from this setting.
  execute 'set local role authenticated';

  -- ---- Ali writes a list ------------------------------------------------
  perform set_config('request.jwt.claim.sub', ali::text, true);

  insert into personal_notes (id, user_id, title, body)
    values (list, ali, 'Site visit', 'Meet at the yard');
  insert into personal_note_items (note_id, user_id, content, position) values
    (list, ali, 'Book the van', 1024),
    (list, ali, 'Print the manifest', 2048);

  -- ---- Before sharing, it is nobody else's business ---------------------
  perform set_config('request.jwt.claim.sub', sara::text, true);
  select count(*) into seen from personal_notes;
  assert seen = 0, 'an unshared list was visible to someone else';
  select count(*) into seen from personal_note_items;
  assert seen = 0, 'the lines of an unshared list were visible to someone else';

  -- Nobody invites themselves.
  refused := false;
  begin
    insert into personal_note_shares (note_id, user_id, added_by)
      values (list, sara, sara);
  exception when insufficient_privilege then refused := true;
  end;
  assert refused, 'someone was able to invite themselves to a list';

  -- ---- Ali shares it ----------------------------------------------------
  perform set_config('request.jwt.claim.sub', ali::text, true);

  refused := false;
  begin
    insert into personal_note_shares (note_id, user_id, added_by)
      values (list, ali, ali);
  exception when insufficient_privilege then refused := true;
  end;
  assert refused, 'an owner was able to share a list with themselves';

  insert into personal_note_shares (note_id, user_id, added_by)
    values (list, sara, ali);

  -- ---- What a collaborator can do ---------------------------------------
  perform set_config('request.jwt.claim.sub', sara::text, true);

  select count(*) into seen from personal_notes;
  assert seen = 1, 'a shared list did not reach the person it was shared with';
  select count(*) into seen from personal_note_items;
  assert seen = 2, 'the lines of a shared list did not come with it';

  insert into personal_note_items (note_id, user_id, content, position)
    values (list, sara, 'Bring the keys', 3072);
  update personal_note_items set done = true where content = 'Book the van';
  update personal_notes set body = 'Sara was here' where id = list;

  select count(*) into seen from personal_note_items where done;
  assert seen = 1, 'a collaborator could not tick a line off';

  -- ---- What a collaborator cannot do ------------------------------------
  update personal_notes set user_id = sara where id = list;
  select user_id into owner from personal_notes where id = list;
  assert owner = ali, 'a collaborator was able to take the list over';

  delete from personal_notes where id = list;
  select count(*) into seen from personal_notes where id = list;
  assert seen = 1, 'a collaborator was able to delete somebody else''s list';

  refused := false;
  begin
    insert into personal_note_shares (note_id, user_id, added_by)
      values (list, omar, sara);
  exception when insufficient_privilege then refused := true;
  end;
  assert refused, 'a collaborator was able to invite somebody else';

  -- ---- Everybody else still sees nothing --------------------------------
  perform set_config('request.jwt.claim.sub', omar::text, true);
  select count(*) into seen from personal_notes;
  assert seen = 0, 'a shared list leaked to somebody it was not shared with';
  select count(*) into seen from personal_note_items;
  assert seen = 0, 'the lines of a shared list leaked';
  select count(*) into seen from personal_note_shares;
  assert seen = 0, 'the share rows leaked';

  -- ---- Leaving ----------------------------------------------------------
  perform set_config('request.jwt.claim.sub', sara::text, true);
  delete from personal_note_shares where note_id = list and user_id = sara;
  select count(*) into seen from personal_notes;
  assert seen = 0, 'leaving a list did not take away access to it';

  -- What she added stays, credited to her.
  perform set_config('request.jwt.claim.sub', ali::text, true);
  select count(*) into seen
    from personal_note_items where content = 'Bring the keys' and user_id = sara;
  assert seen = 1, 'a line added by a collaborator did not survive them leaving';

  -- ---- The owner is still the owner -------------------------------------
  delete from personal_notes where id = list;
  select count(*) into seen from personal_notes where id = list;
  assert seen = 0, 'an owner could not delete their own list';

  raise notice 'shared-notes: every expectation held';
end $$;

rollback;
