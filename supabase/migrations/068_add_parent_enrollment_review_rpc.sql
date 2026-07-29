begin;

-- Compatibility step: add the director-only review RPC before admin.html
-- switches away from direct class_enrollments updates.
create or replace function public.review_parent_enrollment(
  p_enrollment_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_caller_id uuid := auth.uid();
  v_class_id uuid;
  v_current_status text;
  v_result_id uuid;
  v_result_class_id uuid;
  v_result_status text;
begin
  if v_caller_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_enrollment_id is null then
    raise exception 'enrollment_id_required';
  end if;

  if p_status is null or p_status not in ('approved', 'rejected') then
    raise exception 'invalid_enrollment_status';
  end if;

  select ce.class_id, ce.status
    into v_class_id, v_current_status
  from public.class_enrollments as ce
  where ce.id = p_enrollment_id
  for update;

  if not found then
    raise exception 'enrollment_not_found';
  end if;

  if not coalesce(public.is_class_owner(v_class_id), false) then
    raise exception 'class_access_denied';
  end if;

  if v_current_status <> 'pending' then
    raise exception 'enrollment_not_pending';
  end if;

  update public.class_enrollments as ce
  set status = p_status,
      approved_at = now(),
      approved_by = v_caller_id
  where ce.id = p_enrollment_id
    and ce.status = 'pending'
  returning ce.id, ce.class_id, ce.status
    into v_result_id, v_result_class_id, v_result_status;

  if not found then
    raise exception 'enrollment_not_pending';
  end if;

  return jsonb_build_object(
    'enrollment_id', v_result_id,
    'class_id', v_result_class_id,
    'status', v_result_status
  );
end;
$$;

revoke execute on function public.review_parent_enrollment(uuid, text)
  from public, anon;
grant execute on function public.review_parent_enrollment(uuid, text)
  to authenticated;

commit;
