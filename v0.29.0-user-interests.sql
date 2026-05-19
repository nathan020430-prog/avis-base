-- ============================================================================
-- Avis Base -- v0.29.0 -- Feed personnalise : interets + suggestions
-- ============================================================================
--
-- Table `user_interests` + 3 RPCs :
--   * set_user_interests(p_themes text[])              -> replace mes interets
--   * get_user_interests()                              -> mes interets
--   * get_suggested_authors_by_interest(p_limit)        -> auteurs dans mes
--                                                          sujets que je ne
--                                                          suis pas encore
--
-- Idempotent. ASCII pur. A appliquer apres v0.28.0.
-- Pre-requis : table `article_themes` (deja en prod), `follows` (v0.10.0).
-- ============================================================================

set search_path = public;


-- ----------------------------------------------------------------------------
-- 1. Table user_interests
-- ----------------------------------------------------------------------------
create table if not exists user_interests (
  user_id     uuid not null references profiles(id) on delete cascade,
  theme_slug  text not null,
  weight      int  not null default 1,
  created_at  timestamptz not null default now(),
  primary key (user_id, theme_slug),
  constraint user_interests_weight_check check (weight >= 0)
);

create index if not exists user_interests_user_idx
  on user_interests(user_id);

create index if not exists user_interests_theme_idx
  on user_interests(theme_slug);

-- ----------------------------------------------------------------------------
-- 2. RLS
-- ----------------------------------------------------------------------------
alter table user_interests enable row level security;

drop policy if exists "read own interests" on user_interests;
create policy "read own interests"
  on user_interests for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "insert own interests" on user_interests;
create policy "insert own interests"
  on user_interests for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "update own interests" on user_interests;
create policy "update own interests"
  on user_interests for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "delete own interests" on user_interests;
create policy "delete own interests"
  on user_interests for delete to authenticated
  using (user_id = auth.uid());


-- ----------------------------------------------------------------------------
-- 3. RPC : set_user_interests(p_themes text[])
-- ----------------------------------------------------------------------------
-- Remplace les interets du user courant par la liste fournie.
-- - Filtre les slugs invalides (non presents dans article_themes)
-- - Limite a 10 sujets max (anti-spam)
-- Retourne le tableau final des slugs sauvegardes.

create or replace function set_user_interests(p_themes text[])
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_valid  text[];
begin
  if v_uid is null then
    raise exception 'auth required';
  end if;

  if p_themes is null or array_length(p_themes, 1) is null then
    delete from user_interests where user_id = v_uid;
    return array[]::text[];
  end if;

  -- Garde seulement les slugs valides + max 10 + dedoublonne
  begin
    select array_agg(distinct t)
      into v_valid
      from (
        select t
          from unnest(p_themes) as t
          where t in (select slug from article_themes)
          limit 10
      ) s;
  exception when undefined_table then
    -- Pas de table article_themes (cas inattendu) : on accepte tout
    select array_agg(distinct t) into v_valid from unnest(p_themes) as t;
  end;

  v_valid := coalesce(v_valid, array[]::text[]);

  -- Replace (delete + insert)
  delete from user_interests where user_id = v_uid;
  if array_length(v_valid, 1) > 0 then
    insert into user_interests (user_id, theme_slug)
    select v_uid, t from unnest(v_valid) as t
    on conflict do nothing;
  end if;

  return v_valid;
end $$;

grant execute on function set_user_interests(text[]) to authenticated;


-- ----------------------------------------------------------------------------
-- 4. RPC : get_user_interests()
-- ----------------------------------------------------------------------------
create or replace function get_user_interests()
returns text[]
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(array_agg(theme_slug order by weight desc, theme_slug), array[]::text[])
    from user_interests
   where user_id = auth.uid();
$$;

grant execute on function get_user_interests() to authenticated;


-- ----------------------------------------------------------------------------
-- 5. RPC : get_suggested_authors_by_interest(p_limit int default 6)
-- ----------------------------------------------------------------------------
-- Retourne les top contributeurs (par credibility_score) qui ont publie
-- dans au moins un sujet aime par le user courant, et que le user ne suit
-- pas encore. Exclut le user courant lui-meme.

create or replace function get_suggested_authors_by_interest(p_limit int default 6)
returns table (
  id                  uuid,
  username            text,
  avatar_url          text,
  credibility_score   int,
  articles_published  int,
  matching_themes     text[]
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_uid    uuid := auth.uid();
  v_limit  int  := greatest(1, least(coalesce(p_limit, 6), 30));
begin
  if v_uid is null then
    return;
  end if;

  return query
    with my_themes as (
      select theme_slug from user_interests where user_id = v_uid
    ),
    candidate_authors as (
      select a.author_id,
             array_agg(distinct a.theme_slug) filter (
               where a.theme_slug in (select theme_slug from my_themes)
             ) as matching
        from articles a
       where a.status = 'published'
         and a.author_id <> v_uid
         and a.author_id not in (
           select following_id from follows where follower_id = v_uid
         )
         and a.theme_slug in (select theme_slug from my_themes)
       group by a.author_id
    )
    select p.id,
           p.username,
           p.avatar_url,
           coalesce(p.credibility_score, 0)::int,
           coalesce(p.articles_published, 0)::int,
           ca.matching
      from candidate_authors ca
      join profiles p on p.id = ca.author_id
     where coalesce(p.articles_published, 0) > 0
     order by coalesce(p.credibility_score, 0) desc,
              coalesce(p.articles_published, 0) desc
     limit v_limit;
exception
  when undefined_table then
    return; -- Pas de follows ou user_interests -> rien a suggerer
end $$;

grant execute on function get_suggested_authors_by_interest(int) to authenticated;


-- ============================================================================
-- Smoke tests :
--   select set_user_interests(array['politique','culture','economie']);
--   select get_user_interests();
--   select * from get_suggested_authors_by_interest(5);
-- ============================================================================
-- Fin v0.29.0
-- ============================================================================
