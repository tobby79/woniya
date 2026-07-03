-- 기존 pending 중복이 있다면 가장 최근 것만 남기고 나머지는 revoked 처리 (데이터 보호, 삭제 아님)
with ranked as (
  select id, row_number() over (
    partition by class_id, email
    order by invited_at desc
  ) as rn
  from teacher_invites
  where status = 'pending'
)
update teacher_invites
set status = 'revoked'
where id in (select id from ranked where rn > 1);

-- pending 상태에 한해서만 (class_id, email) 유일하도록 부분 유니크 인덱스 생성
-- status가 바뀌면(accepted/revoked) 다시 초대 가능해야 하므로 전체 유니크가 아니라 pending에만 적용
create unique index if not exists teacher_invites_pending_unique
on teacher_invites (class_id, email)
where status = 'pending';
