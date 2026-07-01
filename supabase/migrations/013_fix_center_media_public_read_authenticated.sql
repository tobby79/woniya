-- ============================================================
-- Fix public read policies for authenticated browser sessions.
-- Public pages may run with an existing Supabase Auth session, so
-- published public content must be readable by both anon and authenticated.
-- ============================================================

drop policy if exists "Public read center_media" on public.center_media;
create policy "Public read center_media" on public.center_media
  for select
  to anon, authenticated
  using (EXISTS ( SELECT 1 FROM centers c WHERE ((c.id = center_media.center_id) AND (c.status = 'published'::text))));

drop policy if exists "admissions_public_read" on public.admissions;
create policy "admissions_public_read" on public.admissions
  for select
  to anon, authenticated
  using (true);
