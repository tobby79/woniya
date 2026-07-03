-- Final baseline and security hardening before the next feature phase.
-- This migration is safe to run after the existing woniya-m1 migrations and
-- repairs environments that were created from an incomplete baseline.

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

do $$
begin
  if to_regclass('public.centers') is not null
     and not exists (
       select 1 from pg_constraint
       where conrelid = 'public.centers'::regclass
         and contype = 'p'
     ) then
    alter table public.centers add constraint centers_pkey primary key (id);
  end if;

  if to_regclass('public.center_media') is not null
     and not exists (
       select 1 from pg_constraint
       where conrelid = 'public.center_media'::regclass
         and contype = 'p'
     ) then
    alter table public.center_media add constraint center_media_pkey primary key (id);
  end if;

  if to_regclass('public.consultations') is not null
     and not exists (
       select 1 from pg_constraint
       where conrelid = 'public.consultations'::regclass
         and contype = 'p'
     ) then
    alter table public.consultations add constraint consultations_pkey primary key (id);
  end if;

  if to_regclass('public.admissions') is not null
     and not exists (
       select 1 from pg_constraint
       where conrelid = 'public.admissions'::regclass
         and contype = 'p'
     ) then
    alter table public.admissions add constraint admissions_pkey primary key (id);
  end if;
end $$;

alter table public.centers
  add column if not exists owner_id uuid references auth.users(id) on delete set null,
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
  add column if not exists teacher_media_id uuid references public.center_media(id) on delete set null,
  add column if not exists teacher_id uuid references auth.users(id),
  add column if not exists updated_at timestamptz not null default now();

create index if not exists classes_center_id_idx on public.classes (center_id);
create index if not exists classes_teacher_id_idx on public.classes (teacher_id);

drop trigger if exists classes_set_updated_at on public.classes;
create trigger classes_set_updated_at
  before update on public.classes
  for each row
  execute function public.set_updated_at();

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

create index if not exists center_applications_center_name_idx
  on public.center_applications (center_name, consent_at desc);

drop trigger if exists center_applications_set_updated_at on public.center_applications;
create trigger center_applications_set_updated_at
  before update on public.center_applications
  for each row
  execute function public.set_updated_at();

create table if not exists public.platform_templates (
  id uuid primary key default gen_random_uuid(),
  template_id text unique not null
    check (template_id in ('sunshine', 'carnival', 'forest', 'gallery')),
  hero_image_url text,
  director_photo_url text,
  director_name text,
  director_message text,
  intro_text text,
  album jsonb not null default '[]'::jsonb,
  teachers jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  constraint platform_templates_album_array_check
    check (jsonb_typeof(album) = 'array'),
  constraint platform_templates_teachers_array_check
    check (jsonb_typeof(teachers) = 'array')
);

insert into public.platform_templates (template_id, album, teachers)
values
  ('sunshine', '[]'::jsonb, '[]'::jsonb),
  ('carnival', '[]'::jsonb, '[]'::jsonb),
  ('forest', '[]'::jsonb, '[]'::jsonb),
  ('gallery', '[]'::jsonb, '[]'::jsonb)
on conflict (template_id) do nothing;

alter table public.centers enable row level security;
alter table public.center_media enable row level security;
alter table public.classes enable row level security;
alter table public.consultations enable row level security;
alter table public.admissions enable row level security;
alter table public.center_applications enable row level security;
alter table public.platform_templates enable row level security;

grant usage on schema public to anon, authenticated;

revoke all on table public.centers from anon, authenticated;
revoke all on table public.center_media from anon, authenticated;
revoke all on table public.classes from anon, authenticated;
revoke all on table public.admissions from anon, authenticated;
revoke all on table public.consultations from anon, authenticated;
revoke all on table public.center_applications from anon, authenticated;

grant select on table public.centers to anon;
grant select on table public.center_media to anon;
grant select on table public.classes to anon;
grant select on table public.admissions to anon;
grant insert on table public.consultations to anon;
grant insert on table public.center_applications to anon;

grant select, insert, update, delete on table public.centers to authenticated;
grant select, insert, update, delete on table public.center_media to authenticated;
grant select, insert, update, delete on table public.classes to authenticated;
grant select, insert, update, delete on table public.admissions to authenticated;
grant select, insert, update on table public.consultations to authenticated;
grant select, insert, update on table public.center_applications to authenticated;

revoke all on table public.platform_templates from anon, authenticated;
grant select on table public.platform_templates to anon;
grant select, insert, update, delete on table public.platform_templates to authenticated;

drop policy if exists "anon can update centers" on public.centers;
drop policy if exists "anon can insert center_media" on public.center_media;
drop policy if exists "anon can update center_media" on public.center_media;

drop policy if exists centers_public_select on public.centers;
drop policy if exists "centers_public_select" on public.centers;
create policy centers_public_select
  on public.centers
  for select
  to anon, authenticated
  using (status = 'published');

drop policy if exists centers_owner_insert on public.centers;
drop policy if exists "centers_owner_insert" on public.centers;
create policy centers_owner_insert
  on public.centers
  for insert
  to authenticated
  with check (owner_id = auth.uid());

drop policy if exists centers_owner_update on public.centers;
drop policy if exists "centers_owner_update" on public.centers;
create policy centers_owner_update
  on public.centers
  for update
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists centers_owner_delete on public.centers;
create policy centers_owner_delete
  on public.centers
  for delete
  to authenticated
  using (owner_id = auth.uid());

drop policy if exists "Public read center_media" on public.center_media;
drop policy if exists center_media_public_select on public.center_media;
create policy center_media_public_select
  on public.center_media
  for select
  to anon, authenticated
  using (
    exists (
      select 1
      from public.centers c
      where c.id = center_media.center_id
        and c.status = 'published'
    )
  );

drop policy if exists center_media_owner_select on public.center_media;
drop policy if exists owner_select_media on public.center_media;
create policy center_media_owner_select
  on public.center_media
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.centers c
      where c.id = center_media.center_id
        and c.owner_id = auth.uid()
    )
  );

drop policy if exists center_media_owner_insert on public.center_media;
drop policy if exists owner_insert_media on public.center_media;
create policy center_media_owner_insert
  on public.center_media
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.centers c
      where c.id = center_media.center_id
        and c.owner_id = auth.uid()
    )
  );

drop policy if exists center_media_owner_update on public.center_media;
create policy center_media_owner_update
  on public.center_media
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.centers c
      where c.id = center_media.center_id
        and c.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.centers c
      where c.id = center_media.center_id
        and c.owner_id = auth.uid()
    )
  );

drop policy if exists center_media_owner_delete on public.center_media;
drop policy if exists owner_delete_media on public.center_media;
create policy center_media_owner_delete
  on public.center_media
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.centers c
      where c.id = center_media.center_id
        and c.owner_id = auth.uid()
    )
  );

drop policy if exists classes_public_select on public.classes;
create policy classes_public_select
  on public.classes
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
create policy classes_owner_select
  on public.classes
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

drop policy if exists classes_teacher_select on public.classes;
create policy classes_teacher_select
  on public.classes
  for select
  to authenticated
  using (teacher_id = auth.uid());

drop policy if exists classes_owner_insert on public.classes;
create policy classes_owner_insert
  on public.classes
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
create policy classes_owner_update
  on public.classes
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
create policy classes_owner_delete
  on public.classes
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

drop policy if exists consultations_public_insert on public.consultations;
drop policy if exists "consultations_public_insert" on public.consultations;
create policy consultations_public_insert
  on public.consultations
  for insert
  to anon, authenticated
  with check (
    exists (
      select 1
      from public.centers c
      where c.id = consultations.center_id
        and c.status = 'published'
    )
  );

drop policy if exists consultations_owner_select on public.consultations;
drop policy if exists "consultations_owner_select" on public.consultations;
create policy consultations_owner_select
  on public.consultations
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.centers c
      where c.id = consultations.center_id
        and c.owner_id = auth.uid()
    )
  );

drop policy if exists admissions_public_read on public.admissions;
drop policy if exists "admissions_public_read" on public.admissions;
create policy admissions_public_read
  on public.admissions
  for select
  to anon, authenticated
  using (
    exists (
      select 1
      from public.centers c
      where c.id = admissions.center_id
        and c.status = 'published'
    )
  );

drop policy if exists admissions_owner_select on public.admissions;
drop policy if exists "admissions_owner_select" on public.admissions;
create policy admissions_owner_select
  on public.admissions
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.centers c
      where c.id = admissions.center_id
        and c.owner_id = auth.uid()
    )
  );

drop policy if exists admissions_owner_insert on public.admissions;
drop policy if exists "admissions_owner_insert" on public.admissions;
create policy admissions_owner_insert
  on public.admissions
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.centers c
      where c.id = admissions.center_id
        and c.owner_id = auth.uid()
    )
  );

drop policy if exists admissions_owner_update on public.admissions;
drop policy if exists "admissions_owner_update" on public.admissions;
create policy admissions_owner_update
  on public.admissions
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.centers c
      where c.id = admissions.center_id
        and c.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.centers c
      where c.id = admissions.center_id
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

insert into storage.buckets (id, name, public)
values ('center-images', 'center-images', false)
on conflict (id) do update
set public = false;

drop policy if exists "public_read" on storage.objects;
drop policy if exists "anon can read center-images" on storage.objects;
drop policy if exists "anon can upload images" on storage.objects;
drop policy if exists "anon can update images" on storage.objects;
drop policy if exists "authenticated_upload" on storage.objects;
drop policy if exists "authenticated_delete" on storage.objects;
drop policy if exists "center_images_public_read" on storage.objects;
drop policy if exists "center_images_owner_insert" on storage.objects;
drop policy if exists "center_images_owner_update" on storage.objects;
drop policy if exists "center_images_owner_delete" on storage.objects;

create policy "center_images_public_read"
  on storage.objects
  for select
  to anon, authenticated
  using (bucket_id = 'center-images');

create policy "center_images_owner_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'center-images'
    and (storage.foldername(name))[1] = 'centers'
    and (
      exists (
        select 1
        from public.centers c
        where c.id::text = (storage.foldername(name))[2]
          and c.owner_id = auth.uid()
      )
      or exists (
        select 1
        from public.classes cl
        where (storage.foldername(name))[3] = 'classes'
          and cl.center_id::text = (storage.foldername(name))[2]
          and cl.id::text = (storage.foldername(name))[4]
          and cl.teacher_id = auth.uid()
      )
    )
  );

create policy "center_images_owner_update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'center-images'
    and (storage.foldername(name))[1] = 'centers'
    and (
      exists (
        select 1
        from public.centers c
        where c.id::text = (storage.foldername(name))[2]
          and c.owner_id = auth.uid()
      )
      or exists (
        select 1
        from public.classes cl
        where (storage.foldername(name))[3] = 'classes'
          and cl.center_id::text = (storage.foldername(name))[2]
          and cl.id::text = (storage.foldername(name))[4]
          and cl.teacher_id = auth.uid()
      )
    )
  )
  with check (
    bucket_id = 'center-images'
    and (storage.foldername(name))[1] = 'centers'
    and (
      exists (
        select 1
        from public.centers c
        where c.id::text = (storage.foldername(name))[2]
          and c.owner_id = auth.uid()
      )
      or exists (
        select 1
        from public.classes cl
        where (storage.foldername(name))[3] = 'classes'
          and cl.center_id::text = (storage.foldername(name))[2]
          and cl.id::text = (storage.foldername(name))[4]
          and cl.teacher_id = auth.uid()
      )
    )
  );

create policy "center_images_owner_delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'center-images'
    and (storage.foldername(name))[1] = 'centers'
    and (
      exists (
        select 1
        from public.centers c
        where c.id::text = (storage.foldername(name))[2]
          and c.owner_id = auth.uid()
      )
      or exists (
        select 1
        from public.classes cl
        where (storage.foldername(name))[3] = 'classes'
          and cl.center_id::text = (storage.foldername(name))[2]
          and cl.id::text = (storage.foldername(name))[4]
          and cl.teacher_id = auth.uid()
      )
    )
  );
