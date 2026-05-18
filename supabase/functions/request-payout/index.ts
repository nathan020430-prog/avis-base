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

  // ---- check balance + KYC ----
  const { data: bal } = await supa
    .from('contributor_balance')
    .select('balance_cents, kyc_completed, stripe_connect_account_id')
    .eq('user_id', userId)
    .maybeSingle();

  if (!bal) return jsonResponse({ error: 'no_balance' }, 400);
  if (!bal.kyc_completed || !bal.stripe_connect_account_id) {
    return jsonResponse({ error: 'kyc_not_completed' }, 400);
  }
  if ((bal.balance_cents || 0) < 2000) {
    return jsonResponse({ error: 'below_threshold', balance_cents: bal.balance_cents }, 400);
  }

  // ---- vérifier qu'il n'y a pas de virement en attente ----
  const { data: pendingPay } = await supa
    .from('contributor_payments')
    .select('id')
    .eq('user_id', userId)
    .eq('status', 'pending')
    .limit(1);
  if (pendingPay && pendingPay.length > 0) {
    return jsonResponse({ error: 'payment_already_pending', payment_id: pendingPay[0].id }, 409);
  }

  const amountCents = bal.balance_cents;
  const stripe = new Stripe(stripeKey, { apiVersion: '2024-06-20' });

  // ---- insert pending payment ----
  const { data: payment, error: payErr } = await supa
    .from('contributor_payments')
    .insert({
      user_id: userId,
      amount_cents: amountCents,
      status: 'pending',
    })
    .select('id')
    .single();
  if (payErr || !payment) return jsonResponse({ error: 'insert_failed' }, 500);

  try {
    // ---- Stripe Transfer ----
    const transfer = await stripe.transfers.create({
      amount: amountCents,
      currency: 'eur',
      destination: bal.stripe_connect_account_id,
      transfer_group: `payout_${payment.id}`,
      metadata: {
        user_id: userId,
        payment_id: payment.id,
      },
    });

    // ---- update payment + decrement balance ----
    await supa.from('contributor_payments').update({
      stripe_transfer_id: transfer.id,
      status: 'completed',
      completed_at: new Date().toISOString(),
    }).eq('id', payment.id);

    await supa.from('contributor_balance').update({
      balance_cents: 0,
      updated_at: new Date().toISOString(),
    }).eq('user_id', userId);

    return jsonResponse({
      payment_id: payment.id,
      stripe_transfer_id: transfer.id,
      amount_cents: amountCents,
      status: 'completed',
    });
  } catch (e: any) {
    // Mark payment as failed, preserve balance
    await supa.from('contributor_payments').update({
      status: 'failed',
      failed_at: new Date().toISOString(),
      failure_reason: String(e?.message || e).slice(0, 500),
    }).eq('id', payment.id);
    console.error('[request-payout] transfer failed', e);
    return jsonResponse({ error: String(e?.message || e), payment_id: payment.id }, 500);
  }
});
