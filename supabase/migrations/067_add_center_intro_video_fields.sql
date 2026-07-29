begin;

alter table public.centers
  add column if not exists intro_video_url text,
  add column if not exists intro_video_title text;

alter table public.template_centers
  add column if not exists intro_video_url text,
  add column if not exists intro_video_title text;

commit;
