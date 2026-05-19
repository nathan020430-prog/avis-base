# Contexte — Avis Basé

> Ce fichier est lu par Claude Code (et tout autre agent IA) à chaque session.
> Il évite de devoir répéter le contexte du projet.

## Le projet
**Avis Basé** — média collaboratif qui source tout. Site : https://avis-base.com · TikTok : @avis_base.nth

## Stack actuelle
- **Frontend** : un seul fichier `index.html` (~14 600 lignes) — HTML/CSS/JS vanilla
- **Backend** : Supabase (auth, Postgres, RLS, RPC)
- **Hébergement** : Cloudflare Pages
- **PWA** : installable iOS/Android, soumise aux App Store + Play Store
- **Mobile native** : app Expo dans un repo séparé `avis-base-app` (en cours)

## Version actuelle — v0.29.0 (Feed personnalisé + onboarding intérêts) — 2026-05-19
- v0.16.x → App Store ready + masquage articles test
- v0.17.0 → Économie collaborative complète (frontend + SQL + Edge Functions)
- v0.17.1 → Banner CTA Avis Basé+ sur la home
- v0.18.0 → Trust & Identity (compte renforcé + certification rémunérable + crédibilité enrichie)
- v0.18.1 → Hotfix race conditions tips/payouts + RLS contributor_balance
- v0.19.0 → Modération avancée (signalement enrichi + masquage auto + peer review + dashboard mod)
- v0.19.1 → Notifs auteur + charte de modération publique
- v0.20.0 → Transparence & Identité (/a-propos + /stats + RPCs publiques)
- v0.21.0 → Polish pre-launch (mod clips dashboard + SEO JSON-LD + onboarding + perf preconnect)
- v0.21.1 → Polish RGPD + Changelog public (bandeau cookies + modale changelog)
- v0.22.0 → Finance — Customer Portal Stripe (Edge Function + section adhésion + tips reçus)
- v0.22.1 → Finance — Top tippers publics (RPC + section /financement)
- v0.23.0 → UX lecture améliorée (prefs typo + temps restant + articles suggérés)
- v0.23.1 → Citation partageable (sélection texte article → tooltip Twitter/Copier/Partager)
- v0.23.2 → Reprise de lecture (ReadResume module + banner reprendre)
- v0.23.3 → Auto-link sources `[N]` dans le corps d'article (Wikipedia-like)
- v0.24.0 → Liste d'attente pré-lancement (table waitlist + RPC + modale form)
- v0.25.0 → Éditeur de clips refondu (preview live + templates + bulk + indicateurs)
- v0.25.1 → Publication multi-plateforme (table `clip_publications` + assistant UI 3 onglets TikTok/Twitter/Instagram)
- v0.26.0 → Help section clips (modale tutoriel 4 onglets : Capture / Édition / Publication / Best practices)
- v0.26.1 → Stats financières enrichies (RPCs `get_public_finance_summary` + `get_public_finance_history` + section "Transparence financière" sur `/stats` avec mini-chart Chart.js 12 mois)
- v0.26.2 → Search amélioré (historique 8 dernières recherches en localStorage + suggestions groupées Articles + Sources)
- **v0.26.3 → Service Worker offline + PWA polish** :
  - Bump cache `v0.26.3` dans `sw.js` (busts les anciens caches)
  - Nouvelle page `/offline.html` stylisée (auto-reload sur retour connexion)
  - Bandeau status online/offline dans l'app (`#offlineBanner`) qui apparaît auto + variante "Connexion rétablie"
  - `manifest.json` nettoyé (référence screenshot manquante retirée)
  - Migration SQL à appliquer : `v0.26.1-public-finance-stats-migration.sql` (après v0.25.1)

Tags sur origin : `v0.16.0-prep`, `v0.16.1`, `v0.17.0`, `v0.17.0-ui-and-sql`, `v0.18.0`

## ⚠️ SQL à appliquer côté Supabase (dans cet ordre)
Le code est mergé mais les migrations doivent être exécutées manuellement dans le SQL Editor :
1. `v0.17.0-financement-migration.sql` — 9 tables économie + 4 vues + 4 RPCs (✅ déjà appliquée)
2. `v0.18.0-trust-migration.sql` — `contributor_certifications` + 2 RPCs + vue publique
3. `v0.18.0-credibility-migration.sql` — `cred_score_history` + 3 RPCs
4. `v0.18.1-hotfix-money-races.sql` — **CRITIQUE** : corrige 3 race conditions sur les flux d'argent (tips + payouts) + ferme une faille RLS sur `contributor_balance`. À appliquer AVANT tout déploiement Stripe en prod.
5. `v0.19.0-moderation-migration.sql` — étend `reports` + tables `moderation_actions` & `peer_reviews` + colonnes `moderation_state`/`reports_count` sur `articles`/`clips` + RPCs `submit_report`/`submit_peer_review`/`mod_apply_action`/`get_moderation_queue`/`get_peer_review_queue`/`get_user_moderation_summary`. Tant que la migration n'est pas appliquée, le frontend retombe sur l'INSERT direct dans `reports` (compat v0.18 préservée). (✅ appliquée 2026-05-19)
6. `v0.19.1-moderation-notifs.sql` — étend `notifications.type` avec `content_hidden`/`content_restored` + trigger `notify_on_moderation_change` sur articles et clips. Sans cette migration, les notifs de masquage ne se déclencheront pas (mais aucune erreur côté front).
7. `v0.20.0-stats-migration.sql` — RPCs publiques `get_public_stats()` + `get_public_top_contributors()` pour la page `/stats`. Sans cette migration, la page affiche "Migration non appliquée" au lieu de crasher.
8. `v0.22.1-top-tippers-migration.sql` — RPC publique `get_public_top_tippers(limit, days)` pour la section "Top donateurs" sur `/financement`. Sans elle, la section est masquée silencieusement.
9. `v0.24.0-waitlist-migration.sql` — table `waitlist` + RPC `submit_waitlist()` + vue `waitlist_summary`. Permet de collecter les emails pré-lancement. Sans elle, le form affiche "Migration non appliquée" au lieu de crasher.
10. `v0.25.1-clip-publications-migration.sql` — table `clip_publications` (multi-plateforme) + trigger sync `clips.status` + vue `clip_publications_by_clip` + backfill TikTok. Sans elle, la modale de publication retombe sur l'ancien comportement (`clips.published_tiktok_url`) avec toast d'info.
11. `v0.26.1-public-finance-stats-migration.sql` — RPCs publiques `get_public_finance_summary()` + `get_public_finance_history(n)` pour la section "Transparence financière" sur `/stats`. Sans elle, la section est masquée silencieusement.
12. `v0.26.4-fix-stats-rpc.sql` — **HOTFIX** : la RPC `get_public_stats()` (v0.20.0) plantait en prod (`column reports.validated does not exist`) → page `/stats` cassée. Cette migration recrée la RPC avec un handler `undefined_column` qui retombe gracieusement sur "tous les `resolved` comptent" si la colonne manque. À appliquer après v0.26.1.
13. `v0.28.0-mutual-followers.sql` — RPC publique `get_mutual_followers(p_target_id, p_limit)` qui retourne les profils suivis à la fois par moi et par la cible (preuve sociale "Suivi par @x, @y et N autres que tu suis" sur la page profil). Sans elle, la section mutual followers est masquée silencieusement.
14. `v0.29.0-user-interests.sql` — table `user_interests` + 3 RPCs (`set_user_interests`, `get_user_interests`, `get_suggested_authors_by_interest`). Permet à l'utilisateur de choisir 3+ sujets favoris à l'onboarding, alimente le feed "Pour toi" et les suggestions d'auteurs. Sans elle, l'étape onboarding "Choisis tes sujets" enregistre rien et le feed "Pour toi" retombe sur le filtre par auteurs suivis uniquement.

Les sections UI correspondantes affichent un fallback gracieux ("Migration non appliquée") tant que pas exécutées.

## ⚠️ Reste à faire (admin/owner, pas du code)
**Stripe — pour activer l'économie collab en prod** (voir `supabase/functions/README.md`) :
1. Créer compte Stripe (mode test), produit 5€/mois, copier `price_id`
2. Set Supabase secrets : `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `PRICE_ID_MEMBERSHIP`, `SITE_URL`
3. Déployer les 6 Edge Functions : `supabase functions deploy create-checkout-session create-portal-session stripe-webhook compute-monthly-payout request-payout stripe-connect-onboarding`
4. Configurer webhook Stripe → URL Supabase → copier `whsec_` → secret
5. **Activer Customer Portal** : Stripe Dashboard → Settings → Billing → Customer portal → Activate (v0.22.0, sinon le bouton "Gérer mon abonnement" sur /mon-financement retourne une erreur claire)
6. (Phase 6) Activer extension pg_cron + `select cron.schedule(...)` pour compute-monthly-payout mensuel
7. (Phase 7) Activer Stripe Connect Express + ⚠️ **consulter avocat ACPR avant 1er virement réel** (statut intermédiaire de paiement)

**Auth — Phase 1** :
1. Supabase Dashboard → Auth → Settings → activer "Confirm email"
2. (Optionnel) Cloudflare Turnstile → créer site → remplacer la sitekey dans `index.html` (actuellement `1x00000000000000000000AA` de test)

**Décisions économie collab actées (ne pas y revenir sans demander)** :
5€/mois, 0 salaire admin, 100% surplus aux contributeurs, opt-in affichage anonyme par défaut, seuil virement 20€, certification rémunérable obligatoire

## Versionning
- Pré-release `0.x.x` jusqu'au lancement public en v1.0.0
- Version actuelle dans `README.md` (et au début d'`index.html`)
- À chaque release : `git tag v0.x.y && git push --tags`

## Choix éditoriaux structurants
1. **Écriture d'articles + édition de clips = DESKTOP UNIQUEMENT**
   Ne JAMAIS débloquer ces actions sur mobile (web ou app native).
   Sur mobile, afficher la modale "✍️ La rédaction se fait sur ordinateur".
2. **Tout sourcer** — toute affirmation factuelle doit avoir une source.
3. **Pas de com publique avant v1.0.0** — soft-launch jusqu'à ce que tout soit prêt.

## Avant d'écrire du code
1. Lis le PLAN_DEV.md pour voir où on en est
2. Propose le plan détaillé + fichiers/tables affectés
3. Attends validation puis code par petites étapes

## Sécurité
- La clé Supabase dans `index.html` est la clé **anon** (publique).
- Toutes les écritures sont protégées par les **RLS** Postgres.
- NE JAMAIS commiter la clé `service_role`.
- Le workflow `.github/workflows/sanity.yml` bloque les PRs contenant `service_role`.

## Déploiement
- `git push` sur `main` → build auto Cloudflare Pages
- Avec le workflow `.github/workflows/deploy.yml`, je peux aussi le forcer manuellement
- App mobile : voir `avis-base-app/AUTONOMY.md`
