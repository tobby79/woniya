-- Ensure teacher invite acceptance only succeeds when the class assignment succeeds.

create or replace function public.accept_teacher_invite() returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text;
  v_invite record;
  v_assigned_class_id uuid;
  v_accepted_count integer;
  v_linked_classes uuid[] := '{}';
begin
  select lower(trim(email))
    into v_email
  from auth.users
  where id = auth.uid();

  if v_email is null then
    raise exception 'Unable to confirm logged-in user email.';
  end if;

  for v_invite in
    select ti.*
    from public.teacher_invites as ti
    where lower(trim(ti.email)) = v_email
      and ti.status = 'pending'
    order by ti.invited_at, ti.id
    for update of ti
  loop
    v_assigned_class_id := null;
    v_accepted_count := 0;

    update public.classes
    set teacher_id = auth.uid()
    where id = v_invite.class_id
      and teacher_id is null
    returning id into v_assigned_class_id;

    if v_assigned_class_id is not null then
      update public.teacher_invites
      set status = 'accepted',
          accepted_at = now()
      where id = v_invite.id
        and status = 'pending';

      get diagnostics v_accepted_count = row_count;

      if v_accepted_count = 1 then
        v_linked_classes := array_append(v_linked_classes, v_assigned_class_id);
      else
        raise exception 'Teacher invite could not be marked accepted.';
      end if;
    end if;
  end loop;

  if coalesce(array_length(v_linked_classes, 1), 0) = 0 then
    raise exception 'No assignable pending teacher invite found.';
  end if;

  return jsonb_build_object('linked_classes', v_linked_classes);
end;
$$;

revoke execute on function public.accept_teacher_invite() from public;
revoke execute on function public.accept_teacher_invite() from anon;
grant execute on function public.accept_teacher_invite() to authenticated;
