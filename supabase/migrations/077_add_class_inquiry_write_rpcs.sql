begin;

create or replace function public.create_class_inquiry(
  p_class_id uuid,
  p_category text,
  p_subject text,
  p_body text,
  p_request_key uuid
)
returns table (
  inquiry_id uuid,
  document_no text,
  status text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_category text := lower(btrim(p_category));
  v_subject text := btrim(p_subject);
  v_body text := btrim(p_body);
  v_center_id uuid;
  v_document_date date;
  v_daily_sequence integer;
  v_document_no text;
  v_inquiry_id uuid;
  v_existing_inquiry public.class_inquiries%rowtype;
  v_existing_body text;
begin
  if v_user_id is null then
    raise exception using message = 'not_authenticated';
  end if;

  if p_class_id is null
     or p_request_key is null
     or v_category is null
     or v_category not in ('general', 'attendance', 'health', 'schedule', 'supplies', 'other')
     or v_subject is null
     or char_length(v_subject) not between 1 and 120
     or v_body is null
     or char_length(v_body) not between 1 and 5000 then
    raise exception using message = 'invalid_input';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_request_key::text, 0)
  );

  select ci.*
    into v_existing_inquiry
  from public.class_inquiries as ci
  where ci.create_request_key = p_request_key;

  if v_existing_inquiry.id is not null then
    select cim.body
      into v_existing_body
    from public.class_inquiry_messages as cim
    where cim.inquiry_id = v_existing_inquiry.id
      and cim.request_key = p_request_key
      and cim.sender_id = v_user_id
      and cim.sender_role = 'parent'
      and cim.message_type = 'message'
      and cim.status_from is null
      and cim.status_to is null;

    if v_existing_inquiry.author_id is distinct from v_user_id
       or v_existing_inquiry.class_id is distinct from p_class_id
       or v_existing_inquiry.category is distinct from v_category
       or v_existing_inquiry.subject is distinct from v_subject
       or v_existing_body is distinct from v_body then
      raise exception using message = 'request_key_conflict';
    end if;

    inquiry_id := v_existing_inquiry.id;
    document_no := v_existing_inquiry.document_no;
    status := v_existing_inquiry.status;
    created_at := v_existing_inquiry.created_at;
    return next;
    return;
  end if;

  if exists (
    select 1
    from public.class_inquiry_messages as cim
    where cim.request_key = p_request_key
  ) then
    raise exception using message = 'request_key_conflict';
  end if;

  select c.center_id
    into v_center_id
  from public.classes as c
  where c.id = p_class_id
  for share of c;

  if v_center_id is null then
    raise exception using message = 'class_access_denied';
  end if;

  if not coalesce(public.is_approved_parent(p_class_id), false) then
    raise exception using message = 'parent_not_approved';
  end if;

  perform ce.id
  from public.class_enrollments as ce
  where ce.class_id = p_class_id
    and ce.parent_id = v_user_id
    and ce.status = 'approved'
  for share of ce;

  if not found then
    raise exception using message = 'parent_not_approved';
  end if;

  v_document_date := (v_now at time zone 'Asia/Seoul')::date;

  insert into public.class_inquiry_daily_counters as cidc (
    center_id,
    document_date,
    last_value,
    updated_at
  )
  values (
    v_center_id,
    v_document_date,
    1,
    v_now
  )
  on conflict (center_id, document_date) do update
    set last_value = cidc.last_value + 1,
        updated_at = v_now
    where cidc.last_value < 9999
  returning last_value into v_daily_sequence;

  if v_daily_sequence is null or v_daily_sequence > 9999 then
    raise exception using message = 'daily_sequence_exhausted';
  end if;

  v_document_no := 'INQ-'
    || upper(substr(replace(v_center_id::text, '-', ''), 1, 8))
    || '-'
    || to_char(v_document_date, 'YYMMDD')
    || '-'
    || lpad(v_daily_sequence::text, 4, '0');

  insert into public.class_inquiries (
    class_id,
    center_id,
    author_id,
    create_request_key,
    document_date,
    daily_sequence,
    document_no,
    category,
    subject,
    status,
    created_at,
    updated_at,
    last_message_at,
    last_parent_message_at,
    last_staff_message_at,
    parent_last_read_at,
    staff_last_read_at,
    answered_at,
    closed_at,
    closed_by_id,
    closed_by_role
  )
  values (
    p_class_id,
    v_center_id,
    v_user_id,
    p_request_key,
    v_document_date,
    v_daily_sequence,
    v_document_no,
    v_category,
    v_subject,
    'received',
    v_now,
    v_now,
    v_now,
    v_now,
    null,
    v_now,
    null,
    null,
    null,
    null,
    null
  )
  returning id into v_inquiry_id;

  insert into public.class_inquiry_messages (
    inquiry_id,
    sender_id,
    sender_role,
    message_type,
    body,
    status_from,
    status_to,
    request_key,
    created_at
  )
  values (
    v_inquiry_id,
    v_user_id,
    'parent',
    'message',
    v_body,
    null,
    null,
    p_request_key,
    v_now
  );

  inquiry_id := v_inquiry_id;
  document_no := v_document_no;
  status := 'received';
  created_at := v_now;
  return next;
end;
$$;

comment on function public.create_class_inquiry(uuid, text, text, text, uuid) is
  'Creates an approved parent inquiry, allocates its per-center Seoul-date document number, and stores the first append-only message atomically.';

create or replace function public.add_parent_class_inquiry_message(
  p_inquiry_id uuid,
  p_body text,
  p_request_key uuid
)
returns table (
  message_id uuid,
  inquiry_id uuid,
  status text,
  message_created_at timestamptz,
  last_message_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_body text := btrim(p_body);
  v_inquiry public.class_inquiries%rowtype;
  v_existing_message public.class_inquiry_messages%rowtype;
  v_message_id uuid;
  v_status_from text;
  v_status_to text;
  v_next_status text;
begin
  if v_user_id is null then
    raise exception using message = 'not_authenticated';
  end if;

  if p_inquiry_id is null
     or p_request_key is null
     or v_body is null
     or char_length(v_body) not between 1 and 5000 then
    raise exception using message = 'invalid_input';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_request_key::text, 0)
  );

  if exists (
    select 1
    from public.class_inquiries as ci
    where ci.create_request_key = p_request_key
  ) then
    raise exception using message = 'request_key_conflict';
  end if;

  select cim.*
    into v_existing_message
  from public.class_inquiry_messages as cim
  where cim.request_key = p_request_key;

  if v_existing_message.id is not null then
    if v_existing_message.inquiry_id is distinct from p_inquiry_id
       or v_existing_message.sender_id is distinct from v_user_id
       or v_existing_message.sender_role <> 'parent'
       or v_existing_message.message_type <> 'message'
       or v_existing_message.body is distinct from v_body then
      raise exception using message = 'request_key_conflict';
    end if;

    select ci.*
      into v_inquiry
    from public.class_inquiries as ci
    where ci.id = p_inquiry_id;

    if v_inquiry.id is null
       or v_inquiry.author_id is distinct from v_user_id then
      raise exception using message = 'request_key_conflict';
    end if;

    message_id := v_existing_message.id;
    inquiry_id := v_existing_message.inquiry_id;
    status := v_inquiry.status;
    message_created_at := v_existing_message.created_at;
    last_message_at := v_inquiry.last_message_at;
    return next;
    return;
  end if;

  select ci.*
    into v_inquiry
  from public.class_inquiries as ci
  where ci.id = p_inquiry_id
  for update of ci;

  if v_inquiry.id is null
     or v_inquiry.author_id is distinct from v_user_id then
    raise exception using message = 'inquiry_not_found_or_denied';
  end if;

  if not coalesce(public.is_approved_parent(v_inquiry.class_id), false) then
    raise exception using message = 'parent_not_approved';
  end if;

  perform ce.id
  from public.class_enrollments as ce
  where ce.class_id = v_inquiry.class_id
    and ce.parent_id = v_user_id
    and ce.status = 'approved'
  for share of ce;

  if not found then
    raise exception using message = 'parent_not_approved';
  end if;

  if v_inquiry.status = 'closed' then
    raise exception using message = 'inquiry_closed';
  end if;

  if v_inquiry.status = 'answered' then
    v_status_from := 'answered';
    v_status_to := 'in_progress';
    v_next_status := 'in_progress';
  elsif v_inquiry.status in ('received', 'in_progress') then
    v_status_from := null;
    v_status_to := null;
    v_next_status := v_inquiry.status;
  else
    raise exception using message = 'invalid_status_transition';
  end if;

  insert into public.class_inquiry_messages (
    inquiry_id,
    sender_id,
    sender_role,
    message_type,
    body,
    status_from,
    status_to,
    request_key,
    created_at
  )
  values (
    v_inquiry.id,
    v_user_id,
    'parent',
    'message',
    v_body,
    v_status_from,
    v_status_to,
    p_request_key,
    v_now
  )
  returning id into v_message_id;

  update public.class_inquiries as ci
  set status = v_next_status,
      last_parent_message_at = v_now,
      last_message_at = v_now,
      updated_at = v_now,
      parent_last_read_at = v_now
  where ci.id = v_inquiry.id;

  message_id := v_message_id;
  inquiry_id := v_inquiry.id;
  status := v_next_status;
  message_created_at := v_now;
  last_message_at := v_now;
  return next;
end;
$$;

comment on function public.add_parent_class_inquiry_message(uuid, text, uuid) is
  'Appends a currently approved parent follow-up and reopens an answered inquiry to in_progress without changing answered_at.';

create or replace function public.reply_to_class_inquiry(
  p_inquiry_id uuid,
  p_body text,
  p_request_key uuid
)
returns table (
  message_id uuid,
  inquiry_id uuid,
  status text,
  message_created_at timestamptz,
  last_message_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_body text := btrim(p_body);
  v_inquiry public.class_inquiries%rowtype;
  v_existing_message public.class_inquiry_messages%rowtype;
  v_message_id uuid;
  v_sender_role text;
  v_status_from text;
  v_status_to text;
begin
  if v_user_id is null then
    raise exception using message = 'not_authenticated';
  end if;

  if p_inquiry_id is null
     or p_request_key is null
     or v_body is null
     or char_length(v_body) not between 1 and 5000 then
    raise exception using message = 'invalid_input';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_request_key::text, 0)
  );

  select ci.*
    into v_inquiry
  from public.class_inquiries as ci
  where ci.id = p_inquiry_id
  for update of ci;

  if v_inquiry.id is null
     or v_inquiry.author_id is not distinct from v_user_id
     or not coalesce(public.is_class_staff(v_inquiry.class_id), false) then
    raise exception using message = 'inquiry_not_found_or_denied';
  end if;

  if coalesce(public.is_class_owner(v_inquiry.class_id), false) then
    v_sender_role := 'owner';
  else
    v_sender_role := 'teacher';
  end if;

  if exists (
    select 1
    from public.class_inquiries as ci
    where ci.create_request_key = p_request_key
  ) then
    raise exception using message = 'request_key_conflict';
  end if;

  select cim.*
    into v_existing_message
  from public.class_inquiry_messages as cim
  where cim.request_key = p_request_key;

  if v_existing_message.id is not null then
    if v_existing_message.inquiry_id is distinct from p_inquiry_id
       or v_existing_message.sender_id is distinct from v_user_id
       or v_existing_message.sender_role not in ('teacher', 'owner')
       or v_existing_message.message_type <> 'message'
       or v_existing_message.body is distinct from v_body then
      raise exception using message = 'request_key_conflict';
    end if;

    message_id := v_existing_message.id;
    inquiry_id := v_existing_message.inquiry_id;
    status := v_inquiry.status;
    message_created_at := v_existing_message.created_at;
    last_message_at := v_inquiry.last_message_at;
    return next;
    return;
  end if;

  if v_inquiry.status = 'closed' then
    raise exception using message = 'inquiry_closed';
  end if;

  if v_inquiry.status in ('received', 'in_progress') then
    v_status_from := v_inquiry.status;
    v_status_to := 'answered';
  elsif v_inquiry.status = 'answered' then
    v_status_from := null;
    v_status_to := null;
  else
    raise exception using message = 'invalid_status_transition';
  end if;

  insert into public.class_inquiry_messages (
    inquiry_id,
    sender_id,
    sender_role,
    message_type,
    body,
    status_from,
    status_to,
    request_key,
    created_at
  )
  values (
    v_inquiry.id,
    v_user_id,
    v_sender_role,
    'message',
    v_body,
    v_status_from,
    v_status_to,
    p_request_key,
    v_now
  )
  returning id into v_message_id;

  update public.class_inquiries as ci
  set status = 'answered',
      last_staff_message_at = v_now,
      answered_at = v_now,
      last_message_at = v_now,
      updated_at = v_now,
      staff_last_read_at = v_now
  where ci.id = v_inquiry.id;

  message_id := v_message_id;
  inquiry_id := v_inquiry.id;
  status := 'answered';
  message_created_at := v_now;
  last_message_at := v_now;
  return next;
end;
$$;

comment on function public.reply_to_class_inquiry(uuid, text, uuid) is
  'Appends a current teacher or owner reply, records the server-derived staff role, marks shared staff read state, and sets the inquiry to answered. The original author is treated as parent and cannot reply as staff to that inquiry.';

create or replace function public.start_class_inquiry_review(
  p_inquiry_id uuid
)
returns table (
  inquiry_id uuid,
  status text,
  updated_at timestamptz,
  changed boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_inquiry public.class_inquiries%rowtype;
  v_sender_role text;
begin
  if v_user_id is null then
    raise exception using message = 'not_authenticated';
  end if;

  if p_inquiry_id is null then
    raise exception using message = 'invalid_input';
  end if;

  select ci.*
    into v_inquiry
  from public.class_inquiries as ci
  where ci.id = p_inquiry_id
  for update of ci;

  if v_inquiry.id is null
     or v_inquiry.author_id is not distinct from v_user_id
     or not coalesce(public.is_class_staff(v_inquiry.class_id), false) then
    raise exception using message = 'inquiry_not_found_or_denied';
  end if;

  if coalesce(public.is_class_owner(v_inquiry.class_id), false) then
    v_sender_role := 'owner';
  else
    v_sender_role := 'teacher';
  end if;

  if v_inquiry.status = 'closed' then
    raise exception using message = 'inquiry_closed';
  end if;

  if v_inquiry.status in ('in_progress', 'answered') then
    inquiry_id := v_inquiry.id;
    status := v_inquiry.status;
    updated_at := v_inquiry.updated_at;
    changed := false;
    return next;
    return;
  end if;

  if v_inquiry.status <> 'received' then
    raise exception using message = 'invalid_status_transition';
  end if;

  update public.class_inquiries as ci
  set status = 'in_progress',
      updated_at = v_now,
      last_message_at = v_now
  where ci.id = v_inquiry.id;

  insert into public.class_inquiry_messages (
    inquiry_id,
    sender_id,
    sender_role,
    message_type,
    body,
    status_from,
    status_to,
    request_key,
    created_at
  )
  values (
    v_inquiry.id,
    v_user_id,
    v_sender_role,
    'status_change',
    '문의 확인을 시작했습니다.',
    'received',
    'in_progress',
    gen_random_uuid(),
    v_now
  );

  inquiry_id := v_inquiry.id;
  status := 'in_progress';
  updated_at := v_now;
  changed := true;
  return next;
end;
$$;

comment on function public.start_class_inquiry_review(uuid) is
  'Idempotently starts review by current class staff based on inquiry state without accepting a client request key, appending one server-keyed status-change record only for received inquiries. The original author is treated as parent and cannot start staff review for that inquiry.';

create or replace function public.close_class_inquiry(
  p_inquiry_id uuid,
  p_request_key uuid
)
returns table (
  inquiry_id uuid,
  status text,
  closed_at timestamptz,
  closed_by_role text
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_inquiry public.class_inquiries%rowtype;
  v_existing_message public.class_inquiry_messages%rowtype;
  v_actor_role text;
  v_previous_status text;
begin
  if v_user_id is null then
    raise exception using message = 'not_authenticated';
  end if;

  if p_inquiry_id is null or p_request_key is null then
    raise exception using message = 'invalid_input';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_request_key::text, 0)
  );

  select ci.*
    into v_inquiry
  from public.class_inquiries as ci
  where ci.id = p_inquiry_id
  for update of ci;

  if v_inquiry.id is null then
    raise exception using message = 'inquiry_not_found_or_denied';
  end if;

  if v_inquiry.author_id is not distinct from v_user_id then
    v_actor_role := 'parent';
  elsif coalesce(public.is_class_staff(v_inquiry.class_id), false) then
    if coalesce(public.is_class_owner(v_inquiry.class_id), false) then
      v_actor_role := 'owner';
    else
      v_actor_role := 'teacher';
    end if;
  else
    raise exception using message = 'inquiry_not_found_or_denied';
  end if;

  if exists (
    select 1
    from public.class_inquiries as ci
    where ci.create_request_key = p_request_key
  ) then
    raise exception using message = 'request_key_conflict';
  end if;

  select cim.*
    into v_existing_message
  from public.class_inquiry_messages as cim
  where cim.request_key = p_request_key;

  if v_existing_message.id is not null then
    if v_existing_message.inquiry_id is distinct from p_inquiry_id
       or v_existing_message.sender_id is distinct from v_user_id
       or v_existing_message.message_type <> 'status_change'
       or v_existing_message.body <> '문의가 종료되었습니다.'
       or v_existing_message.status_to <> 'closed' then
      raise exception using message = 'request_key_conflict';
    end if;

    if v_inquiry.status <> 'closed' then
      raise exception using message = 'request_key_conflict';
    end if;

    inquiry_id := v_inquiry.id;
    status := v_inquiry.status;
    closed_at := v_inquiry.closed_at;
    closed_by_role := v_inquiry.closed_by_role;
    return next;
    return;
  end if;

  if v_inquiry.status = 'closed' then
    raise exception using message = 'inquiry_closed';
  end if;

  if v_inquiry.status not in ('received', 'in_progress', 'answered') then
    raise exception using message = 'invalid_status_transition';
  end if;

  v_previous_status := v_inquiry.status;

  update public.class_inquiries as ci
  set status = 'closed',
      closed_at = v_now,
      closed_by_id = v_user_id,
      closed_by_role = v_actor_role,
      updated_at = v_now,
      last_message_at = v_now
  where ci.id = v_inquiry.id;

  insert into public.class_inquiry_messages (
    inquiry_id,
    sender_id,
    sender_role,
    message_type,
    body,
    status_from,
    status_to,
    request_key,
    created_at
  )
  values (
    v_inquiry.id,
    v_user_id,
    v_actor_role,
    'status_change',
    '문의가 종료되었습니다.',
    v_previous_status,
    'closed',
    p_request_key,
    v_now
  );

  inquiry_id := v_inquiry.id;
  status := 'closed';
  closed_at := v_now;
  closed_by_role := v_actor_role;
  return next;
end;
$$;

comment on function public.close_class_inquiry(uuid, uuid) is
  'Lets the original parent or current class staff close an open inquiry once and append the corresponding status-change record.';

create or replace function public.mark_class_inquiry_parent_read(
  p_inquiry_id uuid
)
returns table (
  inquiry_id uuid,
  parent_last_read_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
begin
  if v_user_id is null then
    raise exception using message = 'not_authenticated';
  end if;

  if p_inquiry_id is null then
    raise exception using message = 'invalid_input';
  end if;

  update public.class_inquiries as ci
  set parent_last_read_at = greatest(ci.parent_last_read_at, v_now)
  where ci.id = p_inquiry_id
    and ci.author_id = v_user_id
  returning ci.id, ci.parent_last_read_at
    into inquiry_id, parent_last_read_at;

  if inquiry_id is null then
    raise exception using message = 'inquiry_not_found_or_denied';
  end if;

  return next;
end;
$$;

comment on function public.mark_class_inquiry_parent_read(uuid) is
  'Monotonically advances the original parent author read timestamp without requiring current enrollment approval or changing activity timestamps.';

create or replace function public.mark_class_inquiry_staff_read(
  p_inquiry_id uuid
)
returns table (
  inquiry_id uuid,
  staff_last_read_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
begin
  if v_user_id is null then
    raise exception using message = 'not_authenticated';
  end if;

  if p_inquiry_id is null then
    raise exception using message = 'invalid_input';
  end if;

  update public.class_inquiries as ci
  set staff_last_read_at = greatest(
    coalesce(ci.staff_last_read_at, ci.created_at),
    v_now
  )
  where ci.id = p_inquiry_id
    and ci.author_id is distinct from v_user_id
    and coalesce(public.is_class_staff(ci.class_id), false)
  returning ci.id, ci.staff_last_read_at
    into inquiry_id, staff_last_read_at;

  if inquiry_id is null then
    raise exception using message = 'inquiry_not_found_or_denied';
  end if;

  return next;
end;
$$;

comment on function public.mark_class_inquiry_staff_read(uuid) is
  'Monotonically advances the shared current-staff read timestamp without changing inquiry activity timestamps. The original author is treated as parent and cannot mark that inquiry as staff-read.';

revoke execute on function public.create_class_inquiry(uuid, text, text, text, uuid)
  from public, anon, service_role;
grant execute on function public.create_class_inquiry(uuid, text, text, text, uuid)
  to authenticated;

revoke execute on function public.add_parent_class_inquiry_message(uuid, text, uuid)
  from public, anon, service_role;
grant execute on function public.add_parent_class_inquiry_message(uuid, text, uuid)
  to authenticated;

revoke execute on function public.reply_to_class_inquiry(uuid, text, uuid)
  from public, anon, service_role;
grant execute on function public.reply_to_class_inquiry(uuid, text, uuid)
  to authenticated;

revoke execute on function public.start_class_inquiry_review(uuid)
  from public, anon, service_role;
grant execute on function public.start_class_inquiry_review(uuid)
  to authenticated;

revoke execute on function public.close_class_inquiry(uuid, uuid)
  from public, anon, service_role;
grant execute on function public.close_class_inquiry(uuid, uuid)
  to authenticated;

revoke execute on function public.mark_class_inquiry_parent_read(uuid)
  from public, anon, service_role;
grant execute on function public.mark_class_inquiry_parent_read(uuid)
  to authenticated;

revoke execute on function public.mark_class_inquiry_staff_read(uuid)
  from public, anon, service_role;
grant execute on function public.mark_class_inquiry_staff_read(uuid)
  to authenticated;

commit;
