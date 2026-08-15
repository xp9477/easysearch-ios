-- Training log + expense assistant cloud tables (run on Supabase).

create schema if not exists easysearch;

grant usage on schema easysearch to authenticated;
grant select, insert, update, delete on all tables in schema easysearch to authenticated;
alter default privileges in schema easysearch
    grant select, insert, update, delete on tables to authenticated;

-- Training days (one row per calendar day)
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
revoke all on table easysearch.training_log_days from anon;
grant select, insert, update, delete on table easysearch.training_log_days to authenticated;

drop policy if exists "training_log_days_select_own" on easysearch.training_log_days;
create policy "training_log_days_select_own"
    on easysearch.training_log_days for select to authenticated
    using ((select auth.uid()) = user_id);

drop policy if exists "training_log_days_insert_own" on easysearch.training_log_days;
create policy "training_log_days_insert_own"
    on easysearch.training_log_days for insert to authenticated
    with check ((select auth.uid()) = user_id);

drop policy if exists "training_log_days_update_own" on easysearch.training_log_days;
create policy "training_log_days_update_own"
    on easysearch.training_log_days for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

drop policy if exists "training_log_days_delete_own" on easysearch.training_log_days;
create policy "training_log_days_delete_own"
    on easysearch.training_log_days for delete to authenticated
    using ((select auth.uid()) = user_id);

-- LWW guard: an offline/older client must not overwrite a newer edit or tombstone.
create or replace function easysearch.keep_newest_training_log_day()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
    -- A delete is an explicit user action. Stamp live -> tombstone transitions on
    -- the server so a device with a slow clock can still delete a newer row.
    if jsonb_array_length(new.lines) = 0
       and btrim(coalesce(new.note, '')) = ''
       and not (
           jsonb_array_length(old.lines) = 0
           and btrim(coalesce(old.note, '')) = ''
       ) then
        new.updated_at := greatest(
            new.updated_at,
            old.updated_at + interval '1 microsecond',
            clock_timestamp()
        );
    end if;

    if new.updated_at < old.updated_at then
        return old;
    end if;

    -- On equal clocks, a tombstone is monotonic and cannot be replaced by live data.
    if new.updated_at = old.updated_at
       and jsonb_array_length(old.lines) = 0
       and btrim(coalesce(old.note, '')) = ''
       and not (
           jsonb_array_length(new.lines) = 0
           and btrim(coalesce(new.note, '')) = ''
       ) then
        return old;
    end if;

    return new;
end;
$$;

drop trigger if exists training_log_days_keep_newest on easysearch.training_log_days;
create trigger training_log_days_keep_newest
    before update on easysearch.training_log_days
    for each row execute function easysearch.keep_newest_training_log_day();

-- Compatibility for installed clients that still issue DELETE: recreate the row as
-- an empty, newer tombstone. Service-role/cascade deletes have no auth.uid() and
-- remain true deletes, so account removal is not blocked.
create or replace function easysearch.tombstone_deleted_training_log_day()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
    if auth.uid() is null or auth.uid() <> old.user_id then
        return old;
    end if;

    insert into easysearch.training_log_days (
        user_id, day_id, day_start, note, lines, updated_at
    ) values (
        old.user_id,
        old.day_id,
        old.day_start,
        '',
        '[]'::jsonb,
        greatest(old.updated_at + interval '1 microsecond', clock_timestamp())
    )
    on conflict (user_id, day_id) do update
    set note = excluded.note,
        lines = excluded.lines,
        updated_at = excluded.updated_at;

    return old;
end;
$$;

drop trigger if exists training_log_days_tombstone_delete on easysearch.training_log_days;
create trigger training_log_days_tombstone_delete
    after delete on easysearch.training_log_days
    for each row execute function easysearch.tombstone_deleted_training_log_day();

-- Monthly expense claims
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

-- Travel expense claims
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
