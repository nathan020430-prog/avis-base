// ============================================================================
// create-portal-session
//
// Cree une session Stripe Billing Portal pour le user connecte.
// Le portail Stripe permet a l'user de :
//   - annuler son abonnement (immediat ou en fin de periode selon config Stripe)
//   - mettre a jour sa methode de paiement
//   - consulter et telecharger ses factures
//   - mettre a jour son email de facturation
//
// On utilise ici un return_url qui pointe vers /mon-financement pour
// que l'user revienne directement sur son dashboard apres modification.
//
// Pre-requis cote Stripe :
//   - Activer le Customer Portal :
//     Dashboard Stripe > Settings > Billing > Customer portal > Activate
//   - Configurer les fonctionnalites autorisees (cancel, update payment method,
//     invoice history). Par defaut Stripe les active toutes.
//
// Variables d'env requises :
//   STRIPE_SECRET_KEY
//   SITE_URL  (pour le return_url)
//
// Le user doit avoir un stripe_customer_id dans members (cree par
// stripe-webhook lors du checkout.session.completed initial).
//
// Deploiement : supabase functions deploy create-portal-session
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

  // ---- find stripe customer ----
  const { data: member, error: memErr } = await supa
    .from('members')
    .select('stripe_customer_id, status')
    .eq('user_id', user.id)
    .maybeSingle();

  if (memErr) {
    console.error('[create-portal-session] members lookup', memErr);
    return jsonResponse({ error: 'Database error' }, 500);
  }
  if (!member?.stripe_customer_id) {
    return jsonResponse({
      error: 'no_subscription',
      hint: "Pas d'abonnement Avis Base+ actif. Devenez membre d'abord via /devenir-membre."
    }, 404);
  }

  // ---- Stripe Billing Portal ----
  const stripe = new Stripe(stripeKey, { apiVersion: '2024-06-20' });

  try {
    const session = await stripe.billingPortal.sessions.create({
      customer: member.stripe_customer_id,
      return_url: `${siteUrl}/#mon-financement`,
    });
    return jsonResponse({ url: session.url });
  } catch (e: any) {
    console.error('[create-portal-session] stripe', e);
    // Cas typique : Customer Portal non active dans le Dashboard Stripe
    const msg = String(e?.message || e);
    if (msg.includes('No configuration provided') || msg.includes('Customer Portal')) {
      return jsonResponse({
        error: 'portal_not_configured',
        hint: 'Active le Customer Portal dans Stripe : Settings > Billing > Customer portal > Activate.'
      }, 500);
    }
    return jsonResponse({ error: msg }, 500);
  }
});
