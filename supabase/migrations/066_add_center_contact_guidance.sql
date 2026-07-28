begin;

alter table public.centers
  add column if not exists contact_note text;

comment on column public.centers.contact_note is
  'Public guidance for contacting the center representative. Not an applicant phone number, requested consultation time, or private inquiry.';

alter table public.template_centers
  add column if not exists contact_phone text,
  add column if not exists contact_note text;

comment on column public.template_centers.contact_phone is
  'Public representative phone number shown in template previews. Not an applicant personal phone number.';

comment on column public.template_centers.contact_note is
  'Public contact guidance shown in template previews. Not a requested consultation time or private applicant inquiry.';

commit;
