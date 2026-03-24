create schema if not exists easysearch;

grant usage on schema easysearch to authenticated;
grant select, insert, update, delete on all tables in schema easysearch to authenticated;
alter default privileges in schema easysearch
    grant select, insert, update, delete on tables to authenticated;

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
