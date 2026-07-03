-- Harden SECURITY DEFINER functions flagged by Supabase Security Advisor.
-- Keep authenticated RPC access for existing app flows while removing public/anon execute.

alter function public.is_class_teacher(uuid)
  set search_path = public, auth;
alter function public.is_class_owner(uuid)
  set search_path = public, auth;
alter function public.is_class_staff(uuid)
  set search_path = public, auth;
alter function public.is_approved_parent(uuid)
  set search_path = public, auth;
alter function public.redeem_class_invite(text)
  set search_path = public, auth;
alter function public.accept_teacher_invite()
  set search_path = public, auth;
alter function public.my_owned_center_ids()
  set search_path = public, auth;
alter function public.my_teaching_class_ids()
  set search_path = public, auth;

revoke execute on function public.is_class_teacher(uuid) from public;
revoke execute on function public.is_class_teacher(uuid) from anon;
grant execute on function public.is_class_teacher(uuid) to authenticated;

revoke execute on function public.is_class_owner(uuid) from public;
revoke execute on function public.is_class_owner(uuid) from anon;
grant execute on function public.is_class_owner(uuid) to authenticated;

revoke execute on function public.is_class_staff(uuid) from public;
revoke execute on function public.is_class_staff(uuid) from anon;
grant execute on function public.is_class_staff(uuid) to authenticated;

revoke execute on function public.is_approved_parent(uuid) from public;
revoke execute on function public.is_approved_parent(uuid) from anon;
grant execute on function public.is_approved_parent(uuid) to authenticated;

revoke execute on function public.redeem_class_invite(text) from public;
revoke execute on function public.redeem_class_invite(text) from anon;
grant execute on function public.redeem_class_invite(text) to authenticated;

revoke execute on function public.accept_teacher_invite() from public;
revoke execute on function public.accept_teacher_invite() from anon;
grant execute on function public.accept_teacher_invite() to authenticated;

revoke execute on function public.my_owned_center_ids() from public;
revoke execute on function public.my_owned_center_ids() from anon;
grant execute on function public.my_owned_center_ids() to authenticated;

revoke execute on function public.my_teaching_class_ids() from public;
revoke execute on function public.my_teaching_class_ids() from anon;
grant execute on function public.my_teaching_class_ids() to authenticated;
