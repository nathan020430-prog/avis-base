# Comment appliquer `v0.13.0-migration.sql`

## 1. Sauvegarde (sécurité)

Avant toute migration en prod, snapshot ta DB. Pour Supabase :

- **Plan Pro** : Database → Backups → activer Point-in-Time Recovery (si pas déjà fait)
- **Plan Free** : Database → Backups → "Backup now" (download du dump)

## 2. Exécuter la migration

1. https://supabase.com/dashboard/project/panjgsqwitwduxckgbbq/sql/new
2. Copie le contenu de `v0.13.0-migration.sql`
3. Colle dans l'éditeur
4. Clique sur **Run**

La migration est **idempotente** : tu peux la relancer sans risque si quelque chose plante au milieu.

## 3. Smoke tests (à coller après dans le SQL Editor)

```sql
-- Vérifie les 3 tables
select tablename from pg_tables
where schemaname='public' and tablename like 'dm_%' or tablename='conversations'
order by tablename;
-- Attendu : conversations, dm_messages, dm_participants

-- Vérifie les 5 RPC
select proname from pg_proc
where proname in (
  'find_or_create_dm','mark_conversation_read','set_conversation_block',
  'dm_update_conv_last_message','dm_notify_recipient'
)
order by proname;
-- Attendu : 5 lignes

-- Vérifie les RLS
select tablename, count(*) as policies
from pg_policies
where schemaname='public' and tablename in ('conversations','dm_participants','dm_messages')
group by tablename;
-- Attendu : conversations 2, dm_participants 3, dm_messages 3

-- Vérifie la publication realtime (pour les websockets)
select tablename from pg_publication_tables
where pubname='supabase_realtime' and schemaname='public' and tablename='dm_messages';
-- Attendu : 1 ligne
```

## 4. Test fonctionnel (manuel)

Depuis n'importe quel client connecté (la console JS de `avis-base.com` est parfaite) :

```js
// 1. Récupère l'ID d'un autre user (par exemple toi-même + un compte test)
const { data: someoneElse } = await supa.from('profiles').select('id, username').limit(2);
const targetId = someoneElse.find(u => u.id !== (await supa.auth.getUser()).data.user.id)?.id;

// 2. Crée la conversation
const { data: convId, error } = await supa.rpc('find_or_create_dm', {
  other_user_id: targetId
});
console.log('Conversation', convId, error);

// 3. Envoie un message
const { error: insertErr } = await supa.from('dm_messages').insert({
  conversation_id: convId,
  sender_id: (await supa.auth.getUser()).data.user.id,
  body: 'Hello, depuis le smoke test'
});
console.log('Inséré ?', !insertErr, insertErr);

// 4. Lis la conv
const { data: msgs } = await supa.from('dm_messages')
  .select('*')
  .eq('conversation_id', convId)
  .order('created_at');
console.log(msgs);
```

Si chaque étape renvoie pas d'erreur : ✅ la migration est bonne.

## 5. Mise à jour du README + PLAN_DEV

Dans ton repo principal, ajoute à `README.md` :

```diff
 1. `v0.8-migration.sql` (V0.8 — économie de pièces)
 2. `schema_v083.sql` (V0.8.3 — schéma complet refactor)
 3. `hotfix_v0832_comments.sql` (V0.8.3.2 — commentaires polymorphes)
 4. `v0.9.0-migration.sql` (V0.9.0 — profils enrichis + favoris)
 5. `v0.9.7-migration.sql` (V0.9.7 — notifications in-app : table, RLS, triggers, RPC)
 6. `v0.10.0-migration.sql` (V0.10.0 — follows, compteurs, trigger notif follow)
+7. **`v0.13.0-migration.sql`** (V0.13.0 — messagerie privée, RLS strict, anti-spam) ← **NOUVEAU**
```

Et dans `PLAN_DEV.md`, coche la case **v0.13.0** ou note "🟡 SQL appliqué, UI à brancher".

## 6. Brancher l'UI

Deux endroits :

### A. Site (`index.html`) — Phase UI v0.13.0

À faire ensuite (je peux te le rédiger en session suivante) :

- Onglet "Messages" dans la nav latérale (caché sur mobile actuellement → à débloquer)
- Liste des conversations (vue `user_conversations` à ajouter)
- Composer + bulles
- Bouton "Envoyer un message" sur les profils

### B. App mobile (`avis-base-app/`) — déjà câblée

Mon app appelle déjà :
- `find_or_create_dm` → ✅ (dans `app/user/[username].tsx`)
- `dm_messages` insert + realtime → ✅ (dans `app/conversation/[id].tsx`)
- `mark_conversation_read` → ✅ on l'a ajouté côté app mais pas appelé encore — TODO

Une fois la migration appliquée, l'app mobile DM fonctionne **sans modif** côté app.

## Annexe — Rollback

Si quelque chose se passe mal (peu probable, mais bon) :

```sql
-- ⚠️ destructif : supprime toutes les conversations et messages.
-- Ne fait ça QUE si la DB n'a pas encore d'usage réel.
drop trigger if exists dm_messages_after_insert on dm_messages;
drop trigger if exists dm_messages_notify on dm_messages;
drop function if exists dm_update_conv_last_message();
drop function if exists dm_notify_recipient();
drop function if exists find_or_create_dm(uuid);
drop function if exists mark_conversation_read(uuid);
drop function if exists set_conversation_block(uuid, boolean);
drop table if exists dm_messages cascade;
drop table if exists dm_participants cascade;
drop table if exists conversations cascade;
```
