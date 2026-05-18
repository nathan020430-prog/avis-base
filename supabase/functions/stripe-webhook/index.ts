// ============================================================================
// stripe-webhook
//
// Endpoint webhook Stripe. Traite les événements :
//   - checkout.session.completed         (membre nouveau ou tip succeeded)
//   - customer.subscription.created
//   - customer.subscription.updated
//   - customer.subscription.deleted
//   - invoice.paid                       (renouvellement mensuel)
//   - payment_intent.succeeded           (tips one-shot)
//
// Variables d'env requises :
//   STRIPE_SECRET_KEY
//   STRIPE_WEBHOOK_SECRET
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY    -> service_role pour écrire dans members/tips
//
// Configuration Stripe Dashboard :
//   Webhooks → Add endpoint → URL = https://<project>.supabase.co/functions/v1/stripe-webhook
//   Events à écouter : checkout.session.completed, customer.subscription.*,
//                       invoice.paid, payment_intent.succeeded
//
// Déploiement : supabase functions deploy stripe-webhook --no-verify-jwt
// (NB : --no-verify-jwt car le webhook Stripe ne porte pas de JWT, on
//  vérifie via stripe-signature à la place)
// ============================================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (req) => {
  const stripeKey  = Deno.env.get('STRIPE_SECRET_KEY');
  const webhookSec = Deno.env.get('STRIPE_WEBHOOK_SECRET');
  const supaUrl    = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

  if (!stripeKey || !webhookSec) {
    return new Response('Stripe env missing', { status: 500 });
  }
  if (!supaUrl || !serviceKey) {
    return new Response('Supabase env missing', { status: 500 });
  }

  const stripe = new Stripe(stripeKey, { apiVersion: '2024-06-20' });
  const supa = createClient(supaUrl, serviceKey);

  // ---- signature verification ----
  const sig = req.headers.get('stripe-signature');
  if (!sig) return new Response('Missing signature', { status: 400 });
  const rawBody = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(rawBody, sig, webhookSec);
  } catch (e) {
    console.error('[stripe-webhook] sig verification failed', e);
    return new Response('Bad signature', { status: 400 });
  }

  // ---- dispatch ----
  try {
    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session;
        const userId = session.client_reference_id || session.metadata?.user_id;
        if (!userId) {
          console.warn('[checkout.session.completed] no user_id in session', session.id);
          break;
        }

        if (session.mode === 'subscription') {
          // L'événement customer.subscription.created va aussi arriver
          // mais on enregistre déjà le customer_id ici (idempotent)
          const customerId = session.customer as string;
          const subId = session.subscription as string;
          const displayConsent = session.metadata?.display_consent === 'true';

          await supa.from('members').upsert({
            user_id: userId,
            stripe_customer_id: customerId,
            stripe_subscription_id: subId,
            status: 'active',
            display_consent: displayConsent,
            updated_at: new Date().toISOString(),
          }, { onConflict: 'user_id' });
        } else if (session.mode === 'payment') {
          // Tip one-shot : on n'enregistre rien ici, on attend
          // payment_intent.succeeded qui a toutes les metadata propres.
        }
        break;
      }

      case 'customer.subscription.created':
      case 'customer.subscription.updated': {
        const sub = event.data.object as Stripe.Subscription;
        const userId = sub.metadata?.user_id;
        if (!userId) {
          console.warn('[subscription.*] no user_id in metadata', sub.id);
          break;
        }
        await supa.from('members').upsert({
          user_id: userId,
          stripe_customer_id: sub.customer as string,
          stripe_subscription_id: sub.id,
          status: sub.status,
          tier: 'plus',
          amount_cents: sub.items.data[0]?.price.unit_amount || 500,
          current_period_end: sub.current_period_end
            ? new Date(sub.current_period_end * 1000).toISOString()
            : null,
          cancel_at_period_end: sub.cancel_at_period_end,
          cancelled_at: sub.canceled_at ? new Date(sub.canceled_at * 1000).toISOString() : null,
          updated_at: new Date().toISOString(),
        }, { onConflict: 'user_id' });
        break;
      }

      case 'customer.subscription.deleted': {
        const sub = event.data.object as Stripe.Subscription;
        const userId = sub.metadata?.user_id;
        if (!userId) break;
        await supa.from('members').update({
          status: 'cancelled',
          cancelled_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }).eq('user_id', userId);
        break;
      }

      case 'invoice.paid': {
        // Renouvellement mensuel — on met à jour current_period_end
        const invoice = event.data.object as Stripe.Invoice;
        if (invoice.subscription) {
          const subId = invoice.subscription as string;
          const sub = await stripe.subscriptions.retrieve(subId);
          const userId = sub.metadata?.user_id;
          if (userId) {
            await supa.from('members').update({
              status: 'active',
              current_period_end: new Date(sub.current_period_end * 1000).toISOString(),
              updated_at: new Date().toISOString(),
            }).eq('user_id', userId);
          }
        }
        break;
      }

      case 'payment_intent.succeeded': {
        const pi = event.data.object as Stripe.PaymentIntent;
        const meta = pi.metadata || {};
        const userId = meta.user_id;
        if (!userId) {
          // Ce PI peut être lié à une subscription (renouvellement) — déjà géré
          // par invoice.paid. On skip.
          break;
        }
        // C'est un tip one-shot
        const targetType = (meta.target_type as string) || 'pool';
        await supa.from('tips').upsert({
          sender_user_id: userId,
          target_type: targetType,
          target_article_id: meta.target_article_id || null,
          target_user_id: meta.target_user_id || null,
          amount_cents: pi.amount,
          stripe_payment_intent_id: pi.id,
          status: 'succeeded',
          display_consent: meta.display_consent === 'true',
        }, { onConflict: 'stripe_payment_intent_id' });

        // Si tip pour un article ou un contributeur, créditer immédiatement la balance
        // du contributeur (100% net, 0 commission — frais absorbés par adhésion).
        let targetUserId: string | null = null;
        if (targetType === 'article' && meta.target_article_id) {
          const { data: art } = await supa
            .from('articles')
            .select('author_id')
            .eq('id', meta.target_article_id)
            .maybeSingle();
          targetUserId = art?.author_id || null;
        } else if (targetType === 'contributor') {
          targetUserId = meta.target_user_id || null;
        }
        if (targetUserId) {
          // Crédit atomique + idempotent via RPC (cf. v0.18.1-hotfix-money-races.sql).
          // La RPC verrouille la ligne `tips` (FOR UPDATE), incrémente la balance
          // en une seule instruction SQL, et pose `tips.credited_at` pour bloquer
          // les retries de Stripe.
          const { error: creditErr } = await supa.rpc('credit_tip_to_contributor', {
            p_payment_intent_id: pi.id,
            p_target_user_id:    targetUserId,
            p_amount_cents:      pi.amount,
          });
          if (creditErr) {
            // On laisse Stripe relivrer le webhook : si la RPC n'existe pas encore
            // (migration v0.18.1 non appliquée), 500 → Stripe réessayera.
            console.error('[stripe-webhook] credit_tip_to_contributor failed', creditErr);
            throw new Error(`credit_failed: ${creditErr.message}`);
          }
        }
        break;
      }

      default:
        console.log('[stripe-webhook] unhandled event', event.type);
    }

    return new Response(JSON.stringify({ received: true }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('[stripe-webhook] handler error', e);
    return new Response(JSON.stringify({ error: String(e?.message || e) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
