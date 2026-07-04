-- ===== 038_centers_admin_select.sql =====
--
-- 버그 수정: super-admin.html 신청서 상세 모달에서 이미 생성된 원("생성된 원"
-- 영역)을 다시 열면 "원 정보를 불러오지 못했습니다"가 표시되는 문제.
--
-- 원인: loadCreatedCenterLink() 가 anon 키(client)로 centers 를 직접
-- SELECT 하는데, centers_public_select 정책은 status='published' 인
-- 원만 허용한다. 생성 직후 원은 draft(비공개) 이므로 이 조회가 RLS 에
-- 막혀 res.data 가 비어 에러 문구로 빠진다.
-- (생성 직후 콜백은 create_center_from_onboarding RPC 의 반환값을 그대로
-- 재사용해 문제 없이 동작 — 재조회가 필요한 "모달 재오픈" 케이스만 실패)
--
-- 035(center_applications_admin_select), 036 과 동일한 패턴으로
-- centers 에도 관리자 전용 SELECT 정책을 추가한다. 공개 조회
-- (centers_public_select) 는 그대로 두고, 관리자 세션에서만 draft 포함
-- 전체 조회가 추가로 허용된다.

drop policy if exists centers_admin_select on public.centers;
create policy centers_admin_select
  on public.centers
  for select
  to authenticated
  using (auth.email() = 'tobby79@naver.com');

-- ===== 끝 =====
