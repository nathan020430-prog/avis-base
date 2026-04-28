# 📘 Plan de Développement — Avis Basé

> **Le média collaboratif qui source tout** — @avis_base.nth
>
> Ce document contient la roadmap complète et les prompts prêts à utiliser avec Claude Code pour chaque version.

---

## 🎯 Vision globale

Devenir **la référence du média collaboratif sourcé** : un mélange entre X (texte/liens), Instagram (visuel), et Wikipedia (vérification des sources), avec une communauté qui vérifie chaque info. Le but etant de proposée une alternative au format cour tout en essayer d'attirer les gens depuis ces platforme. donner des explication sur ce qui ce passe dans le monde basée sur des source les plus sur possible. Casser le mode de consomation surtout des jeune et essayer de les faire reflechire ou de leur donner les outils pour qu'il puisse le faiure part eu meme. trouvez un moyer de s'inspirer des platformes les plus utiliée pour d'etournée leur clients vers la notre. le but n'est pas de remplacée ces platforme mais de s'en servire pour attirée du monde sur la notre.  

---

## 📊 État actuel — v0.8.3.2

✅ **Déjà fait :**
- Authentification Supabase
- Articles avec éditeur markdown
- Clips vidéo (éditeur avec sous-titres, hashtags)
- Recherche avec suggestions
- Mode sombre/clair
- Rôles (user, admin, super-admin)
- Sources citées
- Likes/dislikes, pagination, filtres
- Brouillons sauvegardés
- Single-file HTML (~7700 lignes)

⚠️ **Limitations actuelles :**
- Mobile en lecture seule (à faire évoluer en "lecture + interactions")
- Pas de fil personnalisé (pas de follow)
- Pas de notifications
- Pas de messagerie
- Pas d'upload vidéo direct (juste éditeur de clips)

## 🎯 Choix éditoriaux structurants

> **L'écriture d'articles et l'édition de clips restent DESKTOP UNIQUEMENT.**
>
> C'est un choix volontaire et différenciant :
> - Garantit la qualité rédactionnelle
> - Encourage des articles plus structurés et mieux sourcés
> - Filtre les contenus impulsifs
> - Slogan possible : *"Sur Avis Basé, on n'écrit pas en attendant le bus. On prend le temps."*
>
> Le mobile est dédié à la **lecture, au débat et aux interactions** (likes, commentaires, follow).

---

## 🗺️ Roadmap globale

> **🎯 Philosophie de lancement** : Pas de com publique tant que le produit n'est pas **complètement fini**.
> Tout le développement reste en `0.x.x` (pré-release). La **v1.0.0 = lancement public final**, à la toute fin.
> Pendant la phase 0.x.x, le site est accessible sur `avis-base.com` mais en **soft-launch** : on construit, on itère avec quelques beta-testeurs, on ne fait **pas de com**.

| Version | Phase | Objectif | Durée estimée |
|---------|-------|----------|---------------|
| **v0.9.0** | Stabilisation | Mobile interactif (lecture + social) — **écriture reste desktop** | 1 semaine |
| **v0.9.1** | Stabilisation | Notifications in-app basiques | 3-5 jours |
| **v0.10.0** | Social | Système de follow + fil personnalisé | 1-2 semaines |
| **v0.11.0** | Média | Upload vidéo direct (desktop) | 1-2 semaines |
| **v0.12.0** | Social | Commentaires améliorés (threads) | 1 semaine |
| **v0.13.0** | Communication | Messages privés (DM) — mobile + desktop | 2 semaines |
| **v0.14.0** | Engagement | Notifications push + emails | 1 semaine |
| **v0.15.0** | 🏗️ Refonte | Architecture Next.js (préparer dev pro) | 3-4 semaines |
| **v0.16.0** | Mobile | App iOS + Android (lecture/interaction, pas d'écriture) | 4-6 semaines |
| **v0.17.0** | Sécurité | Modération avancée + anti-fake news | 2 semaines |
| **v0.18.0** | 💰 Monétisation | Abonnements + tips créateurs | 2-3 semaines |
| **v1.0.0** | 🚀 **LANCEMENT** | **Polish final + com publique + ouverture massive** | 1-2 semaines |

---

# 📝 Prompts par version

---

## 🔧 v0.9.0 — Mobile interactif (lecture + social) + Stabilisation

**Objectif :** Permettre les interactions sociales sur mobile (likes, commentaires, follow) **MAIS GARDER l'écriture d'articles et l'édition de clips uniquement sur desktop** — c'est un choix éditorial assumé.

### Ce qui reste **desktop uniquement** :
- ✍️ Écriture/édition d'articles (qualité rédactionnelle)
- 🎬 Édition de clips vidéo (interface complexe)

### Ce qui devient possible sur mobile :
- 👍 Likes / dislikes
- 💬 Commentaires (texte court, max 500 chars)
- 🔖 Sauvegarde d'articles
- 👤 Édition du profil (bio, avatar, lien social)
- 🔔 Gestion des notifications
- 🚩 Signalement de contenu
- ❤️ Suivre / ne plus suivre

### Prompt Claude Code :

```
Contexte : Je travaille sur "Avis Basé", plateforme single-file HTML
+ Supabase. Version actuelle : v0.8.3.2 (mobile read-only).

Choix éditorial IMPORTANT : L'écriture d'articles et l'édition de clips
restent DESKTOP UNIQUEMENT. C'est volontaire pour garantir la qualité
rédactionnelle et différencier Avis Basé des réseaux jetables.

Mission v0.9.0 : Permettre les interactions sociales sur mobile,
sans débloquer la création de contenu.

À DÉBLOQUER sur mobile :
1. Likes / dislikes sur articles, clips, commentaires
2. Écriture de commentaires (textarea simple, max 500 chars)
3. Édition du profil utilisateur :
   - Bio, photo de profil, lien social
   - PAS la création d'articles
4. Sauvegarde / mise en favoris
5. Suivre / ne plus suivre un utilisateur
6. Signalement de contenu

À GARDER bloqué sur mobile :
1. Bouton "Écrire un article" → masqué OU affiche un message :
   "✍️ La rédaction d'articles se fait sur ordinateur pour garantir
   la qualité. Retrouvez l'éditeur complet sur avisbase.fr"
2. Bouton "Créer un clip" → même chose :
   "🎬 L'éditeur de clips nécessite un écran plus large.
   Connectez-vous depuis un ordinateur."
3. Si un utilisateur a un brouillon en cours, afficher sur mobile :
   "📝 Vous avez un brouillon en cours sur ordinateur — terminez-le
   sur desktop"

Détails techniques :
- Détecter le mobile via media query CSS (max-width: 768px) ET via JS
  (window.innerWidth + 'ontouchstart' in window)
- Sur les boutons de création bloqués : afficher un message explicatif,
  PAS désactivé silencieusement (mauvaise UX)
- Ajouter un message d'incitation soft : "💻 Passez sur ordinateur pour
  publier votre article"

UX du blocage :
- Modal/toast élégant avec :
  - Icône desktop
  - Message explicatif court
  - Bouton "Compris" + "Pourquoi ?" (lien vers la charte éditoriale)
  - PAS culpabilisant, juste informatif

Adaptations mobile pour les interactions débloquées :
- Boutons tactiles min 44x44px
- Composer de commentaire : sticky en bas avec safe-area
- Édition profil : formulaire simple, pas d'upload complexe

Mise à jour version : v0.9.0
Mettre à jour le tag bêta : retirer "mobile read-only", remplacer par
"mobile lecture & interactions"

Avant de coder : montre-moi la liste des écrans/boutons à modifier
pour validation.
```

### Prompt complémentaire — Page Charte éditoriale

```
Mission complémentaire v0.9.0 : Page "Charte éditoriale".

Crée une page /charte (ou modal) qui explique :

1. Pourquoi Avis Basé existe
   - Lutter contre la désinformation
   - Tout sourcer, tout vérifier

2. Pourquoi l'écriture est desktop-only
   - "Un bon article demande de la concentration. Le format desktop
     pousse à mieux structurer ses idées et à vérifier ses sources."
   - "Le mobile est fait pour lire, débattre et s'informer. La rédaction
     mérite mieux."

3. Nos engagements
   - Toute affirmation = source
   - Modération communautaire transparente
   - Pas d'algorithme manipulateur

4. Ce qu'on attend des contributeurs
   - Sources fiables (médias reconnus, études, sites officiels)
   - Au moins 2 sources par affirmation factuelle
   - Pas de titres putaclic
   - Respect dans les débats

Design : sobre, lisible, dans le ton de la marque (Fraunces + Manrope).
Lien depuis le footer + depuis les modaux de blocage mobile.
```

### ✅ Critères de validation
- [ ] Sur mobile, je peux liker, commenter, suivre, modifier mon profil
- [ ] Sur mobile, le bouton "Écrire un article" affiche un message explicatif clair
- [ ] Sur mobile, le bouton "Créer un clip" affiche un message explicatif clair
- [ ] La page Charte éditoriale est accessible et bien rédigée
- [ ] Sur desktop, tout fonctionne comme avant
- [ ] Les utilisateurs comprennent le choix (pas de frustration)

---

## 🔔 v0.9.1 — Notifications in-app

**Objectif :** Notifier les utilisateurs des interactions (likes, commentaires, mentions).

### Prompt Claude Code :

```
Contexte : Avis Basé v0.9.0 fonctionne bien. Maintenant je veux ajouter
un système de notifications in-app (cloche en haut de l'écran).

Mission v0.9.1 : Système de notifications basique.

Côté Supabase (à faire en premier) :
1. Crée-moi le SQL pour une table "notifications" avec :
   - id (uuid, primary key)
   - user_id (uuid, qui reçoit la notif)
   - actor_id (uuid, qui a déclenché l'action)
   - type (text : 'like', 'comment', 'mention', 'follow', 'article_validated')
   - target_type (text : 'article', 'clip', 'comment')
   - target_id (uuid)
   - read (boolean, default false)
   - created_at (timestamptz)
2. Active Row Level Security (RLS) :
   - Un user peut voir ses propres notifs
   - Un user peut marquer ses notifs comme lues
3. Crée des triggers PostgreSQL pour générer les notifs auto :
   - Quand un like est ajouté → notif au propriétaire du contenu
   - Quand un commentaire est ajouté → notif au propriétaire
   - Quand un article est validé par un admin → notif à l'auteur

Côté frontend (index.html) :
1. Ajoute une icône cloche dans le header avec badge (nombre de non-lues)
2. Au clic : dropdown avec liste des 20 dernières notifs
3. Format de chaque notif : avatar + texte + temps relatif ("il y a 5min")
4. Au clic sur une notif : navigation vers le contenu + marquage comme lu
5. Polling toutes les 30s OU realtime Supabase (préférable)
6. Animation discrète quand nouvelle notif arrive

Mets à jour la version en v0.9.1.
Avant de coder, propose-moi le SQL et la structure UI pour validation.
```

### ✅ Critères de validation
- [ ] La cloche affiche le bon nombre de notifs non lues
- [ ] Les notifs apparaissent en temps réel
- [ ] Le clic sur une notif amène au bon contenu
- [ ] Les notifs sont marquées comme lues correctement

---

## 👥 v0.10.0 — Système de follow + fil personnalisé

**Objectif :** Transformer Avis Basé en vrai réseau social.

### Prompt Claude Code :

```
Contexte : Avis Basé v0.9.1 fonctionne (mobile interactif + notifs).
Maintenant je veux ajouter le cœur du réseau social : suivre des
utilisateurs et avoir un fil personnalisé.

Mission v0.10.0 : Système de follow + fil "Mon Feed".

Côté Supabase :
1. Crée la table "follows" :
   - follower_id (uuid)
   - following_id (uuid)
   - created_at (timestamptz)
   - PRIMARY KEY (follower_id, following_id)
2. Index sur les deux colonnes pour performance
3. RLS : un user peut suivre/unfollow, peut voir ses follows
4. Vue SQL "user_stats" :
   - followers_count
   - following_count
   - articles_count
   - clips_count
5. Trigger : créer une notif "follow" quand quelqu'un suit

Côté frontend :
1. Bouton "Suivre" / "Suivi" sur les profils utilisateurs
   - État chargé au mount, optimistic update au clic
2. Page profil enrichie :
   - Avatar + bio + bouton suivre
   - Stats : X abonnés, X abonnements, X articles
   - Onglets : Articles | Clips | Sources citées
3. Pages "Followers" et "Following" (modales ou pages)
4. Nouveau fil "Mon Feed" en plus de "Découvrir" :
   - Onglet en haut : "Mon Feed" / "Découvrir" / "Tendances"
   - Mon Feed = articles + clips des personnes suivies, par chrono inverse
   - Si aucun follow : suggestions à suivre
5. Suggestions d'utilisateurs à suivre :
   - Sur la page d'accueil
   - Basé sur : auteurs d'articles likés, sources fréquemment citées

Version : v0.10.0
Propose-moi le schéma et les écrans avant de coder.
```

### ✅ Critères de validation
- [ ] Je peux suivre/ne plus suivre un utilisateur
- [ ] Mon fil personnalisé affiche bien les posts des suivis
- [ ] Les compteurs de followers se mettent à jour
- [ ] Les suggestions sont pertinentes

---

## 🎥 v0.11.0 — Upload vidéo direct (desktop)

**Objectif :** Permettre l'upload de vidéos courtes (pas juste l'éditeur de clips). **Conformément au choix éditorial : l'upload se fait sur desktop uniquement.**

### Prompt Claude Code :

```
Contexte : Actuellement les clips se créent à partir de timestamps
(éditeur de plage). Je veux maintenant permettre l'upload direct
de vidéos courtes (60s max au début).

RAPPEL ÉDITORIAL : L'upload de vidéos se fait sur DESKTOP uniquement
(comme la rédaction d'articles et l'édition de clips). Sur mobile,
le bouton affiche le même message explicatif.

Mission v0.11.0 : Upload vidéo natif (desktop only).

Côté Supabase :
1. Configure le bucket "videos" dans Supabase Storage :
   - Public read
   - Authenticated upload uniquement
   - Limite 50 MB par fichier
2. Table "videos" :
   - id, author_id, title, description
   - storage_path (chemin dans le bucket)
   - thumbnail_path (généré côté client)
   - duration_seconds
   - width, height
   - hashtags (text[])
   - views_count, likes_count
   - status ('uploading', 'processing', 'published', 'rejected')
   - created_at
3. RLS classique (auteur modifie, tous lisent les publiées)

Côté frontend (desktop) :
1. Bouton "Publier une vidéo" dans le menu de création (caché sur mobile)
2. Composant d'upload :
   - Drag & drop ou clic pour choisir
   - Validation : durée max 60s, taille max 50 MB, formats mp4/mov/webm
   - Preview local avant upload
   - Sélection d'un thumbnail (capture d'une frame avec canvas)
   - Champs : titre (max 100), description (max 280), hashtags
3. Barre de progression d'upload
4. Compression côté client si possible (FFmpeg.wasm — optionnel, peut être lourd)

Côté frontend (mobile et desktop) :
5. Affichage des vidéos dans le feed :
   - Player custom : lecture auto au scroll (intersection observer),
     muet par défaut, son au tap, double-tap pour like
   - Disponible en lecture sur tous les supports

IMPORTANT :
- Stocker dans Supabase Storage est OK pour démarrer mais devient cher.
- Plan B : intégrer Cloudflare Stream plus tard pour scaler.

Version : v0.11.0
Avant : montre-moi le composant d'upload en wireframe + le SQL.
```

### ✅ Critères de validation
- [ ] Je peux uploader une vidéo depuis le desktop
- [ ] Sur mobile, le bouton d'upload affiche un message "Passez sur ordinateur"
- [ ] La vidéo s'affiche dans le feed mobile et desktop
- [ ] Le player fonctionne (auto-play muet, son au tap)
- [ ] Les vidéos refusées (>60s, >50MB) sont rejetées proprement

---

## 💬 v0.12.0 — Commentaires améliorés

**Objectif :** Système de commentaires avec threads (réponses imbriquées).

### Prompt Claude Code :

```
Contexte : Les commentaires actuels sont basiques. Je veux un vrai système
de discussion avec threads (comme Reddit en plus simple).

Mission v0.12.0 : Commentaires en threads + modération de base.

Côté Supabase :
1. Adapter (ou créer) la table "comments" :
   - id, target_type, target_id
   - author_id
   - parent_id (uuid, nullable — pour les réponses)
   - body (text, max 1000 chars)
   - likes_count
   - is_deleted (soft delete)
   - is_pinned (boolean, l'auteur du contenu peut épingler)
   - created_at, updated_at
2. RLS :
   - Lecture publique
   - Écriture si auth
   - Suppression : auteur du commentaire OU auteur du contenu OU admin
3. Compteur de commentaires sur les articles/clips/vidéos (trigger)

Côté frontend :
1. Section commentaires sous chaque contenu :
   - Tri : Top (par likes) / Récents / Anciens
   - Affichage en arbre (max 2 niveaux d'indentation)
2. Composer un commentaire :
   - @mentions avec autocomplétion
   - Markdown limité (gras, italique, lien, citation)
   - Preview avant envoi
3. Actions sur commentaire :
   - Like (compteur)
   - Répondre (ouvre un sous-composer)
   - Signaler (modal de raison)
   - Supprimer (si auteur/admin)
   - Épingler (si auteur du contenu)
4. Lazy loading : 10 commentaires top, "Voir plus" pour charger
5. Realtime : nouveau commentaire apparaît avec animation discrète

Version : v0.12.0
```

### ✅ Critères de validation
- [ ] Je peux commenter et répondre à un commentaire
- [ ] Les @mentions fonctionnent et notifient
- [ ] Le tri fonctionne
- [ ] Le signalement crée une entrée dans la modération

---

## 📩 v0.13.0 — Messages privés

**Objectif :** Permettre la messagerie 1-to-1 entre utilisateurs.

### Prompt Claude Code :

```
Contexte : Les utilisateurs veulent pouvoir se contacter en privé.

Mission v0.13.0 : Messagerie privée (DM).

Côté Supabase :
1. Table "conversations" :
   - id, created_at, last_message_at
2. Table "conversation_participants" :
   - conversation_id, user_id, last_read_at
   - PRIMARY KEY (conversation_id, user_id)
3. Table "messages" :
   - id, conversation_id, sender_id
   - body (text, max 2000)
   - is_deleted
   - created_at
4. RLS strict : seuls les participants peuvent lire/écrire
5. Vue "user_conversations" pour lister les conversations d'un user
   avec dernier message + non-lus

Côté frontend :
1. Icône messagerie dans le header (badge non-lus)
2. Page Messages :
   - Liste des conversations à gauche
   - Conversation active à droite (responsive)
   - Sur mobile : navigation type messenger
3. Conversation :
   - Bulles de message (gauche/droite)
   - Date + heure
   - Indicateur "lu" (✓✓)
   - Liens cliquables, mentions
4. Composer :
   - Textarea auto-resize
   - Envoi par Entrée (Maj+Entrée = retour ligne)
   - Envoi optimistic
5. Realtime Supabase pour réception instantanée
6. Bouton "Envoyer un message" sur les profils

Limites importantes pour éviter le spam :
- Un user ne peut DM que les comptes vérifiés OU ceux qu'il suit
- Un user qui ne suit pas peut envoyer 1 "demande de message" par jour
- Bouton "Bloquer" sur les profils

Version : v0.13.0
Présente-moi le schéma et les wireframes avant de coder.
```

### ✅ Critères de validation
- [ ] Je peux envoyer/recevoir des messages
- [ ] La messagerie est temps réel
- [ ] Le système anti-spam fonctionne
- [ ] Le blocage fonctionne

---

## 🔔 v0.14.0 — Notifications push + emails

**Objectif :** Garder les utilisateurs engagés même hors site.

### Prompt Claude Code :

```
Contexte : Les notifs in-app sont OK, mais je veux notifier hors-app.

Mission v0.14.0 : Notifications push (web) + emails.

Web Push :
1. Génère les clés VAPID (à stocker en variables Supabase)
2. Service Worker pour recevoir les push
3. Demande de permission au bon moment (pas au load !) :
   - Après 3 actions positives (like, follow, etc.)
   - Modal explicatif personnalisé avant la demande native
4. Table "push_subscriptions" :
   - user_id, endpoint, keys (jsonb)
5. Edge Function Supabase pour envoyer les push
6. Préférences : permettre à l'user de choisir quels types de notifs

Emails :
1. Intégration Resend ou Supabase Email :
   - Email de bienvenue (avec checklist d'onboarding)
   - Email de récap hebdo (top articles + nouveaux abonnés)
   - Email de notif importante (mention par admin, article validé)
2. Templates HTML responsive (tester sur Litmus ou similaire)
3. Page "Préférences email" pour désabonner par catégorie
4. Footer email avec unsubscribe (obligatoire RGPD)

Préférences notifs (page dédiée) :
- Toggle par type : likes, commentaires, follows, mentions, validations
- Toggle par canal : in-app, push, email
- Mode "Ne pas déranger" (créneaux horaires)

Version : v0.14.0
```

### ✅ Critères de validation
- [ ] Je reçois une notif push quand quelqu'un me suit
- [ ] Je reçois l'email de bienvenue
- [ ] Le récap hebdo arrive le lundi matin
- [ ] Je peux me désabonner facilement

---

## 🏗️ v0.15.0 — Refonte architecture (préparation dev pro)

**Objectif :** Passer du single-file HTML à une vraie app moderne, prête pour un dev professionnel.

### Prompt Claude Code :

```
Contexte : J'ai validé le concept avec mon MVP single-file. Maintenant
je veux migrer vers une architecture pro pour pouvoir embaucher un dev.

Mission v0.15.0 : Refonte complète en Next.js 14 + TypeScript.

Stack cible :
- Next.js 14 (App Router)
- TypeScript strict
- Tailwind CSS (avec mes couleurs actuelles)
- shadcn/ui pour les composants
- Supabase (garde le même backend)
- Zustand pour le state global
- TanStack Query pour les données
- Zod pour la validation

Structure du projet :
/app
  /(public)         → pages publiques (article/[slug], profil/[user])
  /(auth)           → login, signup
  /(app)            → app authentifiée (feed, messages, notifications)
  /api              → routes API (webhooks, upload)
/components
  /ui               → composants shadcn
  /article          → ArticleCard, ArticleEditor, etc.
  /clip             → composants clips/vidéos
  /shared           → Header, Sidebar, Footer
/lib
  /supabase         → client (server + browser)
  /utils            → helpers
/hooks              → hooks réutilisables
/types              → types TypeScript globaux

Étapes :
1. Setup projet Next.js + dépendances + ESLint/Prettier
2. Configuration Tailwind avec les variables CSS actuelles
3. Migration de l'authentification
4. Migration page d'accueil / feed
5. Migration article : lecture, édition
6. Migration clips/vidéos
7. Migration profils + follows
8. Migration messagerie
9. Migration notifications
10. Tests unitaires des composants critiques (Vitest)
11. Documentation (README + ARCHITECTURE.md)
12. Déploiement Vercel + variables d'env

⚠️ IMPORTANT : Tu vas tout reprendre fonction par fonction depuis l'ancien
index.html. Pour chaque feature, montre-moi avant la structure des fichiers
et le code, puis je valide.

Version : v0.15.0
Commence par la phase 1 (setup) et confirme avec moi à chaque étape.
```

### ✅ Critères de validation
- [ ] Toutes les features de v0.14.0 fonctionnent en v0.15.0
- [ ] Le code est propre, typé, testé
- [ ] Un dev pro peut comprendre l'architecture en 30 min
- [ ] Le déploiement Vercel est automatique depuis GitHub

> 💡 **C'est à ce moment qu'embaucher un dev devient pertinent.**
> Ils peuvent prendre le relais à partir de cette base solide.

---

## 📱 v0.16.0 — App mobile native (lecture + interactions)

**Objectif :** Apps iOS et Android avec une seule base de code. **Cohérent avec le choix éditorial : pas de création d'articles ni d'upload vidéo dans l'app mobile.**

### Prompt Claude Code :

```
Contexte : Le site web Next.js v0.15.0 fonctionne bien. Je veux maintenant
des apps mobiles natives.

RAPPEL ÉDITORIAL : Comme sur le mobile web, l'app native ne permet PAS :
- L'écriture d'articles
- L'édition de clips
- L'upload de vidéos
Ces actions restent desktop only. L'app mobile est focalisée sur :
LECTURE + INTERACTIONS SOCIALES + MESSAGERIE.

Mission v0.16.0 : App mobile en Expo (React Native).

Stack :
- Expo SDK (le plus récent)
- TypeScript
- Expo Router (navigation file-based)
- NativeWind (Tailwind pour RN)
- Supabase JS (même backend)
- Expo Notifications pour les push natives
- Expo Image, Expo Video pour les médias

Structure :
/app
  /(tabs)
    index.tsx           → Mon Feed
    explore.tsx         → Découvrir
    notifications.tsx
    messages.tsx
    profile.tsx
  /article/[id].tsx     → Lecture article
  /clip/[id].tsx        → Lecture clip/vidéo
  /user/[username].tsx  → Profil utilisateur
/components             → Composants partagés
/lib                    → Logique métier

Fonctionnalités INCLUSES dans l'app :
1. Authentification (Apple Sign In + Google + Email)
2. Feed avec pull-to-refresh + infinite scroll
3. Lecture d'articles confortable (mode lecture, taille texte ajustable)
4. Player vidéo natif (gestures TikTok-like : swipe, double-tap like)
5. Likes, commentaires, signalement
6. Système de follow / unfollow
7. Édition profil (bio, avatar, lien)
8. Messagerie privée (DM)
9. Notifications push (APNs + FCM)
10. Deep linking (avisbase://article/123)
11. Sauvegarde / favoris
12. Partage natif vers autres apps

Fonctionnalités EXCLUES de l'app (renvoyer vers desktop) :
- Bouton "Écrire un article" → redirection avec message :
  "✍️ Pour rédiger un article, rendez-vous sur avisbase.fr depuis
   un ordinateur. Cela garantit la qualité que mérite votre travail."
- Édition de clips
- Upload de vidéos

Cohérence cross-platform :
- Le même utilisateur retrouve ses brouillons sur desktop quand il s'y
  reconnecte
- Les notifications push fonctionnent même app fermée
- L'état "lu/non-lu" se synchronise entre web et app

Étapes :
1. Setup Expo + ergonomie iOS/Android
2. Authentification (Apple Sign In + Google + Email)
3. Feed avec pull-to-refresh + infinite scroll
4. Lecteur d'articles confortable
5. Player vidéo natif
6. Système d'interactions (likes, commentaires, follow)
7. Édition profil basique
8. Messagerie native
9. Notifications push (APNs + FCM)
10. Deep linking
11. Tests sur device réel iOS et Android
12. Préparation des stores :
    - App Store : screenshots, description, mots-clés, privacy policy
    - Google Play : pareil
    - Compte développeur (99$/an Apple, 25$ unique Google)

Version : v0.16.0
Phase 1 d'abord et on valide.
```

### ✅ Critères de validation
- [ ] L'app fonctionne sur iPhone réel
- [ ] L'app fonctionne sur Android réel
- [ ] Les notifications push arrivent
- [ ] Les actions de création renvoient bien vers le desktop
- [ ] L'app est soumise aux stores

---

## 🛡️ v0.17.0 — Modération avancée

**Objectif :** Lutter contre les abus et la désinformation (cohérent avec votre concept "sourcer tout").

### Prompt Claude Code :

```
Contexte : Avec la croissance, j'ai besoin d'outils de modération solides.
Le concept d'Avis Basé est de sourcer tout, donc la modération doit
être exemplaire.

Mission v0.17.0 : Système de modération communautaire + anti-fake news.

Backend :
1. Table "reports" (signalements) :
   - reporter_id, target_type, target_id, reason, details, status
2. Table "moderation_actions" :
   - moderator_id, action ('hide', 'delete', 'warn', 'ban'), target, reason
3. Table "fact_checks" :
   - article_id, fact_checker_id, verdict ('true', 'partially_true', 'false', 'misleading')
   - sources (jsonb)
   - explanation
4. Système de score de confiance utilisateur :
   - Augmente avec contributions validées, sources fiables
   - Diminue avec signalements confirmés
5. Edge Function : analyse auto avec IA des nouveaux articles
   - Détection de patterns suspects (titres putaclic, sources manquantes)
   - Score de confiance auto

Frontend :
1. Bouton "Signaler" sur tout contenu (modal avec raisons)
2. Dashboard modération (admins) :
   - File d'attente des signalements
   - Historique des actions
   - Stats par modérateur
3. Affichage public des fact-checks sur les articles :
   - Badge ✅ Vérifié / ⚠️ Trompeur / ❌ Faux
   - Lien vers explication détaillée
   - Sources de la vérification
4. Page de transparence publique :
   - Nombre de contenus vérifiés
   - Statistiques de modération
   - Charte de modération

Modération communautaire :
- Les users avec score >X peuvent voter sur les fact-checks
- Système jury pour les cas litigieux
- Tutoriel/formation pour devenir fact-checker

Version : v0.17.0
```

### ✅ Critères de validation
- [ ] Je peux signaler un contenu
- [ ] Les modérateurs ont un dashboard efficace
- [ ] Les fact-checks sont visibles publiquement
- [ ] La page transparence est accessible

---

## 💰 v0.18.0 — Monétisation

**Objectif :** Rendre la plateforme viable financièrement de façon éthique.

### Prompt Claude Code :

```
Contexte : Avis Basé a une communauté active. Il est temps de monétiser
de façon éthique (pas de pub intrusive, alignée avec les valeurs).

Mission v0.18.0 : Modèle économique multi-source.

Modèle :

A) Abonnement Avis Basé+ (5-7€/mois)
   - Pas de pub
   - Badge "Soutien" sur le profil
   - Accès anticipé aux nouveautés
   - Statistiques détaillées sur ses contenus
   - Couleur de profil personnalisée
   - Modes thèmes exclusifs

B) Tips créateurs
   - Les lecteurs peuvent envoyer 1€, 5€, 10€ aux auteurs
   - Avis Basé prend 5% (vs 30% des plateformes US)
   - Paiement Stripe Connect
   - Page "Top Contributeurs" mensuelle

C) Sponsoring d'articles éthiques
   - Marques peuvent sponsoriser des articles d'investigation
   - Marqué clairement "Sponsorisé" + transparence totale
   - Sources et fact-checking obligatoires

D) Don ponctuel
   - Bouton "Soutenir Avis Basé" en pied de page
   - Don libre

Implémentation :
1. Setup Stripe + Stripe Connect
2. Table "subscriptions" + webhooks Stripe
3. Système de gating des features premium
4. Composant "Tip jar" sur articles/clips
5. Onboarding créateurs pour Stripe Connect
6. Page transparence financière (mensuelle, depuis le début)

⚠️ RGPD : intégration soignée des CGV, CGU, mentions de paiement.
⚠️ Comptabilité : prévoir un comptable dès la première facture.

Version : v0.18.0
```

### ✅ Critères de validation
- [ ] Je peux m'abonner et accéder aux features premium
- [ ] Je peux envoyer un tip à un créateur
- [ ] Le créateur reçoit ses tips moins commission
- [ ] La page transparence est publique

---

## 🚀 v1.0.0 — LANCEMENT PUBLIC (étape finale)

> **🎯 Cette version arrive UNIQUEMENT quand TOUT le reste est fini.**
> C'est le moment où on retire le tag "beta", où on lance la com publique
> (TikTok, presse, réseaux), et où on ouvre les inscriptions massives.
>
> **Avant la v1.0.0** : `avis-base.com` est en soft-launch — accessible mais
> sans com active. On itère avec quelques beta-testeurs pour fiabiliser tout.
>
> **🚨 NE PAS faire de communication publique avant cette version.**
> Le produit doit être 100% prêt : stable, performant, beau, complet.

**Objectif :** Lancer publiquement Avis Basé avec un produit fini, polish maximal, prêt à accueillir des milliers d'utilisateurs.

### Pré-requis (à valider avant de coder la v1.0.0)

Toutes les versions précédentes doivent être livrées et stables :
- [x] v0.8.3.2 — Mobile read-only ✅
- [ ] v0.9.0 — Mobile interactif (lecture + social)
- [ ] v0.9.1 — Notifications in-app
- [ ] v0.10.0 — Follow + fil personnalisé
- [ ] v0.11.0 — Upload vidéo direct
- [ ] v0.12.0 — Commentaires en threads
- [ ] v0.13.0 — Messages privés
- [ ] v0.14.0 — Notifications push + emails
- [ ] v0.15.0 — Refonte Next.js
- [ ] v0.16.0 — App mobile native iOS/Android
- [ ] v0.17.0 — Modération avancée + fact-checking
- [ ] v0.18.0 — Monétisation (abonnements + tips)

**Tant qu'une de ces cases est décochée, on ne lance pas v1.0.0.**

### Prompt Claude Code :

```
Contexte : Toutes les versions 0.x.x sont livrées et stables. Avis Basé
est prêt techniquement (web + mobile + monétisation). Le moment du
lancement public est venu.

Mission v1.0.0 : Polish final + retrait du tag beta + préparation com.

Ce qui est DÉJÀ fait (à NE PAS refaire) :
- Hébergement Cloudflare Pages ✅
- Domaine avis-base.com ✅
- HTTPS automatique ✅
- Configuration Supabase prod ✅

À faire pour v1.0.0 :

1. Retrait du tag "beta"
   - Suppression de la beta-tag dans le header
   - Console.log : "Avis Basé v1.0.0 - Le média collaboratif qui source tout"
   - Mise à jour du footer (retire "Beta")
   - Mise à jour du README

2. SEO et métadonnées sociales (audit complet)
   - Open Graph tags vérifiés sur chaque page (og:title, og:description,
     og:image, og:url, og:type)
   - Twitter Card tags
   - Schema.org JSON-LD pour les articles (type Article + author + sources)
   - Sitemap.xml dynamique
   - robots.txt
   - Favicon multi-format (32, 192, 512px) + apple-touch-icon
   - Metas description optimisées par page

3. Pages légales obligatoires (RGPD)
   - Mentions légales (éditeur, hébergeur, contact, directeur publication)
   - Politique de confidentialité (cookies, données collectées,
     droits d'accès/suppression)
   - CGU (Conditions Générales d'Utilisation)
   - CGV si abonnements payants
   - Charte éditoriale publique
   - Charte de modération publique
   - Bandeau cookies conforme RGPD

4. Performance (Lighthouse cible >95 sur tout)
   - Audit Lighthouse complet → corriger tous les warnings
   - Compression images (WebP, lazy loading)
   - Préconnexion aux domaines externes
   - Service Worker pour cache offline + PWA installable
   - Analyse du bundle, suppression du code mort
   - Tests sur connexion lente (3G simulé)

5. Onboarding nouveau user
   - Tour guidé en 4-5 étapes au premier login
   - Suggestion : suivre 5 articles populaires + 3 contributeurs
   - Email de bienvenue détaillé (qu'est-ce qu'Avis Basé, comment contribuer)

6. Page 404 stylée + page erreur 500

7. Page "Changelog" publique
   - Historique des versions avec descriptions courtes
   - Lien depuis le footer

8. Page "À propos"
   - Histoire d'Avis Basé
   - Manifeste éditorial
   - L'équipe (même si solo : "Créé par X")

9. Page "Statistiques publiques"
   - Nombre d'articles, contributeurs, sources citées
   - Mise à jour temps réel
   - Crédibilité moyenne de la plateforme

10. Tests cross-browser
    - Chrome, Firefox, Safari, Edge
    - iOS Safari, Android Chrome
    - Tablette iPad/Android

Mise à jour version : v1.0.0
- Tag git : `git tag v1.0.0 && git push --tags`
- Annonce sur changelog public

Propose-moi le plan détaillé avant de commencer.
```

### Plan de communication (à préparer en parallèle)

À avoir prêt pour le **jour du lancement** :

1. **TikTok** (@avis_base.nth)
   - Vidéo de lancement avec démo du site
   - Série "Pourquoi j'ai créé Avis Basé"
   - Plan de contenu pour les 4 premières semaines

2. **Réseaux sociaux**
   - X (anciennement Twitter) : compte créé, bio + lien
   - Instagram : compte créé, lien en bio
   - LinkedIn : post de lancement (si tu en as un)

3. **Presse / Communauté**
   - Communiqué de presse (1 page) à envoyer à 10-20 médias
   - Post Reddit dans r/france, r/medias, r/journalisme
   - Hacker News (si version anglaise)
   - Product Hunt (le matin, ne pas oublier)

4. **Email**
   - Liste d'attente des beta-testeurs (à constituer pendant 0.x.x)
   - Email de lancement avec invitation

5. **Discord/Telegram**
   - Serveur communautaire ouvert au public

### ✅ Critères de validation v1.0.0
- [ ] Toutes les versions 0.x.x sont stables et déployées
- [ ] Les performances Lighthouse sont >95 sur Performance, Accessibility, Best Practices, SEO
- [ ] Aucune erreur console en production
- [ ] Toutes les pages légales sont en ligne et conformes RGPD
- [ ] Le site est testé sur 6+ navigateurs/appareils
- [ ] Le partage sur réseaux sociaux affiche un beau preview
- [ ] L'onboarding nouveau user est fluide et guidé
- [ ] La page 404 est stylée
- [ ] Le tag "beta" est retiré partout
- [ ] La com publique est planifiée et prête à être déclenchée
- [ ] Le tag git `v1.0.0` est poussé

---

# 🛠️ Bonnes pratiques pour tout le projet

## Avec Claude Code

**À chaque session, ouvrez avec ce prompt système :**
```
Tu travailles sur Avis Basé, un média collaboratif.
Stack : Single-file HTML + Supabase (jusqu'à v0.14.0), puis Next.js + Supabase à partir de v0.15.0.
Concept : tout doit être sourcé, vérifiable, transparent.
Le lancement public est en v1.0.0 (toute fin) — pas de com avant.

Avant de coder une feature :
1. Propose le plan détaillé
2. Liste les fichiers/tables affectés
3. Attends ma validation
Puis code par petites étapes vérifiables.
```

## Versionning

- Numérotation **semantic versioning** : MAJEUR.MINEUR.CORRECTIF
- Tag Git à chaque version : `git tag v0.9.0 && git push --tags`
- Changelog visible publiquement (page `/changelog`)

## Backups

- Supabase : activez les **Point-in-Time Recovery** dès que vous avez des users (plan payant nécessaire)
- Code : GitHub privé minimum (gratuit)
- Exports manuels mensuels de la DB

## Tests utilisateurs

- **Pendant la phase 0.x.x (soft-launch)** : recrutez 5-10 beta-testeurs proches
- Outil simple : groupe Discord ou Telegram privé
- Faites un appel vidéo de 20 min toutes les 2 semaines
- Notez TOUT ce qui les fait râler
- **À l'approche de v1.0.0** : étendez à 30-50 beta-testeurs externes
- C'est leur retour qui valide le go/no-go pour la com publique

## Quand passer à un dev pro

**Indicateurs que c'est le moment :**
- Vous avez ~500-1000 users actifs
- Vous touchez aux limites de Claude Code (bugs récurrents, code spaghetti)
- Vous voulez ajouter des features qui demandent de l'expertise (vidéo live, IA avancée, paiement)
- Vous avez des revenus pour payer (1 dev junior = 500-2000€/mois en freelance)

**Comment recruter :**
- Malt, Upwork, LinkedIn
- Préférez junior+ motivé que senior cher
- Test technique : "améliorez cette fonctionnalité d'Avis Basé"
- Démarrez par un sprint d'essai de 2 semaines

---

# 📞 Ressources utiles

| Besoin | Outil recommandé |
|--------|------------------|
| Hébergement web | Cloudflare Pages (gratuit) |
| Backend | Supabase (gratuit jusqu'à 50k users actifs) |
| Vidéos scaling | Cloudflare Stream (5$/mois pour 1000 min) |
| Emails | Resend (3000 emails/mois gratuit) |
| Analytics | Plausible (privacy-friendly) ou Umami (self-host gratuit) |
| Monitoring | Sentry (gratuit jusqu'à 5k events/mois) |
| Domaine | Namecheap, Gandi, OVH |
| Design | Figma (gratuit) |
| Recherche utilisateurs | Tally.so pour les formulaires |
| Communauté | Discord (gratuit) |

---

# 🎯 Checklist finale de lancement v1.0.0

> **À cocher avant de cliquer sur "Publier" sur TikTok le jour J.**

### Technique
- [x] Site déployé sur Cloudflare Pages (gratuit) ✅
- [x] Domaine `avis-base.com` configuré ✅
- [x] HTTPS activé ✅
- [x] Backend Supabase configuré pour `avis-base.com` ✅
- [ ] Toutes les versions v0.9.0 → v0.18.0 livrées et stables
- [ ] Lighthouse > 95 sur Performance, Accessibility, Best Practices, SEO
- [ ] Testé sur Chrome, Firefox, Safari, Edge (desktop)
- [ ] Testé sur iOS Safari + Android Chrome
- [ ] Testé sur tablette iPad/Android
- [ ] Aucune erreur console en production
- [ ] Backup Supabase activé (Point-in-Time Recovery)
- [ ] Sentry ou monitoring d'erreurs en place

### Légal & RGPD
- [ ] Mentions légales conformes (éditeur, hébergeur, contact)
- [ ] Politique de confidentialité publiée
- [ ] CGU publiées
- [ ] CGV publiées (si abonnements)
- [ ] Bandeau cookies conforme RGPD
- [ ] Page de désabonnement aux emails accessible
- [ ] Email de support actif (contact@avis-base.com)

### Contenu & UX
- [ ] Charte éditoriale publiée
- [ ] Charte de modération publiée
- [ ] Page À propos rédigée
- [ ] Page Changelog publique
- [ ] Page Statistiques publiques
- [ ] Page 404 stylée
- [ ] Tag "beta" retiré partout
- [ ] Onboarding nouveau user testé sur 5+ personnes
- [ ] Open Graph + Twitter Cards testés sur metatags.io
- [ ] Au moins 20 articles de qualité publiés pour le jour du lancement
- [ ] Au moins 5 clips vidéo publiés

### Communauté
- [ ] Discord/Telegram public ouvert
- [ ] 30-50 beta-testeurs ont validé l'expérience
- [ ] Liste d'attente d'inscriptions pré-lancement constituée

### Communication (à déclencher le jour J)
- [ ] Vidéo de lancement TikTok prête (@avis_base.nth)
- [ ] Plan éditorial TikTok pour les 4 premières semaines
- [ ] Comptes X / Instagram / LinkedIn créés et alimentés
- [ ] Communiqué de presse rédigé (1 page) — liste de 10-20 médias prêts
- [ ] Post Product Hunt préparé (planifier le matin du jour J)
- [ ] Post Reddit préparé (r/france, r/medias)
- [ ] Email de lancement à la liste d'attente prêt

### Tag final
- [ ] `git tag v1.0.0 && git push --tags`
- [ ] Annonce sur changelog public

---

**Bonne route avec Avis Basé ! 🚀**

*Document généré pour servir de feuille de route. Adaptez les versions selon vos retours utilisateurs réels — c'est eux qui doivent guider les priorités.*

*Philosophie : pas de com tant que ce n'est pas fini. Le soft-launch en 0.x.x permet d'itérer dans l'ombre. La v1.0.0 = grand feu d'artifice public.*
