begin;

-- Enrollment creation is reserved for the SECURITY DEFINER invite RPC.
revoke insert on table public.class_enrollments
  from public, anon, authenticated;
revoke insert (
  id,
  class_id,
  parent_id,
  invite_id,
  status,
  requested_at,
  approved_at,
  approved_by,
  last_notice_read_at
) on table public.class_enrollments
  from public, anon, authenticated;

drop policy if exists class_enrollments_parent_insert
  on public.class_enrollments;

-- Direct updates are limited to the parent notice-read timestamp.
revoke update on table public.class_enrollments
  from public, anon, authenticated;
revoke update (
  id,
  class_id,
  parent_id,
  invite_id,
  status,
  requested_at,
  approved_at,
  approved_by,
  last_notice_read_at
) on table public.class_enrollments
  from public, anon, authenticated;

grant update (last_notice_read_at)
  on table public.class_enrollments
  to authenticated;

drop policy if exists class_enrollments_parent_notice_read_update
  on public.class_enrollments;
create policy class_enrollments_parent_notice_read_update
  on public.class_enrollments
  for update
  to authenticated
  using (parent_id = auth.uid())
  with check (parent_id = auth.uid());

-- Keep the application RPC execution contracts explicit.
revoke execute on function public.redeem_class_invite(text)
  from public, anon, authenticated;
grant execute on function public.redeem_class_invite(text)
  to authenticated;

revoke execute on function public.review_parent_enrollment(uuid, text)
  from public, anon, authenticated;
grant execute on function public.review_parent_enrollment(uuid, text)
  to authenticated;

commit;
