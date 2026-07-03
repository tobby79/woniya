-- Fill owner-scoped RLS policy gaps that migration 025 intended but that never
-- landed on the remote database (confirmed via read-only catalog audit):
--   * centers  : no DELETE policy of any kind existed (RLS denied all deletes)
--   * classes  : no owner-scoped SELECT policy (only public-published + teacher-self)
--   * classes  : no DELETE policy of any kind existed
-- This migration targets ONLY those three gaps. It does not touch the other
-- unreconciled parts of 025 (missing indexes, storage/center_media/center_applications
-- policies) — those are handled separately.
--
-- classes policies reuse public.my_owned_center_ids() (defined in 016, hardened in 027):
--   SECURITY DEFINER, returns the caller's owned center ids. Using it avoids an
--   inline EXISTS subquery re-reading centers under RLS.

-- 1. centers: allow an owner to delete their own center.
--    Table-level DELETE grant is also required — authenticated only had
--    INSERT/SELECT/UPDATE, so the policy alone would still 42501 on delete.
grant delete on table public.centers to authenticated;

drop policy if exists centers_owner_delete on public.centers;
create policy centers_owner_delete
  on public.centers
  for delete
  to authenticated
  using (owner_id = auth.uid());

-- 2. classes: allow an owner to SELECT every class in a center they own,
--    regardless of publish status or teacher assignment.
drop policy if exists classes_owner_select on public.classes;
create policy classes_owner_select
  on public.classes
  for select
  to authenticated
  using (center_id = any (public.my_owned_center_ids()));

-- 3. classes: allow an owner to DELETE classes in a center they own.
--    Table-level DELETE grant was missing for authenticated on classes too.
grant delete on table public.classes to authenticated;

drop policy if exists classes_owner_delete on public.classes;
create policy classes_owner_delete
  on public.classes
  for delete
  to authenticated
  using (center_id = any (public.my_owned_center_ids()));
