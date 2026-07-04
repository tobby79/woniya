-- 보안 부채 해소: storage.objects의 소유자 검증 없는 느슨한 정책 제거
-- center_images_owner_insert/update/delete가 이미 소유자 기반으로 정상 동작 중이므로
-- bucket_id만 체크하는 아래 4개 정책은 중복이자 취약점이라 제거한다.
drop policy if exists "anon can update images" on storage.objects;
drop policy if exists "anon can upload images" on storage.objects;
drop policy if exists "authenticated_upload" on storage.objects;
drop policy if exists "authenticated_delete" on storage.objects;
