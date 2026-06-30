-- Add the facility media type used by the admin facility/program tab.
-- Some environments have no media_type check constraint; this keeps those
-- environments unchanged while updating older constrained schemas.

do $$
declare
  media_type_constraint text;
begin
  select conname
    into media_type_constraint
  from pg_constraint
  where conrelid = 'public.center_media'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) like '%media_type%'
  limit 1;

  if media_type_constraint is not null then
    execute format(
      'alter table public.center_media drop constraint %I',
      media_type_constraint
    );

    alter table public.center_media
      add constraint center_media_media_type_check
      check (media_type in ('hero', 'day_story', 'album', 'teacher', 'director', 'facility'));
  end if;
end $$;

-- Keep center_media admin CRUD grants explicit for authenticated owners.
-- RLS policies still restrict rows by center ownership.
grant select, insert, update, delete
on table public.center_media
to authenticated;
