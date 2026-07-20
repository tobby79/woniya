-- Allow the platform administrator to manage photos for real centers,
-- including draft centers that do not have an owner yet.

begin;

-- Keep these policies separate from the existing published-read and owner
-- policies so their access rules continue to be evaluated independently.
drop policy if exists center_media_platform_admin_select on public.center_media;
create policy center_media_platform_admin_select
  on public.center_media
  for select
  to authenticated
  using (auth.email() = 'tobby79@naver.com');

drop policy if exists center_media_platform_admin_insert on public.center_media;
create policy center_media_platform_admin_insert
  on public.center_media
  for insert
  to authenticated
  with check (
    auth.email() = 'tobby79@naver.com'
    and exists (
      select 1
      from public.centers c
      where c.id = center_media.center_id
    )
  );

drop policy if exists center_media_platform_admin_update on public.center_media;
create policy center_media_platform_admin_update
  on public.center_media
  for update
  to authenticated
  using (auth.email() = 'tobby79@naver.com')
  with check (
    auth.email() = 'tobby79@naver.com'
    and exists (
      select 1
      from public.centers c
      where c.id = center_media.center_id
    )
  );

drop policy if exists center_media_platform_admin_delete on public.center_media;
create policy center_media_platform_admin_delete
  on public.center_media
  for delete
  to authenticated
  using (auth.email() = 'tobby79@naver.com');

-- The admin UI stores real-center images only at:
-- centers/{center_id}/{kind}/{filename}
-- Limit the exception to the kinds currently written by admin.html. Comparing
-- centers.id::text avoids casting an invalid path segment to uuid.
drop policy if exists center_images_platform_admin_insert on storage.objects;
create policy center_images_platform_admin_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'center-images'
    and auth.email() = 'tobby79@naver.com'
    and (storage.foldername(storage.objects.name))[1] = 'centers'
    and (storage.foldername(storage.objects.name))[3]
      in ('hero', 'director', 'teacher', 'day_story', 'facility', 'program')
    and array_length(storage.foldername(storage.objects.name), 1) = 3
    and exists (
      select 1
      from public.centers c
      where c.id::text = (storage.foldername(storage.objects.name))[2]
    )
  );

drop policy if exists center_images_platform_admin_update on storage.objects;
create policy center_images_platform_admin_update
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'center-images'
    and auth.email() = 'tobby79@naver.com'
    and (storage.foldername(storage.objects.name))[1] = 'centers'
    and (storage.foldername(storage.objects.name))[3]
      in ('hero', 'director', 'teacher', 'day_story', 'facility', 'program')
    and array_length(storage.foldername(storage.objects.name), 1) = 3
    and exists (
      select 1
      from public.centers c
      where c.id::text = (storage.foldername(storage.objects.name))[2]
    )
  )
  with check (
    bucket_id = 'center-images'
    and auth.email() = 'tobby79@naver.com'
    and (storage.foldername(storage.objects.name))[1] = 'centers'
    and (storage.foldername(storage.objects.name))[3]
      in ('hero', 'director', 'teacher', 'day_story', 'facility', 'program')
    and array_length(storage.foldername(storage.objects.name), 1) = 3
    and exists (
      select 1
      from public.centers c
      where c.id::text = (storage.foldername(storage.objects.name))[2]
    )
  );

drop policy if exists center_images_platform_admin_delete on storage.objects;
create policy center_images_platform_admin_delete
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'center-images'
    and auth.email() = 'tobby79@naver.com'
    and (storage.foldername(storage.objects.name))[1] = 'centers'
    and (storage.foldername(storage.objects.name))[3]
      in ('hero', 'director', 'teacher', 'day_story', 'facility', 'program')
    and array_length(storage.foldername(storage.objects.name), 1) = 3
    and exists (
      select 1
      from public.centers c
      where c.id::text = (storage.foldername(storage.objects.name))[2]
    )
  );

commit;
