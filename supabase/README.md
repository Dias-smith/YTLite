# Supabase (YTLite)

## Account deletion (Apple 5.1.1(v))

Edge Function: `functions/delete-account`

```bash
supabase functions deploy delete-account
```

iOS calls `POST /functions/v1/delete-account` with the signed-in user's access token.
The function deletes `user_track_metadata`, clears `playlist-covers/{user_id}/`, then
`auth.admin.deleteUser` (CASCADE removes other user-scoped rows).
