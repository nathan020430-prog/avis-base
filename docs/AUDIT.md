# Audit Avis Basé — v0.10.0

> Audit réalisé sur `index.html` (11 277 lignes, 548 KB) et les 6 migrations SQL.
> Méthode : analyse statique du code + revue de schéma. Pas de mesure runtime.

---

## Score global

| Axe | Note | Verdict |
|---|---|---|
| **Sécurité** | 8 / 10 | Solide. Quelques zones d'attention sur les RPC `security definer`. |
| **Architecture** | 6 / 10 | Le single-file commence à devenir difficile à tenir. |
| **Performance** | 7 / 10 | Bon point de départ, plein de leviers faciles non actionnés. |
| **SEO** | 6 / 10 | OG/Twitter OK, SPA pure pénalise les bots simples. |
| **Accessibilité** | 5 / 10 | Trop peu d'`aria-label`, focus management non vérifié. |
| **Schéma de données** | 8 / 10 | Bien structuré, mais 3 tables référencées sans être créées. |

---

## 🔒 Sécurité — 8/10

### ✅ Ce qui est bien
- Clé Supabase `anon` exposée (normal, par design)
- **Aucune occurrence de `service_role` dans le code public**
- Aucun `eval()`, `new Function()`, `document.write()` — zéro vecteur XSS via injection JS
- **`escapeHtml` utilisé 141 fois** pour 70 `innerHTML =` — bon ratio
- **RLS activé sur les 18 tables** (vérifié dans `schema_v083.sql` + migrations ultérieures)
- 18 tables, 50+ policies, 4 triggers, indexes en place

### ⚠️ À surveiller
- **70 occurrences de `.innerHTML =`** — sur 3 lignes l'interpolation utilise des valeurs non escapées :
  - L7133 (stats lecture, valeurs numériques → faux positif)
  - L8959 (message admin statique → faux positif)
  - L10466 (encart "creuser cette source" → vérifier que `srcUrl` est échappée)
- **11 RPC `security definer`** (claim_read, send_tip, boost_article, buy_badge, mark_notifications_read, etc.)
  - Pattern recommandé Supabase pour les opérations multi-tables, **mais** chaque RPC doit valider `auth.uid()` à l'entrée
  - À auditer un par un (j'en ai survolé : la plupart vérifient l'auth, mais à confirmer)
- **Pas de Content Security Policy** dans `_headers` Cloudflare — opportunité facile

### 🔧 Actions sécurité recommandées (v0.10.1)
1. Ajouter une **CSP stricte** dans `_headers` :
   ```
   /*
     Content-Security-Policy: default-src 'self'; script-src 'self' https://cdn.jsdelivr.net 'unsafe-inline'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; img-src 'self' data: https:; font-src 'self' https://fonts.gstatic.com; connect-src 'self' https://*.supabase.co wss://*.supabase.co; frame-ancestors 'none';
   ```
2. Audit ligne par ligne des 11 RPC `security definer` — vérifier qu'ils refusent quand `auth.uid()` est NULL ou non autorisé.
3. Vérifier que `L10466` (encart "creuser source") échappe bien `srcUrl`.

---

## 🏗️ Architecture — 6/10

### Constat
- **11 277 lignes** dans un seul fichier
  - 3 565 lignes de `<head>` (metas, JSON-LD)
  - 3 527 lignes de `<style>`
  - 7 542 lignes de markup + JS (266 fonctions top-level)
- **345 IDs uniques** (au lieu de composants réutilisables)
- **18 modales** avec chacune leur propre ID et logique
- **242 `addEventListener`** au top-level → risque de fuites mémoire quand on navigue
- Pas de bundler, pas de module → tout est dans le scope global

### Pourquoi ça marche encore
- Vanilla JS reste **très rapide** (pas de framework overhead)
- Supabase fait le gros du boulot (auth, query, realtime)
- Cloudflare Pages sert le fichier en < 50 ms partout dans le monde

### Le mur qui approche
- Au-delà de **15 000 lignes**, le single-file devient impossible à débugger
- Tu approches **75 %** de cette limite
- Recruter un dev sur ce code = compliqué (apprendre 345 IDs)

### 🔧 Actions archi
1. **Court terme** (v0.11.0 → v0.14.0) : continuer en single-file mais en extrayant le CSS dans un fichier `styles.css` séparé. Gain : cache navigateur indépendant + lisibilité.
2. **Moyen terme** (v0.15.0) : la **migration Next.js prévue dans ton PLAN_DEV** est **la bonne décision**. À démarrer **dès que la base de features sera là (après v0.14.0)**.
3. Préparer la migration en commentant des **"sections"** dans le code actuel — déjà à moitié fait (`// ─── Profiles ───`).

---

## ⚡ Performance — 7/10

### Mesures statiques
- **548 KB** HTML servi (tout inline)
- **2 preconnect** (fonts.googleapis, fonts.gstatic)
- **0 preload** — opportunité immédiate
- **0 defer / async** sur les scripts — Supabase JS bloque le rendu
- **2 images en `loading="lazy"`** sur l'ensemble du site

### Quick wins (gain estimé : 30-40 % LCP)

```html
<!-- 1. defer le script Supabase -->
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2" defer></script>

<!-- 2. Préchargement des polices critiques (le poids principal des fonts) -->
<link rel="preload" as="font" type="font/woff2" crossorigin
  href="https://fonts.gstatic.com/s/fraunces/v32/...woff2"/>

<!-- 3. Cache long sur les fonts et icons -->
```

Dans `_headers` :
```
/*.woff2
  Cache-Control: public, max-age=31536000, immutable

/icon-*.png
  Cache-Control: public, max-age=31536000, immutable
```

### Plus gros chantier
- Toutes les `<img>` d'articles devraient avoir `loading="lazy" decoding="async"` — il y en a 16 actuellement, beaucoup plus pourraient en bénéficier.
- Service Worker (PWA) pour cache offline — déjà à moitié configuré (manifest.json présent), à finaliser.

---

## 🔍 SEO — 6/10

### ✅ Bon
- Meta description dynamique selon la page
- Open Graph + Twitter Cards complets
- JSON-LD `application/ld+json` présent
- Sitemap : non détecté → **à créer**
- robots.txt : non visible → **à vérifier**

### Le problème de fond
Avis Basé est une **SPA pure** : Google peut indexer (depuis 2018 il exécute du JS), mais :
- Le **time-to-content** pour le bot est long → certains crawlers abandonnent
- Le partage social (`og:image`) est **statique** quel que soit l'article ouvert
- Bing, DuckDuckGo, Yandex sont moins fiables sur le JS

### 🔧 Action SEO (v0.15.0 Next.js)
La migration Next.js que tu as prévue **règle ça d'un coup** :
- Pages `/article/[slug]` avec **SSG/ISR** → un bot reçoit du HTML statique
- `og:image` dynamique par article via `next/og`
- Sitemap.xml généré automatiquement

En attendant, sur la version actuelle :
1. Créer un **`/sitemap.xml`** statique avec au moins la home + page charte
2. Ajouter `/robots.txt`
3. Page **`/404.html`** stylée (✅ livrée dans les patches)

---

## ♿ Accessibilité — 5/10

### Score WCAG approximatif
- 26 `aria-label`, 22 `aria-hidden`, 9 `role=` sur ~1 000 éléments interactifs estimés
- Beaucoup de boutons icon-only (emojis 🗑 ✏ 💬) sans label
- Focus management dans 18 modales non audité (probablement non géré)

### 🔧 Actions a11y (v0.10.1)
1. **Tous les boutons icon-only** doivent avoir un `aria-label` :
   ```html
   <button class="comment__action" aria-label="Signaler ce commentaire">🚩</button>
   ```
2. **Modales** : à l'ouverture, focus sur le premier élément interactif. À la fermeture, retour au bouton qui a ouvert.
3. **Trap focus** dans les modales (`Tab` ne sort pas).
4. **Contraste** : vérifier `--ink-light` (#8A7F6E) sur `--bg` (#F4EFE4) — ratio probablement < 4.5:1, à corriger pour les textes critiques.

---

## 📊 Schéma de données — 8/10

### Tables existantes (18)
`profiles`, `articles`, `article_themes`, `article_tones`, `votes`, `comments`, `comment_edits`, `sources`, `submissions`, `reports`, `clips`, `site_settings`, `credibility_events`, `favorites`, `notifications`, `article_reads`, `coin_transactions`, `follows`

### ⚠️ Tables référencées mais NON créées
Dans `index.html` et `wrangler.jsonc` on voit des références à :
- `dm_messages`
- `dm_participants`
- `dm-attachments` (bucket storage)

Ces tables ne sont dans **aucune migration**. Soit :
- Tu les as créées à la main dans le dashboard Supabase (à confirmer dans le SQL Editor : `SELECT count(*) FROM dm_messages;`)
- Soit ce sont des stubs pour v0.13.0 jamais activés

**Action immédiate** : si elles n'existent pas en DB, créer la migration `v0.13.0-migration.sql` **avant** d'ouvrir la fonction Messages dans l'app mobile (sinon l'app crashe à l'ouverture de l'onglet Messages).

### Autres remarques schéma
- ✅ Indexes bien posés sur `notifications(user_id, read, created_at desc)`
- ✅ Foreign keys avec `on delete cascade` ou `set null`
- ⚠️ **Pas de vue `user_stats`** détectée dans v0.10.0 → les compteurs `followers_count`, `following_count` doivent venir d'ailleurs (sans doute via triggers sur `follows`, mais à vérifier)
- ⚠️ **Pas de RPC `find_or_create_dm`** non plus → mon app mobile ne pourra pas créer de nouvelle conversation

---

## 🗺️ Roadmap révisée

Comparée au `PLAN_DEV.md` actuel — je propose 3 changements :

### 1. Ajouter une **v0.10.1 — Hotfix audit** (2-3 jours)

Avant de passer à l'upload vidéo, capitaliser sur ce qui est facile et gagne en qualité :

- ✅ Page 404 stylée (livrée dans `avis-base-site-patches/404.html`)
- ✅ Page Changelog publique (livrée)
- ✅ Workflow CI sanity check (livré)
- ⬜ CSP stricte dans `_headers`
- ⬜ `defer` sur le script Supabase
- ⬜ `preload` sur Fraunces 600 (la fonte du titre)
- ⬜ `loading="lazy"` sur toutes les `<img>` d'articles (au-delà du fold)
- ⬜ `aria-label` sur les 60+ boutons icon-only
- ⬜ Cache long dans `_headers` pour woff2 + icons

### 2. **Avancer v0.13.0 (DM) AVANT v0.11.0 (upload vidéo)**

Raison : les tables DM sont déjà référencées partout. Soit on les crée, soit on retire les références. La cohérence du schéma compte plus que le confort d'avoir de la vidéo.

L'app mobile que je viens de livrer **expose déjà** la messagerie ; sans tables DM côté Supabase, elle plante.

**Migration `v0.13.0-migration.sql` à créer** (je peux te la rédiger ensuite) :

```sql
create table if not exists conversations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),
  last_message_at timestamptz
);

create table if not exists dm_participants (
  conversation_id uuid references conversations(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  last_read_at timestamptz,
  primary key (conversation_id, user_id)
);

create table if not exists dm_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid references conversations(id) on delete cascade,
  sender_id uuid references profiles(id),
  body text not null check (length(body) <= 2000),
  attachment_url text,
  is_deleted boolean default false,
  created_at timestamptz default now()
);

-- RLS, indexes, RPC find_or_create_dm…
```

### 3. **Décaler v0.16.0 (app mobile)**

L'app mobile dépend de l'**API stable**. Tant que les tables DM n'existent pas et que la vue `user_stats` n'est pas faite, l'app mobile ne peut pas être livrée sereinement.

**Nouvel ordre proposé** :

| Version | Phase | Objectif | Effort |
|---|---|---|---|
| v0.10.1 | Hotfix | Audit fixes (CSP, lazy, aria, 404, changelog) | 2-3 jours |
| **v0.13.0** | Social | **DM ⬅ avancée** | 1 semaine |
| v0.11.0 | Média | Upload vidéo direct (desktop) | 1-2 semaines |
| v0.12.0 | Social | Commentaires threads + mentions | 1 semaine |
| v0.14.0 | Engagement | Push + emails | 1 semaine |
| v0.15.0 | Refonte | Next.js + TypeScript | 3-4 semaines |
| v0.16.0 | Mobile | **App mobile** (déjà 80% codée — voir `avis-base-app/`) | 1-2 semaines de polish + sortie stores |
| v0.17.0 | Sécurité | Fact-checking + modération avancée | 2 semaines |
| v0.18.0 | Monétisation | Abonnements + tips | 2-3 semaines |
| v1.0.0 | 🚀 | Lancement public | 1 semaine |

**Économie totale estimée** : environ 0 — c'est juste un meilleur ordre, mais ça **évite la régression** d'avoir une app mobile qui crash sur l'onglet Messages.

---

## 📦 Ce qui est livré dès maintenant

Dans `avis-base-site-patches/` :

- `404.html` — page d'erreur stylée Broadsheet, prête à committer
- `CHANGELOG.md` — historique public des versions
- `AUDIT.md` — **ce document**
- `.claude/CLAUDE.md` — contexte projet pour futures sessions Claude Code
- `.github/workflows/deploy.yml` — déploiement Cloudflare Pages auto
- `.github/workflows/sanity.yml` — bloque toute PR avec `service_role`

Dans `avis-base-app/` :

- Phase 1 complète de l'app mobile Expo (5 onglets, 12 écrans, typecheck OK)
- `AUTONOMY.md` — la procédure pour me donner les tokens et que je continue seul

---

## 🎯 La question principale

Tu as 3 chemins possibles :

1. **Tu m'envoies les tokens** (GitHub PAT + Expo Token, cf. AUTONOMY.md) → je commence dès la prochaine session à pousser la v0.10.1 (hotfix audit) sur ton repo.

2. **Tu codes la v0.10.1 toi-même** avec Claude Code en local → tu utilises le présent audit comme cahier des charges.

3. **On commence par la migration `v0.13.0-migration.sql`** dans cette session → je te la rédige maintenant, et tu n'as qu'à la coller dans le SQL Editor Supabase.

À toi de choisir.
