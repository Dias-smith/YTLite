-- ==========================================
-- YTLite Library Schema — Phase 1
-- Replaces flat watch_history / liked_videos / watch_later
-- ==========================================

-- ------------------------------------------
-- 0. 通用 updated_at 触发器
-- ------------------------------------------
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------
-- 1. 艺术家 / 频道（全局目录，无 user_id）
-- ------------------------------------------
CREATE TABLE artists (
  artist_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  avatar_url TEXT,
  banner_url TEXT,
  subscriber_count BIGINT,
  subscriber_count_text TEXT,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_timestamp_artists
  BEFORE UPDATE ON artists
  FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- ------------------------------------------
-- 2. 歌曲 / 视频主表（全局目录）
-- ------------------------------------------
CREATE TABLE tracks (
  track_id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  duration_seconds INT NOT NULL DEFAULT 0,
  duration_text TEXT,
  thumbnail_low TEXT,
  thumbnail_medium TEXT,
  thumbnail_high TEXT,
  view_count BIGINT DEFAULT 0,
  view_count_text TEXT,
  published_text TEXT,
  primary_artist_id TEXT REFERENCES artists(artist_id) ON DELETE SET NULL,
  primary_artist_name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_timestamp_tracks
  BEFORE UPDATE ON tracks
  FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

CREATE INDEX idx_tracks_primary_artist ON tracks(primary_artist_id);

-- ------------------------------------------
-- 3. 歌单（用户私有，含系统歌单）
-- ------------------------------------------
CREATE TABLE playlists (
  playlist_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  cover_url_or_path TEXT,
  description TEXT,
  system_type TEXT CHECK (
    system_type IS NULL
    OR system_type IN ('favorites', 'watch_later', 'downloads')
  ),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_playlists_user_system_type
  ON playlists(user_id, system_type)
  WHERE system_type IS NOT NULL;

CREATE INDEX idx_playlists_user_id ON playlists(user_id);

CREATE TRIGGER set_timestamp_playlists
  BEFORE UPDATE ON playlists
  FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- ------------------------------------------
-- 4. 歌单-歌曲中间表
-- ------------------------------------------
CREATE TABLE playlist_track_cross_ref (
  playlist_id UUID NOT NULL REFERENCES playlists(playlist_id) ON DELETE CASCADE,
  track_id TEXT NOT NULL REFERENCES tracks(track_id) ON DELETE CASCADE,
  position INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (playlist_id, track_id)
);

CREATE INDEX idx_playlist_track_position
  ON playlist_track_cross_ref(playlist_id, position);

CREATE TRIGGER set_timestamp_playlist_track_cross_ref
  BEFORE UPDATE ON playlist_track_cross_ref
  FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- ------------------------------------------
-- 5. 播放历史明细（每次播放一条）
-- ------------------------------------------
CREATE TABLE playback_history (
  history_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  track_id TEXT NOT NULL REFERENCES tracks(track_id) ON DELETE CASCADE,
  played_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  progress_ms BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_playback_history_user_played_at
  ON playback_history(user_id, played_at DESC);

CREATE TRIGGER set_timestamp_playback_history
  BEFORE UPDATE ON playback_history
  FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- ------------------------------------------
-- 6. 用户最近播放汇总（Library 横向列表高频读）
-- ------------------------------------------
CREATE TABLE user_track_last_played (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  track_id TEXT NOT NULL REFERENCES tracks(track_id) ON DELETE CASCADE,
  last_played_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  progress_ms BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, track_id)
);

CREATE INDEX idx_user_track_last_played_time
  ON user_track_last_played(user_id, last_played_at DESC);

CREATE TRIGGER set_timestamp_user_track_last_played
  BEFORE UPDATE ON user_track_last_played
  FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- ------------------------------------------
-- 7. 用户资料（对齐 auth.users）
-- ------------------------------------------
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL DEFAULT '',
  handle TEXT UNIQUE,
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_timestamp_profiles
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

CREATE OR REPLACE FUNCTION seed_system_playlists()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO playlists (user_id, name, system_type) VALUES
    (NEW.id, 'Liked videos', 'favorites'),
    (NEW.id, 'Watch later', 'watch_later');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_profile_created_seed_playlists
  AFTER INSERT ON profiles
  FOR EACH ROW EXECUTE FUNCTION seed_system_playlists();

-- ------------------------------------------
-- 8. Row Level Security
-- ------------------------------------------
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE artists ENABLE ROW LEVEL SECURITY;
ALTER TABLE tracks ENABLE ROW LEVEL SECURITY;
ALTER TABLE playlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE playlist_track_cross_ref ENABLE ROW LEVEL SECURITY;
ALTER TABLE playback_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_track_last_played ENABLE ROW LEVEL SECURITY;

CREATE POLICY profiles_select_own ON profiles
  FOR SELECT USING (auth.uid() = id);
CREATE POLICY profiles_insert_own ON profiles
  FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY profiles_update_own ON profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY artists_select_auth ON artists
  FOR SELECT TO authenticated USING (true);
CREATE POLICY artists_insert_auth ON artists
  FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY artists_update_auth ON artists
  FOR UPDATE TO authenticated USING (true);

CREATE POLICY tracks_select_auth ON tracks
  FOR SELECT TO authenticated USING (true);
CREATE POLICY tracks_insert_auth ON tracks
  FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY tracks_update_auth ON tracks
  FOR UPDATE TO authenticated USING (true);

CREATE POLICY playlists_all_own ON playlists
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY playlist_track_all_own ON playlist_track_cross_ref
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM playlists p
      WHERE p.playlist_id = playlist_track_cross_ref.playlist_id
        AND p.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM playlists p
      WHERE p.playlist_id = playlist_track_cross_ref.playlist_id
        AND p.user_id = auth.uid()
    )
  );

CREATE POLICY playback_history_all_own ON playback_history
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY user_track_last_played_all_own ON user_track_last_played
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
