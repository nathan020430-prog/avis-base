// ============================================================================
// create-checkout-session
//
// Crée une session Stripe Checkout pour :
//  - mode='subscription' : adhésion mensuelle 5€ via Avis Basé+
//  - mode='tip'          : don ponctuel one-shot (1/3/5/10€ ou libre)
//
// Le user doit être authentifié (JWT bearer dans Authorization header).
// Retourne { url } à utiliser pour redirect côté client.
//
// Variables d'env requises (à set dans Supabase secrets) :
//   STRIPE_SECRET_KEY
//   PRICE_ID_MEMBERSHIP    -> ID du Price mensuel 5€ créé sur Stripe
//   SITE_URL               -> https://avis-base.com (pour success/cancel URLs)
//
// Déploiement : supabase functions deploy create-checkout-session
// ============================================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { handleCors, jsonResponse } from '../_shared/cors.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method !== 'POST') return jsonResponse({ error: 'Method not allowed' }, 405);

  // ---- env ----
  const stripeKey = Deno.env.get('STRIPE_SECRET_KEY');
  const priceId   = Deno.env.get('PRICE_ID_MEMBERSHIP');
  const siteUrl   = Deno.env.get('SITE_URL') || 'https://avis-base.com';
  const supaUrl   = Deno.env.get('SUPABASE_URL');
  const anonKey   = Deno.env.get('SUPABASE_ANON_KEY');

  if (!stripeKey) return jsonResponse({ error: 'STRIPE_SECRET_KEY missing' }, 500);
  if (!supaUrl || !anonKey) return jsonResponse({ error: 'Supabase env missing' }, 500);

  // ---- auth ----
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return jsonResponse({ error: 'Auth required' }, 401);

  const supa = createClient(supaUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await supa.auth.getUser();
  if (userErr || !userData?.user) return jsonResponse({ error: 'Invalid token' }, 401);
  const user = userData.user;

  // ---- body ----
  let body: any;
  try { body = await req.json(); }
  catch { return jsonResponse({ error: 'Invalid JSON' }, 400); }

  const mode = body.mode;
  if (mode !== 'subscription' && mode !== 'tip') {
    return jsonResponse({ error: 'mode must be "subscription" or "tip"' }, 400);
  }

  // ---- Stripe ----
  const stripe = new Stripe(stripeKey, { apiVersion: '2024-06-20' });

  try {
    if (mode === 'subscription') {
      if (!priceId) return jsonResponse({ error: 'PRICE_ID_MEMBERSHIP missing' }, 500);

      const displayConsent = !!body.display_consent;

      const session = await stripe.checkout.sessions.create({
        mode: 'subscription',
        line_items: [{ price: priceId, quantity: 1 }],
        success_url: `${siteUrl}/?member=success`,
        cancel_url:  `${siteUrl}/#devenir-membre`,
        customer_email: user.email,
        client_reference_id: user.id,
        metadata: {
          user_id: user.id,
          display_consent: displayConsent ? 'true' : 'false',
        },
        subscription_data: {
          metadata: {
            user_id: user.id,
            display_consent: displayConsent ? 'true' : 'false',
          },
        },
      });
      return jsonResponse({ url: session.url });
    }

    // mode === 'tip'
    const amountCents = parseInt(body.amount_cents, 10);
    if (!Number.isFinite(amountCents) || amountCents < 100 || amountCents > 100000) {
      return jsonResponse({ error: 'amount_cents must be in [100, 100000]' }, 400);
    }
    const targetType = body.target_type || 'pool';
    if (!['pool', 'article', 'contributor'].includes(targetType)) {
      return jsonResponse({ error: 'invalid target_type' }, 400);
    }
    const displayConsent = !!body.display_consent;

    const session = await stripe.checkout.sessions.create({
      mode: 'payment',
      line_items: [{
        price_data: {
          currency: 'eur',
          unit_amount: amountCents,
          product_data: {
            name: 'Don ponctuel à Avis Basé',
            description: targetType === 'pool'
              ? 'Don ajouté au pool général, partagé au prorata des scores.'
              : targetType === 'article'
                ? 'Don pour un article spécifique.'
                : 'Don pour un contributeur spécifique.',
          },
        },
        quantity: 1,
      }],
      success_url: `${siteUrl}/?tip=success`,
      cancel_url:  `${siteUrl}/#financement`,
      customer_email: user.email,
      client_reference_id: user.id,
      payment_intent_data: {
        metadata: {
          user_id: user.id,
          target_type: targetType,
          target_article_id: body.target_article_id || '',
          target_user_id: body.target_user_id || '',
          display_consent: displayConsent ? 'true' : 'false',
        },
      },
    });
    return jsonResponse({ url: session.url });
  } catch (e) {
    console.error('[create-checkout-session]', e);
    return jsonResponse({ error: String(e?.message || e) }, 500);
  }
});
