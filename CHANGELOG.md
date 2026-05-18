# Changelog — Avis Basé

Historique public des versions. Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/).

## [Non publié]
- v0.11.0 — Upload vidéo direct (desktop)
- v0.16.0 — App mobile native iOS + Android (Expo)

## [v0.18.2] — Hotfix audit (RLS server-side + certif auto-revoke)
- Restriction écriture (7 jours + email confirmé) déplacée côté Postgres : helper `account_can_publish()` + policy INSERT `articles_insert_auth_and_aged`
- Edge Function `compute-monthly-payout` : frais Stripe lus depuis `balance_transactions` au lieu d'une estimation 5% hardcodée (fallback transparent si l'API échoue, flag `stripe_fees_estimated` dans la réponse)
- Trigger `trg_articles_recheck_certification` : révoque automatiquement la certif d'un auteur si son nombre d'articles publiés tombe sous 3

## [v0.18.1] — Hotfix race conditions money
- Crédit de tip atomique + idempotent (sentinelle `tips.credited_at`)
- request-payout verrouillé (`select ... for update`)
- Durcissement RLS `contributor_balance` (suppression UPDATE policy générique)

## [v0.18.0] — Trust & Identity
- Compte renforcé : captcha Turnstile, charte, email confirm, min 8 chars, restriction écriture 7 jours
- Certification "Auteur rémunérable" (4 critères cumulatifs + roadmap personnelle)
- Crédibilité enrichie : badges multiples + breakdown public + historique

## [v0.17.1] — Banner CTA Avis Basé+
- Banner CTA discret sur la home, dismissible

## [v0.17.0] — Économie collaborative
- Abonnement Avis Basé+ 5€/mois + tips créateurs + payouts via Stripe Connect
- Pages `/financement`, `/devenir-membre`, `/mon-financement`
- RPC `track_view` pour pool mensuel

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
