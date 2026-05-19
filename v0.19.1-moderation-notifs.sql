-- ============================================================================
-- Avis Base -- v0.19.1 -- Notifications de moderation a l'auteur
-- ============================================================================
--
-- Ajoute :
--   1. 2 nouveaux types de notifs : 'content_hidden' et 'content_restored'
--      (etend le CHECK sur notifications.type)
--   2. Trigger AFTER UPDATE OF moderation_state sur articles et clips
--      qui insere une notif a l'auteur quand son contenu passe en
--      hidden_auto / hidden_mod (content_hidden) ou revient en
--      visible / reviewed_ok (content_restored).
--
-- Idempotent. ASCII pur. A appliquer APRES v0.19.0-moderation-migration.sql.
-- ============================================================================

set search_path = public;


-- ----------------------------------------------------------------------------
-- 1. Etend le CHECK sur notifications.type
-- ----------------------------------------------------------------------------
-- Etat avant v0.19.1 :
--   'like','comment','reply','article_validated','follow'
-- Etat apres v0.19.1 :
--   + 'content_hidden','content_restored'

do $$
begin
  alter table notifications drop constraint if exists notifications_type_check;
  alter table notifications add constraint notifications_type_check
    check (type in (
      'like','comment','reply','article_validated','follow',
      'content_hidden','content_restored'
    ));
exception when others then
  raise notice 'notifications_type_check non modifiee : %', SQLERRM;
end $$;


-- ----------------------------------------------------------------------------
-- 2. Fonction trigger : notif sur changement de moderation_state
-- ----------------------------------------------------------------------------
-- Strategie :
--   * Si OLD.moderation_state IN ('visible','reviewed_ok')
--     ET NEW.moderation_state IN ('hidden_auto','hidden_mod')
--     -> content_hidden a l'auteur
--   * Si OLD.moderation_state IN ('hidden_auto','hidden_mod')
--     ET NEW.moderation_state IN ('visible','reviewed_ok')
--     -> content_restored a l'auteur
--   * Autres transitions -> rien (changement neutre)

create or replace function notify_on_moderation_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old text := coalesce(old.moderation_state, 'visible');
  v_new text := coalesce(new.moderation_state, 'visible');
  v_target_type text;
  v_preview text;
  v_notif_type text := null;
begin
  -- Pas de changement reel
  if v_old = v_new then return new; end if;

  -- Determine le type de cible selon la table
  if tg_table_name = 'articles' then
    v_target_type := 'article';
    v_preview := left(coalesce(new.title, ''), 80);
  elsif tg_table_name = 'clips' then
    v_target_type := 'clip';
    v_preview := left(coalesce(new.hook, ''), 80);
  else
    return new;  -- table non geree
  end if;

  -- Transitions visibles -> masquees
  if v_old in ('visible','reviewed_ok')
     and v_new in ('hidden_auto','hidden_mod') then
    v_notif_type := 'content_hidden';
  -- Transitions masquees -> visibles
  elsif v_old in ('hidden_auto','hidden_mod')
        and v_new in ('visible','reviewed_ok') then
    v_notif_type := 'content_restored';
  end if;

  if v_notif_type is null then return new; end if;
  if new.author_id is null then return new; end if;

  insert into notifications (user_id, actor_id, type, target_type, target_id, target_preview)
  values (new.author_id, null, v_notif_type, v_target_type, new.id, v_preview);

  return new;
end $$;


-- ----------------------------------------------------------------------------
-- 3. Triggers sur articles et clips
-- ----------------------------------------------------------------------------

drop trigger if exists trg_notify_on_article_moderation on articles;
create trigger trg_notify_on_article_moderation
  after update of moderation_state on articles
  for each row execute function notify_on_moderation_change();

drop trigger if exists trg_notify_on_clip_moderation on clips;
create trigger trg_notify_on_clip_moderation
  after update of moderation_state on clips
  for each row execute function notify_on_moderation_change();


-- ============================================================================
-- Smoke tests :
--
--   -- Verifier le check etendu
--   select pg_get_constraintdef(oid) from pg_constraint
--    where conname = 'notifications_type_check';
--
--   -- Verifier les 2 triggers
--   select tgname from pg_trigger
--    where tgname in ('trg_notify_on_article_moderation','trg_notify_on_clip_moderation');
--
--   -- Test (necessite un article et un compte) :
--   --   update articles set moderation_state='hidden_mod', moderation_hidden_at=now()
--   --    where id='<id_test>';
--   --   select * from notifications where target_id='<id_test>' order by created_at desc limit 5;
-- ============================================================================
-- Fin v0.19.1
-- ============================================================================
