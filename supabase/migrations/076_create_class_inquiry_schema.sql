begin;

-- Private one-to-one parent inquiry schema. Read policies and RPC write
-- contracts are intentionally deferred to later migrations.

create table public.class_inquiry_daily_counters (
  center_id uuid not null,
  document_date date not null,
  last_value integer not null default 0,
  updated_at timestamptz not null default now(),
  constraint class_inquiry_daily_counters_pkey
    primary key (center_id, document_date),
  constraint class_inquiry_daily_counters_center_id_fkey
    foreign key (center_id)
    references public.centers (id)
    on delete restrict,
  constraint class_inquiry_daily_counters_last_value_check
    check (last_value >= 0)
);

comment on table public.class_inquiry_daily_counters is
  'Allocates atomic per-center, per-Seoul-calendar-date inquiry document sequences. Direct client access is not allowed.';
comment on column public.class_inquiry_daily_counters.center_id is
  'Center that owns this daily sequence scope.';
comment on column public.class_inquiry_daily_counters.document_date is
  'Document date calculated by a later RPC using the Asia/Seoul time zone.';
comment on column public.class_inquiry_daily_counters.last_value is
  'Last allocated daily sequence value; allocation is implemented by a later RPC.';

create table public.class_inquiries (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null,
  center_id uuid not null,
  author_id uuid,
  create_request_key uuid not null,
  document_date date not null,
  daily_sequence integer not null,
  document_no text not null,
  category text not null,
  subject text not null,
  status text not null default 'received',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  last_parent_message_at timestamptz not null default now(),
  last_staff_message_at timestamptz,
  parent_last_read_at timestamptz not null default now(),
  staff_last_read_at timestamptz,
  answered_at timestamptz,
  closed_at timestamptz,
  closed_by_id uuid,
  closed_by_role text,
  constraint class_inquiries_class_id_fkey
    foreign key (class_id)
    references public.classes (id)
    on delete restrict,
  constraint class_inquiries_center_id_fkey
    foreign key (center_id)
    references public.centers (id)
    on delete restrict,
  constraint class_inquiries_author_id_fkey
    foreign key (author_id)
    references auth.users (id)
    on delete set null,
  constraint class_inquiries_closed_by_id_fkey
    foreign key (closed_by_id)
    references auth.users (id)
    on delete set null,
  constraint class_inquiries_create_request_key_key
    unique (create_request_key),
  constraint class_inquiries_document_no_key
    unique (document_no),
  constraint class_inquiries_center_document_sequence_key
    unique (center_id, document_date, daily_sequence),
  constraint class_inquiries_daily_sequence_check
    check (daily_sequence >= 1),
  constraint class_inquiries_document_no_check
    check (
      document_no = btrim(document_no)
      and char_length(btrim(document_no)) between 1 and 50
    ),
  constraint class_inquiries_category_check
    check (
      category in ('general', 'attendance', 'health', 'schedule', 'supplies', 'other')
    ),
  constraint class_inquiries_subject_check
    check (
      char_length(btrim(subject)) between 1 and 120
    ),
  constraint class_inquiries_status_check
    check (
      status in ('received', 'in_progress', 'answered', 'closed')
    ),
  constraint class_inquiries_closed_by_role_check
    check (
      closed_by_role is null
      or closed_by_role in ('parent', 'teacher', 'owner')
    ),
  constraint class_inquiries_closed_state_consistency_check
    check (
      (
        status = 'closed'
        and closed_at is not null
        and closed_by_role is not null
      )
      or
      (
        status <> 'closed'
        and closed_at is null
        and closed_by_id is null
        and closed_by_role is null
      )
    ),
  constraint class_inquiries_updated_at_check
    check (updated_at >= created_at),
  constraint class_inquiries_last_message_at_check
    check (last_message_at >= created_at),
  constraint class_inquiries_last_parent_message_at_check
    check (last_parent_message_at >= created_at),
  constraint class_inquiries_last_staff_message_at_check
    check (
      last_staff_message_at is null
      or last_staff_message_at >= created_at
    ),
  constraint class_inquiries_parent_last_read_at_check
    check (parent_last_read_at >= created_at),
  constraint class_inquiries_staff_last_read_at_check
    check (
      staff_last_read_at is null
      or staff_last_read_at >= created_at
    ),
  constraint class_inquiries_answered_at_check
    check (
      answered_at is null
      or answered_at >= created_at
    ),
  constraint class_inquiries_closed_at_check
    check (
      closed_at is null
      or closed_at >= created_at
    )
);

comment on table public.class_inquiries is
  'Private one-to-one parent inquiries retained by class across current teacher assignment changes.';
comment on column public.class_inquiries.class_id is
  'Class that owns the inquiry and determines current staff access.';
comment on column public.class_inquiries.center_id is
  'Center copied from the class by a later creation RPC for document-number scope and auditing.';
comment on column public.class_inquiries.author_id is
  'Original parent author. It becomes null if the auth account is deleted while the inquiry is retained.';
comment on column public.class_inquiries.create_request_key is
  'Idempotency key for inquiry creation retries.';
comment on column public.class_inquiries.document_date is
  'Document-number date calculated using the Asia/Seoul time zone.';
comment on column public.class_inquiries.daily_sequence is
  'Per-center, per-document-date daily sequence starting at 1.';
comment on column public.class_inquiries.document_no is
  'Display-only number. Planned format: INQ-{center identifier token}-{YYMMDD}-{four-digit daily sequence}. Never use it for authorization.';
comment on column public.class_inquiries.category is
  'Inquiry category: general, attendance, health, schedule, supplies, or other.';
comment on column public.class_inquiries.status is
  'Workflow state: received, in_progress, answered, or closed.';
comment on column public.class_inquiries.last_message_at is
  'Timestamp used to sort inquiry lists by most recent activity.';
comment on column public.class_inquiries.parent_last_read_at is
  'Last time the parent read this inquiry.';
comment on column public.class_inquiries.staff_last_read_at is
  'Shared last-read time for all current staff with access to this inquiry.';

create table public.class_inquiry_messages (
  id uuid primary key default gen_random_uuid(),
  inquiry_id uuid not null,
  sender_id uuid,
  sender_role text not null,
  message_type text not null default 'message',
  body text not null,
  status_from text,
  status_to text,
  request_key uuid not null,
  created_at timestamptz not null default now(),
  constraint class_inquiry_messages_inquiry_id_fkey
    foreign key (inquiry_id)
    references public.class_inquiries (id)
    on delete restrict,
  constraint class_inquiry_messages_sender_id_fkey
    foreign key (sender_id)
    references auth.users (id)
    on delete set null,
  constraint class_inquiry_messages_request_key_key
    unique (request_key),
  constraint class_inquiry_messages_sender_role_check
    check (
      sender_role in ('parent', 'teacher', 'owner', 'system')
    ),
  constraint class_inquiry_messages_message_type_check
    check (
      message_type in ('message', 'status_change')
    ),
  constraint class_inquiry_messages_body_check
    check (
      char_length(btrim(body)) between 1 and 5000
    ),
  constraint class_inquiry_messages_status_from_check
    check (
      status_from is null
      or status_from in ('received', 'in_progress', 'answered', 'closed')
    ),
  constraint class_inquiry_messages_status_to_check
    check (
      status_to is null
      or status_to in ('received', 'in_progress', 'answered', 'closed')
    ),
  constraint class_inquiry_messages_status_pair_check
    check (
      (status_from is null and status_to is null)
      or (status_from is not null and status_to is not null)
    ),
  constraint class_inquiry_messages_status_transition_check
    check (
      status_from is null
      or status_from <> status_to
    ),
  constraint class_inquiry_messages_status_change_check
    check (
      message_type <> 'status_change'
      or (status_from is not null and status_to is not null)
    )
);

comment on table public.class_inquiry_messages is
  'Append-only messages and status-change records for private class inquiries.';
comment on column public.class_inquiry_messages.sender_id is
  'Original sender account. It becomes null if the auth account is deleted while the message is retained.';
comment on column public.class_inquiry_messages.sender_role is
  'Sender role captured at insertion: parent, teacher, owner, or system.';
comment on column public.class_inquiry_messages.message_type is
  'Record kind: message or status_change.';
comment on column public.class_inquiry_messages.status_from is
  'Optional prior workflow state. General messages may carry a transition when a reply or follow-up changes state.';
comment on column public.class_inquiry_messages.status_to is
  'Optional next workflow state. It is required with status_from for status_change records.';
comment on column public.class_inquiry_messages.request_key is
  'Idempotency key for message and status-change insertion retries.';

create index class_inquiries_author_updated_idx
  on public.class_inquiries (author_id, updated_at desc, id desc);

create index class_inquiries_class_updated_idx
  on public.class_inquiries (class_id, updated_at desc, id desc);

create index class_inquiries_class_status_updated_idx
  on public.class_inquiries (class_id, status, updated_at desc, id desc);

create index class_inquiries_class_unanswered_idx
  on public.class_inquiries (class_id, updated_at desc, id desc)
  where status in ('received', 'in_progress');

create index class_inquiries_class_staff_unread_idx
  on public.class_inquiries (class_id, last_parent_message_at desc, id desc)
  where (
    staff_last_read_at is null
    or staff_last_read_at < last_parent_message_at
  );

create index class_inquiries_author_parent_unread_idx
  on public.class_inquiries (author_id, last_staff_message_at desc, id desc)
  where last_staff_message_at is not null
    and parent_last_read_at < last_staff_message_at;

create index class_inquiry_messages_inquiry_created_idx
  on public.class_inquiry_messages (inquiry_id, created_at asc, id asc);

create or replace function public.reject_class_inquiry_message_mutation()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'class_inquiry_messages_append_only';
end;
$$;

comment on function public.reject_class_inquiry_message_mutation() is
  'Rejects UPDATE and DELETE row mutations against class_inquiry_messages during normal operation. Privileged maintenance may explicitly disable the trigger.';

revoke execute on function public.reject_class_inquiry_message_mutation()
  from public, anon, authenticated, service_role;

create trigger class_inquiry_messages_reject_mutation
  before update or delete
  on public.class_inquiry_messages
  for each row
  execute function public.reject_class_inquiry_message_mutation();

alter table public.class_inquiry_daily_counters enable row level security;
alter table public.class_inquiries enable row level security;
alter table public.class_inquiry_messages enable row level security;

revoke all on table public.class_inquiry_daily_counters from public;
revoke all on table public.class_inquiry_daily_counters from anon;
revoke all on table public.class_inquiry_daily_counters from authenticated;
revoke all on table public.class_inquiry_daily_counters from service_role;

revoke all on table public.class_inquiries from public;
revoke all on table public.class_inquiries from anon;
revoke all on table public.class_inquiries from authenticated;
revoke all on table public.class_inquiries from service_role;

revoke all on table public.class_inquiry_messages from public;
revoke all on table public.class_inquiry_messages from anon;
revoke all on table public.class_inquiry_messages from authenticated;
revoke all on table public.class_inquiry_messages from service_role;

commit;
