-- ════════════════════════════════════════════════════════════════════
-- Avis Basé — Migration V0.10.0 : Système de follow + fil personnalisé
-- À exécuter UNE FOIS dans Supabase SQL editor.
-- Idempotent : ré-exécutable sans erreur.
-- ════════════════════════════════════════════════════════════════════

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 1. Table follows                                                │
-- └─────────────────────────────────────────────────────────────────┘
create table if not exists follows (
  follower_id   uuid not null,
  following_id  uuid not null,
  created_at    timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint follows_follower_id_fkey
    foreign key (follower_id) references profiles(id) on delete cascade,
  constraint follows_following_id_fkey
    foreign key (following_id) references profiles(id) on delete cascade,
  constraint follows_no_self_follow
    check (follower_id <> following_id)
);

-- Index pour les requêtes courantes
create index if not exists follows_follower_idx
  on follows(follower_id, created_at desc);
create index if not exists follows_following_idx
  on follows(following_id, created_at desc);

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 2. Compteurs dénormalisés sur profiles                          │
-- └─────────────────────────────────────────────────────────────────┘
alter table profiles add column if not exists followers_count  int not null default 0;
alter table profiles add column if not exists following_count  int not null default 0;

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 3. Row Level Security                                            │
-- └─────────────────────────────────────────────────────────────────┘
alter table follows enable row level security;

-- Tout le monde peut voir qui suit qui
drop policy if exists "anyone can read follows" on follows;
create policy "anyone can read follows"
  on follows for select to authenticated
  using (true);

-- Un user ne peut créer que ses propres follows
drop policy if exists "users follow others" on follows;
create policy "users follow others"
  on follows for insert to authenticated
  with check (follower_id = auth.uid());

-- Un user ne peut supprimer que ses propres follows
drop policy if exists "users unfollow" on follows;
create policy "users unfollow"
  on follows for delete to authenticated
  using (follower_id = auth.uid());

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 4. Trigger : mise à jour des compteurs + notification           │
-- └─────────────────────────────────────────────────────────────────┘
create or replace function on_follow_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    -- Incrémenter les compteurs
    update profiles set following_count = following_count + 1 where id = new.follower_id;
    update profiles set followers_count = followers_count + 1 where id = new.following_id;

    -- Notification "follow"
    insert into notifications (user_id, actor_id, type, target_type, target_id, target_preview)
    values (new.following_id, new.follower_id, 'follow', 'profile', new.following_id, null);

    return new;
  elsif TG_OP = 'DELETE' then
    -- Décrémenter les compteurs (plancher à 0)
    update profiles set following_count = greatest(0, following_count - 1) where id = old.follower_id;
    update profiles set followers_count = greatest(0, followers_count - 1) where id = old.following_id;

    return old;
  end if;
  return null;
end $$;

drop trigger if exists trg_on_follow_change on follows;
create trigger trg_on_follow_change
  after insert or delete on follows
  for each row execute function on_follow_change();

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 5. Ajouter 'follow' au type de notification autorisé            │
-- └─────────────────────────────────────────────────────────────────┘
-- La contrainte check sur notifications.type doit inclure 'follow'
do $$
begin
  alter table notifications drop constraint if exists notifications_type_check;
  alter table notifications add constraint notifications_type_check
    check (type in ('like','comment','reply','article_validated','follow'));
exception when others then null;
end $$;

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 6. RPC : compter les follows pour un user donné                 │
-- └─────────────────────────────────────────────────────────────────┘
create or replace function get_following_ids(p_user_id uuid)
returns setof uuid
language sql
security definer
set search_path = public
stable
as $$
  select following_id from follows where follower_id = p_user_id;
$$;

grant execute on function get_following_ids(uuid) to authenticated;

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 7. Realtime — publier follows sur supabase_realtime             │
-- └─────────────────────────────────────────────────────────────────┘
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'follows'
  ) then
    alter publication supabase_realtime add table follows;
  end if;
exception
  when undefined_object then null;
end $$;

-- ════════════════════════════════════════════════════════════════════
-- Fin de la migration V0.10.0
-- ════════════════════════════════════════════════════════════════════
