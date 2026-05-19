-- ============================================================================
-- Avis Base -- v0.24.0 -- Liste d'attente pre-lancement (waitlist)
-- ============================================================================
--
-- Permet de collecter les emails des futurs beta-testeurs et inscrits a
-- l'attente du lancement v1.0.0.
--
-- 1 table `waitlist` + 1 RPC publique `submit_waitlist` accessible aux
-- visiteurs non authentifies (anon).
--
-- Anti-abus :
--   - UNIQUE(email) -> pas de doublon
--   - Rate-limit applicatif : on n'expose pas le compteur (silencieux pour
--     l'utilisateur en cas de re-soumission)
--
-- Lecture : reservee aux admins/superadmins via RLS.
--
-- Idempotent. ASCII pur. A appliquer apres v0.22.1.
-- ============================================================================

set search_path = public;


-- ----------------------------------------------------------------------------
-- 1. Table waitlist
-- ----------------------------------------------------------------------------

create table if not exists waitlist (
  id          uuid primary key default gen_random_uuid(),
  email       text not null,
  name        text,
  kind        text not null default 'launch'
                check (kind in ('launch','beta')),
  source      text,
  user_id     uuid references profiles(id) on delete set null,
  ip_hash     text,
  created_at  timestamptz not null default now(),
  notified_at timestamptz
);

-- Email unique (case-insensitive)
create unique index if not exists waitlist_email_unique
  on waitlist (lower(email));

create index if not exists waitlist_created_idx
  on waitlist(created_at desc);

create index if not exists waitlist_kind_idx
  on waitlist(kind, created_at desc);

alter table waitlist enable row level security;


-- ----------------------------------------------------------------------------
-- 2. RLS : lecture admin/superadmin uniquement, ecriture via RPC
-- ----------------------------------------------------------------------------

drop policy if exists "waitlist_read_admin" on waitlist;
create policy "waitlist_read_admin" on waitlist
  for select using (
    exists (
      select 1 from profiles p
      where p.id = auth.uid()
        and p.role in ('admin','superadmin')
    )
  );

-- Pas de policy INSERT directe : la RPC SECURITY DEFINER fait le boulot.


-- ----------------------------------------------------------------------------
-- 3. RPC publique : submit_waitlist(email, kind, source, name)
-- ----------------------------------------------------------------------------
-- Insertion idempotente :
--   - Si l'email existe deja avec le meme kind, on ne fait rien (no-op silencieux)
--   - Si l'email existe avec un autre kind, on update kind (la nouvelle
--     soumission gagne, ex : un user beta peut basculer en launch)
-- Retour : { id, status: 'created'|'updated'|'already' }
--
-- Validation cote serveur :
--   - format email basique (lower + check pattern)
--   - longueur max
--   - kind dans ('launch','beta')

create or replace function submit_waitlist(
  p_email   text,
  p_kind    text default 'launch',
  p_source  text default null,
  p_name    text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email_norm    text;
  v_existing      record;
  v_id            uuid;
  v_user_id       uuid := auth.uid();
begin
  -- Normalisation + validation
  v_email_norm := lower(trim(coalesce(p_email, '')));
  if length(v_email_norm) < 5 or length(v_email_norm) > 254 then
    raise exception 'invalid_email';
  end if;
  if v_email_norm !~ '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$' then
    raise exception 'invalid_email';
  end if;
  if p_kind not in ('launch','beta') then
    raise exception 'invalid_kind';
  end if;
  if p_name is not null and length(p_name) > 80 then
    p_name := left(p_name, 80);
  end if;
  if p_source is not null and length(p_source) > 80 then
    p_source := left(p_source, 80);
  end if;

  -- Existe deja ?
  select id, kind into v_existing
  from waitlist
  where lower(email) = v_email_norm
  limit 1;

  if v_existing.id is not null then
    if v_existing.kind = p_kind then
      return jsonb_build_object('id', v_existing.id, 'status', 'already');
    end if;
    -- Switch de kind (ex : passe de 'launch' a 'beta')
    update waitlist
      set kind = p_kind,
          name = coalesce(p_name, name),
          source = coalesce(p_source, source),
          user_id = coalesce(v_user_id, user_id)
      where id = v_existing.id;
    return jsonb_build_object('id', v_existing.id, 'status', 'updated');
  end if;

  -- Nouvelle inscription
  insert into waitlist (email, name, kind, source, user_id)
  values (v_email_norm, p_name, p_kind, p_source, v_user_id)
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'status', 'created');
end $$;

grant execute on function submit_waitlist(text, text, text, text) to anon, authenticated;


-- ----------------------------------------------------------------------------
-- 4. Vue agregee privee pour export admin (compte par kind + total)
-- ----------------------------------------------------------------------------

create or replace view waitlist_summary
with (security_invoker = true) as
select
  kind,
  count(*)::int                                         as total,
  count(*) filter (where notified_at is null)::int      as pending,
  count(*) filter (where notified_at is not null)::int  as notified,
  min(created_at)                                        as first_signup_at,
  max(created_at)                                        as last_signup_at
from waitlist
group by kind;

comment on view waitlist_summary is
  'Agregat par kind (launch/beta). Visible uniquement par admin (RLS via waitlist).';


-- ============================================================================
-- Smoke tests :
--   -- En anon (Supabase JS) :
--   select submit_waitlist('test@example.com', 'beta', 'a-propos-modal', 'Test User');
--   -- Devrait retourner { id: '...', status: 'created' }
--
--   -- Re-test :
--   select submit_waitlist('TEST@example.com', 'beta');
--   -- Devrait retourner { id: '...', status: 'already' }
--
--   -- En admin :
--   select * from waitlist_summary;
-- ============================================================================
-- Fin v0.24.0
-- ============================================================================
