-- ============================================================================
-- v0.18.2 — Hotfix audit : RLS server-side + auto-révocation certif
-- ============================================================================
-- Ferme deux findings de l'audit du 2026-05-18 :
--
--   1. Restriction écriture 7 jours = client-only
--      `canWriteArticle()` (index.html) bloque l'éditeur, mais un attaquant
--      peut appeler `supabase.from('articles').insert(...)` directement avec
--      la clé anon. Aucune vérification côté serveur.
--      → Helper `account_can_publish()` SECURITY DEFINER + nouvelle policy
--      INSERT sur `articles` qui vérifie âge ≥ 7j ET email confirmé.
--
--   2. Pas de révocation auto de certification quand un article est dégradé
--      Si un admin archive/supprime un article et que l'auteur tombe sous
--      3 articles publiés (critère cumulatif certif "Auteur rémunérable"),
--      sa certif reste à 'certified'.
--      → Trigger AFTER UPDATE OR DELETE sur `articles` qui révoque auto
--      si le compteur articles publiés < 3.
--
-- Politique de révocation conservatrice (volontaire) :
--   - Articles < 3 → revoke auto (admin action visible / contestable)
--   - Score < 50 → PAS de revoke (fluctuation naturelle, peut remonter)
--   - KYC perdu → impossible (ne peut que rester true)
--   - Age < 30j → impossible (ne peut que rester true)
--
-- Idempotent. Appliquer après v0.18.1-hotfix-money-races.sql.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Helper account_can_publish(uuid)
-- ----------------------------------------------------------------------------
-- Retourne true si le compte (auth.uid() par défaut) peut publier un article :
--   - Compte admin/superadmin → bypass
--   - Email confirmé (email_confirmed_at OU confirmed_at non null)
--   - Compte créé depuis >= 7 jours
--
-- SECURITY DEFINER nécessaire pour lire auth.users depuis une policy.
-- ----------------------------------------------------------------------------

create or replace function account_can_publish(p_user_id uuid default null)
returns boolean
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := coalesce(p_user_id, auth.uid());
  v_role text;
  v_created timestamptz;
  v_confirmed timestamptz;
begin
  if v_uid is null then return false; end if;

  -- Admin/superadmin bypass
  select role
    into v_role
    from public.profiles
    where id = v_uid;
  if v_role in ('admin', 'superadmin') then
    return true;
  end if;

  -- Lecture auth.users (nécessite SECURITY DEFINER)
  select created_at, coalesce(email_confirmed_at, confirmed_at)
    into v_created, v_confirmed
    from auth.users
    where id = v_uid;

  if v_created is null then return false; end if;
  if v_confirmed is null then return false; end if;
  if v_created + interval '7 days' > now() then return false; end if;

  return true;
end $$;

revoke execute on function account_can_publish(uuid) from public;
grant  execute on function account_can_publish(uuid) to authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 2. Policy INSERT articles avec vérification côté serveur
-- ----------------------------------------------------------------------------

drop policy if exists "articles_insert_auth"          on articles;
drop policy if exists "articles_insert_auth_and_aged" on articles;

create policy "articles_insert_auth_and_aged" on articles
  for insert
  with check (
    auth.uid() = author_id
    and account_can_publish(auth.uid())
  );


-- ----------------------------------------------------------------------------
-- 3. Trigger auto-révocation certif sur articles
-- ----------------------------------------------------------------------------
-- Re-vérifie le compteur d'articles publiés de l'auteur quand un article
-- change de statut ou est supprimé. Révoque la certif si le compteur tombe
-- sous 3 articles publiés ET que l'auteur était certifié.
--
-- Ne se déclenche que sur UPDATE OF status ou DELETE, donc négligeable côté
-- perfs (les status changes sont rares). On filtre OLD.status = published
-- ou NEW.status changed pour éviter les recompts inutiles.
-- ----------------------------------------------------------------------------

create or replace function _trg_articles_recheck_certification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_author uuid;
  v_was_published boolean;
  v_is_published  boolean;
  v_published_count int;
  v_is_certified boolean;
begin
  -- Pour AFTER triggers row-level, la valeur de retour est ignorée :
  -- on choisit OLD si DELETE, NEW sinon, par convention.
  v_author := OLD.author_id;
  v_was_published := (OLD.status = 'published');
  if TG_OP = 'DELETE' then
    v_is_published := false;
  else
    v_is_published := (NEW.status = 'published');
    if v_author is null then v_author := NEW.author_id; end if;
  end if;

  if v_author is null then
    if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
  end if;

  -- Pas de transition pertinente (published → published, ou non-published → non-published)
  if v_was_published = v_is_published then
    if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
  end if;

  -- L'auteur est-il actuellement certifié ?
  select (status = 'certified')
    into v_is_certified
    from contributor_certifications
    where user_id = v_author;
  if v_is_certified is null or v_is_certified = false then
    if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
  end if;

  -- Recompte articles publiés (la modif AFTER est déjà appliquée)
  select count(*)
    into v_published_count
    from articles
    where author_id = v_author and status = 'published';

  if v_published_count < 3 then
    update contributor_certifications
      set status          = 'revoked',
          revoked_at      = now(),
          revoked_reason  = 'auto: articles publiés < 3 après changement de statut/suppression',
          last_checked_at = now()
      where user_id = v_author
        and status = 'certified';
  end if;

  if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
end $$;

drop trigger if exists trg_articles_recheck_certification on articles;
create trigger trg_articles_recheck_certification
  after update or delete
  on articles
  for each row
  execute function _trg_articles_recheck_certification();


-- ----------------------------------------------------------------------------
-- 4. Sanity check (à exécuter manuellement après migration)
-- ----------------------------------------------------------------------------
-- Tester que la policy bloque bien un user récent :
--   set role authenticated;
--   set request.jwt.claim.sub = '<uuid d''un user créé il y a 1h, non confirmé>';
--   insert into articles (title, author_id, ...) values (..., auth.uid(), ...);
--   -- => devrait échouer avec "new row violates row-level security policy"
--
-- Tester que la policy laisse passer un user éligible :
--   -- même chose avec un user > 7j et email confirmé → doit passer.
--
-- Tester la révocation auto :
--   -- Prendre un user certifié, archiver un de ses articles publiés tel qu'il
--   -- en reste 2 → vérifier contributor_certifications.status = 'revoked'.
-- ----------------------------------------------------------------------------
