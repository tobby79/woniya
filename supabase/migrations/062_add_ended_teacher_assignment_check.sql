begin;

create or replace function public.has_ended_class_teacher_assignment(
  p_class_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    auth.uid() is not null
    and exists (
      select 1
      from public.class_teacher_assignments as cta
      where cta.class_id = p_class_id
        and cta.teacher_user_id = auth.uid()
        and cta.ended_at is not null
    );
$$;

revoke all on function public.has_ended_class_teacher_assignment(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.has_ended_class_teacher_assignment(uuid)
  to authenticated;

commit;
