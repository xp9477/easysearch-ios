begin;

revoke all on table easysearch.training_log_days from anon;
grant select, insert, update, delete on table easysearch.training_log_days to authenticated;

drop policy if exists "training_log_days_select_own" on easysearch.training_log_days;
create policy "training_log_days_select_own"
    on easysearch.training_log_days
    for select
    to authenticated
    using ((select auth.uid()) = user_id);

drop policy if exists "training_log_days_insert_own" on easysearch.training_log_days;
create policy "training_log_days_insert_own"
    on easysearch.training_log_days
    for insert
    to authenticated
    with check ((select auth.uid()) = user_id);

drop policy if exists "training_log_days_update_own" on easysearch.training_log_days;
create policy "training_log_days_update_own"
    on easysearch.training_log_days
    for update
    to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

drop policy if exists "training_log_days_delete_own" on easysearch.training_log_days;
create policy "training_log_days_delete_own"
    on easysearch.training_log_days
    for delete
    to authenticated
    using ((select auth.uid()) = user_id);

create or replace function easysearch.keep_newest_training_log_day()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
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

commit;
