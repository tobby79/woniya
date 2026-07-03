-- Broaden template-previews storage paths for admin.html Stage B.
-- The bucket itself was created in 019_platform_templates.sql.

drop policy if exists "template_previews_super_admin_insert" on storage.objects;
create policy "template_previews_super_admin_insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'template-previews'
  and auth.email() = 'tobby79@naver.com'
  and (storage.foldername(name))[1] in ('sunshine', 'carnival', 'forest', 'gallery')
  and (storage.foldername(name))[2] in ('hero', 'director', 'album', 'teachers', 'teacher', 'day_story', 'facility', 'program')
);

drop policy if exists "template_previews_super_admin_update" on storage.objects;
create policy "template_previews_super_admin_update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'template-previews'
  and auth.email() = 'tobby79@naver.com'
)
with check (
  bucket_id = 'template-previews'
  and auth.email() = 'tobby79@naver.com'
  and (storage.foldername(name))[1] in ('sunshine', 'carnival', 'forest', 'gallery')
  and (storage.foldername(name))[2] in ('hero', 'director', 'album', 'teachers', 'teacher', 'day_story', 'facility', 'program')
);

drop policy if exists "template_previews_super_admin_delete" on storage.objects;
create policy "template_previews_super_admin_delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'template-previews'
  and auth.email() = 'tobby79@naver.com'
);
