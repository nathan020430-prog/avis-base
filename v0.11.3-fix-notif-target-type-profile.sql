-- ════════════════════════════════════════════════════════════════════
-- Avis Basé — HOTFIX V0.11.3 : ajouter 'profile' au CHECK target_type
--
-- BUG : la migration v0.10.0 (système de follow) ajoute 'follow' au
-- CHECK sur notifications.type mais oublie d'ajouter 'profile' au CHECK
-- sur notifications.target_type. Conséquence : le trigger on_follow_change
-- qui INSERT une notif avec target_type='profile' échoue avec
-- "notifications_target_type_check" violation, ce qui rollback la
-- transaction → impossible de suivre un user.
--
-- FIX : étendre le CHECK pour inclure 'profile'.
--
-- À exécuter UNE FOIS dans Supabase SQL Editor.
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════

do $$
begin
  alter table notifications drop constraint if exists notifications_target_type_check;
  alter table notifications add constraint notifications_target_type_check
    check (target_type in ('article','clip','comment','profile'));
exception when others then
  raise notice 'notifications_target_type_check non modifiée (probablement déjà OK ou table absente) : %', SQLERRM;
end $$;

-- ════════════════════════════════════════════════════════════════════
-- FIN HOTFIX V0.11.3
-- ════════════════════════════════════════════════════════════════════
