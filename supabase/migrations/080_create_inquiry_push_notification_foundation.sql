begin;

-- Database-only foundation for inquiry Web Push notifications.
-- This migration intentionally does not attach the notification event function
-- to class_inquiry_messages. A later migration may create that trigger after
-- the delivery worker is ready.

do $migration$
begin
  if to_regclass('public.class_inquiries') is null
     or to_regclass('public.class_inquiry_messages') is null then
    raise exception using
      errcode = '42P01',
      message = 'Required class inquiry tables do not exist.';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_extension as e
    join pg_catalog.pg_namespace as n on n.oid = e.extnamespace
    where e.extname = 'pgcrypto'
      and n.nspname = 'extensions'
  ) then
    raise exception using
      errcode = '42704',
      message = 'Required extension extensions.pgcrypto does not exist.';
  end if;

  if to_regprocedure('public.set_updated_at()') is null then
    raise exception using
      errcode = '42883',
      message = 'Required function public.set_updated_at() does not exist.';
  end if;
end
$migration$;

create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  installation_id uuid not null,
  binding_token uuid not null default gen_random_uuid(),
  endpoint text not null,
  endpoint_hash text not null,
  p256dh text not null,
  auth text not null,
  expiration_at timestamptz,
  vapid_key_version smallint not null default 1,
  browser_family text,
  platform_family text,
  last_seen_at timestamptz not null default now(),
  last_success_at timestamptz,
  disabled_at timestamptz,
  disabled_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint push_subscriptions_user_id_fkey
    foreign key (user_id)
    references auth.users (id)
    on delete cascade,
  constraint push_subscriptions_binding_token_key
    unique (binding_token),
  constraint push_subscriptions_endpoint_check
    check (
      endpoint = btrim(endpoint)
      and char_length(endpoint) between 9 and 4096
      and left(endpoint, 8) = 'https://'
    ),
  constraint push_subscriptions_endpoint_hash_check
    check (
      char_length(endpoint_hash) = 64
      and endpoint_hash ~ '^[0-9a-f]{64}$'
    ),
  constraint push_subscriptions_p256dh_check
    check (
      p256dh = btrim(p256dh)
      and char_length(p256dh) between 1 and 512
    ),
  constraint push_subscriptions_auth_check
    check (
      auth = btrim(auth)
      and char_length(auth) between 1 and 256
    ),
  constraint push_subscriptions_vapid_key_version_check
    check (vapid_key_version = 1),
  constraint push_subscriptions_browser_family_check
    check (
      browser_family is null
      or (
        browser_family = btrim(browser_family)
        and char_length(browser_family) between 1 and 100
      )
    ),
  constraint push_subscriptions_platform_family_check
    check (
      platform_family is null
      or (
        platform_family = btrim(platform_family)
        and char_length(platform_family) between 1 and 100
      )
    ),
  constraint push_subscriptions_disabled_reason_check
    check (
      disabled_reason is null
      or disabled_reason in (
        'logout',
        'permission_denied',
        'unsubscribed',
        'expired',
        'gone',
        'endpoint_replaced',
        'user_changed',
        'vapid_rotated',
        'manual',
        'invalid_subscription'
      )
    ),
  constraint push_subscriptions_disabled_state_check
    check (
      (disabled_at is null and disabled_reason is null)
      or (disabled_at is not null and disabled_reason is not null)
    ),
  constraint push_subscriptions_last_seen_at_check
    check (last_seen_at >= created_at),
  constraint push_subscriptions_last_success_at_check
    check (last_success_at is null or last_success_at >= created_at),
  constraint push_subscriptions_disabled_at_check
    check (disabled_at is null or disabled_at >= created_at),
  constraint push_subscriptions_updated_at_check
    check (updated_at >= created_at)
);

comment on table public.push_subscriptions is
  'Private user-owned browser PushSubscription material. Clients manage rows only through authenticated SECURITY DEFINER RPCs.';
comment on column public.push_subscriptions.installation_id is
  'Client-generated installation identifier scoped to the authenticated user by server-side reconciliation.';
comment on column public.push_subscriptions.binding_token is
  'Server-generated opaque binding identifier returned only by registration, not by status reads.';
comment on column public.push_subscriptions.endpoint_hash is
  'Lowercase hexadecimal SHA-256 of endpoint, calculated by the registration RPC with extensions.digest.';

create unique index push_subscriptions_active_endpoint_hash_key
  on public.push_subscriptions (endpoint_hash)
  where disabled_at is null;

create unique index push_subscriptions_active_user_installation_key
  on public.push_subscriptions (user_id, installation_id)
  where disabled_at is null;

create index push_subscriptions_user_created_idx
  on public.push_subscriptions (user_id, created_at desc, id desc);

create table public.notification_events (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null,
  inquiry_id uuid not null,
  class_id uuid not null,
  recipient_user_id uuid not null,
  actor_user_id uuid,
  notification_type text not null,
  audience text not null,
  read_at timestamptz,
  dispatch_status text not null default 'pending',
  dispatch_attempt_count integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  claim_token uuid,
  lease_expires_at timestamptz,
  expanded_at timestamptz,
  completed_at timestamptz,
  expires_at timestamptz not null,
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_events_message_id_fkey
    foreign key (message_id)
    references public.class_inquiry_messages (id)
    on delete restrict,
  constraint notification_events_inquiry_id_fkey
    foreign key (inquiry_id)
    references public.class_inquiries (id)
    on delete restrict,
  constraint notification_events_class_id_fkey
    foreign key (class_id)
    references public.classes (id)
    on delete restrict,
  constraint notification_events_recipient_user_id_fkey
    foreign key (recipient_user_id)
    references auth.users (id)
    on delete cascade,
  constraint notification_events_actor_user_id_fkey
    foreign key (actor_user_id)
    references auth.users (id)
    on delete set null,
  constraint notification_events_message_recipient_type_key
    unique (message_id, recipient_user_id, notification_type),
  constraint notification_events_notification_type_check
    check (
      notification_type in (
        'inquiry_staff_reply',
        'inquiry_parent_message'
      )
    ),
  constraint notification_events_audience_check
    check (audience in ('parent', 'staff')),
  constraint notification_events_type_audience_check
    check (
      (notification_type = 'inquiry_staff_reply' and audience = 'parent')
      or
      (notification_type = 'inquiry_parent_message' and audience = 'staff')
    ),
  constraint notification_events_dispatch_status_check
    check (
      dispatch_status in (
        'pending',
        'processing',
        'expanded',
        'no_subscription',
        'complete',
        'partial',
        'cancelled',
        'dead'
      )
    ),
  constraint notification_events_dispatch_attempt_count_check
    check (dispatch_attempt_count >= 0),
  constraint notification_events_claim_state_check
    check (
      (
        dispatch_status = 'processing'
        and claim_token is not null
        and lease_expires_at is not null
      )
      or
      (
        dispatch_status <> 'processing'
        and claim_token is null
        and lease_expires_at is null
      )
    ),
  constraint notification_events_completed_state_check
    check (
      (
        dispatch_status in (
          'no_subscription',
          'complete',
          'partial',
          'cancelled',
          'dead'
        )
        and completed_at is not null
      )
      or
      (
        dispatch_status not in (
          'no_subscription',
          'complete',
          'partial',
          'cancelled',
          'dead'
        )
        and completed_at is null
      )
    ),
  constraint notification_events_expanded_state_check
    check (
      dispatch_status not in (
        'expanded',
        'no_subscription',
        'complete',
        'partial'
      )
      or expanded_at is not null
    ),
  constraint notification_events_last_error_code_check
    check (
      last_error_code is null
      or (
        char_length(last_error_code) between 1 and 100
        and last_error_code ~ '^[a-z0-9_]+$'
      )
    ),
  constraint notification_events_expires_at_check
    check (expires_at > created_at),
  constraint notification_events_read_at_check
    check (read_at is null or read_at >= created_at),
  constraint notification_events_expanded_at_check
    check (expanded_at is null or expanded_at >= created_at),
  constraint notification_events_completed_at_check
    check (completed_at is null or completed_at >= created_at),
  constraint notification_events_updated_at_check
    check (updated_at >= created_at)
);

comment on table public.notification_events is
  'One logical notification per inquiry message, recipient, and notification type. It persists even when no active PushSubscription exists.';
comment on column public.notification_events.dispatch_status is
  'Outbox expansion and aggregate delivery state; Push delivery success is independent from read_at.';

create index notification_events_pending_claim_idx
  on public.notification_events (next_attempt_at, created_at, id)
  where dispatch_status = 'pending';

create index notification_events_processing_lease_idx
  on public.notification_events (lease_expires_at, id)
  where dispatch_status = 'processing';

create index notification_events_recipient_unread_idx
  on public.notification_events (recipient_user_id, created_at desc, id desc)
  where read_at is null;

create index notification_events_expires_at_idx
  on public.notification_events (expires_at, id)
  where dispatch_status in ('pending', 'processing', 'expanded');

create table public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null,
  subscription_id uuid not null,
  status text not null default 'pending',
  attempt_count integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  claim_token uuid,
  lease_expires_at timestamptz,
  last_attempt_at timestamptz,
  sent_at timestamptz,
  http_status integer,
  last_error_code text,
  last_error_detail text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_deliveries_event_id_fkey
    foreign key (event_id)
    references public.notification_events (id)
    on delete cascade,
  constraint notification_deliveries_subscription_id_fkey
    foreign key (subscription_id)
    references public.push_subscriptions (id)
    on delete cascade,
  constraint notification_deliveries_event_subscription_key
    unique (event_id, subscription_id),
  constraint notification_deliveries_status_check
    check (
      status in (
        'pending',
        'processing',
        'retry',
        'sent',
        'permanent_failed',
        'skipped'
      )
    ),
  constraint notification_deliveries_attempt_count_check
    check (attempt_count >= 0),
  constraint notification_deliveries_claim_state_check
    check (
      (
        status = 'processing'
        and claim_token is not null
        and lease_expires_at is not null
      )
      or
      (
        status <> 'processing'
        and claim_token is null
        and lease_expires_at is null
      )
    ),
  constraint notification_deliveries_sent_state_check
    check (
      (status = 'sent' and sent_at is not null)
      or (status <> 'sent' and sent_at is null)
    ),
  constraint notification_deliveries_http_status_check
    check (http_status is null or http_status between 100 and 599),
  constraint notification_deliveries_last_error_code_check
    check (
      last_error_code is null
      or (
        char_length(last_error_code) between 1 and 100
        and last_error_code ~ '^[a-z0-9_]+$'
      )
    ),
  constraint notification_deliveries_last_error_detail_check
    check (
      last_error_detail is null
      or char_length(last_error_detail) between 1 and 2000
    ),
  constraint notification_deliveries_last_attempt_at_check
    check (last_attempt_at is null or last_attempt_at >= created_at),
  constraint notification_deliveries_sent_at_check
    check (sent_at is null or sent_at >= created_at),
  constraint notification_deliveries_updated_at_check
    check (updated_at >= created_at)
);

comment on table public.notification_deliveries is
  'Server-only per-PushSubscription delivery work derived from a logical notification event.';

create index notification_deliveries_pending_claim_idx
  on public.notification_deliveries (next_attempt_at, created_at, id)
  where status in ('pending', 'retry');

create index notification_deliveries_processing_lease_idx
  on public.notification_deliveries (lease_expires_at, id)
  where status = 'processing';

create index notification_deliveries_event_status_idx
  on public.notification_deliveries (event_id, status, id);

create trigger push_subscriptions_set_updated_at
  before update on public.push_subscriptions
  for each row
  execute function public.set_updated_at();

create trigger notification_events_set_updated_at
  before update on public.notification_events
  for each row
  execute function public.set_updated_at();

create trigger notification_deliveries_set_updated_at
  before update on public.notification_deliveries
  for each row
  execute function public.set_updated_at();

alter table public.push_subscriptions enable row level security;
alter table public.notification_events enable row level security;
alter table public.notification_deliveries enable row level security;

revoke all privileges on table public.push_subscriptions
  from public, anon, authenticated, service_role;
revoke all privileges on table public.notification_events
  from public, anon, authenticated, service_role;
revoke all privileges on table public.notification_deliveries
  from public, anon, authenticated, service_role;

create function public.register_my_push_subscription(
  p_installation_id uuid,
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_expiration_at timestamptz default null,
  p_vapid_key_version smallint default 1,
  p_browser_family text default null,
  p_platform_family text default null
)
returns table (
  subscription_id uuid,
  binding_token uuid,
  enabled boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
  v_endpoint text := btrim(p_endpoint);
  v_endpoint_hash text;
  v_p256dh text := btrim(p_p256dh);
  v_auth text := btrim(p_auth);
  v_browser_family text := nullif(btrim(p_browser_family), '');
  v_platform_family text := nullif(btrim(p_platform_family), '');
  v_endpoint_subscription public.push_subscriptions%rowtype;
  v_installation_subscription public.push_subscriptions%rowtype;
  v_locked_subscription public.push_subscriptions%rowtype;
  v_endpoint_lock bigint;
  v_installation_lock bigint;
  v_subscription_id uuid;
  v_binding_token uuid;
begin
  if v_user_id is null then
    raise exception using message = 'not_authenticated';
  end if;

  if p_vapid_key_version is distinct from 1::smallint then
    raise exception using message = 'unsupported_vapid_key_version';
  end if;

  if p_installation_id is null
     or v_endpoint is null
     or char_length(v_endpoint) not between 9 and 4096
     or left(v_endpoint, 8) <> 'https://'
     or v_p256dh is null
     or char_length(v_p256dh) not between 1 and 512
     or v_auth is null
     or char_length(v_auth) not between 1 and 256
     or (p_expiration_at is not null and p_expiration_at <= v_now)
     or (v_browser_family is not null and char_length(v_browser_family) > 100)
     or (v_platform_family is not null and char_length(v_platform_family) > 100) then
    raise exception using message = 'invalid_push_subscription';
  end if;

  v_endpoint_hash := encode(
    extensions.digest(v_endpoint, 'sha256'),
    'hex'
  );

  v_endpoint_lock := pg_catalog.hashtextextended(
    'push_endpoint:' || v_endpoint_hash,
    0
  );
  v_installation_lock := pg_catalog.hashtextextended(
    'push_installation:' || v_user_id::text || ':' || p_installation_id::text,
    0
  );

  perform pg_catalog.pg_advisory_xact_lock(
    least(v_endpoint_lock, v_installation_lock)
  );
  if v_endpoint_lock is distinct from v_installation_lock then
    perform pg_catalog.pg_advisory_xact_lock(
      greatest(v_endpoint_lock, v_installation_lock)
    );
  end if;

  -- Lock both possible active rows in primary-key order. This avoids a
  -- cross-installation endpoint swap taking the same row locks in reverse.
  for v_locked_subscription in
    select ps.*
    from public.push_subscriptions as ps
    where ps.disabled_at is null
      and (
        ps.endpoint_hash = v_endpoint_hash
        or (
          ps.user_id = v_user_id
          and ps.installation_id = p_installation_id
        )
      )
    order by ps.id
    for update of ps
  loop
    if v_locked_subscription.endpoint_hash = v_endpoint_hash then
      v_endpoint_subscription := v_locked_subscription;
    end if;

    if v_locked_subscription.user_id = v_user_id
       and v_locked_subscription.installation_id = p_installation_id then
      v_installation_subscription := v_locked_subscription;
    end if;
  end loop;

  if v_endpoint_subscription.id is not null
     and v_endpoint_subscription.endpoint is distinct from v_endpoint then
    raise exception using message = 'push_endpoint_hash_collision';
  end if;

  if v_endpoint_subscription.id is not null
     and v_endpoint_subscription.user_id is distinct from v_user_id then
    raise exception using message = 'push_endpoint_owned_by_another_user';
  end if;

  if v_endpoint_subscription.id is not null then
    if v_installation_subscription.id is not null
       and v_installation_subscription.id is distinct from v_endpoint_subscription.id then
      update public.push_subscriptions as ps
      set disabled_at = v_now,
          disabled_reason = 'endpoint_replaced'
      where ps.id = v_installation_subscription.id
        and ps.disabled_at is null;
    end if;

    update public.push_subscriptions as ps
    set installation_id = p_installation_id,
        endpoint = v_endpoint,
        p256dh = v_p256dh,
        auth = v_auth,
        expiration_at = p_expiration_at,
        vapid_key_version = p_vapid_key_version,
        browser_family = v_browser_family,
        platform_family = v_platform_family,
        last_seen_at = v_now
    where ps.id = v_endpoint_subscription.id
    returning ps.id, ps.binding_token
      into v_subscription_id, v_binding_token;
  else
    if v_installation_subscription.id is not null then
      update public.push_subscriptions as ps
      set disabled_at = v_now,
          disabled_reason = 'endpoint_replaced'
      where ps.id = v_installation_subscription.id
        and ps.disabled_at is null;
    end if;

    insert into public.push_subscriptions as ps (
      user_id,
      installation_id,
      endpoint,
      endpoint_hash,
      p256dh,
      auth,
      expiration_at,
      vapid_key_version,
      browser_family,
      platform_family,
      last_seen_at,
      created_at,
      updated_at
    )
    values (
      v_user_id,
      p_installation_id,
      v_endpoint,
      v_endpoint_hash,
      v_p256dh,
      v_auth,
      p_expiration_at,
      p_vapid_key_version,
      v_browser_family,
      v_platform_family,
      v_now,
      v_now,
      v_now
    )
    returning ps.id, ps.binding_token
      into v_subscription_id, v_binding_token;
  end if;

  subscription_id := v_subscription_id;
  binding_token := v_binding_token;
  enabled := true;
  return next;
end;
$$;

comment on function public.register_my_push_subscription(
  uuid, text, text, text, timestamptz, smallint, text, text
) is
  'Registers or reconciles the authenticated user''s active browser PushSubscription without accepting a user id or exposing key material in the result.';

create function public.disable_my_push_installation(
  p_installation_id uuid,
  p_reason text
)
returns table (
  subscription_id uuid,
  enabled boolean,
  disabled_reason text
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
  v_reason text := lower(btrim(p_reason));
  v_subscription public.push_subscriptions%rowtype;
begin
  if v_user_id is null then
    raise exception using message = 'not_authenticated';
  end if;

  if p_installation_id is null
     or v_reason is null
     or v_reason not in (
       'logout',
       'permission_denied',
       'unsubscribed',
       'user_changed',
       'manual'
     ) then
    raise exception using message = 'invalid_disable_reason';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'push_installation:' || v_user_id::text || ':' || p_installation_id::text,
      0
    )
  );

  select ps.*
    into v_subscription
  from public.push_subscriptions as ps
  where ps.user_id = v_user_id
    and ps.installation_id = p_installation_id
    and ps.disabled_at is null
  for update of ps;

  if v_subscription.id is not null then
    update public.push_subscriptions as ps
    set disabled_at = v_now,
        disabled_reason = v_reason
    where ps.id = v_subscription.id
    returning ps.* into v_subscription;
  else
    select ps.*
      into v_subscription
    from public.push_subscriptions as ps
    where ps.user_id = v_user_id
      and ps.installation_id = p_installation_id
    order by ps.created_at desc, ps.id desc
    limit 1;
  end if;

  subscription_id := v_subscription.id;
  enabled := false;
  disabled_reason := v_subscription.disabled_reason;
  return next;
end;
$$;

comment on function public.disable_my_push_installation(uuid, text) is
  'Idempotently disables only the authenticated user''s installation using a client-allowed reason.';

create function public.get_my_push_subscription_status(
  p_installation_id uuid
)
returns table (
  enabled boolean,
  subscription_id uuid,
  vapid_key_version smallint,
  last_seen_at timestamptz,
  disabled_reason text
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
  v_subscription public.push_subscriptions%rowtype;
begin
  if v_user_id is null then
    raise exception using message = 'not_authenticated';
  end if;

  if p_installation_id is null then
    raise exception using message = 'invalid_input';
  end if;

  update public.push_subscriptions as ps
  set disabled_at = v_now,
      disabled_reason = 'expired'
  where ps.user_id = v_user_id
    and ps.installation_id = p_installation_id
    and ps.disabled_at is null
    and ps.expiration_at is not null
    and ps.expiration_at <= v_now;

  select ps.*
    into v_subscription
  from public.push_subscriptions as ps
  where ps.user_id = v_user_id
    and ps.installation_id = p_installation_id
  order by (ps.disabled_at is null) desc, ps.created_at desc, ps.id desc
  limit 1;

  enabled := coalesce(v_subscription.disabled_at is null and v_subscription.id is not null, false);
  subscription_id := v_subscription.id;
  vapid_key_version := v_subscription.vapid_key_version;
  last_seen_at := v_subscription.last_seen_at;
  disabled_reason := v_subscription.disabled_reason;
  return next;
end;
$$;

comment on function public.get_my_push_subscription_status(uuid) is
  'Returns minimal non-secret status for the authenticated user''s installation without endpoint, key, auth, or binding token material.';

revoke all on function public.register_my_push_subscription(
  uuid, text, text, text, timestamptz, smallint, text, text
) from public, anon, service_role;
grant execute on function public.register_my_push_subscription(
  uuid, text, text, text, timestamptz, smallint, text, text
) to authenticated;

revoke all on function public.disable_my_push_installation(uuid, text)
  from public, anon, service_role;
grant execute on function public.disable_my_push_installation(uuid, text)
  to authenticated;

revoke all on function public.get_my_push_subscription_status(uuid)
  from public, anon, service_role;
grant execute on function public.get_my_push_subscription_status(uuid)
  to authenticated;

create function public.refresh_notification_event_dispatch_state(
  p_event_id uuid
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_now timestamptz := now();
  v_event public.notification_events%rowtype;
  v_total integer;
  v_open integer;
  v_sent integer;
  v_skipped integer;
  v_status text;
begin
  select ne.*
    into v_event
  from public.notification_events as ne
  where ne.id = p_event_id
  for update of ne;

  if v_event.id is null then
    return null;
  end if;

  if v_event.dispatch_status in (
    'pending',
    'processing',
    'no_subscription',
    'cancelled'
  ) then
    return v_event.dispatch_status;
  end if;

  select
    count(*)::integer,
    count(*) filter (
      where nd.status in ('pending', 'processing', 'retry')
    )::integer,
    count(*) filter (where nd.status = 'sent')::integer,
    count(*) filter (where nd.status = 'skipped')::integer
  into v_total, v_open, v_sent, v_skipped
  from public.notification_deliveries as nd
  where nd.event_id = p_event_id;

  if v_total = 0 then
    v_status := 'no_subscription';
  elsif v_open > 0 then
    v_status := 'expanded';
  elsif v_sent = v_total then
    v_status := 'complete';
  elsif v_sent > 0 then
    v_status := 'partial';
  elsif v_skipped = v_total then
    v_status := 'cancelled';
  else
    v_status := 'dead';
  end if;

  update public.notification_events as ne
  set dispatch_status = v_status,
      claim_token = null,
      lease_expires_at = null,
      expanded_at = case
        when v_status in ('expanded', 'no_subscription', 'complete', 'partial')
          then coalesce(ne.expanded_at, v_now)
        else ne.expanded_at
      end,
      completed_at = case
        when v_status in (
          'no_subscription',
          'complete',
          'partial',
          'cancelled',
          'dead'
        ) then coalesce(ne.completed_at, v_now)
        else null
      end,
      last_error_code = case
        when v_status = 'partial' then 'partial_delivery_failure'
        when v_status = 'dead' then 'all_deliveries_failed'
        else null
      end
  where ne.id = p_event_id;

  return v_status;
end;
$$;

comment on function public.refresh_notification_event_dispatch_state(uuid) is
  'Internal aggregate-state helper. It is callable only by SECURITY DEFINER notification worker functions.';

revoke all on function public.refresh_notification_event_dispatch_state(uuid)
  from public, anon, authenticated, service_role;

create function public.claim_notification_events(
  p_limit integer default 50,
  p_lease_seconds integer default 60
)
returns table (
  event_id uuid,
  claim_token uuid,
  message_id uuid,
  inquiry_id uuid,
  class_id uuid,
  recipient_user_id uuid,
  actor_user_id uuid,
  notification_type text,
  audience text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_now timestamptz := now();
begin
  if p_limit is null or p_limit not between 1 and 100
     or p_lease_seconds is null or p_lease_seconds not between 15 and 300 then
    raise exception using message = 'invalid_claim_options';
  end if;

  update public.notification_events as ne
  set dispatch_status = 'cancelled',
      claim_token = null,
      lease_expires_at = null,
      completed_at = coalesce(ne.completed_at, v_now),
      last_error_code = 'event_expired'
  where ne.dispatch_status in ('pending', 'processing')
    and ne.expires_at <= v_now;

  update public.notification_events as ne
  set dispatch_status = 'dead',
      claim_token = null,
      lease_expires_at = null,
      completed_at = coalesce(ne.completed_at, v_now),
      last_error_code = 'event_claim_exhausted'
  where ne.dispatch_status = 'processing'
    and ne.lease_expires_at <= v_now
    and ne.dispatch_attempt_count >= 5;

  return query
  with candidates as (
    select ne.id
    from public.notification_events as ne
    where ne.expires_at > v_now
      and ne.dispatch_attempt_count < 5
      and (
        (
          ne.dispatch_status = 'pending'
          and ne.next_attempt_at <= v_now
        )
        or
        (
          ne.dispatch_status = 'processing'
          and ne.lease_expires_at <= v_now
        )
      )
    order by ne.next_attempt_at, ne.created_at, ne.id
    limit p_limit
    for update of ne skip locked
  ),
  claimed as (
    update public.notification_events as ne
    set dispatch_status = 'processing',
        dispatch_attempt_count = ne.dispatch_attempt_count + 1,
        claim_token = gen_random_uuid(),
        lease_expires_at = v_now + make_interval(secs => p_lease_seconds),
        last_error_code = null
    from candidates as c
    where ne.id = c.id
    returning ne.*
  )
  select
    c.id,
    c.claim_token,
    c.message_id,
    c.inquiry_id,
    c.class_id,
    c.recipient_user_id,
    c.actor_user_id,
    c.notification_type,
    c.audience,
    c.expires_at
  from claimed as c
  order by c.next_attempt_at, c.created_at, c.id;
end;
$$;

comment on function public.claim_notification_events(integer, integer) is
  'Claims pending or expired-lease logical notification events without holding row locks during worker processing.';

create function public.expand_notification_event_deliveries(
  p_event_id uuid,
  p_claim_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_now timestamptz := now();
  v_event public.notification_events%rowtype;
  v_message_inquiry_id uuid;
  v_message_sender_id uuid;
  v_message_sender_role text;
  v_message_type text;
  v_inquiry_class_id uuid;
  v_inquiry_author_id uuid;
  v_class_center_id uuid;
  v_teacher_id uuid;
  v_owner_id uuid;
  v_current_recipient_id uuid;
  v_cancel_reason text;
  v_delivery_count integer;
  v_status text;
begin
  if p_event_id is null or p_claim_token is null then
    raise exception using message = 'invalid_event_claim';
  end if;

  select ne.*
    into v_event
  from public.notification_events as ne
  where ne.id = p_event_id
  for update of ne;

  if v_event.id is null then
    raise exception using message = 'notification_event_not_found';
  end if;

  if v_event.dispatch_status <> 'processing'
     or v_event.claim_token is distinct from p_claim_token
     or v_event.lease_expires_at is null
     or v_event.lease_expires_at <= v_now then
    raise exception using message = 'notification_event_claim_not_active';
  end if;

  if v_event.expires_at <= v_now then
    update public.notification_events as ne
    set dispatch_status = 'cancelled',
        claim_token = null,
        lease_expires_at = null,
        completed_at = v_now,
        last_error_code = 'event_expired'
    where ne.id = v_event.id;

    return jsonb_build_object(
      'event_id', v_event.id,
      'delivery_count', 0,
      'dispatch_status', 'cancelled'
    );
  end if;

  select
    cim.inquiry_id,
    cim.sender_id,
    cim.sender_role,
    cim.message_type,
    ci.class_id,
    ci.author_id,
    c.center_id,
    c.teacher_id,
    ct.owner_id
  into
    v_message_inquiry_id,
    v_message_sender_id,
    v_message_sender_role,
    v_message_type,
    v_inquiry_class_id,
    v_inquiry_author_id,
    v_class_center_id,
    v_teacher_id,
    v_owner_id
  from public.class_inquiry_messages as cim
  join public.class_inquiries as ci
    on ci.id = cim.inquiry_id
  join public.classes as c
    on c.id = ci.class_id
   and c.center_id = ci.center_id
  join public.centers as ct
    on ct.id = c.center_id
  where cim.id = v_event.message_id
    and cim.inquiry_id = v_event.inquiry_id
    and ci.id = v_event.inquiry_id
    and ci.class_id = v_event.class_id
  for share of cim, ci, c, ct;

  if not found
     or v_message_inquiry_id is distinct from v_event.inquiry_id
     or v_inquiry_class_id is distinct from v_event.class_id
     or v_class_center_id is null
     or v_message_type <> 'message'
     or v_message_sender_id is null
     or v_event.actor_user_id is null
     or v_event.actor_user_id is distinct from v_message_sender_id then
    v_cancel_reason := 'recipient_missing';
  elsif v_event.notification_type = 'inquiry_staff_reply' then
    if v_message_sender_role not in ('teacher', 'owner') then
      v_cancel_reason := 'recipient_missing';
    elsif v_inquiry_author_id is null
          or v_event.recipient_user_id is distinct from v_inquiry_author_id
          or v_event.recipient_user_id is not distinct from v_message_sender_id then
      v_cancel_reason := 'recipient_no_longer_current';
    end if;
  elsif v_event.notification_type = 'inquiry_parent_message' then
    if v_message_sender_role <> 'parent'
       or v_message_sender_id is distinct from v_inquiry_author_id then
      v_cancel_reason := 'recipient_missing';
    else
      for v_current_recipient_id in
        select distinct candidate.user_id
        from (
          values (v_teacher_id), (v_owner_id)
        ) as candidate(user_id)
        where candidate.user_id is not null
          and candidate.user_id is distinct from v_message_sender_id
      loop
        insert into public.notification_events (
          message_id,
          inquiry_id,
          class_id,
          recipient_user_id,
          actor_user_id,
          notification_type,
          audience,
          dispatch_status,
          dispatch_attempt_count,
          next_attempt_at,
          expires_at,
          created_at,
          updated_at
        )
        values (
          v_event.message_id,
          v_event.inquiry_id,
          v_event.class_id,
          v_current_recipient_id,
          v_message_sender_id,
          'inquiry_parent_message',
          'staff',
          'pending',
          0,
          v_now,
          v_event.expires_at,
          v_now,
          v_now
        )
        on conflict (message_id, recipient_user_id, notification_type)
          do nothing;
      end loop;

      if (
        v_event.recipient_user_id is distinct from v_teacher_id
        and v_event.recipient_user_id is distinct from v_owner_id
      ) or v_event.recipient_user_id is not distinct from v_message_sender_id then
        v_cancel_reason := 'recipient_no_longer_current';
      end if;
    end if;
  else
    v_cancel_reason := 'recipient_missing';
  end if;

  if v_cancel_reason is not null then
    update public.notification_events as ne
    set dispatch_status = 'cancelled',
        claim_token = null,
        lease_expires_at = null,
        completed_at = v_now,
        last_error_code = v_cancel_reason
    where ne.id = v_event.id;

    return jsonb_build_object(
      'event_id', v_event.id,
      'delivery_count', 0,
      'dispatch_status', 'cancelled',
      'result_code', v_cancel_reason
    );
  end if;

  update public.push_subscriptions as ps
  set disabled_at = v_now,
      disabled_reason = 'expired'
  where ps.user_id = v_event.recipient_user_id
    and ps.disabled_at is null
    and ps.expiration_at is not null
    and ps.expiration_at <= v_now;

  insert into public.notification_deliveries (
    event_id,
    subscription_id,
    status,
    attempt_count,
    next_attempt_at,
    created_at,
    updated_at
  )
  select
    v_event.id,
    ps.id,
    'pending',
    0,
    v_now,
    v_now,
    v_now
  from public.push_subscriptions as ps
  where ps.user_id = v_event.recipient_user_id
    and ps.disabled_at is null
    and (ps.expiration_at is null or ps.expiration_at > v_now)
  on conflict (event_id, subscription_id) do nothing;

  select count(*)::integer
    into v_delivery_count
  from public.notification_deliveries as nd
  where nd.event_id = v_event.id;

  if v_delivery_count = 0 then
    v_status := 'no_subscription';

    update public.notification_events as ne
    set dispatch_status = v_status,
        claim_token = null,
        lease_expires_at = null,
        expanded_at = v_now,
        completed_at = v_now,
        last_error_code = null
    where ne.id = v_event.id;
  else
    v_status := 'expanded';

    update public.notification_events as ne
    set dispatch_status = v_status,
        claim_token = null,
        lease_expires_at = null,
        expanded_at = v_now,
        completed_at = null,
        last_error_code = null
    where ne.id = v_event.id;
  end if;

  return jsonb_build_object(
    'event_id', v_event.id,
    'delivery_count', v_delivery_count,
    'dispatch_status', v_status
  );
end;
$$;

comment on function public.expand_notification_event_deliveries(uuid, uuid) is
  'Validates an event claim and atomically expands it into one delivery per active recipient subscription.';

create function public.claim_notification_deliveries(
  p_limit integer default 100,
  p_lease_seconds integer default 60
)
returns table (
  delivery_id uuid,
  event_id uuid,
  subscription_id uuid,
  claim_token uuid,
  endpoint text,
  p256dh text,
  auth text,
  vapid_key_version smallint,
  message_id uuid,
  inquiry_id uuid,
  class_id uuid,
  notification_type text,
  audience text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_now timestamptz := now();
  v_event_id uuid;
begin
  if p_limit is null or p_limit not between 1 and 200
     or p_lease_seconds is null or p_lease_seconds not between 15 and 300 then
    raise exception using message = 'invalid_claim_options';
  end if;

  update public.push_subscriptions as ps
  set disabled_at = v_now,
      disabled_reason = 'expired'
  where ps.disabled_at is null
    and ps.expiration_at is not null
    and ps.expiration_at <= v_now;

  update public.notification_events as ne
  set dispatch_status = 'cancelled',
      claim_token = null,
      lease_expires_at = null,
      completed_at = coalesce(ne.completed_at, v_now),
      last_error_code = 'event_expired'
  where ne.dispatch_status in ('expanded', 'pending', 'processing')
    and ne.expires_at <= v_now;

  update public.notification_deliveries as nd
  set status = 'skipped',
      claim_token = null,
      lease_expires_at = null,
      last_error_code = 'event_expired',
      last_error_detail = null
  from public.notification_events as ne
  where ne.id = nd.event_id
    and ne.expires_at <= v_now
    and nd.status in ('pending', 'processing', 'retry');

  for v_event_id in
    with changed as (
      update public.notification_deliveries as nd
      set status = 'skipped',
          claim_token = null,
          lease_expires_at = null,
          last_error_code = 'subscription_inactive',
          last_error_detail = null
      from public.push_subscriptions as ps,
           public.notification_events as ne
      where ps.id = nd.subscription_id
        and ne.id = nd.event_id
        and ne.expires_at > v_now
        and ps.disabled_at is not null
        and nd.status in ('pending', 'processing', 'retry')
      returning nd.event_id
    )
    select distinct changed.event_id
    from changed
  loop
    perform public.refresh_notification_event_dispatch_state(v_event_id);
  end loop;

  for v_event_id in
    with changed as (
      update public.notification_deliveries as nd
      set status = 'permanent_failed',
          claim_token = null,
          lease_expires_at = null,
          last_error_code = 'delivery_claim_exhausted',
          last_error_detail = null
      where nd.status = 'processing'
        and nd.lease_expires_at <= v_now
        and nd.attempt_count >= 5
      returning nd.event_id
    )
    select distinct changed.event_id
    from changed
  loop
    perform public.refresh_notification_event_dispatch_state(v_event_id);
  end loop;

  return query
  with candidates as (
    select nd.id
    from public.notification_deliveries as nd
    join public.notification_events as ne on ne.id = nd.event_id
    join public.push_subscriptions as ps on ps.id = nd.subscription_id
    where ne.dispatch_status = 'expanded'
      and ne.expires_at > v_now
      and ps.disabled_at is null
      and (ps.expiration_at is null or ps.expiration_at > v_now)
      and nd.attempt_count < 5
      and (
        (
          nd.status in ('pending', 'retry')
          and nd.next_attempt_at <= v_now
        )
        or
        (
          nd.status = 'processing'
          and nd.lease_expires_at <= v_now
        )
      )
    order by nd.next_attempt_at, nd.created_at, nd.id
    limit p_limit
    for update of nd skip locked
  ),
  claimed as (
    update public.notification_deliveries as nd
    set status = 'processing',
        attempt_count = nd.attempt_count + 1,
        claim_token = gen_random_uuid(),
        lease_expires_at = v_now + make_interval(secs => p_lease_seconds),
        last_attempt_at = v_now,
        last_error_code = null,
        last_error_detail = null
    from candidates as c
    where nd.id = c.id
    returning nd.*
  )
  select
    c.id,
    c.event_id,
    c.subscription_id,
    c.claim_token,
    ps.endpoint,
    ps.p256dh,
    ps.auth,
    ps.vapid_key_version,
    ne.message_id,
    ne.inquiry_id,
    ne.class_id,
    ne.notification_type,
    ne.audience,
    ne.expires_at
  from claimed as c
  join public.push_subscriptions as ps on ps.id = c.subscription_id
  join public.notification_events as ne on ne.id = c.event_id
  order by c.next_attempt_at, c.created_at, c.id;
end;
$$;

comment on function public.claim_notification_deliveries(integer, integer) is
  'Claims per-subscription deliveries and returns PushSubscription secrets plus the required VAPID key version only to the service-role worker.';

create function public.complete_notification_delivery(
  p_delivery_id uuid,
  p_claim_token uuid,
  p_outcome text,
  p_http_status integer default null,
  p_error_code text default null,
  p_error_detail text default null,
  p_disable_subscription_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_now timestamptz := now();
  v_delivery public.notification_deliveries%rowtype;
  v_outcome text := lower(btrim(p_outcome));
  v_error_code text := nullif(lower(btrim(p_error_code)), '');
  v_error_detail text := nullif(btrim(p_error_detail), '');
  v_disable_reason text := nullif(lower(btrim(p_disable_subscription_reason)), '');
  v_final_status text;
  v_event_status text;
  v_next_attempt_at timestamptz;
begin
  if p_delivery_id is null
     or p_claim_token is null
     or v_outcome is null
     or v_outcome not in ('sent', 'retry', 'permanent_failed', 'skipped')
     or (p_http_status is not null and p_http_status not between 100 and 599)
     or (v_error_code is not null and (
       char_length(v_error_code) > 100
       or v_error_code !~ '^[a-z0-9_]+$'
     ))
     or (v_error_detail is not null and char_length(v_error_detail) > 2000)
     or (v_disable_reason is not null and v_disable_reason not in (
       'expired',
       'gone',
       'vapid_rotated',
       'invalid_subscription'
     ))
     or (v_outcome = 'sent' and v_disable_reason is not null) then
    raise exception using message = 'invalid_delivery_result';
  end if;

  select nd.*
    into v_delivery
  from public.notification_deliveries as nd
  where nd.id = p_delivery_id
  for update of nd;

  if v_delivery.id is null then
    return jsonb_build_object(
      'applied', false,
      'result_code', 'delivery_not_found'
    );
  end if;

  if v_delivery.status <> 'processing'
     or v_delivery.claim_token is distinct from p_claim_token
     or v_delivery.lease_expires_at is null
     or v_delivery.lease_expires_at <= v_now then
    return jsonb_build_object(
      'applied', false,
      'result_code', 'stale_claim',
      'delivery_id', v_delivery.id,
      'event_id', v_delivery.event_id,
      'delivery_status', v_delivery.status
    );
  end if;

  if p_http_status in (404, 410) then
    v_final_status := 'permanent_failed';
    v_disable_reason := 'gone';
    v_error_code := coalesce(v_error_code, 'push_endpoint_gone');
  elsif v_disable_reason is not null then
    v_final_status := 'permanent_failed';
    v_error_code := coalesce(v_error_code, 'subscription_disabled');
  elsif v_outcome = 'retry' and v_delivery.attempt_count >= 5 then
    v_final_status := 'permanent_failed';
    v_error_code := coalesce(v_error_code, 'delivery_attempts_exhausted');
  else
    v_final_status := v_outcome;
  end if;

  if v_final_status = 'retry' then
    v_next_attempt_at := v_now + case v_delivery.attempt_count
      when 1 then interval '1 minute'
      when 2 then interval '5 minutes'
      when 3 then interval '15 minutes'
      else interval '1 hour'
    end;
  else
    v_next_attempt_at := v_delivery.next_attempt_at;
  end if;

  if v_final_status = 'sent' then
    v_error_code := null;
    v_error_detail := null;
    v_disable_reason := null;
  end if;

  update public.notification_deliveries as nd
  set status = v_final_status,
      next_attempt_at = v_next_attempt_at,
      claim_token = null,
      lease_expires_at = null,
      sent_at = case when v_final_status = 'sent' then v_now else null end,
      http_status = p_http_status,
      last_error_code = v_error_code,
      last_error_detail = v_error_detail
  where nd.id = v_delivery.id;

  if v_final_status = 'sent' then
    update public.push_subscriptions as ps
    set last_success_at = v_now,
        last_seen_at = greatest(ps.last_seen_at, v_now)
    where ps.id = v_delivery.subscription_id
      and ps.disabled_at is null;
  elsif v_disable_reason is not null then
    update public.push_subscriptions as ps
    set disabled_at = v_now,
        disabled_reason = v_disable_reason
    where ps.id = v_delivery.subscription_id
      and ps.disabled_at is null;
  end if;

  v_event_status := public.refresh_notification_event_dispatch_state(
    v_delivery.event_id
  );

  return jsonb_build_object(
    'applied', true,
    'result_code', 'applied',
    'delivery_id', v_delivery.id,
    'event_id', v_delivery.event_id,
    'delivery_status', v_final_status,
    'event_status', v_event_status,
    'subscription_disabled', v_disable_reason is not null
  );
end;
$$;

comment on function public.complete_notification_delivery(
  uuid, uuid, text, integer, text, text, text
) is
  'Applies a claimed delivery result, schedules bounded retries, disables gone subscriptions, and refreshes aggregate event state.';

revoke all on function public.claim_notification_events(integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_notification_events(integer, integer)
  to service_role;

revoke all on function public.expand_notification_event_deliveries(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.expand_notification_event_deliveries(uuid, uuid)
  to service_role;

revoke all on function public.claim_notification_deliveries(integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_notification_deliveries(integer, integer)
  to service_role;

revoke all on function public.complete_notification_delivery(
  uuid, uuid, text, integer, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.complete_notification_delivery(
  uuid, uuid, text, integer, text, text, text
) to service_role;

create function public.enqueue_class_inquiry_message_notification_events()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_now timestamptz := now();
  v_inquiry_id uuid;
  v_class_id uuid;
  v_author_id uuid;
  v_create_request_key uuid;
  v_teacher_id uuid;
  v_owner_id uuid;
  v_recipient_id uuid;
begin
  if new.message_type <> 'message'
     or new.sender_role = 'system'
     or new.sender_id is null then
    return new;
  end if;

  select
    ci.id,
    ci.class_id,
    ci.author_id,
    ci.create_request_key,
    c.teacher_id,
    ct.owner_id
  into
    v_inquiry_id,
    v_class_id,
    v_author_id,
    v_create_request_key,
    v_teacher_id,
    v_owner_id
  from public.class_inquiries as ci
  join public.classes as c
    on c.id = ci.class_id
   and c.center_id = ci.center_id
  join public.centers as ct
    on ct.id = ci.center_id
  where ci.id = new.inquiry_id;

  if v_inquiry_id is null then
    return new;
  end if;

  if new.sender_role in ('teacher', 'owner') then
    if (
      new.sender_role = 'teacher'
      and new.sender_id is distinct from v_teacher_id
    ) or (
      new.sender_role = 'owner'
      and new.sender_id is distinct from v_owner_id
    ) then
      return new;
    end if;

    if v_author_id is null or v_author_id is not distinct from new.sender_id then
      return new;
    end if;

    insert into public.notification_events (
      message_id,
      inquiry_id,
      class_id,
      recipient_user_id,
      actor_user_id,
      notification_type,
      audience,
      dispatch_status,
      dispatch_attempt_count,
      next_attempt_at,
      expires_at,
      created_at,
      updated_at
    )
    values (
      new.id,
      v_inquiry_id,
      v_class_id,
      v_author_id,
      new.sender_id,
      'inquiry_staff_reply',
      'parent',
      'pending',
      0,
      v_now,
      v_now + interval '24 hours',
      v_now,
      v_now
    )
    on conflict (message_id, recipient_user_id, notification_type)
      do nothing;

    return new;
  end if;

  if new.sender_role = 'parent' then
    if new.sender_id is distinct from v_author_id
       or new.request_key is not distinct from v_create_request_key then
      return new;
    end if;

    for v_recipient_id in
      select distinct candidate.user_id
      from (
        values (v_teacher_id), (v_owner_id)
      ) as candidate(user_id)
      where candidate.user_id is not null
        and candidate.user_id is distinct from new.sender_id
    loop
      insert into public.notification_events (
        message_id,
        inquiry_id,
        class_id,
        recipient_user_id,
        actor_user_id,
        notification_type,
        audience,
        dispatch_status,
        dispatch_attempt_count,
        next_attempt_at,
        expires_at,
        created_at,
        updated_at
      )
      values (
        new.id,
        v_inquiry_id,
        v_class_id,
        v_recipient_id,
        new.sender_id,
        'inquiry_parent_message',
        'staff',
        'pending',
        0,
        v_now,
        v_now + interval '24 hours',
        v_now,
        v_now
      )
      on conflict (message_id, recipient_user_id, notification_type)
        do nothing;
    end loop;
  end if;

  return new;
end;
$$;

comment on function public.enqueue_class_inquiry_message_notification_events() is
  'Prepared but intentionally unattached AFTER INSERT trigger function. It validates sender identity against current inquiry, class, and center relationships before creating 24-hour logical notification events.';

revoke all on function public.enqueue_class_inquiry_message_notification_events()
  from public, anon, authenticated, service_role;

commit;
