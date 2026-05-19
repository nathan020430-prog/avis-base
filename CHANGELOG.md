# Changelog — Avis Basé

Historique public des versions. Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/).

## [Non publié]
- v0.11.0 — Upload vidéo direct (desktop)
- v0.16.0 — App mobile native iOS + Android (Expo)

## [v0.24.0] — Liste d'attente pré-lancement
- Nouvelle **table `waitlist`** : email (unique case-insensitive), kind (`launch` ou `beta`), source, name, user_id, ip_hash, timestamps
- Nouvelle **RPC publique `submit_waitlist(email, kind, source, name)`** ouverte à `anon` :
  - Validation regex email + longueur 5-254
  - Idempotente : si email déjà inscrit avec même kind → `{status: 'already'}`, avec kind différent → update + `{status: 'updated'}`, sinon insert + `{status: 'created'}`
- RLS : lecture admin/superadmin uniquement
- Vue `waitlist_summary` pour les agrégats (total, pending, notified par kind)
- Nouvelle **modale frontend `Waitlist`** : form en 2 champs (email + nom optionnel) + radio cards pour choisir `launch` (notif jour J) ou `beta` (rejoindre les beta-testeurs)
- États de succès distincts selon `created` / `updated` / `already`
- 2 entry points :
  - Home, section "App mobile" : « rejoindre les bêta-testeurs » + « être prévenu du lancement public »
  - Modale `/a-propos` : 2 entrées dédiées
- Anti-zoom iOS (font-size 16px), shake animation sur email invalide
- Migration : `v0.24.0-waitlist-migration.sql` (à appliquer après v0.22.1)

## [v0.23.3] — Auto-link sources [N] dans le corps d'article
- Les références numériques `[1]`, `[2]` etc. dans le corps d'un article deviennent désormais des **liens cliquables** qui smooth-scroll vers la source citée correspondante dans la section "Sources citées"
- Flash visuel de 1.7s sur la source cible pour attirer le regard
- Implémenté dans `renderArticleMarkdown` après les footnotes, avec garde anti-match sur les constructs comme `var[0]`
- Chaque source citée a maintenant un `id="cited-N"` pour servir de cible aux ancres
- Convention alignée sur celle de Wikipédia, parfaitement cohérente avec le concept éditorial du « média qui source tout »

## [v0.23.2] — Reprise de lecture mémorisée par article
- Module `ReadResume` qui mémorise la **position de scroll** (en %) par slug d'article dans `localStorage.avb_reading_positions_v1`
- À la réouverture d'un article : banner discret **"🔖 Tu en étais à X %. Reprendre ?"** au-dessus du contenu
- 2 boutons : `Recommencer` (purge l'entrée et recommence du début) et `Reprendre →` (scroll smooth à la bonne position)
- Save debounced (600ms après l'arrêt du scroll) pour éviter de spammer localStorage
- Ignore les positions extrêmes : < 5% (juste ouvert) et > 95% (quasi fini, pas la peine de mémoriser)
- Cleanup automatique des entrées > 30 jours, plafond de 100 entrées (les plus récentes gardées)

## [v0.23.1] — Citation partageable depuis l'article
- Sélectionner du texte dans la page article fait apparaître un **tooltip flottant** avec 3 actions :
  - 🐦 **Twitter** — ouvre intent/tweet avec `« citation »\n— @auteur, sur Avis Basé\n[url] via @avis_base.nth`
  - 📋 **Copier** — copie `« citation »\n— auteur\n[url]` dans le presse-papier
  - 📲 **Partage natif** (Web Share API) — masqué automatiquement si non supporté
- Filtres : longueur minimale 12 caractères, troncature à 280 (limite Twitter), ignore les sélections hors `.article-page__body`
- Tooltip se positionne intelligemment au-dessus de la sélection (ou en dessous si pas assez d'espace), avec une petite flèche pointant vers le texte
- Repositionnement automatique au scroll, hide intelligent (Esc / click ailleurs / désélection)
- Format `« » + attribution auteur + lien + via @avis_base.nth` pensé pour maximiser le partage organique sur les réseaux sociaux

## [v0.23.0] — UX lecture : prefs typo + temps restant + articles suggérés
- **Préférences typographiques** :
  - Bouton flottant `Aa` en haut à droite de la page article (visible en mode lecture)
  - Popover avec taille (S/M/L) et police (Serif Fraunces / Sans-serif Manrope)
  - Persistance dans `localStorage.avb_read_prefs_v1`, appliqué dès le chargement
  - Bouton "Réinitialiser" pour revenir aux valeurs par défaut
- **Temps de lecture restant** :
  - Badge `⏱ X min restantes` co-localisé avec le bouton Aa
  - Mise à jour à chaque scroll : `ceil(readingMinutes × (1 - pct))`
  - Passe à `✓ lu` (vert) à 98.5 % de progression
- **Articles suggérés en fin d'article** :
  - Section « 📰 Articles à découvrir » avec 3 cartes après le vote bar
  - Algorithme de scoring : `+5 même thème, +likes/10, +reads/100, -3 si déjà vu en session`
  - Tracking des articles vus via `sessionStorage.avb_seen_articles` (50 derniers)
  - Clic sur une carte → scroll top + ouverture du nouvel article (sans fermer la modale)

## [v0.22.1] — Finance — Top tippers publics
- Nouvelle RPC publique `get_public_top_tippers(p_limit, p_days)` : top des donateurs sur les N derniers jours, agrégés par username + somme + nombre + dernier tip. Filtre strict `tips.status='succeeded'` AND `display_consent=true`.
- Nouvelle section **"Top donateurs — 30 derniers jours"** sur `/financement`, entre le Mur des soutiens et les Articles rémunérés. Liste numérotée, 1er rang en couleur accent, empty state explicite si personne n'a opt-in.
- Section masquée si la migration n'est pas appliquée (silencieux, pas d'erreur visible).
- Confirmation : la page `/financement` est désormais 100 % alimentée par les vraies données live (les vues `public_economy_current`, `public_donor_wall`, `public_article_leaderboard`, `public_monthly_archive` étaient déjà branchées depuis v0.17.0).

## [v0.22.0] — Finance — Customer Portal Stripe + tips reçus
- Nouvelle Edge Function **`create-portal-session`** : crée une session Stripe Billing Portal pour le user authentifié et retourne l'URL. Le portail Stripe permet à l'user d'annuler son abonnement Avis Basé+, mettre à jour sa méthode de paiement, consulter ses factures.
- Nouvelle section **"💛 Mon adhésion Avis Basé+"** sur `/mon-financement` :
  - Statut affiché en chip coloré : Active / Annulation programmée / Impayé / Annulée / Inactive
  - Date de prochain renouvellement (ou date de fin si annulé)
  - Bouton **"⚙️ Gérer mon abonnement"** qui ouvre Stripe Portal en redirect
  - CTA "Devenir membre +" si pas membre, "Redevenir membre" si abonnement annulé
- Nouvelle sous-section **"🎁 Tips reçus en tant que contributeur"** (affichée si > 0 tips) :
  - Total cumulé + nombre de dons
  - Agrégation par mois sur les 12 derniers mois
  - Note de crédit sur la cagnotte au prochain calcul mensuel
- Fetch additionnel dans `MonFin.loadFromSupabase()` : la row complète de `members` + les `tips` agrégés (target_user_id OU target_article_id ∈ mes articles)
- Setup côté Stripe : activer le Customer Portal dans le Dashboard (Settings → Billing → Customer portal → Activate), pas de variable d'env supplémentaire à set. Pas de migration SQL pour cette version.

## [v0.21.1] — Polish RGPD + Changelog public
- Bandeau cookies/RGPD informatif sticky-bottom : explique qu'on utilise des cookies fonctionnels (auth Supabase) + localStorage pour le thème, l'onboarding et les brouillons, sans tracker publicitaire. Persistance via `localStorage.avb_rgpd_ack_v1`. Lien vers `/confidentialite.html`.
- Nouvelle modale **Changelog public** (hash `#changelog`) avec les 9 dernières releases v0.10 → v0.21.1, structurées par version + date + tag (Feature / Polish / Fix / Bundle). Liens internes vers À propos / Stats / Charte de modération / Financement.
- Footer enrichi à 5 liens : `À propos · Stats publiques · Changelog · Charte éditoriale · Charte de modération`.
- Lien depuis /a-propos vers le Changelog en un clic (alternative au lien GitHub déjà présent).
- Esc et clic backdrop ferment la modale changelog.

## [v0.21.0] — Polish pre-launch
- **Modération clips dans le dashboard mod** : la file mod affiche maintenant un bouton "👁 Voir article parent" pour les clips et "👁 Voir l'article" pour les commentaires (avec scroll + highlight). Les actions hide/unhide/dismiss/resolve fonctionnaient déjà côté RPC, c'est l'UI qui n'était branchée que pour les articles.
- **Audit SEO** :
  - `setArticleMeta()` génère désormais les meta `article:published_time`, `article:modified_time`, `article:author`, `article:section`
  - Injection dynamique d'un JSON-LD de type `NewsArticle` par article ouvert, avec headline, image, dates, auteur, publisher, mainEntityOfPage et citations (jusqu'à 20 sources)
  - `resetMeta()` nettoie tout ça quand on quitte un article
- **Onboarding nouveau user** :
  - Tour guidé en 5 étapes affiché au premier login (`localStorage.avb_onboarding_done_v1`)
  - Étapes : Bienvenue → Basitude (échelle 0-100, 4 paliers) → Mobile/desktop → Modération transparente → Suggestions à suivre (top 5 contributeurs, follow inline)
  - Barre de progression + boutons "Suivant / Précédent / Passer le tour"
  - Déclenchement sur `SIGNED_IN` (login + signup) ET au boot si profil chargé et flag absent
  - Relançable depuis console via `window.Onboarding.start()`
- **Audit perf (Lighthouse pre-launch)** :
  - `<link rel="preconnect">` : Supabase project URL, cdn.jsdelivr.net
  - `<link rel="dns-prefetch">` : i.ytimg.com, www.youtube.com, challenges.cloudflare.com
  - Supabase JS reste en chargement bloquant (`<script src>`) car il est utilisé par un inline script en body au boot. Chart.js et Turnstile sont en `defer` comme avant.
  - Meta `color-scheme: light dark` + `format-detection: telephone=no`

## [v0.20.0] — Transparence & Identité
- Nouvelle page **/a-propos** (modale, hash `#a-propos`) : manifeste éditorial, différenciateurs, "pourquoi desktop-only", équipe, liens externes (TikTok, GitHub, contact, beta-testeurs), pointeur vers le changelog public
- Nouvelle page **/stats** (modale, hash `#stats`) :
  - Grille de 6 cards principales : articles publiés (+ en revue), contributeurs (+ certifiés), sources citées (+ moyenne par article), commentaires, clips TikTok, basitude moyenne (+ record)
  - Section "Soutien Avis Basé+" si membres actifs
  - Section modération : signalements pending / validés / dismissed (avec %), contenus auto-masqués actifs, actions journalisées
  - Top 10 contributeurs (badges certified ✓ / member 💛 inclus)
- 4 liens propres dans le footer : `À propos · Stats publiques · Charte éditoriale · Charte de modération`
- Hash deep-link initial supporté : `avis-base.com/#a-propos` ou `#stats` ouvre directement la modale
- SQL : `v0.20.0-stats-migration.sql` — RPCs `get_public_stats()` (jsonb) et `get_public_top_contributors(limit)`, ouvertes à `anon` et `authenticated`. Tolérance migrations partielles via `begin/exception when undefined_table` autour des tables optionnelles.
- Compat : si la migration n'est pas appliquée, la page stats affiche un message clair au lieu de crasher.

## [v0.19.1] — Notifs modération + charte publique
- 2 nouveaux types de notif : `content_hidden` (ton article/clip a été masqué) et `content_restored` (de nouveau visible)
- Trigger PG `notify_on_moderation_change` sur `articles` et `clips` qui détecte les transitions `moderation_state` et insère la notif à l'auteur
- Module `Notif` côté frontend : libellés français + avatars système colorés + navigation au clic vers l'article/clip parent
- Bonus : navigation `target_type='profile'` fixée pour les notifs follow
- Nouvelle modale **Charte de modération** publique (8 sections : principe, signalement, masquage auto, peer review, action mod, conséquences crédibilité, recours, droit à l'oubli)
- Liens d'accès à la charte : footer (à côté de "Charte éditoriale"), bas de la modale de signalement, depuis la charte éditoriale, hash deep-link `#charte-moderation`
- SQL : `v0.19.1-moderation-notifs.sql` (idempotente, ASCII pur). À appliquer **après** `v0.19.0-moderation-migration.sql`. Sans elle, aucune erreur frontend mais les notifs de masquage ne se déclencheront pas.

## [v0.19.0] — Modération avancée + peer review
- Signalement enrichi : 8 raisons standardisées (désinformation, source douteuse, hors-sujet, spam, harcèlement, contenu illégal, droit d'auteur, autre) avec marquage automatique de sévérité (low/normal/high)
- Masquage automatique des contenus problématiques : seuil 3 signalements distincts OU 1 signalement de priorité haute (`hidden_auto`)
- Peer review communautaire : tout utilisateur avec un score de Basitude ≥ 50 peut voter sur les signalements ; quorum 3 votes décide (validé → contenu masqué + pénalité crédibilité auteur ; invalidé → restauration)
- Dashboard `/moderation` (modal) : tabs « File mod » (admin OU score ≥75) et « Peer review » (score ≥50)
- Actions modérateur : hide / unhide / dismiss_reports / resolve_reports avec journal `moderation_actions`
- Badges visuels « ⚠️ Masqué — revue en cours » sur les cartes article et la page article, visibles uniquement pour l'auteur et les modérateurs
- SQL : `v0.19.0-moderation-migration.sql` (idempotente, ASCII pur). Tables `moderation_actions` & `peer_reviews`, RPCs `submit_report`, `submit_peer_review`, `mod_apply_action`, `get_moderation_queue`, `get_peer_review_queue`, `get_user_moderation_summary`
- Compat : tant que la migration n'est pas appliquée, le frontend retombe sur l'INSERT direct dans `reports` (signalement v0.18 fonctionne toujours)

## [v0.18.1] — Hotfix race conditions tips / payouts
- Crédit de tip atomique + idempotent (RPC `credit_tip_to_contributor`)
- Réservation de payout sérialisée (RPC `reserve_payout` avec SELECT FOR UPDATE)
- Suppression de la policy UPDATE trop large sur `contributor_balance`
- RPCs réservées au `service_role` (Edge Functions Stripe)

## [v0.18.0] — Trust & Identity
- Phase 1 — Compte renforcé : captcha Turnstile + charte editorial + email confirm + min 8 chars + restriction écriture 7 jours
- Phase 2 — Certification « Auteur rémunérable » : 4 critères cumulatifs (3 articles + 30 jours + score ≥50 + KYC) avec roadmap personnelle
- Phase 3 — Crédibilité enrichie : badges multiples (⭐ Vétéran, 📝 Prolifique, ✓ Rémunérable, 💛 Membre+) + breakdown public + historique des scores

## [v0.17.1] — Banner CTA Avis Basé+
- Banner discret au-dessus du masthead, dismissible

## [v0.17.0] — Économie collaborative
- Page `/financement`, `/devenir-membre`, dashboard `/mon-financement`
- Tip jar inline sur les articles publiés
- SQL : 9 tables + 4 vues + 4 RPCs ; Edge Functions Stripe (Checkout, Webhook, Connect onboarding, request-payout, compute-monthly-payout)

## [v0.10.0] — Follow + Mon Feed
- Système de follow / unfollow
- Vue `user_stats` (followers, following, articles)
- Fil personnalisé "Mon Feed"
- Suggestions de contributeurs à suivre

## [v0.9.7] — Notifications in-app
- Cloche dans le masthead + badge non-lues
- Panel realtime (Supabase Realtime + polling fallback)
- Triggers Postgres pour likes, commentaires, publications

## [v0.9.6] — Mobile fluidity (paint + viewport)
## [v0.9.5] — Mobile fluidity (perf, tactile)
## [v0.9.4] — Pack animations
## [v0.9.0/Broadsheet] — Refonte direction artistique "Broadsheet"
## [v0.9.0] — Mobile interactif (lecture + social)
## [v0.8.3.2] — Mobile read-only + bottom nav
## [v0.8.3] — Détection mobile, blocage écriture
## [v0.8.2] — Pagination, compteurs
## [v0.8] — Économie de pièces, badges, crédibilité
## [v0.7.1] — Refonte top bar, design éditorial
## [v0.7] — Menu nav unifié

---

*Pendant la phase 0.x.x, le site est en soft-launch — pas de com publique avant v1.0.0.*
