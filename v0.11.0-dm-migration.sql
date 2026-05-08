-- ════════════════════════════════════════════════════════════════════
-- Avis Basé — Migration V0.10.0 : Système de Messagerie Privée (DM)
-- 1-on-1 conversations, real-time, read receipts, typing, attachments,
-- block & report. Strict RLS — aucun admin lecture des DM.
--
-- À exécuter UNE FOIS dans Supabase SQL editor.
-- Idempotent : ré-exécutable sans erreur.
-- ════════════════════════════════════════════════════════════════════

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 1. Tables                                                        │
-- └─────────────────────────────────────────────────────────────────┘

-- Conversations (1-à-1 uniquement dans cette version)
create table if not exists dm_conversations (
  id                    uuid primary key default gen_random_uuid(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  last_message_at       timestamptz not null default now(),
  last_message_preview  text default '',
  last_sender_id        uuid references profiles(id) on delete set null
);

-- Participants (toujours 2 par conversation pour le 1-à-1)
create table if not exists dm_participants (
  conversation_id  uuid not null references dm_conversations(id) on delete cascade,
  user_id          uuid not null references profiles(id) on delete cascade,
  joined_at        timestamptz not null default now(),
  last_read_at     timestamptz not null default '1970-01-01'::timestamptz,
  is_typing        boolean not null default false,
  typing_at        timestamptz,
  is_archived      boolean not null default false,
  primary key (conversation_id, user_id)
);

-- Messages
create table if not exists dm_messages (
  id                uuid primary key default gen_random_uuid(),
  conversation_id   uuid not null references dm_conversations(id) on delete cascade,
  sender_id         uuid not null references profiles(id) on delete cascade,
  content           text not null default '',
  attachment_url    text,
  attachment_type   text check (attachment_type in ('image','file') or attachment_type is null),
  attachment_name   text,
  attachment_size   int,
  created_at        timestamptz not null default now(),
  edited_at         timestamptz,
  deleted_at        timestamptz,
  constraint dm_messages_content_or_attachment
    check (length(content) > 0 or attachment_url is not null),
  constraint dm_messages_content_max_length
    check (length(content) <= 4000)
);

-- Blocks (un user bloque un autre — empêche la création de nouvelle conversation
-- mais l'historique reste accessible)
create table if not exists dm_blocks (
  blocker_id   uuid not null references profiles(id) on delete cascade,
  blocked_id   uuid not null references profiles(id) on delete cascade,
  created_at   timestamptz not null default now(),
  reason       text,
  primary key (blocker_id, blocked_id),
  constraint dm_blocks_no_self check (blocker_id <> blocked_id)
);

-- Reports
create table if not exists dm_reports (
  id              uuid primary key default gen_random_uuid(),
  reporter_id     uuid not null references profiles(id) on delete cascade,
  reported_id     uuid not null references profiles(id) on delete cascade,
  conversation_id uuid references dm_conversations(id) on delete set null,
  message_id      uuid references dm_messages(id) on delete set null,
  reason          text not null,
  description     text,
  status          text not null default 'pending' check (status in ('pending','reviewed','dismissed','actioned')),
  created_at      timestamptz not null default now(),
  reviewed_at     timestamptz,
  reviewed_by     uuid references profiles(id) on delete set null
);

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 2. Indexes                                                       │
-- └─────────────────────────────────────────────────────────────────┘

create index if not exists dm_messages_conv_idx
  on dm_messages(conversation_id, created_at desc);
create index if not exists dm_messages_sender_idx
  on dm_messages(sender_id, created_at desc);
create index if not exists dm_participants_user_idx
  on dm_participants(user_id, is_archived);
create index if not exists dm_conversations_updated_idx
  on dm_conversations(last_message_at desc);
create index if not exists dm_blocks_blocker_idx
  on dm_blocks(blocker_id);
create index if not exists dm_blocks_blocked_idx
  on dm_blocks(blocked_id);
create index if not exists dm_reports_status_idx
  on dm_reports(status, created_at desc);

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 3. RLS — Strict : seuls les participants accèdent à leurs DM    │
-- └─────────────────────────────────────────────────────────────────┘

alter table dm_conversations enable row level security;
alter table dm_participants  enable row level security;
alter table dm_messages       enable row level security;
alter table dm_blocks         enable row level security;
alter table dm_reports        enable row level security;

-- ─── dm_conversations ───────────────────────────────────────
drop policy if exists "users read own conversations" on dm_conversations;
create policy "users read own conversations"
  on dm_conversations for select to authenticated
  using (
    exists (
      select 1 from dm_participants p
      where p.conversation_id = dm_conversations.id
        and p.user_id = auth.uid()
    )
  );

-- INSERT/UPDATE/DELETE de dm_conversations passent par RPC SECURITY DEFINER

-- ─── dm_participants ────────────────────────────────────────
drop policy if exists "users read participants of own convs" on dm_participants;
create policy "users read participants of own convs"
  on dm_participants for select to authenticated
  using (
    exists (
      select 1 from dm_participants me
      where me.conversation_id = dm_participants.conversation_id
        and me.user_id = auth.uid()
    )
  );

drop policy if exists "users update own participation" on dm_participants;
create policy "users update own participation"
  on dm_participants for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ─── dm_messages ────────────────────────────────────────────
drop policy if exists "users read messages of own convs" on dm_messages;
create policy "users read messages of own convs"
  on dm_messages for select to authenticated
  using (
    exists (
      select 1 from dm_participants p
      where p.conversation_id = dm_messages.conversation_id
        and p.user_id = auth.uid()
    )
  );

drop policy if exists "users insert own messages" on dm_messages;
create policy "users insert own messages"
  on dm_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from dm_participants p
      where p.conversation_id = dm_messages.conversation_id
        and p.user_id = auth.uid()
    )
    -- on bloque l'envoi si l'autre participant a bloqué l'expéditeur
    and not exists (
      select 1 from dm_blocks b
      join dm_participants p2 on p2.user_id = b.blocker_id
      where p2.conversation_id = dm_messages.conversation_id
        and p2.user_id <> auth.uid()
        and b.blocked_id = auth.uid()
    )
  );

drop policy if exists "users edit own messages" on dm_messages;
create policy "users edit own messages"
  on dm_messages for update to authenticated
  using (sender_id = auth.uid())
  with check (sender_id = auth.uid());

drop policy if exists "users delete own messages" on dm_messages;
create policy "users delete own messages"
  on dm_messages for delete to authenticated
  using (sender_id = auth.uid());

-- ─── dm_blocks ──────────────────────────────────────────────
drop policy if exists "users read own blocks" on dm_blocks;
create policy "users read own blocks"
  on dm_blocks for select to authenticated
  using (blocker_id = auth.uid() or blocked_id = auth.uid());

drop policy if exists "users insert own block" on dm_blocks;
create policy "users insert own block"
  on dm_blocks for insert to authenticated
  with check (blocker_id = auth.uid());

drop policy if exists "users delete own block" on dm_blocks;
create policy "users delete own block"
  on dm_blocks for delete to authenticated
  using (blocker_id = auth.uid());

-- ─── dm_reports ─────────────────────────────────────────────
drop policy if exists "users insert own report" on dm_reports;
create policy "users insert own report"
  on dm_reports for insert to authenticated
  with check (reporter_id = auth.uid());

drop policy if exists "users read own reports" on dm_reports;
create policy "users read own reports"
  on dm_reports for select to authenticated
  using (reporter_id = auth.uid());

drop policy if exists "admins read all reports" on dm_reports;
create policy "admins read all reports"
  on dm_reports for select to authenticated
  using (
    exists (
      select 1 from profiles
      where profiles.id = auth.uid()
        and profiles.role in ('admin','superadmin')
    )
  );

drop policy if exists "admins update reports" on dm_reports;
create policy "admins update reports"
  on dm_reports for update to authenticated
  using (
    exists (
      select 1 from profiles
      where profiles.id = auth.uid()
        and profiles.role in ('admin','superadmin')
    )
  );

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 4. Triggers : maintenir last_message_at + preview               │
-- └─────────────────────────────────────────────────────────────────┘

create or replace function dm_update_conversation_on_message()
returns trigger language plpgsql as $$
begin
  update dm_conversations
  set last_message_at      = new.created_at,
      last_sender_id       = new.sender_id,
      last_message_preview = case
        when new.attachment_url is not null and (new.content is null or length(new.content)=0)
          then case when new.attachment_type='image' then '📷 Image' else '📎 Fichier' end
        else left(new.content, 100)
      end,
      updated_at = now()
  where id = new.conversation_id;
  return new;
end $$;

drop trigger if exists trg_dm_update_conv_on_msg on dm_messages;
create trigger trg_dm_update_conv_on_msg
  after insert on dm_messages
  for each row execute function dm_update_conversation_on_message();

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 5. RPC : ouvrir/créer une conversation 1-à-1                    │
-- └─────────────────────────────────────────────────────────────────┘

create or replace function dm_open_conversation(other_user_id uuid)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  me uuid := auth.uid();
  conv_id uuid;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  if other_user_id = me then raise exception 'cannot_dm_self'; end if;

  -- Vérifie que ni l'un ni l'autre n'a bloqué
  if exists (
    select 1 from dm_blocks
    where (blocker_id = me and blocked_id = other_user_id)
       or (blocker_id = other_user_id and blocked_id = me)
  ) then
    raise exception 'blocked';
  end if;

  -- Cherche une conversation 1-à-1 existante entre les deux
  select c.id into conv_id
  from dm_conversations c
  join dm_participants p1 on p1.conversation_id = c.id and p1.user_id = me
  join dm_participants p2 on p2.conversation_id = c.id and p2.user_id = other_user_id
  where (
    select count(*) from dm_participants p3
    where p3.conversation_id = c.id
  ) = 2
  limit 1;

  if conv_id is not null then return conv_id; end if;

  -- Création
  insert into dm_conversations default values returning id into conv_id;
  insert into dm_participants(conversation_id, user_id) values (conv_id, me);
  insert into dm_participants(conversation_id, user_id) values (conv_id, other_user_id);

  return conv_id;
end $$;

revoke all on function dm_open_conversation(uuid) from public;
grant execute on function dm_open_conversation(uuid) to authenticated;

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 6. RPC : marquer comme lu                                        │
-- └─────────────────────────────────────────────────────────────────┘

create or replace function dm_mark_read(conv_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not_authenticated'; end if;
  update dm_participants
  set last_read_at = now()
  where conversation_id = conv_id and user_id = me;
end $$;

revoke all on function dm_mark_read(uuid) from public;
grant execute on function dm_mark_read(uuid) to authenticated;

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 7. RPC : indicateur "en train d'écrire"                         │
-- └─────────────────────────────────────────────────────────────────┘

create or replace function dm_set_typing(conv_id uuid, typing boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not_authenticated'; end if;
  update dm_participants
  set is_typing = typing,
      typing_at = case when typing then now() else null end
  where conversation_id = conv_id and user_id = me;
end $$;

revoke all on function dm_set_typing(uuid, boolean) from public;
grant execute on function dm_set_typing(uuid, boolean) to authenticated;

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 8. RPC : compter messages non-lus (pour badge nav)              │
-- └─────────────────────────────────────────────────────────────────┘

create or replace function dm_unread_count()
returns int
language sql security definer set search_path = public stable
as $$
  select coalesce(count(*)::int, 0)
  from dm_messages m
  join dm_participants p on p.conversation_id = m.conversation_id
  where p.user_id = auth.uid()
    and m.sender_id <> auth.uid()
    and m.created_at > p.last_read_at
    and m.deleted_at is null
$$;

revoke all on function dm_unread_count() from public;
grant execute on function dm_unread_count() to authenticated;

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 9. RPC : liste des conversations avec preview                    │
-- └─────────────────────────────────────────────────────────────────┘

create or replace function dm_list_conversations()
returns table (
  conversation_id      uuid,
  last_message_at      timestamptz,
  last_message_preview text,
  last_sender_id       uuid,
  unread_count         int,
  other_user_id        uuid,
  other_username       text,
  other_avatar_url     text,
  other_role           text,
  is_blocked_by_me     boolean,
  is_archived          boolean
)
language sql security definer set search_path = public stable
as $$
  select
    c.id,
    c.last_message_at,
    c.last_message_preview,
    c.last_sender_id,
    (select count(*)::int from dm_messages m
       where m.conversation_id = c.id
         and m.sender_id <> auth.uid()
         and m.created_at > me.last_read_at
         and m.deleted_at is null),
    other.id,
    other.username,
    other.avatar_url,
    other.role,
    exists (select 1 from dm_blocks b where b.blocker_id = auth.uid() and b.blocked_id = other.id),
    me.is_archived
  from dm_conversations c
  join dm_participants me on me.conversation_id = c.id and me.user_id = auth.uid()
  join dm_participants op on op.conversation_id = c.id and op.user_id <> auth.uid()
  join profiles other on other.id = op.user_id
  order by c.last_message_at desc
$$;

revoke all on function dm_list_conversations() from public;
grant execute on function dm_list_conversations() to authenticated;

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 10. RPC : block / unblock                                       │
-- └─────────────────────────────────────────────────────────────────┘

create or replace function dm_block_user(target_id uuid, block_reason text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not_authenticated'; end if;
  if target_id = me then raise exception 'cannot_block_self'; end if;
  insert into dm_blocks(blocker_id, blocked_id, reason)
    values (me, target_id, block_reason)
    on conflict (blocker_id, blocked_id) do update set reason = excluded.reason;
end $$;

create or replace function dm_unblock_user(target_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not_authenticated'; end if;
  delete from dm_blocks where blocker_id = me and blocked_id = target_id;
end $$;

revoke all on function dm_block_user(uuid, text) from public;
revoke all on function dm_unblock_user(uuid) from public;
grant execute on function dm_block_user(uuid, text) to authenticated;
grant execute on function dm_unblock_user(uuid) to authenticated;

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 11. RPC : signaler                                              │
-- └─────────────────────────────────────────────────────────────────┘

create or replace function dm_report_user(
  target_id uuid,
  conv_id uuid default null,
  msg_id uuid default null,
  report_reason text default 'other',
  report_description text default null
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  me uuid := auth.uid();
  new_id uuid;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  insert into dm_reports(reporter_id, reported_id, conversation_id, message_id, reason, description)
    values (me, target_id, conv_id, msg_id, report_reason, report_description)
    returning id into new_id;
  return new_id;
end $$;

revoke all on function dm_report_user(uuid, uuid, uuid, text, text) from public;
grant execute on function dm_report_user(uuid, uuid, uuid, text, text) to authenticated;

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 12. RPC : archiver / désarchiver une conversation               │
-- └─────────────────────────────────────────────────────────────────┘

create or replace function dm_archive_conversation(conv_id uuid, archived boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not_authenticated'; end if;
  update dm_participants
  set is_archived = archived
  where conversation_id = conv_id and user_id = me;
end $$;

revoke all on function dm_archive_conversation(uuid, boolean) from public;
grant execute on function dm_archive_conversation(uuid, boolean) to authenticated;

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 13. Realtime : activer la publication                           │
-- └─────────────────────────────────────────────────────────────────┘

-- À exécuter en supplément si besoin (souvent déjà activé via UI Supabase) :
-- alter publication supabase_realtime add table dm_messages;
-- alter publication supabase_realtime add table dm_participants;

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 14. Storage : bucket pour pièces jointes                        │
-- │     IMPORTANT : exécuter dans Supabase Storage UI ou via API    │
-- │     car les buckets ne se créent pas via SQL pur.               │
-- └─────────────────────────────────────────────────────────────────┘

-- Crée le bucket privé "dm-attachments" si absent
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'dm-attachments',
  'dm-attachments',
  false,
  10485760, -- 10 MB
  array['image/jpeg','image/png','image/gif','image/webp','application/pdf','text/plain']
)
on conflict (id) do nothing;

-- Storage policies : un user lit/écrit uniquement les fichiers de ses conversations
-- Le path du fichier doit suivre le format : {conversation_id}/{filename}

drop policy if exists "dm storage upload" on storage.objects;
create policy "dm storage upload"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'dm-attachments'
    and exists (
      select 1 from dm_participants
      where conversation_id::text = (storage.foldername(name))[1]
        and user_id = auth.uid()
    )
  );

drop policy if exists "dm storage read" on storage.objects;
create policy "dm storage read"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'dm-attachments'
    and exists (
      select 1 from dm_participants
      where conversation_id::text = (storage.foldername(name))[1]
        and user_id = auth.uid()
    )
  );

drop policy if exists "dm storage delete own" on storage.objects;
create policy "dm storage delete own"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'dm-attachments'
    and owner = auth.uid()
  );

-- ════════════════════════════════════════════════════════════════════
-- FIN MIGRATION V0.10.0
-- ════════════════════════════════════════════════════════════════════
