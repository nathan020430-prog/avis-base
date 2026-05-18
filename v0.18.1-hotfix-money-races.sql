-- ============================================================================
-- v0.18.1 — Hotfix : race conditions sur les flux d'argent
-- ============================================================================
-- Corrige 3 bugs identifiés à l'audit du 2026-05-18 :
--
--   1. Crédit de tip non atomique dans le webhook Stripe
--      (read balance → ajouter en JS → upsert : perte de tips concurrents)
--
--   2. Crédit de tip non idempotent
--      (un re-delivery webhook par Stripe créditait deux fois le contributeur)
--
--   3. request-payout sans verrou
--      (deux requêtes concurrentes pouvaient toutes deux passer la vérif
--       de balance et déclencher deux Stripe Transfers)
--
-- Bonus :
--   4. Verrouillage de la colonne `balance_cents` (et autres champs sensibles)
--      côté RLS : on supprime l'UPDATE policy générique qui laissait l'user
--      modifier sa propre ligne `contributor_balance` directement via PostgREST.
--      Le seul usage légitime (toggle du consentement public) passe déjà par
--      la RPC `update_contributor_public_consent` (SECURITY DEFINER).
--
-- Appliquer après `v0.17.0-financement-migration.sql`.
-- Idempotent : peut être ré-exécuté sans dommage.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. tips.credited_at : sentinelle d'idempotence pour le crédit de balance
-- ----------------------------------------------------------------------------
-- Posée par credit_tip_to_contributor() après l'increment.
-- NULL = tip pas encore crédité, timestamptz = déjà crédité.

alter table tips
  add column if not exists credited_at timestamptz;

create index if not exists tips_uncredited_idx
  on tips(stripe_payment_intent_id)
  where credited_at is null;


-- ----------------------------------------------------------------------------
-- 2. Supprime la policy UPDATE trop large sur contributor_balance
-- ----------------------------------------------------------------------------
-- Cette policy permettait à un user de patcher SA ligne, y compris
-- `balance_cents`, `total_earned_cents`, `stripe_connect_account_id`,
-- `kyc_completed`. Postgres ne supporte pas le RLS au niveau colonne.
-- Le seul usage côté user (toggle public_name_consent) passe par la
-- RPC SECURITY DEFINER `update_contributor_public_consent`.

drop policy if exists "balance_update_consent_own" on contributor_balance;


-- ----------------------------------------------------------------------------
-- 3. RPC credit_tip_to_contributor : crédit atomique + idempotent
-- ----------------------------------------------------------------------------
-- Appelée par l'Edge Function stripe-webhook après le upsert de `tips`.
-- Garanties :
--   * SELECT FOR UPDATE sur la ligne `tips` → sérialise les retries concurrents
--   * Marquage `credited_at` → idempotent face aux retries de Stripe
--   * INSERT…ON CONFLICT DO UPDATE avec increment SQL → pas de read-modify-write
-- Retourne :
--   true  → crédit effectué (1re fois)
--   false → tip déjà crédité, no-op
-- Lève une exception si le tip n'existe pas (cas anormal).

create or replace function credit_tip_to_contributor(
  p_payment_intent_id text,
  p_target_user_id    uuid,
  p_amount_cents      int
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tip_id           uuid;
  v_already_credited boolean;
begin
  if p_payment_intent_id is null then
    raise exception 'payment_intent_id required';
  end if;
  if p_target_user_id is null then
    raise exception 'target_user_id required';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'amount_cents must be > 0';
  end if;

  -- Verrouille la ligne tip → sérialise les retries simultanés
  select id, credited_at is not null
    into v_tip_id, v_already_credited
  from tips
  where stripe_payment_intent_id = p_payment_intent_id
  for update;

  if v_tip_id is null then
    raise exception 'tip_not_found:%', p_payment_intent_id;
  end if;

  if v_already_credited then
    return false;  -- déjà crédité, no-op idempotent
  end if;

  -- Increment atomique en une seule instruction SQL
  insert into contributor_balance (
    user_id, balance_cents, total_earned_cents, updated_at
  )
  values (
    p_target_user_id, p_amount_cents, p_amount_cents, now()
  )
  on conflict (user_id) do update set
    balance_cents      = contributor_balance.balance_cents      + excluded.balance_cents,
    total_earned_cents = contributor_balance.total_earned_cents + excluded.total_earned_cents,
    updated_at         = now();

  -- Marque le tip comme crédité (sentinelle d'idempotence)
  update tips
    set credited_at = now()
    where id = v_tip_id;

  return true;
end $$;


-- ----------------------------------------------------------------------------
-- 4. RPC reserve_payout : vérif + débit atomique + création paiement pending
-- ----------------------------------------------------------------------------
-- Appelée par l'Edge Function request-payout AVANT l'appel Stripe Transfer.
-- Garanties :
--   * SELECT FOR UPDATE sur contributor_balance ET contributor_payments
--     → impossible que deux requêtes concurrentes passent toutes deux
--   * Débit de la balance + insertion du payment 'pending' dans la même tx
--   * Si Stripe échoue ensuite, l'Edge Function appelle rollback_payout()
--     pour restaurer la balance
-- Erreurs (via RAISE EXCEPTION) :
--   no_balance, kyc_not_completed, below_threshold:<bal>,
--   payment_already_pending:<uuid>
-- Retourne (en cas de succès) : payout_id, amount_cents, stripe_connect_account_id

create or replace function reserve_payout(
  p_user_id            uuid,
  p_min_threshold_cents int default 2000
) returns table (
  payout_id                   uuid,
  amount_cents                int,
  stripe_connect_account_id   text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bal      int;
  v_kyc      boolean;
  v_acct     text;
  v_pending  uuid;
  v_new_id   uuid;
begin
  if p_user_id is null then
    raise exception 'user_id required';
  end if;

  -- Verrouille la balance du contributeur
  select balance_cents, kyc_completed, stripe_connect_account_id
    into v_bal, v_kyc, v_acct
  from contributor_balance
  where user_id = p_user_id
  for update;

  if v_bal is null then
    raise exception 'no_balance';
  end if;
  if not v_kyc or v_acct is null then
    raise exception 'kyc_not_completed';
  end if;
  if v_bal < p_min_threshold_cents then
    raise exception 'below_threshold:%', v_bal;
  end if;

  -- Verrouille aussi un éventuel payment en attente
  -- (sinon deux reserve_payout concurrents pourraient passer ici)
  select id into v_pending
  from contributor_payments
  where user_id = p_user_id
    and status  = 'pending'
  for update
  limit 1;

  if v_pending is not null then
    raise exception 'payment_already_pending:%', v_pending;
  end if;

  -- Débit atomique de la balance
  update contributor_balance
    set balance_cents = 0,
        updated_at    = now()
    where user_id = p_user_id;

  -- Crée le paiement pending
  insert into contributor_payments (user_id, amount_cents, status)
  values (p_user_id, v_bal, 'pending')
  returning id into v_new_id;

  return query select v_new_id, v_bal, v_acct;
end $$;


-- ----------------------------------------------------------------------------
-- 5. RPC finalize_payout : valide un payment 'pending' après Stripe Transfer OK
-- ----------------------------------------------------------------------------
-- Idempotente : si le payment n'est plus 'pending', no-op.

create or replace function finalize_payout(
  p_payment_id          uuid,
  p_stripe_transfer_id  text
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated int;
begin
  if p_payment_id is null or p_stripe_transfer_id is null then
    raise exception 'payment_id and stripe_transfer_id required';
  end if;

  update contributor_payments
    set status              = 'completed',
        stripe_transfer_id  = p_stripe_transfer_id,
        completed_at        = now()
    where id     = p_payment_id
      and status = 'pending';

  get diagnostics v_updated = row_count;
  return v_updated > 0;
end $$;


-- ----------------------------------------------------------------------------
-- 6. RPC rollback_payout : restaure la balance après échec Stripe Transfer
-- ----------------------------------------------------------------------------
-- Idempotente : si le payment n'est plus 'pending', no-op (pas de double
-- restauration).

create or replace function rollback_payout(
  p_payment_id     uuid,
  p_failure_reason text default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid;
  v_amount int;
begin
  if p_payment_id is null then
    raise exception 'payment_id required';
  end if;

  -- Mark failed + récupère user_id/amount, seulement si encore pending
  update contributor_payments
    set status         = 'failed',
        failed_at      = now(),
        failure_reason = left(coalesce(p_failure_reason, 'unknown'), 500)
    where id     = p_payment_id
      and status = 'pending'
    returning user_id, amount_cents into v_user, v_amount;

  if v_user is null then
    return false;  -- déjà finalisé ou rollback, no-op
  end if;

  -- Restaure la balance
  update contributor_balance
    set balance_cents = balance_cents + v_amount,
        updated_at    = now()
    where user_id = v_user;

  return true;
end $$;


-- ----------------------------------------------------------------------------
-- 7. Permissions
-- ----------------------------------------------------------------------------
-- Ces RPCs ne doivent être appelables que par le service_role (Edge Functions).
-- On révoque tout pour authenticated/anon par sécurité, même si la fonction
-- est SECURITY DEFINER (ça empêche l'invocation accidentelle).

revoke all on function credit_tip_to_contributor(text, uuid, int) from public, authenticated, anon;
revoke all on function reserve_payout(uuid, int)                  from public, authenticated, anon;
revoke all on function finalize_payout(uuid, text)                from public, authenticated, anon;
revoke all on function rollback_payout(uuid, text)                from public, authenticated, anon;

grant execute on function credit_tip_to_contributor(text, uuid, int) to service_role;
grant execute on function reserve_payout(uuid, int)                  to service_role;
grant execute on function finalize_payout(uuid, text)                to service_role;
grant execute on function rollback_payout(uuid, text)                to service_role;


-- ============================================================================
-- Fin v0.18.1
-- ============================================================================
