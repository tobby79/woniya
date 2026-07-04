-- ===== 032_centers_service_role_grant.sql =====
--
-- invite-center-owner Edge Function이 service_role 클라이언트로 centers를
-- SELECT할 때 "permission denied for table centers" 발생.
-- 원인: centers 테이블에 service_role 대상 GRANT가 애초에 없었음
-- (018_service_role_grants.sql 은 classes/teacher_invites 계열만 부여했고
-- centers 는 누락되어 있었다. service_role 은 RLS는 우회하지만 테이블
-- 자체의 GRANT 는 별도로 필요하다).

grant select, insert, update, delete on public.centers to service_role;

-- ===== 끝 =====
