-- ==========================================
-- User subscribed channels (YTLite Library Channels)
-- Local subscribe only; not YouTube Data API subscriptions.
-- ==========================================

CREATE TABLE IF NOT EXISTS user_subscribed_channels (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  channel_id TEXT NOT NULL,
  title TEXT NOT NULL,
  handle TEXT,
  avatar_url TEXT,
  subscriber_count_text TEXT,
  description TEXT,
  subscribed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, channel_id)
);

CREATE INDEX IF NOT EXISTS idx_user_subscribed_channels_user_subscribed_at
  ON user_subscribed_channels(user_id, subscribed_at DESC);

CREATE TRIGGER set_timestamp_user_subscribed_channels
  BEFORE UPDATE ON user_subscribed_channels
  FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

ALTER TABLE user_subscribed_channels ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_subscribed_channels_select_own ON user_subscribed_channels
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY user_subscribed_channels_insert_own ON user_subscribed_channels
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY user_subscribed_channels_update_own ON user_subscribed_channels
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY user_subscribed_channels_delete_own ON user_subscribed_channels
  FOR DELETE USING (auth.uid() = user_id);
