-- ============================================================================
-- Avis Base -- v0.28.0 -- Mutual followers (preuve sociale profil)
-- ============================================================================
--
-- RPC publique qui retourne les profils suivis a la fois par :
--   - l'utilisateur courant (auth.uid())
--   - le profil cible (p_target_id)
--
-- Sert a afficher "Suivi par @x, @y et N autres que tu suis" sur la page
-- profil, levier de preuve sociale (TikTok/Insta/Twitter).
--
-- Idempotent. ASCII pur. A appliquer apres v0.10.0 (table `follows`).
-- ============================================================================

set search_path = public;


-- ----------------------------------------------------------------------------
-- get_mutual_followers(p_target_id uuid, p_limit int default 3)
-- ----------------------------------------------------------------------------
-- Retourne jusqu'a p_limit profils (username + avatar_url + id) qui :
--   - sont suivis par le user courant (follower_id = auth.uid())
--   - suivent egalement la cible (following_id = p_target_id)
-- + total count des matchs (au-dela du limit, pour l'affichage "et N autres").
--
-- Si pas de session, retourne tableau vide / count 0.

create or replace function get_mutual_followers(
  p_target_id uuid,
  p_limit     int default 3
)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_uid    uuid := auth.uid();
  v_arr    jsonb := '[]'::jsonb;
  v_total  int   := 0;
  v_limit  int   := greatest(1, least(coalesce(p_limit, 3), 20));
begin
  if v_uid is null or p_target_id is null or v_uid = p_target_id then
    return jsonb_build_object('mutuals', '[]'::jsonb, 'total', 0);
  end if;

  -- Total = nombre de profils que MOI je suis ET qui suivent aussi la cible
  begin
    select count(*) into v_total
      from follows f_me
      join follows f_them on f_me.following_id = f_them.follower_id
     where f_me.follower_id    = v_uid
       and f_them.following_id = p_target_id
       and f_me.following_id  <> p_target_id; -- exclut la cible elle-meme
  exception when others then
    v_total := 0;
  end;

  if v_total = 0 then
    return jsonb_build_object('mutuals', '[]'::jsonb, 'total', 0);
  end if;

  -- Top N mutuels ordonnes par credibilite descendante (les plus "presents")
  begin
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id',         p.id,
          'username',   p.username,
          'avatar_url', p.avatar_url
        )
      ),
      '[]'::jsonb
    ) into v_arr
    from (
      select distinct p.id, p.username, p.avatar_url, p.credibility_score
        from follows f_me
        join follows f_them on f_me.following_id = f_them.follower_id
        join profiles p     on p.id = f_me.following_id
       where f_me.follower_id    = v_uid
         and f_them.following_id = p_target_id
         and f_me.following_id  <> p_target_id
       order by p.credibility_score desc nulls last
       limit v_limit
    ) p;
  exception when others then
    v_arr := '[]'::jsonb;
  end;

  return jsonb_build_object('mutuals', coalesce(v_arr, '[]'::jsonb), 'total', v_total);
end $$;

grant execute on function get_mutual_followers(uuid, int) to authenticated;
-- Pas de grant a `anon` : la preuve sociale n'a de sens que connecte.


-- ============================================================================
-- Smoke tests :
--   select get_mutual_followers(
--     'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'::uuid, 3
--   );
-- ============================================================================
-- Fin v0.28.0
-- ============================================================================
