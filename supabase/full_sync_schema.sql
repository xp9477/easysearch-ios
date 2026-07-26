create schema if not exists easysearch;

grant usage on schema easysearch to authenticated;
grant select, insert, update, delete on all tables in schema easysearch to authenticated;
alter default privileges in schema easysearch
    grant select, insert, update, delete on tables to authenticated;

drop table if exists easysearch.missav_favorite_markers;
drop table if exists easysearch.missav_favorites;

create table if not exists easysearch.jav_favorites (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    movie_id text not null,
    movie_url text not null,
    code text not null,
    title text not null,
    cover_url text not null,
    actresses text[] not null default '{}'::text[],
    created_at timestamptz not null default timezone('utc', now()),
    primary key (user_id, movie_id)
);

create index if not exists jav_favorites_user_created_at_idx
    on easysearch.jav_favorites (user_id, created_at desc);

alter table easysearch.jav_favorites enable row level security;

drop policy if exists "jav_favorites_select_own" on easysearch.jav_favorites;
create policy "jav_favorites_select_own"
    on easysearch.jav_favorites
    for select
    using (auth.uid() = user_id);

drop policy if exists "jav_favorites_insert_own" on easysearch.jav_favorites;
create policy "jav_favorites_insert_own"
    on easysearch.jav_favorites
    for insert
    with check (auth.uid() = user_id);

drop policy if exists "jav_favorites_update_own" on easysearch.jav_favorites;
create policy "jav_favorites_update_own"
    on easysearch.jav_favorites
    for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "jav_favorites_delete_own" on easysearch.jav_favorites;
create policy "jav_favorites_delete_own"
    on easysearch.jav_favorites
    for delete
    using (auth.uid() = user_id);

create table if not exists easysearch.jav_playbacks (
    id uuid primary key,
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    movie_id text not null,
    movie_url text not null,
    code text not null,
    title text not null,
    cover_url text not null,
    actresses text[] not null default '{}'::text[],
    source_name text not null,
    stream_url text not null,
    referer_url text not null,
    position_seconds double precision not null check (position_seconds >= 0),
    created_at timestamptz not null default timezone('utc', now())
);

create index if not exists jav_playbacks_user_created_at_idx
    on easysearch.jav_playbacks (user_id, created_at desc);

alter table easysearch.jav_playbacks enable row level security;

drop policy if exists "jav_playbacks_select_own" on easysearch.jav_playbacks;
create policy "jav_playbacks_select_own"
    on easysearch.jav_playbacks
    for select
    using (auth.uid() = user_id);

drop policy if exists "jav_playbacks_insert_own" on easysearch.jav_playbacks;
create policy "jav_playbacks_insert_own"
    on easysearch.jav_playbacks
    for insert
    with check (auth.uid() = user_id);

drop policy if exists "jav_playbacks_update_own" on easysearch.jav_playbacks;
create policy "jav_playbacks_update_own"
    on easysearch.jav_playbacks
    for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "jav_playbacks_delete_own" on easysearch.jav_playbacks;
create policy "jav_playbacks_delete_own"
    on easysearch.jav_playbacks
    for delete
    using (auth.uid() = user_id);

create table if not exists easysearch.fourkhd_favorite_albums (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    album_id text not null,
    album_url text not null,
    title text not null,
    cover_url text not null,
    created_at timestamptz not null default timezone('utc', now()),
    primary key (user_id, album_id)
);

create index if not exists fourkhd_favorite_albums_user_created_at_idx
    on easysearch.fourkhd_favorite_albums (user_id, created_at desc);

alter table easysearch.fourkhd_favorite_albums enable row level security;

drop policy if exists "fourkhd_favorite_albums_select_own" on easysearch.fourkhd_favorite_albums;
create policy "fourkhd_favorite_albums_select_own"
    on easysearch.fourkhd_favorite_albums
    for select
    using (auth.uid() = user_id);

drop policy if exists "fourkhd_favorite_albums_insert_own" on easysearch.fourkhd_favorite_albums;
create policy "fourkhd_favorite_albums_insert_own"
    on easysearch.fourkhd_favorite_albums
    for insert
    with check (auth.uid() = user_id);

drop policy if exists "fourkhd_favorite_albums_update_own" on easysearch.fourkhd_favorite_albums;
create policy "fourkhd_favorite_albums_update_own"
    on easysearch.fourkhd_favorite_albums
    for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "fourkhd_favorite_albums_delete_own" on easysearch.fourkhd_favorite_albums;
create policy "fourkhd_favorite_albums_delete_own"
    on easysearch.fourkhd_favorite_albums
    for delete
    using (auth.uid() = user_id);

create table if not exists easysearch.fourkhd_favorite_images (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    image_id text not null,
    image_url text not null,
    created_at timestamptz not null default timezone('utc', now()),
    primary key (user_id, image_id)
);

create index if not exists fourkhd_favorite_images_user_created_at_idx
    on easysearch.fourkhd_favorite_images (user_id, created_at desc);

alter table easysearch.fourkhd_favorite_images enable row level security;

drop policy if exists "fourkhd_favorite_images_select_own" on easysearch.fourkhd_favorite_images;
create policy "fourkhd_favorite_images_select_own"
    on easysearch.fourkhd_favorite_images
    for select
    using (auth.uid() = user_id);

drop policy if exists "fourkhd_favorite_images_insert_own" on easysearch.fourkhd_favorite_images;
create policy "fourkhd_favorite_images_insert_own"
    on easysearch.fourkhd_favorite_images
    for insert
    with check (auth.uid() = user_id);

drop policy if exists "fourkhd_favorite_images_update_own" on easysearch.fourkhd_favorite_images;
create policy "fourkhd_favorite_images_update_own"
    on easysearch.fourkhd_favorite_images
    for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "fourkhd_favorite_images_delete_own" on easysearch.fourkhd_favorite_images;
create policy "fourkhd_favorite_images_delete_own"
    on easysearch.fourkhd_favorite_images
    for delete
    using (auth.uid() = user_id);

create table if not exists easysearch.ut_entries (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    entry_id uuid not null,
    entry_date timestamptz not null,
    hours double precision not null check (hours >= 0),
    note text not null default '',
    created_at timestamptz not null default timezone('utc', now()),
    primary key (user_id, entry_id)
);

create index if not exists ut_entries_user_created_at_idx
    on easysearch.ut_entries (user_id, created_at desc);

alter table easysearch.ut_entries enable row level security;

drop policy if exists "ut_entries_select_own" on easysearch.ut_entries;
create policy "ut_entries_select_own"
    on easysearch.ut_entries
    for select
    using (auth.uid() = user_id);

drop policy if exists "ut_entries_insert_own" on easysearch.ut_entries;
create policy "ut_entries_insert_own"
    on easysearch.ut_entries
    for insert
    with check (auth.uid() = user_id);

drop policy if exists "ut_entries_update_own" on easysearch.ut_entries;
create policy "ut_entries_update_own"
    on easysearch.ut_entries
    for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "ut_entries_delete_own" on easysearch.ut_entries;
create policy "ut_entries_delete_own"
    on easysearch.ut_entries
    for delete
    using (auth.uid() = user_id);

create table if not exists easysearch.qinglong_panel_profiles (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    profile_id text not null,
    base_url text not null,
    display_name text not null,
    saved_at timestamptz not null,
    last_connected_at timestamptz,
    primary key (user_id, profile_id)
);

create index if not exists qinglong_panel_profiles_user_saved_at_idx
    on easysearch.qinglong_panel_profiles (user_id, saved_at desc);

alter table easysearch.qinglong_panel_profiles enable row level security;

drop policy if exists "qinglong_panel_profiles_select_own" on easysearch.qinglong_panel_profiles;
create policy "qinglong_panel_profiles_select_own"
    on easysearch.qinglong_panel_profiles
    for select
    using (auth.uid() = user_id);

drop policy if exists "qinglong_panel_profiles_insert_own" on easysearch.qinglong_panel_profiles;
create policy "qinglong_panel_profiles_insert_own"
    on easysearch.qinglong_panel_profiles
    for insert
    with check (auth.uid() = user_id);

drop policy if exists "qinglong_panel_profiles_update_own" on easysearch.qinglong_panel_profiles;
create policy "qinglong_panel_profiles_update_own"
    on easysearch.qinglong_panel_profiles
    for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "qinglong_panel_profiles_delete_own" on easysearch.qinglong_panel_profiles;
create policy "qinglong_panel_profiles_delete_own"
    on easysearch.qinglong_panel_profiles
    for delete
    using (auth.uid() = user_id);

-- Training + expense (also in training_expense_sync.sql)
create table if not exists easysearch.training_log_days (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    day_id text not null,
    day_start timestamptz not null,
    note text not null default '',
    lines jsonb not null default '[]'::jsonb,
    updated_at timestamptz not null default timezone('utc', now()),
    primary key (user_id, day_id)
);

create index if not exists training_log_days_user_updated_at_idx
    on easysearch.training_log_days (user_id, updated_at desc);

alter table easysearch.training_log_days enable row level security;

drop policy if exists "training_log_days_select_own" on easysearch.training_log_days;
create policy "training_log_days_select_own"
    on easysearch.training_log_days for select using (auth.uid() = user_id);

drop policy if exists "training_log_days_insert_own" on easysearch.training_log_days;
create policy "training_log_days_insert_own"
    on easysearch.training_log_days for insert with check (auth.uid() = user_id);

drop policy if exists "training_log_days_update_own" on easysearch.training_log_days;
create policy "training_log_days_update_own"
    on easysearch.training_log_days for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "training_log_days_delete_own" on easysearch.training_log_days;
create policy "training_log_days_delete_own"
    on easysearch.training_log_days for delete using (auth.uid() = user_id);

create table if not exists easysearch.expense_monthly_claims (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    claim_id text not null,
    month_start timestamptz not null,
    taxi text not null,
    parking text not null,
    phone_bill text not null,
    misc text not null,
    updated_at timestamptz not null default timezone('utc', now()),
    primary key (user_id, claim_id)
);

create index if not exists expense_monthly_claims_user_month_idx
    on easysearch.expense_monthly_claims (user_id, month_start desc);

alter table easysearch.expense_monthly_claims enable row level security;

drop policy if exists "expense_monthly_claims_select_own" on easysearch.expense_monthly_claims;
create policy "expense_monthly_claims_select_own"
    on easysearch.expense_monthly_claims for select using (auth.uid() = user_id);

drop policy if exists "expense_monthly_claims_insert_own" on easysearch.expense_monthly_claims;
create policy "expense_monthly_claims_insert_own"
    on easysearch.expense_monthly_claims for insert with check (auth.uid() = user_id);

drop policy if exists "expense_monthly_claims_update_own" on easysearch.expense_monthly_claims;
create policy "expense_monthly_claims_update_own"
    on easysearch.expense_monthly_claims for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "expense_monthly_claims_delete_own" on easysearch.expense_monthly_claims;
create policy "expense_monthly_claims_delete_own"
    on easysearch.expense_monthly_claims for delete using (auth.uid() = user_id);

create table if not exists easysearch.expense_travel_claims (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    claim_id uuid not null,
    title text not null default '',
    start_date timestamptz not null,
    end_date timestamptz,
    travel_approval_status text not null,
    per_diem_status text not null,
    expense_status text not null,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    primary key (user_id, claim_id)
);

create index if not exists expense_travel_claims_user_updated_at_idx
    on easysearch.expense_travel_claims (user_id, updated_at desc);

alter table easysearch.expense_travel_claims enable row level security;

drop policy if exists "expense_travel_claims_select_own" on easysearch.expense_travel_claims;
create policy "expense_travel_claims_select_own"
    on easysearch.expense_travel_claims for select using (auth.uid() = user_id);

drop policy if exists "expense_travel_claims_insert_own" on easysearch.expense_travel_claims;
create policy "expense_travel_claims_insert_own"
    on easysearch.expense_travel_claims for insert with check (auth.uid() = user_id);

drop policy if exists "expense_travel_claims_update_own" on easysearch.expense_travel_claims;
create policy "expense_travel_claims_update_own"
    on easysearch.expense_travel_claims for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "expense_travel_claims_delete_own" on easysearch.expense_travel_claims;
create policy "expense_travel_claims_delete_own"
    on easysearch.expense_travel_claims for delete using (auth.uid() = user_id);
