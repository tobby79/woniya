-- 025 cleanup, phase 2: storage.objects owner-scoped write policies for center-images.
-- Closes a cross-tenant write hole: the old authenticated_* policies only checked
-- bucket_id, so any logged-in user could insert/update/delete ANY center's file.
-- The 025 policies (reproduced verbatim below) require the object path to be
--   centers/{center_id}/...   owned by auth.uid(),  OR
--   centers/{center_id}/classes/{class_id}/...  where the class teacher is auth.uid().
--
-- Pre-audited: all 5 existing center-images objects conform to this path shape and
-- map to a real owned center / teacher-assigned class, so no existing file is locked out.
--
-- SELECT (public read) is intentionally left as-is (existing "public_read"); its
-- condition already matches 025's intent. Name normalization deferred to a later pass.
-- New owner policies are created FIRST, then the old broad policies are dropped, all
-- in one transaction (applied atomically).

-- ── 1. create owner-scoped write policies (025 conditions, verbatim) ──
drop policy if exists "center_images_owner_insert" on storage.objects;
create policy "center_images_owner_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'center-images'
    and (storage.foldername(name))[1] = 'centers'
    and (
      exists (
        select 1
        from public.centers c
        where c.id::text = (storage.foldername(name))[2]
          and c.owner_id = auth.uid()
      )
      or exists (
        select 1
        from public.classes cl
        where (storage.foldername(name))[3] = 'classes'
          and cl.center_id::text = (storage.foldername(name))[2]
          and cl.id::text = (storage.foldername(name))[4]
          and cl.teacher_id = auth.uid()
      )
    )
  );

drop policy if exists "center_images_owner_update" on storage.objects;
create policy "center_images_owner_update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'center-images'
    and (storage.foldername(name))[1] = 'centers'
    and (
      exists (
        select 1
        from public.centers c
        where c.id::text = (storage.foldername(name))[2]
          and c.owner_id = auth.uid()
      )
      or exists (
        select 1
        from public.classes cl
        where (storage.foldername(name))[3] = 'classes'
          and cl.center_id::text = (storage.foldername(name))[2]
          and cl.id::text = (storage.foldername(name))[4]
          and cl.teacher_id = auth.uid()
      )
    )
  )
  with check (
    bucket_id = 'center-images'
    and (storage.foldername(name))[1] = 'centers'
    and (
      exists (
        select 1
        from public.centers c
        where c.id::text = (storage.foldername(name))[2]
          and c.owner_id = auth.uid()
      )
      or exists (
        select 1
        from public.classes cl
        where (storage.foldername(name))[3] = 'classes'
          and cl.center_id::text = (storage.foldername(name))[2]
          and cl.id::text = (storage.foldername(name))[4]
          and cl.teacher_id = auth.uid()
      )
    )
  );

drop policy if exists "center_images_owner_delete" on storage.objects;
create policy "center_images_owner_delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'center-images'
    and (storage.foldername(name))[1] = 'centers'
    and (
      exists (
        select 1
        from public.centers c
        where c.id::text = (storage.foldername(name))[2]
          and c.owner_id = auth.uid()
      )
      or exists (
        select 1
        from public.classes cl
        where (storage.foldername(name))[3] = 'classes'
          and cl.center_id::text = (storage.foldername(name))[2]
          and cl.id::text = (storage.foldername(name))[4]
          and cl.teacher_id = auth.uid()
      )
    )
  );

-- ── 2. drop the old bucket-only write policies (superseded) ──
drop policy if exists "authenticated_upload" on storage.objects;
drop policy if exists "authenticated_update" on storage.objects;
drop policy if exists "authenticated_delete" on storage.objects;
