-- consultations.kind에 걸린 CHECK 제약(consultations_kind_check)은 production DB에는
-- 존재했지만 이 저장소의 마이그레이션 이력에는 한 번도 기록된 적이 없었다.
-- 방문 상담(visit) 유형을 허용하기 위해 아래 SQL을 Supabase SQL Editor에서 이미
-- production에 직접 적용했으며, 이 파일은 그 변경 사항을 저장소에 사후 기록하는
-- 마이그레이션이다.

alter table consultations
  drop constraint consultations_kind_check;

alter table consultations
  add constraint consultations_kind_check
  check (kind = any (array['consult'::text, 'waiting'::text, 'info_session'::text, 'visit'::text]));
