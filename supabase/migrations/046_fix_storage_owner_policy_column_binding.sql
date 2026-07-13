-- Fix center-images owner/teacher storage policies so path checks bind to
-- storage.objects.name, not inner subquery columns named "name".

drop policy if exists "center_images_owner_insert" on storage.objects;
create policy "center_images_owner_insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'center-images'
  and (storage.foldername(storage.objects.name))[1] = 'centers'
  and (
    exists (
      select 1
      from public.centers c
      where c.id::text = (storage.foldername(storage.objects.name))[2]
        and c.owner_id = auth.uid()
    )
    or exists (
      select 1
      from public.classes cl
      where (storage.foldername(storage.objects.name))[3] = 'classes'
        and cl.center_id::text = (storage.foldername(storage.objects.name))[2]
        and cl.id::text = (storage.foldername(storage.objects.name))[4]
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
  and (storage.foldername(storage.objects.name))[1] = 'centers'
  and (
    exists (
      select 1
      from public.centers c
      where c.id::text = (storage.foldername(storage.objects.name))[2]
        and c.owner_id = auth.uid()
    )
    or exists (
      select 1
      from public.classes cl
      where (storage.foldername(storage.objects.name))[3] = 'classes'
        and cl.center_id::text = (storage.foldername(storage.objects.name))[2]
        and cl.id::text = (storage.foldername(storage.objects.name))[4]
        and cl.teacher_id = auth.uid()
    )
  )
)
with check (
  bucket_id = 'center-images'
  and (storage.foldername(storage.objects.name))[1] = 'centers'
  and (
    exists (
      select 1
      from public.centers c
      where c.id::text = (storage.foldername(storage.objects.name))[2]
        and c.owner_id = auth.uid()
    )
    or exists (
      select 1
      from public.classes cl
      where (storage.foldername(storage.objects.name))[3] = 'classes'
        and cl.center_id::text = (storage.foldername(storage.objects.name))[2]
        and cl.id::text = (storage.foldername(storage.objects.name))[4]
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
  and (storage.foldername(storage.objects.name))[1] = 'centers'
  and (
    exists (
      select 1
      from public.centers c
      where c.id::text = (storage.foldername(storage.objects.name))[2]
        and c.owner_id = auth.uid()
    )
    or exists (
      select 1
      from public.classes cl
      where (storage.foldername(storage.objects.name))[3] = 'classes'
        and cl.center_id::text = (storage.foldername(storage.objects.name))[2]
        and cl.id::text = (storage.foldername(storage.objects.name))[4]
        and cl.teacher_id = auth.uid()
    )
  )
);
