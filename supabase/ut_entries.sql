create schema if not exists easysearch;

grant usage on schema easysearch to authenticated;
grant select, insert, update, delete on all tables in schema easysearch to authenticated;
alter default privileges in schema easysearch
    grant select, insert, update, delete on tables to authenticated;

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
