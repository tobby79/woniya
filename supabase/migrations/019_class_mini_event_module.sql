-- ===== 019_class_mini_event_module.sql =====

alter table public.class_mini
  alter column modules_enabled
  set default '{"diary":true,"event":true,"album":true,"guestbook":true,"notice":true,"letters":true}'::jsonb;

update public.class_mini
   set modules_enabled = coalesce(modules_enabled, '{}'::jsonb) || '{"event":true}'::jsonb
 where not (coalesce(modules_enabled, '{}'::jsonb) ? 'event');

-- ===== end =====
