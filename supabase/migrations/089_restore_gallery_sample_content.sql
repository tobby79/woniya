begin;

-- Restore the public gallery sample sections without replacing content that may
-- already have been populated. Facility/program images intentionally continue
-- to use template-gallery.html's existing gallery album fallback.
do $migration$
declare
  v_target_count integer;
begin
  select count(*)
    into v_target_count
  from public.template_centers
  where id = '8a2419f1-8c4d-4557-a8f2-e5b6fa1a0d57'::uuid
    and template_id = 'gallery'
    and slug = 'gallery';

  if v_target_count <> 1 then
    raise exception
      'Expected exactly one gallery sample row (id %, template_id gallery, slug gallery); found %',
      '8a2419f1-8c4d-4557-a8f2-e5b6fa1a0d57',
      v_target_count;
  end if;

  update public.template_centers
  set
    facilities = case
      when facilities is null or facilities = '{}'::jsonb then $gallery_facilities$
        {
          "intro": "아이들이 편안하게 머물고 자유롭게 놀이할 수 있도록 공간을 구성했습니다.",
          "items": [
            {
              "name": "놀이방",
              "desc": "블록과 역할놀이로 상상력이 자라는 우리 반의 공간입니다."
            },
            {
              "name": "바깥 놀이터",
              "desc": "안전한 모래밭과 미끄럼틀에서 마음껏 뛰노는 시간."
            },
            {
              "name": "그림책 도서관",
              "desc": "포근한 쿠션에 앉아 선생님과 그림책을 읽습니다."
            },
            {
              "name": "급식실",
              "desc": "영양 가득한 식단을 친구들과 함께 나눕니다."
            }
          ]
        }
      $gallery_facilities$::jsonb
      else facilities
    end,
    programs = case
      when programs is null or programs = '{}'::jsonb then $gallery_programs$
        {
          "intro": "다양한 예술 활동을 통해 아이들이 자신의 생각과 감정을 자연스럽게 표현하도록 돕습니다.",
          "items": [
            {
              "name": "그림 표현",
              "desc": "다양한 재료와 색을 탐색하며 생각과 느낌을 자유롭게 표현합니다."
            },
            {
              "name": "입체 만들기",
              "desc": "점토와 종이 등 여러 재료를 활용해 손끝의 감각과 상상력을 키웁니다."
            },
            {
              "name": "음악과 움직임",
              "desc": "노래와 악기, 신체 표현을 통해 리듬과 움직임을 즐깁니다."
            },
            {
              "name": "함께하는 전시",
              "desc": "친구들의 작품을 감상하고 서로의 생각을 나누는 경험을 합니다."
            }
          ]
        }
      $gallery_programs$::jsonb
      else programs
    end,
    faqs = case
      when faqs is null or faqs = '{}'::jsonb then $gallery_faqs$
        {
          "eyebrow": "FAQ",
          "title": "자주 묻는 질문",
          "items": [
            {
              "q": "입학 상담은 어떻게 신청하나요?",
              "a": "홈페이지의 입소 상담을 통해 연락처와 희망 내용을 남겨주시면 확인 후 안내드립니다."
            },
            {
              "q": "모집 시기는 언제인가요?",
              "a": "모집 일정은 원의 운영 상황과 연령별 정원에 따라 달라질 수 있어 상담 시 안내드립니다."
            },
            {
              "q": "입학 상담 시 어떤 서류가 필요한가요?",
              "a": "상담 단계에서는 기본 정보를 확인하며, 등록에 필요한 서류는 절차에 따라 별도로 안내드립니다."
            },
            {
              "q": "운영 시간은 어떻게 확인하나요?",
              "a": "운영 시간과 등·하원 관련 사항은 원으로 문의하시면 현재 기준으로 안내받을 수 있습니다."
            },
            {
              "q": "급식과 하루 생활은 어떻게 운영되나요?",
              "a": "연령과 일과에 맞춰 생활하며, 급식과 세부 일정은 상담 또는 방문 시 안내드립니다."
            },
            {
              "q": "방문 상담도 가능한가요?",
              "a": "방문 상담은 사전 일정 확인 후 가능하며, 입소 상담을 통해 희망 시간을 남겨주세요."
            }
          ]
        }
      $gallery_faqs$::jsonb
      else faqs
    end,
    finale = case
      when finale is null or finale = '{}'::jsonb then $gallery_finale$
        {
          "title": "아이의 하루를 함께 바라봅니다",
          "subtitle": "궁금한 점은 입소 상담을 통해 편하게 문의해 주세요.",
          "cta": "입소 상담"
        }
      $gallery_finale$::jsonb
      else finale
    end
  where id = '8a2419f1-8c4d-4557-a8f2-e5b6fa1a0d57'::uuid
    and template_id = 'gallery'
    and slug = 'gallery'
    and (
      facilities is null or facilities = '{}'::jsonb
      or programs is null or programs = '{}'::jsonb
      or faqs is null or faqs = '{}'::jsonb
      or finale is null or finale = '{}'::jsonb
    );

  if exists (
    select 1
    from public.template_centers
    where id = '8a2419f1-8c4d-4557-a8f2-e5b6fa1a0d57'::uuid
      and template_id = 'gallery'
      and slug = 'gallery'
      and (
        coalesce(jsonb_typeof(facilities), '') <> 'object'
        or coalesce(jsonb_typeof(facilities -> 'items'), '') <> 'array'
        or coalesce(jsonb_typeof(programs), '') <> 'object'
        or coalesce(jsonb_typeof(programs -> 'items'), '') <> 'array'
        or coalesce(jsonb_typeof(faqs), '') <> 'object'
        or coalesce(jsonb_typeof(faqs -> 'items'), '') <> 'array'
        or coalesce(jsonb_typeof(finale), '') <> 'object'
        or nullif(btrim(finale ->> 'cta'), '') is null
      )
  ) then
    raise exception 'Gallery sample content does not match the template renderer contract';
  end if;

  if exists (
    select 1
    from public.template_centers
    where id = '8a2419f1-8c4d-4557-a8f2-e5b6fa1a0d57'::uuid
      and template_id = 'gallery'
      and slug = 'gallery'
      and (
        jsonb_array_length(facilities -> 'items') = 0
        or jsonb_array_length(programs -> 'items') = 0
        or jsonb_array_length(faqs -> 'items') not between 4 and 6
      )
  ) then
    raise exception 'Gallery sample facilities, programs, or FAQs are empty or outside the expected range';
  end if;
end;
$migration$;

commit;
