# Contexte — Avis Basé

> Ce fichier est lu par Claude Code (et tout autre agent IA) à chaque session.
> Il évite de devoir répéter le contexte du projet.

## Le projet
**Avis Basé** — média collaboratif qui source tout. Site : https://avis-base.com · TikTok : @avis_base.nth

## Stack actuelle
- **Frontend** : un seul fichier `index.html` (~11 000 lignes) — HTML/CSS/JS vanilla
- **Backend** : Supabase (auth, Postgres, RLS, RPC)
- **Hébergement** : Cloudflare Pages
- **Mobile (à venir v0.16.0)** : app Expo dans un repo séparé `avis-base-app`

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
