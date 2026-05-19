-- ============================================================================
-- Avis Base -- v0.30.0 -- Web Push notifications (VAPID)
-- ============================================================================
--
-- Table `push_subscriptions` + 4 RPCs + trigger sur `notifications` INSERT :
--
--   * subscribe_push(p_endpoint, p_p256dh, p_auth, p_user_agent)
--   * unsubscribe_push(p_endpoint)
--   * list_my_push_subscriptions()
--   * has_push_subscription()                -> bool
--
-- Trigger : a chaque insert dans `notifications`, on appelle l'Edge Function
-- `send-push-notification` via pg_net (HTTP POST async).
--
-- Idempotent. ASCII pur. A appliquer apres v0.29.0.
-- Pre-requis : extension `pg_net` activee + secret `app.settings.edge_url`
-- (URL https://<project>.supabase.co/functions/v1/) + cle service_role.
-- ============================================================================

set search_path = public;


-- ----------------------------------------------------------------------------
-- 1. Table push_subscriptions
-- ----------------------------------------------------------------------------
-- 1 ligne par device/browser. Un user peut avoir N subscriptions (laptop,
-- tel, etc.). On dedoublonne sur (user_id, endpoint).

create table if not exists push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  endpoint    text not null,
  p256dh      text not null,
  auth_key    text not null,  -- "auth" est un mot reserve PG, on prefere "auth_key"
  user_agent  text,
  created_at  timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (user_id, endpoint)
);

create index if not exists push_subscriptions_user_idx
  on push_subscriptions(user_id);


-- ----------------------------------------------------------------------------
-- 2. RLS
-- ----------------------------------------------------------------------------
alter table push_subscriptions enable row level security;

drop policy if exists "users read own push subs" on push_subscriptions;
create policy "users read own push subs"
  on push_subscriptions for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "users insert own push subs" on push_subscriptions;
create policy "users insert own push subs"
  on push_subscriptions for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "users delete own push subs" on push_subscriptions;
create policy "users delete own push subs"
  on push_subscriptions for delete to authenticated
  using (user_id = auth.uid());

-- Update reserve au service_role (pour bump last_seen_at depuis l'Edge Function
-- et delete les endpoints 410 Gone)
drop policy if exists "service_role manages push subs" on push_subscriptions;
create policy "service_role manages push subs"
  on push_subscriptions for all to service_role
  using (true) with check (true);


-- ----------------------------------------------------------------------------
-- 3. RPC : subscribe_push
-- ----------------------------------------------------------------------------
-- Upsert sur (user_id, endpoint) : si la subscription existe deja, on met
-- a jour p256dh + auth + last_seen_at. Sinon insert.
-- Retourne l'id de la subscription.

create or replace function subscribe_push(
  p_endpoint    text,
  p_p256dh      text,
  p_auth        text,
  p_user_agent  text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
begin
  if v_uid is null then
    raise exception 'auth required';
  end if;
  if p_endpoint is null or length(p_endpoint) < 10 then
    raise exception 'invalid endpoint';
  end if;
  if p_p256dh is null or p_auth is null then
    raise exception 'p256dh and auth required';
  end if;

  insert into push_subscriptions (user_id, endpoint, p256dh, auth_key, user_agent)
       values (v_uid, p_endpoint, p_p256dh, p_auth, p_user_agent)
  on conflict (user_id, endpoint) do update
    set p256dh = excluded.p256dh,
        auth_key = excluded.auth_key,
        user_agent = excluded.user_agent,
        last_seen_at = now()
  returning id into v_id;

  return v_id;
end $$;

grant execute on function subscribe_push(text, text, text, text) to authenticated;


-- ----------------------------------------------------------------------------
-- 4. RPC : unsubscribe_push
-- ----------------------------------------------------------------------------
create or replace function unsubscribe_push(p_endpoint text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_n   int;
begin
  if v_uid is null then return false; end if;

  delete from push_subscriptions
   where user_id = v_uid
     and endpoint = p_endpoint;

  get diagnostics v_n = row_count;
  return v_n > 0;
end $$;

grant execute on function unsubscribe_push(text) to authenticated;


-- ----------------------------------------------------------------------------
-- 5. RPC : has_push_subscription
-- ----------------------------------------------------------------------------
-- Pour que le frontend sache si l'user a deja active les push (sur n'importe
-- quel device). Pratique pour afficher l'etat dans les reglages.

create or replace function has_push_subscription()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from push_subscriptions where user_id = auth.uid()
  );
$$;

grant execute on function has_push_subscription() to authenticated;


-- ----------------------------------------------------------------------------
-- 6. RPC : list_my_push_subscriptions
-- ----------------------------------------------------------------------------
-- Liste des devices abonnes (pour permettre de revoquer un device specifique).

create or replace function list_my_push_subscriptions()
returns table (
  id           uuid,
  endpoint     text,
  user_agent   text,
  created_at   timestamptz,
  last_seen_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select id, endpoint, user_agent, created_at, last_seen_at
    from push_subscriptions
   where user_id = auth.uid()
   order by last_seen_at desc;
$$;

grant execute on function list_my_push_subscriptions() to authenticated;


-- ----------------------------------------------------------------------------
-- 7. Trigger : notifications INSERT -> Edge Function send-push-notification
-- ----------------------------------------------------------------------------
-- A chaque nouvelle notification in-app, on tente d'envoyer un push via
-- l'Edge Function. pg_net.http_post est async (fire-and-forget), donc le
-- trigger ne ralentit pas l'insert.
--
-- L'Edge Function s'authentifie via la service_role key (lue dans le secret
-- `app.settings.service_role_key`).
--
-- Si pg_net n'est pas active : le trigger essaie quand meme et catch l'erreur
-- silencieusement (la notification in-app reste creee).

create or replace function notify_push_on_notification()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_edge_url text;
  v_sr_key   text;
  v_payload  jsonb;
  v_actor    record;
  v_title    text;
  v_body     text;
  v_url      text;
begin
  -- Tente de recuperer les secrets (no-op si pas configures)
  begin
    v_edge_url := current_setting('app.settings.edge_url', true);
    v_sr_key   := current_setting('app.settings.service_role_key', true);
  exception when others then
    return new;
  end;

  if v_edge_url is null or v_sr_key is null then
    return new; -- Pas configure -> on n'envoie rien (les notifs in-app marchent toujours)
  end if;

  -- Lookup actor (pour le titre du push)
  begin
    select username, avatar_url into v_actor
      from profiles where id = new.actor_id;
  exception when others then null;
  end;

  -- Format human-readable selon le type
  v_title := 'Avis Base';
  v_body  := 'Tu as une nouvelle notification.';
  if new.type = 'follow' then
    v_title := '+1 abonne';
    v_body  := coalesce('@' || v_actor.username, 'Quelqu''un') || ' te suit maintenant.';
  elsif new.type = 'like' then
    v_title := 'Nouveau like';
    v_body  := coalesce('@' || v_actor.username, 'Quelqu''un') || ' aime ton contenu.';
  elsif new.type = 'comment' then
    v_title := 'Nouveau commentaire';
    v_body  := coalesce('@' || v_actor.username, 'Quelqu''un') || ' a commente.';
  elsif new.type = 'reply' then
    v_title := 'Reponse a ton commentaire';
    v_body  := coalesce('@' || v_actor.username, 'Quelqu''un') || ' t''a repondu.';
  elsif new.type = 'article_validated' then
    v_title := 'Article publie';
    v_body  := 'Ton article a ete valide et publie.';
  elsif new.type = 'content_hidden' then
    v_title := 'Contenu masque';
    v_body  := 'Un de tes contenus a ete masque par la moderation.';
  elsif new.type = 'content_restored' then
    v_title := 'Contenu restaure';
    v_body  := 'Un de tes contenus a ete restaure.';
  end if;

  -- Cible : URL canonique selon target_type
  v_url := '/';
  if new.target_type = 'article' then
    v_url := '/?article=' || new.target_id;
  elsif new.target_type = 'profile' then
    v_url := '/?profile=' || new.target_id;
  elsif new.target_type = 'clip' then
    v_url := '/?clip=' || new.target_id;
  end if;

  v_payload := jsonb_build_object(
    'user_id', new.user_id,
    'title',   v_title,
    'body',    v_body,
    'url',     v_url,
    'icon',    '/icon-192.png',
    'badge',   '/icon-72.png',
    'tag',     new.type
  );

  -- Fire-and-forget via pg_net (async, ne bloque pas l'insert)
  begin
    perform net.http_post(
      url     := v_edge_url || 'send-push-notification',
      body    := v_payload,
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || v_sr_key
      )
    );
  exception when others then
    -- pg_net pas active ou erreur reseau : on ne casse pas l'insert
    null;
  end;

  return new;
end $$;

drop trigger if exists tr_notify_push_on_notification on notifications;
create trigger tr_notify_push_on_notification
  after insert on notifications
  for each row execute function notify_push_on_notification();


-- ============================================================================
-- Smoke tests :
--   select subscribe_push('https://fcm.googleapis.com/...', 'BNc...', 'xyz', 'test');
--   select has_push_subscription();
--   select * from list_my_push_subscriptions();
--   select unsubscribe_push('https://fcm.googleapis.com/...');
-- ============================================================================
-- Setup admin requis :
--   1) Generer VAPID keys : npx web-push generate-vapid-keys
--   2) Set Supabase secrets :
--        supabase secrets set VAPID_PUBLIC_KEY=<...> VAPID_PRIVATE_KEY=<...> VAPID_SUBJECT=mailto:contact@avis-base.com
--   3) Mettre la cle publique dans index.html (constante VAPID_PUBLIC_KEY)
--   4) Activer extension pg_net :
--        create extension if not exists pg_net;
--   5) Set secrets DB pour le trigger :
--        alter database postgres set "app.settings.edge_url" to 'https://<ref>.supabase.co/functions/v1/';
--        alter database postgres set "app.settings.service_role_key" to '<service_role_key>';
--   6) Deployer Edge Function : supabase functions deploy send-push-notification
-- ============================================================================
-- Fin v0.30.0
-- ============================================================================
