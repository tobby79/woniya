-- 025 cleanup, phase 1 (safe items only).
-- 1) Add the two missing 025 indexes (pure performance, no constraints).
-- 2) Normalize center_media policy names to the 025 canonical set.
--    Every remote center_media owner policy was audited to be condition-equivalent
--    to its 025 counterpart (center_id IN (my owned centers) == EXISTS owner check),
--    so this only renames/dedups — the effective access rules are unchanged.
--    The published-only public SELECT (013 fix) is preserved verbatim.
-- NOT touched here: storage.objects policies, center_applications policies.

-- ── 1. missing indexes ──────────────────────────────────────────────
create index if not exists classes_teacher_id_idx
  on public.classes (teacher_id);

create index if not exists center_applications_center_name_idx
  on public.center_applications (center_name, consent_at desc);

-- ── 2. center_media policy name normalization ───────────────────────
-- SELECT (public, published only) — 013 fix condition kept identical.
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

-- SELECT (owner) — rename owner_select_media -> center_media_owner_select.
drop policy if exists owner_select_media on public.center_media;
drop policy if exists center_media_owner_select on public.center_media;
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

-- INSERT — drop the duplicate (owner_insert_media) and keep one canonical policy.
drop policy if exists owner_insert_media on public.center_media;
drop policy if exists center_media_owner_insert on public.center_media;
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

-- UPDATE — already canonical; recreate for a consistent condition form.
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

-- DELETE — rename owner_delete_media -> center_media_owner_delete.
drop policy if exists owner_delete_media on public.center_media;
drop policy if exists center_media_owner_delete on public.center_media;
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
