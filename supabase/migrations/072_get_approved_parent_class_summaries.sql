begin;

-- Return only the minimal class summary fields needed by an approved parent.
-- This RPC intentionally leaves the existing classes and class_enrollments RLS
-- policies unchanged.
create or replace function public.get_my_approved_class_summaries()
returns table (
  id uuid,
  name text,
  age_label text,
  enrolled integer
)
language sql
security definer
stable
set search_path = public, auth
as $$
  select
    c.id,
    c.name,
    c.age_label,
    c.enrolled
  from public.class_enrollments as ce
  join public.classes as c
    on c.id = ce.class_id
  where auth.uid() is not null
    and ce.parent_id = auth.uid()
    and ce.status = 'approved';
$$;

comment on function public.get_my_approved_class_summaries() is
  'Returns only id, name, age_label, and enrolled for classes linked to the current user by an approved parent enrollment.';

revoke execute on function public.get_my_approved_class_summaries()
  from public, anon, authenticated;
grant execute on function public.get_my_approved_class_summaries()
  to authenticated;

commit;
