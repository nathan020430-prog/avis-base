-- ============================================================================
-- Avis Base -- v0.25.1 -- Publication multi-plateforme des clips
-- ============================================================================
--
-- Permet de tracker la publication d'un meme clip sur plusieurs reseaux
-- sociaux : TikTok, Twitter/X, Instagram (+ extensible).
--
-- Strategie : nouvelle table `clip_publications` (1 ligne par couple
-- (clip_id, platform)). Conserve la compat avec `clips.published_tiktok_url`
-- via une vue / un trigger pour ne pas casser l'UI existante.
--
-- Idempotent. ASCII pur. A appliquer apres v0.24.0.
-- ============================================================================

set search_path = public;


-- ----------------------------------------------------------------------------
-- 1. Table `clip_publications`
-- ----------------------------------------------------------------------------

create table if not exists clip_publications (
  id            uuid primary key default gen_random_uuid(),
  clip_id       uuid not null references clips(id) on delete cascade,
  platform      text not null
                  check (platform in ('tiktok','twitter','instagram','linkedin','facebook','snapchat','youtube_shorts')),
  url           text,
  status        text not null default 'planned'
                  check (status in ('planned','published','archived','removed')),
  caption       text,            -- caption finale postee (peut differ par plateforme)
  stats         jsonb not null default '{}'::jsonb,
                  -- ex : {"views": 1234, "likes": 56, "comments": 7, "shares": 12, "saves": 3}
  published_at  timestamptz,
  published_by  uuid references profiles(id) on delete set null,
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (clip_id, platform)
);

create index if not exists clip_publications_clip_idx     on clip_publications(clip_id);
create index if not exists clip_publications_platform_idx on clip_publications(platform);
create index if not exists clip_publications_published_idx
  on clip_publications(published_at desc)
  where status = 'published';


-- ----------------------------------------------------------------------------
-- 2. RLS
-- ----------------------------------------------------------------------------

alter table clip_publications enable row level security;

-- Lecture publique : on veut que tout le monde puisse voir oU un clip a ete publie
drop policy if exists "clip_publications_select_public" on clip_publications;
create policy "clip_publications_select_public" on clip_publications
  for select using (
    status = 'published'
  );

-- Lecture pour admins (toutes lignes meme planned)
drop policy if exists "clip_publications_select_admin" on clip_publications;
create policy "clip_publications_select_admin" on clip_publications
  for select using (
    exists (
      select 1 from profiles p
      where p.id = auth.uid()
        and p.role in ('admin','superadmin')
    )
  );

-- Ecritures : reservees aux admins via RPC ou client (RLS direct)
drop policy if exists "clip_publications_insert_admin" on clip_publications;
create policy "clip_publications_insert_admin" on clip_publications
  for insert with check (
    exists (
      select 1 from profiles p
      where p.id = auth.uid()
        and p.role in ('admin','superadmin')
    )
  );

drop policy if exists "clip_publications_update_admin" on clip_publications;
create policy "clip_publications_update_admin" on clip_publications
  for update using (
    exists (
      select 1 from profiles p
      where p.id = auth.uid()
        and p.role in ('admin','superadmin')
    )
  );

drop policy if exists "clip_publications_delete_admin" on clip_publications;
create policy "clip_publications_delete_admin" on clip_publications
  for delete using (
    exists (
      select 1 from profiles p
      where p.id = auth.uid()
        and p.role in ('admin','superadmin')
    )
  );


-- ----------------------------------------------------------------------------
-- 3. Trigger updated_at
-- ----------------------------------------------------------------------------

create or replace function _clip_publications_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_clip_publications_updated_at on clip_publications;
create trigger trg_clip_publications_updated_at
  before update on clip_publications
  for each row execute function _clip_publications_set_updated_at();


-- ----------------------------------------------------------------------------
-- 4. Trigger : quand au moins 1 publication est en status='published',
--    bascule clips.status='published' (si pas deja) + setup published_at +
--    miroir sur published_tiktok_url pour compat.
-- ----------------------------------------------------------------------------

create or replace function _clip_publication_sync_clip_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_clip clips%rowtype;
  v_pub_count int;
  v_tiktok_url text;
begin
  -- On regarde l'etat actuel du clip
  select * into v_clip from clips where id = coalesce(new.clip_id, old.clip_id);
  if not found then return coalesce(new, old); end if;

  -- Compte les publications actives
  select count(*) into v_pub_count
  from clip_publications
  where clip_id = v_clip.id and status = 'published';

  -- Recupere l'URL TikTok la plus recente pour la compat
  select url into v_tiktok_url
  from clip_publications
  where clip_id = v_clip.id and platform = 'tiktok' and status = 'published'
  order by published_at desc nulls last
  limit 1;

  if v_pub_count > 0 then
    -- Au moins 1 plateforme publiee -> status = 'published'
    update clips
      set status = case when status in ('draft','review','approved','needs_changes','scheduled')
                       then 'published'
                       else status
                   end,
          published_at = coalesce(published_at, now()),
          published_tiktok_url = coalesce(v_tiktok_url, published_tiktok_url)
      where id = v_clip.id;
  else
    -- Plus aucune publication -> on ne touche pas (l'admin peut avoir intentionnellement)
    null;
  end if;

  return coalesce(new, old);
end $$;

drop trigger if exists trg_clip_publication_sync_status on clip_publications;
create trigger trg_clip_publication_sync_status
  after insert or update of status, url, published_at or delete on clip_publications
  for each row execute function _clip_publication_sync_clip_status();


-- ----------------------------------------------------------------------------
-- 5. Vue agreggee : un row par clip avec liste des publications
-- ----------------------------------------------------------------------------

create or replace view clip_publications_by_clip
with (security_invoker = true) as
select
  c.id   as clip_id,
  count(*) filter (where cp.status = 'published')           as published_count,
  count(*) filter (where cp.status = 'planned')             as planned_count,
  array_agg(cp.platform order by cp.platform)
    filter (where cp.status = 'published')                  as published_platforms,
  array_agg(cp.platform order by cp.platform)
    filter (where cp.status = 'planned')                    as planned_platforms,
  (
    select jsonb_object_agg(p.platform, jsonb_build_object(
      'url',           p.url,
      'status',        p.status,
      'caption',       p.caption,
      'stats',         p.stats,
      'published_at',  p.published_at
    ))
    from clip_publications p
    where p.clip_id = c.id
  ) as publications_json
from clips c
left join clip_publications cp on cp.clip_id = c.id
group by c.id;

comment on view clip_publications_by_clip is
  'Agregat par clip : compteurs + JSON map des publications par plateforme.';


-- ----------------------------------------------------------------------------
-- 6. Backfill : si des clips existent deja en status='published' avec
--    published_tiktok_url renseigne, on cree la ligne TikTok correspondante.
-- ----------------------------------------------------------------------------

do $$
begin
  insert into clip_publications (
    clip_id, platform, url, status, stats, published_at
  )
  select
    c.id,
    'tiktok',
    c.published_tiktok_url,
    'published',
    jsonb_strip_nulls(jsonb_build_object(
      'views',    nullif(c.tiktok_views, 0),
      'likes',    nullif(c.tiktok_likes, 0),
      'comments', nullif(c.tiktok_comments, 0),
      'shares',   nullif(c.tiktok_shares, 0)
    )),
    c.published_at
  from clips c
  where c.status = 'published'
    and c.published_tiktok_url is not null
    and not exists (
      select 1 from clip_publications cp
      where cp.clip_id = c.id and cp.platform = 'tiktok'
    );
exception when others then
  raise notice 'Backfill TikTok clip_publications skipped : %', SQLERRM;
end $$;


-- ============================================================================
-- Smoke tests :
--   -- En admin :
--   insert into clip_publications (clip_id, platform, url, status, caption)
--   values ('<some-clip-id>', 'twitter', 'https://x.com/...', 'published', 'caption');
--   select * from clip_publications_by_clip where clip_id = '<id>';
--   select status, published_tiktok_url from clips where id = '<id>';
-- ============================================================================
-- Fin v0.25.1
-- ============================================================================
