-- Fixes a real bug found while verifying account deletion end-to-end:
-- `assets.created_by_user_id` referenced `public.users(id)` with the
-- default ON DELETE NO ACTION, which made `delete_own_account()` (see
-- 20260901000003) fail with a foreign-key violation whenever the deleting
-- user had ever created an asset in a workspace they don't solely own —
-- e.g. a member's contribution to a shared workspace they don't own
-- outright. Deleting that membership must not delete someone else's
-- workspace's data.
--
-- Cascading the asset itself (like `workspaces.owner_id` does) would be
-- wrong here: it would silently delete another workspace owner's asset
-- records just because the *creator* of one of them left SerialSnap. The
-- correct behavior is to keep the asset (the workspace's data survives)
-- and anonymize the creator attribution — hence ON DELETE SET NULL, which
-- requires the column to become nullable.
alter table public.assets
    alter column created_by_user_id drop not null;

alter table public.assets
    drop constraint if exists assets_created_by_user_id_fkey;

alter table public.assets
    add constraint assets_created_by_user_id_fkey
    foreign key (created_by_user_id) references public.users (id) on delete set null;
