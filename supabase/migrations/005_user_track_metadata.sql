-- ==========================================
-- User track metadata (parity with Android UserTrackMetadataEntity)
-- Previously lived only in supabase/user_track_metadata.sql
-- ==========================================

CREATE TABLE IF NOT EXISTS public.user_track_metadata (
  user_id TEXT NOT NULL,
  track_id TEXT NOT NULL,
  custom_title TEXT,
  custom_artist_name TEXT,
  custom_thumbnail_url TEXT,
  custom_album TEXT,
  custom_year TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, track_id)
);

ALTER TABLE public.user_track_metadata ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own track metadata" ON public.user_track_metadata;
DROP POLICY IF EXISTS "Users can insert own track metadata" ON public.user_track_metadata;
DROP POLICY IF EXISTS "Users can update own track metadata" ON public.user_track_metadata;
DROP POLICY IF EXISTS "Users can delete own track metadata" ON public.user_track_metadata;

CREATE POLICY "Users can read own track metadata"
  ON public.user_track_metadata FOR SELECT
  USING (auth.uid()::text = user_id);

CREATE POLICY "Users can insert own track metadata"
  ON public.user_track_metadata FOR INSERT
  WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY "Users can update own track metadata"
  ON public.user_track_metadata FOR UPDATE
  USING (auth.uid()::text = user_id);

CREATE POLICY "Users can delete own track metadata"
  ON public.user_track_metadata FOR DELETE
  USING (auth.uid()::text = user_id);
