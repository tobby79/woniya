begin;

create or replace function public.can_read_legacy_class_image(
  p_object_name text
)
returns boolean
language plpgsql
security definer
stable
set search_path = public, auth
as $$
declare
  v_parts text[];
  v_class_id uuid;
begin
  if p_object_name is null or btrim(p_object_name) = '' then
    return false;
  end if;

  v_parts := string_to_array(p_object_name, '/');

  if coalesce(array_length(v_parts, 1), 0) < 5
     or v_parts[1] <> 'centers'
     or coalesce(v_parts[2], '') = ''
     or v_parts[3] <> 'classes'
     or coalesce(v_parts[4], '') = '' then
    return false;
  end if;

  select c.id
    into v_class_id
  from public.classes as c
  where c.id::text = v_parts[4]
    and c.center_id::text = v_parts[2]
  limit 1;

  if v_class_id is null then
    return false;
  end if;

  return coalesce(public.is_class_staff(v_class_id), false)
    or coalesce(public.is_approved_parent(v_class_id), false);
end;
$$;

revoke execute on function public.can_read_legacy_class_image(text)
  from public, anon, authenticated;
grant execute on function public.can_read_legacy_class_image(text)
  to authenticated;

drop policy if exists center_images_public_read on storage.objects;
create policy center_images_public_read
  on storage.objects
  for select
  to anon, authenticated
  using (
    bucket_id = 'center-images'
    and storage.objects.name !~ '^centers(/[^/]*)*/classes(/|$)'
  );

drop policy if exists center_images_class_private_read on storage.objects;
create policy center_images_class_private_read
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'center-images'
    and storage.objects.name ~ '^centers(/[^/]*)*/classes(/|$)'
    and public.can_read_legacy_class_image(storage.objects.name)
  );

commit;
