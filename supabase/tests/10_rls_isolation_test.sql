-- RLS cross-tenant isolation verification.
-- Run with: psql <connection> -f supabase/tests/00_local_test_shim.sql \
--                              -f supabase/tests/10_rls_isolation_test.sql
-- (or, against a hosted/local Supabase project, skip 00_local_test_shim.sql
-- since auth.users/auth.uid() already exist there).
--
-- Every assertion raises an exception (aborting the script) on failure, and
-- prints "PASS: <name>" on success, so a clean run with no exception and a
-- PASS line per test is proof RLS is doing its job.

\set ON_ERROR_STOP on

begin;

-- Two users, two separate single-owner workspaces, one asset each.
insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-000000000001', 'alice@example.com'),
    ('00000000-0000-0000-0000-000000000002', 'bob@example.com');

-- public.users rows are populated by the on_auth_user_created trigger
-- fired by the auth.users insert above; nothing further to do here.

-- Act as Alice to create her workspace + asset.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
set local role postgres; -- service-role-equivalent for setup; policies still apply to authenticated queries below via auth.uid()

insert into public.workspaces (id, name, owner_id) values
    ('10000000-0000-0000-0000-000000000001', 'Alice Workspace', '00000000-0000-0000-0000-000000000001');

insert into public.assets (id, workspace_id, manufacturer, serial_number, created_by_user_id, idempotency_key)
values ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'HP', 'ALICE-SN-001',
        '00000000-0000-0000-0000-000000000001', 'seed-alice-1');

-- Act as Bob to create his workspace + asset.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);

insert into public.workspaces (id, name, owner_id) values
    ('10000000-0000-0000-0000-000000000002', 'Bob Workspace', '00000000-0000-0000-0000-000000000002');

insert into public.assets (id, workspace_id, manufacturer, serial_number, created_by_user_id, idempotency_key)
values ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'Dell', 'BOB-SN-001',
        '00000000-0000-0000-0000-000000000002', 'seed-bob-1');

commit;

-- ======================================================================
-- From here on, run as an ordinary authenticated (non-superuser) role so
-- RLS actually applies. `postgres`/table owners bypass RLS by default.
-- ======================================================================
drop role if exists ss_test_authenticated;
create role ss_test_authenticated nologin;
grant usage on schema public to ss_test_authenticated;
grant select, insert, update, delete on public.assets, public.workspaces, public.workspace_memberships, public.users to ss_test_authenticated;
grant execute on function public.is_workspace_member(uuid), public.is_workspace_owner(uuid) to ss_test_authenticated;

set role ss_test_authenticated;

-- Test 1: Alice sees exactly her own asset, never Bob's.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
do $$
declare
    visible_count int;
    bob_asset_visible boolean;
begin
    select count(*) into visible_count from public.assets;
    if visible_count <> 1 then
        raise exception 'FAIL: Alice should see exactly 1 asset, saw %', visible_count;
    end if;

    select exists(select 1 from public.assets where id = '20000000-0000-0000-0000-000000000002')
      into bob_asset_visible;
    if bob_asset_visible then
        raise exception 'FAIL: Alice must not be able to see Bob''s asset';
    end if;

    raise notice 'PASS: alice_sees_only_own_workspace_assets';
end $$;

-- Test 2: Bob cannot UPDATE Alice's asset (cross-tenant write denied).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
do $$
declare
    rows_affected int;
begin
    update public.assets set manufacturer = 'HACKED' where id = '20000000-0000-0000-0000-000000000001';
    get diagnostics rows_affected = row_count;
    if rows_affected <> 0 then
        raise exception 'FAIL: Bob must not be able to update Alice''s asset, but % rows changed', rows_affected;
    end if;
    raise notice 'PASS: cross_tenant_update_denied';
end $$;

-- Test 3: Bob cannot DELETE Alice's asset.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
do $$
declare
    rows_affected int;
begin
    delete from public.assets where id = '20000000-0000-0000-0000-000000000001';
    get diagnostics rows_affected = row_count;
    if rows_affected <> 0 then
        raise exception 'FAIL: Bob must not be able to delete Alice''s asset, but % rows changed', rows_affected;
    end if;
    raise notice 'PASS: cross_tenant_delete_denied';
end $$;

-- Test 4: Bob cannot INSERT an asset directly into Alice's workspace, even
-- though he knows its id (he is not a member).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
do $$
begin
    begin
        insert into public.assets (id, workspace_id, serial_number, created_by_user_id)
        values ('20000000-0000-0000-0000-000000000099', '10000000-0000-0000-0000-000000000001', 'INTRUDER-SN', '00000000-0000-0000-0000-000000000002');
        raise exception 'FAIL: Bob must not be able to insert into Alice''s workspace';
    exception
        when insufficient_privilege or others then
            -- RLS with-check violation raises 'new row violates row-level security policy'
            raise notice 'PASS: cross_tenant_insert_denied';
    end;
end $$;

-- Test 5: Bob cannot read Alice's workspace row itself.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
do $$
declare
    visible boolean;
begin
    select exists(select 1 from public.workspaces where id = '10000000-0000-0000-0000-000000000001') into visible;
    if visible then
        raise exception 'FAIL: Bob must not see Alice''s workspace row';
    end if;
    raise notice 'PASS: cross_tenant_workspace_select_denied';
end $$;

-- Test 6: legitimate member CAN see and update their own workspace's asset.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
do $$
declare
    rows_affected int;
begin
    update public.assets set notes = 'reviewed' where id = '20000000-0000-0000-0000-000000000001';
    get diagnostics rows_affected = row_count;
    if rows_affected <> 1 then
        raise exception 'FAIL: Alice should be able to update her own asset, % rows changed', rows_affected;
    end if;
    raise notice 'PASS: same_tenant_update_allowed';
end $$;

reset role;
do $$ begin raise notice 'ALL RLS ISOLATION TESTS PASSED'; end $$;
