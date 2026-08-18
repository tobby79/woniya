begin;

-- Center publication and the service-contract lifecycle are separate concerns.
-- service_ended_at is the retention clock for the 30-day period after an
-- official service end. Archived, unpublished, or ownerless centers are not
-- inferred to be ended, and actual retention cleanup belongs in a later migration.
do $precondition$
declare
  v_status_attnum smallint;
  v_status_type oid;
  v_status_not_null boolean;
  v_is_published_type oid;
  v_is_published_not_null boolean;
  v_status_check_count integer;
  v_matching_status_check_count integer;
begin
  if to_regclass('public.centers') is null then
    raise exception 'Expected public.centers to exist before adding the service lifecycle';
  end if;

  select attribute.attnum, attribute.atttypid, attribute.attnotnull
    into v_status_attnum, v_status_type, v_status_not_null
  from pg_attribute as attribute
  where attribute.attrelid = 'public.centers'::regclass
    and attribute.attname = 'status'
    and not attribute.attisdropped;

  if not found
     or v_status_type <> 'text'::regtype
     or not v_status_not_null then
    raise exception 'Expected public.centers.status to be a NOT NULL text column';
  end if;

  select attribute.atttypid, attribute.attnotnull
    into v_is_published_type, v_is_published_not_null
  from pg_attribute as attribute
  where attribute.attrelid = 'public.centers'::regclass
    and attribute.attname = 'is_published'
    and not attribute.attisdropped;

  if not found
     or v_is_published_type <> 'boolean'::regtype
     or not v_is_published_not_null then
    raise exception 'Expected public.centers.is_published to be a NOT NULL boolean column';
  end if;

  select count(*)
    into v_status_check_count
  from pg_constraint as constraint_row
  where constraint_row.conrelid = 'public.centers'::regclass
    and constraint_row.contype = 'c'
    and v_status_attnum = any(constraint_row.conkey);

  select count(*)
    into v_matching_status_check_count
  from pg_constraint as constraint_row
  where constraint_row.conrelid = 'public.centers'::regclass
    and constraint_row.contype = 'c'
    and constraint_row.conkey = array[v_status_attnum]::smallint[]
    and regexp_replace(
      lower(pg_get_expr(constraint_row.conbin, constraint_row.conrelid)),
      '[[:space:]]+',
      '',
      'g'
    ) ~ '^\(*status=any\(array\[''draft''::text,''published''::text,''archived''::text\]\)\)*$';

  if v_status_check_count <> 1 or v_matching_status_check_count <> 1 then
    raise exception
      'Expected exactly one centers.status CHECK allowing only draft, published, and archived';
  end if;
end;
$precondition$;

alter table public.centers
  add column service_ended_at timestamptz;

comment on column public.centers.service_ended_at is
  'Official Woniya service end time and the retention clock for 30-day post-service cleanup. NULL means service end is not confirmed. This lifecycle is independent of draft, published, and archived publication states.';

create index centers_service_ended_at_retention_idx
  on public.centers (service_ended_at)
  where service_ended_at is not null;

alter table public.centers
  add constraint centers_service_ended_publication_check
  check (
    service_ended_at is null
    or (status <> 'published' and is_published = false)
  );

create function public.enforce_center_service_lifecycle()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $function$
declare
  v_is_platform_admin boolean := lower(coalesce(auth.email(), '')) = 'tobby79@naver.com';
begin
  if tg_op = 'INSERT' then
    if new.service_ended_at is not null then
      raise exception 'centers.service_ended_at cannot be set during center creation';
    end if;

    new.service_ended_at := null;
    return new;
  end if;

  -- Active centers keep the existing draft/published/archived workflow.
  if old.service_ended_at is null and new.service_ended_at is null then
    return new;
  end if;

  -- Official service end. Ignore any caller-supplied timestamp.
  if old.service_ended_at is null and new.service_ended_at is not null then
    if not v_is_platform_admin then
      raise exception 'only the platform administrator can end center service';
    end if;

    new.service_ended_at := now();
    new.status := 'draft';
    new.is_published := false;
    return new;
  end if;

  -- Official reactivation. Reactivation never republishes automatically.
  if old.service_ended_at is not null and new.service_ended_at is null then
    if not v_is_platform_admin then
      raise exception 'only the platform administrator can reactivate center service';
    end if;

    new.service_ended_at := null;
    new.status := 'draft';
    new.is_published := false;
    return new;
  end if;

  -- An ended center keeps its original end time and cannot be republished.
  if new.service_ended_at is distinct from old.service_ended_at then
    raise exception 'centers.service_ended_at cannot be changed after service end';
  end if;

  if new.status = 'published' or new.is_published then
    raise exception 'ended center service must be reactivated before publication';
  end if;

  new.service_ended_at := old.service_ended_at;
  return new;
end;
$function$;

create trigger centers_enforce_service_lifecycle
  before insert or update of service_ended_at, status, is_published
  on public.centers
  for each row
  execute function public.enforce_center_service_lifecycle();

create function public.end_center_service(p_center_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_center public.centers%rowtype;
begin
  if lower(coalesce(auth.email(), '')) <> 'tobby79@naver.com' then
    raise exception 'platform admin only';
  end if;

  if p_center_id is null then
    raise exception 'center_id is required';
  end if;

  select *
    into v_center
  from public.centers
  where id = p_center_id
  for update;

  if not found then
    raise exception 'center not found';
  end if;

  if v_center.service_ended_at is null then
    update public.centers
      set service_ended_at = now()
      where id = p_center_id
      returning * into v_center;
  end if;

  return jsonb_build_object(
    'success', true,
    'center_id', v_center.id,
    'service_ended_at', v_center.service_ended_at,
    'status', v_center.status,
    'is_published', v_center.is_published
  );
end;
$function$;

comment on function public.end_center_service(uuid) is
  'Platform-admin-only, idempotent transition that records the database service-end time and unpublishes the center.';

create function public.reactivate_center_service(p_center_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_center public.centers%rowtype;
begin
  if lower(coalesce(auth.email(), '')) <> 'tobby79@naver.com' then
    raise exception 'platform admin only';
  end if;

  if p_center_id is null then
    raise exception 'center_id is required';
  end if;

  select *
    into v_center
  from public.centers
  where id = p_center_id
  for update;

  if not found then
    raise exception 'center not found';
  end if;

  if v_center.service_ended_at is not null then
    update public.centers
      set service_ended_at = null,
          status = 'draft',
          is_published = false
      where id = p_center_id
      returning * into v_center;
  end if;

  return jsonb_build_object(
    'success', true,
    'center_id', v_center.id,
    'service_ended_at', v_center.service_ended_at,
    'status', v_center.status,
    'is_published', v_center.is_published
  );
end;
$function$;

comment on function public.reactivate_center_service(uuid) is
  'Platform-admin-only, idempotent reactivation that clears the retention clock while leaving the center unpublished.';

revoke all on function public.end_center_service(uuid)
  from public, anon, authenticated;
grant execute on function public.end_center_service(uuid)
  to authenticated;

revoke all on function public.reactivate_center_service(uuid)
  from public, anon, authenticated;
grant execute on function public.reactivate_center_service(uuid)
  to authenticated;

commit;
