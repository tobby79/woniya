begin;

alter table public.center_applications
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid,
  add column if not exists archive_reason text;

alter table public.center_applications
  drop constraint if exists center_applications_archive_reason_check;

alter table public.center_applications
  add constraint center_applications_archive_reason_check
  check (
    archive_reason is null
    or char_length(archive_reason) <= 300
  );

create index if not exists center_applications_archived_at_idx
  on public.center_applications (archived_at)
  where archived_at is not null;

commit;
