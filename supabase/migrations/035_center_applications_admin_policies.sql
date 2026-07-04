-- ===== 035_center_applications_admin_policies.sql =====
--
-- 목적: 플랫폼 관리자(super-admin.html, auth.email() = 'tobby79@naver.com')가
--       신청서 관리 화면에서 center_applications 전체를 조회하고
--       status(new/setting/done/rejected)를 변경할 수 있도록 RLS/GRANT 추가.
--
-- 현재 상태(작업 전 원격 catalog 조회로 확정):
--   * center_applications 에는 owner 대상 SELECT/UPDATE 정책만 있고
--     (center_name 을 centers.name 과 LIKE 매칭), 관리자 전용 정책이 없다.
--   * authenticated 에게 UPDATE 테이블 GRANT 자체가 없어(INSERT/SELECT 만),
--     정책만 추가해도 admin UPDATE 가 42501 로 막힌다. GRANT 도 함께 부여한다.
--   * onboarding_submissions 는 034 에서 이미 admin 전용 SELECT/INSERT/UPDATE
--     정책 + authenticated GRANT 가 있으므로 여기서 손대지 않는다.

begin;

-- admin 이 status 변경(UPDATE)을 하려면 테이블 UPDATE GRANT 가 필요하다.
grant update on table public.center_applications to authenticated;

-- 관리자 전용 전체 SELECT (owner 매칭 정책과 별개로 OR 결합되어 전체 조회 허용).
drop policy if exists center_applications_admin_select on public.center_applications;
create policy center_applications_admin_select
  on public.center_applications
  for select
  to authenticated
  using (auth.email() = 'tobby79@naver.com');

-- 관리자 전용 UPDATE (status 변경: setting/done/rejected 처리).
drop policy if exists center_applications_admin_update on public.center_applications;
create policy center_applications_admin_update
  on public.center_applications
  for update
  to authenticated
  using (auth.email() = 'tobby79@naver.com')
  with check (auth.email() = 'tobby79@naver.com');

commit;

-- ===== 마이그레이션 끝 =====
