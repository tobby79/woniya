-- ===== 015_teacher_invites.sql =====

create table if not exists teacher_invites (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references classes(id) on delete cascade,
  email text not null,
  invited_by uuid references auth.users(id),
  status text not null default 'pending' check (status in ('pending','accepted','revoked')),
  invited_at timestamptz not null default now(),
  accepted_at timestamptz
);

alter table teacher_invites enable row level security;

grant select, insert, update on teacher_invites to authenticated;

create policy teacher_invites_owner_select on teacher_invites
  for select using (is_class_owner(class_id));

create policy teacher_invites_owner_insert on teacher_invites
  for insert with check (is_class_owner(class_id));

create policy teacher_invites_owner_update on teacher_invites
  for update using (is_class_owner(class_id));

-- 교사가 초대 링크로 로그인한 뒤 스스로 실행하는 RPC.
-- 본인 이메일과 일치하는 pending 초대를 찾아서 classes.teacher_id를 자동 연결하고 초대를 accepted 처리한다.
-- teacher_invites 테이블 자체는 원장만 접근 가능하므로, 교사는 이 RPC를 통해서만 결과를 얻는다.

create or replace function accept_teacher_invite() returns jsonb
language plpgsql security definer as $$
declare
  v_email text;
  v_invite record;
  v_linked_classes uuid[] := '{}';
begin
  select email into v_email from auth.users where id = auth.uid();

  if v_email is null then
    raise exception '로그인 정보를 확인할 수 없습니다';
  end if;

  for v_invite in
    select * from teacher_invites where email = v_email and status = 'pending'
  loop
    update classes set teacher_id = auth.uid()
    where id = v_invite.class_id and teacher_id is null;

    update teacher_invites set status = 'accepted', accepted_at = now()
    where id = v_invite.id;

    v_linked_classes := array_append(v_linked_classes, v_invite.class_id);
  end loop;

  return jsonb_build_object('linked_classes', v_linked_classes);
end;
$$;

grant execute on function accept_teacher_invite() to authenticated;

-- 로그인 후 역할 판별용 헬퍼 함수 (원장인지, 교사인지 확인)

create or replace function my_owned_center_ids() returns uuid[]
language sql security definer stable as $$
  select coalesce(array_agg(id), '{}') from centers where owner_id = auth.uid();
$$;

create or replace function my_teaching_class_ids() returns uuid[]
language sql security definer stable as $$
  select coalesce(array_agg(id), '{}') from classes where teacher_id = auth.uid();
$$;

grant execute on function my_owned_center_ids() to authenticated;
grant execute on function my_teaching_class_ids() to authenticated;

-- ===== 마이그레이션 끝 =====
