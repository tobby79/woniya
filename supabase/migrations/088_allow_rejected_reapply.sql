-- 088: redeem_class_invite에서 rejected 상태 재신청 시 pending으로 재활성화, child_name 갱신
-- (기존 on conflict do nothing으로 인해 거절된 학부모가 영구히 재신청 불가능했던 결함 수정)

create or replace function redeem_class_invite(p_code text, p_child_name text)
returns uuid
language plpgsql security definer as $$
declare
  v_invite class_invites%rowtype;
  v_enrollment_id uuid;
  v_trimmed_name text;
  v_existing class_enrollments%rowtype;
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

  select * into v_existing from class_enrollments
  where class_id = v_invite.class_id and parent_id = auth.uid();

  if not found then
    insert into class_enrollments (class_id, parent_id, invite_id, status, child_name)
    values (v_invite.class_id, auth.uid(), v_invite.id, 'pending', v_trimmed_name)
    returning id into v_enrollment_id;
  elsif v_existing.status = 'rejected' then
    update class_enrollments
    set status = 'pending',
        child_name = v_trimmed_name,
        invite_id = v_invite.id,
        requested_at = now(),
        approved_at = null,
        approved_by = null
    where id = v_existing.id
    returning id into v_enrollment_id;
  elsif v_existing.status = 'pending' then
    update class_enrollments
    set child_name = v_trimmed_name
    where id = v_existing.id
    returning id into v_enrollment_id;
  else
    v_enrollment_id := v_existing.id;
  end if;

  return v_enrollment_id;
end;
$$;

alter function redeem_class_invite(text, text) set search_path = public, pg_temp;

revoke all on function redeem_class_invite(text, text) from public;
grant execute on function redeem_class_invite(text, text) to authenticated;
