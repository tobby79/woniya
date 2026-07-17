-- Harden teacher invite preparation, delivery tracking, and acceptance.

alter table public.teacher_invites
  add column if not exists delivery_status text not null default 'not_sent',
  add column if not exists delivery_attempt_id uuid,
  add column if not exists send_attempt_count integer not null default 0,
  add column if not exists last_send_attempt_at timestamptz,
  add column if not exists last_sent_at timestamptz,
  add column if not exists last_send_error_code text;

-- Revoke unusable pending invites before enforcing one pending invite per class.
update public.teacher_invites as ti
set status = 'revoked',
    accepted_at = null
from public.classes as c
where ti.class_id = c.id
  and ti.status = 'pending'
  and c.teacher_id is not null;

with ranked_pending as (
  select
    ti.id,
    row_number() over (
      partition by ti.class_id
      order by ti.invited_at desc, ti.id desc
    ) as row_number
  from public.teacher_invites as ti
  where ti.status = 'pending'
)
update public.teacher_invites as ti
set status = 'revoked',
    accepted_at = null
from ranked_pending as ranked
where ti.id = ranked.id
  and ranked.row_number > 1;

-- Normalize after pending deduplication so the legacy raw-email index cannot
-- reject canonical values that used to differ only by case or whitespace.
update public.teacher_invites
set email = lower(btrim(email))
where email is distinct from lower(btrim(email));

do $$
begin
  if exists (
    select 1
    from public.teacher_invites
    where email = ''
  ) then
    raise exception 'teacher_invites contains an empty canonical email';
  end if;
end;
$$;

alter table public.teacher_invites
  drop constraint if exists teacher_invites_email_canonical_check,
  add constraint teacher_invites_email_canonical_check
    check (email <> '' and email = lower(btrim(email))),
  drop constraint if exists teacher_invites_delivery_status_check,
  add constraint teacher_invites_delivery_status_check
    check (delivery_status in ('not_sent', 'sending', 'sent', 'failed')),
  drop constraint if exists teacher_invites_send_attempt_count_check,
  add constraint teacher_invites_send_attempt_count_check
    check (send_attempt_count >= 0),
  drop constraint if exists teacher_invites_last_send_error_code_check,
  add constraint teacher_invites_last_send_error_code_check
    check (
      last_send_error_code is null
      or (
        char_length(last_send_error_code) between 1 and 64
        and last_send_error_code ~ '^[a-z0-9_]+$'
      )
    );

-- Accepted legacy invites necessarily completed the old delivery flow.
update public.teacher_invites
set delivery_status = 'sent',
    send_attempt_count = greatest(send_attempt_count, 1),
    last_send_attempt_at = coalesce(last_send_attempt_at, invited_at),
    last_sent_at = coalesce(last_sent_at, accepted_at, invited_at),
    last_send_error_code = null
where status = 'accepted';

drop index if exists public.teacher_invites_pending_unique;

create unique index teacher_invites_pending_unique
  on public.teacher_invites (class_id)
  where status = 'pending';

-- Invite lifecycle writes must go through the functions below.
revoke insert, update, delete on table public.teacher_invites from public, anon, authenticated;

create or replace function public.prepare_teacher_invite_delivery(
  p_class_id uuid,
  p_email text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_caller_id uuid := auth.uid();
  v_normalized_email text := lower(btrim(coalesce(p_email, '')));
  v_class_teacher_id uuid;
  v_center_owner_id uuid;
  v_pending public.teacher_invites%rowtype;
  v_has_pending boolean := false;
  v_invite_id uuid;
  v_delivery_attempt_id uuid;
  v_reused boolean := false;
  v_dispatch_action text := 'send';
  v_retry_after_seconds integer := 0;
  v_now timestamptz;
  v_sending_protection constant interval := interval '5 minutes';
  v_sent_cooldown constant interval := interval '10 minutes';
begin
  if v_caller_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_class_id is null then
    raise exception 'class_id_required';
  end if;

  if v_normalized_email = '' or char_length(v_normalized_email) > 320 then
    raise exception 'email_invalid';
  end if;

  select c.teacher_id, ct.owner_id
    into v_class_teacher_id, v_center_owner_id
  from public.classes as c
  join public.centers as ct on ct.id = c.center_id
  where c.id = p_class_id
  for update of c;

  if not found then
    raise exception 'class_not_found';
  end if;

  if v_center_owner_id is distinct from v_caller_id then
    raise exception 'class_access_denied';
  end if;

  if v_class_teacher_id is not null then
    raise exception 'class_already_assigned';
  end if;

  select ti.*
    into v_pending
  from public.teacher_invites as ti
  where ti.class_id = p_class_id
    and ti.status = 'pending'
  order by ti.invited_at desc, ti.id desc
  limit 1
  for update of ti;

  v_has_pending := found;
  v_now := clock_timestamp();

  if v_has_pending and v_pending.email = v_normalized_email then
    v_reused := true;
    v_invite_id := v_pending.id;
    v_delivery_attempt_id := v_pending.delivery_attempt_id;

    if v_pending.delivery_status = 'sending'
       and v_pending.delivery_attempt_id is not null
       and v_pending.last_send_attempt_at is not null
       and v_pending.last_send_attempt_at + v_sending_protection > v_now then
      v_dispatch_action := 'in_progress';
      v_retry_after_seconds := greatest(
        1,
        ceil(extract(epoch from (
          v_pending.last_send_attempt_at + v_sending_protection - v_now
        )))::integer
      );
    elsif v_pending.delivery_status = 'sent'
          and v_pending.delivery_attempt_id is not null
          and v_pending.last_sent_at is not null
          and v_pending.last_sent_at + v_sent_cooldown > v_now then
      v_dispatch_action := 'already_sent';
      v_retry_after_seconds := greatest(
        1,
        ceil(extract(epoch from (
          v_pending.last_sent_at + v_sent_cooldown - v_now
        )))::integer
      );
    else
      v_delivery_attempt_id := gen_random_uuid();

      update public.teacher_invites
      set invited_by = v_caller_id,
          invited_at = v_now,
          delivery_status = 'sending',
          delivery_attempt_id = v_delivery_attempt_id,
          send_attempt_count = send_attempt_count + 1,
          last_send_attempt_at = v_now,
          last_send_error_code = null
      where id = v_invite_id;
    end if;
  else
    if v_has_pending then
      update public.teacher_invites
      set status = 'revoked',
          accepted_at = null
      where id = v_pending.id
        and status = 'pending';
    end if;

    v_delivery_attempt_id := gen_random_uuid();

    insert into public.teacher_invites (
      class_id,
      email,
      invited_by,
      status,
      invited_at,
      delivery_status,
      delivery_attempt_id,
      send_attempt_count,
      last_send_attempt_at,
      last_send_error_code
    )
    values (
      p_class_id,
      v_normalized_email,
      v_caller_id,
      'pending',
      v_now,
      'sending',
      v_delivery_attempt_id,
      1,
      v_now,
      null
    )
    returning id into v_invite_id;
  end if;

  return jsonb_build_object(
    'invite_id', v_invite_id,
    'normalized_email', v_normalized_email,
    'delivery_attempt_id', v_delivery_attempt_id,
    'reused', v_reused,
    'dispatch_action', v_dispatch_action,
    'retry_after_seconds', v_retry_after_seconds
  );
end;
$$;

revoke all on function public.prepare_teacher_invite_delivery(uuid, text) from public;
revoke all on function public.prepare_teacher_invite_delivery(uuid, text) from anon;
revoke all on function public.prepare_teacher_invite_delivery(uuid, text) from service_role;
grant execute on function public.prepare_teacher_invite_delivery(uuid, text) to authenticated;

create or replace function public.finalize_teacher_invite_delivery(
  p_invite_id uuid,
  p_delivery_attempt_id uuid,
  p_succeeded boolean,
  p_error_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.teacher_invites%rowtype;
  v_error_code text := lower(btrim(coalesce(p_error_code, '')));
begin
  if p_invite_id is null or p_delivery_attempt_id is null or p_succeeded is null then
    raise exception 'invalid_delivery_result';
  end if;

  if not p_succeeded
     and v_error_code not in ('auth_invite_failed', 'auth_user_already_exists') then
    raise exception 'invalid_delivery_error_code';
  end if;

  select ti.*
    into v_invite
  from public.teacher_invites as ti
  where ti.id = p_invite_id
  for update of ti;

  if not found then
    return jsonb_build_object(
      'updated', false,
      'finalized', false,
      'result_code', 'invite_not_found',
      'delivery_status', null
    );
  end if;

  if v_invite.status <> 'pending' then
    return jsonb_build_object(
      'updated', false,
      'finalized', false,
      'result_code', 'invite_not_pending',
      'delivery_status', v_invite.delivery_status
    );
  end if;

  if v_invite.delivery_attempt_id is distinct from p_delivery_attempt_id then
    return jsonb_build_object(
      'updated', false,
      'finalized', false,
      'result_code', 'stale_attempt',
      'delivery_status', v_invite.delivery_status
    );
  end if;

  if v_invite.delivery_status = 'sending' then
    if p_succeeded then
      update public.teacher_invites
      set delivery_status = 'sent',
          last_sent_at = clock_timestamp(),
          last_send_error_code = null
      where id = p_invite_id;

      return jsonb_build_object(
        'updated', true,
        'finalized', true,
        'result_code', 'applied',
        'delivery_status', 'sent'
      );
    end if;

    update public.teacher_invites
    set delivery_status = 'failed',
        last_send_error_code = v_error_code
    where id = p_invite_id;

    return jsonb_build_object(
      'updated', true,
      'finalized', true,
      'result_code', 'applied',
      'delivery_status', 'failed'
    );
  end if;

  if p_succeeded and v_invite.delivery_status = 'sent' then
    return jsonb_build_object(
      'updated', false,
      'finalized', true,
      'result_code', 'already_applied',
      'delivery_status', 'sent'
    );
  end if;

  if not p_succeeded
     and v_invite.delivery_status = 'failed'
     and v_invite.last_send_error_code = v_error_code then
    return jsonb_build_object(
      'updated', false,
      'finalized', true,
      'result_code', 'already_applied',
      'delivery_status', 'failed'
    );
  end if;

  return jsonb_build_object(
    'updated', false,
    'finalized', false,
    'result_code', 'finalize_conflict',
    'delivery_status', v_invite.delivery_status
  );
end;
$$;

revoke all on function public.finalize_teacher_invite_delivery(uuid, uuid, boolean, text) from public;
revoke all on function public.finalize_teacher_invite_delivery(uuid, uuid, boolean, text) from anon;
revoke all on function public.finalize_teacher_invite_delivery(uuid, uuid, boolean, text) from authenticated;
grant execute on function public.finalize_teacher_invite_delivery(uuid, uuid, boolean, text) to service_role;

create or replace function public.accept_teacher_invite()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text;
  v_candidate record;
  v_locked_invite_id uuid;
  v_locked_class_id uuid;
  v_assigned_class_id uuid;
  v_accepted_count integer;
  v_linked_classes uuid[] := '{}';
begin
  select lower(btrim(email))
    into v_email
  from auth.users
  where id = auth.uid();

  if v_email is null then
    raise exception 'Unable to confirm logged-in user email.';
  end if;

  for v_candidate in
    select ti.id, ti.class_id
    from public.teacher_invites as ti
    where ti.email = v_email
      and ti.status = 'pending'
    order by ti.invited_at, ti.id
  loop
    v_locked_class_id := null;
    v_locked_invite_id := null;
    v_assigned_class_id := null;
    v_accepted_count := 0;

    -- Keep the same class-then-invite lock order as invite preparation.
    select c.id
      into v_locked_class_id
    from public.classes as c
    where c.id = v_candidate.class_id
    for update of c;

    if v_locked_class_id is null then
      continue;
    end if;

    select ti.id
      into v_locked_invite_id
    from public.teacher_invites as ti
    where ti.id = v_candidate.id
      and ti.class_id = v_candidate.class_id
      and ti.email = v_email
      and ti.status = 'pending'
    for update of ti;

    if v_locked_invite_id is null then
      continue;
    end if;

    update public.classes
    set teacher_id = auth.uid()
    where id = v_locked_class_id
      and teacher_id is null
    returning id into v_assigned_class_id;

    if v_assigned_class_id is not null then
      update public.teacher_invites
      set status = 'accepted',
          accepted_at = now(),
          delivery_status = 'sent',
          last_sent_at = coalesce(last_sent_at, now()),
          last_send_error_code = null
      where id = v_locked_invite_id
        and status = 'pending';

      get diagnostics v_accepted_count = row_count;

      if v_accepted_count <> 1 then
        raise exception 'Teacher invite could not be marked accepted.';
      end if;

      update public.teacher_invites
      set status = 'revoked',
          accepted_at = null
      where class_id = v_assigned_class_id
        and id <> v_locked_invite_id
        and status = 'pending';

      v_linked_classes := array_append(v_linked_classes, v_assigned_class_id);
    end if;
  end loop;

  if coalesce(array_length(v_linked_classes, 1), 0) = 0 then
    raise exception 'No assignable pending teacher invite found.';
  end if;

  return jsonb_build_object('linked_classes', v_linked_classes);
end;
$$;

revoke all on function public.accept_teacher_invite() from public;
revoke all on function public.accept_teacher_invite() from anon;
revoke all on function public.accept_teacher_invite() from service_role;
grant execute on function public.accept_teacher_invite() to authenticated;
