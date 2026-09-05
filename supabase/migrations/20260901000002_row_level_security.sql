-- Row Level Security: this is the ONLY place multi-tenant isolation is
-- actually enforced. Client-side workspace filtering is a UX convenience,
-- not a security boundary — every policy below assumes a hostile or buggy
-- client and must hold regardless of what the client sends.

alter table public.users enable row level security;
alter table public.workspaces enable row level security;
alter table public.workspace_memberships enable row level security;
alter table public.assets enable row level security;

-- ---------------------------------------------------------------------
-- helper: is auth.uid() a member of a given workspace?
-- Marked stable + security definer so it can be used inside policies
-- without itself being blocked by RLS on workspace_memberships (which
-- would otherwise cause infinite recursion when memberships policies
-- also call this function).
-- ---------------------------------------------------------------------
create or replace function public.is_workspace_member(target_workspace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.workspace_memberships m
        where m.workspace_id = target_workspace_id
          and m.user_id = auth.uid()
    );
$$;

create or replace function public.is_workspace_owner(target_workspace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.workspace_memberships m
        where m.workspace_id = target_workspace_id
          and m.user_id = auth.uid()
          and m.role = 'owner'
    );
$$;

-- ---------------------------------------------------------------------
-- users: a user can read their own profile, and the profiles of people
-- who share at least one workspace with them (so member lists can render
-- display names). No one may read arbitrary strangers' profiles.
-- ---------------------------------------------------------------------
create policy "users_select_self_or_workspace_peers"
    on public.users for select
    using (
        id = auth.uid()
        or exists (
            select 1
            from public.workspace_memberships mine
            join public.workspace_memberships theirs
              on theirs.workspace_id = mine.workspace_id
            where mine.user_id = auth.uid()
              and theirs.user_id = public.users.id
        )
    );

create policy "users_update_self"
    on public.users for update
    using (id = auth.uid())
    with check (id = auth.uid());

-- ---------------------------------------------------------------------
-- workspaces: visible only to members; insertable by any authenticated
-- user (they become owner via the handle_new_workspace trigger); mutable
-- only by the owner.
-- ---------------------------------------------------------------------
create policy "workspaces_select_member"
    on public.workspaces for select
    using (public.is_workspace_member(id));

create policy "workspaces_insert_self_as_owner"
    on public.workspaces for insert
    with check (owner_id = auth.uid());

create policy "workspaces_update_owner"
    on public.workspaces for update
    using (public.is_workspace_owner(id))
    with check (public.is_workspace_owner(id));

create policy "workspaces_delete_owner"
    on public.workspaces for delete
    using (public.is_workspace_owner(id));

-- ---------------------------------------------------------------------
-- workspace_memberships: members can see the roster of workspaces they
-- belong to; only owners can add/remove members (besides the automatic
-- owner-insert trigger, which runs as security definer and bypasses RLS).
-- ---------------------------------------------------------------------
create policy "memberships_select_fellow_members"
    on public.workspace_memberships for select
    using (public.is_workspace_member(workspace_id));

create policy "memberships_insert_owner_only"
    on public.workspace_memberships for insert
    with check (public.is_workspace_owner(workspace_id));

create policy "memberships_delete_owner_or_self"
    on public.workspace_memberships for delete
    using (public.is_workspace_owner(workspace_id) or user_id = auth.uid());

-- ---------------------------------------------------------------------
-- assets: THE core isolation boundary. A user may select/insert/update/
-- delete an asset only when they are a member of that asset's workspace.
-- This is enforced independently for every operation, and `with check`
-- clauses prevent a member of workspace A from re-parenting a row into
-- workspace B they don't belong to (or inserting directly into B).
-- ---------------------------------------------------------------------
create policy "assets_select_workspace_member"
    on public.assets for select
    using (public.is_workspace_member(workspace_id));

create policy "assets_insert_workspace_member"
    on public.assets for insert
    with check (
        public.is_workspace_member(workspace_id)
        and created_by_user_id = auth.uid()
    );

create policy "assets_update_workspace_member"
    on public.assets for update
    using (public.is_workspace_member(workspace_id))
    with check (public.is_workspace_member(workspace_id));

create policy "assets_delete_workspace_member"
    on public.assets for delete
    using (public.is_workspace_member(workspace_id));
