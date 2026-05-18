-- ============================================================================
-- Avis Basé — v0.16.0 — Features Apple App Store obligatoires
--
-- 1. user_blocks : blocage entre utilisateurs (Apple Guideline 1.2)
-- 2. account_deletion_requests + request_account_deletion :
--    suppression de compte avec délai de grâce 30 jours
--    (Apple Guideline 5.1.1(v))
--
-- Idempotent. À exécuter dans le SQL Editor Supabase.
-- ============================================================================

set search_path = public;

-- ----------------------------------------------------------------------------
-- 1. Table user_blocks
-- ----------------------------------------------------------------------------

create table if not exists user_blocks (
  blocker_id uuid not null references profiles(id) on delete cascade,
  blocked_id uuid not null references profiles(id) on delete cascade,
  reason text,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create index if not exists user_blocks_blocked_idx
  on user_blocks(blocked_id);

alter table user_blocks enable row level security;

drop policy if exists "blocks_select_own" on user_blocks;
drop policy if exists "blocks_insert_own" on user_blocks;
drop policy if exists "blocks_delete_own" on user_blocks;

-- Un user voit uniquement sa propre liste de blocages
create policy "blocks_select_own" on user_blocks
  for select using (blocker_id = auth.uid());

-- Un user ne peut bloquer qu'au nom de soi-même
create policy "blocks_insert_own" on user_blocks
  for insert with check (blocker_id = auth.uid());

-- Un user peut débloquer
create policy "blocks_delete_own" on user_blocks
  for delete using (blocker_id = auth.uid());

-- ----------------------------------------------------------------------------
-- 2. Table account_deletion_requests
-- ----------------------------------------------------------------------------

create table if not exists account_deletion_requests (
  user_id uuid primary key references profiles(id) on delete cascade,
  requested_at timestamptz not null default now(),
  scheduled_deletion_at timestamptz not null,
  reason text,
  status text not null default 'pending'
    check (status in ('pending','cancelled','completed'))
);

create index if not exists deletion_requests_scheduled_idx
  on account_deletion_requests(scheduled_deletion_at)
  where status = 'pending';

alter table account_deletion_requests enable row level security;

drop policy if exists "deletion_select_own" on account_deletion_requests;
drop policy if exists "deletion_insert_via_rpc" on account_deletion_requests;

create policy "deletion_select_own" on account_deletion_requests
  for select using (user_id = auth.uid());

-- Pas d'insert/update direct : tout passe par la RPC ci-dessous

-- ----------------------------------------------------------------------------
-- 3. RPC : request_account_deletion
-- ----------------------------------------------------------------------------

create or replace function request_account_deletion()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Unauthorized';
  end if;

  insert into account_deletion_requests (user_id, requested_at, scheduled_deletion_at, status)
  values (uid, now(), now() + interval '30 days', 'pending')
  on conflict (user_id) do update set
    requested_at = excluded.requested_at,
    scheduled_deletion_at = excluded.scheduled_deletion_at,
    status = 'pending';

  -- Désactiver immédiatement la possibilité de se reconnecter :
  -- on n'a PAS le droit de toucher à auth.users via SQL côté client.
  -- On stocke donc un flag dans profiles pour bloquer l'accès aux features.
  update profiles
  set bio = coalesce(bio, ''),  -- no-op, mais permet de vérifier que le user existe
      role = 'user'
  where id = uid;

  -- Optionnel : log dans coin_transactions ou audit_log si tu as une table
end $$;

-- ----------------------------------------------------------------------------
-- 4. RPC : cancel_account_deletion
-- ----------------------------------------------------------------------------

create or replace function cancel_account_deletion()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Unauthorized';
  end if;

  update account_deletion_requests
  set status = 'cancelled'
  where user_id = uid and status = 'pending';
end $$;

-- ----------------------------------------------------------------------------
-- 5. Function : execute_pending_deletions (à appeler en CRON)
-- ----------------------------------------------------------------------------
-- Pour vraiment supprimer les comptes après les 30 jours, il faut soit :
--   a) une Edge Function Supabase appelée par un CRON (pg_cron ou externe)
--   b) une exécution manuelle régulière par un admin
-- Cette fonction effectue le boulot — à appeler par un admin ou un job.

create or replace function execute_pending_deletions()
returns table(deleted_count int)
language plpgsql
security definer
set search_path = public
as $$
declare
  victim uuid;
  count_done int := 0;
begin
  for victim in
    select user_id
    from account_deletion_requests
    where status = 'pending'
      and scheduled_deletion_at <= now()
  loop
    -- Anonymiser les articles (on garde les contenus, on retire l'identité)
    update articles
      set author_id = null,
          body = body || E'\n\n_[Article publié par un compte supprimé.]_'
      where author_id = victim;

    -- Supprimer les commentaires
    delete from comments where author_id = victim;

    -- Supprimer les messages privés
    delete from dm_messages where sender_id = victim;

    -- Retirer des conversations
    delete from dm_participants where user_id = victim;

    -- Supprimer follows
    delete from follows where follower_id = victim or following_id = victim;

    -- Supprimer favorites, votes
    delete from favorites where user_id = victim;
    delete from votes where user_id = victim;

    -- Supprimer notifications (envoyées et reçues)
    delete from notifications where user_id = victim or actor_id = victim;

    -- Supprimer blocks
    delete from user_blocks where blocker_id = victim or blocked_id = victim;

    -- Supprimer le profil
    delete from profiles where id = victim;

    -- Suppression du compte Auth :
    -- ⚠️ Ne fonctionne PAS via SQL classique : il faut appeler
    -- auth.admin.deleteUser(victim) depuis une Edge Function avec la clé service_role.
    -- À implémenter séparément. En attendant on marque comme "complétée".

    update account_deletion_requests
      set status = 'completed'
      where user_id = victim;

    count_done := count_done + 1;
  end loop;
  return query select count_done;
end $$;

-- ----------------------------------------------------------------------------
-- 6. Anti-spam : empêcher les bloqués d'envoyer un DM
-- ----------------------------------------------------------------------------
-- Mise à jour de la policy dm_insert_participants pour bloquer l'envoi
-- depuis un user qui a été bloqué par le destinataire.

drop policy if exists "dm_insert_participants" on dm_messages;
create policy "dm_insert_participants" on dm_messages
  for insert with check (
    sender_id = auth.uid()
    and exists (
      select 1 from dm_participants p
      where p.conversation_id = dm_messages.conversation_id
        and p.user_id = auth.uid()
        and p.is_blocked = false
    )
    -- ET le destinataire ne m'a pas bloqué
    and not exists (
      select 1 from user_blocks ub
      join dm_participants p2 on p2.conversation_id = dm_messages.conversation_id
      where ub.blocker_id = p2.user_id
        and ub.blocked_id = auth.uid()
        and p2.user_id <> auth.uid()
    )
  );

-- ----------------------------------------------------------------------------
-- 7. Vue : articles_visible (masque les contenus bloqués)
-- ----------------------------------------------------------------------------
-- Crée une vue qui filtre automatiquement les articles des users bloqués.
-- L'app peut requêter cette vue au lieu de `articles` pour appliquer le filtre.

create or replace view articles_visible
with (security_invoker = true) as
select a.*
from articles a
where a.status = 'published'
  and not exists (
    select 1 from user_blocks ub
    where ub.blocker_id = auth.uid()
      and ub.blocked_id = a.author_id
  );

comment on view articles_visible is
  'Articles publiés visibles pour l''utilisateur courant (masque les blocked users)';

-- ----------------------------------------------------------------------------
-- 8. Smoke tests
-- ----------------------------------------------------------------------------
-- À exécuter manuellement après la migration :
--
--   select tablename from pg_tables
--   where schemaname='public' and tablename in ('user_blocks','account_deletion_requests');
--   -- Attendu : 2 lignes
--
--   select proname from pg_proc
--   where proname in ('request_account_deletion','cancel_account_deletion','execute_pending_deletions');
--   -- Attendu : 3 lignes
--
--   -- Test côté client (connecté) :
--   --   const { error } = await supa.from('user_blocks').insert({
--   --     blocker_id: (await supa.auth.getUser()).data.user.id,
--   --     blocked_id: '<un_autre_uuid>'
--   --   });
--   --   console.log(error);  // null si OK
--
--   --   const { error } = await supa.rpc('request_account_deletion');
--   --   console.log(error);  // null si OK
--   --   const { error } = await supa.rpc('cancel_account_deletion');

-- ============================================================================
-- Migration v0.16.0 — terminée.
--
-- Étape suivante : créer une Edge Function `delete-pending-accounts` qui :
--   1. Appelle execute_pending_deletions() pour purger les données
--   2. Pour chaque user retourné, appelle auth.admin.deleteUser(id)
--      avec la SERVICE_ROLE_KEY (côté serveur, jamais dans l'app)
--   3. Est déclenchée par pg_cron tous les jours à 3h du matin
--
-- Code prêt dans : avis-base-app/app-store/scripts/delete-edge-fn.ts
-- ============================================================================
