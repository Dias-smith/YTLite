-- ==========================================
-- Playlist cover images (Supabase Storage)
-- Path convention: {user_id}/{playlist_id}.jpg
-- ==========================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'playlist-covers',
  'playlist-covers',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Anyone can read (bucket is public; covers shown in library UI).
DROP POLICY IF EXISTS "playlist_covers_select" ON storage.objects;
CREATE POLICY "playlist_covers_select"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'playlist-covers');

-- Authenticated users may write only under their own user_id folder.
DROP POLICY IF EXISTS "playlist_covers_insert_own" ON storage.objects;
CREATE POLICY "playlist_covers_insert_own"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'playlist-covers'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "playlist_covers_update_own" ON storage.objects;
CREATE POLICY "playlist_covers_update_own"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'playlist-covers'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'playlist-covers'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "playlist_covers_delete_own" ON storage.objects;
CREATE POLICY "playlist_covers_delete_own"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'playlist-covers'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
