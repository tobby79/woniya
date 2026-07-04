-- ===== 034_onboarding_submissions.sql =====
--
-- 목적: 원장 신청 승인 후, 홈페이지 세팅에 필요한 콘텐츠(사진 제외)를 원장에게
--       웹 폼(onboarding-form.html)으로 받는 기능의 스키마 + RPC.
--       사진은 이 폼으로 받지 않고 카카오톡으로 별도 수령한다.
--
-- 설계:
--   * onboarding_submissions 는 center_applications(신청서)에 종속된다.
--     신청 승인 후 관리자가 토큰을 발급하여 원장에게 링크를 전달하고,
--     원장은 로그인 없이 ?token= 링크로 폼을 작성/제출한다.
--   * 테이블 자체는 anon/authenticated 에게 직접 접근을 열지 않는다.
--     비로그인 원장의 폼 조회/제출은 전적으로 SECURITY DEFINER RPC 2개로만 처리한다.
--     (accept_center_owner_invite 패턴과 동일 — 테이블 직접 접근 없이 RPC 경유)
--   * 관리자(super-admin, auth.email() = 'tobby79@naver.com')만 테이블 직접
--     SELECT/INSERT/UPDATE 가능 (토큰 발급/제출 내용 확인/confirm 처리용).
--   * service_role 은 GRANT 를 명시 부여한다. (032 에서 centers GRANT 누락으로
--     Edge Function 이 막혔던 사례를 반복하지 않기 위함)

begin;

-- ---------------------------------------------------------------------------
-- 1. onboarding_submissions 테이블
-- ---------------------------------------------------------------------------
create table if not exists public.onboarding_submissions (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null
    references public.center_applications(id) on delete cascade,
  token text not null unique,
  status text not null default 'sent'
    check (status in ('sent', 'submitted', 'confirmed')),
  answers jsonb,
  created_at timestamptz not null default now(),
  submitted_at timestamptz,
  expires_at timestamptz not null default (now() + interval '30 days')
);

create index if not exists onboarding_submissions_application_id_idx
  on public.onboarding_submissions (application_id);

alter table public.onboarding_submissions enable row level security;

-- 기본 전면 차단: 명시 GRANT 전 revoke.
revoke all on table public.onboarding_submissions from anon, authenticated;

-- 관리자는 테이블을 직접 다룬다(토큰 발급 INSERT, 확인 SELECT, confirm UPDATE).
-- anon/authenticated 원장은 아래 RPC 로만 접근하므로 테이블 GRANT 를 주지 않는다.
grant select, insert, update on table public.onboarding_submissions to authenticated;

-- service_role 전권 (Edge Function/서버 작업용, GRANT 누락 방지).
grant select, insert, update, delete on table public.onboarding_submissions to service_role;

-- 1-a. platform admin(super-admin) 전권 정책
drop policy if exists onboarding_submissions_admin_select on public.onboarding_submissions;
create policy onboarding_submissions_admin_select
  on public.onboarding_submissions
  for select
  to authenticated
  using (auth.email() = 'tobby79@naver.com');

drop policy if exists onboarding_submissions_admin_insert on public.onboarding_submissions;
create policy onboarding_submissions_admin_insert
  on public.onboarding_submissions
  for insert
  to authenticated
  with check (auth.email() = 'tobby79@naver.com');

drop policy if exists onboarding_submissions_admin_update on public.onboarding_submissions;
create policy onboarding_submissions_admin_update
  on public.onboarding_submissions
  for update
  to authenticated
  using (auth.email() = 'tobby79@naver.com')
  with check (auth.email() = 'tobby79@naver.com');

-- ---------------------------------------------------------------------------
-- 2-a. get_onboarding_form(p_token): 폼 로드용
--      토큰이 유효(존재 + 만료 전)하고 status 가 'confirmed' 가 아니면
--      원 이름(center_applications.center_name)과 기존 answers(임시저장분)를 반환.
--      유효하지 않으면 null 을 반환(프론트에서 무효 링크 안내로 처리).
--      SECURITY DEFINER 라 RLS/테이블 GRANT 없이도 조회되며, 반환 범위를
--      토큰 소유 건으로만 한정하므로 다른 신청서는 노출되지 않는다.
-- ---------------------------------------------------------------------------
create or replace function public.get_onboarding_form(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub record;
  v_center_name text;
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return null;
  end if;

  select * into v_sub
  from public.onboarding_submissions
  where token = p_token
    and status <> 'confirmed'
    and expires_at >= now();

  if not found then
    return null;
  end if;

  select center_name into v_center_name
  from public.center_applications
  where id = v_sub.application_id;

  return jsonb_build_object(
    'center_name', v_center_name,
    'status', v_sub.status,
    'answers', coalesce(v_sub.answers, '{}'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 2-b. submit_onboarding_form(p_token, p_answers): 제출용
--      토큰 검증 후 answers 저장, status='submitted', submitted_at=now().
--      이미 confirmed 면 거부(예외). 무효/만료 토큰도 예외.
-- ---------------------------------------------------------------------------
create or replace function public.submit_onboarding_form(p_token text, p_answers jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sub record;
begin
  if p_token is null or length(trim(p_token)) = 0 then
    raise exception '유효하지 않은 링크입니다';
  end if;

  select * into v_sub
  from public.onboarding_submissions
  where token = p_token;

  if not found then
    raise exception '유효하지 않은 링크입니다';
  end if;

  if v_sub.status = 'confirmed' then
    raise exception '이미 확정된 신청서입니다';
  end if;

  if v_sub.expires_at < now() then
    raise exception '만료된 링크입니다';
  end if;

  update public.onboarding_submissions
    set answers = p_answers,
        status = 'submitted',
        submitted_at = now()
    where id = v_sub.id;

  return jsonb_build_object('success', true);
end;
$$;

-- 두 함수 모두 비로그인(anon) 원장이 호출할 수 있어야 한다.
grant execute on function public.get_onboarding_form(text) to anon, authenticated;
grant execute on function public.submit_onboarding_form(text, jsonb) to anon, authenticated;

commit;

-- ===== 마이그레이션 끝 =====
