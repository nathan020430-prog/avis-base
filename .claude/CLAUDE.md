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

## Version actuelle — v0.23.2 (Reprise de lecture mémorisée par article) — 2026-05-19
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
- **v0.23.2 → Reprise de lecture** :
  - Module ReadResume : sauvegarde la position de scroll (en %) par slug, debounced, cleanup 30j, max 100 entrées
  - Banner "🔖 Tu en étais à X % — Reprendre ?" au-dessus de l'article
  - 2 actions : Reprendre (scroll smooth) ou Recommencer (purge l'entrée)

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
