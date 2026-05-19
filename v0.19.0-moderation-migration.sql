-- ============================================================================
-- Avis Base -- v0.19.0 -- Moderation avancee + peer review + masquage auto
-- ============================================================================
--
-- Ajoute :
--   1. Extension de la table `reports` : reason_code, severity, details, unique
--      composite (reporter, target_type, target_id).
--   2. Colonnes `moderation_state` et `reports_count` sur `articles` et `clips`.
--   3. Table `moderation_actions` (journal des actions mod / admin).
--   4. Table `peer_reviews` (votes communautaires sur les signalements).
--   5. RPCs : submit_report, submit_peer_review, mod_apply_action,
--             get_moderation_queue, get_user_reports_summary,
--             auto_hide_if_threshold (private helper).
--   6. RLS sur les nouvelles tables.
--
-- Idempotent. ASCII pur. A appliquer APRES v0.18.0-credibility-migration.sql.
-- ============================================================================

set search_path = public;


-- ----------------------------------------------------------------------------
-- 1. Extension de la table `reports`
-- ----------------------------------------------------------------------------

-- Defensif : selon l'age de la base, `target_type` / `target_id` peuvent ne pas
-- exister (la version originale de `reports` ne gerait que `comment_id`).
-- On les cree d'abord si necessaire avant tout autre ADD COLUMN qui en depend.
alter table reports add column if not exists target_type text;
alter table reports add column if not exists target_id   uuid;

alter table reports add column if not exists reason_code text;
alter table reports add column if not exists severity   text not null default 'normal';
alter table reports add column if not exists details    text;

-- Codes de raison standardises
do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'reports_reason_code_check'
  ) then
    alter table reports add constraint reports_reason_code_check
      check (reason_code is null or reason_code in (
        'misinformation','unsourced','harassment','spam',
        'off_topic','copyright','illegal','other'
      ));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'reports_severity_check'
  ) then
    alter table reports add constraint reports_severity_check
      check (severity in ('low','normal','high'));
  end if;
end $$;

-- Unique composite (reporter, target_type, target_id) -- partiel : seulement si target defini.
-- L'ancien UNIQUE(reporter_id, comment_id) reste pour la compat (NULL non bloquant).
create unique index if not exists reports_reporter_target_unique_idx
  on reports(reporter_id, target_type, target_id)
  where target_type is not null and target_id is not null;

-- Index utiles pour le dashboard mod
create index if not exists reports_pending_target_idx
  on reports(target_type, target_id)
  where status = 'pending';

create index if not exists reports_pending_created_idx
  on reports(created_at desc)
  where status = 'pending';


-- ----------------------------------------------------------------------------
-- 2. Colonnes `moderation_state` sur articles et clips
-- ----------------------------------------------------------------------------

-- moderation_state :
--   'visible'      -> public normal
--   'hidden_auto'  -> masque automatiquement par le seuil de signalements
--   'hidden_mod'   -> masque par un moderateur / admin
--   'reviewed_ok'  -> revue passee, public normal (etat post-peer-review valide)

alter table articles add column if not exists moderation_state     text not null default 'visible';
alter table articles add column if not exists moderation_hidden_at timestamptz;
alter table articles add column if not exists reports_count        int  not null default 0;

alter table clips add column if not exists moderation_state     text not null default 'visible';
alter table clips add column if not exists moderation_hidden_at timestamptz;
alter table clips add column if not exists reports_count        int  not null default 0;

do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'articles_moderation_state_check'
  ) then
    alter table articles add constraint articles_moderation_state_check
      check (moderation_state in ('visible','hidden_auto','hidden_mod','reviewed_ok'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'clips_moderation_state_check'
  ) then
    alter table clips add constraint clips_moderation_state_check
      check (moderation_state in ('visible','hidden_auto','hidden_mod','reviewed_ok'));
  end if;
end $$;

create index if not exists articles_moderation_state_idx
  on articles(moderation_state)
  where moderation_state <> 'visible';

create index if not exists clips_moderation_state_idx
  on clips(moderation_state)
  where moderation_state <> 'visible';


-- ----------------------------------------------------------------------------
-- 3. Table `moderation_actions` (journal)
-- ----------------------------------------------------------------------------

create table if not exists moderation_actions (
  id                 uuid primary key default gen_random_uuid(),
  moderator_id       uuid not null references profiles(id) on delete cascade,
  target_type        text not null check (target_type in ('article','clip','comment','profile')),
  target_id          uuid not null,
  action             text not null check (action in (
                       'hide','unhide','delete','warn','ban','unban',
                       'dismiss_reports','resolve_reports'
                     )),
  reason             text,
  related_report_id  uuid references reports(id) on delete set null,
  created_at         timestamptz not null default now()
);

create index if not exists moderation_actions_target_idx on moderation_actions(target_type, target_id, created_at desc);
create index if not exists moderation_actions_moderator_idx on moderation_actions(moderator_id, created_at desc);

alter table moderation_actions enable row level security;

drop policy if exists "mod_actions_select_mod_or_admin" on moderation_actions;
create policy "mod_actions_select_mod_or_admin" on moderation_actions
  for select using (
    exists (
      select 1 from profiles p
      where p.id = auth.uid()
        and (p.role in ('admin','superadmin') or coalesce(p.credibility_score,0) >= 75)
    )
  );

-- INSERT reserve aux RPCs SECURITY DEFINER (mod_apply_action). Aucun acces direct.


-- ----------------------------------------------------------------------------
-- 4. Table `peer_reviews`
-- ----------------------------------------------------------------------------

create table if not exists peer_reviews (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references reports(id) on delete cascade,
  reviewer_id uuid not null references profiles(id) on delete cascade,
  verdict     text not null check (verdict in ('valid','invalid','skip')),
  created_at  timestamptz not null default now(),
  unique (report_id, reviewer_id)
);

create index if not exists peer_reviews_report_idx on peer_reviews(report_id);
create index if not exists peer_reviews_reviewer_idx on peer_reviews(reviewer_id, created_at desc);

alter table peer_reviews enable row level security;

drop policy if exists "peer_reviews_select_own_or_mod" on peer_reviews;
create policy "peer_reviews_select_own_or_mod" on peer_reviews
  for select using (
    reviewer_id = auth.uid()
    or exists (
      select 1 from profiles p
      where p.id = auth.uid()
        and (p.role in ('admin','superadmin') or coalesce(p.credibility_score,0) >= 75)
    )
  );

-- INSERT reserve a la RPC submit_peer_review (SECURITY DEFINER)


-- ----------------------------------------------------------------------------
-- 5. Helper interne : auto_hide_if_threshold
-- ----------------------------------------------------------------------------
-- Compte les signalements pending DISTINCTS (par reporter_id) sur la cible.
-- Si severite haute presente, seuil = 1 (masquage immediat).
-- Sinon, seuil = 3 signalements distincts.
-- Met aussi a jour `reports_count` meme sans masquage.

create or replace function auto_hide_if_threshold(p_target_type text, p_target_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_threshold   int := 3;
  v_count       int;
  v_high_count  int;
  v_should_hide boolean;
begin
  if p_target_type is null or p_target_id is null then
    return;
  end if;

  select count(distinct reporter_id),
         count(*) filter (where severity = 'high')
    into v_count, v_high_count
  from reports
  where target_type = p_target_type
    and target_id = p_target_id
    and status = 'pending';

  v_should_hide := (v_high_count >= 1) or (v_count >= v_threshold);

  if p_target_type = 'article' then
    if v_should_hide then
      update articles
        set moderation_state     = 'hidden_auto',
            moderation_hidden_at = now(),
            reports_count        = v_count
        where id = p_target_id
          and moderation_state = 'visible';
    end if;
    update articles set reports_count = v_count where id = p_target_id;
  elsif p_target_type = 'clip' then
    if v_should_hide then
      update clips
        set moderation_state     = 'hidden_auto',
            moderation_hidden_at = now(),
            reports_count        = v_count
        where id = p_target_id
          and moderation_state = 'visible';
    end if;
    update clips set reports_count = v_count where id = p_target_id;
  end if;
end $$;

revoke all on function auto_hide_if_threshold(text, uuid) from public, authenticated, anon;


-- ----------------------------------------------------------------------------
-- 6. RPC publique : submit_report
-- ----------------------------------------------------------------------------
-- Cree un signalement, deduit la severite, puis declenche le masquage auto.
-- Retour :
--   { report_id, hidden, already_reported }

create or replace function submit_report(
  p_target_type text,
  p_target_id   uuid,
  p_reason_code text,
  p_details     text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid         uuid := auth.uid();
  v_username    text;
  v_severity    text;
  v_id          uuid;
  v_state       text;
  v_already     boolean := false;
begin
  if v_uid is null then
    raise exception 'auth_required';
  end if;
  if p_target_id is null then
    raise exception 'invalid_target_id';
  end if;
  if p_target_type not in ('article','clip','comment','profile') then
    raise exception 'invalid_target_type';
  end if;
  if p_reason_code is null or p_reason_code not in (
    'misinformation','unsourced','harassment','spam','off_topic','copyright','illegal','other'
  ) then
    raise exception 'invalid_reason_code';
  end if;

  v_severity := case
    when p_reason_code in ('harassment','illegal') then 'high'
    when p_reason_code in ('spam','copyright')    then 'normal'
    else 'normal'
  end;

  select username into v_username from profiles where id = v_uid;

  insert into reports (
    reporter_id, reporter_username, target_type, target_id,
    reason, reason_code, details, severity, status
  ) values (
    v_uid, v_username, p_target_type, p_target_id,
    coalesce(left(p_details, 500), p_reason_code),
    p_reason_code,
    nullif(left(coalesce(p_details, ''), 500), ''),
    v_severity,
    'pending'
  )
  on conflict (reporter_id, target_type, target_id) where target_type is not null and target_id is not null
  do nothing
  returning id into v_id;

  if v_id is null then
    v_already := true;
    select id into v_id
    from reports
    where reporter_id = v_uid
      and target_type = p_target_type
      and target_id   = p_target_id;
  else
    perform auto_hide_if_threshold(p_target_type, p_target_id);
  end if;

  -- Etat actuel de la cible (pour informer l'UI)
  if p_target_type = 'article' then
    select moderation_state into v_state from articles where id = p_target_id;
  elsif p_target_type = 'clip' then
    select moderation_state into v_state from clips where id = p_target_id;
  else
    v_state := 'visible';
  end if;

  return jsonb_build_object(
    'report_id',       v_id,
    'already_reported', v_already,
    'moderation_state', coalesce(v_state, 'visible')
  );
end $$;

grant execute on function submit_report(text, uuid, text, text) to authenticated;


-- ----------------------------------------------------------------------------
-- 7. RPC publique : get_moderation_queue
-- ----------------------------------------------------------------------------
-- Renvoie la file d'attente des signalements pending, agregee par cible.
-- Accessible aux moderateurs (role admin/superadmin OU credibility_score >= 75).

create or replace function get_moderation_queue()
returns table (
  target_type         text,
  target_id           uuid,
  reports_count       bigint,
  high_severity_count bigint,
  first_reported_at   timestamptz,
  last_reported_at    timestamptz,
  reason_codes        text[],
  report_ids          uuid[],
  preview             text,
  author_id           uuid,
  author_username     text,
  moderation_state    text
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_uid     uuid := auth.uid();
  v_is_mod boolean;
begin
  if v_uid is null then
    raise exception 'auth_required';
  end if;

  select (p.role in ('admin','superadmin')) or coalesce(p.credibility_score,0) >= 75
    into v_is_mod
  from profiles p
  where p.id = v_uid;

  if not coalesce(v_is_mod, false) then
    raise exception 'forbidden_mod';
  end if;

  return query
  select
    r.target_type,
    r.target_id,
    count(*)                                       as reports_count,
    count(*) filter (where r.severity='high')      as high_severity_count,
    min(r.created_at)                              as first_reported_at,
    max(r.created_at)                              as last_reported_at,
    array_agg(distinct coalesce(r.reason_code,'other'))      as reason_codes,
    array_agg(r.id)                                          as report_ids,
    case r.target_type
      when 'article' then (select left(coalesce(a.title,''), 120) from articles a where a.id = r.target_id)
      when 'clip'    then (select left(coalesce(c.hook,''),  120) from clips    c where c.id = r.target_id)
      when 'comment' then (select left(coalesce(cm.body,''), 120) from comments cm where cm.id = r.target_id)
      else null
    end                                            as preview,
    case r.target_type
      when 'article' then (select a.author_id from articles a where a.id = r.target_id)
      when 'clip'    then (select c.author_id from clips    c where c.id = r.target_id)
      when 'comment' then (select cm.author_id from comments cm where cm.id = r.target_id)
      else null
    end                                            as author_id,
    case r.target_type
      when 'article' then (select pa.username from articles a join profiles pa on pa.id = a.author_id where a.id = r.target_id)
      when 'clip'    then (select pc.username from clips c    join profiles pc on pc.id = c.author_id where c.id = r.target_id)
      when 'comment' then (select pm.username from comments cm join profiles pm on pm.id = cm.author_id where cm.id = r.target_id)
      else null
    end                                            as author_username,
    case r.target_type
      when 'article' then (select a.moderation_state from articles a where a.id = r.target_id)
      when 'clip'    then (select c.moderation_state from clips    c where c.id = r.target_id)
      else 'visible'
    end                                            as moderation_state
  from reports r
  where r.status = 'pending'
    and r.target_type is not null
    and r.target_id is not null
  group by r.target_type, r.target_id
  order by max(r.created_at) desc;
end $$;

grant execute on function get_moderation_queue() to authenticated;


-- ----------------------------------------------------------------------------
-- 8. RPC publique : submit_peer_review
-- ----------------------------------------------------------------------------
-- Un peer reviewer (credibility_score >= 50, non-auteur, non-reporter) vote
-- sur un signalement. Quorum 3 -> decision automatique :
--   3 'valid'   -> report resolved + cible masquee
--   3 'invalid' -> report dismissed + cible restauree (si masquage auto)
-- Retour : { valid_count, invalid_count, quorum, decision, my_verdict }

create or replace function submit_peer_review(
  p_report_id uuid,
  p_verdict   text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid           uuid := auth.uid();
  v_score         int;
  v_min_score     int := 50;
  v_quorum        int := 3;
  v_valid         int;
  v_invalid       int;
  v_report        record;
  v_decision      text := null;
  v_content_author uuid;
begin
  if v_uid is null then raise exception 'auth_required'; end if;
  if p_verdict not in ('valid','invalid','skip') then raise exception 'invalid_verdict'; end if;

  select coalesce(credibility_score,0) into v_score from profiles where id = v_uid;
  if v_score < v_min_score then
    raise exception 'forbidden_score:%', v_score;
  end if;

  select id, target_type, target_id, reporter_id, status
    into v_report
  from reports where id = p_report_id;

  if v_report.id is null then
    raise exception 'report_not_found';
  end if;
  if v_report.status <> 'pending' then
    raise exception 'report_already_resolved';
  end if;
  if v_report.reporter_id = v_uid then
    raise exception 'forbidden_reporter';
  end if;

  -- Auteur de la cible : interdit de peer-reviewer un signalement contre soi
  v_content_author := null;
  if v_report.target_type = 'article' then
    select author_id into v_content_author from articles where id = v_report.target_id;
  elsif v_report.target_type = 'clip' then
    select author_id into v_content_author from clips where id = v_report.target_id;
  elsif v_report.target_type = 'comment' then
    select author_id into v_content_author from comments where id = v_report.target_id;
  end if;

  if v_content_author = v_uid then
    raise exception 'forbidden_self';
  end if;

  insert into peer_reviews (report_id, reviewer_id, verdict)
  values (p_report_id, v_uid, p_verdict)
  on conflict (report_id, reviewer_id)
    do update set verdict = excluded.verdict, created_at = now();

  select count(*) filter (where verdict='valid'),
         count(*) filter (where verdict='invalid')
    into v_valid, v_invalid
  from peer_reviews
  where report_id = p_report_id;

  if v_valid >= v_quorum then
    update reports
      set status = 'resolved', validated = true, reviewed_at = now()
      where id = p_report_id and status = 'pending';

    if v_report.target_type = 'article' then
      update articles
        set moderation_state = 'hidden_mod', moderation_hidden_at = now()
        where id = v_report.target_id;
    elsif v_report.target_type = 'clip' then
      update clips
        set moderation_state = 'hidden_mod', moderation_hidden_at = now()
        where id = v_report.target_id;
    end if;

    -- Penalite de credibilite pour l'auteur (compteur)
    if v_content_author is not null then
      update profiles
        set validated_reports = validated_reports + 1
        where id = v_content_author;
    end if;

    v_decision := 'resolved';

  elsif v_invalid >= v_quorum then
    update reports
      set status = 'dismissed', validated = false, reviewed_at = now()
      where id = p_report_id and status = 'pending';

    -- Restaurer la visibilite si masquage auto + plus d'autres reports pending
    if not exists (
      select 1 from reports r2
      where r2.target_type = v_report.target_type
        and r2.target_id   = v_report.target_id
        and r2.status      = 'pending'
        and r2.id          <> p_report_id
    ) then
      if v_report.target_type = 'article' then
        update articles
          set moderation_state = 'reviewed_ok', moderation_hidden_at = null
          where id = v_report.target_id and moderation_state = 'hidden_auto';
      elsif v_report.target_type = 'clip' then
        update clips
          set moderation_state = 'reviewed_ok', moderation_hidden_at = null
          where id = v_report.target_id and moderation_state = 'hidden_auto';
      end if;
    end if;

    v_decision := 'dismissed';
  end if;

  return jsonb_build_object(
    'valid_count',   v_valid,
    'invalid_count', v_invalid,
    'quorum',        v_quorum,
    'decision',      v_decision,
    'my_verdict',    p_verdict
  );
end $$;

grant execute on function submit_peer_review(uuid, text) to authenticated;


-- ----------------------------------------------------------------------------
-- 9. RPC publique : get_peer_review_queue
-- ----------------------------------------------------------------------------
-- Liste les signalements en attente sur lesquels le user CONNECTE peut voter.
-- Exclut : ses propres signalements, ses propres contenus, ceux deja votes.

create or replace function get_peer_review_queue(p_limit int default 20)
returns table (
  report_id        uuid,
  target_type      text,
  target_id        uuid,
  reason_code      text,
  severity         text,
  details          text,
  created_at       timestamptz,
  preview          text,
  author_username  text,
  current_votes    jsonb
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_uid    uuid := auth.uid();
  v_score  int;
  v_min    int := 50;
begin
  if v_uid is null then raise exception 'auth_required'; end if;

  select coalesce(credibility_score,0) into v_score from profiles where id = v_uid;
  if v_score < v_min then
    raise exception 'forbidden_score:%', v_score;
  end if;

  return query
  select
    r.id,
    r.target_type,
    r.target_id,
    r.reason_code,
    r.severity,
    r.details,
    r.created_at,
    case r.target_type
      when 'article' then (select left(coalesce(a.title,''), 160) from articles a where a.id = r.target_id)
      when 'clip'    then (select left(coalesce(c.hook,''),  160) from clips    c where c.id = r.target_id)
      when 'comment' then (select left(coalesce(cm.body,''), 160) from comments cm where cm.id = r.target_id)
      else null
    end as preview,
    case r.target_type
      when 'article' then (select pa.username from articles a join profiles pa on pa.id = a.author_id where a.id = r.target_id)
      when 'clip'    then (select pc.username from clips    c join profiles pc on pc.id = c.author_id where c.id = r.target_id)
      when 'comment' then (select pm.username from comments cm join profiles pm on pm.id = cm.author_id where cm.id = r.target_id)
      else null
    end as author_username,
    (
      select jsonb_build_object(
        'valid',   coalesce(count(*) filter (where pr.verdict='valid'),   0),
        'invalid', coalesce(count(*) filter (where pr.verdict='invalid'), 0)
      )
      from peer_reviews pr
      where pr.report_id = r.id
    ) as current_votes
  from reports r
  where r.status = 'pending'
    and r.reporter_id <> v_uid
    and r.target_type is not null
    and r.target_id is not null
    and not exists (
      select 1 from peer_reviews pr2
      where pr2.report_id = r.id and pr2.reviewer_id = v_uid
    )
    and not exists (
      select 1 from articles a where a.id = r.target_id and a.author_id = v_uid
      union all
      select 1 from clips    c where c.id = r.target_id and c.author_id = v_uid
      union all
      select 1 from comments cm where cm.id = r.target_id and cm.author_id = v_uid
    )
  order by r.severity desc, r.created_at asc
  limit greatest(1, least(coalesce(p_limit, 20), 100));
end $$;

grant execute on function get_peer_review_queue(int) to authenticated;


-- ----------------------------------------------------------------------------
-- 10. RPC publique : mod_apply_action
-- ----------------------------------------------------------------------------
-- Action manuelle d'un moderateur (admin/superadmin OU credibility >= 75).
-- Actions : hide / unhide / dismiss_reports / resolve_reports
-- Journalise dans moderation_actions.

create or replace function mod_apply_action(
  p_target_type       text,
  p_target_id         uuid,
  p_action            text,
  p_reason            text default null,
  p_related_report_id uuid default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  v_score    int;
  v_author   uuid;
begin
  if v_uid is null then raise exception 'auth_required'; end if;

  select (role in ('admin','superadmin')), coalesce(credibility_score,0)
    into v_is_admin, v_score
  from profiles where id = v_uid;

  if not coalesce(v_is_admin, false) and coalesce(v_score, 0) < 75 then
    raise exception 'forbidden_mod';
  end if;

  if p_target_type not in ('article','clip','comment','profile') then
    raise exception 'invalid_target_type';
  end if;

  if p_action not in ('hide','unhide','dismiss_reports','resolve_reports') then
    raise exception 'invalid_action';
  end if;

  -- Applique l'effet
  if p_action = 'hide' then
    if p_target_type = 'article' then
      update articles set moderation_state='hidden_mod', moderation_hidden_at=now() where id=p_target_id;
    elsif p_target_type = 'clip' then
      update clips set moderation_state='hidden_mod', moderation_hidden_at=now() where id=p_target_id;
    end if;
  elsif p_action = 'unhide' then
    if p_target_type = 'article' then
      update articles set moderation_state='reviewed_ok', moderation_hidden_at=null where id=p_target_id;
    elsif p_target_type = 'clip' then
      update clips set moderation_state='reviewed_ok', moderation_hidden_at=null where id=p_target_id;
    end if;
  elsif p_action = 'dismiss_reports' then
    update reports
      set status='dismissed', reviewed_by=v_uid, reviewed_at=now()
      where target_type=p_target_type and target_id=p_target_id and status='pending';
    -- Restaure si masquage auto
    if p_target_type = 'article' then
      update articles set moderation_state='reviewed_ok', moderation_hidden_at=null
        where id=p_target_id and moderation_state='hidden_auto';
    elsif p_target_type = 'clip' then
      update clips set moderation_state='reviewed_ok', moderation_hidden_at=null
        where id=p_target_id and moderation_state='hidden_auto';
    end if;
  elsif p_action = 'resolve_reports' then
    update reports
      set status='resolved', validated=true, reviewed_by=v_uid, reviewed_at=now()
      where target_type=p_target_type and target_id=p_target_id and status='pending';

    -- Penalite credibilite : +1 validated_reports a l'auteur
    if p_target_type = 'article' then
      select author_id into v_author from articles where id=p_target_id;
    elsif p_target_type = 'clip' then
      select author_id into v_author from clips where id=p_target_id;
    elsif p_target_type = 'comment' then
      select author_id into v_author from comments where id=p_target_id;
    end if;
    if v_author is not null then
      update profiles set validated_reports = validated_reports + 1 where id = v_author;
    end if;
  end if;

  insert into moderation_actions (moderator_id, target_type, target_id, action, reason, related_report_id)
  values (v_uid, p_target_type, p_target_id, p_action, left(coalesce(p_reason,''), 500), p_related_report_id);

  return true;
end $$;

grant execute on function mod_apply_action(text, uuid, text, text, uuid) to authenticated;


-- ----------------------------------------------------------------------------
-- 11. RPC publique : get_user_moderation_summary
-- ----------------------------------------------------------------------------
-- Renvoie l'etat de moderation des contenus du user CONNECTE
-- (ce qui est masque chez lui, et pourquoi). Utile pour la page profil.

create or replace function get_user_moderation_summary()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_uid uuid := auth.uid();
  v_articles_hidden int;
  v_clips_hidden int;
  v_pending_against int;
begin
  if v_uid is null then raise exception 'auth_required'; end if;

  select count(*) into v_articles_hidden from articles
    where author_id = v_uid and moderation_state in ('hidden_auto','hidden_mod');

  select count(*) into v_clips_hidden from clips
    where author_id = v_uid and moderation_state in ('hidden_auto','hidden_mod');

  select count(*) into v_pending_against from reports r
    where r.status = 'pending' and r.target_type in ('article','clip','comment','profile')
      and (
        (r.target_type='article' and r.target_id in (select id from articles where author_id=v_uid)) or
        (r.target_type='clip'    and r.target_id in (select id from clips    where author_id=v_uid)) or
        (r.target_type='comment' and r.target_id in (select id from comments where author_id=v_uid)) or
        (r.target_type='profile' and r.target_id = v_uid)
      );

  return jsonb_build_object(
    'articles_hidden',   coalesce(v_articles_hidden, 0),
    'clips_hidden',      coalesce(v_clips_hidden, 0),
    'pending_against',   coalesce(v_pending_against, 0)
  );
end $$;

grant execute on function get_user_moderation_summary() to authenticated;


-- ============================================================================
-- Smoke tests :
--
--   -- Verifier le schema
--   select column_name from information_schema.columns
--    where table_name='reports' and column_name in ('reason_code','severity','details');
--   select tablename from pg_tables
--    where schemaname='public' and tablename in ('moderation_actions','peer_reviews');
--   select column_name from information_schema.columns
--    where table_name='articles' and column_name in ('moderation_state','reports_count');
--
--   -- Verifier les RPCs
--   select proname from pg_proc where proname in (
--     'submit_report','submit_peer_review','mod_apply_action',
--     'get_moderation_queue','get_peer_review_queue',
--     'get_user_moderation_summary','auto_hide_if_threshold'
--   );
--
--   -- Test cycle complet (manuel) :
--   --   1. select submit_report('article', '<id>', 'misinformation', 'fake');
--   --   2. (autre user) select submit_peer_review('<report_id>', 'valid');
--   --   3. select * from get_moderation_queue();
-- ============================================================================
-- Migration v0.19.0 -- terminee.
-- ============================================================================
