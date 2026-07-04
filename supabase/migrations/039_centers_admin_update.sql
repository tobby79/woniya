-- ===== 039_centers_admin_update.sql =====
--
-- super-admin.html 의 "원 관리" 탭에서 플랫폼 관리자가 centers.status /
-- centers.is_published 를 공개/비공개로 전환할 수 있도록 관리자 전용
-- UPDATE 정책을 추가한다.
--
-- 기존 centers_admin_select(038)는 draft 포함 전체 조회만 담당하므로 유지하고,
-- 소유자 정책(centers_owner_update)과 별도로 super-admin 정책을 둔다.

drop policy if exists centers_admin_update on public.centers;
create policy centers_admin_update
  on public.centers
  for update
  to authenticated
  using (auth.email() = 'tobby79@naver.com')
  with check (auth.email() = 'tobby79@naver.com');

-- ===== 끝 =====
