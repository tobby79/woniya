begin;

-- Optional read-only diagnostic for invalid existing links. This migration does
-- not execute the query or modify existing rows.
-- select count(*)
-- from public.classes as c
-- left join public.center_media as teacher_media
--   on teacher_media.id = c.teacher_media_id
--  and teacher_media.center_id = c.center_id
--  and teacher_media.media_type = 'teacher'
-- where c.teacher_media_id is not null
--   and teacher_media.id is null;

create or replace function public.validate_class_teacher_media()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $$
begin
  if tg_op = 'UPDATE'
     and new.teacher_media_id is not distinct from old.teacher_media_id
     and new.center_id is not distinct from old.center_id then
    return new;
  end if;

  if new.teacher_media_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.center_media as teacher_media
    where teacher_media.id = new.teacher_media_id
      and teacher_media.center_id = new.center_id
      and teacher_media.media_type = 'teacher'
  ) then
    raise exception using
      errcode = '23514',
      message = 'teacher_media_id must reference a teacher card from the same center';
  end if;

  return new;
end;
$$;

comment on function public.validate_class_teacher_media() is
  'Validates that classes.teacher_media_id is null or references a teacher media row from the same center.';

revoke execute on function public.validate_class_teacher_media()
  from public, anon, authenticated;

drop trigger if exists classes_validate_teacher_media on public.classes;
create trigger classes_validate_teacher_media
  before insert or update of teacher_media_id, center_id
  on public.classes
  for each row
  execute function public.validate_class_teacher_media();

commit;
