-- ════════════════════════════════════════════════════════════════════
-- Avis Basé — Migration V0.8 : économie de pièces (coins)
-- À exécuter UNE FOIS dans Supabase SQL editor.
-- ════════════════════════════════════════════════════════════════════

-- 1) Solde + badge cosmétique sur profiles
alter table profiles add column if not exists coins integer not null default 0;
alter table profiles add column if not exists badge text default null;

-- 2) Suivi des lectures uniques (anti-farming minimal)
create table if not exists article_reads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  article_id uuid not null references articles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(user_id, article_id)
);
create index if not exists article_reads_article_idx on article_reads(article_id);

-- 3) Journal d'audit des mouvements de pièces
create table if not exists coin_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  amount integer not null,                   -- + = gagné / - = dépensé
  type text not null,                        -- 'view_earn'|'tip_sent'|'tip_received'|'boost'|'badge_buy'
  ref_id uuid,                               -- id de l'article ou de l'autre user selon le type
  note text,
  created_at timestamptz not null default now()
);
create index if not exists coin_transactions_user_idx on coin_transactions(user_id, created_at desc);

-- 4) Boost d'article (mise à la une temporaire)
alter table articles add column if not exists boosted_until timestamptz default null;

-- 5) Row Level Security
alter table article_reads enable row level security;
alter table coin_transactions enable row level security;

drop policy if exists "users insert own read" on article_reads;
create policy "users insert own read"
  on article_reads for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "users read own reads" on article_reads;
create policy "users read own reads"
  on article_reads for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "users read own tx" on coin_transactions;
create policy "users read own tx"
  on coin_transactions for select to authenticated
  using (user_id = auth.uid());
-- Pas de policy d'insert → tout passe par les RPC ci-dessous (security definer).

-- 6) RPC claim_read : idempotent, crédite l'auteur tous les 10 lecteurs uniques
create or replace function claim_read(p_article_id uuid)
returns table(credited integer, total_reads integer)
language plpgsql security definer as $$
declare
  v_author uuid;
  v_reads integer;
  v_inserted boolean := false;
  v_credit integer := 0;
begin
  if auth.uid() is null then raise exception 'auth required'; end if;

  begin
    insert into article_reads(user_id, article_id) values (auth.uid(), p_article_id);
    v_inserted := true;
  exception when unique_violation then
    v_inserted := false;
  end;

  if v_inserted then
    update articles set reads = coalesce(reads,0) + 1
    where id = p_article_id
    returning reads, author_id into v_reads, v_author;

    if v_reads is not null and v_reads % 10 = 0 and v_author is not null and v_author <> auth.uid() then
      update profiles set coins = coins + 1 where id = v_author;
      insert into coin_transactions(user_id, amount, type, ref_id, note)
      values (v_author, 1, 'view_earn', p_article_id, 'Palier de ' || v_reads || ' lectures');
      v_credit := 1;
    end if;
  else
    select reads into v_reads from articles where id = p_article_id;
  end if;

  return query select v_credit, coalesce(v_reads, 0);
end;
$$;
grant execute on function claim_read(uuid) to authenticated;

-- 7) RPC send_tip : pourboire entre utilisateurs
create or replace function send_tip(p_to_user uuid, p_amount integer, p_article_id uuid default null)
returns table(new_balance integer)
language plpgsql security definer as $$
declare
  v_from uuid := auth.uid();
  v_balance integer;
begin
  if v_from is null then raise exception 'auth required'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'amount must be positive'; end if;
  if v_from = p_to_user then raise exception 'cannot tip yourself'; end if;

  select coins into v_balance from profiles where id = v_from for update;
  if v_balance < p_amount then raise exception 'insufficient coins'; end if;

  update profiles set coins = coins - p_amount where id = v_from;
  update profiles set coins = coins + p_amount where id = p_to_user;

  insert into coin_transactions(user_id, amount, type, ref_id, note)
  values (v_from, -p_amount, 'tip_sent', p_to_user, 'Pourboire envoyé');
  insert into coin_transactions(user_id, amount, type, ref_id, note)
  values (p_to_user, p_amount, 'tip_received', v_from, 'Pourboire reçu');

  return query select v_balance - p_amount;
end;
$$;
grant execute on function send_tip(uuid, integer, uuid) to authenticated;

-- 8) RPC boost_article : mise à la une payante (5 pièces par heure)
create or replace function boost_article(p_article_id uuid, p_hours integer default 24)
returns table(boosted_until timestamptz, new_balance integer)
language plpgsql security definer as $$
declare
  v_user uuid := auth.uid();
  v_cost integer;
  v_balance integer;
  v_until timestamptz;
begin
  if v_user is null then raise exception 'auth required'; end if;
  if p_hours is null or p_hours <= 0 then raise exception 'hours must be positive'; end if;

  v_cost := p_hours * 5;

  select coins into v_balance from profiles where id = v_user for update;
  if v_balance < v_cost then raise exception 'insufficient coins'; end if;

  update profiles set coins = coins - v_cost where id = v_user;

  update articles
  set boosted_until = greatest(coalesce(boosted_until, now()), now()) + (p_hours || ' hours')::interval
  where id = p_article_id
  returning boosted_until into v_until;

  insert into coin_transactions(user_id, amount, type, ref_id, note)
  values (v_user, -v_cost, 'boost', p_article_id, 'Boost ' || p_hours || 'h');

  return query select v_until, v_balance - v_cost;
end;
$$;
grant execute on function boost_article(uuid, integer) to authenticated;

-- 9) RPC buy_badge : achat d'un badge cosmétique
create or replace function buy_badge(p_badge text)
returns table(new_balance integer)
language plpgsql security definer as $$
declare
  v_user uuid := auth.uid();
  v_cost integer;
  v_balance integer;
begin
  if v_user is null then raise exception 'auth required'; end if;

  v_cost := case p_badge
    when 'star'    then 50
    when 'flame'   then 100
    when 'crown'   then 250
    when 'diamond' then 500
    else null
  end;
  if v_cost is null then raise exception 'unknown badge'; end if;

  select coins into v_balance from profiles where id = v_user for update;
  if v_balance < v_cost then raise exception 'insufficient coins'; end if;

  update profiles set coins = coins - v_cost, badge = p_badge where id = v_user;

  insert into coin_transactions(user_id, amount, type, ref_id, note)
  values (v_user, -v_cost, 'badge_buy', null, 'Badge ' || p_badge);

  return query select v_balance - v_cost;
end;
$$;
grant execute on function buy_badge(text) to authenticated;
