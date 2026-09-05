-- Account deletion RPC. The client (Packages/SupabaseKit/Sources/SupabaseKit/
-- SupabaseGateway.swift, `deleteAccount()`) calls this via `client.rpc(...)`
-- rather than deleting rows itself, for two reasons: (1) deleting the
-- `auth.users` row requires elevated privilege the client's anon/authenticated
-- key does not have — only `auth.admin` APIs or a `security definer`
-- function running as the table owner can do it; (2) this keeps the
-- deletion semantics (what cascades, what doesn't) as a single
-- server-side, testable definition rather than duplicated client logic.
--
-- Deleting the `auth.users` row cascades (via the foreign keys declared in
-- 20260901000001_initial_schema.sql) to: the caller's `public.users` profile
-- row, every `workspace_memberships` row naming them, and — because
-- `workspaces.owner_id references public.users(id) on delete cascade` —
-- every workspace *they own*, which in turn cascades to that workspace's
-- `assets`. A workspace the caller only *belongs to* (not owns) survives;
-- only their membership row in it is removed. This is the deliberately
-- simple v1 policy documented in docs/CLOUD_CONTINUATION.md /
-- docs/SECURITY.md: account deletion is irreversible and takes
-- solely-owned data with it, rather than orphaning or reassigning it.
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer set search_path = public
as $$
begin
    if auth.uid() is null then
        raise exception 'delete_own_account() must be called by an authenticated user';
    end if;

    -- Deleting from auth.users (not just public.users) is what actually
    -- revokes the account's ability to sign in again; the public.users row
    -- disappears as a cascade of this delete, not the other way around.
    delete from auth.users where id = auth.uid();
end;
$$;

-- Only an authenticated caller may invoke this, and — because the function
-- always operates on auth.uid() itself — a caller can only ever delete
-- their own account, never anyone else's.
revoke all on function public.delete_own_account() from public;
grant execute on function public.delete_own_account() to authenticated;
