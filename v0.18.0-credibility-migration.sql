-- ============================================================================
-- Avis Basé — v0.18.0 — Phase 3 : Crédibilité enrichie
--
-- Ajoute :
--   - Table cred_score_history pour tracer l'évolution du score
--   - RPC recompute_user_cred_score qui calcule + persiste + log l'historique
--   - RPC get_user_cred_breakdown qui renvoie le détail (d'où vient le score)
--
-- Note : on ne câble pas de triggers automatiques sur articles/votes/comments
-- pour éviter de casser des flows existants. Le admin peut call
-- recompute_user_cred_score() manuellement ou via cron.
--
-- Idempotent. ASCII pur. À appliquer APRÈS v0.18.0-trust-migration.sql.
-- ============================================================================

set search_path = public;

-- ----------------------------------------------------------------------------
-- 1. Table cred_score_history
-- ----------------------------------------------------------------------------

create table if not exists cred_score_history (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references profiles(id) on delete cascade,
  score_before    int not null,
  score_after     int not null,
  delta           int generated always as (score_after - score_before) stored,
  reason          text not null default 'recompute',
  related_type    text,
  related_id      uuid,
  created_at      timestamptz not null default now()
);

create index if not exists cred_history_user_created_idx on cred_score_history(user_id, created_at desc);

alter table cred_score_history enable row level security;

drop policy if exists "cred_history_select_own" on cred_score_history;
drop policy if exists "cred_history_select_public_certified" on cred_score_history;

-- Un user voit son propre historique
create policy "cred_history_select_own" on cred_score_history
  for select using (user_id = auth.uid());

-- Public peut voir l'historique des users certifiés (transparence)
create policy "cred_history_select_public_certified" on cred_score_history
  for select using (
    exists (
      select 1 from contributor_certifications c
      where c.user_id = cred_score_history.user_id and c.status = 'certified'
    )
  );

-- INSERT réservé au service_role + RPC


-- ----------------------------------------------------------------------------
-- 2. RPC : recompute_user_cred_score
-- ----------------------------------------------------------------------------
-- Recalcule le score d'un user et persiste si changement. Log l'historique.
-- Formule (alignée sur computeUserCredScore frontend) :
--   raw = articles_published*1 + sources_added*2 + comments_count*0.5
--       + weighted_likes_received*1 + weighted_useful_comments*2
--       + validated_reports*-5
--   clamp 0..200, puis × 0.5 → score 0..100

create or replace function recompute_user_cred_score(p_user_id uuid, p_reason text default 'recompute')
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := coalesce(p_user_id, auth.uid());
  v_raw numeric;
  v_score int;
  v_old_score int;
begin
  if v_uid is null then return -1; end if;

  select coalesce(credibility_score, 0) into v_old_score from profiles where id = v_uid;

  select coalesce(articles_published, 0) * 1
       + coalesce(sources_added, 0) * 2
       + coalesce(comments_count, 0) * 0.5
       + coalesce(weighted_likes_received, 0) * 1
       + coalesce(weighted_useful_comments, 0) * 2
       + coalesce(validated_reports, 0) * -5
    into v_raw
    from profiles
   where id = v_uid;

  -- Clamp 0..200 puis normalise sur 100
  v_score := round(greatest(0, least(v_raw, 200)) * 0.5)::int;

  -- Si changement, persiste + log
  if v_old_score is null or v_old_score <> v_score then
    update profiles set credibility_score = v_score where id = v_uid;
    insert into cred_score_history (user_id, score_before, score_after, reason)
    values (v_uid, coalesce(v_old_score, 0), v_score, p_reason);
  end if;

  return v_score;
end $$;


-- ----------------------------------------------------------------------------
-- 3. RPC : get_user_cred_breakdown
-- ----------------------------------------------------------------------------
-- Renvoie le détail "d'où vient ce score" — JSON avec points par catégorie.

create or replace function get_user_cred_breakdown(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_p record;
  v_result jsonb;
begin
  if p_user_id is null then return jsonb_build_object('error', 'no_user'); end if;

  select articles_published, sources_added, comments_count,
         weighted_likes_received, weighted_useful_comments,
         validated_reports, credibility_score
    into v_p
    from profiles
   where id = p_user_id;

  if not found then return jsonb_build_object('error', 'not_found'); end if;

  v_result := jsonb_build_object(
    'score', coalesce(v_p.credibility_score, 0),
    'breakdown', jsonb_build_array(
      jsonb_build_object('label', 'Articles publiés', 'count', coalesce(v_p.articles_published, 0), 'weight', 1, 'points', coalesce(v_p.articles_published, 0) * 1.0),
      jsonb_build_object('label', 'Sources ajoutées', 'count', coalesce(v_p.sources_added, 0), 'weight', 2, 'points', coalesce(v_p.sources_added, 0) * 2.0),
      jsonb_build_object('label', 'Commentaires', 'count', coalesce(v_p.comments_count, 0), 'weight', 0.5, 'points', coalesce(v_p.comments_count, 0) * 0.5),
      jsonb_build_object('label', 'Likes pondérés reçus', 'count', coalesce(v_p.weighted_likes_received, 0), 'weight', 1, 'points', coalesce(v_p.weighted_likes_received, 0) * 1.0),
      jsonb_build_object('label', 'Commentaires utiles pondérés', 'count', coalesce(v_p.weighted_useful_comments, 0), 'weight', 2, 'points', coalesce(v_p.weighted_useful_comments, 0) * 2.0),
      jsonb_build_object('label', 'Signalements validés', 'count', coalesce(v_p.validated_reports, 0), 'weight', -5, 'points', coalesce(v_p.validated_reports, 0) * -5.0)
    ),
    'max_raw_for_100pct', 200
  );

  return v_result;
end $$;


-- ----------------------------------------------------------------------------
-- 4. RPC : recompute_all_cred_scores (admin only, batch reconciliation)
-- ----------------------------------------------------------------------------

create or replace function recompute_all_cred_scores()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_admin boolean;
  v_uid uuid;
  v_count int := 0;
begin
  select role in ('admin','superadmin')
    into v_is_admin
    from profiles
   where id = auth.uid();
  if v_is_admin is null or v_is_admin = false then
    raise exception 'Forbidden : admin required';
  end if;

  for v_uid in select id from profiles loop
    perform recompute_user_cred_score(v_uid, 'batch_recompute');
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;


-- ============================================================================
-- Smoke tests :
--   select tablename from pg_tables where schemaname='public' and tablename='cred_score_history';
--   select proname from pg_proc where proname in ('recompute_user_cred_score','get_user_cred_breakdown','recompute_all_cred_scores');
--   select recompute_user_cred_score();  -- connecté → recalcule mon score
--   select get_user_cred_breakdown(auth.uid());
-- ============================================================================
-- Migration v0.18.0 Phase 3 — terminée.
-- ============================================================================
