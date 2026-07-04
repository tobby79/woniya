-- ===== 033_center_owner_invite_force_owner_update.sql =====
--
-- 버그 수정: accept_center_owner_invite() 가 "centers.owner_id is null 일 때만"
-- owner_id를 갱신하도록 되어 있어(031), 관리자가 대신 만든 원에 이미 owner_id가
-- 채워져 있던 경우(예: haetsal, 임시/테스트 계정 연결) 초대 수락 시
-- center_owner_invites 는 accepted 로 갱신되면서도 centers.owner_id 는
-- 조용히 그대로 남는 문제가 있었다.
--
-- 온보딩 시나리오는 "관리자가 대신 만든 원의 소유권을 새 원장 계정으로 넘기는 것"이
-- 목적이므로, 기존 owner_id 유무와 무관하게 무조건 accepted_by 로 덮어쓴다.
-- 초대 발송(invite-center-owner Edge Function) 자체가 super-admin 전용 호출이라
-- "누가 초대를 만들 수 있는지"는 이미 통제되어 있으므로 owner_id is null 조건은
-- 불필요한 안전장치였다.

create or replace function public.accept_center_owner_invite()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_invite record;
  v_linked_centers uuid[] := '{}';
begin
  select email into v_email from auth.users where id = auth.uid();

  if v_email is null then
    raise exception '로그인 정보를 확인할 수 없습니다';
  end if;

  -- 만료된 pending 초대는 먼저 expired 처리 (본인 것만).
  update public.center_owner_invites
    set status = 'expired'
    where lower(email) = lower(v_email)
      and status = 'pending'
      and expires_at < now();

  for v_invite in
    select * from public.center_owner_invites
    where lower(email) = lower(v_email)
      and status = 'pending'
      and expires_at >= now()
  loop
    -- 기존 owner_id 유무와 무관하게 초대받은 계정으로 소유권을 넘긴다.
    update public.centers
      set owner_id = auth.uid()
      where id = v_invite.center_id;

    update public.center_owner_invites
      set status = 'accepted',
          accepted_by = auth.uid(),
          accepted_at = now()
      where id = v_invite.id;

    v_linked_centers := array_append(v_linked_centers, v_invite.center_id);
  end loop;

  return jsonb_build_object('linked_centers', v_linked_centers);
end;
$$;

grant execute on function public.accept_center_owner_invite() to authenticated;

-- ===== 끝 =====
