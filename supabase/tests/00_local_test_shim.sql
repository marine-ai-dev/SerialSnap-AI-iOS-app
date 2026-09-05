-- Minimal shim of the pieces of Supabase Auth that our schema/RLS depend on
-- (auth.users table and auth.uid()), for running these tests against a
-- plain local Postgres instance that does not have the full Supabase stack.
-- Against a REAL Supabase project (local `supabase start` or hosted), this
-- file must NOT be run — auth.users and auth.uid() already exist and are
-- managed by Supabase Auth itself.

create schema if not exists auth;

create table if not exists auth.users (
    id uuid primary key default gen_random_uuid(),
    email text,
    raw_user_meta_data jsonb not null default '{}'::jsonb
);

-- In real Supabase, auth.uid() reads the JWT claim for the current request.
-- Here we emulate it with a session-local setting so tests can impersonate
-- different users via `select set_config('request.jwt.claim.sub', ..., true)`.
create or replace function auth.uid() returns uuid
language sql stable
as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

-- A real Supabase project always has these two built-in roles (PostgREST
-- authenticates as one or the other); migrations that `grant ... to
-- authenticated` (e.g. 20260901000003_delete_own_account.sql) fail against
-- a bare Postgres instance without them. Created as NOLOGIN roles purely so
-- GRANT has a target — nothing here logs in as them directly.
do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
end
$$;
