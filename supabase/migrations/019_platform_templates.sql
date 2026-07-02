-- Platform template preview data for the super admin dashboard.

create table if not exists public.platform_templates (
  id uuid primary key default gen_random_uuid(),
  template_id text unique not null,
  hero_image_url text,
  director_photo_url text,
  director_name text,
  director_message text,
  intro_text text,
  album jsonb not null default '[]'::jsonb,
  teachers jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  constraint platform_templates_template_id_check
    check (template_id in ('sunshine', 'carnival', 'forest', 'gallery')),
  constraint platform_templates_album_array_check
    check (jsonb_typeof(album) = 'array'),
  constraint platform_templates_teachers_array_check
    check (jsonb_typeof(teachers) = 'array')
);

alter table public.platform_templates enable row level security;

revoke all on table public.platform_templates from anon, authenticated;
grant select on table public.platform_templates to anon;
grant select, insert, update, delete on table public.platform_templates to authenticated;

drop policy if exists "platform_templates_public_select" on public.platform_templates;
create policy "platform_templates_public_select"
on public.platform_templates
for select
to anon, authenticated
using (true);

drop policy if exists "platform_templates_super_admin_insert" on public.platform_templates;
create policy "platform_templates_super_admin_insert"
on public.platform_templates
for insert
to authenticated
with check (auth.email() = 'tobby79@naver.com');

drop policy if exists "platform_templates_super_admin_update" on public.platform_templates;
create policy "platform_templates_super_admin_update"
on public.platform_templates
for update
to authenticated
using (auth.email() = 'tobby79@naver.com')
with check (auth.email() = 'tobby79@naver.com');

drop policy if exists "platform_templates_super_admin_delete" on public.platform_templates;
create policy "platform_templates_super_admin_delete"
on public.platform_templates
for delete
to authenticated
using (auth.email() = 'tobby79@naver.com');

insert into public.platform_templates (template_id, album, teachers)
values
  ('sunshine', '[]'::jsonb, '[]'::jsonb),
  ('carnival', '[]'::jsonb, '[]'::jsonb),
  ('forest', '[]'::jsonb, '[]'::jsonb),
  ('gallery', '[]'::jsonb, '[]'::jsonb)
on conflict (template_id) do nothing;

insert into storage.buckets (id, name, public)
values ('template-previews', 'template-previews', true)
on conflict (id) do update
set public = excluded.public;

drop policy if exists "template_previews_public_select" on storage.objects;
create policy "template_previews_public_select"
on storage.objects
for select
to public
using (bucket_id = 'template-previews');

drop policy if exists "template_previews_super_admin_insert" on storage.objects;
create policy "template_previews_super_admin_insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'template-previews'
  and auth.email() = 'tobby79@naver.com'
  and (storage.foldername(name))[1] in ('sunshine', 'carnival', 'forest', 'gallery')
  and (storage.foldername(name))[2] in ('hero', 'director', 'album', 'teachers')
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
  and (storage.foldername(name))[2] in ('hero', 'director', 'album', 'teachers')
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
