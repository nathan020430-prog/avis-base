-- ═══════════════════════════════════════════════════════════════════════════
-- HOTFIX V0.8.3.2 — comments.source_id doit être nullable
-- (commentaires polymorphes : sur article OU sur source, jamais les deux)
-- À exécuter dans Supabase → SQL Editor → Run
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'comments'
      AND column_name = 'source_id' AND is_nullable = 'NO'
  ) THEN
    ALTER TABLE comments ALTER COLUMN source_id DROP NOT NULL;
    RAISE NOTICE 'comments.source_id : DROP NOT NULL appliqué';
  ELSE
    RAISE NOTICE 'comments.source_id : déjà nullable, rien à faire';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'comments'
      AND column_name = 'article_id' AND is_nullable = 'NO'
  ) THEN
    ALTER TABLE comments ALTER COLUMN article_id DROP NOT NULL;
    RAISE NOTICE 'comments.article_id : DROP NOT NULL appliqué';
  ELSE
    RAISE NOTICE 'comments.article_id : déjà nullable, rien à faire';
  END IF;
END $$;

-- Vérification finale : on doit avoir au moins UN des deux IDs renseigné
-- (cohérence métier — un commentaire concerne soit un article soit une source)
ALTER TABLE comments DROP CONSTRAINT IF EXISTS comments_target_check;
ALTER TABLE comments ADD CONSTRAINT comments_target_check
  CHECK (article_id IS NOT NULL OR source_id IS NOT NULL);
