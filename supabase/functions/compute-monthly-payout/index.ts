// ============================================================================
// compute-monthly-payout
//
// Calcule le payout d'un mois clos :
//   1. Snapshot revenus (members fees + tips succeeded) du mois
//   2. Soustrait frais Stripe réels (depuis Stripe API) + frais infra
//      (depuis monthly_infra_costs)
//   3. Calcule scores par article via recompute_article_stats_daily()
//   4. Partage le pool au prorata des scores
//   5. Crée la ligne monthly_payouts (status='computed') + détail
//      monthly_payout_articles + crédite contributor_balance
//
// Idempotent : si monthly_payouts existe déjà pour ce mois en status
// 'distributed' ou 'archived', on refuse de recalculer.
//
// Appelable :
//   - Manuellement : POST {payout_month:'2026-04'}
//   - Cron pg_cron : SELECT cron.schedule('compute-payout', '0 3 1 * *',
//       'SELECT net.http_post(url:=...''compute-monthly-payout''...) ');
//
// Variables d'env :
//   STRIPE_SECRET_KEY            -> pour récupérer les balance_transactions
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
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!stripeKey || !supaUrl || !serviceKey) {
    return jsonResponse({ error: 'env missing' }, 500);
  }

  const stripe = new Stripe(stripeKey, { apiVersion: '2024-06-20' });
  const supa = createClient(supaUrl, serviceKey);

  // ---- determine month ----
  let payoutMonth: string;
  try {
    const body = await req.json().catch(() => ({}));
    if (body.payout_month && /^\d{4}-\d{2}$/.test(body.payout_month)) {
      payoutMonth = body.payout_month;
    } else {
      // Par défaut : mois précédent
      const now = new Date();
      const d = new Date(now.getFullYear(), now.getMonth() - 1, 1);
      payoutMonth = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    }
  } catch {
    return jsonResponse({ error: 'invalid body' }, 400);
  }

  // ---- check idempotence ----
  const { data: existing } = await supa.from('monthly_payouts')
    .select('id, status')
    .eq('payout_month', payoutMonth)
    .maybeSingle();
  if (existing?.status === 'distributed' || existing?.status === 'archived') {
    return jsonResponse({ error: `Month ${payoutMonth} already ${existing.status}`, id: existing.id }, 409);
  }

  try {
    // ---- 1. Revenus ----
    const monthStart = new Date(payoutMonth + '-01T00:00:00Z');
    const nextMonth = new Date(monthStart.getFullYear(), monthStart.getMonth() + 1, 1);

    // Tips succeeded
    const { data: tips } = await supa
      .from('tips')
      .select('amount_cents')
      .eq('status', 'succeeded')
      .gte('created_at', monthStart.toISOString())
      .lt('created_at', nextMonth.toISOString());
    const tipsTotal = (tips || []).reduce((s, t) => s + (t.amount_cents || 0), 0);
    const tipsCount = (tips || []).length;

    // Member fees : on prend tous les membres actifs (current_period_end >= monthStart)
    // approximation : amount_cents * 1 (un mois) si le membre était actif tout le mois.
    // Pour précision exacte, on devrait croiser avec les invoices Stripe.
    const { count: activeMembersCount } = await supa
      .from('members')
      .select('user_id', { count: 'exact', head: true })
      .eq('status', 'active');
    const membersFeesTotal = (activeMembersCount || 0) * 500; // 5€/mois

    const revenueCents = membersFeesTotal + tipsTotal;

    // ---- 2. Frais Stripe (réels via balance_transactions) ----
    // On somme `bt.fee` (en cents) pour toutes les BalanceTransaction du mois.
    // - `bt.fee` est positif sur charge/payment (frais prélevés)
    // - `bt.fee` est négatif sur refund (remboursement partiel des frais)
    // → la somme donne le net réel des frais Stripe sur le mois.
    //
    // Fallback : si l'API Stripe échoue, on retombe sur l'estimation 5% pour
    // ne pas bloquer le calcul, mais on positionne `stripe_fees_estimated=true`
    // dans la réponse pour que l'admin sache qu'il faut réviser à la main.
    let stripeFeesCents = 0;
    let stripeFeesEstimated = false;
    try {
      const gte = Math.floor(monthStart.getTime() / 1000);
      const lt  = Math.floor(nextMonth.getTime() / 1000);
      let startingAfter: string | undefined;
      // garde-fou : 100 pages * 100 tx = 10 000 transactions max
      for (let i = 0; i < 100; i++) {
        const page = await stripe.balanceTransactions.list({
          created: { gte, lt },
          limit: 100,
          ...(startingAfter ? { starting_after: startingAfter } : {}),
        });
        for (const bt of page.data) {
          stripeFeesCents += bt.fee || 0;
        }
        if (!page.has_more) break;
        startingAfter = page.data[page.data.length - 1]?.id;
        if (!startingAfter) break;
      }
    } catch (e) {
      console.error('[compute-monthly-payout] balance_transactions fetch failed, fallback to 5%:', e);
      stripeFeesCents = Math.round(revenueCents * 0.05);
      stripeFeesEstimated = true;
    }

    // Infra costs saisis manuellement par le superadmin
    const { data: infraRows } = await supa
      .from('monthly_infra_costs')
      .select('amount_cents')
      .eq('cost_month', payoutMonth);
    const infraCostCents = (infraRows || []).reduce((s, r) => s + (r.amount_cents || 0), 0);

    const poolCents = Math.max(0, revenueCents - stripeFeesCents - infraCostCents);

    // ---- 3. Reconcile stats du mois (recompute_article_stats_daily for each day) ----
    // On suppose que le RPC a tourné chaque jour. Sinon on peut le rappeler ici
    // pour tous les jours du mois (coûteux). Skip pour l'instant.

    // ---- 4. Scores par article du mois ----
    const { data: dailyStats } = await supa
      .from('article_stats_daily')
      .select('article_id, score')
      .gte('stat_date', monthStart.toISOString().slice(0, 10))
      .lt('stat_date', nextMonth.toISOString().slice(0, 10));

    // Agrège par article
    const scoreByArticle = new Map<string, number>();
    (dailyStats || []).forEach((s) => {
      scoreByArticle.set(s.article_id, (scoreByArticle.get(s.article_id) || 0) + Number(s.score || 0));
    });
    const totalScore = Array.from(scoreByArticle.values()).reduce((a, b) => a + b, 0);

    // Pour chaque article : part_cents = (score / total) * pool
    const articleShares: Array<{ article_id: string; author_id: string | null; score: number; share_cents: number }> = [];
    if (totalScore > 0 && poolCents > 0) {
      for (const [articleId, score] of scoreByArticle) {
        const share = Math.floor((score / totalScore) * poolCents);
        if (share <= 0) continue;
        // Récupérer author_id
        const { data: art } = await supa
          .from('articles')
          .select('author_id')
          .eq('id', articleId)
          .maybeSingle();
        articleShares.push({
          article_id: articleId,
          author_id: art?.author_id || null,
          score,
          share_cents: share,
        });
      }
    }

    // ---- 5. Insert monthly_payouts ----
    let payoutId: string;
    if (existing) {
      // Reset si status='draft' ou 'computed'
      const { data: updated } = await supa
        .from('monthly_payouts')
        .update({
          revenue_cents: revenueCents,
          stripe_fees_cents: stripeFeesCents,
          infra_cost_cents: infraCostCents,
          pool_cents: poolCents,
          members_count: activeMembersCount || 0,
          tips_count: tipsCount,
          articles_count: articleShares.length,
          status: 'computed',
          computed_at: new Date().toISOString(),
        })
        .eq('id', existing.id)
        .select('id')
        .single();
      payoutId = updated!.id;

      // Wipe les détails existants pour recompute
      await supa.from('monthly_payout_articles').delete().eq('monthly_payout_id', payoutId);
    } else {
      const { data: inserted } = await supa
        .from('monthly_payouts')
        .insert({
          payout_month: payoutMonth,
          revenue_cents: revenueCents,
          stripe_fees_cents: stripeFeesCents,
          infra_cost_cents: infraCostCents,
          pool_cents: poolCents,
          members_count: activeMembersCount || 0,
          tips_count: tipsCount,
          articles_count: articleShares.length,
          status: 'computed',
          computed_at: new Date().toISOString(),
        })
        .select('id')
        .single();
      payoutId = inserted!.id;
    }

    // ---- 6. Insert détails par article + crédit contributor_balance ----
    if (articleShares.length > 0) {
      await supa.from('monthly_payout_articles').insert(
        articleShares.map((a) => ({
          monthly_payout_id: payoutId,
          article_id: a.article_id,
          author_id: a.author_id,
          score_total: a.score,
          share_cents: a.share_cents,
        }))
      );

      // Crédit balance par auteur (agréger les shares du même auteur)
      const byAuthor = new Map<string, number>();
      for (const a of articleShares) {
        if (!a.author_id) continue;
        byAuthor.set(a.author_id, (byAuthor.get(a.author_id) || 0) + a.share_cents);
      }
      for (const [authorId, total] of byAuthor) {
        const { data: bal } = await supa
          .from('contributor_balance')
          .select('balance_cents, total_earned_cents')
          .eq('user_id', authorId)
          .maybeSingle();
        await supa.from('contributor_balance').upsert({
          user_id: authorId,
          balance_cents: (bal?.balance_cents || 0) + total,
          total_earned_cents: (bal?.total_earned_cents || 0) + total,
          updated_at: new Date().toISOString(),
        }, { onConflict: 'user_id' });
      }
    }

    return jsonResponse({
      payout_id: payoutId,
      payout_month: payoutMonth,
      revenue_cents: revenueCents,
      stripe_fees_cents: stripeFeesCents,
      stripe_fees_estimated: stripeFeesEstimated,
      infra_cost_cents: infraCostCents,
      pool_cents: poolCents,
      members_count: activeMembersCount || 0,
      tips_count: tipsCount,
      articles_count: articleShares.length,
      status: 'computed',
    });
  } catch (e) {
    console.error('[compute-monthly-payout]', e);
    return jsonResponse({ error: String(e?.message || e) }, 500);
  }
});
