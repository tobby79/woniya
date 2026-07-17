-- Keep minimal class creation aligned with the classes NOT NULL constraint.
alter table public.classes
  alter column capacity set default 0;
