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
