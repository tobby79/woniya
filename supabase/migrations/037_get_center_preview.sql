-- ===== 037_get_center_preview.sql =====
--
-- 목적: 플랫폼 관리자(드림파파)가 draft 상태의 실제 원(centers)도 template 페이지에서
--       미리 볼 수 있도록 하는 RPC. centers_public_select RLS 는 status='published'
--       만 허용하므로, draft 원은 anon 조회 시 0행(406)이 난다 — 이는 의도된 차단이며,
--       관리자 전용 경로를 별도로 열어준다.
--
-- 패턴: create_center_from_onboarding(036)과 동일한 관리자 검증
--       (auth.email() = 'tobby79@naver.com', 아니면 예외) + SECURITY DEFINER.
--
-- 반환 형태: template-*.html 의 mapRowToData(row) 가 기대하는 그대로 —
--   centers 전체 컬럼 + center_media 배열 + admissions 배열을 하나의 jsonb 로 묶어
--   row.center_media / row.admissions 필드에 담는다. 기존 slug 조회
--   (.select('*, center_media(*), admissions(*), ...').eq('slug', slug).single())와
--   동일한 데이터 범위이므로 프론트는 받은 jsonb 를 그대로 mapRowToData 에 넘기면 된다.
--
-- anon 은 로그인 자체가 없어 호출이 의미 없으므로 EXECUTE 를 주지 않는다.
-- authenticated 에게만 EXECUTE 를 주고, 관리자가 아니면 함수 내부에서 예외로 차단한다.

create or replace function public.get_center_preview(p_slug text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_center record;
  v_media jsonb;
  v_admissions jsonb;
  v_row jsonb;
begin
  v_email := auth.email();
  if v_email is null or v_email <> 'tobby79@naver.com' then
    raise exception '플랫폼 관리자만 미리보기를 사용할 수 있습니다';
  end if;

  select * into v_center from public.centers where slug = p_slug;
  if not found then
    return null;
  end if;

  select coalesce(jsonb_agg(to_jsonb(cm) order by cm.sort_order), '[]'::jsonb)
    into v_media
    from public.center_media cm
    where cm.center_id = v_center.id;

  select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb)
    into v_admissions
    from public.admissions a
    where a.center_id = v_center.id;

  v_row := to_jsonb(v_center) || jsonb_build_object(
    'center_media', v_media,
    'admissions', v_admissions
  );

  return v_row;
end;
$$;

grant execute on function public.get_center_preview(text) to authenticated;

-- ===== 끝 =====
