begin;

alter table public.class_mini
  add column if not exists teacher_intro text;

comment on column public.class_mini.teacher_intro is
  'Per-class static teacher profile introduction displayed on the class mini homepage landing screen; not a temporary daily message.';

commit;
