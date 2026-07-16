-- ==========================================
-- YTLite Library Schema — Phase 1.5
-- YouTube × Local Data Fusion (Supabase 侧兼容)
--
-- 前置条件：已执行 001_library_schema.sql
-- 设计原则：
--   • YouTube 官方歌单只读、仅存于客户端内存，不同步到 Supabase
--   • Supabase 仅持久化 LOCAL 歌单（含系统歌单 favorites / watch_later）
--   • playlist_id 为 UUID 类型，天然拒绝 YT_PL_* 前缀的 YouTube ID
--   • progress_ms 为播放进度唯一单位（毫秒）
-- ==========================================

-- ------------------------------------------
-- 1. 表注释（架构文档化）
-- ------------------------------------------
COMMENT ON TABLE playlists IS
  '用户可同步的本地歌单。YouTube 官方歌单（客户端 source=YOUTUBE）只读缓存，不入库。'
  '克隆到本地后生成新 UUID 歌单，按普通 LOCAL 歌单同步。';

COMMENT ON TABLE playback_history IS
  '每次开始播放插入一条明细；progress_ms 为毫秒，高频进度更新写 user_track_last_played。';

COMMENT ON TABLE user_track_last_played IS
  'Library 历史横向列表数据源；按 last_played_at 降序，progress_ms 支持续播。';

COMMENT ON COLUMN playlists.system_type IS
  '系统歌单：favorites | watch_later | downloads；自定义歌单为 NULL。';

COMMENT ON COLUMN playlists.updated_at IS
  '融合排序键：与客户端 Room playlists.updatedAt 对齐，用于云侧歌单列表排序。';

-- ------------------------------------------
-- 2. 索引优化（对齐客户端查询模式）
-- ------------------------------------------

-- 融合列表排序：本地歌单按 updated_at 降序（对应 Room observeLocalByOwner）
CREATE INDEX IF NOT EXISTS idx_playlists_user_updated_at
  ON playlists(user_id, updated_at DESC);

-- 用户自定义歌单（排除系统歌单）
CREATE INDEX IF NOT EXISTS idx_playlists_user_custom_updated
  ON playlists(user_id, updated_at DESC)
  WHERE system_type IS NULL;

-- Library 历史：user_track_last_played 按时间拉取
-- （001 已有 idx_user_track_last_played_time，此处补充 track 维度查询）
CREATE INDEX IF NOT EXISTS idx_user_track_last_played_track
  ON user_track_last_played(user_id, track_id);

-- 播放历史：按用户+曲目查最近记录（可选 30s / onPause 更新 progress_ms）
CREATE INDEX IF NOT EXISTS idx_playback_history_user_track_played
  ON playback_history(user_id, track_id, played_at DESC);

-- ------------------------------------------
-- 3. 扩展：pg_trgm（曲目标题模糊搜索，可选）
-- ------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_tracks_title_trgm
  ON tracks USING gin (title gin_trgm_ops);

-- ------------------------------------------
-- 4. 为已有用户补全系统歌单（幂等）
--    对应客户端 ensureSystemPlaylists + 融合后 LOCAL 系统歌单
-- ------------------------------------------
INSERT INTO playlists (user_id, name, system_type)
SELECT p.id, 'Liked videos', 'favorites'
FROM profiles p
WHERE NOT EXISTS (
  SELECT 1 FROM playlists pl
  WHERE pl.user_id = p.id AND pl.system_type = 'favorites'
);

INSERT INTO playlists (user_id, name, system_type)
SELECT p.id, 'Watch later', 'watch_later'
FROM profiles p
WHERE NOT EXISTS (
  SELECT 1 FROM playlists pl
  WHERE pl.user_id = p.id AND pl.system_type = 'watch_later'
);

-- ------------------------------------------
-- 5. 旧版扁平表迁移（仅当仍存在时执行）
--    从 watch_history / liked_videos / watch_later 迁入规范化 schema
-- ------------------------------------------
DO $$
BEGIN
  -- 5a. watch_history → tracks + user_track_last_played + playback_history
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'watch_history'
  ) THEN
    -- 迁入 tracks（去重）
    INSERT INTO tracks (track_id, title, thumbnail_high, primary_artist_name)
    SELECT DISTINCT ON (video_id)
      video_id,
      COALESCE(title, ''),
      thumbnail_url,
      COALESCE(channel_name, '')
    FROM watch_history
    WHERE video_id IS NOT NULL AND video_id <> ''
    ON CONFLICT (track_id) DO NOTHING;

    -- 迁入 user_track_last_played
    INSERT INTO user_track_last_played (user_id, track_id, last_played_at, progress_ms)
    SELECT
      wh.user_id,
      wh.video_id,
      COALESCE(wh.watched_at, NOW()),
      COALESCE(wh.progress_ms, 0)
    FROM (
      SELECT DISTINCT ON (user_id, video_id)
        user_id, video_id, watched_at, progress_ms
      FROM watch_history
      WHERE video_id IS NOT NULL AND video_id <> ''
      ORDER BY user_id, video_id, watched_at DESC
    ) wh
    ON CONFLICT (user_id, track_id) DO UPDATE SET
      last_played_at = GREATEST(
        user_track_last_played.last_played_at,
        EXCLUDED.last_played_at
      ),
      progress_ms = EXCLUDED.progress_ms;

    -- 迁入 playback_history 明细（旧表每用户每视频仅一条，直接迁移）
    INSERT INTO playback_history (user_id, track_id, played_at, progress_ms)
    SELECT
      user_id,
      video_id,
      COALESCE(watched_at, NOW()),
      COALESCE(progress_ms, 0)
    FROM watch_history
    WHERE video_id IS NOT NULL AND video_id <> '';

    DROP TABLE watch_history CASCADE;
  END IF;

  -- 5b. liked_videos → favorites 系统歌单 + playlist_track_cross_ref
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'liked_videos'
  ) THEN
    INSERT INTO tracks (track_id, title, thumbnail_high, primary_artist_name)
    SELECT DISTINCT ON (video_id)
      video_id,
      COALESCE(title, ''),
      thumbnail_url,
      COALESCE(channel_name, '')
    FROM liked_videos
    WHERE video_id IS NOT NULL AND video_id <> ''
    ON CONFLICT (track_id) DO NOTHING;

    INSERT INTO playlist_track_cross_ref (playlist_id, track_id, position)
    SELECT
      pl.playlist_id,
      lv.video_id,
      ROW_NUMBER() OVER (PARTITION BY lv.user_id ORDER BY lv.liked_at DESC NULLS LAST) - 1
    FROM liked_videos lv
    JOIN playlists pl
      ON pl.user_id = lv.user_id AND pl.system_type = 'favorites'
    WHERE lv.video_id IS NOT NULL AND lv.video_id <> ''
    ON CONFLICT (playlist_id, track_id) DO NOTHING;

    DROP TABLE liked_videos CASCADE;
  END IF;

  -- 5c. watch_later → watch_later 系统歌单 + playlist_track_cross_ref
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'watch_later'
  ) THEN
    INSERT INTO tracks (track_id, title, thumbnail_high, primary_artist_name)
    SELECT DISTINCT ON (video_id)
      video_id,
      COALESCE(title, ''),
      thumbnail_url,
      COALESCE(channel_name, '')
    FROM watch_later
    WHERE video_id IS NOT NULL AND video_id <> ''
    ON CONFLICT (track_id) DO NOTHING;

    INSERT INTO playlist_track_cross_ref (playlist_id, track_id, position)
    SELECT
      pl.playlist_id,
      wl.video_id,
      ROW_NUMBER() OVER (PARTITION BY wl.user_id ORDER BY wl.added_at DESC NULLS LAST) - 1
    FROM watch_later wl
    JOIN playlists pl
      ON pl.user_id = wl.user_id AND pl.system_type = 'watch_later'
    WHERE wl.video_id IS NOT NULL AND wl.video_id <> ''
    ON CONFLICT (playlist_id, track_id) DO NOTHING;

    DROP TABLE watch_later CASCADE;
  END IF;
END $$;

-- ------------------------------------------
-- 6. RLS 补充：匿名用户不可写全局目录（可选加固）
-- ------------------------------------------
-- artists / tracks 在 001 中已允许 authenticated 读写；
-- 融合后仍由客户端 upsert 目录数据，策略保持不变。
