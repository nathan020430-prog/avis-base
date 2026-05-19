# Changelog — Avis Basé

Historique public des versions. Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/).

## [Non publié]
- v0.11.0 — Upload vidéo direct (desktop)
- v0.16.0 — App mobile native iOS + Android (Expo)

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
