# Avis Basé

Le média collaboratif qui source tout. Chaque article part d'une vidéo longue, détaille le contexte et cite ses sources.

🌐 **Site :** [avis-base.com](https://avis-base.com)
🎵 **TikTok :** [@avis_base.nth](https://www.tiktok.com/@avis_base.nth)

---

## Stack

- **Frontend** : un seul fichier `index.html` (~14 600 lignes) — HTML/CSS/JS vanilla
- **Backend** : [Supabase](https://supabase.com) (auth, Postgres, RLS, RPC)
- **Hébergement** : [Cloudflare Pages](https://pages.cloudflare.com) (gratuit, CDN mondial)
- **Domaine** : `avis-base.com`

## Déploiement

Le déploiement est automatique : un `git push` sur la branche `main` déclenche un build Cloudflare Pages.

### Premier déploiement

1. Va sur [dash.cloudflare.com](https://dash.cloudflare.com) → **Workers & Pages** → **Create** → **Pages** → **Connect to Git**
2. Sélectionne ce repo (`avis-base`)
3. Build settings :
   - **Framework preset** : `None`
   - **Build command** : *(laisser vide)*
   - **Build output directory** : `/`
4. **Save and Deploy**

### Custom domain

- Cloudflare Pages → ton projet → **Custom domains** → ajoute `avis-base.com` et `www.avis-base.com`
- Si le domaine est chez Cloudflare Registrar : DNS auto-config en 1 clic
- Sinon : pointe les nameservers du registrar vers Cloudflare

## Configuration Supabase

Avant la mise en prod, dans le dashboard Supabase :

- **Auth → URL Configuration** : ajoute `https://avis-base.com` aux **Site URL** et **Redirect URLs**
- **Project Settings → API → CORS** : ajoute `https://avis-base.com`

## Migrations SQL

Le fichier [`v0.8-migration.sql`](./v0.8-migration.sql) contient les tables, RPC et policies de la V0.8 (économie de pièces). À exécuter une fois dans le SQL editor Supabase.

## Versions

- **v0.23.2** — Reprise de lecture : la position de scroll est mémorisée par article dans localStorage. À la réouverture, banner "Reprendre à X %" avec choix Reprendre / Recommencer. Cleanup auto 30j + max 100 entrées.
- **v0.23.1** — Citation partageable : sélectionner du texte dans un article fait apparaître un tooltip "Twitter / Copier / Partager", avec attribution auteur + lien article. Format Twitter : `« citation » — @auteur via @avis_base.nth`.
- **v0.23.0** — UX lecture : préférences typographiques (3 tailles + Serif/Sans-serif, persistance localStorage) + temps de lecture restant dynamique + 3 articles suggérés en fin d'article (même thème + likes + reads, exclusion des articles déjà lus en session).
- **v0.22.1** — Finance — Top tippers : RPC `get_public_top_tippers(limit, days)` + section "Top donateurs — 30 derniers jours" sur `/financement` (opt-in `display_consent`). La page financement est désormais 100 % alimentée par les vraies vues.
- **v0.22.0** — Finance — Customer Portal Stripe : nouvelle Edge Function `create-portal-session` + section "Mon adhésion" sur `/mon-financement` (statut, prochain renouvellement, bouton "Gérer mon abonnement" via Stripe Billing Portal) + historique des tips reçus en tant que contributeur, agrégé par mois.
- **v0.21.1** — Polish RGPD : bandeau cookies/RGPD informatif (sticky-bottom dismissible) + page Changelog publique (modale `#changelog` accessible depuis footer / À propos / hash deep-link). Footer enrichi à 5 liens (À propos · Stats · Changelog · Charte éditoriale · Charte de modération).
- **v0.21.0** — Polish pre-launch : modération clips dans le dashboard mod (ouverture parent article/comment) + audit SEO (NewsArticle JSON-LD par article + meta `article:*`) + onboarding nouveau user (tour guidé 5 étapes + suggestions follow) + audit perf (preconnect Supabase/CDN, dns-prefetch YouTube/Cloudflare, `defer` sur Supabase JS, color-scheme).
- **v0.20.0** — Transparence & Identité : page **/a-propos** (manifeste, différenciateurs, équipe, liens) + page **/stats** publiques (compteurs articles/contributeurs/sources/commentaires/basitude moyenne + stats modération + top 10 contributeurs). RPCs `get_public_stats()` / `get_public_top_contributors()` ouvertes à `anon`.
- **v0.19.1** — Modération (suite) : notifications auteur quand son contenu est masqué/restauré (trigger DB) + charte de modération publique (modale `#charte-moderation` accessible depuis footer / signalement / charte éditoriale)
- **v0.19.0** — Modération avancée : signalement enrichi (8 raisons + 3 niveaux de sévérité), masquage auto (≥3 signalements distincts ou 1 priorité haute), peer review communautaire (score ≥50, quorum 3 votes), dashboard mod (admin ou score ≥75), journal d'actions, RPC `submit_report`/`submit_peer_review`/`mod_apply_action`
- **v0.18.0** — Trust & Identity : compte renforcé (captcha + charte + email confirm + min 8 chars + restriction écriture 7 jours), certification "Auteur rémunérable" (4 critères cumulatifs avec roadmap personnelle), crédibilité enrichie (badges multiples ⭐📝✓💛 + breakdown public + historique)
- **v0.17.1** — Banner CTA Avis Basé+ discret au-dessus du masthead (dismissible)
- **v0.17.0** — Économie collaborative complète :
  - `/financement` (10 sections + camembert/ligne 12 mois Chart.js, mock data + live ticker)
  - `/devenir-membre` (hero + price card 5€/mois + opt-in mur + 3 benefits + FAQ)
  - Modale "Don ponctuel" (presets 1/3/5/10€ + libre + opt-in + bénéficiaire + summary live)
  - Tip jar **inline** sur chaque article publié (presets + libre + opt-in pseudo)
  - `/mon-financement` (dashboard contributeur : cagnotte €/mois, total reversé, articles du mois avec stats détaillées, KYC Stripe Connect stub, toggle pseudo public, historique virements)
  - Lien "Mon financement" dans le user menu (visible si connecté)
  - SQL (Phase 2), Stripe Checkout (Phase 3 backend), Realtime (Phase 4), algo mensuel (Phase 6) et Stripe Connect (Phase 7) : à câbler en fin de chantier.
- **v0.16.1** — Masque les articles "test/demo" du feed public (visibles pour l'auteur et l'admin)
- **v0.16.0** — Préparation App Store : pages légales (CGU, confidentialité, support, suppression compte), migration Apple-ready (blocage, suppression compte), section download App Store + Play Store
- **v0.11.3** — Correctifs (notif target_type profile, follow CHECK constraint, DM iOS zoom-in + safe-area + touch targets)
- **v0.11.2** — Soft-launch : refonte esthétique DM, profil public style Instagram, refonte modal d'édition profil
- **v0.11.1** — DM : refonte esthétique éditoriale
- **v0.11.0** — PWA installable (App Store / Play Store ready) + Système de messagerie directe (DM)
- **v0.10.0** — Système de follow + fil personnalisé « Mon Feed » + niveaux de Basitude
- **v0.9.7** — Notifications in-app (cloche dans le masthead, badge non-lues, panel realtime, triggers Postgres)
- **v0.9.6** — Mobile fluidity (viewport, inputs, paint)
- **v0.9.5** — Mobile fluidity (perf et tactile)
- **v0.9.4** — Pack animations
- **v0.9.0/Broadsheet** — Refonte direction artistique « Broadsheet » (masthead journal, tokens encre/papier)
- **v0.9.0** — Mobile interactif (édition profil, favoris, signalement d'articles, charte éditoriale)
- **v0.8.3.2** — Mode mobile lecture seule + bottom nav + bottom-sheet menu compte
- **v0.8.3** — Détection mobile + blocage écriture/édition sur mobile (choix éditorial)
- **v0.8.2** — Pagination & compteur de publications
- **v0.8.0.1** — Correctifs V0.8 (collisions CSS modales, boost dans "À la une")
- **v0.8** — Économie de pièces (gain par lectures, pourboires, boost, badges) + score de crédibilité automatique
- **v0.7.1** — Refonte UI top bar, design plus éditorial
- **v0.7** — Menu nav unifié

## Migrations SQL à appliquer (dans l'ordre)

1. `v0.8-migration.sql` (V0.8 — économie de pièces)
2. `schema_v083.sql` (V0.8.3 — schéma complet refactor)
3. `hotfix_v0832_comments.sql` (V0.8.3.2 — commentaires polymorphes)
4. `v0.9.0-migration.sql` (V0.9.0 — profils enrichis + favoris)
5. `v0.9.7-migration.sql` (V0.9.7 — notifications in-app : table, RLS, triggers, RPC)
6. `v0.10.0-migration.sql` (V0.10.0 — follows, compteurs, trigger notif follow)
7. `v0.11.0-dm-migration.sql` (V0.11.0 — messagerie directe : threads, participants, messages, RLS)
8. `v0.11.2-dm-fix-rls.sql` (V0.11.2 — correctif récursion RLS dm_participants)
9. `v0.11.3-fix-notif-target-type-profile.sql` (V0.11.3 — contrainte CHECK notif target_type profile)
10. `v0.16.0-migration.sql` (V0.16.0 — user_blocks + account_deletion_requests pour Apple App Store)
11. `v0.17.0-financement-migration.sql` (V0.17.0 — économie collaborative : 9 tables + 4 vues + 4 RPCs + RLS strict)
12. `v0.18.0-trust-migration.sql` (V0.18.0 Phase 2 — certification rémunérable : `contributor_certifications` + 2 RPCs + vue publique)
13. `v0.18.0-credibility-migration.sql` (V0.18.0 Phase 3 — `cred_score_history` + 3 RPCs `recompute_user_cred_score`, `get_user_cred_breakdown`, `recompute_all_cred_scores`)
14. `v0.18.1-hotfix-money-races.sql` (V0.18.1 — corrige 3 race conditions sur les flux d'argent + ferme une faille RLS sur `contributor_balance`)
15. `v0.19.0-moderation-migration.sql` (V0.19.0 — modération avancée : extension `reports` + `moderation_state` sur articles/clips + tables `moderation_actions` & `peer_reviews` + RPCs `submit_report`/`submit_peer_review`/`mod_apply_action`/`get_moderation_queue`/`get_peer_review_queue`)
16. `v0.19.1-moderation-notifs.sql` (V0.19.1 — étend `notifications.type` (+`content_hidden`, `content_restored`) + trigger `notify_on_moderation_change` sur articles/clips)
17. `v0.20.0-stats-migration.sql` (V0.20.0 — RPCs publiques `get_public_stats()` + `get_public_top_contributors()`)
18. **`v0.22.1-top-tippers-migration.sql`** (V0.22.1 — RPC publique `get_public_top_tippers(limit, days)` filtrée sur display_consent=true) ← **NOUVEAU**

## Développement local

```bash
# Sert l'index.html sur http://localhost:8000
python -m http.server 8000
```

## Sécurité

La clé Supabase exposée dans `index.html` est la clé **`anon`** (publique par design). Toutes les écritures sont protégées par les **policies RLS** côté Postgres. Aucune clé service n'est jamais commitée.

---

© Avis Basé · Beta · v0.23.2
