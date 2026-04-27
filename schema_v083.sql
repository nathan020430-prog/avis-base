-- ═══════════════════════════════════════════════════════════════════════════
-- AVIS BASÉ — V0.8.3 : Schéma Supabase complet (CORRECTIF)
-- Corrige les bugs de soumission d'articles + ajoute les tables manquantes :
--   • article_themes / article_tones (seed data inclus)
--   • clips (système TikTok)
--   • comment_edits (historique d'édition)
--   • site_settings (charte, config)
-- Fixe les colonnes manquantes : comments (source_id, target_type),
--   reports (comment_id, reporter_username, status)
-- Ajoute les policies INSERT/UPDATE/DELETE manquantes (sources, comments, clips...)
-- Ajoute le statut 'archived' aux articles
--
-- Idempotent — peut être ré-exécuté sans danger.
-- ORDRE D'EXÉCUTION :
--   1) CREATE TABLE IF NOT EXISTS
--   2) ALTER TABLE ADD COLUMN IF NOT EXISTS
--   3) DROP COLUMN
--   4) CHECK constraints (recreate)
--   5) INDEXES
--   6) RLS + POLICIES
--   7) FONCTIONS + TRIGGERS
--   8) RPC
--   9) SEEDS (article_themes / article_tones)
--  10) RECALCUL INITIAL
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════
-- 1. CREATE TABLE IF NOT EXISTS
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Profiles ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS profiles (
  id                        UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username                  TEXT UNIQUE NOT NULL,
  role                      TEXT NOT NULL DEFAULT 'contributor' CHECK (role IN ('contributor','admin','superadmin')),
  badge                     TEXT,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  articles_published        INT NOT NULL DEFAULT 0,
  sources_added             INT NOT NULL DEFAULT 0,
  comments_count            INT NOT NULL DEFAULT 0,
  validated_reports         INT NOT NULL DEFAULT 0,
  weighted_likes_received   NUMERIC(10,2) NOT NULL DEFAULT 0,
  weighted_useful_comments  NUMERIC(10,2) NOT NULL DEFAULT 0,
  credibility_score         INT NOT NULL DEFAULT 0 CHECK (credibility_score BETWEEN 0 AND 100),
  credibility_level         TEXT NOT NULL DEFAULT 'nouveau'
                              CHECK (credibility_level IN ('nouveau','contributeur','verificateur','reference'))
);

-- ─── Article Themes (catalogue) ─────────────────────────────
CREATE TABLE IF NOT EXISTS article_themes (
  slug          TEXT PRIMARY KEY,
  label         TEXT NOT NULL,
  emoji         TEXT,
  display_order INT NOT NULL DEFAULT 100,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─── Article Tones (catalogue) ──────────────────────────────
CREATE TABLE IF NOT EXISTS article_tones (
  slug          TEXT PRIMARY KEY,
  label         TEXT NOT NULL,
  emoji         TEXT,
  display_order INT NOT NULL DEFAULT 100,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─── Articles ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS articles (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug                      TEXT UNIQUE NOT NULL,
  title                     TEXT NOT NULL,
  subtitle                  TEXT,
  cover_image               TEXT,
  body_markdown             TEXT NOT NULL DEFAULT '',
  word_count                INT NOT NULL DEFAULT 0,
  reading_time_minutes      INT NOT NULL DEFAULT 1,
  video_source_url          TEXT,
  video_source_type         TEXT DEFAULT 'youtube',
  video_source_duration_seconds INT,
  video_source_title        TEXT,
  cited_sources             JSONB NOT NULL DEFAULT '[]',
  theme_slug                TEXT NOT NULL DEFAULT 'autre',
  tone_slug                 TEXT,
  author_id                 UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  author_username           TEXT NOT NULL,
  author_cred_score         INT NOT NULL DEFAULT 0,
  status                    TEXT NOT NULL DEFAULT 'draft',
  admin_notes               TEXT,
  from_source_id            UUID,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  submitted_at              TIMESTAMPTZ,
  reviewed_at               TIMESTAMPTZ,
  published_at              TIMESTAMPTZ,
  reads                     INT NOT NULL DEFAULT 0,
  likes_count               INT NOT NULL DEFAULT 0,
  dislikes_count            INT NOT NULL DEFAULT 0,
  comments_count            INT NOT NULL DEFAULT 0,
  popularity_score          INT NOT NULL DEFAULT 0,
  reliability_score         INT NOT NULL DEFAULT 0,
  global_score              INT NOT NULL DEFAULT 0
);

-- ─── Votes ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS votes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  target_type     TEXT NOT NULL CHECK (target_type IN ('article','comment','source')),
  target_id       UUID NOT NULL,
  vote_type       INT  NOT NULL CHECK (vote_type IN (1, -1)),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, target_type, target_id)
);

-- ─── Comments (polymorphes : articles OU sources) ───────────
CREATE TABLE IF NOT EXISTS comments (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id        UUID REFERENCES articles(id) ON DELETE CASCADE,
  source_id         UUID,
  target_type       TEXT NOT NULL DEFAULT 'article' CHECK (target_type IN ('article','source')),
  author_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  author_username   TEXT NOT NULL,
  author_role       TEXT NOT NULL DEFAULT 'contributor',
  content           TEXT NOT NULL,
  reply_to_id       UUID REFERENCES comments(id) ON DELETE SET NULL,
  reply_to_preview  TEXT,
  reply_to_author   TEXT,
  edited            BOOLEAN NOT NULL DEFAULT false,
  edited_at         TIMESTAMPTZ,
  hidden            BOOLEAN NOT NULL DEFAULT false,
  hidden_by         UUID REFERENCES profiles(id),
  hidden_at         TIMESTAMPTZ,
  hidden_reason     TEXT,
  useful_marked     BOOLEAN NOT NULL DEFAULT false,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─── Comment Edits (historique) ─────────────────────────────
CREATE TABLE IF NOT EXISTS comment_edits (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  comment_id       UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
  previous_content TEXT NOT NULL,
  edited_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─── Sources (archive pré-v0.6) ─────────────────────────────
CREATE TABLE IF NOT EXISTS sources (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title                TEXT NOT NULL,
  description          TEXT,
  source_url           TEXT,
  tiktok_url           TEXT,
  type                 TEXT DEFAULT 'youtube',
  date                 DATE,
  thumb                TEXT,
  tags                 TEXT[] DEFAULT '{}',
  additional_sources   JSONB DEFAULT '[]',
  contributor_username TEXT,
  views                INT NOT NULL DEFAULT 0,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─── Submissions ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS submissions (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title                TEXT NOT NULL,
  description          TEXT,
  source_url           TEXT,
  tiktok_url           TEXT,
  type                 TEXT DEFAULT 'youtube',
  date                 DATE,
  thumb                TEXT,
  tags                 TEXT[] DEFAULT '{}',
  additional_sources   JSONB DEFAULT '[]',
  submitter_id         UUID REFERENCES profiles(id) ON DELETE SET NULL,
  submitter_username   TEXT,
  status               TEXT NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending','approved','rejected')),
  admin_notes          TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_at          TIMESTAMPTZ
);

-- ─── Reports ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS reports (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id       UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  reporter_username TEXT,
  comment_id        UUID REFERENCES comments(id) ON DELETE CASCADE,
  target_type       TEXT,
  target_id         UUID,
  reason            TEXT,
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','dismissed','resolved')),
  validated         BOOLEAN,
  reviewed_by       UUID REFERENCES profiles(id),
  reviewed_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (reporter_id, comment_id)
);

-- ─── Clips (TikTok) ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS clips (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id            UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
  author_id             UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  author_username       TEXT NOT NULL,
  video_start_seconds   INT NOT NULL DEFAULT 0,
  video_end_seconds     INT NOT NULL DEFAULT 15,
  duration_seconds      INT GENERATED ALWAYS AS (video_end_seconds - video_start_seconds) STORED,
  hook                  TEXT NOT NULL DEFAULT '',
  subtitles             JSONB NOT NULL DEFAULT '[]',
  hashtags              JSONB NOT NULL DEFAULT '[]',
  status                TEXT NOT NULL DEFAULT 'draft'
                          CHECK (status IN ('draft','review','approved','needs_changes','scheduled','published','rejected','archived')),
  admin_notes           TEXT,
  scheduled_for         TIMESTAMPTZ,
  published_tiktok_url  TEXT,
  published_at          TIMESTAMPTZ,
  tiktok_views          INT,
  tiktok_likes          INT,
  tiktok_comments       INT,
  tiktok_shares         INT,
  submitted_at          TIMESTAMPTZ,
  reviewed_at           TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─── Site Settings (charte, config) ─────────────────────────
CREATE TABLE IF NOT EXISTS site_settings (
  key         TEXT PRIMARY KEY,
  value       TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID REFERENCES profiles(id)
);

-- ─── Credibility Events (historique) ────────────────────────
CREATE TABLE IF NOT EXISTS credibility_events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  event_type  TEXT NOT NULL,
  delta       NUMERIC(6,2) NOT NULL,
  actor_id    UUID REFERENCES profiles(id),
  actor_cred  INT,
  weight      NUMERIC(5,4),
  note        TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ═══════════════════════════════════════════════════════════════════════════
-- 2. ALTER TABLE — ajout des nouvelles colonnes (si bases existantes)
-- ═══════════════════════════════════════════════════════════════════════════

-- Profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS articles_published       INT           NOT NULL DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS sources_added            INT           NOT NULL DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS comments_count           INT           NOT NULL DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS validated_reports        INT           NOT NULL DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS weighted_likes_received  NUMERIC(10,2) NOT NULL DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS weighted_useful_comments NUMERIC(10,2) NOT NULL DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS credibility_score        INT           NOT NULL DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS credibility_level        TEXT          NOT NULL DEFAULT 'nouveau';

-- Articles : compteurs et scores
ALTER TABLE articles ADD COLUMN IF NOT EXISTS author_cred_score   INT NOT NULL DEFAULT 0;
ALTER TABLE articles ADD COLUMN IF NOT EXISTS likes_count         INT NOT NULL DEFAULT 0;
ALTER TABLE articles ADD COLUMN IF NOT EXISTS dislikes_count      INT NOT NULL DEFAULT 0;
ALTER TABLE articles ADD COLUMN IF NOT EXISTS comments_count      INT NOT NULL DEFAULT 0;
ALTER TABLE articles ADD COLUMN IF NOT EXISTS popularity_score    INT NOT NULL DEFAULT 0;
ALTER TABLE articles ADD COLUMN IF NOT EXISTS reliability_score   INT NOT NULL DEFAULT 0;
ALTER TABLE articles ADD COLUMN IF NOT EXISTS global_score        INT NOT NULL DEFAULT 0;
ALTER TABLE articles ADD COLUMN IF NOT EXISTS theme_slug          TEXT NOT NULL DEFAULT 'autre';
ALTER TABLE articles ADD COLUMN IF NOT EXISTS tone_slug           TEXT;

-- Article Themes / Tones : ajouter emoji et display_order si absents
ALTER TABLE article_themes ADD COLUMN IF NOT EXISTS emoji         TEXT;
ALTER TABLE article_themes ADD COLUMN IF NOT EXISTS display_order INT NOT NULL DEFAULT 100;
ALTER TABLE article_themes ADD COLUMN IF NOT EXISTS created_at    TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE article_tones ADD COLUMN IF NOT EXISTS emoji         TEXT;
ALTER TABLE article_tones ADD COLUMN IF NOT EXISTS display_order INT NOT NULL DEFAULT 100;
ALTER TABLE article_tones ADD COLUMN IF NOT EXISTS created_at    TIMESTAMPTZ NOT NULL DEFAULT now();

-- Comments : permettre source_id (commentaires sur sources archivées)
ALTER TABLE comments ADD COLUMN IF NOT EXISTS useful_marked  BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE comments ADD COLUMN IF NOT EXISTS source_id      UUID;
ALTER TABLE comments ADD COLUMN IF NOT EXISTS target_type    TEXT NOT NULL DEFAULT 'article';

-- Comments : article_id devient nullable (pour permettre les commentaires sur sources)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'comments'
      AND column_name = 'article_id' AND is_nullable = 'NO'
  ) THEN
    ALTER TABLE comments ALTER COLUMN article_id DROP NOT NULL;
  END IF;
END $$;

-- Reports : compatibilité avec le code (insertion par comment_id direct)
ALTER TABLE reports ADD COLUMN IF NOT EXISTS reporter_username TEXT;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS comment_id        UUID REFERENCES comments(id) ON DELETE CASCADE;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS status            TEXT NOT NULL DEFAULT 'pending';

-- Clips : assurer toutes les colonnes attendues si la table pré-existait
ALTER TABLE clips ADD COLUMN IF NOT EXISTS author_username      TEXT;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS video_start_seconds  INT NOT NULL DEFAULT 0;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS video_end_seconds    INT NOT NULL DEFAULT 15;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS hook                 TEXT NOT NULL DEFAULT '';
ALTER TABLE clips ADD COLUMN IF NOT EXISTS subtitles            JSONB NOT NULL DEFAULT '[]';
ALTER TABLE clips ADD COLUMN IF NOT EXISTS hashtags             JSONB NOT NULL DEFAULT '[]';
ALTER TABLE clips ADD COLUMN IF NOT EXISTS status               TEXT NOT NULL DEFAULT 'draft';
ALTER TABLE clips ADD COLUMN IF NOT EXISTS admin_notes          TEXT;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS scheduled_for        TIMESTAMPTZ;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS published_tiktok_url TEXT;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS published_at         TIMESTAMPTZ;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS tiktok_views         INT;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS tiktok_likes         INT;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS tiktok_comments      INT;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS tiktok_shares        INT;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS submitted_at         TIMESTAMPTZ;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS reviewed_at          TIMESTAMPTZ;
ALTER TABLE clips ADD COLUMN IF NOT EXISTS updated_at           TIMESTAMPTZ NOT NULL DEFAULT now();

-- Site Settings : assurer la forme attendue
ALTER TABLE site_settings ADD COLUMN IF NOT EXISTS value      TEXT;
ALTER TABLE site_settings ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE site_settings ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES profiles(id);

-- Comment Edits : assurer les colonnes
ALTER TABLE comment_edits ADD COLUMN IF NOT EXISTS previous_content TEXT;
ALTER TABLE comment_edits ADD COLUMN IF NOT EXISTS edited_at        TIMESTAMPTZ NOT NULL DEFAULT now();

-- Reports : assouplir target_type/target_id/reason pour ne plus être obligatoires
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'reports'
      AND column_name = 'target_type' AND is_nullable = 'NO'
  ) THEN
    ALTER TABLE reports ALTER COLUMN target_type DROP NOT NULL;
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'reports'
      AND column_name = 'target_id' AND is_nullable = 'NO'
  ) THEN
    ALTER TABLE reports ALTER COLUMN target_id DROP NOT NULL;
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'reports'
      AND column_name = 'reason' AND is_nullable = 'NO'
  ) THEN
    ALTER TABLE reports ALTER COLUMN reason DROP NOT NULL;
  END IF;
END $$;


-- ═══════════════════════════════════════════════════════════════════════════
-- 3. DROP COLUMN — nettoyage monétaire
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE profiles DROP COLUMN IF EXISTS coins;
ALTER TABLE profiles DROP COLUMN IF EXISTS boosted_until;
ALTER TABLE articles DROP COLUMN IF EXISTS boosted_until;

DROP TABLE IF EXISTS coin_transactions CASCADE;


-- ═══════════════════════════════════════════════════════════════════════════
-- 4. CHECK CONSTRAINTS — recréation pour ajouter 'archived' au statut articles
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_constraint_name TEXT;
BEGIN
  -- Drop ancien CHECK sur articles.status si présent
  SELECT con.conname INTO v_constraint_name
  FROM pg_constraint con
  JOIN pg_class rel ON rel.oid = con.conrelid
  WHERE rel.relname = 'articles' AND con.contype = 'c'
    AND pg_get_constraintdef(con.oid) ILIKE '%status%';
  IF v_constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE articles DROP CONSTRAINT %I', v_constraint_name);
  END IF;
END $$;

ALTER TABLE articles ADD CONSTRAINT articles_status_check
  CHECK (status IN ('draft','review','needs_changes','approved','published','rejected','archived'));


-- ═══════════════════════════════════════════════════════════════════════════
-- 5. INDEXES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS articles_status_idx           ON articles(status);
CREATE INDEX IF NOT EXISTS articles_author_id_idx        ON articles(author_id);
CREATE INDEX IF NOT EXISTS articles_published_at_idx     ON articles(published_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS articles_global_score_idx     ON articles(global_score DESC);
CREATE INDEX IF NOT EXISTS articles_popularity_score_idx ON articles(popularity_score DESC);
CREATE INDEX IF NOT EXISTS articles_theme_slug_idx       ON articles(theme_slug);
CREATE INDEX IF NOT EXISTS votes_target_idx              ON votes(target_type, target_id);
CREATE INDEX IF NOT EXISTS comments_article_idx          ON comments(article_id);
CREATE INDEX IF NOT EXISTS comments_source_idx           ON comments(source_id);
CREATE INDEX IF NOT EXISTS comments_target_idx           ON comments(target_type);
CREATE INDEX IF NOT EXISTS clips_article_idx             ON clips(article_id);
CREATE INDEX IF NOT EXISTS clips_status_idx              ON clips(status);
CREATE INDEX IF NOT EXISTS clips_author_idx              ON clips(author_id);
CREATE INDEX IF NOT EXISTS reports_status_idx            ON reports(status);
CREATE INDEX IF NOT EXISTS reports_comment_idx           ON reports(comment_id);
CREATE INDEX IF NOT EXISTS cred_events_user_idx          ON credibility_events(user_id, created_at DESC);


-- ═══════════════════════════════════════════════════════════════════════════
-- 6. RLS + POLICIES
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE profiles           ENABLE ROW LEVEL SECURITY;
ALTER TABLE articles           ENABLE ROW LEVEL SECURITY;
ALTER TABLE article_themes     ENABLE ROW LEVEL SECURITY;
ALTER TABLE article_tones      ENABLE ROW LEVEL SECURITY;
ALTER TABLE votes              ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments           ENABLE ROW LEVEL SECURITY;
ALTER TABLE comment_edits      ENABLE ROW LEVEL SECURITY;
ALTER TABLE sources            ENABLE ROW LEVEL SECURITY;
ALTER TABLE submissions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports            ENABLE ROW LEVEL SECURITY;
ALTER TABLE clips              ENABLE ROW LEVEL SECURITY;
ALTER TABLE site_settings      ENABLE ROW LEVEL SECURITY;
ALTER TABLE credibility_events ENABLE ROW LEVEL SECURITY;

-- Drop des policies existantes (idempotence)
DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('profiles','articles','article_themes','article_tones','votes',
                        'comments','comment_edits','sources','submissions','reports',
                        'clips','site_settings','credibility_events','charter')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I',
                   pol.policyname, pol.schemaname, pol.tablename);
  END LOOP;
END $$;

-- ─── Profiles ───
CREATE POLICY "profiles_read_all"   ON profiles FOR SELECT USING (true);
CREATE POLICY "profiles_insert_own" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles_update_own" ON profiles FOR UPDATE USING (
  auth.uid() = id OR
  EXISTS (SELECT 1 FROM profiles p2 WHERE p2.id = auth.uid() AND p2.role IN ('admin','superadmin'))
);

-- ─── Articles ───
CREATE POLICY "articles_read_published" ON articles FOR SELECT USING (
  status = 'published' OR auth.uid() = author_id OR
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
);
CREATE POLICY "articles_insert_auth" ON articles FOR INSERT WITH CHECK (auth.uid() = author_id);
CREATE POLICY "articles_update_own"  ON articles FOR UPDATE USING (
  auth.uid() = author_id OR
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
);
CREATE POLICY "articles_delete_own_or_admin" ON articles FOR DELETE USING (
  auth.uid() = author_id OR
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
);

-- ─── Article Themes / Tones (lecture libre, écriture admin) ───
CREATE POLICY "article_themes_read_all" ON article_themes FOR SELECT USING (true);
CREATE POLICY "article_themes_admin"    ON article_themes FOR ALL USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
);

CREATE POLICY "article_tones_read_all" ON article_tones FOR SELECT USING (true);
CREATE POLICY "article_tones_admin"    ON article_tones FOR ALL USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
);

-- ─── Votes ───
CREATE POLICY "votes_read_all"    ON votes FOR SELECT USING (true);
CREATE POLICY "votes_insert_auth" ON votes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "votes_update_own"  ON votes FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "votes_delete_own"  ON votes FOR DELETE USING (auth.uid() = user_id);

-- ─── Comments ───
CREATE POLICY "comments_read_all"    ON comments FOR SELECT USING (true);
CREATE POLICY "comments_insert_auth" ON comments FOR INSERT WITH CHECK (auth.uid() = author_id);
CREATE POLICY "comments_update_own"  ON comments FOR UPDATE USING (
  auth.uid() = author_id OR
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
);
CREATE POLICY "comments_delete_own"  ON comments FOR DELETE USING (
  auth.uid() = author_id OR
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
);

-- ─── Comment Edits (lecture admin / auteur, insertion auth) ───
CREATE POLICY "comment_edits_read" ON comment_edits FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM comments c
    WHERE c.id = comment_id AND (
      c.author_id = auth.uid() OR
      EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
    )
  )
);
CREATE POLICY "comment_edits_insert" ON comment_edits FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM comments c WHERE c.id = comment_id AND c.author_id = auth.uid())
  OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
);

-- ─── Sources (lecture libre, écriture admin) ───
CREATE POLICY "sources_read_all" ON sources FOR SELECT USING (true);
CREATE POLICY "sources_admin_all" ON sources FOR ALL USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
);
-- Permettre la mise à jour du compteur de vues à tous les utilisateurs auth
CREATE POLICY "sources_update_views_auth" ON sources FOR UPDATE USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- ─── Submissions ───
CREATE POLICY "submissions_read_own_or_admin" ON submissions FOR SELECT USING (
  auth.uid() = submitter_id OR
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
);
CREATE POLICY "submissions_insert_auth" ON submissions FOR INSERT WITH CHECK (auth.uid() = submitter_id);
CREATE POLICY "submissions_update_admin" ON submissions FOR UPDATE USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
);

-- ─── Reports ───
CREATE POLICY "reports_insert_auth" ON reports FOR INSERT WITH CHECK (auth.uid() = reporter_id);
CREATE POLICY "reports_admin_all"   ON reports FOR ALL USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
);
CREATE POLICY "reports_read_own"    ON reports FOR SELECT USING (auth.uid() = reporter_id);

-- ─── Clips ───
CREATE POLICY "clips_read_all" ON clips FOR SELECT USING (
  status = 'published' OR auth.uid() = author_id OR
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
);
CREATE POLICY "clips_insert_auth" ON clips FOR INSERT WITH CHECK (auth.uid() = author_id);
CREATE POLICY "clips_update_own"  ON clips FOR UPDATE USING (
  auth.uid() = author_id OR
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
);
CREATE POLICY "clips_delete_own"  ON clips FOR DELETE USING (
  auth.uid() = author_id OR
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
);

-- ─── Site Settings (lecture libre, écriture admin) ───
CREATE POLICY "site_settings_read_all" ON site_settings FOR SELECT USING (true);
CREATE POLICY "site_settings_admin"    ON site_settings FOR ALL USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
);

-- ─── Credibility Events ───
CREATE POLICY "cred_events_read_own" ON credibility_events FOR SELECT USING (
  auth.uid() = user_id OR
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin','superadmin'))
);


-- ═══════════════════════════════════════════════════════════════════════════
-- 7. FONCTIONS & TRIGGERS
-- ═══════════════════════════════════════════════════════════════════════════

-- F0. Auto-update timestamps
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_articles_updated ON articles;
CREATE TRIGGER trg_articles_updated BEFORE UPDATE ON articles
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

DROP TRIGGER IF EXISTS trg_clips_updated ON clips;
CREATE TRIGGER trg_clips_updated BEFORE UPDATE ON clips
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- F1. Recalcul du score de crédibilité d'un utilisateur
CREATE OR REPLACE FUNCTION recompute_user_cred(p_user_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_raw   NUMERIC;
  v_score INT;
  v_level TEXT;
  CAP CONSTANT NUMERIC := 200;
BEGIN
  SELECT
    COALESCE(articles_published, 0) * 1
    + COALESCE(sources_added, 0) * 2
    + COALESCE(comments_count, 0) * 0.5
    + COALESCE(weighted_likes_received, 0) * 1
    + COALESCE(weighted_useful_comments, 0) * 2
    + COALESCE(validated_reports, 0) * (-5)
  INTO v_raw
  FROM profiles WHERE id = p_user_id;

  v_raw   := GREATEST(0, LEAST(v_raw, CAP));
  v_score := ROUND((v_raw / CAP) * 100)::INT;
  v_level := CASE
    WHEN v_score >= 80 THEN 'reference'
    WHEN v_score >= 60 THEN 'verificateur'
    WHEN v_score >= 30 THEN 'contributeur'
    ELSE 'nouveau'
  END;

  UPDATE profiles
    SET credibility_score = v_score, credibility_level = v_level
    WHERE id = p_user_id;
END;
$$;

-- F2. Recalcul des scores d'un article
CREATE OR REPLACE FUNCTION recompute_article_scores(p_article_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pop  INT;
  v_rel  INT;
  v_glob INT;
  POP_CAP CONSTANT INT := 5000;
BEGIN
  SELECT
    (COALESCE(likes_count,0) * 3)
    + (COALESCE(comments_count,0) * 2)
    + (COALESCE(reads,0) * 1),
    COALESCE(author_cred_score, 0)
  INTO v_pop, v_rel
  FROM articles WHERE id = p_article_id;

  v_glob := ROUND(
    (v_rel * 0.5)
    + (LEAST(100, ROUND((v_pop::NUMERIC / POP_CAP) * 100)) * 0.5)
  )::INT;

  UPDATE articles
    SET popularity_score = v_pop,
        reliability_score = v_rel,
        global_score = v_glob
    WHERE id = p_article_id;
END;
$$;

-- F3. Snapshot de la crédibilité auteur à la publication
CREATE OR REPLACE FUNCTION snapshot_author_cred()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'published' AND (OLD.status IS NULL OR OLD.status <> 'published') THEN
    SELECT credibility_score INTO NEW.author_cred_score
    FROM profiles WHERE id = NEW.author_id;
    NEW.published_at := COALESCE(NEW.published_at, now());
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_snapshot_author_cred ON articles;
CREATE TRIGGER trg_snapshot_author_cred
  BEFORE UPDATE ON articles
  FOR EACH ROW EXECUTE FUNCTION snapshot_author_cred();

-- F3b. Après publication : incrémente le compteur et recalcule le score
CREATE OR REPLACE FUNCTION after_article_published()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.status = 'published' AND (OLD.status IS NULL OR OLD.status <> 'published') THEN
    UPDATE profiles SET articles_published = articles_published + 1
      WHERE id = NEW.author_id;
    PERFORM recompute_user_cred(NEW.author_id);
    PERFORM recompute_article_scores(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_after_article_published ON articles;
CREATE TRIGGER trg_after_article_published
  AFTER UPDATE ON articles
  FOR EACH ROW EXECUTE FUNCTION after_article_published();

-- F4. Vote : incrémente compteurs + crédibilité pondérée
CREATE OR REPLACE FUNCTION handle_vote()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_article_author UUID;
  v_actor_cred     INT;
  v_weight         NUMERIC;
BEGIN
  SELECT credibility_score INTO v_actor_cred FROM profiles WHERE id = NEW.user_id;
  v_weight := COALESCE(v_actor_cred, 0)::NUMERIC / 100;

  IF NEW.target_type = 'article' AND NEW.vote_type = 1 THEN
    UPDATE articles SET likes_count = likes_count + 1 WHERE id = NEW.target_id;
    SELECT author_id INTO v_article_author FROM articles WHERE id = NEW.target_id;
    IF v_article_author IS NOT NULL THEN
      UPDATE profiles SET weighted_likes_received = weighted_likes_received + v_weight
        WHERE id = v_article_author;
      INSERT INTO credibility_events(user_id, event_type, delta, actor_id, actor_cred, weight)
      VALUES (v_article_author, 'like_received', v_weight, NEW.user_id, v_actor_cred, v_weight);
      PERFORM recompute_user_cred(v_article_author);
      PERFORM recompute_article_scores(NEW.target_id);
    END IF;
  ELSIF NEW.target_type = 'article' AND NEW.vote_type = -1 THEN
    UPDATE articles SET dislikes_count = dislikes_count + 1 WHERE id = NEW.target_id;
    PERFORM recompute_article_scores(NEW.target_id);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_handle_vote ON votes;
CREATE TRIGGER trg_handle_vote
  AFTER INSERT ON votes
  FOR EACH ROW EXECUTE FUNCTION handle_vote();

-- F5. Commentaire posté
CREATE OR REPLACE FUNCTION handle_comment_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE profiles SET comments_count = comments_count + 1 WHERE id = NEW.author_id;
  IF NEW.article_id IS NOT NULL THEN
    UPDATE articles SET comments_count = comments_count + 1 WHERE id = NEW.article_id;
    PERFORM recompute_article_scores(NEW.article_id);
  END IF;
  PERFORM recompute_user_cred(NEW.author_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_handle_comment_insert ON comments;
CREATE TRIGGER trg_handle_comment_insert
  AFTER INSERT ON comments
  FOR EACH ROW EXECUTE FUNCTION handle_comment_insert();

-- F6. Commentaire marqué "utile"
CREATE OR REPLACE FUNCTION handle_useful_comment()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_mod_cred INT;
  v_weight   NUMERIC;
BEGIN
  IF NEW.useful_marked = true AND (OLD.useful_marked IS NULL OR OLD.useful_marked = false) THEN
    SELECT credibility_score INTO v_mod_cred FROM profiles WHERE id = auth.uid();
    v_weight := COALESCE(v_mod_cred, 100)::NUMERIC / 100;
    UPDATE profiles
      SET weighted_useful_comments = weighted_useful_comments + v_weight
      WHERE id = NEW.author_id;
    INSERT INTO credibility_events(user_id, event_type, delta, actor_id, actor_cred, weight)
    VALUES (NEW.author_id, 'useful_comment', v_weight * 2, auth.uid(), v_mod_cred, v_weight);
    PERFORM recompute_user_cred(NEW.author_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_handle_useful_comment ON comments;
CREATE TRIGGER trg_handle_useful_comment
  AFTER UPDATE ON comments
  FOR EACH ROW EXECUTE FUNCTION handle_useful_comment();

-- F7. Signalement validé → malus
CREATE OR REPLACE FUNCTION handle_report_validated()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_reported_user UUID;
BEGIN
  IF NEW.validated = true AND (OLD.validated IS NULL OR OLD.validated = false) THEN
    IF NEW.comment_id IS NOT NULL THEN
      SELECT author_id INTO v_reported_user FROM comments WHERE id = NEW.comment_id;
    ELSIF NEW.target_type = 'article' THEN
      SELECT author_id INTO v_reported_user FROM articles WHERE id = NEW.target_id;
    ELSIF NEW.target_type = 'comment' THEN
      SELECT author_id INTO v_reported_user FROM comments WHERE id = NEW.target_id;
    END IF;

    IF v_reported_user IS NOT NULL THEN
      UPDATE profiles SET validated_reports = validated_reports + 1 WHERE id = v_reported_user;
      INSERT INTO credibility_events(user_id, event_type, delta, actor_id, note)
      VALUES (v_reported_user, 'report_validated', -5, NEW.reviewed_by, NEW.reason);
      PERFORM recompute_user_cred(v_reported_user);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_handle_report_validated ON reports;
CREATE TRIGGER trg_handle_report_validated
  AFTER UPDATE ON reports
  FOR EACH ROW EXECUTE FUNCTION handle_report_validated();


-- ═══════════════════════════════════════════════════════════════════════════
-- 8. RPC (appels côté client)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION get_trending_articles(
  p_period TEXT DEFAULT 'week',
  p_limit  INT  DEFAULT 8
)
RETURNS SETOF articles LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT * FROM articles
  WHERE status = 'published'
    AND CASE p_period
          WHEN 'today' THEN published_at >= now() - INTERVAL '1 day'
          WHEN 'week'  THEN published_at >= now() - INTERVAL '7 days'
          WHEN 'month' THEN published_at >= now() - INTERVAL '30 days'
          ELSE true
        END
  ORDER BY popularity_score DESC
  LIMIT p_limit;
$$;

CREATE OR REPLACE FUNCTION get_top_authors(p_limit INT DEFAULT 5)
RETURNS TABLE (
  author_id       UUID,
  username        TEXT,
  cred_score      INT,
  cred_level      TEXT,
  last_article_id UUID,
  last_title      TEXT,
  last_subtitle   TEXT,
  last_published  TIMESTAMPTZ
) LANGUAGE sql STABLE SECURITY DEFINER AS $$
  WITH last_art AS (
    SELECT DISTINCT ON (a.author_id)
      a.author_id, a.id, a.title, a.subtitle, a.published_at
    FROM articles a
    WHERE a.status = 'published'
    ORDER BY a.author_id, a.published_at DESC
  )
  SELECT
    la.author_id, p.username, p.credibility_score, p.credibility_level,
    la.id, la.title, la.subtitle, la.published_at
  FROM last_art la
  JOIN profiles p ON p.id = la.author_id
  ORDER BY p.credibility_score DESC
  LIMIT p_limit;
$$;

CREATE OR REPLACE FUNCTION increment_article_reads(p_article_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE articles SET reads = reads + 1 WHERE id = p_article_id;
  PERFORM recompute_article_scores(p_article_id);
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- 9. SEED DATA — article_themes & article_tones
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO article_themes (slug, label, emoji, display_order) VALUES
  ('autre',      'Autre',          '📌',  100),
  ('politique',  'Politique',      '🏛️',  10),
  ('societe',    'Société',        '👥',  20),
  ('economie',   'Économie',       '💰',  30),
  ('international', 'International','🌍',  40),
  ('sciences',   'Sciences',       '🔬',  50),
  ('tech',       'Tech',           '💻',  60),
  ('environnement','Environnement','🌱',  70),
  ('culture',    'Culture',        '🎨',  80),
  ('sport',      'Sport',          '⚽',  90)
ON CONFLICT (slug) DO UPDATE
  SET label = EXCLUDED.label,
      emoji = EXCLUDED.emoji,
      display_order = EXCLUDED.display_order;

INSERT INTO article_tones (slug, label, emoji, display_order) VALUES
  ('analyse',     'Analyse',     '🔍',  10),
  ('enquete',     'Enquête',     '🕵️',  20),
  ('explication', 'Explication', '📖',  30),
  ('opinion',     'Opinion',     '💭',  40),
  ('factuel',     'Factuel',     '📊',  50),
  ('verification','Vérification','✅',  60)
ON CONFLICT (slug) DO UPDATE
  SET label = EXCLUDED.label,
      emoji = EXCLUDED.emoji,
      display_order = EXCLUDED.display_order;


-- ═══════════════════════════════════════════════════════════════════════════
-- 10. RECALCUL INITIAL
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_uid UUID;
  v_aid UUID;
BEGIN
  FOR v_uid IN SELECT id FROM profiles LOOP
    PERFORM recompute_user_cred(v_uid);
  END LOOP;
  FOR v_aid IN SELECT id FROM articles LOOP
    PERFORM recompute_article_scores(v_aid);
  END LOOP;
END $$;
