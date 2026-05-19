# Edge Functions — v0.17.0+ Économie collaborative

6 Edge Functions Deno + Stripe SDK pour câbler l'économie collaborative.
Skeletons fonctionnels — il manque uniquement la config Stripe pour les activer.

| Function | Rôle | Auth | Cron-callable |
|---|---|---|---|
| `create-checkout-session` | Crée une session Stripe Checkout (subscription 5€/mois ou tip one-shot) | JWT user | non |
| `create-portal-session` | Crée une session Stripe Billing Portal (cancel, payment method, invoices) | JWT user | non |
| `stripe-webhook` | Reçoit les events Stripe (subscription, payment_intent) et écrit dans `members` / `tips` / `contributor_balance` | signature Stripe | non |
| `compute-monthly-payout` | Snapshot du mois clos : calcule pool et parts par article, crédite les balances | service_role | **oui** (pg_cron 1er du mois 3h) |
| `request-payout` | Demande de virement Stripe Connect Transfer (si balance ≥ 20 € + KYC) | JWT user | non |
| `stripe-connect-onboarding` | Crée/récupère un compte Stripe Connect Express et retourne le lien KYC | JWT user | non |

## Variables d'environnement à configurer

Dans le dashboard Supabase → **Project Settings → Edge Functions → Secrets** :

```
STRIPE_SECRET_KEY=sk_test_...          # mode test d'abord !
STRIPE_WEBHOOK_SECRET=whsec_...        # depuis Stripe Dashboard > Webhooks
PRICE_ID_MEMBERSHIP=price_...          # Price récurrent 5€/mois EUR créé dans Stripe
SITE_URL=https://avis-base.com         # pour les redirect Stripe
```

Les variables `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` sont injectées automatiquement par Supabase.

## Setup Stripe (mode test)

1. **Compte Stripe** — créer un compte sur https://dashboard.stripe.com (passer en mode test)
2. **Produit + Price**
   - Products → New product → "Avis Basé+"
   - Pricing : Recurring monthly, **5,00 EUR**
   - Note : copier le `price_id` (commence par `price_...`) → variable `PRICE_ID_MEMBERSHIP`
3. **Webhook** (après déploiement de la fonction)
   - Developers → Webhooks → Add endpoint
   - URL : `https://<project-ref>.supabase.co/functions/v1/stripe-webhook`
   - Events :
     - `checkout.session.completed`
     - `customer.subscription.created`
     - `customer.subscription.updated`
     - `customer.subscription.deleted`
     - `invoice.paid`
     - `payment_intent.succeeded`
   - Copier le **Signing secret** (commence par `whsec_...`) → variable `STRIPE_WEBHOOK_SECRET`
4. **Stripe Connect** (Phase 7, pour les payouts)
   - Settings → Connect → Activate Connect platform
   - Choisir Express → activer Transfers capability
5. **Customer Portal** (v0.22.0, pour la gestion d'abonnement par l'user)
   - Settings → Billing → Customer portal → **Activate test link**
   - Activer les fonctionnalités à autoriser : annulation, mise à jour de la méthode de paiement, historique des factures
   - Pas de variable d'env à set : `create-portal-session` n'utilise que `STRIPE_SECRET_KEY` + `SITE_URL`

## Déploiement

```bash
# Installer Supabase CLI (une fois)
npm i -g supabase
supabase login
supabase link --project-ref <project-ref>

# Déployer les 6 fonctions
supabase functions deploy create-checkout-session
supabase functions deploy create-portal-session
supabase functions deploy stripe-webhook --no-verify-jwt
supabase functions deploy compute-monthly-payout --no-verify-jwt
supabase functions deploy request-payout
supabase functions deploy stripe-connect-onboarding

# Vérifier
supabase functions list
```

**Pourquoi `--no-verify-jwt` pour `stripe-webhook` et `compute-monthly-payout`** :
- `stripe-webhook` : Stripe ne porte pas de JWT, on vérifie via la signature `stripe-signature` à la place
- `compute-monthly-payout` : appelée par pg_cron sans JWT user, sécurisée par le service_role en backend

## Cron mensuel — `compute-monthly-payout`

Activer l'extension `pg_cron` + `pg_net` dans Supabase Dashboard → Database → Extensions.

Puis dans le SQL Editor :

```sql
-- Le 1er du mois à 3h du matin, calcule le payout du mois précédent
select cron.schedule(
  'compute-monthly-payout',
  '0 3 1 * *',
  $$
    select net.http_post(
      url := 'https://<project-ref>.supabase.co/functions/v1/compute-monthly-payout',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key')
      ),
      body := '{}'::jsonb
    );
  $$
);
```

NB : la variable `app.settings.service_role_key` doit être set en amont (Database → Settings → Custom Settings).

## Test rapide (curl)

```bash
# create-checkout-session (avec JWT user)
curl -X POST https://<project-ref>.supabase.co/functions/v1/create-checkout-session \
  -H "Authorization: Bearer <JWT_USER>" \
  -H "Content-Type: application/json" \
  -d '{"mode":"subscription","display_consent":true}'
# → renvoie { "url": "https://checkout.stripe.com/..." } à utiliser pour redirect

# stripe-connect-onboarding (avec JWT user)
curl -X POST https://<project-ref>.supabase.co/functions/v1/stripe-connect-onboarding \
  -H "Authorization: Bearer <JWT_USER>"
# → renvoie { "account_id": "acct_...", "url": "https://connect.stripe.com/..." }

# compute-monthly-payout (mode test sans JWT, via service_role)
curl -X POST https://<project-ref>.supabase.co/functions/v1/compute-monthly-payout \
  -H "Authorization: Bearer <SERVICE_ROLE_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"payout_month":"2026-04"}'
```

## ⚠️ Avant le 1er virement réel à un contributeur

**Statut juridique** : intermédiaire de paiement en France → consulter un avocat sur :
- Statut CGP / agrément ACPR éventuellement requis
- Mise à jour CGU + politique de confidentialité
- Déclaration TRACFIN si seuils atteints
- Conditions de Stripe Connect Express (clauses utilisateur final)

Stripe Connect Express porte le KYC réglementaire mais **pas** le conseil juridique sur le statut de la plateforme.

## Reset si quelque chose foire

```bash
# Supprimer une fonction
supabase functions delete <name>

# Voir les logs
supabase functions logs <name>
```
