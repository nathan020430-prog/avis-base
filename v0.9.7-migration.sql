-- ════════════════════════════════════════════════════════════════════
-- Avis Basé — Migration V0.9.7 : Notifications in-app
-- À exécuter UNE FOIS dans Supabase SQL editor.
-- Idempotent : ré-exécutable sans erreur.
-- ════════════════════════════════════════════════════════════════════

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 1. Table notifications                                          │
-- └─────────────────────────────────────────────────────────────────┘
create table if not exists notifications (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null,
  actor_id        uuid,
  type            text not null check (type in ('like','comment','reply','article_validated')),
  target_type     text not null check (target_type in ('article','clip','comment')),
  target_id       uuid not null,
  target_preview  text,
  read            boolean not null default false,
  created_at      timestamptz not null default now(),
  constraint notifications_user_id_fkey
    foreign key (user_id) references profiles(id) on delete cascade,
  constraint notifications_actor_id_fkey
    foreign key (actor_id) references profiles(id) on delete set null
);

-- Si la table existe déjà (ré-exécution), on s'assure que les FK ont
-- les bons noms (pour les embeds PostgREST). Idempotent.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'notifications_user_id_fkey'
  ) then
    alter table notifications drop constraint if exists notifications_user_id_fkey1;
    alter table notifications add constraint notifications_user_id_fkey
      foreign key (user_id) references profiles(id) on delete cascade;
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'notifications_actor_id_fkey'
  ) then
    alter table notifications add constraint notifications_actor_id_fkey
      foreign key (actor_id) references profiles(id) on delete set null;
  end if;
exception when others then null;
end $$;

create index if not exists notifications_user_unread_idx
  on notifications(user_id, read, created_at desc);

create index if not exists notifications_user_created_idx
  on notifications(user_id, created_at desc);

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 2. Row Level Security                                            │
-- └─────────────────────────────────────────────────────────────────┘
alter table notifications enable row level security;

drop policy if exists "users read own notifications" on notifications;
create policy "users read own notifications"
  on notifications for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "users mark own notifications" on notifications;
create policy "users mark own notifications"
  on notifications for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "users delete own notifications" on notifications;
create policy "users delete own notifications"
  on notifications for delete to authenticated
  using (user_id = auth.uid());

-- Pas de policy INSERT : seuls les triggers (SECURITY DEFINER) peuvent insérer.

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 3. Realtime — publier la table sur supabase_realtime            │
-- └─────────────────────────────────────────────────────────────────┘
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table notifications;
  end if;
exception
  when undefined_object then null;  -- publication absente (env de test)
end $$;

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 4. Trigger : notif sur like (vote_type = 1)                     │
-- └─────────────────────────────────────────────────────────────────┘
create or replace function notify_on_vote()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recipient uuid;
  v_preview   text;
begin
  -- Seuls les likes (pas les dislikes) déclenchent une notif
  if new.vote_type <> 1 then
    return new;
  end if;

  if new.target_type = 'article' then
    select author_id, left(coalesce(title,''), 80)
      into v_recipient, v_preview
      from articles
     where id = new.target_id;
  elsif new.target_type = 'comment' then
    select author_id, left(coalesce(content,''), 80)
      into v_recipient, v_preview
      from comments
     where id = new.target_id;
  else
    return new;  -- target_type 'source' : pas de notif pour l'instant
  end if;

  -- Skip si pas de destinataire ou auto-like
  if v_recipient is null or v_recipient = new.user_id then
    return new;
  end if;

  insert into notifications (user_id, actor_id, type, target_type, target_id, target_preview)
  values (v_recipient, new.user_id, 'like', new.target_type, new.target_id, v_preview);

  return new;
end $$;

drop trigger if exists trg_notify_on_vote on votes;
create trigger trg_notify_on_vote
  after insert on votes
  for each row execute function notify_on_vote();

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 5. Trigger : notif sur commentaire                              │
-- │    - 'comment' au propriétaire de l'article                      │
-- │    - 'reply' à l'auteur du commentaire parent (si reply_to_id)   │
-- └─────────────────────────────────────────────────────────────────┘
create or replace function notify_on_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_article_author uuid;
  v_article_title  text;
  v_parent_author  uuid;
  v_comment_excerpt text;
begin
  v_comment_excerpt := left(coalesce(new.content,''), 80);

  -- Notif "comment" au propriétaire de l'article (si target_type='article')
  if new.target_type = 'article' and new.article_id is not null then
    select author_id, left(coalesce(title,''), 80)
      into v_article_author, v_article_title
      from articles
     where id = new.article_id;

    if v_article_author is not null and v_article_author <> new.author_id then
      insert into notifications (user_id, actor_id, type, target_type, target_id, target_preview)
      values (v_article_author, new.author_id, 'comment', 'article', new.article_id, v_article_title);
    end if;
  end if;

  -- Notif "reply" à l'auteur du commentaire parent
  if new.reply_to_id is not null then
    select author_id into v_parent_author
      from comments
     where id = new.reply_to_id;

    if v_parent_author is not null
       and v_parent_author <> new.author_id
       and v_parent_author <> v_article_author then  -- évite double notif si parent = author article
      insert into notifications (user_id, actor_id, type, target_type, target_id, target_preview)
      values (v_parent_author, new.author_id, 'reply', 'comment', new.id, v_comment_excerpt);
    end if;
  end if;

  return new;
end $$;

drop trigger if exists trg_notify_on_comment on comments;
create trigger trg_notify_on_comment
  after insert on comments
  for each row execute function notify_on_comment();

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 6. Trigger : notif quand un article passe à 'published'         │
-- └─────────────────────────────────────────────────────────────────┘
create or replace function notify_on_article_publish()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'published' and (old.status is distinct from 'published') then
    insert into notifications (user_id, actor_id, type, target_type, target_id, target_preview)
    values (new.author_id, null, 'article_validated', 'article', new.id, left(coalesce(new.title,''), 80));
  end if;
  return new;
end $$;

drop trigger if exists trg_notify_on_article_publish on articles;
create trigger trg_notify_on_article_publish
  after update of status on articles
  for each row execute function notify_on_article_publish();

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 7. RPC : marquer toutes les notifs comme lues                    │
-- └─────────────────────────────────────────────────────────────────┘
create or replace function mark_all_notifications_read()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  n int;
begin
  update notifications
     set read = true
   where user_id = auth.uid()
     and read = false;
  get diagnostics n = row_count;
  return n;
end $$;

grant execute on function mark_all_notifications_read() to authenticated;

-- ════════════════════════════════════════════════════════════════════
-- Fin de la migration V0.9.7
-- ════════════════════════════════════════════════════════════════════
