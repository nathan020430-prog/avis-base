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

- **v0.17.0-phase1** — Économie collaborative — squelette page `/financement` avec mock data (Phase 1/7) : 10 sections Broadsheet, camembert + ligne 12 mois (Chart.js), live ticker simulé, bouton € dans le masthead. Phases suivantes : migration SQL, Stripe, dashboards, payouts.
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
10. **`v0.16.0-migration.sql`** (V0.16.0 — user_blocks + account_deletion_requests pour Apple App Store) ← **NOUVEAU**

## Développement local

```bash
# Sert l'index.html sur http://localhost:8000
python -m http.server 8000
```

## Sécurité

La clé Supabase exposée dans `index.html` est la clé **`anon`** (publique par design). Toutes les écritures sont protégées par les **policies RLS** côté Postgres. Aucune clé service n'est jamais commitée.

---

© Avis Basé · Beta · v0.10.0
