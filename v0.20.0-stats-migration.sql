-- ============================================================================
-- Avis Base -- v0.20.0 -- Stats publiques (transparence)
-- ============================================================================
--
-- Expose deux RPCs publiques (anon + authenticated) qui retournent des
-- compteurs agreges pour la page /stats :
--
--   * get_public_stats()              -> jsonb avec tous les compteurs
--   * get_public_top_contributors(n)  -> table des N premiers contributeurs
--                                        (filtres : articles_published > 0)
--
-- Pas de nouvelles tables. Pas de PII. Tous les chiffres sont calculables
-- depuis ce que le public peut deja voir page apres page.
--
-- Idempotent. ASCII pur. A appliquer apres v0.19.1.
-- ============================================================================

set search_path = public;


-- ----------------------------------------------------------------------------
-- 1. RPC : get_public_stats
-- ----------------------------------------------------------------------------
-- Retourne un JSON avec :
--   articles : { published, public_visible, hidden_by_mod }
--   clips    : { published_total }
--   contributors : { total_authors, certified, members }
--   sources  : { total_cited }
--   comments : { visible_total }
--   credibility : { avg_score, max_score }
--   moderation : { reports_pending, reports_resolved, reports_dismissed,
--                  auto_hidden_active, mod_actions_total }
--   generated_at : timestamptz

create or replace function get_public_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_articles_published        int;
  v_articles_public_visible   int;
  v_articles_hidden_by_mod    int;
  v_clips_published           int;
  v_contributors_total        int;
  v_contributors_certified    int;
  v_contributors_members      int;
  v_sources_total             bigint;
  v_comments_visible          int;
  v_avg_cred                  int;
  v_max_cred                  int;
  v_reports_pending           int;
  v_reports_resolved          int;
  v_reports_dismissed         int;
  v_auto_hidden_active        int;
  v_mod_actions_total         int;
begin
  -- Articles
  select count(*) into v_articles_published
    from articles where status = 'published';

  select count(*) into v_articles_public_visible
    from articles
   where status = 'published'
     and coalesce(moderation_state, 'visible') not in ('hidden_auto','hidden_mod');

  select count(*) into v_articles_hidden_by_mod
    from articles where coalesce(moderation_state, 'visible') in ('hidden_auto','hidden_mod');

  -- Clips
  select count(*) into v_clips_published
    from clips where status = 'published';

  -- Contributeurs
  select count(distinct author_id) into v_contributors_total
    from articles where status = 'published';

  -- Certifies (table optionnelle : tolerance si la migration v0.18.0 pas appliquee)
  begin
    select count(*) into v_contributors_certified
      from contributor_certifications where status = 'certified';
  exception when undefined_table then
    v_contributors_certified := 0;
  end;

  -- Membres Avis Base+ (table optionnelle, idem)
  begin
    select count(*) into v_contributors_members
      from members where status in ('active','grace_period');
  exception when undefined_table then
    v_contributors_members := 0;
  end;

  -- Sources : somme des longueurs de cited_sources sur les articles publies
  select coalesce(sum(jsonb_array_length(coalesce(cited_sources, '[]'::jsonb))), 0)
    into v_sources_total
    from articles where status = 'published';

  -- Commentaires visibles (hidden=false)
  begin
    select count(*) into v_comments_visible
      from comments where coalesce(hidden, false) = false;
  exception when undefined_column then
    -- vieux schema sans la colonne hidden
    select count(*) into v_comments_visible from comments;
  end;

  -- Credibilite : moyenne et max sur les profils contributeurs
  select round(coalesce(avg(credibility_score), 0))::int,
         coalesce(max(credibility_score), 0)
    into v_avg_cred, v_max_cred
    from profiles
   where coalesce(articles_published, 0) > 0;

  -- Moderation (table reports / moderation_actions optionnelles)
  begin
    select count(*) filter (where status = 'pending'),
           count(*) filter (where status = 'resolved' and coalesce(validated, false) = true),
           count(*) filter (where status = 'dismissed')
      into v_reports_pending, v_reports_resolved, v_reports_dismissed
      from reports;
  exception when undefined_table then
    v_reports_pending := 0; v_reports_resolved := 0; v_reports_dismissed := 0;
  end;

  begin
    select count(*) into v_auto_hidden_active
      from articles where coalesce(moderation_state, 'visible') = 'hidden_auto';
  exception when undefined_column then
    v_auto_hidden_active := 0;
  end;

  begin
    select count(*) into v_mod_actions_total from moderation_actions;
  exception when undefined_table then
    v_mod_actions_total := 0;
  end;

  return jsonb_build_object(
    'articles', jsonb_build_object(
      'published',      v_articles_published,
      'public_visible', v_articles_public_visible,
      'hidden_by_mod',  v_articles_hidden_by_mod
    ),
    'clips', jsonb_build_object(
      'published_total', v_clips_published
    ),
    'contributors', jsonb_build_object(
      'total_authors', v_contributors_total,
      'certified',     v_contributors_certified,
      'members',       v_contributors_members
    ),
    'sources', jsonb_build_object(
      'total_cited', v_sources_total
    ),
    'comments', jsonb_build_object(
      'visible_total', v_comments_visible
    ),
    'credibility', jsonb_build_object(
      'avg_score', v_avg_cred,
      'max_score', v_max_cred
    ),
    'moderation', jsonb_build_object(
      'reports_pending',    v_reports_pending,
      'reports_resolved',   v_reports_resolved,
      'reports_dismissed',  v_reports_dismissed,
      'auto_hidden_active', v_auto_hidden_active,
      'mod_actions_total',  v_mod_actions_total
    ),
    'generated_at', now()
  );
end $$;

grant execute on function get_public_stats() to anon, authenticated;


-- ----------------------------------------------------------------------------
-- 2. RPC : get_public_top_contributors
-- ----------------------------------------------------------------------------
-- Retourne les N premiers contributeurs (par credibilite, puis articles).
-- Pas d'opt-in necessaire : ces donnees (username, articles, score) sont
-- deja visibles sur chaque profil public. C'est juste un classement.

create or replace function get_public_top_contributors(p_limit int default 10)
returns table (
  username             text,
  articles_published   int,
  credibility_score    int,
  credibility_level    text,
  is_certified         boolean,
  is_member            boolean
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_has_cert  boolean := true;
  v_has_memb  boolean := true;
begin
  -- Detect optional tables
  begin
    perform 1 from contributor_certifications limit 1;
  exception when undefined_table then v_has_cert := false;
  end;
  begin
    perform 1 from members limit 1;
  exception when undefined_table then v_has_memb := false;
  end;

  return query
  select
    p.username,
    coalesce(p.articles_published, 0)             as articles_published,
    coalesce(p.credibility_score, 0)              as credibility_score,
    coalesce(p.credibility_level, 'nouveau')      as credibility_level,
    case when v_has_cert then exists (
      select 1 from contributor_certifications c
       where c.user_id = p.id and c.status = 'certified'
    ) else false end                              as is_certified,
    case when v_has_memb then exists (
      select 1 from members m
       where m.user_id = p.id and m.status in ('active','grace_period')
    ) else false end                              as is_member
  from profiles p
  where coalesce(p.articles_published, 0) > 0
  order by p.credibility_score desc nulls last,
           p.articles_published desc nulls last,
           p.username asc
  limit greatest(1, least(coalesce(p_limit, 10), 50));
end $$;

grant execute on function get_public_top_contributors(int) to anon, authenticated;


-- ============================================================================
-- Smoke tests :
--
--   select get_public_stats();
--   select * from get_public_top_contributors(10);
-- ============================================================================
-- Fin v0.20.0
-- ============================================================================
