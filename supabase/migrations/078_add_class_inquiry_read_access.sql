begin;

create policy class_inquiries_select_participants
on public.class_inquiries
for select
to authenticated
using (
  author_id = auth.uid()
  or coalesce(public.is_class_staff(class_id), false)
);

create policy class_inquiry_messages_select_participants
on public.class_inquiry_messages
for select
to authenticated
using (
  exists (
    select 1
    from public.class_inquiries as ci
    where ci.id = class_inquiry_messages.inquiry_id
      and (
        ci.author_id = auth.uid()
        or coalesce(public.is_class_staff(ci.class_id), false)
      )
  )
);

revoke all privileges on table public.class_inquiry_daily_counters
  from public, anon, authenticated, service_role;
revoke all privileges on table public.class_inquiries
  from public, anon, authenticated, service_role;
revoke all privileges on table public.class_inquiry_messages
  from public, anon, authenticated, service_role;

grant select (
  id,
  document_no,
  class_id,
  author_id,
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
  closed_by_role
) on table public.class_inquiries to authenticated;

grant select (
  id,
  inquiry_id,
  sender_id,
  sender_role,
  message_type,
  body,
  status_from,
  status_to,
  created_at
) on table public.class_inquiry_messages to authenticated;

create or replace function public.get_my_class_inquiries(
  p_class_id uuid default null,
  p_status text default null,
  p_before_has_unread_reply boolean default null,
  p_before_updated_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 30
)
returns table (
  inquiry_id uuid,
  document_no text,
  class_id uuid,
  category text,
  subject text,
  status text,
  created_at timestamptz,
  updated_at timestamptz,
  last_message_at timestamptz,
  last_staff_message_at timestamptz,
  parent_last_read_at timestamptz,
  has_unread_reply boolean,
  is_closed boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_status text := case
    when p_status is null then null
    else lower(btrim(p_status))
  end;
begin
  if v_user_id is null then
    raise exception using message = 'not_authenticated';
  end if;

  if p_limit is null or p_limit not between 1 and 50 then
    raise exception using message = 'invalid_input';
  end if;

  if v_status is not null
     and v_status not in ('received', 'in_progress', 'answered', 'closed') then
    raise exception using message = 'invalid_status';
  end if;

  if not (
    (
      p_before_has_unread_reply is null
      and p_before_updated_at is null
      and p_before_id is null
    )
    or
    (
      p_before_has_unread_reply is not null
      and p_before_updated_at is not null
      and p_before_id is not null
    )
  ) then
    raise exception using message = 'invalid_cursor';
  end if;

  if p_before_id is not null then
    perform 1
    from public.class_inquiries as ci
    where ci.id = p_before_id
      and ci.author_id = v_user_id
      and (p_class_id is null or ci.class_id = p_class_id)
      and (v_status is null or ci.status = v_status);

    if not found then
      raise exception using message = 'invalid_cursor';
    end if;
  end if;

  return query
  with candidate_rows as (
    select
      ci.id,
      ci.document_no,
      ci.class_id,
      ci.category,
      ci.subject,
      ci.status,
      ci.created_at,
      ci.updated_at,
      ci.last_message_at,
      ci.last_staff_message_at,
      ci.parent_last_read_at,
      (
        ci.last_staff_message_at is not null
        and ci.parent_last_read_at < ci.last_staff_message_at
      ) as has_unread_reply
    from public.class_inquiries as ci
    where ci.author_id = v_user_id
      and (p_class_id is null or ci.class_id = p_class_id)
      and (v_status is null or ci.status = v_status)
  )
  select
    cr.id,
    cr.document_no,
    cr.class_id,
    cr.category,
    cr.subject,
    cr.status,
    cr.created_at,
    cr.updated_at,
    cr.last_message_at,
    cr.last_staff_message_at,
    cr.parent_last_read_at,
    cr.has_unread_reply,
    (cr.status = 'closed')
  from candidate_rows as cr
  where p_before_id is null
     or (
       (p_before_has_unread_reply and not cr.has_unread_reply)
       or (
         cr.has_unread_reply = p_before_has_unread_reply
         and (cr.updated_at, cr.id) < (p_before_updated_at, p_before_id)
       )
     )
  order by
    cr.has_unread_reply desc,
    cr.updated_at desc,
    cr.id desc
  limit p_limit;
end;
$$;

comment on function public.get_my_class_inquiries(uuid, text, boolean, timestamptz, uuid, integer) is
  'Returns only the authenticated author''s inquiries. A cursor repeats the prior last row''s unread priority, updated_at, and id; supplied sort values remain authoritative after list changes, but concurrent changes to other rows can still reposition results because pagination is not a snapshot.';

create or replace function public.get_class_inquiries_for_staff(
  p_class_id uuid,
  p_status text default null,
  p_unread_only boolean default false,
  p_before_has_unread_parent_message boolean default null,
  p_before_requires_response boolean default null,
  p_before_updated_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 30
)
returns table (
  inquiry_id uuid,
  document_no text,
  class_id uuid,
  author_id uuid,
  category text,
  subject text,
  status text,
  created_at timestamptz,
  updated_at timestamptz,
  last_message_at timestamptz,
  last_parent_message_at timestamptz,
  staff_last_read_at timestamptz,
  has_unread_parent_message boolean,
  requires_response boolean,
  is_closed boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_status text := case
    when p_status is null then null
    else lower(btrim(p_status))
  end;
  v_unread_only boolean := coalesce(p_unread_only, false);
begin
  if v_user_id is null then
    raise exception using message = 'not_authenticated';
  end if;

  if p_class_id is null
     or p_limit is null
     or p_limit not between 1 and 50 then
    raise exception using message = 'invalid_input';
  end if;

  if v_status is not null
     and v_status not in ('received', 'in_progress', 'answered', 'closed') then
    raise exception using message = 'invalid_status';
  end if;

  if not (
    (
      p_before_has_unread_parent_message is null
      and p_before_requires_response is null
      and p_before_updated_at is null
      and p_before_id is null
    )
    or
    (
      p_before_has_unread_parent_message is not null
      and p_before_requires_response is not null
      and p_before_updated_at is not null
      and p_before_id is not null
    )
  ) then
    raise exception using message = 'invalid_cursor';
  end if;

  if not coalesce(public.is_class_staff(p_class_id), false) then
    raise exception using message = 'class_access_denied';
  end if;

  if p_before_id is not null then
    perform 1
    from public.class_inquiries as ci
    where ci.id = p_before_id
      and ci.class_id = p_class_id
      and ci.author_id is distinct from v_user_id
      and (v_status is null or ci.status = v_status)
      and (
        not v_unread_only
        or p_before_has_unread_parent_message
      );

    if not found then
      raise exception using message = 'invalid_cursor';
    end if;
  end if;

  return query
  with candidate_rows as (
    select
      ci.id,
      ci.document_no,
      ci.class_id,
      ci.author_id,
      ci.category,
      ci.subject,
      ci.status,
      ci.created_at,
      ci.updated_at,
      ci.last_message_at,
      ci.last_parent_message_at,
      ci.staff_last_read_at,
      (
        ci.staff_last_read_at is null
        or ci.staff_last_read_at < ci.last_parent_message_at
      ) as has_unread_parent_message,
      (ci.status in ('received', 'in_progress')) as requires_response
    from public.class_inquiries as ci
    where ci.class_id = p_class_id
      and ci.author_id is distinct from v_user_id
      and (v_status is null or ci.status = v_status)
      and (
        not v_unread_only
        or ci.staff_last_read_at is null
        or ci.staff_last_read_at < ci.last_parent_message_at
      )
  )
  select
    cr.id,
    cr.document_no,
    cr.class_id,
    cr.author_id,
    cr.category,
    cr.subject,
    cr.status,
    cr.created_at,
    cr.updated_at,
    cr.last_message_at,
    cr.last_parent_message_at,
    cr.staff_last_read_at,
    cr.has_unread_parent_message,
    cr.requires_response,
    (cr.status = 'closed')
  from candidate_rows as cr
  where p_before_id is null
     or (
       (
         p_before_has_unread_parent_message
         and not cr.has_unread_parent_message
       )
       or (
         cr.has_unread_parent_message = p_before_has_unread_parent_message
         and (
           (p_before_requires_response and not cr.requires_response)
           or (
             cr.requires_response = p_before_requires_response
             and (cr.updated_at, cr.id) < (p_before_updated_at, p_before_id)
           )
         )
       )
     )
  order by
    cr.has_unread_parent_message desc,
    cr.requires_response desc,
    cr.updated_at desc,
    cr.id desc
  limit p_limit;
end;
$$;

comment on function public.get_class_inquiries_for_staff(uuid, text, boolean, boolean, boolean, timestamptz, uuid, integer) is
  'Returns one class''s inquiries to current staff, excluding inquiries authored by the caller because the original author is treated as parent. A cursor repeats the prior last row''s unread and response priorities, updated_at, and id; supplied sort values remain authoritative after list changes, but concurrent changes to other rows can still reposition results because pagination is not a snapshot.';

create or replace function public.get_class_inquiry_thread(
  p_inquiry_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_inquiry public.class_inquiries%rowtype;
  v_is_parent boolean;
  v_is_staff boolean;
  v_is_owner boolean;
  v_is_approved_parent boolean;
  v_viewer_role text;
  v_result jsonb;
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
  where ci.id = p_inquiry_id;

  if v_inquiry.id is null then
    raise exception using message = 'inquiry_not_found_or_denied';
  end if;

  v_is_parent := v_inquiry.author_id is not distinct from v_user_id;
  v_is_staff := coalesce(public.is_class_staff(v_inquiry.class_id), false);

  if not v_is_parent and not v_is_staff then
    raise exception using message = 'inquiry_not_found_or_denied';
  end if;

  if v_is_parent then
    v_viewer_role := 'parent';
    v_is_owner := false;
  else
    v_is_owner := coalesce(public.is_class_owner(v_inquiry.class_id), false);
    if v_is_owner then
      v_viewer_role := 'owner';
    else
      v_viewer_role := 'teacher';
    end if;
  end if;

  v_is_approved_parent := v_is_parent
    and coalesce(public.is_approved_parent(v_inquiry.class_id), false);

  select jsonb_build_object(
    'inquiry', jsonb_build_object(
      'id', v_inquiry.id,
      'document_no', v_inquiry.document_no,
      'class_id', v_inquiry.class_id,
      'author_id', v_inquiry.author_id,
      'category', v_inquiry.category,
      'subject', v_inquiry.subject,
      'status', v_inquiry.status,
      'created_at', v_inquiry.created_at,
      'updated_at', v_inquiry.updated_at,
      'last_message_at', v_inquiry.last_message_at,
      'last_parent_message_at', v_inquiry.last_parent_message_at,
      'last_staff_message_at', v_inquiry.last_staff_message_at,
      'parent_last_read_at', v_inquiry.parent_last_read_at,
      'staff_last_read_at', v_inquiry.staff_last_read_at,
      'answered_at', v_inquiry.answered_at,
      'closed_at', v_inquiry.closed_at,
      'closed_by_role', v_inquiry.closed_by_role
    ),
    'messages', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', cim.id,
            'sender_id', cim.sender_id,
            'sender_role', cim.sender_role,
            'message_type', cim.message_type,
            'body', cim.body,
            'status_from', cim.status_from,
            'status_to', cim.status_to,
            'created_at', cim.created_at
          )
          order by cim.created_at asc, cim.id asc
        )
        from public.class_inquiry_messages as cim
        where cim.inquiry_id = v_inquiry.id
      ),
      '[]'::jsonb
    ),
    'viewer_role', v_viewer_role,
    'permissions', jsonb_build_object(
      'can_add_parent_message', (
        v_viewer_role = 'parent'
        and v_inquiry.status <> 'closed'
        and v_is_approved_parent
      ),
      'can_reply', (
        v_viewer_role in ('teacher', 'owner')
        and v_inquiry.status <> 'closed'
      ),
      'can_start_review', (
        v_viewer_role in ('teacher', 'owner')
        and v_inquiry.status = 'received'
      ),
      'can_close', (
        (v_is_parent or v_is_staff)
        and v_inquiry.status <> 'closed'
      ),
      'can_mark_read', true
    )
  )
    into v_result;

  return v_result;
end;
$$;

comment on function public.get_class_inquiry_thread(uuid) is
  'Returns one authorized inquiry with all append-only messages, viewer role, and current action permissions without mutating status or read timestamps.';

revoke execute on function public.get_my_class_inquiries(uuid, text, boolean, timestamptz, uuid, integer)
  from public, anon, service_role;
grant execute on function public.get_my_class_inquiries(uuid, text, boolean, timestamptz, uuid, integer)
  to authenticated;

revoke execute on function public.get_class_inquiries_for_staff(uuid, text, boolean, boolean, boolean, timestamptz, uuid, integer)
  from public, anon, service_role;
grant execute on function public.get_class_inquiries_for_staff(uuid, text, boolean, boolean, boolean, timestamptz, uuid, integer)
  to authenticated;

revoke execute on function public.get_class_inquiry_thread(uuid)
  from public, anon, service_role;
grant execute on function public.get_class_inquiry_thread(uuid)
  to authenticated;

commit;
