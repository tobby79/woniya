begin;

-- Applications and onboarding materials have different retention periods.
-- Center-owned onboarding must survive application deletion, while onboarding
-- without a center remains application-owned. Actual cleanup is implemented later.
do $precondition$
declare
  v_application_fk_count integer;
  v_matching_fk_count integer;
begin
  select count(*)
    into v_application_fk_count
  from pg_constraint as constraint_row
  join pg_attribute as child_column
    on child_column.attrelid = constraint_row.conrelid
   and child_column.attname = 'application_id'
   and not child_column.attisdropped
  where constraint_row.contype = 'f'
    and constraint_row.conrelid = 'public.onboarding_submissions'::regclass
    and child_column.attnum = any(constraint_row.conkey);

  select count(*)
    into v_matching_fk_count
  from pg_constraint as constraint_row
  join pg_attribute as child_column
    on child_column.attrelid = constraint_row.conrelid
   and child_column.attname = 'application_id'
   and not child_column.attisdropped
  join pg_attribute as parent_column
    on parent_column.attrelid = constraint_row.confrelid
   and parent_column.attname = 'id'
   and not parent_column.attisdropped
  where constraint_row.conname = 'onboarding_submissions_application_id_fkey'
    and constraint_row.contype = 'f'
    and constraint_row.conrelid = 'public.onboarding_submissions'::regclass
    and constraint_row.confrelid = 'public.center_applications'::regclass
    and constraint_row.confdeltype = 'c'
    and constraint_row.conkey = array[child_column.attnum]
    and constraint_row.confkey = array[parent_column.attnum];

  if v_application_fk_count <> 1 or v_matching_fk_count <> 1 then
    raise exception
      'Expected exactly one application_id FK: onboarding_submissions_application_id_fkey -> center_applications.id with ON DELETE CASCADE';
  end if;
end;
$precondition$;

alter table public.onboarding_submissions
  add column center_id uuid;

comment on column public.onboarding_submissions.center_id is
  'Center that owns retained onboarding materials after the source application is removed.';

alter table public.onboarding_submissions
  add constraint onboarding_submissions_center_id_fkey
  foreign key (center_id)
  references public.centers(id)
  on delete restrict;

create index onboarding_submissions_center_id_idx
  on public.onboarding_submissions (center_id);

-- Backfill only through the existing UUID relationship. Do not infer by name,
-- slug, owner, or any other descriptive value.
update public.onboarding_submissions as submission
set center_id = application.linked_center_id
from public.center_applications as application
where submission.application_id = application.id
  and application.linked_center_id is not null
  and submission.center_id is null;

alter table public.onboarding_submissions
  alter column application_id drop not null;

alter table public.onboarding_submissions
  drop constraint onboarding_submissions_application_id_fkey;

alter table public.onboarding_submissions
  add constraint onboarding_submissions_application_id_fkey
  foreign key (application_id)
  references public.center_applications(id)
  on delete set null;

alter table public.onboarding_submissions
  add constraint onboarding_submissions_retention_owner_check
  check (application_id is not null or center_id is not null);

create or replace function public.create_center_from_onboarding(
  p_submission_id uuid,
  p_template text,
  p_slug text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
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
  v_region text;
  v_contact_phone text;
  v_intro_text text;
  v_stats jsonb := '[]'::jsonb;
  v_dir_text text := '';
  v_faq_items jsonb := '[]'::jsonb;
  v_teacher jsonb;
  v_tags text[] := '{}';
  v_badge_items jsonb := '[]'::jsonb;
  v_badges jsonb;
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

  -- basic.region is accepted for forward compatibility. The current onboarding
  -- form does not send it, so the application region is the normal fallback.
  v_region := coalesce(
    nullif(trim(coalesce(v_basic->>'region','')), ''),
    nullif(trim(coalesce(v_app.region,'')), '')
  );

  -- basic.phone is explicitly labelled as the center's representative phone.
  -- center_applications.phone is private application/contact data and is not
  -- used as a public fallback.
  v_contact_phone := nullif(trim(coalesce(v_basic->>'phone','')), '');
  v_intro_text := nullif(trim(coalesce(v_intro->>'about','')), '');

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

  -- 8) tags text[] / badges {items:[string...]}
  if jsonb_typeof(v_answers->'tags') = 'array' then
    select coalesce(array_agg(value), '{}') into v_tags
    from jsonb_array_elements_text(v_answers->'tags');
  end if;
  if jsonb_typeof(v_answers->'badges') = 'array' then
    select coalesce(jsonb_agg(d.badge order by d.first_position), '[]'::jsonb)
    into v_badge_items
    from (
      select btrim(item.value) as badge, min(item.ordinality) as first_position
      from jsonb_array_elements_text(v_answers->'badges') with ordinality as item(value, ordinality)
      where nullif(btrim(item.value), '') is not null
      group by btrim(item.value)
    ) as d;
  end if;
  v_badges := jsonb_build_object('items', v_badge_items);

  -- 9) centers INSERT
  insert into public.centers (
    slug, name, region, address, contact_phone, template, theme,
    owner_id, is_published, status,
    operating_hours, intro, directions_text,
    hero, director, philosophy, facilities, faqs, finale, footer, tags, badges
  ) values (
    v_slug, v_name, v_region,
    nullif(trim(coalesce(v_basic->>'address','')), ''),
    v_contact_phone,
    p_template, 'pink',
    null, false, 'draft',
    nullif(trim(coalesce(v_basic->>'hours','')), ''),
    v_intro_text,
    v_dir_text,
    jsonb_build_object(
      'eyebrow', '우리 원을 소개합니다',
      'title', v_name,
      'title_accent', '',
      'subtitle', coalesce(v_intro_text, v_name || '의 이야기를 소개합니다.')
    ),
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
    jsonb_build_object(
      'title', v_name || '에 대해 궁금한 점이 있으신가요?',
      'subtitle', '입학과 상담에 관한 문의를 남겨주세요.',
      'cta', '입소상담 신청하기'
    ),
    jsonb_build_object(
      'tag', v_name,
      'text', '원이야'
    ),
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
        center_id, media_type, sort_order, title, subtitle,
        photo_url, caption, note
      ) values (
        v_center_id, 'teacher', v_sort,
        nullif(trim(coalesce(v_teacher->>'name','')), ''),
        nullif(trim(
          concat_ws(' · ',
            nullif(trim(coalesce(v_teacher->>'role','')), ''),
            nullif(trim(coalesce(v_teacher->>'class','')), '')
          )
        ), ''),
        '', null, null
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

  -- 12) 신청서/제출 상태 및 retention owner 갱신
  update public.center_applications
    set linked_center_id = v_center_id, status = 'done'
    where id = v_app.id;

  update public.onboarding_submissions
    set center_id = v_center_id
    where application_id = v_app.id;

  update public.onboarding_submissions
    set status = 'confirmed'
    where id = v_sub.id;

  return jsonb_build_object(
    'center_id', v_center_id,
    'slug', v_slug,
    'template', p_template
  );
end;
$function$;

create or replace function public.get_onboarding_form(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
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
    and application_id is not null
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
$function$;

create or replace function public.submit_onboarding_form(p_token text, p_answers jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_sub record;
begin
  if p_token is null or length(trim(p_token)) = 0 then
    raise exception '유효하지 않은 링크입니다';
  end if;

  select * into v_sub
  from public.onboarding_submissions
  where token = p_token
    and application_id is not null;

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
$function$;

-- CREATE OR REPLACE preserves existing ACLs. Reassert only the final explicit
-- create-center contract from migrations 056 and 063.
revoke execute on function public.create_center_from_onboarding(uuid, text, text)
  from public, anon;
grant execute on function public.create_center_from_onboarding(uuid, text, text)
  to authenticated;

commit;
