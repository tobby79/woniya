-- 087: 학부모 반 연결 신청 시 아이 이름을 함께 받아 저장 (승인 화면 식별 정보 보완)

-- 1. class_enrollments에 child_name 컬럼 추가 (nullable — 기존 신청 건은 값 없음, admin.html에서 폴백 처리)
alter table class_enrollments
  add column if not exists child_name text;

-- 2. 기존 1-인자 함수 제거 (시그니처가 바뀌므로 create or replace로 대체되지 않음)
drop function if exists redeem_class_invite(text);

-- 3. redeem_class_invite RPC 재정의 — p_child_name 파라미터 추가, 필수 값 검증
create or replace function redeem_class_invite(p_code text, p_child_name text)
returns uuid
language plpgsql security definer as $$
declare
  v_invite class_invites%rowtype;
  v_enrollment_id uuid;
  v_trimmed_name text;
begin
  v_trimmed_name := trim(p_child_name);
  if v_trimmed_name is null or v_trimmed_name = '' then
    raise exception '아이 이름을 입력해주세요';
  end if;

  select * into v_invite from class_invites
  where code = p_code and status = 'active' and (expires_at is null or expires_at > now());

  if not found then
    raise exception '유효하지 않거나 만료된 초대 코드입니다';
  end if;

  insert into class_enrollments (class_id, parent_id, invite_id, status, child_name)
  values (v_invite.class_id, auth.uid(), v_invite.id, 'pending', v_trimmed_name)
  on conflict (class_id, parent_id) do nothing
  returning id into v_enrollment_id;

  if v_enrollment_id is null then
    select id into v_enrollment_id from class_enrollments
    where class_id = v_invite.class_id and parent_id = auth.uid();
  end if;

  return v_enrollment_id;
end;
$$;

-- 4. search_path 명시 재설정 (create or replace 시 초기화되므로 기존 마이그레이션과 동일 패턴 재적용)
alter function redeem_class_invite(text, text) set search_path = public, pg_temp;

-- 5. 실행 권한 재설정 (create or replace 시 PUBLIC EXECUTE가 자동 부여되므로 회수 후 authenticated만 허용)
revoke all on function redeem_class_invite(text, text) from public;
grant execute on function redeem_class_invite(text, text) to authenticated;
