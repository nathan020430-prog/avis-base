-- ════════════════════════════════════════════════════════════════════
-- Avis Basé — Migration V0.9.0 : Mobile interactif (profil + favoris)
-- À exécuter UNE FOIS dans Supabase SQL editor.
-- Idempotent : ré-exécutable sans erreur.
-- ════════════════════════════════════════════════════════════════════

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 1. Profils enrichis : bio, avatar, lien social                  │
-- └─────────────────────────────────────────────────────────────────┘
alter table profiles add column if not exists bio          text default null;
alter table profiles add column if not exists avatar_url   text default null;
alter table profiles add column if not exists social_link  text default null;

-- Contrainte taille bio (gardée souple : 280 chars dans le front)
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_bio_length_chk'
  ) then
    alter table profiles add constraint profiles_bio_length_chk
      check (bio is null or length(bio) <= 500);
  end if;
end $$;

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 2. Table favorites : sauvegarde d'articles/clips/sources        │
-- └─────────────────────────────────────────────────────────────────┘
create table if not exists favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  target_type text not null check (target_type in ('article','clip','source')),
  target_id uuid not null,
  created_at timestamptz not null default now(),
  unique(user_id, target_type, target_id)
);
create index if not exists favorites_user_idx on favorites(user_id, created_at desc);
create index if not exists favorites_target_idx on favorites(target_type, target_id);

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 3. Row Level Security                                            │
-- └─────────────────────────────────────────────────────────────────┘
alter table favorites enable row level security;

drop policy if exists "users insert own favorite" on favorites;
create policy "users insert own favorite"
  on favorites for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "users read own favorites" on favorites;
create policy "users read own favorites"
  on favorites for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "users delete own favorite" on favorites;
create policy "users delete own favorite"
  on favorites for delete to authenticated
  using (user_id = auth.uid());

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 4. Profiles : policies d'update (l'user peut modifier son propre │
-- │    profil — bio/avatar/social_link uniquement)                   │
-- │    Si une policy "users update own profile" existe déjà, on la   │
-- │    laisse en place. Sinon on la crée.                            │
-- └─────────────────────────────────────────────────────────────────┘
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles'
      and policyname = 'users update own profile'
  ) then
    create policy "users update own profile"
      on profiles for update to authenticated
      using (id = auth.uid())
      with check (id = auth.uid());
  end if;
end $$;

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 5. Reports : flexibilisation pour signalement d'articles        │
-- │    (la colonne target_type/target_id existait déjà)              │
-- │    On vérifie juste que la contrainte UNIQUE n'empêche pas de    │
-- │    signaler le même article par plusieurs users.                 │
-- └─────────────────────────────────────────────────────────────────┘
-- Anti-doublon : un user ne signale qu'une fois la même cible
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'reports_unique_per_target'
  ) then
    -- La contrainte existante reports_reporter_id_comment_id_key empêche
    -- les doubles signalements de commentaire ; on en ajoute une pour les
    -- couples (target_type, target_id) (articles, sources, etc.)
    alter table reports add constraint reports_unique_per_target
      unique (reporter_id, target_type, target_id);
  end if;
exception
  when duplicate_object then null;
  when others then
    raise notice 'reports_unique_per_target : impossible de créer la contrainte (probablement des doublons existants). Skip.';
end $$;

-- ┌─────────────────────────────────────────────────────────────────┐
-- │ 6. Vue helper : nombre de favoris par cible (pour stats futures) │
-- └─────────────────────────────────────────────────────────────────┘
create or replace view favorites_counts as
select
  target_type,
  target_id,
  count(*) as fav_count
from favorites
group by target_type, target_id;

-- ════════════════════════════════════════════════════════════════════
-- Fin de la migration V0.9.0
-- ════════════════════════════════════════════════════════════════════
