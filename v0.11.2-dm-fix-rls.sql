-- ════════════════════════════════════════════════════════════════════
-- Avis Basé — HOTFIX V0.11.2 : Récursion RLS sur dm_participants
--
-- BUG : la policy SELECT sur dm_participants interrogeait dm_participants
-- elle-même → "infinite recursion detected in policy for relation
-- dm_participants" lors de l'envoi de DM.
--
-- FIX : on encapsule le test "suis-je participant ?" dans une fonction
-- SECURITY DEFINER qui contourne RLS lors de son exécution interne.
--
-- À exécuter UNE FOIS dans Supabase SQL Editor.
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════

-- ─── 1. Fonction utilitaire SECURITY DEFINER ─────────────────────
-- Permet aux policies de tester l'appartenance sans déclencher de récursion
create or replace function dm_is_participant(conv uuid)
returns boolean
language sql security definer stable set search_path = public
as $$
  select exists (
    select 1 from dm_participants
    where conversation_id = conv and user_id = auth.uid()
  )
$$;

revoke all on function dm_is_participant(uuid) from public;
grant execute on function dm_is_participant(uuid) to authenticated;

-- ─── 2. Recrée les policies en utilisant la fonction ────────────

-- dm_conversations SELECT
drop policy if exists "users read own conversations" on dm_conversations;
create policy "users read own conversations"
  on dm_conversations for select to authenticated
  using (dm_is_participant(id));

-- dm_participants SELECT (LA cause de la récursion)
drop policy if exists "users read participants of own convs" on dm_participants;
create policy "users read participants of own convs"
  on dm_participants for select to authenticated
  using (dm_is_participant(conversation_id));

-- dm_participants UPDATE (déjà OK mais on s'assure)
drop policy if exists "users update own participation" on dm_participants;
create policy "users update own participation"
  on dm_participants for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- dm_messages SELECT
drop policy if exists "users read messages of own convs" on dm_messages;
create policy "users read messages of own convs"
  on dm_messages for select to authenticated
  using (dm_is_participant(conversation_id));

-- dm_messages INSERT — IMPORTANT : on garde le check anti-bloqué
drop policy if exists "users insert own messages" on dm_messages;
create policy "users insert own messages"
  on dm_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and dm_is_participant(conversation_id)
    -- L'autre user ne doit pas avoir bloqué l'expéditeur
    and not exists (
      select 1 from dm_blocks b
      where b.blocked_id = auth.uid()
        and b.blocker_id in (
          select user_id from dm_participants
          where conversation_id = dm_messages.conversation_id
            and user_id <> auth.uid()
        )
    )
  );

-- dm_messages UPDATE (édition)
drop policy if exists "users edit own messages" on dm_messages;
create policy "users edit own messages"
  on dm_messages for update to authenticated
  using (sender_id = auth.uid())
  with check (sender_id = auth.uid());

-- dm_messages DELETE
drop policy if exists "users delete own messages" on dm_messages;
create policy "users delete own messages"
  on dm_messages for delete to authenticated
  using (sender_id = auth.uid());

-- ─── 3. Storage policies : même fix pour les pièces jointes ──────

drop policy if exists "dm storage upload" on storage.objects;
create policy "dm storage upload"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'dm-attachments'
    and dm_is_participant(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists "dm storage read" on storage.objects;
create policy "dm storage read"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'dm-attachments'
    and dm_is_participant(((storage.foldername(name))[1])::uuid)
  );

-- (delete own reste inchangé : pas de récursion possible)

-- ════════════════════════════════════════════════════════════════════
-- FIN HOTFIX V0.11.2
-- ════════════════════════════════════════════════════════════════════
