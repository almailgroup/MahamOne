-- ---------------------------------------------------------------------------
-- Adding work from Telegram.
--
-- Once someone has linked Telegram for reminders, anything they send the
-- bot that is not a command is added as theirs. Admins and managers get a
-- general task, assigned to themselves; members, who do not create general
-- tasks or assign them, get an item on a "Telegram" list in My List — the
-- same rules the app has, from the chat.
--
-- add_from_chat() is called by the webhook with the service key, which
-- answers to nobody; so it does the work as the person whose chat it is.
-- Every trigger — the activity log, notifications — sees them as the actor.
--
-- And the assignment reminder is no longer sent to somebody who assigned
-- themselves.
--
-- Run in the Supabase SQL editor after 41. Safe to run more than once.
-- ---------------------------------------------------------------------------

create or replace function public.add_from_chat(
  chat          text,
  item_title    text,
  item_detail   text default null,
  item_priority public.task_priority default 'medium',
  due           timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  person      uuid;
  person_role public.user_role;
  created     uuid;
  inbox       uuid;
  title_text  text := left(btrim(coalesce(item_title, '')), 200);
  detail_text text := nullif(btrim(coalesce(item_detail, '')), '');
begin
  if title_text = '' or chat is null then
    return null;
  end if;

  select np.user_id, p.role into person, person_role
    from public.notification_preferences np
    join public.profiles p on p.id = np.user_id
   where np.telegram_chat_id = chat
   limit 1;
  if person is null then
    return null;
  end if;

  -- From here on, as them.
  perform set_config('request.jwt.claim.sub', person::text, true);

  if person_role in ('admin', 'manager') then
    insert into public.tasks (project_id, title, description, priority, due_at, created_by, position)
    values (
      null, title_text, detail_text, item_priority, due, person,
      coalesce((select max(position) from public.tasks where project_id is null and status = 'todo'), 0) + 1024
    )
    returning id into created;

    insert into public.task_assignments (task_id, user_id) values (created, person);
    return jsonb_build_object('kind', 'task', 'id', created);
  end if;

  select id into inbox
    from public.personal_notes
   where user_id = person and title = 'Telegram'
   order by created_at
   limit 1;
  if inbox is null then
    insert into public.personal_notes (user_id, title) values (person, 'Telegram')
    returning id into inbox;
  end if;

  insert into public.personal_note_items (note_id, user_id, content, position)
  values (
    inbox, person,
    left(concat_ws(' — ', title_text, detail_text), 1000),
    coalesce((select max(position) from public.personal_note_items where note_id = inbox), 0) + 1024
  )
  returning id into created;

  -- To the top of My List, where the newest thing belongs.
  update public.personal_notes set updated_at = now() where id = inbox;
  return jsonb_build_object('kind', 'note', 'id', created);
end;
$$;

revoke all on function public.add_from_chat(text, text, text, public.task_priority, timestamptz)
  from public, anon, authenticated;
grant execute on function public.add_from_chat(text, text, text, public.task_priority, timestamptz)
  to service_role;

-- ---------------------------------------------------------------------------
-- No "Assigned to you" for assigning yourself. Repeated whole from 37 with
-- that one check added.
-- ---------------------------------------------------------------------------

create or replace function public.enqueue_assignment_reminder()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  t public.tasks%rowtype;
  prefs public.notification_preferences%rowtype;
begin
  select * into t from public.tasks where id = new.task_id;
  if not found then return null; end if;

  -- Nobody needs telling that they assigned themselves: from the task form,
  -- or from Telegram, where the bot has just said so.
  if new.user_id = auth.uid() then return null; end if;

  select * into prefs from public.notification_preferences where user_id = new.user_id;
  if not found or not prefs.remind_assigned then return null; end if;

  insert into public.reminder_queue
    (user_id, task_id, channel, kind, recipient, subject, body, dedupe_key)
  select
    new.user_id, t.id, ch.channel, 'assigned',
    ch.recipient,
    'Assigned to you: ' || t.title,
    'You were assigned "' || t.title || '"'
      || coalesce(' - due ' || to_char(t.due_at at time zone public.company_time_zone(), 'Dy DD Mon, HH24:MI'), '') || '.',
    'assigned:' || t.id || ':' || new.user_id || ':' || ch.channel
      || case when ch.channel = 'push' then ':' || ch.recipient else '' end
  from (
    select 'email'::text as channel, (select email from public.profiles where id = new.user_id) as recipient
      where prefs.email_enabled
    union all
    select 'telegram', prefs.telegram_chat_id
      where prefs.telegram_enabled and prefs.telegram_chat_id is not null
    union all
    select 'whatsapp', prefs.whatsapp_number
      where prefs.whatsapp_enabled and prefs.whatsapp_number is not null
    union all
    select 'push', s.endpoint
      from public.push_subscriptions s
     where prefs.push_enabled and s.user_id = new.user_id
  ) ch
  where ch.recipient is not null
  on conflict (dedupe_key) do nothing;

  return null;
end;
$fn$;
