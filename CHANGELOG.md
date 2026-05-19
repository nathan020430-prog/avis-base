# Changelog — Avis Basé

Historique public des versions. Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/).

## [Non publié]
- v0.11.0 — Upload vidéo direct (desktop)
- v0.16.0 — App mobile native iOS + Android (Expo)

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
