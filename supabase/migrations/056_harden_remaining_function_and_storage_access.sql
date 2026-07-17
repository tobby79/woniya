-- 056: Harden remaining function execution and template preview listing access

-- Fix mutable search_path warning on the shared trigger function.
alter function public.set_updated_at()
  set search_path = public, pg_temp;

-- Remove default PUBLIC/anon EXECUTE from authenticated-only functions.
revoke execute on function public.get_center_preview(text)
  from public, anon;

revoke execute on function public.create_center_from_onboarding(uuid, text, text)
  from public, anon;

revoke execute on function public.accept_center_owner_invite()
  from public, anon;

-- Keep the template-previews bucket public for getPublicUrl(),
-- but remove anonymous object listing through storage.objects.
drop policy if exists "template_previews_public_select"
  on storage.objects;
