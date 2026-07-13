begin;

alter table public.center_applications
  alter column consent_at set default now();

drop policy if exists center_applications_public_insert on public.center_applications;

create policy center_applications_public_insert
  on public.center_applications
  for insert
  to anon, authenticated
  with check (
    length(trim(center_name)) between 1 and 120
    and length(trim(director_name)) between 1 and 80
    and length(trim(phone)) between 7 and 30
    and phone ~ '^[0-9[:space:]+().-]{7,30}$'
    and (
      region is null
      or length(trim(region)) <= 100
    )
    and (
      message is null
      or length(trim(message)) <= 2000
    )
  );

commit;
