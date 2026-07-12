-- Harden public consultation submissions without changing existing owner reads.
-- Existing data is validated before adding constraints; the migration aborts if any row is incompatible.

do $$
begin
  if exists (
    select 1
    from public.consultations
    where btrim(parent_name) = ''
       or char_length(parent_name) > 50
       or btrim(phone) = ''
       or char_length(btrim(phone)) < 7
       or char_length(phone) > 20
       or phone !~ '^[0-9[:space:]()+-]+$'
       or (wish_class is not null and char_length(wish_class) > 50)
       or (wish_time is not null and char_length(wish_time) > 100)
  ) then
    raise exception 'public.consultations has rows that violate the new public consultation constraints';
  end if;
end $$;

revoke insert on table public.consultations from public;
revoke insert on table public.consultations from anon;
revoke insert on table public.consultations from authenticated;

revoke insert (id, status, created_at) on table public.consultations from public;
revoke insert (id, status, created_at) on table public.consultations from anon;
revoke insert (id, status, created_at) on table public.consultations from authenticated;

revoke trigger on table public.consultations from public;
revoke trigger on table public.consultations from anon;
revoke trigger on table public.consultations from authenticated;

revoke references on table public.consultations from public;
revoke references on table public.consultations from anon;
revoke references on table public.consultations from authenticated;

grant insert (
  center_id,
  parent_name,
  phone,
  kind,
  wish_class,
  wish_time,
  consent_at
) on table public.consultations to anon, authenticated;

alter table public.consultations
  add constraint consultations_parent_name_public_input_check
    check (char_length(btrim(parent_name)) >= 1 and char_length(parent_name) <= 50),
  add constraint consultations_phone_public_input_check
    check (
      char_length(btrim(phone)) >= 7
      and char_length(phone) <= 20
      and phone ~ '^[0-9[:space:]()+-]+$'
    ),
  add constraint consultations_wish_class_public_input_check
    check (wish_class is null or char_length(wish_class) <= 50),
  add constraint consultations_wish_time_public_input_check
    check (wish_time is null or char_length(wish_time) <= 100);

drop policy if exists consultations_public_insert on public.consultations;
drop policy if exists "consultations_public_insert" on public.consultations;

create policy consultations_public_insert
  on public.consultations
  for insert
  to anon, authenticated
  with check (
    status = 'new'
    and center_id is not null
    and char_length(btrim(parent_name)) >= 1
    and char_length(btrim(phone)) >= 1
    and consent_at is not null
    and exists (
      select 1
      from public.centers c
      where c.id = consultations.center_id
        and c.status = 'published'
    )
  );
