-- Run in Supabase SQL editor for user-specific track metadata overrides.
create table if not exists public.user_track_metadata (
    user_id text not null,
    track_id text not null,
    custom_title text,
    custom_artist_name text,
    custom_thumbnail_url text,
    custom_album text,
    custom_year text,
    updated_at timestamptz not null default now(),
    primary key (user_id, track_id)
);

alter table public.user_track_metadata enable row level security;

create policy "Users can read own track metadata"
    on public.user_track_metadata for select
    using (auth.uid()::text = user_id);

create policy "Users can insert own track metadata"
    on public.user_track_metadata for insert
    with check (auth.uid()::text = user_id);

create policy "Users can update own track metadata"
    on public.user_track_metadata for update
    using (auth.uid()::text = user_id);

create policy "Users can delete own track metadata"
    on public.user_track_metadata for delete
    using (auth.uid()::text = user_id);
