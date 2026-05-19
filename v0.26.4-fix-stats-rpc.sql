-- ============================================================================
-- Avis Base -- v0.26.4 -- Hotfix : RPC get_public_stats() resiliente
-- ============================================================================
--
-- Probleme detecte en prod (page /stats) :
--   ERROR: column "validated" does not exist
--
-- La RPC `get_public_stats()` (introduite en v0.20.0) lit la colonne
-- `reports.validated` qui n'est pas presente sur toutes les bases (selon
-- l'historique de creation du schema, elle peut manquer). Le bloc PL/pgSQL
-- gerait deja `undefined_table` mais pas `undefined_column` -> la RPC
-- entiere plantait et la page /stats affichait l'erreur SQL aux visiteurs.
--
-- Ce hotfix recree la RPC en :
--   1) wrappant la lecture de `validated` dans un bloc qui retombe
--      gracieusement sur "tous les resolved comptent" si la colonne manque
--   2) ajoutant le handler `undefined_column` au bloc moderation principal
--
-- Idempotent. ASCII pur. A appliquer apres v0.26.1.
-- ============================================================================

set search_path = public;

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
  v_has_validated_col         boolean := true;
begin
  -- Articles
  begin
    select count(*) into v_articles_published
      from articles where status = 'published';
  exception when undefined_column then
    v_articles_published := 0;
  end;

  begin
    select count(*) into v_articles_public_visible
      from articles
     where status = 'published'
       and coalesce(moderation_state, 'visible') = 'visible';
  exception when undefined_column then
    select count(*) into v_articles_public_visible
      from articles where status = 'published';
  end;

  begin
    select count(*) into v_articles_hidden_by_mod
      from articles
     where coalesce(moderation_state, 'visible') in ('hidden_auto','hidden_mod');
  exception when undefined_column then
    v_articles_hidden_by_mod := 0;
  end;

  -- Clips
  begin
    select count(*) into v_clips_published from clips where status = 'published';
  exception when undefined_table then
    v_clips_published := 0;
  end;

  -- Contributeurs
  select count(*) into v_contributors_total
    from profiles where coalesce(articles_published, 0) > 0;

  begin
    select count(*) into v_contributors_certified
      from contributor_certifications where status = 'approved';
  exception when undefined_table then
    v_contributors_certified := 0;
  end;

  begin
    select count(*) into v_contributors_members from members where status = 'active';
  exception when undefined_table then
    v_contributors_members := 0;
  end;

  -- Sources citees (best-effort)
  begin
    select coalesce(sum(coalesce(array_length(sources, 1), 0)), 0) into v_sources_total
      from articles where status = 'published';
  exception when undefined_column then
    v_sources_total := 0;
  end;

  -- Commentaires visibles
  begin
    select count(*) into v_comments_visible
      from comments where coalesce(hidden, false) = false;
  exception when undefined_column then
    select count(*) into v_comments_visible from comments;
  end;

  -- Credibilite
  select round(coalesce(avg(credibility_score), 0))::int,
         coalesce(max(credibility_score), 0)
    into v_avg_cred, v_max_cred
    from profiles
   where coalesce(articles_published, 0) > 0;

  -- Moderation : gere a la fois `undefined_table` et `undefined_column`
  -- (la colonne `reports.validated` n'existe pas sur toutes les bases).
  begin
    select count(*) filter (where status = 'pending'),
           count(*) filter (where status = 'resolved' and coalesce(validated, false) = true),
           count(*) filter (where status = 'dismissed')
      into v_reports_pending, v_reports_resolved, v_reports_dismissed
      from reports;
  exception
    when undefined_table then
      v_reports_pending := 0; v_reports_resolved := 0; v_reports_dismissed := 0;
    when undefined_column then
      -- Fallback : pas de colonne `validated` -> on compte tous les `resolved`
      v_has_validated_col := false;
      begin
        select count(*) filter (where status = 'pending'),
               count(*) filter (where status = 'resolved'),
               count(*) filter (where status = 'dismissed')
          into v_reports_pending, v_reports_resolved, v_reports_dismissed
          from reports;
      exception when others then
        v_reports_pending := 0; v_reports_resolved := 0; v_reports_dismissed := 0;
      end;
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

-- ============================================================================
-- Smoke test :
--   select get_public_stats();
-- ============================================================================
-- Fin v0.26.4
-- ============================================================================
