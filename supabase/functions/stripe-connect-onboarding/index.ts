// ============================================================================
// stripe-connect-onboarding
//
// Crée (ou récupère) un compte Stripe Connect Express pour le contributeur
// et retourne un account_link (URL de KYC à laquelle on redirige le user).
//
// Stripe Connect Express :
// - Le user remplit nom / date de naissance / IBAN sur la page Stripe
// - Stripe gère le KYC/AML/PSD2 (5 min env.)
// - Une fois complété, Stripe webhook account.updated → on set kyc_completed
//
// Pour la mise en prod : valider statut juridique d'intermédiaire de paiement
// (ACPR si applicable).
//
// Variables d'env :
//   STRIPE_SECRET_KEY
//   SITE_URL
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
  const siteUrl    = Deno.env.get('SITE_URL') || 'https://avis-base.com';
  const supaUrl    = Deno.env.get('SUPABASE_URL');
  const anonKey    = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!stripeKey || !supaUrl || !anonKey || !serviceKey) {
    return jsonResponse({ error: 'env missing' }, 500);
  }

  // ---- auth ----
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return jsonResponse({ error: 'Auth required' }, 401);
  const supaAuth = createClient(supaUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: userData, error: userErr } = await supaAuth.auth.getUser();
  if (userErr || !userData?.user) return jsonResponse({ error: 'Invalid token' }, 401);
  const user = userData.user;

  const stripe = new Stripe(stripeKey, { apiVersion: '2024-06-20' });
  const supa = createClient(supaUrl, serviceKey);

  try {
    // ---- get or create Connect account ----
    const { data: bal } = await supa
      .from('contributor_balance')
      .select('stripe_connect_account_id')
      .eq('user_id', user.id)
      .maybeSingle();

    let accountId = bal?.stripe_connect_account_id;

    if (!accountId) {
      const account = await stripe.accounts.create({
        type: 'express',
        country: 'FR',
        email: user.email,
        capabilities: {
          transfers: { requested: true },
        },
        metadata: {
          user_id: user.id,
        },
      });
      accountId = account.id;

      // Upsert dans contributor_balance
      await supa.from('contributor_balance').upsert({
        user_id: user.id,
        stripe_connect_account_id: accountId,
        updated_at: new Date().toISOString(),
      }, { onConflict: 'user_id' });
    }

    // ---- create account link (URL KYC) ----
    const accountLink = await stripe.accountLinks.create({
      account: accountId,
      refresh_url: `${siteUrl}/#mon-financement?kyc=refresh`,
      return_url: `${siteUrl}/#mon-financement?kyc=done`,
      type: 'account_onboarding',
    });

    return jsonResponse({
      account_id: accountId,
      url: accountLink.url,
      expires_at: accountLink.expires_at,
    });
  } catch (e) {
    console.error('[stripe-connect-onboarding]', e);
    return jsonResponse({ error: String(e?.message || e) }, 500);
  }
});
