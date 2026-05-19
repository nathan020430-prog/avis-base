-- ============================================================================
-- Avis Base -- v0.26.1 -- Stats financieres publiques pour /stats
-- ============================================================================
--
-- Ajoute 2 RPCs publiques qui exposent l'historique financier sous forme
-- agregee, lisible par anon + authenticated. Donnees deja transparentes
-- via les vues `public_economy_current` et `public_monthly_archive` —
-- les RPCs simplifient juste l'appel cote frontend (et permettent de
-- retourner des chiffres "morts" pour les mois sans donnees).
--
--   * get_public_finance_summary()      -> jsonb cumule depuis le debut
--   * get_public_finance_history(n)     -> n derniers mois (defaut 12)
--
-- Idempotent. ASCII pur. A appliquer apres v0.25.1.
-- ============================================================================

set search_path = public;


-- ----------------------------------------------------------------------------
-- 1. RPC : get_public_finance_summary
-- ----------------------------------------------------------------------------
-- Retourne un JSON avec :
--   * current_month       : {month, pool_cents, members_count, tips_total_cents_month}
--   * cumulative          : {revenue_cents, stripe_fees_cents, infra_cents,
--                             pool_cents, contributors_paid_cents}
--   * counts              : {months_archived, active_members,
--                             paying_contributors_total}

create or replace function get_public_finance_summary()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_current             jsonb;
  v_revenue             bigint := 0;
  v_stripe_fees         bigint := 0;
  v_infra               bigint := 0;
  v_pool                bigint := 0;
  v_paid                bigint := 0;
  v_archived_count      int    := 0;
  v_active_members      int    := 0;
  v_paying_contribs     int    := 0;
begin
  -- Mois en cours via la vue existante (v0.17.0)
  begin
    select to_jsonb(public_economy_current.*) into v_current
    from public_economy_current
    limit 1;
  exception when undefined_table then
    v_current := '{}'::jsonb;
  end;

  -- Cumul historique depuis monthly_payouts
  begin
    select
      coalesce(sum(revenue_cents),     0),
      coalesce(sum(stripe_fees_cents), 0),
      coalesce(sum(infra_cost_cents),  0),
      coalesce(sum(pool_cents),        0),
      count(*)
    into v_revenue, v_stripe_fees, v_infra, v_pool, v_archived_count
    from monthly_payouts
    where status in ('computed','distributed','archived');
  exception when undefined_table then
    v_revenue := 0; v_stripe_fees := 0; v_infra := 0; v_pool := 0; v_archived_count := 0;
  end;

  -- Total reverse aux contributeurs (payouts completed)
  begin
    select coalesce(sum(amount_cents), 0)
    into v_paid
    from contributor_payments
    where status = 'completed';
  exception when undefined_table then
    v_paid := 0;
  end;

  -- Membres actifs (snapshot now)
  begin
    select count(*) into v_active_members
    from members
    where status = 'active';
  exception when undefined_table then
    v_active_members := 0;
  end;

  -- Nombre de contributeurs ayant ete payes au moins 1 fois
  begin
    select count(distinct user_id) into v_paying_contribs
    from contributor_payments
    where status = 'completed';
  exception when undefined_table then
    v_paying_contribs := 0;
  end;

  return jsonb_build_object(
    'current_month', coalesce(v_current, '{}'::jsonb),
    'cumulative', jsonb_build_object(
      'revenue_cents',            v_revenue,
      'stripe_fees_cents',        v_stripe_fees,
      'infra_cents',              v_infra,
      'pool_cents',               v_pool,
      'contributors_paid_cents',  v_paid
    ),
    'counts', jsonb_build_object(
      'months_archived',         v_archived_count,
      'active_members',          v_active_members,
      'paying_contributors_total', v_paying_contribs
    ),
    'generated_at', now()
  );
end $$;

grant execute on function get_public_finance_summary() to anon, authenticated;


-- ----------------------------------------------------------------------------
-- 2. RPC : get_public_finance_history(p_months int)
-- ----------------------------------------------------------------------------
-- Retourne les `p_months` derniers mois cloturés (par defaut 12) sous forme
-- d'un tableau JSON, ordonnes du plus ancien au plus recent.

create or replace function get_public_finance_history(p_months int default 12)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_arr   jsonb;
  v_limit int := greatest(1, least(coalesce(p_months, 12), 60));
begin
  begin
    select coalesce(jsonb_agg(row_to_json(r)::jsonb order by r.payout_month asc), '[]'::jsonb)
    into v_arr
    from (
      select
        payout_month,
        revenue_cents,
        stripe_fees_cents,
        infra_cost_cents,
        pool_cents,
        members_count,
        tips_count,
        articles_count,
        status
      from monthly_payouts
      where status in ('computed','distributed','archived')
      order by payout_month desc
      limit v_limit
    ) r;
  exception when undefined_table then
    v_arr := '[]'::jsonb;
  end;

  return coalesce(v_arr, '[]'::jsonb);
end $$;

grant execute on function get_public_finance_history(int) to anon, authenticated;


-- ============================================================================
-- Smoke tests :
--   select get_public_finance_summary();
--   select get_public_finance_history(12);
-- ============================================================================
-- Fin v0.26.1
-- ============================================================================
