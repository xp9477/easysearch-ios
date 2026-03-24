create schema if not exists easysearch;

grant usage on schema easysearch to authenticated;
grant select, insert, update, delete on all tables in schema easysearch to authenticated;
alter default privileges in schema easysearch
    grant select, insert, update, delete on tables to authenticated;

create table if not exists easysearch.github_repo_watches (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    repo_id text not null,
    owner text not null,
    name text not null,
    full_name text not null,
    html_url text not null,
    repo_description text not null default '',
    default_branch text not null default 'main',
    is_archived boolean not null default false,
    is_disabled boolean not null default false,
    last_known_pushed_at timestamptz,
    last_checked_at timestamptz,
    last_notified_pushed_at timestamptz,
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now()),
    primary key (user_id, repo_id)
);

create index if not exists github_repo_watches_user_updated_at_idx
    on easysearch.github_repo_watches (user_id, updated_at desc);

alter table easysearch.github_repo_watches enable row level security;

drop policy if exists "github_repo_watches_select_own" on easysearch.github_repo_watches;
create policy "github_repo_watches_select_own"
    on easysearch.github_repo_watches
    for select
    using (auth.uid() = user_id);

drop policy if exists "github_repo_watches_insert_own" on easysearch.github_repo_watches;
create policy "github_repo_watches_insert_own"
    on easysearch.github_repo_watches
    for insert
    with check (auth.uid() = user_id);

drop policy if exists "github_repo_watches_update_own" on easysearch.github_repo_watches;
create policy "github_repo_watches_update_own"
    on easysearch.github_repo_watches
    for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "github_repo_watches_delete_own" on easysearch.github_repo_watches;
create policy "github_repo_watches_delete_own"
    on easysearch.github_repo_watches
    for delete
    using (auth.uid() = user_id);
