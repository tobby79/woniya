-- ============================================================
-- 임시 보안 구조 경고
-- anon 역할에 INSERT/UPDATE 권한(anon can upload images,
-- anon can update images)이 부여되어 있음. 이는 원장 콘솔이
-- 아직 Supabase Auth 기반 인증 없이 anon key로 동작하기 때문에
-- 테스트 단계에서 임시로 허용한 것임.
-- 정식 인증 체계(M2 Auth 구현) 도입 후 반드시 다음으로 교체할 것:
--   anon can upload images, anon can update images 정책 삭제
--   authenticated 역할 기준으로 본인 소유 center_id 검증하는
--   정책으로 재작성 (단순 bucket_id 체크가 아닌 owner 검증 필요)
-- ============================================================

drop policy if exists "public_read" on storage.objects;
create policy "public_read"
on storage.objects
for select
to public
using (bucket_id = 'center-images');

drop policy if exists "anon can read center-images" on storage.objects;
create policy "anon can read center-images"
on storage.objects
for select
to anon
using (bucket_id = 'center-images');

drop policy if exists "anon can upload images" on storage.objects;
create policy "anon can upload images"
on storage.objects
for insert
to anon
with check (bucket_id = 'center-images');

drop policy if exists "anon can update images" on storage.objects;
create policy "anon can update images"
on storage.objects
for update
to anon
using (bucket_id = 'center-images')
with check (bucket_id = 'center-images');

drop policy if exists "authenticated_upload" on storage.objects;
create policy "authenticated_upload"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'center-images');

drop policy if exists "authenticated_delete" on storage.objects;
create policy "authenticated_delete"
on storage.objects
for delete
to authenticated
using (bucket_id = 'center-images');
