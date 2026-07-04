-- ===== 041_cleanup_center_media_legacy_policies.sql =====
--
-- center_media 에 012(baseline_schema_rls)가 만든 레거시 정책과 025가 만든
-- 신규(canonical) 정책이 나란히 남아있었다. 029_025_cleanup_safe.sql 이 이미
-- 이 레거시 정책들을 drop 하도록 작성되어 있었으나(파일 내 주석: "모든 원격
-- center_media owner 정책은 025 대응 정책과 조건이 동일함을 감사했다"),
-- 실제 원격 DB에는 적용되지 않고 남아있었다(부분 미반영/drift).
--
-- 조건 동치 재검증(이번 작업 시점):
--   * "Public read center_media" (SELECT) == center_media_public_select
--     : 둘 다 EXISTS(centers c WHERE c.id=center_media.center_id AND c.status='published') — 완전 동일
--   * owner_select_media (SELECT) == center_media_owner_select
--   * owner_insert_media (INSERT) == center_media_owner_insert
--   * owner_delete_media (DELETE) == center_media_owner_delete
--     : 레거시는 `center_id IN (SELECT id FROM centers WHERE owner_id=auth.uid())`,
--       신규는 `EXISTS(centers c WHERE c.id=center_media.center_id AND c.owner_id=auth.uid())`.
--       IN 서브쿼리와 EXISTS 서브쿼리는 동일 행 집합을 반환하는 논리적 동치 표현이며,
--       실데이터(현재 center_media 0행) 기준으로도 두 조건의 결과 차이가 없음을 확인했다.
--
-- 제거 대상 4종 (029가 원래 지우려 했던 것과 동일):
--   "Public read center_media"  (SELECT)
--   owner_select_media          (SELECT)
--   owner_insert_media          (INSERT)
--   owner_delete_media          (DELETE)
--
-- 신규 정책(center_media_public_select/owner_select/owner_insert/owner_update/owner_delete)은
-- 그대로 유지되며 접근 범위 공백이 발생하지 않는다.

drop policy if exists "Public read center_media" on public.center_media;
drop policy if exists owner_select_media on public.center_media;
drop policy if exists owner_insert_media on public.center_media;
drop policy if exists owner_delete_media on public.center_media;

-- ===== 끝 =====
