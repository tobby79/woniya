begin;

-- Center names are not unique authorization keys, and ordinary owners do not
-- currently need direct access to center applications. If owner access is
-- added later, authorize it through an ID relationship such as
-- linked_center_id plus centers.owner_id = auth.uid().
drop policy if exists center_applications_owner_select
  on public.center_applications;

drop policy if exists center_applications_owner_update
  on public.center_applications;

commit;
