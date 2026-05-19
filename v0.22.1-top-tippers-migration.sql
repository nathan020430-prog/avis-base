-- ============================================================================
-- Avis Base -- v0.22.1 -- Top tippers publics (transparence)
-- ============================================================================
--
-- Ajoute :
--   * RPC get_public_top_tippers(p_limit, p_days) qui retourne le top des
--     donateurs sur les N derniers jours, filtres sur display_consent=true.
--     Aggregation par username + somme des dons + nombre + dernier tip.
--
-- Pas de nouvelle table. Lecture uniquement, ouverte a anon + authenticated.
--
-- Idempotent. ASCII pur. A appliquer apres v0.20.0-stats-migration.sql.
-- ============================================================================

set search_path = public;


-- ----------------------------------------------------------------------------
-- RPC : get_public_top_tippers
-- ----------------------------------------------------------------------------
-- Top donateurs visibles publiquement sur les N derniers jours (defaut 30).
-- Filtres : tip.status = 'succeeded' ET tip.display_consent = true.
-- Aggregation par sender_user_id (donc par username).

create or replace function get_public_top_tippers(
  p_limit int default 10,
  p_days  int default 30
) returns table (
  username     text,
  total_cents  bigint,
  tip_count    bigint,
  last_tip_at  timestamptz
)
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  return query
  select
    p.username                  as username,
    sum(t.amount_cents)::bigint as total_cents,
    count(*)::bigint            as tip_count,
    max(t.created_at)           as last_tip_at
  from tips t
  join profiles p on p.id = t.sender_user_id
  where t.status = 'succeeded'
    and coalesce(t.display_consent, false) = true
    and t.sender_user_id is not null
    and t.created_at >= now() - (greatest(1, least(coalesce(p_days, 30), 365))::text || ' days')::interval
  group by p.username
  order by total_cents desc, last_tip_at desc
  limit greatest(1, least(coalesce(p_limit, 10), 50));
end $$;

grant execute on function get_public_top_tippers(int, int) to anon, authenticated;


-- ============================================================================
-- Smoke tests :
--   select * from get_public_top_tippers(10, 30);
--   select * from get_public_top_tippers(5, 365);  -- toute l'annee
-- ============================================================================
-- Fin v0.22.1
-- ============================================================================
