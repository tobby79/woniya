-- Add an auditable class teacher assignment lifecycle and RPC-only writes.

BEGIN;

create table public.class_teacher_assignments (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  teacher_user_id uuid references auth.users(id) on delete set null,
  teacher_email_snapshot text,
  teacher_invite_id uuid references public.teacher_invites(id) on delete set null,
  assigned_at timestamptz,
  assigned_by uuid references auth.users(id) on delete set null,
  assignment_source text not null,
  ended_at timestamptz,
  ended_by uuid references auth.users(id) on delete set null,
  end_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint class_teacher_assignments_email_canonical_check
    check (
      teacher_email_snapshot is null
      or (
        teacher_email_snapshot <> ''
        and teacher_email_snapshot = lower(btrim(teacher_email_snapshot))
      )
    ),
  constraint class_teacher_assignments_end_reason_check
    check (
      end_reason is null
      or (
        char_length(end_reason) between 1 and 200
        and end_reason = btrim(end_reason)
      )
    ),
  constraint class_teacher_assignments_source_check
    check (
      (assignment_source = 'baseline' and assigned_at is null)
      or (
        assignment_source = 'invite_acceptance'
        and assigned_at is not null
      )
    ),
  constraint class_teacher_assignments_ended_state_check
    check (
      ended_at is not null
      or (ended_by is null and end_reason is null)
    )
);

create unique index class_teacher_assignments_active_class_unique
  on public.class_teacher_assignments (class_id)
  where ended_at is null;

create index class_teacher_assignments_class_history_idx
  on public.class_teacher_assignments (
    class_id,
    assigned_at desc nulls last,
    created_at desc
  );

create index class_teacher_assignments_teacher_user_id_idx
  on public.class_teacher_assignments (teacher_user_id);

create index class_teacher_assignments_teacher_invite_id_idx
  on public.class_teacher_assignments (teacher_invite_id);

create trigger class_teacher_assignments_set_updated_at
  before update on public.class_teacher_assignments
  for each row
  execute function public.set_updated_at();

alter table public.class_teacher_assignments enable row level security;

revoke all on table public.class_teacher_assignments
  from public, anon, authenticated;
grant select on table public.class_teacher_assignments to authenticated;

create policy class_teacher_assignments_owner_select
  on public.class_teacher_assignments
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.classes as c
      join public.centers as ct on ct.id = c.center_id
      where c.id = class_teacher_assignments.class_id
        and ct.owner_id = auth.uid()
    )
  );

create policy class_teacher_assignments_current_teacher_select
  on public.class_teacher_assignments
  for select
  to authenticated
  using (
    teacher_user_id = auth.uid()
    and ended_at is null
    and exists (
      select 1
      from public.classes as c
      where c.id = class_teacher_assignments.class_id
        and c.teacher_id = auth.uid()
    )
  );

-- Prevent legacy assignment writes while validating and recording the baseline.
-- This transaction-scoped lock is held through the RPC replacement below.
lock table public.classes in share row exclusive mode;

do $$
begin
  if exists (
    select 1
    from public.classes as c
    left join auth.users as u on u.id = c.teacher_id
    where c.teacher_id is not null
      and u.id is null
  ) then
    raise exception 'Existing class teacher references are invalid; assignment lifecycle migration cannot continue.';
  end if;
end;
$$;

-- Record only the current assignment baseline. Historical assignment dates and
-- invite links cannot be reconstructed reliably, so they intentionally stay null.
insert into public.class_teacher_assignments (
  class_id,
  teacher_user_id,
  teacher_email_snapshot,
  teacher_invite_id,
  assigned_at,
  assigned_by,
  assignment_source
)
select
  c.id,
  c.teacher_id,
  nullif(lower(btrim(u.email)), ''),
  null,
  null,
  null,
  'baseline'
from public.classes as c
left join auth.users as u on u.id = c.teacher_id
where c.teacher_id is not null;

-- Keep ordinary class management available while reserving teacher_id for RPCs.
revoke insert, update on table public.classes from anon, authenticated;
grant insert (
  center_id,
  teacher_media_id,
  name,
  age_label,
  capacity,
  enrolled,
  waiting,
  status
) on public.classes to authenticated;
grant update (
  teacher_media_id,
  name,
  age_label,
  capacity,
  enrolled,
  waiting,
  status
) on public.classes to authenticated;

create or replace function public.unassign_class_teacher(
  p_class_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_caller_id uuid := auth.uid();
  v_owner_id uuid;
  v_teacher_id uuid;
  v_assignment_id uuid;
  v_assignment_teacher_id uuid;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_now timestamptz;
begin
  if v_caller_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_class_id is null then
    raise exception 'class_id_required';
  end if;

  if v_reason is not null and char_length(v_reason) > 200 then
    raise exception 'reason_too_long';
  end if;

  select c.teacher_id, ct.owner_id
    into v_teacher_id, v_owner_id
  from public.classes as c
  join public.centers as ct on ct.id = c.center_id
  where c.id = p_class_id
  for update of c;

  if not found then
    raise exception 'class_not_found';
  end if;

  if v_owner_id is distinct from v_caller_id then
    raise exception 'class_access_denied';
  end if;

  if v_teacher_id is null then
    return jsonb_build_object(
      'success', true,
      'action', 'already_unassigned',
      'class_id', p_class_id
    );
  end if;

  select cta.id, cta.teacher_user_id
    into v_assignment_id, v_assignment_teacher_id
  from public.class_teacher_assignments as cta
  where cta.class_id = p_class_id
    and cta.ended_at is null
  for update of cta;

  if v_assignment_id is null
     or v_assignment_teacher_id is distinct from v_teacher_id then
    raise exception 'assignment_state_conflict';
  end if;

  v_now := clock_timestamp();

  update public.class_teacher_assignments
  set ended_at = v_now,
      ended_by = v_caller_id,
      end_reason = v_reason
  where id = v_assignment_id
    and ended_at is null;

  update public.classes
  set teacher_id = null
  where id = p_class_id
    and teacher_id = v_teacher_id;

  if not found then
    raise exception 'assignment_state_conflict';
  end if;

  update public.teacher_invites
  set status = 'revoked',
      accepted_at = null
  where class_id = p_class_id
    and status = 'pending';

  return jsonb_build_object(
    'success', true,
    'action', 'unassigned',
    'class_id', p_class_id
  );
end;
$$;

revoke all on function public.unassign_class_teacher(uuid, text) from public;
revoke all on function public.unassign_class_teacher(uuid, text) from anon;
revoke all on function public.unassign_class_teacher(uuid, text) from service_role;
grant execute on function public.unassign_class_teacher(uuid, text) to authenticated;

create or replace function public.accept_teacher_invite()
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_caller_id uuid := auth.uid();
  v_email text;
  v_candidate record;
  v_locked_invite_id uuid;
  v_locked_class_id uuid;
  v_locked_teacher_id uuid;
  v_active_assignment_id uuid;
  v_assigned_class_id uuid;
  v_accepted_count integer;
  v_linked_classes uuid[] := '{}';
  v_now timestamptz;
begin
  select lower(btrim(email))
    into v_email
  from auth.users
  where id = v_caller_id;

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
    v_locked_teacher_id := null;
    v_locked_invite_id := null;
    v_active_assignment_id := null;
    v_assigned_class_id := null;
    v_accepted_count := 0;

    select c.id, c.teacher_id
      into v_locked_class_id, v_locked_teacher_id
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

    select cta.id
      into v_active_assignment_id
    from public.class_teacher_assignments as cta
    where cta.class_id = v_locked_class_id
      and cta.ended_at is null
    for update of cta;

    if v_locked_teacher_id is not null
       or v_active_assignment_id is not null then
      raise exception 'Class teacher assignment state is inconsistent.';
    end if;

    update public.classes
    set teacher_id = v_caller_id
    where id = v_locked_class_id
      and teacher_id is null
    returning id into v_assigned_class_id;

    if v_assigned_class_id is not null then
      v_now := clock_timestamp();

      update public.teacher_invites
      set status = 'accepted',
          accepted_at = v_now,
          delivery_status = 'sent',
          last_sent_at = coalesce(last_sent_at, v_now),
          last_send_error_code = null
      where id = v_locked_invite_id
        and status = 'pending';

      get diagnostics v_accepted_count = row_count;

      if v_accepted_count <> 1 then
        raise exception 'Teacher invite could not be marked accepted.';
      end if;

      insert into public.class_teacher_assignments (
        class_id,
        teacher_user_id,
        teacher_email_snapshot,
        teacher_invite_id,
        assigned_at,
        assigned_by,
        assignment_source
      )
      values (
        v_assigned_class_id,
        v_caller_id,
        v_email,
        v_locked_invite_id,
        v_now,
        v_caller_id,
        'invite_acceptance'
      );

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

COMMIT;
