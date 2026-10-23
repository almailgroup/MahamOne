-- ---------------------------------------------------------------------------
-- Task attachments — uploaded files and external links.
--
-- Both kinds live in one table so the task detail view renders a single list.
-- A row is either a file (storage_path set) or a link (url set), never both.
-- ---------------------------------------------------------------------------

create table if not exists public.task_attachments (
  id           uuid primary key default gen_random_uuid(),
  task_id      uuid not null references public.tasks (id) on delete cascade,
  uploaded_by  uuid references public.profiles (id) on delete set null,
  kind         text not null check (kind in ('file', 'link')),
  name         text not null,
  storage_path text,
  url          text,
  mime_type    text,
  size_bytes   bigint,
  created_at   timestamptz not null default now(),

  constraint task_attachments_name_length check (length(btrim(name)) between 1 and 255),

  -- Exactly one of storage_path / url, matching `kind`.
  constraint task_attachments_shape check (
    (kind = 'file' and storage_path is not null and url is null)
    or (kind = 'link' and url is not null and storage_path is null)
  ),

  -- Only http(s) links. Blocks javascript: and data: URLs, which would
  -- otherwise become a stored-XSS vector the moment one is rendered as a link.
  constraint task_attachments_url_scheme check (
    url is null or url ~* '^https?://'
  ),

  constraint task_attachments_size check (
    size_bytes is null or (size_bytes >= 0 and size_bytes <= 26214400)
  )
);

create index if not exists task_attachments_task_idx
  on public.task_attachments (task_id, created_at desc);

create unique index if not exists task_attachments_storage_path_key
  on public.task_attachments (storage_path)
  where storage_path is not null;

comment on table public.task_attachments is
  'Files and links attached to a task. Files live in the task-attachments bucket.';

-- --------------------------------------------------------------------------
-- Row Level Security
-- --------------------------------------------------------------------------

alter table public.task_attachments enable row level security;
alter table public.task_attachments force row level security;

drop policy if exists "attachments are readable by authenticated users" on public.task_attachments;
create policy "attachments are readable by authenticated users"
  on public.task_attachments for select
  to authenticated
  using (auth.uid() is not null);

-- Anyone who may edit the task may attach to it.
drop policy if exists "task editors add attachments" on public.task_attachments;
create policy "task editors add attachments"
  on public.task_attachments for insert
  to authenticated
  with check (
    uploaded_by = auth.uid()
    and (public.is_manager_or_admin() or public.can_edit_task(task_id))
  );

drop policy if exists "uploaders and managers remove attachments" on public.task_attachments;
create policy "uploaders and managers remove attachments"
  on public.task_attachments for delete
  to authenticated
  using (uploaded_by = auth.uid() or public.is_manager_or_admin());

grant select, insert, delete on public.task_attachments to authenticated;

-- --------------------------------------------------------------------------
-- Storage bucket
--
-- Private: objects are reached through short-lived signed URLs, so an
-- attachment cannot be read by guessing its path.
--
-- Guarded on the storage schema existing, so this migration also applies to a
-- plain Postgres instance (CI, local validation) that has no Supabase Storage.
-- Object keys are "<task_id>/<uuid>-<filename>", so the first path segment
-- identifies the task an object belongs to.
-- --------------------------------------------------------------------------

do $$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'storage schema not found - skipping bucket and object policies';
    return;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit)
  values ('task-attachments', 'task-attachments', false, 26214400)
  on conflict (id) do update
    set public = false,
        file_size_limit = excluded.file_size_limit;

  execute $p$drop policy if exists "attachment objects readable by authenticated" on storage.objects$p$;
  execute $p$create policy "attachment objects readable by authenticated"
    on storage.objects for select
    to authenticated
    using (bucket_id = 'task-attachments' and auth.uid() is not null)$p$;

  execute $p$drop policy if exists "attachment objects writable by task editors" on storage.objects$p$;
  execute $p$create policy "attachment objects writable by task editors"
    on storage.objects for insert
    to authenticated
    with check (
      bucket_id = 'task-attachments'
      and owner = auth.uid()
      and (
        public.is_manager_or_admin()
        or public.can_edit_task(nullif(split_part(name, '/', 1), '')::uuid)
      )
    )$p$;

  execute $p$drop policy if exists "attachment objects removable by owner or manager" on storage.objects$p$;
  execute $p$create policy "attachment objects removable by owner or manager"
    on storage.objects for delete
    to authenticated
    using (
      bucket_id = 'task-attachments'
      and (owner = auth.uid() or public.is_manager_or_admin())
    )$p$;
end $$;
