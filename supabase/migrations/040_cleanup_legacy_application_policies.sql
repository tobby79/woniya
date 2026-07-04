-- ===== 040_cleanup_legacy_application_policies.sql =====
--
-- center_applications 에 파일로 추적되지 않는 구식 정책 3종이 원격 DB에만
-- 남아있었다(039 이전 진단에서 발견). 어느 로컬 마이그레이션 파일에도 이
-- 이름이 등장하지 않아 SQL Editor에서 수기로 만들어진 잔재로 판단된다.
--
--   "anyone can submit application"              (INSERT, with_check: true)
--   "owner can read own center applications"     (SELECT, center_name ~~* LIKE 부분매칭)
--   "owner can update own center applications"   (UPDATE, center_name ~~* LIKE 부분매칭)
--
-- 025_security_hardening_and_baseline_fixes.sql 이 만든 신규 정책이 각각의
-- 목적을 이미 대체하고 있어 제거해도 기능 공백이 없다:
--
--   center_applications_public_insert   (INSERT, center_name/director_name/phone
--                                         비어있지 않음 + consent_at 필수 +
--                                         status='new' 검증 포함 — 구식보다 엄격)
--   center_applications_owner_select    (SELECT, c.name = center_applications.center_name 정확 일치)
--   center_applications_owner_update    (UPDATE, 위와 동일 조건)
--
-- 정확 일치 vs LIKE 부분매칭 차이로 인한 회귀 가능성을 실데이터로 점검했다.
-- 제거 시점 기준 center_applications(2건)/centers(1건, owner_id 모두 null) 조합에서
-- "LIKE 매칭은 되지만 정확 일치는 안 되는" 행이 0건이었다 — 안전하게 제거 가능.

drop policy if exists "anyone can submit application" on public.center_applications;
drop policy if exists "owner can read own center applications" on public.center_applications;
drop policy if exists "owner can update own center applications" on public.center_applications;

-- ===== 끝 =====
