-- SerialSnap initial schema: users profile, workspaces, memberships, assets.
-- Auth users live in Supabase's built-in auth.users; this migration adds the
-- public-schema tables the app reads/writes plus a public.users profile
-- table that mirrors auth.users for FK convenience.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- users: a thin profile row per auth.users, created by trigger on signup.
-- ---------------------------------------------------------------------
create table if not exists public.users (
    id uuid primary key references auth.users (id) on delete cascade,
    email text,
    display_name text,
    created_at timestamptz not null default now()
);

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    insert into public.users (id, email, display_name)
    values (new.id, new.email, new.raw_user_meta_data ->> 'full_name')
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_auth_user();

-- ---------------------------------------------------------------------
-- workspaces
-- ---------------------------------------------------------------------
create table if not exists public.workspaces (
    id uuid primary key default gen_random_uuid(),
    name text not null check (char_length(trim(name)) > 0),
    owner_id uuid not null references public.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- workspace_memberships: who belongs to which workspace, and their role.
-- This table is the single source of truth RLS policies consult to decide
-- whether a user may touch a given workspace's rows.
-- ---------------------------------------------------------------------
create type public.workspace_role as enum ('owner', 'member');

create table if not exists public.workspace_memberships (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references public.workspaces (id) on delete cascade,
    user_id uuid not null references public.users (id) on delete cascade,
    role public.workspace_role not null default 'member',
    created_at timestamptz not null default now(),
    unique (workspace_id, user_id)
);

create index if not exists idx_workspace_memberships_user on public.workspace_memberships (user_id);
create index if not exists idx_workspace_memberships_workspace on public.workspace_memberships (workspace_id);

-- Automatically add the creator of a workspace as its owner member.
create or replace function public.handle_new_workspace()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    insert into public.workspace_memberships (workspace_id, user_id, role)
    values (new.id, new.owner_id, 'owner')
    on conflict (workspace_id, user_id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_workspace_created on public.workspaces;
create trigger on_workspace_created
    after insert on public.workspaces
    for each row execute function public.handle_new_workspace();

-- ---------------------------------------------------------------------
-- assets: minimal structured fields only — no images stored by default.
-- ---------------------------------------------------------------------
create table if not exists public.assets (
    id uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references public.workspaces (id) on delete cascade,
    manufacturer text,
    model text,
    serial_number text,
    asset_tag text,
    barcode_value text,
    barcode_symbology text,
    notes text,
    confidence text not null default 'medium' check (confidence in ('low', 'medium', 'high')),
    created_by_user_id uuid not null references public.users (id),
    -- Idempotency key from the client's offline write queue. Unique per
    -- workspace so a retried create can never produce a duplicate asset —
    -- see Packages/Sync/Sources/Sync/WriteQueue.swift for the client side.
    idempotency_key text,
    is_deleted boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create unique index if not exists uq_assets_workspace_idempotency
    on public.assets (workspace_id, idempotency_key)
    where idempotency_key is not null;

create index if not exists idx_assets_workspace on public.assets (workspace_id) where is_deleted = false;
create index if not exists idx_assets_serial on public.assets (workspace_id, serial_number);
create index if not exists idx_assets_asset_tag on public.assets (workspace_id, asset_tag);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists set_assets_updated_at on public.assets;
create trigger set_assets_updated_at
    before update on public.assets
    for each row execute function public.set_updated_at();

drop trigger if exists set_workspaces_updated_at on public.workspaces;
create trigger set_workspaces_updated_at
    before update on public.workspaces
    for each row execute function public.set_updated_at();
