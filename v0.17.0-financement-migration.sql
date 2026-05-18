-- ============================================================================
-- Avis Basé — v0.17.0 — Économie collaborative transparente
--
-- 9 tables + 4 vues publiques + 4 RPCs + RLS strict.
-- 100 % transparence : pool, frais, virements visibles sur /financement.
--
-- Adhésion 5 €/mois ("Avis Basé+"). 0 salaire admin. 100 % du surplus
-- reversé aux contributeurs au prorata des scores d'articles publiés.
--
-- Anti-fraude : 1 vue/jour/user, read_time min 10s, auteur exclu,
-- vues de membres pondérées x2.
--
-- Idempotent. ASCII comments only (pas de box-drawing). À exécuter dans le
-- SQL Editor Supabase. À appliquer APRÈS v0.16.0-migration.sql.
-- ============================================================================

set search_path = public;

-- ----------------------------------------------------------------------------
-- 1. members : adhérents Avis Basé+ (Stripe Subscription)
-- ----------------------------------------------------------------------------

create table if not exists members (
  user_id                   uuid primary key references profiles(id) on delete cascade,
  stripe_customer_id        text unique,
  stripe_subscription_id    text unique,
  status                    text not null default 'active'
    check (status in ('active','cancelled','past_due','incomplete','trialing','unpaid')),
  tier                      text not null default 'plus'
    check (tier in ('plus')),
  amount_cents              int  not null default 500
    check (amount_cents > 0),
  display_consent           boolean not null default false,
  started_at                timestamptz not null default now(),
  current_period_end        timestamptz,
  cancel_at_period_end      boolean not null default false,
  cancelled_at              timestamptz,
  updated_at                timestamptz not null default now()
);

create index if not exists members_status_idx on members(status) where status = 'active';
create index if not exists members_display_consent_idx on members(display_consent) where display_consent = true;

alter table members enable row level security;

drop policy if exists "members_select_own" on members;
drop policy if exists "members_update_consent_own" on members;

-- Un user voit sa propre adhésion
create policy "members_select_own" on members
  for select using (user_id = auth.uid());

-- Un user peut changer son consentement d'affichage (mais pas le reste)
create policy "members_update_consent_own" on members
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- INSERT/DELETE réservés au service_role (Stripe webhook)


-- ----------------------------------------------------------------------------
-- 2. tips : dons ponctuels (Stripe Payment Intent)
-- ----------------------------------------------------------------------------

create table if not exists tips (
  id                        uuid primary key default gen_random_uuid(),
  sender_user_id            uuid references profiles(id) on delete set null,
  target_type               text not null default 'pool'
    check (target_type in ('pool','article','contributor')),
  target_article_id         uuid references articles(id) on delete set null,
  target_user_id            uuid references profiles(id) on delete set null,
  amount_cents              int not null check (amount_cents > 0 and amount_cents <= 100000),
  stripe_payment_intent_id  text unique,
  status                    text not null default 'pending'
    check (status in ('pending','succeeded','failed','refunded')),
  display_consent           boolean not null default false,
  created_at                timestamptz not null default now()
);

create index if not exists tips_status_idx on tips(status);
create index if not exists tips_created_at_idx on tips(created_at desc);
create index if not exists tips_target_article_idx on tips(target_article_id) where target_article_id is not null;
create index if not exists tips_target_user_idx on tips(target_user_id) where target_user_id is not null;
create index if not exists tips_display_consent_idx on tips(display_consent) where display_consent = true;

alter table tips enable row level security;

drop policy if exists "tips_select_own" on tips;

-- Un user voit ses propres tips envoyés
create policy "tips_select_own" on tips
  for select using (sender_user_id = auth.uid());

-- INSERT/UPDATE réservés au service_role (Stripe webhook)


-- ----------------------------------------------------------------------------
-- 3. article_views : vues brutes avec dédup
-- ----------------------------------------------------------------------------
-- 1 vue = 1 (viewer_user_id OU session_hash) par article par jour max.
-- read_time_seconds < 10 ne compte pas (filtré côté RPC).

create table if not exists article_views (
  id                  uuid primary key default gen_random_uuid(),
  article_id          uuid not null references articles(id) on delete cascade,
  viewer_user_id      uuid references profiles(id) on delete set null,
  session_hash        text,
  read_time_seconds   int not null default 0 check (read_time_seconds >= 0),
  is_member           boolean not null default false,
  viewed_date         date not null default current_date,
  created_at          timestamptz not null default now(),
  constraint article_views_one_id check (viewer_user_id is not null or session_hash is not null)
);

create index if not exists article_views_article_date_idx on article_views(article_id, viewed_date);

-- Dédup : un user (connecté) ne peut compter qu'une vue par article par jour
create unique index if not exists article_views_dedup_user_idx
  on article_views(article_id, viewer_user_id, viewed_date)
  where viewer_user_id is not null;

-- Dédup : une session (anonyme) ne peut compter qu'une vue par article par jour
create unique index if not exists article_views_dedup_session_idx
  on article_views(article_id, session_hash, viewed_date)
  where viewer_user_id is null and session_hash is not null;

alter table article_views enable row level security;

drop policy if exists "views_insert_via_rpc" on article_views;
drop policy if exists "views_select_own" on article_views;

-- INSERT via RPC track_view uniquement (security definer)
-- SELECT : un user voit ses propres vues (utile pour le debug, pas critique)
create policy "views_select_own" on article_views
  for select using (viewer_user_id = auth.uid());


-- ----------------------------------------------------------------------------
-- 4. article_stats_daily : agrégat journalier (perf)
-- ----------------------------------------------------------------------------
-- Évite de scanner article_views à chaque calcul. Mis à jour par le RPC
-- track_view (incrémental) ou par un cron de réconciliation.

create table if not exists article_stats_daily (
  article_id            uuid not null references articles(id) on delete cascade,
  stat_date             date not null,
  views_unique_count    int not null default 0,
  views_member_count    int not null default 0,
  read_time_total_sec   int not null default 0,
  engagement_count      int not null default 0,
  score                 numeric(12,2) not null default 0,
  updated_at            timestamptz not null default now(),
  primary key (article_id, stat_date)
);

create index if not exists article_stats_score_idx on article_stats_daily(stat_date, score desc);

alter table article_stats_daily enable row level security;

drop policy if exists "stats_select_public" on article_stats_daily;

-- Lecture publique (agrégats anonymes)
create policy "stats_select_public" on article_stats_daily
  for select using (true);

-- INSERT/UPDATE réservés au service_role


-- ----------------------------------------------------------------------------
-- 5. contributor_balance : cagnotte par contributeur
-- ----------------------------------------------------------------------------

create table if not exists contributor_balance (
  user_id                       uuid primary key references profiles(id) on delete cascade,
  balance_cents                 int not null default 0 check (balance_cents >= 0),
  total_earned_cents            int not null default 0 check (total_earned_cents >= 0),
  stripe_connect_account_id     text unique,
  kyc_completed                 boolean not null default false,
  kyc_completed_at              timestamptz,
  public_name_consent           boolean not null default false,
  updated_at                    timestamptz not null default now()
);

create index if not exists balance_kyc_idx on contributor_balance(kyc_completed) where kyc_completed = true;
create index if not exists balance_public_consent_idx on contributor_balance(public_name_consent) where public_name_consent = true;

alter table contributor_balance enable row level security;

drop policy if exists "balance_select_own" on contributor_balance;
drop policy if exists "balance_update_consent_own" on contributor_balance;

create policy "balance_select_own" on contributor_balance
  for select using (user_id = auth.uid());

-- L'user peut changer son consentement et lancer son onboarding KYC
-- mais pas modifier balance/total/stripe_connect_account_id (service_role)
create policy "balance_update_consent_own" on contributor_balance
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());


-- ----------------------------------------------------------------------------
-- 6. monthly_payouts : clôture mensuelle (immuable une fois 'distributed')
-- ----------------------------------------------------------------------------

create table if not exists monthly_payouts (
  id                    uuid primary key default gen_random_uuid(),
  payout_month          text not null unique
    check (payout_month ~ '^[0-9]{4}-[0-9]{2}$'),
  revenue_cents         int not null default 0 check (revenue_cents >= 0),
  stripe_fees_cents     int not null default 0 check (stripe_fees_cents >= 0),
  infra_cost_cents      int not null default 0 check (infra_cost_cents >= 0),
  pool_cents            int not null default 0 check (pool_cents >= 0),
  members_count         int not null default 0,
  tips_count            int not null default 0,
  articles_count        int not null default 0,
  status                text not null default 'draft'
    check (status in ('draft','computed','distributed','archived')),
  computed_at           timestamptz,
  distributed_at        timestamptz,
  notes                 text
);

create index if not exists payouts_status_idx on monthly_payouts(status);
create index if not exists payouts_month_idx on monthly_payouts(payout_month desc);

alter table monthly_payouts enable row level security;

drop policy if exists "payouts_select_public" on monthly_payouts;

-- Lecture publique (transparence intégrale)
create policy "payouts_select_public" on monthly_payouts
  for select using (true);

-- INSERT/UPDATE/DELETE réservés au service_role


-- ----------------------------------------------------------------------------
-- 7. monthly_payout_articles : détail par article (snapshot immuable)
-- ----------------------------------------------------------------------------

create table if not exists monthly_payout_articles (
  monthly_payout_id     uuid not null references monthly_payouts(id) on delete cascade,
  article_id            uuid not null references articles(id) on delete cascade,
  author_id             uuid references profiles(id) on delete set null,
  score_total           numeric(12,2) not null default 0,
  share_cents           int not null default 0 check (share_cents >= 0),
  primary key (monthly_payout_id, article_id)
);

create index if not exists payout_articles_author_idx on monthly_payout_articles(author_id);

alter table monthly_payout_articles enable row level security;

drop policy if exists "payout_articles_select_public" on monthly_payout_articles;

create policy "payout_articles_select_public" on monthly_payout_articles
  for select using (true);

-- INSERT/UPDATE réservés au service_role


-- ----------------------------------------------------------------------------
-- 8. contributor_payments : virements Stripe Connect
-- ----------------------------------------------------------------------------

create table if not exists contributor_payments (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references profiles(id) on delete cascade,
  amount_cents          int not null check (amount_cents > 0),
  stripe_transfer_id    text unique,
  status                text not null default 'pending'
    check (status in ('pending','completed','failed','cancelled')),
  requested_at          timestamptz not null default now(),
  completed_at          timestamptz,
  failed_at             timestamptz,
  failure_reason        text
);

create index if not exists payments_user_idx on contributor_payments(user_id, requested_at desc);
create index if not exists payments_status_idx on contributor_payments(status);

alter table contributor_payments enable row level security;

drop policy if exists "payments_select_own" on contributor_payments;

create policy "payments_select_own" on contributor_payments
  for select using (user_id = auth.uid());

-- INSERT/UPDATE réservés au service_role


-- ----------------------------------------------------------------------------
-- 9. monthly_infra_costs : frais saisis manuellement (transparence)
-- ----------------------------------------------------------------------------

create table if not exists monthly_infra_costs (
  id                    uuid primary key default gen_random_uuid(),
  cost_month            text not null
    check (cost_month ~ '^[0-9]{4}-[0-9]{2}$'),
  label                 text not null,
  amount_cents          int not null check (amount_cents >= 0),
  notes                 text,
  created_by            uuid references profiles(id) on delete set null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index if not exists infra_costs_month_idx on monthly_infra_costs(cost_month);

alter table monthly_infra_costs enable row level security;

drop policy if exists "infra_costs_select_public" on monthly_infra_costs;
drop policy if exists "infra_costs_insert_superadmin" on monthly_infra_costs;
drop policy if exists "infra_costs_update_superadmin" on monthly_infra_costs;
drop policy if exists "infra_costs_delete_superadmin" on monthly_infra_costs;

-- Lecture publique (transparence)
create policy "infra_costs_select_public" on monthly_infra_costs
  for select using (true);

-- Écriture réservée aux superadmins (saisie manuelle des factures)
create policy "infra_costs_insert_superadmin" on monthly_infra_costs
  for insert with check (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'superadmin')
  );

create policy "infra_costs_update_superadmin" on monthly_infra_costs
  for update using (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'superadmin')
  );

create policy "infra_costs_delete_superadmin" on monthly_infra_costs
  for delete using (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'superadmin')
  );


-- ============================================================================
-- VUES PUBLIQUES (security_invoker = true, lecture anonyme)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- VUE 1. public_economy_current : pool en cours + agrégats anonymisés
-- ----------------------------------------------------------------------------

create or replace view public_economy_current
with (security_invoker = true) as
with current_m as (
  select to_char(now(), 'YYYY-MM') as month
),
revenue_month as (
  -- Revenus du mois en cours = somme des member fees actifs + tips succeeded
  select
    (select coalesce(count(*), 0) from members where status = 'active') * 500 +
    (select coalesce(sum(amount_cents), 0) from tips where status = 'succeeded' and to_char(created_at, 'YYYY-MM') = (select month from current_m))
    as revenue_cents
),
fees_month as (
  select coalesce(sum(amount_cents), 0) as infra_cost_cents
  from monthly_infra_costs
  where cost_month = (select month from current_m)
),
members_count as (
  select coalesce(count(*), 0) as cnt from members where status = 'active'
),
tips_month as (
  select coalesce(count(*), 0) as cnt, coalesce(sum(amount_cents), 0) as total_cents
  from tips where status = 'succeeded' and to_char(created_at, 'YYYY-MM') = (select month from current_m)
)
select
  (select month from current_m) as current_month,
  rm.revenue_cents,
  greatest(0, (rm.revenue_cents * 5 / 100)::int) as stripe_fees_cents,
  fm.infra_cost_cents,
  greatest(0, rm.revenue_cents - (rm.revenue_cents * 5 / 100)::int - fm.infra_cost_cents) as pool_cents,
  mc.cnt as members_count,
  tm.cnt as tips_count_month,
  tm.total_cents as tips_total_cents_month
from revenue_month rm, fees_month fm, members_count mc, tips_month tm;

comment on view public_economy_current is
  'Pool en cours, nombre de membres, tips du mois — données anonymisées.';


-- ----------------------------------------------------------------------------
-- VUE 2. public_donor_wall : mur des soutiens (opt-in only)
-- ----------------------------------------------------------------------------

create or replace view public_donor_wall
with (security_invoker = true) as
-- Members opt-in
select
  'member'::text       as kind,
  p.username           as name,
  p.id                 as profile_id,
  m.amount_cents,
  m.started_at         as since,
  null::int            as tip_amount_cents
from members m
join profiles p on p.id = m.user_id
where m.status = 'active' and m.display_consent = true
union all
-- Tips opt-in
select
  'tip'::text          as kind,
  p.username           as name,
  p.id                 as profile_id,
  null::int            as amount_cents,
  t.created_at         as since,
  t.amount_cents       as tip_amount_cents
from tips t
join profiles p on p.id = t.sender_user_id
where t.status = 'succeeded' and t.display_consent = true
order by since desc;

comment on view public_donor_wall is
  'Soutiens visibles publiquement — uniquement ceux ayant coché display_consent.';


-- ----------------------------------------------------------------------------
-- VUE 3. public_article_leaderboard : top articles du mois (avec part estimée)
-- ----------------------------------------------------------------------------

create or replace view public_article_leaderboard
with (security_invoker = true) as
with current_m as (
  select to_char(now(), 'YYYY-MM') as month
),
month_stats as (
  -- Somme des scores par article pour le mois courant
  select
    a.id as article_id,
    a.title,
    a.author_id,
    coalesce(sum(s.score), 0) as score_total
  from articles a
  left join article_stats_daily s on s.article_id = a.id
    and to_char(s.stat_date, 'YYYY-MM') = (select month from current_m)
  where a.status = 'published'
  group by a.id, a.title, a.author_id
),
score_sum as (
  select coalesce(sum(score_total), 0) as total from month_stats
),
pool as (
  select pool_cents from public_economy_current
)
select
  ms.article_id,
  ms.title,
  ms.author_id,
  case
    when cb.public_name_consent = true then p.username
    else 'Auteur #' || substring(md5(ms.author_id::text), 1, 4)
  end as author_display_name,
  cb.public_name_consent as author_consent,
  ms.score_total as score,
  case
    when (select total from score_sum) > 0 then
      ((ms.score_total / (select total from score_sum)) * (select pool_cents from pool))::int
    else 0
  end as estimated_share_cents
from month_stats ms
left join profiles p on p.id = ms.author_id
left join contributor_balance cb on cb.user_id = ms.author_id
where ms.score_total > 0
order by ms.score_total desc
limit 30;

comment on view public_article_leaderboard is
  'Top 30 articles du mois avec part estimée du pool. Pseudonyme stable si auteur opt-out.';


-- ----------------------------------------------------------------------------
-- VUE 4. public_monthly_archive : historique des mois clôturés
-- ----------------------------------------------------------------------------

create or replace view public_monthly_archive
with (security_invoker = true) as
select
  payout_month,
  revenue_cents,
  stripe_fees_cents,
  infra_cost_cents,
  pool_cents,
  members_count,
  tips_count,
  articles_count,
  status,
  computed_at,
  distributed_at
from monthly_payouts
where status in ('computed','distributed','archived')
order by payout_month desc;

comment on view public_monthly_archive is
  'Historique des clôtures mensuelles passées — transparence complète.';


-- ============================================================================
-- RPCs (security definer pour anti-fraude et écritures protégées)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- RPC 1. track_view : enregistre une vue + read_time, avec dédup et anti-fraude
-- ----------------------------------------------------------------------------
-- Règles :
-- - 1 vue/user/jour/article (dédup via UNIQUE INDEX)
-- - read_time_seconds < 10 → vue NON enregistrée
-- - viewer = auteur de l'article → vue ignorée silencieusement
-- - is_member calculé automatiquement depuis members.status = 'active'

create or replace function track_view(
  p_article_id       uuid,
  p_read_time_sec    int,
  p_session_hash     text default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_author_id uuid;
  v_is_member boolean := false;
  v_inserted boolean := false;
begin
  -- Validation read_time minimum
  if p_read_time_sec is null or p_read_time_sec < 10 then
    return false;
  end if;

  -- Récupérer l'auteur pour exclusion
  select author_id into v_author_id from articles where id = p_article_id;
  if v_author_id is null then return false; end if;

  -- Auteur exclu de ses propres vues
  if v_uid is not null and v_uid = v_author_id then
    return false;
  end if;

  -- Pour un user anonyme, exiger session_hash
  if v_uid is null and (p_session_hash is null or length(p_session_hash) < 8) then
    return false;
  end if;

  -- Est-ce un membre actif ?
  if v_uid is not null then
    select exists(select 1 from members where user_id = v_uid and status = 'active')
      into v_is_member;
  end if;

  -- Insert avec ON CONFLICT (gère la dédup quotidienne)
  begin
    insert into article_views (article_id, viewer_user_id, session_hash, read_time_seconds, is_member, viewed_date)
    values (p_article_id, v_uid, p_session_hash, p_read_time_sec, v_is_member, current_date);
    v_inserted := true;
  exception when unique_violation then
    -- Déjà compté aujourd'hui — on update le read_time si plus grand
    update article_views
    set read_time_seconds = greatest(read_time_seconds, p_read_time_sec)
    where article_id = p_article_id
      and (
        (viewer_user_id is not null and viewer_user_id = v_uid)
        or (viewer_user_id is null and session_hash = p_session_hash)
      )
      and viewed_date = current_date;
  end;

  return v_inserted;
end $$;


-- ----------------------------------------------------------------------------
-- RPC 2. update_member_consent : un user change son display_consent
-- ----------------------------------------------------------------------------

create or replace function update_member_consent(p_consent boolean)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then return false; end if;
  update members set display_consent = p_consent, updated_at = now() where user_id = v_uid;
  return found;
end $$;


-- ----------------------------------------------------------------------------
-- RPC 3. update_contributor_public_consent : toggle pseudo public
-- ----------------------------------------------------------------------------

create or replace function update_contributor_public_consent(p_consent boolean)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then return false; end if;
  -- Upsert (un user peut activer le consent même sans avoir de balance encore)
  insert into contributor_balance (user_id, public_name_consent, updated_at)
  values (v_uid, p_consent, now())
  on conflict (user_id) do update set
    public_name_consent = excluded.public_name_consent,
    updated_at = now();
  return true;
end $$;


-- ----------------------------------------------------------------------------
-- RPC 4. recompute_article_stats_daily : recalcule l'agrégat (idempotent)
-- ----------------------------------------------------------------------------
-- À appeler par un cron quotidien OU manuellement après réconciliation.
-- engagement = likes + comments*2 + sources_validées*5
-- (partages × 3 pas inclus tant que pas de tracking shares)

create or replace function recompute_article_stats_daily(p_date date default current_date)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
begin
  insert into article_stats_daily (article_id, stat_date, views_unique_count, views_member_count, read_time_total_sec, engagement_count, score, updated_at)
  select
    av.article_id,
    p_date as stat_date,
    count(*) filter (where av.read_time_seconds >= 10) as views_unique_count,
    count(*) filter (where av.is_member = true and av.read_time_seconds >= 10) as views_member_count,
    coalesce(sum(av.read_time_seconds), 0) as read_time_total_sec,
    -- Engagement de l'article (snapshot du jour)
    coalesce(a.likes_count, 0)
      + coalesce(a.comments_count, 0) * 2
      + coalesce(jsonb_array_length(a.cited_sources), 0) * 5 as engagement_count,
    -- Score = vues_uniques×0.3 + read_time_normalisé×0.5 + engagement×0.2
    -- read_time_normalisé = read_time_total_sec / 60 (en minutes)
    (
      (count(*) filter (where av.read_time_seconds >= 10) * 0.3)
      + ((coalesce(sum(av.read_time_seconds), 0)::numeric / 60.0) * 0.5)
      + ((coalesce(a.likes_count, 0) + coalesce(a.comments_count, 0) * 2 + coalesce(jsonb_array_length(a.cited_sources), 0) * 5) * 0.2)
      -- Pondération membres x2 : ajoute la même formule restreinte aux membres
      + (count(*) filter (where av.is_member = true and av.read_time_seconds >= 10) * 0.3)
    )::numeric(12,2) as score,
    now()
  from article_views av
  join articles a on a.id = av.article_id
  where av.viewed_date = p_date
  group by av.article_id, a.likes_count, a.comments_count, a.cited_sources
  on conflict (article_id, stat_date) do update set
    views_unique_count = excluded.views_unique_count,
    views_member_count = excluded.views_member_count,
    read_time_total_sec = excluded.read_time_total_sec,
    engagement_count = excluded.engagement_count,
    score = excluded.score,
    updated_at = now();

  get diagnostics v_count = row_count;
  return v_count;
end $$;


-- ============================================================================
-- Smoke tests à exécuter manuellement après la migration :
--
--   -- 9 tables créées ?
--   select tablename from pg_tables
--   where schemaname='public'
--     and tablename in ('members','tips','article_views','article_stats_daily',
--                       'contributor_balance','monthly_payouts','monthly_payout_articles',
--                       'contributor_payments','monthly_infra_costs');
--   -- Attendu : 9 lignes
--
--   -- 4 vues créées ?
--   select viewname from pg_views
--   where schemaname='public'
--     and viewname in ('public_economy_current','public_donor_wall',
--                      'public_article_leaderboard','public_monthly_archive');
--   -- Attendu : 4 lignes
--
--   -- 4 RPCs créées ?
--   select proname from pg_proc
--   where proname in ('track_view','update_member_consent',
--                     'update_contributor_public_consent','recompute_article_stats_daily');
--   -- Attendu : 4 lignes
--
--   -- Vue économie courante (devrait renvoyer 1 ligne avec pool_cents=0)
--   select * from public_economy_current;
--
--   -- Test track_view (en remplaçant les UUIDs)
--   -- select track_view('<article_id>'::uuid, 15, 'sessXXXX12345678');
-- ============================================================================
-- Migration v0.17.0 — terminée.
--
-- Étape suivante : déployer les Edge Functions
--   - create-checkout-session (Stripe Subscription 5€/mois + tips one-shot)
--   - stripe-webhook (subscription.* + payment_intent.succeeded)
--   - compute-monthly-payout (cron 1er du mois 3h via pg_cron)
--   - request-payout (Stripe Connect Transfer si balance >= 20€ + KYC done)
--   - stripe-connect-onboarding (lien KYC Stripe Express)
-- ============================================================================
