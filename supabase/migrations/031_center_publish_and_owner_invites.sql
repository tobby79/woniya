-- ===== 031_center_publish_and_owner_invites.sql =====
--
-- 목적: 플랫폼 관리자가 온보딩 과정에서 원(center)을 대신 생성할 때 필요한
--       스키마 변경. (1) 원 공개/비공개 상태, (2) 초대 링크로 원장 계정을
--       center 소유권에 연결, (3) 신청서(center_applications) 상태 관리 및
--       실제 center 연결 추적.
--
-- 파일명 안내: 요청 파일명은 019_... 였으나 019~030 번호가 이미 모두 사용 중이라
--            중복을 피하기 위해 다음 번호(031)로 생성했다. (016_teacher_invites 등
--            기존 규칙과 동일하게 연번 유지)
--
-- 설계 결정(작업 전 실제 원격 DB catalog 조회로 확정):
--   * teacher_invites 실제 스키마에는 token / expires_at 컬럼이 없다.
--     Supabase auth.admin.inviteUserByEmail(매직 링크) + auth.users.email 매칭으로
--     동작하며 별도 랜덤 토큰 생성 로직이 없다. 사용자 확인 결과 center_owner_invites도
--     "토큰 없이 email 매칭" 패턴을 그대로 따른다. 따라서 token 컬럼은 만들지 않고,
--     수락은 로그인한 사용자의 email이 초대 email과 일치하는지로 판별한다.
--   * center_applications 실제 CHECK 제약명은 center_applications_status_check 이고
--     값은 ('new','contacted','converted','closed')이다(마이그레이션 파일과 불일치).
--     이 실제 제약을 drop 후 요청대로 재생성한다.
--   * super-admin 판별은 기존 template_centers / platform_templates 정책과 동일하게
--     auth.email() = 'tobby79@naver.com' 을 사용한다.
--
-- 기존 테스트 데이터(haetsal/soop/carnival/gallery 센터, 신청서 2건) DELETE는
-- 이 파일에 포함하지 않는다. centers 삭제는 center_media / classes(→class_mini) /
-- admissions / consultations 로 ON DELETE CASCADE 전파되므로, 별도 확인 후 수동 실행한다.

begin;

-- ---------------------------------------------------------------------------
-- 1. centers: 공개/비공개 상태 컬럼 추가
--    기존 status('draft'/'published'/'archived')와 별개로, 온보딩 완료 전까지
--    노출을 막는 명시적 published 플래그. 테스트 데이터는 전부 삭제 예정이므로
--    기본값 false 로 통일한다.
-- ---------------------------------------------------------------------------
alter table public.centers
  add column if not exists is_published boolean not null default false;

-- ---------------------------------------------------------------------------
-- 2. center_owner_invites: 원장 초대 테이블 신규 생성
--    teacher_invites 패턴(토큰 없이 email + auth.users.email 매칭)을 따른다.
--    expires_at / accepted_by / accepted_at 는 온보딩 추적을 위해 추가한다.
-- ---------------------------------------------------------------------------
create table if not exists public.center_owner_invites (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references public.centers(id) on delete cascade,
  email text not null,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_by uuid references auth.users(id),
  accepted_at timestamptz
);

-- pending 상태에 한해 (center_id, email) 유일 (teacher_invites_pending_unique 패턴).
-- 만료/수락되면 재초대가 가능해야 하므로 전체 유니크가 아니라 pending 부분 유니크로 둔다.
create unique index if not exists center_owner_invites_pending_unique
  on public.center_owner_invites (center_id, email)
  where status = 'pending';

create index if not exists center_owner_invites_email_idx
  on public.center_owner_invites (email)
  where status = 'pending';

alter table public.center_owner_invites enable row level security;

-- 기본 전면 차단: 명시 GRANT 전 revoke.
revoke all on table public.center_owner_invites from anon, authenticated;

-- authenticated 는 RLS 정책이 허용하는 범위에서만 SELECT 가능.
-- INSERT/UPDATE 는 super-admin 정책으로만 통과.
grant select, insert, update on table public.center_owner_invites to authenticated;

-- service_role 은 Edge Function(초대 발송/수락 처리)용 전권. (018 패턴)
grant select, insert, update, delete on table public.center_owner_invites to service_role;

-- 2-a. platform admin(super-admin) 전권 정책
drop policy if exists center_owner_invites_admin_select on public.center_owner_invites;
create policy center_owner_invites_admin_select
  on public.center_owner_invites
  for select
  to authenticated
  using (auth.email() = 'tobby79@naver.com');

drop policy if exists center_owner_invites_admin_insert on public.center_owner_invites;
create policy center_owner_invites_admin_insert
  on public.center_owner_invites
  for insert
  to authenticated
  with check (auth.email() = 'tobby79@naver.com');

drop policy if exists center_owner_invites_admin_update on public.center_owner_invites;
create policy center_owner_invites_admin_update
  on public.center_owner_invites
  for update
  to authenticated
  using (auth.email() = 'tobby79@naver.com')
  with check (auth.email() = 'tobby79@naver.com');

-- 2-b. 초대받은 본인은 자신의 pending 초대만 SELECT 가능 (수락 화면용).
--      email 은 대소문자 무시로 비교한다.
drop policy if exists center_owner_invites_invitee_select on public.center_owner_invites;
create policy center_owner_invites_invitee_select
  on public.center_owner_invites
  for select
  to authenticated
  using (
    status = 'pending'
    and lower(email) = lower(auth.email())
  );

-- ---------------------------------------------------------------------------
-- 3. center_applications: 상태 관리 및 실제 center 연결 추적 컬럼 추가
--    실제 CHECK 제약(center_applications_status_check)은 값이 달라 drop 후 재생성.
-- ---------------------------------------------------------------------------
alter table public.center_applications
  drop constraint if exists center_applications_status_check;

alter table public.center_applications
  alter column status set default 'new';

-- 기존 행 중 새 허용값에 없는 status 를 안전하게 'new' 로 정규화한 뒤 제약 추가.
update public.center_applications
  set status = 'new'
  where status not in ('new', 'setting', 'done', 'rejected');

alter table public.center_applications
  add constraint center_applications_status_check
  check (status in ('new', 'setting', 'done', 'rejected'));

alter table public.center_applications
  add column if not exists linked_center_id uuid references public.centers(id);

-- ---------------------------------------------------------------------------
-- 4. 초대 수락 RPC: accept_center_owner_invite()
--    teacher_invites 의 accept_teacher_invite() 패턴을 그대로 재사용한다.
--    로그인한 사용자의 email 과 일치하는 pending & 미만료 초대를 찾아
--    centers.owner_id 를 auth.uid() 로 연결하고(소유권 미할당 원에 한해),
--    초대를 accepted / accepted_by / accepted_at 로 갱신한다.
--    security definer 이므로 초대받은 본인만 자신의 초대를 수락할 수 있고,
--    테이블 직접 UPDATE 권한 없이 이 RPC 로만 소유권이 연결된다.
-- ---------------------------------------------------------------------------
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
    -- 소유권이 아직 없는 원에만 연결한다. (이미 주인이 있으면 건드리지 않음)
    update public.centers
      set owner_id = auth.uid()
      where id = v_invite.center_id
        and owner_id is null;

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

commit;

-- ===== 마이그레이션 끝 =====
