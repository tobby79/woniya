begin;

-- Return only the class-scoped teacher profile fields needed by an approved
-- parent or a staff member of the requested class. Invalid teacher media
-- links remain null instead of exposing media from another center or type.
create or replace function public.get_class_teacher_profile(
  p_class_id uuid
)
returns table (
  class_id uuid,
  teacher_media_id uuid,
  teacher_name text,
  photo_path text,
  photo_alt text,
  teacher_intro text
)
language sql
security definer
stable
set search_path = public, auth
as $$
  select
    c.id as class_id,
    teacher_media.id as teacher_media_id,
    teacher_media.title as teacher_name,
    teacher_media.photo_url as photo_path,
    teacher_media.photo_alt,
    mini.teacher_intro
  from public.classes as c
  left join public.center_media as teacher_media
    on teacher_media.id = c.teacher_media_id
   and teacher_media.center_id = c.center_id
   and teacher_media.media_type = 'teacher'
  left join public.class_mini as mini
    on mini.class_id = c.id
  where auth.uid() is not null
    and c.id = p_class_id
    and (
      coalesce(public.is_approved_parent(p_class_id), false)
      or coalesce(public.is_class_staff(p_class_id), false)
    );
$$;

comment on function public.get_class_teacher_profile(uuid) is
  'Returns only the requested class ID, validated teacher media ID, teacher display name, photo path, photo alt text, and per-class static teacher introduction to an authenticated approved parent or class staff member.';

revoke execute on function public.get_class_teacher_profile(uuid)
  from public, anon, authenticated;
grant execute on function public.get_class_teacher_profile(uuid)
  to authenticated;

commit;
