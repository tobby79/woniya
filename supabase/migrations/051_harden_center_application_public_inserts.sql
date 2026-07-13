begin;

do $$
declare
  v_bad_count integer;
begin
  select count(*)
    into v_bad_count
  from public.center_applications
  where length(trim(center_name)) not between 1 and 120
     or length(trim(director_name)) not between 1 and 80
     or length(trim(phone)) not between 7 and 30
     or phone !~ '^[0-9[:space:]+().-]{7,30}$'
     or (region is not null and length(trim(region)) > 100)
     or (message is not null and length(trim(message)) > 2000);

  if v_bad_count > 0 then
    raise exception 'center_applications has % row(s) violating public input constraints', v_bad_count;
  end if;
end $$;

revoke insert on table public.center_applications from public, anon, authenticated;
revoke insert (
  id,
  center_name,
  director_name,
  phone,
  region,
  message,
  consent_at,
  status,
  created_at,
  updated_at,
  linked_center_id
) on table public.center_applications from public, anon, authenticated;

grant insert (
  center_name,
  director_name,
  phone,
  region,
  message
) on table public.center_applications to anon, authenticated;

alter table public.center_applications
  add constraint center_applications_center_name_input_check
  check (length(trim(center_name)) between 1 and 120);

alter table public.center_applications
  add constraint center_applications_director_name_input_check
  check (length(trim(director_name)) between 1 and 80);

alter table public.center_applications
  add constraint center_applications_phone_input_check
  check (
    length(trim(phone)) between 7 and 30
    and phone ~ '^[0-9[:space:]+().-]{7,30}$'
  );

alter table public.center_applications
  add constraint center_applications_region_input_check
  check (
    region is null
    or length(trim(region)) <= 100
  );

alter table public.center_applications
  add constraint center_applications_message_input_check
  check (
    message is null
    or length(trim(message)) <= 2000
  );

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
    and consent_at is not null
    and status = 'new'
    and linked_center_id is null
  );

commit;
