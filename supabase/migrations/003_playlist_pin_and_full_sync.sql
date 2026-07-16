-- ==========================================
-- YTLite Library Schema — Phase 1.6
-- Playlist pin state + full LOCAL playlist sync support
-- ==========================================

ALTER TABLE playlists
  ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_playlists_user_pinned_updated
  ON playlists(user_id, is_pinned DESC, updated_at DESC);

COMMENT ON COLUMN playlists.is_pinned IS
  '客户端 Pin 状态，跨设备同步；仅 LOCAL 歌单（系统 + 自定义）。YouTube 官方歌单不入库。';
