-- ============================================================
-- Baseline: public schema tables, RLS, and grants
-- Source: Supabase SQL Editor snapshot provided on 2026-06-30.
-- This migration intentionally records the current public schema state only.
-- Storage policies are managed separately in 011_storage_center_images_policies.sql.
-- ============================================================

create table if not exists public.centers (
  id uuid not null default gen_random_uuid(),
  owner_id uuid,
  slug text not null,
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
  status text not null default 'draft'::text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  intro text,
  operating_hours text,
  template text not null default 'sunshine'::text,
  card_image text,
  directions_text text,
  philosophy jsonb,
  programs jsonb,
  facilities jsonb
);

create table if not exists public.center_media (
  id uuid not null default gen_random_uuid(),
  center_id uuid not null,
  media_type text not null,
  sort_order integer not null default 0,
  slot text,
  time_label text,
  title text,
  subtitle text,
  photo_url text not null,
  photo_alt text,
  caption text,
  note text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.consultations (
  id uuid not null default gen_random_uuid(),
  center_id uuid not null,
  parent_name text not null,
  phone text not null,
  kind text not null,
  wish_class text,
  wish_time text,
  consent_at timestamp with time zone not null,
  status text not null default 'new'::text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.admissions (
  id uuid not null default gen_random_uuid(),
  center_id uuid,
  target text,
  capacity_info text,
  period text,
  process text,
  supplies text,
  notes text,
  updated_at timestamp with time zone default now()
);

alter table public.centers enable row level security;
alter table public.center_media enable row level security;
alter table public.consultations enable row level security;
alter table public.admissions enable row level security;

grant references on table public.admissions to anon;
grant select on table public.admissions to anon;
grant trigger on table public.admissions to anon;
grant truncate on table public.admissions to anon;
grant delete on table public.admissions to authenticated;
grant insert on table public.admissions to authenticated;
grant references on table public.admissions to authenticated;
grant select on table public.admissions to authenticated;
grant trigger on table public.admissions to authenticated;
grant truncate on table public.admissions to authenticated;
grant update on table public.admissions to authenticated;
grant references on table public.center_media to anon;
grant select on table public.center_media to anon;
grant trigger on table public.center_media to anon;
grant truncate on table public.center_media to anon;
grant insert on table public.center_media to authenticated;
grant references on table public.center_media to authenticated;
grant select on table public.center_media to authenticated;
grant trigger on table public.center_media to authenticated;
grant truncate on table public.center_media to authenticated;
grant update on table public.center_media to authenticated;
grant references on table public.centers to anon;
grant select on table public.centers to anon;
grant trigger on table public.centers to anon;
grant truncate on table public.centers to anon;
grant insert on table public.centers to authenticated;
grant references on table public.centers to authenticated;
grant select on table public.centers to authenticated;
grant trigger on table public.centers to authenticated;
grant truncate on table public.centers to authenticated;
grant update on table public.centers to authenticated;
grant insert on table public.consultations to anon;
grant references on table public.consultations to anon;
grant trigger on table public.consultations to anon;
grant truncate on table public.consultations to anon;
grant insert on table public.consultations to authenticated;
grant references on table public.consultations to authenticated;
grant select on table public.consultations to authenticated;
grant trigger on table public.consultations to authenticated;
grant truncate on table public.consultations to authenticated;

drop policy if exists "anon can update centers" on public.centers;
-- ============================================================
-- 임시 보안 구조 경고
-- anon 역할의 전체 UPDATE 권한(anon can update centers)이 부여되어 있음.
-- 이는 원장 콘솔이 아직 Supabase Auth 기반 인증 없이 anon key로 동작하기 때문에
-- 테스트 단계에서 임시로 허용한 구조임.
-- 정식 인증 체계(M2 Auth 구현) 도입 후 반드시 다음으로 교체할 것:
--   anon can update centers 정책 제거
--   authenticated 역할 기반으로 본인 소유 center_id 검증
--   이미 존재하는 centers_owner_update 정책으로 전환
-- ============================================================
create policy "anon can update centers" on public.centers
  for update
  to anon
  using (true)
  with check (true);

drop policy if exists "centers_owner_insert" on public.centers;
create policy "centers_owner_insert" on public.centers
  for insert
  to authenticated
  with check (owner_id = auth.uid());

drop policy if exists "centers_owner_update" on public.centers;
create policy "centers_owner_update" on public.centers
  for update
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists "centers_public_select" on public.centers;
create policy "centers_public_select" on public.centers
  for select
  to anon, authenticated
  using (status = 'published'::text);

drop policy if exists "Public read center_media" on public.center_media;
create policy "Public read center_media" on public.center_media
  for select
  to anon, authenticated
  using (EXISTS ( SELECT 1 FROM centers c WHERE ((c.id = center_media.center_id) AND (c.status = 'published'::text))));

drop policy if exists "anon can insert center_media" on public.center_media;
-- ============================================================
-- 임시 보안 구조 경고
-- anon 역할의 전체 INSERT 권한(anon can insert center_media)이 부여되어 있음.
-- 이는 원장 콘솔이 아직 Supabase Auth 기반 인증 없이 anon key로 동작하기 때문에
-- 테스트 단계에서 임시로 허용한 구조임.
-- 정식 인증 체계(M2 Auth 구현) 도입 후 반드시 다음으로 교체할 것:
--   anon can insert center_media 정책 제거
--   authenticated 역할 기반으로 본인 소유 center_id 검증
--   이미 존재하는 center_media_owner_insert 정책으로 전환
-- ============================================================
create policy "anon can insert center_media" on public.center_media
  for insert
  to anon
  with check (true);

drop policy if exists "anon can update center_media" on public.center_media;
-- ============================================================
-- 임시 보안 구조 경고
-- anon 역할의 전체 UPDATE 권한(anon can update center_media)이 부여되어 있음.
-- 이는 원장 콘솔이 아직 Supabase Auth 기반 인증 없이 anon key로 동작하기 때문에
-- 테스트 단계에서 임시로 허용한 구조임.
-- 정식 인증 체계(M2 Auth 구현) 도입 후 반드시 다음으로 교체할 것:
--   anon can update center_media 정책 제거
--   authenticated 역할 기반으로 본인 소유 center_id 검증
--   이미 존재하는 center_media_owner_update 정책으로 전환
-- ============================================================
create policy "anon can update center_media" on public.center_media
  for update
  to anon
  using (true)
  with check (true);

drop policy if exists "center_media_owner_insert" on public.center_media;
create policy "center_media_owner_insert" on public.center_media
  for insert
  to authenticated
  with check (EXISTS ( SELECT 1 FROM centers c WHERE ((c.id = center_media.center_id) AND (c.owner_id = auth.uid()))));

drop policy if exists "center_media_owner_update" on public.center_media;
create policy "center_media_owner_update" on public.center_media
  for update
  to authenticated
  using (EXISTS ( SELECT 1 FROM centers c WHERE ((c.id = center_media.center_id) AND (c.owner_id = auth.uid()))))
  with check (EXISTS ( SELECT 1 FROM centers c WHERE ((c.id = center_media.center_id) AND (c.owner_id = auth.uid()))));

drop policy if exists "owner_delete_media" on public.center_media;
create policy "owner_delete_media" on public.center_media
  for delete
  to authenticated
  using (center_id IN ( SELECT centers.id FROM centers WHERE (centers.owner_id = auth.uid())));

drop policy if exists "owner_insert_media" on public.center_media;
create policy "owner_insert_media" on public.center_media
  for insert
  to authenticated
  with check (center_id IN ( SELECT centers.id FROM centers WHERE (centers.owner_id = auth.uid())));

drop policy if exists "owner_select_media" on public.center_media;
create policy "owner_select_media" on public.center_media
  for select
  to authenticated
  using (center_id IN ( SELECT centers.id FROM centers WHERE (centers.owner_id = auth.uid())));

drop policy if exists "consultations_owner_select" on public.consultations;
create policy "consultations_owner_select" on public.consultations
  for select
  to authenticated
  using (EXISTS ( SELECT 1 FROM centers c WHERE ((c.id = consultations.center_id) AND (c.owner_id = auth.uid()))));

drop policy if exists "consultations_public_insert" on public.consultations;
create policy "consultations_public_insert" on public.consultations
  for insert
  to anon, authenticated
  with check (EXISTS ( SELECT 1 FROM centers c WHERE ((c.id = consultations.center_id) AND (c.status = 'published'::text))));

drop policy if exists "admissions_owner_insert" on public.admissions;
create policy "admissions_owner_insert" on public.admissions
  for insert
  to authenticated
  with check (center_id IN ( SELECT centers.id FROM centers WHERE (centers.owner_id = auth.uid())));

drop policy if exists "admissions_owner_select" on public.admissions;
create policy "admissions_owner_select" on public.admissions
  for select
  to authenticated
  using (center_id IN ( SELECT centers.id FROM centers WHERE (centers.owner_id = auth.uid())));

drop policy if exists "admissions_owner_update" on public.admissions;
create policy "admissions_owner_update" on public.admissions
  for update
  to authenticated
  using (center_id IN ( SELECT centers.id FROM centers WHERE (centers.owner_id = auth.uid())))
  with check (center_id IN ( SELECT centers.id FROM centers WHERE (centers.owner_id = auth.uid())));

drop policy if exists "admissions_public_read" on public.admissions;
create policy "admissions_public_read" on public.admissions
  for select
  to anon, authenticated
  using (true);
