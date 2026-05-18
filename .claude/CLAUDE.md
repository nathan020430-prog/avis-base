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

## Version actuelle
- Code en **v0.17.0-phase1** (squelette `/financement`, mock data, 1ère des 7 phases — économie collaborative)
- v0.16.x livrée : App Store ready + masquage articles test
- Tag remote : `v0.16.0-prep`, `v0.16.1` sur origin

## Mission en cours : v0.17.0 — Économie collaborative
- 7 phases successives, validation explicite à chaque palier
- Phase 1 (squelette `/financement`) : ✅ livrée
- Phase 3 UI (`/devenir-membre` + modale tip + tip jar inline articles) : ✅ livrée
- Phase 5 UI (`/mon-financement` dashboard contributeur) : ✅ livrée — mock data, KYC stub, bouton virement disabled si <20€
- Phase 2 (migration SQL — `v0.17.0-financement-migration.sql` : 9 tables + 4 vues + 4 RPCs + RLS strict) : ✅ livrée — à exécuter dans Supabase SQL Editor
- Phase 3 backend : Edge Functions `create-checkout-session` + `stripe-webhook` — à faire quand SQL en place
- Phase 4 : branchement Realtime sur vraies données
- Phase 5 backend : RPC track-view + agrégat quotidien — à faire avec SQL
- Phase 6 : algo mensuel + cron compute-monthly-payout
- Phase 7 : Stripe Connect + virements (⚠️ valider statut juridique ACPR avant)
- Décisions actées : 5€/mois, 0 salaire admin, 100% surplus aux contributeurs, opt-in affichage anonyme par défaut, seuil virement 20€

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
