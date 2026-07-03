-- ===== 020_class_enrollments_notice_read.sql =====

alter table public.class_enrollments
  add column if not exists last_notice_read_at timestamptz;

drop policy if exists class_enrollments_parent_notice_read_update on public.class_enrollments;

create policy class_enrollments_parent_notice_read_update on public.class_enrollments
  for update
  to authenticated
  using (parent_id = auth.uid())
  with check (parent_id = auth.uid());

grant update (last_notice_read_at) on public.class_enrollments to authenticated;

-- ===== end =====
