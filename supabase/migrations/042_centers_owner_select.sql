-- ===== 042_centers_owner_select.sql =====
--
-- 버그 수정: 원장 본인 원이 draft(비공개) 상태일 때 center_applications
-- 조회가 막히는 문제.
--
-- 원인: center_applications_owner_select 정책은
--   EXISTS (SELECT 1 FROM centers c WHERE c.name = center_applications.center_name
--                                      AND c.owner_id = auth.uid())
-- 서브쿼리로 소유 여부를 판단하는데, 이 서브쿼리도 centers 테이블 자체의 RLS를
-- 통과해야 한다. centers 에는 SELECT 정책이 centers_public_select
-- (status='published' 만 허용) 와 centers_admin_select(관리자 전용) 뿐이라,
-- 원장 본인의 draft 원은 이 서브쿼리에서 아예 보이지 않아 결과가 0행이 되고
-- center_applications 조회 자체가 막힌다.
--
-- 해결: centers 에 소유자 본인은 상태(status) 와 무관하게 조회 가능한
-- SELECT 정책을 추가한다. 기존 centers_public_select(공개 published 조회)는
-- 그대로 유지되며, 이 정책은 그와 병행(OR)되어 평가된다.
-- 조건 패턴은 기존 centers_owner_update/centers_owner_delete 와 동일하게
-- owner_id = auth.uid() 를 사용한다.

drop policy if exists centers_owner_select on public.centers;
create policy centers_owner_select
  on public.centers
  for select
  to authenticated
  using (owner_id = auth.uid());

-- ===== 끝 =====
