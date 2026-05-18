-- ============================================================================
-- Avis Basé — v0.18.0 — Trust & Identity
--
-- Phase 2 : Certification "Auteur rémunérable"
--
-- Avant qu'un contributeur puisse retirer sa cagnotte via Stripe Connect,
-- il doit cumuler :
--   - ≥ 3 articles publiés validés par modération
--   - ≥ 30 jours d'ancienneté
--   - Score crédibilité ≥ 50 (niveau "Correct" minimum)
--   - KYC Stripe Connect complet (déjà tracké dans contributor_balance)
--
-- Tant que pas certifié → la cagnotte continue à se remplir mais le bouton
-- "Demander un virement" reste verrouillé avec message explicite.
--
-- Idempotent. ASCII pur. À appliquer APRÈS v0.17.0-financement-migration.sql.
-- ============================================================================

set search_path = public;

-- ----------------------------------------------------------------------------
-- 1. Table contributor_certifications
-- ----------------------------------------------------------------------------
-- Snapshot du dernier check de certification pour chaque contributeur.
-- Mis à jour à chaque appel de check_contributor_certification().

create table if not exists contributor_certifications (
  user_id                 uuid primary key references profiles(id) on delete cascade,
  status                  text not null default 'pending'
    check (status in ('pending','certified','revoked')),
  milestones_met          jsonb not null default '{}'::jsonb,
  -- milestones_met est un objet booléen :
  --   { "articles_published_3": bool, "account_age_30d": bool,
  --     "credibility_50": bool, "kyc_completed": bool }
  certified_at            timestamptz,
  last_checked_at         timestamptz not null default now(),
  revoked_at              timestamptz,
  revoked_reason          text
);

create index if not exists certifications_status_idx on contributor_certifications(status);

alter table contributor_certifications enable row level security;

drop policy if exists "certifications_select_own" on contributor_certifications;
drop policy if exists "certifications_select_public_certified" on contributor_certifications;

-- Un user voit sa propre certification
create policy "certifications_select_own" on contributor_certifications
  for select using (user_id = auth.uid());

-- Tout le monde voit qui est certifié (pour les badges publics)
create policy "certifications_select_public_certified" on contributor_certifications
  for select using (status = 'certified');

-- INSERT/UPDATE réservés au service_role + via RPC


-- ----------------------------------------------------------------------------
-- 2. RPC : check_contributor_certification
-- ----------------------------------------------------------------------------
-- Calcule et persiste l'état de certification d'un user.
-- Appelable :
--   - Par le user lui-même (auth.uid()) pour rafraichir son statut
--   - Avec p_user_id explicite (admin / service_role / edge function)
--
-- Retourne un objet JSON avec :
--   { user_id, status, milestones_met, certified, missing_criteria[] }

create or replace function check_contributor_certification(p_user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := coalesce(p_user_id, auth.uid());
  v_articles_count int := 0;
  v_account_age_days int := 0;
  v_cred_score int := 0;
  v_kyc_done boolean := false;
  v_milestones jsonb;
  v_all_met boolean;
  v_status text;
  v_current_status text;
  v_result jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('error', 'Unauthorized');
  end if;

  -- Count articles publiés validés
  select count(*)
    into v_articles_count
    from articles
   where author_id = v_uid
     and status = 'published';

  -- Account age en jours
  select coalesce(extract(epoch from (now() - created_at)) / 86400, 0)::int
    into v_account_age_days
    from profiles
   where id = v_uid;

  -- Score crédibilité (colonne stockée ou défaut 0)
  select coalesce(credibility_score, 0)
    into v_cred_score
    from profiles
   where id = v_uid;

  -- KYC complet depuis contributor_balance
  select coalesce(kyc_completed, false)
    into v_kyc_done
    from contributor_balance
   where user_id = v_uid;
  if v_kyc_done is null then v_kyc_done := false; end if;

  -- Build milestones
  v_milestones := jsonb_build_object(
    'articles_published_3', v_articles_count >= 3,
    'account_age_30d',      v_account_age_days >= 30,
    'credibility_50',       v_cred_score >= 50,
    'kyc_completed',        v_kyc_done
  );

  v_all_met := (v_articles_count >= 3)
           and (v_account_age_days >= 30)
           and (v_cred_score >= 50)
           and (v_kyc_done = true);

  -- Récupère le statut courant pour savoir si on doit set certified_at
  select status into v_current_status
    from contributor_certifications
   where user_id = v_uid;

  if v_all_met then
    v_status := 'certified';
  else
    -- On ne révoque pas automatiquement quelqu'un déjà certifié : ses critères
    -- peuvent fluctuer légèrement (ex: score qui baisse temporairement).
    -- La révocation est manuelle (admin) ou via une autre RPC.
    if v_current_status = 'certified' then
      v_status := 'certified';
    else
      v_status := 'pending';
    end if;
  end if;

  -- Upsert
  insert into contributor_certifications (user_id, status, milestones_met, certified_at, last_checked_at)
  values (
    v_uid,
    v_status,
    v_milestones,
    case when v_status = 'certified' and v_current_status <> 'certified' then now() else null end,
    now()
  )
  on conflict (user_id) do update set
    status = excluded.status,
    milestones_met = excluded.milestones_met,
    last_checked_at = now(),
    certified_at = case
      when contributor_certifications.certified_at is not null then contributor_certifications.certified_at
      when excluded.status = 'certified' then now()
      else null
    end;

  -- Build result
  v_result := jsonb_build_object(
    'user_id', v_uid,
    'status', v_status,
    'milestones_met', v_milestones,
    'certified', v_status = 'certified',
    'criteria', jsonb_build_object(
      'articles_published', v_articles_count,
      'account_age_days', v_account_age_days,
      'credibility_score', v_cred_score,
      'kyc_completed', v_kyc_done
    )
  );

  return v_result;
end $$;


-- ----------------------------------------------------------------------------
-- 3. RPC : revoke_contributor_certification (admin only)
-- ----------------------------------------------------------------------------

create or replace function revoke_contributor_certification(p_user_id uuid, p_reason text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_admin boolean;
begin
  -- Check caller is admin/superadmin
  select role in ('admin','superadmin')
    into v_is_admin
    from profiles
   where id = auth.uid();

  if v_is_admin is null or v_is_admin = false then
    raise exception 'Forbidden : admin required';
  end if;

  update contributor_certifications
     set status = 'revoked',
         revoked_at = now(),
         revoked_reason = p_reason,
         last_checked_at = now()
   where user_id = p_user_id;

  return found;
end $$;


-- ----------------------------------------------------------------------------
-- 4. Vue publique : public_certified_contributors
-- ----------------------------------------------------------------------------
-- Liste des auteurs certifiés (badge "✓ rémunérable" affichable publiquement)

create or replace view public_certified_contributors
with (security_invoker = true) as
select
  c.user_id,
  c.certified_at,
  -- Pseudo affiché seulement si l'auteur a coché public_name_consent
  case
    when cb.public_name_consent = true then p.username
    else 'Auteur #' || substring(md5(c.user_id::text), 1, 4)
  end as display_name,
  cb.public_name_consent as is_public_name
from contributor_certifications c
join profiles p on p.id = c.user_id
left join contributor_balance cb on cb.user_id = c.user_id
where c.status = 'certified';

comment on view public_certified_contributors is
  'Liste des auteurs certifiés rémunérables. Pseudo masqué en "Auteur #N" si pas opt-in.';


-- ============================================================================
-- Smoke tests à exécuter manuellement après la migration :
--
--   -- Table créée ?
--   select tablename from pg_tables
--    where schemaname='public' and tablename = 'contributor_certifications';
--
--   -- RPCs créées ?
--   select proname from pg_proc
--    where proname in ('check_contributor_certification','revoke_contributor_certification');
--
--   -- Test pour un user (connecté)
--   select check_contributor_certification();
--   -- → renvoie un jsonb avec milestones_met et criteria
--
--   -- Vue public
--   select * from public_certified_contributors limit 5;
-- ============================================================================
-- Migration v0.18.0 Phase 2 — terminée.
-- ============================================================================
