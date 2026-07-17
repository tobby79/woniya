-- ===== 054_connect_center_owner_by_email.sql =====
--
-- Purpose:
--   Allow the platform administrator to connect an existing signed-up auth user
--   to a center as its owner, without exposing service_role credentials in the
--   frontend and without reading auth.users from the client.
--
-- Usage:
--   select public.connect_center_owner_by_email(
--     '00000000-0000-0000-0000-000000000000'::uuid,
--     'owner@example.com'
--   );

create or replace function public.connect_center_owner_by_email(
  p_center_id uuid,
  p_email text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_email text;
  v_email text;
  v_center_id uuid;
  v_owner_id uuid;
  v_owner_email text;
begin
  v_admin_email := auth.email();
  if v_admin_email is null or lower(v_admin_email) <> 'tobby79@naver.com' then
    raise exception 'platform admin only';
  end if;

  if p_center_id is null then
    raise exception 'center_id is required';
  end if;

  v_email := lower(trim(coalesce(p_email, '')));
  if v_email = '' then
    raise exception 'owner email is required';
  end if;

  select c.id
    into v_center_id
    from public.centers c
    where c.id = p_center_id;

  if v_center_id is null then
    raise exception 'center not found';
  end if;

  select u.id, u.email
    into v_owner_id, v_owner_email
    from auth.users u
    where lower(u.email) = v_email
    order by u.created_at desc
    limit 1;

  if v_owner_id is null then
    raise exception 'owner account not found';
  end if;

  update public.centers
    set owner_id = v_owner_id
    where id = p_center_id;

  return jsonb_build_object(
    'center_id', p_center_id,
    'owner_id', v_owner_id,
    'owner_email', v_owner_email
  );
end;
$$;

revoke all on function public.connect_center_owner_by_email(uuid, text) from public;
revoke all on function public.connect_center_owner_by_email(uuid, text) from anon;
grant execute on function public.connect_center_owner_by_email(uuid, text) to authenticated;

-- ===== end =====
