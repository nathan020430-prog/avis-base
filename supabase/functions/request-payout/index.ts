// ============================================================================
// request-payout
//
// Demande de virement d'un contributeur via Stripe Connect Transfer.
//
// Pré-conditions :
//   - User authentifié (JWT)
//   - contributor_balance.balance_cents >= 2000 (20€)
//   - contributor_balance.kyc_completed = true
//   - contributor_balance.stripe_connect_account_id != null
//
// Effet :
//   - Crée un Stripe Transfer du compte plateforme vers le compte Connect
//   - Crée une ligne contributor_payments (status='pending'/'completed')
//   - Décrémente contributor_balance.balance_cents
//
// ⚠️ Statut juridique : avant le 1er virement réel, valider auprès d'un
// avocat le statut d'intermédiaire de paiement (ACPR). Stripe Connect
// Express porte le KYC mais pas le conseil juridique.
//
// Variables d'env :
//   STRIPE_SECRET_KEY
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY
// ============================================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { handleCors, jsonResponse } from '../_shared/cors.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== 'POST') return jsonResponse({ error: 'Method not allowed' }, 405);

  const stripeKey  = Deno.env.get('STRIPE_SECRET_KEY');
  const supaUrl    = Deno.env.get('SUPABASE_URL');
  const anonKey    = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!stripeKey || !supaUrl || !anonKey || !serviceKey) {
    return jsonResponse({ error: 'env missing' }, 500);
  }

  // ---- auth (anon client pour lire l'identité) ----
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return jsonResponse({ error: 'Auth required' }, 401);
  const supaAuth = createClient(supaUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: userData, error: userErr } = await supaAuth.auth.getUser();
  if (userErr || !userData?.user) return jsonResponse({ error: 'Invalid token' }, 401);
  const userId = userData.user.id;

  // ---- service client pour écriture protégée ----
  const supa = createClient(supaUrl, serviceKey);

  // v0.18.0 Phase 2 — Certification "Auteur rémunérable"
  // (4 critères : KYC + ≥3 articles + ≥30j + score ≥50)
  // Vérifié AVANT reserve_payout pour donner une erreur claire au front
  // sans gaspiller un verrou Postgres.
  const { data: certData, error: certErr } = await supa.rpc('check_contributor_certification', { p_user_id: userId });
  if (certErr) {
    console.warn('[request-payout] cert RPC unavailable, allowing payout (migration not applied?)', certErr.message);
  } else if (certData && certData.certified !== true) {
    const missing: string[] = [];
    const m = certData.milestones_met || {};
    if (!m.articles_published_3) missing.push('articles_published_3');
    if (!m.account_age_30d)      missing.push('account_age_30d');
    if (!m.credibility_50)       missing.push('credibility_50');
    if (!m.kyc_completed)        missing.push('kyc_completed');
    return jsonResponse({
      error: 'not_certified',
      missing_criteria: missing,
      criteria: certData.criteria || {},
    }, 403);
  }

  // v0.18.1 — Réservation atomique via RPC SECURITY DEFINER.
  // Verrouille contributor_balance + contributor_payments (FOR UPDATE),
  // débite la balance, crée le payment 'pending' en une seule tx.
  // → Impossible que deux requêtes concurrentes passent.
  const { data: reserveData, error: reserveErr } = await supa.rpc('reserve_payout', {
    p_user_id:             userId,
    p_min_threshold_cents: 2000,
  });

  if (reserveErr) {
    // Les erreurs métier sont remontées via raise exception → message Postgres
    const msg = String(reserveErr.message || '');
    if (msg.includes('no_balance'))                return jsonResponse({ error: 'no_balance' }, 400);
    if (msg.includes('kyc_not_completed'))         return jsonResponse({ error: 'kyc_not_completed' }, 400);
    if (msg.includes('below_threshold'))           {
      const match = msg.match(/below_threshold:(\d+)/);
      return jsonResponse({ error: 'below_threshold', balance_cents: match ? parseInt(match[1]) : null }, 400);
    }
    if (msg.includes('payment_already_pending'))   {
      const match = msg.match(/payment_already_pending:([0-9a-f-]+)/);
      return jsonResponse({ error: 'payment_already_pending', payment_id: match ? match[1] : null }, 409);
    }
    console.error('[request-payout] reserve_payout failed', reserveErr);
    return jsonResponse({ error: 'reserve_failed' }, 500);
  }

  // reserve_payout returns table — supabase-js renvoie un tableau
  const reserve = Array.isArray(reserveData) ? reserveData[0] : reserveData;
  if (!reserve?.payout_id) {
    console.error('[request-payout] reserve_payout returned no payout_id', reserveData);
    return jsonResponse({ error: 'reserve_failed' }, 500);
  }
  const paymentId   = reserve.payout_id as string;
  const amountCents = reserve.amount_cents as number;
  const destAccount = reserve.stripe_connect_account_id as string;

  // À partir d'ici, la balance est DÉJÀ débitée et un payment 'pending'
  // existe. Toute sortie sans finalize_payout() doit appeler rollback_payout().
  const stripe = new Stripe(stripeKey, { apiVersion: '2024-06-20' });

  try {
    const transfer = await stripe.transfers.create({
      amount:         amountCents,
      currency:       'eur',
      destination:    destAccount,
      transfer_group: `payout_${paymentId}`,
      metadata: {
        user_id:    userId,
        payment_id: paymentId,
      },
    });

    const { error: finErr } = await supa.rpc('finalize_payout', {
      p_payment_id:         paymentId,
      p_stripe_transfer_id: transfer.id,
    });
    if (finErr) {
      // Cas anormal : Stripe a transféré mais on n'a pas pu marquer 'completed'.
      // On NE rollback PAS la balance (l'argent est parti). On log fort.
      console.error('[request-payout] STRIPE OK BUT finalize_payout FAILED — manual review', {
        paymentId, transferId: transfer.id, err: finErr,
      });
    }

    return jsonResponse({
      payment_id:         paymentId,
      stripe_transfer_id: transfer.id,
      amount_cents:       amountCents,
      status:             'completed',
    });
  } catch (e: any) {
    // Stripe a refusé → restaure la balance
    const { error: rbErr } = await supa.rpc('rollback_payout', {
      p_payment_id:     paymentId,
      p_failure_reason: String(e?.message || e),
    });
    if (rbErr) {
      console.error('[request-payout] rollback_payout failed — balance NOT restored', {
        paymentId, originalErr: e?.message, rbErr,
      });
    }
    console.error('[request-payout] transfer failed', e);
    return jsonResponse({ error: String(e?.message || e), payment_id: paymentId }, 500);
  }
});
