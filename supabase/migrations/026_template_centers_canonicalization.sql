-- Canonicalize template preview data on the template_centers table family.
-- The legacy platform_templates table is intentionally kept for audit/backfill safety.

create or replace function pg_temp.template_preview_storage_path(value text)
returns text
language sql
immutable
as $$
  select case
    when value is null or btrim(value) = '' then ''
    when value ~ '^https?://'
      and position('/storage/v1/object/public/template-previews/' in value) > 0
      then split_part(split_part(value, '/storage/v1/object/public/template-previews/', 2), '?', 1)
    else value
  end;
$$;

with legacy as (
  select
    pt.template_id,
    pg_temp.template_preview_storage_path(pt.director_photo_url) as director_photo,
    nullif(btrim(pt.director_name), '') as director_name,
    nullif(btrim(pt.director_message), '') as director_message,
    nullif(btrim(pt.intro_text), '') as intro_text
  from public.platform_templates pt
)
update public.template_centers tc
set
  director =
    coalesce(tc.director, '{}'::jsonb)
    || case
      when legacy.director_photo <> ''
        and nullif(btrim(coalesce(tc.director->>'photo', '')), '') is null
        then jsonb_build_object('photo', legacy.director_photo)
      else '{}'::jsonb
    end
    || case
      when legacy.director_name is not null
        and nullif(btrim(coalesce(tc.director->>'sign_name', '')), '') is null
        then jsonb_build_object('sign_name', legacy.director_name)
      else '{}'::jsonb
    end
    || case
      when legacy.director_message is not null
        and nullif(btrim(coalesce(tc.director->>'message', '')), '') is null
        then jsonb_build_object('message', legacy.director_message)
      else '{}'::jsonb
    end,
  intro = case
    when legacy.intro_text is not null
      and nullif(btrim(coalesce(tc.intro, '')), '') is null
      then legacy.intro_text
    else tc.intro
  end
from legacy
where tc.template_id = legacy.template_id
  and (
    (
      legacy.director_photo <> ''
      and nullif(btrim(coalesce(tc.director->>'photo', '')), '') is null
    )
    or (
      legacy.director_name is not null
      and nullif(btrim(coalesce(tc.director->>'sign_name', '')), '') is null
    )
    or (
      legacy.director_message is not null
      and nullif(btrim(coalesce(tc.director->>'message', '')), '') is null
    )
    or (
      legacy.intro_text is not null
      and nullif(btrim(coalesce(tc.intro, '')), '') is null
    )
  );

with legacy_hero as (
  select
    tc.id as template_center_id,
    pg_temp.template_preview_storage_path(pt.hero_image_url) as photo_url
  from public.platform_templates pt
  join public.template_centers tc on tc.template_id = pt.template_id
  where pg_temp.template_preview_storage_path(pt.hero_image_url) <> ''
),
existing_hero as (
  select distinct template_center_id
  from public.template_center_media
  where media_type = 'hero'
    and nullif(btrim(coalesce(photo_url, '')), '') is not null
)
insert into public.template_center_media (
  template_center_id,
  media_type,
  sort_order,
  photo_url
)
select
  legacy_hero.template_center_id,
  'hero',
  0,
  legacy_hero.photo_url
from legacy_hero
where not exists (
  select 1
  from existing_hero eh
  where eh.template_center_id = legacy_hero.template_center_id
)
  and not exists (
    select 1
    from public.template_center_media m
    where m.template_center_id = legacy_hero.template_center_id
      and m.media_type = 'hero'
      and m.photo_url = legacy_hero.photo_url
  );

with legacy_album as (
  select
    tc.id as template_center_id,
    pg_temp.template_preview_storage_path(item.value->>'url') as photo_url,
    nullif(btrim(item.value->>'caption'), '') as caption,
    item.ordinality::integer as ordinal
  from public.platform_templates pt
  join public.template_centers tc on tc.template_id = pt.template_id
  cross join lateral jsonb_array_elements(pt.album) with ordinality as item(value, ordinality)
),
album_max as (
  select
    template_center_id,
    coalesce(max(sort_order), 0) as max_sort_order
  from public.template_center_media
  where media_type = 'album'
  group by template_center_id
)
insert into public.template_center_media (
  template_center_id,
  media_type,
  sort_order,
  title,
  photo_url,
  caption
)
select
  la.template_center_id,
  'album',
  coalesce(am.max_sort_order, 0) + la.ordinal,
  la.caption,
  la.photo_url,
  la.caption
from legacy_album la
left join album_max am on am.template_center_id = la.template_center_id
where (la.photo_url <> '' or la.caption is not null)
  and not exists (
    select 1
    from public.template_center_media m
    where m.template_center_id = la.template_center_id
      and m.media_type = 'album'
      and coalesce(m.photo_url, '') = la.photo_url
      and coalesce(m.title, '') = coalesce(la.caption, '')
  );

with legacy_teachers as (
  select
    tc.id as template_center_id,
    pg_temp.template_preview_storage_path(coalesce(item.value->>'photo_url', item.value->>'url')) as photo_url,
    nullif(btrim(item.value->>'name'), '') as name,
    nullif(btrim(item.value->>'role'), '') as role,
    item.ordinality::integer as ordinal
  from public.platform_templates pt
  join public.template_centers tc on tc.template_id = pt.template_id
  cross join lateral jsonb_array_elements(pt.teachers) with ordinality as item(value, ordinality)
),
teacher_max as (
  select
    template_center_id,
    coalesce(max(sort_order), 0) as max_sort_order
  from public.template_center_media
  where media_type = 'teacher'
  group by template_center_id
)
insert into public.template_center_media (
  template_center_id,
  media_type,
  sort_order,
  title,
  subtitle,
  photo_url
)
select
  lt.template_center_id,
  'teacher',
  coalesce(tm.max_sort_order, 0) + lt.ordinal,
  lt.name,
  lt.role,
  lt.photo_url
from legacy_teachers lt
left join teacher_max tm on tm.template_center_id = lt.template_center_id
where (lt.photo_url <> '' or lt.name is not null or lt.role is not null)
  and not exists (
    select 1
    from public.template_center_media m
    where m.template_center_id = lt.template_center_id
      and m.media_type = 'teacher'
      and coalesce(m.photo_url, '') = lt.photo_url
      and coalesce(m.title, '') = coalesce(lt.name, '')
      and coalesce(m.subtitle, '') = coalesce(lt.role, '')
  );

do $$
begin
  if exists (
    select 1
    from public.template_admissions
    where template_center_id is not null
    group by template_center_id
    having count(*) > 1
  ) then
    raise exception
      'Cannot add unique index: duplicate template_admissions rows exist for at least one template_center_id';
  end if;
end $$;

create unique index if not exists template_admissions_template_center_id_key
  on public.template_admissions (template_center_id)
  where template_center_id is not null;
