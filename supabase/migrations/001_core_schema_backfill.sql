-- Woniya core baseline backfill.
-- This file lets woniya-m1/supabase/migrations stand on its own when applied
-- to a clean Supabase project. Later migrations remain idempotent.

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.centers (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete set null,
  slug text not null unique,
  name text not null,
  region text,
  address text,
  lat numeric,
  lng numeric,
  theme text not null default 'pink',
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
  status text not null default 'draft'
    check (status in ('draft', 'published', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  intro text,
  operating_hours text,
  template text not null default 'sunshine',
  card_image text,
  directions_text text,
  philosophy jsonb,
  programs jsonb,
  facilities jsonb
);

alter table public.centers
  add column if not exists id uuid default gen_random_uuid(),
  add column if not exists owner_id uuid references auth.users(id) on delete set null,
  add column if not exists slug text,
  add column if not exists name text,
  add column if not exists region text,
  add column if not exists address text,
  add column if not exists lat numeric,
  add column if not exists lng numeric,
  add column if not exists theme text not null default 'pink',
  add column if not exists menu jsonb not null default '[]'::jsonb,
  add column if not exists hero jsonb not null default '{}'::jsonb,
  add column if not exists director jsonb not null default '{}'::jsonb,
  add column if not exists notices jsonb not null default '{}'::jsonb,
  add column if not exists schedule jsonb not null default '{}'::jsonb,
  add column if not exists faqs jsonb not null default '{}'::jsonb,
  add column if not exists finale jsonb not null default '{}'::jsonb,
  add column if not exists footer jsonb not null default '{}'::jsonb,
  add column if not exists badges jsonb not null default '{}'::jsonb,
  add column if not exists tags text[] not null default '{}'::text[],
  add column if not exists status text not null default 'draft',
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists intro text,
  add column if not exists operating_hours text,
  add column if not exists template text not null default 'sunshine',
  add column if not exists card_image text,
  add column if not exists directions_text text,
  add column if not exists philosophy jsonb,
  add column if not exists programs jsonb,
  add column if not exists facilities jsonb;

drop trigger if exists centers_set_updated_at on public.centers;
create trigger centers_set_updated_at
  before update on public.centers
  for each row
  execute function public.set_updated_at();

create table if not exists public.center_media (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references public.centers(id) on delete cascade,
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

alter table public.center_media
  add column if not exists id uuid default gen_random_uuid(),
  add column if not exists center_id uuid,
  add column if not exists media_type text,
  add column if not exists sort_order integer not null default 0,
  add column if not exists slot text,
  add column if not exists time_label text,
  add column if not exists title text,
  add column if not exists subtitle text,
  add column if not exists photo_url text,
  add column if not exists photo_alt text,
  add column if not exists caption text,
  add column if not exists note text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create index if not exists center_media_center_id_idx
  on public.center_media (center_id, media_type, sort_order);

drop trigger if exists center_media_set_updated_at on public.center_media;
create trigger center_media_set_updated_at
  before update on public.center_media
  for each row
  execute function public.set_updated_at();

create table if not exists public.classes (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references public.centers(id) on delete cascade,
  teacher_media_id uuid references public.center_media(id) on delete set null,
  teacher_id uuid references auth.users(id),
  name text not null,
  age_label text,
  capacity integer not null default 0 check (capacity >= 0),
  enrolled integer not null default 0 check (enrolled >= 0),
  waiting integer not null default 0 check (waiting >= 0),
  status text not null default 'open'
    check (status in ('open', 'waiting', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (enrolled <= capacity)
);

alter table public.classes
  add column if not exists id uuid default gen_random_uuid(),
  add column if not exists center_id uuid,
  add column if not exists teacher_media_id uuid,
  add column if not exists teacher_id uuid references auth.users(id),
  add column if not exists name text,
  add column if not exists age_label text,
  add column if not exists capacity integer not null default 0,
  add column if not exists enrolled integer not null default 0,
  add column if not exists waiting integer not null default 0,
  add column if not exists status text not null default 'open',
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create index if not exists classes_center_id_idx on public.classes (center_id);
create index if not exists classes_teacher_id_idx on public.classes (teacher_id);

drop trigger if exists classes_set_updated_at on public.classes;
create trigger classes_set_updated_at
  before update on public.classes
  for each row
  execute function public.set_updated_at();

create table if not exists public.consultations (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references public.centers(id) on delete cascade,
  parent_name text not null,
  phone text not null,
  kind text not null,
  wish_class text,
  wish_time text,
  consent_at timestamptz not null,
  status text not null default 'new',
  created_at timestamptz not null default now()
);

alter table public.consultations
  add column if not exists id uuid default gen_random_uuid(),
  add column if not exists center_id uuid,
  add column if not exists parent_name text,
  add column if not exists phone text,
  add column if not exists kind text,
  add column if not exists wish_class text,
  add column if not exists wish_time text,
  add column if not exists consent_at timestamptz,
  add column if not exists status text not null default 'new',
  add column if not exists created_at timestamptz not null default now();

create table if not exists public.admissions (
  id uuid primary key default gen_random_uuid(),
  center_id uuid references public.centers(id) on delete cascade,
  target text,
  capacity_info text,
  period text,
  process text,
  supplies text,
  notes text,
  updated_at timestamptz default now()
);

alter table public.admissions
  add column if not exists id uuid default gen_random_uuid(),
  add column if not exists center_id uuid,
  add column if not exists target text,
  add column if not exists capacity_info text,
  add column if not exists period text,
  add column if not exists process text,
  add column if not exists supplies text,
  add column if not exists notes text,
  add column if not exists updated_at timestamptz default now();

create unique index if not exists admissions_center_id_key
  on public.admissions (center_id);

create table if not exists public.center_applications (
  id uuid primary key default gen_random_uuid(),
  center_name text not null,
  director_name text not null,
  phone text not null,
  region text,
  message text,
  consent_at timestamptz not null default now(),
  status text not null default 'new'
    check (status in ('new', 'checked', 'contacted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.center_applications
  add column if not exists id uuid default gen_random_uuid(),
  add column if not exists center_name text,
  add column if not exists director_name text,
  add column if not exists phone text,
  add column if not exists region text,
  add column if not exists message text,
  add column if not exists consent_at timestamptz not null default now(),
  add column if not exists status text not null default 'new',
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create index if not exists center_applications_center_name_idx
  on public.center_applications (center_name, consent_at desc);

drop trigger if exists center_applications_set_updated_at on public.center_applications;
create trigger center_applications_set_updated_at
  before update on public.center_applications
  for each row
  execute function public.set_updated_at();

alter table public.centers enable row level security;
alter table public.center_media enable row level security;
alter table public.classes enable row level security;
alter table public.consultations enable row level security;
alter table public.admissions enable row level security;
alter table public.center_applications enable row level security;

grant usage on schema public to anon, authenticated;
grant select on public.centers, public.center_media, public.classes, public.admissions to anon;
grant insert on public.consultations, public.center_applications to anon;
grant select, insert, update, delete on public.centers, public.center_media, public.classes, public.admissions to authenticated;
grant select, insert, update on public.consultations, public.center_applications to authenticated;

drop policy if exists classes_public_select on public.classes;
create policy classes_public_select on public.classes
  for select
  to anon, authenticated
  using (
    exists (
      select 1
      from public.centers c
      where c.id = classes.center_id
        and c.status = 'published'
    )
  );

drop policy if exists classes_owner_select on public.classes;
create policy classes_owner_select on public.classes
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.centers c
      where c.id = classes.center_id
        and c.owner_id = auth.uid()
    )
  );

drop policy if exists classes_owner_insert on public.classes;
create policy classes_owner_insert on public.classes
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.centers c
      where c.id = classes.center_id
        and c.owner_id = auth.uid()
    )
  );

drop policy if exists classes_owner_update on public.classes;
create policy classes_owner_update on public.classes
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.centers c
      where c.id = classes.center_id
        and c.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.centers c
      where c.id = classes.center_id
        and c.owner_id = auth.uid()
    )
  );

drop policy if exists classes_owner_delete on public.classes;
create policy classes_owner_delete on public.classes
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.centers c
      where c.id = classes.center_id
        and c.owner_id = auth.uid()
    )
  );

drop policy if exists center_applications_public_insert on public.center_applications;
create policy center_applications_public_insert
  on public.center_applications
  for insert
  to anon, authenticated
  with check (
    length(trim(center_name)) > 0
    and length(trim(director_name)) > 0
    and length(trim(phone)) > 0
    and consent_at is not null
    and status = 'new'
  );

drop policy if exists center_applications_owner_select on public.center_applications;
create policy center_applications_owner_select
  on public.center_applications
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.centers c
      where c.name = center_applications.center_name
        and c.owner_id = auth.uid()
    )
  );

drop policy if exists center_applications_owner_update on public.center_applications;
create policy center_applications_owner_update
  on public.center_applications
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.centers c
      where c.name = center_applications.center_name
        and c.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.centers c
      where c.name = center_applications.center_name
        and c.owner_id = auth.uid()
    )
  );

insert into storage.buckets (id, name, public)
values ('center-images', 'center-images', false)
on conflict (id) do update
set public = false;
