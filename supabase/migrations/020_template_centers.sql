-- Template preview tables for the platform admin redesign Stage A.
-- These tables mirror the admin-managed center content tables without
-- touching admin.html yet.

-- Keep the legacy platform_templates table.
-- super-admin.html still reads/writes this table, and dropping it here would
-- delete preview data in environments that already used the Stage A editor.
-- If a manual cleanup is needed later, export/migrate the data first.

create table if not exists public.template_centers (
  id uuid primary key default gen_random_uuid(),
  template_id text unique not null
    check (template_id in ('sunshine', 'carnival', 'forest', 'gallery')),

  slug text not null unique,
  name text not null,
  region text,
  address text,
  lat numeric,
  lng numeric,
  theme text not null default 'pink'::text,

  menu jsonb not null default '[]'::jsonb,
  hero jsonb not null default '{}'::jsonb,
  director jsonb not null default '{}'::jsonb,
  notices jsonb not null default '{}'::jsonb,
  schedule jsonb not null default '{}'::jsonb,
  faqs jsonb not null default '{}'::jsonb,
  finale jsonb not null default '{}'::jsonb,
  footer jsonb not null default '{}'::jsonb,

  badges jsonb not null default '{}'::jsonb,
  tags text[] not null default '{}'::text[],

  status text not null default 'draft'::text
    check (status in ('draft', 'published', 'archived')),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  intro text,
  operating_hours text,
  template text not null default 'sunshine'::text,
  card_image text,
  directions_text text,
  philosophy jsonb,
  programs jsonb,
  facilities jsonb
);

drop trigger if exists template_centers_set_updated_at on public.template_centers;
create trigger template_centers_set_updated_at
  before update on public.template_centers
  for each row
  execute function public.set_updated_at();

create table if not exists public.template_center_media (
  id uuid primary key default gen_random_uuid(),
  template_center_id uuid not null references public.template_centers(id) on delete cascade,

  media_type text not null
    check (media_type in ('hero', 'day_story', 'album', 'teacher', 'director', 'facility')),
  sort_order integer not null default 0,

  slot text,
  time_label text,
  title text,
  subtitle text,
  photo_url text not null,
  photo_alt text,
  caption text,
  note text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists template_center_media_center_id_idx
  on public.template_center_media (template_center_id, media_type, sort_order);

drop trigger if exists template_center_media_set_updated_at on public.template_center_media;
create trigger template_center_media_set_updated_at
  before update on public.template_center_media
  for each row
  execute function public.set_updated_at();

create table if not exists public.template_admissions (
  id uuid primary key default gen_random_uuid(),
  template_center_id uuid references public.template_centers(id) on delete cascade,
  target text,
  capacity_info text,
  period text,
  process text,
  supplies text,
  notes text,
  updated_at timestamptz default now()
);

alter table public.template_centers enable row level security;
alter table public.template_center_media enable row level security;
alter table public.template_admissions enable row level security;

revoke all on table public.template_centers from anon, authenticated;
revoke all on table public.template_center_media from anon, authenticated;
revoke all on table public.template_admissions from anon, authenticated;

grant select on table public.template_centers to anon;
grant select on table public.template_center_media to anon;
grant select on table public.template_admissions to anon;

grant select, insert, update, delete on table public.template_centers to authenticated;
grant select, insert, update, delete on table public.template_center_media to authenticated;
grant select, insert, update, delete on table public.template_admissions to authenticated;

drop policy if exists "template_centers_public_select" on public.template_centers;
create policy "template_centers_public_select"
on public.template_centers
for select
to anon, authenticated
using (true);

drop policy if exists "template_centers_super_admin_insert" on public.template_centers;
create policy "template_centers_super_admin_insert"
on public.template_centers
for insert
to authenticated
with check (auth.email() = 'tobby79@naver.com');

drop policy if exists "template_centers_super_admin_update" on public.template_centers;
create policy "template_centers_super_admin_update"
on public.template_centers
for update
to authenticated
using (auth.email() = 'tobby79@naver.com')
with check (auth.email() = 'tobby79@naver.com');

drop policy if exists "template_centers_super_admin_delete" on public.template_centers;
create policy "template_centers_super_admin_delete"
on public.template_centers
for delete
to authenticated
using (auth.email() = 'tobby79@naver.com');

drop policy if exists "template_center_media_public_select" on public.template_center_media;
create policy "template_center_media_public_select"
on public.template_center_media
for select
to anon, authenticated
using (true);

drop policy if exists "template_center_media_super_admin_insert" on public.template_center_media;
create policy "template_center_media_super_admin_insert"
on public.template_center_media
for insert
to authenticated
with check (auth.email() = 'tobby79@naver.com');

drop policy if exists "template_center_media_super_admin_update" on public.template_center_media;
create policy "template_center_media_super_admin_update"
on public.template_center_media
for update
to authenticated
using (auth.email() = 'tobby79@naver.com')
with check (auth.email() = 'tobby79@naver.com');

drop policy if exists "template_center_media_super_admin_delete" on public.template_center_media;
create policy "template_center_media_super_admin_delete"
on public.template_center_media
for delete
to authenticated
using (auth.email() = 'tobby79@naver.com');

drop policy if exists "template_admissions_public_select" on public.template_admissions;
create policy "template_admissions_public_select"
on public.template_admissions
for select
to anon, authenticated
using (true);

drop policy if exists "template_admissions_super_admin_insert" on public.template_admissions;
create policy "template_admissions_super_admin_insert"
on public.template_admissions
for insert
to authenticated
with check (auth.email() = 'tobby79@naver.com');

drop policy if exists "template_admissions_super_admin_update" on public.template_admissions;
create policy "template_admissions_super_admin_update"
on public.template_admissions
for update
to authenticated
using (auth.email() = 'tobby79@naver.com')
with check (auth.email() = 'tobby79@naver.com');

drop policy if exists "template_admissions_super_admin_delete" on public.template_admissions;
create policy "template_admissions_super_admin_delete"
on public.template_admissions
for delete
to authenticated
using (auth.email() = 'tobby79@naver.com');

insert into public.template_centers (
  template_id,
  slug,
  name,
  template
)
values
  ('sunshine', 'sunshine', '햇살 템플릿', 'sunshine'),
  ('carnival', 'carnival', '카니발 템플릿', 'carnival'),
  ('forest', 'forest', '숲 템플릿', 'forest'),
  ('gallery', 'gallery', '갤러리 템플릿', 'gallery')
on conflict (template_id) do nothing;
