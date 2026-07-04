-- ===== 036_create_center_from_onboarding.sql =====
--
-- 목적: 신청서 관리 화면의 "실제 원 생성" 기능. onboarding_submissions.answers
--       (원장이 온보딩 폼으로 제출한 8개 섹션 데이터)를 기반으로 centers 실제
--       레코드 + 선생님(center_media) + 입학안내(admissions)를 한 트랜잭션으로
--       생성하고, center_applications.linked_center_id/status 및
--       onboarding_submissions.status 를 갱신한다.
--
-- 설계:
--   * 여러 테이블 INSERT/UPDATE 를 "하나라도 실패하면 전체 롤백"으로 묶어야 하므로
--     프론트 개별 요청이 아니라 단일 SECURITY DEFINER 함수(=단일 트랜잭션)로 처리한다.
--     (accept_center_owner_invite / submit_onboarding_form 과 동일한 RPC 패턴)
--   * 함수 내부에서 관리자(auth.email() = 'tobby79@naver.com') 인지 먼저 검증하므로
--     이 함수를 통한 원 생성은 super-admin 만 가능하다.
--   * SECURITY DEFINER 라 테이블 RLS 를 우회하지만, 방어적으로 centers/admissions 에
--     admin INSERT 정책도 함께 추가한다(향후 프론트가 직접 INSERT 하게 될 경우 대비).
--
-- answers → 스키마 매핑 (실제 스키마/템플릿 렌더 코드 확인 후 확정):
--   basic.official_name           → centers.name
--   basic.address                 → centers.address
--   basic.hours                   → centers.operating_hours
--   basic.capacity/class_count/teacher_count/hours → centers.facilities.stats[{label,value}]
--   intro.about                   → centers.intro
--   intro.greeting                → centers.director.message (badge/sign 포함 director jsonb)
--   intro.philosophy/child_image  → centers.philosophy jsonb
--   directions.*                  → centers.directions_text (조합 텍스트)
--   faqs[]                        → centers.faqs {eyebrow,title,items:[{q,a}]}
--   tags[]                        → centers.tags text[]
--   badges[]                      → centers.badges jsonb {items:[...]}
--   teachers[]                    → center_media (media_type='teacher', title=이름, subtitle=역할·반)
--   admission.*                   → admissions (target/capacity_info/period/process/supplies)
--   slug/template/owner_id(null)/is_published(false)/status('draft' — 비공개 생성)

begin;

-- ── 방어적 admin INSERT 정책 (RPC 는 SECURITY DEFINER 라 없어도 되지만 명시) ──
drop policy if exists centers_admin_insert on public.centers;
create policy centers_admin_insert
  on public.centers
  for insert
  to authenticated
  with check (auth.email() = 'tobby79@naver.com');

drop policy if exists admissions_admin_insert on public.admissions;
create policy admissions_admin_insert
  on public.admissions
  for insert
  to authenticated
  with check (auth.email() = 'tobby79@naver.com');

-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.create_center_from_onboarding(
  p_submission_id uuid,
  p_template text,
  p_slug text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_sub record;
  v_app record;
  v_answers jsonb;
  v_basic jsonb;
  v_intro jsonb;
  v_dir jsonb;
  v_center_id uuid;
  v_name text;
  v_slug text;
  v_stats jsonb := '[]'::jsonb;
  v_dir_text text := '';
  v_faq_items jsonb := '[]'::jsonb;
  v_teacher jsonb;
  v_tags text[] := '{}';
  v_badges jsonb := '[]'::jsonb;
  v_faq jsonb;
  v_sort int := 0;
begin
  -- 1) 관리자 검증
  v_email := auth.email();
  if v_email is null or v_email <> 'tobby79@naver.com' then
    raise exception '플랫폼 관리자만 원을 생성할 수 있습니다';
  end if;

  -- 2) 템플릿 검증
  if p_template is null or p_template not in ('sunshine','forest','carnival','gallery') then
    raise exception '유효한 템플릿을 선택해주세요';
  end if;

  -- 3) 슬러그 검증 + 중복 체크
  v_slug := lower(trim(coalesce(p_slug, '')));
  if v_slug = '' then
    raise exception '슬러그(URL 주소)를 입력해주세요';
  end if;
  if v_slug !~ '^[a-z0-9-]+$' then
    raise exception '슬러그는 영문 소문자, 숫자, 하이픈(-)만 사용할 수 있습니다';
  end if;
  if exists (select 1 from public.centers where slug = v_slug) then
    raise exception '이미 사용 중인 슬러그입니다: %', v_slug;
  end if;

  -- 4) 제출 레코드 확인
  select * into v_sub from public.onboarding_submissions where id = p_submission_id;
  if not found then
    raise exception '온보딩 제출을 찾을 수 없습니다';
  end if;
  if v_sub.status <> 'submitted' then
    raise exception '제출 완료(submitted) 상태의 신청서만 원으로 생성할 수 있습니다';
  end if;

  select * into v_app from public.center_applications where id = v_sub.application_id;
  if not found then
    raise exception '연결된 신청서를 찾을 수 없습니다';
  end if;
  if v_app.linked_center_id is not null then
    raise exception '이미 원이 생성된 신청서입니다';
  end if;

  v_answers := coalesce(v_sub.answers, '{}'::jsonb);
  v_basic := coalesce(v_answers->'basic', '{}'::jsonb);
  v_intro := coalesce(v_answers->'intro', '{}'::jsonb);
  v_dir   := coalesce(v_answers->'directions', '{}'::jsonb);

  v_name := nullif(trim(coalesce(v_basic->>'official_name','')), '');
  if v_name is null then
    v_name := coalesce(v_app.center_name, '이름 없는 원');
  end if;

  -- 5) facilities.stats 조립 (운영시간/정원/반수/교사수 중 값이 있는 것만)
  if nullif(trim(coalesce(v_basic->>'hours','')), '') is not null then
    v_stats := v_stats || jsonb_build_array(jsonb_build_object('label','운영시간','value', v_basic->>'hours'));
  end if;
  if nullif(trim(coalesce(v_basic->>'capacity','')), '') is not null then
    v_stats := v_stats || jsonb_build_array(jsonb_build_object('label','정원','value', v_basic->>'capacity'));
  end if;
  if nullif(trim(coalesce(v_basic->>'class_count','')), '') is not null then
    v_stats := v_stats || jsonb_build_array(jsonb_build_object('label','반 수','value', v_basic->>'class_count'));
  end if;
  if nullif(trim(coalesce(v_basic->>'teacher_count','')), '') is not null then
    v_stats := v_stats || jsonb_build_array(jsonb_build_object('label','선생님','value', v_basic->>'teacher_count'));
  end if;

  -- 6) directions_text 조립 (주차/대중교통/통학차량)
  if nullif(trim(coalesce(v_dir->>'parking','')), '') is not null then
    v_dir_text := v_dir_text || '[주차] ' || (v_dir->>'parking') || E'\n';
  end if;
  if nullif(trim(coalesce(v_dir->>'transit','')), '') is not null then
    v_dir_text := v_dir_text || '[대중교통] ' || (v_dir->>'transit') || E'\n';
  end if;
  if (v_dir->>'shuttle') = 'yes' then
    v_dir_text := v_dir_text || '[통학차량] 운영';
    if nullif(trim(coalesce(v_dir->>'shuttle_detail','')), '') is not null then
      v_dir_text := v_dir_text || ' — ' || (v_dir->>'shuttle_detail');
    end if;
    v_dir_text := v_dir_text || E'\n';
  elsif (v_dir->>'shuttle') = 'no' then
    v_dir_text := v_dir_text || '[통학차량] 운영 안 함' || E'\n';
  end if;
  v_dir_text := nullif(trim(v_dir_text), '');

  -- 7) FAQ items 조립
  if jsonb_typeof(v_answers->'faqs') = 'array' then
    select coalesce(jsonb_agg(jsonb_build_object('q', elem->>'q', 'a', elem->>'a')), '[]'::jsonb)
    into v_faq_items
    from jsonb_array_elements(v_answers->'faqs') as elem;
  end if;
  v_faq := jsonb_build_object(
    'eyebrow', 'FAQ',
    'title', '자주 묻는 질문',
    'items', v_faq_items
  );

  -- 8) tags text[] / badges jsonb
  if jsonb_typeof(v_answers->'tags') = 'array' then
    select coalesce(array_agg(value), '{}') into v_tags
    from jsonb_array_elements_text(v_answers->'tags');
  end if;
  if jsonb_typeof(v_answers->'badges') = 'array' then
    v_badges := jsonb_build_object('items', v_answers->'badges');
  else
    v_badges := jsonb_build_object('items', '[]'::jsonb);
  end if;

  -- 9) centers INSERT
  insert into public.centers (
    slug, name, address, template, theme,
    owner_id, is_published, status,
    operating_hours, intro, directions_text,
    director, philosophy, facilities, faqs, tags, badges
  ) values (
    v_slug, v_name, nullif(trim(coalesce(v_basic->>'address','')), ''),
    p_template, 'pink',
    -- 온보딩 직후에는 비공개로 생성한다. 공개 조회 RLS(centers_public_select)는
    -- status='published' 기준이므로 'draft' 로 두면 관리자/원장 검토 전까지 노출되지 않는다.
    null, false, 'draft',
    nullif(trim(coalesce(v_basic->>'hours','')), ''),
    nullif(trim(coalesce(v_intro->>'about','')), ''),
    v_dir_text,
    jsonb_build_object(
      'badge', '원장 인사말',
      'message', coalesce(v_intro->>'greeting',''),
      'sign_label', '',
      'sign_name', coalesce(v_app.director_name,''),
      'photo', '',
      'photo_alt', v_name || ' 원장'
    ),
    jsonb_build_object(
      'motto', coalesce(v_intro->>'philosophy',''),
      'child_image', coalesce(v_intro->>'child_image','')
    ),
    jsonb_build_object('stats', v_stats),
    v_faq,
    v_tags,
    v_badges
  )
  returning id into v_center_id;

  -- 10) 선생님 → center_media (media_type='teacher')
  if jsonb_typeof(v_answers->'teachers') = 'array' then
    for v_teacher in select * from jsonb_array_elements(v_answers->'teachers')
    loop
      v_sort := v_sort + 1;
      insert into public.center_media (
        center_id, media_type, sort_order, title, subtitle, photo_url
      ) values (
        v_center_id, 'teacher', v_sort,
        nullif(trim(coalesce(v_teacher->>'name','')), ''),
        -- 역할 + 담당 반을 subtitle 로 합침 (예: "담임 · 햇살반")
        nullif(trim(
          concat_ws(' · ',
            nullif(trim(coalesce(v_teacher->>'role','')), ''),
            nullif(trim(coalesce(v_teacher->>'class','')), '')
          )
        ), ''),
        ''
      );
    end loop;
  end if;

  -- 11) 입학안내 → admissions
  insert into public.admissions (
    center_id, target, capacity_info, period, process, supplies
  ) values (
    v_center_id,
    nullif(trim(coalesce((v_answers#>>'{admission,target_age}'),'')), ''),
    nullif(trim(coalesce((v_answers#>>'{admission,capacity_info}'),'')), ''),
    nullif(trim(coalesce((v_answers#>>'{admission,period}'),'')), ''),
    nullif(trim(coalesce((v_answers#>>'{admission,process}'),'')), ''),
    nullif(trim(coalesce((v_answers#>>'{admission,supplies}'),'')), '')
  );

  -- 12) 신청서/제출 상태 갱신
  update public.center_applications
    set linked_center_id = v_center_id, status = 'done'
    where id = v_app.id;

  update public.onboarding_submissions
    set status = 'confirmed'
    where id = v_sub.id;

  return jsonb_build_object(
    'center_id', v_center_id,
    'slug', v_slug,
    'template', p_template
  );
end;
$$;

grant execute on function public.create_center_from_onboarding(uuid, text, text) to authenticated;

commit;

-- ===== 마이그레이션 끝 =====
