// ============================================================================
// Edge Function : send-push-notification
// ----------------------------------------------------------------------------
// Recoit un payload { user_id, title, body, url, icon, badge, tag } depuis
// le trigger DB notify_push_on_notification (declenche par insert dans
// `notifications`).
//
// Lit toutes les push_subscriptions du user (service_role), signe chaque
// envoi avec les cles VAPID, POST sur l'endpoint du browser. Si un endpoint
// renvoie 404/410 (Gone), on le supprime de la table.
//
// Env requis :
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY
//   VAPID_PUBLIC_KEY
//   VAPID_PRIVATE_KEY
//   VAPID_SUBJECT    (mailto:contact@avis-base.com)
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import * as webpush from 'https://esm.sh/web-push@3.6.7';
import { handleCors, jsonResponse } from '../_shared/cors.ts';

interface PushPayload {
  user_id: string;
  title: string;
  body: string;
  url?: string;
  icon?: string;
  badge?: string;
  tag?: string;
}

interface PushSub {
  id: string;
  endpoint: string;
  p256dh: string;
  auth_key: string;
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== 'POST') return jsonResponse({ error: 'method_not_allowed' }, 405);

  const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
  const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const VAPID_PUBLIC_KEY = Deno.env.get('VAPID_PUBLIC_KEY');
  const VAPID_PRIVATE_KEY = Deno.env.get('VAPID_PRIVATE_KEY');
  const VAPID_SUBJECT = Deno.env.get('VAPID_SUBJECT') || 'mailto:contact@avis-base.com';

  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return jsonResponse({ error: 'supabase_env_missing' }, 500);
  }

  // Auth : seul l'appelant en possession du service_role_key peut envoyer un
  // push (le trigger DB `notify_push_on_notification` l'attache via pg_net,
  // cf. v0.30.0-push-subscriptions.sql). Sans cette garde, l'endpoint est
  // ouvert sur internet et n'importe qui peut spoofer une push a un user_id
  // arbitraire (phishing).
  const authHeader = req.headers.get('authorization') || '';
  const expected = `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`;
  if (authHeader !== expected) {
    return jsonResponse({ error: 'unauthorized' }, 401);
  }

  if (!VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY) {
    // Pas de VAPID configure : silencieusement ignore (cas dev / pre-prod)
    return jsonResponse({ ok: true, sent: 0, skipped: 'vapid_not_configured' });
  }

  let payload: PushPayload;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: 'invalid_json' }, 400);
  }

  if (!payload.user_id || !payload.title) {
    return jsonResponse({ error: 'missing_fields' }, 400);
  }

  const supa = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  // Recupere toutes les subscriptions du user
  const { data: subs, error } = await supa
    .from('push_subscriptions')
    .select('id, endpoint, p256dh, auth_key')
    .eq('user_id', payload.user_id);

  if (error) return jsonResponse({ error: error.message }, 500);
  if (!subs || subs.length === 0) return jsonResponse({ ok: true, sent: 0 });

  webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

  const notifPayload = JSON.stringify({
    title: payload.title,
    body: payload.body,
    url: payload.url || '/',
    icon: payload.icon || '/icon-192.png',
    badge: payload.badge || '/icon-72.png',
    tag: payload.tag || 'default',
  });

  let sent = 0;
  const toDelete: string[] = [];

  await Promise.all(
    (subs as PushSub[]).map(async (s) => {
      try {
        await webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth_key } },
          notifPayload,
          { TTL: 60 * 60 * 24 } // 24h
        );
        sent++;
      } catch (e: any) {
        const status = e?.statusCode || 0;
        // 404 Not Found ou 410 Gone -> endpoint mort, on supprime
        if (status === 404 || status === 410) {
          toDelete.push(s.id);
        }
        // 413 Payload Too Large, 429 Too Many Requests : on garde, on log
        console.warn('[push] send failed:', status, e?.body || e?.message);
      }
    }),
  );

  if (toDelete.length > 0) {
    await supa.from('push_subscriptions').delete().in('id', toDelete);
  }

  return jsonResponse({ ok: true, sent, removed: toDelete.length });
});
